class_name FateSystem
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")

const MODE_PIECE := "棋子命运"
const MODE_SKILL := "技能命运"
const MODE_CHAOS := "混沌命运"
const MODE_ALL := "全命运"
const PURSUIT_ID := "pursuit"
const SIDES := ["ally", "enemy"]
const RNG_METHODS := ["next", "int_range", "pick"]
const BUFF_METHODS := ["is_valid", "definition_for", "validate_unit_holder", "apply_unit"]
const SELECTION_KEYS := [
	"active", "side", "mode", "all_in", "next_roll_index", "used_rng",
]


static func roll(
	state: Variant,
	side: Variant,
	tuning: Variant,
	combat_rng: Variant,
	buffs: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_state_side(state, side, errors):
		return {}
	var fate: Dictionary = _fate_state(state, side)
	if not fate["active"]:
		return {
			"applied": false,
			"side": side,
			"mode": fate["mode"],
			"all_in": false,
			"next_roll_index": fate["roll_index"] if side == "ally" else null,
			"used_rng": false,
			"pursuit_target_ids": [],
		}
	# Preflight every B1 holder before selection can consume combat RNG.
	if not preflight(state, side, buffs, errors):
		return {}
	var selection := select_mode(state, side, tuning, combat_rng, errors)
	if selection.is_empty():
		return {}
	return apply_mode(state, side, selection, buffs, errors)


static func preflight(
	state: Variant,
	side: Variant,
	buffs: Variant,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if not _validate_state_side(state, side, errors):
		return false
	if not _object_has_methods(buffs, BUFF_METHODS, "buffs", errors):
		return false
	if buffs.is_valid() != true:
		errors.append("buffs must be a valid B1 BuffSystem")
		return false
	if buffs.definition_for(PURSUIT_ID, "unit", errors) == null:
		return false
	for unit: Dictionary in _own_team(state, side):
		if not buffs.validate_unit_holder(unit, errors):
			return false
	return true


static func select_mode(
	state: Variant,
	side: Variant,
	tuning: Variant,
	combat_rng: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_state_side(state, side, errors):
		return {}
	var side_name := String(side)
	var fate: Dictionary = _fate_state(state, side_name)
	var current_index: Variant = fate["roll_index"] if side_name == "ally" else null
	if not fate["active"]:
		return {
			"active": false,
			"side": side_name,
			"mode": fate["mode"],
			"all_in": false,
			"next_roll_index": current_index,
			"used_rng": false,
		}
	if fate["all_in_turns"] > 0:
		return {
			"active": true,
			"side": side_name,
			"mode": MODE_ALL,
			"all_in": true,
			"next_roll_index": current_index,
			"used_rng": false,
		}
	var modes := (
		[MODE_PIECE, MODE_SKILL]
		if fate["chaos_used"]
		else [MODE_PIECE, MODE_SKILL, MODE_CHAOS]
	)
	var next_index := int(current_index) if side_name == "ally" else 0
	if side_name == "ally":
		var fixed := _parse_fixed_order(_tuning_string(tuning, "fateFixedOrder", errors))
		if not errors.is_empty():
			return {}
		if not fixed.is_empty():
			for _offset in fixed.size():
				var candidate: String = fixed[next_index % fixed.size()]
				next_index += 1
				if not fate["chaos_used"] or candidate != MODE_CHAOS:
					return {
						"active": true,
						"side": side_name,
						"mode": candidate,
						"all_in": false,
						"next_roll_index": next_index,
						"used_rng": false,
					}
	if not _object_has_methods(combat_rng, RNG_METHODS, "combat_rng", errors):
		return {}
	var picked: Variant = combat_rng.pick(modes)
	if picked not in modes:
		errors.append("combat_rng returned an invalid Fate mode")
		return {}
	return {
		"active": true,
		"side": side_name,
		"mode": picked,
		"all_in": false,
		"next_roll_index": next_index if side_name == "ally" else null,
		"used_rng": true,
	}


static func apply_mode(
	state: Variant,
	side: Variant,
	selection: Variant,
	buffs: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_state_side(state, side, errors):
		return {}
	if not _validate_selection(selection, String(side), errors):
		return {}
	if not selection["active"]:
		return {
			"applied": false,
			"side": side,
			"mode": selection["mode"],
			"all_in": false,
			"next_roll_index": selection["next_roll_index"],
			"used_rng": false,
			"pursuit_target_ids": [],
		}
	if not preflight(state, side, buffs, errors):
		return {}
	var pursuit_ids: Array = []
	if selection["mode"] in [MODE_PIECE, MODE_ALL]:
		# Freeze this roll's living targets before the first B1 callback can alter
		# later holders. This makes sequential-commit failures deterministic.
		var pursuit_targets: Array[Dictionary] = []
		for unit: Dictionary in _own_team(state, side):
			if unit["alive"]:
				pursuit_targets.append(unit)
		for unit: Dictionary in pursuit_targets:
			if not buffs.apply_unit(unit, PURSUIT_ID, 1, null, errors):
				var detail := errors[0] if not errors.is_empty() else "B1 apply_unit returned false"
				errors.clear()
				errors.append(
					"Fate pursuit committed prefix=%d before unit %s failed: %s"
					% [pursuit_ids.size(), str(unit["id"]), detail]
				)
				return {}
			pursuit_ids.append(unit["id"])
	# Fate metadata is committed only after every required Pursuit application.
	var fate: Dictionary = _fate_state(state, side)
	var lock_field := "enemy_lock" if side == "ally" else "ally_lock"
	fate["mode"] = selection["mode"]
	if side == "ally":
		fate["roll_index"] = selection["next_roll_index"]
	if selection["all_in"]:
		fate[lock_field] = "noSkill"
	else:
		fate[lock_field] = null
		if selection["mode"] == MODE_CHAOS:
			fate["chaos_used"] = true
			fate[lock_field] = "noSkill"
	return {
		"applied": true,
		"side": side,
		"mode": selection["mode"],
		"all_in": selection["all_in"],
		"next_roll_index": selection["next_roll_index"],
		"used_rng": selection["used_rng"],
		"pursuit_target_ids": pursuit_ids,
	}


static func _validate_state_side(state: Variant, side: Variant, errors: Array[String]) -> bool:
	if side not in SIDES:
		errors.append("side must be ally or enemy")
		return false
	var state_errors: Array[String] = []
	if not BattleStateScript.validate(state, state_errors):
		_append_errors(state_errors, errors)
		return false
	return true


static func _validate_selection(selection: Variant, side: String, errors: Array[String]) -> bool:
	if typeof(selection) != TYPE_DICTIONARY or selection.size() != SELECTION_KEYS.size():
		errors.append("Fate selection must be a canonical Dictionary")
		return false
	for key in SELECTION_KEYS:
		if not selection.has(key):
			errors.append("Fate selection.%s is required" % key)
			return false
	for key: Variant in selection:
		if typeof(key) != TYPE_STRING or key not in SELECTION_KEYS:
			errors.append("Fate selection contains an unknown field")
			return false
	if typeof(selection["active"]) != TYPE_BOOL or typeof(selection["all_in"]) != TYPE_BOOL:
		errors.append("Fate selection active/all_in must be booleans")
		return false
	if typeof(selection["used_rng"]) != TYPE_BOOL or selection["side"] != side:
		errors.append("Fate selection side/RNG metadata is invalid")
		return false
	if selection["active"]:
		if selection["mode"] not in [MODE_PIECE, MODE_SKILL, MODE_CHAOS, MODE_ALL]:
			errors.append("Fate selection mode is invalid")
			return false
		if selection["all_in"] != (selection["mode"] == MODE_ALL):
			errors.append("Fate selection all_in and mode disagree")
			return false
	if side == "ally":
		if typeof(selection["next_roll_index"]) != TYPE_INT or selection["next_roll_index"] < 0:
			errors.append("ally Fate selection next_roll_index must be non-negative")
			return false
	elif selection["next_roll_index"] != null:
		errors.append("enemy Fate selection must not contain a roll index")
		return false
	return true


static func _tuning_string(tuning: Variant, id: String, errors: Array[String]) -> String:
	if typeof(tuning) != TYPE_DICTIONARY or not tuning.has(id):
		errors.append("tuning.%s is required" % id)
		return ""
	var value: Variant = tuning[id]
	if value is Resource:
		if value.get_script() != TuningValueDefinition or value.id != id:
			errors.append("tuning.%s must be a TuningValueDefinition" % id)
			return ""
		value = value.value
	if typeof(value) != TYPE_STRING:
		errors.append("tuning.%s must be a string" % id)
		return ""
	return value


static func _parse_fixed_order(value: String) -> Array[String]:
	var normalized := value
	for separator in ["，", "、", "|", "/", "\t", "\r", "\n", " "]:
		normalized = normalized.replace(separator, ",")
	var result: Array[String] = []
	for raw in normalized.split(",", false):
		var mode := _normalize_mode(raw)
		if not mode.is_empty():
			result.append(mode)
	return result


static func _normalize_mode(value: Variant) -> String:
	var text := str(value).strip_edges()
	if text in ["1", "棋子命运", "棋子", "piece"]:
		return MODE_PIECE
	if text in ["2", "技能命运", "技能", "skill"]:
		return MODE_SKILL
	if text in ["3", "混沌命运", "混沌", "chaos"]:
		return MODE_CHAOS
	return ""


static func _object_has_methods(
	value: Variant,
	methods: Array,
	path: String,
	errors: Array[String],
) -> bool:
	if typeof(value) != TYPE_OBJECT or value == null:
		errors.append("%s must be an injected service Object" % path)
		return false
	for method in methods:
		if not value.has_method(method):
			errors.append("%s must provide %s" % [path, method])
	return errors.is_empty()


static func _fate_state(state: Dictionary, side: String) -> Dictionary:
	return state["fate" if side == "ally" else "enemy_fate"]


static func _own_team(state: Dictionary, side: String) -> Array:
	return state["allies" if side == "ally" else "enemies"]


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message in source:
		destination.append(message)
