extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const DamageScript = preload("res://core/damage.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const Rng = preload("res://core/rng.gd")


class FakeValidPorts:
	extends RefCounted

	func is_valid() -> bool:
		return true


class UnknownResourceNoSnapshot:
	extends Resource

	var payload: Array = []


class UnknownResourceSelfSnapshot:
	extends Resource

	var snapshot_calls := 0
	var payload: Dictionary = {}

	func snapshot() -> Resource:
		snapshot_calls += 1
		return self


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("canonical battle state maps M1 player and stage enemy runtime authorities", func() -> void:
		_test_state_create_snapshot(harness)
	)
	harness.run_test("battle state rejects closed-shape numeric hp slot side and id violations", func() -> void:
		_test_state_fail_closed(harness)
	)
	harness.run_test("enemy skill pool preserves explicit empty while rejecting malformed ids", func() -> void:
		_test_enemy_skill_pool_contract(harness)
	)
	harness.run_test("battle state excludes obsolete player action card UI and roguelike fields", func() -> void:
		_test_state_exclusions(harness)
	)
	harness.run_test("runtime state exposes mutable refs while snapshot is deeply isolated", func() -> void:
		_test_state_reference_boundary(harness)
	)
	harness.run_test("combat ports require separate RNG B0 B1 services and callable ids", func() -> void:
		_test_ports_shape(harness)
	)
	harness.run_test("combat ports allow only isolated explicit M1 Resource graphs", func() -> void:
		_test_ports_resource_allowlist(harness)
	)
	harness.run_test("combat ports accept only canonical structured results", func() -> void:
		_test_ports_results(harness)
	)
	harness.run_test("effect registry merges atomically rejects duplicates and sorts ids", func() -> void:
		_test_registry_atomic_order(harness)
	)
	harness.run_test("effect execution preserves registry on failure and rejects reentry", func() -> void:
		_test_registry_execution(harness)
	)
	print("B3-0 BATTLE CONTRACT TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_state_create_snapshot(harness: TestHarness) -> void:
	var source := _state()
	var errors: Array[String] = []
	var state: Dictionary = BattleStateScript.create(source, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(BattleStateScript.validate(state, errors))
	harness.assert_equal(errors, [])
	harness.assert_false(is_same(state, source))
	harness.assert_false(is_same(state["allies"], source["allies"]))
	harness.assert_equal(state["allies"].size(), 6)
	harness.assert_equal(state["enemies"].size(), 6)
	harness.assert_equal(state["player_heroes"].size(), 9)
	harness.assert_equal(state["enemy_heroes"].size(), 3)
	var content := _m1_content()
	harness.assert_equal(
		state["player_heroes"][0],
		_player_hero_from_m1(content["characters"]["players"][1]),
	)
	harness.assert_equal(
		state["enemy_heroes"][0],
		_enemy_hero_from_stage(content["stages"]["core"].enemy_yizhes[0]),
	)
	harness.assert_false(state["player_heroes"][0].has("skills"))
	harness.assert_false(state["enemy_heroes"][0].has("deployed"))
	harness.assert_equal(state["enemy_heroes"][0]["skill_pool"], ["pieceAction", "smallHeal", "pieceDamageUp"])
	harness.assert_equal(state["enemy_heroes"][0]["fist_momentum"], 0)
	state["enemy_heroes"][0]["fist_momentum"] = 1
	harness.assert_true(BattleStateScript.validate(state), "enemy fist momentum write must preserve canonical shape")
	var snapshot: Dictionary = BattleStateScript.snapshot(state, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(JSON.stringify(snapshot).length() > 0)
	harness.assert_equal(typeof(JSON.parse_string(JSON.stringify(snapshot))), TYPE_DICTIONARY)


func _test_state_fail_closed(harness: TestHarness) -> void:
	var invalid_cases := []
	var unknown := _state()
	unknown["ui"] = {}
	invalid_cases.append(unknown)
	var nan_state := _state()
	nan_state["allies"][0]["atk"] = NAN
	invalid_cases.append(nan_state)
	var hp_state := _state()
	hp_state["allies"][0]["hp"] = hp_state["allies"][0]["max_hp"] + 1
	invalid_cases.append(hp_state)
	var duplicate_slot := _state()
	duplicate_slot["allies"][1]["slot"] = 1
	invalid_cases.append(duplicate_slot)
	var duplicate_id := _state()
	duplicate_id["enemies"][1]["id"] = duplicate_id["enemies"][0]["id"]
	invalid_cases.append(duplicate_id)
	var wrong_side := _state()
	wrong_side["enemies"][0]["side"] = "ally"
	invalid_cases.append(wrong_side)
	var invalid_enemy_fist := _state()
	invalid_enemy_fist["enemy_heroes"][0]["fist_momentum"] = 6
	invalid_cases.append(invalid_enemy_fist)
	for candidate in invalid_cases:
		var before_text := str(candidate)
		var errors: Array[String] = []
		harness.assert_equal(BattleStateScript.create(candidate, errors), {})
		harness.assert_true(not errors.is_empty())
		harness.assert_equal(str(candidate), before_text, "validation must not mutate rejected state")


func _test_enemy_skill_pool_contract(harness: TestHarness) -> void:
	var source := _state()
	source["enemy_heroes"][0]["skill_pool"] = []
	var errors: Array[String] = []
	harness.assert_true(BattleStateScript.validate(source, errors))
	harness.assert_equal(errors, [])
	var state: Dictionary = BattleStateScript.create(source, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(state["enemy_heroes"][0]["skill_pool"], [])
	var snapshot: Dictionary = BattleStateScript.snapshot(state, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(snapshot["enemy_heroes"][0]["skill_pool"], [])
	snapshot["enemy_heroes"][0]["skill_pool"].append("snapshot-only")
	harness.assert_equal(state["enemy_heroes"][0]["skill_pool"], [])
	harness.assert_equal(source["enemy_heroes"][0]["skill_pool"], [])

	for invalid_pool in [42, [""], ["pieceAction", "pieceAction"]]:
		var invalid := _state()
		invalid["enemy_heroes"][0]["skill_pool"] = invalid_pool
		var before := str(invalid)
		errors.clear()
		harness.assert_false(BattleStateScript.validate(invalid, errors))
		harness.assert_true(not errors.is_empty())
		harness.assert_equal(str(invalid), before)


func _test_state_exclusions(harness: TestHarness) -> void:
	var player_forbidden_fields := [
		["acted", true],
		["free_slots", ["pieceAction"]],
		["pending_ultimate", {"hero_id": 1}],
		["skills", ["enemy-only"]],
		["skill_pool", ["enemy-only"]],
	]
	for pair in player_forbidden_fields:
		var candidate := _state()
		candidate["player_heroes"][0][pair[0]] = pair[1]
		var errors: Array[String] = []
		harness.assert_false(BattleStateScript.validate(candidate, errors))
		harness.assert_true(not errors.is_empty())
	var enemy_forbidden_fields := [
		["acted", true],
		["free_slots", ["pieceAction"]],
		["pending_ultimate", {"hero_id": 301}],
		["deployed", true],
	]
	for pair in enemy_forbidden_fields:
		var candidate := _state()
		candidate["enemy_heroes"][0][pair[0]] = pair[1]
		var errors: Array[String] = []
		harness.assert_false(BattleStateScript.validate(candidate, errors))
		harness.assert_true(not errors.is_empty())
	var pending_candidate := _state()
	pending_candidate["pending_ultimate"] = {"hero_id": 1}
	var pending_errors: Array[String] = []
	harness.assert_false(BattleStateScript.validate(pending_candidate, pending_errors))
	harness.assert_true(not pending_errors.is_empty())
	var valid := _state()
	for field in ["selected_yizhe_id", "ui", "logs", "damage_stats", "roguelike", "hand", "draw_pile"]:
		harness.assert_false(valid.has(field))
	for field in ["acted", "free_slots", "pending_ultimate", "shadow_ex_used_this_turn"]:
		harness.assert_false(valid["player_heroes"][0].has(field))
		harness.assert_false(valid["enemy_heroes"][0].has(field))
	harness.assert_false(valid["player_heroes"][0].has("skills"))
	harness.assert_false(valid["player_heroes"][0].has("skill_pool"))
	harness.assert_false(valid["enemy_heroes"][0].has("deployed"))


func _test_state_reference_boundary(harness: TestHarness) -> void:
	var state: Dictionary = BattleStateScript.create(_state())
	var unit: Dictionary = state["allies"][0]
	var hero: Dictionary = state["player_heroes"][0]
	unit["hp"] = 80.0
	hero["energy"] = 25.0
	harness.assert_equal(state["allies"][0]["hp"], 80.0)
	harness.assert_equal(state["player_heroes"][0]["energy"], 25.0)
	var snapshot: Dictionary = BattleStateScript.snapshot(state)
	snapshot["allies"][0]["hp"] = 1.0
	snapshot["enemy_heroes"][0]["skills"].append("snapshot-only")
	snapshot["enemy_heroes"][0]["skill_pool"].append("snapshot-only")
	snapshot["side_buffs"]["ally"].append({"id": "temp", "stacks": 1, "turns": 1, "layer_turns": []})
	harness.assert_equal(unit["hp"], 80.0)
	harness.assert_equal(state["enemy_heroes"][0]["skills"], ["棋子行动", "小回血"])
	harness.assert_equal(state["enemy_heroes"][0]["skill_pool"], ["pieceAction", "smallHeal", "pieceDamageUp"])
	harness.assert_equal(state["side_buffs"]["ally"], [])


func _test_ports_shape(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var authority_config := _port_config()
	var damage_authority: Variant = authority_config["services"]["damage"]
	var buff_authority: Variant = authority_config["services"]["buffs"]
	var combat_rng_authority: Variant = authority_config["services"]["combat_rng"]
	var tuning_ids: Array = authority_config["services"]["tuning"].keys()
	tuning_ids.sort()
	var tuning_id: Variant = tuning_ids[0]
	var source_tuning: Resource = authority_config["services"]["tuning"][tuning_id]
	var source_tuning_value: Variant = source_tuning.get("value")
	var source_player: Resource = authority_config["services"]["catalogs"]["characters"]["players"][1]
	var source_player_name: String = source_player.get("name")
	var source_stage: Resource = authority_config["services"]["catalogs"]["stages"]["core"]
	var source_pool: Array = source_stage.get("enemy_yizhes")[0]["free_skill_ids"].duplicate()
	var ports: Variant = CombatPortsScript.new(authority_config, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(ports.is_valid())
	harness.assert_equal(ports.action_ids(), CombatPortsScript.REQUIRED_ACTION_IDS)
	harness.assert_true(is_same(ports.service("combat_rng", errors), combat_rng_authority))
	harness.assert_true(is_same(ports.service("damage"), damage_authority))
	harness.assert_true(is_same(ports.service("buffs"), buff_authority))
	harness.assert_equal(errors, [])
	# Mutating original M1 Resources after construction cannot cross into ports.
	source_tuning.set("value", "source-mutated")
	source_player.set("name", "source-mutated")
	source_stage.get("enemy_yizhes")[0]["free_skill_ids"].append("source-mutated")
	var tuning_snapshot: Dictionary = ports.service("tuning")
	var catalogs_snapshot: Dictionary = ports.service("catalogs")
	var first_tuning: Resource = tuning_snapshot[tuning_id]
	var first_player: Resource = catalogs_snapshot["characters"]["players"][1]
	var first_stage: Resource = catalogs_snapshot["stages"]["core"]
	harness.assert_false(is_same(first_tuning, source_tuning))
	harness.assert_false(is_same(first_player, source_player))
	harness.assert_false(is_same(first_stage, source_stage))
	harness.assert_equal(first_tuning.get("value"), source_tuning_value)
	harness.assert_equal(first_player.get("name"), source_player_name)
	harness.assert_equal(first_stage.get("enemy_yizhes")[0]["free_skill_ids"], source_pool)
	# Every accessor call returns new Resource identities and recursively isolated
	# nested containers without changing the public Resource-shaped data contract.
	first_tuning.set("value", "returned-mutated")
	first_player.set("name", "returned-mutated")
	first_stage.get("enemy_yizhes")[0]["free_skill_ids"].append("returned-mutated")
	var second_tuning_snapshot: Dictionary = ports.service("tuning")
	var second_catalogs_snapshot: Dictionary = ports.service("catalogs")
	var second_tuning: Resource = second_tuning_snapshot[tuning_id]
	var second_player: Resource = second_catalogs_snapshot["characters"]["players"][1]
	var second_stage: Resource = second_catalogs_snapshot["stages"]["core"]
	harness.assert_false(is_same(second_tuning, first_tuning))
	harness.assert_false(is_same(second_player, first_player))
	harness.assert_false(is_same(second_stage, first_stage))
	harness.assert_equal(second_tuning.get("value"), source_tuning_value)
	harness.assert_equal(second_player.get("name"), source_player_name)
	harness.assert_equal(second_stage.get("enemy_yizhes")[0]["free_skill_ids"], source_pool)
	# Constructor/accessor also isolate Dictionary containers. Service Objects keep
	# identity so B0/B1/RNG remain the actual injected authorities.
	authority_config["services"]["tuning"].clear()
	authority_config["services"]["catalogs"].clear()
	tuning_snapshot = ports.service("tuning")
	catalogs_snapshot = ports.service("catalogs")
	harness.assert_true(not tuning_snapshot.is_empty())
	harness.assert_true(catalogs_snapshot.has("characters"))
	tuning_snapshot.clear()
	catalogs_snapshot.erase("characters")
	catalogs_snapshot["stages"].clear()
	harness.assert_true(not ports.service("tuning").is_empty())
	harness.assert_true(ports.service("catalogs").has("characters"))
	harness.assert_true(not ports.service("catalogs")["stages"].is_empty())
	var config := _port_config()
	config["services"].erase("damage")
	harness.assert_false(CombatPortsScript.validate(config, errors))
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("damage")))
	config = _port_config()
	config["services"]["enemy_policy_rng"] = config["services"]["combat_rng"]
	harness.assert_false(CombatPortsScript.validate(config, errors))
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("distinct")))
	config = _port_config()
	config["actions"].erase("record_heal")
	harness.assert_false(CombatPortsScript.validate(config, errors))
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("record_heal")))
	config = _port_config()
	config["services"]["tuning"] = {}
	harness.assert_false(CombatPortsScript.validate(config, errors))
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("tuning")))


func _test_ports_resource_allowlist(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var direct_unknown := UnknownResourceNoSnapshot.new()
	var direct_config := _port_config()
	direct_config["services"]["tuning"]["unknown"] = direct_unknown
	harness.assert_false(CombatPortsScript.validate(direct_config, errors))
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("allowlist")))
	var invalid_direct: Variant = CombatPortsScript.new(direct_config, errors)
	harness.assert_false(invalid_direct.is_valid())
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("allowlist")))

	# A duck-typed snapshot callback on an unknown Resource is never invoked,
	# including through Dictionary/Array nesting.
	var self_snapshot := UnknownResourceSelfSnapshot.new()
	self_snapshot.payload = {"nested": ["authored"]}
	var nested_config := _port_config()
	nested_config["services"]["catalogs"]["malicious"] = [
		{"resource": self_snapshot},
	]
	harness.assert_false(CombatPortsScript.validate(nested_config, errors))
	harness.assert_equal(self_snapshot.snapshot_calls, 0)
	var invalid_nested: Variant = CombatPortsScript.new(nested_config, errors)
	harness.assert_false(invalid_nested.is_valid())
	harness.assert_equal(self_snapshot.snapshot_calls, 0)

	# Unknown Resources are also rejected when hidden inside an allowlisted M1
	# Resource property graph; the unknown callback remains untouched.
	var property_config := _port_config()
	var stage: Resource = property_config["services"]["catalogs"]["stages"]["core"]
	stage.get("enemy_yizhes")[0]["unknown_resource"] = self_snapshot
	harness.assert_false(CombatPortsScript.validate(property_config, errors))
	harness.assert_equal(self_snapshot.snapshot_calls, 0)
	var invalid_property: Variant = CombatPortsScript.new(property_config, errors)
	harness.assert_false(invalid_property.is_valid())
	harness.assert_equal(self_snapshot.snapshot_calls, 0)

	# An allowlisted Resource may appear inside authored containers and remains
	# Resource-shaped, recursively isolated, and fresh on every service access.
	var known_config := _port_config()
	var tuning_ids: Array = known_config["services"]["tuning"].keys()
	tuning_ids.sort()
	var known_source: Resource = known_config["services"]["tuning"][tuning_ids[0]]
	known_config["services"]["catalogs"]["known_nested"] = [
		{"resource": known_source},
	]
	harness.assert_true(CombatPortsScript.validate(known_config, errors))
	harness.assert_equal(errors, [])
	var valid_ports: Variant = CombatPortsScript.new(known_config, errors)
	harness.assert_true(valid_ports.is_valid())
	harness.assert_equal(errors, [])
	var first: Resource = valid_ports.service("catalogs", errors)["known_nested"][0]["resource"]
	var second: Resource = valid_ports.service("catalogs", errors)["known_nested"][0]["resource"]
	harness.assert_equal(errors, [])
	harness.assert_false(is_same(first, known_source))
	harness.assert_false(is_same(second, known_source))
	harness.assert_false(is_same(first, second))
	harness.assert_equal(first.get_script(), known_source.get_script())


func _test_ports_results(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var ports: Variant = _ports({
		"emit_combat_event": func(request: Dictionary) -> Dictionary:
			return CombatPortsScript.ok(request.get("event")),
		"log": func(_request: Dictionary) -> Variant:
			return true,
		"record_damage": func(_request: Dictionary) -> Dictionary:
			return {"ok": true},
		"record_heal": func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.fail("rejected"),
	}, errors)
	harness.assert_true(ports.is_valid())
	harness.assert_equal(ports.call_action("emit_combat_event", {"event": "unit_died"}), CombatPortsScript.ok("unit_died"))
	var failed: Dictionary = ports.call_action("record_heal", {}, errors)
	harness.assert_equal(failed, CombatPortsScript.fail("rejected"))
	harness.assert_equal(errors, [], "canonical external failure is not a protocol error")
	harness.assert_false(ports.call_action("log", {}, errors)["ok"])
	harness.assert_true(errors[0].contains("non-canonical"))
	harness.assert_false(ports.call_action("record_damage", {}, errors)["ok"])
	harness.assert_true(errors[0].contains("non-canonical"))
	harness.assert_false(ports.call_action("missing", {}, errors)["ok"])
	harness.assert_true(not errors.is_empty())
	harness.assert_false(CombatPortsScript.is_result({"ok": false, "error": "", "extra": true}))
	harness.assert_false(CombatPortsScript.is_result({"ok": true}))


func _test_registry_atomic_order(harness: TestHarness) -> void:
	var registry: Variant = EffectRegistryScript.new()
	var handler_a := func(_context: Dictionary, _ports: Variant) -> Dictionary: return CombatPortsScript.ok("a")
	var handler_b := func(_context: Dictionary, _ports: Variant) -> Dictionary: return CombatPortsScript.ok("b")
	var handler_c := func(_context: Dictionary, _ports: Variant) -> Dictionary: return CombatPortsScript.ok("c")
	var errors: Array[String] = []
	harness.assert_true(registry.merge([{"effect.z": handler_c}, {"effect.a": handler_a}], errors))
	harness.assert_equal(errors, [])
	harness.assert_equal(registry.handler_ids(), ["effect.a", "effect.z"])
	var snapshot: Dictionary = registry.handlers_snapshot()
	snapshot.erase("effect.a")
	snapshot["effect.injected"] = handler_b
	harness.assert_equal(registry.handler_ids(), ["effect.a", "effect.z"])
	var before: Dictionary = registry.handlers_snapshot()
	harness.assert_false(registry.merge([{"effect.b": handler_b}, {"effect.a": handler_a}], errors))
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("duplicate")))
	harness.assert_equal(registry.handlers_snapshot(), before)
	harness.assert_false(registry.register_map({"": handler_b}, errors))
	harness.assert_equal(registry.handlers_snapshot(), before)
	harness.assert_false(registry.register_map({"effect.missing": Callable()}, errors))
	harness.assert_equal(registry.handlers_snapshot(), before)
	harness.assert_true(registry.get_handler("effect.a", errors).is_valid())
	harness.assert_false(registry.get_handler("missing", errors).is_valid())
	harness.assert_true(not errors.is_empty())


func _test_registry_execution(harness: TestHarness) -> void:
	var ports: Variant = _ports()
	var registry: Variant = EffectRegistryScript.new()
	var calls: Array = []
	var nested_results: Array = []
	var register_results: Array = []
	var ok_handler := func(context: Dictionary, received_ports: Variant) -> Dictionary:
		calls.append(context["value"])
		return received_ports.call_action("emit_combat_event", {"event": context["value"]})
	var invalid_handler := func(_context: Dictionary, _ports: Variant) -> Variant:
		return false
	var reentrant_handler := func(context: Dictionary, received_ports: Variant) -> Dictionary:
		var nested_errors: Array[String] = []
		var current_registry: Variant = context["registry"]
		nested_results.append(current_registry.execute("effect.ok", {"value": "nested"}, received_ports, nested_errors))
		register_results.append(current_registry.register_map({
			"effect.late": func(_c: Dictionary, _p: Variant) -> Dictionary: return CombatPortsScript.ok(null),
		}, nested_errors))
		return CombatPortsScript.ok("outer")
	var errors: Array[String] = []
	harness.assert_true(registry.register_map({
		"effect.ok": ok_handler,
		"effect.invalid": invalid_handler,
		"effect.reentrant": reentrant_handler,
	}, errors))
	harness.assert_equal(registry.execute("effect.ok", {"value": "hit"}, ports), CombatPortsScript.ok("hit"))
	harness.assert_equal(calls, ["hit"])
	var before_ids: Array[String] = registry.handler_ids()
	var fake_errors: Array[String] = []
	var fake_result: Dictionary = registry.execute(
		"effect.ok", {"value": "must-not-run"}, FakeValidPorts.new(), fake_errors,
	)
	harness.assert_false(fake_result["ok"])
	harness.assert_true(fake_errors[0].contains("CombatPorts"))
	harness.assert_equal(calls, ["hit"], "duck-typed is_valid object must not execute handler")
	harness.assert_equal(registry.handler_ids(), before_ids)
	harness.assert_false(registry.execute("effect.invalid", {}, ports, errors)["ok"])
	harness.assert_true(errors[0].contains("non-canonical"))
	harness.assert_equal(registry.handler_ids(), before_ids)
	harness.assert_true(registry.has("effect.invalid"), "failed execution must not consume its handler")
	harness.assert_equal(registry.execute("effect.reentrant", {"registry": registry}, ports), CombatPortsScript.ok("outer"))
	harness.assert_false(nested_results[0]["ok"])
	harness.assert_false(register_results[0])
	harness.assert_equal(registry.handler_ids(), before_ids)
	harness.assert_false(registry.execute("missing", {}, ports, errors)["ok"])
	harness.assert_equal(registry.handler_ids(), before_ids)


func _state() -> Dictionary:
	var content := _m1_content()
	return {
		"round": 1,
		"phase": "player_input",
		"sp": 4.0,
		"sp_max": 6.0,
		"base_sp_max": 6.0,
		"enemy_sp": 4.0,
		"enemy_sp_max": 6.0,
		"allies": _units("ally"),
		"enemies": _units("enemy"),
		"player_heroes": _player_heroes_from_m1(content["characters"]["players"]),
		"enemy_heroes": _enemy_heroes_from_stage(content["stages"]["core"]),
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


func _units(side: String) -> Array:
	var result: Array = []
	for slot in range(1, 7):
		var alive := side == "ally" or slot <= 3
		result.append({
			"id": slot,
			"slot": slot,
			"side": side,
			"class_id": "default",
			"class_name": "棋子" if alive else "空位",
			"hp": 100.0 if alive else 0.0,
			"max_hp": 100.0 if alive else 0.0,
			"atk": 20.0 if alive else 0.0,
			"crit_rate": 0.05,
			"alive": alive,
			"general": false,
			"base_block_rate": 0.1,
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
	return result


func _player_heroes_from_m1(catalog: Dictionary) -> Array:
	var result: Array = []
	var ids: Array = catalog.keys()
	ids.sort()
	for id in ids:
		result.append(_player_hero_from_m1(catalog[id]))
	return result


func _player_hero_from_m1(definition: Variant) -> Dictionary:
	return {
		"id": definition.id,
		"name": definition.name,
		"deployed": definition.deployed,
		"ex_skill": definition.exclusive_skill_id,
		"energy": definition.energy,
		"max_energy": definition.max_energy,
		"base_crit_rate": definition.base_crit_rate,
		"fist_momentum": definition.fist_momentum,
	}


func _enemy_heroes_from_stage(stage: Variant) -> Array:
	var result: Array = []
	for definition: Dictionary in stage.enemy_yizhes:
		result.append(_enemy_hero_from_stage(definition))
	return result


func _enemy_hero_from_stage(definition: Dictionary) -> Dictionary:
	return {
		"id": definition["id"],
		"name": definition["name"],
		"ex_skill": definition["exclusive_skill_id"],
		"skills": definition["source_skill_names"].duplicate(),
		"skill_pool": definition["free_skill_ids"].duplicate(),
		"energy": 0,
		"max_energy": definition["source_max_energy"],
		"base_crit_rate": definition["base_crit_rate"],
		# Web stage clone omits this JS-dynamic field, but battle.js reads/writes it
		# for enemy fist. Canonical Godot runtime initializes it explicitly.
		"fist_momentum": 0,
	}


func _m1_content() -> Dictionary:
	var errors: Array[String] = []
	var content: Dictionary = ContentCatalog.build(errors)
	assert(errors.is_empty())
	return content


func _ports(action_overrides: Dictionary = {}, errors: Array[String] = []) -> Variant:
	var config := _port_config()
	config["actions"].merge(action_overrides, true)
	return CombatPortsScript.new(config, errors)


func _port_config() -> Dictionary:
	var actions := {
		"emit_combat_event": func(request: Dictionary) -> Dictionary: return CombatPortsScript.ok(request.get("event")),
		"emit_content_event": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"log": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"on_battle_resolved": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_damage": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_heal": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"resolve_battle_end": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(true),
	}
	var damage_errors: Array[String] = []
	var damage := DamageScript.new({
		"random": func() -> float: return 0.5,
		"format": func(value: float) -> float: return value,
		"get_block_rate": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 0.0,
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 1.0,
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"record_damage": func(_payload: Dictionary) -> void: pass,
	}, damage_errors)
	assert(damage_errors.is_empty())
	var catalog_errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(catalog_errors)
	assert(catalog_errors.is_empty())
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": {"side_buffs": {"ally": [], "enemy": []}},
		"catalog": catalog["buffs"],
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
	}, buff_errors)
	assert(buff_errors.is_empty())
	return {
		"actions": actions,
		"services": {
			"combat_rng": Rng.seeded("B3-0-combat"),
			"enemy_policy_rng": Rng.seeded("B3-0-enemy-policy"),
			"damage": damage,
			"buffs": buffs,
			"tuning": catalog["tuning"],
			"catalogs": catalog,
		},
	}
