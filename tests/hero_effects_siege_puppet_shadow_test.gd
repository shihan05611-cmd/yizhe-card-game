extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const EffectsScript = preload("res://systems/effects/hero_effects_siege_puppet_shadow.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
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
	var fail := false
	var mutate_then_fail := false
	var calls := 0
	var records: Array[Dictionary] = []

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
		if mutate_then_fail:
			target["hp"] = maxf(0.0, float(target["hp"]) - 1.0)
			errors.append("injected damage failure after mutation")
			return {}
		if fail:
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
		record["target_side"] = target["side"]
		record["target_slot"] = target["slot"]
		records.append(record)
		return {
			"dealt": dealt, "blocked": false, "died": died,
			"crit": float(damage_context["crit_rate"]) >= 1.0,
			"damage_context": damage_context.duplicate(true), "death_context": null,
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
	harness.run_test("Siege Puppet Shadow handler ids integrate without SP energy or cast events", func() -> void:
		_test_handlers_and_m3_exclusion(harness)
	)
	harness.run_test("siege exclusive uses Web average formula priority RNG mark and death semantics", func() -> void:
		_test_siege_exclusive(harness)
	)
	harness.run_test("siege ultimate marks every living opponent and applies side field for both sides", func() -> void:
		_test_siege_ultimate(harness)
	)
	harness.run_test("puppet exclusive selects deterministic empty slot and creates a full fixed shape", func() -> void:
		_test_puppet_exclusive(harness)
	)
	harness.run_test("puppet attunement opens exactly one enchantment slot", func() -> void:
		_test_puppet_attunement(harness)
	)
	harness.run_test("puppet ultimate fills slots heals existing puppets and preserves Web martyr asymmetry", func() -> void:
		_test_puppet_ultimate(harness)
	)
	harness.run_test("shadow exclusive excludes puppets enforces n minus one and uses atk id tie break", func() -> void:
		_test_shadow_exclusive(harness)
	)
	harness.run_test("shadow ultimate targets by ratio hp id and returns a pending deterministic B4 sequence", func() -> void:
		_test_shadow_ultimate(harness)
	)
	harness.run_test("closed contexts preflight and injected failures report commit truthfully", func() -> void:
		_test_fail_closed_and_commit_semantics(harness)
	)
	print("B3-5C SIEGE PUPPET SHADOW EFFECT TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_handlers_and_m3_exclusion(harness: TestHarness) -> void:
	var expected := [
		EffectsScript.EX_PRESS_OPENING, EffectsScript.EX_PUPPET, EffectsScript.EX_PUPPET_ATTUNEMENT,
		EffectsScript.EX_SHADOW, EffectsScript.EX_SIEGE,
		EffectsScript.ULT_PUPPET, EffectsScript.ULT_SHADOW, EffectsScript.ULT_SIEGE,
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

	for side in ["ally", "enemy"]:
		for entry in [
			[EffectsScript.EX_SIEGE, "siege", false],
			[EffectsScript.ULT_SIEGE, "siege", true],
			[EffectsScript.EX_PUPPET, "puppet", false],
			[EffectsScript.ULT_PUPPET, "puppet", true],
			[EffectsScript.EX_SHADOW, "shadow", false],
			[EffectsScript.ULT_SHADOW, "shadow", true],
		]:
			var state := _state()
			if entry[1] == "puppet":
				_kill(_team(state, side)[2])
			var kit := _kit(state)
			var sp_before: Variant = state["sp"]
			var enemy_sp_before: Variant = state["enemy_sp"]
			var caster := _caster(state, side, entry[1])
			var energy_before: Variant = caster["energy"]
			var result := _execute(entry[0], state, side, entry[1], entry[2], kit["ports"])
			harness.assert_true(result["ok"], "%s %s" % [side, entry[0]])
			harness.assert_equal(state["sp"], sp_before)
			harness.assert_equal(state["enemy_sp"], enemy_sp_before)
			harness.assert_equal(caster["energy"], energy_before)
			harness.assert_equal(kit["metrics"]["content_events"], 0)
			harness.assert_equal(kit["metrics"]["combat_events"], 0)


func _test_siege_exclusive(harness: TestHarness) -> void:
	var state := _state()
	var kit := _kit(state, FixedRng.new([0]))
	var errors: Array[String] = []
	harness.assert_true(kit["buffs"].apply_unit(state["enemies"][0], "breakMarked", 1, null, errors))
	var result := _execute(EffectsScript.EX_SIEGE, state, "ally", "siege", false, kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["target_id"], 2, "marked id 1 is skipped before RNG")
	harness.assert_equal(result["value"]["dealt"], 8.0, "six alive atk10 / six * 0.8")
	harness.assert_equal(kit["damage"].records[0]["raw_amount"], 8.0)
	harness.assert_equal(_buff_stacks(state["enemies"][1], "breakMarked"), 1)

	var marked_state := _state()
	var marked_kit := _kit(marked_state, FixedRng.new([0]))
	for unit: Dictionary in marked_state["enemies"]:
		harness.assert_true(marked_kit["buffs"].apply_unit(unit, "breakMarked"))
	harness.assert_true(marked_kit["buffs"].apply_side("ally", "breakFormation", 1, 2))
	var marked := _execute(EffectsScript.EX_SIEGE, marked_state, "ally", "siege", false, marked_kit["ports"])
	harness.assert_true(marked["ok"])
	harness.assert_equal(marked_kit["damage"].records[0]["crit_rate"], 0.25)
	harness.assert_false(marked["value"]["marked"])

	var kill_state := _state()
	for unit: Dictionary in kill_state["enemies"]:
		unit["hp"] = 1.0
	var kill_kit := _kit(kill_state)
	var killed := _execute(EffectsScript.EX_SIEGE, kill_state, "ally", "siege", false, kill_kit["ports"])
	harness.assert_true(killed["ok"])
	harness.assert_false(kill_state["enemies"][0]["alive"])
	harness.assert_equal(_buff_stacks(kill_state["enemies"][0], "breakMarked"), 0)

	var empty_state := _state()
	for unit: Dictionary in empty_state["enemies"]:
		_kill(unit)
	var empty_kit := _kit(empty_state)
	var empty := _execute(EffectsScript.EX_SIEGE, empty_state, "ally", "siege", false, empty_kit["ports"])
	harness.assert_true(empty["ok"])
	harness.assert_true(empty["value"]["no_target"])


func _test_siege_ultimate(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var state := _state()
		_kill(_team(state, _other_side(side))[3])
		var kit := _kit(state)
		var result := _execute(EffectsScript.ULT_SIEGE, state, side, "siege", true, kit["ports"])
		harness.assert_true(result["ok"])
		harness.assert_equal(result["value"]["marked_target_ids"], [1, 2, 3, 5, 6])
		harness.assert_equal(result["value"]["turns"], 2)
		for unit: Dictionary in _team(state, _other_side(side)):
			harness.assert_equal(_buff_stacks(unit, "breakMarked"), 0 if unit["slot"] == 4 else 1)
		harness.assert_equal(_side_buff_turns(state, side, "breakFormation"), 2)


func _test_puppet_exclusive(harness: TestHarness) -> void:
	var state := _state()
	# Deliberately put slot 4 before slot 2; selection remains slot-deterministic.
	_kill(state["allies"][1])
	_kill(state["allies"][3])
	var temp: Dictionary = state["allies"][1]
	state["allies"][1] = state["allies"][3]
	state["allies"][3] = temp
	var kit := _kit(state)
	var result := _execute(EffectsScript.EX_PUPPET, state, "ally", "puppet", false, kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["summoned_slot"], 2)
	var puppet := _slot(state["allies"], 2)
	harness.assert_equal(_sorted_keys(puppet), _sorted_strings(BattleStateScript.UNIT_KEYS + BattleStateScript.OPTIONAL_UNIT_KEYS))
	harness.assert_true(puppet["alive"])
	harness.assert_true(puppet["is_puppet"])
	harness.assert_equal(puppet["class_id"], "puppet")
	harness.assert_equal(puppet["class_name"], "傀儡")
	harness.assert_equal(puppet["hp"], 100.0)
	harness.assert_equal(puppet["max_hp"], 100.0)
	harness.assert_equal(puppet["fixed_max_hp"], 100.0)
	harness.assert_equal(puppet["atk"], 0.0)
	harness.assert_equal(puppet["buffs"], [])
	harness.assert_false(puppet["general"])
	harness.assert_false(puppet["stealth_attack_ready"])
	harness.assert_equal(puppet["enchantment_capacity"], 0)

	var martyr_state := _state()
	martyr_state["ally_puppet_martyr_active"] = true
	_kill(martyr_state["allies"][0])
	var martyr_kit := _kit(martyr_state)
	var martyr := _execute(EffectsScript.EX_PUPPET, martyr_state, "ally", "puppet", false, martyr_kit["ports"])
	harness.assert_true(martyr["ok"])
	harness.assert_true(martyr_state["allies"][0]["puppet_martyr"])


func _test_puppet_attunement(harness: TestHarness) -> void:
	var state := _state()
	_make_puppet(state["allies"][2], 100.0, false)
	var kit := _kit(state)
	var context := _context(state, "ally", "puppetAttunement", false)
	context["target_unit_id"] = state["allies"][2]["id"]
	var result := _registry_execute(EffectsScript.EX_PUPPET_ATTUNEMENT, context, kit["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_equal(result["value"]["target_id"], state["allies"][2]["id"])
	harness.assert_equal(kit["buffs"].get_unit_enchantment_capacity(state["allies"][2]), 1)
	harness.assert_true(kit["buffs"].apply_unit(state["allies"][2], "enchant"))


func _test_puppet_ultimate(harness: TestHarness) -> void:
	var ally_state := _state()
	_make_puppet(ally_state["allies"][0], 12.0, false)
	_kill(ally_state["allies"][2])
	_kill(ally_state["allies"][5])
	var ally_kit := _kit(ally_state)
	var ally := _execute(EffectsScript.ULT_PUPPET, ally_state, "ally", "puppet", true, ally_kit["ports"])
	harness.assert_true(ally["ok"])
	harness.assert_equal(ally["value"]["summoned_count"], 2)
	harness.assert_equal(ally["value"]["puppet_ids"], [1, 3, 6])
	harness.assert_true(ally["value"]["martyr_granted"])
	harness.assert_true(ally_state["ally_puppet_martyr_active"])
	for slot in [1, 3, 6]:
		var puppet := _slot(ally_state["allies"], slot)
		harness.assert_equal(puppet["hp"], 100.0)
		harness.assert_true(puppet["puppet_martyr"])

	var enemy_state := _state()
	_make_puppet(enemy_state["enemies"][1], 9.0, false)
	_kill(enemy_state["enemies"][4])
	var enemy_kit := _kit(enemy_state)
	var enemy := _execute(EffectsScript.ULT_PUPPET, enemy_state, "enemy", "puppet", true, enemy_kit["ports"])
	harness.assert_true(enemy["ok"])
	harness.assert_false(enemy["value"]["martyr_granted"], "Web only grants martyr in the ally branch")
	harness.assert_equal(enemy_state["enemies"][1]["hp"], 100.0)
	harness.assert_false(enemy_state["enemies"][1]["puppet_martyr"])
	harness.assert_false(enemy_state["enemies"][4]["puppet_martyr"])
	harness.assert_false(enemy_state["ally_puppet_martyr_active"])

	var full_ally_state := _state()
	var full_ally_kit := _kit(full_ally_state)
	var full_ally := _execute(
		EffectsScript.ULT_PUPPET, full_ally_state, "ally", "puppet", true,
		full_ally_kit["ports"],
	)
	harness.assert_true(full_ally["ok"])
	harness.assert_true(full_ally["value"]["committed"], "ally martyr field commits even with no puppet yet")
	harness.assert_equal(full_ally["value"]["summoned_count"], 0)
	harness.assert_true(full_ally_state["ally_puppet_martyr_active"])


func _test_shadow_exclusive(harness: TestHarness) -> void:
	var state := _state()
	state["allies"][0]["atk"] = 30.0
	state["allies"][1]["atk"] = 30.0
	_make_puppet(state["allies"][0], 100.0, false)
	var kit := _kit(state)
	var result := _execute(EffectsScript.EX_SHADOW, state, "ally", "shadow", false, kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["target_id"], 2, "highest puppet is excluded and atk tie uses id")
	harness.assert_equal(_buff_turns(state["allies"][1], "stealth"), 1)
	harness.assert_true(state["allies"][1]["stealth_attack_ready"])

	var enemy_state := _state()
	var enemy_kit := _kit(enemy_state)
	for slot in [1, 2, 3, 4, 5]:
		harness.assert_true(enemy_kit["buffs"].apply_unit(_slot(enemy_state["enemies"], slot), "stealth", 1, 1))
	var errors: Array[String] = []
	var context := _context(enemy_state, "enemy", "shadow", false)
	harness.assert_false(EffectsScript.is_usable("shadow", false, context, enemy_kit["ports"], errors))
	harness.assert_equal(errors, [])
	var before := BattleStateScript.snapshot(enemy_state)
	var blocked := _registry_execute(EffectsScript.EX_SHADOW, context, enemy_kit["ports"])
	harness.assert_false(blocked["ok"])
	harness.assert_equal(enemy_state, before)


func _test_shadow_ultimate(harness: TestHarness) -> void:
	var state := _state()
	state["enemies"][0]["hp"] = 60.0
	state["enemies"][0]["max_hp"] = 100.0
	state["enemies"][1]["hp"] = 50.0
	state["enemies"][1]["max_hp"] = 100.0
	state["enemies"][2]["hp"] = 25.0
	state["enemies"][2]["max_hp"] = 50.0
	state["allies"][0]["atk"] = 20.0
	var kit := _kit(state)
	harness.assert_true(kit["buffs"].apply_unit(state["allies"][3], "stealth", 1, 1))
	harness.assert_true(kit["buffs"].apply_unit(state["allies"][1], "stealth", 1, 1))
	var before_non_target_hp: Array = state["enemies"].map(func(unit: Dictionary) -> Variant: return unit["hp"])
	var result := _execute(EffectsScript.ULT_SHADOW, state, "ally", "shadow", true, kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["target_id"], 3, "ratio tie then current hp")
	harness.assert_true(result["value"]["forced_crit"], "Web threshold includes exactly 50 percent")
	harness.assert_equal(kit["damage"].records[0]["raw_amount"], 46.7, "alive atk sum 70 / 6 * 4")
	harness.assert_equal(kit["damage"].records[0]["crit_rate"], 1.0)
	var sequence: Dictionary = result["value"]["pursuit_sequence"]
	harness.assert_equal(sequence["status"], "pending_b4_execution")
	harness.assert_true(sequence["retarget_on_target_death"])
	harness.assert_equal(sequence["retarget_policy"], "lowest_hp_percent_lockable")
	harness.assert_equal(sequence["initial_target_id"], 2, "main kill triggers post-main initial retarget")
	harness.assert_equal(sequence["plans"].size(), 2)
	harness.assert_equal(sequence["plans"][0]["attacker_slot"], 2)
	harness.assert_equal(sequence["plans"][1]["attacker_slot"], 4)
	for plan: Dictionary in sequence["plans"]:
		harness.assert_equal(plan["kind"], "execute_piece_attack")
		harness.assert_equal(plan["damage_multiplier"], 0.5)
		harness.assert_equal(plan["target_id"], 2)
		harness.assert_false(plan["trigger_extra_action"])
		harness.assert_false(plan["trigger_pursuit"])
		harness.assert_equal(plan["damage_kind_override"], "pursuit")
	# Only the direct main target changed; plans are JSON-safe descriptions and do
	# not pre-execute either pursuit.
	harness.assert_equal(state["enemies"][0]["hp"], before_non_target_hp[0])
	harness.assert_equal(state["enemies"][1]["hp"], before_non_target_hp[1])
	sequence["plans"][0]["source_effect"]["source_id"] = "tampered"
	harness.assert_equal(_context(state, "ally", "shadow", true)["source_effect"]["source_id"], "shadow")
	harness.assert_true(_json_safe(result["value"]))

	var no_target_state := _state()
	for unit: Dictionary in no_target_state["enemies"]:
		_kill(unit)
	var no_target_kit := _kit(no_target_state)
	var no_target := _execute(EffectsScript.ULT_SHADOW, no_target_state, "ally", "shadow", true, no_target_kit["ports"])
	harness.assert_true(no_target["ok"])
	harness.assert_true(no_target["value"]["no_target"])
	harness.assert_equal(no_target["value"]["pursuit_sequence"]["plans"], [])


func _test_fail_closed_and_commit_semantics(harness: TestHarness) -> void:
	var state := _state()
	var kit := _kit(state)
	var context := _context(state, "ally", "siege", false)
	context["sp"] = 99
	var before := BattleStateScript.snapshot(state)
	var malformed := _registry_execute(EffectsScript.EX_SIEGE, context, kit["ports"])
	harness.assert_false(malformed["ok"])
	harness.assert_contains(malformed["error"], "context")
	harness.assert_equal(state, before)

	var growth_context := _context(state, "ally", "shadow", false)
	growth_context["growth_piece_ratios"] = {1: 1.0}
	var growth := _registry_execute(EffectsScript.EX_SHADOW, growth_context, kit["ports"])
	harness.assert_false(growth["ok"])
	harness.assert_contains(growth["error"], "do not own")

	var failed_state := _state()
	var failed_damage := ControlledDamage.new()
	failed_damage.fail = true
	var failed_kit := _kit(failed_state, FixedRng.new(), failed_damage)
	var failed_before := BattleStateScript.snapshot(failed_state)
	var failed := _execute(EffectsScript.EX_SIEGE, failed_state, "ally", "siege", false, failed_kit["ports"])
	harness.assert_false(failed["ok"])
	harness.assert_contains(failed["error"], "no state committed")
	harness.assert_equal(failed_state, failed_before)

	var partial_state := _state()
	var partial_damage := ControlledDamage.new()
	partial_damage.mutate_then_fail = true
	var partial_kit := _kit(partial_state, FixedRng.new(), partial_damage)
	var partial := _execute(EffectsScript.ULT_SHADOW, partial_state, "ally", "shadow", true, partial_kit["ports"])
	harness.assert_false(partial["ok"])
	harness.assert_contains(partial["error"], "state committed")
	harness.assert_equal(partial_state["enemies"][0]["hp"], 99.0)

	var log_state := _state()
	var log_kit := _kit(log_state, FixedRng.new(), null, true)
	var log_result := _execute(EffectsScript.EX_SIEGE, log_state, "ally", "siege", false, log_kit["ports"])
	harness.assert_false(log_result["ok"])
	harness.assert_contains(log_result["error"], "state committed")
	harness.assert_equal(_buff_stacks(log_state["enemies"][0], "breakMarked"), 1)
	harness.assert_equal(log_kit["metrics"]["content_events"], 0)
	harness.assert_equal(log_kit["metrics"]["combat_events"], 0)

	var ally_locked_state := _state()
	ally_locked_state["enemy_fate"]["ally_lock"] = "noSkill"
	var ally_locked_kit := _kit(ally_locked_state)
	var ally_locked_before := BattleStateScript.snapshot(ally_locked_state)
	var ally_locked := _execute(
		EffectsScript.ULT_SHADOW, ally_locked_state, "ally", "shadow", true,
		ally_locked_kit["ports"],
	)
	harness.assert_false(ally_locked["ok"])
	harness.assert_contains(ally_locked["error"], "prevents")
	harness.assert_equal(ally_locked_kit["damage"].calls, 0)
	harness.assert_equal(ally_locked_state, ally_locked_before)

	var enemy_locked_state := _state()
	_kill(enemy_locked_state["enemies"][2])
	enemy_locked_state["enemy_fate"]["active"] = true
	enemy_locked_state["enemy_fate"]["mode"] = "棋子命运"
	var enemy_locked_kit := _kit(enemy_locked_state)
	var enemy_locked_before := BattleStateScript.snapshot(enemy_locked_state)
	var enemy_locked := _execute(
		EffectsScript.ULT_PUPPET, enemy_locked_state, "enemy", "puppet", true,
		enemy_locked_kit["ports"],
	)
	harness.assert_false(enemy_locked["ok"])
	harness.assert_contains(enemy_locked["error"], "piece Fate")
	harness.assert_equal(enemy_locked_kit["damage"].calls, 0)
	harness.assert_equal(enemy_locked_state, enemy_locked_before)

	var game_over_state := _state()
	for unit: Dictionary in game_over_state["enemies"]:
		_kill(unit)
	game_over_state["game_over"] = true
	game_over_state["battle_result"] = "win"
	var game_over_kit := _kit(game_over_state)
	var game_over_before := BattleStateScript.snapshot(game_over_state)
	var game_over := _execute(
		EffectsScript.ULT_SIEGE, game_over_state, "ally", "siege", true,
		game_over_kit["ports"],
	)
	harness.assert_false(game_over["ok"])
	harness.assert_contains(game_over["error"], "battle end")
	harness.assert_equal(game_over_state, game_over_before)


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


func _context(state: Dictionary, side: String, skill_id: String, ultimate: bool) -> Dictionary:
	var caster_skill := "puppet" if skill_id == "puppetAttunement" else skill_id
	var caster := _caster(state, side, caster_skill)
	var effect := ContextsScript.create_effect_context({
		"source_type": (
			ContextsScript.EFFECT_SOURCE_TYPE["ULTIMATE"]
			if ultimate else ContextsScript.EFFECT_SOURCE_TYPE["EXCLUSIVE_SKILL"]
		),
		"source_id": skill_id, "source_name": skill_id,
		"source_side": side, "source_actor_id": caster["id"],
		"counts_as_skill_cast": true,
	})
	return {"state": state, "caster": caster, "source_effect": effect}


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
	damage_override: Variant = null,
	fail_log: bool = false,
) -> Dictionary:
	var catalog_errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(catalog_errors)
	assert(catalog_errors.is_empty())
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": state, "catalog": catalog["buffs"],
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
	}, buff_errors)
	assert(buff_errors.is_empty())
	var metrics := {"logs": [], "content_events": 0, "combat_events": 0}
	var actions := {
		"emit_combat_event": func(_request: Dictionary) -> Dictionary:
			metrics["combat_events"] += 1
			return CombatPortsScript.ok(null),
		"emit_content_event": func(_request: Dictionary) -> Dictionary:
			metrics["content_events"] += 1
			return CombatPortsScript.ok(null),
		"log": func(request: Dictionary) -> Dictionary:
			if fail_log:
				return CombatPortsScript.fail("injected log failure")
			metrics["logs"].append(request.duplicate(true))
			return CombatPortsScript.ok(null),
		"on_battle_resolved": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_damage": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_heal": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"resolve_battle_end": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(true),
	}
	var damage: Variant = damage_override if damage_override != null else ControlledDamage.new()
	var port_errors: Array[String] = []
	var ports := CombatPortsScript.new({
		"actions": actions,
		"services": {
			"combat_rng": rng if rng != null else FixedRng.new(),
			"enemy_policy_rng": FixedRng.new([1]), "damage": damage,
			"buffs": buffs, "tuning": catalog["tuning"], "catalogs": catalog,
		},
	}, port_errors)
	assert(port_errors.is_empty(), str(port_errors))
	return {"ports": ports, "metrics": metrics, "damage": damage, "buffs": buffs}


func _state() -> Dictionary:
	var source := {
		"round": 1, "phase": "player_input",
		"sp": 4.0, "sp_max": 6.0, "base_sp_max": 6.0,
		"enemy_sp": 4.0, "enemy_sp_max": 6.0,
		"allies": _piece_team("ally"), "enemies": _piece_team("enemy"),
		"player_heroes": [
			_player_hero(7, "城主", "siege", 100.0),
			_player_hero(8, "千机", "puppet", 120.0),
			_player_hero(9, "影狩", "shadow", 100.0),
		],
		"enemy_heroes": [
			_enemy_hero(107, "敌城主", "siege", 100.0),
			_enemy_hero(108, "敌千机", "puppet", 120.0),
			_enemy_hero(109, "敌影狩", "shadow", 100.0),
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
	assert(errors.is_empty(), str(errors))
	return state


func _piece_team(side: String) -> Array:
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


func _player_hero(id: int, name: String, skill: String, max_energy: float) -> Dictionary:
	return {
		"id": id, "name": name, "deployed": true, "ex_skill": skill,
		"energy": max_energy, "max_energy": max_energy, "base_crit_rate": 0.05,
		"fist_momentum": 0,
	}


func _enemy_hero(id: int, name: String, skill: String, max_energy: float) -> Dictionary:
	return {
		"id": id, "name": name, "ex_skill": skill,
		"skills": [], "skill_pool": ["smallHeal"],
		"energy": max_energy, "max_energy": max_energy, "base_crit_rate": 0.05,
		"fist_momentum": 0,
	}


func _kill(unit: Dictionary) -> void:
	unit["hp"] = 0.0
	unit["alive"] = false


func _make_puppet(unit: Dictionary, hp: float, martyr: bool) -> void:
	unit["class_id"] = "puppet"
	unit["class_name"] = "傀儡"
	unit["hp"] = hp
	unit["max_hp"] = 100.0
	unit["atk"] = 0.0
	unit["crit_rate"] = 0.0
	unit["alive"] = true
	unit["general"] = false
	unit["base_block_rate"] = 0.0
	unit["extra_action_charges"] = 0
	unit["buffs"] = []
	unit["is_puppet"] = true
	unit["fixed_max_hp"] = 100.0
	unit["puppet_martyr"] = martyr
	unit["disarm_turns"] = 0
	unit["stealth_attack_ready"] = false
	unit["special_id"] = null
	unit["echo_damage_bonus"] = 0.0
	unit["hp_threshold_crossed"] = false


func _team(state: Dictionary, side: String) -> Array:
	return state["allies"] if side == "ally" else state["enemies"]


func _other_side(side: String) -> String:
	return "enemy" if side == "ally" else "ally"


func _slot(team: Array, slot: int) -> Dictionary:
	for unit: Dictionary in team:
		if unit["slot"] == slot:
			return unit
	assert(false)
	return {}


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


func _side_buff_turns(state: Dictionary, side: String, id: String) -> int:
	for buff: Dictionary in state["side_buffs"][side]:
		if buff["id"] == id:
			return int(buff["turns"])
	return 0


func _sorted_keys(value: Dictionary) -> Array:
	var result: Array = value.keys()
	result.sort()
	return result


func _sorted_strings(value: Array) -> Array:
	var result := value.duplicate()
	result.sort()
	return result


func _json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			return value.all(func(item: Variant) -> bool: return _json_safe(item))
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or not _json_safe(value[key]):
					return false
			return true
	return false
