class_name RoguelikeRunLifecycle
extends RefCounted

## Pure M5-03 Run lifecycle. Economy option construction, reward value,
## battle-world startup/settlement, UI and persistence are intentionally absent.

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const MapSystemScript = preload("res://systems/roguelike/map_system.gd")

const INITIAL_HERO_CHOICE_COUNT := 4
const INITIAL_FREE_SKILL_COUNT := 2
const RECRUITMENT_OPTION_COUNT := 4
const PERMANENT_GROWTH_EXCLUSIVE_IDS := ["ascend", "burnEnchant", "fist"]
const BATTLE_NODE_TYPES := ["battle", "elite", "boss"]
const NON_BATTLE_STATUS_BY_TYPE := {"forge": "forge", "shop": "shop", "event": "event"}
const NODE_KEYS := [
	"id", "chapter", "row", "column", "type", "available", "completed", "next_node_ids",
]
const RECRUITMENT_OPTION_KEYS := ["id", "payload_id", "type"]

var _state: Dictionary
var _catalogs: Dictionary
var _players: Dictionary
var _skills: Dictionary
var _roguelike_catalog: Dictionary
var _random: Variant
var _valid := false
var _dependency_error := ""


func _init(
	run_state: Variant = null,
	content_catalog: Variant = null,
	run_random: Variant = null,
	errors: Array[String] = [],
) -> void:
	errors.clear()
	if typeof(run_state) != TYPE_DICTIONARY:
		_dependency_error = "Run lifecycle requires the authoritative Run Dictionary"
	elif typeof(content_catalog) != TYPE_DICTIONARY:
		_dependency_error = "Run lifecycle requires the M1 content catalog"
	elif not _read_catalogs(content_catalog, errors):
		_dependency_error = errors[0] if not errors.is_empty() else "Run lifecycle catalogs are invalid"
	elif (
		typeof(run_random) != TYPE_OBJECT
		or run_random == null
		or not run_random.has_method("with_transaction")
		or not run_random.has_method("pick")
		or not run_random.has_method("shuffle")
	):
		_dependency_error = "Run lifecycle requires TransactionalRunRandom"
	else:
		var state_errors: Array[String] = []
		if not RunContractScript.validate(run_state, state_errors):
			_dependency_error = state_errors[0]
		else:
			_state = run_state
			_catalogs = content_catalog
			_random = run_random
			_valid = true
	if not _dependency_error.is_empty():
		errors.clear()
		errors.append(_dependency_error)


func is_valid() -> bool:
	return _valid


func snapshot(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return {}
	return RunContractScript.snapshot(_state, errors)


func validate(errors: Array[String] = []) -> bool:
	errors.clear()
	return _require_valid(errors) and _validate_state(_state, errors)


func start_run(errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		var choices := _draw_initial_hero_choices(local_errors)
		if choices.size() != INITIAL_HERO_CHOICE_COUNT:
			return false
		_replace(candidate, RunContractScript.create())
		candidate["active"] = true
		candidate["chapter"] = 1
		candidate["currency"] = 30
		candidate["status"] = "heroSelect"
		candidate["initial_hero_choice_ids"] = choices
		return true
	, errors)


func choose_starting_hero(hero_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			typeof(hero_id) != TYPE_INT
			or not candidate["active"]
			or candidate["status"] != "heroSelect"
			or hero_id not in candidate["initial_hero_choice_ids"]
		):
			return false
		var zero_cost_ids: Array = []
		for skill_id: Variant in _skills:
			var skill: Variant = _skills[skill_id]
			if skill.base_sp_cost == 0:
				zero_cost_ids.append(skill_id)
		if zero_cost_ids.size() < INITIAL_FREE_SKILL_COUNT:
			local_errors.append("Run initial loadout requires two distinct zero-SP free skills")
			return false
		var shuffled: Array = _random.shuffle(zero_cost_ids, local_errors)
		if not local_errors.is_empty():
			return false
		var map_nodes := MapSystemScript.build_chapter_map(
			_roguelike_catalog, 1, _random, local_errors
		)
		if not local_errors.is_empty() or map_nodes.size() != 30:
			return false
		candidate["hero_deployment_slots"] = {str(hero_id): 1}
		_sync_roster_views(candidate)
		candidate["free_skill_ids"] = shuffled.slice(0, INITIAL_FREE_SKILL_COUNT)
		candidate["map_nodes"] = map_nodes
		candidate["status"] = "map"
		return true
	, errors)


func quit_run(errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		if not candidate["active"]:
			return false
		_replace(candidate, RunContractScript.create())
		return true
	, errors)


func set_hero_deployment_slot(
	hero_id: Variant,
	slot: Variant,
	errors: Array[String] = [],
) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or typeof(hero_id) != TYPE_INT
			or typeof(slot) != TYPE_INT
			or slot < 1
			or slot > 6
			or not candidate["hero_deployment_slots"].has(str(hero_id))
		):
			return false
		for other_hero_id: Variant in candidate["hero_deployment_slots"]:
			if other_hero_id != str(hero_id) and candidate["hero_deployment_slots"][other_hero_id] == slot:
				return false
		candidate["hero_deployment_slots"][str(hero_id)] = slot
		_sync_roster_views(candidate)
		return true
	, errors)


func deployed_hero_ids(errors: Array[String] = []) -> Array[int]:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return []
	return _sorted_deployment_ids(_state["hero_deployment_slots"])


func add_free_skill_copy(skill_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or typeof(skill_id) != TYPE_STRING
			or skill_id == "basicDamage"
			or not _skills.has(skill_id)
		):
			return false
		candidate["free_skill_ids"].append(skill_id)
		return true
	, errors)


func choose_node(node_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if not candidate["active"] or candidate["status"] != "map" or typeof(node_id) != TYPE_STRING:
			return false
		var node: Dictionary = _node_by_id(candidate["map_nodes"], node_id)
		if node.is_empty() or not node["available"] or node["completed"]:
			return false
		var scales := MapSystemScript.get_node_scales(node, local_errors)
		if not local_errors.is_empty() or scales.is_empty():
			return false
		for other_node: Dictionary in candidate["map_nodes"]:
			other_node["available"] = false
		candidate["current_node_id"] = node_id
		candidate["reward_pending"] = false
		candidate["reward_options"] = []
		candidate["shop_options"] = []
		candidate["forge_uses_this_node"] = 0
		if node["type"] in BATTLE_NODE_TYPES:
			candidate["status"] = "fighting"
			candidate["enemy_hp_scale"] = scales["hp"]
			candidate["enemy_atk_scale"] = scales["atk"]
		elif NON_BATTLE_STATUS_BY_TYPE.has(node["type"]):
			# M5-03 owns only entry/completion state. M5-04 will populate and
			# transact forge/shop/event economy details.
			candidate["status"] = NON_BATTLE_STATUS_BY_TYPE[node["type"]]
			candidate["enemy_hp_scale"] = 1.0
			candidate["enemy_atk_scale"] = 1.0
		else:
			local_errors.append("unsupported roguelike node type: %s" % str(node["type"]))
			return false
		return true
	, errors)


func complete_current_node(errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if not candidate["active"] or candidate["status"] not in NON_BATTLE_STATUS_BY_TYPE.values():
			return false
		var node := _current_node(candidate)
		if node.is_empty() or NON_BATTLE_STATUS_BY_TYPE.get(node["type"]) != candidate["status"]:
			return false
		return _finish_successful_node(candidate, node, local_errors)
	, errors)


func complete_current_battle(won: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if not candidate["active"] or candidate["status"] != "fighting" or typeof(won) != TYPE_BOOL:
			return false
		var node := _current_node(candidate)
		if node.is_empty() or node["type"] not in BATTLE_NODE_TYPES:
			return false
		if not won:
			candidate["status"] = "failed"
			candidate["reward_pending"] = false
			candidate["reward_options"] = []
			return true
		# This records only the lifecycle outcome. M5-05 will call it after a
		# real battle transaction; battle rewards belong to M5-04/M5-05.
		return _finish_successful_node(candidate, node, local_errors)
	, errors)


func recruit_hero(hero_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or candidate["status"] != "reward"
			or not candidate["reward_pending"]
			or typeof(hero_id) != TYPE_INT
			or candidate["hero_deployment_slots"].has(str(hero_id))
		):
			return false
		var option_found := false
		for option: Dictionary in candidate["reward_options"]:
			if option["type"] == "hero" and option["payload_id"] == hero_id:
				option_found = true
				break
		if not option_found:
			return false
		var occupied: Array = candidate["hero_deployment_slots"].values()
		var slot := 0
		for preferred_slot in [4, 5, 6, 1, 2, 3]:
			if preferred_slot not in occupied:
				slot = preferred_slot
				break
		if slot == 0:
			return false
		var node := _current_node(candidate)
		if node.is_empty():
			local_errors.append("recruitment requires the authoritative current node")
			return false
		candidate["hero_deployment_slots"][str(hero_id)] = slot
		_sync_roster_views(candidate)
		candidate["reward_pending"] = false
		candidate["reward_options"] = []
		return _advance_after_node(candidate, node, local_errors)
	, errors)


func _finish_successful_node(
	candidate: Dictionary,
	node: Dictionary,
	errors: Array[String],
) -> bool:
	if _is_recruitment_milestone(node) and _prepare_recruitment(candidate, errors):
		return true
	if not errors.is_empty():
		return false
	return _advance_after_node(candidate, node, errors)


func _prepare_recruitment(candidate: Dictionary, errors: Array[String]) -> bool:
	var owned: Dictionary = candidate["hero_deployment_slots"]
	var candidates: Array = []
	for hero_id: Variant in _players:
		if not owned.has(str(hero_id)) and _players[hero_id].exclusive_skill_id != "fate":
			candidates.append(hero_id)
	var shuffled: Array = _random.shuffle(candidates, errors)
	if not errors.is_empty() or shuffled.is_empty():
		return false
	var options: Array = []
	for hero_id: Variant in shuffled.slice(0, RECRUITMENT_OPTION_COUNT):
		options.append({
			"id": "reward:hero:%d" % hero_id,
			"payload_id": hero_id,
			"type": "hero",
		})
	for node: Dictionary in candidate["map_nodes"]:
		node["available"] = false
	candidate["reward_pending"] = true
	candidate["reward_options"] = options
	candidate["shop_options"] = []
	candidate["status"] = "reward"
	candidate["enemy_hp_scale"] = 1.0
	candidate["enemy_atk_scale"] = 1.0
	candidate["forge_uses_this_node"] = 0
	return true


func _advance_after_node(
	candidate: Dictionary,
	node: Dictionary,
	errors: Array[String],
) -> bool:
	node["completed"] = true
	node["available"] = false
	_clear_node_runtime(candidate)
	if node["type"] == "boss":
		if candidate["chapter"] >= candidate["max_chapters"]:
			candidate["status"] = "cleared"
			return true
		var next_chapter: int = candidate["chapter"] + 1
		var next_map := MapSystemScript.build_chapter_map(
			_roguelike_catalog, next_chapter, _random, errors
		)
		if not errors.is_empty() or next_map.size() != 30:
			return false
		candidate["chapter"] = next_chapter
		candidate["map_nodes"] = next_map
		candidate["status"] = "map"
		return true
	var next_ids: Array = node["next_node_ids"]
	for candidate_node: Dictionary in candidate["map_nodes"]:
		candidate_node["available"] = (
			candidate_node["id"] in next_ids and not candidate_node["completed"]
		)
	candidate["status"] = "map"
	return true


func _clear_node_runtime(candidate: Dictionary) -> void:
	candidate["current_node_id"] = null
	candidate["enemy_hp_scale"] = 1.0
	candidate["enemy_atk_scale"] = 1.0
	candidate["reward_pending"] = false
	candidate["reward_options"] = []
	candidate["shop_options"] = []
	candidate["forge_uses_this_node"] = 0


func _is_recruitment_milestone(node: Dictionary) -> bool:
	return node["chapter"] == 1 and (node["column"] == 2 or node["type"] == "boss")


func _draw_initial_hero_choices(errors: Array[String]) -> Array:
	var candidates: Array = []
	var growth_candidates: Array = []
	for hero_id: Variant in _players:
		var exclusive_id: String = _players[hero_id].exclusive_skill_id
		if exclusive_id == "fate":
			continue
		candidates.append(hero_id)
		if exclusive_id in PERMANENT_GROWTH_EXCLUSIVE_IDS:
			growth_candidates.append(hero_id)
	if candidates.size() < INITIAL_HERO_CHOICE_COUNT or growth_candidates.is_empty():
		errors.append("Run hero catalog cannot provide four choices including permanent growth")
		return []
	var required_growth: Variant = _random.pick(growth_candidates, errors)
	if not errors.is_empty() or required_growth == null:
		return []
	var others := candidates.filter(func(hero_id: Variant) -> bool: return hero_id != required_growth)
	others = _random.shuffle(others, errors)
	if not errors.is_empty():
		return []
	var result: Array = [required_growth]
	result.append_array(others.slice(0, INITIAL_HERO_CHOICE_COUNT - 1))
	return _random.shuffle(result, errors)


func _atomic(command: Callable, errors: Array[String]) -> bool:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return false
	var transition_errors: Array[String] = []
	var random_errors: Array[String] = []
	var result: Variant = _random.with_transaction(func() -> bool:
		return RunContractScript.transition(_state, func(candidate: Dictionary) -> bool:
			var changed: Variant = command.call(candidate, transition_errors)
			if typeof(changed) != TYPE_BOOL or not changed:
				return false
			return _validate_state(candidate, transition_errors)
		, transition_errors)
	, random_errors)
	for message: String in transition_errors:
		if message not in errors:
			errors.append(message)
	for message: String in random_errors:
		if message not in errors:
			errors.append(message)
	return typeof(result) == TYPE_BOOL and result


func _validate_state(state: Dictionary, errors: Array[String]) -> bool:
	var structural_errors: Array[String] = []
	if not RunContractScript.validate(state, structural_errors):
		errors.append_array(structural_errors)
		return false
	if not state["active"]:
		if state != RunContractScript.create():
			errors.append("inactive Run must equal the canonical idle state")
			return false
		return true
	if state["chapter"] < 1:
		errors.append("active Run chapter must be from 1 through 3")
		return false
	if not _validate_initial_choices(state, errors):
		return false
	for raw_hero_id: Variant in state["hero_deployment_slots"]:
		if not _players.has(int(raw_hero_id)):
			errors.append("Run roster references unknown hero %s" % raw_hero_id)
			return false
	for skill_id: Variant in state["free_skill_ids"]:
		if skill_id == "basicDamage" or not _skills.has(skill_id):
			errors.append("Run free-skill multiset references an unavailable player card: %s" % str(skill_id))
			return false
	if state["status"] == "heroSelect":
		if (
			state["chapter"] != 1
			or state["currency"] != 30
			or not state["hero_deployment_slots"].is_empty()
			or not state["free_skill_ids"].is_empty()
			or not state["map_nodes"].is_empty()
			or state["current_node_id"] != null
		):
			errors.append("hero selection must not own roster, cards, map, or current node")
			return false
		return _no_m5_04_options(state, errors)
	if state["hero_deployment_slots"].is_empty():
		errors.append("active post-selection Run requires a deployed roster")
		return false
	if not _owned_includes_initial_choice(state):
		errors.append("Run roster must retain the selected initial hero")
		return false
	if state["free_skill_ids"].size() < INITIAL_FREE_SKILL_COUNT:
		errors.append("active post-selection Run requires its initial free-skill cards")
		return false
	if not _validate_map(state, errors) or not _validate_status(state, errors):
		return false
	return _no_m5_04_options(state, errors)


func _validate_initial_choices(state: Dictionary, errors: Array[String]) -> bool:
	var choices: Array = state["initial_hero_choice_ids"]
	if choices.size() != INITIAL_HERO_CHOICE_COUNT:
		errors.append("active Run requires exactly four initial hero choices")
		return false
	var has_growth := false
	for hero_id: Variant in choices:
		if not _players.has(hero_id) or _players[hero_id].exclusive_skill_id == "fate":
			errors.append("initial hero choices must be known non-fate heroes")
			return false
		has_growth = has_growth or _players[hero_id].exclusive_skill_id in PERMANENT_GROWTH_EXCLUSIVE_IDS
	if not has_growth:
		errors.append("initial hero choices must contain a permanent-growth hero")
		return false
	return true


func _validate_map(state: Dictionary, errors: Array[String]) -> bool:
	if state["map_nodes"].size() != state["map_rows"] * state["map_columns"]:
		errors.append("post-selection Run map must contain exactly 30 nodes")
		return false
	var ids := {}
	var coordinates := {}
	var available_columns := {}
	for raw_node: Variant in state["map_nodes"]:
		if typeof(raw_node) != TYPE_DICTIONARY or raw_node.keys() != NODE_KEYS:
			errors.append("Run map node must keep the canonical M5 map shape")
			return false
		var node: Dictionary = raw_node
		var coordinate := "%d:%d" % [node.get("row", -1), node.get("column", -1)]
		if (
			typeof(node["id"]) != TYPE_STRING
			or node["chapter"] != state["chapter"]
			or typeof(node["row"]) != TYPE_INT
			or node["row"] < 0
			or node["row"] >= state["map_rows"]
			or typeof(node["column"]) != TYPE_INT
			or node["column"] < 0
			or node["column"] >= state["map_columns"]
			or node["type"] not in MapSystemScript.NODE_TYPES
			or typeof(node["available"]) != TYPE_BOOL
			or typeof(node["completed"]) != TYPE_BOOL
			or typeof(node["next_node_ids"]) != TYPE_ARRAY
			or ids.has(node["id"])
			or coordinates.has(coordinate)
			or (node["available"] and node["completed"])
		):
			errors.append("Run map contains an invalid node")
			return false
		ids[node["id"]] = node
		coordinates[coordinate] = true
		if node["id"] != "c%d-r%d-n%d" % [node["chapter"], node["row"], node["column"]]:
			errors.append("Run map node id must match its chapter, row, and column")
			return false
		if node["available"]:
			available_columns[node["column"]] = true
	if available_columns.size() > 1:
		errors.append("Run map frontier must occupy only one column")
		return false
	for node: Dictionary in state["map_nodes"]:
		var expected_successors: Array[String] = []
		if node["column"] < state["map_columns"] - 1:
			for next_row in [node["row"] - 1, node["row"], node["row"] + 1]:
				if next_row >= 0 and next_row < state["map_rows"]:
					expected_successors.append(
						"c%d-r%d-n%d" % [state["chapter"], next_row, node["column"] + 1]
					)
		if node["next_node_ids"] != expected_successors:
			errors.append("Run map successor edges must match adjacent rows in the next column")
			return false
		for next_id: Variant in node["next_node_ids"]:
			if typeof(next_id) != TYPE_STRING or not ids.has(next_id) or ids[next_id]["column"] != node["column"] + 1:
				errors.append("Run map contains an invalid successor edge")
				return false
	return true


func _validate_status(state: Dictionary, errors: Array[String]) -> bool:
	var status: String = state["status"]
	var current := _current_node(state)
	var available_count: int = state["map_nodes"].filter(func(node: Dictionary) -> bool:
		return node["available"]
	).size()
	if status == "map":
		if (
			state["current_node_id"] != null
			or available_count == 0
			or state["enemy_hp_scale"] != 1.0
			or state["enemy_atk_scale"] != 1.0
		):
			errors.append("map status requires a non-empty frontier and no current node")
			return false
		return true
	if status == "cleared":
		if (
			state["chapter"] != 3
			or state["current_node_id"] != null
			or available_count != 0
			or state["enemy_hp_scale"] != 1.0
			or state["enemy_atk_scale"] != 1.0
		):
			errors.append("cleared status requires the completed chapter-three boss")
			return false
		return state["map_nodes"].any(func(node: Dictionary) -> bool:
			return node["type"] == "boss" and node["completed"]
		)
	if current.is_empty() or current["completed"] or available_count != 0:
		errors.append("selected Run status requires one incomplete current node and no frontier")
		return false
	if status == "fighting" or status == "failed":
		if current["type"] not in BATTLE_NODE_TYPES:
			errors.append("battle status requires a battle current node")
			return false
		return true
	if status in NON_BATTLE_STATUS_BY_TYPE.values():
		if NON_BATTLE_STATUS_BY_TYPE.get(current["type"]) != status:
			errors.append("non-battle status must match the current node type")
			return false
		if state["enemy_hp_scale"] != 1.0 or state["enemy_atk_scale"] != 1.0:
			errors.append("non-battle status must keep neutral enemy scales")
			return false
		return true
	if status == "reward":
		if not state["reward_pending"] or not _validate_recruitment_options(state, errors):
			return false
		if state["enemy_hp_scale"] != 1.0 or state["enemy_atk_scale"] != 1.0:
			errors.append("recruitment status must keep neutral enemy scales")
			return false
		return _is_recruitment_milestone(current)
	errors.append("unsupported active Run status for M5-03: %s" % status)
	return false


func _validate_recruitment_options(state: Dictionary, errors: Array[String]) -> bool:
	var options: Array = state["reward_options"]
	if options.is_empty() or options.size() > RECRUITMENT_OPTION_COUNT:
		errors.append("recruitment must publish from one through four hero options")
		return false
	var seen := {}
	for raw_option: Variant in options:
		if typeof(raw_option) != TYPE_DICTIONARY or raw_option.keys() != RECRUITMENT_OPTION_KEYS:
			errors.append("recruitment option must keep the canonical hero option shape")
			return false
		var option: Dictionary = raw_option
		var hero_id: Variant = option["payload_id"]
		if (
			option["type"] != "hero"
			or typeof(hero_id) != TYPE_INT
			or option["id"] != "reward:hero:%d" % hero_id
			or seen.has(hero_id)
			or state["hero_deployment_slots"].has(str(hero_id))
			or not _players.has(hero_id)
			or _players[hero_id].exclusive_skill_id == "fate"
		):
			errors.append("recruitment options must be unique unowned non-fate heroes")
			return false
		seen[hero_id] = true
	return true


func _no_m5_04_options(state: Dictionary, errors: Array[String]) -> bool:
	if not state["shop_options"].is_empty():
		errors.append("M5-03 does not populate shop or forge options")
		return false
	if state["status"] != "reward" and (state["reward_pending"] or not state["reward_options"].is_empty()):
		errors.append("M5-03 reward fields are reserved for recruitment")
		return false
	return true


func _owned_includes_initial_choice(state: Dictionary) -> bool:
	for raw_hero_id: Variant in state["hero_deployment_slots"]:
		if int(raw_hero_id) in state["initial_hero_choice_ids"]:
			return true
	return false


func _sync_roster_views(state: Dictionary) -> void:
	state["front_hero_ids"] = []
	state["back_hero_ids"] = []
	for hero_id: int in _sorted_deployment_ids(state["hero_deployment_slots"]):
		if state["hero_deployment_slots"][str(hero_id)] <= 3:
			state["front_hero_ids"].append(hero_id)
		else:
			state["back_hero_ids"].append(hero_id)


func _sorted_deployment_ids(slots: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for raw_hero_id: Variant in slots:
		ids.append(int(raw_hero_id))
	ids.sort_custom(func(left: int, right: int) -> bool:
		return slots[str(left)] < slots[str(right)]
	)
	return ids


func _current_node(state: Dictionary) -> Dictionary:
	return _node_by_id(state["map_nodes"], state["current_node_id"])


func _node_by_id(nodes: Array, node_id: Variant) -> Dictionary:
	if typeof(node_id) != TYPE_STRING:
		return {}
	for node: Dictionary in nodes:
		if node["id"] == node_id:
			return node
	return {}


func _read_catalogs(content_catalog: Dictionary, errors: Array[String]) -> bool:
	if (
		typeof(content_catalog.get("characters")) != TYPE_DICTIONARY
		or typeof(content_catalog["characters"].get("players")) != TYPE_DICTIONARY
		or typeof(content_catalog.get("skills")) != TYPE_DICTIONARY
		or typeof(content_catalog.get("roguelike_content")) != TYPE_DICTIONARY
	):
		errors.append("Run lifecycle M1 catalog groups are missing")
		return false
	_players = content_catalog["characters"]["players"]
	_skills = content_catalog["skills"]
	_roguelike_catalog = content_catalog["roguelike_content"]
	return true


func _require_valid(errors: Array[String]) -> bool:
	if _valid:
		return true
	errors.append(_dependency_error if not _dependency_error.is_empty() else "Run lifecycle is invalid")
	return false


func _replace(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for key: Variant in source:
		target[key] = source[key]
