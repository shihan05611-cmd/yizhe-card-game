extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const OutcomeScript = preload("res://systems/combat/battle_outcome.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")


class FixedRng:
	extends RefCounted
	func next() -> float: return 0.0
	func int_range(minimum: int, _maximum: int) -> int: return minimum
	func pick(items: Array) -> Variant: return null if items.is_empty() else items[0]


class DamageStub:
	extends RefCounted
	func is_valid() -> bool: return true
	func apply(_target: Variant, _context: Variant, _metadata: Variant = {}, errors: Array[String] = []) -> Dictionary:
		errors.clear()
		return {}
	func kill(_target: Variant, _context: Variant = {}, errors: Array[String] = []) -> Dictionary:
		errors.clear()
		return {}


class ThrowingDuckPorts:
	extends RefCounted
	var calls := 0
	func is_valid() -> bool: return true
	func call_action(_id: Variant, _request: Variant = {}, _errors: Array[String] = []) -> Dictionary:
		calls += 1
		assert(false, "duck-typed throw boundary must never be entered")
		return {"ok": true, "value": true}


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("living effective units return canonical none with zero actions", func() -> void:
		_test_non_terminal(harness)
	)
	harness.run_test("ally effective wipe settles lose after accepted resolve", func() -> void:
		_test_single_wipe(harness, "ally", "lose")
	)
	harness.run_test("enemy effective wipe settles win after accepted resolve", func() -> void:
		_test_single_wipe(harness, "enemy", "win")
	)
	harness.run_test("puppet-only teams do not count as effective combat units", func() -> void:
		_test_puppet_only(harness)
	)
	harness.run_test("current_web_compat_simultaneous_wipe_is_win is explicit and tested", func() -> void:
		_test_simultaneous_wipe(harness)
	)
	harness.run_test("already settled state is idempotent and performs no action", func() -> void:
		_test_already_settled(harness)
	)
	harness.run_test("resolve rejection non-acceptance and malformed result preserve unsettled state", func() -> void:
		_test_resolve_failures(harness)
	)
	harness.run_test("post-commit log and notification failures never repeat external settlement", func() -> void:
		_test_post_commit_failures(harness)
	)
	harness.run_test("malformed state fake ports and throw boundary fail closed before actions", func() -> void:
		_test_strict_boundaries(harness)
	)
	print("B4-3A BATTLE OUTCOME TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_non_terminal(harness: TestHarness) -> void:
	var state := _state()
	var before := BattleStateScript.snapshot(state)
	var kit := _kit(state)
	var result := OutcomeScript.check(state, kit["ports"])
	harness.assert_equal(result, CombatPortsScript.ok({"status": "none", "result": null, "committed": false}))
	harness.assert_equal(state, before)
	harness.assert_equal(kit["metrics"]["order"], [])
	harness.assert_equal(OutcomeScript.candidate(state), null)


func _test_single_wipe(harness: TestHarness, wiped_side: String, expected: String) -> void:
	var state := _state()
	var team_key := "allies" if wiped_side == "ally" else "enemies"
	_kill_effective_team(state[team_key])
	var kit := _kit(state)
	var result := OutcomeScript.check(state, kit["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_equal(result["value"], {"status": "settled", "result": expected, "committed": true})
	harness.assert_true(state["game_over"])
	harness.assert_equal(state["battle_result"], expected)
	harness.assert_equal(kit["metrics"]["order"], ["resolve", "log", "on_resolved"])
	harness.assert_equal(kit["metrics"]["requests"][0], {"result": expected})
	harness.assert_equal(kit["metrics"]["requests"][2], {"result": expected})
	var expected_class := "bad" if expected == "lose" else "ok"
	harness.assert_equal(kit["metrics"]["requests"][1]["class"], expected_class)


func _test_puppet_only(harness: TestHarness) -> void:
	var ally_state := _state()
	_kill_effective_team(ally_state["allies"])
	ally_state["allies"][0]["alive"] = true
	ally_state["allies"][0]["hp"] = 100.0
	ally_state["allies"][0]["is_puppet"] = true
	var ally_kit := _kit(ally_state)
	harness.assert_equal(OutcomeScript.check(ally_state, ally_kit["ports"])["value"]["result"], "lose")

	var enemy_state := _state()
	_kill_effective_team(enemy_state["enemies"])
	enemy_state["enemies"][0]["alive"] = true
	enemy_state["enemies"][0]["hp"] = 100.0
	enemy_state["enemies"][0]["is_puppet"] = true
	var enemy_kit := _kit(enemy_state)
	harness.assert_equal(OutcomeScript.check(enemy_state, enemy_kit["ports"])["value"]["result"], "win")


func _test_simultaneous_wipe(harness: TestHarness) -> void:
	harness.assert_true(OutcomeScript.CURRENT_WEB_COMPAT_SIMULTANEOUS_WIPE_IS_WIN)
	var state := _state()
	_kill_effective_team(state["allies"])
	_kill_effective_team(state["enemies"])
	var kit := _kit(state)
	var result := OutcomeScript.check(state, kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["result"], "win")
	harness.assert_equal(state["battle_result"], "win")
	harness.assert_equal(kit["metrics"]["requests"][0], {"result": "win"})


func _test_already_settled(harness: TestHarness) -> void:
	var state := _state()
	state["game_over"] = true
	state["battle_result"] = "lose"
	var before := BattleStateScript.snapshot(state)
	var kit := _kit(state)
	var result := OutcomeScript.check(state, kit["ports"])
	harness.assert_equal(result, CombatPortsScript.ok({"status": "already_settled", "result": "lose", "committed": true}))
	harness.assert_equal(state, before)
	harness.assert_equal(kit["metrics"]["order"], [])


func _test_resolve_failures(harness: TestHarness) -> void:
	for mode in ["reject", "not_accepted", "bad_result"]:
		var state := _state()
		_kill_effective_team(state["enemies"])
		var before := BattleStateScript.snapshot(state)
		var kit := _kit(state, {"resolve_mode": mode})
		var result := OutcomeScript.check(state, kit["ports"])
		harness.assert_false(result["ok"])
		harness.assert_equal(state, before)
		harness.assert_equal(kit["metrics"]["order"], ["resolve"])
		harness.assert_equal(kit["metrics"]["requests"], [{"result": "win"}])
	var accepted_state := _state()
	_kill_effective_team(accepted_state["enemies"])
	var accepted_kit := _kit(accepted_state, {"resolve_mode": "accepted_dict"})
	harness.assert_true(OutcomeScript.check(accepted_state, accepted_kit["ports"])["ok"])


func _test_post_commit_failures(harness: TestHarness) -> void:
	for failed_action in ["log", "on_resolved"]:
		var state := _state()
		_kill_effective_team(state["enemies"])
		var kit := _kit(state, {"fail_action": failed_action})
		var result := OutcomeScript.check(state, kit["ports"])
		harness.assert_false(result["ok"])
		harness.assert_contains(result["error"], "committed=win")
		harness.assert_true(state["game_over"])
		harness.assert_equal(state["battle_result"], "win")
		var expected_order := ["resolve", "log"] if failed_action == "log" else ["resolve", "log", "on_resolved"]
		harness.assert_equal(kit["metrics"]["order"], expected_order)
		var calls_before: Array = kit["metrics"]["order"].duplicate()
		var retry := OutcomeScript.check(state, kit["ports"])
		harness.assert_true(retry["ok"])
		harness.assert_equal(retry["value"]["status"], "already_settled")
		harness.assert_equal(kit["metrics"]["order"], calls_before)


func _test_strict_boundaries(harness: TestHarness) -> void:
	var malformed := _state()
	malformed["unexpected"] = true
	var valid_state := _state()
	var kit := _kit(valid_state)
	var malformed_result := OutcomeScript.check(malformed, kit["ports"])
	harness.assert_false(malformed_result["ok"])
	harness.assert_equal(kit["metrics"]["order"], [])

	_kill_effective_team(valid_state["enemies"])
	var duck := ThrowingDuckPorts.new()
	var before := BattleStateScript.snapshot(valid_state)
	var fake_result := OutcomeScript.check(valid_state, duck)
	harness.assert_false(fake_result["ok"])
	harness.assert_contains(fake_result["error"], "exact valid CombatPorts")
	harness.assert_equal(duck.calls, 0)
	harness.assert_equal(valid_state, before)


func _kit(state: Dictionary, options: Dictionary = {}) -> Dictionary:
	var catalog_errors: Array[String] = []
	var catalog := ContentCatalogScript.build(catalog_errors)
	assert(catalog_errors.is_empty(), str(catalog_errors))
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": state, "catalog": catalog["buffs"],
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
	}, buff_errors)
	assert(buff_errors.is_empty(), str(buff_errors))
	var metrics := {"order": [], "requests": []}
	var resolve_mode: String = options.get("resolve_mode", "accept")
	var fail_action: String = options.get("fail_action", "")
	var actions := {
		"emit_combat_event": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"emit_content_event": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"log": func(request: Dictionary) -> Dictionary:
			metrics["order"].append("log")
			metrics["requests"].append(request.duplicate(true))
			return CombatPortsScript.fail("injected log failure") if fail_action == "log" else CombatPortsScript.ok(null),
		"on_battle_resolved": func(request: Dictionary) -> Dictionary:
			metrics["order"].append("on_resolved")
			metrics["requests"].append(request.duplicate(true))
			return CombatPortsScript.fail("injected notification failure") if fail_action == "on_resolved" else CombatPortsScript.ok(null),
		"record_damage": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_heal": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"resolve_battle_end": func(request: Dictionary) -> Variant:
			metrics["order"].append("resolve")
			metrics["requests"].append(request.duplicate(true))
			if resolve_mode == "reject": return CombatPortsScript.fail("injected resolve rejection")
			if resolve_mode == "not_accepted": return CombatPortsScript.ok(false)
			if resolve_mode == "accepted_dict": return CombatPortsScript.ok({"accepted": true})
			if resolve_mode == "bad_result": return {"ok": true}
			return CombatPortsScript.ok(true),
	}
	var port_errors: Array[String] = []
	var ports := CombatPortsScript.new({
		"actions": actions,
		"services": {
			"combat_rng": FixedRng.new(), "enemy_policy_rng": FixedRng.new(),
			"damage": DamageStub.new(), "buffs": buffs,
			"tuning": catalog["tuning"], "catalogs": catalog,
		},
	}, port_errors)
	assert(port_errors.is_empty(), str(port_errors))
	return {"ports": ports, "metrics": metrics}


func _state() -> Dictionary:
	var source := {
		"round": 1, "phase": "resolution",
		"sp": 4.0, "sp_max": 6.0, "base_sp_max": 6.0,
		"enemy_sp": 4.0, "enemy_sp_max": 6.0,
		"allies": _team("ally"), "enemies": _team("enemy"),
		"player_heroes": [], "enemy_heroes": [],
		"side_buffs": {"ally": [], "enemy": []},
		"fate": {"active": false, "mode": null, "cast_used": false, "chaos_used": false, "enemy_lock": null, "all_in_turns": 0, "roll_index": 0, "skill_sp_gain_this_round": 0},
		"enemy_fate": {"active": false, "mode": null, "cast_used": false, "chaos_used": false, "ally_lock": null, "all_in_turns": 0, "skill_sp_gain_this_round": 0},
		"battle_growth_flags": {"flame_investment_used": false},
		"burn_ex_cast_count": 0, "enemy_burn_ex_cast_count": 0,
		"counter_threshold": 4, "marshal_target_id": 1,
		"ally_puppet_martyr_active": false,
		"game_over": false, "battle_result": null,
	}
	var errors: Array[String] = []
	var state := BattleStateScript.create(source, errors)
	assert(errors.is_empty(), str(errors))
	return state


func _team(side: String) -> Array:
	var result: Array = []
	for slot in range(1, 7):
		result.append({
			"id": slot, "slot": slot, "side": side,
			"class_id": "default", "class_name": "棋子",
			"hp": 100.0, "max_hp": 100.0, "atk": 10.0, "crit_rate": 0.05,
			"alive": true, "general": false, "base_block_rate": 0.1,
			"extra_action_charges": 0, "buffs": [], "is_puppet": false,
			"fixed_max_hp": null, "puppet_martyr": false, "disarm_turns": 0,
			"stealth_attack_ready": false, "special_id": null,
			"echo_damage_bonus": 0.0, "hp_threshold_crossed": false,
		})
	return result


func _kill_effective_team(team: Array) -> void:
	for unit: Dictionary in team:
		unit["hp"] = 0.0
		unit["alive"] = false
