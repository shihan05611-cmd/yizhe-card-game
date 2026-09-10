extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const DamageScript = preload("res://core/damage.gd")
const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const HeroEffectsScript = preload("res://systems/effects/hero_effects_flame_fate.gd")
const GrowthPortScript = preload("res://systems/growth/growth_port.gd")


class FixedRng:
	extends RefCounted

	var calls := 0
	var pick_index := 0

	func _init(index: int = 0) -> void:
		pick_index = index

	func next() -> float:
		calls += 1
		return 0.99

	func int_range(minimum: int, _maximum: int) -> Variant:
		calls += 1
		return minimum

	func pick(values: Array) -> Variant:
		calls += 1
		if values.is_empty():
			return null
		return values[mini(pick_index, values.size() - 1)]


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("Flame Fate module registers only the six M1 handler ids", func() -> void:
		_test_handler_surface(harness)
	)
	harness.run_test("burn01 exclusive doubles and extends living Burn layers on both sides", func() -> void:
		_test_ex_burn01(harness)
	)
	harness.run_test("Fate exclusive latches once and applies deterministic side-neutral modes", func() -> void:
		_test_ex_fate(harness)
	)
	harness.run_test("burnEnchant battle mode follows Web eligibility and application sets", func() -> void:
		_test_ex_burn_enchant_battle(harness)
	)
	harness.run_test("burnEnchant repeats in battle and never writes permanent growth", func() -> void:
		_test_ex_burn_enchant_growth(harness)
	)
	harness.run_test("burn01 ultimate uses six-slot average burn stacks and canonical damage context", func() -> void:
		_test_ult_burn01(harness)
	)
	harness.run_test("Fate and burnEnchant ultimates mutate only their canonical M2 state", func() -> void:
		_test_ult_fate_and_flame_leech(harness)
	)
	harness.run_test("closed contexts previews and M3 resources remain side effect free", func() -> void:
		_test_closed_context_and_invariance(harness)
	)
	harness.run_test("damage buff and growth failures expose explicit commit semantics", func() -> void:
		_test_failure_semantics(harness)
	)
	print("B3-5A FLAME FATE HERO EFFECT TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_handler_surface(harness: TestHarness) -> void:
	var expected := [
		"battle.castExclusiveSkill.burn01",
		"battle.castExclusiveSkill.burnEnchant",
		"battle.castExclusiveSkill.fate",
		"battle.castUltimateByHero.burn01",
		"battle.castUltimateByHero.burnEnchant",
		"battle.castUltimateByHero.fate",
	]
	var handlers: Dictionary = HeroEffectsScript.handler_map()
	var registry := EffectRegistryScript.new()
	var errors: Array[String] = []
	harness.assert_true(registry.register_map(handlers, errors))
	harness.assert_equal(errors, [])
	harness.assert_equal(registry.handler_ids(), expected)
	harness.assert_equal(handlers.size(), 6)


func _test_ex_burn01(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var fixture := _fixture(side, "burn01", false)
		var opposing := _opposing(side)
		var errors: Array[String] = []
		var target := _unit(fixture["state"], opposing, 1)
		var hidden := _unit(fixture["state"], opposing, 2)
		var dead := _unit(fixture["state"], opposing, 3)
		hidden["buffs"].append(_buff("stealth", 1, 1))
		harness.assert_true(fixture["buffs"].apply_unit(target, "burn", 2, 3, errors))
		harness.assert_true(fixture["buffs"].apply_unit(hidden, "burn", 1, 4, errors))
		_kill(dead)
		dead["buffs"].append(_buff("burn", 1, 5, [5]))
		var result := _execute(fixture)
		harness.assert_true(result["ok"], str(result))
		harness.assert_equal(fixture["buffs"].get_unit_state(target, "burn")["layer_turns"], [5, 5, 5, 5])
		harness.assert_equal(fixture["buffs"].get_unit_state(hidden, "burn")["layer_turns"], [6, 6])
		harness.assert_equal(fixture["buffs"].get_unit_stacks(dead, "burn"), 1)
		var count_field := "burn_ex_cast_count" if side == "ally" else "enemy_burn_ex_cast_count"
		harness.assert_equal(fixture["state"][count_field], 1)
		harness.assert_equal(fixture["actions"], [], "effect layer must not emit a cast event")

	var no_burn := _fixture("ally", "burn01", false)
	var before := BattleStateScript.snapshot(no_burn["state"])
	var unusable := _execute(no_burn)
	harness.assert_false(unusable["ok"])
	harness.assert_equal(no_burn["state"], before)


func _test_ex_fate(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var fixture := _fixture(side, "fate", false, 0)
		_kill(_unit(fixture["state"], side, 6))
		var result := _execute(fixture)
		harness.assert_true(result["ok"], str(result))
		harness.assert_equal(result["value"]["mode"], "棋子命运")
		var fate: Dictionary = fixture["state"]["fate" if side == "ally" else "enemy_fate"]
		harness.assert_true(fate["active"])
		harness.assert_true(fate["cast_used"])
		for slot in range(1, 6):
			harness.assert_equal(fixture["buffs"].get_unit_stacks(_unit(fixture["state"], side, slot), "pursuit"), 1)
		harness.assert_equal(fixture["buffs"].get_unit_stacks(_unit(fixture["state"], side, 6), "pursuit"), 0)
		var repeat := _execute(fixture)
		harness.assert_false(repeat["ok"])
		for slot in range(1, 6):
			harness.assert_equal(fixture["buffs"].get_unit_stacks(_unit(fixture["state"], side, slot), "pursuit"), 1)

	for side in ["ally", "enemy"]:
		var chaos := _fixture(side, "fate", false, 2)
		var result := _execute(chaos)
		harness.assert_true(result["ok"])
		harness.assert_equal(result["value"]["mode"], "混沌命运")
		var fate: Dictionary = chaos["state"]["fate" if side == "ally" else "enemy_fate"]
		harness.assert_true(fate["chaos_used"])
		var lock_field := "enemy_lock" if side == "ally" else "ally_lock"
		harness.assert_equal(fate[lock_field], "noSkill")

	var fixed := _fixture("ally", "fate", false, 2, null, false, false, false, "技能命运")
	var fixed_result := _execute(fixed)
	harness.assert_true(fixed_result["ok"])
	harness.assert_equal(fixed_result["value"]["mode"], "技能命运")
	harness.assert_equal(fixed["combat_rng"].calls, 0, "player fixed order precedes combat RNG")
	var skip_used_chaos := _fixture(
		"ally", "fate", false, 2, null, false, false, false, "混沌命运,技能命运"
	)
	skip_used_chaos["state"]["fate"]["chaos_used"] = true
	var skip_result := _execute(skip_used_chaos)
	harness.assert_true(skip_result["ok"])
	harness.assert_equal(skip_result["value"]["mode"], "技能命运")
	harness.assert_equal(skip_used_chaos["state"]["fate"]["roll_index"], 2)
	var enemy_ignores_fixed := _fixture(
		"enemy", "fate", false, 2, null, false, false, false, "技能命运"
	)
	var enemy_fixed_result := _execute(enemy_ignores_fixed)
	harness.assert_equal(enemy_fixed_result["value"]["mode"], "混沌命运")


func _test_ex_burn_enchant_battle(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var fixture := _fixture(side, "burnEnchant", false)
		var errors: Array[String] = []
		var puppet := _unit(fixture["state"], side, 1)
		var capped := _unit(fixture["state"], side, 2)
		puppet["is_puppet"] = true
		harness.assert_true(fixture["buffs"].apply_unit(capped, "enchant", 5, null, errors))
		_kill(_unit(fixture["state"], side, 4))
		var result := _execute(fixture)
		harness.assert_true(result["ok"], str(result))
		harness.assert_equal(fixture["buffs"].get_unit_stacks(puppet, "enchant"), 0, "puppets reject enchantments until attuned")
		harness.assert_equal(fixture["buffs"].get_unit_stacks(capped, "enchant"), 5)
		harness.assert_equal(fixture["buffs"].get_unit_stacks(_unit(fixture["state"], side, 3), "enchant"), 1)
		harness.assert_equal(fixture["buffs"].get_unit_stacks(_unit(fixture["state"], side, 4), "enchant"), 0)
		harness.assert_equal(fixture["actions"], [])

	var capped_team := _fixture("ally", "burnEnchant", false)
	var errors: Array[String] = []
	for unit: Dictionary in capped_team["state"]["allies"]:
		if not unit["is_puppet"]:
			harness.assert_true(capped_team["buffs"].apply_unit(unit, "enchant", 5, null, errors))
	var before := BattleStateScript.snapshot(capped_team["state"])
	harness.assert_false(_execute(capped_team)["ok"])
	harness.assert_equal(capped_team["state"], before)


func _test_ex_burn_enchant_growth(harness: TestHarness) -> void:
	var run_state := {"permanent_buffs": []}
	var fixture := _fixture("ally", "burnEnchant", false, 0, run_state)
	fixture["context"]["growth_piece_ratios"] = {1: 1.0, 2: 0.0, 3: 1.0, 4: 1.0, 5: 1.0, 6: 1.0}
	var puppet := _unit(fixture["state"], "ally", 3)
	puppet["is_puppet"] = true
	var errors: Array[String] = []
	harness.assert_true(fixture["buffs"].set_unit_enchantment_capacity(puppet, 1, errors))
	for expected_count in range(1, 6):
		var result := _execute(fixture)
		harness.assert_true(result["ok"], str(result))
		harness.assert_equal(result["value"]["mode"], "battle")
		harness.assert_equal(result["value"]["cast_count"], expected_count)
		harness.assert_equal(fixture["buffs"].get_side_stacks("ally", "flameCastCount"), expected_count)
	harness.assert_equal(fixture["buffs"].get_unit_stacks(puppet, "enchant"), 5, "attuned puppet receives repeated enchantment")
	harness.assert_equal(run_state["permanent_buffs"], [], "legacy Run growth state is never written")
	harness.assert_false(fixture["state"]["battle_growth_flags"]["flame_investment_used"])
	harness.assert_equal(fixture["actions"], [], "no GrowthPort action is called")


func _test_ult_burn01(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var fixture := _fixture(side, "burn01", true)
		var opposing := _opposing(side)
		var errors: Array[String] = []
		for own: Dictionary in fixture["state"]["allies" if side == "ally" else "enemies"]:
			own["atk"] = 20.0
		var target := _unit(fixture["state"], opposing, 1)
		target["buffs"].append(_buff("stealth", 1, 1))
		harness.assert_true(fixture["buffs"].apply_unit(target, "burn", 2, 3, errors))
		var second_target := _unit(fixture["state"], opposing, 2)
		harness.assert_true(fixture["buffs"].apply_unit(second_target, "burn", 1, 3, errors))
		var dead := _unit(fixture["state"], opposing, 3)
		_kill(dead)
		dead["buffs"].append(_buff("burn", 3, 3, [3, 3, 3]))
		var resources_before := _m3_snapshot(fixture["state"])
		var result := _execute(fixture)
		harness.assert_true(result["ok"], str(result))
		harness.assert_equal(result["value"]["target_ids"], [1, 2])
		harness.assert_equal(result["value"]["total_dealt"], 3.0)
		harness.assert_equal(target["hp"], 98.0, "stealth does not hide from this ultimate")
		harness.assert_equal(fixture["damage_records"].size(), 2)
		var record: Dictionary = fixture["damage_records"][0]
		harness.assert_equal(record["damage_context"]["raw_amount"], 2.0)
		harness.assert_equal(record["damage_context"]["effect"], fixture["context"]["source_effect"])
		harness.assert_equal(fixture["damage_records"].map(func(value: Dictionary) -> Variant: return value["metadata"].get("presentation_wave_index")), [0, 0], "burn01's actual DamagePipeline records one shared hit wave")
		harness.assert_equal(_m3_snapshot(fixture["state"]), resources_before)
		harness.assert_equal(fixture["actions"], [])


func _test_ult_fate_and_flame_leech(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		var fate := _fixture(side, "fate", true)
		var fate_state: Dictionary = fate["state"]["fate" if side == "ally" else "enemy_fate"]
		fate_state["all_in_turns"] = 3
		var result := _execute(fate)
		harness.assert_true(result["ok"], str(result))
		harness.assert_equal(fate_state["mode"], "全命运")
		harness.assert_equal(fate_state["all_in_turns"], 3)
		var lock_field := "enemy_lock" if side == "ally" else "ally_lock"
		harness.assert_equal(fate_state[lock_field], "noSkill")
		for slot in range(1, 7):
			harness.assert_equal(fate["buffs"].get_unit_stacks(_unit(fate["state"], side, slot), "pursuit"), 1)
		harness.assert_equal(fate["actions"], [])

		var leech := _fixture(side, "burnEnchant", true)
		result = _execute(leech)
		harness.assert_true(result["ok"], str(result))
		harness.assert_equal(leech["buffs"].get_side_stacks(side, "flameLeech"), 1)
		harness.assert_equal(leech["buffs"].get_side_turns(side, "flameLeech"), 2)
		harness.assert_equal(leech["actions"], [])


func _test_closed_context_and_invariance(harness: TestHarness) -> void:
	var fixture := _fixture("ally", "fate", false)
	var state_before := BattleStateScript.snapshot(fixture["state"])
	var context_before: Dictionary = fixture["context"].duplicate(true)
	var errors: Array[String] = []
	harness.assert_true(HeroEffectsScript.is_usable(fixture["effect_id"], fixture["context"], fixture["ports"], errors))
	harness.assert_equal(errors, [])
	harness.assert_equal(fixture["state"], state_before)
	harness.assert_equal(fixture["context"], context_before)
	harness.assert_equal(fixture["combat_rng"].calls, 0, "usable must not roll Fate")

	fixture["context"]["extra"] = true
	harness.assert_false(_execute(fixture)["ok"])
	harness.assert_equal(fixture["state"], state_before)
	fixture["context"].erase("extra")
	fixture["context"]["caster"] = fixture["context"]["caster"].duplicate(true)
	harness.assert_false(_execute(fixture)["ok"], "equal data is not the canonical hero reference")
	harness.assert_equal(fixture["state"], state_before)

	var wrong_source := _fixture("enemy", "burn01", true)
	wrong_source["context"]["source_effect"]["source_id"] = "fate"
	state_before = BattleStateScript.snapshot(wrong_source["state"])
	harness.assert_false(_execute(wrong_source)["ok"])
	harness.assert_equal(wrong_source["state"], state_before)


func _test_failure_semantics(harness: TestHarness) -> void:
	var damage_fail := _fixture("ally", "burn01", true, 0, null, false, true)
	var errors: Array[String] = []
	var target := _unit(damage_fail["state"], "enemy", 1)
	harness.assert_true(damage_fail["buffs"].apply_unit(target, "burn", 2, 3, errors))
	var before_hp: Variant = target["hp"]
	var result := _execute(damage_fail)
	harness.assert_false(result["ok"])
	harness.assert_equal(target["hp"], before_hp, "DamagePipeline rejects before hp commit")

	var buff_fail := _fixture("ally", "burnEnchant", false, 0, null, true)
	result = _execute(buff_fail)
	harness.assert_false(result["ok"])
	harness.assert_equal(buff_fail["buffs"].get_unit_stacks(_unit(buff_fail["state"], "ally", 1), "enchant"), 1)
	harness.assert_false(_unit(buff_fail["state"], "ally", 2)["alive"])
	harness.assert_equal(buff_fail["buffs"].get_unit_stacks(_unit(buff_fail["state"], "ally", 2), "enchant"), 0)

	var run_state := {"permanent_buffs": []}
	var ignored_growth_failure := _fixture("ally", "burnEnchant", false, 0, run_state, false, false, true)
	ignored_growth_failure["context"]["growth_piece_ratios"] = {1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0, 5: 1.0, 6: 1.0}
	result = _execute(ignored_growth_failure)
	harness.assert_true(result["ok"], str(result))
	harness.assert_equal(run_state["permanent_buffs"], [])
	harness.assert_equal(ignored_growth_failure["buffs"].get_side_stacks("ally", "flameCastCount"), 1)
	harness.assert_equal(ignored_growth_failure["actions"], [])


func _execute(fixture: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var result: Dictionary = fixture["registry"].execute(
		fixture["effect_id"], fixture["context"], fixture["ports"], errors
	)
	assert(errors.is_empty() or not result["ok"])
	return result


func _fixture(
	side: String,
	ability_id: String,
	ultimate: bool,
	pick_index: int = 0,
	run_state: Variant = null,
	kill_second_after_first_buff: bool = false,
	invalid_damage: bool = false,
	fail_growth_stage: bool = false,
	fixed_fate_order: String = "",
) -> Dictionary:
	var state := _state()
	var catalog_errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(catalog_errors)
	assert(catalog_errors.is_empty())
	if not fixed_fate_order.is_empty():
		catalog["tuning"]["fateFixedOrder"].value = fixed_fate_order
	var buff_errors: Array[String] = []
	var corrupted_once := false
	var buffs := BuffSystemScript.new({
		"state": state,
		"catalog": catalog["buffs"],
		"on_event": func(type: String, payload: Dictionary) -> void:
			if kill_second_after_first_buff and not corrupted_once and type == "buff_applied" and payload["target_id"] == 1:
				corrupted_once = true
				_kill(_unit(state, side, 2)),
	}, buff_errors)
	assert(buff_errors.is_empty())
	var combat_rng := FixedRng.new(pick_index)
	var enemy_rng := FixedRng.new(0)
	var damage_records: Array = []
	var damage_errors: Array[String] = []
	var damage := DamageScript.new({
		"random": combat_rng.next,
		"format": func(value: float) -> float: return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(_unit_value: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 0.0,
		"get_damage_multiplier": func(_unit_value: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return NAN if invalid_damage else 1.0,
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
		"on_death": func(_unit_value: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"record_damage": func(payload: Dictionary) -> void: damage_records.append(payload),
	}, damage_errors)
	assert(damage_errors.is_empty())
	var actions: Array = []
	var action_map := {}
	var growth_port: Variant = null
	for action_id: String in CombatPortsScript.REQUIRED_ACTION_IDS:
		action_map[action_id] = _recording_action.bind(action_id, actions, "")
	if run_state != null:
		var growth_errors: Array[String] = []
		growth_port = GrowthPortScript.new({
			"run_state": run_state,
			"catalog": catalog["buffs"],
			"valid_hero_ids": catalog["characters"]["players"].keys(),
		}, growth_errors)
		assert(growth_errors.is_empty())
		var growth_actions: Dictionary = growth_port.action_map()
		for action_id: String in growth_actions:
			action_map[action_id] = _recording_growth_action.bind(
				action_id,
				actions,
				growth_actions[action_id],
				GrowthPortScript.ACTION_STAGE if fail_growth_stage else "",
			)
	var port_errors: Array[String] = []
	var ports := CombatPortsScript.new({
		"actions": action_map,
		"services": {
			"combat_rng": combat_rng,
			"enemy_policy_rng": enemy_rng,
			"damage": damage,
			"buffs": buffs,
			"tuning": catalog["tuning"],
			"catalogs": catalog,
		},
	}, port_errors)
	assert(port_errors.is_empty())
	var caster := _hero(state, side, ability_id)
	var source_errors: Array[String] = []
	var source_effect := ContextsScript.create_effect_context({
		"source_type": "ultimate" if ultimate else "exclusive_skill",
		"source_id": ability_id,
		"source_name": ability_id,
		"source_side": side,
		"source_actor_id": caster["id"],
		"counts_as_skill_cast": true,
		"spent_skill_points": false,
		"free_cast": false,
		"counts_as_basic_attack": false,
		"counts_as_attack": false,
		"triggers_enemy_kill_effects": true,
	}, source_errors)
	assert(source_errors.is_empty())
	var effect_id := "%s.%s" % [
		"battle.castUltimateByHero" if ultimate else "battle.castExclusiveSkill",
		ability_id,
	]
	var registry := EffectRegistryScript.new()
	var registry_errors: Array[String] = []
	assert(registry.register_map(HeroEffectsScript.handler_map(), registry_errors))
	assert(registry_errors.is_empty())
	return {
		"state": state,
		"buffs": buffs,
		"ports": ports,
		"registry": registry,
		"effect_id": effect_id,
		"context": {"state": state, "caster": caster, "source_effect": source_effect},
		"actions": actions,
		"combat_rng": combat_rng,
		"damage_records": damage_records,
		"growth_port": growth_port,
	}


func _recording_action(_request: Dictionary, action_id: String, actions: Array, failure: String) -> Dictionary:
	actions.append({"id": action_id, "request": _request.duplicate(true)})
	return CombatPortsScript.fail(failure) if not failure.is_empty() else CombatPortsScript.ok(null)


func _recording_growth_action(
	request: Dictionary,
	action_id: String,
	actions: Array,
	inner: Callable,
	failing_action: String,
) -> Dictionary:
	actions.append({"id": action_id, "request": request.duplicate(true)})
	if action_id == failing_action:
		return CombatPortsScript.fail("injected growth stage failure")
	return inner.call(request)


func _state() -> Dictionary:
	var source := {
		"round": 1, "phase": "player_input", "sp": 4.0, "sp_max": 6.0,
		"base_sp_max": 6.0, "enemy_sp": 4.0, "enemy_sp_max": 6.0,
		"allies": _team("ally"), "enemies": _team("enemy"),
		"player_heroes": [
			_player_hero(1, "burn01"), _player_hero(2, "fate"), _player_hero(5, "burnEnchant"),
		],
		"enemy_heroes": [
			_enemy_hero(101, "burn01"), _enemy_hero(102, "fate"), _enemy_hero(105, "burnEnchant"),
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


func _player_hero(id: int, ability_id: String) -> Dictionary:
	return {
		"id": id, "name": ability_id, "deployed": true, "ex_skill": ability_id,
		"energy": 100.0, "max_energy": 100.0, "base_crit_rate": 0.05,
		"fist_momentum": 0,
	}


func _enemy_hero(id: int, ability_id: String) -> Dictionary:
	return {
		"id": id, "name": ability_id, "ex_skill": ability_id,
		"skills": [], "skill_pool": ["basicDamage"],
		"energy": 100.0, "max_energy": 100.0, "base_crit_rate": 0.05,
		"fist_momentum": 0,
	}


func _hero(state: Dictionary, side: String, ability_id: String) -> Dictionary:
	var heroes: Array = state["player_heroes" if side == "ally" else "enemy_heroes"]
	for hero: Dictionary in heroes:
		if hero["ex_skill"] == ability_id:
			return hero
	assert(false)
	return {}


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


func _buff(id: String, stacks: int, turns: int, layers: Array = []) -> Dictionary:
	return {"id": id, "stacks": stacks, "turns": turns, "layer_turns": layers.duplicate()}


func _opposing(side: String) -> String:
	return "enemy" if side == "ally" else "ally"


func _m3_snapshot(state: Dictionary) -> Dictionary:
	return {
		"sp": state["sp"],
		"enemy_sp": state["enemy_sp"],
		"player_energy": state["player_heroes"].map(func(hero: Dictionary) -> Variant: return hero["energy"]),
		"enemy_energy": state["enemy_heroes"].map(func(hero: Dictionary) -> Variant: return hero["energy"]),
	}
