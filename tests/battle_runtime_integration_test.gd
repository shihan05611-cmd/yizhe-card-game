extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const BattleRuntimeScript = preload("res://systems/combat/battle_runtime.gd")
const BattleStateScript = preload("res://core/battle_state.gd")
const DeterministicRngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const DamagePipelineScript = preload("res://core/damage.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const BurnSettlementScript = preload("res://systems/buffs/burn.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const GrowthPortScript = preload("res://systems/growth/growth_port.gd")
const HookDispatcherScript = preload("res://systems/relics/hook_dispatcher.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("catalogs and hero extensions compose one exact 33-handler authority graph", func() -> void:
		_test_authority_graph(harness)
	)
	harness.run_test("real registry effect and RoundResolver complete one deterministic round", func() -> void:
		_test_real_round(harness)
	)
	harness.run_test("GrowthPort action collision fails before every external boundary", func() -> void:
		_test_action_collision_atomic(harness)
	)
	harness.run_test("missing M1 handler authority fails without state run RNG hook or action commit", func() -> void:
		_test_missing_catalog_atomic(harness)
	)
	print("B4-3B BATTLE RUNTIME INTEGRATION TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_authority_graph(harness: TestHarness) -> void:
	var fixture := _fixture()
	var runtime: Variant = fixture["runtime"]
	harness.assert_true(runtime.is_valid(), str(fixture["errors"]))
	harness.assert_equal(runtime.handler_ids().size(), 33)
	var expected_ids := _catalog_handler_ids(fixture["catalogs"])
	harness.assert_equal(runtime.handler_ids(), expected_ids)
	harness.assert_equal(expected_ids.size(), 33)

	var ports: Variant = runtime.component("ports")
	harness.assert_true(ports.get_script() == CombatPortsScript)
	harness.assert_true(runtime.component("registry").get_script() == EffectRegistryScript)
	harness.assert_true(runtime.component("damage").get_script() == DamagePipelineScript)
	harness.assert_true(runtime.component("buffs").get_script() == BuffSystemScript)
	harness.assert_true(runtime.component("burn_settlement").get_script() == BurnSettlementScript)
	harness.assert_true(runtime.component("growth_port").get_script() == GrowthPortScript)
	harness.assert_true(runtime.component("hook_dispatcher").get_script() == HookDispatcherScript)
	harness.assert_true(runtime.component("relic_system").get_script() == RelicSystemScript)
	harness.assert_true(is_same(runtime.component("state"), fixture["state"]))
	harness.assert_true(is_same(runtime.component("run_state"), fixture["run_state"]))
	harness.assert_true(is_same(runtime.component("catalogs"), fixture["catalogs"]))
	harness.assert_true(is_same(runtime.component("tuning"), fixture["catalogs"]["tuning"]))
	harness.assert_true(is_same(runtime.component("combat_rng"), fixture["combat_rng"]))
	harness.assert_true(is_same(runtime.component("enemy_policy_rng"), fixture["policy_rng"]))
	harness.assert_false(is_same(runtime.component("combat_rng"), runtime.component("enemy_policy_rng")))

	var service_errors: Array[String] = []
	harness.assert_true(is_same(ports.service("damage", service_errors), runtime.component("damage")))
	harness.assert_true(is_same(ports.service("buffs", service_errors), runtime.component("buffs")))
	harness.assert_true(is_same(ports.service("relics", service_errors), runtime.component("relic_system")))
	harness.assert_true(service_errors.is_empty(), str(service_errors))
	var growth_snapshot: Dictionary = ports.call_action("snapshot_permanent_growth", {}, service_errors)
	harness.assert_true(growth_snapshot["ok"], str(growth_snapshot))
	harness.assert_equal(growth_snapshot["value"], fixture["run_state"]["permanent_buffs"])


func _test_real_round(harness: TestHarness) -> void:
	var fixture := _fixture()
	var runtime: Variant = fixture["runtime"]
	var result: Dictionary = runtime.resolve_round()
	harness.assert_true(result["ok"], str(result))
	if not result["ok"]:
		return
	var value: Dictionary = result["value"]
	harness.assert_equal(value["status"], "completed")
	harness.assert_equal(value["round_before"], 1)
	harness.assert_equal(value["round_after"], 2)
	harness.assert_equal(value["phase"], "player_input")
	harness.assert_equal(fixture["state"]["round"], 2)
	harness.assert_equal(fixture["state"]["phase"], "player_input")

	var hero_entries: Array = value["trace"].filter(func(entry: Dictionary) -> bool:
		return entry["phase"] == "enemy_yizhe" and entry["status"] == "cast"
	)
	harness.assert_equal(hero_entries.size(), 1)
	if hero_entries.size() == 1:
		harness.assert_equal(hero_entries[0]["result"]["skill_id"], "basicDamage")
		harness.assert_equal(hero_entries[0]["result"]["skill_kind"], "free")
	harness.assert_true(fixture["metrics"]["record_damage"] > 0)
	harness.assert_true(fixture["metrics"]["damage_events"] > 0)
	harness.assert_true(fixture["metrics"]["owned_queries"] > 0)
	harness.assert_true(fixture["metrics"]["relic_heals"] > 0)
	harness.assert_equal(_round_events(fixture["metrics"]["content_events"]), ["roundEnd", "roundStart"])
	harness.assert_true(_has_trace(value["trace"], "burn", "settled", "enemy"))
	harness.assert_true(_has_trace(value["trace"], "burn", "settled", "ally"))
	harness.assert_true(_has_trace(value["trace"], "finalize", "hook_reset", null))
	harness.assert_equal(value["m3_obligations"].size(), 3)
	var json_errors: Array[String] = []
	harness.assert_true(_json_safe(value, "result", [], json_errors), str(json_errors))
	for forbidden: String in [
		"acted", "freeSlots", "free_slots", "pending_ultimate",
		"pendingUltimate", "action_quota", "ultimate_decision",
	]:
		harness.assert_false(fixture["state"].has(forbidden))
		harness.assert_false(fixture["run_state"].has(forbidden))


func _test_action_collision_atomic(harness: TestHarness) -> void:
	var source := _fixture_inputs()
	var state_before: Dictionary = source["state"].duplicate(true)
	var run_before: Dictionary = source["run_state"].duplicate(true)
	var control_rng := DeterministicRngScript.new(1001)
	source["config"]["actions"][GrowthPortScript.ACTION_STAGE] = (
		func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null)
	)
	var errors: Array[String] = []
	var runtime := BattleRuntimeScript.new(source["config"], errors)
	harness.assert_false(runtime.is_valid())
	harness.assert_true(not errors.is_empty())
	harness.assert_contains(errors[0], "collides with owned GrowthPort action")
	_assert_zero_construction_commit(harness, source, state_before, run_before, control_rng)


func _test_missing_catalog_atomic(harness: TestHarness) -> void:
	var source := _fixture_inputs()
	var state_before: Dictionary = source["state"].duplicate(true)
	var run_before: Dictionary = source["run_state"].duplicate(true)
	var control_rng := DeterministicRngScript.new(1001)
	var broken: Dictionary = source["catalogs"].duplicate(false)
	broken["skills"] = source["catalogs"]["skills"].duplicate(false)
	broken["skills"].erase("basicDamage")
	source["config"]["catalogs"] = broken
	source["config"]["tuning"] = broken["tuning"]
	var errors: Array[String] = []
	var runtime := BattleRuntimeScript.new(source["config"], errors)
	harness.assert_false(runtime.is_valid())
	harness.assert_true(not errors.is_empty())
	harness.assert_contains(errors[0], "complete M1 authority")
	_assert_zero_construction_commit(harness, source, state_before, run_before, control_rng)


func _assert_zero_construction_commit(
	harness: TestHarness,
	source: Dictionary,
	state_before: Dictionary,
	run_before: Dictionary,
	control_rng: Variant,
) -> void:
	harness.assert_equal(source["state"], state_before)
	harness.assert_equal(source["run_state"], run_before)
	harness.assert_equal(source["metrics"]["action_calls"], 0)
	harness.assert_equal(source["metrics"]["owned_queries"], 0)
	harness.assert_equal(source["metrics"]["damage_events"], 0)
	harness.assert_equal(source["metrics"]["deaths"], 0)
	harness.assert_equal(source["metrics"]["buff_events"], 0)
	harness.assert_equal(source["metrics"]["burn_settled"], 0)
	harness.assert_equal(source["metrics"]["hook_errors"], 0)
	harness.assert_equal(source["metrics"]["relic_heals"], 0)
	harness.assert_equal(source["combat_rng"].next(), control_rng.next())


func _fixture() -> Dictionary:
	var source := _fixture_inputs()
	var errors: Array[String] = []
	var runtime := BattleRuntimeScript.new(source["config"], errors)
	source["runtime"] = runtime
	source["errors"] = errors
	return source


func _fixture_inputs() -> Dictionary:
	var catalog_errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(catalog_errors)
	assert(catalog_errors.is_empty(), str(catalog_errors))
	var state := _state()
	var run_state := {"permanent_buffs": []}
	var metrics := {
		"action_calls": 0, "content_events": [], "record_damage": 0,
		"damage_events": 0, "deaths": 0, "buff_events": 0,
		"burn_settled": 0, "hook_errors": 0, "owned_queries": 0,
		"relic_heals": 0,
	}
	var actions := {
		"emit_combat_event": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			return CombatPortsScript.ok(null),
		"emit_content_event": func(request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			metrics["content_events"].append(request.duplicate(true))
			return CombatPortsScript.ok(null),
		"log": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			return CombatPortsScript.ok(null),
		"on_battle_resolved": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			return CombatPortsScript.ok(null),
		"record_damage": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			metrics["record_damage"] += 1
			return CombatPortsScript.ok(null),
		"record_heal": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			return CombatPortsScript.ok(null),
		"resolve_battle_end": func(_request: Dictionary) -> Dictionary:
			metrics["action_calls"] += 1
			return CombatPortsScript.ok(true),
	}
	var combat_rng := DeterministicRngScript.new(1001)
	var policy_rng := DeterministicRngScript.new(2002)
	var config := {
		"state": state, "run_state": run_state,
		"catalogs": catalogs, "tuning": catalogs["tuning"],
		"combat_rng": combat_rng, "enemy_policy_rng": policy_rng,
		"actions": actions,
		"relic_actions": {
			"heal": func(target: Dictionary, amount: float, _source_id: String, _source_name: String) -> Dictionary:
				metrics["relic_heals"] += 1
				target["hp"] = minf(float(target["max_hp"]), float(target["hp"]) + amount)
				return CombatPortsScript.ok(null),
		},
		"get_owned_relic_ids": func() -> Array:
			metrics["owned_queries"] += 1
			return ["fieldBandage"],
		"format_damage": func(value: float) -> float:
			return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return float(unit["base_block_rate"]),
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return 1.0,
		"on_damage_event": func(_event_id: String, _payload: Dictionary) -> void:
			metrics["damage_events"] += 1,
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void:
			metrics["deaths"] += 1,
		"on_buff_event": func(_event_id: String, _payload: Dictionary) -> void:
			metrics["buff_events"] += 1,
		"on_burn_settled": func(_result: Dictionary) -> void:
			metrics["burn_settled"] += 1,
		"on_hook_error": func(_message: String, _metadata: Dictionary) -> void:
			metrics["hook_errors"] += 1,
	}
	return {
		"config": config, "catalogs": catalogs, "state": state,
		"run_state": run_state, "metrics": metrics,
		"combat_rng": combat_rng, "policy_rng": policy_rng,
	}


func _state() -> Dictionary:
	var source := {
		"round": 1, "phase": "player_input",
		"sp": 4.0, "sp_max": 6.0, "base_sp_max": 6.0,
		"enemy_sp": 4.0, "enemy_sp_max": 6.0,
		"allies": _team("ally", 0.0), "enemies": _team("enemy", 1.0),
		"player_heroes": [_player_hero(1)], "enemy_heroes": [_enemy_hero(2)],
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
		"burn_ex_cast_count": 0, "enemy_burn_ex_cast_count": 0,
		"counter_threshold": 4, "marshal_target_id": 1,
		"ally_puppet_martyr_active": false,
		"game_over": false, "battle_result": null,
	}
	var errors: Array[String] = []
	var state: Dictionary = BattleStateScript.create(source, errors)
	assert(errors.is_empty(), str(errors))
	return state


func _team(side: String, attack: float) -> Array:
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


func _player_hero(id: int) -> Dictionary:
	return {
		"id": id, "name": "我方弈者", "deployed": true, "ex_skill": "fate",
		"energy": 0.0, "max_energy": 100.0, "base_crit_rate": 0.0,
		"fist_momentum": 0,
	}


func _enemy_hero(id: int) -> Dictionary:
	return {
		"id": id, "name": "敌方弈者", "ex_skill": "counterAura",
		"skills": [], "skill_pool": ["basicDamage"],
		"energy": 0.0, "max_energy": 100.0, "base_crit_rate": 0.0,
		"fist_momentum": 0,
	}


func _catalog_handler_ids(catalogs: Dictionary) -> Array[String]:
	var ids: Array[String] = [
		"battle.castExclusiveSkill.pressOpening",
		"battle.castExclusiveSkill.puppetAttunement",
	]
	for definition: Variant in catalogs["skills"].values():
		ids.append(definition.effect_id)
	for group: String in ["exclusive", "ultimate"]:
		for definition: Variant in catalogs["hero_abilities"][group].values():
			ids.append(definition.handler_id)
	ids.sort()
	return ids


func _round_events(events: Array) -> Array:
	var result: Array = []
	for event: Dictionary in events:
		if event["event_id"] in ["roundEnd", "roundStart"]:
			result.append(event["event_id"])
	return result


func _has_trace(trace: Array, phase: String, status: String, side: Variant) -> bool:
	for entry: Dictionary in trace:
		if entry["phase"] == phase and entry["status"] == status and entry["side"] == side:
			return true
	return false


func _json_safe(value: Variant, path: String, seen: Array, errors: Array[String]) -> bool:
	if value == null or typeof(value) in [TYPE_STRING, TYPE_BOOL, TYPE_INT]:
		return true
	if typeof(value) == TYPE_FLOAT:
		if is_finite(value):
			return true
		errors.append("%s non-finite" % path)
		return false
	if typeof(value) not in [TYPE_ARRAY, TYPE_DICTIONARY]:
		errors.append("%s non-JSON" % path)
		return false
	for previous: Variant in seen:
		if is_same(previous, value):
			errors.append("%s shared" % path)
			return false
	seen.append(value)
	if typeof(value) == TYPE_ARRAY:
		for index in value.size():
			if not _json_safe(value[index], "%s[%d]" % [path, index], seen, errors):
				return false
		return true
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not _json_safe(value[key], "%s.%s" % [path, str(key)], seen, errors):
			return false
	return true
