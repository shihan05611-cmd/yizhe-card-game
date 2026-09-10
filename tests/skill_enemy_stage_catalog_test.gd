extends RefCounted

const SkillCatalogScript = preload("res://data/catalogs/skill_catalog.gd")
const HeroAbilityCatalogScript = preload("res://data/catalogs/hero_ability_catalog.gd")
const EnemySpecialCatalogScript = preload("res://data/catalogs/enemy_special_catalog.gd")
const StageCatalogScript = preload("res://data/catalogs/stage_catalog.gd")
const CharacterCatalogScript = preload("res://data/catalogs/character_catalog.gd")
const EventCatalogScript = preload("res://data/catalogs/event_catalog.gd")
const PieceClassCatalogScript = preload("res://data/catalogs/piece_class_catalog.gd")
const Skill = preload("res://data/definitions/skill_definition.gd")
const Ability = preload("res://data/definitions/hero_ability_definition.gd")
const EnemySpecial = preload("res://data/definitions/enemy_special_definition.gd")
const Stage = preload("res://data/definitions/stage_definition.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("free skill catalog matches all 13 Web metadata rows", func() -> void:
		_test_free_skills(harness)
	)
	harness.run_test("hero ability catalog matches 9 exclusive and 9 ultimate rows", func() -> void:
		_test_hero_abilities(harness)
	)
	harness.run_test("enemy special catalog matches Web metadata and hook references", func() -> void:
		_test_enemy_specials(harness)
	)
	harness.run_test("stage catalog matches all 3 stages and 9 enemy yizhes", func() -> void:
		_test_stages(harness)
	)
	harness.run_test("skill enemy and stage catalogs reject invalid data atomically", func() -> void:
		_test_atomic_validation(harness)
	)
	harness.run_test("skill enemy and stage builds return deeply isolated snapshots", func() -> void:
		_test_snapshot_isolation(harness)
	)
	print("A1 CATALOG TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_free_skills(harness: TestHarness) -> void:
	var expected := [
		["burnStackBase", "基础叠层", 1, "消耗1技能点。敌方全体100%施加1层灼烧；每个单位有概率额外+1层。"],
		["burnDetonate", "灼烧引爆", 2, "消耗2技能点。引爆灼烧层数最高敌人：每层造成固定伤害并清空其灼烧；若引爆击杀，则将原灼烧层平均分给其余敌人。"],
		["executeStrike", "斩杀", 2, "消耗2技能点。指定一个可锁定敌方目标，由我方攻击力最高的棋子立即造成150%直接伤害；若击杀，回复1点技能点。"],
		["pieceAction", "棋子行动", 1, "消耗1技能点。指定我方弈子获得下回合额外行动1次（普通Buff，可叠加）。"],
		["pieceBlock", "棋子格挡", 1, "消耗1技能点。全体我方棋子获得15%临时格挡率，持续1回合。"],
		["pieceDamageUp", "棋子增伤", 1, "消耗1技能点。全体我方棋子直接伤害+25%，持续1回合。"],
		["pieceHealAll", "棋子回血", 1, "消耗1技能点。为我方全体棋子回复5%生命上限。"],
		["smallHeal", "小回血", 0, "消耗0技能点。为我方当前血量最低棋子回复5%生命上限。"],
		["markBurn", "灼痕标记", 0, "消耗0技能点。对敌方灼烧层数最高单位施加1层灼烧。"],
		["bloodShift", "血移", 1, "我方血量最高棋子额外受伤，其他棋子获得免伤。"],
		["spSurge", "回气", 1, "消耗1技能点，本场消耗。回复2技能点；回复可以在本回合超过技能点上限。"],
		["tacticalDraw", "筹策", 1, "消耗1技能点，本场消耗。抽2张牌。"],
		["basicDamage", "基础伤害", 1, "对敌方单体造成 200% 伤害。"],
	]
	var catalog := SkillCatalogScript.build()
	harness.assert_equal(catalog.size(), 13)
	harness.assert_equal(catalog.keys(), expected.map(func(row: Array) -> Variant: return row[0]))
	for row in expected:
		var definition: Variant = catalog[row[0]]
		harness.assert_true(definition is Resource and definition.get_script() == Skill, row[0])
		harness.assert_equal(definition.to_source_dict(), {
			"id": row[0], "name": row[1], "cost": row[2], "tip": row[3],
		}, row[0])
		harness.assert_equal(definition.condition_id, "free_skill.%s.condition" % row[0])
		harness.assert_equal(definition.targeting_id, "free_skill.%s.targeting" % row[0])
		harness.assert_equal(definition.effect_id, "free_skill.%s.effect" % row[0])
		harness.assert_false(_contains_callable([
			definition.condition_id,
			definition.targeting_id,
			definition.effect_id,
		]))


func _test_hero_abilities(harness: TestHarness) -> void:
	var expected := [
		["burn01", 1, "蔓炎", "第1/2/3/4次释放消耗1/2/4/8技能点。使已有灼烧层数翻倍并持续+2回合。", "焚界爆炎", 100, "消耗100能量。对敌方全体造成直接伤害，基础值为己方棋子平均攻击*目标灼烧层数*系数。"],
		["fate", 2, "命运", "消耗1技能点。激活命运结界（每场仅可释放一次），每回合在「棋子命运/技能命运/混沌命运」中随机切换。技能命运每回合最多通过该效果回复3点技能点；混沌命运自然触发每场最多1次。", "众命同轨", 120, "消耗120能量。1回合内同时生效所有命运（含混沌命运），并剔除对己方的约束效果。"],
		["ascend", 3, "封命", "消耗2技能点。首次释放需指定一名存活非傀儡弈子，使其获得将军附魔（生命上限+80、格挡率+10%、暴击率+5%）。已有将军时无需指定，重复释放使其攻击+3、格挡率+3%、暴击率+3%，并回复5%已损生命。", "将军出征", 100, "消耗100能量。将军回复已损生命值50%，并获得出征2回合：攻击一列且必定暴击。"],
		["counterAura", 4, "反击", "被动：骑士上阵时我方棋子格挡率+10%。棋子受伤若格挡成功则触发小反击（40%攻击）；若技能点>x（默认4），则消耗1技能点将其升级为超级反击（200%攻击），并使骑士获得5能量。", "骑士道誓", 100, "消耗100能量。全体我方棋子获得1层骑士道：下次受到伤害时直接触发超级反击且不耗技能点，该次反击伤害+25%，触发后移除。"],
		["burnEnchant", 5, "炎华", "本场第1/2/3/4次释放消耗1/2/2/4技能点，之后均消耗4点。使所有可附魔且未满层的存活弈子获得1层炎华附魔。", "炎汲仪式", 100, "消耗100能量。全体我方获得炎汲2回合：被带灼烧的敌方攻击时，按目标灼烧层数×0.3%自身已损生命回复。"],
		["fist", 6, "拳劲", "消耗1技能点。造成基于我方弈子平均攻击的直接伤害并叠加拳势。前5层保持原有伤害、暴击率及目标数成长；超过5层后每层额外提供5%拳系增伤。", "拳意·无量", 100, "消耗100能量。随机目标连续打击3段，前5层拳势每层额外+1段并沿用其拳系增伤；5层后的拳势只继续提供每层5%拳系增伤。击杀时追加2段并自动转火，拳势不清空。"],
		["siege", 7, "破势", "消耗1技能点。对单体造成基于我方棋子平均攻击的直接伤害并施加破势（不可叠加，受直接伤害提高）。优先攻击未被破势的目标。", "摧城令", 100, "消耗100能量。展开破阵领域2回合：敌方棋子受直接伤害提高20%，攻击带破势目标时暴击率+20%。"],
		["puppet", 8, "机巧造物", "消耗1技能点。在我方空位召唤傀儡（固定100生命，攻击0，视为棋子目标；不吃任何生命上限加成）。", "森罗万象", 120, "消耗120能量。所有空位召唤傀儡并将傀儡生命回满至100，同时赋予傀儡殉道：被击杀时自爆并施加困扰。"],
		["shadow", 9, "潜影", "消耗1技能点（迅捷：不消耗弈者决策次数）。使我方未处于潜行的非傀儡棋子中攻击最高者进入潜行1回合。场上最多同时存在 n-1 个潜行棋子（n为非傀儡存活棋子数），傀儡不会被施加潜行。潜行棋子不可被敌方单体技能锁定，且下一次普攻会无视站位优先攻击敌方生命值最低单位。", "影·狩", 100, "消耗100能量。优先锁定敌方当前生命百分比最低单位（同百分比时取当前生命更低者，再同则取序号更小者），造成400%伤害；若其血量低于50%则必定暴击。随后所有潜行棋子立刻对该目标发动一次50%追击。"],
	]
	var players: Dictionary = CharacterCatalogScript.build()[CharacterCatalogScript.PLAYER]
	var catalog := HeroAbilityCatalogScript.build(players)
	harness.assert_equal(catalog.keys(), [HeroAbilityCatalogScript.EXCLUSIVE, HeroAbilityCatalogScript.ULTIMATE])
	harness.assert_equal(catalog[HeroAbilityCatalogScript.EXCLUSIVE].size(), 9)
	harness.assert_equal(catalog[HeroAbilityCatalogScript.ULTIMATE].size(), 9)
	for row in expected:
		var exclusive: Variant = catalog[HeroAbilityCatalogScript.EXCLUSIVE][row[0]]
		var ultimate: Variant = catalog[HeroAbilityCatalogScript.ULTIMATE][row[0]]
		harness.assert_true(exclusive is Resource and exclusive.get_script() == Ability)
		harness.assert_true(ultimate is Resource and ultimate.get_script() == Ability)
		harness.assert_equal([exclusive.owner_hero_id, exclusive.name, exclusive.tip], [row[1], row[2], row[3]], row[0])
		harness.assert_equal([ultimate.owner_hero_id, ultimate.name, ultimate.source_energy_requirement, ultimate.tip], [row[1], row[4], row[5], row[6]], row[0])
		harness.assert_equal(exclusive.condition_id, "battle.canCastExclusiveSkill.%s" % row[0])
		harness.assert_equal(exclusive.handler_id, "battle.castExclusiveSkill.%s" % row[0])
		harness.assert_equal(ultimate.condition_id, "battle.canHeroCastUltimate.%s" % row[0])
		harness.assert_equal(ultimate.handler_id, "battle.castUltimateByHero.%s" % row[0])
		harness.assert_equal(exclusive.is_passive, row[0] == "counterAura")
		harness.assert_equal(exclusive.source_energy_requirement, 0)


func _test_enemy_specials(harness: TestHarness) -> void:
	var catalog := EnemySpecialCatalogScript.build(EventCatalogScript.build(), PieceClassCatalogScript.build())
	harness.assert_equal(catalog.keys(), ["devourer", "echo"])
	harness.assert_equal(catalog.size(), 2)
	var expected := {
		"devourer": ["噬元兽", 2, null, 2, 1, "pieceAttackHit"],
		"echo": ["回响", 3, null, 3, 1, "unitDamaged"],
	}
	for id in expected:
		var definition: Variant = catalog[id]
		var hook: Dictionary = definition.hooks[0]
		harness.assert_true(definition is Resource and definition.get_script() == EnemySpecial)
		harness.assert_equal([
			definition.name,
			definition.grid_cells,
			definition.piece_class_id,
			definition.hp_scale,
			definition.atk_scale,
			hook["event_id"],
		], expected[id], id)
		harness.assert_equal(hook, {
			"event_id": expected[id][5],
			"condition_id": "enemy_special.%s.hook.0.when" % id,
			"effect_id": "enemy_special.%s.hook.0.effect" % id,
			"limit": "none",
			"limit_value": 1,
			"hook_index": 0,
		})
		harness.assert_equal(definition.modifiers, [])
		harness.assert_false(_contains_callable(definition.hooks))


func _test_stages(harness: TestHarness) -> void:
	var skills := SkillCatalogScript.build()
	var abilities := HeroAbilityCatalogScript.build(CharacterCatalogScript.build()[CharacterCatalogScript.PLAYER])
	var catalog := StageCatalogScript.build(skills, abilities)
	var expected := [
		["counter", "关卡1：反击流阵地", "反击流", "以格挡反击为核心，偏防守反打。", [
			[101, "敌·军令", "ascend", ["棋子增伤", "棋子行动"], ["pieceDamageUp", "pieceAction", "pieceBlock"], 100],
			[102, "敌·铁卫", "counterAura", ["棋子格挡", "棋子回血"], ["pieceBlock", "pieceHealAll", "pieceAction"], 100],
			[103, "敌·千机", "puppet", ["棋子格挡", "斩杀"], ["pieceBlock", "executeStrike", "pieceAction"], 120],
		]],
		["burn", "关卡2：灼烧流熔炉", "灼烧流", "灼烧铺场与引爆联动，持续压血。", [
			[201, "敌·灼痕", "burn01", ["基础叠层", "灼烧引爆"], ["burnStackBase", "burnDetonate", "markBurn"], 100],
			[202, "敌·炎契", "burnEnchant", ["基础叠层", "棋子增伤"], ["burnStackBase", "pieceDamageUp", "pieceAction"], 100],
			[203, "敌·命巡", "fate", ["棋子格挡", "棋子行动"], ["pieceBlock", "pieceAction", "burnStackBase"], 120],
		]],
		["core", "关卡3：弈者主核流", "弈者主核流", "以弈者直伤技能与大招为核心输出。", [
			[301, "敌·无锋", "fist", ["棋子行动", "小回血"], ["pieceAction", "smallHeal", "pieceDamageUp"], 100],
			[302, "敌·沉戈", "siege", ["棋子回血", "小回血"], ["pieceHealAll", "smallHeal", "pieceDamageUp"], 100],
			[303, "敌·命巡", "fate", ["棋子增伤", "棋子格挡"], ["pieceDamageUp", "pieceBlock", "pieceAction"], 120],
		]],
	]
	harness.assert_equal(catalog.keys(), ["counter", "burn", "core"])
	harness.assert_equal(catalog.size(), 3)
	var enemy_count := 0
	for stage_row in expected:
		var definition: Variant = catalog[stage_row[0]]
		harness.assert_true(definition is Resource and definition.get_script() == Stage)
		harness.assert_equal([definition.name, definition.archetype, definition.description], [stage_row[1], stage_row[2], stage_row[3]])
		harness.assert_equal(definition.enemy_yizhes.size(), 3)
		for index in range(3):
			var enemy: Dictionary = definition.enemy_yizhes[index]
			var row: Array = stage_row[4][index]
			harness.assert_equal([
				enemy["id"], enemy["name"], enemy["exclusive_skill_id"],
				enemy["source_skill_names"], enemy["free_skill_ids"],
				enemy["source_max_energy"], enemy["base_crit_rate"],
			], [row[0], row[1], row[2], row[3], row[4], row[5], 0.05])
			for skill_id in enemy["free_skill_ids"]:
				harness.assert_true(skills.has(skill_id), "%s:%s" % [stage_row[0], skill_id])
			harness.assert_true(abilities[HeroAbilityCatalogScript.EXCLUSIVE].has(enemy["exclusive_skill_id"]))
			harness.assert_true(abilities[HeroAbilityCatalogScript.ULTIMATE].has(enemy["exclusive_skill_id"]))
			enemy_count += 1
	harness.assert_equal(enemy_count, 9)


func _test_atomic_validation(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var references := SkillCatalogScript.reference_ids()
	var valid_skill := Skill.new("valid", "有效", "有效。", "free_skill.burnStackBase.condition", "free_skill.burnStackBase.targeting", "free_skill.burnStackBase.effect", 0)
	var invalid_skill := valid_skill.snapshot()
	invalid_skill.id = "invalid"
	invalid_skill.effect_id = "missing.effect"
	invalid_skill.base_sp_cost = -1
	harness.assert_equal(SkillCatalogScript.build_from([valid_skill, valid_skill.snapshot(), invalid_skill], references, errors), {})
	harness.assert_true(errors.size() >= 3)
	harness.assert_equal(valid_skill.name, "有效", "failed skill build must not mutate inputs")

	var players: Dictionary = CharacterCatalogScript.build()[CharacterCatalogScript.PLAYER]
	var ability_catalog := HeroAbilityCatalogScript.build(players)
	var ability_definitions: Array = ability_catalog[HeroAbilityCatalogScript.EXCLUSIVE].values() + ability_catalog[HeroAbilityCatalogScript.ULTIMATE].values()
	ability_definitions[0].handler_id = "missing.handler"
	errors.clear()
	harness.assert_equal(HeroAbilityCatalogScript.build_from(ability_definitions, players, HeroAbilityCatalogScript.reference_ids(), errors), {})
	harness.assert_true(not errors.is_empty())

	var event_catalog := EventCatalogScript.build()
	var piece_catalog := PieceClassCatalogScript.build()
	var special_catalog := EnemySpecialCatalogScript.build(event_catalog, piece_catalog)
	var special_definitions := special_catalog.values()
	special_definitions[0].hooks[0]["event_id"] = "missingEvent"
	errors.clear()
	harness.assert_equal(EnemySpecialCatalogScript.build_from(special_definitions, event_catalog, piece_catalog, EnemySpecialCatalogScript.reference_ids(), errors), {})
	harness.assert_true(not errors.is_empty())

	var stage_catalog := StageCatalogScript.build(SkillCatalogScript.build(), HeroAbilityCatalogScript.build(players))
	var stage_definitions := stage_catalog.values()
	stage_definitions[0].enemy_yizhes[0]["free_skill_ids"][0] = "missingSkill"
	errors.clear()
	harness.assert_equal(StageCatalogScript.build_from(stage_definitions, SkillCatalogScript.build(), HeroAbilityCatalogScript.build(players), errors), {})
	harness.assert_true(not errors.is_empty())


func _test_snapshot_isolation(harness: TestHarness) -> void:
	var first_skills := SkillCatalogScript.build()
	var second_skills := SkillCatalogScript.build()
	first_skills["burnStackBase"].name = "mutated"
	harness.assert_equal(second_skills["burnStackBase"].name, "基础叠层")

	var players: Dictionary = CharacterCatalogScript.build()[CharacterCatalogScript.PLAYER]
	var first_abilities := HeroAbilityCatalogScript.build(players)
	var second_abilities := HeroAbilityCatalogScript.build(players)
	first_abilities[HeroAbilityCatalogScript.EXCLUSIVE]["burn01"].name = "mutated"
	harness.assert_equal(second_abilities[HeroAbilityCatalogScript.EXCLUSIVE]["burn01"].name, "蔓炎")

	var first_specials := EnemySpecialCatalogScript.build(EventCatalogScript.build(), PieceClassCatalogScript.build())
	var second_specials := EnemySpecialCatalogScript.build(EventCatalogScript.build(), PieceClassCatalogScript.build())
	first_specials["devourer"].hooks[0]["effect_id"] = "mutated"
	harness.assert_equal(second_specials["devourer"].hooks[0]["effect_id"], "enemy_special.devourer.hook.0.effect")

	var first_stages := StageCatalogScript.build(second_skills, second_abilities)
	var second_stages := StageCatalogScript.build(second_skills, second_abilities)
	first_stages["counter"].enemy_yizhes[0]["free_skill_ids"].append("mutated")
	harness.assert_equal(second_stages["counter"].enemy_yizhes[0]["free_skill_ids"], ["pieceDamageUp", "pieceAction", "pieceBlock"])

	var errors: Array[String] = []
	var source := Stage.new("custom", "自定义", "测试", "测试。", [{
		"id": 999,
		"name": "敌·测试",
		"exclusive_skill_id": "burn01",
		"source_skill_names": ["基础叠层"],
		"free_skill_ids": ["burnStackBase"],
		"source_max_energy": 100,
		"base_crit_rate": 0.05,
	}])
	var built := StageCatalogScript.build_from([source], second_skills, second_abilities, errors)
	harness.assert_equal(errors, [])
	source.enemy_yizhes[0]["free_skill_ids"].append("mutated")
	harness.assert_equal(built["custom"].enemy_yizhes[0]["free_skill_ids"], ["burnStackBase"])


func _contains_callable(value: Variant) -> bool:
	if typeof(value) == TYPE_CALLABLE:
		return true
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if _contains_callable(item):
				return true
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if _contains_callable(key) or _contains_callable(value[key]):
				return true
	return false
