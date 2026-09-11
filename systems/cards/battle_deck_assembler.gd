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
	var retained_flags: Array[bool] = []
	var retained_key_set := {}
	var matched_retained_keys := {}
	for retained_key: String in config.get("retained_card_keys", []):
		retained_key_set[retained_key] = true
	var normalized_free_skill_ids: Array[String] = []
	for free_index in config["free_skill_ids"].size():
		var raw_skill_id: Variant = config["free_skill_ids"][free_index]
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
		var retain_key := "free:%d" % free_index
		var retained := retained_key_set.has(retain_key)
		retained_flags.append(retained)
		if retained:
			matched_retained_keys[retain_key] = true
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
		var retain_key := "hero:%d" % hero_id
		var retained := retained_key_set.has(retain_key)
		retained_flags.append(retained)
		if retained:
			matched_retained_keys[retain_key] = true

	# Rewards add independent copies; initial owner cards above remain one each.
	var extra_card_ids: Array = config.get("exclusive_card_ids", [])
	for exclusive_index in extra_card_ids.size():
		var card_id: String = extra_card_ids[exclusive_index]
		var extra: Variant = config["card_catalog"].get(card_id)
		if (
			not _exact_card(extra)
			or extra.card_category != CardDefinitionScript.CATEGORY_EXCLUSIVE
			or extra.owner_hero_id not in normalized_roster
		):
			return CombatPortsScript.fail("battle deck exclusive card requires its deployed owner: %s" % card_id)
		card_ids.append(card_id)
		var retain_key := "exclusive:%d" % exclusive_index
		var retained := retained_key_set.has(retain_key)
		retained_flags.append(retained)
		if retained:
			matched_retained_keys[retain_key] = true

	for retained_key: String in retained_key_set:
		if not matched_retained_keys.has(retained_key):
			return CombatPortsScript.fail(
				"battle deck retained card key does not match a card copy: %s" % retained_key
			)

	var build_errors: Array[String] = []
	var definitions: Array[Resource] = CardCatalogScript.build_deck_from_card_ids(
		config["card_catalog"], card_ids, build_errors
	)
	if not build_errors.is_empty():
		return CombatPortsScript.fail("battle deck build failed: %s" % build_errors[0])
	return CombatPortsScript.ok({
		"card_ids": card_ids,
		"definitions": definitions,
		"retained_flags": retained_flags,
		"retained_card_keys": config.get("retained_card_keys", []).duplicate(),
		"deployed_hero_ids": normalized_roster,
		"free_skill_ids": normalized_free_skill_ids,
		"exclusive_card_ids": config.get("exclusive_card_ids", []).duplicate(),
		"active_hero_count": normalized_roster.size(),
	})


static func _validate_config(config: Variant) -> String:
	if typeof(config) != TYPE_DICTIONARY:
		return "battle deck config must have a canonical closed shape"
	for key: String in CONFIG_KEYS:
		if not config.has(key):
			return "battle deck config.%s is required" % key
	for key: Variant in config:
		if (
			typeof(key) != TYPE_STRING
			or (key not in CONFIG_KEYS and key not in ["exclusive_card_ids", "retained_card_keys"])
		):
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
	if typeof(config.get("exclusive_card_ids", [])) != TYPE_ARRAY:
		return "battle deck exclusive_card_ids must be an Array"
	if typeof(config.get("retained_card_keys", [])) != TYPE_ARRAY:
		return "battle deck retained_card_keys must be an Array"
	for card_id: Variant in config.get("exclusive_card_ids", []):
		if typeof(card_id) != TYPE_STRING or card_id.is_empty() or card_id != card_id.strip_edges():
			return "battle deck exclusive_card_ids must contain non-empty trimmed strings"
	var seen_retained_keys := {}
	for retained_key: Variant in config.get("retained_card_keys", []):
		if (
			typeof(retained_key) != TYPE_STRING
			or retained_key.is_empty()
			or retained_key != retained_key.strip_edges()
		):
			return "battle deck retained_card_keys must contain non-empty trimmed strings"
		if seen_retained_keys.has(retained_key):
			return "battle deck retained_card_keys must be unique"
		seen_retained_keys[retained_key] = true
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
