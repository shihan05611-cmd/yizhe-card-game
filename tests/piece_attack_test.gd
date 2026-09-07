extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const PieceAttackScript = preload("res://systems/combat/piece_attack.gd")
const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const DamageScript = preload("res://core/damage.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const HookDispatcherScript = preload("res://systems/relics/hook_dispatcher.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")


class FixedRng extends RefCounted:
	var values: Array
	var calls := 0

	func _init(configured: Array = []) -> void:
		values = configured.duplicate()

	func next() -> float:
		var value := float(values[calls]) if calls < values.size() else 0.99
		calls += 1
		return value

	func int_range(minimum: int, _maximum: int) -> int:
		return minimum

	func pick(items: Array) -> Variant:
		return null if items.is_empty() else items[0]


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("piece basic attacks mirror sides and honor lane or forced targets", func() -> void:
		_test_basic_targets(harness)
	)
	harness.run_test("dead disarm and stealth guards commit only their specified prefix", func() -> void:
		_test_guards_and_stealth(harness)
	)
	harness.run_test("extra actions and crossbow use canonical charges and combat RNG", func() -> void:
		_test_extra_and_crossbow(harness)
	)
	harness.run_test("pursuit consumes bounded layers and retargets by lowest hp percent", func() -> void:
		_test_pursuit(harness)
	)
	harness.run_test("march columns crit and break formation adds marked crit chance", func() -> void:
		_test_march_and_break(harness)
	)
	harness.run_test("banner rewards the deployed highest-energy hero with stable ties", func() -> void:
		_test_banner(harness)
	)
	harness.run_test("content events precede reactions and failures expose committed steps", func() -> void:
		_test_reaction_order_and_failures(harness)
	)
	harness.run_test("single executeStrike plans are strict immutable one-shot values", func() -> void:
		_test_single_plan(harness)
	)
	harness.run_test("shadow sequences preflight all plans then retarget and complete", func() -> void:
		_test_shadow_sequence(harness)
	)
	harness.run_test("closed inputs and permanent snapshots fail before consumptions or RNG", func() -> void:
		_test_static_failures(harness)
	)
	print("B4-1A PIECE ATTACK TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_basic_targets(harness: TestHarness) -> void:
	var ally := _fixture()
	var request := _request(ally, "ally", 2)
	var result := PieceAttackScript.execute(request, ally["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(_unit(ally["state"], "enemy", 2)["hp"], 90.0)
	harness.assert_equal(_event_ids(ally["events"]), ["pieceAttackHit", "basicAttackHit"])
	harness.assert_equal(result["value"]["primary_target_id"], 2)

	var enemy := _fixture()
	request = _request(enemy, "enemy", 3)
	request["forced_target_side"] = "ally"
	request["forced_target_id"] = 5
	request["forced_target_slot"] = 5
	result = PieceAttackScript.execute(request, enemy["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(_unit(enemy["state"], "ally", 5)["hp"], 90.0)
	harness.assert_equal(_event_ids(enemy["events"]), ["pieceAttackHit"])


func _test_guards_and_stealth(harness: TestHarness) -> void:
	var dead := _fixture()
	var attacker := _unit(dead["state"], "ally", 1)
	attacker["hp"] = 0.0
	attacker["alive"] = false
	var result := PieceAttackScript.execute(_request(dead), dead["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["reason"], "dead")
	harness.assert_equal(dead["rng"].calls, 0)

	var disarmed := _fixture()
	attacker = _unit(disarmed["state"], "ally", 1)
	attacker["disarm_turns"] = 2
	attacker["extra_action_charges"] = 1
	result = PieceAttackScript.execute(_request(disarmed), disarmed["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(attacker["disarm_turns"], 1)
	harness.assert_equal(attacker["extra_action_charges"], 1)
	harness.assert_equal(disarmed["rng"].calls, 0)

	var stealth := _fixture()
	attacker = _unit(stealth["state"], "ally", 1)
	attacker["stealth_attack_ready"] = true
	stealth["buffs"].apply_unit(attacker, "stealth", 1, 2)
	_unit(stealth["state"], "enemy", 4)["hp"] = 12.0
	result = PieceAttackScript.execute(_request(stealth), stealth["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["primary_target_id"], 4)
	harness.assert_false(attacker["stealth_attack_ready"])
	harness.assert_false(stealth["buffs"].has_unit(attacker, "stealth"))


func _test_extra_and_crossbow(harness: TestHarness) -> void:
	var extra := _fixture()
	var attacker := _unit(extra["state"], "ally", 1)
	attacker["extra_action_charges"] = 2
	var result := PieceAttackScript.execute(_request(extra), extra["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(attacker["extra_action_charges"], 1)
	harness.assert_equal(_unit(extra["state"], "enemy", 1)["hp"], 80.0)
	harness.assert_equal(result["value"]["strikes"], 2)

	var crossbow := _fixture([0.99, 0.99, 0.49])
	attacker = _unit(crossbow["state"], "ally", 1)
	attacker["class_id"] = "crossbow"
	var request := _request(crossbow)
	request["trigger_pursuit"] = false
	result = PieceAttackScript.execute(request, crossbow["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(_unit(crossbow["state"], "enemy", 1)["hp"], 92.5)
	harness.assert_equal(crossbow["buffs"].get_unit_stacks(attacker, "pursuit"), 1)
	harness.assert_equal(crossbow["rng"].calls, 3)

	var plus := _fixture([0.99, 0.99, 0.55], ["crossbowPlus"])
	attacker = _unit(plus["state"], "ally", 1)
	attacker["class_id"] = "crossbow"
	request = _request(plus)
	request["trigger_pursuit"] = false
	result = PieceAttackScript.execute(request, plus["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(plus["buffs"].get_unit_stacks(attacker, "pursuit"), 1)


func _test_pursuit(harness: TestHarness) -> void:
	var retarget := _fixture()
	var attacker := _unit(retarget["state"], "ally", 1)
	retarget["buffs"].apply_unit(attacker, "pursuit", 2)
	_unit(retarget["state"], "enemy", 1)["hp"] = 10.0
	_unit(retarget["state"], "enemy", 2)["hp"] = 20.0
	var result := PieceAttackScript.execute(_request(retarget), retarget["ports"])
	harness.assert_true(result["ok"])
	harness.assert_true(result["value"]["primary_died"])
	harness.assert_equal(result["value"]["pursuit_count"], 2)
	harness.assert_equal(retarget["buffs"].get_unit_stacks(attacker, "pursuit"), 0)
	var hit_targets := _event_targets(retarget["events"], "pieceAttackHit")
	harness.assert_equal(hit_targets, [1, 2, 2])

	var bounded := _fixture()
	attacker = _unit(bounded["state"], "ally", 1)
	attacker["atk"] = 0.0
	bounded["buffs"].apply_unit(attacker, "pursuit", 13)
	result = PieceAttackScript.execute(_request(bounded), bounded["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["pursuit_count"], 12)
	harness.assert_equal(bounded["buffs"].get_unit_stacks(attacker, "pursuit"), 1)


func _test_march_and_break(harness: TestHarness) -> void:
	var march := _fixture()
	var attacker := _unit(march["state"], "ally", 2)
	attacker["general"] = true
	march["buffs"].apply_unit(attacker, "march", 1)
	var result := PieceAttackScript.execute(_request(march, "ally", 2), march["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(_unit(march["state"], "enemy", 2)["hp"], 85.0)
	harness.assert_equal(_unit(march["state"], "enemy", 5)["hp"], 85.0)
	harness.assert_equal(result["value"]["strikes"], 2)

	var forced := _fixture()
	attacker = _unit(forced["state"], "ally", 2)
	attacker["general"] = true
	forced["buffs"].apply_unit(attacker, "march", 1)
	var request := _request(forced, "ally", 2)
	request["forced_target_side"] = "enemy"
	request["forced_target_id"] = 1
	request["forced_target_slot"] = 1
	result = PieceAttackScript.execute(request, forced["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(_unit(forced["state"], "enemy", 1)["hp"], 85.0)
	harness.assert_equal(_unit(forced["state"], "enemy", 4)["hp"], 85.0)
	harness.assert_equal(_unit(forced["state"], "enemy", 2)["hp"], 100.0)

	var broken := _fixture([0.15, 0.99])
	var target := _unit(broken["state"], "enemy", 1)
	broken["buffs"].apply_side("ally", "breakFormation", 1)
	broken["buffs"].apply_unit(target, "breakMarked", 1)
	result = PieceAttackScript.execute(_request(broken), broken["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(target["hp"], 85.0)


func _test_banner(harness: TestHarness) -> void:
	var fixture := _fixture()
	var attacker := _unit(fixture["state"], "ally", 1)
	attacker["class_id"] = "banner"
	fixture["state"]["player_heroes"] = [
		_player_hero(3, 90.0, 100.0, true),
		_player_hero(2, 90.0, 92.0, true),
		_player_hero(1, 99.0, 100.0, false),
	]
	var result := PieceAttackScript.execute(_request(fixture), fixture["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(fixture["state"]["player_heroes"][0]["energy"], 90.0)
	harness.assert_equal(fixture["state"]["player_heroes"][1]["energy"], 92.0)
	harness.assert_equal(fixture["state"]["player_heroes"][2]["energy"], 99.0)
	harness.assert_true("banner_energy" in result["value"]["steps"])


func _test_reaction_order_and_failures(harness: TestHarness) -> void:
	var ordered := _fixture()
	var attacker := _unit(ordered["state"], "ally", 1)
	var target := _unit(ordered["state"], "enemy", 1)
	ordered["buffs"].apply_unit(attacker, "enchant", 2)
	var result := PieceAttackScript.execute(_request(ordered), ordered["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(ordered["event_burn_snapshots"], [0, 0])
	harness.assert_equal(ordered["buffs"].get_unit_stacks(target, "burn"), 2)

	var event_fail := _fixture([], [], "pieceAttackHit")
	attacker = _unit(event_fail["state"], "ally", 1)
	target = _unit(event_fail["state"], "enemy", 1)
	event_fail["buffs"].apply_unit(attacker, "enchant", 2)
	result = PieceAttackScript.execute(_request(event_fail), event_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_equal(target["hp"], 90.0)
	harness.assert_equal(event_fail["buffs"].get_unit_stacks(target, "burn"), 0)
	harness.assert_contains(result["error"], "committed steps: damage:1")

	var reaction_fail := _fixture([], [], "", true)
	attacker = _unit(reaction_fail["state"], "ally", 1)
	target = _unit(reaction_fail["state"], "enemy", 1)
	reaction_fail["buffs"].apply_side("enemy", "flameLeech", 1)
	reaction_fail["buffs"].apply_unit(attacker, "burn", 4, 2)
	target["hp"] = 50.0
	result = PieceAttackScript.execute(_request(reaction_fail), reaction_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "piece reaction failed")
	harness.assert_contains(result["error"], "event:basicAttackHit")

	var damage_fail := _fixture([], [], "", false, true)
	var before: Dictionary = damage_fail["state"].duplicate(true)
	result = PieceAttackScript.execute(_request(damage_fail), damage_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "piece attack damage failed")
	harness.assert_contains(result["error"], "committed steps: none")
	harness.assert_equal(damage_fail["state"], before)


func _test_single_plan(harness: TestHarness) -> void:
	var fixture := _fixture()
	_unit(fixture["state"], "enemy", 1)["hp"] = 12.0
	var plan := _plan(fixture["state"], "ally", 1, "enemy", 1, "斩杀", 1.5, "execute", _effect("free_skill", "execute", "ally", 7, true))
	var before_plan: Dictionary = plan.duplicate(true)
	var wrapper := _consume_request(fixture, plan)
	var result := PieceAttackScript.consume_plan(wrapper, fixture["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["status"], "completed_b4_execution")
	harness.assert_true(result["value"]["primary_died"])
	harness.assert_equal(plan, before_plan)
	var hp_after: float = _unit(fixture["state"], "enemy", 1)["hp"]
	var replay_wrapper := _consume_request(fixture, result["value"])
	result = PieceAttackScript.consume_plan(replay_wrapper, fixture["ports"])
	harness.assert_false(result["ok"])
	harness.assert_equal(_unit(fixture["state"], "enemy", 1)["hp"], hp_after)


func _test_shadow_sequence(harness: TestHarness) -> void:
	var fixture := _fixture()
	_unit(fixture["state"], "enemy", 1)["hp"] = 4.0
	_unit(fixture["state"], "enemy", 2)["hp"] = 20.0
	var source := _effect("ultimate", "shadow", "ally", 3, true)
	var plan1 := _plan(fixture["state"], "ally", 1, "enemy", 1, "潜行追击", 0.5, "pursuit", source)
	var plan2 := _plan(fixture["state"], "ally", 2, "enemy", 1, "潜行追击", 0.5, "pursuit", source)
	var sequence := {
		"kind": "execute_piece_attack_sequence", "status": "pending_b4_execution",
		"initial_target_side": "enemy", "initial_target_id": 1, "initial_target_slot": 1,
		"retarget_on_target_death": true,
		"retarget_policy": "lowest_hp_percent_lockable", "plans": [plan1, plan2],
	}
	var before_sequence: Dictionary = sequence.duplicate(true)
	var result := PieceAttackScript.consume_sequence(_consume_request(fixture, sequence), fixture["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["status"], "completed_b4_execution")
	harness.assert_equal(result["value"]["plan_results"].map(func(item: Dictionary) -> Variant: return item["target_id"]), [1, 2])
	harness.assert_equal(sequence, before_sequence)

	var invalid := _fixture()
	var invalid_sequence: Dictionary = sequence.duplicate(true)
	invalid_sequence["retarget_policy"] = "random"
	var before_state: Dictionary = invalid["state"].duplicate(true)
	result = PieceAttackScript.consume_sequence(_consume_request(invalid, invalid_sequence), invalid["ports"])
	harness.assert_false(result["ok"])
	harness.assert_equal(invalid["state"], before_state)
	harness.assert_equal(invalid["rng"].calls, 0)


func _test_static_failures(harness: TestHarness) -> void:
	var fixture := _fixture()
	var attacker := _unit(fixture["state"], "ally", 1)
	attacker["disarm_turns"] = 1
	attacker["extra_action_charges"] = 1
	var request := _request(fixture)
	request["permanent_buffs"] = [{
		"id": "missing", "target": {"type": "pieceSlot", "id": 1}, "stacks": 1,
	}]
	var before: Dictionary = fixture["state"].duplicate(true)
	var result := PieceAttackScript.execute(request, fixture["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "permanent Buff snapshot invalid")
	harness.assert_equal(fixture["state"], before)
	harness.assert_equal(fixture["rng"].calls, 0)

	var bad_shape := _request(fixture)
	bad_shape["unknown"] = true
	result = PieceAttackScript.execute(bad_shape, fixture["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "closed shape")
	result = PieceAttackScript.execute(_request(fixture), RefCounted.new())
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "valid CombatPorts")


func _fixture(
	rng_values: Array = [],
	owned_relics: Array = [],
	fail_event: String = "",
	fail_record_heal: bool = false,
	invalid_damage: bool = false,
) -> Dictionary:
	var state := _state()
	var catalog_errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(catalog_errors)
	assert(catalog_errors.is_empty())
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": state, "catalog": catalog["buffs"],
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
	}, buff_errors)
	assert(buff_errors.is_empty())
	var rng := FixedRng.new(rng_values)
	var policy_rng := FixedRng.new()
	var damage_errors: Array[String] = []
	var damage := DamageScript.new({
		"random": func() -> float: return rng.next(),
		"format": func(value: float) -> float: return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return unit["base_block_rate"],
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return NAN if invalid_damage else 1.0,
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"record_damage": func(_payload: Dictionary) -> void: pass,
	}, damage_errors)
	assert(damage_errors.is_empty())
	var event_records: Array = []
	var event_burn_snapshots: Array = []
	var action_map := {}
	for action_id: String in CombatPortsScript.REQUIRED_ACTION_IDS:
		action_map[action_id] = func(action_request: Dictionary) -> Dictionary:
			if action_id == "emit_content_event":
				var event_id: String = action_request["event_id"]
				event_records.append({
					"id": event_id, "target_id": action_request["payload"]["target"]["id"],
				})
				event_burn_snapshots.append(buffs.get_unit_stacks(action_request["payload"]["target"], "burn"))
				if event_id == fail_event:
					return CombatPortsScript.fail("injected event failure")
			if action_id == "record_heal" and fail_record_heal:
				return CombatPortsScript.fail("injected heal record failure")
			return CombatPortsScript.ok(null)
	var port_errors: Array[String] = []
	var ports := CombatPortsScript.new({
		"actions": action_map,
		"services": {
			"combat_rng": rng, "enemy_policy_rng": policy_rng,
			"damage": damage, "buffs": buffs,
			"tuning": catalog["tuning"], "catalogs": catalog,
		},
	}, port_errors)
	assert(port_errors.is_empty())
	return {
		"state": state, "catalog": catalog, "buffs": buffs, "rng": rng,
		"events": event_records, "event_burn_snapshots": event_burn_snapshots,
		"ports": ports, "relic_system": _relic_system(catalog, owned_relics),
	}


func _relic_system(catalog: Dictionary, owned: Array) -> Variant:
	var dispatcher_errors: Array[String] = []
	var dispatcher := HookDispatcherScript.new({
		"event_catalog": catalog["events"],
		"on_error": func(_message: String, _metadata: Dictionary) -> void: pass,
	}, dispatcher_errors)
	assert(dispatcher_errors.is_empty())
	var relic_errors: Array[String] = []
	var system := RelicSystemScript.new({
		"catalog": catalog["relics"], "dispatcher": dispatcher,
		"get_owned_relic_ids": func() -> Array: return owned,
		"actions": {},
	}, relic_errors)
	assert(relic_errors.is_empty())
	assert(system.is_valid())
	return system


func _request(fixture: Dictionary, side: String = "ally", slot: int = 1) -> Dictionary:
	return {
		"state": fixture["state"], "attacker_side": side,
		"attacker_id": slot, "attacker_slot": slot,
		"forced_target_side": null, "forced_target_id": null, "forced_target_slot": null,
		"attack_name": "普攻", "damage_multiplier": 1.0,
		"trigger_extra_action": true, "trigger_pursuit": true,
		"trigger_banner_action": true, "damage_kind_override": "",
		"source_effect": _effect("basic_attack", "normalAttack", side, slot, false),
		"permanent_buffs": [], "relic_system": fixture["relic_system"],
	}


func _consume_request(fixture: Dictionary, plan: Dictionary) -> Dictionary:
	return {
		"state": fixture["state"], "plan": plan,
		"permanent_buffs": [], "relic_system": fixture["relic_system"],
	}


func _plan(
	state: Dictionary, attacker_side: String, attacker_slot: int,
	target_side: String, target_slot: int, attack_name: String,
	damage_multiplier: float, damage_kind: String, source: Dictionary,
) -> Dictionary:
	return {
		"kind": "execute_piece_attack", "attacker_side": attacker_side,
		"attacker_id": _unit(state, attacker_side, attacker_slot)["id"],
		"attacker_slot": attacker_slot, "target_side": target_side,
		"target_id": _unit(state, target_side, target_slot)["id"],
		"target_slot": target_slot, "attack_name": attack_name,
		"damage_multiplier": damage_multiplier, "trigger_extra_action": false,
		"trigger_pursuit": false, "damage_kind_override": damage_kind,
		"source_effect": source.duplicate(true),
	}


func _effect(
	type_id: String, source_id: String, side: String, actor_id: Variant,
	counts_skill: bool,
) -> Dictionary:
	var errors: Array[String] = []
	var effect := ContextsScript.create_effect_context({
		"source_type": type_id, "source_id": source_id, "source_name": source_id,
		"source_side": side, "source_actor_id": actor_id,
		"counts_as_skill_cast": counts_skill, "spent_skill_points": false,
		"free_cast": counts_skill, "counts_as_basic_attack": type_id == "basic_attack",
		"counts_as_attack": true, "triggers_enemy_kill_effects": true,
	}, errors)
	assert(errors.is_empty())
	return effect


func _state() -> Dictionary:
	var errors: Array[String] = []
	var state := BattleStateScript.create({
		"round": 1, "phase": "piece_attack", "sp": 4.0, "sp_max": 6.0,
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
	}, errors)
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


func _player_hero(id: int, energy: float, max_energy: float, deployed: bool) -> Dictionary:
	return {
		"id": id, "name": "弈者%d" % id, "deployed": deployed, "ex_skill": "testEx",
		"energy": energy, "max_energy": max_energy, "base_crit_rate": 0.0,
		"fist_momentum": 0,
	}


func _unit(state: Dictionary, side: String, slot: int) -> Dictionary:
	for unit: Dictionary in state["allies" if side == "ally" else "enemies"]:
		if unit["slot"] == slot:
			return unit
	assert(false)
	return {}


func _event_ids(events: Array) -> Array:
	return events.map(func(item: Dictionary) -> Variant: return item["id"])


func _event_targets(events: Array, id: String) -> Array:
	var result: Array = []
	for item: Dictionary in events:
		if item["id"] == id:
			result.append(item["target_id"])
	return result
