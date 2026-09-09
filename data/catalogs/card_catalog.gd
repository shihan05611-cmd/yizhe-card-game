class_name CardCatalog
extends RefCounted

const Card = preload("res://data/definitions/card_definition.gd")
const Skill = preload("res://data/definitions/skill_definition.gd")
const Ability = preload("res://data/definitions/hero_ability_definition.gd")
const HeroCardCatalog = preload("res://data/catalogs/hero_card_catalog.gd")

const EXCLUDED_FREE_SKILL_IDS: Array[String] = ["basicDamage"]


static func build(skill_catalog: Dictionary, ability_catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return build_from(skill_catalog, ability_catalog, errors)


static func build_from(
	skill_catalog: Dictionary,
	ability_catalog: Dictionary,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	_validate_skill_catalog(skill_catalog, errors)
	_validate_ability_catalog(ability_catalog, errors)
	if not errors.is_empty():
		return {}

	var catalog := {}
	var skill_ids := skill_catalog.keys()
	skill_ids.sort()
	for raw_skill_id in skill_ids:
		var skill_id := str(raw_skill_id)
		if skill_id in EXCLUDED_FREE_SKILL_IDS:
			continue
		var skill: Variant = skill_catalog[raw_skill_id]
		var definition := Card.new(
			"free:%s" % skill.id,
			skill.id,
			"free_skill",
			Card.CATEGORY_FREE,
			skill.base_sp_cost,
			0,
			Card.PILE_DISCARD,
			Card.PILE_DISCARD,
			false,
			skill.condition_id,
			skill.effect_id,
		)
		catalog[definition.id] = definition

	var exclusive_catalog: Dictionary = ability_catalog["exclusive"]
	var exclusive_ids := exclusive_catalog.keys()
	exclusive_ids.sort()
	for raw_ability_id in exclusive_ids:
		var ability: Variant = exclusive_catalog[raw_ability_id]
		if ability.is_passive:
			continue
		var play_destination := Card.PILE_HAND if ability.id == "shadow" else Card.PILE_DISCARD
		var max_successes := 1 if ability.id == "fate" else 0
		var definition := Card.new(
			"exclusive:%s" % ability.id,
			ability.id,
			"hero_ability",
			Card.CATEGORY_EXCLUSIVE,
			ability.base_sp_cost,
			ability.owner_hero_id,
			play_destination,
			Card.PILE_DISCARD,
			false,
			ability.condition_id,
			ability.handler_id,
			false,
			0,
			0,
			1.0,
			max_successes,
		)
		catalog[definition.id] = definition

	var ultimate_catalog: Dictionary = ability_catalog["ultimate"]
	var ultimate_ids := ultimate_catalog.keys()
	ultimate_ids.sort()
	for raw_ability_id in ultimate_ids:
		var ability: Variant = ultimate_catalog[raw_ability_id]
		var definition := Card.new(
			"ultimate:%s" % ability.id,
			ability.id,
			"hero_ability",
			Card.CATEGORY_ULTIMATE,
			0,
			ability.owner_hero_id,
			Card.PILE_EXHAUST,
			Card.PILE_DISCARD,
			true,
			ability.condition_id,
			ability.handler_id,
		)
		catalog[definition.id] = definition
	for card_id: String in HeroCardCatalog.ids():
		var extra: Variant = HeroCardCatalog.definitions().get(card_id)
		if extra == null:
			errors.append("card catalog references unknown extra card: %s" % card_id)
			continue
		catalog[card_id] = extra.snapshot()
	if not errors.is_empty():
		return {}
	return catalog


static func build_deck_from_card_ids(
	catalog: Dictionary,
	card_ids: Array,
	errors: Array[String],
) -> Array[Resource]:
	errors.clear()
	var definitions: Array[Resource] = []
	for raw_card_id in card_ids:
		var card_id := str(raw_card_id)
		if not catalog.has(card_id):
			errors.append("deck references unknown card: %s" % card_id)
			continue
		var definition: Variant = catalog[card_id]
		if not definition is Resource or definition.get_script() != Card:
			errors.append("deck entries must reference CardDefinition resources: %s" % card_id)
			continue
		if definition.source_skill_id in EXCLUDED_FREE_SKILL_IDS:
			errors.append("deck excludes card source: %s" % definition.source_skill_id)
			continue
		definitions.append(definition.snapshot())
	if not errors.is_empty():
		return []
	return definitions


static func _validate_skill_catalog(catalog: Dictionary, errors: Array[String]) -> void:
	if catalog.is_empty():
		errors.append("card catalog requires a non-empty free skill catalog")
		return
	for raw_id in catalog:
		var skill: Variant = catalog[raw_id]
		if not skill is Resource or skill.get_script() != Skill:
			errors.append("card catalog free skill entries must be SkillDefinition resources")
		elif str(raw_id) != skill.id:
			errors.append("card catalog free skill key mismatch: %s" % str(raw_id))


static func _validate_ability_catalog(catalog: Dictionary, errors: Array[String]) -> void:
	for ability_type in ["exclusive", "ultimate"]:
		if not catalog.has(ability_type) or typeof(catalog[ability_type]) != TYPE_DICTIONARY:
			errors.append("card catalog requires hero ability group: %s" % ability_type)
			continue
		if catalog[ability_type].is_empty():
			errors.append("card catalog hero ability group must not be empty: %s" % ability_type)
			continue
		for raw_id in catalog[ability_type]:
			var ability: Variant = catalog[ability_type][raw_id]
			if not ability is Resource or ability.get_script() != Ability:
				errors.append("card catalog hero ability entries must be HeroAbilityDefinition resources")
			elif str(raw_id) != ability.id or ability.ability_type != ability_type:
				errors.append("card catalog hero ability key/type mismatch: %s:%s" % [ability_type, str(raw_id)])
