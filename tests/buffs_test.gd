extends RefCounted

const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const BuffDefinition = preload("res://data/definitions/buff_definition.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const BuffEffectsScript = preload("res://systems/buffs/buff_effects.gd")
const BurnSettlementScript = preload("res://systems/buffs/burn.gd")
const Contexts = preload("res://core/contexts.gd")
const Damage = preload("res://core/damage.gd")
const Rng = preload("res://core/rng.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("BuffSystem requires explicit M1 authority and initializes side state", func() -> void:
		_test_construction(harness)
	)
	harness.run_test("battle Buff mutations reject permanent scope and invalid values atomically", func() -> void:
		_test_fail_closed_mutations(harness)
	)
	harness.run_test("all unit mutations reject malformed canonical holders without events", func() -> void:
		_test_malformed_unit_holders(harness)
	)
	harness.run_test("all side mutations reject malformed canonical state without events", func() -> void:
		_test_malformed_side_state(harness)
	)
	harness.run_test("unit and side stack consume clear and events match Web order", func() -> void:
		_test_stack_consume_clear(harness)
	)
	harness.run_test("enchantments obey capacity FIFO while ordinary Buffs ignore slots", func() -> void:
		_test_enchantment_capacity(harness)
	)
	harness.run_test("battle damage and block callbacks apply authored Buff effects", func() -> void:
		_test_effective_buff_values(harness)
	)
	harness.run_test("layer durations duplicate decay and synchronize state", func() -> void:
		_test_layer_lifecycle(harness)
	)
	harness.run_test("round decay visits sides before units and only expires declared Buffs", func() -> void:
		_test_round_decay(harness)
	)
	harness.run_test("Buff snapshots and event payloads are deeply isolated", func() -> void:
		_test_buff_isolation(harness)
	)
	harness.run_test("burn delayed damage settles before layer decay without RNG", func() -> void:
		_test_burn_pipeline(harness)
	)
	harness.run_test("burn rejects empty DamagePipeline results before decay or settled callback", func() -> void:
		_test_burn_callback_failure(harness)
	)
	harness.run_test("burn statically preflights the whole input batch before first damage", func() -> void:
		_test_burn_batch_preflight(harness)
	)
	harness.run_test("burn returns the committed prefix when a later callback fails structurally", func() -> void:
		_test_burn_sequential_commit(harness)
	)
	harness.run_test("burn settlement is reentrant and each unit settles once per outer call", func() -> void:
		_test_burn_reentry(harness)
	)
	harness.run_test("burn result snapshots isolate compounds while preserving unit reference", func() -> void:
		_test_burn_result_isolation(harness)
	)
	print("B1 BUFF TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_construction(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var state := {"side_buffs": {"ally": [{"id": "old"}], "enemy": [{"id": "old"}]}}
	var events: Array = []
	var system := BuffSystemScript.new({
		"state": state,
		"catalog": _catalog()["buffs"],
		"on_event": func(type: String, payload: Dictionary) -> void:
			events.append({"type": type, "payload": payload}),
	}, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(system.is_valid())
	harness.assert_equal(state["side_buffs"], {"ally": [], "enemy": []})
	harness.assert_equal(events, [])
	var definition: Variant = system.definition_for("burn", "unit", errors)
	harness.assert_equal(definition.id, "burn")
	definition.id = "mutated"
	harness.assert_equal(system.definition_for("burn").id, "burn")

	var invalid := BuffSystemScript.new({"state": state, "catalog": {}, "on_event": Callable()}, errors)
	harness.assert_false(invalid.is_valid())
	harness.assert_true(not errors.is_empty())


func _test_fail_closed_mutations(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var system: Variant = setup["system"]
	var unit := _unit()
	var errors: Array[String] = []
	var before: Array = unit["buffs"]
	harness.assert_false(system.apply_unit(unit, "flameEnchant", 1, null, errors))
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("permanent")))
	harness.assert_true(is_same(unit["buffs"], before))
	harness.assert_equal(setup["events"], [])

	errors.clear()
	harness.assert_false(system.apply_unit(unit, "tempBlock", 1, null, errors))
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("side scope")))
	harness.assert_true(is_same(unit["buffs"], before))

	for invalid: Variant in [0, -1, 1.5, NAN, INF, "2"]:
		errors.clear()
		harness.assert_false(system.apply_unit(unit, "burn", invalid, 2, errors))
		harness.assert_true(not errors.is_empty())
		harness.assert_true(is_same(unit["buffs"], before))
	harness.assert_equal(setup["events"], [])

	# decay_round preflights all scopes before touching the first side. This
	# intentionally malformed battle holder must not partially expire tempBlock.
	system.apply_side("ally", "tempBlock")
	unit["buffs"] = [{"id": "flameEnchant", "stacks": 1, "turns": 0, "layer_turns": []}]
	var side_before: Array = setup["state"]["side_buffs"]["ally"]
	var unit_before: Array = unit["buffs"]
	errors.clear()
	harness.assert_equal(system.decay_round([unit], errors), [])
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("permanent")))
	harness.assert_true(is_same(setup["state"]["side_buffs"]["ally"], side_before))
	harness.assert_true(is_same(unit["buffs"], unit_before))


func _test_malformed_unit_holders(harness: TestHarness) -> void:
	var malformed_units := [
		{"id": 1, "side": "ally", "alive": true},
		{"id": 1, "side": "ally", "alive": true, "buffs": {}},
		{"id": 0, "side": "ally", "alive": true, "buffs": []},
		{"id": 1, "side": "neutral", "alive": true, "buffs": []},
		{"id": 1, "side": "ally", "alive": 1, "buffs": []},
		{"id": 1, "side": "ally", "alive": true, "buffs": [{
			"id": "burn", "stacks": 1, "turns": 2, "layer_turns": [2], "extra": true,
		}]},
		{"id": 1, "side": "ally", "alive": true, "buffs": [{
			"id": "burn", "stacks": 2, "turns": 2, "layer_turns": [2],
		}]},
		{"id": 1, "side": "ally", "alive": true, "buffs": [{
			"id": "burn", "stacks": 1, "turns": 0, "layer_turns": [0],
		}]},
		{"id": 1, "side": "ally", "alive": true, "buffs": [{
			"id": "tempBlock", "stacks": 1, "turns": 1, "layer_turns": [],
		}]},
		{"id": 1, "side": "ally", "alive": true, "buffs": [{
			"id": "flameEnchant", "stacks": 1, "turns": 0, "layer_turns": [],
		}]},
	]
	for malformed: Dictionary in malformed_units:
		var setup := _buff_harness()
		var before := malformed.duplicate(true)
		var errors: Array[String] = []
		harness.assert_false(setup["system"].apply_unit(malformed, "pursuit", 1, null, errors))
		harness.assert_true(not errors.is_empty())
		harness.assert_equal(malformed, before)
		harness.assert_equal(setup["events"], [])

	var setup := _buff_harness()
	var broken := {"id": 1, "side": "ally", "alive": true, "buffs": null}
	var broken_before := broken.duplicate(true)
	var errors: Array[String] = []
	harness.assert_false(setup["system"].reset_unit(broken, errors))
	harness.assert_equal(broken, broken_before)
	harness.assert_equal(setup["events"], [])


func _test_malformed_side_state(harness: TestHarness) -> void:
	var malformed_values := [
		{"ally": []},
		{"ally": [], "enemy": [], "neutral": []},
		{"ally": {}, "enemy": []},
		{"ally": [{"id": "burn", "stacks": 1, "turns": 2, "layer_turns": [2]}], "enemy": []},
		{"ally": [{"id": "tempBlock", "stacks": 2, "turns": 1, "layer_turns": []}], "enemy": []},
	]
	for malformed: Dictionary in malformed_values:
		var setup := _buff_harness()
		setup["state"]["side_buffs"] = malformed
		var before: Dictionary = malformed.duplicate(true)
		var reference: Dictionary = setup["state"]["side_buffs"]
		var errors: Array[String] = []
		harness.assert_false(setup["system"].apply_side("ally", "tempBlock", 1, null, errors))
		harness.assert_true(not errors.is_empty())
		harness.assert_true(is_same(setup["state"]["side_buffs"], reference))
		harness.assert_equal(setup["state"]["side_buffs"], before)
		harness.assert_equal(setup["events"], [])

	var setup := _buff_harness()
	setup["state"]["side_buffs"] = null
	var errors: Array[String] = []
	harness.assert_false(setup["system"].reset_sides(errors))
	harness.assert_equal(setup["state"]["side_buffs"], null)
	harness.assert_equal(setup["events"], [])


func _test_stack_consume_clear(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var system: Variant = setup["system"]
	var unit := _unit()
	harness.assert_true(system.apply_unit(unit, "enchant", 4))
	harness.assert_true(system.apply_unit(unit, "enchant", 4))
	harness.assert_true(system.apply_unit(unit, "march", 1, 1))
	harness.assert_true(system.apply_unit(unit, "march", 1, 3))
	harness.assert_equal(system.get_unit_stacks(unit, "enchant"), 5)
	harness.assert_equal(system.get_unit_turns(unit, "march"), 3)
	harness.assert_equal(system.consume_unit(unit, "enchant", 2), 2)
	harness.assert_equal(system.get_unit_stacks(unit, "enchant"), 3)
	harness.assert_true(system.clear_unit(unit, "enchant"))
	harness.assert_false(system.has_unit(unit, "enchant"))
	harness.assert_equal(
		setup["events"].map(func(event: Dictionary) -> String: return event["type"]),
		["buff_applied", "buff_applied", "buff_applied", "buff_applied", "buff_consumed", "buff_cleared"],
	)
	harness.assert_equal(
		setup["events"].map(func(event: Dictionary) -> int: return event["payload"]["sequence"]),
		[1, 2, 3, 4, 5, 6],
	)

	harness.assert_true(system.apply_side("ally", "tempBlock"))
	harness.assert_equal(system.consume_side("ally", "tempBlock"), 1)
	harness.assert_true(system.has_side("ally", "tempBlock"))
	harness.assert_equal(system.get_side_state("ally", "tempBlock"), {
		"id": "tempBlock", "stacks": 0, "turns": 1, "layer_turns": [],
	})
	harness.assert_true(system.clear_side("ally", "tempBlock"))
	harness.assert_false(system.has_side("ally", "tempBlock"))
	system.apply_unit(unit, "pursuit", 1)
	harness.assert_true(system.reset_unit(unit))
	harness.assert_equal(unit["buffs"], [])
	system.apply_side("enemy", "pieceDamageUp")
	harness.assert_true(system.reset_sides())
	harness.assert_equal(setup["state"]["side_buffs"], {"ally": [], "enemy": []})


func _test_enchantment_capacity(harness: TestHarness) -> void:
	var third_enchantment := BuffDefinition.new(
		"runeProbe", "测试符文", "unit", false, false, 1, 0,
		false, false, "测试第三种附魔。", "battle", [], "enchantment",
	)
	var setup := _buff_harness({"runeProbe": third_enchantment})
	var buffs: Variant = setup["system"]
	var unit := _unit(1, "ally", {
		"atk": 10.0, "base_block_rate": 0.1, "crit_rate": 0.05,
		"general": false, "is_puppet": false,
	})
	harness.assert_equal(buffs.get_unit_enchantment_capacity(unit), 2)
	harness.assert_true(buffs.apply_unit(unit, "general"))
	unit["general"] = true
	unit["max_hp"] += 80.0
	unit["hp"] += 80.0
	unit["base_block_rate"] += 0.1
	unit["crit_rate"] += 0.05
	harness.assert_true(buffs.apply_unit(unit, "enchant", 2))
	harness.assert_equal(buffs.get_unit_enchantment_ids(unit), ["general", "enchant"])
	harness.assert_true(buffs.apply_unit(unit, "general"), "same enchantment refreshes in place")
	unit["atk"] += 3.0
	unit["base_block_rate"] += 0.03
	unit["crit_rate"] += 0.03
	harness.assert_equal(buffs.get_unit_enchantment_ids(unit), ["general", "enchant"])
	harness.assert_true(buffs.apply_unit(unit, "march", 1, 2))
	harness.assert_equal(buffs.get_unit_enchantment_ids(unit), ["general", "enchant"], "ordinary Buffs do not consume enchantment slots")

	harness.assert_true(buffs.apply_unit(unit, "runeProbe"), "a third enchantment evicts the oldest")
	harness.assert_equal(buffs.get_unit_enchantment_ids(unit), ["enchant", "runeProbe"])
	harness.assert_false(unit["general"])
	harness.assert_equal(unit["max_hp"], 200.0)
	harness.assert_equal(unit["hp"], 200.0)
	harness.assert_equal(unit["atk"], 10.0)
	harness.assert_true(is_equal_approx(unit["base_block_rate"], 0.1), "two General stacks revert first and doubled repeat block")
	harness.assert_true(is_equal_approx(unit["crit_rate"], 0.05), "two General stacks revert first and doubled repeat crit")
	harness.assert_equal(setup["events"].filter(func(event: Dictionary) -> bool: return event["type"] == "buff_evicted").size(), 1)

	var puppet := _unit(2, "ally", {"is_puppet": true})
	var errors: Array[String] = []
	harness.assert_equal(buffs.get_unit_enchantment_capacity(puppet), 0)
	harness.assert_false(buffs.apply_unit(puppet, "enchant", 1, null, errors))
	harness.assert_true(not errors.is_empty())
	harness.assert_true(buffs.set_unit_enchantment_capacity(puppet, 1))
	harness.assert_true(buffs.apply_unit(puppet, "enchant"))


func _test_effective_buff_values(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var buffs: Variant = setup["system"]
	var catalog := _catalog()
	var attacker := _unit(1, "ally", {"echo_damage_bonus": 0.2})
	var target := _unit(2, "enemy", {"base_block_rate": 0.1})
	buffs.apply_side("enemy", "tempBlock")
	harness.assert_true(is_equal_approx(
		BuffEffectsScript.effective_block_rate(target, buffs, catalog["tuning"]), 0.25,
	))
	buffs.apply_side("ally", "pieceDamageUp")
	buffs.apply_unit(attacker, "vexed")
	buffs.apply_unit(target, "bloodShiftVulnerable")
	var direct := {
		"category": "direct", "dealer_type": "piece",
		"effect": {"source_side": "ally"},
	}
	var multiplier := BuffEffectsScript.damage_multiplier(
		target, direct, {"attacker_unit": attacker}, buffs, catalog["tuning"],
	)
	harness.assert_true(is_equal_approx(multiplier, 1.25 * 0.75 * 1.2 * 1.25))
	var delayed := direct.duplicate(true)
	delayed["category"] = "delayed"
	harness.assert_equal(
		BuffEffectsScript.damage_multiplier(target, delayed, {"attacker_unit": attacker}, buffs, catalog["tuning"]),
		1.0,
	)


func _test_layer_lifecycle(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var system: Variant = setup["system"]
	var unit := _unit()
	system.apply_unit(unit, "burn", 2, 2)
	system.apply_unit(unit, "burn", 1, 3)
	harness.assert_equal(system.get_unit_state(unit, "burn"), {
		"id": "burn", "stacks": 3, "turns": 3, "layer_turns": [2, 2, 3],
	})
	harness.assert_equal(system.duplicate_layers(unit, "burn", 1), 3)
	harness.assert_equal(system.get_unit_state(unit, "burn")["layer_turns"], [3, 3, 4, 3, 3, 4])
	harness.assert_equal(system.decay_layers(unit, "burn", 3), 4)
	harness.assert_equal(system.get_unit_state(unit, "burn"), {
		"id": "burn", "stacks": 2, "turns": 1, "layer_turns": [1, 1],
	})
	harness.assert_equal(system.decay_layers(unit, "burn"), 2)
	harness.assert_false(system.has_unit(unit, "burn"))
	harness.assert_equal(
		setup["events"].filter(func(event: Dictionary) -> bool: return event["type"] == "buff_expired")
			.map(func(event: Dictionary) -> int: return event["payload"]["amount"]),
		[4, 2],
	)


func _test_round_decay(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var system: Variant = setup["system"]
	var unit := _unit()
	system.apply_unit(unit, "pursuit", 2)
	system.apply_unit(unit, "vexed")
	system.apply_side("ally", "tempBlock")
	system.apply_side("ally", "flameLeech", 1, 2)
	var expired: Array[Dictionary] = system.decay_round([unit])
	harness.assert_true(system.has_unit(unit, "pursuit"))
	harness.assert_false(system.has_unit(unit, "vexed"))
	harness.assert_false(system.has_side("ally", "tempBlock"))
	harness.assert_equal(system.get_side_turns("ally", "flameLeech"), 1)
	harness.assert_equal(
		expired.map(func(item: Dictionary) -> String: return "%s:%s" % [item["scope"], item["id"]]),
		["side:tempBlock", "unit:vexed"],
	)
	var event_types: Array = setup["events"].map(func(event: Dictionary) -> String: return event["type"])
	harness.assert_true(event_types.find("side_buff_expired") < event_types.find("buff_expired"))


func _test_buff_isolation(harness: TestHarness) -> void:
	var state := {"side_buffs": {}}
	var observed: Array = []
	var system := BuffSystemScript.new({
		"state": state,
		"catalog": _catalog()["buffs"],
		"on_event": func(type: String, payload: Dictionary) -> void:
			observed.append({"type": type, "payload": payload.duplicate(true)})
			if payload.get("state") != null:
				payload["state"]["layer_turns"].append(99),
	})
	var first := _unit(1)
	var second := _unit(2)
	system.apply_unit(first, "burn", 1, 2)
	system.apply_unit(second, "burn", 1, 3)
	var first_snapshot: Dictionary = system.get_unit_state(first, "burn")
	first_snapshot["layer_turns"].append(77)
	harness.assert_equal(system.get_unit_state(first, "burn")["layer_turns"], [2])
	harness.assert_equal(system.get_unit_state(second, "burn")["layer_turns"], [3])
	harness.assert_false(is_same(first["buffs"], second["buffs"]))
	harness.assert_false(is_same(first["buffs"][0], second["buffs"][0]))
	harness.assert_equal(observed[0]["payload"]["state"]["layer_turns"], [2])


func _test_burn_pipeline(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var system: Variant = setup["system"]
	var victim := _unit(1, "enemy", {"hp": 100.0, "max_hp": 100.0})
	system.apply_unit(victim, "burn", 1, 1)
	system.apply_unit(victim, "burn", 1, 2)
	var random := Rng.seeded("B1-burn-no-rng")
	var control := Rng.seeded("B1-burn-no-rng")
	var pipeline: Variant = _pipeline({
		"random": Callable(random, "next"),
		"on_event": func(type: String, payload: Dictionary) -> void:
			setup["events"].append({"type": type, "payload": payload}),
	})
	var settlement := BurnSettlementScript.new({
		"buff_system": system,
		"damage_per_stack": 2,
		"apply_damage_context": func(unit: Dictionary, context: Dictionary) -> Dictionary:
			return pipeline.apply(unit, context),
		"on_settled": func(_result: Dictionary) -> void: pass,
	})
	var results: Array[Dictionary] = settlement.settle([victim])
	harness.assert_equal(results.size(), 1)
	harness.assert_equal(results[0]["stacks_before"], 2)
	harness.assert_equal(results[0]["damage"]["dealt"], 4.0)
	harness.assert_equal(victim["hp"], 96.0)
	harness.assert_equal(system.get_unit_stacks(victim, "burn"), 1)
	harness.assert_equal(results[0]["damage_context"]["category"], "delayed")
	harness.assert_false(results[0]["damage_context"]["can_crit"])
	harness.assert_false(results[0]["damage_context"]["can_block"])
	harness.assert_equal(random.next(), control.next(), "burn must consume neither crit nor block RNG")
	harness.assert_equal(
		setup["events"].slice(-2).map(func(event: Dictionary) -> String: return event["type"]),
		["unit_damaged", "buff_expired"],
	)


func _test_burn_callback_failure(harness: TestHarness) -> void:
	for callback_result: Dictionary in [{}, {"dealt": 2.0}]:
		var setup := _buff_harness()
		var unit := _unit(1, "enemy", {"hp": 20.0, "max_hp": 20.0})
		setup["system"].apply_unit(unit, "burn", 1, 2)
		var buffs_before: Array = unit["buffs"]
		var event_count: int = setup["events"].size()
		var settled_count := [0]
		var settlement := BurnSettlementScript.new({
			"buff_system": setup["system"],
			"damage_per_stack": 2,
			"apply_damage_context": func(_target: Dictionary, _context: Dictionary) -> Dictionary:
				return callback_result.duplicate(true),
			"on_settled": func(_result: Dictionary) -> void: settled_count[0] += 1,
		})
		var errors: Array[String] = []
		harness.assert_equal(settlement.settle([unit], true, errors), [])
		harness.assert_true(not errors.is_empty())
		harness.assert_equal(unit["hp"], 20.0)
		harness.assert_true(is_same(unit["buffs"], buffs_before))
		harness.assert_equal(setup["system"].get_unit_state(unit, "burn")["layer_turns"], [2])
		harness.assert_equal(setup["events"].size(), event_count)
		harness.assert_equal(settled_count[0], 0)


func _test_burn_batch_preflight(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var first := _unit(1, "enemy", {"hp": 20.0, "max_hp": 20.0})
	var later := _unit(2, "enemy", {"hp": 20.0, "max_hp": 20.0})
	setup["system"].apply_unit(first, "burn", 1, 2)
	setup["system"].apply_unit(later, "burn", 1, 2)
	later["buffs"][0]["stacks"] = 2
	var first_buffs: Array = first["buffs"]
	var later_before := later.duplicate(true)
	var event_count: int = setup["events"].size()
	var damage_calls := [0]
	var settlement := BurnSettlementScript.new({
		"buff_system": setup["system"],
		"damage_per_stack": 2,
		"apply_damage_context": func(_target: Dictionary, _context: Dictionary) -> Dictionary:
			damage_calls[0] += 1
			return {},
		"on_settled": func(_result: Dictionary) -> void: pass,
	})
	var errors: Array[String] = []
	harness.assert_equal(settlement.settle([first, later], true, errors), [])
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("inconsistent")))
	harness.assert_equal(damage_calls[0], 0)
	harness.assert_equal(first["hp"], 20.0)
	harness.assert_true(is_same(first["buffs"], first_buffs))
	harness.assert_equal(later, later_before)
	harness.assert_equal(setup["events"].size(), event_count)


func _test_burn_sequential_commit(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var first := _unit(1, "enemy", {"hp": 20.0, "max_hp": 20.0})
	var second := _unit(2, "enemy", {"hp": 20.0, "max_hp": 20.0})
	setup["system"].apply_unit(first, "burn", 1, 2)
	setup["system"].apply_unit(second, "burn", 1, 2)
	var pipeline: Variant = _pipeline()
	var calls := [0]
	var settled := [0]
	var settlement := BurnSettlementScript.new({
		"buff_system": setup["system"],
		"damage_per_stack": 2,
		"apply_damage_context": func(target: Dictionary, context: Dictionary) -> Dictionary:
			calls[0] += 1
			return pipeline.apply(target, context) if calls[0] == 1 else {},
		"on_settled": func(_result: Dictionary) -> void: settled[0] += 1,
	})
	var errors: Array[String] = []
	var results: Array[Dictionary] = settlement.settle([first, second], true, errors)
	harness.assert_equal(results.size(), 1)
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(calls[0], 2)
	harness.assert_equal(settled[0], 1)
	harness.assert_equal(first["hp"], 18.0)
	harness.assert_equal(setup["system"].get_unit_state(first, "burn")["layer_turns"], [1])
	harness.assert_equal(second["hp"], 20.0)
	harness.assert_equal(setup["system"].get_unit_state(second, "burn")["layer_turns"], [2])


func _test_burn_reentry(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var system: Variant = setup["system"]
	var first := _unit(1, "enemy", {"hp": 100.0, "max_hp": 100.0})
	var victim := _unit(2, "enemy", {"hp": 1.0, "max_hp": 100.0})
	var last := _unit(3, "enemy", {"hp": 100.0, "max_hp": 100.0})
	var units := [first, victim, last]
	system.apply_unit(victim, "burn", 1, 2)
	var random_calls := [0]
	var settlement_holder := [null]
	var pipeline: Variant = _pipeline({
		"random": func() -> float:
			random_calls[0] += 1
			return 0.0,
		"on_death": func(_unit: Dictionary, _death: Dictionary, _payload: Dictionary) -> void:
			system.apply_unit(first, "burn", 1, 2)
			system.apply_unit(last, "burn", 1, 2)
			settlement_holder[0].settle(units, false),
	})
	var settlement: Variant = BurnSettlementScript.new({
		"buff_system": system,
		"damage_per_stack": 2,
		"apply_damage_context": func(unit: Dictionary, context: Dictionary) -> Dictionary:
			return pipeline.apply(unit, context),
		"on_settled": func(_result: Dictionary) -> void: pass,
	})
	settlement_holder[0] = settlement
	var results: Array[Dictionary] = settlement.settle(units)
	harness.assert_equal(results.size(), 1, "nested results belong to the nested caller")
	harness.assert_false(victim["alive"])
	harness.assert_equal(first["hp"], 98.0)
	harness.assert_equal(last["hp"], 98.0)
	harness.assert_equal(system.get_unit_stacks(first, "burn"), 1)
	harness.assert_equal(system.get_unit_stacks(last, "burn"), 1)
	harness.assert_equal(random_calls[0], 0)
	harness.assert_false(settlement.is_active())
	settlement.settle([first], false)
	harness.assert_equal(first["hp"], 96.0, "coordination resets after the outer settlement")
	# Break the deliberate re-entry fixture cycle (pipeline -> holder -> settlement).
	settlement_holder[0] = null


func _test_burn_result_isolation(harness: TestHarness) -> void:
	var setup := _buff_harness()
	var system: Variant = setup["system"]
	var unit := _unit(1, "enemy", {"hp": 20.0, "max_hp": 20.0})
	system.apply_unit(unit, "burn", 1, 2)
	var callback_results: Array = []
	var pipeline: Variant = _pipeline()
	var settlement := BurnSettlementScript.new({
		"buff_system": system,
		"damage_per_stack": 2,
		"apply_damage_context": func(target: Dictionary, context: Dictionary) -> Dictionary:
			return pipeline.apply(target, context),
		"on_settled": func(result: Dictionary) -> void:
			callback_results.append(result)
			result["damage_context"]["effect"]["source_id"] = "callback-mutated",
	})
	var results: Array[Dictionary] = settlement.settle([unit], false)
	harness.assert_true(is_same(results[0]["unit"], unit))
	harness.assert_true(is_same(callback_results[0]["unit"], unit))
	harness.assert_equal(results[0]["damage_context"]["effect"]["source_id"], "burn_tick")
	results[0]["damage_context"]["effect"]["source_id"] = "caller-mutated"
	harness.assert_equal(callback_results[0]["damage_context"]["effect"]["source_id"], "callback-mutated")


func _buff_harness(extra_catalog: Dictionary = {}) -> Dictionary:
	var state := {"side_buffs": {"ally": [], "enemy": []}}
	var events: Array = []
	var errors: Array[String] = []
	var definitions: Dictionary = _catalog()["buffs"]
	definitions.merge(extra_catalog, true)
	var system := BuffSystemScript.new({
		"state": state,
		"catalog": definitions,
		"on_event": func(type: String, payload: Dictionary) -> void:
			events.append({"type": type, "payload": payload}),
	}, errors)
	assert(errors.is_empty())
	return {"state": state, "events": events, "system": system}


func _catalog() -> Dictionary:
	var errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(errors)
	assert(errors.is_empty())
	return catalog


func _unit(id: int = 1, side: String = "ally", overrides: Dictionary = {}) -> Dictionary:
	var unit := {
		"id": id, "side": side, "alive": true, "buffs": [],
		"hp": 200.0, "max_hp": 200.0,
	}
	unit.merge(overrides, true)
	return unit


func _pipeline(overrides: Dictionary = {}) -> Variant:
	var config := {
		"random": func() -> float: return 0.5,
		"format": func(value: float) -> float: return value,
		"get_block_rate": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 0.0,
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 1.0,
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"record_damage": func(_payload: Dictionary) -> void: pass,
	}
	config.merge(overrides, true)
	var errors: Array[String] = []
	var pipeline := Damage.new(config, errors)
	assert(errors.is_empty())
	return pipeline
