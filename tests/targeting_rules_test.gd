extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const TargetingRulesScript = preload("res://systems/targeting/targeting_rules.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("alive and lockable candidates are stable and use B1 stealth state", func() -> void:
		_test_alive_lockable(harness)
	)
	harness.run_test("HP percentage and current HP selectors preserve each Web tie-break", func() -> void:
		_test_hp_selectors(harness)
	)
	harness.run_test("highest ATK and highest current HP ignore dead units and tie by id", func() -> void:
		_test_highest_selectors(harness)
	)
	harness.run_test("burn selectors use B1 layer stacks and their distinct skill tie-breaks", func() -> void:
		_test_burn_selectors(harness)
	)
	harness.run_test("lane mapping and priority match Web front then back order", func() -> void:
		_test_lane_priority(harness)
	)
	harness.run_test("lane target and both column helpers use canonical slots without stealth filtering", func() -> void:
		_test_positional_targets(harness)
	)
	harness.run_test("random target surface returns only a deterministic candidate pool", func() -> void:
		_test_random_candidates(harness)
	)
	harness.run_test("invalid closed shape numeric side and slot inputs fail before mutation", func() -> void:
		_test_fail_closed(harness)
	)
	print("B3-1 TARGETING RULES TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_alive_lockable(harness: TestHarness) -> void:
	var state := _state()
	state["enemies"] = [
		_unit_at(state, "enemy", 4), _unit_at(state, "enemy", 2),
		_unit_at(state, "enemy", 6), _unit_at(state, "enemy", 1),
		_unit_at(state, "enemy", 5), _unit_at(state, "enemy", 3),
	]
	_kill(_unit_at(state, "enemy", 2))
	_unit_at(state, "enemy", 3)["buffs"] = [_buff("stealth")]
	var before := str(state)
	var errors: Array[String] = []
	harness.assert_equal(_ids(TargetingRulesScript.alive(state, "enemy", errors)), [1, 3, 4, 5, 6])
	harness.assert_equal(errors, [])
	harness.assert_equal(_ids(TargetingRulesScript.lockable(state, "enemy", errors)), [1, 4, 5, 6])
	harness.assert_true(TargetingRulesScript.is_alive_at_slot(state, "enemy", 3, errors))
	harness.assert_false(TargetingRulesScript.is_alive_at_slot(state, "enemy", 2, errors))
	harness.assert_false(TargetingRulesScript.is_lockable_at_slot(state, "enemy", 3, errors))
	harness.assert_true(TargetingRulesScript.is_lockable_at_slot(state, "enemy", 4, errors))
	harness.assert_equal(errors, [])
	harness.assert_equal(str(state), before, "target queries must not mutate canonical snapshots")


func _test_hp_selectors(harness: TestHarness) -> void:
	var state := _state()
	_set_hp(state, "enemy", 1, 40.0, 100.0)
	_set_hp(state, "enemy", 2, 20.0, 50.0)
	_set_hp(state, "enemy", 3, 5.0, 25.0)
	_unit_at(state, "enemy", 3)["buffs"] = [_buff("stealth")]
	_set_hp(state, "enemy", 4, 60.0, 100.0)
	_set_hp(state, "enemy", 5, 20.0, 50.0)
	_set_hp(state, "enemy", 6, 80.0, 100.0)
	var errors: Array[String] = []
	# battle.js helper uses ratio -> current hp -> id, so 2 beats 1 and 5.
	harness.assert_equal(TargetingRulesScript.lowest_hp_percent_lockable(state, "enemy", errors)["id"], 2)
	# skills.js basicDamage/smallHeal omit the current-HP tie-break.
	harness.assert_equal(TargetingRulesScript.lowest_hp_percent_lockable_by_id(state, "enemy", errors)["id"], 1)
	harness.assert_equal(TargetingRulesScript.lowest_hp_percent_alive(state, "enemy", errors)["id"], 3)
	harness.assert_equal(TargetingRulesScript.lowest_current_hp_lockable(state, "enemy", errors)["id"], 2)
	harness.assert_equal(TargetingRulesScript.lowest_current_hp_alive(state, "enemy", errors)["id"], 3)
	harness.assert_equal(errors, [])


func _test_highest_selectors(harness: TestHarness) -> void:
	var state := _state()
	_unit_at(state, "ally", 1)["atk"] = 50.0
	_unit_at(state, "ally", 2)["atk"] = 50.0
	_unit_at(state, "ally", 6)["atk"] = 999.0
	_kill(_unit_at(state, "ally", 6))
	_set_hp(state, "ally", 1, 80.0, 100.0)
	_set_hp(state, "ally", 2, 80.0, 100.0)
	_set_hp(state, "ally", 3, 90.0, 100.0)
	_set_hp(state, "ally", 4, 90.0, 100.0)
	_set_hp(state, "ally", 5, 80.0, 100.0)
	var errors: Array[String] = []
	harness.assert_equal(TargetingRulesScript.highest_atk_alive(state, "ally", errors)["id"], 1)
	harness.assert_equal(TargetingRulesScript.highest_current_hp_alive(state, "ally", errors)["id"], 3)
	harness.assert_equal(errors, [])


func _test_burn_selectors(harness: TestHarness) -> void:
	var state := _state()
	_set_hp(state, "enemy", 1, 60.0, 100.0)
	_set_hp(state, "enemy", 2, 20.0, 50.0)
	_unit_at(state, "enemy", 1)["buffs"] = [_burn(3)]
	_unit_at(state, "enemy", 2)["buffs"] = [_burn(3)]
	_unit_at(state, "enemy", 3)["buffs"] = [_burn(4), _buff("stealth")]
	var errors: Array[String] = []
	harness.assert_equal(TargetingRulesScript.burn_detonate_target(state, "enemy", errors)["id"], 2)
	harness.assert_equal(TargetingRulesScript.mark_burn_target(state, "enemy", errors)["id"], 1)
	for slot in range(1, 7):
		_unit_at(state, "enemy", slot)["buffs"] = []
	harness.assert_equal(TargetingRulesScript.burn_detonate_target(state, "enemy", errors), null)
	harness.assert_equal(TargetingRulesScript.mark_burn_target(state, "enemy", errors)["id"], 1)
	harness.assert_equal(errors, [])


func _test_lane_priority(harness: TestHarness) -> void:
	var errors: Array[String] = []
	harness.assert_equal([
		TargetingRulesScript.lane_by_slot(1, errors), TargetingRulesScript.lane_by_slot(4, errors),
		TargetingRulesScript.lane_by_slot(5, errors), TargetingRulesScript.lane_by_slot(6, errors),
	], [1, 1, 2, 3])
	harness.assert_equal(TargetingRulesScript.lane_priority(1, errors), [1, 2, 3])
	harness.assert_equal(TargetingRulesScript.lane_priority(2, errors), [2, 1, 3])
	harness.assert_equal(TargetingRulesScript.lane_priority(3, errors), [3, 2, 1])
	harness.assert_equal(errors, [])


func _test_positional_targets(harness: TestHarness) -> void:
	var state := _state()
	_kill(_unit_at(state, "enemy", 2))
	_unit_at(state, "enemy", 1)["buffs"] = [_buff("stealth")]
	var errors: Array[String] = []
	# Lane 2 searches front slots 2,1,3; positional attacks ignore stealth.
	harness.assert_equal(TargetingRulesScript.target_by_lane(state, "ally", 2, errors)["id"], 1)
	_kill(_unit_at(state, "enemy", 1))
	harness.assert_equal(TargetingRulesScript.target_by_lane(state, "ally", 2, errors)["id"], 3)
	_kill(_unit_at(state, "enemy", 3))
	harness.assert_equal(TargetingRulesScript.target_by_lane(state, "ally", 2, errors)["id"], 5)
	harness.assert_equal(_ids(TargetingRulesScript.column_targets_by_attacker(state, "ally", 2, errors)), [5])
	harness.assert_equal(_ids(TargetingRulesScript.column_targets_by_target(state, "enemy", 5, errors)), [5])
	harness.assert_equal(errors, [])


func _test_random_candidates(harness: TestHarness) -> void:
	var state := _state()
	_kill(_unit_at(state, "ally", 2))
	_unit_at(state, "ally", 4)["buffs"] = [_buff("stealth")]
	var before := str(state)
	var errors: Array[String] = []
	harness.assert_equal(
		_ids(TargetingRulesScript.random_lockable_candidates(state, "ally", errors)),
		[1, 3, 5, 6],
	)
	harness.assert_equal(errors, [])
	harness.assert_equal(str(state), before)
	for slot in range(1, 7):
		_kill(_unit_at(state, "enemy", slot))
	harness.assert_equal(TargetingRulesScript.random_lockable_candidates(state, "enemy", errors), [])
	harness.assert_equal(TargetingRulesScript.lowest_hp_percent_lockable(state, "enemy", errors), null)
	harness.assert_equal(errors, [])


func _test_fail_closed(harness: TestHarness) -> void:
	var invalid := _state()
	invalid["enemies"][0]["unknown"] = true
	var before := str(invalid)
	var errors: Array[String] = []
	harness.assert_equal(TargetingRulesScript.alive(invalid, "enemy", errors), [])
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(str(invalid), before)
	invalid = _state()
	invalid["enemies"][0]["atk"] = NAN
	harness.assert_equal(TargetingRulesScript.highest_atk_alive(invalid, "enemy", errors), null)
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("atk")))
	var valid := _state()
	harness.assert_equal(TargetingRulesScript.lockable(valid, "neutral", errors), [])
	harness.assert_true(errors[0].contains("side"))
	harness.assert_equal(TargetingRulesScript.target_by_lane(valid, "ally", 0, errors), null)
	harness.assert_true(errors[0].contains("slot"))
	harness.assert_equal(TargetingRulesScript.lane_priority(4, errors), [])
	harness.assert_true(errors[0].contains("lane"))


func _state() -> Dictionary:
	var source := {
		"round": 1,
		"phase": "player_input",
		"sp": 4.0,
		"sp_max": 6.0,
		"base_sp_max": 6.0,
		"enemy_sp": 4.0,
		"enemy_sp_max": 6.0,
		"allies": _team("ally"),
		"enemies": _team("enemy"),
		"player_heroes": [],
		"enemy_heroes": [],
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
	var errors: Array[String] = []
	var state: Dictionary = BattleStateScript.create(source, errors)
	assert(errors.is_empty())
	return state


func _team(side: String) -> Array:
	var result: Array = []
	for slot in range(1, 7):
		result.append({
			"id": slot,
			"slot": slot,
			"side": side,
			"class_id": "default",
			"class_name": "棋子",
			"hp": 100.0,
			"max_hp": 100.0,
			"atk": 10.0,
			"crit_rate": 0.05,
			"alive": true,
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


func _unit_at(state: Dictionary, side: String, slot: int) -> Dictionary:
	var team: Array = state["allies" if side == "ally" else "enemies"]
	for unit: Dictionary in team:
		if unit["slot"] == slot:
			return unit
	assert(false)
	return {}


func _kill(unit: Dictionary) -> void:
	unit["hp"] = 0.0
	unit["alive"] = false


func _set_hp(state: Dictionary, side: String, slot: int, hp: float, max_hp: float) -> void:
	var unit := _unit_at(state, side, slot)
	unit["hp"] = hp
	unit["max_hp"] = max_hp
	unit["alive"] = hp > 0.0


func _buff(id: String) -> Dictionary:
	return {"id": id, "stacks": 1, "turns": 1, "layer_turns": []}


func _burn(stacks: int) -> Dictionary:
	var layers: Array = []
	for _index in stacks:
		layers.append(2)
	return {"id": "burn", "stacks": stacks, "turns": 2, "layer_turns": layers}


func _ids(units: Array) -> Array:
	return units.map(func(unit: Dictionary) -> Variant: return unit["id"])
