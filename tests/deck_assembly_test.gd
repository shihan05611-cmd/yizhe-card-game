extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const CardCatalogScript = preload("res://data/catalogs/card_catalog.gd")
const DeckAssemblerScript = preload("res://systems/cards/battle_deck_assembler.gd")
const HandRuntimeScript = preload("res://systems/cards/hand_runtime.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("duplicate free skills create independent cards and active exclusives", func() -> void:
		_test_duplicates_exclusives_and_knight(harness)
	)
	harness.run_test("battle deck rejects removed basicDamage input atomically", func() -> void:
		_test_basic_damage_rejected(harness)
	)
	harness.run_test("new external roster and free-skill inputs change only new battle assembly", func() -> void:
		_test_changed_external_input(harness)
	)
	harness.run_test("earned exclusive copies retain ownership and independent instances", func() -> void:
		_test_earned_exclusives(harness)
	)
	print("M3-3 DECK ASSEMBLY TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_duplicates_exclusives_and_knight(harness: TestHarness) -> void:
	var authority := _authority()
	var result: Dictionary = _assemble(authority, [1, 4, 9], ["smallHeal", "smallHeal"])
	harness.assert_true(result["ok"], str(result))
	if not result["ok"]:
		return
	var value: Dictionary = result["value"]
	harness.assert_equal(value["active_hero_count"], 3)
	harness.assert_equal(value["deployed_hero_ids"], [1, 4, 9])
	harness.assert_equal(value["free_skill_ids"], ["smallHeal", "smallHeal"])
	harness.assert_equal(value["card_ids"], [
		"free:smallHeal", "free:smallHeal", "exclusive:burn01", "exclusive:shadow",
	])
	harness.assert_equal(value["definitions"].size(), 4)
	var hand := HandRuntimeScript.new("m3-3-duplicates")
	var initialized: Variant = hand.initialize_deck(value["definitions"], false)
	harness.assert_true(initialized.ok, initialized.message)
	harness.assert_equal(initialized.details["instance_ids"].size(), 4)
	harness.assert_equal(initialized.details["instance_ids"][0], "card-00000001")
	harness.assert_equal(initialized.details["instance_ids"][1], "card-00000002")
	var first: Variant = hand.get_instance_snapshot("card-00000001")
	var second: Variant = hand.get_instance_snapshot("card-00000002")
	harness.assert_equal(first.source_skill_id, "smallHeal")
	harness.assert_equal(second.source_skill_id, "smallHeal")
	harness.assert_false(first.instance_id == second.instance_id)
	harness.assert_false(value["card_ids"].has("exclusive:counterAura"))


func _test_basic_damage_rejected(harness: TestHarness) -> void:
	var authority := _authority()
	var before_cards: Dictionary = _card_dicts(authority["cards"])
	var result: Dictionary = _assemble(
		authority, [1, 4], ["smallHeal", "basicDamage", "smallHeal"]
	)
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "explicitly rejects")
	harness.assert_equal(_card_dicts(authority["cards"]), before_cards)
	harness.assert_false(authority["cards"].has("free:basicDamage"))
	harness.assert_true(authority["catalogs"]["skills"].has("basicDamage"))


func _test_changed_external_input(harness: TestHarness) -> void:
	var authority := _authority()
	var first: Dictionary = _assemble(authority, [1], ["smallHeal"])
	var second: Dictionary = _assemble(
		authority, [1, 4, 9], ["smallHeal", "smallHeal", "pieceBlock"]
	)
	harness.assert_true(first["ok"], str(first))
	harness.assert_true(second["ok"], str(second))
	if not first["ok"] or not second["ok"]:
		return
	harness.assert_equal(first["value"]["active_hero_count"], 1)
	harness.assert_equal(second["value"]["active_hero_count"], 3)
	harness.assert_equal(first["value"]["card_ids"].size(), 2)
	harness.assert_equal(second["value"]["card_ids"].size(), 5)
	harness.assert_equal(
		second["value"]["card_ids"].count("free:smallHeal"),
		2,
	)
	harness.assert_false(second["value"]["card_ids"].has("exclusive:counterAura"))


func _test_earned_exclusives(harness: TestHarness) -> void:
	var authority := _authority()
	var earned := ["exclusive:shadow", "exclusive:shadow"]
	var result := _assemble(authority, [9], [], earned)
	harness.assert_true(result["ok"], str(result))
	if not result["ok"]:
		return
	harness.assert_equal(result["value"]["card_ids"].count("exclusive:shadow"), 3)
	harness.assert_equal(result["value"]["active_hero_count"], 1, "extra copies do not increase turn draw")
	var hand := HandRuntimeScript.new("earned-exclusive-copies")
	var initialized: Variant = hand.initialize_deck(result["value"]["definitions"], false)
	harness.assert_true(initialized.ok, initialized.message)
	var ids: Array = initialized.details["instance_ids"]
	harness.assert_equal(ids.size(), 3)
	harness.assert_false(ids[0] == ids[1])
	harness.assert_false(ids[1] == ids[2])
	for invalid in [["exclusive:shadow"], ["ultimate:shadow"], ["free:smallHeal"], ["exclusive:counterAura"], [12]]:
		var rejected := _assemble(authority, [4], [], invalid)
		harness.assert_false(rejected["ok"], "undeployed, passive, ultimate and non-exclusive inputs are rejected")
	harness.assert_equal(earned, ["exclusive:shadow", "exclusive:shadow"], "assembly does not mutate ownership")


func _authority() -> Dictionary:
	var errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(errors)
	assert(errors.is_empty(), str(errors))
	var cards: Dictionary = CardCatalogScript.build_from(
		catalogs["skills"], catalogs["hero_abilities"], errors
	)
	assert(errors.is_empty(), str(errors))
	return {"catalogs": catalogs, "cards": cards}


func _assemble(
	authority: Dictionary,
	roster: Array,
	free_skill_ids: Array,
	exclusive_card_ids: Array = [],
) -> Dictionary:
	return DeckAssemblerScript.assemble({
		"card_catalog": authority["cards"],
		"player_catalog": authority["catalogs"]["characters"]["players"],
		"exclusive_catalog": authority["catalogs"]["hero_abilities"]["exclusive"],
		"deployed_hero_ids": roster,
		"free_skill_ids": free_skill_ids,
		"exclusive_card_ids": exclusive_card_ids,
	})


func _card_dicts(cards: Dictionary) -> Dictionary:
	var result := {}
	for id: Variant in cards:
		result[id] = cards[id].to_dict()
	return result
