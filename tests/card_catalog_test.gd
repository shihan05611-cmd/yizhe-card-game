extends RefCounted

const CardCatalogScript = preload("res://data/catalogs/card_catalog.gd")
const Card = preload("res://data/definitions/card_definition.gd")
const SkillCatalogScript = preload("res://data/catalogs/skill_catalog.gd")
const HeroAbilityCatalogScript = preload("res://data/catalogs/hero_ability_catalog.gd")
const CharacterCatalogScript = preload("res://data/catalogs/character_catalog.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("card catalog derives stable player cards and excludes basicDamage", func() -> void:
		_test_derived_catalog(harness)
	)
	harness.run_test("card deck builder permits copies but rejects excluded or unknown sources", func() -> void:
		_test_deck_builder(harness)
	)
	harness.run_test("card catalog validation is atomic and snapshots are isolated", func() -> void:
		_test_validation_and_isolation(harness)
	)


func _test_derived_catalog(harness: TestHarness) -> void:
	var skills := SkillCatalogScript.build()
	var abilities := _abilities()
	var catalog := CardCatalogScript.build(skills, abilities)
	harness.assert_equal(catalog.size(), 31)
	var expansion: Variant = catalog["exclusive:pressOpening"]
	harness.assert_equal([expansion.owner_hero_id, expansion.base_sp_cost, expansion.card_category], [7, 1, Card.CATEGORY_EXCLUSIVE])
	var puppet_expansion: Variant = catalog["exclusive:puppetAttunement"]
	harness.assert_equal([puppet_expansion.owner_hero_id, puppet_expansion.base_sp_cost, puppet_expansion.card_category], [8, 1, Card.CATEGORY_EXCLUSIVE])
	harness.assert_false(abilities["exclusive"].has("pressOpening"), "follow-up cards do not replace initial hero abilities")
	harness.assert_false(abilities["exclusive"].has("puppetAttunement"), "follow-up cards do not replace initial hero abilities")
	harness.assert_false(catalog.has("free:basicDamage"))
	for definition in catalog.values():
		harness.assert_true(definition is Resource and definition.get_script() == Card)
		harness.assert_true(definition.source_skill_id != "basicDamage")
		harness.assert_true(not definition.validator_id.is_empty())
		harness.assert_true(not definition.effect_id.is_empty())

	var free_card: Variant = catalog["free:burnDetonate"]
	harness.assert_equal([
		free_card.source_skill_id,
		free_card.card_category,
		free_card.base_sp_cost,
		free_card.owner_hero_id,
		free_card.card_play_destination,
		free_card.does_card_exhaust(),
	], ["burnDetonate", Card.CATEGORY_FREE, 2, 0, Card.PILE_DISCARD, false])

	var shadow: Variant = catalog["exclusive:shadow"]
	harness.assert_equal([
		shadow.source_skill_id,
		shadow.card_category,
		shadow.base_sp_cost,
		shadow.owner_hero_id,
		shadow.card_play_destination,
	], ["shadow", Card.CATEGORY_EXCLUSIVE, 1, 9, Card.PILE_HAND])
	harness.assert_false(catalog.has("exclusive:counterAura"), "passive counterAura must not create an exclusive card")
	harness.assert_true(catalog.has("ultimate:counterAura"), "the knight ultimate remains a card")

	var ultimate: Variant = catalog["ultimate:burn01"]
	harness.assert_equal([
		ultimate.source_skill_id,
		ultimate.card_category,
		ultimate.base_sp_cost,
		ultimate.owner_hero_id,
		ultimate.card_play_destination,
		ultimate.does_card_exhaust(),
	], ["burn01", Card.CATEGORY_ULTIMATE, 0, 1, Card.PILE_EXHAUST, true])
	harness.assert_equal(catalog["exclusive:fate"].max_successful_plays_per_combat, 1)
	harness.assert_true(catalog["free:executeStrike"].card_requires_target)
	harness.assert_true(catalog["free:pieceAction"].card_requires_target)
	harness.assert_true(catalog["free:spSurge"].does_card_exhaust())
	harness.assert_true(catalog["free:tacticalDraw"].does_card_exhaust())

	# Q8 removes only the player card exposure. M1/M2 authority remains intact.
	harness.assert_true(skills.has("basicDamage"))
	harness.assert_equal(skills["basicDamage"].effect_id, "free_skill.basicDamage.effect")


func _test_deck_builder(harness: TestHarness) -> void:
	var catalog := CardCatalogScript.build(SkillCatalogScript.build(), _abilities())
	var errors: Array[String] = []
	var deck := CardCatalogScript.build_deck_from_card_ids(
		catalog,
		["free:smallHeal", "free:smallHeal", "exclusive:shadow"],
		errors,
	)
	harness.assert_equal(errors, [])
	harness.assert_equal(deck.size(), 3)
	harness.assert_equal([deck[0].source_skill_id, deck[1].source_skill_id], ["smallHeal", "smallHeal"])
	harness.assert_true(deck[0] != deck[1], "duplicate cards must receive independent definition snapshots")

	var forbidden := Card.new(
		"free:basicDamage",
		"basicDamage",
		"free_skill",
		Card.CATEGORY_FREE,
		1,
		0,
		Card.PILE_DISCARD,
		Card.PILE_DISCARD,
		false,
		"validator",
		"effect",
	)
	var tainted := catalog.duplicate()
	tainted[forbidden.id] = forbidden
	harness.assert_equal(
		CardCatalogScript.build_deck_from_card_ids(tainted, [forbidden.id], errors),
		[],
	)
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(
		CardCatalogScript.build_deck_from_card_ids(catalog, ["missing"], errors),
		[],
	)
	harness.assert_true(not errors.is_empty())


func _test_validation_and_isolation(harness: TestHarness) -> void:
	var skills := SkillCatalogScript.build()
	var abilities := _abilities()
	var errors: Array[String] = []
	var malformed_skills := skills.duplicate()
	malformed_skills["burnStackBase"] = abilities["exclusive"]["burn01"]
	harness.assert_equal(CardCatalogScript.build_from(malformed_skills, abilities, errors), {})
	harness.assert_true(not errors.is_empty())

	var first := CardCatalogScript.build(skills, abilities)
	var second := CardCatalogScript.build(skills, abilities)
	first["free:smallHeal"].base_sp_cost = 99
	harness.assert_equal(second["free:smallHeal"].base_sp_cost, 0)


func _abilities() -> Dictionary:
	var characters := CharacterCatalogScript.build()
	return HeroAbilityCatalogScript.build(characters[CharacterCatalogScript.PLAYER])
