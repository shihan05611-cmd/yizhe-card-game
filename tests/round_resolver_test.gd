extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const RoundResolverScript = preload("res://systems/combat/round_resolver.gd")
const BattleStateScript = preload("res://core/battle_state.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const DamageScript = preload("res://core/damage.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const BurnSettlementScript = preload("res://systems/buffs/burn.gd")
const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const HookDispatcherScript = preload("res://systems/relics/hook_dispatcher.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")


class FixedRng extends RefCounted:
	var next_values: Array
	var pick_index := 0
	var invalid_pick := false
	var next_calls := 0
	var pick_calls := 0

	func _init(values: Array = []) -> void:
		next_values = values.duplicate()

	func next() -> float:
		var value := float(next_values[next_calls]) if next_calls < next_values.size() else 0.99
		next_calls += 1
		return value

	func int_range(minimum: int, _maximum: int) -> int:
		return minimum

	func pick(items: Array) -> Variant:
		pick_calls += 1
		if invalid_pick:
			return "invalid_fate"
		return null if items.is_empty() else items[mini(pick_index, items.size() - 1)]


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("one real round traces hero pieces burn and finalize in Web order", func() -> void:
		_test_end_to_end(harness)
	)
	harness.run_test("enemy heroes retain array order and expose pre or post ultimate timing", func() -> void:
		_test_enemy_hero_order(harness)
	)
	harness.run_test("an early piece outcome skips remaining pieces but still burns enemy then ally", func() -> void:
		_test_early_terminal_burn(harness)
	)
	harness.run_test("finalize recovers clamps decays stealth all-in Fate hooks and events", func() -> void:
		_test_finalize(harness)
	)
	harness.run_test("player next-round action layers wait stack consume together and preserve new layers", func() -> void:
		_test_next_round_actions(harness)
	)
	harness.run_test("settled and phase gates make round entry explicit and non-reentrant", func() -> void:
		_test_phase_gates(harness)
	)
	harness.run_test("enemy adapter and piece failures preserve phase and committed trace", func() -> void:
		_test_action_failures(harness)
	)
	harness.run_test("outcome rejection and burn runtime failure preserve sequential prefixes", func() -> void:
		_test_outcome_and_burn_failures(harness)
	)
	harness.run_test("roundEnd roundStart and Fate failures identify their commit boundary", func() -> void:
		_test_finalize_failures(harness)
	)
	harness.run_test("strict dependencies and permanent snapshots fail before first mutation", func() -> void:
		_test_preflight_failures(harness)
	)
	harness.run_test("policy and attack relic authorities must share one exact instance", func() -> void:
		_test_relic_identity_gate(harness)
	)
	harness.run_test("trace is JSON-safe and M3 session responsibilities are explicit", func() -> void:
		_test_trace_and_m3_boundary(harness)
	)
	print("B4-2R ROUND RESOLVER TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_end_to_end(harness: TestHarness) -> void:
	var fixture := _fixture()
	var result := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(result["ok"], str(result))
	var value: Dictionary = result["value"]
	harness.assert_equal(value["status"], "completed")
	harness.assert_equal(value["round_before"], 1)
	harness.assert_equal(value["round_after"], 2)
	harness.assert_equal(value["phase"], "player_input")
	var action_phases := _trace_phases(value["trace"], ["ally_piece", "enemy_piece"])
	harness.assert_equal(action_phases.size(), 12)
	harness.assert_equal(action_phases.slice(0, 4), ["ally_piece", "enemy_piece", "ally_piece", "enemy_piece"])
	var burn_sides := _trace_sides(value["trace"], "burn", "settled")
	harness.assert_equal(burn_sides, ["enemy", "ally"])
	var finalize_statuses := _trace_statuses(value["trace"], "finalize")
	harness.assert_equal(finalize_statuses, [
		"round_end", "round_resources", "buff_decay", "all_in_decay",
		"fate", "fate", "hook_reset", "round_start",
	])
	harness.assert_equal(_round_events(fixture["metrics"]["events"]), ["roundEnd", "roundStart"])


func _test_enemy_hero_order(harness: TestHarness) -> void:
	var heroes := [
		_enemy_hero(901, 100.0),
		_enemy_hero(902, 70.0),
	]
	var fixture := _fixture({"enemy_heroes": heroes, "enemy_sp": 6.0, "enemy_sp_max": 6.0})
	var result := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(result["ok"], str(result))
	var entries := _trace_entries(result["value"]["trace"], "enemy_yizhe", "cast")
	harness.assert_equal(entries.size(), 2)
	harness.assert_equal(entries.map(func(item: Dictionary) -> Variant: return item["result"]["hero_id"]), [901, 902])
	harness.assert_true(entries[0]["result"]["pre_ultimate"])
	harness.assert_false(entries[0]["result"]["post_ultimate"])
	harness.assert_false(entries[1]["result"]["pre_ultimate"])
	harness.assert_true(entries[1]["result"]["post_ultimate"])
	harness.assert_equal(entries[0]["result"]["ultimate_casts"], 1)
	harness.assert_equal(entries[1]["result"]["ultimate_casts"], 1)


func _test_early_terminal_burn(harness: TestHarness) -> void:
	var fixture := _fixture()
	for slot in range(2, 7):
		_kill(_unit(fixture["state"], "enemy", slot))
	_unit(fixture["state"], "enemy", 1)["hp"] = 1.0
	var ally := _unit(fixture["state"], "ally", 1)
	fixture["buffs"].apply_unit(ally, "burn", 1, 2)
	var hp_before: float = ally["hp"]
	var result := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_equal(result["value"]["status"], "settled")
	harness.assert_equal(result["value"]["result"], "win")
	harness.assert_equal(result["value"]["round_after"], 1)
	harness.assert_equal(result["value"]["phase"], "settled")
	harness.assert_true(ally["hp"] < hp_before, "ally burn still settles after early win")
	harness.assert_equal(_trace_sides(result["value"]["trace"], "burn", "settled"), ["enemy", "ally"])
	harness.assert_equal(_round_events(fixture["metrics"]["events"]), [])
	harness.assert_equal(_trace_entries(result["value"]["trace"], "enemy_piece", "resolved"), [])


func _test_finalize(harness: TestHarness) -> void:
	var fixture := _fixture({
		"sp": 5.5, "enemy_sp": 5.5, "fate_active": true,
		"enemy_fate_active": true, "all_in_turns": 1,
		"fate_fixed_order": "技能命运", "zero_attack": true,
		"owned_relics": ["zeroCostSpark"],
	})
	var stealth := _unit(fixture["state"], "ally", 1)
	stealth["stealth_attack_ready"] = true
	fixture["buffs"].apply_unit(stealth, "stealth", 1, 1)
	var dispatch_errors: Array[String] = []
	harness.assert_equal(fixture["hook_dispatcher"].dispatch("freeSkillCast", {
		"amount": 0,
		"source_effect": {"source_side": "ally"},
	}, dispatch_errors)["delivered"], 1)
	harness.assert_equal(fixture["hook_dispatcher"].get_trigger_count("zeroCostSpark", 0), 1)
	var result := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_equal(fixture["state"]["round"], 2)
	harness.assert_equal(fixture["state"]["sp"], 6.0)
	harness.assert_equal(fixture["state"]["enemy_sp"], 6.0)
	harness.assert_false(fixture["buffs"].has_unit(stealth, "stealth"))
	harness.assert_false(stealth["stealth_attack_ready"])
	harness.assert_equal(fixture["state"]["fate"]["all_in_turns"], 0)
	harness.assert_equal(fixture["state"]["enemy_fate"]["all_in_turns"], 0)
	harness.assert_equal(fixture["state"]["fate"]["enemy_lock"], null)
	harness.assert_equal(fixture["state"]["enemy_fate"]["ally_lock"], null)
	harness.assert_equal(fixture["state"]["fate"]["mode"], "技能命运")
	harness.assert_equal(fixture["state"]["enemy_fate"]["mode"], "棋子命运")
	harness.assert_equal(fixture["state"]["phase"], "player_input")
	harness.assert_equal(fixture["hook_dispatcher"].get_trigger_count("zeroCostSpark", 0), 0)


func _test_next_round_actions(harness: TestHarness) -> void:
	var fixture := _fixture({"zero_attack": true})
	var unit := _unit(fixture["state"], "ally", 1)
	var errors: Array[String] = []
	harness.assert_true(fixture["buffs"].apply_unit(unit, "nextRoundAction", 2, 2, errors))
	var first := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(first["ok"], str(first))
	var first_action: Dictionary = _piece_entry(first["value"]["trace"], "ally", 1)
	harness.assert_equal(first_action["result"]["strikes"], 1, "duration-2 layers do not trigger in the cast round")
	harness.assert_equal(fixture["buffs"].get_unit_state(unit, "nextRoundAction")["layer_turns"], [1, 1])

	# A new cast in round 2 stays pending while both ready layers are consumed.
	harness.assert_true(fixture["buffs"].apply_unit(unit, "nextRoundAction", 1, 2, errors))
	var second := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(second["ok"], str(second))
	var second_action: Dictionary = _piece_entry(second["value"]["trace"], "ally", 1)
	harness.assert_equal(second_action["result"]["strikes"], 3, "two ready layers grant two extra actions")
	harness.assert_true("next_round_actions_consumed:2" in second_action["result"]["steps"])
	harness.assert_equal(fixture["buffs"].get_unit_state(unit, "nextRoundAction")["layer_turns"], [1], "the newly cast layer activates one round later")

	var third := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(third["ok"], str(third))
	harness.assert_equal(_piece_entry(third["value"]["trace"], "ally", 1)["result"]["strikes"], 2)
	harness.assert_false(fixture["buffs"].has_unit(unit, "nextRoundAction"))

	var dead_fixture := _fixture({"zero_attack": true})
	var doomed := _unit(dead_fixture["state"], "ally", 1)
	harness.assert_true(dead_fixture["buffs"].apply_unit(doomed, "nextRoundAction", 1, 2, errors))
	harness.assert_true(RoundResolverScript.resolve(dead_fixture["request"], dead_fixture["ports"])["ok"])
	_kill(doomed)
	var dead_round := RoundResolverScript.resolve(dead_fixture["request"], dead_fixture["ports"])
	harness.assert_true(dead_round["ok"], str(dead_round))
	harness.assert_false(dead_fixture["buffs"].has_unit(doomed, "nextRoundAction"), "a dead unit's due layer expires without acting or reviving")


func _test_phase_gates(harness: TestHarness) -> void:
	var settled := _fixture({"game_over": true, "battle_result": "win", "phase": "settled"})
	var before := BattleStateScript.snapshot(settled["state"])
	var result := RoundResolverScript.resolve(settled["request"], settled["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["status"], "already_settled")
	harness.assert_equal(result["value"]["trace"], [])
	harness.assert_equal(settled["state"], before)

	var gated := _fixture({"phase": "enemy_yizhe"})
	before = BattleStateScript.snapshot(gated["state"])
	result = RoundResolverScript.resolve(gated["request"], gated["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "phase gate")
	harness.assert_equal(gated["state"], before)

	var completed := _fixture({"zero_attack": true})
	result = RoundResolverScript.resolve(completed["request"], completed["ports"])
	harness.assert_true(result["ok"])
	var first_round: int = completed["state"]["round"]
	result = RoundResolverScript.resolve(completed["request"], completed["ports"])
	harness.assert_true(result["ok"], "player_input explicitly starts the next round")
	harness.assert_equal(completed["state"]["round"], first_round + 1)


func _test_action_failures(harness: TestHarness) -> void:
	var enemy_fail := _fixture({
		"enemy_heroes": [_enemy_hero(901, 0.0)], "registry_fail": true,
	})
	var before_sp: float = enemy_fail["state"]["enemy_sp"]
	var result := RoundResolverScript.resolve(enemy_fail["request"], enemy_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "current_phase=enemy_yizhe")
	harness.assert_contains(result["error"], "committed_trace")
	harness.assert_true(enemy_fail["state"]["enemy_sp"] < before_sp, "adapter payment stays committed")

	var piece_fail := _fixture({"fail_event_id": "pieceAttackHit"})
	var enemy_hp: float = _unit(piece_fail["state"], "enemy", 1)["hp"]
	result = RoundResolverScript.resolve(piece_fail["request"], piece_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "current_phase=ally_piece")
	harness.assert_true(_unit(piece_fail["state"], "enemy", 1)["hp"] < enemy_hp)


func _test_outcome_and_burn_failures(harness: TestHarness) -> void:
	var outcome_fail := _fixture({"reject_outcome": true})
	for slot in range(2, 7):
		_kill(_unit(outcome_fail["state"], "enemy", slot))
	_unit(outcome_fail["state"], "enemy", 1)["hp"] = 1.0
	var result := RoundResolverScript.resolve(outcome_fail["request"], outcome_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "battle outcome failed")
	harness.assert_contains(result["error"], "current_phase=ally_piece")
	harness.assert_false(outcome_fail["state"]["game_over"])

	var burn_fail := _fixture({"zero_attack": true, "invalid_burn_at": 2})
	var enemy1 := _unit(burn_fail["state"], "enemy", 1)
	var enemy2 := _unit(burn_fail["state"], "enemy", 2)
	var ally1 := _unit(burn_fail["state"], "ally", 1)
	burn_fail["buffs"].apply_unit(enemy1, "burn", 1, 2)
	burn_fail["buffs"].apply_unit(enemy2, "burn", 1, 2)
	burn_fail["buffs"].apply_unit(ally1, "burn", 1, 2)
	var ally_hp: float = ally1["hp"]
	result = RoundResolverScript.resolve(burn_fail["request"], burn_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "current_phase=burn")
	harness.assert_contains(result["error"], "settled_prefix")
	harness.assert_true(enemy1["hp"] < enemy1["max_hp"])
	harness.assert_equal(ally1["hp"], ally_hp, "ally burn does not run after enemy burn failure")


func _test_finalize_failures(harness: TestHarness) -> void:
	var end_fail := _fixture({"zero_attack": true, "fail_event_id": "roundEnd"})
	var result := RoundResolverScript.resolve(end_fail["request"], end_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "roundEnd event failed before round increment")
	harness.assert_contains(result["error"], "current_phase=finalize")
	harness.assert_equal(end_fail["state"]["round"], 1)

	var start_fail := _fixture({"zero_attack": true, "fail_event_id": "roundStart"})
	result = RoundResolverScript.resolve(start_fail["request"], start_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "roundStart event failed after round/finalize committed")
	harness.assert_equal(start_fail["state"]["round"], 2)
	harness.assert_equal(start_fail["state"]["phase"], "finalize")

	var fate_fail := _fixture({"zero_attack": true, "fate_active": true})
	fate_fail["combat_rng"].invalid_pick = true
	result = RoundResolverScript.resolve(fate_fail["request"], fate_fail["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "ally Fate roll failed after round commit")
	harness.assert_equal(fate_fail["state"]["round"], 2)
	harness.assert_equal(fate_fail["state"]["phase"], "finalize")


func _test_preflight_failures(harness: TestHarness) -> void:
	var fixture := _fixture()
	var before := BattleStateScript.snapshot(fixture["state"])
	var malformed: Dictionary = fixture["request"].duplicate(false)
	malformed["unknown"] = true
	var result := RoundResolverScript.resolve(malformed, fixture["ports"])
	harness.assert_false(result["ok"])
	harness.assert_equal(fixture["state"], before)

	var bad_permanent: Dictionary = fixture["request"].duplicate(false)
	bad_permanent["permanent_buffs"] = [{
		"id": "missing", "target": {"type": "pieceSlot", "id": 1}, "stacks": 1,
	}]
	result = RoundResolverScript.resolve(bad_permanent, fixture["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "permanent Buff snapshot invalid")
	harness.assert_equal(fixture["state"], before)
	harness.assert_equal(fixture["combat_rng"].next_calls, 0)

	var fake_registry: Dictionary = fixture["request"].duplicate(false)
	fake_registry["registry"] = RefCounted.new()
	result = RoundResolverScript.resolve(fake_registry, fixture["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "exact EffectRegistry")
	result = RoundResolverScript.resolve(fixture["request"], RefCounted.new())
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "exact valid CombatPorts")
	harness.assert_equal(fixture["state"], before)


func _test_relic_identity_gate(harness: TestHarness) -> void:
	var fixture := _fixture({
		"mismatched_relics": true,
		"owned_relics": ["zeroCostSpark"],
	})
	var hook_errors: Array[String] = []
	harness.assert_equal(fixture["hook_dispatcher"].dispatch("freeSkillCast", {
		"amount": 0, "source_effect": {"source_side": "ally"},
	}, hook_errors)["delivered"], 1)
	harness.assert_equal(fixture["hook_dispatcher"].get_trigger_count("zeroCostSpark", 0), 1)
	var before := BattleStateScript.snapshot(fixture["state"])
	var result := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "must be the same instance")
	harness.assert_equal(result.keys().size(), 2, "preflight failure publishes no trace/value")
	harness.assert_equal(fixture["state"], before)
	harness.assert_equal(fixture["state"]["phase"], "player_input")
	harness.assert_equal(fixture["metrics"]["events"], [])
	harness.assert_equal(fixture["metrics"]["burn_settled"], [])
	harness.assert_equal(fixture["metrics"]["outcomes"], 0)
	harness.assert_equal(fixture["combat_rng"].next_calls, 0)
	harness.assert_equal(fixture["combat_rng"].pick_calls, 0)
	harness.assert_equal(fixture["hook_dispatcher"].get_trigger_count("zeroCostSpark", 0), 1)
	harness.assert_true(fixture["request_relic"].is_valid())
	harness.assert_true(fixture["policy_relic"].is_valid())
	harness.assert_false(is_same(fixture["request_relic"], fixture["policy_relic"]))


func _test_trace_and_m3_boundary(harness: TestHarness) -> void:
	var fixture := _fixture({"zero_attack": true})
	var result := RoundResolverScript.resolve(fixture["request"], fixture["ports"])
	harness.assert_true(result["ok"])
	var value: Dictionary = result["value"]
	var json_errors: Array[String] = []
	harness.assert_true(_json_safe(value["trace"], "trace", [], json_errors), str(json_errors))
	for entry: Dictionary in value["trace"]:
		harness.assert_equal(entry.keys().size(), 5)
		for key in ["phase", "side", "slot", "status", "result"]:
			harness.assert_true(entry.has(key))
	harness.assert_equal(value["m3_obligations"], [
		{"id": "discard_hand_before_resolution", "status": "battle_card_session"},
		{"id": "preserve_resolution_generated_cards", "status": "battle_card_session"},
		{"id": "draw_next_player_turn_after_finalize", "status": "battle_card_session"},
	])
	for forbidden: String in ["acted", "freeSlots", "pending_ultimate", "pendingUltimate"]:
		harness.assert_false(fixture["state"].has(forbidden))


func _fixture(options: Dictionary = {}) -> Dictionary:
	var catalog_errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(catalog_errors)
	assert(catalog_errors.is_empty())
	catalog["tuning"]["fateFixedOrder"].value = options.get("fate_fixed_order", "")
	var state := _state(options)
	if options.get("zero_attack", false):
		for unit: Dictionary in state["allies"] + state["enemies"]:
			unit["atk"] = 0.0
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": state, "catalog": catalog["buffs"],
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
	}, buff_errors)
	assert(buff_errors.is_empty())
	var combat_rng := FixedRng.new()
	var policy_rng := FixedRng.new()
	var damage_errors: Array[String] = []
	var damage := DamageScript.new({
		"random": func() -> float: return combat_rng.next(),
		"format": func(value: float) -> float: return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return unit["base_block_rate"],
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 1.0,
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"record_damage": func(_payload: Dictionary) -> void: pass,
	}, damage_errors)
	assert(damage_errors.is_empty())
	var hook_errors: Array[String] = []
	var hook_dispatcher := HookDispatcherScript.new({
		"event_catalog": catalog["events"],
		"on_error": func(_message: String, _metadata: Dictionary) -> void: pass,
	}, hook_errors)
	assert(hook_errors.is_empty())
	var owned: Array = options.get("owned_relics", []).duplicate()
	var relic_errors: Array[String] = []
	var relic_system := RelicSystemScript.new({
		"catalog": catalog["relics"], "dispatcher": hook_dispatcher,
		"get_owned_relic_ids": func() -> Array: return owned,
		"actions": {
			"gain_lowest_energy_active_hero_energy": func(_amount: int) -> void: pass,
		},
	}, relic_errors)
	assert(relic_errors.is_empty())
	var policy_relic: Variant = relic_system
	if options.get("mismatched_relics", false):
		var policy_hook_errors: Array[String] = []
		var policy_hook := HookDispatcherScript.new({
			"event_catalog": catalog["events"],
			"on_error": func(_message: String, _metadata: Dictionary) -> void: pass,
		}, policy_hook_errors)
		assert(policy_hook_errors.is_empty())
		var policy_relic_errors: Array[String] = []
		policy_relic = RelicSystemScript.new({
			"catalog": catalog["relics"], "dispatcher": policy_hook,
			"get_owned_relic_ids": func() -> Array: return [],
			"actions": {},
		}, policy_relic_errors)
		assert(policy_relic_errors.is_empty())
		assert(policy_relic.is_valid())
	var registry: Variant = _registry(catalog, bool(options.get("registry_fail", false)))
	var metrics := {"events": [], "burn_settled": [], "outcomes": 0}
	var fail_event_id: String = options.get("fail_event_id", "")
	var reject_outcome: bool = options.get("reject_outcome", false)
	var actions := {}
	for action_id: String in CombatPortsScript.REQUIRED_ACTION_IDS:
		actions[action_id] = func(action_request: Dictionary) -> Dictionary:
			if action_id == "emit_content_event":
				metrics["events"].append(action_request.duplicate(true))
				if action_request["event_id"] == fail_event_id:
					return CombatPortsScript.fail("injected %s failure" % fail_event_id)
				var dispatch_errors: Array[String] = []
				hook_dispatcher.dispatch(action_request["event_id"], action_request["payload"], dispatch_errors)
				if not dispatch_errors.is_empty():
					return CombatPortsScript.fail(dispatch_errors[0])
			if action_id == "resolve_battle_end":
				metrics["outcomes"] += 1
				if reject_outcome:
					return CombatPortsScript.fail("injected outcome rejection")
				return CombatPortsScript.ok(true)
			return CombatPortsScript.ok(null)
	var port_errors: Array[String] = []
	var ports := CombatPortsScript.new({
		"actions": actions,
		"services": {
			"combat_rng": combat_rng, "enemy_policy_rng": policy_rng,
			"damage": damage, "buffs": buffs, "tuning": catalog["tuning"],
			"catalogs": catalog, "relics": policy_relic,
		},
	}, port_errors)
	assert(port_errors.is_empty())
	var burn_counter := {"calls": 0}
	var invalid_burn_at: int = options.get("invalid_burn_at", 0)
	var burn_errors: Array[String] = []
	var burn_settlement := BurnSettlementScript.new({
		"buff_system": buffs, "damage_per_stack": 2.0,
		"apply_damage_context": func(unit: Dictionary, context: Dictionary) -> Dictionary:
			burn_counter["calls"] += 1
			if invalid_burn_at > 0 and burn_counter["calls"] == invalid_burn_at:
				return {}
			var errors: Array[String] = []
			return damage.apply(unit, context, {"damage_kind": "burn"}, errors),
		"on_settled": func(result: Dictionary) -> void:
			metrics["burn_settled"].append(result["unit"]["id"]),
	}, burn_errors)
	assert(burn_errors.is_empty())
	var request := {
		"state": state, "registry": registry, "burn_settlement": burn_settlement,
		"permanent_buffs": [], "relic_system": relic_system,
		"hook_dispatcher": hook_dispatcher,
	}
	return {
		"state": state, "catalog": catalog, "buffs": buffs,
		"combat_rng": combat_rng, "ports": ports, "request": request,
		"metrics": metrics, "hook_dispatcher": hook_dispatcher,
		"request_relic": relic_system, "policy_relic": policy_relic,
	}


func _registry(catalog: Dictionary, fail: bool) -> Variant:
	var handler := func(_context: Dictionary, _ports: Variant) -> Dictionary:
		return CombatPortsScript.fail("injected registry failure") if fail else CombatPortsScript.ok({})
	var handlers := {}
	for definition: Variant in catalog["skills"].values():
		handlers[definition.effect_id] = handler
	for group: String in ["exclusive", "ultimate"]:
		for definition: Variant in catalog["hero_abilities"][group].values():
			handlers[definition.handler_id] = handler
	var registry := EffectRegistryScript.new()
	var errors: Array[String] = []
	assert(registry.register_map(handlers, errors), str(errors))
	return registry


func _state(options: Dictionary) -> Dictionary:
	var source := {
		"round": 1, "phase": options.get("phase", "player_input"),
		"sp": options.get("sp", 4.0), "sp_max": 6.0, "base_sp_max": 6.0,
		"enemy_sp": options.get("enemy_sp", 4.0),
		"enemy_sp_max": options.get("enemy_sp_max", 6.0),
		"allies": _team("ally"), "enemies": _team("enemy"),
		"player_heroes": [], "enemy_heroes": options.get("enemy_heroes", []).duplicate(true),
		"side_buffs": {"ally": [], "enemy": []},
		"fate": {
			"active": options.get("fate_active", false), "mode": null,
			"cast_used": false, "chaos_used": false,
			"enemy_lock": "noSkill" if options.get("all_in_turns", 0) > 0 else null,
			"all_in_turns": options.get("all_in_turns", 0), "roll_index": 0,
			"skill_sp_gain_this_round": 2,
		},
		"enemy_fate": {
			"active": options.get("enemy_fate_active", false), "mode": null,
			"cast_used": false, "chaos_used": false,
			"ally_lock": "noSkill" if options.get("all_in_turns", 0) > 0 else null,
			"all_in_turns": options.get("all_in_turns", 0),
			"skill_sp_gain_this_round": 2,
		},
		"battle_growth_flags": {"flame_investment_used": false},
		"burn_ex_cast_count": 0, "enemy_burn_ex_cast_count": 0,
		"counter_threshold": 4, "marshal_target_id": 1,
		"ally_puppet_martyr_active": false,
		"game_over": options.get("game_over", false),
		"battle_result": options.get("battle_result", null),
	}
	var errors: Array[String] = []
	var state := BattleStateScript.create(source, errors)
	assert(errors.is_empty(), str(errors))
	return state


func _team(side: String) -> Array:
	var result: Array = []
	for slot in range(1, 7):
		result.append({
			"id": slot, "slot": slot, "side": side,
			"class_id": "default", "class_name": "棋子",
			"hp": 100.0, "max_hp": 100.0, "atk": 1.0, "crit_rate": 0.0,
			"alive": true, "general": false, "base_block_rate": 0.0,
			"extra_action_charges": 0, "buffs": [], "is_puppet": false,
			"fixed_max_hp": null, "puppet_martyr": false, "disarm_turns": 0,
			"stealth_attack_ready": false, "special_id": null,
			"echo_damage_bonus": 0.0, "hp_threshold_crossed": false,
		})
	return result


func _enemy_hero(id: int, energy: float) -> Dictionary:
	return {
		"id": id, "name": "敌方弈者%d" % id, "ex_skill": "burnEnchant",
		"skills": [], "skill_pool": ["basicDamage"], "energy": energy,
		"max_energy": 100.0, "base_crit_rate": 0.0, "fist_momentum": 0,
	}


func _unit(state: Dictionary, side: String, slot: int) -> Dictionary:
	for unit: Dictionary in state["allies" if side == "ally" else "enemies"]:
		if unit["slot"] == slot:
			return unit
	assert(false)
	return {}


func _kill(unit: Dictionary) -> void:
	unit["hp"] = 0.0
	unit["alive"] = false


func _trace_entries(trace: Array, phase: String, status: String) -> Array:
	return trace.filter(func(item: Dictionary) -> bool:
		return item["phase"] == phase and item["status"] == status
	)


func _piece_entry(trace: Array, side: String, slot: int) -> Dictionary:
	var phase := "%s_piece" % side
	for item: Dictionary in trace:
		if item["phase"] == phase and item["side"] == side and item["slot"] == slot and item["status"] == "completed":
			return item
	return {}


func _trace_phases(trace: Array, phases: Array) -> Array:
	var result: Array = []
	for item: Dictionary in trace:
		if item["phase"] in phases and item["status"] != "outcome":
			result.append(item["phase"])
	return result


func _trace_sides(trace: Array, phase: String, status: String) -> Array:
	return _trace_entries(trace, phase, status).map(func(item: Dictionary) -> Variant: return item["side"])


func _trace_statuses(trace: Array, phase: String) -> Array:
	var result: Array = []
	for item: Dictionary in trace:
		if item["phase"] == phase:
			result.append(item["status"])
	return result


func _round_events(events: Array) -> Array:
	var result: Array = []
	for event: Dictionary in events:
		if event["event_id"] in ["roundEnd", "roundStart"]:
			result.append(event["event_id"])
	return result


func _json_safe(value: Variant, path: String, seen: Array, errors: Array[String]) -> bool:
	if value == null or typeof(value) in [TYPE_STRING, TYPE_BOOL, TYPE_INT]:
		return true
	if typeof(value) == TYPE_FLOAT:
		if is_finite(value):
			return true
		errors.append("%s non-finite" % path)
		return false
	if typeof(value) not in [TYPE_ARRAY, TYPE_DICTIONARY]:
		errors.append("%s non-JSON" % path)
		return false
	for previous: Variant in seen:
		if is_same(previous, value):
			errors.append("%s shared" % path)
			return false
	seen.append(value)
	if typeof(value) == TYPE_ARRAY:
		for index in value.size():
			if not _json_safe(value[index], "%s[%d]" % [path, index], seen, errors):
				return false
		return true
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not _json_safe(value[key], "%s.%s" % [path, str(key)], seen, errors):
			return false
	return true
