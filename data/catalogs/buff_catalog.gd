class_name BuffCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const Buff = preload("res://data/definitions/buff_definition.gd")
const TuningValue = preload("res://data/definitions/tuning_value_definition.gd")

const SCOPE_UNIT := "unit"
const SCOPE_SIDE := "side"
const PERSISTENCE_BATTLE := "battle"
const PERSISTENCE_PERMANENT := "permanent"
const TARGET_PIECE_SLOT := "pieceSlot"
const TARGET_HERO := "hero"


static func build(tuning: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(tuning), errors)


static func build_from(definitions: Array, errors: Array[String]) -> Dictionary:
	errors.clear()
	var seen := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != Buff:
			errors.append("buff entries must be BuffDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.non_empty_id(definition.id, "buff", errors):
			Validation.unique_id(definition.id, seen, "buff", errors)
		Validation.non_empty_string(definition.name, "buff name", errors)
		Validation.non_empty_string(definition.description, "buff description", errors)
		Validation.enum_value(
			definition.persistence,
			[PERSISTENCE_BATTLE, PERSISTENCE_PERMANENT],
			"buff persistence",
			errors,
		)
		Validation.non_negative_int(definition.max_stacks, "buff maxStacks", errors)
		Validation.non_negative_int(definition.default_duration, "buff defaultDuration", errors)
		if definition.persistence == PERSISTENCE_BATTLE:
			Validation.enum_value(
				definition.scope,
				[SCOPE_UNIT, SCOPE_SIDE],
				"battle buff scope",
				errors,
			)
			if not definition.target_types.is_empty():
				errors.append("battle buff targetTypes must be empty")
		elif definition.persistence == PERSISTENCE_PERMANENT:
			if definition.scope != null:
				errors.append("permanent buff scope must be null")
			Validation.string_array(definition.target_types, "permanent buff targetTypes", errors, false)
			var seen_target_types := {}
			for target_type in definition.target_types:
				Validation.enum_value(
					target_type,
					[TARGET_PIECE_SLOT, TARGET_HERO],
					"permanent buff target type",
					errors,
				)
				Validation.unique_id(target_type, seen_target_types, "permanent buff target type", errors)
	if not errors.is_empty():
		return {}

	var catalog := {}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.id] = definition.snapshot()
	return catalog


static func _source_definitions(tuning: Dictionary) -> Array:
	var burn_duration: int = max(1, _tuning_int(tuning, "burnBaseDuration", 2))
	var enchant_cap: int = max(1, _tuning_int(tuning, "enchantStackCap", 5))
	var march_duration: int = max(1, _tuning_int(tuning, "ultAscendMarchTurns", 2))
	var flame_leech_duration: int = max(1, _tuning_int(tuning, "ultFlameLeechTurns", 2))
	var break_formation_duration: int = max(1, _tuning_int(tuning, "ultBreakFormationTurns", 2))
	return [
		Buff.new("burn", "灼烧", SCOPE_UNIT, true, true, 0, burn_duration, true, false, "回合结算时每层造成持续伤害。"),
		Buff.new("enchant", "附魔", SCOPE_UNIT, false, true, enchant_cap, 0, false, false, "攻击命中后按层数施加灼烧。"),
		Buff.new("knightChivalry", "骑士道", SCOPE_UNIT, false, true, 0, 0, false, false, "下一次反击强化。"),
		Buff.new("march", "出征", SCOPE_UNIT, false, false, 1, march_duration, false, true, "将军攻击同列目标并必定暴击。"),
		Buff.new("stealth", "潜行", SCOPE_UNIT, false, false, 1, 1, false, true, "暂时不被常规锁定，下一次攻击改为锁定低生命目标。"),
		Buff.new("vexed", "困扰", SCOPE_UNIT, true, false, 1, 1, false, true, "造成伤害降低。"),
		Buff.new("breakMarked", "破势", SCOPE_UNIT, true, false, 1, 0, false, false, "受到伤害提高，破阵领域中额外提高受暴击率。"),
		Buff.new("tempBlock", "临时格挡", SCOPE_SIDE, false, false, 1, 1, false, true, "全体格挡率临时提高。"),
		Buff.new("pieceDamageUp", "棋子增伤", SCOPE_SIDE, false, false, 1, 1, false, true, "棋子直接伤害提高。"),
		Buff.new("bloodShiftVulnerable", "血移易伤", SCOPE_UNIT, true, false, 1, 1, false, true, "受到伤害提高。"),
		Buff.new("bloodShiftGuard", "血移庇护", SCOPE_UNIT, false, false, 1, 1, false, true, "受到伤害降低。"),
		Buff.new("flameLeech", "炎汲", SCOPE_SIDE, false, false, 1, flame_leech_duration, false, true, "灼烧目标攻击本方时触发治疗。"),
		Buff.new("breakFormation", "破阵领域", SCOPE_SIDE, false, false, 1, break_formation_duration, false, true, "本方对敌方伤害提高，并强化破势目标受暴击率。"),
		Buff.new("pursuit", "追击", SCOPE_UNIT, false, true, 0, 0, false, false, "下一次棋子行动后追加一次追击。"),
		Buff.new("flamePractice", "炎华修习", null, false, true, 0, 0, false, false, "记录炎术士在本轮 Run 中完成的永久投资次数。", PERSISTENCE_PERMANENT, [TARGET_HERO]),
		Buff.new("flameEnchant", "引火", null, false, true, 0, 0, false, false, "记录棋子位置获得的引火层数。", PERSISTENCE_PERMANENT, [TARGET_PIECE_SLOT]),
		Buff.new("marshalPromotion", "元帅晋升", null, false, true, 0, 0, false, false, "记录棋子位置获得的元帅永久成长层数。", PERSISTENCE_PERMANENT, [TARGET_PIECE_SLOT]),
		Buff.new("fistMastery", "永久拳意", null, false, true, 0, 0, false, false, "每层使拳劲与大招伤害+5%；每5层使大招基础段数+1。", PERSISTENCE_PERMANENT, [TARGET_HERO]),
	]


static func _tuning_int(tuning: Dictionary, id: String, fallback: int) -> int:
	var definition: Variant = tuning.get(id)
	if definition is Resource and definition.get_script() == TuningValue and typeof(definition.value) in [TYPE_INT, TYPE_FLOAT]:
		return int(definition.value)
	return fallback
