extends RefCounted

const TuningCatalogScript = preload("res://data/catalogs/tuning_catalog.gd")
const EventCatalogScript = preload("res://data/catalogs/event_catalog.gd")
const BuffCatalogScript = preload("res://data/catalogs/buff_catalog.gd")
const CharacterCatalogScript = preload("res://data/catalogs/character_catalog.gd")
const PieceClassCatalogScript = preload("res://data/catalogs/piece_class_catalog.gd")
const TuningValue = preload("res://data/definitions/tuning_value_definition.gd")
const ContentEvent = preload("res://data/definitions/content_event_definition.gd")
const Buff = preload("res://data/definitions/buff_definition.gd")
const PlayerCharacter = preload("res://data/definitions/player_character_definition.gd")
const EnemyCharacter = preload("res://data/definitions/enemy_character_definition.gd")
const PieceClass = preload("res://data/definitions/piece_class_definition.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("tuning catalog matches every Web field and value", func() -> void:
		_test_tuning(harness)
	)
	harness.run_test("content event catalog matches the stable Web contract", func() -> void:
		_test_events(harness)
	)
	harness.run_test("buff catalog matches all 18 Web definitions", func() -> void:
		_test_buffs(harness)
	)
	harness.run_test("character catalogs match 9 players and 3 default enemies", func() -> void:
		_test_characters(harness)
	)
	harness.run_test("piece class catalog and six-slot mapping match Web", func() -> void:
		_test_piece_classes(harness)
	)
	harness.run_test("catalog builds return deeply isolated snapshots", func() -> void:
		_test_snapshot_isolation(harness)
	)
	harness.run_test("invalid catalogs fail atomically before publication", func() -> void:
		_test_atomic_validation(harness)
	)


func _test_tuning(harness: TestHarness) -> void:
	var catalog := TuningCatalogScript.build()
	var expected := {
		"allyBaseHp": 360,
		"allyBaseAtk": 32,
		"allyBaseBlock": 0.05,
		"allyBaseCrit": 0.05,
		"enemyBaseHp": 360,
		"enemyBaseAtk": 30,
		"enemyBaseBlock": 0.05,
		"enemyBaseCrit": 0.05,
		"yizheBaseCrit": 0.05,
		"burnTickPerStack": 2,
		"burnDetonatePerStack": 5,
		"burnBonusChance": 0.3,
		"burnBaseDuration": 2,
		"burn01DurationBonus": 2,
		"counterDamageRatio": 0.4,
		"superCounterDamageRatio": 2.0,
		"counterAuraBlockBonus": 0.1,
		"tempBlockBonus": 0.15,
		"pieceDamageUpRatio": 0.25,
		"pursuitDamageRatio": 0.5,
		"enchantStackCap": 5,
		"skipRecover": 1,
		"roundRecover": 1,
		"ascendCost": 2,
		"ascendAtkBonus": 0,
		"ascendHpBonus": 80,
		"ascendBlockBonus": 0.1,
		"ascendRepeatAtkBonus": 1.5,
		"ascendRepeatBlockBonus": 0.015,
		"ascendRepeatCritBonus": 0.015,
		"ascendRepeatMissingHpHealRatio": 0.05,
		"fistMasteryDamageUpPerStack": 0.05,
		"ultBurn01AtkFactor": 0.05,
		"ultFateAllInTurns": 1,
		"ultAscendHealRatio": 0.5,
		"enemyUltAscendHealRatio": 0.25,
		"ultAscendMarchTurns": 2,
		"ultKnightSuperBonus": 0.25,
		"ultFlameLeechRatio": 0.003,
		"ultFlameLeechTurns": 2,
		"ultBreakFormationTurns": 2,
		"fateFixedOrder": "",
	}
	harness.assert_equal(catalog.size(), 42)
	harness.assert_equal(TuningCatalogScript.values(catalog), expected)
	for id in catalog:
		harness.assert_true(
			catalog[id] is Resource and catalog[id].get_script() == TuningValue,
			"%s must be a TuningValue Resource definition" % id,
		)


func _test_events(harness: TestHarness) -> void:
	var catalog := EventCatalogScript.build()
	var expected := {
		"BATTLE_START": "battleStart",
		"ROUND_START": "roundStart",
		"ROUND_END": "roundEnd",
		"SKILL_POINT_SPENT": "skillPointSpent",
		"BASIC_ATTACK_HIT": "basicAttackHit",
		"PIECE_ATTACK_HIT": "pieceAttackHit",
		"UNIT_DAMAGED": "unitDamaged",
		"UNIT_BLOCKED": "unitBlocked",
		"UNIT_DIED": "unitDied",
		"ULTIMATE_CAST": "ultimateCast",
		"EXCLUSIVE_CAST": "exclusiveCast",
		"FREE_SKILL_CAST": "freeSkillCast",
		"HP_THRESHOLD_CROSSED": "hpThresholdCrossed",
	}
	harness.assert_equal(catalog.size(), 13)
	harness.assert_equal(EventCatalogScript.content_event(catalog), expected)
	harness.assert_equal(EventCatalogScript.types(catalog), expected.values())
	for definition in catalog.values():
		harness.assert_true(definition is Resource and definition.get_script() == ContentEvent)


func _test_buffs(harness: TestHarness) -> void:
	var catalog := BuffCatalogScript.build(TuningCatalogScript.build())
	var expected := {
		"burn": ["灼烧", "unit", true, true, 0, 2, true, false, "回合结算时每层造成持续伤害。", "battle", []],
		"enchant": ["附魔", "unit", false, true, 5, 0, false, false, "攻击命中后按层数施加灼烧。", "battle", []],
		"knightChivalry": ["骑士道", "unit", false, true, 0, 0, false, false, "下一次反击强化。", "battle", []],
		"march": ["出征", "unit", false, false, 1, 2, false, true, "将军攻击同列目标并必定暴击。", "battle", []],
		"stealth": ["潜行", "unit", false, false, 1, 1, false, true, "暂时不被常规锁定，下一次攻击改为锁定低生命目标。", "battle", []],
		"vexed": ["困扰", "unit", true, false, 1, 1, false, true, "造成伤害降低。", "battle", []],
		"breakMarked": ["破势", "unit", true, false, 1, 0, false, false, "受到伤害提高，破阵领域中额外提高受暴击率。", "battle", []],
		"tempBlock": ["临时格挡", "side", false, false, 1, 1, false, true, "全体格挡率临时提高。", "battle", []],
		"pieceDamageUp": ["棋子增伤", "side", false, false, 1, 1, false, true, "棋子直接伤害提高。", "battle", []],
		"bloodShiftVulnerable": ["血移易伤", "unit", true, false, 1, 1, false, true, "受到伤害提高。", "battle", []],
		"bloodShiftGuard": ["血移庇护", "unit", false, false, 1, 1, false, true, "受到伤害降低。", "battle", []],
		"flameLeech": ["炎汲", "side", false, false, 1, 2, false, true, "灼烧目标攻击本方时触发治疗。", "battle", []],
		"breakFormation": ["破阵领域", "side", false, false, 1, 2, false, true, "本方对敌方伤害提高，并强化破势目标受暴击率。", "battle", []],
		"pursuit": ["追击", "unit", false, true, 0, 0, false, false, "下一次棋子行动后追加一次追击。", "battle", []],
		"flamePractice": ["炎华修习", null, false, true, 0, 0, false, false, "记录炎术士在本轮 Run 中完成的永久投资次数。", "permanent", ["hero"]],
		"flameEnchant": ["引火", null, false, true, 0, 0, false, false, "记录棋子位置获得的引火层数。", "permanent", ["pieceSlot"]],
		"marshalPromotion": ["元帅晋升", null, false, true, 0, 0, false, false, "记录棋子位置获得的元帅永久成长层数。", "permanent", ["pieceSlot"]],
		"fistMastery": ["永久拳意", null, false, true, 0, 0, false, false, "每层使拳劲与大招伤害+5%；每5层使大招基础段数+1。", "permanent", ["hero"]],
	}
	harness.assert_equal(catalog.keys(), expected.keys())
	harness.assert_equal(catalog.size(), 18)
	for id in expected:
		var definition: Variant = catalog[id]
		harness.assert_equal([
			definition.name,
			definition.scope,
			definition.is_debuff,
			definition.stackable,
			definition.max_stacks,
			definition.default_duration,
			definition.uses_layer_durations,
			definition.decays_at_round_end,
			definition.description,
			definition.persistence,
			definition.target_types,
		], expected[id], id)


func _test_characters(harness: TestHarness) -> void:
	var catalog := CharacterCatalogScript.build()
	var players: Dictionary = catalog[CharacterCatalogScript.PLAYER]
	var enemies: Dictionary = catalog[CharacterCatalogScript.ENEMY]
	harness.assert_equal(CharacterCatalogScript.avatar_colors(), [
		["#ff7d6b", "#ffb26b"],
		["#6bc6ff", "#6be0c7"],
		["#9f7bff", "#ff7be9"],
		["#5ee07a", "#7ed0ff"],
		["#ffc66b", "#ff8b8b"],
	])
	var player_rows := [
		[1, "赤焰", "burn01", ["burnStackBase", "smallHeal"], false, 0, true, 0, 100, 0.05, 0, "assets/portraits/chiyan_lihui_transparent_v2.png"],
		[2, "命轮", "fate", ["pieceAction", "pieceBlock"], false, 1, false, 0, 120, 0.05, 0, ""],
		[3, "元帅", "ascend", ["pieceDamageUp", "pieceAction"], false, 2, false, 0, 100, 0.05, 0, "assets/portraits/yuanshuai_lihui.png"],
		[4, "骑士", "counterAura", ["pieceBlock", "markBurn"], false, 3, true, 0, 100, 0.05, 0, "assets/portraits/qishi_lihui_transparent.png"],
		[5, "炎术士", "burnEnchant", ["smallHeal", "burnDetonate"], false, 4, true, 0, 100, 0.05, 0, "assets/portraits/yanshushi_lihui_transparent_v2.png"],
		[6, "宁不凡", "fist", ["pieceAction", "smallHeal"], false, 0, false, 0, 100, 0.05, 0, "assets/portraits/ningbufan_lihui_transparent_v2.png"],
		[7, "沉戈", "siege", ["pieceHealAll", "smallHeal"], false, 2, false, 0, 100, 0.05, 0, "assets/portraits/chenge_lihui_transparent.png"],
		[8, "千机", "puppet", ["pieceBlock", "executeStrike"], false, 1, false, 0, 120, 0.05, 0, "assets/portraits/qianji_lihui.png"],
		[9, "影狩", "shadow", ["pieceAction", "pieceDamageUp"], false, 2, false, 0, 100, 0.05, 0, "assets/portraits/yingshou_lihui_transparent_v2.png"],
	]
	var enemy_rows := [
		[1, "敌弈者-灼痕", "burn01", ["基础叠层", "灼烧引爆"], 0, 100, 0.05],
		[2, "敌弈者-裂隙", "fate", ["棋子格挡", "棋子增伤"], 0, 120, 0.05],
		[3, "敌弈者-军械", "counterAura", ["棋子行动", "棋子格挡"], 0, 100, 0.05],
	]
	harness.assert_equal(players.keys(), range(1, 10))
	harness.assert_equal(enemies.keys(), range(1, 4))
	for row in player_rows:
		var definition: Variant = players[row[0]]
		harness.assert_equal([
			definition.id,
			definition.name,
			definition.exclusive_skill_id,
			definition.legacy_source_metadata["freeSlots"],
			definition.legacy_source_metadata["acted"],
			definition.color_index,
			definition.deployed,
			definition.energy,
			definition.max_energy,
			definition.base_crit_rate,
			definition.fist_momentum,
			definition.source_portrait_path,
		], row, "player character %d" % row[0])
	for row in enemy_rows:
		var definition: Variant = enemies[row[0]]
		harness.assert_equal([
			definition.id,
			definition.name,
			definition.exclusive_skill_id,
			definition.skills,
			definition.energy,
			definition.max_energy,
			definition.base_crit_rate,
		], row, "enemy character %d" % row[0])


func _test_piece_classes(harness: TestHarness) -> void:
	var catalog := PieceClassCatalogScript.build()
	var expected := {
		"default": ["默认", 360, 32, 0.0, 0.0, "生命360，攻击32。无特殊效果。"],
		"shield": ["甲卒", 450, 24, 0.10, 0.0, "生命450，攻击24。被动【坚阵】：天生+10%格挡。"],
		"assassin": ["死士", 240, 42, 0.0, 0.10, "生命240，攻击42。被动【破绽】：天生+10%暴击。"],
		"crossbow": ["机弩", 300, 30, 0.0, 0.0, "生命300，攻击30。被动【连发】：普攻75%倍率，50%概率追加一段50%追击。"],
		"banner": ["旗兵", 360, 26, 0.0, 0.0, "生命360，攻击26。被动【击鼓】：行动后为我方当前能量最高弈者回复4能量。"],
	}
	harness.assert_equal(catalog.keys(), expected.keys())
	for id in expected:
		var definition: Variant = catalog[id]
		harness.assert_equal([
			definition.name,
			definition.hp,
			definition.attack,
			definition.block_bonus,
			definition.crit_bonus,
			definition.tip,
		], expected[id], id)
	harness.assert_equal(PieceClassCatalogScript.build_default_ally_mapping(catalog), {
		1: "shield", 2: "shield", 3: "shield",
		4: "crossbow", 5: "crossbow", 6: "crossbow",
	})


func _test_snapshot_isolation(harness: TestHarness) -> void:
	var first_tuning := TuningCatalogScript.build()
	var second_tuning := TuningCatalogScript.build()
	first_tuning["allyBaseHp"].value = 1
	harness.assert_equal(second_tuning["allyBaseHp"].value, 360)

	var first_buffs := BuffCatalogScript.build(second_tuning)
	var second_buffs := BuffCatalogScript.build(second_tuning)
	first_buffs["flamePractice"].target_types.append("pieceSlot")
	harness.assert_equal(second_buffs["flamePractice"].target_types, ["hero"])

	var first_characters := CharacterCatalogScript.build()
	var second_characters := CharacterCatalogScript.build()
	first_characters["players"][1].legacy_source_metadata["freeSlots"].append("mutated")
	first_characters["enemies"][1].skills.append("mutated")
	harness.assert_equal(second_characters["players"][1].legacy_source_metadata["freeSlots"], ["burnStackBase", "smallHeal"])
	harness.assert_equal(second_characters["enemies"][1].skills, ["基础叠层", "灼烧引爆"])
	var first_colors := CharacterCatalogScript.avatar_colors()
	var second_colors := CharacterCatalogScript.avatar_colors()
	first_colors[0].append("mutated")
	harness.assert_equal(second_colors[0], ["#ff7d6b", "#ffb26b"])

	var first_pieces := PieceClassCatalogScript.build()
	var second_pieces := PieceClassCatalogScript.build()
	first_pieces["shield"].name = "mutated"
	harness.assert_equal(second_pieces["shield"].name, "甲卒")
	var first_mapping := PieceClassCatalogScript.build_default_ally_mapping(first_pieces)
	var second_mapping := PieceClassCatalogScript.build_default_ally_mapping(second_pieces)
	first_mapping[1] = "banner"
	harness.assert_equal(second_mapping[1], "shield")

	var source := Buff.new("custom", "自定义", null, false, true, 0, 0, false, false, "测试。", "permanent", ["hero"])
	var errors: Array[String] = []
	var built := BuffCatalogScript.build_from([source], errors)
	source.target_types.append("pieceSlot")
	harness.assert_equal(errors, [])
	harness.assert_equal(built["custom"].target_types, ["hero"])


func _test_atomic_validation(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var valid_tuning := TuningValue.new("valid", 1)
	harness.assert_equal(TuningCatalogScript.build_from([
		valid_tuning,
		TuningValue.new("valid", 2),
		TuningValue.new("negative", -1),
	], errors), {})
	harness.assert_true(errors.size() >= 2)
	harness.assert_equal(valid_tuning.value, 1, "failed build must not mutate source resources")

	errors.clear()
	harness.assert_equal(EventCatalogScript.build_from([
		ContentEvent.new("VALID", "event"),
		ContentEvent.new("DUPLICATE", "event"),
		ContentEvent.new("", ""),
	], errors), {})
	harness.assert_true(errors.size() >= 3)

	var valid_buff := Buff.new("valid", "有效", "unit", false, true, 0, 0, false, false, "有效。")
	for invalid_buff in [
		Buff.new("invalidScope", "非法", "world", false, true, 0, 0, false, false, "非法。"),
		Buff.new("invalidNumber", "非法", "unit", false, true, -1, 0, false, false, "非法。"),
		Buff.new("invalidPermanentTarget", "非法", null, false, true, 0, 0, false, false, "非法。", "permanent", ["unit"]),
	]:
		errors.clear()
		harness.assert_equal(BuffCatalogScript.build_from([valid_buff, invalid_buff], errors), {})
		harness.assert_true(not errors.is_empty())

	errors.clear()
	harness.assert_equal(BuffCatalogScript.build_from([valid_buff, valid_buff.snapshot()], errors), {})
	harness.assert_true(not errors.is_empty())

	var player := PlayerCharacter.new(1, "玩家", "skill", 0, true, 0, 100, 0.05, 0, "", ["free"], false)
	var enemy := EnemyCharacter.new(1, "敌方", "skill", ["技能"], 0, 0, 0.05)
	errors.clear()
	harness.assert_equal(CharacterCatalogScript.build_from([player], [enemy], errors), {})
	harness.assert_true(not errors.is_empty(), "invalid enemy must reject the whole two-part catalog")

	var valid_piece := PieceClass.new("valid", "有效", 1, 0, 0.0, 0.0, "有效。")
	var invalid_piece := PieceClass.new("invalid", "非法", 1, 0, 1.1, 0.0, "非法。")
	errors.clear()
	harness.assert_equal(PieceClassCatalogScript.build_from([valid_piece, invalid_piece], errors), {})
	harness.assert_true(not errors.is_empty())
	errors.clear()
	harness.assert_equal(PieceClassCatalogScript.build_mapping_from({
		1: "valid", 2: "valid", 3: "valid", 4: "valid", 5: "valid", 6: "missing",
	}, {"valid": valid_piece}, errors), {})
	harness.assert_true(not errors.is_empty())
