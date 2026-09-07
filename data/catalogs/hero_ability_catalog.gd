class_name HeroAbilityCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const Ability = preload("res://data/definitions/hero_ability_definition.gd")
const PlayerCharacter = preload("res://data/definitions/player_character_definition.gd")

const EXCLUSIVE := "exclusive"
const ULTIMATE := "ultimate"
const CONDITION_IDS := "condition_ids"
const HANDLER_IDS := "handler_ids"


static func build(player_catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(), player_catalog, reference_ids(), errors)


static func reference_ids() -> Dictionary:
	var conditions: Array[String] = []
	var handlers: Array[String] = []
	for id in _source_ids():
		conditions.append("battle.canCastExclusiveSkill.%s" % id)
		handlers.append("battle.castExclusiveSkill.%s" % id)
		conditions.append("battle.canHeroCastUltimate.%s" % id)
		handlers.append("battle.castUltimateByHero.%s" % id)
	return {CONDITION_IDS: conditions, HANDLER_IDS: handlers}


static func build_from(
	definitions: Array,
	player_catalog: Dictionary,
	references: Dictionary,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	_validate_player_catalog(player_catalog, errors)
	_validate_reference_registry(references, errors)
	var seen_keys := {}
	var seen_owners := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != Ability:
			errors.append("hero ability entries must be HeroAbilityDefinition resources")
			continue
		var definition: Variant = raw_definition
		var id_valid := Validation.non_empty_id(definition.id, "hero ability", errors)
		var type_valid := Validation.enum_value(definition.ability_type, [EXCLUSIVE, ULTIMATE], "hero ability type", errors)
		if id_valid and type_valid:
			Validation.unique_id("%s:%s" % [definition.ability_type, definition.id], seen_keys, "hero ability", errors)
			Validation.unique_id("%s:%d" % [definition.ability_type, definition.owner_hero_id], seen_owners, "hero ability owner/type", errors)
		Validation.positive_int_id(definition.owner_hero_id, "hero ability owner", errors)
		Validation.non_empty_string(definition.name, "hero ability name", errors)
		Validation.non_empty_string(definition.tip, "hero ability tip", errors)
		_validate_reference(definition.condition_id, references.get(CONDITION_IDS, []), "condition", errors)
		_validate_reference(definition.handler_id, references.get(HANDLER_IDS, []), "handler", errors)
		Validation.non_negative_int(definition.base_sp_cost, "hero ability base SP cost", errors)
		_validate_source_metadata(definition, errors)
		_validate_owner_reference(definition, player_catalog, errors)
	_validate_complete_coverage(player_catalog, seen_owners, errors)
	if not errors.is_empty():
		return {}

	var catalog := {EXCLUSIVE: {}, ULTIMATE: {}}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.ability_type][definition.id] = definition.snapshot()
	return catalog


static func _validate_player_catalog(player_catalog: Dictionary, errors: Array[String]) -> void:
	if player_catalog.is_empty():
		errors.append("hero ability player catalog must not be empty")
		return
	for raw_id in player_catalog:
		var player: Variant = player_catalog[raw_id]
		if not player is Resource or player.get_script() != PlayerCharacter:
			errors.append("hero ability player references must be PlayerCharacterDefinition resources")
		elif raw_id != player.id:
			errors.append("hero ability player catalog key does not match player id: %s" % str(raw_id))


static func _validate_reference_registry(references: Dictionary, errors: Array[String]) -> void:
	for key in [CONDITION_IDS, HANDLER_IDS]:
		if not references.has(key) or typeof(references[key]) != TYPE_ARRAY:
			errors.append("hero ability reference registry is missing array: %s" % key)
			continue
		Validation.string_array(references[key], "hero ability %s" % key, errors)
		var seen := {}
		for reference_id in references[key]:
			Validation.unique_id(reference_id, seen, "hero ability %s" % key, errors)


static func _validate_reference(reference_id: String, known_ids: Array, label: String, errors: Array[String]) -> void:
	if not Validation.non_empty_id(reference_id, "hero ability %s" % label, errors):
		return
	if reference_id not in known_ids:
		errors.append("hero ability references unknown %s: %s" % [label, reference_id])


static func _validate_source_metadata(definition: Variant, errors: Array[String]) -> void:
	if definition.ability_type == EXCLUSIVE:
		if definition.source_energy_requirement != 0:
			errors.append("exclusive ability source energy requirement must be zero")
		return
	if definition.base_sp_cost != 0:
		errors.append("ultimate ability base SP cost must be zero")
	Validation.positive_int(definition.source_energy_requirement, "ultimate source energy requirement", errors)
	if definition.is_passive:
		errors.append("ultimate ability must not be passive")


static func _validate_owner_reference(definition: Variant, player_catalog: Dictionary, errors: Array[String]) -> void:
	if not player_catalog.has(definition.owner_hero_id):
		errors.append("hero ability references unknown owner: %d" % definition.owner_hero_id)
		return
	var player: Variant = player_catalog[definition.owner_hero_id]
	if player is Resource and player.get_script() == PlayerCharacter and player.exclusive_skill_id != definition.id:
		errors.append("hero ability %s does not match owner %d exSkill" % [definition.id, definition.owner_hero_id])


static func _validate_complete_coverage(
	player_catalog: Dictionary,
	seen_owners: Dictionary,
	errors: Array[String],
) -> void:
	for raw_id in player_catalog:
		if typeof(raw_id) != TYPE_INT:
			continue
		for ability_type in [EXCLUSIVE, ULTIMATE]:
			var key := "%s:%d" % [ability_type, raw_id]
			if not seen_owners.has(key):
				errors.append("hero %d is missing %s ability metadata" % [raw_id, ability_type])


static func _source_ids() -> Array[String]:
	return ["burn01", "fate", "ascend", "counterAura", "burnEnchant", "fist", "siege", "puppet", "shadow"]


static func _source_definitions() -> Array:
	return [
		Ability.new("burn01", 1, EXCLUSIVE, "蔓炎", "第1/2/3/4次释放消耗1/2/4/8技能点。使已有灼烧层数翻倍并持续+2回合。", "battle.canCastExclusiveSkill.burn01", "battle.castExclusiveSkill.burn01", false, 0, 1),
		Ability.new("fate", 2, EXCLUSIVE, "命运", "消耗1技能点。激活命运结界（每场仅可释放一次），每回合在「棋子命运/技能命运/混沌命运」中随机切换。技能命运每回合最多通过该效果回复3点技能点；混沌命运自然触发每场最多1次。", "battle.canCastExclusiveSkill.fate", "battle.castExclusiveSkill.fate", false, 0, 1),
		Ability.new("ascend", 3, EXCLUSIVE, "封命", "消耗2技能点。优先令局外配置的目标位棋子升变为将军（攻击+0、生命上限+80、格挡率+10%、暴击率+5%；若该位置不可用，则回退为存活棋子中序号最小者）。若已存在将军，重复释放使将军攻击+1.5、格挡率+1.5%、暴击率+1.5%，并回复5%已损生命。有我方单位阵亡时，将军获得同层属性成长（不回血）。", "battle.canCastExclusiveSkill.ascend", "battle.castExclusiveSkill.ascend", false, 0, 2),
		Ability.new("counterAura", 4, EXCLUSIVE, "反击", "被动：骑士上阵时我方棋子格挡率+10%。棋子受伤若格挡成功则触发小反击（40%攻击）；若技能点>x（默认4），则消耗1技能点将其升级为超级反击（200%攻击），并使骑士获得5能量。", "battle.canCastExclusiveSkill.counterAura", "battle.castExclusiveSkill.counterAura", true, 0, 0),
		Ability.new("burnEnchant", 5, EXCLUSIVE, "炎华", "肉鸽战斗中每场最多投资一次：基础消耗按炎华修习层数为2/3/4技能点，存活非傀儡位置获得引火并立即生效；普通战斗仍消耗2点并施加战斗附魔。", "battle.canCastExclusiveSkill.burnEnchant", "battle.castExclusiveSkill.burnEnchant", false, 0, 2),
		Ability.new("fist", 6, EXCLUSIVE, "拳劲", "消耗1技能点。造成基于我方棋子平均攻击的直接伤害并叠加拳势（最多5层）。拳势提升直接伤害与暴击率；2/4层时额外攻击1/2个目标。肉鸽中每次成功释放积累1层永久拳意，每层使拳劲与大招伤害+5%。", "battle.canCastExclusiveSkill.fist", "battle.castExclusiveSkill.fist", false, 0, 1),
		Ability.new("siege", 7, EXCLUSIVE, "破势", "消耗1技能点。对单体造成基于我方棋子平均攻击的直接伤害并施加破势（不可叠加，受直接伤害提高）。优先攻击未被破势的目标。", "battle.canCastExclusiveSkill.siege", "battle.castExclusiveSkill.siege", false, 0, 1),
		Ability.new("puppet", 8, EXCLUSIVE, "机巧造物", "消耗1技能点。在我方空位召唤傀儡（固定100生命，攻击0，视为棋子目标；不吃任何生命上限加成）。", "battle.canCastExclusiveSkill.puppet", "battle.castExclusiveSkill.puppet", false, 0, 1),
		Ability.new("shadow", 9, EXCLUSIVE, "潜影", "消耗1技能点（迅捷：不消耗弈者决策次数）。使我方未处于潜行的非傀儡棋子中攻击最高者进入潜行1回合。场上最多同时存在 n-1 个潜行棋子（n为非傀儡存活棋子数），傀儡不会被施加潜行。潜行棋子不可被敌方单体技能锁定，且下一次普攻会无视站位优先攻击敌方生命值最低单位。", "battle.canCastExclusiveSkill.shadow", "battle.castExclusiveSkill.shadow", false, 0, 1),
		Ability.new("burn01", 1, ULTIMATE, "焚界爆炎", "消耗100能量。对敌方全体造成直接伤害，基础值为己方棋子平均攻击*目标灼烧层数*系数。", "battle.canHeroCastUltimate.burn01", "battle.castUltimateByHero.burn01", false, 100),
		Ability.new("fate", 2, ULTIMATE, "众命同轨", "消耗120能量。1回合内同时生效所有命运（含混沌命运），并剔除对己方的约束效果。", "battle.canHeroCastUltimate.fate", "battle.castUltimateByHero.fate", false, 120),
		Ability.new("ascend", 3, ULTIMATE, "将军出征", "消耗100能量。将军回复已损生命值50%，并获得出征2回合：攻击一列且必定暴击。", "battle.canHeroCastUltimate.ascend", "battle.castUltimateByHero.ascend", false, 100),
		Ability.new("counterAura", 4, ULTIMATE, "骑士道誓", "消耗100能量。全体我方棋子获得1层骑士道：下次受到伤害时直接触发超级反击且不耗技能点，该次反击伤害+25%，触发后移除。", "battle.canHeroCastUltimate.counterAura", "battle.castUltimateByHero.counterAura", false, 100),
		Ability.new("burnEnchant", 5, ULTIMATE, "炎汲仪式", "消耗100能量。全体我方获得炎汲2回合：被带灼烧的敌方攻击时，按目标灼烧层数×0.3%自身已损生命回复。", "battle.canHeroCastUltimate.burnEnchant", "battle.castUltimateByHero.burnEnchant", false, 100),
		Ability.new("fist", 6, ULTIMATE, "拳意·无量", "消耗100能量。随机目标连续打击3段，每层拳势额外+1段，每5层永久拳意使基础段数+1；永久拳意每层使伤害+5%。击杀时追加2段并自动转火，拳势不清空。", "battle.canHeroCastUltimate.fist", "battle.castUltimateByHero.fist", false, 100),
		Ability.new("siege", 7, ULTIMATE, "摧城令", "消耗100能量。展开破阵领域2回合：敌方棋子受直接伤害提高20%，攻击带破势目标时暴击率+20%。", "battle.canHeroCastUltimate.siege", "battle.castUltimateByHero.siege", false, 100),
		Ability.new("puppet", 8, ULTIMATE, "森罗万象", "消耗120能量。所有空位召唤傀儡并将傀儡生命回满至100，同时赋予傀儡殉道：被击杀时自爆并施加困扰。", "battle.canHeroCastUltimate.puppet", "battle.castUltimateByHero.puppet", false, 120),
		Ability.new("shadow", 9, ULTIMATE, "影·狩", "消耗100能量。优先锁定敌方当前生命百分比最低单位（同百分比时取当前生命更低者，再同则取序号更小者），造成400%伤害；若其血量低于50%则必定暴击。随后所有潜行棋子立刻对该目标发动一次50%追击。", "battle.canHeroCastUltimate.shadow", "battle.castUltimateByHero.shadow", false, 100),
	]
