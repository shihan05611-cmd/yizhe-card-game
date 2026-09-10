extends RefCounted

const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const Dispatcher = preload("res://systems/relics/hook_dispatcher.gd")
const Relics = preload("res://systems/relics/relic_system.gd")
const EnemySpecials = preload("res://systems/enemy_specials/enemy_special_system.gd")
const Rng = preload("res://core/rng.gd")


class ClonePickRng extends RefCounted:
	var picked: Variant

	func pick(_values: Array) -> Variant:
		return picked


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("owned relic modifiers match Web queries and rounding", func() -> void:
		_test_relic_modifiers(harness)
	)
	harness.run_test("unowned relics neither modify queries nor dispatch hooks", func() -> void:
		_test_owned_gating(harness)
	)
	harness.run_test("high-value relic hooks match Arc Ember Thorn and battle-once behavior", func() -> void:
		_test_high_value_hooks(harness)
	)
	harness.run_test("reward relic hooks enforce round actor target kill and sacrifice semantics", func() -> void:
		_test_reward_hooks(harness)
	)
	harness.run_test("relic action failure is reported and does not consume its limit", func() -> void:
		_test_relic_action_failure(harness)
	)
	harness.run_test("enemy special initialization scales stats and invalid input is mutation-free", func() -> void:
		_test_special_initialization(harness)
	)
	harness.run_test("devourer drains SP then a seeded surviving hero energy", func() -> void:
		_test_devourer_branches(harness)
	)
	harness.run_test("devourer invalid dependencies fail closed before mutation", func() -> void:
		_test_devourer_fail_closed(harness)
	)
	harness.run_test("devourer rejects same-id RNG clones by reference identity", func() -> void:
		_test_devourer_rng_identity(harness)
	)
	harness.run_test("echo grows only from direct non-delayed damage and multiplies later output", func() -> void:
		_test_echo_growth(harness)
	)
	harness.run_test("enemy reset and dispatch only mutate current enemies", func() -> void:
		_test_current_enemy_boundary(harness)
	)
	print("B2 RELICS SPECIALS TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_relic_modifiers(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var owned := {"ids": [
		"trueNameUnseal", "crossbowPlus", "assassinPlus", "discountCard",
		"tradePermit", "shentongAssaultBurst", "spLimitPlus", "witheredSeal",
	]}
	var system: Variant = _relic_system(content, owned, {}, [])
	harness.assert_true(system.has("trueNameUnseal"))
	harness.assert_false(system.has("missing"))
	harness.assert_equal(system.get_definition("missing"), null)
	harness.assert_equal(system.get_skill_point_max_adjustment(), 1.0)
	harness.assert_equal(system.get_effective_skill_point_cost(2, "ally", 1, "freeSkill"), 0)
	harness.assert_equal(system.get_effective_skill_point_cost(2, "ally", 2, "exclusive"), 0)
	harness.assert_equal(system.get_effective_skill_point_cost(2, "ally", 3, "freeSkill"), 2)
	harness.assert_equal(system.get_effective_skill_point_cost(2, "enemy", 1, "freeSkill"), 2)
	harness.assert_equal(system.get_class_max_hp_adjustment("crossbow", "ally"), -20.0)
	harness.assert_equal(system.get_crossbow_pursuit_chance(0.5, {"side": "ally", "class_id": "crossbow"}), 0.6)
	harness.assert_equal(system.get_effective_crit_rate(0.1, {"side": "ally", "class_id": "assassin", "hp": 49, "max_hp": 100}), 0.4)
	harness.assert_equal(system.get_effective_crit_rate(0.9, {"side": "ally", "classId": "assassin", "hp": 10, "maxHp": 100}), 0.95)
	harness.assert_true(system.can_sell_free_skills())
	harness.assert_equal(system.get_currency_cost(5), 4)
	harness.assert_equal(system.get_effective_healing_amount(40, {"side": "enemy"}), 30.0)
	harness.assert_equal(system.get_effective_healing_amount(40, {"side": "ally"}), 40.0)
	harness.assert_equal(system.get_shentong_assault_damage_multiplier("assault"), 5.0)
	harness.assert_equal(system.get_shentong_assault_damage_multiplier("charge"), 3.0)
	harness.assert_equal(system.get_shentong_charge_energy_gain("charge"), 0.0)
	owned["ids"] = ["shentongChargeOverload"]
	harness.assert_equal(system.get_shentong_charge_energy_gain("charge"), 30.0)


func _test_owned_gating(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var calls: Array = []
	var owned := {"ids": []}
	var setup := _relic_setup(content, owned, _actions(calls))
	var dispatcher: Variant = setup["dispatcher"]
	var system: Variant = setup["system"]
	dispatcher.dispatch("skill_point_spent", {"round": 1, "amount": 2, "source_side": "ally"})
	harness.assert_equal(calls, [])
	harness.assert_equal(system.get_skill_point_max_adjustment(), 0.0)
	owned["ids"] = ["arcConductor"]
	dispatcher.dispatch("skill_point_spent", {"round": 1, "amount": 2, "source_side": "ally"})
	harness.assert_equal(calls, [["arcConductor", 12.0]])


func _test_high_value_hooks(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var calls: Array = []
	var owned := {"ids": ["ultPursuitMark", "arcConductor", "emberStorm", "thornCrown"]}
	var setup := _relic_setup(content, owned, _actions(calls))
	var dispatcher: Variant = setup["dispatcher"]
	var enemy := {"id": 9, "side": "enemy", "alive": true, "buffs": [{"id": "burn", "stacks": 3}]}
	var attacker := {"id": 7, "side": "enemy", "alive": true}
	var ally_effect := {"source_type": "ultimate", "source_side": "ally", "triggers_enemy_kill_effects": true}
	# Web-shaped payload regression: the dispatcher owns camelCase normalization.
	var web_ally_effect := {"sourceType": "ultimate", "sourceSide": "ally", "triggersEnemyKillEffects": true}
	dispatcher.dispatch("ultimateCast", {"round": 1, "sourceEffect": web_ally_effect})
	dispatcher.dispatch("ultimateCast", {"round": 1, "sourceEffect": web_ally_effect})
	dispatcher.dispatch("skillPointSpent", {"round": 1, "amount": 2, "sourceSide": "ally"})
	dispatcher.dispatch("unit_died", {
		"round": 1, "target": enemy, "sourceEffect": web_ally_effect,
		"deathContext": {"triggersEnemyKillEffects": true},
	})
	dispatcher.dispatch("unit_died", {
		"round": 1, "target": enemy,
		"sourceEffect": {"sourceSide": "ally", "triggersEnemyKillEffects": false},
		"deathContext": {"triggersEnemyKillEffects": false},
	})
	dispatcher.dispatch("unitBlocked", {
		"round": 1,
		"target": {"id": 3, "side": "ally", "alive": true},
		"actor": attacker,
		"rawAmountBeforeBlock": 80,
		"amount": 40,
	})
	harness.assert_equal(calls, [
		["ultPursuit", 1],
		["arcConductor", 12.0],
		["emberStorm", 9],
		["thornCrown", 7, 40.0],
	])
	harness.assert_equal(dispatcher.get_trigger_count("ultPursuitMark", 0), 1)
	dispatcher.reset_battle()
	dispatcher.dispatch("ultimateCast", {"round": 1, "source_effect": ally_effect})
	harness.assert_equal(calls.back(), ["ultPursuit", 1])


func _test_reward_hooks(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var calls: Array = []
	var owned := {"ids": ["rationChip", "zeroCostSpark", "scorchShard", "fieldBandage", "graveChange", "lastEmber"]}
	var setup := _relic_setup(content, owned, _actions(calls))
	var dispatcher: Variant = setup["dispatcher"]
	var actor_one := {"id": 1, "side": "ally", "alive": true}
	var actor_two := {"id": 2, "side": "ally", "alive": true}
	var enemy := {"id": 4, "side": "enemy", "alive": true}
	var ally_one := {"id": 1, "side": "ally", "alive": true, "max_hp": 100}
	var ally_two := {"id": 2, "side": "ally", "alive": true, "max_hp": 200}
	var free_effect := {"source_type": "free_skill", "source_side": "ally"}
	dispatcher.dispatch("battleStart", {"round": 1})
	dispatcher.dispatch("freeSkillCast", {"round": 1, "amount": 0, "effect_context": free_effect})
	dispatcher.dispatch("freeSkillCast", {"round": 1, "amount": 0, "effect_context": free_effect})
	dispatcher.dispatch("pieceAttackHit", {"round": 1, "actor": actor_one, "target": enemy})
	dispatcher.dispatch("pieceAttackHit", {"round": 1, "actor": actor_one, "target": enemy})
	dispatcher.dispatch("pieceAttackHit", {"round": 1, "actor": actor_two, "target": enemy})
	dispatcher.dispatch("unitDamaged", {"round": 1, "target": ally_one})
	dispatcher.dispatch("unitDamaged", {"round": 1, "target": ally_one})
	dispatcher.dispatch("unitDamaged", {"round": 1, "target": ally_two})
	dispatcher.dispatch("unitDied", {"round": 1, "target": enemy, "effect_context": free_effect})
	dispatcher.dispatch("unitDied", {"round": 1, "target": enemy, "effect_context": free_effect})
	dispatcher.dispatch("unitDied", {
		"round": 1,
		"target": {"id": 3, "side": "ally", "alive": false},
		"effect_context": {"source_type": "sacrifice", "source_side": "ally", "triggers_enemy_kill_effects": false},
	})
	dispatcher.reset_round()
	dispatcher.dispatch("freeSkillCast", {"round": 2, "amount": 0, "effect_context": free_effect})
	harness.assert_equal(calls, [
		["sp", 1], ["energy", 10], ["burn", 4, 1], ["burn", 4, 1],
		["fieldBandage", 1, 2.0], ["fieldBandage", 2, 4.0],
		["sp", 1], ["lastEmber", 0.1], ["sp", 1], ["sp", 1], ["energy", 10],
	])


func _test_relic_action_failure(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var reports: Array = []
	var owned := {"ids": ["ultPursuitMark"]}
	var setup := _relic_setup(content, owned, {
		"apply_pursuit_to_alive_allies": func(_stacks: int) -> Dictionary: return {"ok": false, "error": "action rejected"},
	}, reports)
	var dispatcher: Variant = setup["dispatcher"]
	var payload := {"round": 1, "source_effect": {"source_side": "ally"}}
	harness.assert_equal(dispatcher.dispatch("ultimateCast", payload)["delivered"], 0)
	harness.assert_equal(dispatcher.get_trigger_count("ultPursuitMark", 0), 0)
	harness.assert_equal(reports[0]["metadata"]["phase"], "effect")
	harness.assert_contains(reports[0]["message"], "action rejected")


func _test_special_initialization(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var enemies: Array = []
	var setup := _enemy_setup(content, enemies, [], {"value": 0.0}, Rng.seeded("special-init"))
	var system: Variant = setup["system"]
	var devourer := _enemy(null, 1)
	var echo := _enemy(null, 2)
	var errors: Array[String] = []
	harness.assert_true(system.initialize_unit(devourer, "devourer", true, errors))
	harness.assert_true(system.initialize_unit(echo, "echo", true, errors))
	harness.assert_equal([devourer["special_id"], devourer["hp"], devourer["max_hp"], system.get_definition("devourer").grid_cells], ["devourer", 200.0, 200.0, 2])
	harness.assert_equal([echo["special_id"], echo["hp"], echo["max_hp"], system.get_definition("echo").grid_cells], ["echo", 300.0, 300.0, 3])
	var invalid := {"id": 8, "side": "enemy", "alive": true, "hp": "bad", "max_hp": 100, "atk": 20}
	var before: Dictionary = invalid.duplicate(true)
	harness.assert_false(system.initialize_unit(invalid, "echo", true, errors))
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(invalid, before)
	harness.assert_false(system.initialize_unit(invalid, "missing", false, errors))
	harness.assert_equal(invalid, before)


func _test_devourer_branches(harness: TestHarness) -> void:
	var first := _run_devourer_seed("B2-devourer")
	var replay := _run_devourer_seed("B2-devourer")
	harness.assert_equal(first, replay)
	harness.assert_equal(first["sp"], 0.0)
	harness.assert_equal(first["events"].map(func(event: Dictionary) -> String: return event["kind"]), ["sp_drain", "sp_drain", "energy_drain"])
	var sp_event: Dictionary = first["events"][0]
	harness.assert_equal([
		sp_event["resource"], sp_event["old_sp"], sp_event["new_sp"],
		sp_event["amount"], sp_event["source_action_id"],
	], ["sp", 2.0, 1.0, 1.0, "normalAttack"])
	harness.assert_equal(sp_event["actor"], {"id": 1, "side": "enemy", "slot": null})
	var second_sp_event: Dictionary = first["events"][1]
	harness.assert_equal([
		second_sp_event["old_sp"], second_sp_event["new_sp"], second_sp_event["amount"],
	], [1.0, 0.0, 1.0])
	var energy_event: Dictionary = first["events"][2]
	harness.assert_equal([
		energy_event["resource"], energy_event["old_sp"], energy_event["new_sp"],
		energy_event["amount"], energy_event["source_action_id"],
	], ["hero_energy", 0.0, 0.0, 10.0, "normalAttack"])
	harness.assert_true(energy_event["target"]["hero_id"] in [1, 2])
	harness.assert_equal(
		energy_event["target"]["old_energy"] - energy_event["target"]["new_energy"],
		10.0,
	)
	harness.assert_equal(first["energies"].reduce(func(sum: float, value: Variant) -> float: return sum + float(value), 0.0), 90.0)
	harness.assert_equal(first["logs"].size(), 3)
	var content: Dictionary = ContentCatalog.build()
	var empty_devourer := _enemy("devourer", 10)
	var empty_setup := _enemy_setup(content, [empty_devourer], [], {"value": 0.0}, Rng.seeded("empty-active"))
	empty_setup["dispatcher"].dispatch("pieceAttackHit", {"actor": empty_devourer})
	harness.assert_equal(empty_setup["events"], [])
	harness.assert_equal(empty_setup["logs"], [])


func _test_devourer_fail_closed(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var devourer := _enemy("devourer", 1)
	var heroes := [{"id": 1, "side": "ally", "alive": true, "energy": 50}]
	var errors: Array[String] = []
	var dispatcher: Variant = _dispatcher(content, [])
	var system: Variant = EnemySpecials.new({
		"catalog": content["enemy_specials"],
		"dispatcher": dispatcher,
		"get_enemies": func() -> Array: return [devourer],
		"get_active_heroes": func() -> Array: return heroes,
		"get_skill_points": func() -> float: return NAN,
		"set_skill_points": func(_value: float) -> void: harness.fail("setter must not run"),
		"gain_hero_energy": func(_hero: Dictionary, _amount: int) -> void: harness.fail("energy mutation must not run"),
		"rng": Rng.seeded("invalid"),
		"log": func(_text: String, _level: String) -> void: pass,
		"on_triggered": func(_payload: Dictionary) -> void: pass,
	}, errors)
	harness.assert_equal(errors, [])
	harness.assert_false(system.devour_skill_point(devourer, errors))
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(heroes[0]["energy"], 50)


func _test_devourer_rng_identity(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var devourer := _enemy("devourer", 1)
	var hero := {"id": 7, "side": "ally", "deployed": true, "energy": 50}
	var same_id_clone: Dictionary = hero.duplicate(true)
	var clone_rng := ClonePickRng.new()
	clone_rng.picked = same_id_clone
	var mutations := [0]
	var dispatcher: Variant = _dispatcher(content, [])
	var errors: Array[String] = []
	var system: Variant = EnemySpecials.new({
		"catalog": content["enemy_specials"],
		"dispatcher": dispatcher,
		"get_enemies": func() -> Array: return [devourer],
		"get_active_heroes": func() -> Array: return [hero],
		"get_skill_points": func() -> float: return 0.0,
		"set_skill_points": func(_value: float) -> void: mutations[0] += 1,
		"gain_hero_energy": func(_hero: Dictionary, _amount: int) -> void: mutations[0] += 1,
		"rng": clone_rng,
		"log": func(_text: String, _level: String) -> void: pass,
		"on_triggered": func(_payload: Dictionary) -> void: pass,
	}, errors)
	harness.assert_equal(errors, [])
	harness.assert_false(system.devour_skill_point(devourer, errors))
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(mutations[0], 0)
	harness.assert_equal(hero["energy"], 50)
	harness.assert_equal(same_id_clone["energy"], 50)


func _test_echo_growth(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var echo := _enemy("echo", 2)
	var enemies := [echo]
	var setup := _enemy_setup(content, enemies, [], {"value": 0.0}, Rng.seeded("echo"))
	var dispatcher: Variant = setup["dispatcher"]
	var system: Variant = setup["system"]
	dispatcher.dispatch("unitDamaged", {
		"target": echo,
		"damageContext": {"category": "direct"},
		"effectContext": {"sourceType": "basic_attack", "sourceSide": "ally"},
	})
	dispatcher.dispatch("unitDamaged", {
		"target": echo,
		"damage_context": {"category": "delayed"},
		"effect_context": {"source_type": "delayed_damage", "source_side": "ally"},
	})
	dispatcher.dispatch("unitDamaged", {
		"target": echo,
		"damage_context": {"category": "effect"},
		"effect_context": {"source_type": "relic", "source_side": "ally"},
	})
	harness.assert_equal(echo["echo_damage_bonus"], 0.01)
	harness.assert_equal(system.get_echo_damage_bonus(echo), 0.01)
	harness.assert_equal(system.get_outgoing_damage_multiplier(echo, 2.0), 2.02)


func _test_current_enemy_boundary(harness: TestHarness) -> void:
	var content: Dictionary = ContentCatalog.build()
	var current := _enemy("echo", 1)
	var stale: Dictionary = current.duplicate(true)
	var enemies := [current]
	var setup := _enemy_setup(content, enemies, [], {"value": 0.0}, Rng.seeded("boundary"))
	var dispatcher: Variant = setup["dispatcher"]
	var system: Variant = setup["system"]
	dispatcher.dispatch("unitDamaged", {
		"target": stale,
		"damage_context": {"category": "direct"},
		"effect_context": {"source_type": "basic_attack"},
	})
	harness.assert_equal(current["echo_damage_bonus"], 0.0)
	harness.assert_equal(stale["echo_damage_bonus"], 0.0)
	current["echo_damage_bonus"] = 0.5
	stale["echo_damage_bonus"] = 0.75
	harness.assert_true(system.reset_battle())
	harness.assert_equal(current["echo_damage_bonus"], 0.0)
	harness.assert_equal(stale["echo_damage_bonus"], 0.75)
	harness.assert_equal(system.get_outgoing_damage_multiplier(stale), 1.0)


func _run_devourer_seed(seed: String) -> Dictionary:
	var content: Dictionary = ContentCatalog.build()
	var devourer := _enemy("devourer", 1)
	var enemies := [devourer]
	var heroes := [
		{"id": 1, "side": "ally", "deployed": true, "energy": 50},
		{"id": 2, "side": "ally", "deployed": true, "energy": 50},
	]
	var sp := {"value": 2.0}
	var setup := _enemy_setup(content, enemies, heroes, sp, Rng.seeded(seed))
	var dispatcher: Variant = setup["dispatcher"]
	var source_effect := {
		"source_type": "basic_attack", "source_id": "normalAttack",
		"source_name": "普攻", "source_side": "enemy", "source_actor_id": devourer["id"],
	}
	dispatcher.dispatch("piece_attack_hit", {
		"actor": devourer, "round": 1, "source_effect": source_effect,
	})
	dispatcher.dispatch("pieceAttackHit", {
		"actor": devourer, "round": 1, "source_effect": source_effect,
	})
	dispatcher.dispatch("pieceAttackHit", {
		"actor": devourer, "round": 1, "source_effect": source_effect,
	})
	return {
		"sp": sp["value"],
		"energies": heroes.map(func(hero: Dictionary) -> int: return hero["energy"]),
		"events": setup["events"],
		"logs": setup["logs"],
	}


func _relic_setup(content: Dictionary, owned: Dictionary, actions: Dictionary, reports: Array = []) -> Dictionary:
	var dispatcher: Variant = _dispatcher(content, reports)
	var errors: Array[String] = []
	var system: Variant = Relics.new({
		"catalog": content["relics"],
		"dispatcher": dispatcher,
		"get_owned_relic_ids": func() -> Array: return owned["ids"],
		"actions": actions,
	}, errors)
	assert(errors.is_empty())
	assert(system.is_valid())
	return {"dispatcher": dispatcher, "system": system}


func _relic_system(content: Dictionary, owned: Dictionary, actions: Dictionary, reports: Array) -> Variant:
	return _relic_setup(content, owned, actions, reports)["system"]


func _enemy_setup(content: Dictionary, enemies: Array, heroes: Array, sp: Dictionary, rng: Variant) -> Dictionary:
	var reports: Array = []
	var events: Array = []
	var logs: Array = []
	var dispatcher: Variant = _dispatcher(content, reports)
	var errors: Array[String] = []
	var system: Variant = EnemySpecials.new({
		"catalog": content["enemy_specials"],
		"dispatcher": dispatcher,
		"get_enemies": func() -> Array: return enemies,
		"get_active_heroes": func() -> Array: return heroes,
		"get_skill_points": func() -> float: return sp["value"],
		"set_skill_points": func(value: float) -> void: sp["value"] = value,
		"gain_hero_energy": func(hero: Dictionary, amount: int) -> void:
			hero["energy"] = maxi(0, int(hero.get("energy", 0)) + amount),
		"rng": rng,
		"log": func(text: String, level: String) -> void: logs.append([text, level]),
		"on_triggered": func(payload: Dictionary) -> void: events.append(payload),
	}, errors)
	assert(errors.is_empty())
	assert(system.is_valid())
	return {"dispatcher": dispatcher, "system": system, "events": events, "logs": logs, "reports": reports}


func _dispatcher(content: Dictionary, reports: Array) -> Variant:
	var errors: Array[String] = []
	var dispatcher: Variant = Dispatcher.new({
		"event_catalog": content["events"],
		"on_error": func(message: String, metadata: Dictionary) -> void:
			reports.append({"message": message, "metadata": metadata}),
	}, errors)
	assert(errors.is_empty())
	return dispatcher


func _actions(calls: Array) -> Dictionary:
	return {
		"apply_pursuit_to_alive_allies": func(stacks: int) -> void: calls.append(["ultPursuit", stacks]),
		"get_team_average_atk": func(_side: String) -> float: return 10.0,
		"deal_relic_damage_to_all_enemies": func(raw: float, id: String, _name: String) -> void: calls.append([id, raw]),
		"get_buff_stacks": func(target: Dictionary, id: String) -> int:
			for buff in target.get("buffs", []):
				if buff.get("id") == id:
					return int(buff.get("stacks", 0))
			return 0,
		"spread_burn_on_enemy_death": func(target: Dictionary) -> void: calls.append(["emberStorm", target["id"]]),
		"trigger_strongest_ally_pursuit": func(target: Dictionary) -> void: calls.append(["executionAxe", target["id"]]),
		"apply_relic_damage": func(target: Dictionary, raw: float, id: String, _name: String) -> void: calls.append([id, target["id"], raw]),
		"heal": func(target: Dictionary, amount: float, id: String, _name: String) -> void: calls.append([id, target["id"], amount]),
		"gain_random_active_hero_energy": func(amount: int, id: String, _name: String) -> void: calls.append([id, amount]),
		"gain_skill_points": func(amount: int) -> void: calls.append(["sp", amount]),
		"gain_lowest_energy_active_hero_energy": func(amount: int) -> void: calls.append(["energy", amount]),
		"apply_burn": func(target: Dictionary, stacks: int) -> void: calls.append(["burn", target["id"], stacks]),
		"heal_alive_allies": func(ratio: float, id: String, _name: String) -> void: calls.append([id, ratio]),
	}


func _enemy(special_id: Variant, id: int) -> Dictionary:
	return {
		"id": id,
		"side": "enemy",
		"name": "enemy-%d" % id,
		"alive": true,
		"hp": 100.0,
		"max_hp": 100.0,
		"atk": 20.0,
		"special_id": special_id,
		"echo_damage_bonus": 0.0,
	}
