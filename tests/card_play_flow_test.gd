extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const Fixture = preload("res://tests/support/m3_card_fixture.gd")
const Request = preload("res://systems/cards/card_play_request.gd")
const CardDefinitionScript = preload("res://data/definitions/card_definition.gd")
const Result = preload("res://core/card_runtime_result.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("free cards use one real handler and actual-cost team energy", func() -> void:
		_test_free_card_actual_costs(harness)
	)
	harness.run_test("exclusive owner is derived and shadow can replay without quota", func() -> void:
		_test_owner_shadow_and_no_quota(harness)
	)
	harness.run_test("SP validator owner and forged basicDamage reject with zero changes", func() -> void:
		_test_preflight_failures(harness)
	)
	harness.run_test("committed effect failure is fatal and halts the card queue", func() -> void:
		_test_committed_failure(harness)
	)
	harness.run_test("one-battle success limit records only after successful settlement", func() -> void:
		_test_success_limit(harness)
	)
	print("M3-2 CARD PLAY FLOW TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_free_card_actual_costs(harness: TestHarness) -> void:
	var original := Fixture.create({"sp": 6.0})
	var ids := Fixture.put_cards_in_hand(original, ["free:pieceDamageUp"])
	var result: Variant = original["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_true(result.ok, result.message)
	harness.assert_equal(result.details["base_cost"], 1)
	harness.assert_equal(result.details["effective_cost"], 1)
	harness.assert_equal(result.details["actual_cost"], 1)
	harness.assert_equal(result.details["effect_call_count"], 1)
	harness.assert_equal(original["state"]["sp"], 5.0)
	harness.assert_equal(result.details["destination"], CardDefinitionScript.PILE_DISCARD)
	harness.assert_equal(original["metrics"]["content_events"].size(), 1)
	harness.assert_equal(original["metrics"]["content_events"][0]["event_id"], "freeSkillCast")
	harness.assert_equal(original["metrics"]["content_events"][0]["payload"]["amount"], 1)
	_assert_deployed_energies(harness, original["state"], [10.0, 10.0, 10.0, 10.0, 0.0])
	# The real M2 handler applied one layer, proving the bridge did not calculate
	# or execute the effect a second time.
	harness.assert_equal(original["runtime"].component("buffs").get_side_stacks("ally", "pieceDamageUp"), 1)

	var reduced := Fixture.create({"sp": 6.0})
	ids = Fixture.put_cards_in_hand(reduced, ["free:executeStrike"])
	var changed: Variant = reduced["hand"].set_card_cost_modifiers(ids[0], {
		"until_played": -1, "until_turn": 0, "until_combat": 0,
	})
	harness.assert_true(changed.ok, changed.message)
	result = reduced["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_true(result.ok, result.message)
	harness.assert_equal(result.details["base_cost"], 2)
	harness.assert_equal(result.details["effective_cost"], 1)
	harness.assert_equal(result.details["actual_cost"], 1)
	harness.assert_equal(reduced["state"]["sp"], 5.0)
	_assert_deployed_energies(harness, reduced["state"], [10.0, 10.0, 10.0, 10.0, 0.0])

	var free := Fixture.create({
		"sp": 6.0, "round": 2, "owned_relic_ids": ["trueNameUnseal"],
	})
	ids = Fixture.put_cards_in_hand(free, ["free:pieceDamageUp"])
	result = free["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_true(result.ok, result.message)
	harness.assert_equal(result.details["effective_cost"], 1)
	harness.assert_equal(result.details["actual_cost"], 0)
	harness.assert_equal(free["state"]["sp"], 6.0)
	_assert_deployed_energies(harness, free["state"], [5.0, 5.0, 5.0, 5.0, 0.0])


func _test_owner_shadow_and_no_quota(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 8.0})
	var ids := Fixture.put_cards_in_hand(fixture, ["exclusive:shadow"])
	var before_state: Dictionary = fixture["state"].duplicate(true)
	var before_hand: Dictionary = fixture["hand"].snapshot()
	var conflict: Variant = fixture["runtime"].play_player_card(
		Request.new(ids[0], "exclusive:shadow", "shadow", 2)
	)
	harness.assert_false(conflict.ok)
	harness.assert_equal(conflict.code, Result.VALIDATOR_REJECTED)
	harness.assert_contains(conflict.message, "conflicts")
	harness.assert_equal(fixture["state"], before_state)
	harness.assert_equal(fixture["hand"].snapshot(), before_hand)

	var first: Variant = fixture["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_true(first.ok, first.message)
	harness.assert_equal(first.details["destination"], CardDefinitionScript.PILE_HAND)
	harness.assert_equal(first.details["actual_cost"], 1)
	harness.assert_equal(Fixture.hero(fixture["state"], 9)["energy"], 20.0)
	harness.assert_equal(Fixture.hero(fixture["state"], 2)["energy"], 0.0)
	harness.assert_equal(first.details["event"]["owner_hero_id"], 9)
	harness.assert_equal(first.details["event"]["source_effect"]["source_actor_id"], 9)
	var second: Variant = fixture["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_true(second.ok, second.message)
	harness.assert_equal(fixture["hand"].successful_play_count(ids[0]), 2)
	harness.assert_equal(fixture["state"]["sp"], 6.0)
	harness.assert_equal(Fixture.hero(fixture["state"], 9)["energy"], 40.0)
	harness.assert_true(ids[0] in fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND))
	var other_owner: Variant = fixture["hand"].create_card(
		fixture["cards"]["exclusive:ascend"], CardDefinitionScript.PILE_HAND
	)
	harness.assert_true(other_owner.ok, other_owner.message)
	var third: Variant = fixture["runtime"].play_player_card(
		Request.new(other_owner.details["instance_id"])
	)
	harness.assert_true(third.ok, third.message)
	harness.assert_equal(third.details["event"]["owner_hero_id"], 3)
	harness.assert_equal(fixture["state"]["sp"], 4.0)

	var reduced := Fixture.create({"sp": 5.0})
	var reduced_ids := Fixture.put_cards_in_hand(reduced, ["exclusive:ascend"])
	var changed: Variant = reduced["hand"].set_card_cost_modifiers(reduced_ids[0], {
		"until_played": -1, "until_turn": 0, "until_combat": 0,
	})
	harness.assert_true(changed.ok, changed.message)
	var reduced_result: Variant = reduced["runtime"].play_player_card(Request.new(reduced_ids[0]))
	harness.assert_true(reduced_result.ok, reduced_result.message)
	harness.assert_equal(reduced_result.details["base_cost"], 2)
	harness.assert_equal(reduced_result.details["actual_cost"], 1)
	harness.assert_equal(Fixture.hero(reduced["state"], 3)["energy"], 20.0)
	harness.assert_equal(Fixture.hero(reduced["state"], 9)["energy"], 0.0)

	var free := Fixture.create({
		"sp": 5.0, "round": 2, "owned_relic_ids": ["trueNameUnseal"],
	})
	var free_ids := Fixture.put_cards_in_hand(free, ["exclusive:shadow"])
	var free_result: Variant = free["runtime"].play_player_card(Request.new(free_ids[0]))
	harness.assert_true(free_result.ok, free_result.message)
	harness.assert_equal(free_result.details["actual_cost"], 0)
	harness.assert_equal(free["state"]["sp"], 5.0)
	harness.assert_equal(Fixture.hero(free["state"], 9)["energy"], 10.0)


func _test_preflight_failures(harness: TestHarness) -> void:
	var insufficient := Fixture.create({"sp": 0.0})
	var ids := Fixture.put_cards_in_hand(insufficient, ["free:pieceDamageUp"])
	_assert_rejection_zero_change(harness, insufficient, Request.new(ids[0]), "insufficient")

	var unusable := Fixture.create({"sp": 5.0})
	ids = Fixture.put_cards_in_hand(unusable, ["free:smallHeal"])
	_assert_rejection_zero_change(harness, unusable, Request.new(ids[0]), "validator")

	var forged := Fixture.create({"sp": 5.0})
	ids = Fixture.put_cards_in_hand(forged, ["free:pieceDamageUp"])
	var state_before: Dictionary = forged["state"].duplicate(true)
	var hand_before: Dictionary = forged["hand"].snapshot()
	var result: Variant = forged["runtime"].play_player_card(
		Request.new(ids[0], "", "basicDamage")
	)
	harness.assert_false(result.ok)
	harness.assert_equal(result.code, Result.INVALID_CARD)
	harness.assert_contains(result.message, "basicDamage")
	harness.assert_equal(forged["state"], state_before)
	harness.assert_equal(forged["hand"].snapshot(), hand_before)
	harness.assert_equal(forged["metrics"]["content_events"], [])


func _test_committed_failure(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 5.0, "fail_log": true})
	var ids := Fixture.put_cards_in_hand(fixture, ["free:pieceDamageUp"])
	var result: Variant = fixture["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_false(result.ok)
	harness.assert_equal(result.code, Result.COMMITTED_FAILURE)
	harness.assert_true(result.details["fatal"])
	harness.assert_true(result.details["committed_prefix"])
	harness.assert_equal(result.details["effect_call_count"], 1)
	harness.assert_equal(fixture["state"]["sp"], 4.0)
	harness.assert_equal(fixture["metrics"]["logs"].size(), 1)
	harness.assert_equal(fixture["runtime"].component("buffs").get_side_stacks("ally", "pieceDamageUp"), 1)
	harness.assert_equal(fixture["hand"].successful_play_count(ids[0]), 0)
	harness.assert_true(ids[0] in fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND))
	harness.assert_true(fixture["hand"].is_queue_halted())
	var retry: Variant = fixture["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_false(retry.ok)
	harness.assert_equal(retry.code, Result.QUEUE_HALTED)
	harness.assert_equal(fixture["metrics"]["logs"].size(), 1)


func _test_success_limit(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 5.0})
	var ids := Fixture.put_cards_in_hand(fixture, ["exclusive:fate"])
	var first: Variant = fixture["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_true(first.ok, first.message)
	harness.assert_equal(fixture["hand"].successful_play_count(ids[0]), 1)
	harness.assert_true(ids[0] in fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_DISCARD))
	var moved: Variant = fixture["hand"].move_card_to_pile(ids[0], CardDefinitionScript.PILE_HAND)
	harness.assert_true(moved.ok, moved.message)
	var state_before: Dictionary = fixture["state"].duplicate(true)
	var second: Variant = fixture["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_false(second.ok)
	harness.assert_equal(second.code, Result.SUCCESS_LIMIT_REACHED)
	harness.assert_equal(fixture["state"], state_before)
	harness.assert_equal(fixture["hand"].successful_play_count(ids[0]), 1)


func _assert_rejection_zero_change(
	harness: TestHarness,
	fixture: Dictionary,
	request: Variant,
	message_fragment: String,
) -> void:
	var state_before: Dictionary = fixture["state"].duplicate(true)
	var hand_before: Dictionary = fixture["hand"].snapshot()
	var result: Variant = fixture["runtime"].play_player_card(request)
	harness.assert_false(result.ok)
	harness.assert_equal(result.code, Result.VALIDATOR_REJECTED)
	harness.assert_contains(result.message, message_fragment)
	harness.assert_equal(fixture["state"], state_before)
	harness.assert_equal(fixture["hand"].snapshot(), hand_before)
	harness.assert_equal(fixture["metrics"]["content_events"], [])


func _assert_deployed_energies(
	harness: TestHarness,
	state: Dictionary,
	expected: Array,
) -> void:
	var actual: Array = []
	for hero: Dictionary in state["player_heroes"]:
		actual.append(hero["energy"])
	harness.assert_equal(actual, expected)
