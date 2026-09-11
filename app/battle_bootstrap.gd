class_name BattleBootstrap
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const BattleRuntimeScript = preload("res://systems/combat/battle_runtime.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const RoguelikeRelicActionAdapterScript = preload("res://app/roguelike_relic_action_adapter.gd")
const RunBattleProgressScript = preload("res://systems/roguelike/run_battle_progress.gd")
const EnemySpecialSystemScript = preload("res://systems/enemy_specials/enemy_special_system.gd")
const BuffEffectsScript = preload("res://systems/buffs/buff_effects.gd")

const DIRECT_CONFIG_KEYS := ["battle_seed", "deployed_hero_ids", "free_skill_ids", "stage_id"]
const RUN_CONFIG_KEYS := DIRECT_CONFIG_KEYS + ["relic_ids", "encounter", "run_progress"]
const SHENTONG_EVOLUTION_RELIC_IDS := ["shentongAssaultBurst", "shentongChargeOverload"]
const RUN_ALLY_CLASS_BY_SLOT := {
	1: "shield", 2: "shield", 3: "shield",
	4: "assassin", 5: "crossbow", 6: "banner",
}
# Run layers share the counter-stage enemy roster. Layer progression controls
# how many already-authored enemy Yizhes are active; direct M4 starts keep the
# complete roster authored by their selected stage.
const RUN_ENEMY_HERO_IDS_BY_STAGE := {
	"counter": [101],
	"burn": [101, 102],
	"core": [101, 102, 103],
}
const RUN_ENEMY_HERO_SOURCE_STAGE := "counter"


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
	var run_mode: bool = config.has("run_progress")
	var relic_ids: Array = []
	var battle_draft := {"permanent_buffs": []}
	if run_mode:
		if not _validate_run_config(config, catalogs, errors):
			return {}
		relic_ids = config["relic_ids"].duplicate()
		battle_draft = config["run_progress"].runtime_draft_authority(errors)
		if not errors.is_empty():
			return {}
		# Legacy checkpoints retain the field for compatibility, never its bonuses.
		battle_draft["permanent_buffs"] = []
	var state := _build_state(config, catalogs, errors)
	if not errors.is_empty():
		return {}
	var relic_action_adapter := RoguelikeRelicActionAdapterScript.new(state)
	var streams := RngScript.create_named_streams(
		config["battle_seed"], ["combat", "enemyPolicy"]
	)
	if streams.is_empty():
		errors.append("battle RNG streams failed to initialize")
		return {}
	var runtime_errors: Array[String] = []
	# Damage callbacks execute after construction; bind the one authoritative
	# BuffSystem once the runtime has finished composing its components.
	var buff_holder := {}
	var runtime := BattleRuntimeScript.new({
		"state": state,
		"run_state": battle_draft,
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
		"relic_actions": relic_action_adapter.action_map(),
		"get_owned_relic_ids": func() -> Array: return relic_ids.duplicate(),
		"format_damage": func(value: float) -> float:
			return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return BuffEffectsScript.effective_block_rate(unit, buff_holder.get("value"), catalogs["tuning"]),
		"get_damage_multiplier": func(unit: Dictionary, context: Dictionary, metadata: Dictionary) -> float:
			var resolved := metadata.duplicate(true)
			if context.get("dealer_type") == "piece":
				var attacker_id: Variant = context.get("attacker_unit_id")
				var side: String = str(context.get("effect", {}).get("source_side", ""))
				for candidate: Dictionary in state["allies"] + state["enemies"]:
					if candidate["id"] == attacker_id and candidate["side"] == side:
						resolved["attacker_unit"] = candidate
						break
			return BuffEffectsScript.damage_multiplier(unit, context, resolved, buff_holder.get("value"), catalogs["tuning"]),
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
	buff_holder["value"] = runtime.component("buffs", errors)
	if not relic_action_adapter.bind_runtime(runtime, errors):
		return {}
	if not _install_enemy_specials(runtime, state, catalogs, streams["combat"], stream, errors):
		return {}
	if run_mode and not _apply_run_projection(
		state, runtime, config["run_progress"], battle_draft, catalogs, errors,
	):
		return {}
	return {
		"runtime": runtime,
		"state": state,
		"catalogs": catalogs,
		"deployed_hero_ids": config["deployed_hero_ids"].duplicate(),
		"free_skill_ids": config["free_skill_ids"].duplicate(),
		"exclusive_card_ids": config.get("exclusive_card_ids", []).duplicate(),
		"retained_card_keys": config.get("retained_card_keys", []).duplicate(),
		"battle_seed": config["battle_seed"],
		"run_progress": config.get("run_progress"),
		"relic_ids": relic_ids.duplicate(),
		"relic_action_adapter": relic_action_adapter,
	}


static func _install_enemy_specials(
	runtime: Variant, state: Dictionary, catalogs: Dictionary,
	rng: Variant, stream: Variant, errors: Array[String],
) -> bool:
	var has_special := false
	for enemy: Dictionary in state["enemies"]:
		if enemy.get("special_id") != null and bool(enemy["alive"]):
			has_special = true
	if not has_special:
		return true
	var specials := EnemySpecialSystemScript.new({
		"catalog": catalogs["enemy_specials"],
		"dispatcher": runtime.component("hook_dispatcher", errors),
		"get_enemies": func() -> Array: return state["enemies"],
		"get_active_heroes": func() -> Array:
			return state["player_heroes"].filter(func(hero: Dictionary) -> bool: return hero["deployed"]),
		"get_skill_points": func() -> float: return float(state["sp"]),
		"set_skill_points": func(value: float) -> Dictionary:
			state["sp"] = maxf(0.0, value)
			return CombatPortsScript.ok(true),
		"gain_hero_energy": func(hero: Dictionary, amount: float) -> Dictionary:
			# This port is the special monster's drain, not a player energy grant.
			hero["energy"] = clampf(float(hero["energy"]) + amount, 0.0, float(hero["max_energy"]))
			return CombatPortsScript.ok(true),
		"log": func(message: String, tone: String) -> void:
			stream.capture_log({"message": message, "tone": tone}),
		"on_triggered": func(payload: Dictionary) -> void:
			var event := payload.duplicate(true)
			event["event_id"] = "enemySpecialTriggered"
			stream.capture_combat(event),
		"rng": rng,
	}, errors)
	if not errors.is_empty() or not specials.is_valid():
		return false
	# Godot method Callables are weak: the composition owner must retain the
	# special system, which itself deliberately does not retain the dispatcher.
	runtime.set_meta("enemy_special_system", specials)
	return true


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
	var enemy_definitions := _enemy_yizhe_definitions(config, catalogs, stage, errors)
	if not errors.is_empty():
		return {}
	var enemy_heroes: Array[Dictionary] = []
	for enemy: Dictionary in enemy_definitions:
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
		"sp": 4.0,
		"sp_max": 4.0,
		"base_sp_max": 4.0,
		"enemy_sp": 6.0,
		"enemy_sp_max": 6.0,
		"allies": _run_allies(catalogs, config["run_progress"], errors) if config.has("run_progress") else _team("ally", catalogs),
		"enemies": _encounter_team(config["encounter"], catalogs) if config.has("encounter") else _team("enemy", catalogs),
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
	if not errors.is_empty():
		return {}
	var state_errors: Array[String] = []
	var state: Dictionary = BattleStateScript.create(source, state_errors)
	if not state_errors.is_empty():
		errors.append("battle state failed: %s" % state_errors[0])
	return state


static func _enemy_yizhe_definitions(
	config: Dictionary, catalogs: Dictionary, stage: Variant, errors: Array[String]
) -> Array:
	if not config.has("run_progress"):
		return stage.enemy_yizhes.duplicate(true)
	var expected_ids: Variant = RUN_ENEMY_HERO_IDS_BY_STAGE.get(config["stage_id"])
	var source_stage: Variant = catalogs["stages"].get(RUN_ENEMY_HERO_SOURCE_STAGE)
	if typeof(expected_ids) != TYPE_ARRAY or source_stage == null:
		errors.append("Run enemy Yizhe layer configuration is unavailable")
		return []
	var definitions_by_id := {}
	for raw_enemy: Variant in source_stage.enemy_yizhes:
		if typeof(raw_enemy) == TYPE_DICTIONARY:
			definitions_by_id[raw_enemy.get("id")] = raw_enemy
	var selected: Array = []
	for hero_id: Variant in expected_ids:
		if not definitions_by_id.has(hero_id):
			errors.append("Run enemy Yizhe layer references missing hero %s" % str(hero_id))
			return []
		selected.append(definitions_by_id[hero_id].duplicate(true))
	return selected


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
			"general": false,
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


static func _run_allies(catalogs: Dictionary, progress: Variant, errors: Array[String]) -> Array[Dictionary]:
	errors.clear()
	var formation: Array = progress.formation_slots(errors)
	if not errors.is_empty() or formation.size() != 6:
		if errors.is_empty():
			errors.append("Run formation projection must contain six slots")
		return []
	var class_by_slot := {}
	for entry: Dictionary in formation:
		class_by_slot[entry["slot"]] = entry["piece_class_id"]
	var units := _team("ally", catalogs)
	var base_block := _tuning(catalogs, "allyBaseBlock")
	var base_crit := _tuning(catalogs, "allyBaseCrit")
	for unit: Dictionary in units:
		var requested: Variant = class_by_slot.get(unit["slot"])
		var class_id: String = "default" if requested == null else requested
		var definition: Variant = catalogs["piece_classes"][class_id]
		unit["class_id"] = definition.id
		unit["class_name"] = definition.name
		unit["hp"] = 0.0 if requested == null else float(definition.hp)
		unit["max_hp"] = float(definition.hp)
		unit["atk"] = float(definition.attack)
		unit["base_block_rate"] = base_block + float(definition.block_bonus)
		unit["crit_rate"] = base_crit + float(definition.crit_bonus)
		unit["alive"] = requested != null
	return units


static func _encounter_team(encounter: Dictionary, catalogs: Dictionary) -> Array[Dictionary]:
	var units := _team("enemy", catalogs)
	for slot: Dictionary in encounter["slots"]:
		var unit: Dictionary = units[slot["unit_id"] - 1]
		var class_id: String = "default" if slot["piece_class_id"] == null else slot["piece_class_id"]
		var class_definition: Variant = catalogs["piece_classes"][class_id]
		unit["class_id"] = class_id
		unit["class_name"] = slot["class_name"]
		unit["base_block_rate"] += float(class_definition.block_bonus)
		unit["crit_rate"] += float(class_definition.crit_bonus)
		unit["special_id"] = slot["special_id"]
		if slot["empty"]:
			unit["hp"] = 0.0
			unit["max_hp"] = 0.0
			unit["atk"] = 0.0
			unit["alive"] = false
			continue
		unit["max_hp"] = _format_damage(_tuning(catalogs, "enemyBaseHp") * float(slot["total_hp_scale"]))
		unit["hp"] = unit["max_hp"]
		unit["atk"] = _format_damage(_tuning(catalogs, "enemyBaseAtk") * float(slot["total_atk_scale"]))
	return units


static func _apply_run_projection(
	state: Dictionary,
	runtime: Variant,
	progress: Variant,
	_battle_draft: Dictionary,
	_catalogs: Dictionary,
	errors: Array[String],
) -> bool:
	var relic_system: Variant = runtime.component("relic_system", errors)
	if not errors.is_empty():
		return false
	state["sp_max"] = maxf(0.0, float(state["base_sp_max"]) + relic_system.get_skill_point_max_adjustment())
	state["sp"] = state["sp_max"]
	for unit: Dictionary in state["allies"]:
		unit["max_hp"] += relic_system.get_class_max_hp_adjustment(unit["class_id"], "ally")
		if unit["max_hp"] <= 0.0:
			errors.append("Run relic projection produced non-positive ally max HP")
			return false
		unit["hp"] = unit["max_hp"] if unit["alive"] else 0.0
	var projected: Array = progress.project_allies(state["allies"], errors)
	if not errors.is_empty():
		return false
	state["allies"] = projected
	return BattleStateScript.validate(state, errors)


static func _tuning(catalogs: Dictionary, id: String) -> float:
	return float(catalogs["tuning"][id].value)


static func _validate_config(config: Variant, errors: Array[String]) -> bool:
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("battle bootstrap config must have a canonical closed shape")
		return false
	var expected: Array = (RUN_CONFIG_KEYS if config.has("run_progress") else DIRECT_CONFIG_KEYS).duplicate()
	if config.has("exclusive_card_ids"):
		expected.append("exclusive_card_ids")
	if config.has("retained_card_keys"):
		expected.append("retained_card_keys")
	if config.size() != expected.size():
		errors.append("battle bootstrap config must have a canonical closed shape")
		return false
	for key: String in expected:
		if not config.has(key):
			errors.append("battle bootstrap config.%s is required" % key)
	for key: Variant in config:
		if typeof(key) != TYPE_STRING or key not in expected:
			errors.append("battle bootstrap config contains an unknown field")
	if not errors.is_empty():
		return false
	if typeof(config["deployed_hero_ids"]) != TYPE_ARRAY or config["deployed_hero_ids"].is_empty():
		errors.append("deployed_hero_ids must be a non-empty Array")
	if typeof(config["free_skill_ids"]) != TYPE_ARRAY:
		errors.append("free_skill_ids must be an Array")
	if typeof(config.get("exclusive_card_ids", [])) != TYPE_ARRAY:
		errors.append("exclusive_card_ids must be an Array")
		return false
	if typeof(config.get("retained_card_keys", [])) != TYPE_ARRAY:
		errors.append("retained_card_keys must be an Array")
		return false
	var retained_seen := {}
	for key: Variant in config.get("retained_card_keys", []):
		if typeof(key) != TYPE_STRING or key.is_empty() or key != key.strip_edges() or retained_seen.has(key):
			errors.append("retained_card_keys must contain unique non-empty trimmed strings")
			return false
		retained_seen[key] = true
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


static func _validate_run_config(
	config: Dictionary,
	catalogs: Dictionary,
	errors: Array[String],
) -> bool:
	if (
		typeof(config["relic_ids"]) != TYPE_ARRAY
		or typeof(config["encounter"]) != TYPE_DICTIONARY
		or config["run_progress"] == null
		or config["run_progress"].get_script() != RunBattleProgressScript
		or config["run_progress"].status() != "open"
	):
		errors.append("Run battle bootstrap requires relics, encounter, and one open progress session")
		return false
	var seen := {}
	for relic_id: Variant in config["relic_ids"]:
		if (
			typeof(relic_id) != TYPE_STRING
			or not catalogs["relics"].has(relic_id)
			or seen.has(relic_id)
			or relic_id in SHENTONG_EVOLUTION_RELIC_IDS
			or catalogs["relics"][relic_id].category == "shentongEvolve"
		):
			errors.append("Run battle relic ids must be unique known non-shentong relics")
			return false
		seen[relic_id] = true
	var encounter: Dictionary = config["encounter"]
	if encounter.size() != 5:
		errors.append("Run battle encounter must keep the authoritative M5 shape")
		return false
	for field in ["id", "name", "hp_scale", "atk_scale", "slots"]:
		if not encounter.has(field):
			errors.append("Run battle encounter must keep the authoritative M5 shape")
			return false
	if (
		typeof(encounter["slots"]) != TYPE_ARRAY
		or encounter["slots"].size() != 6
	):
		errors.append("Run battle encounter must keep the authoritative M5 shape")
		return false
	for slot: Dictionary in encounter["slots"]:
		var class_id: Variant = slot.get("piece_class_id")
		if class_id != null and not catalogs["piece_classes"].has(class_id):
			errors.append("Run battle encounter references an unknown piece class")
			return false
	return true


static func _format_damage(value: float) -> float:
	return maxf(0.0, roundf(value * 10.0) / 10.0)


static func _marshal_tuning(catalogs: Dictionary) -> Dictionary:
	var result := {}
	for id in [
		"ascendAtkBonus", "ascendHpBonus", "ascendBlockBonus",
		"ascendRepeatAtkBonus", "ascendRepeatBlockBonus", "ascendRepeatCritBonus",
		"ascendRepeatMissingHpHealRatio",
	]:
		if catalogs["tuning"].has(id):
			result[id] = catalogs["tuning"][id].value
	return result
