extends RefCounted

const RelicCatalogScript = preload("res://data/catalogs/relic_catalog.gd")
const RoguelikeCatalogScript = preload("res://data/catalogs/roguelike_content_catalog.gd")
const EventCatalogScript = preload("res://data/catalogs/event_catalog.gd")
const PieceClassCatalogScript = preload("res://data/catalogs/piece_class_catalog.gd")
const Relic = preload("res://data/definitions/relic_definition.gd")
const RoguelikeContent = preload("res://data/definitions/roguelike_content_definition.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("relic catalog matches all 22 Web definitions and stable ids", func() -> void:
		_test_relics(harness)
	)
	harness.run_test("relic hook and modifier metadata replaces every Web callback", func() -> void:
		_test_relic_metadata(harness)
	)
	harness.run_test("relic catalog rejects invalid duplicate and dangling metadata atomically", func() -> void:
		_test_relic_atomic_validation(harness)
	)
	harness.run_test("roguelike catalog matches Web chapters encounters shentongs rewards and node types", func() -> void:
		_test_roguelike_content(harness)
	)
	harness.run_test("roguelike catalog rejects duplicate invalid and dangling definitions atomically", func() -> void:
		_test_roguelike_atomic_validation(harness)
	)
	harness.run_test("relic and roguelike builds return deeply isolated snapshots", func() -> void:
		_test_deep_snapshot_isolation(harness)
	)


func _test_relics(harness: TestHarness) -> void:
	var catalog := RelicCatalogScript.build()
	var expected := [
		["spLimitPlus", "01号遗物", "common", "技能点上限 +1。"],
		["trueNameUnseal", "真名解放", "common", "每场战斗的前两回合，释放自由技或专属不消耗技能点。"],
		["ultPursuitMark", "余韵追击", "common", "每场战斗，我方首次释放大招后，全体棋子获得一层追击。"],
		["arcConductor", "奥术导体", "common", "我方消耗 SP 时，对敌方全体造成队伍平均攻击 x 0.6 x 消耗 SP 的遗物伤害。"],
		["emberStorm", "余烬风暴", "common", "带灼烧的敌方阵亡时，灼烧层数扩散并立即结算一次。"],
		["executionAxe", "处刑巨斧", "common", "敌方首次低于 30% 生命时，攻击最高的我方棋子获得并立即消耗一层追击。"],
		["thornCrown", "荆棘王冠", "common", "我方成功格挡时，对攻击者造成本次伤害 50% 的遗物反伤。"],
		["tradePermit", "交易许可", "common", "商店页面解锁出售已有自由技，售价等于标准买入价。"],
		["discountCard", "打折卡", "common", "所有货币消耗降低 25%。"],
		["witheredSeal", "凋零印记", "common", "敌方受到的恢复效果降低 25%。"],
		["crossbowPlus", "连发PLUS", "classUpgrade", "机弩额外追击概率 +10%，但生命 -20。"],
		["shieldPlus", "坚阵PLUS", "classUpgrade", "甲卒格挡成功时回复 3% 已损生命。"],
		["assassinPlus", "破绽PLUS", "classUpgrade", "死士血量低于 50% 时额外获得 30% 暴击率。"],
		["bannerPlus", "击鼓PLUS", "classUpgrade", "旗兵每次攻击后额外给随机弈者回复 1 能量，追击也算。"],
		["shentongAssaultBurst", "终极爆发", "shentongEvolve", "神通【突击】的基础伤害增幅提升至 500%。"],
		["shentongChargeOverload", "能量过载", "shentongEvolve", "神通【蓄势】发动时，我方全体弈者回复 30 点能量。"],
		["rationChip", "配给筹码", "common", "每场战斗开始时回复 1 点技能点。"],
		["zeroCostSpark", "零耗火花", "common", "每回合首次释放实际消耗为 0 的我方自由技后，最低能量弈者回复 10 点能量。"],
		["scorchShard", "焦痕弹片", "common", "每回合我方每个棋子首次攻击命中后，对目标施加 1 层灼烧。"],
		["fieldBandage", "战地绷带", "common", "每回合我方每个棋子首次受伤后，回复其生命上限的 2%。"],
		["graveChange", "亡者零钱", "elite", "由我方击杀的敌人阵亡时回复 1 点技能点；我方献祭单位阵亡时同样生效。"],
		["lastEmber", "余命火种", "common", "每场战斗首个敌方单位阵亡后，所有存活棋子各回复生命上限的 10%。"],
	]
	harness.assert_equal(catalog.size(), 22)
	harness.assert_equal(catalog.keys(), expected.map(func(row: Array) -> String: return row[0]))
	for row in expected:
		var definition: Variant = catalog[row[0]]
		harness.assert_true(definition is Resource and definition.get_script() == Relic, row[0])
		harness.assert_equal([
			definition.id, definition.name, definition.category, definition.description,
		], row, row[0])


func _test_relic_metadata(harness: TestHarness) -> void:
	var catalog := RelicCatalogScript.build()
	var expected_hooks := {
		"ultPursuitMark": ["ultimateCast", "relic.condition.source_effect_is_ally", "relic.effect.apply_pursuit_to_alive_allies", "perBattle", "event", 1],
		"arcConductor": ["skillPointSpent", "relic.condition.ally_spent_positive_sp", "relic.effect.deal_arc_conductor_damage_to_all_enemies", "none", "event", 1],
		"emberStorm": ["unitDied", "relic.condition.enemy_burn_death_allows_kill_effects", "relic.effect.spread_burn_on_enemy_death", "none", "event", 1],
		"executionAxe": ["hpThresholdCrossed", "relic.condition.target_is_enemy", "relic.effect.trigger_strongest_ally_pursuit", "none", "event", 1],
		"thornCrown": ["unitBlocked", "relic.condition.ally_blocked_by_alive_actor", "relic.effect.reflect_blocked_raw_damage", "none", "event", 1],
		"shieldPlus": ["unitBlocked", "relic.condition.ally_shield_blocked", "relic.effect.heal_missing_hp_ratio", "none", "event", 1],
		"bannerPlus": ["pieceAttackHit", "relic.condition.ally_banner_attack_hit", "relic.effect.gain_random_active_hero_energy", "none", "event", 1],
		"rationChip": ["battleStart", "", "relic.effect.gain_skill_points", "none", "event", 1],
		"zeroCostSpark": ["freeSkillCast", "relic.condition.ally_free_skill_actual_cost_zero", "relic.effect.gain_lowest_energy_active_hero_energy", "perRound", "event", 1],
		"scorchShard": ["pieceAttackHit", "relic.condition.ally_piece_hit_alive_target", "relic.effect.apply_burn", "perRound", "actor", 1],
		"fieldBandage": ["unitDamaged", "relic.condition.ally_target_alive", "relic.effect.heal_max_hp_ratio", "perRound", "target", 1],
		"graveChange": ["unitDied", "relic.condition.ally_kill_or_ally_sacrifice", "relic.effect.gain_skill_points", "none", "event", 1],
		"lastEmber": ["unitDied", "relic.condition.target_is_enemy", "relic.effect.heal_alive_allies_ratio", "perBattle", "event", 1],
	}
	var expected_params := {
		"ultPursuitMark": [{"source_side": "ally"}, {"stacks": 1}],
		"arcConductor": [{"source_side": "ally", "minimum_amount": 1}, {"team_average_attack_multiplier_per_sp": 0.6, "source_id": "arcConductor", "source_name": "奥术导体"}],
		"emberStorm": [{"target_side": "enemy", "buff_id": "burn", "minimum_stacks": 1, "requires_enemy_kill_effects": true}, {}],
		"executionAxe": [{"target_side": "enemy", "hp_ratio": 0.3}, {}],
		"thornCrown": [{"target_side": "ally", "actor_alive": true}, {"raw_damage_ratio": 0.5, "minimum_damage": 1, "source_id": "thornCrown", "source_name": "荆棘王冠"}],
		"shieldPlus": [{"target_side": "ally", "class_id": "shield"}, {"missing_hp_ratio": 0.03, "source_id": "shieldPlus", "source_name": "坚阵PLUS"}],
		"bannerPlus": [{"actor_side": "ally", "class_id": "banner"}, {"amount": 1, "source_id": "bannerPlus", "source_name": "击鼓PLUS"}],
		"rationChip": [{}, {"amount": 1}],
		"zeroCostSpark": [{"source_side": "ally", "actual_cost": 0}, {"amount": 10}],
		"scorchShard": [{"actor_side": "ally", "target_alive": true}, {"buff_id": "burn", "stacks": 1}],
		"fieldBandage": [{"target_side": "ally", "target_alive": true}, {"max_hp_ratio": 0.02, "source_id": "fieldBandage", "source_name": "战地绷带"}],
		"graveChange": [{"accepted_cases": [{"target_side": "enemy", "source_side": "ally"}, {"target_side": "ally", "source_side": "ally", "source_type": "sacrifice"}]}, {"amount": 1}],
		"lastEmber": [{"target_side": "enemy"}, {"max_hp_ratio": 0.1, "source_id": "lastEmber", "source_name": "余命火种"}],
	}
	for id in catalog:
		var definition: Variant = catalog[id]
		harness.assert_equal(definition.hooks.size(), 1 if expected_hooks.has(id) else 0, "%s hook count" % id)
		for hook_index in definition.hooks.size():
			var hook: Dictionary = definition.hooks[hook_index]
			harness.assert_false(_contains_callable(hook), "%s hook must be static data" % id)
			harness.assert_equal([
				hook["event"], hook["condition_id"], hook["effect_id"],
				hook["limit"], hook["limit_scope"], hook["limit_value"],
			], expected_hooks[id], id)
			harness.assert_equal(hook["hook_index"], hook_index, id)
			harness.assert_equal([hook["condition_params"], hook["effect_params"]], expected_params[id], "%s hook params" % id)

	var expected_modifiers := {
		"spLimitPlus": [{"type": "skillPointMaxFlat", "handler_id": "relic.modifier.skillPointMaxFlat", "value": 1}],
		"trueNameUnseal": [{"type": "skillPointCostOverride", "handler_id": "relic.modifier.skillPointCostOverride", "side": "ally", "skillKinds": ["freeSkill", "exclusive"], "maxRound": 2, "value": 0}],
		"tradePermit": [{"type": "canSellFreeSkills", "handler_id": "relic.modifier.canSellFreeSkills", "value": true}],
		"discountCard": [{"type": "currencyCostMultiplier", "handler_id": "relic.modifier.currencyCostMultiplier", "value": 0.75}],
		"witheredSeal": [{"type": "healingReceivedMultiplier", "handler_id": "relic.modifier.healingReceivedMultiplier", "side": "enemy", "value": 0.75}],
		"crossbowPlus": [
			{"type": "classMaxHpFlat", "handler_id": "relic.modifier.classMaxHpFlat", "side": "ally", "classId": "crossbow", "value": -20},
			{"type": "pursuitChanceFlat", "handler_id": "relic.modifier.pursuitChanceFlat", "side": "ally", "classId": "crossbow", "value": 0.1},
		],
		"assassinPlus": [{"type": "critRateFlatBelowHp", "handler_id": "relic.modifier.critRateFlatBelowHp", "side": "ally", "classId": "assassin", "hpRatio": 0.5, "value": 0.3}],
		"shentongAssaultBurst": [{"type": "shentongDamageMultiplier", "handler_id": "relic.modifier.shentongDamageMultiplier", "shentongId": "assault", "value": 5}],
		"shentongChargeOverload": [{"type": "shentongEnergyGain", "handler_id": "relic.modifier.shentongEnergyGain", "shentongId": "charge", "value": 30}],
	}
	for id in catalog:
		var modifiers: Array = catalog[id].modifiers
		harness.assert_equal(modifiers, expected_modifiers.get(id, []), "%s modifiers" % id)
		harness.assert_false(_contains_callable(modifiers), "%s modifiers must be static data" % id)


func _test_relic_atomic_validation(harness: TestHarness) -> void:
	var event_catalog := EventCatalogScript.build()
	var piece_classes := PieceClassCatalogScript.build()
	var valid := Relic.new("valid", "有效", "common", "有效。", [{
		"event": "battleStart", "condition_id": "", "effect_id": "effect.valid",
		"limit": "none", "limit_scope": "event", "limit_value": 1, "hook_index": 0,
		"condition_params": {}, "effect_params": {},
	}], [])
	var errors: Array[String] = []
	var invalid_event := valid.snapshot()
	invalid_event.id = "invalidEvent"
	invalid_event.hooks[0]["event"] = "missing"
	harness.assert_equal(RelicCatalogScript.build_from([
		valid, valid.snapshot(), invalid_event,
	], event_catalog, piece_classes, ["charge", "assault", "sacrifice"], errors), {})
	harness.assert_true(errors.size() >= 2)
	harness.assert_equal(valid.hooks[0]["event"], "battleStart", "failed build must not mutate source")

	errors.clear()
	var dangling_class := Relic.new("class", "非法", "common", "非法。", [], [{
		"type": "classMaxHpFlat", "handler_id": "relic.modifier.classMaxHpFlat",
		"side": "ally", "classId": "missing", "value": 1,
	}])
	harness.assert_equal(RelicCatalogScript.build_from([
		dangling_class,
	], event_catalog, piece_classes, ["charge", "assault", "sacrifice"], errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var executable_modifier := Relic.new("callable", "非法", "common", "非法。", [], [{
		"type": "skillPointMaxFlat", "handler_id": "relic.modifier.skillPointMaxFlat",
		"value": 1, "callback": func() -> void: pass,
	}])
	harness.assert_equal(RelicCatalogScript.build_from([
		executable_modifier,
	], event_catalog, piece_classes, ["charge", "assault", "sacrifice"], errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var dangling_shentong := Relic.new("shentong", "非法", "common", "非法。", [], [{
		"type": "shentongEnergyGain", "handler_id": "relic.modifier.shentongEnergyGain",
		"shentongId": "missing", "value": 1,
	}])
	harness.assert_equal(RelicCatalogScript.build_from([
		dangling_shentong,
	], event_catalog, piece_classes, ["charge", "assault", "sacrifice"], errors), {})
	harness.assert_true(not errors.is_empty())


func _test_roguelike_content(harness: TestHarness) -> void:
	var catalog: Dictionary = RoguelikeCatalogScript.build()
	harness.assert_equal(catalog["node_types"], ["battle", "elite", "boss", "forge", "shop", "event"])
	harness.assert_equal(catalog["chapters"].keys(), [1, 2, 3])
	harness.assert_equal(catalog["encounters"].size(), 13)
	harness.assert_true(catalog["encounters"].has("normal_vanguard"))
	harness.assert_true(catalog["encounters"].has("elite_devourer"))
	harness.assert_true(catalog["encounters"].has("boss_echo"))
	harness.assert_true(catalog["encounters"].has("elite_core"))
	for chapter: Resource in catalog["chapters"].values():
		var chapter_data: Dictionary = chapter.metadata
		var fresh_encounters: Array = chapter_data["battleEncounterIds"] + chapter_data["eliteEncounterIds"] + [chapter_data["bossEncounterId"]]
		harness.assert_false(fresh_encounters.any(func(id: String) -> bool:
			return id in ["normal", "elite_core", "boss_core"]
		))
	harness.assert_equal(catalog["shentongs"].keys(), ["charge", "assault", "sacrifice"])
	harness.assert_equal(catalog["relics"].size(), 22)
	harness.assert_equal(catalog["piece_classes"].size(), 5)
	harness.assert_equal(catalog["free_skills"].size(), 13)
	harness.assert_equal(catalog["enemy_specials"].size(), 2)
	var references_with_executable := _references_from_catalog(catalog)
	references_with_executable["free_skills"]["staticSkill"] = {
		"id": "staticSkill", "name": "静态技能", "cost": 1, "tip": "静态说明",
		"effect": func() -> void: pass,
	}
	var reference_errors: Array[String] = []
	var safe_reference_catalog: Dictionary = RoguelikeCatalogScript.build_from(
		_definitions_from_catalog(catalog), references_with_executable, reference_errors,
	)
	harness.assert_equal(reference_errors, [])
	harness.assert_equal(safe_reference_catalog["free_skills"]["staticSkill"], {
		"id": "staticSkill", "name": "静态技能", "cost": 1, "tip": "静态说明",
	})
	harness.assert_false(_contains_callable(safe_reference_catalog))
	var expected_columns := {
		1: [
			["battle", "battle", "battle"], ["battle", "shop", "battle"], ["battle", "battle", "shop"],
			["forge", "event", "shop"], ["event", "forge", "battle"], ["battle", "event", "forge"],
			["shop", "elite", "forge"], ["event", "elite", "battle"], ["battle", "event", "elite"],
			["boss", "boss", "boss"],
		],
		2: [
			["battle", "battle", "battle"], ["battle", "battle", "shop"], ["forge", "battle", "battle"],
			["forge", "event", "shop"], ["battle", "event", "forge"], ["elite", "battle", "event"],
			["shop", "elite", "forge"], ["battle", "event", "elite"], ["battle", "battle", "event"],
			["boss", "boss", "boss"],
		],
		3: [
			["battle", "battle", "battle"], ["forge", "battle", "battle"], ["event", "forge", "battle"],
			["forge", "event", "shop"], ["elite", "battle", "event"], ["event", "elite", "battle"],
			["shop", "elite", "forge"], ["battle", "battle", "event"], ["shop", "battle", "battle"],
			["boss", "boss", "boss"],
		],
	}
	for chapter_id in [1, 2, 3]:
		var data: Dictionary = catalog["chapters"][chapter_id].metadata
		harness.assert_equal([data["chapter"], data["rows"], data["columns"]], [chapter_id, 3, 10])
		harness.assert_equal(data["columnRules"].map(func(rule: Dictionary) -> Array: return rule["fixedByRow"]), expected_columns[chapter_id])
		harness.assert_equal(data["battleReward"], {"freeSkillCount": 3, "relicCount": 0, "currency": 15})
		harness.assert_true(data["battleEncounterIds"].size() >= 2)
		harness.assert_true(data["eliteEncounterIds"].size() >= 1)
		harness.assert_true(catalog["encounters"].has(data["bossEncounterId"]))
		harness.assert_equal(data["eliteReward"], {"freeSkillCount": 2, "relicCount": 1, "currency": 25})
		harness.assert_equal(data["bossReward"], {"freeSkillCount": 1, "relicCount": 2, "currency": 40})

	for encounter: Resource in catalog["encounters"].values():
		harness.assert_equal(encounter.metadata["slots"].size(), 6)
		for slot: Dictionary in encounter.metadata["slots"]:
			harness.assert_true(slot.has("occupiesSlots"))
	var devourer: Dictionary = catalog["encounters"]["elite_devourer"].metadata["slots"][0]
	var echo: Dictionary = catalog["encounters"]["elite_echo"].metadata["slots"][3]
	harness.assert_equal([devourer["specialId"], devourer["occupiesSlots"]], ["devourer", [1, 2]])
	harness.assert_equal([echo["specialId"], echo["occupiesSlots"]], ["echo", [4, 5, 6]])

	var shentong_rows := [
		["charge", "蓄势", "全体消耗本回合行动，回复存活棋子并延长敌方灼烧；本回合减伤，下一有效回合增伤。", "必须是本回合第一个玩家行动。", 1, "shentong.charge"],
		["assault", "突击", "选择可释放专属技的弈者免费施放，并强化该次伤害。", "需要至少一名上阵弈者当前可释放主动专属技。", 1, "shentong.assault"],
		["sacrifice", "献祭", "献祭生命比例最低的存活棋子，获得技能点并为随机上阵弈者回复能量。", "场上必须有可献祭的存活我方棋子。", 2, "shentong.sacrifice"],
	]
	for row in shentong_rows:
		var data: Dictionary = catalog["shentongs"][row[0]].metadata
		harness.assert_equal([data["id"], data["name"], data["description"], data["restriction"], data["usesPerBattle"], data["handler_id"]], row)
		harness.assert_false(_contains_callable(data))


func _test_roguelike_atomic_validation(harness: TestHarness) -> void:
	var valid_catalog: Dictionary = RoguelikeCatalogScript.build()
	var definitions := _definitions_from_catalog(valid_catalog)
	var references := _references_from_catalog(valid_catalog)
	var errors: Array[String] = []
	var reordered_definitions := definitions.duplicate()
	reordered_definitions.reverse()
	var reordered: Dictionary = RoguelikeCatalogScript.build_from(
		reordered_definitions, references, errors,
	)
	harness.assert_equal(errors, [])
	harness.assert_equal(reordered["chapters"].keys(), [1, 2, 3])
	harness.assert_equal(reordered["encounters"].keys(), valid_catalog["encounters"].keys())
	harness.assert_equal(reordered["shentongs"].keys(), ["charge", "assault", "sacrifice"])

	errors.clear()
	var duplicate: Variant = definitions[0].snapshot()
	harness.assert_equal(RoguelikeCatalogScript.build_from(definitions + [duplicate], references, errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var missing_chapter := definitions.filter(func(definition: Variant) -> bool:
		return definition.kind != "chapter" or definition.id != 3
	)
	harness.assert_equal(RoguelikeCatalogScript.build_from(missing_chapter, references, errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var missing_shentong := definitions.filter(func(definition: Variant) -> bool:
		return definition.kind != "shentong" or definition.id != "assault"
	)
	harness.assert_equal(RoguelikeCatalogScript.build_from(missing_shentong, references, errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var missing_encounter_definitions := _definitions_from_catalog(valid_catalog)
	missing_encounter_definitions[0].metadata["battleEncounterIds"] = ["missing"]
	harness.assert_equal(RoguelikeCatalogScript.build_from(missing_encounter_definitions, references, errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var bad_slots := _definitions_from_catalog(valid_catalog)
	for definition in bad_slots:
		if definition.kind == "encounter" and definition.id == "elite_devourer":
			definition.metadata["slots"][1]["unitId"] = 1
	harness.assert_equal(RoguelikeCatalogScript.build_from(bad_slots, references, errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var dangling_special := _definitions_from_catalog(valid_catalog)
	for definition in dangling_special:
		if definition.kind == "encounter" and definition.id == "elite_devourer":
			definition.metadata["slots"][0]["specialId"] = "missing"
	harness.assert_equal(RoguelikeCatalogScript.build_from(dangling_special, references, errors), {})
	harness.assert_true(not errors.is_empty())

	errors.clear()
	var bad_fixed_column := _definitions_from_catalog(valid_catalog)
	bad_fixed_column[0].metadata["columnRules"][9]["fixedByRow"][0] = "battle"
	harness.assert_equal(RoguelikeCatalogScript.build_from(bad_fixed_column, references, errors), {})
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(valid_catalog["chapters"][1].metadata["columnRules"][9]["fixedByRow"], ["boss", "boss", "boss"])


func _test_deep_snapshot_isolation(harness: TestHarness) -> void:
	var first_relics := RelicCatalogScript.build()
	var second_relics := RelicCatalogScript.build()
	first_relics["trueNameUnseal"].modifiers[0]["skillKinds"].append("mutated")
	first_relics["scorchShard"].hooks[0]["effect_id"] = "mutated"
	harness.assert_equal(second_relics["trueNameUnseal"].modifiers[0]["skillKinds"], ["freeSkill", "exclusive"])
	harness.assert_equal(second_relics["scorchShard"].hooks[0]["effect_id"], "relic.effect.apply_burn")

	var first_content: Dictionary = RoguelikeCatalogScript.build()
	var second_content: Dictionary = RoguelikeCatalogScript.build()
	first_content["node_types"].append("mutated")
	first_content["chapters"][1].metadata["columnRules"][0]["fixedByRow"][0] = "event"
	first_content["encounters"]["elite_devourer"].metadata["slots"][0]["className"] = "mutated"
	first_content["shentongs"]["charge"].metadata["handler_id"] = "mutated"
	first_content["relics"]["spLimitPlus"]["name"] = "mutated"
	harness.assert_equal(second_content["node_types"], ["battle", "elite", "boss", "forge", "shop", "event"])
	harness.assert_equal(second_content["chapters"][1].metadata["columnRules"][0]["fixedByRow"], ["battle", "battle", "battle"])
	harness.assert_equal(second_content["encounters"]["elite_devourer"].metadata["slots"][0]["className"], "噬元兽")
	harness.assert_equal(second_content["shentongs"]["charge"].metadata["handler_id"], "shentong.charge")
	harness.assert_equal(second_content["relics"]["spLimitPlus"]["name"], "01号遗物")

	var source_definitions := _definitions_from_catalog(second_content)
	var errors: Array[String] = []
	var built: Dictionary = RoguelikeCatalogScript.build_from(source_definitions, _references_from_catalog(second_content), errors)
	source_definitions[0].metadata["battleReward"]["currency"] = 999
	harness.assert_equal(errors, [])
	harness.assert_equal(built["chapters"][1].metadata["battleReward"]["currency"], 15)


func _definitions_from_catalog(catalog: Dictionary) -> Array:
	var result: Array = []
	for group in ["chapters", "encounters", "shentongs"]:
		for definition in catalog[group].values():
			result.append(definition.snapshot())
	return result


func _references_from_catalog(catalog: Dictionary) -> Dictionary:
	return {
		"free_skills": catalog["free_skills"].duplicate(true),
		"relics": catalog["relics"].duplicate(true),
		"piece_classes": catalog["piece_classes"].duplicate(true),
		"enemy_specials": catalog["enemy_specials"].duplicate(true),
	}


func _contains_callable(value: Variant) -> bool:
	if value is Callable:
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
