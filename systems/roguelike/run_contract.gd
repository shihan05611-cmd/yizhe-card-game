class_name RoguelikeRunContract
extends RefCounted

## M5's in-memory authority shape. Persistence/version migration belongs to M6.
## Gameplay catalogs are intentionally not consumed here; later M5 services add
## their catalog-aware invariants around this closed structural contract.

const STATUS_IDLE := "idle"
const STATUSES := [
	STATUS_IDLE,
	"heroSelect",
	"map",
	"fighting",
	"reward",
	"forge",
	"shop",
	"event",
	"failed",
	"cleared",
]
const STATE_KEYS := [
	"active",
	"chapter",
	"max_chapters",
	"map_rows",
	"map_columns",
	"currency",
	"status",
	"current_node_id",
	"enemy_hp_scale",
	"enemy_atk_scale",
	"reward_pending",
	"forge_uses_this_node",
	"map_nodes",
	"relic_ids",
	"free_skill_ids",
	"exclusive_card_ids",
	"reward_options",
	"shop_options",
	"initial_hero_choice_ids",
	"hero_deployment_slots",
	"front_hero_ids",
	"back_hero_ids",
	"piece_slots",
	"permanent_buffs",
]


static func create() -> Dictionary:
	return {
		"active": false,
		"chapter": 0,
		"max_chapters": 3,
		"map_rows": 3,
		"map_columns": 10,
		"currency": 0,
		"status": STATUS_IDLE,
		"current_node_id": null,
		"enemy_hp_scale": 1.0,
		"enemy_atk_scale": 1.0,
		"reward_pending": false,
		"forge_uses_this_node": 0,
		"map_nodes": [],
		"relic_ids": [],
		"free_skill_ids": [],
		# Extra acquired active-exclusive card copies. The base copy for each
		# deployed hero is assembled separately and is never recorded here.
		"exclusive_card_ids": [],
		"reward_options": [],
		"shop_options": [],
		"initial_hero_choice_ids": [],
		# JSON-safe hero id string -> exact board slot (1..6). The front/back
		# arrays below are derived row views for M3 deck assembly, not positions.
		"hero_deployment_slots": {},
		"front_hero_ids": [],
		"back_hero_ids": [],
		"piece_slots": _default_piece_slots(),
		"permanent_buffs": [],
	}


static func reset(state: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if typeof(state) != TYPE_DICTIONARY:
		errors.append("run state must be a Dictionary")
		return false
	_publish(state, create())
	return true


static func validate(state: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _closed_dictionary(state, "run state", STATE_KEYS, errors):
		return false
	if typeof(state["active"]) != TYPE_BOOL:
		errors.append("run state.active must be a boolean")
		return false
	if state["status"] not in STATUSES:
		errors.append("run state.status contains an invalid value")
		return false
	if bool(state["active"]) != (state["status"] != STATUS_IDLE):
		errors.append("run state.active must be false only for idle status")
		return false
	if not _integer_in_range(state["chapter"], 0, 3):
		errors.append("run state.chapter must be an integer from 0 through 3")
		return false
	for fixed_field in [["max_chapters", 3], ["map_rows", 3], ["map_columns", 10]]:
		if typeof(state[fixed_field[0]]) != TYPE_INT or state[fixed_field[0]] != fixed_field[1]:
			errors.append("run state.%s must equal %d" % fixed_field)
			return false
	for field in ["currency", "forge_uses_this_node"]:
		if not _non_negative_integer(state[field]):
			errors.append("run state.%s must be a non-negative integer" % field)
			return false
	for field in ["enemy_hp_scale", "enemy_atk_scale"]:
		if not _positive_number(state[field]):
			errors.append("run state.%s must be a positive finite number" % field)
			return false
	if typeof(state["reward_pending"]) != TYPE_BOOL:
		errors.append("run state.reward_pending must be a boolean")
		return false
	if state["current_node_id"] != null and not _non_empty_string(state["current_node_id"]):
		errors.append("run state.current_node_id must be null or a non-empty trimmed string")
		return false
	for field in ["map_nodes", "reward_options", "shop_options", "permanent_buffs"]:
		if typeof(state[field]) != TYPE_ARRAY:
			errors.append("run state.%s must be an Array" % field)
			return false
	if not _string_id_array(state["relic_ids"], "run state.relic_ids", false, errors):
		return false
	# Deliberately allow duplicates: each entry is one owned card copy.
	if not _string_id_array(state["free_skill_ids"], "run state.free_skill_ids", true, errors):
		return false
	if not _string_id_array(state["exclusive_card_ids"], "run state.exclusive_card_ids", true, errors):
		return false
	for field in ["initial_hero_choice_ids", "front_hero_ids", "back_hero_ids"]:
		if not _hero_id_array(state[field], "run state.%s" % field, errors):
			return false
	if not _hero_deployment_slots(state["hero_deployment_slots"], errors):
		return false
	if not _derived_roster_matches_slots(state, errors):
		return false
	if not _piece_slots(state["piece_slots"], errors):
		return false
	return _json_safe(state, "run state", errors)


static func snapshot(state: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not validate(state, errors):
		return {}
	return _deep_copy(state)


static func transition(
	state: Variant,
	command: Callable,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if typeof(state) != TYPE_DICTIONARY:
		errors.append("run state must be a Dictionary")
		return false
	if not command.is_valid():
		errors.append("run transition command must be callable")
		return false
	var candidate := snapshot(state, errors)
	if not errors.is_empty():
		return false
	var result: Variant = command.call(candidate)
	if typeof(result) != TYPE_BOOL:
		errors.append("run transition command must return a boolean")
		return false
	if not result:
		return false
	if not validate(candidate, errors):
		return false
	_publish(state, candidate)
	return true


static func _default_piece_slots() -> Array:
	# Empty positions are explicit. A defeated deployed piece keeps its class id
	# with hp_ratio 0.0, while an unused position carries a null class id.
	return [
		{"slot": 1, "hp_ratio": 1.0, "piece_class_id": null},
		{"slot": 2, "hp_ratio": 1.0, "piece_class_id": "shield"},
		{"slot": 3, "hp_ratio": 1.0, "piece_class_id": null},
		{"slot": 4, "hp_ratio": 1.0, "piece_class_id": "assassin"},
		{"slot": 5, "hp_ratio": 1.0, "piece_class_id": "crossbow"},
		{"slot": 6, "hp_ratio": 1.0, "piece_class_id": "banner"},
	]


static func _piece_slots(value: Variant, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 6:
		errors.append("run state.piece_slots must contain exactly six ordered slots")
		return false
	for index in value.size():
		var path := "run state.piece_slots[%d]" % index
		var entry: Variant = value[index]
		if not _closed_dictionary(entry, path, ["slot", "hp_ratio", "piece_class_id"], errors):
			return false
		if typeof(entry["slot"]) != TYPE_INT or entry["slot"] != index + 1:
			errors.append("%s.slot must equal %d" % [path, index + 1])
			return false
		if not _finite_number(entry["hp_ratio"]) or float(entry["hp_ratio"]) < 0.0 or float(entry["hp_ratio"]) > 1.0:
			errors.append("%s.hp_ratio must be a finite number from 0 through 1" % path)
			return false
		var class_id: Variant = entry["piece_class_id"]
		if class_id != null and not _non_empty_string(class_id):
			errors.append("%s.piece_class_id must be null or a non-empty string" % path)
			return false
	return true


static func _string_id_array(
	value: Variant,
	path: String,
	allow_duplicates: bool,
	errors: Array[String],
) -> bool:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an Array" % path)
		return false
	var seen := {}
	for index in value.size():
		if not _non_empty_string(value[index]):
			errors.append("%s[%d] must be a non-empty trimmed string" % [path, index])
			return false
		if not allow_duplicates and seen.has(value[index]):
			errors.append("%s must contain unique ids" % path)
			return false
		seen[value[index]] = true
	return true


static func _hero_id_array(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an Array" % path)
		return false
	var seen := {}
	for index in value.size():
		var id: Variant = value[index]
		if typeof(id) != TYPE_INT or id <= 0:
			errors.append("%s[%d] must be a positive integer" % [path, index])
			return false
		if seen.has(id):
			errors.append("%s must contain unique ids" % path)
			return false
		seen[id] = true
	return true


static func _hero_deployment_slots(value: Variant, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("run state.hero_deployment_slots must be a Dictionary")
		return false
	var seen_slots := {}
	for raw_hero_id: Variant in value:
		if typeof(raw_hero_id) != TYPE_STRING or not raw_hero_id.is_valid_int():
			errors.append("run state.hero_deployment_slots keys must be canonical positive integer strings")
			return false
		var hero_id := int(raw_hero_id)
		if hero_id <= 0 or str(hero_id) != raw_hero_id:
			errors.append("run state.hero_deployment_slots keys must be canonical positive integer strings")
			return false
		var slot: Variant = value[raw_hero_id]
		if typeof(slot) != TYPE_INT or slot < 1 or slot > 6 or seen_slots.has(slot):
			errors.append("run state.hero_deployment_slots must assign unique slots from 1 through 6")
			return false
		seen_slots[slot] = true
	return true


static func _derived_roster_matches_slots(state: Dictionary, errors: Array[String]) -> bool:
	var entries: Array = []
	for raw_hero_id: String in state["hero_deployment_slots"]:
		entries.append({"hero_id": int(raw_hero_id), "slot": state["hero_deployment_slots"][raw_hero_id]})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left["slot"] < right["slot"] or (
			left["slot"] == right["slot"] and left["hero_id"] < right["hero_id"]
		)
	)
	var expected_front: Array[int] = []
	var expected_back: Array[int] = []
	for entry: Dictionary in entries:
		if entry["slot"] <= 3:
			expected_front.append(entry["hero_id"])
		else:
			expected_back.append(entry["hero_id"])
	if state["front_hero_ids"] != expected_front or state["back_hero_ids"] != expected_back:
		errors.append("run state front/back hero ids must be slot-sorted row views of hero_deployment_slots")
		return false
	return true


static func _closed_dictionary(
	value: Variant,
	path: String,
	expected_keys: Array,
	errors: Array[String],
) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be a canonical Dictionary" % path)
		return false
	if value.size() != expected_keys.size():
		errors.append("%s has a non-canonical field set" % path)
		return false
	for key in expected_keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in expected_keys:
			errors.append("%s contains an unknown field: %s" % [path, str(key)])
			return false
	return true


static func _json_safe(value: Variant, path: String, errors: Array[String]) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			if is_finite(value):
				return true
		TYPE_ARRAY:
			for index in value.size():
				if not _json_safe(value[index], "%s[%d]" % [path, index], errors):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING:
					errors.append("%s contains a non-string JSON key" % path)
					return false
				if not _json_safe(value[key], "%s.%s" % [path, key], errors):
					return false
			return true
	errors.append("%s contains a non-JSON-safe value" % path)
	return false


static func _publish(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for key: Variant in source:
		target[key] = _deep_copy(source[key])


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


static func _non_empty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value == value.strip_edges() and not value.is_empty()


static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and value >= minimum and value <= maximum


static func _non_negative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


static func _positive_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) > 0.0


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))
