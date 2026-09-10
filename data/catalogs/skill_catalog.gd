class_name SkillCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const Skill = preload("res://data/definitions/skill_definition.gd")

const CONDITION_IDS := "condition_ids"
const TARGETING_IDS := "targeting_ids"
const EFFECT_IDS := "effect_ids"


static func build() -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(), reference_ids(), errors)


static func reference_ids() -> Dictionary:
	var conditions: Array[String] = []
	var targetings: Array[String] = []
	var effects: Array[String] = []
	for id in _source_ids():
		conditions.append("free_skill.%s.condition" % id)
		targetings.append("free_skill.%s.targeting" % id)
		effects.append("free_skill.%s.effect" % id)
	return {
		CONDITION_IDS: conditions,
		TARGETING_IDS: targetings,
		EFFECT_IDS: effects,
	}


static func build_from(
	definitions: Array,
	references: Dictionary,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	_validate_reference_registry(references, errors)
	var seen := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != Skill:
			errors.append("free skill entries must be SkillDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.non_empty_id(definition.id, "free skill", errors):
			Validation.unique_id(definition.id, seen, "free skill", errors)
		Validation.non_empty_string(definition.name, "free skill name", errors)
		Validation.non_empty_string(definition.tip, "free skill tip", errors)
		_validate_reference(definition.condition_id, references.get(CONDITION_IDS, []), "condition", errors)
		_validate_reference(definition.targeting_id, references.get(TARGETING_IDS, []), "targeting", errors)
		_validate_reference(definition.effect_id, references.get(EFFECT_IDS, []), "effect", errors)
		Validation.non_negative_int(definition.base_sp_cost, "free skill base SP cost", errors)
	if not errors.is_empty():
		return {}

	var catalog := {}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.id] = definition.snapshot()
	return catalog


static func _validate_reference_registry(references: Dictionary, errors: Array[String]) -> void:
	for key in [CONDITION_IDS, TARGETING_IDS, EFFECT_IDS]:
		if not references.has(key) or typeof(references[key]) != TYPE_ARRAY:
			errors.append("free skill reference registry is missing array: %s" % key)
			continue
		Validation.string_array(references[key], "free skill %s" % key, errors)
		var seen := {}
		for reference_id in references[key]:
			Validation.unique_id(reference_id, seen, "free skill %s" % key, errors)


static func _validate_reference(
	reference_id: String,
	known_ids: Array,
	reference_type: String,
	errors: Array[String],
) -> void:
	if not Validation.non_empty_id(reference_id, "free skill %s" % reference_type, errors):
		return
	if reference_id not in known_ids:
		errors.append("free skill references unknown %s: %s" % [reference_type, reference_id])


static func _source_ids() -> Array[String]:
	return [
		"burnStackBase",
		"burnDetonate",
		"executeStrike",
		"pieceAction",
		"pieceBlock",
		"pieceDamageUp",
		"pieceHealAll",
		"smallHeal",
		"markBurn",
		"bloodShift",
		"spSurge",
		"tacticalDraw",
		"basicDamage",
	]


static func _source_definitions() -> Array:
	return [
		Skill.new("burnStackBase", "基础叠层", "消耗1技能点。敌方全体100%施加1层灼烧；每个单位有概率额外+1层。", "free_skill.burnStackBase.condition", "free_skill.burnStackBase.targeting", "free_skill.burnStackBase.effect", 1),
		Skill.new("burnDetonate", "灼烧引爆", "消耗2技能点。引爆灼烧层数最高敌人：每层造成固定伤害并清空其灼烧；若引爆击杀，则将原灼烧层平均分给其余敌人。", "free_skill.burnDetonate.condition", "free_skill.burnDetonate.targeting", "free_skill.burnDetonate.effect", 2),
		Skill.new("executeStrike", "斩杀", "消耗2技能点。指定一个可锁定敌方目标，由我方攻击力最高的棋子立即造成150%直接伤害；若击杀，回复1点技能点。", "free_skill.executeStrike.condition", "free_skill.executeStrike.targeting", "free_skill.executeStrike.effect", 2),
		Skill.new("pieceAction", "棋子行动", "消耗1技能点。指定我方弈子获得下回合额外行动1次（普通Buff，可叠加）。", "free_skill.pieceAction.condition", "free_skill.pieceAction.targeting", "free_skill.pieceAction.effect", 1),
		Skill.new("pieceBlock", "棋子格挡", "消耗1技能点。全体我方棋子获得15%临时格挡率，持续1回合。", "free_skill.pieceBlock.condition", "free_skill.pieceBlock.targeting", "free_skill.pieceBlock.effect", 1),
		Skill.new("pieceDamageUp", "棋子增伤", "消耗1技能点。全体我方棋子直接伤害+25%，持续1回合。", "free_skill.pieceDamageUp.condition", "free_skill.pieceDamageUp.targeting", "free_skill.pieceDamageUp.effect", 1),
		Skill.new("pieceHealAll", "棋子回血", "消耗1技能点。为我方全体棋子回复5%生命上限。", "free_skill.pieceHealAll.condition", "free_skill.pieceHealAll.targeting", "free_skill.pieceHealAll.effect", 1),
		Skill.new("smallHeal", "小回血", "消耗0技能点。为我方当前血量最低棋子回复5%生命上限。", "free_skill.smallHeal.condition", "free_skill.smallHeal.targeting", "free_skill.smallHeal.effect", 0),
		Skill.new("markBurn", "灼痕标记", "消耗0技能点。对敌方灼烧层数最高单位施加1层灼烧。", "free_skill.markBurn.condition", "free_skill.markBurn.targeting", "free_skill.markBurn.effect", 0),
		Skill.new("bloodShift", "血移", "我方血量最高棋子额外受伤，其他棋子获得免伤。", "free_skill.bloodShift.condition", "free_skill.bloodShift.targeting", "free_skill.bloodShift.effect", 1),
		Skill.new("spSurge", "回气", "消耗1技能点，本场消耗。回复2技能点；回复可以在本回合超过技能点上限。", "free_skill.spSurge.condition", "free_skill.spSurge.targeting", "free_skill.spSurge.effect", 1),
		Skill.new("tacticalDraw", "筹策", "消耗1技能点，本场消耗。抽2张牌。", "free_skill.tacticalDraw.condition", "free_skill.tacticalDraw.targeting", "free_skill.tacticalDraw.effect", 1),
		Skill.new("basicDamage", "基础伤害", "对敌方单体造成 200% 伤害。", "free_skill.basicDamage.condition", "free_skill.basicDamage.targeting", "free_skill.basicDamage.effect", 1),
	]
