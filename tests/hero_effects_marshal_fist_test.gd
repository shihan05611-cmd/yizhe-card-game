extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const EffectsScript = preload("res://systems/effects/hero_effects_marshal_fist.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const GrowthPortScript = preload("res://systems/growth/growth_port.gd")
const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")


class FixedRng:
	extends RefCounted
	var values: Array[int] = []
	var cursor := 0
	var invalid := false

	func _init(initial: Array[int] = []) -> void:
		values = initial.duplicate()

	func next() -> float:
		return 0.0

	func int_range(minimum: int, maximum: int) -> int:
		if invalid:
			return maximum + 1
		if values.is_empty():
			return minimum
		var raw := values[cursor % values.size()]
		cursor += 1
		return minimum + posmod(raw, maximum - minimum + 1)

	func pick(items: Array) -> Variant:
		return null if items.is_empty() else items[int_range(0, items.size() - 1)]


class ControlledDamage:
	extends RefCounted
	var fail_at := 0
	var calls := 0
	var records: Array[Dictionary] = []
	var metadata_records: Array[Dictionary] = []

	func is_valid() -> bool:
		return true

	func apply(
		target: Variant,
		damage_context: Variant,
		_metadata: Variant = {},
		errors: Array[String] = [],
	) -> Dictionary:
		errors.clear()
		calls += 1
		if fail_at > 0 and calls == fail_at:
			errors.append("injected damage failure")
			return {}
		var old_hp := float(target["hp"])
		var dealt := minf(old_hp, maxf(0.0, float(damage_context["raw_amount"])))
		target["hp"] = old_hp - dealt
		var died := old_hp > 0.0 and float(target["hp"]) <= 0.0
		if died:
			target["hp"] = 0.0
			target["alive"] = false
		var record: Dictionary = damage_context.duplicate(true)
		records.append(record)
		metadata_records.append(_metadata.duplicate(true))
		return {
			"dealt": dealt, "blocked": false, "died": died,
			"crit": float(damage_context["crit_rate"]) >= 1.0,
			"damage_context": record, "death_context": null,
		}

	func kill(target: Variant, _context: Variant = {}, errors: Array[String] = []) -> Dictionary:
		errors.clear()
		if typeof(target) != TYPE_DICTIONARY:
			errors.append("invalid target")
			return {}
		target["hp"] = 0.0
		target["alive"] = false
		return {"died": true}


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("Marshal/Fist handler ids integrate directly and passive counterAura rejects active cast", func() -> void:
		_test_handlers_and_passive(harness)
	)
	harness.run_test("counterAura ultimate applies Knight oath to living same-side units for ally and enemy", func() -> void:
		_test_counter_ultimate(harness)
	)
	harness.run_test("ascend exclusive selects promotes repeats caps heals and is side-neutral", func() -> void:
		_test_ascend_exclusive(harness)
	)
	harness.run_test("ascend Run growth stages atomically and failure preserves battle state", func() -> void:
		_test_ascend_growth(harness)
	)
	harness.run_test("ascend ultimate heals by side tuning applies march and preserves real no-target semantics", func() -> void:
		_test_ascend_ultimate(harness)
	)
	harness.run_test("fist exclusive covers momentum zero through five random unique targets crit and enemy side", func() -> void:
		_test_fist_exclusive(harness)
	)
	harness.run_test("fist exclusive stages pre-cast mastery and reports sequential damage failure", func() -> void:
		_test_fist_growth_failure(harness)
	)
	harness.run_test("fist ultimate uses mastery hits kill extension retargets and never clears momentum", func() -> void:
		_test_fist_ultimate(harness)
	)
	harness.run_test("closed contexts invalid RNG and record failures fail without invented cast events", func() -> void:
		_test_fail_closed_and_ports(harness)
	)
	harness.run_test("battle-end and both Fate skill locks guard all six handlers before every port or mutation", func() -> void:
		_test_battle_guards(harness)
	)
	print("B3-5B MARSHAL FIST EFFECT TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_handlers_and_passive(harness: TestHarness) -> void:
	var expected := [
		EffectsScript.EX_ASCEND, EffectsScript.EX_COUNTER, EffectsScript.EX_FIST,
		EffectsScript.ULT_ASCEND, EffectsScript.ULT_COUNTER, EffectsScript.ULT_FIST,
	]
	expected.sort()
	var handlers := EffectsScript.handler_map()
	var ids: Array = handlers.keys()
	ids.sort()
	harness.assert_equal(ids, expected)
	var registry := EffectRegistryScript.new()
	var errors: Array[String] = []
	harness.assert_true(registry.register_map(handlers, errors))
	harness.assert_equal(errors, [])
	var state := _state()
	var kit := _kit(state)
	var context := _context(state, "ally", "counterAura", false)
	var before := str(state)
	harness.assert_false(EffectsScript.is_usable("counterAura", false, context, kit["ports"], errors))
	harness.assert_equal(errors, [])
	var result := registry.execute(EffectsScript.EX_COUNTER, context, kit["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "passive")
	harness.assert_equal(str(state), before)
	var enemy_result := registry.execute(
		EffectsScript.EX_COUNTER,
		_context(state, "enemy", "counterAura", false), kit["ports"],
	)
	harness.assert_false(enemy_result["ok"])
	harness.assert_contains(enemy_result["error"], "passive")
	harness.assert_equal(kit["metrics"]["content_events"], 0)
	harness.assert_equal(kit["metrics"]["combat_events"], 0)


func _test_counter_ultimate(harness: TestHarness) -> void:
	var state := _state()
	_kill(state["allies"][1])
	_kill(state["enemies"][4])
	var kit := _kit(state)
	var ally := _execute(EffectsScript.ULT_COUNTER, state, "ally", "counterAura", true, kit["ports"])
	harness.assert_true(ally["ok"])
	harness.assert_equal(ally["value"]["applied_count"], 5)
	for index in state["allies"].size():
		harness.assert_equal(_buff_stacks(state["allies"][index], "knightChivalry"), 0 if index == 1 else 1)
	var enemy := _execute(EffectsScript.ULT_COUNTER, state, "enemy", "counterAura", true, kit["ports"])
	harness.assert_true(enemy["ok"])
	harness.assert_equal(enemy["value"]["applied_count"], 5)
	for index in state["enemies"].size():
		harness.assert_equal(_buff_stacks(state["enemies"][index], "knightChivalry"), 0 if index == 4 else 1)


func _test_ascend_exclusive(harness: TestHarness) -> void:
	var state := _state()
	state["marshal_target_id"] = 2
	var kit := _kit(state)
	var first := _execute(EffectsScript.EX_ASCEND, state, "ally", "ascend", false, kit["ports"])
	harness.assert_true(first["ok"])
	harness.assert_equal(first["value"]["target_slot"], 2)
	harness.assert_true(state["allies"][1]["general"])
	harness.assert_equal(state["allies"][1]["max_hp"], 180.0)
	harness.assert_equal(state["allies"][1]["hp"], 180.0)
	harness.assert_equal(state["allies"][1]["atk"], 10.0)
	state["allies"][1]["hp"] = 100.0
	state["allies"][1]["base_block_rate"] = 0.949
	state["allies"][1]["crit_rate"] = 0.949
	var repeated := _execute(EffectsScript.EX_ASCEND, state, "ally", "ascend", false, kit["ports"])
	harness.assert_true(repeated["ok"])
	harness.assert_true(repeated["value"]["repeated"])
	harness.assert_equal(repeated["value"]["healed"], 4.0)
	harness.assert_equal(state["allies"][1]["hp"], 104.0)
	harness.assert_equal(state["allies"][1]["atk"], 11.5)
	harness.assert_equal(state["allies"][1]["base_block_rate"], 0.95)
	harness.assert_equal(state["allies"][1]["crit_rate"], 0.95)

	var enemy_state := _state()
	_kill(enemy_state["enemies"][0])
	var enemy_kit := _kit(enemy_state)
	var enemy := _execute(EffectsScript.EX_ASCEND, enemy_state, "enemy", "ascend", false, enemy_kit["ports"])
	harness.assert_true(enemy["ok"])
	harness.assert_equal(enemy["value"]["target_slot"], 2)
	harness.assert_true(enemy_state["enemies"][1]["general"])

	var empty := _state()
	for unit: Dictionary in empty["allies"]:
		_kill(unit)
	var empty_kit := _kit(empty)
	var errors: Array[String] = []
	harness.assert_false(EffectsScript.is_usable("ascend", false, _context(empty, "ally", "ascend", false), empty_kit["ports"], errors))
	harness.assert_equal(errors, [])


func _test_ascend_growth(harness: TestHarness) -> void:
	var state := _state()
	state["marshal_target_id"] = 2
	var run_state := {"permanent_buffs": []}
	var kit := _kit(state, FixedRng.new(), run_state)
	var ratios := _ratios()
	ratios[2] = 0.0
	var context := _context(state, "ally", "ascend", false, ratios)
	var result := _registry_execute(EffectsScript.EX_ASCEND, context, kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["target_slot"], 1)
	harness.assert_equal(run_state["permanent_buffs"], [{
		"id": "marshalPromotion", "target": {"type": "pieceSlot", "id": 1}, "stacks": 1,
	}])

	var failed_state := _state()
	var failed_run := {"permanent_buffs": []}
	var failed_kit := _kit(failed_state, FixedRng.new(), failed_run, {
		GrowthPortScript.ACTION_STAGE: func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.fail("injected growth failure"),
	})
	var before := str(failed_state)
	var failed := _registry_execute(
		EffectsScript.EX_ASCEND,
		_context(failed_state, "ally", "ascend", false, _ratios()),
		failed_kit["ports"],
	)
	harness.assert_false(failed["ok"])
	harness.assert_contains(failed["error"], "no battle state committed")
	harness.assert_equal(str(failed_state), before)
	harness.assert_equal(failed_run["permanent_buffs"], [])


func _test_ascend_ultimate(harness: TestHarness) -> void:
	var state := _state()
	state["allies"][2]["general"] = true
	state["allies"][2]["hp"] = 40.0
	state["enemies"][3]["general"] = true
	state["enemies"][3]["hp"] = 40.0
	var kit := _kit(state)
	var ally := _execute(EffectsScript.ULT_ASCEND, state, "ally", "ascend", true, kit["ports"])
	harness.assert_true(ally["ok"])
	harness.assert_equal(ally["value"]["healed"], 30.0)
	harness.assert_equal(_buff_turns(state["allies"][2], "march"), 2)
	var enemy := _execute(EffectsScript.ULT_ASCEND, state, "enemy", "ascend", true, kit["ports"])
	harness.assert_true(enemy["ok"])
	harness.assert_equal(enemy["value"]["healed"], 15.0)
	harness.assert_equal(_buff_turns(state["enemies"][3], "march"), 2)

	var no_general := _state()
	var no_general_kit := _kit(no_general)
	var caster := _caster(no_general, "ally", "ascend")
	caster["energy"] = 77.0
	var no_target := _registry_execute(
		EffectsScript.ULT_ASCEND,
		_context(no_general, "ally", "ascend", true), no_general_kit["ports"],
	)
	harness.assert_true(no_target["ok"])
	harness.assert_true(no_target["value"]["no_target"])
	harness.assert_false(no_target["value"]["committed"])
	harness.assert_equal(caster["energy"], 77.0, "M2 effect must not spend ultimate energy")


func _test_fist_exclusive(harness: TestHarness) -> void:
	for momentum in range(0, 6):
		var state := _state()
		var caster := _caster(state, "ally", "fist")
		caster["fist_momentum"] = momentum
		var damage := ControlledDamage.new()
		var kit := _kit(state, FixedRng.new([5, 0, 1]), null, {}, damage)
		var result := _execute(EffectsScript.EX_FIST, state, "ally", "fist", false, kit["ports"])
		harness.assert_true(result["ok"], "momentum %d should execute" % momentum)
		var expected_targets := 3 if momentum >= 4 else (2 if momentum >= 2 else 1)
		harness.assert_equal(result["value"]["hits"], expected_targets)
		harness.assert_equal(result["value"]["momentum_after"], mini(5, momentum + 1))
		harness.assert_equal(damage.records.size(), expected_targets)
		var expected_wave: Array[int] = []
		for _target in expected_targets:
			expected_wave.append(0)
		harness.assert_equal(damage.metadata_records.map(func(value: Dictionary) -> Variant: return value.get("presentation_wave_index")), expected_wave, "宁不凡拳劲的同段多目标共享一个 presentation wave")
		harness.assert_equal(
			float(damage.records[0]["crit_rate"]), 0.05 + float(momentum) * 0.04,
		)
		var unique := {}
		for id: Variant in result["value"]["target_ids"]:
			unique[id] = true
		harness.assert_equal(unique.size(), expected_targets)

	var enemy_state := _state()
	var enemy_damage := ControlledDamage.new()
	var enemy_kit := _kit(enemy_state, FixedRng.new([2]), null, {}, enemy_damage)
	var enemy := _execute(EffectsScript.EX_FIST, enemy_state, "enemy", "fist", false, enemy_kit["ports"])
	harness.assert_true(enemy["ok"])
	harness.assert_equal(enemy_damage.records[0]["effect"]["source_side"], "enemy")
	harness.assert_equal(enemy_state["enemy_heroes"][2]["fist_momentum"], 1)
	for unit: Dictionary in enemy_state["allies"]:
		_kill(unit)
	var unusable_errors: Array[String] = []
	harness.assert_false(EffectsScript.is_usable(
		"fist", false, _context(enemy_state, "enemy", "fist", false),
		enemy_kit["ports"], unusable_errors,
	))
	harness.assert_equal(unusable_errors, [])


func _test_fist_growth_failure(harness: TestHarness) -> void:
	var state := _state()
	_caster(state, "ally", "fist")["fist_momentum"] = 2
	var run_state := {"permanent_buffs": [{
		"id": "fistMastery", "target": {"type": "hero", "id": 6}, "stacks": 5,
	}]}
	var damage := ControlledDamage.new()
	damage.fail_at = 2
	var kit := _kit(state, FixedRng.new([0, 0]), run_state, {}, damage)
	var result := _registry_execute(
		EffectsScript.EX_FIST,
		_context(state, "ally", "fist", false, _ratios()), kit["ports"],
	)
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "state committed")
	harness.assert_equal(run_state["permanent_buffs"][0]["stacks"], 6)
	harness.assert_equal(damage.records.size(), 1)
	harness.assert_equal(damage.records[0]["raw_amount"], 15.5, "10 * (1 + .30 momentum + .25 pre-layer mastery)")
	harness.assert_equal(_caster(state, "ally", "fist")["fist_momentum"], 2, "momentum commits only after every target")

	var stage_state := _state()
	var stage_run := {"permanent_buffs": []}
	var stage_rng := FixedRng.new([4])
	var stage_kit := _kit(stage_state, stage_rng, stage_run, {
		GrowthPortScript.ACTION_STAGE: func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.fail("injected fist growth failure"),
	})
	var stage_before := str(stage_state)
	var stage_failed := _registry_execute(
		EffectsScript.EX_FIST,
		_context(stage_state, "ally", "fist", false, _ratios()), stage_kit["ports"],
	)
	harness.assert_false(stage_failed["ok"])
	harness.assert_contains(stage_failed["error"], "no combat state committed")
	harness.assert_equal(str(stage_state), stage_before)
	harness.assert_equal(stage_run["permanent_buffs"], [])
	harness.assert_equal(stage_rng.cursor, 0, "failed growth must not consume combat target RNG")


func _test_fist_ultimate(harness: TestHarness) -> void:
	var state := _state()
	var caster := _caster(state, "ally", "fist")
	caster["fist_momentum"] = 4
	var run_state := {"permanent_buffs": [{
		"id": "fistMastery", "target": {"type": "hero", "id": 6}, "stacks": 5,
	}]}
	var damage := ControlledDamage.new()
	var kit := _kit(state, FixedRng.new([0]), run_state, {}, damage)
	var result := _registry_execute(
		EffectsScript.ULT_FIST,
		_context(state, "ally", "fist", true, _ratios()), kit["ports"],
	)
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["base_hits"], 8)
	harness.assert_equal(result["value"]["hits"], 8)
	harness.assert_equal(caster["fist_momentum"], 4)
	harness.assert_equal(run_state["permanent_buffs"][0]["stacks"], 5)
	harness.assert_equal(damage.metadata_records.map(func(value: Dictionary) -> Variant: return value.get("presentation_wave_index")), range(0, int(result["value"]["hits"])), "宁不凡大招 gives every sequential strike its own presentation hit index")

	var kill_state := _state()
	for unit: Dictionary in kill_state["enemies"]:
		unit["hp"] = 6.0
		unit["max_hp"] = 6.0
	var kill_damage := ControlledDamage.new()
	var kill_kit := _kit(kill_state, FixedRng.new([0, 0, 0, 0, 0, 0]), null, {}, kill_damage)
	var kills := _execute(EffectsScript.ULT_FIST, kill_state, "ally", "fist", true, kill_kit["ports"])
	harness.assert_true(kills["ok"])
	harness.assert_equal(kills["value"]["base_hits"], 3)
	harness.assert_equal(kills["value"]["hits"], 6)
	harness.assert_equal(kills["value"]["kills"], 6)
	harness.assert_true(kill_state["enemies"].all(func(unit: Dictionary) -> bool: return not unit["alive"]))

	var enemy_state := _state()
	var enemy_damage := ControlledDamage.new()
	var enemy_kit := _kit(enemy_state, FixedRng.new([5]), null, {}, enemy_damage)
	var enemy := _execute(EffectsScript.ULT_FIST, enemy_state, "enemy", "fist", true, enemy_kit["ports"])
	harness.assert_true(enemy["ok"])
	harness.assert_equal(enemy["value"]["hits"], 3)
	harness.assert_equal(enemy_damage.records[0]["effect"]["source_side"], "enemy")
	harness.assert_equal(enemy_state["enemy_heroes"][2]["fist_momentum"], 0)

	var failure_state := _state()
	var failure_damage := ControlledDamage.new()
	failure_damage.fail_at = 2
	var failure_kit := _kit(failure_state, FixedRng.new([0]), null, {}, failure_damage)
	var failure := _execute(EffectsScript.ULT_FIST, failure_state, "ally", "fist", true, failure_kit["ports"])
	harness.assert_false(failure["ok"])
	harness.assert_contains(failure["error"], "state committed")
	harness.assert_equal(failure_damage.records.size(), 1)
	harness.assert_equal(_caster(failure_state, "ally", "fist")["fist_momentum"], 0)

	var empty := _state()
	for unit: Dictionary in empty["enemies"]:
		_kill(unit)
	var empty_kit := _kit(empty)
	var no_target := _execute(EffectsScript.ULT_FIST, empty, "ally", "fist", true, empty_kit["ports"])
	harness.assert_true(no_target["ok"])
	harness.assert_true(no_target["value"]["no_target"])
	harness.assert_equal(no_target["value"]["hits"], 0)


func _test_fail_closed_and_ports(harness: TestHarness) -> void:
	var state := _state()
	var kit := _kit(state)
	var context := _context(state, "ally", "fist", false)
	context["sp"] = 99
	var before := str(state)
	var invalid := _registry_execute(EffectsScript.EX_FIST, context, kit["ports"])
	harness.assert_false(invalid["ok"])
	harness.assert_contains(invalid["error"], "context")
	harness.assert_equal(str(state), before)

	var rng_state := _state()
	var invalid_rng := FixedRng.new()
	invalid_rng.invalid = true
	var rng_kit := _kit(rng_state, invalid_rng)
	var rng_before := str(rng_state)
	var rng_result := _execute(EffectsScript.EX_FIST, rng_state, "ally", "fist", false, rng_kit["ports"])
	harness.assert_false(rng_result["ok"])
	harness.assert_contains(rng_result["error"], "out-of-range")
	harness.assert_equal(str(rng_state), rng_before)

	var heal_state := _state()
	heal_state["allies"][0]["general"] = true
	heal_state["allies"][0]["hp"] = 20.0
	var heal_kit := _kit(heal_state, FixedRng.new(), null, {}, null, {"fail_heal": true})
	var heal_result := _execute(EffectsScript.ULT_ASCEND, heal_state, "ally", "ascend", true, heal_kit["ports"])
	harness.assert_false(heal_result["ok"])
	harness.assert_contains(heal_result["error"], "state committed")
	harness.assert_equal(heal_state["allies"][0]["hp"], 60.0)
	harness.assert_equal(_buff_stacks(heal_state["allies"][0], "march"), 0)
	harness.assert_equal(heal_kit["metrics"]["content_events"], 0)
	harness.assert_equal(heal_kit["metrics"]["combat_events"], 0)


func _test_battle_guards(harness: TestHarness) -> void:
	var handlers := [
		[EffectsScript.EX_COUNTER, "counterAura", false],
		[EffectsScript.EX_ASCEND, "ascend", false],
		[EffectsScript.EX_FIST, "fist", false],
		[EffectsScript.ULT_COUNTER, "counterAura", true],
		[EffectsScript.ULT_ASCEND, "ascend", true],
		[EffectsScript.ULT_FIST, "fist", true],
	]
	# The opposite Fate lock is checked for every handler on both sides. Ally
	# growth-capable handlers receive live GrowthPort actions to prove validation
	# rejects before snapshot/get/preview/stage as well as RNG/damage/Buff work.
	for side in ["ally", "enemy"]:
		for specification: Array in handlers:
			var state := _state()
			if side == "ally":
				state["enemy_fate"]["ally_lock"] = "noSkill"
			else:
				state["fate"]["enemy_lock"] = "noSkill"
			var run_state: Variant = (
				{"permanent_buffs": []}
				if side == "ally" and specification[1] in ["ascend", "fist"] else null
			)
			var rng := FixedRng.new([4, 3, 2])
			var damage := ControlledDamage.new()
			var kit := _kit(state, rng, run_state, {}, damage)
			var context := _context(
				state, side, specification[1], specification[2],
				_ratios() if run_state != null else null,
			)
			var state_before := BattleStateScript.snapshot(state)
			var run_before: Variant = run_state.duplicate(true) if run_state != null else null
			var result := _registry_execute(specification[0], context, kit["ports"])
			harness.assert_false(result["ok"])
			harness.assert_contains(result["error"], "prevents")
			harness.assert_equal(state, state_before)
			harness.assert_equal(run_state, run_before)
			harness.assert_equal(rng.cursor, 0)
			harness.assert_equal(damage.calls, 0)
			harness.assert_equal(kit["metrics"]["growth_actions"], 0)
			harness.assert_equal(kit["metrics"]["logs"], [])

	# Battle-end and the side's own piece-Fate guard are also symmetric.
	for side in ["ally", "enemy"]:
		var ended := _state()
		ended["game_over"] = true
		ended["battle_result"] = "win" if side == "ally" else "lose"
		var ended_rng := FixedRng.new([5])
		var ended_damage := ControlledDamage.new()
		var ended_kit := _kit(ended, ended_rng, null, {}, ended_damage)
		var ended_before := BattleStateScript.snapshot(ended)
		var ended_result := _execute(
			EffectsScript.ULT_COUNTER, ended, side, "counterAura", true, ended_kit["ports"],
		)
		harness.assert_false(ended_result["ok"])
		harness.assert_contains(ended_result["error"], "battle end")
		harness.assert_equal(ended, ended_before)
		harness.assert_equal(ended_rng.cursor, 0)
		harness.assert_equal(ended_damage.calls, 0)
		harness.assert_equal(ended_kit["metrics"]["growth_actions"], 0)

		var fate_locked := _state()
		var fate: Dictionary = fate_locked["fate" if side == "ally" else "enemy_fate"]
		fate["active"] = true
		fate["mode"] = "棋子命运"
		fate["all_in_turns"] = 0
		var fate_rng := FixedRng.new([5])
		var fate_damage := ControlledDamage.new()
		var fate_kit := _kit(fate_locked, fate_rng, null, {}, fate_damage)
		var fate_before := BattleStateScript.snapshot(fate_locked)
		var fate_result := _execute(
			EffectsScript.ULT_COUNTER, fate_locked, side, "counterAura", true, fate_kit["ports"],
		)
		harness.assert_false(fate_result["ok"])
		harness.assert_contains(fate_result["error"], "piece Fate")
		harness.assert_equal(fate_locked, fate_before)
		harness.assert_equal(fate_rng.cursor, 0)
		harness.assert_equal(fate_damage.calls, 0)
		harness.assert_equal(fate_kit["metrics"]["growth_actions"], 0)


func _execute(
	effect_id: String,
	state: Dictionary,
	side: String,
	skill_id: String,
	ultimate: bool,
	ports: Variant,
) -> Dictionary:
	return _registry_execute(effect_id, _context(state, side, skill_id, ultimate), ports)


func _registry_execute(effect_id: String, context: Dictionary, ports: Variant) -> Dictionary:
	var registry := EffectRegistryScript.new()
	assert(registry.register_map(EffectsScript.handler_map()))
	return registry.execute(effect_id, context, ports)


func _context(
	state: Dictionary,
	side: String,
	skill_id: String,
	ultimate: bool,
	ratios: Variant = null,
) -> Dictionary:
	var caster := _caster(state, side, skill_id)
	var effect := ContextsScript.create_effect_context({
		"source_type": (
			ContextsScript.EFFECT_SOURCE_TYPE["ULTIMATE"]
			if ultimate else ContextsScript.EFFECT_SOURCE_TYPE["EXCLUSIVE_SKILL"]
		),
		"source_id": skill_id,
		"source_name": skill_id,
		"source_side": side,
		"source_actor_id": caster["id"],
		"counts_as_skill_cast": true,
	})
	var context := {"state": state, "caster": caster, "source_effect": effect}
	if ratios != null:
		context["growth_piece_ratios"] = ratios
	return context


func _caster(state: Dictionary, side: String, skill_id: String) -> Dictionary:
	var heroes: Array = state["player_heroes"] if side == "ally" else state["enemy_heroes"]
	for hero: Dictionary in heroes:
		if hero["ex_skill"] == skill_id:
			return hero
	assert(false)
	return {}


func _kit(
	state: Dictionary,
	rng: Variant = null,
	run_state: Variant = null,
	action_overrides: Dictionary = {},
	damage_override: Variant = null,
	metric_options: Dictionary = {},
) -> Dictionary:
	var catalog_errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(catalog_errors)
	assert(catalog_errors.is_empty())
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": state,
		"catalog": catalog["buffs"],
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
	}, buff_errors)
	assert(buff_errors.is_empty())
	var metrics := {
		"logs": [], "heals": [], "content_events": 0, "combat_events": 0,
		"growth_actions": 0,
		"fail_heal": metric_options.get("fail_heal", false),
	}
	var actions := {
		"emit_combat_event": func(_request: Dictionary) -> Dictionary:
			metrics["combat_events"] += 1
			return CombatPortsScript.ok(null),
		"emit_content_event": func(_request: Dictionary) -> Dictionary:
			metrics["content_events"] += 1
			return CombatPortsScript.ok(null),
		"log": func(request: Dictionary) -> Dictionary:
			metrics["logs"].append(request.duplicate(true))
			return CombatPortsScript.ok(null),
		"on_battle_resolved": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_damage": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_heal": func(request: Dictionary) -> Dictionary:
			if metrics["fail_heal"]:
				return CombatPortsScript.fail("injected record_heal failure")
			metrics["heals"].append(request.duplicate(true))
			return CombatPortsScript.ok(null),
		"resolve_battle_end": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(true),
	}
	var growth_port: Variant = null
	if run_state != null:
		var growth_errors: Array[String] = []
		growth_port = GrowthPortScript.new({
			"run_state": run_state,
			"catalog": catalog["buffs"],
			"valid_hero_ids": catalog["characters"]["players"].keys(),
		}, growth_errors)
		assert(growth_errors.is_empty())
		for action_id: String in growth_port.action_map():
			actions[action_id] = _recording_growth_action(
				growth_port.action_map()[action_id], metrics,
			)
	actions.merge(action_overrides, true)
	var combat_rng: Variant = rng if rng != null else FixedRng.new()
	var damage: Variant = damage_override if damage_override != null else ControlledDamage.new()
	var port_errors: Array[String] = []
	var ports := CombatPortsScript.new({
		"actions": actions,
		"services": {
			"combat_rng": combat_rng,
			"enemy_policy_rng": FixedRng.new([1]),
			"damage": damage,
			"buffs": buffs,
			"tuning": catalog["tuning"],
			"catalogs": catalog,
		},
	}, port_errors)
	assert(port_errors.is_empty(), str(port_errors))
	return {
		"ports": ports, "metrics": metrics, "damage": damage,
		"growth_port": growth_port,
	}


func _recording_growth_action(action: Callable, metrics: Dictionary) -> Callable:
	return func(request: Dictionary) -> Dictionary:
		metrics["growth_actions"] += 1
		return action.call(request)


func _state() -> Dictionary:
	var source := {
		"round": 1, "phase": "player_input",
		"sp": 4.0, "sp_max": 6.0, "base_sp_max": 6.0,
		"enemy_sp": 4.0, "enemy_sp_max": 6.0,
		"allies": _team("ally"), "enemies": _team("enemy"),
		"player_heroes": [
			_player_hero(3, "元帅", "ascend"),
			_player_hero(4, "骑士", "counterAura"),
			_player_hero(6, "宁不凡", "fist"),
		],
		"enemy_heroes": [
			_enemy_hero(103, "敌元帅", "ascend"),
			_enemy_hero(104, "敌骑士", "counterAura"),
			_enemy_hero(106, "敌宁", "fist"),
		],
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
	var state := BattleStateScript.create(source, errors)
	assert(errors.is_empty())
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


func _player_hero(id: int, name: String, skill: String) -> Dictionary:
	return {
		"id": id, "name": name, "deployed": true, "ex_skill": skill,
		"energy": 0.0, "max_energy": 100.0, "base_crit_rate": 0.05,
		"fist_momentum": 0,
	}


func _enemy_hero(id: int, name: String, skill: String) -> Dictionary:
	return {
		"id": id, "name": name, "ex_skill": skill,
		"skills": [], "skill_pool": ["smallHeal"],
		"energy": 0.0, "max_energy": 100.0, "base_crit_rate": 0.05,
		"fist_momentum": 0,
	}


func _ratios() -> Dictionary:
	return {1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0, 5: 1.0, 6: 1.0}


func _kill(unit: Dictionary) -> void:
	unit["hp"] = 0.0
	unit["alive"] = false


func _buff_stacks(unit: Dictionary, id: String) -> int:
	for buff: Dictionary in unit["buffs"]:
		if buff["id"] == id:
			return int(buff["stacks"])
	return 0


func _buff_turns(unit: Dictionary, id: String) -> int:
	for buff: Dictionary in unit["buffs"]:
		if buff["id"] == id:
			return int(buff["turns"])
	return 0
