class_name ContentCatalog
extends RefCounted

const TuningCatalogScript = preload("res://data/catalogs/tuning_catalog.gd")
const EventCatalogScript = preload("res://data/catalogs/event_catalog.gd")
const BuffCatalogScript = preload("res://data/catalogs/buff_catalog.gd")
const CharacterCatalogScript = preload("res://data/catalogs/character_catalog.gd")
const PieceClassCatalogScript = preload("res://data/catalogs/piece_class_catalog.gd")
const SkillCatalogScript = preload("res://data/catalogs/skill_catalog.gd")
const HeroAbilityCatalogScript = preload("res://data/catalogs/hero_ability_catalog.gd")
const EnemySpecialCatalogScript = preload("res://data/catalogs/enemy_special_catalog.gd")
const StageCatalogScript = preload("res://data/catalogs/stage_catalog.gd")
const RelicCatalogScript = preload("res://data/catalogs/relic_catalog.gd")
const RoguelikeContentCatalogScript = preload("res://data/catalogs/roguelike_content_catalog.gd")

const TuningValue = preload("res://data/definitions/tuning_value_definition.gd")
const ContentEvent = preload("res://data/definitions/content_event_definition.gd")
const Buff = preload("res://data/definitions/buff_definition.gd")
const PlayerCharacter = preload("res://data/definitions/player_character_definition.gd")
const EnemyCharacter = preload("res://data/definitions/enemy_character_definition.gd")
const PieceClass = preload("res://data/definitions/piece_class_definition.gd")
const Skill = preload("res://data/definitions/skill_definition.gd")
const HeroAbility = preload("res://data/definitions/hero_ability_definition.gd")
const EnemySpecial = preload("res://data/definitions/enemy_special_definition.gd")
const Stage = preload("res://data/definitions/stage_definition.gd")
const Relic = preload("res://data/definitions/relic_definition.gd")
const RoguelikeContent = preload("res://data/definitions/roguelike_content_definition.gd")

const GROUP_ORDER := [
	"tuning",
	"events",
	"piece_classes",
	"characters",
	"skills",
	"relics",
	"buffs",
	"hero_abilities",
	"enemy_specials",
	"stages",
	"roguelike_content",
]

const EXPECTED_IDS := {
	"tuning": [
		"allyBaseHp", "allyBaseAtk", "allyBaseBlock", "allyBaseCrit",
		"enemyBaseHp", "enemyBaseAtk", "enemyBaseBlock", "enemyBaseCrit",
		"yizheBaseCrit", "burnTickPerStack", "burnDetonatePerStack",
		"burnBonusChance", "burnBaseDuration", "burn01DurationBonus",
		"counterDamageRatio", "superCounterDamageRatio", "counterAuraBlockBonus",
		"tempBlockBonus", "pieceDamageUpRatio", "pursuitDamageRatio",
		"enchantStackCap", "skipRecover", "roundRecover", "enemyRoundRecover", "ascendCost",
		"ascendAtkBonus", "ascendHpBonus", "ascendBlockBonus",
		"ascendRepeatAtkBonus", "ascendRepeatBlockBonus", "ascendRepeatCritBonus",
		"ascendRepeatMissingHpHealRatio", "fistMasteryDamageUpPerStack",
		"ultBurn01AtkFactor", "ultFateAllInTurns", "ultAscendHealRatio",
		"enemyUltAscendHealRatio", "ultAscendMarchTurns", "ultKnightSuperBonus",
		"ultFlameLeechRatio", "ultFlameLeechTurns", "ultBreakFormationTurns",
		"fateFixedOrder",
	],
	"events": [
		"battleStart", "roundStart", "roundEnd", "skillPointSpent",
		"basicAttackHit", "pieceAttackHit", "unitDamaged", "unitBlocked",
		"unitDied", "ultimateCast", "exclusiveCast", "freeSkillCast",
		"hpThresholdCrossed",
	],
	"buffs": [
		"burn", "enchant", "general", "knightChivalry", "march", "stealth", "vexed",
		"breakMarked", "tempBlock", "pieceDamageUp", "flameCastCount",
		"bloodShiftVulnerable", "bloodShiftGuard", "flameLeech", "breakFormation", "pursuit", "nextRoundAction",
		"flamePractice", "flameEnchant", "marshalPromotion", "fistMastery",
	],
	"players": [1, 2, 3, 4, 5, 6, 7, 8, 9],
	"enemies": [1, 2, 3],
	"piece_classes": ["default", "shield", "assassin", "crossbow", "banner"],
	"skills": [
		"burnStackBase", "burnDetonate", "executeStrike", "pieceAction",
		"pieceBlock", "pieceDamageUp", "pieceHealAll", "smallHeal", "markBurn",
		"bloodShift", "spSurge", "tacticalDraw", "basicDamage",
	],
	"abilities": [
		"burn01", "fate", "ascend", "counterAura", "burnEnchant", "fist",
		"siege", "puppet", "shadow",
	],
	"enemy_specials": ["devourer", "echo"],
	"stages": ["counter", "burn", "core"],
	"relics": [
		"spLimitPlus", "trueNameUnseal", "ultPursuitMark", "arcConductor",
		"emberStorm", "executionAxe", "thornCrown", "tradePermit",
		"discountCard", "witheredSeal", "crossbowPlus", "shieldPlus",
		"assassinPlus", "bannerPlus", "shentongAssaultBurst",
		"shentongChargeOverload", "rationChip", "zeroCostSpark", "scorchShard",
		"fieldBandage", "graveChange", "lastEmber",
	],
	"chapters": [1, 2, 3],
	"encounters": [
		"boss_devourer", "boss_echo", "elite_devourer", "elite_echo",
		"normal_ambush", "normal_crossfire", "normal_phalanx", "normal_pressure",
		"normal_siege", "normal_vanguard", "normal", "elite_core", "boss_core",
	],
	"shentongs": ["charge", "assault", "sacrifice"],
	"node_types": ["battle", "elite", "boss", "forge", "shop", "event"],
}


static func build(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	var groups := {}

	# This order is part of the frozen M1 composition contract.
	groups["tuning"] = TuningCatalogScript.build()
	if not _require_default_group(groups, "tuning", errors):
		return {}
	groups["events"] = EventCatalogScript.build()
	if not _require_default_group(groups, "events", errors):
		return {}
	groups["piece_classes"] = PieceClassCatalogScript.build()
	if not _require_default_group(groups, "piece_classes", errors):
		return {}
	groups["characters"] = CharacterCatalogScript.build()
	if not _require_default_group(groups, "characters", errors):
		return {}
	groups["skills"] = SkillCatalogScript.build()
	if not _require_default_group(groups, "skills", errors):
		return {}
	# A2 exposes validated definitions only through build(). The seed is never
	# published: rebuild it against this batch's events and piece classes.
	var relic_seed: Dictionary = RelicCatalogScript.build()
	if relic_seed.is_empty():
		errors.append("default relic definition seed failed to build")
		return {}
	var dependency_errors: Array[String] = []
	groups["relics"] = RelicCatalogScript.build_from(
		relic_seed.values(),
		groups["events"],
		groups["piece_classes"],
		EXPECTED_IDS["shentongs"],
		dependency_errors,
	)
	_append_errors("relics", dependency_errors, errors)
	if not errors.is_empty() or not _require_default_group(groups, "relics", errors):
		return {}

	groups["buffs"] = BuffCatalogScript.build(groups["tuning"])
	if not _require_default_group(groups, "buffs", errors):
		return {}
	groups["hero_abilities"] = HeroAbilityCatalogScript.build(groups["characters"]["players"])
	if not _require_default_group(groups, "hero_abilities", errors):
		return {}
	groups["enemy_specials"] = EnemySpecialCatalogScript.build(
		groups["events"], groups["piece_classes"],
	)
	if not _require_default_group(groups, "enemy_specials", errors):
		return {}
	groups["stages"] = StageCatalogScript.build(groups["skills"], groups["hero_abilities"])
	if not _require_default_group(groups, "stages", errors):
		return {}
	# Likewise, use the A2 default only as a definition seed, then replace every
	# copied reference with snapshots from this exact dependency batch.
	var rogue_seed: Dictionary = RoguelikeContentCatalogScript.build()
	if rogue_seed.is_empty():
		errors.append("default roguelike content definition seed failed to build")
		return {}
	var rogue_definitions: Array = []
	for rogue_group in ["chapters", "encounters", "shentongs"]:
		rogue_definitions.append_array(rogue_seed[rogue_group].values())
	groups["roguelike_content"] = RoguelikeContentCatalogScript.build_from(
		rogue_definitions,
		_trimmed_references_from_groups(groups),
		dependency_errors,
	)
	_append_errors("roguelike_content", dependency_errors, errors)
	if not errors.is_empty() or not _require_default_group(groups, "roguelike_content", errors):
		return {}

	return build_from(groups, errors)


static func build_from(groups: Dictionary, errors: Array[String]) -> Dictionary:
	errors.clear()
	_validate_top_level_shape(groups, errors)
	if not errors.is_empty():
		return {}

	_validate_stable_shapes(groups, errors)
	_validate_with_specialized_builders(groups, errors)
	if not errors.is_empty():
		return {}
	_validate_cross_references(groups, errors)
	if _contains_callable(groups):
		errors.append("content catalog must contain static data only; Callable found")
	if not errors.is_empty():
		return {}

	var published := {}
	for group_name in GROUP_ORDER:
		published[group_name] = _deep_snapshot(groups[group_name])
	return published


static func _require_default_group(
	groups: Dictionary,
	group_name: String,
	errors: Array[String],
) -> bool:
	var value: Variant = groups.get(group_name)
	if typeof(value) == TYPE_DICTIONARY and not value.is_empty():
		return true
	errors.append("default %s catalog failed to build" % group_name)
	return false


static func _validate_top_level_shape(groups: Dictionary, errors: Array[String]) -> void:
	if groups.keys() != GROUP_ORDER:
		errors.append("content catalog groups must exactly match the frozen group order")
	for group_name in GROUP_ORDER:
		if not groups.has(group_name):
			errors.append("content catalog is missing required group: %s" % group_name)
			continue
		if typeof(groups[group_name]) != TYPE_DICTIONARY:
			errors.append("content catalog group %s must be a Dictionary" % group_name)


static func _validate_stable_shapes(groups: Dictionary, errors: Array[String]) -> void:
	_validate_resource_catalog(groups["tuning"], EXPECTED_IDS["tuning"], TuningValue, "tuning", errors)
	_validate_resource_catalog(groups["events"], EXPECTED_IDS["events"], ContentEvent, "events", errors)
	_validate_resource_catalog(groups["buffs"], EXPECTED_IDS["buffs"], Buff, "buffs", errors)
	_validate_resource_catalog(groups["piece_classes"], EXPECTED_IDS["piece_classes"], PieceClass, "piece_classes", errors)
	_validate_resource_catalog(groups["skills"], EXPECTED_IDS["skills"], Skill, "skills", errors)
	_validate_resource_catalog(groups["enemy_specials"], EXPECTED_IDS["enemy_specials"], EnemySpecial, "enemy_specials", errors)
	_validate_resource_catalog(groups["stages"], EXPECTED_IDS["stages"], Stage, "stages", errors)
	_validate_resource_catalog(groups["relics"], EXPECTED_IDS["relics"], Relic, "relics", errors)

	var characters: Dictionary = groups["characters"]
	if characters.keys() != ["players", "enemies"]:
		errors.append("characters must contain exactly players then enemies")
	if typeof(characters.get("players")) == TYPE_DICTIONARY:
		_validate_resource_catalog(characters["players"], EXPECTED_IDS["players"], PlayerCharacter, "characters.players", errors)
	else:
		errors.append("characters.players must be a Dictionary")
	if typeof(characters.get("enemies")) == TYPE_DICTIONARY:
		_validate_resource_catalog(characters["enemies"], EXPECTED_IDS["enemies"], EnemyCharacter, "characters.enemies", errors)
	else:
		errors.append("characters.enemies must be a Dictionary")

	var abilities: Dictionary = groups["hero_abilities"]
	if abilities.keys() != ["exclusive", "ultimate"]:
		errors.append("hero_abilities must contain exactly exclusive then ultimate")
	for ability_type in ["exclusive", "ultimate"]:
		if typeof(abilities.get(ability_type)) == TYPE_DICTIONARY:
			_validate_resource_catalog(abilities[ability_type], EXPECTED_IDS["abilities"], HeroAbility, "hero_abilities.%s" % ability_type, errors)
		else:
			errors.append("hero_abilities.%s must be a Dictionary" % ability_type)

	var rogue: Dictionary = groups["roguelike_content"]
	var rogue_groups := [
		"node_types", "chapters", "encounters", "shentongs", "free_skills",
		"relics", "piece_classes", "enemy_specials",
	]
	if rogue.keys() != rogue_groups:
		errors.append("roguelike_content groups must match the frozen order")
	if rogue.get("node_types") != EXPECTED_IDS["node_types"]:
		errors.append("roguelike_content.node_types does not match the stable id list")
	for rogue_group in ["chapters", "encounters", "shentongs"]:
		if typeof(rogue.get(rogue_group)) == TYPE_DICTIONARY:
			_validate_resource_catalog(rogue[rogue_group], EXPECTED_IDS[rogue_group], RoguelikeContent, "roguelike_content.%s" % rogue_group, errors)
		else:
			errors.append("roguelike_content.%s must be a Dictionary" % rogue_group)
	for reference_group in ["free_skills", "relics", "piece_classes", "enemy_specials"]:
		if typeof(rogue.get(reference_group)) != TYPE_DICTIONARY:
			errors.append("roguelike_content.%s must be a Dictionary" % reference_group)


static func _validate_resource_catalog(
	catalog: Dictionary,
	expected_ids: Array,
	expected_script: Script,
	label: String,
	errors: Array[String],
) -> void:
	if catalog.keys() != expected_ids:
		errors.append("%s ids must exactly match the stable ordered list" % label)
	for id in catalog:
		var definition: Variant = catalog[id]
		if not definition is Resource or definition.get_script() != expected_script:
			errors.append("%s.%s must use the expected Resource definition" % [label, str(id)])
		elif definition.get("id") != id:
			errors.append(
				"%s.%s catalog key does not match definition id: %s"
				% [label, str(id), str(definition.get("id"))]
			)


static func _validate_with_specialized_builders(groups: Dictionary, errors: Array[String]) -> void:
	if not errors.is_empty():
		return
	var local_errors: Array[String] = []
	TuningCatalogScript.build_from(groups["tuning"].values(), local_errors)
	_append_errors("tuning", local_errors, errors)
	EventCatalogScript.build_from(groups["events"].values(), local_errors)
	_append_errors("events", local_errors, errors)
	BuffCatalogScript.build_from(groups["buffs"].values(), local_errors)
	_append_errors("buffs", local_errors, errors)
	CharacterCatalogScript.build_from(
		groups["characters"]["players"].values(),
		groups["characters"]["enemies"].values(),
		local_errors,
	)
	_append_errors("characters", local_errors, errors)
	PieceClassCatalogScript.build_from(groups["piece_classes"].values(), local_errors)
	_append_errors("piece_classes", local_errors, errors)
	SkillCatalogScript.build_from(
		groups["skills"].values(), SkillCatalogScript.reference_ids(), local_errors,
	)
	_append_errors("skills", local_errors, errors)
	var ability_definitions: Array = []
	ability_definitions.append_array(groups["hero_abilities"]["exclusive"].values())
	ability_definitions.append_array(groups["hero_abilities"]["ultimate"].values())
	HeroAbilityCatalogScript.build_from(
		ability_definitions,
		groups["characters"]["players"],
		HeroAbilityCatalogScript.reference_ids(),
		local_errors,
	)
	_append_errors("hero_abilities", local_errors, errors)
	EnemySpecialCatalogScript.build_from(
		groups["enemy_specials"].values(),
		groups["events"],
		groups["piece_classes"],
		EnemySpecialCatalogScript.reference_ids(),
		local_errors,
	)
	_append_errors("enemy_specials", local_errors, errors)
	StageCatalogScript.build_from(
		groups["stages"].values(), groups["skills"], groups["hero_abilities"], local_errors,
	)
	_append_errors("stages", local_errors, errors)
	RelicCatalogScript.build_from(
		groups["relics"].values(),
		groups["events"],
		groups["piece_classes"],
		EXPECTED_IDS["shentongs"],
		local_errors,
	)
	_append_errors("relics", local_errors, errors)

	var rogue: Dictionary = groups["roguelike_content"]
	var rogue_definitions: Array = []
	for rogue_group in ["chapters", "encounters", "shentongs"]:
		rogue_definitions.append_array(rogue[rogue_group].values())
	var rogue_references := {
		"free_skills": rogue["free_skills"],
		"relics": rogue["relics"],
		"piece_classes": rogue["piece_classes"],
		"enemy_specials": rogue["enemy_specials"],
	}
	RoguelikeContentCatalogScript.build_from(rogue_definitions, rogue_references, local_errors)
	_append_errors("roguelike_content", local_errors, errors)


static func _append_errors(prefix: String, source: Array[String], errors: Array[String]) -> void:
	for message in source:
		errors.append("%s: %s" % [prefix, message])


static func _validate_cross_references(groups: Dictionary, errors: Array[String]) -> void:
	var tuning: Dictionary = groups["tuning"]
	var buffs: Dictionary = groups["buffs"]
	var tuning_links := {
		"burn": ["default_duration", "burnBaseDuration"],
		"enchant": ["max_stacks", "enchantStackCap"],
		"march": ["default_duration", "ultAscendMarchTurns"],
		"flameLeech": ["default_duration", "ultFlameLeechTurns"],
		"breakFormation": ["default_duration", "ultBreakFormationTurns"],
	}
	for buff_id in tuning_links:
		var link: Array = tuning_links[buff_id]
		if buffs[buff_id].get(link[0]) != max(1, int(tuning[link[1]].value)):
			errors.append("buff %s does not match tuning %s" % [buff_id, link[1]])

	var players: Dictionary = groups["characters"]["players"]
	var skills: Dictionary = groups["skills"]
	var abilities: Dictionary = groups["hero_abilities"]
	for player_id in players:
		var player: Variant = players[player_id]
		if player.get_property_list().any(func(property: Dictionary) -> bool:
			return property["name"] in ["acted", "freeSlots", "free_slots"]
		):
			errors.append("player %d exposes removed acted/freeSlots outside legacy_source_metadata" % player_id)
		if player.legacy_source_metadata.keys() != ["freeSlots", "acted"]:
			errors.append("player %d legacy_source_metadata must contain only freeSlots and acted" % player_id)
		for skill_id in player.legacy_source_metadata.get("freeSlots", []):
			if not skills.has(skill_id):
				errors.append("player %d legacy freeSlots references missing skill %s" % [player_id, str(skill_id)])
		for ability_type in ["exclusive", "ultimate"]:
			if not abilities[ability_type].has(player.exclusive_skill_id):
				errors.append("player %d references missing %s ability %s" % [player_id, ability_type, player.exclusive_skill_id])
			elif abilities[ability_type][player.exclusive_skill_id].owner_hero_id != player_id:
				errors.append("player %d %s ability owner does not match" % [player_id, ability_type])

	var rogue: Dictionary = groups["roguelike_content"]
	_validate_trimmed_references(rogue, groups, errors)
	for chapter_id in rogue["chapters"]:
		var metadata: Dictionary = rogue["chapters"][chapter_id].metadata
		for encounter_id in metadata["battleEncounterIds"] + metadata["eliteEncounterIds"] + [metadata["bossEncounterId"]]:
			if not rogue["encounters"].has(encounter_id):
				errors.append("chapter %d references missing encounter %s" % [chapter_id, str(encounter_id)])


static func _validate_trimmed_references(
	rogue: Dictionary,
	groups: Dictionary,
	errors: Array[String],
) -> void:
	var expected := _trimmed_references_from_groups(groups)
	for reference_group in expected:
		if rogue[reference_group] != expected[reference_group]:
			errors.append("roguelike_content.%s must match its trimmed root catalog references" % reference_group)


static func _trimmed_references_from_groups(groups: Dictionary) -> Dictionary:
	var expected_free_skills := {}
	for id in groups["skills"]:
		expected_free_skills[id] = groups["skills"][id].to_source_dict()
	var expected_relics := {}
	for id in groups["relics"]:
		var relic: Variant = groups["relics"][id]
		expected_relics[id] = {
			"id": relic.id,
			"name": relic.name,
			"description": relic.description,
			"category": relic.category,
		}
	var expected_piece_classes := {}
	for id in groups["piece_classes"]:
		var piece_class: Variant = groups["piece_classes"][id]
		expected_piece_classes[id] = {
			"id": piece_class.id,
			"name": piece_class.name,
			"blockBonus": piece_class.block_bonus,
			"critBonus": piece_class.crit_bonus,
		}
	var expected_enemy_specials := {}
	for id in groups["enemy_specials"]:
		var special: Variant = groups["enemy_specials"][id]
		expected_enemy_specials[id] = {
			"id": special.id,
			"name": special.name,
			"gridCells": special.grid_cells,
			"pieceClassId": special.piece_class_id,
			"hpScale": special.hp_scale,
			"atkScale": special.atk_scale,
		}
	return {
		"free_skills": expected_free_skills,
		"relics": expected_relics,
		"piece_classes": expected_piece_classes,
		"enemy_specials": expected_enemy_specials,
	}


static func _deep_snapshot(value: Variant) -> Variant:
	if value is Resource:
		if value.has_method("snapshot"):
			return value.snapshot()
		return value.duplicate(true)
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item in value:
			result.append(_deep_snapshot(item))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key in value:
			result[_deep_snapshot(key)] = _deep_snapshot(value[key])
		return result
	return value


static func _contains_callable(value: Variant) -> bool:
	if value is Callable:
		return true
	if value is Resource:
		for property in value.get_property_list():
			if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				if _contains_callable(value.get(property["name"])):
					return true
		return false
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if _contains_callable(item):
				return true
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if _contains_callable(key) or _contains_callable(value[key]):
				return true
	return false
