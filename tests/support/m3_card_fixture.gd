class_name M3CardFixture
extends RefCounted

const BattleRuntimeScript = preload("res://systems/combat/battle_runtime.gd")
const BattleStateScript = preload("res://core/battle_state.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const CardCatalogScript = preload("res://data/catalogs/card_catalog.gd")
const HandRuntimeScript = preload("res://systems/cards/hand_runtime.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")


static func create(options: Dictionary = {}) -> Dictionary:
	var catalog_errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(catalog_errors)
	assert(catalog_errors.is_empty(), str(catalog_errors))
	var card_catalog := CardCatalogScript.build_from(
		catalogs["skills"], catalogs["hero_abilities"], catalog_errors
	)
	assert(catalog_errors.is_empty(), str(catalog_errors))
	var state := _state(float(options.get("sp", 10.0)), int(options.get("round", 3)))
	if options.has("deployed_hero_ids"):
		var deployed_ids: Array = options["deployed_hero_ids"]
		for hero: Dictionary in state["player_heroes"]:
			hero["deployed"] = hero["id"] in deployed_ids
	var hero_energy: Dictionary = options.get("hero_energy", {})
	for hero: Dictionary in state["player_heroes"]:
		if hero_energy.has(hero["id"]):
			hero["energy"] = float(hero_energy[hero["id"]])
	for slot: Variant in options.get("ally_banner_slots", []):
		state["allies"][int(slot) - 1]["class_id"] = "banner"
	for unit: Dictionary in state["allies"]:
		unit["atk"] = float(options.get("ally_attack", unit["atk"]))
	for unit: Dictionary in state["enemies"]:
		unit["hp"] = float(options.get("enemy_hp", unit["hp"]))
		unit["max_hp"] = maxf(unit["max_hp"], unit["hp"])
		unit["atk"] = float(options.get("enemy_attack", unit["atk"]))
	var metrics := {
		"content_events": [], "logs": [], "damage_records": [],
		"heal_records": [], "action_calls": 0,
	}
	var runtime_holder := {"runtime": null}
	var actions := {
		"emit_combat_event": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			return CombatPortsScript.ok(null),
		"emit_content_event": func(request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			metrics["content_events"].append(request.duplicate(true))
			if bool(options.get("fail_content_event", false)):
				return CombatPortsScript.fail("injected content event failure")
			if request["event_id"] == "roundEnd":
				for energy_request: Dictionary in options.get("round_end_energy_requests", []):
					var held_runtime: Variant = runtime_holder["runtime"].get_ref()
					var energy_result: Dictionary = held_runtime.apply_player_energy(
						energy_request
					)
					if not energy_result["ok"]:
						return energy_result
			return CombatPortsScript.ok(null),
		"log": func(request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			metrics["logs"].append(request.duplicate(true))
			if bool(options.get("fail_log", false)):
				return CombatPortsScript.fail("injected log failure")
			return CombatPortsScript.ok(null),
		"on_battle_resolved": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			return CombatPortsScript.ok(null),
		"record_damage": func(request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			metrics["damage_records"].append(request.duplicate(true))
			return CombatPortsScript.ok(null),
		"record_heal": func(request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			metrics["heal_records"].append(request.duplicate(true))
			return CombatPortsScript.ok(null),
		"resolve_battle_end": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			return CombatPortsScript.ok(bool(options.get("accept_battle_end", false))),
	}
	var combat_rng := RngScript.new(options.get("combat_seed", "m3-card-combat"))
	var enemy_rng := RngScript.new(options.get("enemy_seed", "m3-card-enemy"))
	var runtime_errors: Array[String] = []
	var runtime := BattleRuntimeScript.new({
		"state": state,
		"run_state": {"permanent_buffs": []},
		"catalogs": catalogs,
		"tuning": catalogs["tuning"],
		"combat_rng": combat_rng,
		"enemy_policy_rng": enemy_rng,
		"actions": actions,
		"relic_actions": {},
		"get_owned_relic_ids": func() -> Array:
			return options.get("owned_relic_ids", []).duplicate(true),
		"format_damage": func(value: float) -> float:
			return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return float(unit["base_block_rate"]),
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return 1.0,
		"on_damage_event": func(_event_id: String, _payload: Dictionary) -> void: pass,
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"on_buff_event": func(_event_id: String, _payload: Dictionary) -> void: pass,
		"on_burn_settled": func(_result: Dictionary) -> void: pass,
		"on_hook_error": func(_message: String, _metadata: Dictionary) -> void: pass,
	}, runtime_errors)
	assert(runtime_errors.is_empty(), str(runtime_errors))
	assert(runtime.is_valid())
	runtime_holder["runtime"] = weakref(runtime)
	var hand_runtime: Variant = null
	if bool(options.get("install_card_runtime", true)):
		hand_runtime = HandRuntimeScript.new(options.get("deck_seed", "m3-card-deck"))
		assert(runtime.install_player_card_runtime({
			"hand_runtime": hand_runtime,
			"card_catalog": card_catalog,
		}, runtime_errors), str(runtime_errors))
	return {
		"runtime": runtime, "hand": hand_runtime, "state": state,
		"catalogs": catalogs, "cards": card_catalog, "metrics": metrics,
		"combat_rng": combat_rng, "enemy_rng": enemy_rng,
	}


static func put_cards_in_hand(fixture: Dictionary, card_ids: Array) -> Array[String]:
	var definitions: Array = []
	for card_id: String in card_ids:
		definitions.append(fixture["cards"][card_id])
	var initialized: Variant = fixture["hand"].initialize_deck(definitions, false)
	assert(initialized.ok, initialized.message)
	var drawn: Variant = fixture["hand"].draw_cards(card_ids.size())
	assert(drawn.ok, drawn.message)
	return drawn.details["drawn_instance_ids"]


static func hero(state: Dictionary, hero_id: int) -> Dictionary:
	for value: Dictionary in state["player_heroes"]:
		if value["id"] == hero_id:
			return value
	assert(false)
	return {}


static func _state(sp: float, round_number: int) -> Dictionary:
	var errors: Array[String] = []
	var state := BattleStateScript.create({
		"round": round_number, "phase": "player_input",
		"sp": sp, "sp_max": 20.0, "base_sp_max": 20.0,
		"enemy_sp": 6.0, "enemy_sp_max": 6.0,
		"allies": _team("ally", 12.0), "enemies": _team("enemy", 4.0),
		"player_heroes": [
			_player_hero(2, "命途师", "fate", true, 120.0),
			_player_hero(3, "统帅", "ascend", true, 100.0),
			_player_hero(4, "骑士", "counterAura", true, 100.0),
			_player_hero(9, "影狩", "shadow", true, 100.0),
			_player_hero(1, "炎术士", "burn01", false, 100.0),
		],
		"enemy_heroes": [{
			"id": 101, "name": "敌弈者", "ex_skill": "counterAura",
			"skills": ["pieceBlock"], "skill_pool": ["basicDamage"],
			"energy": 0.0, "max_energy": 100.0, "base_crit_rate": 0.0,
			"fist_momentum": 0,
		}],
		"side_buffs": {"ally": [], "enemy": []},
		"fate": {
			"active": false, "mode": null, "cast_used": false, "chaos_used": false,
			"enemy_lock": null, "all_in_turns": 0, "roll_index": 0,
			"skill_sp_gain_this_round": 0,
		},
		"enemy_fate": {
			"active": false, "mode": null, "cast_used": false, "chaos_used": false,
			"ally_lock": null, "all_in_turns": 0,
			"skill_sp_gain_this_round": 0,
		},
		"battle_growth_flags": {"flame_investment_used": false},
		"burn_ex_cast_count": 0, "enemy_burn_ex_cast_count": 0,
		"counter_threshold": 4, "marshal_target_id": 1,
		"ally_puppet_martyr_active": false,
		"game_over": false, "battle_result": null,
	}, errors)
	assert(errors.is_empty(), str(errors))
	return state


static func _team(side: String, attack: float) -> Array:
	var result: Array = []
	for slot in range(1, 7):
		result.append({
			"id": slot, "slot": slot, "side": side,
			"class_id": "default", "class_name": "棋子",
			"hp": 100.0, "max_hp": 100.0, "atk": attack, "crit_rate": 0.0,
			"alive": true, "general": false, "base_block_rate": 0.0,
			"extra_action_charges": 0, "buffs": [], "is_puppet": false,
			"fixed_max_hp": null, "puppet_martyr": false, "disarm_turns": 0,
			"stealth_attack_ready": false, "special_id": null,
			"echo_damage_bonus": 0.0, "hp_threshold_crossed": false,
		})
	return result


static func _player_hero(
	id: int,
	name: String,
	ex_skill: String,
	deployed: bool,
	max_energy: float,
) -> Dictionary:
	return {
		"id": id, "name": name, "deployed": deployed, "ex_skill": ex_skill,
		"energy": 0.0, "max_energy": max_energy, "base_crit_rate": 0.0,
		"fist_momentum": 0,
	}
