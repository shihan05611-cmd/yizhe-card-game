extends RefCounted

const DomainScript = preload("res://systems/roguelike/dormant_shentong_domain.gd")
const PortScript = preload("res://systems/roguelike/dormant_shentong_battle_port.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const RngScript = preload("res://core/rng.gd")

var _catalogs: Dictionary = {}


class FakeBattle:
	extends RefCounted

	var state: Dictionary
	var damage_multiplier_probe: Callable


	func _init(initial_state: Dictionary) -> void:
		state = initial_state


	func snapshot() -> Dictionary:
		return state.duplicate(true)


	func restore(value: Dictionary) -> bool:
		state.clear()
		state.merge(value.duplicate(true), true)
		return true


	func view() -> Dictionary:
		return state.duplicate(true)


	func action(request: Dictionary, action_id: String) -> Dictionary:
		state["action_log"].append(action_id)
		if state["fail_action"] == action_id:
			return {"ok": false, "error": "forced failure: %s" % action_id}
		match action_id:
			"consume_player_turn":
				state["player_turn_consumed"] = true
			"heal_alive_allies":
				for unit: Dictionary in state["allies"]:
					if unit["alive"]:
						unit["hp"] = minf(
							float(unit["max_hp"]),
							float(unit["hp"]) + float(unit["max_hp"]) * float(request["ratio"]),
						)
			"extend_enemy_burn":
				for enemy: Dictionary in state["enemies"]:
					enemy["burn_turns"] += int(request["turns"])
			"gain_hero_energy":
				if not _gain_hero_energy(int(request["hero_id"]), float(request["amount"])):
					return {"ok": false, "error": "unknown hero"}
			"gain_skill_points":
				state["skill_points"] += int(request["amount"])
			"mark_player_action":
				state["player_action_taken"] = true
			"cast_exclusive_free":
				var observed := float(request["damage_multiplier"])
				if damage_multiplier_probe.is_valid():
					observed = damage_multiplier_probe.call({
						"source_side": "ally",
						"source_type": "exclusiveSkill",
						"target_side": "enemy",
						"round": state["round"],
					})
				state["exclusive_casts"].append({
					"hero_id": request["hero_id"],
					"requested_multiplier": request["damage_multiplier"],
					"observed_multiplier": observed,
				})
			"sacrifice_unit":
				if not _sacrifice(int(request["unit_id"]), request["death_context"]):
					return {"ok": false, "error": "unknown living sacrifice"}
			"detect_battle_result":
				return {"ok": true, "value": state["detected_result"]}
			"settle_battle":
				state["settled_results"].append(request["result"])
				state["game_over"] = true
			_:
				return {"ok": false, "error": "unknown fake action"}
		return {"ok": true, "value": null}


	func _gain_hero_energy(hero_id: int, amount: float) -> bool:
		for hero: Dictionary in state["heroes"]:
			if hero["id"] == hero_id:
				hero["energy"] += amount
				return true
		return false


	func _sacrifice(unit_id: int, death_context: Dictionary) -> bool:
		for unit: Dictionary in state["allies"]:
			if unit["id"] == unit_id and unit["alive"]:
				unit["alive"] = false
				unit["hp"] = 0.0
				state["sacrifices"].append({
					"unit_id": unit_id,
					"death_context": death_context.duplicate(true),
				})
				return true
		return false


func run(harness: TestHarness) -> void:
	harness.run_test("M5 dormant shentong definitions expose exact independent budgets", func() -> void:
		_test_definitions(harness)
	)
	harness.run_test("M5 dormant charge enforces first action and evolved timing", func() -> void:
		_test_charge(harness)
	)
	harness.run_test("M5 dormant assault uses deployment order and temporary 3x or 5x", func() -> void:
		_test_assault(harness)
	)
	harness.run_test("M5 dormant sacrifice uses stable target puppet reward and death context", func() -> void:
		_test_sacrifice(harness)
	)
	harness.run_test("M5 dormant shentong failures roll back world uses settlement and RNG", func() -> void:
		_test_atomic_rollback(harness)
	)


func _test_definitions(harness: TestHarness) -> void:
	for pair in [["charge", 1], ["assault", 1], ["sacrifice", 2]]:
		var fixture := _fixture(pair[0], [], "m5-06-definition-%s" % pair[0], harness)
		var snapshot: Dictionary = fixture["domain"].snapshot()
		harness.assert_equal(snapshot["id"], pair[0])
		harness.assert_equal(snapshot["handler_id"], "shentong.%s" % pair[0])
		harness.assert_equal(snapshot["uses_max"], pair[1])
		harness.assert_equal(snapshot["uses_left"], pair[1])
	var base: Dictionary = _fixture(
		"assault", [], "m5-06-base-query", harness,
	)["domain"].evolution_effects()
	harness.assert_equal(base, {
		"assault_damage_multiplier": 3.0,
		"charge_energy_gain": 0.0,
	})
	var evolved: Dictionary = _fixture(
		"charge",
		["shentongAssaultBurst", "shentongChargeOverload"],
		"m5-06-evolved-query",
		harness,
	)["domain"].evolution_effects()
	harness.assert_equal(evolved, {
		"assault_damage_multiplier": 5.0,
		"charge_energy_gain": 30.0,
	})


func _test_charge(harness: TestHarness) -> void:
	var blocked := _fixture("charge", [], "m5-06-charge-blocked", harness)
	blocked["state"]["player_action_taken"] = true
	var before: Dictionary = blocked["state"].duplicate(true)
	var errors: Array[String] = []
	harness.assert_false(blocked["domain"].can_use(errors))
	harness.assert_false(blocked["domain"].use(errors))
	harness.assert_equal(blocked["state"], before)

	var evolved := _fixture(
		"charge", ["shentongChargeOverload"], "m5-06-charge-evolved", harness,
	)
	var state: Dictionary = evolved["state"]
	harness.assert_true(evolved["domain"].use(errors), "; ".join(errors))
	harness.assert_true(state["player_turn_consumed"])
	harness.assert_true(state["player_action_taken"])
	harness.assert_equal(state["allies"][0]["hp"], 60.0)
	harness.assert_equal(state["allies"][1]["hp"], 65.0)
	harness.assert_equal(state["allies"][2]["hp"], 100.0)
	harness.assert_equal(state["enemies"][0]["burn_turns"], 3)
	harness.assert_equal(state["enemies"][1]["burn_turns"], 1)
	for hero: Dictionary in state["heroes"]:
		harness.assert_equal(hero["energy"], 30.0 if hero["deployed"] else 0.0)
	var domain: Variant = evolved["domain"]
	harness.assert_equal(domain.snapshot()["uses_left"], 0)
	harness.assert_equal(domain.get_damage_multiplier(_damage_query("enemy", "piece", "ally", 1)), 0.8)
	harness.assert_equal(domain.get_damage_multiplier(_damage_query("ally", "piece", "enemy", 1)), 1.0)
	harness.assert_equal(domain.get_damage_multiplier(_damage_query("ally", "piece", "enemy", 2)), 2.0)
	harness.assert_equal(domain.get_damage_multiplier(_damage_query("ally", "piece", "enemy", 3)), 1.0)
	var exhausted_before: Dictionary = state.duplicate(true)
	harness.assert_false(domain.use(errors))
	harness.assert_equal(state, exhausted_before)


func _test_assault(harness: TestHarness) -> void:
	var base := _fixture("assault", [], "m5-06-assault-base", harness)
	base["state"]["selected_hero_id"] = 2
	base["state"]["heroes"][0]["can_cast_exclusive"] = false
	var errors: Array[String] = []
	harness.assert_true(base["domain"].use(errors), "; ".join(errors))
	harness.assert_equal(base["state"]["exclusive_casts"], [{
		"hero_id": 1,
		"requested_multiplier": 3.0,
		"observed_multiplier": 3.0,
	}])
	harness.assert_equal(
		base["domain"].get_damage_multiplier(_damage_query("ally", "exclusiveSkill", "enemy", 1)),
		1.0,
	)

	var evolved := _fixture(
		"assault", ["shentongAssaultBurst"], "m5-06-assault-evolved", harness,
	)
	evolved["state"]["selected_hero_id"] = 2
	harness.assert_true(evolved["domain"].use(errors), "; ".join(errors))
	harness.assert_equal(evolved["state"]["exclusive_casts"], [{
		"hero_id": 2,
		"requested_multiplier": 5.0,
		"observed_multiplier": 5.0,
	}])
	harness.assert_equal(evolved["domain"].snapshot()["uses_left"], 0)


func _test_sacrifice(harness: TestHarness) -> void:
	var normal := _fixture("sacrifice", [], "m5-06-sacrifice-normal", harness)
	var errors: Array[String] = []
	harness.assert_true(normal["domain"].use(errors), "; ".join(errors))
	harness.assert_equal(normal["state"]["sacrifices"].size(), 1)
	harness.assert_equal(normal["state"]["sacrifices"][0]["unit_id"], 10)
	harness.assert_equal(normal["state"]["skill_points"], 2)
	harness.assert_equal(_total_energy(normal["state"]), 30.0)
	var context: Dictionary = normal["state"]["sacrifices"][0]["death_context"]
	harness.assert_equal(context["source_kind"], "sacrifice")
	harness.assert_equal(context["source_side"], "ally")
	harness.assert_false(context["triggers_enemy_kill_effects"])
	harness.assert_equal(context["effect"]["source_type"], "sacrifice")
	harness.assert_equal(context["effect"]["source_name"], "神通【献祭】")

	var puppet := _fixture("sacrifice", [], "m5-06-sacrifice-puppet", harness)
	puppet["state"]["allies"][1]["hp"] = 5.0
	harness.assert_true(puppet["domain"].use(errors), "; ".join(errors))
	harness.assert_equal(puppet["state"]["sacrifices"][0]["unit_id"], 11)
	harness.assert_equal(puppet["state"]["skill_points"], 1)
	harness.assert_equal(_total_energy(puppet["state"]), 15.0)

	var budget := _fixture("sacrifice", [], "m5-06-sacrifice-budget", harness)
	harness.assert_true(budget["domain"].use(errors), "; ".join(errors))
	budget["state"]["player_action_taken"] = false
	harness.assert_true(budget["domain"].use(errors), "; ".join(errors))
	budget["state"]["player_action_taken"] = false
	var exhausted_before: Dictionary = budget["state"].duplicate(true)
	harness.assert_false(budget["domain"].use(errors))
	harness.assert_equal(budget["state"], exhausted_before)
	harness.assert_equal(budget["domain"].snapshot()["uses_left"], 0)


func _test_atomic_rollback(harness: TestHarness) -> void:
	var random_failure := _fixture("sacrifice", [], "m5-06-rng-rollback", harness)
	random_failure["state"]["fail_action"] = "gain_hero_energy"
	var world_before: Dictionary = random_failure["state"].duplicate(true)
	var domain_before: Dictionary = random_failure["domain"].snapshot()
	var raw_before: int = random_failure["raw"].state_snapshot()
	var errors: Array[String] = []
	harness.assert_false(random_failure["domain"].use(errors))
	harness.assert_contains("; ".join(errors), "forced failure: gain_hero_energy")
	harness.assert_equal(random_failure["state"], world_before)
	harness.assert_equal(random_failure["domain"].snapshot(), domain_before)
	harness.assert_false(random_failure["raw"].state_snapshot() == raw_before)
	harness.assert_equal(random_failure["random"].replay_count(), 1)
	var raw_after_failure: int = random_failure["raw"].state_snapshot()
	random_failure["state"]["fail_action"] = ""
	harness.assert_true(random_failure["domain"].use(errors), "; ".join(errors))
	harness.assert_equal(random_failure["raw"].state_snapshot(), raw_after_failure)
	harness.assert_equal(random_failure["random"].replay_count(), 0)

	var settlement_failure := _fixture("charge", [], "m5-06-settlement-rollback", harness)
	settlement_failure["state"]["detected_result"] = "win"
	settlement_failure["state"]["fail_action"] = "settle_battle"
	world_before = settlement_failure["state"].duplicate(true)
	domain_before = settlement_failure["domain"].snapshot()
	harness.assert_false(settlement_failure["domain"].use(errors))
	harness.assert_contains("; ".join(errors), "forced failure: settle_battle")
	harness.assert_equal(settlement_failure["state"], world_before)
	harness.assert_equal(settlement_failure["domain"].snapshot(), domain_before)


func _fixture(
	shentong_id: String,
	relic_ids: Array,
	seed: String,
	harness: TestHarness,
) -> Dictionary:
	var errors: Array[String] = []
	if _catalogs.is_empty():
		_catalogs = ContentCatalogScript.build(errors)
		harness.assert_equal(errors, [])
	var state := _initial_state()
	var fake := FakeBattle.new(state)
	var actions := {}
	for action_id: String in PortScript.ACTION_IDS:
		actions[action_id] = Callable(fake, "action").bind(action_id)
	var port := PortScript.new({
		"snapshot": Callable(fake, "snapshot"),
		"restore": Callable(fake, "restore"),
		"view": Callable(fake, "view"),
		"actions": actions,
	}, errors)
	harness.assert_equal(errors, [])
	var raw := RngScript.seeded(seed)
	var random := TransactionalRandomScript.new(raw, errors)
	harness.assert_equal(errors, [])
	var domain: Variant = DomainScript.new({
		"shentong_definition": _catalogs["roguelike_content"]["shentongs"][shentong_id],
		"owned_relic_ids": relic_ids,
		"battle_port": port,
		"random": random,
	}, errors)
	harness.assert_equal(errors, [])
	fake.damage_multiplier_probe = Callable(domain, "get_damage_multiplier")
	return {
		"state": state,
		"fake": fake,
		"port": port,
		"raw": raw,
		"random": random,
		"domain": domain,
	}


func _initial_state() -> Dictionary:
	return {
		"round": 1,
		"game_over": false,
		"player_action_taken": false,
		"selected_hero_id": 1,
		"heroes": [
			{
				"id": 2, "deployed": true, "deployment_slot": 2,
				"can_cast_exclusive": true, "energy": 0.0,
			},
			{
				"id": 1, "deployed": true, "deployment_slot": 1,
				"can_cast_exclusive": true, "energy": 0.0,
			},
			{
				"id": 3, "deployed": false, "deployment_slot": 3,
				"can_cast_exclusive": true, "energy": 0.0,
			},
		],
		"allies": [
			{"id": 10, "alive": true, "is_puppet": false, "hp": 50.0, "max_hp": 100.0},
			{"id": 11, "alive": true, "is_puppet": true, "hp": 55.0, "max_hp": 100.0},
			{"id": 12, "alive": true, "is_puppet": false, "hp": 95.0, "max_hp": 100.0},
		],
		"enemies": [
			{"id": 20, "burn_turns": 2},
			{"id": 21, "burn_turns": 0},
		],
		"player_turn_consumed": false,
		"skill_points": 0,
		"exclusive_casts": [],
		"sacrifices": [],
		"detected_result": null,
		"settled_results": [],
		"fail_action": "",
		"action_log": [],
	}


func _total_energy(state: Dictionary) -> float:
	var total := 0.0
	for hero: Dictionary in state["heroes"]:
		total += float(hero["energy"])
	return total


func _damage_query(
	source_side: String,
	source_type: String,
	target_side: String,
	round_number: int,
) -> Dictionary:
	return {
		"source_side": source_side,
		"source_type": source_type,
		"target_side": target_side,
		"round": round_number,
	}
