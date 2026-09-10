extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const FreeSkillEffectsScript = preload("res://systems/effects/free_skill_effects.gd")
const DamageScript = preload("res://core/damage.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const Rng = preload("res://core/rng.gd")


class CountingRng:
	extends RefCounted

	var calls := 0
	var _inner: Variant

	func _init(seed: String) -> void:
		_inner = Rng.seeded(seed)

	func next() -> float:
		calls += 1
		return _inner.next()

	func int_range(minimum: int, maximum: int) -> Variant:
		calls += 1
		return _inner.int_range(minimum, maximum)

	func pick(values: Array) -> Variant:
		calls += 1
		return _inner.pick(values)


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("free skill module exposes exactly thirteen stable registry handlers", func() -> void:
		_test_handler_surface(harness)
	)
	harness.run_test("all thirteen effects execute for both canonical battle sides without effect-layer payment", func() -> void:
		_test_all_effects_both_sides(harness)
	)
	harness.run_test("burn detonate uses Web target formula source context and stable death spread", func() -> void:
		_test_burn_detonate(harness)
	)
	harness.run_test("burn stack consumes only injected combat RNG and replays from a fixed seed", func() -> void:
		_test_burn_rng(harness)
	)
	harness.run_test("execute strike is a narrow immutable B4 request and performs no attack", func() -> void:
		_test_execute_plan(harness)
	)
	harness.run_test("healing targeting caps and buff targets match Web tie breaks", func() -> void:
		_test_heal_and_buffs(harness)
	)
	harness.run_test("unusable and malformed requests fail before action RNG or state mutation", func() -> void:
		_test_fail_closed(harness)
	)
	harness.run_test("external failures report precommit versus committed state without rollback", func() -> void:
		_test_commit_semantics(harness)
	)
	print("B3-3 FREE SKILL EFFECT TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_handler_surface(harness: TestHarness) -> void:
	var expected: Array[String] = []
	for skill_id: String in FreeSkillEffectsScript.SKILL_IDS:
		expected.append("free_skill.%s.effect" % skill_id)
	expected.sort()
	var handlers: Dictionary = FreeSkillEffectsScript.handler_map()
	var errors: Array[String] = []
	var registry := EffectRegistryScript.new()
	harness.assert_true(registry.register_map(handlers, errors))
	harness.assert_equal(errors, [])
	harness.assert_equal(registry.handler_ids(), expected)
	harness.assert_equal(handlers.size(), 13)
	var copy := registry.handlers_snapshot()
	copy.erase(expected[0])
	harness.assert_equal(registry.handler_ids(), expected)


func _test_all_effects_both_sides(harness: TestHarness) -> void:
	for side in ["ally", "enemy"]:
		for skill_id: String in FreeSkillEffectsScript.SKILL_IDS:
			var fixture := _fixture(side, skill_id)
			_prepare(fixture, skill_id)
			var state: Dictionary = fixture["state"]
			var sp_before: Variant = state["sp"]
			var enemy_sp_before: Variant = state["enemy_sp"]
			var result := _execute(fixture, skill_id)
			harness.assert_true(result["ok"], "%s must execute for %s: %s" % [skill_id, side, result.get("error", "")])
			if result["ok"]:
				_assert_effect_outcome(harness, fixture, skill_id, result["value"])
			var expected_sp := float(sp_before) + (2.0 if skill_id == "spSurge" and side == "ally" else 0.0)
			var expected_enemy_sp := float(enemy_sp_before) + (2.0 if skill_id == "spSurge" and side == "enemy" else 0.0)
			harness.assert_equal(state["sp"], expected_sp, "%s changes only its caster-side resource" % skill_id)
			harness.assert_equal(state["enemy_sp"], expected_enemy_sp, "%s changes only its caster-side resource" % skill_id)
			var errors: Array[String] = []
			harness.assert_true(BattleStateScript.validate(state, errors), "%s must preserve canonical state: %s" % [skill_id, errors])


func _assert_effect_outcome(
	harness: TestHarness,
	fixture: Dictionary,
	skill_id: String,
	value: Dictionary,
) -> void:
	var state: Dictionary = fixture["state"]
	var side: String = fixture["context"]["caster_side"]
	var opposing := "enemy" if side == "ally" else "ally"
	var buffs: Variant = fixture["buffs"]
	match skill_id:
		"burnStackBase":
			for slot in range(1, 7):
				var stacks: int = buffs.get_unit_stacks(_unit(state, opposing, slot), "burn")
				harness.assert_true(stacks == 1 or stacks == 2)
		"burnDetonate":
			harness.assert_equal(value["target_id"], 2)
			harness.assert_equal(value["stacks"], 3)
			harness.assert_equal(value["dealt"], 15.0)
			harness.assert_equal(buffs.get_unit_stacks(_unit(state, opposing, 2), "burn"), 0)
		"executeStrike":
			harness.assert_equal(value["plan"]["attacker_id"], 2)
			harness.assert_equal(value["plan"]["target_id"], 3)
			harness.assert_equal(value["plan"]["damage_multiplier"], 1.5)
		"pieceAction":
			harness.assert_equal(value["target_id"], 2)
			if side == "ally":
				harness.assert_equal(value["buff_id"], "nextRoundAction")
				harness.assert_equal(value["activation_round"], int(state["round"]) + 1)
				harness.assert_equal(buffs.get_unit_state(_unit(state, side, 2), "nextRoundAction")["layer_turns"], [2])
				harness.assert_equal(_unit(state, side, 2)["extra_action_charges"], 0, "player effect does not also grant a legacy charge")
			else:
				harness.assert_equal(_unit(state, side, 2)["extra_action_charges"], 1, "enemy keeps immediate legacy charge")
		"pieceBlock":
			harness.assert_equal(value["buff_id"], "tempBlock")
			harness.assert_equal(buffs.get_side_stacks(side, "tempBlock"), 1)
		"pieceDamageUp":
			harness.assert_equal(value["buff_id"], "pieceDamageUp")
			harness.assert_equal(buffs.get_side_stacks(side, "pieceDamageUp"), 1)
		"pieceHealAll":
			harness.assert_equal(value["total_healed"], 10.0)
			harness.assert_equal(_unit(state, side, 2)["hp"], 45.0)
			harness.assert_equal(_unit(state, side, 3)["hp"], 65.0)
		"smallHeal":
			harness.assert_equal(value["target_id"], 2)
			harness.assert_equal(value["healed"], 5.0)
			harness.assert_equal(_unit(state, side, 2)["hp"], 45.0)
		"markBurn":
			harness.assert_equal(value["target_id"], 2)
			harness.assert_equal(buffs.get_unit_stacks(_unit(state, opposing, 2), "burn"), 3)
		"bloodShift":
			harness.assert_equal(value["anchor_id"], 1)
			harness.assert_equal(buffs.get_unit_stacks(_unit(state, side, 1), "bloodShiftVulnerable"), 1)
			harness.assert_equal(buffs.get_unit_stacks(_unit(state, side, 2), "bloodShiftGuard"), 1)
		"basicDamage":
			harness.assert_equal(value["target_id"], 3)
			harness.assert_equal(value["raw_amount"], 20.0)
			harness.assert_equal(value["dealt"], 20.0)
			harness.assert_equal(_unit(state, opposing, 3)["hp"], 20.0)


func _test_burn_detonate(harness: TestHarness) -> void:
	var fixture := _fixture("ally", "burnDetonate")
	var state: Dictionary = fixture["state"]
	var buffs: Variant = fixture["buffs"]
	var errors: Array[String] = []
	_set_hp(state, "enemy", 1, 10.0)
	_set_hp(state, "enemy", 2, 40.0)
	_set_hp(state, "enemy", 3, 70.0)
	for slot in range(4, 7):
		_kill(_unit(state, "enemy", slot))
	harness.assert_true(buffs.apply_unit(_unit(state, "enemy", 1), "burn", 3, null, errors))
	harness.assert_true(buffs.apply_unit(_unit(state, "enemy", 2), "burn", 1, null, errors))
	var result := _execute(fixture, "burnDetonate")
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["target_id"], 1)
	harness.assert_equal(result["value"]["dealt"], 10.0)
	harness.assert_true(result["value"]["died"])
	harness.assert_equal(result["value"]["spread_stacks"], 3)
	harness.assert_equal(buffs.get_unit_stacks(_unit(state, "enemy", 2), "burn"), 3)
	harness.assert_equal(buffs.get_unit_stacks(_unit(state, "enemy", 3), "burn"), 1)
	harness.assert_equal(fixture["damage_records"].size(), 1)
	var damage_record: Dictionary = fixture["damage_records"][0]
	harness.assert_equal(damage_record["damage_context"]["effect"], fixture["context"]["source_effect"])
	harness.assert_equal(damage_record["damage_context"]["raw_amount"], 15.0)


func _test_burn_rng(harness: TestHarness) -> void:
	var first := _fixture("ally", "burnStackBase", "replay-seed")
	var second := _fixture("ally", "burnStackBase", "replay-seed")
	var first_result := _execute(first, "burnStackBase")
	var second_result := _execute(second, "burnStackBase")
	harness.assert_true(first_result["ok"])
	harness.assert_equal(second_result, first_result)
	harness.assert_equal(_buff_views(first["state"], "enemy"), _buff_views(second["state"], "enemy"))
	harness.assert_equal(first["combat_rng"].calls, 6)
	harness.assert_equal(first["enemy_rng"].calls, 0)


func _test_execute_plan(harness: TestHarness) -> void:
	var fixture := _fixture("enemy", "executeStrike")
	_prepare(fixture, "executeStrike")
	var before := BattleStateScript.snapshot(fixture["state"])
	var result := _execute(fixture, "executeStrike")
	harness.assert_true(result["ok"])
	harness.assert_false(result["value"]["committed"])
	var plan: Dictionary = result["value"]["plan"]
	harness.assert_equal(plan["kind"], "execute_piece_attack")
	harness.assert_equal(plan["attacker_side"], "enemy")
	harness.assert_equal(plan["attacker_id"], 2)
	harness.assert_equal(plan["target_side"], "ally")
	harness.assert_equal(plan["target_id"], 3)
	harness.assert_equal(plan["damage_multiplier"], 1.5)
	harness.assert_false(plan["trigger_extra_action"])
	harness.assert_false(plan["trigger_pursuit"])
	harness.assert_equal(plan["damage_kind_override"], "execute")
	harness.assert_equal(plan["source_effect"], fixture["context"]["source_effect"])
	plan["source_effect"]["source_id"] = "tampered"
	harness.assert_equal(fixture["context"]["source_effect"]["source_id"], "executeStrike")
	harness.assert_equal(fixture["state"], before)
	harness.assert_equal(fixture["actions"].size(), 0)


func _test_heal_and_buffs(harness: TestHarness) -> void:
	var heal := _fixture("ally", "smallHeal")
	var state: Dictionary = heal["state"]
	_set_hp(state, "ally", 1, 40.0, 100.0)
	_set_hp(state, "ally", 2, 20.0, 50.0)
	_set_hp(state, "ally", 3, 5.0, 25.0)
	_unit(state, "ally", 3)["buffs"] = [_buff("stealth")]
	var result := _execute(heal, "smallHeal")
	harness.assert_true(result["ok"])
	# smallHeal follows skills.js ratio then id, and does not filter friendly stealth.
	harness.assert_equal(result["value"]["target_id"], 3)
	harness.assert_equal(_unit(state, "ally", 3)["hp"], 6.25)
	var all_heal := _fixture("ally", "pieceHealAll")
	_set_hp(all_heal["state"], "ally", 1, 99.0)
	var all_result := _execute(all_heal, "pieceHealAll")
	harness.assert_true(all_result["ok"])
	harness.assert_equal(_unit(all_heal["state"], "ally", 1)["hp"], 100.0)
	harness.assert_equal(all_result["value"]["total_healed"], 1.0)
	var blood := _fixture("ally", "bloodShift")
	_prepare(blood, "bloodShift")
	var blood_result := _execute(blood, "bloodShift")
	harness.assert_true(blood_result["ok"])
	harness.assert_equal(blood_result["value"]["anchor_id"], 1)
	harness.assert_equal(blood["buffs"].get_unit_stacks(_unit(blood["state"], "ally", 1), "bloodShiftVulnerable"), 1)
	harness.assert_equal(blood["buffs"].get_unit_stacks(_unit(blood["state"], "ally", 2), "bloodShiftGuard"), 1)


func _test_fail_closed(harness: TestHarness) -> void:
	var no_target := _fixture("ally", "basicDamage")
	for slot in range(1, 7):
		_unit(no_target["state"], "enemy", slot)["buffs"] = [_buff("stealth")]
	var before := BattleStateScript.snapshot(no_target["state"])
	var errors: Array[String] = []
	harness.assert_false(FreeSkillEffectsScript.is_usable("basicDamage", no_target["context"], no_target["ports"], errors))
	harness.assert_equal(errors, [])
	var result := _execute(no_target, "basicDamage")
	harness.assert_false(result["ok"])
	harness.assert_true(result["error"].contains("unusable"))
	harness.assert_equal(no_target["state"], before)
	harness.assert_equal(no_target["actions"].size(), 0)
	harness.assert_equal(no_target["combat_rng"].calls, 0)
	var full_team := _fixture("ally", "smallHeal")
	harness.assert_false(FreeSkillEffectsScript.is_usable("smallHeal", full_team["context"], full_team["ports"], errors))
	var missing_piece_target := _fixture("ally", "pieceAction")
	before = BattleStateScript.snapshot(missing_piece_target["state"])
	harness.assert_false(FreeSkillEffectsScript.is_usable("pieceAction", missing_piece_target["context"], missing_piece_target["ports"], errors))
	harness.assert_false(_execute(missing_piece_target, "pieceAction")["ok"])
	harness.assert_equal(missing_piece_target["state"], before)
	var malformed := _fixture("ally", "pieceAction")
	malformed["context"]["cost"] = 0
	before = BattleStateScript.snapshot(malformed["state"])
	result = _execute(malformed, "pieceAction")
	harness.assert_false(result["ok"])
	harness.assert_true(result["error"].contains("closed shape"))
	harness.assert_equal(malformed["state"], before)
	malformed = _fixture("ally", "pieceAction")
	malformed["context"]["source_effect"]["spent_skill_points"] = 1
	result = _execute(malformed, "pieceAction")
	harness.assert_false(result["ok"])
	harness.assert_true(result["error"].contains("spent_skill_points"))


func _test_commit_semantics(harness: TestHarness) -> void:
	var post_fail := _fixture("ally", "pieceAction", "commit", "log")
	_prepare(post_fail, "pieceAction")
	var result := _execute(post_fail, "pieceAction")
	harness.assert_false(result["ok"])
	harness.assert_true(result["error"].contains("state committed"))
	harness.assert_equal(post_fail["buffs"].get_unit_stacks(_unit(post_fail["state"], "ally", 2), "nextRoundAction"), 1)
	harness.assert_equal(_unit(post_fail["state"], "ally", 2)["extra_action_charges"], 0)
	var record_fail := _fixture("ally", "smallHeal", "commit", "record_heal")
	_set_hp(record_fail["state"], "ally", 1, 50.0)
	result = _execute(record_fail, "smallHeal")
	harness.assert_false(result["ok"])
	harness.assert_true(result["error"].contains("state committed"))
	harness.assert_equal(_unit(record_fail["state"], "ally", 1)["hp"], 55.0)
	var pre_fail := _fixture("ally", "basicDamage", "commit", "", true)
	_prepare(pre_fail, "basicDamage")
	var target := _unit(pre_fail["state"], "enemy", 3)
	var hp_before: Variant = target["hp"]
	result = _execute(pre_fail, "basicDamage")
	harness.assert_false(result["ok"])
	harness.assert_true(result["error"].contains("before commit"))
	harness.assert_equal(target["hp"], hp_before)
	harness.assert_equal(pre_fail["actions"].size(), 0)


func _execute(fixture: Dictionary, skill_id: String) -> Dictionary:
	var errors: Array[String] = []
	var result: Dictionary = fixture["registry"].execute(
		"free_skill.%s.effect" % skill_id,
		fixture["context"],
		fixture["ports"],
		errors,
	)
	assert(errors.is_empty() or not result["ok"])
	return result


func _fixture(
	side: String,
	skill_id: String,
	seed: String = "B3-3",
	failing_action: String = "",
	invalid_damage: bool = false,
) -> Dictionary:
	var state := _state()
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
	var combat_rng := CountingRng.new("%s-combat" % seed)
	var enemy_rng := CountingRng.new("%s-enemy" % seed)
	var damage_records: Array = []
	var damage_errors: Array[String] = []
	var damage := DamageScript.new({
		"random": combat_rng.next,
		"format": func(value: float) -> float: return value,
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
	for action_id: String in CombatPortsScript.REQUIRED_ACTION_IDS:
		action_map[action_id] = func(request: Dictionary) -> Dictionary:
			actions.append({"id": action_id, "request": request.duplicate(true)})
			if action_id == failing_action:
				return CombatPortsScript.fail("injected %s failure" % action_id)
			return CombatPortsScript.ok(null)
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
	var effect_errors: Array[String] = []
	var source_effect := ContextsScript.create_effect_context({
		"source_type": "free_skill",
		"source_id": skill_id,
		"source_name": skill_id,
		"source_side": side,
		"source_actor_id": 10 if side == "ally" else 110,
		"counts_as_skill_cast": true,
		"spent_skill_points": 0,
		"free_cast": true,
		"counts_as_basic_attack": false,
		"counts_as_attack": false,
		"triggers_enemy_kill_effects": false,
	}, effect_errors)
	assert(effect_errors.is_empty())
	var context := {
		"state": state,
		"caster_side": side,
		"caster_id": 10 if side == "ally" else 110,
		"caster_name": "测试弈者",
		"caster_base_crit_rate": 0.0,
		"source_effect": source_effect,
	}
	var registry := EffectRegistryScript.new()
	var registry_errors: Array[String] = []
	assert(registry.register_map(FreeSkillEffectsScript.handler_map(), registry_errors))
	assert(registry_errors.is_empty())
	return {
		"state": state, "buffs": buffs, "ports": ports, "context": context,
		"registry": registry, "actions": actions, "damage_records": damage_records,
		"combat_rng": combat_rng, "enemy_rng": enemy_rng,
	}


func _prepare(fixture: Dictionary, skill_id: String) -> void:
	var state: Dictionary = fixture["state"]
	var side: String = fixture["context"]["caster_side"]
	var opposing := "enemy" if side == "ally" else "ally"
	match skill_id:
		"burnDetonate":
			fixture["buffs"].apply_unit(_unit(state, opposing, 2), "burn", 3)
			_set_hp(state, opposing, 1, 60.0)
			_set_hp(state, opposing, 2, 40.0)
		"executeStrike":
			_unit(state, side, 2)["atk"] = 25.0
			_set_hp(state, opposing, 1, 70.0)
			_set_hp(state, opposing, 2, 50.0)
			_set_hp(state, opposing, 3, 40.0)
		"pieceAction":
			_unit(state, side, 2)["atk"] = 25.0
			if side == "ally":
				fixture["context"]["target_unit_id"] = _unit(state, side, 2)["id"]
		"pieceHealAll", "smallHeal":
			_set_hp(state, side, 2, 40.0)
			_set_hp(state, side, 3, 60.0)
		"markBurn":
			fixture["buffs"].apply_unit(_unit(state, opposing, 2), "burn", 2)
		"bloodShift":
			_set_hp(state, side, 1, 100.0)
			_set_hp(state, side, 2, 80.0)
			_set_hp(state, side, 3, 60.0)
		"basicDamage":
			_set_hp(state, opposing, 1, 70.0)
			_set_hp(state, opposing, 2, 50.0)
			_set_hp(state, opposing, 3, 40.0)


func _state() -> Dictionary:
	var source := {
		"round": 1, "phase": "player_input", "sp": 4.0, "sp_max": 6.0,
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


func _set_hp(state: Dictionary, side: String, slot: int, hp: float, max_hp: float = 100.0) -> void:
	var unit := _unit(state, side, slot)
	unit["hp"] = hp
	unit["max_hp"] = max_hp
	unit["alive"] = hp > 0.0


func _kill(unit: Dictionary) -> void:
	unit["hp"] = 0.0
	unit["alive"] = false


func _buff(id: String) -> Dictionary:
	return {"id": id, "stacks": 1, "turns": 1, "layer_turns": []}


func _buff_views(state: Dictionary, side: String) -> Array:
	var views: Array = []
	for unit: Dictionary in state["allies" if side == "ally" else "enemies"]:
		views.append(unit["buffs"].duplicate(true))
	return views
