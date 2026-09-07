class_name BattleState
extends RefCounted

## Canonical mutable M2 battle state. Callers inject authored unit/hero values and
## tuning/catalog services at the composition root; neither authority is embedded
## here. create() publishes new mutable references, while snapshot() is JSON-safe
## and deeply isolated. Both reject non-canonical input instead of normalizing it.

const SIDES := ["ally", "enemy"]
const RESULTS := ["win", "lose"]
const STATE_KEYS := [
	"round", "phase", "sp", "sp_max", "base_sp_max", "enemy_sp", "enemy_sp_max",
	"allies", "enemies", "player_heroes", "enemy_heroes", "side_buffs", "fate",
	"enemy_fate", "battle_growth_flags", "burn_ex_cast_count",
	"enemy_burn_ex_cast_count", "counter_threshold", "marshal_target_id",
	"ally_puppet_martyr_active", "game_over", "battle_result",
]
const UNIT_KEYS := [
	"id", "slot", "side", "class_id", "class_name", "hp", "max_hp", "atk",
	"crit_rate", "alive", "general", "base_block_rate", "extra_action_charges",
	"buffs", "is_puppet", "fixed_max_hp", "puppet_martyr", "disarm_turns",
	"stealth_attack_ready", "special_id", "echo_damage_bonus", "hp_threshold_crossed",
]
const PLAYER_HERO_KEYS := [
	"id", "name", "deployed", "ex_skill", "energy", "max_energy",
	"base_crit_rate", "fist_momentum",
]
# Enemy runtime preserves the stage-authored skill_pool as-is, including an empty
# pool; choosing the default pool is an orchestration concern. Web battle.js also
# implicitly adds fistMomentum on the first enemy fist cast, so Godot makes it
# canonical up front.
const ENEMY_HERO_KEYS := [
	"id", "name", "ex_skill", "skills", "skill_pool", "energy", "max_energy",
	"base_crit_rate", "fist_momentum",
]
const BUFF_KEYS := ["id", "stacks", "turns", "layer_turns"]
const FATE_KEYS := [
	"active", "mode", "cast_used", "chaos_used", "enemy_lock", "all_in_turns",
	"roll_index", "skill_sp_gain_this_round",
]
const ENEMY_FATE_KEYS := [
	"active", "mode", "cast_used", "chaos_used", "ally_lock", "all_in_turns",
	"skill_sp_gain_this_round",
]
const GROWTH_FLAG_KEYS := ["flame_investment_used"]


static func create(source: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _validate_state(source, errors):
		return {}
	return _deep_copy(source)


static func validate(state: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	return _validate_state(state, errors)


static func snapshot(state: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _validate_state(state, errors):
		return {}
	return _deep_copy(state)


static func _validate_state(state: Variant, errors: Array[String]) -> bool:
	if not _closed_dictionary(state, "state", STATE_KEYS, errors):
		return false
	if not _positive_integer(state["round"], "state.round", errors):
		return false
	if not _non_empty_string(state["phase"], "state.phase", errors):
		return false
	for field in ["sp", "sp_max", "base_sp_max", "enemy_sp", "enemy_sp_max"]:
		if not _non_negative_number(state[field], "state.%s" % field, errors):
			return false
	if float(state["sp"]) > float(state["sp_max"]):
		errors.append("state.sp must not exceed state.sp_max")
		return false
	if float(state["enemy_sp"]) > float(state["enemy_sp_max"]):
		errors.append("state.enemy_sp must not exceed state.enemy_sp_max")
		return false
	if not _validate_units(state["allies"], "ally", "state.allies", errors):
		return false
	if not _validate_units(state["enemies"], "enemy", "state.enemies", errors):
		return false
	if not _validate_player_heroes(state["player_heroes"], errors):
		return false
	if not _validate_enemy_heroes(state["enemy_heroes"], errors):
		return false
	if not _validate_side_buffs(state["side_buffs"], errors):
		return false
	if not _validate_fate(state["fate"], false, "state.fate", errors):
		return false
	if not _validate_fate(state["enemy_fate"], true, "state.enemy_fate", errors):
		return false
	if not _closed_dictionary(state["battle_growth_flags"], "state.battle_growth_flags", GROWTH_FLAG_KEYS, errors):
		return false
	if typeof(state["battle_growth_flags"]["flame_investment_used"]) != TYPE_BOOL:
		errors.append("state.battle_growth_flags.flame_investment_used must be a boolean")
		return false
	for field in ["burn_ex_cast_count", "enemy_burn_ex_cast_count", "counter_threshold"]:
		if not _non_negative_integer(state[field], "state.%s" % field, errors):
			return false
	if not _slot(state["marshal_target_id"], "state.marshal_target_id", errors):
		return false
	if typeof(state["ally_puppet_martyr_active"]) != TYPE_BOOL:
		errors.append("state.ally_puppet_martyr_active must be a boolean")
		return false
	if typeof(state["game_over"]) != TYPE_BOOL:
		errors.append("state.game_over must be a boolean")
		return false
	var result: Variant = state["battle_result"]
	if state["game_over"]:
		if result not in RESULTS:
			errors.append("state.battle_result must be win or lose when game_over is true")
			return false
	elif result != null:
		errors.append("state.battle_result must be null while game_over is false")
		return false
	return _json_safe(state, "state", errors)


static func _validate_units(value: Variant, side: String, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 6:
		errors.append("%s must be an Array containing exactly six slots" % path)
		return false
	var ids := {}
	var slots := {}
	for index in value.size():
		var unit: Variant = value[index]
		var unit_path := "%s[%d]" % [path, index]
		if not _closed_dictionary(unit, unit_path, UNIT_KEYS, errors):
			return false
		if not _stable_id(unit["id"], "%s.id" % unit_path, errors):
			return false
		var id_key := str(unit["id"])
		if ids.has(id_key):
			errors.append("%s contains duplicate unit id: %s" % [path, id_key])
			return false
		ids[id_key] = true
		if not _slot(unit["slot"], "%s.slot" % unit_path, errors):
			return false
		if slots.has(unit["slot"]):
			errors.append("%s contains duplicate slot: %s" % [path, str(unit["slot"])])
			return false
		slots[unit["slot"]] = true
		if unit["side"] != side:
			errors.append("%s.side must be %s" % [unit_path, side])
			return false
		for field in ["class_id", "class_name"]:
			if not _non_empty_string(unit[field], "%s.%s" % [unit_path, field], errors):
				return false
		for field in ["hp", "max_hp", "atk", "crit_rate", "base_block_rate", "echo_damage_bonus"]:
			if not _non_negative_number(unit[field], "%s.%s" % [unit_path, field], errors):
				return false
		if float(unit["hp"]) > float(unit["max_hp"]):
			errors.append("%s.hp must not exceed max_hp" % unit_path)
			return false
		if typeof(unit["alive"]) != TYPE_BOOL:
			errors.append("%s.alive must be a boolean" % unit_path)
			return false
		if unit["alive"] and (float(unit["hp"]) <= 0.0 or float(unit["max_hp"]) <= 0.0):
			errors.append("%s alive units must have positive hp and max_hp" % unit_path)
			return false
		if not unit["alive"] and float(unit["hp"]) != 0.0:
			errors.append("%s dead units must have zero hp" % unit_path)
			return false
		for field in ["general", "is_puppet", "puppet_martyr", "stealth_attack_ready", "hp_threshold_crossed"]:
			if typeof(unit[field]) != TYPE_BOOL:
				errors.append("%s.%s must be a boolean" % [unit_path, field])
				return false
		for field in ["extra_action_charges", "disarm_turns"]:
			if not _non_negative_integer(unit[field], "%s.%s" % [unit_path, field], errors):
				return false
		if unit["fixed_max_hp"] != null and not _positive_number(unit["fixed_max_hp"], "%s.fixed_max_hp" % unit_path, errors):
			return false
		if unit["special_id"] != null and not _non_empty_string(unit["special_id"], "%s.special_id" % unit_path, errors):
			return false
		if not _validate_buffs(unit["buffs"], "%s.buffs" % unit_path, errors):
			return false
	return true


static func _validate_player_heroes(value: Variant, errors: Array[String]) -> bool:
	var path := "state.player_heroes"
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an Array" % path)
		return false
	var ids := {}
	for index in value.size():
		var hero: Variant = value[index]
		var hero_path := "%s[%d]" % [path, index]
		if not _closed_dictionary(hero, hero_path, PLAYER_HERO_KEYS, errors):
			return false
		if not _validate_common_hero(hero, hero_path, ids, errors):
			return false
		if typeof(hero["deployed"]) != TYPE_BOOL:
			errors.append("%s.deployed must be a boolean" % hero_path)
			return false
		if not _validate_fist_momentum(hero["fist_momentum"], hero_path, errors):
			return false
	return true


static func _validate_enemy_heroes(value: Variant, errors: Array[String]) -> bool:
	var path := "state.enemy_heroes"
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an Array" % path)
		return false
	var ids := {}
	for index in value.size():
		var hero: Variant = value[index]
		var hero_path := "%s[%d]" % [path, index]
		if not _closed_dictionary(hero, hero_path, ENEMY_HERO_KEYS, errors):
			return false
		if not _validate_common_hero(hero, hero_path, ids, errors):
			return false
		if not _validate_string_ids(hero["skills"], "%s.skills" % hero_path, errors):
			return false
		if not _validate_string_ids(hero["skill_pool"], "%s.skill_pool" % hero_path, errors):
			return false
		if not _validate_fist_momentum(hero["fist_momentum"], hero_path, errors):
			return false
	return true


static func _validate_common_hero(
	hero: Dictionary,
	path: String,
	ids: Dictionary,
	errors: Array[String],
) -> bool:
	if not _stable_id(hero["id"], "%s.id" % path, errors):
		return false
	var id_key := str(hero["id"])
	if ids.has(id_key):
		errors.append("%s duplicates hero id: %s" % [path, id_key])
		return false
	ids[id_key] = true
	if not _non_empty_string(hero["name"], "%s.name" % path, errors):
		return false
	if not _non_empty_string(hero["ex_skill"], "%s.ex_skill" % path, errors):
		return false
	if not _positive_number(hero["max_energy"], "%s.max_energy" % path, errors):
		return false
	if not _non_negative_number(hero["energy"], "%s.energy" % path, errors):
		return false
	if float(hero["energy"]) > float(hero["max_energy"]):
		errors.append("%s.energy must not exceed max_energy" % path)
		return false
	if not _non_negative_number(hero["base_crit_rate"], "%s.base_crit_rate" % path, errors):
		return false
	return true


static func _validate_fist_momentum(value: Variant, path: String, errors: Array[String]) -> bool:
	if not _non_negative_integer(value, "%s.fist_momentum" % path, errors):
		return false
	if int(value) > 5:
		errors.append("%s.fist_momentum must not exceed 5" % path)
		return false
	return true


static func _validate_side_buffs(value: Variant, errors: Array[String]) -> bool:
	if not _closed_dictionary(value, "state.side_buffs", SIDES, errors):
		return false
	for side in SIDES:
		if not _validate_buffs(value[side], "state.side_buffs.%s" % side, errors):
			return false
	return true


static func _validate_buffs(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an Array" % path)
		return false
	var ids := {}
	for index in value.size():
		var buff: Variant = value[index]
		var buff_path := "%s[%d]" % [path, index]
		if not _closed_dictionary(buff, buff_path, BUFF_KEYS, errors):
			return false
		if not _non_empty_string(buff["id"], "%s.id" % buff_path, errors):
			return false
		if ids.has(buff["id"]):
			errors.append("%s contains duplicate buff id: %s" % [path, buff["id"]])
			return false
		ids[buff["id"]] = true
		if not _non_negative_integer(buff["stacks"], "%s.stacks" % buff_path, errors):
			return false
		if not _non_negative_integer(buff["turns"], "%s.turns" % buff_path, errors):
			return false
		if typeof(buff["layer_turns"]) != TYPE_ARRAY:
			errors.append("%s.layer_turns must be an Array" % buff_path)
			return false
		var layers: Array = buff["layer_turns"]
		for layer_index in layers.size():
			if not _positive_integer(layers[layer_index], "%s.layer_turns[%d]" % [buff_path, layer_index], errors):
				return false
		if not layers.is_empty() and (int(buff["stacks"]) != layers.size() or int(buff["turns"]) != int(layers.max())):
			errors.append("%s stacks turns and layer_turns are inconsistent" % buff_path)
			return false
		if int(buff["stacks"]) == 0 and int(buff["turns"]) == 0:
			errors.append("%s must represent an active buff" % buff_path)
			return false
	return true


static func _validate_fate(value: Variant, enemy: bool, path: String, errors: Array[String]) -> bool:
	var keys: Array = ENEMY_FATE_KEYS if enemy else FATE_KEYS
	if not _closed_dictionary(value, path, keys, errors):
		return false
	for field in ["active", "cast_used", "chaos_used"]:
		if typeof(value[field]) != TYPE_BOOL:
			errors.append("%s.%s must be a boolean" % [path, field])
			return false
	if value["mode"] != null and not _non_empty_string(value["mode"], "%s.mode" % path, errors):
		return false
	var lock_field := "ally_lock" if enemy else "enemy_lock"
	if value[lock_field] != null and not _non_empty_string(value[lock_field], "%s.%s" % [path, lock_field], errors):
		return false
	for field in ["all_in_turns", "skill_sp_gain_this_round"]:
		if not _non_negative_integer(value[field], "%s.%s" % [path, field], errors):
			return false
	if not enemy and not _non_negative_integer(value["roll_index"], "%s.roll_index" % path, errors):
		return false
	return true


static func _validate_string_ids(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an Array" % path)
		return false
	var seen := {}
	for index in value.size():
		if not _non_empty_string(value[index], "%s[%d]" % [path, index], errors):
			return false
		if seen.has(value[index]):
			errors.append("%s contains duplicate id: %s" % [path, value[index]])
			return false
		seen[value[index]] = true
	return true


static func _closed_dictionary(value: Variant, path: String, expected_keys: Array, errors: Array[String]) -> bool:
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


static func _stable_id(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_INT and value > 0:
		return true
	if typeof(value) == TYPE_STRING and value == value.strip_edges() and not value.is_empty():
		return true
	errors.append("%s must be a positive integer or non-empty trimmed string" % path)
	return false


static func _non_empty_string(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_STRING and value == value.strip_edges() and not value.is_empty():
		return true
	errors.append("%s must be a non-empty trimmed string" % path)
	return false


static func _slot(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_INT and value >= 1 and value <= 6:
		return true
	errors.append("%s must be an integer from 1 through 6" % path)
	return false


static func _positive_integer(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_INT and value > 0:
		return true
	errors.append("%s must be a positive integer" % path)
	return false


static func _non_negative_integer(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_INT and value >= 0:
		return true
	errors.append("%s must be a non-negative integer" % path)
	return false


static func _positive_number(value: Variant, path: String, errors: Array[String]) -> bool:
	if _finite_number(value) and float(value) > 0.0:
		return true
	errors.append("%s must be a positive finite number" % path)
	return false


static func _non_negative_number(value: Variant, path: String, errors: Array[String]) -> bool:
	if _finite_number(value) and float(value) >= 0.0:
		return true
	errors.append("%s must be a non-negative finite number" % path)
	return false


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


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
