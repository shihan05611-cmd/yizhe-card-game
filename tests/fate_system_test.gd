extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const FateSystemScript = preload("res://systems/combat/fate_system.gd")


class FixedRng:
	extends RefCounted

	var calls := 0
	var pick_index := 0

	func _init(index: int = 0) -> void:
		pick_index = index

	func next() -> float:
		calls += 1
		return 0.5

	func int_range(minimum: int, _maximum: int) -> Variant:
		calls += 1
		return minimum

	func pick(values: Array) -> Variant:
		calls += 1
		return values[mini(pick_index, values.size() - 1)] if not values.is_empty() else null


class InvalidPickRng:
	extends RefCounted

	var calls := 0

	func next() -> float:
		calls += 1
		return 0.5

	func int_range(minimum: int, _maximum: int) -> Variant:
		calls += 1
		return minimum

	func pick(_values: Array) -> Variant:
		calls += 1
		return "not-a-fate-mode"


class MissingRng:
	extends RefCounted


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("inactive Fate is a strict no-op without RNG or Buff work", func() -> void:
		_test_inactive(harness)
	)
	harness.run_test("ally fixed Fate advances index skips used chaos and falls back to RNG", func() -> void:
		_test_ally_fixed_order(harness)
	)
	harness.run_test("enemy Fate ignores ally fixed order and uses combat RNG", func() -> void:
		_test_enemy_ignores_fixed(harness)
	)
	harness.run_test("piece Fate applies Pursuit to living own units and clears the side lock", func() -> void:
		_test_piece_both_sides(harness)
	)
	harness.run_test("chaos sets the opposing lock and a later normal mode clears it", func() -> void:
		_test_chaos_and_clear(harness)
	)
	harness.run_test("all-in Fate applies both sides without reading tuning or RNG", func() -> void:
		_test_all_in(harness)
	)
	harness.run_test("Fate APIs reject malformed state RNG Buff and selection before mutation", func() -> void:
		_test_fail_closed(harness)
	)
	harness.run_test("Pursuit runtime failure preserves its prefix and withholds Fate metadata", func() -> void:
		_test_runtime_failure(harness)
	)
	harness.run_test("selection and preflight preserve caller state tuning and RNG boundaries", func() -> void:
		_test_selection_invariance(harness)
	)
	print("B4-2F FATE SYSTEM TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_inactive(harness: TestHarness) -> void:
	var fixture := _fixture("ally", "棋子命运", 0)
	fixture["state"]["fate"]["enemy_lock"] = "noSkill"
	var before := BattleStateScript.snapshot(fixture["state"])
	var errors: Array[String] = []
	var result := FateSystemScript.roll(
		fixture["state"], "ally", fixture["tuning"], fixture["rng"], fixture["buffs"], errors
	)
	harness.assert_equal(errors, [])
	harness.assert_false(result["applied"])
	harness.assert_equal(result["mode"], null)
	harness.assert_equal(fixture["state"], before)
	harness.assert_equal(fixture["rng"].calls, 0)


func _test_ally_fixed_order(harness: TestHarness) -> void:
	var fixture := _fixture("ally", "棋子命运,混沌命运,技能命运", 1)
	fixture["state"]["fate"]["active"] = true
	var result := _roll(fixture)
	harness.assert_equal(result["mode"], FateSystemScript.MODE_PIECE)
	harness.assert_equal(fixture["state"]["fate"]["roll_index"], 1)
	harness.assert_equal(fixture["rng"].calls, 0)
	result = _roll(fixture)
	harness.assert_equal(result["mode"], FateSystemScript.MODE_CHAOS)
	harness.assert_true(fixture["state"]["fate"]["chaos_used"])
	harness.assert_equal(fixture["state"]["fate"]["roll_index"], 2)
	result = _roll(fixture)
	harness.assert_equal(result["mode"], FateSystemScript.MODE_SKILL)
	harness.assert_equal(fixture["state"]["fate"]["roll_index"], 3)
	harness.assert_equal(fixture["rng"].calls, 0)

	var skipped := _fixture("ally", "混沌命运,技能命运", 0)
	skipped["state"]["fate"]["active"] = true
	skipped["state"]["fate"]["chaos_used"] = true
	result = _roll(skipped)
	harness.assert_equal(result["mode"], FateSystemScript.MODE_SKILL)
	harness.assert_equal(skipped["state"]["fate"]["roll_index"], 2)
	harness.assert_equal(skipped["rng"].calls, 0)

	var exhausted := _fixture("ally", "混沌命运", 0)
	exhausted["state"]["fate"]["active"] = true
	exhausted["state"]["fate"]["chaos_used"] = true
	result = _roll(exhausted)
	harness.assert_equal(result["mode"], FateSystemScript.MODE_PIECE)
	harness.assert_true(result["used_rng"])
	harness.assert_equal(exhausted["state"]["fate"]["roll_index"], 1)
	harness.assert_equal(exhausted["rng"].calls, 1)


func _test_enemy_ignores_fixed(harness: TestHarness) -> void:
	var fixture := _fixture("enemy", "技能命运", 2)
	fixture["state"]["enemy_fate"]["active"] = true
	fixture["tuning"]["fateFixedOrder"].value = 42
	var result := _roll(fixture)
	harness.assert_equal(result["mode"], FateSystemScript.MODE_CHAOS)
	harness.assert_true(result["used_rng"])
	harness.assert_equal(fixture["rng"].calls, 1)
	harness.assert_true(fixture["state"]["enemy_fate"]["chaos_used"])
	harness.assert_equal(fixture["state"]["enemy_fate"]["ally_lock"], "noSkill")


func _test_piece_both_sides(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var fixture := _fixture(side, "棋子命运", 0)
		var fate: Dictionary = fixture["state"]["fate" if side == "ally" else "enemy_fate"]
		fate["active"] = true
		fate["enemy_lock" if side == "ally" else "ally_lock"] = "noSkill"
		_kill(_unit(fixture["state"], side, 6))
		var result := _roll(fixture)
		harness.assert_equal(result["mode"], FateSystemScript.MODE_PIECE)
		harness.assert_equal(result["pursuit_target_ids"], [1, 2, 3, 4, 5])
		for slot in range(1, 6):
			harness.assert_equal(fixture["buffs"].get_unit_stacks(_unit(fixture["state"], side, slot), "pursuit"), 1)
		harness.assert_equal(fixture["buffs"].get_unit_stacks(_unit(fixture["state"], side, 6), "pursuit"), 0)
		harness.assert_equal(fate["enemy_lock" if side == "ally" else "ally_lock"], null)


func _test_chaos_and_clear(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var fixture := _fixture(side, "混沌命运", 2)
		var fate: Dictionary = fixture["state"]["fate" if side == "ally" else "enemy_fate"]
		fate["active"] = true
		var result := _roll(fixture)
		harness.assert_equal(result["mode"], FateSystemScript.MODE_CHAOS)
		var lock_field := "enemy_lock" if side == "ally" else "ally_lock"
		harness.assert_equal(fate[lock_field], "noSkill")
		fixture["rng"].pick_index = 1
		if side == "ally":
			fixture["tuning"]["fateFixedOrder"].value = "技能命运"
		result = _roll(fixture)
		harness.assert_equal(result["mode"], FateSystemScript.MODE_SKILL)
		harness.assert_equal(fate[lock_field], null)


func _test_all_in(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var fixture := _fixture(side)
		var fate: Dictionary = fixture["state"]["fate" if side == "ally" else "enemy_fate"]
		fate["active"] = true
		fate["all_in_turns"] = 2
		_kill(_unit(fixture["state"], side, 6))
		var errors: Array[String] = []
		var result := FateSystemScript.roll(
			fixture["state"], side, null, null, fixture["buffs"], errors
		)
		harness.assert_equal(errors, [])
		harness.assert_equal(result["mode"], FateSystemScript.MODE_ALL)
		harness.assert_false(result["used_rng"])
		harness.assert_equal(result["pursuit_target_ids"], [1, 2, 3, 4, 5])
		harness.assert_equal(fate["enemy_lock" if side == "ally" else "ally_lock"], "noSkill")


func _test_fail_closed(harness: TestHarness) -> void:
	var fixture := _fixture("ally")
	fixture["state"]["fate"]["active"] = true
	var before := BattleStateScript.snapshot(fixture["state"])
	var errors: Array[String] = []
	harness.assert_equal(FateSystemScript.roll(
		fixture["state"], "ally", {}, fixture["rng"], fixture["buffs"], errors
	), {})
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(fixture["state"], before)
	harness.assert_equal(fixture["rng"].calls, 0)

	errors.clear()
	harness.assert_equal(FateSystemScript.roll(
		fixture["state"], "ally", fixture["tuning"], MissingRng.new(), fixture["buffs"], errors
	), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("combat_rng")))
	harness.assert_equal(fixture["state"], before)

	var invalid_rng := InvalidPickRng.new()
	errors.clear()
	harness.assert_equal(FateSystemScript.roll(
		fixture["state"], "ally", fixture["tuning"], invalid_rng, fixture["buffs"], errors
	), {})
	harness.assert_equal(invalid_rng.calls, 1)
	harness.assert_equal(fixture["state"], before)

	var fake_buff_rng := FixedRng.new()
	errors.clear()
	harness.assert_equal(FateSystemScript.roll(
		fixture["state"], "ally", fixture["tuning"], fake_buff_rng, RefCounted.new(), errors
	), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("buffs")))
	harness.assert_equal(fake_buff_rng.calls, 0, "B1 preflight precedes RNG")
	harness.assert_equal(fixture["state"], before)

	var malformed := before.duplicate(true)
	malformed["extra"] = true
	errors.clear()
	harness.assert_equal(FateSystemScript.select_mode(
		malformed, "ally", fixture["tuning"], fixture["rng"], errors
	), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	harness.assert_equal(FateSystemScript.apply_mode(
		fixture["state"], "ally", {"mode": "技能命运"}, fixture["buffs"], errors
	), {})
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(fixture["state"], before)


func _test_runtime_failure(harness: TestHarness) -> void:
	var fixture := _fixture("ally", "棋子命运", 0, true)
	var fate: Dictionary = fixture["state"]["fate"]
	fate["active"] = true
	fate["mode"] = FateSystemScript.MODE_SKILL
	fate["enemy_lock"] = "noSkill"
	var errors: Array[String] = []
	var result := FateSystemScript.roll(
		fixture["state"], "ally", fixture["tuning"], fixture["rng"], fixture["buffs"], errors
	)
	harness.assert_equal(result, {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("committed prefix=1")))
	harness.assert_equal(fixture["buffs"].get_unit_stacks(_unit(fixture["state"], "ally", 1), "pursuit"), 1)
	harness.assert_false(_unit(fixture["state"], "ally", 2)["alive"])
	harness.assert_equal(fate["mode"], FateSystemScript.MODE_SKILL)
	harness.assert_equal(fate["enemy_lock"], "noSkill")
	harness.assert_equal(fate["roll_index"], 0)
	var state_errors: Array[String] = []
	harness.assert_true(BattleStateScript.validate(fixture["state"], state_errors), str(state_errors))


func _test_selection_invariance(harness: TestHarness) -> void:
	var fixture := _fixture("ally", "技能命运", 2)
	fixture["state"]["fate"]["active"] = true
	var before := BattleStateScript.snapshot(fixture["state"])
	var tuning_value: Variant = fixture["tuning"]["fateFixedOrder"].value
	var errors: Array[String] = []
	harness.assert_true(FateSystemScript.preflight(
		fixture["state"], "ally", fixture["buffs"], errors
	))
	var selection := FateSystemScript.select_mode(
		fixture["state"], "ally", fixture["tuning"], fixture["rng"], errors
	)
	harness.assert_equal(errors, [])
	harness.assert_equal(selection["mode"], FateSystemScript.MODE_SKILL)
	harness.assert_equal(fixture["state"], before)
	harness.assert_equal(fixture["tuning"]["fateFixedOrder"].value, tuning_value)
	harness.assert_equal(fixture["rng"].calls, 0)


func _roll(fixture: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var result := FateSystemScript.roll(
		fixture["state"], fixture["side"], fixture["tuning"],
		fixture["rng"], fixture["buffs"], errors
	)
	assert(errors.is_empty())
	return result


func _fixture(
	side: String,
	fixed_order: String = "",
	pick_index: int = 0,
	kill_second_after_first_pursuit: bool = false,
) -> Dictionary:
	var state := _state()
	var catalog_errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(catalog_errors)
	assert(catalog_errors.is_empty())
	catalog["tuning"]["fateFixedOrder"].value = fixed_order
	var corrupted_once := false
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": state,
		"catalog": catalog["buffs"],
		"on_event": func(type: String, payload: Dictionary) -> void:
			if (
				kill_second_after_first_pursuit
				and not corrupted_once
				and type == "buff_applied"
				and payload["buff_id"] == "pursuit"
				and payload["target_id"] == 1
			):
				corrupted_once = true
				_kill(_unit(state, side, 2)),
	}, buff_errors)
	assert(buff_errors.is_empty())
	return {
		"side": side,
		"state": state,
		"tuning": catalog["tuning"],
		"buffs": buffs,
		"rng": FixedRng.new(pick_index),
	}


func _state() -> Dictionary:
	var source := {
		"round": 1, "phase": "round_start", "sp": 4.0, "sp_max": 6.0,
		"base_sp_max": 6.0, "enemy_sp": 4.0, "enemy_sp_max": 6.0,
		"allies": _team("ally"), "enemies": _team("enemy"),
		"player_heroes": [], "enemy_heroes": [],
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
		"ally_puppet_martyr_active": false, "game_over": false, "battle_result": null,
	}
	var errors: Array[String] = []
	var state: Dictionary = BattleStateScript.create(source, errors)
	assert(errors.is_empty())
	return state


func _team(side: String) -> Array:
	var result: Array = []
	for slot in range(1, 7):
		result.append({
			"id": slot, "slot": slot, "side": side,
			"class_id": "default", "class_name": "棋子",
			"hp": 100.0, "max_hp": 100.0, "atk": 10.0, "crit_rate": 0.0,
			"alive": true, "general": false, "base_block_rate": 0.0,
			"extra_action_charges": 0, "buffs": [], "is_puppet": false,
			"fixed_max_hp": null, "puppet_martyr": false, "disarm_turns": 0,
			"stealth_attack_ready": false, "special_id": null,
			"echo_damage_bonus": 0.0, "hp_threshold_crossed": false,
		})
	return result


func _unit(state: Dictionary, side: String, slot: int) -> Dictionary:
	var units: Array = state["allies" if side == "ally" else "enemies"]
	for unit: Dictionary in units:
		if unit["slot"] == slot:
			return unit
	assert(false)
	return {}


func _kill(unit: Dictionary) -> void:
	unit["hp"] = 0.0
	unit["alive"] = false
