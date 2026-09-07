class_name HandRuntime
extends RefCounted

const RngScript = preload("res://core/rng.gd")
const CardDefinitionScript = preload("res://data/definitions/card_definition.gd")
const CardInstanceScript = preload("res://core/card_instance.gd")
const Result = preload("res://core/card_runtime_result.gd")

const HAND_LIMIT := 7
const TURN_BASE_DRAW := 2
const DECK_STREAM_NAME := "deck"
const FORBIDDEN_SOURCE_SKILL_IDS: Array[String] = ["basicDamage"]
const PILE_NAMES: Array[String] = [
	CardDefinitionScript.PILE_DRAW,
	CardDefinitionScript.PILE_HAND,
	CardDefinitionScript.PILE_DISCARD,
	CardDefinitionScript.PILE_EXHAUST,
]
const INSERTION_STRATEGIES: Array[String] = [
	CardDefinitionScript.INSERT_TOP,
	CardDefinitionScript.INSERT_BOTTOM,
	CardDefinitionScript.INSERT_RANDOM,
]

var _deck_rng: DeterministicRng
var _piles: Dictionary = {}
var _instances_by_id: Dictionary = {}
var _successful_play_counts: Dictionary = {}
var _next_instance_sequence := 1
var _queue_busy := false
var _queue_halted := false
var _shuffle_count := 0
var _trace: Array[Dictionary] = []


func _init(deck_rng_or_battle_seed: Variant = 0) -> void:
	if deck_rng_or_battle_seed is RefCounted and deck_rng_or_battle_seed.has_method("next_u32"):
		_deck_rng = deck_rng_or_battle_seed
	else:
		var streams := RngScript.create_named_streams(deck_rng_or_battle_seed, [DECK_STREAM_NAME])
		_deck_rng = streams[DECK_STREAM_NAME]
	_reset_state()


func initialize_deck(definitions: Array, shuffle_initial: bool = true) -> RefCounted:
	var validation_error := _validate_definitions(definitions)
	if not validation_error.is_empty():
		return _failure(Result.INVALID_CARD, validation_error)

	var staged_instances: Array = []
	var staged_lookup := {}
	var sequence := 1
	for definition in definitions:
		var instance := CardInstanceScript.new(_format_instance_id(sequence), definition)
		staged_instances.append(instance)
		staged_lookup[instance.instance_id] = instance
		sequence += 1
	if shuffle_initial:
		staged_instances = _shuffle_instances(staged_instances, false)

	_reset_state()
	_piles[CardDefinitionScript.PILE_DRAW] = staged_instances
	_instances_by_id = staged_lookup
	_next_instance_sequence = sequence
	if shuffle_initial and not staged_instances.is_empty():
		_shuffle_count = 1
	_trace.append({
		"event": "deck_initialized",
		"instance_ids": _pile_ids(CardDefinitionScript.PILE_DRAW),
		"shuffled": shuffle_initial,
	})
	return _success({
		"instance_ids": _pile_ids(CardDefinitionScript.PILE_DRAW),
		"shuffled": shuffle_initial,
	})


func create_card(
	definition: Resource,
	destination: String,
	insertion_strategy: String = CardDefinitionScript.INSERT_TOP,
) -> RefCounted:
	var validation_error := _validate_definitions([definition])
	if not validation_error.is_empty():
		return _failure(Result.INVALID_CARD, validation_error)
	var destination_error := _validate_destination(destination, insertion_strategy)
	if not destination_error.is_empty():
		return _failure(Result.INVALID_PILE, destination_error)
	if destination == CardDefinitionScript.PILE_HAND and _piles[destination].size() >= HAND_LIMIT:
		return _failure(Result.HAND_FULL, "hand limit is %d" % HAND_LIMIT)

	var instance := CardInstanceScript.new(_format_instance_id(_next_instance_sequence), definition)
	_next_instance_sequence += 1
	_instances_by_id[instance.instance_id] = instance
	_insert_instance(_piles[destination], instance, insertion_strategy)
	_trace.append({
		"event": "card_created",
		"instance_id": instance.instance_id,
		"destination": destination,
	})
	return _success({
		"instance_id": instance.instance_id,
		"destination": destination,
	})


func move_card_to_pile(
	instance_id: String,
	destination: String,
	insertion_strategy: String = CardDefinitionScript.INSERT_TOP,
) -> RefCounted:
	var destination_error := _validate_destination(destination, insertion_strategy)
	if not destination_error.is_empty():
		return _failure(Result.INVALID_PILE, destination_error)
	var source := _find_instance_pile(instance_id)
	if source.is_empty():
		return _failure(Result.CARD_NOT_FOUND, "card instance is not in a pile: %s" % instance_id)
	if source == destination:
		return _success({
			"instance_id": instance_id,
			"from_pile": source,
			"to_pile": destination,
			"moved": false,
		})
	if destination == CardDefinitionScript.PILE_HAND and _piles[destination].size() >= HAND_LIMIT:
		return _failure(Result.HAND_FULL, "hand limit is %d" % HAND_LIMIT, {
			"instance_id": instance_id,
			"from_pile": source,
		})

	var source_index := _find_instance_index(_piles[source], instance_id)
	var instance: Variant = _piles[source][source_index]
	_piles[source].remove_at(source_index)
	_insert_instance(_piles[destination], instance, insertion_strategy)
	_trace.append({
		"event": "card_moved",
		"instance_id": instance_id,
		"from_pile": source,
		"to_pile": destination,
	})
	return _success({
		"instance_id": instance_id,
		"from_pile": source,
		"to_pile": destination,
		"moved": true,
	})


func draw_one() -> RefCounted:
	if _piles[CardDefinitionScript.PILE_HAND].size() >= HAND_LIMIT:
		return _failure(Result.HAND_FULL, "hand limit is %d" % HAND_LIMIT)
	var reshuffled := false
	if _piles[CardDefinitionScript.PILE_DRAW].is_empty():
		if _piles[CardDefinitionScript.PILE_DISCARD].is_empty():
			return _failure(Result.DECK_EMPTY, "draw and discard piles are empty")
		_reshuffle_discard_into_draw()
		reshuffled = true

	var draw_pile: Array = _piles[CardDefinitionScript.PILE_DRAW]
	var instance: Variant = draw_pile[draw_pile.size() - 1]
	var moved := move_card_to_pile(
		instance.instance_id,
		CardDefinitionScript.PILE_HAND,
		CardDefinitionScript.INSERT_TOP,
	)
	if not moved.ok:
		return moved
	moved.details["reshuffled"] = reshuffled
	return moved


func draw_cards(count: int) -> RefCounted:
	if count < 0:
		return _failure(Result.INVALID_ARGUMENT, "draw count must be non-negative")
	var outcomes: Array[Dictionary] = []
	var drawn_ids: Array[String] = []
	var first_failure_code := Result.OK
	for _attempt in range(count):
		var outcome := draw_one()
		outcomes.append(outcome.to_dict())
		if outcome.ok:
			drawn_ids.append(outcome.details["instance_id"])
		elif first_failure_code == Result.OK:
			first_failure_code = outcome.code
	var details := {
		"requested": count,
		"attempted": count,
		"drawn_instance_ids": drawn_ids,
		"outcomes": outcomes,
	}
	if first_failure_code != Result.OK:
		return _failure(first_failure_code, "one or more draw attempts failed", details)
	return _success(details)


func draw_for_turn(active_hero_count: int) -> RefCounted:
	if active_hero_count < 0:
		return _failure(Result.INVALID_ARGUMENT, "active hero count must be non-negative")
	return draw_cards(TURN_BASE_DRAW + active_hero_count)


func end_player_turn() -> RefCounted:
	var hand_ids := _pile_ids(CardDefinitionScript.PILE_HAND)
	var moved_ids: Array[String] = []
	for instance_id in hand_ids:
		var instance: Variant = _instances_by_id[instance_id]
		var destination: String = instance.definition.card_end_of_turn_destination
		var moved := move_card_to_pile(instance_id, destination, CardDefinitionScript.INSERT_TOP)
		if not moved.ok:
			return moved
		moved_ids.append(instance_id)
	for instance: Variant in _instances_by_id.values():
		instance.clear_until_turn_cost()
	_trace.append({"event": "player_turn_ended", "moved_instance_ids": moved_ids})
	return _success({"moved_instance_ids": moved_ids})


func set_card_cost_modifiers(instance_id: String, modifiers: Variant) -> RefCounted:
	if _queue_busy:
		return _failure(Result.QUEUE_BUSY, "card costs cannot change while a command is resolving")
	if not _instances_by_id.has(instance_id):
		return _failure(Result.CARD_NOT_FOUND, "unknown card instance: %s" % instance_id)
	var validation_error := _validate_cost_modifiers(modifiers)
	if not validation_error.is_empty():
		return _failure(Result.INVALID_ARGUMENT, validation_error)
	var instance: Variant = _instances_by_id[instance_id]
	instance.set_cost_modifiers(modifiers)
	_trace.append({
		"event": "card_cost_changed",
		"instance_id": instance_id,
		"effective_sp_cost": instance.effective_sp_cost(),
		"cost_modifiers": instance.cost_modifiers(),
	})
	return _success({
		"instance_id": instance_id,
		"effective_sp_cost": instance.effective_sp_cost(),
		"cost_modifiers": instance.cost_modifiers(),
	})


func process_play_command(
	instance_id: String,
	validator: Callable,
	executor: Callable,
	return_to_hand: bool = false,
	post_success: Callable = Callable(),
) -> RefCounted:
	if _queue_halted:
		return _failure(Result.QUEUE_HALTED, "card command queue is halted after a committed failure", {
			"fatal": true,
			"committed_prefix": true,
		})
	if _queue_busy:
		return _failure(Result.QUEUE_BUSY, "another card command is already resolving")
	if not executor.is_valid():
		return _failure(Result.INVALID_ARGUMENT, "card command executor must be callable")
	if _find_instance_pile(instance_id) != CardDefinitionScript.PILE_HAND:
		return _failure(Result.CARD_NOT_FOUND, "card command requires an instance in hand: %s" % instance_id)

	var instance: Variant = _instances_by_id[instance_id]
	var success_limit: int = instance.definition.max_successful_plays_per_combat
	if success_limit > 0 and successful_play_count(instance_id) >= success_limit:
		return _failure(Result.SUCCESS_LIMIT_REACHED, "card instance reached its successful play limit")

	_queue_busy = true
	if validator.is_valid():
		var validation: Variant = validator.call(instance.snapshot())
		if not _callback_succeeded(validation):
			_queue_busy = false
			return _failure(
				Result.VALIDATOR_REJECTED,
				_callback_message(validation, "card validator rejected command"),
				_callback_details(validation),
			)

	var execution: Variant = executor.call(instance.snapshot())
	if not _callback_succeeded(execution):
		var execution_details := _callback_details(execution)
		if _callback_committed(execution):
			_queue_halted = true
			execution_details["fatal"] = true
			execution_details["committed_prefix"] = true
		_queue_busy = false
		return _failure(
			Result.COMMITTED_FAILURE if _queue_halted else Result.EXECUTION_FAILED,
			_callback_message(execution, "card command execution failed"),
			execution_details,
		)

	var destination: String
	if return_to_hand:
		destination = CardDefinitionScript.PILE_HAND
	elif instance.definition.does_card_exhaust():
		destination = CardDefinitionScript.PILE_EXHAUST
	else:
		destination = instance.definition.card_play_destination
	var moved := move_card_to_pile(instance_id, destination, CardDefinitionScript.INSERT_TOP)
	if not moved.ok:
		_queue_busy = false
		return moved
	_successful_play_counts[instance_id] = successful_play_count(instance_id) + 1
	instance.clear_until_played_cost()
	var post_details: Dictionary = {}
	if post_success.is_valid():
		var post_result: Variant = post_success.call(instance.snapshot(), destination)
		post_details = _callback_details(post_result)
		if not _callback_succeeded(post_result):
			_queue_halted = true
			post_details["fatal"] = true
			post_details["committed_prefix"] = true
			post_details["destination"] = destination
			post_details["successful_play_count"] = _successful_play_counts[instance_id]
			_queue_busy = false
			return _failure(
				Result.COMMITTED_FAILURE,
				_callback_message(post_result, "card post-success processing failed"),
				post_details,
			)
	_trace.append({
		"event": "card_command_succeeded",
		"instance_id": instance_id,
		"destination": destination,
		"successful_play_count": _successful_play_counts[instance_id],
	})
	_queue_busy = false
	var details := {
		"instance_id": instance_id,
		"destination": destination,
		"successful_play_count": _successful_play_counts[instance_id],
	}
	for key: Variant in _callback_details(execution):
		details[key] = _callback_details(execution)[key]
	for key: Variant in post_details:
		details[key] = post_details[key]
	return _success(details)


func pile_instance_ids(pile_name: String) -> Array[String]:
	if pile_name not in PILE_NAMES:
		return []
	return _pile_ids(pile_name)


func get_instance_snapshot(instance_id: String) -> RefCounted:
	if not _instances_by_id.has(instance_id):
		return null
	return _instances_by_id[instance_id].snapshot()


func successful_play_count(instance_id: String) -> int:
	return int(_successful_play_counts.get(instance_id, 0))


func total_instance_count() -> int:
	return _instances_by_id.size()


func is_queue_busy() -> bool:
	return _queue_busy


func is_queue_halted() -> bool:
	return _queue_halted


func snapshot() -> Dictionary:
	var piles := {}
	for pile_name in PILE_NAMES:
		piles[pile_name] = _pile_ids(pile_name)
	var counts := {}
	var count_ids := _successful_play_counts.keys()
	count_ids.sort()
	for instance_id in count_ids:
		counts[instance_id] = _successful_play_counts[instance_id]
	return {
		"piles": piles,
		"successful_play_counts": counts,
		"total_instance_count": total_instance_count(),
		"next_instance_sequence": _next_instance_sequence,
		"queue_busy": _queue_busy,
		"queue_halted": _queue_halted,
		"shuffle_count": _shuffle_count,
		"deck_rng_state": _deck_rng.state_snapshot(),
		"trace": _trace.duplicate(true),
	}


func _reset_state() -> void:
	_piles = {}
	for pile_name in PILE_NAMES:
		_piles[pile_name] = []
	_instances_by_id = {}
	_successful_play_counts = {}
	_next_instance_sequence = 1
	_queue_busy = false
	_queue_halted = false
	_shuffle_count = 0
	_trace = []


func _validate_definitions(definitions: Array) -> String:
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != CardDefinitionScript:
			return "deck entries must be CardDefinition resources"
		var definition: Variant = raw_definition
		if definition.id.strip_edges().is_empty() or definition.source_skill_id.strip_edges().is_empty():
			return "card id and source skill id must not be empty"
		if definition.source_skill_id in FORBIDDEN_SOURCE_SKILL_IDS:
			return "deck excludes card source: %s" % definition.source_skill_id
		if definition.card_category not in [
			CardDefinitionScript.CATEGORY_FREE,
			CardDefinitionScript.CATEGORY_EXCLUSIVE,
			CardDefinitionScript.CATEGORY_ULTIMATE,
		]:
			return "invalid card category: %s" % definition.card_category
		if definition.base_sp_cost < 0 or definition.owner_hero_id < 0:
			return "card cost and owner must be non-negative"
		if definition.validator_id.strip_edges().is_empty() or definition.effect_id.strip_edges().is_empty():
			return "card validator and effect references must not be empty"
		if definition.card_play_destination not in PILE_NAMES:
			return "invalid card play destination: %s" % definition.card_play_destination
		if definition.card_end_of_turn_destination not in PILE_NAMES:
			return "invalid card end-of-turn destination: %s" % definition.card_end_of_turn_destination
		if definition.card_shuffle_weighting <= 0.0:
			return "card shuffle weight must be positive"
		if definition.max_successful_plays_per_combat < 0:
			return "card successful play limit must be non-negative"
	return ""


func _validate_destination(destination: String, insertion_strategy: String) -> String:
	if destination not in PILE_NAMES:
		return "unknown card pile: %s" % destination
	if insertion_strategy not in INSERTION_STRATEGIES:
		return "unknown pile insertion strategy: %s" % insertion_strategy
	return ""


func _validate_cost_modifiers(value: Variant) -> String:
	var keys := ["until_played", "until_turn", "until_combat"]
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return "card cost modifiers must have a canonical closed shape"
	for key: String in keys:
		if not value.has(key) or typeof(value[key]) != TYPE_INT:
			return "card cost modifier %s must be an integer" % key
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			return "card cost modifiers contain an unknown field"
	return ""


func _insert_instance(pile: Array, instance: Variant, insertion_strategy: String) -> void:
	match insertion_strategy:
		CardDefinitionScript.INSERT_TOP:
			pile.append(instance)
		CardDefinitionScript.INSERT_BOTTOM:
			pile.push_front(instance)
		CardDefinitionScript.INSERT_RANDOM:
			var index: int = int(_deck_rng.int_range(0, pile.size()))
			pile.insert(index, instance)


func _reshuffle_discard_into_draw() -> void:
	var discard_pile: Array = _piles[CardDefinitionScript.PILE_DISCARD]
	var shuffled := _shuffle_instances(discard_pile, true)
	_piles[CardDefinitionScript.PILE_DRAW] = shuffled
	_piles[CardDefinitionScript.PILE_DISCARD] = []
	_shuffle_count += 1
	_trace.append({
		"event": "discard_reshuffled",
		"instance_ids": _pile_ids(CardDefinitionScript.PILE_DRAW),
		"shuffle_count": _shuffle_count,
	})


func _shuffle_instances(instances: Array, is_reshuffle: bool) -> Array:
	var priority_buckets := {}
	for instance in instances:
		var priority: int = instance.definition.card_reshuffle_priority if is_reshuffle else instance.definition.card_first_shuffle_priority
		if not priority_buckets.has(priority):
			priority_buckets[priority] = []
		priority_buckets[priority].append(instance)

	var priorities := priority_buckets.keys()
	priorities.sort()
	var shuffled: Array = []
	for priority in priorities:
		var weighted: Array = []
		for instance in priority_buckets[priority]:
			var weighting: float = clampf(instance.definition.card_shuffle_weighting, 0.1, 10.0)
			weighted.append({
				"instance": instance,
				"key": pow(_deck_rng.next(), 1.0 / weighting),
			})
		weighted.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			if left["key"] == right["key"]:
				return left["instance"].instance_id < right["instance"].instance_id
			return left["key"] < right["key"]
		)
		for entry in weighted:
			shuffled.append(entry["instance"])
	return shuffled


func _find_instance_pile(instance_id: String) -> String:
	for pile_name in PILE_NAMES:
		if _find_instance_index(_piles[pile_name], instance_id) >= 0:
			return pile_name
	return ""


func _find_instance_index(pile: Array, instance_id: String) -> int:
	for index in range(pile.size()):
		if pile[index].instance_id == instance_id:
			return index
	return -1


func _pile_ids(pile_name: String) -> Array[String]:
	var ids: Array[String] = []
	for instance in _piles[pile_name]:
		ids.append(instance.instance_id)
	return ids


func _format_instance_id(sequence: int) -> String:
	return "card-%08d" % sequence


func _callback_succeeded(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		return value.get("ok", false) == true
	return false


func _callback_message(value: Variant, fallback: String) -> String:
	if typeof(value) == TYPE_DICTIONARY and value.has("message"):
		return str(value["message"])
	return fallback


func _callback_committed(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY and (
		value.get("committed", false) == true
		or value.get("committed_prefix", false) == true
	)


func _callback_details(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var details: Variant = value.get("details", {})
	return details.duplicate(true) if typeof(details) == TYPE_DICTIONARY else {}


func _success(details: Dictionary = {}) -> RefCounted:
	return Result.new(true, Result.OK, "", details)


func _failure(code: String, message: String, details: Dictionary = {}) -> RefCounted:
	return Result.new(false, code, message, details)
