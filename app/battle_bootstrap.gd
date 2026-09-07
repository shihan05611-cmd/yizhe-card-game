class_name BattleBootstrap
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const BattleRuntimeScript = preload("res://systems/combat/battle_runtime.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")

const CONFIG_KEYS := ["battle_seed", "deployed_hero_ids", "free_skill_ids", "stage_id"]


static func create(config: Variant, stream: Variant, errors: Array[String]) -> Dictionary:
	errors.clear()
	if not _validate_config(config, errors):
		return {}
	var catalog_errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(catalog_errors)
	if not catalog_errors.is_empty():
		errors.append("content catalog failed: %s" % catalog_errors[0])
		return {}
	if not catalogs["stages"].has(config["stage_id"]):
		errors.append("unknown battle stage: %s" % config["stage_id"])
		return {}
	var state := _build_state(config, catalogs, errors)
	if not errors.is_empty():
		return {}
	var streams := RngScript.create_named_streams(
		config["battle_seed"], ["combat", "enemyPolicy"]
	)
	if streams.is_empty():
		errors.append("battle RNG streams failed to initialize")
		return {}
	var runtime_errors: Array[String] = []
	var runtime := BattleRuntimeScript.new({
		"state": state,
		"run_state": {"permanent_buffs": []},
		"catalogs": catalogs,
		"tuning": catalogs["tuning"],
		"combat_rng": streams["combat"],
		"enemy_policy_rng": streams["enemyPolicy"],
		"actions": {
			"emit_combat_event": Callable(stream, "capture_combat"),
			"emit_content_event": Callable(stream, "capture_content"),
			"log": Callable(stream, "capture_log"),
			"on_battle_resolved": Callable(stream, "capture_battle_resolved"),
			"record_damage": func(_request: Dictionary) -> Dictionary:
				return CombatPortsScript.ok(null),
			"record_heal": Callable(stream, "capture_heal"),
			"resolve_battle_end": func(_request: Dictionary) -> Dictionary:
				return CombatPortsScript.ok(true),
		},
		"relic_actions": {},
		"get_owned_relic_ids": func() -> Array: return [],
		"format_damage": func(value: float) -> float:
			return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return float(unit["base_block_rate"]),
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return 1.0,
		"on_damage_event": Callable(stream, "capture_damage"),
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"on_buff_event": Callable(stream, "capture_buff"),
		"on_burn_settled": func(_result: Dictionary) -> void: pass,
		"on_hook_error": func(message: String, metadata: Dictionary) -> void:
			stream.capture_fatal("hook_error", message, metadata),
	}, runtime_errors)
	if not runtime_errors.is_empty() or not runtime.is_valid():
		errors.append(
			"battle runtime failed: %s"
			% (runtime_errors[0] if not runtime_errors.is_empty() else "invalid runtime")
		)
		return {}
	return {
		"runtime": runtime,
		"state": state,
		"catalogs": catalogs,
		"deployed_hero_ids": config["deployed_hero_ids"].duplicate(),
		"free_skill_ids": config["free_skill_ids"].duplicate(),
		"battle_seed": config["battle_seed"],
	}


static func _build_state(config: Dictionary, catalogs: Dictionary, errors: Array[String]) -> Dictionary:
	var deployed_ids: Array = config["deployed_hero_ids"]
	var player_catalog: Dictionary = catalogs["characters"]["players"]
	for hero_id: Variant in deployed_ids:
		if not player_catalog.has(hero_id):
			errors.append("deployed roster references unknown player hero: %s" % str(hero_id))
	if not errors.is_empty():
		return {}
	var stage: Variant = catalogs["stages"][config["stage_id"]]
	var player_heroes: Array[Dictionary] = []
	for hero_id: Variant in player_catalog:
		var definition: Variant = player_catalog[hero_id]
		player_heroes.append({
			"id": definition.id,
			"name": definition.name,
			"deployed": definition.id in deployed_ids,
			"ex_skill": definition.exclusive_skill_id,
			"energy": float(definition.energy),
			"max_energy": float(definition.max_energy),
			"base_crit_rate": float(definition.base_crit_rate),
			"fist_momentum": int(definition.fist_momentum),
		})
	var enemy_heroes: Array[Dictionary] = []
	for enemy: Dictionary in stage.enemy_yizhes:
		enemy_heroes.append({
			"id": enemy["id"],
			"name": enemy["name"],
			"ex_skill": enemy["exclusive_skill_id"],
			"skills": enemy["source_skill_names"].duplicate(),
			"skill_pool": enemy["free_skill_ids"].duplicate(),
			"energy": 0.0,
			"max_energy": float(enemy["source_max_energy"]),
			"base_crit_rate": float(enemy["base_crit_rate"]),
			"fist_momentum": 0,
		})
	var source := {
		"round": 1,
		"phase": "player_input",
		"sp": 10.0,
		"sp_max": 10.0,
		"base_sp_max": 10.0,
		"enemy_sp": 6.0,
		"enemy_sp_max": 6.0,
		"allies": _team("ally", catalogs),
		"enemies": _team("enemy", catalogs),
		"player_heroes": player_heroes,
		"enemy_heroes": enemy_heroes,
		"side_buffs": {"ally": [], "enemy": []},
		"fate": {
			"active": false, "mode": null, "cast_used": false, "chaos_used": false,
			"enemy_lock": null, "all_in_turns": 0, "roll_index": 0,
			"skill_sp_gain_this_round": 0,
		},
		"enemy_fate": {
			"active": false, "mode": null, "cast_used": false, "chaos_used": false,
			"ally_lock": null, "all_in_turns": 0, "skill_sp_gain_this_round": 0,
		},
		"battle_growth_flags": {"flame_investment_used": false},
		"burn_ex_cast_count": 0,
		"enemy_burn_ex_cast_count": 0,
		"counter_threshold": 4,
		"marshal_target_id": 1,
		"ally_puppet_martyr_active": false,
		"game_over": false,
		"battle_result": null,
	}
	var state_errors: Array[String] = []
	var state: Dictionary = BattleStateScript.create(source, state_errors)
	if not state_errors.is_empty():
		errors.append("battle state failed: %s" % state_errors[0])
	return state


static func _team(side: String, catalogs: Dictionary) -> Array[Dictionary]:
	var prefix := "ally" if side == "ally" else "enemy"
	var class_definition: Variant = catalogs["piece_classes"]["default"]
	var hp := _tuning(catalogs, "%sBaseHp" % prefix)
	var attack := _tuning(catalogs, "%sBaseAtk" % prefix)
	var block := _tuning(catalogs, "%sBaseBlock" % prefix)
	var crit := _tuning(catalogs, "%sBaseCrit" % prefix)
	var units: Array[Dictionary] = []
	for slot in range(1, 7):
		units.append({
			"id": slot if side == "ally" else 100 + slot,
			"slot": slot,
			"side": side,
			"class_id": class_definition.id,
			"class_name": class_definition.name,
			"hp": hp,
			"max_hp": hp,
			"atk": attack,
			"crit_rate": crit,
			"alive": true,
			"general": slot == 1,
			"base_block_rate": block,
			"extra_action_charges": 0,
			"buffs": [],
			"is_puppet": false,
			"fixed_max_hp": null,
			"puppet_martyr": false,
			"disarm_turns": 0,
			"stealth_attack_ready": false,
			"special_id": null,
			"echo_damage_bonus": 0.0,
			"hp_threshold_crossed": false,
		})
	return units


static func _tuning(catalogs: Dictionary, id: String) -> float:
	return float(catalogs["tuning"][id].value)


static func _validate_config(config: Variant, errors: Array[String]) -> bool:
	if typeof(config) != TYPE_DICTIONARY or config.size() != CONFIG_KEYS.size():
		errors.append("battle bootstrap config must have a canonical closed shape")
		return false
	for key: String in CONFIG_KEYS:
		if not config.has(key):
			errors.append("battle bootstrap config.%s is required" % key)
	for key: Variant in config:
		if typeof(key) != TYPE_STRING or key not in CONFIG_KEYS:
			errors.append("battle bootstrap config contains an unknown field")
	if not errors.is_empty():
		return false
	if typeof(config["deployed_hero_ids"]) != TYPE_ARRAY or config["deployed_hero_ids"].is_empty():
		errors.append("deployed_hero_ids must be a non-empty Array")
	if typeof(config["free_skill_ids"]) != TYPE_ARRAY:
		errors.append("free_skill_ids must be an Array")
	if typeof(config["stage_id"]) != TYPE_STRING or config["stage_id"].strip_edges().is_empty():
		errors.append("stage_id must be a non-empty string")
	var seen := {}
	for hero_id: Variant in config["deployed_hero_ids"]:
		if typeof(hero_id) != TYPE_INT or hero_id <= 0 or seen.has(hero_id):
			errors.append("deployed_hero_ids must contain unique positive integers")
			break
		seen[hero_id] = true
	for skill_id: Variant in config["free_skill_ids"]:
		if typeof(skill_id) != TYPE_STRING or skill_id.strip_edges().is_empty():
			errors.append("free_skill_ids must contain non-empty strings")
			break
	return errors.is_empty()
