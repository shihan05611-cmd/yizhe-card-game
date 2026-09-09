extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const PieceReactionsScript = preload("res://systems/combat/piece_reactions.gd")
const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const DamageScript = preload("res://core/damage.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const RngScript = preload("res://core/rng.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("ally enchant combines battle and permanent layers while enemy uses battle only", func() -> void:
		_test_enchant_mirror(harness)
	)
	harness.run_test("martyr resolves before add-ons and vexes only a surviving attacker", func() -> void:
		_test_martyr(harness)
	)
	harness.run_test("flame leech mirrors sides and uses attacker burn times defender missing HP", func() -> void:
		_test_flame_leech(harness)
	)
	harness.run_test("counter guards require a blocked living pair plus aura or chivalry", func() -> void:
		_test_counter_guards(harness)
	)
	harness.run_test("counter threshold spends exactly one canonical side SP without callbacks", func() -> void:
		_test_counter_sp(harness)
	)
	harness.run_test("chivalry consumes itself for free super damage bonus and clamps aura energy", func() -> void:
		_test_chivalry(harness)
	)
	harness.run_test("a surviving counter applies defender enchant after counter damage", func() -> void:
		_test_counter_enchant_order(harness)
	)
	harness.run_test("static preflight and runtime action failures preserve or report committed prefix", func() -> void:
		_test_failures(harness)
	)
	print("B4-1R PIECE REACTIONS TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_enchant_mirror(harness: TestHarness) -> void:
	var ally := _fixture("ally")
	ally["buffs"].apply_unit(ally["attacker"], "enchant", 2)
	ally["request"]["permanent_buffs"] = [{
		"id": "flameEnchant", "target": {"type": "pieceSlot", "id": 1}, "stacks": 3,
	}]
	var result := PieceReactionsScript.resolve(ally["request"], ally["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(ally["buffs"].get_unit_stacks(ally["defender"], "burn"), 5)
	harness.assert_equal(ally["buffs"].get_unit_turns(ally["defender"], "burn"), 2)
	harness.assert_equal(result["value"]["steps"], ["attack_enchant_burn"])

	var enemy := _fixture("enemy")
	enemy["buffs"].apply_unit(enemy["attacker"], "enchant", 2)
	enemy["request"]["permanent_buffs"] = [{
		"id": "flameEnchant", "target": {"type": "pieceSlot", "id": 1}, "stacks": 9,
	}]
	result = PieceReactionsScript.resolve(enemy["request"], enemy["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(enemy["buffs"].get_unit_stacks(enemy["defender"], "burn"), 2)

	var dead := _fixture("ally", false, true)
	dead["buffs"].apply_unit(dead["attacker"], "enchant", 2)
	var before: Dictionary = dead["request"]["state"].duplicate(true)
	result = PieceReactionsScript.resolve(dead["request"], dead["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["steps"], [])
	harness.assert_equal(dead["request"]["state"], before)


func _test_martyr(harness: TestHarness) -> void:
	var survivor := _fixture("ally", false, true)
	survivor["defender"]["is_puppet"] = true
	survivor["defender"]["puppet_martyr"] = true
	survivor["attacker"]["hp"] = 50.0
	var result := PieceReactionsScript.resolve(survivor["request"], survivor["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(survivor["attacker"]["hp"], 45.0)
	harness.assert_true(survivor["buffs"].has_unit(survivor["attacker"], "vexed"))
	harness.assert_equal(result["value"]["steps"], ["martyr_damage", "martyr_vexed"])

	var killed := _fixture("enemy", false, true)
	killed["defender"]["is_puppet"] = true
	killed["defender"]["puppet_martyr"] = true
	killed["attacker"]["hp"] = 4.0
	result = PieceReactionsScript.resolve(killed["request"], killed["ports"])
	harness.assert_true(result["ok"])
	harness.assert_false(killed["attacker"]["alive"])
	harness.assert_false(killed["buffs"].has_unit(killed["attacker"], "vexed"))
	harness.assert_equal(result["value"]["steps"], ["martyr_damage"])


func _test_flame_leech(harness: TestHarness) -> void:
	for attacker_side: String in ["enemy", "ally"]:
		var fixture := _fixture(attacker_side)
		var defender_side: String = fixture["defender"]["side"]
		fixture["buffs"].apply_side(defender_side, "flameLeech")
		fixture["buffs"].apply_unit(fixture["attacker"], "burn", 4, 2)
		fixture["defender"]["hp"] = 50.0
		var result := PieceReactionsScript.resolve(fixture["request"], fixture["ports"])
		harness.assert_true(result["ok"])
		# Web: fmt(50 missing * 0.003 * 4) = 0.6.
		harness.assert_equal(fixture["defender"]["hp"], 50.6)
		harness.assert_equal(fixture["heal_records"].size(), 1)
		harness.assert_equal(roundf(float(fixture["heal_records"][0]["amount"]) * 10.0) / 10.0, 0.6)

	var zero := _fixture("enemy")
	zero["buffs"].apply_side("ally", "flameLeech")
	var result := PieceReactionsScript.resolve(zero["request"], zero["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(zero["heal_records"], [])


func _test_counter_guards(harness: TestHarness) -> void:
	var no_block := _fixture("enemy")
	_set_counter_hero(no_block["request"]["state"], "ally", 20.0)
	var result := PieceReactionsScript.resolve(no_block["request"], no_block["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["counter_kind"], "none")
	harness.assert_equal(no_block["attacker"]["hp"], 100.0)

	var no_aura := _fixture("enemy", true)
	result = PieceReactionsScript.resolve(no_aura["request"], no_aura["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["counter_kind"], "none")

	var dead_attacker := _fixture("enemy", true)
	_set_counter_hero(dead_attacker["request"]["state"], "ally", 20.0)
	dead_attacker["attacker"]["hp"] = 0.0
	dead_attacker["attacker"]["alive"] = false
	result = PieceReactionsScript.resolve(dead_attacker["request"], dead_attacker["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["counter_kind"], "none")


func _test_counter_sp(harness: TestHarness) -> void:
	var threshold := _fixture("enemy", true)
	_set_counter_hero(threshold["request"]["state"], "ally", 20.0)
	threshold["request"]["state"]["sp"] = 4.0
	var result := PieceReactionsScript.resolve(threshold["request"], threshold["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["counter_kind"], "normal")
	harness.assert_equal(threshold["attacker"]["hp"], 96.0)
	harness.assert_equal(threshold["request"]["state"]["sp"], 4.0)

	var upgraded := _fixture("enemy", true)
	var hero := _set_counter_hero(upgraded["request"]["state"], "ally", 20.0)
	upgraded["request"]["state"]["sp"] = 5.0
	result = PieceReactionsScript.resolve(upgraded["request"], upgraded["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["counter_kind"], "super")
	harness.assert_equal(upgraded["attacker"]["hp"], 80.0)
	harness.assert_equal(upgraded["request"]["state"]["sp"], 4.0)
	harness.assert_equal(hero["energy"], 25.0)
	harness.assert_equal(upgraded["content_events"].size(), 1)
	harness.assert_equal(upgraded["content_events"][0]["event_id"], "skillPointSpent")
	harness.assert_equal(upgraded["content_events"][0]["payload"]["amount"], 1)
	harness.assert_equal(upgraded["content_events"][0]["payload"]["source_side"], "ally")
	for value: Variant in upgraded["request"].values():
		harness.assert_false(typeof(value) == TYPE_CALLABLE)

	var enemy_upgraded := _fixture("ally", true)
	_set_counter_hero(enemy_upgraded["request"]["state"], "enemy", 0.0)
	enemy_upgraded["request"]["state"]["enemy_sp"] = 5.0
	result = PieceReactionsScript.resolve(enemy_upgraded["request"], enemy_upgraded["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["counter_kind"], "super")
	harness.assert_equal(enemy_upgraded["request"]["state"]["enemy_sp"], 4.0)
	harness.assert_equal(enemy_upgraded["attacker"]["hp"], 80.0)
	harness.assert_equal(enemy_upgraded["content_events"], [])


func _test_chivalry(harness: TestHarness) -> void:
	var fixture := _fixture("ally", true)
	var hero := _set_counter_hero(fixture["request"]["state"], "enemy", 98.0)
	fixture["request"]["state"]["enemy_sp"] = 0.0
	fixture["buffs"].apply_unit(fixture["defender"], "knightChivalry")
	var result := PieceReactionsScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["counter_kind"], "super")
	# 10 ATK * 2.0 super * (1 + 0.25 chivalry bonus) = 25.
	harness.assert_equal(fixture["attacker"]["hp"], 75.0)
	harness.assert_false(fixture["buffs"].has_unit(fixture["defender"], "knightChivalry"))
	harness.assert_equal(fixture["request"]["state"]["enemy_sp"], 0.0)
	harness.assert_equal(hero["energy"], 100.0)
	harness.assert_equal(fixture["content_events"], [])


func _test_counter_enchant_order(harness: TestHarness) -> void:
	var fixture := _fixture("enemy", true)
	_set_counter_hero(fixture["request"]["state"], "ally", 0.0)
	fixture["request"]["state"]["sp"] = 4.0
	fixture["buffs"].apply_unit(fixture["defender"], "enchant", 2)
	fixture["request"]["permanent_buffs"] = [{
		"id": "flameEnchant", "target": {"type": "pieceSlot", "id": 1}, "stacks": 1,
	}]
	var result := PieceReactionsScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["steps"], ["normal_counter_damage", "attack_enchant_burn"])
	harness.assert_equal(fixture["buffs"].get_unit_stacks(fixture["attacker"], "burn"), 3)


func _test_failures(harness: TestHarness) -> void:
	var malformed := _fixture("ally")
	malformed["request"]["permanent_buffs"] = [{
		"id": "missing", "target": {"type": "pieceSlot", "id": 1}, "stacks": 1,
	}]
	var before: Dictionary = malformed["request"]["state"].duplicate(true)
	var result := PieceReactionsScript.resolve(malformed["request"], malformed["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "permanent_buffs snapshot is invalid")
	harness.assert_equal(malformed["request"]["state"], before)

	var bad_shape := _fixture("ally")
	var callback_called := false
	bad_shape["request"]["counter_payment"] = func(_request: Dictionary) -> Dictionary:
		callback_called = true
		return CombatPortsScript.ok(true)
	result = PieceReactionsScript.resolve(bad_shape["request"], bad_shape["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "closed shape")
	harness.assert_false(callback_called)
	result = PieceReactionsScript.resolve(_fixture("ally")["request"], RefCounted.new())
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "valid CombatPorts")

	var record_fail := _fixture("enemy", false, false, true)
	record_fail["buffs"].apply_side("ally", "flameLeech")
	record_fail["buffs"].apply_unit(record_fail["attacker"], "burn", 4, 2)
	record_fail["defender"]["hp"] = 50.0
	result = PieceReactionsScript.resolve(record_fail["request"], record_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "record action failed")
	harness.assert_contains(result["error"], "committed steps: flame_leech_heal")

	var damage_fail := _fixture("enemy", true, false, false, true)
	_set_counter_hero(damage_fail["request"]["state"], "ally", 0.0)
	damage_fail["request"]["state"]["sp"] = 4.0
	result = PieceReactionsScript.resolve(damage_fail["request"], damage_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "counter damage failed")
	harness.assert_contains(result["error"], "committed steps: none")
	harness.assert_equal(damage_fail["attacker"]["hp"], 100.0)


func _fixture(
	attacker_side: String,
	blocked: bool = false,
	defender_died: bool = false,
	fail_record_heal: bool = false,
	invalid_damage: bool = false,
) -> Dictionary:
	var state := _state()
	var defender_side := "enemy" if attacker_side == "ally" else "ally"
	var attacker := _unit(state, attacker_side, 1)
	var defender := _unit(state, defender_side, 1)
	if defender_died:
		defender["hp"] = 0.0
		defender["alive"] = false
	var catalog_errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(catalog_errors)
	assert(catalog_errors.is_empty())
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": state, "catalog": catalog["buffs"],
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
	}, buff_errors)
	assert(buff_errors.is_empty())
	var rng := RngScript.new("piece-reactions-combat")
	var enemy_rng := RngScript.new("piece-reactions-enemy")
	var damage_errors: Array[String] = []
	var damage := DamageScript.new({
		"random": func() -> float: return 0.99,
		"format": func(value: float) -> float: return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(_unit_value: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 0.0,
		"get_damage_multiplier": func(_unit_value: Dictionary, _context: Dictionary, metadata: Dictionary) -> float:
			return NAN if invalid_damage else 1.0 + float(metadata.get("attack_up_rate", 0.0)),
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
		"on_death": func(_unit_value: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"record_damage": func(_payload: Dictionary) -> void: pass,
	}, damage_errors)
	assert(damage_errors.is_empty())
	var heal_records: Array = []
	var content_events: Array = []
	var action_map := {}
	for action_id: String in CombatPortsScript.REQUIRED_ACTION_IDS:
		action_map[action_id] = func(request: Dictionary) -> Dictionary:
			if action_id == "record_heal":
				heal_records.append(request.duplicate(true))
				if fail_record_heal:
					return CombatPortsScript.fail("injected record_heal failure")
			elif action_id == "emit_content_event":
				content_events.append(request.duplicate(true))
			return CombatPortsScript.ok(null)
	var port_errors: Array[String] = []
	var ports := CombatPortsScript.new({
		"actions": action_map,
		"services": {
			"combat_rng": rng, "enemy_policy_rng": enemy_rng,
			"damage": damage, "buffs": buffs,
			"tuning": catalog["tuning"], "catalogs": catalog,
		},
	}, port_errors)
	assert(port_errors.is_empty())
	var hit := _primary_hit(attacker, defender, blocked, defender_died)
	return {
		"request": {
			"state": state,
			"attacker_side": attacker_side, "attacker_id": attacker["id"],
			"defender_side": defender_side, "defender_id": defender["id"],
			"primary_hit": hit, "defender_alive_after_primary_hit": not defender_died,
			"permanent_buffs": [],
		},
		"ports": ports, "buffs": buffs, "attacker": attacker, "defender": defender,
		"heal_records": heal_records, "content_events": content_events,
	}


func _primary_hit(attacker: Dictionary, defender: Dictionary, blocked: bool, died: bool) -> Dictionary:
	var errors: Array[String] = []
	var effect := ContextsScript.create_effect_context({
		"source_type": "basic_attack", "source_id": "normalAttack", "source_name": "普攻",
		"source_side": attacker["side"], "source_actor_id": attacker["id"],
		"counts_as_skill_cast": false, "spent_skill_points": false, "free_cast": false,
		"counts_as_basic_attack": true, "counts_as_attack": true,
		"triggers_enemy_kill_effects": true,
	}, errors)
	var context := ContextsScript.create_damage_context({
		"target_id": defender["id"], "raw_amount": 10.0, "category": "direct",
		"effect": effect, "dealer_type": "piece", "dealer_name": "测试普攻",
		"dealer_id": attacker["id"], "attacker_unit_id": attacker["id"],
		"can_crit": true, "crit_rate": attacker["crit_rate"],
		"guaranteed_crit": false, "can_block": true,
	}, errors)
	assert(errors.is_empty())
	return {
		"dealt": 10.0, "blocked": blocked, "died": died, "crit": false,
		"damage_context": context, "death_context": null,
	}


func _state() -> Dictionary:
	var source := {
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
	for unit: Dictionary in state["allies" if side == "ally" else "enemies"]:
		if unit["slot"] == slot:
			return unit
	assert(false)
	return {}


func _set_counter_hero(state: Dictionary, side: String, energy: float) -> Dictionary:
	if side == "ally":
		var hero := {
			"id": 4, "name": "骑士", "deployed": true, "ex_skill": "counterAura",
			"energy": energy, "max_energy": 100.0, "base_crit_rate": 0.0,
			"fist_momentum": 0,
		}
		state["player_heroes"] = [hero]
		return hero
	var enemy_hero := {
		"id": 4, "name": "敌方骑士", "ex_skill": "counterAura", "skills": [],
		"skill_pool": ["basicDamage"], "energy": energy, "max_energy": 100.0,
		"base_crit_rate": 0.0, "fist_momentum": 0,
	}
	state["enemy_heroes"] = [enemy_hero]
	return enemy_hero
