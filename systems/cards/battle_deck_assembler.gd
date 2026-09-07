class_name BattleDeckAssembler
extends RefCounted

const CardCatalogScript = preload("res://data/catalogs/card_catalog.gd")
const CardDefinitionScript = preload("res://data/definitions/card_definition.gd")
const PlayerCharacterDefinition = preload("res://data/definitions/player_character_definition.gd")
const HeroAbilityDefinition = preload("res://data/definitions/hero_ability_definition.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")

const CONFIG_KEYS := [
	"card_catalog", "player_catalog", "exclusive_catalog",
	"deployed_hero_ids", "free_skill_ids",
]
const FORBIDDEN_FREE_SKILL_IDS: Array[String] = ["basicDamage"]


static func assemble(config: Variant) -> Dictionary:
	var error := _validate_config(config)
	if not error.is_empty():
		return CombatPortsScript.fail(error)

	var card_ids: Array[String] = []
	var normalized_free_skill_ids: Array[String] = []
	for raw_skill_id: Variant in config["free_skill_ids"]:
		var skill_id: String = raw_skill_id
		if skill_id in FORBIDDEN_FREE_SKILL_IDS:
			return CombatPortsScript.fail(
				"battle deck explicitly rejects removed player card source: %s" % skill_id
			)
		var card_id := "free:%s" % skill_id
		var definition: Variant = config["card_catalog"].get(card_id)
		if not _exact_card(definition):
			return CombatPortsScript.fail("battle deck references unknown free skill: %s" % skill_id)
		if (
			definition.card_category != CardDefinitionScript.CATEGORY_FREE
			or definition.source_skill_id != skill_id
		):
			return CombatPortsScript.fail("battle deck free card authority mismatch: %s" % skill_id)
		card_ids.append(card_id)
		normalized_free_skill_ids.append(skill_id)

	var normalized_roster: Array[int] = []
	for raw_hero_id: Variant in config["deployed_hero_ids"]:
		var hero_id: int = raw_hero_id
		var player: Variant = config["player_catalog"].get(hero_id)
		if not _exact_player(player):
			return CombatPortsScript.fail("battle deck references unknown player hero: %d" % hero_id)
		var ability: Variant = config["exclusive_catalog"].get(player.exclusive_skill_id)
		if not _exact_ability(ability) or ability.owner_hero_id != hero_id:
			return CombatPortsScript.fail(
				"battle deck has no authoritative exclusive ability for hero: %d" % hero_id
			)
		normalized_roster.append(hero_id)
		if ability.is_passive:
			continue
		var exclusive_card_id := "exclusive:%s" % ability.id
		var exclusive_card: Variant = config["card_catalog"].get(exclusive_card_id)
		if (
			not _exact_card(exclusive_card)
			or exclusive_card.card_category != CardDefinitionScript.CATEGORY_EXCLUSIVE
			or exclusive_card.owner_hero_id != hero_id
		):
			return CombatPortsScript.fail(
				"battle deck has no authoritative exclusive card for hero: %d" % hero_id
			)
		card_ids.append(exclusive_card_id)

	var build_errors: Array[String] = []
	var definitions: Array[Resource] = CardCatalogScript.build_deck_from_card_ids(
		config["card_catalog"], card_ids, build_errors
	)
	if not build_errors.is_empty():
		return CombatPortsScript.fail("battle deck build failed: %s" % build_errors[0])
	return CombatPortsScript.ok({
		"card_ids": card_ids,
		"definitions": definitions,
		"deployed_hero_ids": normalized_roster,
		"free_skill_ids": normalized_free_skill_ids,
		"active_hero_count": normalized_roster.size(),
	})


static func _validate_config(config: Variant) -> String:
	if typeof(config) != TYPE_DICTIONARY or config.size() != CONFIG_KEYS.size():
		return "battle deck config must have a canonical closed shape"
	for key: String in CONFIG_KEYS:
		if not config.has(key):
			return "battle deck config.%s is required" % key
	for key: Variant in config:
		if typeof(key) != TYPE_STRING or key not in CONFIG_KEYS:
			return "battle deck config contains an unknown field"
	if typeof(config["card_catalog"]) != TYPE_DICTIONARY or config["card_catalog"].is_empty():
		return "battle deck card_catalog must be non-empty"
	if typeof(config["player_catalog"]) != TYPE_DICTIONARY or config["player_catalog"].is_empty():
		return "battle deck player_catalog must be non-empty"
	if typeof(config["exclusive_catalog"]) != TYPE_DICTIONARY or config["exclusive_catalog"].is_empty():
		return "battle deck exclusive_catalog must be non-empty"
	if typeof(config["deployed_hero_ids"]) != TYPE_ARRAY or config["deployed_hero_ids"].is_empty():
		return "battle deck deployed_hero_ids must be a non-empty Array"
	if typeof(config["free_skill_ids"]) != TYPE_ARRAY:
		return "battle deck free_skill_ids must be an Array"
	var seen_heroes := {}
	for hero_id: Variant in config["deployed_hero_ids"]:
		if typeof(hero_id) != TYPE_INT or hero_id <= 0:
			return "battle deck deployed hero ids must be positive integers"
		if seen_heroes.has(hero_id):
			return "battle deck deployed hero ids must be unique"
		seen_heroes[hero_id] = true
	for skill_id: Variant in config["free_skill_ids"]:
		if (
			typeof(skill_id) != TYPE_STRING
			or skill_id.is_empty()
			or skill_id != skill_id.strip_edges()
		):
			return "battle deck free skill ids must be non-empty trimmed strings"
	return ""


static func _exact_card(value: Variant) -> bool:
	return value is Resource and value.get_script() == CardDefinitionScript


static func _exact_player(value: Variant) -> bool:
	return value is Resource and value.get_script() == PlayerCharacterDefinition


static func _exact_ability(value: Variant) -> bool:
	return value is Resource and value.get_script() == HeroAbilityDefinition
