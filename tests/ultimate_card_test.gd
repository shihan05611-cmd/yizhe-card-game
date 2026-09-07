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
	harness.run_test("generated ultimate costs zero exhausts and grants no energy", func() -> void:
		_test_ultimate_play(harness)
	)
	print("M3-2 ULTIMATE CARD TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_ultimate_play(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 3.0})
	var hero := Fixture.hero(fixture["state"], 9)
	hero["energy"] = 95.0
	var generated: Dictionary = fixture["runtime"].apply_player_energy({
		"hero_id": 9, "amount": 5.0, "source": {"kind": "card_play"},
	})
	harness.assert_true(generated["ok"], str(generated))
	var instance_id: String = generated["value"]["generated_card"]["instance_id"]
	fixture["state"]["enemy_fate"]["ally_lock"] = "noSkill"
	var rejected: Variant = fixture["runtime"].play_player_card(Request.new(instance_id))
	harness.assert_false(rejected.ok)
	harness.assert_equal(rejected.code, Result.VALIDATOR_REJECTED)
	harness.assert_true(instance_id in fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND))
	harness.assert_equal(fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_EXHAUST), [])
	harness.assert_equal(fixture["hand"].successful_play_count(instance_id), 0)
	fixture["state"]["enemy_fate"]["ally_lock"] = null
	var enemy_hp_before := float(fixture["state"]["enemies"][0]["hp"])
	var result: Variant = fixture["runtime"].play_player_card(Request.new(instance_id))
	harness.assert_true(result.ok, result.message)
	harness.assert_equal(result.details["base_cost"], 0)
	harness.assert_equal(result.details["effective_cost"], 0)
	harness.assert_equal(result.details["actual_cost"], 0)
	harness.assert_equal(result.details["effect_call_count"], 1)
	harness.assert_equal(fixture["state"]["sp"], 3.0)
	harness.assert_equal(hero["energy"], 0.0)
	harness.assert_equal(result.details["energy_amount"], 0)
	harness.assert_equal(result.details["energy_changes"], [])
	harness.assert_equal(result.details["destination"], CardDefinitionScript.PILE_EXHAUST)
	harness.assert_true(instance_id in fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_EXHAUST))
	harness.assert_true(float(fixture["state"]["enemies"][0]["hp"]) < enemy_hp_before)
	harness.assert_equal(fixture["metrics"]["content_events"].size(), 1)
	harness.assert_equal(fixture["metrics"]["content_events"][0]["event_id"], "ultimateCast")
