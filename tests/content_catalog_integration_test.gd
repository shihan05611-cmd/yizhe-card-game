extends RefCounted

const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")

const EXPECTED_GROUPS := [
	"tuning", "events", "piece_classes", "characters", "skills", "relics",
	"buffs", "hero_abilities", "enemy_specials", "stages", "roguelike_content",
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
		"battleStart", "roundStart", "roundEnd", "skillPointSpent", "basicAttackHit",
		"pieceAttackHit", "unitDamaged", "unitBlocked", "unitDied", "ultimateCast",
		"exclusiveCast", "freeSkillCast", "hpThresholdCrossed",
	],
	"buffs": [
		"burn", "enchant", "general", "knightChivalry", "march", "stealth", "vexed",
		"breakMarked", "tempBlock", "pieceDamageUp", "flameCastCount", "bloodShiftVulnerable",
		"bloodShiftGuard", "flameLeech", "breakFormation", "pursuit", "nextRoundAction",
		"flamePractice", "flameEnchant", "marshalPromotion", "fistMastery",
	],
	"players": [1, 2, 3, 4, 5, 6, 7, 8, 9],
	"enemies": [1, 2, 3],
	"piece_classes": ["default", "shield", "assassin", "crossbow", "banner"],
	"skills": [
		"burnStackBase", "burnDetonate", "executeStrike", "pieceAction", "pieceBlock",
		"pieceDamageUp", "pieceHealAll", "smallHeal", "markBurn", "bloodShift",
		"spSurge", "tacticalDraw", "basicDamage",
	],
	"abilities": [
		"burn01", "fate", "ascend", "counterAura", "burnEnchant", "fist", "siege",
		"puppet", "shadow",
	],
	"specials": ["devourer", "echo"],
	"stages": ["counter", "burn", "core"],
	"relics": [
		"spLimitPlus", "trueNameUnseal", "ultPursuitMark", "arcConductor", "emberStorm",
		"executionAxe", "thornCrown", "tradePermit", "discountCard", "witheredSeal",
		"crossbowPlus", "shieldPlus", "assassinPlus", "bannerPlus",
		"shentongAssaultBurst", "shentongChargeOverload", "rationChip", "zeroCostSpark",
		"scorchShard", "fieldBandage", "graveChange", "lastEmber",
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


func run(harness: TestHarness) -> void:
	harness.run_test("content catalog publishes every M1 group stable id and logical entry", func() -> void:
		_test_complete_stable_catalog(harness)
	)
	harness.run_test("content catalog preserves all critical cross references and static-only data", func() -> void:
		_test_cross_references_and_static_data(harness)
	)
	harness.run_test("content catalog builds are deeply isolated across every nested group", func() -> void:
		_test_deep_isolation(harness)
	)
	harness.run_test("content catalog rejects missing groups and wrong Resource types atomically", func() -> void:
		_test_missing_and_wrong_type_fail_closed(harness)
	)
	harness.run_test("content catalog rejects Resource key id mismatches without repairing input", func() -> void:
		_test_key_id_mismatch_fails_closed(harness)
	)
	harness.run_test("content catalog rejects dangling references and executable values atomically", func() -> void:
		_test_dangling_references_fail_closed(harness)
	)


func _test_complete_stable_catalog(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var catalog: Dictionary = ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(catalog.keys(), EXPECTED_GROUPS)
	harness.assert_equal(catalog["tuning"].keys(), EXPECTED_IDS["tuning"])
	harness.assert_equal(catalog["events"].keys(), EXPECTED_IDS["events"])
	harness.assert_equal(catalog["buffs"].keys(), EXPECTED_IDS["buffs"])
	harness.assert_equal(catalog["characters"]["players"].keys(), EXPECTED_IDS["players"])
	harness.assert_equal(catalog["characters"]["enemies"].keys(), EXPECTED_IDS["enemies"])
	harness.assert_equal(catalog["piece_classes"].keys(), EXPECTED_IDS["piece_classes"])
	harness.assert_equal(catalog["skills"].keys(), EXPECTED_IDS["skills"])
	harness.assert_equal(catalog["hero_abilities"]["exclusive"].keys(), EXPECTED_IDS["abilities"])
	harness.assert_equal(catalog["hero_abilities"]["ultimate"].keys(), EXPECTED_IDS["abilities"])
	harness.assert_equal(catalog["enemy_specials"].keys(), EXPECTED_IDS["specials"])
	harness.assert_equal(catalog["stages"].keys(), EXPECTED_IDS["stages"])
	harness.assert_equal(catalog["relics"].keys(), EXPECTED_IDS["relics"])
	var rogue: Dictionary = catalog["roguelike_content"]
	harness.assert_equal(rogue["chapters"].keys(), EXPECTED_IDS["chapters"])
	harness.assert_equal(rogue["encounters"].keys(), EXPECTED_IDS["encounters"])
	harness.assert_equal(rogue["shentongs"].keys(), EXPECTED_IDS["shentongs"])
	harness.assert_equal(rogue["node_types"], EXPECTED_IDS["node_types"])
	var stage_enemy_count := 0
	for stage in catalog["stages"].values():
		stage_enemy_count += stage.enemy_yizhes.size()
	harness.assert_equal(stage_enemy_count, 9)
	var logical_total: int = (
		catalog["tuning"].size()
		+ catalog["events"].size()
		+ catalog["buffs"].size()
		+ catalog["characters"]["players"].size()
		+ catalog["characters"]["enemies"].size()
		+ catalog["piece_classes"].size()
		+ catalog["skills"].size()
		+ catalog["hero_abilities"]["exclusive"].size()
		+ catalog["hero_abilities"]["ultimate"].size()
		+ catalog["enemy_specials"].size()
		+ catalog["stages"].size()
		+ stage_enemy_count
		+ catalog["relics"].size()
		+ rogue["chapters"].size()
		+ rogue["encounters"].size()
		+ rogue["shentongs"].size()
		+ rogue["node_types"].size()
	)
	harness.assert_equal(logical_total, 186)


func _test_cross_references_and_static_data(harness: TestHarness) -> void:
	var catalog: Dictionary = ContentCatalogScript.build()
	var players: Dictionary = catalog["characters"]["players"]
	var abilities: Dictionary = catalog["hero_abilities"]
	for player_id in players:
		var player: Variant = players[player_id]
		harness.assert_equal(player.legacy_source_metadata.keys(), ["freeSlots", "acted"])
		harness.assert_false(_has_script_property(player, "acted"))
		harness.assert_false(_has_script_property(player, "freeSlots"))
		harness.assert_false(_has_script_property(player, "free_slots"))
		for skill_id in player.legacy_source_metadata["freeSlots"]:
			harness.assert_true(catalog["skills"].has(skill_id), "%d:%s" % [player_id, skill_id])
		for ability_type in ["exclusive", "ultimate"]:
			harness.assert_true(abilities[ability_type].has(player.exclusive_skill_id))
			harness.assert_equal(abilities[ability_type][player.exclusive_skill_id].owner_hero_id, player_id)
	for special in catalog["enemy_specials"].values():
		if special.piece_class_id != null:
			harness.assert_true(catalog["piece_classes"].has(special.piece_class_id))
		for hook in special.hooks:
			harness.assert_true(catalog["events"].has(hook["event_id"]))
	for stage in catalog["stages"].values():
		for enemy in stage.enemy_yizhes:
			for skill_id in enemy["free_skill_ids"]:
				harness.assert_true(catalog["skills"].has(skill_id))
			harness.assert_true(abilities["exclusive"].has(enemy["exclusive_skill_id"]))
			harness.assert_true(abilities["ultimate"].has(enemy["exclusive_skill_id"]))
	for relic in catalog["relics"].values():
		for hook in relic.hooks:
			harness.assert_true(catalog["events"].has(hook["event"]))
		for modifier in relic.modifiers:
			if modifier.has("classId"):
				harness.assert_true(catalog["piece_classes"].has(modifier["classId"]))
			if modifier.has("shentongId"):
				harness.assert_true(catalog["roguelike_content"]["shentongs"].has(modifier["shentongId"]))
	harness.assert_equal(catalog["roguelike_content"]["free_skills"].keys(), EXPECTED_IDS["skills"])
	harness.assert_equal(catalog["roguelike_content"]["relics"].keys(), EXPECTED_IDS["relics"])
	harness.assert_equal(catalog["roguelike_content"]["piece_classes"].keys(), EXPECTED_IDS["piece_classes"])
	harness.assert_equal(catalog["roguelike_content"]["enemy_specials"].keys(), EXPECTED_IDS["specials"])
	harness.assert_false(_contains_callable(catalog))


func _test_deep_isolation(harness: TestHarness) -> void:
	var first: Dictionary = ContentCatalogScript.build()
	var second: Dictionary = ContentCatalogScript.build()
	first["tuning"]["allyBaseHp"].value = 1
	first["characters"]["players"][1].legacy_source_metadata["freeSlots"].append("mutated")
	first["relics"]["trueNameUnseal"].modifiers[0]["skillKinds"].append("mutated")
	first["stages"]["counter"].enemy_yizhes[0]["free_skill_ids"].append("mutated")
	first["roguelike_content"]["node_types"].append("mutated")
	first["roguelike_content"]["chapters"][1].metadata["columnRules"][0]["fixedByRow"][0] = "event"
	first["roguelike_content"]["free_skills"]["burnStackBase"]["name"] = "mutated"
	harness.assert_equal(second["tuning"]["allyBaseHp"].value, 360)
	harness.assert_equal(second["characters"]["players"][1].legacy_source_metadata["freeSlots"], ["burnStackBase", "smallHeal"])
	harness.assert_equal(second["relics"]["trueNameUnseal"].modifiers[0]["skillKinds"], ["freeSkill", "exclusive"])
	harness.assert_equal(second["stages"]["counter"].enemy_yizhes[0]["free_skill_ids"], ["pieceDamageUp", "pieceAction", "pieceBlock"])
	harness.assert_equal(second["roguelike_content"]["node_types"], EXPECTED_IDS["node_types"])
	harness.assert_equal(second["roguelike_content"]["chapters"][1].metadata["columnRules"][0]["fixedByRow"], ["battle", "battle", "battle"])
	harness.assert_equal(second["roguelike_content"]["free_skills"]["burnStackBase"]["name"], "基础叠层")


func _test_missing_and_wrong_type_fail_closed(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var missing: Dictionary = ContentCatalogScript.build()
	missing.erase("events")
	harness.assert_equal(ContentCatalogScript.build_from(missing, errors), {})
	harness.assert_true(not errors.is_empty())
	harness.assert_true(not missing.has("events"), "failed assembly must not repair or publish its input")

	errors.clear()
	var wrong_type: Dictionary = ContentCatalogScript.build()
	wrong_type["skills"]["burnStackBase"] = wrong_type["relics"]["spLimitPlus"]
	harness.assert_equal(ContentCatalogScript.build_from(wrong_type, errors), {})
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(wrong_type["skills"]["burnStackBase"].id, "spLimitPlus")


func _test_key_id_mismatch_fails_closed(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var swapped: Dictionary = ContentCatalogScript.build()
	var ally_hp: Resource = swapped["tuning"]["allyBaseHp"]
	var ally_atk: Resource = swapped["tuning"]["allyBaseAtk"]
	swapped["tuning"]["allyBaseHp"] = ally_atk
	swapped["tuning"]["allyBaseAtk"] = ally_hp

	harness.assert_equal(ContentCatalogScript.build_from(swapped, errors), {})
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(swapped["tuning"]["allyBaseHp"].id, "allyBaseAtk")
	harness.assert_equal(swapped["tuning"]["allyBaseAtk"].id, "allyBaseHp")


func _test_dangling_references_fail_closed(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var dangling_stage: Dictionary = ContentCatalogScript.build()
	dangling_stage["stages"]["counter"].enemy_yizhes[0]["free_skill_ids"][0] = "missing"
	harness.assert_equal(ContentCatalogScript.build_from(dangling_stage, errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var dangling_rogue: Dictionary = ContentCatalogScript.build()
	dangling_rogue["roguelike_content"]["free_skills"].erase("burnStackBase")
	harness.assert_equal(ContentCatalogScript.build_from(dangling_rogue, errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var executable: Dictionary = ContentCatalogScript.build()
	executable["relics"]["spLimitPlus"].modifiers[0]["callback"] = func() -> void: pass
	harness.assert_equal(ContentCatalogScript.build_from(executable, errors), {})
	harness.assert_true(not errors.is_empty())


func _has_script_property(resource: Resource, property_name: String) -> bool:
	for property in resource.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and property["name"] == property_name:
			return true
	return false


func _contains_callable(value: Variant) -> bool:
	if value is Callable:
		return true
	if value is Resource:
		for property in value.get_property_list():
			if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and _contains_callable(value.get(property["name"])):
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
