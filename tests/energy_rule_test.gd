extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const Fixture = preload("res://tests/support/m3_card_fixture.gd")
const CardDefinitionScript = preload("res://data/definitions/card_definition.gd")
const ContextsScript = preload("res://core/contexts.gd")
const PieceAttackScript = preload("res://systems/combat/piece_attack.gd")
const PieceReactionsScript = preload("res://systems/combat/piece_reactions.gd")
const Request = preload("res://systems/cards/card_play_request.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("every routed player energy change checks threshold immediately", func() -> void:
		_test_threshold_generation(harness)
	)
	harness.run_test("full hand sends generated ultimate to draw top without a draw attempt", func() -> void:
		_test_full_hand_destination(harness)
	)
	harness.run_test("one oversized energy event generates only one ultimate and clears energy", func() -> void:
		_test_single_trigger_per_event(harness)
	)
	harness.run_test("banner action energy uses the installed ultimate threshold coordinator", func() -> void:
		_test_banner_energy_route(harness)
	)
	harness.run_test("knight super counter energy uses the installed ultimate threshold coordinator", func() -> void:
		_test_counter_energy_route(harness)
	)
	harness.run_test("relic-granted player energy also uses the installed threshold coordinator", func() -> void:
		_test_relic_energy_route(harness)
	)
	print("M3-2 ENERGY RULE TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_threshold_generation(harness: TestHarness) -> void:
	var fixture := Fixture.create()
	var hero := Fixture.hero(fixture["state"], 4)
	hero["energy"] = 96.0
	var result: Dictionary = fixture["runtime"].apply_player_energy({
		"hero_id": 4, "amount": 4.0, "source": {"kind": "counter_aura"},
	})
	harness.assert_true(result["ok"], str(result))
	harness.assert_true(result["value"]["threshold_crossed"])
	harness.assert_equal(hero["energy"], 0.0)
	harness.assert_equal(result["value"]["generated_card"]["card_id"], "ultimate:counterAura")
	harness.assert_equal(result["value"]["generated_card"]["destination"], CardDefinitionScript.PILE_HAND)
	harness.assert_equal(fixture["hand"].total_instance_count(), 1)
	harness.assert_false(fixture["cards"].has("exclusive:counterAura"))
	harness.assert_true(fixture["cards"].has("ultimate:counterAura"))


func _test_full_hand_destination(harness: TestHarness) -> void:
	var fixture := Fixture.create()
	var card_ids: Array = []
	for _index in range(7):
		card_ids.append("free:smallHeal")
	Fixture.put_cards_in_hand(fixture, card_ids)
	var hand_before: Array[String] = fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND)
	var draw_before: Array[String] = fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_DRAW)
	var trace_before: Array = fixture["hand"].snapshot()["trace"]
	var hero := Fixture.hero(fixture["state"], 9)
	hero["energy"] = 95.0
	var result: Dictionary = fixture["runtime"].apply_player_energy({
		"hero_id": 9, "amount": 5.0, "source": {"kind": "card_play"},
	})
	harness.assert_true(result["ok"], str(result))
	harness.assert_equal(hero["energy"], 0.0)
	harness.assert_equal(fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND), hand_before)
	var draw_after: Array[String] = fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_DRAW)
	harness.assert_equal(draw_after.size(), draw_before.size() + 1)
	harness.assert_equal(draw_after[draw_after.size() - 1], result["value"]["generated_card"]["instance_id"])
	harness.assert_equal(result["value"]["generated_card"]["destination"], CardDefinitionScript.PILE_DRAW)
	var added_trace: Array = fixture["hand"].snapshot()["trace"].slice(trace_before.size())
	harness.assert_equal(added_trace.size(), 1)
	harness.assert_equal(added_trace[0]["event"], "card_created")


func _test_single_trigger_per_event(harness: TestHarness) -> void:
	var fixture := Fixture.create()
	var hero := Fixture.hero(fixture["state"], 2)
	hero["energy"] = 110.0
	var result: Dictionary = fixture["runtime"].apply_player_energy({
		"hero_id": 2, "amount": 250.0, "source": {"kind": "test_oversized"},
	})
	harness.assert_true(result["ok"], str(result))
	harness.assert_true(result["value"]["threshold_crossed"])
	harness.assert_equal(hero["energy"], 0.0)
	harness.assert_equal(fixture["hand"].total_instance_count(), 1)
	harness.assert_equal(
		fixture["hand"].get_instance_snapshot(result["value"]["generated_card"]["instance_id"]).definition.id,
		"ultimate:fate",
	)


func _test_banner_energy_route(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 5.0})
	fixture["state"]["phase"] = "piece_attack"
	fixture["state"]["allies"][0]["class_id"] = "banner"
	Fixture.hero(fixture["state"], 4)["energy"] = 96.0
	var request := {
		"state": fixture["state"],
		"attacker_side": "ally", "attacker_id": 1, "attacker_slot": 1,
		"forced_target_side": null, "forced_target_id": null, "forced_target_slot": null,
		"attack_name": "普攻", "damage_multiplier": 1.0,
		"trigger_extra_action": false, "trigger_pursuit": false,
		"trigger_banner_action": true, "damage_kind_override": "",
		"source_effect": _effect("basic_attack", "normalAttack", "ally", 1, false),
		"permanent_buffs": [],
		"relic_system": fixture["runtime"].component("relic_system"),
	}
	var result: Dictionary = PieceAttackScript.execute(request, fixture["runtime"].component("ports"))
	harness.assert_true(result["ok"], str(result))
	harness.assert_true("banner_energy" in result["value"]["steps"])
	harness.assert_equal(Fixture.hero(fixture["state"], 4)["energy"], 0.0)
	harness.assert_equal(fixture["hand"].total_instance_count(), 1)
	harness.assert_equal(
		fixture["hand"].get_instance_snapshot(
			fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND)[0]
		).definition.id,
		"ultimate:counterAura",
	)


func _test_counter_energy_route(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 5.0})
	fixture["state"]["phase"] = "piece_attack"
	var knight := Fixture.hero(fixture["state"], 4)
	knight["energy"] = 95.0
	var attacker: Dictionary = fixture["state"]["enemies"][0]
	var defender: Dictionary = fixture["state"]["allies"][0]
	var hit := _primary_hit(attacker, defender, true)
	var result: Dictionary = PieceReactionsScript.resolve({
		"state": fixture["state"],
		"attacker_side": "enemy", "attacker_id": attacker["id"],
		"defender_side": "ally", "defender_id": defender["id"],
		"primary_hit": hit, "defender_alive_after_primary_hit": true,
		"permanent_buffs": [],
	}, fixture["runtime"].component("ports"))
	harness.assert_true(result["ok"], str(result))
	harness.assert_equal(result["value"]["counter_kind"], "super")
	harness.assert_true("counter_aura_energy" in result["value"]["steps"])
	harness.assert_equal(fixture["state"]["sp"], 4.0)
	harness.assert_equal(knight["energy"], 0.0)
	harness.assert_equal(fixture["hand"].total_instance_count(), 1)
	harness.assert_equal(
		fixture["hand"].get_instance_snapshot(
			fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND)[0]
		).definition.id,
		"ultimate:counterAura",
	)


func _test_relic_energy_route(harness: TestHarness) -> void:
	var fixture := Fixture.create({
		"sp": 5.0,
		"round": 2,
		"owned_relic_ids": ["trueNameUnseal", "zeroCostSpark"],
	})
	Fixture.hero(fixture["state"], 2)["energy"] = 92.0
	Fixture.hero(fixture["state"], 3)["energy"] = 91.0
	Fixture.hero(fixture["state"], 4)["energy"] = 92.0
	Fixture.hero(fixture["state"], 9)["energy"] = 92.0
	var ids := Fixture.put_cards_in_hand(fixture, ["free:pieceDamageUp"])
	var result: Variant = fixture["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_true(result.ok, result.message)
	harness.assert_equal(result.details["actual_cost"], 0)
	harness.assert_equal(Fixture.hero(fixture["state"], 3)["energy"], 5.0)
	harness.assert_equal(Fixture.hero(fixture["state"], 2)["energy"], 97.0)
	var hand_ids: Array[String] = fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND)
	harness.assert_equal(hand_ids.size(), 1)
	harness.assert_equal(fixture["hand"].get_instance_snapshot(hand_ids[0]).definition.id, "ultimate:ascend")


func _primary_hit(attacker: Dictionary, defender: Dictionary, blocked: bool) -> Dictionary:
	var effect := _effect("basic_attack", "normalAttack", attacker["side"], attacker["id"], false)
	var errors: Array[String] = []
	var context := ContextsScript.create_damage_context({
		"target_id": defender["id"], "raw_amount": 4.0, "category": "direct",
		"effect": effect, "dealer_type": "piece", "dealer_name": "普攻",
		"dealer_id": attacker["id"], "attacker_unit_id": attacker["id"],
		"can_crit": true, "crit_rate": 0.0,
		"guaranteed_crit": false, "can_block": true,
	}, errors)
	assert(errors.is_empty(), str(errors))
	return {
		"dealt": 4.0, "blocked": blocked, "died": false, "crit": false,
		"damage_context": context, "death_context": null,
	}


func _effect(
	type_id: String,
	source_id: String,
	side: String,
	actor_id: Variant,
	counts_skill: bool,
) -> Dictionary:
	var errors: Array[String] = []
	var effect := ContextsScript.create_effect_context({
		"source_type": type_id, "source_id": source_id, "source_name": source_id,
		"source_side": side, "source_actor_id": actor_id,
		"counts_as_skill_cast": counts_skill,
		"spent_skill_points": false, "free_cast": false,
		"counts_as_basic_attack": type_id == "basic_attack",
		"counts_as_attack": true, "triggers_enemy_kill_effects": true,
	}, errors)
	assert(errors.is_empty(), str(errors))
	return effect
