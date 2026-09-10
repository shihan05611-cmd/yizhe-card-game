extends RefCounted

const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const GrowthPortScript = preload("res://systems/growth/growth_port.gd")
const MarshalGrowth = preload("res://systems/growth/marshal_growth.gd")
const PermanentGrowth = preload("res://systems/growth/permanent_growth.gd")
const StoreScript = preload("res://systems/buffs/permanent_buff_store.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("Marshal formulas match first repeat cap and strict stack semantics", func() -> void:
		_test_marshal_formulas(harness)
	)
	harness.run_test("Marshal snapshots and target choice are canonical and slot based", func() -> void:
		_test_marshal_targeting(harness)
	)
	harness.run_test("Marshal death growth returns a pure repeat projection", func() -> void:
		_test_marshal_death_projection(harness)
	)
	harness.run_test("Flame tiers and requests use pre-cast count and eligible slots", func() -> void:
		_test_flame_plan(harness)
	)
	harness.run_test("Ning momentum is unbounded while post-five layers add damage only", func() -> void:
		_test_fist_plan(harness)
	)
	harness.run_test("growth port preview is side-effect free and stage is canonical", func() -> void:
		_test_growth_port_success(harness)
	)
	harness.run_test("growth port rejects malformed duplicate and overflow batches atomically", func() -> void:
		_test_growth_port_atomic_rejections(harness)
	)
	harness.run_test("growth port fails closed when its injected draft is corrupted", func() -> void:
		_test_growth_port_corrupted_backing(harness)
	)
	print("B3-4 PERMANENT GROWTH TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_marshal_formulas(harness: TestHarness) -> void:
	var errors: Array[String] = []
	harness.assert_equal(MarshalGrowth.promotion_bonuses(0, {}, errors), {
		"atk": 0.0, "max_hp": 0.0, "block": 0.0, "crit": 0.0,
	})
	harness.assert_equal(errors, [])
	harness.assert_equal(MarshalGrowth.promotion_bonuses(1), {
		"atk": 0.0, "max_hp": 80.0, "block": 0.1, "crit": 0.05,
	})
	harness.assert_equal(MarshalGrowth.promotion_bonuses(3), {
		"atk": 6.0, "max_hp": 80.0, "block": 0.16, "crit": 0.11,
	})
	harness.assert_equal(MarshalGrowth.promotion_delta(0, 1), {
		"atk": 0.0, "max_hp": 80.0, "block": 0.1, "crit": 0.05,
	})
	harness.assert_equal(MarshalGrowth.promotion_delta(1, 2), {
		"atk": 3.0, "max_hp": 0.0, "block": 0.03, "crit": 0.03,
	})
	var huge := MarshalGrowth.promotion_bonuses(StoreScript.MAX_SAFE_INTEGER)
	harness.assert_equal(huge["block"], 0.95)
	harness.assert_equal(huge["crit"], 0.95)
	for invalid in [-1, 1.5, INF, "1"]:
		errors.clear()
		harness.assert_equal(MarshalGrowth.promotion_bonuses(invalid, {}, errors), {})
		harness.assert_true(not errors.is_empty())
	errors.clear()
	harness.assert_equal(MarshalGrowth.promotion_delta(1, 3, {}, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("exactly one")))
	errors.clear()
	harness.assert_equal(MarshalGrowth.promotion_plan(2, StoreScript.MAX_SAFE_INTEGER, {}, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("maximum safe integer")))


func _test_marshal_targeting(harness: TestHarness) -> void:
	var snapshot := _progress_snapshot([])
	snapshot["piece_slots"][1]["hp_ratio"] = 0.0
	var before := snapshot.duplicate(true)
	var errors: Array[String] = []
	var ratios := MarshalGrowth.slot_ratios(snapshot, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(ratios, {1: 1.0, 2: 0.0, 3: 1.0, 4: 1.0, 5: 1.0, 6: 1.0})
	harness.assert_equal(snapshot, before)
	var allies := [
		_unit(3, true), _unit(2, true), _unit(1, true),
	]
	var selected: Variant = MarshalGrowth.choose_target(allies, 2, ratios, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(selected["slot"], 1, "ratio-zero preferred slot falls back by slot")
	selected = MarshalGrowth.choose_target(allies, 3, ratios, errors)
	harness.assert_equal(selected["slot"], 3)
	allies[2]["is_puppet"] = true
	selected = MarshalGrowth.choose_target(allies, 1, ratios, errors)
	harness.assert_equal(selected["slot"], 3)
	var malformed := _progress_snapshot([])
	malformed["piece_slots"][0]["extra"] = true
	errors.clear()
	harness.assert_equal(MarshalGrowth.slot_ratios(malformed, errors), {})
	harness.assert_true(not errors.is_empty())
	var duplicate_buff := _progress_snapshot([
		_buff("marshalPromotion", "pieceSlot", 1, 1),
		_buff("marshalPromotion", "pieceSlot", 1, 1),
	])
	errors.clear()
	harness.assert_equal(MarshalGrowth.slot_ratios(duplicate_buff, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("duplicate")))


func _test_marshal_death_projection(harness: TestHarness) -> void:
	var dead := _unit(1, false)
	var general := _unit(2, true)
	general["general"] = true
	var units := [dead, general, _unit(3, true)]
	var errors: Array[String] = []
	var plan := MarshalGrowth.death_growth_plan(
		dead, units, {1: 1.0, 2: 1.0, 3: 1.0}, 0, {}, errors
	)
	harness.assert_equal(errors, [])
	harness.assert_true(plan["eligible"])
	harness.assert_equal(plan["request"], _buff("marshalPromotion", "pieceSlot", 2, 1))
	harness.assert_equal(plan["before_stacks"], 0)
	harness.assert_equal(plan["after_stacks"], 1)
	harness.assert_equal(plan["delta"], {
		"atk": 3.0, "max_hp": 0.0, "block": 0.03, "crit": 0.03,
	}, "legacy pure projection mirrors the doubled repeat delta")
	dead["general"] = true
	plan = MarshalGrowth.death_growth_plan(dead, units, null, 1, {}, errors)
	harness.assert_equal(plan, {"eligible": false, "reason": "general_died"})
	dead["general"] = false
	general["general"] = false
	plan = MarshalGrowth.death_growth_plan(dead, units, null, 1, {}, errors)
	harness.assert_equal(plan, {"eligible": false, "reason": "no_living_general"})
	var source := {
		"atk": 32.0, "max_hp": 360.0, "hp": 180.0,
		"base_block_rate": 0.05, "crit_rate": 0.05, "other": {"kept": true},
	}
	var source_before := source.duplicate(true)
	var projected := MarshalGrowth.project_unit(source, MarshalGrowth.promotion_delta(0, 1), errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(source, source_before)
	harness.assert_equal(projected["atk"], 32.0)
	harness.assert_equal(projected["max_hp"], 440.0)
	harness.assert_equal(projected["hp"], 260.0)
	harness.assert_true(is_equal_approx(projected["base_block_rate"], 0.15))
	harness.assert_equal(projected["crit_rate"], 0.1)
	harness.assert_equal(projected["other"], {"kept": true})
	harness.assert_equal(MarshalGrowth.repeat_heal_amount({"hp": 200.0, "max_hp": 440.0}), 12.0)


func _test_flame_plan(harness: TestHarness) -> void:
	var expected_costs := [2, 2, 2, 3, 3, 4, 4]
	for index in [0, 1, 2, 3, 6, 7, 8]:
		harness.assert_equal(
			PermanentGrowth.flame_investment_base_cost(index),
			expected_costs[[0, 1, 2, 3, 6, 7, 8].find(index)],
		)
	var allies := [_unit(6, true), _unit(1, true), _unit(3, true), _unit(2, false)]
	allies[2]["is_puppet"] = true
	var before := allies.duplicate(true)
	var errors: Array[String] = []
	var plan := PermanentGrowth.flame_investment_plan(
		allies, {1: 1.0, 2: 1.0, 3: 1.0, 6: 1.0}, 3, false, errors
	)
	harness.assert_equal(errors, [])
	harness.assert_equal(allies, before)
	harness.assert_true(plan["available"])
	harness.assert_equal(plan["base_cost"], 3)
	harness.assert_equal(plan["eligible_slots"], [1, 6])
	harness.assert_equal(plan["requests"], [
		_buff("flamePractice", "hero", 5, 1),
		_buff("flameEnchant", "pieceSlot", 1, 1),
		_buff("flameEnchant", "pieceSlot", 6, 1),
	])
	plan = PermanentGrowth.flame_investment_plan(
		allies, {1: 1.0, 2: 1.0, 3: 1.0, 6: 1.0}, 3, true, errors
	)
	harness.assert_false(plan["available"])
	harness.assert_equal(plan["reason"], "used_this_battle")
	harness.assert_equal(plan["requests"], [])
	errors.clear()
	harness.assert_equal(PermanentGrowth.flame_investment_base_cost(-1, errors), 0)
	harness.assert_true(not errors.is_empty())
	errors.clear()
	harness.assert_equal(PermanentGrowth.flame_investment_plan(allies, null, 0, false, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("injected Dictionary")))


func _test_fist_plan(harness: TestHarness) -> void:
	var errors: Array[String] = []
	harness.assert_equal(PermanentGrowth.fist_mastery_damage_up_rate(5), 0.25)
	harness.assert_equal(PermanentGrowth.fist_mastery_ultimate_bonus_hits(4), 0)
	harness.assert_equal(PermanentGrowth.fist_mastery_ultimate_bonus_hits(5), 1)
	harness.assert_equal(PermanentGrowth.fist_mastery_ultimate_bonus_hits(10), 2)
	var effects := PermanentGrowth.fist_momentum_effects(4, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(effects, {
		"momentum": 4, "damage_up_rate": 0.6, "crit_rate_up": 0.16,
		"extra_targets": 2, "target_count": 3, "ultimate_hits": 7,
	})
	effects = PermanentGrowth.fist_momentum_effects(8, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(effects, {
		"momentum": 8, "damage_up_rate": 0.9, "crit_rate_up": 0.2,
		"extra_targets": 2, "target_count": 3, "ultimate_hits": 8,
	})
	var plan := PermanentGrowth.fist_growth_plan(4, 5, 0.05, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(plan["mastery_damage_up_rate"], 0.25)
	harness.assert_equal(plan["mastery_before_stacks"], 5)
	harness.assert_equal(plan["mastery_after_stacks"], 6)
	harness.assert_equal(plan["next_momentum"], 5)
	harness.assert_equal(plan["request"], _buff("fistMastery", "hero", 6, 1))
	plan = PermanentGrowth.fist_growth_plan(5, 6, 0.05, errors)
	harness.assert_equal(plan["next_momentum"], 6)
	errors.clear()
	plan = PermanentGrowth.fist_growth_plan(6, 0, 0.05, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(plan["next_momentum"], 7)
	harness.assert_equal(plan["momentum_effects"]["damage_up_rate"], 0.8)
	errors.clear()
	harness.assert_equal(PermanentGrowth.fist_growth_plan(0, StoreScript.MAX_SAFE_INTEGER, 0.05, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("maximum safe integer")))


func _test_growth_port_success(harness: TestHarness) -> void:
	var run_state := {"permanent_buffs": []}
	var errors: Array[String] = []
	var port := GrowthPortScript.new(_port_config(run_state), errors)
	harness.assert_equal(errors, [])
	harness.assert_true(port.is_valid())
	var actions := port.action_map()
	harness.assert_equal(actions.keys().size(), 4)
	var request := {"requests": [
		_buff("flamePractice", "hero", 5, 1),
		_buff("flameEnchant", "pieceSlot", 1, 1),
		_buff("flameEnchant", "pieceSlot", 2, 1),
	]}
	var preview: Dictionary = actions[GrowthPortScript.ACTION_PREVIEW].call(request)
	harness.assert_true(CombatPortsScript.is_result(preview))
	harness.assert_true(preview["ok"])
	harness.assert_equal(run_state["permanent_buffs"], [])
	harness.assert_equal(preview["value"].size(), 3)
	preview["value"][0]["stacks"] = 99
	harness.assert_equal(run_state["permanent_buffs"], [])
	var staged: Dictionary = actions[GrowthPortScript.ACTION_STAGE].call(request)
	harness.assert_true(CombatPortsScript.is_result(staged))
	harness.assert_true(staged["ok"])
	harness.assert_equal(run_state["permanent_buffs"], request["requests"])
	request["requests"][0]["target"]["id"] = 6
	harness.assert_equal(run_state["permanent_buffs"][0]["target"]["id"], 5)
	var stacks_result: Dictionary = actions[GrowthPortScript.ACTION_GET_STACKS].call({
		"id": "flameEnchant", "target": {"type": "pieceSlot", "id": 2},
	})
	harness.assert_true(stacks_result["ok"])
	harness.assert_equal(stacks_result["value"], 1)
	var snapshot_result: Dictionary = actions[GrowthPortScript.ACTION_SNAPSHOT].call({})
	harness.assert_true(snapshot_result["ok"])
	snapshot_result["value"].clear()
	harness.assert_equal(run_state["permanent_buffs"].size(), 3)


func _test_growth_port_atomic_rejections(harness: TestHarness) -> void:
	var run_state := {"permanent_buffs": []}
	var port := GrowthPortScript.new(_port_config(run_state))
	var before: Array = run_state["permanent_buffs"]
	var malformed := port.stage_batch({"requests": [
		_buff("flamePractice", "hero", 5, 1),
		_buff("missing", "hero", 5, 1),
	]})
	harness.assert_false(malformed["ok"])
	harness.assert_true(is_same(run_state["permanent_buffs"], before))
	harness.assert_equal(run_state["permanent_buffs"], [])
	var duplicate := _buff("fistMastery", "hero", 6, 1)
	var duplicate_result := port.stage_batch({"requests": [duplicate, duplicate.duplicate(true)]})
	harness.assert_false(duplicate_result["ok"])
	harness.assert_contains(duplicate_result["error"], "duplicate")
	harness.assert_true(is_same(run_state["permanent_buffs"], before))
	var extra_field := port.preview_batch({"requests": [duplicate], "extra": true})
	harness.assert_false(extra_field["ok"])
	harness.assert_equal(run_state["permanent_buffs"], [])

	var overflow_state := {"permanent_buffs": [
		_buff("fistMastery", "hero", 6, StoreScript.MAX_SAFE_INTEGER),
	]}
	var overflow_port := GrowthPortScript.new(_port_config(overflow_state))
	var overflow_before: Array = overflow_state["permanent_buffs"]
	var overflow := overflow_port.stage_batch({"requests": [
		_buff("fistMastery", "hero", 6, 1),
	]})
	harness.assert_false(overflow["ok"])
	harness.assert_contains(overflow["error"], "overflow")
	harness.assert_true(is_same(overflow_state["permanent_buffs"], overflow_before))
	harness.assert_equal(overflow_state["permanent_buffs"][0]["stacks"], StoreScript.MAX_SAFE_INTEGER)


func _test_growth_port_corrupted_backing(harness: TestHarness) -> void:
	var run_state := {"permanent_buffs": []}
	var config := _port_config(run_state)
	var port := GrowthPortScript.new(config)
	# The draft is intentionally injected/mutable. Corruption must be observed and
	# rejected before a request can replace or partially repair it.
	var corrupted := [{"id": "missing", "target": {"type": "hero", "id": 5}, "stacks": 1}]
	run_state["permanent_buffs"] = corrupted
	var result := port.stage_batch({"requests": [_buff("fistMastery", "hero", 6, 1)]})
	harness.assert_false(result["ok"])
	harness.assert_true(is_same(run_state["permanent_buffs"], corrupted))
	harness.assert_equal(run_state["permanent_buffs"], corrupted)
	var snapshot_result := port.snapshot_action({})
	harness.assert_false(snapshot_result["ok"])


func _progress_snapshot(permanent_buffs: Array) -> Dictionary:
	var piece_slots: Array[Dictionary] = []
	for index in 6:
		piece_slots.append({"slot": index + 1, "hp_ratio": 1.0})
	return {
		"piece_slots": piece_slots,
		"permanent_buffs": permanent_buffs,
	}


func _unit(slot: int, alive: bool) -> Dictionary:
	return {
		"slot": slot,
		"side": "ally",
		"alive": alive,
		"is_puppet": false,
		"general": false,
	}


func _buff(id: String, target_type: String, target_id: int, stacks: int) -> Dictionary:
	return {
		"id": id,
		"target": {"type": target_type, "id": target_id},
		"stacks": stacks,
	}


func _port_config(run_state: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var catalog := ContentCatalog.build(errors)
	assert(errors.is_empty())
	return {
		"run_state": run_state,
		"catalog": catalog["buffs"],
		"valid_hero_ids": catalog["characters"]["players"].keys(),
	}
