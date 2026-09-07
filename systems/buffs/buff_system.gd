class_name BuffSystem
extends RefCounted

const BuffDefinition = preload("res://data/definitions/buff_definition.gd")

const SIDE_ALLY := "ally"
const SIDE_ENEMY := "enemy"
const SCOPE_UNIT := "unit"
const SCOPE_SIDE := "side"
const PERSISTENCE_BATTLE := "battle"

var _state: Dictionary
var _catalog: Dictionary = {}
var _on_event: Callable
var _sequence := 0
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("buff system config must be a Dictionary")
		return
	var state_value: Variant = config.get("state")
	if typeof(state_value) != TYPE_DICTIONARY:
		errors.append("state must be an explicitly injected Dictionary")
	var catalog_value: Variant = config.get("catalog")
	if typeof(catalog_value) != TYPE_DICTIONARY:
		errors.append("catalog must be an explicitly injected Dictionary")
	var event_value: Variant = config.get("on_event")
	if typeof(event_value) != TYPE_CALLABLE or not event_value.is_valid():
		errors.append("on_event must be an explicitly injected valid Callable")
	if not errors.is_empty():
		return

	var catalog_snapshot := {}
	for key: Variant in catalog_value:
		var definition: Variant = catalog_value[key]
		if typeof(key) != TYPE_STRING or String(key).is_empty():
			errors.append("buff catalog keys must be non-empty strings")
			continue
		if not definition is Resource or definition.get_script() != BuffDefinition:
			errors.append("catalog.%s must be an M1 BuffDefinition resource" % key)
			continue
		if definition.id != key:
			errors.append("catalog.%s id must match its catalog key" % key)
			continue
		catalog_snapshot[key] = definition.snapshot()
	if not errors.is_empty():
		return

	_state = state_value
	_catalog = catalog_snapshot
	_on_event = event_value
	_valid = true
	# Web createBuffSystem() starts a new battle by resetting both side holders.
	# This is the only path allowed to initialize/replace a non-canonical side_buffs value.
	_state["side_buffs"] = {SIDE_ALLY: [], SIDE_ENEMY: []}


func is_valid() -> bool:
	return _valid


func validate_unit_holder(unit: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_valid(errors):
		return false
	return _validate_unit_holder_internal(unit, errors)


func validate_side_state(errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_valid(errors):
		return false
	return _validate_side_state_internal(errors)


func definition_for(id: Variant, expected_scope: String = "", errors: Array[String] = []) -> Variant:
	errors.clear()
	var definition: Variant = _definition_for_internal(id, expected_scope, errors)
	return definition.snapshot() if definition != null else null


func apply_unit(
	unit: Variant,
	id: Variant,
	stacks: Variant = 1,
	duration: Variant = null,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if not _require_valid(errors) or not _validate_unit_holder_internal(unit, errors):
		return false
	var definition: Variant = _definition_for_internal(id, SCOPE_UNIT, errors)
	var values := _normalize_apply_values(definition, stacks, duration, errors)
	if definition == null or not errors.is_empty():
		return false
	if not bool(unit.get("alive", true)):
		return false
	var before := _state_amount(_find_in(_list_of(unit), String(id)))
	var next := _transition_apply(
		_list_of(unit), definition, values["stacks"], values["duration"]
	)
	_write_unit(unit, next)
	var after := _state_amount(_find_in(next, String(id)))
	_emit("buff_applied", {
		"buff_id": id,
		"scope": SCOPE_UNIT,
		"side": unit.get("side"),
		"target_id": unit.get("id"),
		"amount": maxi(1, after - before),
		"state": _snapshot_state(_find_in(next, String(id))),
	})
	return true


func apply_side(
	side: Variant,
	id: Variant,
	stacks: Variant = 1,
	duration: Variant = null,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if not _require_valid(errors) or not _assert_side(side, errors):
		return false
	if not _validate_side_state_internal(errors):
		return false
	var definition: Variant = _definition_for_internal(id, SCOPE_SIDE, errors)
	var values := _normalize_apply_values(definition, stacks, duration, errors)
	if definition == null or not errors.is_empty():
		return false
	var side_name := String(side)
	var before := _state_amount(_find_in(_side_list_of(side_name), String(id)))
	var next := _transition_apply(
		_side_list_of(side_name), definition, values["stacks"], values["duration"]
	)
	_write_side(side_name, next)
	var after := _state_amount(_find_in(next, String(id)))
	_emit("side_buff_applied", {
		"buff_id": id,
		"scope": SCOPE_SIDE,
		"side": side_name,
		"target_id": 0,
		"amount": maxi(1, after - before),
		"state": _snapshot_state(_find_in(next, String(id))),
	})
	return true


func clear_unit(unit: Variant, id: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_valid(errors) or not _validate_unit_holder_internal(unit, errors):
		return false
	if _definition_for_internal(id, SCOPE_UNIT, errors) == null:
		return false
	var existing: Variant = _find_in(_list_of(unit), String(id))
	var amount := _state_amount(existing)
	if amount <= 0:
		return false
	_write_unit(unit, _clear_list(_list_of(unit), String(id)))
	_emit("buff_cleared", {
		"buff_id": id, "scope": SCOPE_UNIT, "side": unit.get("side"),
		"target_id": unit.get("id"), "amount": amount, "state": null,
	})
	return true


func clear_side(side: Variant, id: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_valid(errors) or not _assert_side(side, errors):
		return false
	if not _validate_side_state_internal(errors):
		return false
	if _definition_for_internal(id, SCOPE_SIDE, errors) == null:
		return false
	var side_name := String(side)
	var existing: Variant = _find_in(_side_list_of(side_name), String(id))
	var amount := _state_amount(existing)
	if amount <= 0:
		return false
	_write_side(side_name, _clear_list(_side_list_of(side_name), String(id)))
	_emit("side_buff_cleared", {
		"buff_id": id, "scope": SCOPE_SIDE, "side": side_name,
		"target_id": 0, "amount": amount, "state": null,
	})
	return true


func consume_unit(
	unit: Variant,
	id: Variant,
	stacks: Variant = 1,
	errors: Array[String] = [],
) -> int:
	errors.clear()
	if not _require_valid(errors) or not _validate_unit_holder_internal(unit, errors):
		return 0
	if _definition_for_internal(id, SCOPE_UNIT, errors) == null:
		return 0
	var result := _consume(_list_of(unit), String(id), stacks, errors)
	if not errors.is_empty() or result["consumed"] <= 0:
		return 0
	_write_unit(unit, result["list"])
	_emit("buff_consumed", {
		"buff_id": id, "scope": SCOPE_UNIT, "side": unit.get("side"),
		"target_id": unit.get("id"), "amount": result["consumed"],
		"state": _snapshot_state(result["state"]),
	})
	return result["consumed"]


func consume_side(
	side: Variant,
	id: Variant,
	stacks: Variant = 1,
	errors: Array[String] = [],
) -> int:
	errors.clear()
	if not _require_valid(errors) or not _assert_side(side, errors):
		return 0
	if not _validate_side_state_internal(errors):
		return 0
	if _definition_for_internal(id, SCOPE_SIDE, errors) == null:
		return 0
	var side_name := String(side)
	var result := _consume(_side_list_of(side_name), String(id), stacks, errors)
	if not errors.is_empty() or result["consumed"] <= 0:
		return 0
	_write_side(side_name, result["list"])
	_emit("side_buff_consumed", {
		"buff_id": id, "scope": SCOPE_SIDE, "side": side_name,
		"target_id": 0, "amount": result["consumed"],
		"state": _snapshot_state(result["state"]),
	})
	return result["consumed"]


func duplicate_layers(
	unit: Variant,
	id: Variant,
	duration_bonus: Variant = 0,
	errors: Array[String] = [],
) -> int:
	errors.clear()
	if not _require_valid(errors) or not _validate_unit_holder_internal(unit, errors):
		return 0
	var definition: Variant = _definition_for_internal(id, SCOPE_UNIT, errors)
	if definition == null:
		return 0
	if not definition.uses_layer_durations:
		errors.append("%s does not use layer durations" % id)
		return 0
	var bonus := _finite_floor_int(duration_bonus, "duration_bonus", errors)
	if not errors.is_empty():
		return 0
	var existing: Variant = _find_in(_list_of(unit), String(id))
	if existing == null or _state_amount(existing) <= 0:
		return 0
	var source: Array = existing["layer_turns"].duplicate()
	if source.is_empty():
		for _index in range(int(existing["stacks"])):
			source.append(maxi(1, int(definition.default_duration)))
	var grown: Array = []
	for turns: Variant in source:
		grown.append(maxi(1, int(turns) + bonus))
	var layer_turns := grown.duplicate()
	layer_turns.append_array(grown)
	var next_state := _make_state(String(id), layer_turns.size(), layer_turns.max(), layer_turns)
	var next := _clear_list(_list_of(unit), String(id))
	next.append(next_state)
	_write_unit(unit, next)
	_emit("buff_applied", {
		"buff_id": id, "scope": SCOPE_UNIT, "side": unit.get("side"),
		"target_id": unit.get("id"), "amount": grown.size(),
		"state": _snapshot_state(next_state),
	})
	return grown.size()


func decay_layers(
	unit: Variant,
	id: Variant,
	amount: Variant = 1,
	errors: Array[String] = [],
) -> int:
	errors.clear()
	if not _require_valid(errors) or not _validate_unit_holder_internal(unit, errors):
		return 0
	var definition: Variant = _definition_for_internal(id, SCOPE_UNIT, errors)
	if definition == null:
		return 0
	if not definition.uses_layer_durations:
		errors.append("%s does not use layer durations" % id)
		return 0
	var step := _positive_integer(amount, "amount", errors)
	if not errors.is_empty():
		return 0
	var existing: Variant = _find_in(_list_of(unit), String(id))
	if existing == null or existing["layer_turns"].is_empty():
		return 0
	var layer_turns: Array = []
	for turns: Variant in existing["layer_turns"]:
		var remaining := int(turns) - step
		if remaining > 0:
			layer_turns.append(remaining)
	var expired: int = existing["layer_turns"].size() - layer_turns.size()
	var remaining_state: Variant = null
	if not layer_turns.is_empty():
		remaining_state = _make_state(String(id), layer_turns.size(), layer_turns.max(), layer_turns)
	var next := _clear_list(_list_of(unit), String(id))
	if remaining_state != null:
		next.append(remaining_state)
	_write_unit(unit, next)
	if expired > 0:
		_emit("buff_expired", {
			"buff_id": id, "scope": SCOPE_UNIT, "side": unit.get("side"),
			"target_id": unit.get("id"), "amount": expired,
			"state": _snapshot_state(remaining_state),
		})
	return expired


func decay_round(units: Variant = [], errors: Array[String] = []) -> Array[Dictionary]:
	errors.clear()
	if not _require_valid(errors):
		return []
	if typeof(units) != TYPE_ARRAY:
		errors.append("units must be an Array")
		return []
	# Preflight every definition and unit before the first write. A permanent or
	# wrong-scope record therefore cannot leave a partially decayed battle.
	if not _validate_side_state_internal(errors):
		return []
	for unit: Variant in units:
		if not _validate_unit_holder_internal(unit, errors):
			return []

	var expired: Array[Dictionary] = []
	for side in [SIDE_ALLY, SIDE_ENEMY]:
		var result := _decay_list(_side_list_of(side), SCOPE_SIDE, {"side": side, "target_id": 0})
		_write_side(side, result["next"])
		for item: Dictionary in result["expired"]:
			var payload := item.duplicate(true)
			payload["buff_id"] = item["id"]
			payload["state"] = null
			_emit("side_buff_expired", payload)
		expired.append_array(result["expired"])
	for unit: Dictionary in units:
		var result := _decay_list(
			_list_of(unit), SCOPE_UNIT,
			{"side": unit.get("side"), "target_id": unit.get("id")},
		)
		_write_unit(unit, result["next"])
		for item: Dictionary in result["expired"]:
			var payload := item.duplicate(true)
			payload["buff_id"] = item["id"]
			payload["state"] = null
			_emit("buff_expired", payload)
		expired.append_array(result["expired"])
	return expired.duplicate(true)


func reset_unit(unit: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_valid(errors) or not _validate_unit_holder_internal(unit, errors):
		return false
	_write_unit(unit, [])
	return true


func reset_sides(errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_valid(errors):
		return false
	if not _validate_side_state_internal(errors):
		return false
	_write_side(SIDE_ALLY, [])
	_write_side(SIDE_ENEMY, [])
	return true


func get_unit_state(unit: Variant, id: String) -> Variant:
	return get_buff_state(unit, id)


func get_unit_stacks(unit: Variant, id: String) -> int:
	return get_buff_stacks(unit, id)


func get_unit_turns(unit: Variant, id: String) -> int:
	return get_buff_turns(unit, id)


func has_unit(unit: Variant, id: String) -> bool:
	return has_buff(unit, id)


func get_side_state(side: String, id: String) -> Variant:
	return _snapshot_state(_find_in(_side_list_of(side), id))


func get_side_stacks(side: String, id: String) -> int:
	return _buff_stacks(_find_in(_side_list_of(side), id))


func get_side_turns(side: String, id: String) -> int:
	var buff: Variant = _find_in(_side_list_of(side), id)
	return maxi(0, int(buff.get("turns", 0))) if buff != null else 0


func has_side(side: String, id: String) -> bool:
	return _state_amount(_find_in(_side_list_of(side), id)) > 0


static func get_buff_state(holder: Variant, id: String) -> Variant:
	return _snapshot_state(_find_in(_list_of(holder), id))


static func get_buff_stacks(holder: Variant, id: String) -> int:
	return _buff_stacks(_find_in(_list_of(holder), id))


static func get_buff_turns(holder: Variant, id: String) -> int:
	var buff: Variant = _find_in(_list_of(holder), id)
	return maxi(0, int(buff.get("turns", 0))) if buff != null else 0


static func has_buff(holder: Variant, id: String) -> bool:
	return _state_amount(_find_in(_list_of(holder), id)) > 0


func _definition_for_internal(id: Variant, expected_scope: String, errors: Array[String]) -> Variant:
	if typeof(id) != TYPE_STRING or String(id).is_empty():
		errors.append("buff id must be a non-empty string")
		return null
	var definition: Variant = _catalog.get(id)
	if definition == null:
		errors.append("unknown buff id: %s" % id)
		return null
	if definition.persistence != PERSISTENCE_BATTLE:
		errors.append("%s is permanent and cannot be used by the battle Buff system" % id)
		return null
	if not expected_scope.is_empty() and definition.scope != expected_scope:
		errors.append("%s requires %s scope" % [id, definition.scope])
		return null
	return definition


func _normalize_apply_values(
	definition: Variant,
	stacks: Variant,
	duration: Variant,
	errors: Array[String],
) -> Dictionary:
	if definition == null:
		return {}
	var actual_stacks := _positive_integer(stacks, "stacks", errors)
	var actual_duration: int
	if duration == null:
		actual_duration = int(definition.default_duration)
	else:
		actual_duration = _positive_integer(duration, "duration", errors)
	return {"stacks": actual_stacks, "duration": actual_duration}


func _transition_apply(
	list: Array,
	definition: Variant,
	actual_stacks: int,
	actual_duration: int,
) -> Array:
	var current: Variant = _find_in(list, definition.id)
	if current == null:
		current = _make_state(definition.id, 0, 0, [])
	var next_state: Dictionary
	if definition.uses_layer_durations:
		var layer_duration := maxi(1, actual_duration)
		var layer_turns: Array = current["layer_turns"].duplicate()
		for _index in range(actual_stacks):
			layer_turns.append(layer_duration)
		next_state = _make_state(
			definition.id,
			layer_turns.size(),
			layer_turns.max() if not layer_turns.is_empty() else 0,
			layer_turns,
		)
	else:
		var stacks_after: int
		if definition.stackable:
			stacks_after = int(current["stacks"]) + actual_stacks
			if definition.max_stacks > 0:
				stacks_after = mini(int(definition.max_stacks), stacks_after)
		else:
			stacks_after = 1
		var turns: int
		if definition.decays_at_round_end:
			turns = maxi(int(current["turns"]), maxi(1, actual_duration))
		else:
			turns = maxi(int(current["turns"]), maxi(0, actual_duration))
		next_state = _make_state(definition.id, stacks_after, turns, [])
	var next := _clear_list(list, definition.id)
	next.append(next_state)
	return next


func _consume(list: Array, id: String, stacks: Variant, errors: Array[String]) -> Dictionary:
	var requested := _positive_integer(stacks, "stacks", errors)
	if not errors.is_empty():
		return {"list": list, "consumed": 0, "state": null}
	var existing: Variant = _find_in(list, id)
	if existing == null or _state_amount(existing) <= 0:
		return {"list": list, "consumed": 0, "state": existing}
	var available: int = (
		existing["layer_turns"].size()
		if not existing["layer_turns"].is_empty()
		else int(existing["stacks"])
	)
	var consumed := mini(requested, available)
	var next_state: Dictionary
	if not existing["layer_turns"].is_empty():
		var layer_turns: Array = existing["layer_turns"].slice(consumed)
		next_state = _make_state(
			id, layer_turns.size(),
			layer_turns.max() if not layer_turns.is_empty() else 0,
			layer_turns,
		)
	else:
		next_state = _make_state(
			id, int(existing["stacks"]) - consumed,
			int(existing["turns"]), [],
		)
	var keep := _state_amount(next_state) > 0
	var next := _clear_list(list, id)
	if keep:
		next.append(next_state)
	return {"list": next, "consumed": consumed, "state": next_state if keep else null}


func _decay_list(list: Array, scope: String, owner: Dictionary) -> Dictionary:
	var expired: Array[Dictionary] = []
	var next: Array = []
	for buff: Dictionary in list:
		var definition: Variant = _catalog[buff["id"]]
		if not definition.decays_at_round_end:
			next.append(_snapshot_state(buff))
			continue
		var turns := maxi(0, int(buff["turns"]) - 1)
		if turns > 0:
			next.append(_make_state(buff["id"], buff["stacks"], turns, buff["layer_turns"]))
			continue
		expired.append({
			"scope": scope, "id": buff["id"], "side": owner["side"],
			"target_id": owner["target_id"], "amount": maxi(1, _state_amount(buff)),
		})
	return {"next": next, "expired": expired}


func _preflight_list(list: Array, scope: String, errors: Array[String]) -> bool:
	for buff: Variant in list:
		if typeof(buff) != TYPE_DICTIONARY or typeof(buff.get("id")) != TYPE_STRING:
			errors.append("battle buff state entries must be Dictionaries with string ids")
			return false
		if _definition_for_internal(buff["id"], scope, errors) == null:
			return false
	return true


func _write_unit(unit: Dictionary, list: Array) -> void:
	# The unit Dictionary is the one intentional mutable reference in this API.
	unit["buffs"] = _snapshot_list(list)


func _write_side(side: String, list: Array) -> void:
	# The injected battle state is likewise an intentional mutable reference.
	_state["side_buffs"][side] = _snapshot_list(list)


func _emit(type: String, payload: Dictionary) -> void:
	_sequence += 1
	var event_payload: Dictionary = _deep_copy(payload)
	event_payload["sequence"] = _sequence
	_on_event.call(type, event_payload)


func _require_valid(errors: Array[String]) -> bool:
	if _valid:
		return true
	errors.append("buff system config is invalid")
	return false


func _validate_unit_holder_internal(unit: Variant, errors: Array[String]) -> bool:
	if typeof(unit) != TYPE_DICTIONARY:
		errors.append("unit must be an explicitly referenced Dictionary")
		return false
	if not unit.has("id") or not _valid_unit_id(unit["id"]):
		errors.append("unit.id must be a positive integer or non-empty string")
	if not unit.has("side") or unit["side"] not in [SIDE_ALLY, SIDE_ENEMY]:
		errors.append("unit.side must be ally or enemy")
	if not unit.has("alive") or typeof(unit["alive"]) != TYPE_BOOL:
		errors.append("unit.alive must be a boolean")
	if not unit.has("buffs") or typeof(unit["buffs"]) != TYPE_ARRAY:
		errors.append("unit.buffs must be a canonical Array")
		return false
	if not errors.is_empty():
		return false
	return _validate_buff_list(unit["buffs"], SCOPE_UNIT, "unit.buffs", errors)


func _validate_side_state_internal(errors: Array[String]) -> bool:
	if not _state.has("side_buffs") or typeof(_state["side_buffs"]) != TYPE_DICTIONARY:
		errors.append("state.side_buffs must be a canonical Dictionary")
		return false
	var side_buffs: Dictionary = _state["side_buffs"]
	if side_buffs.size() != 2 or not side_buffs.has(SIDE_ALLY) or not side_buffs.has(SIDE_ENEMY):
		errors.append("state.side_buffs must contain exactly ally and enemy")
		return false
	for side in [SIDE_ALLY, SIDE_ENEMY]:
		if typeof(side_buffs[side]) != TYPE_ARRAY:
			errors.append("state.side_buffs.%s must be a canonical Array" % side)
			return false
		if not _validate_buff_list(
			side_buffs[side], SCOPE_SIDE, "state.side_buffs.%s" % side, errors
		):
			return false
	return true


func _validate_buff_list(
	list: Array,
	scope: String,
	path: String,
	errors: Array[String],
) -> bool:
	var seen_ids := {}
	for index in range(list.size()):
		var buff: Variant = list[index]
		var entry_path := "%s[%d]" % [path, index]
		if typeof(buff) != TYPE_DICTIONARY:
			errors.append("%s must be a canonical Dictionary" % entry_path)
			return false
		var expected_keys := ["id", "stacks", "turns", "layer_turns"]
		if buff.size() != expected_keys.size():
			errors.append("%s must contain exactly id stacks turns and layer_turns" % entry_path)
			return false
		for key in expected_keys:
			if not buff.has(key):
				errors.append("%s.%s is required" % [entry_path, key])
				return false
		for key: Variant in buff:
			if typeof(key) != TYPE_STRING or key not in expected_keys:
				errors.append("%s contains an unknown field" % entry_path)
				return false
		if typeof(buff["id"]) != TYPE_STRING or String(buff["id"]).is_empty():
			errors.append("%s.id must be a non-empty string" % entry_path)
			return false
		var id: String = buff["id"]
		if seen_ids.has(id):
			errors.append("%s contains duplicate buff id: %s" % [path, id])
			return false
		seen_ids[id] = true
		var definition: Variant = _definition_for_internal(id, scope, errors)
		if definition == null:
			return false
		if not _is_non_negative_integer(buff["stacks"]):
			errors.append("%s.stacks must be a non-negative integer" % entry_path)
			return false
		if not _is_non_negative_integer(buff["turns"]):
			errors.append("%s.turns must be a non-negative integer" % entry_path)
			return false
		if typeof(buff["layer_turns"]) != TYPE_ARRAY:
			errors.append("%s.layer_turns must be an Array" % entry_path)
			return false
		var layers: Array = buff["layer_turns"]
		if definition.uses_layer_durations:
			if layers.is_empty():
				errors.append("%s.layer_turns must contain active layers" % entry_path)
				return false
			for turns: Variant in layers:
				if not _is_positive_integer(turns):
					errors.append("%s.layer_turns entries must be positive integers" % entry_path)
					return false
			if int(buff["stacks"]) != layers.size() or int(buff["turns"]) != int(layers.max()):
				errors.append("%s stacks turns and layer_turns are inconsistent" % entry_path)
				return false
		else:
			if not layers.is_empty():
				errors.append("%s.layer_turns must be empty for scalar Buffs" % entry_path)
				return false
			if not definition.stackable and int(buff["stacks"]) > 1:
				errors.append("%s.stacks exceeds the non-stackable limit" % entry_path)
				return false
			if definition.max_stacks > 0 and int(buff["stacks"]) > int(definition.max_stacks):
				errors.append("%s.stacks exceeds max_stacks" % entry_path)
				return false
			if definition.decays_at_round_end and int(buff["turns"]) <= 0:
				errors.append("%s.turns must be positive for a round-decaying Buff" % entry_path)
				return false
			if _state_amount(buff) <= 0:
				errors.append("%s must represent an active Buff" % entry_path)
				return false
	return true


static func _valid_unit_id(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value > 0
	return typeof(value) == TYPE_STRING and not String(value).is_empty()


static func _is_non_negative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


static func _is_positive_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value > 0


static func _assert_side(side: Variant, errors: Array[String]) -> bool:
	if side in [SIDE_ALLY, SIDE_ENEMY]:
		return true
	errors.append("side must be ally or enemy")
	return false


static func _positive_integer(value: Variant, field: String, errors: Array[String]) -> int:
	if typeof(value) == TYPE_INT:
		if value <= 0:
			errors.append("%s must be greater than 0" % field)
			return 0
		return value
	if typeof(value) == TYPE_FLOAT:
		if not is_finite(value):
			errors.append("%s must be a finite number" % field)
			return 0
		if value != floorf(value):
			errors.append("%s must be an integer" % field)
			return 0
		if value <= 0.0:
			errors.append("%s must be greater than 0" % field)
			return 0
		return int(value)
	errors.append("%s must be a finite number" % field)
	return 0


static func _finite_floor_int(value: Variant, field: String, errors: Array[String]) -> int:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value):
		return int(floorf(value))
	errors.append("%s must be a finite number" % field)
	return 0


static func _make_state(id: String, stacks: int, turns: int, layer_turns: Array) -> Dictionary:
	var copied_layers: Array = []
	for value: Variant in layer_turns:
		copied_layers.append(maxi(0, int(value)))
	return {
		"id": id,
		"stacks": maxi(0, stacks),
		"turns": maxi(0, turns),
		"layer_turns": copied_layers,
	}


static func _snapshot_state(buff: Variant) -> Variant:
	if buff == null:
		return null
	return _make_state(
		String(buff.get("id", "")), int(buff.get("stacks", 0)),
		int(buff.get("turns", 0)), buff.get("layer_turns", []),
	)


static func _snapshot_list(list: Array) -> Array:
	var result: Array = []
	for buff: Variant in list:
		result.append(_snapshot_state(buff))
	return result


static func _list_of(holder: Variant) -> Array:
	if typeof(holder) != TYPE_DICTIONARY or typeof(holder.get("buffs")) != TYPE_ARRAY:
		return []
	return holder["buffs"]


func _side_list_of(side: String) -> Array:
	var side_buffs: Variant = _state.get("side_buffs")
	if typeof(side_buffs) != TYPE_DICTIONARY or typeof(side_buffs.get(side)) != TYPE_ARRAY:
		return []
	return side_buffs[side]


static func _find_in(list: Array, id: String) -> Variant:
	for buff: Variant in list:
		if typeof(buff) == TYPE_DICTIONARY and buff.get("id") == id:
			return buff
	return null


static func _buff_stacks(buff: Variant) -> int:
	if buff == null:
		return 0
	var layers: Variant = buff.get("layer_turns", [])
	if typeof(layers) == TYPE_ARRAY and not layers.is_empty():
		return layers.size()
	return maxi(0, int(buff.get("stacks", 0)))


static func _state_amount(buff: Variant) -> int:
	if buff == null:
		return 0
	var layer_count := _buff_stacks(buff)
	if layer_count > 0:
		return layer_count
	return 1 if int(buff.get("turns", 0)) > 0 else 0


static func _clear_list(list: Array, id: String) -> Array:
	var result: Array = []
	for buff: Variant in list:
		if typeof(buff) != TYPE_DICTIONARY or buff.get("id") != id:
			result.append(_snapshot_state(buff))
	return result


static func _deep_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var copied_array: Array = []
		for item: Variant in value:
			copied_array.append(_deep_copy(item))
		return copied_array
	if typeof(value) == TYPE_DICTIONARY:
		var copied_dictionary := {}
		for key: Variant in value:
			copied_dictionary[_deep_copy(key)] = _deep_copy(value[key])
		return copied_dictionary
	return value
