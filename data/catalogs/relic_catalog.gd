class_name RelicCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const Relic = preload("res://data/definitions/relic_definition.gd")
const EventCatalogScript = preload("res://data/catalogs/event_catalog.gd")
const PieceClassCatalogScript = preload("res://data/catalogs/piece_class_catalog.gd")

const CATEGORY_COMMON := "common"
const CATEGORY_ELITE := "elite"
const CATEGORY_BOSS := "boss"
const CATEGORY_CLASS_UPGRADE := "classUpgrade"
const CATEGORY_SHENTONG_EVOLVE := "shentongEvolve"

const LIMIT_NONE := "none"
const LIMIT_PER_BATTLE := "perBattle"
const LIMIT_PER_ROUND := "perRound"
const LIMIT_ONCE_PER_RUN := "oncePerRun"
const LIMIT_FIRST_N_ROUNDS_PER_BATTLE := "firstNRoundsPerBattle"

const SCOPE_EVENT := "event"
const SCOPE_ACTOR := "actor"
const SCOPE_TARGET := "target"

const SHENTONG_IDS := ["charge", "assault", "sacrifice"]
const MODIFIER_TYPES := [
	"skillPointMaxFlat",
	"skillPointCostOverride",
	"canSellFreeSkills",
	"currencyCostMultiplier",
	"healingReceivedMultiplier",
	"classMaxHpFlat",
	"pursuitChanceFlat",
	"critRateFlatBelowHp",
	"shentongDamageMultiplier",
	"shentongEnergyGain",
]


static func build() -> Dictionary:
	var errors: Array[String] = []
	return build_from(
		_source_definitions(),
		EventCatalogScript.build(),
		PieceClassCatalogScript.build(),
		SHENTONG_IDS,
		errors,
	)


static func build_from(
	definitions: Array,
	event_catalog: Dictionary,
	piece_class_catalog: Dictionary,
	shentong_ids: Array,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	var seen := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != Relic:
			errors.append("relic entries must be RelicDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.non_empty_id(definition.id, "relic", errors):
			Validation.unique_id(definition.id, seen, "relic", errors)
		Validation.non_empty_string(definition.name, "relic name", errors)
		Validation.non_empty_string(definition.description, "relic description", errors)
		Validation.enum_value(definition.category, [
			CATEGORY_COMMON,
			CATEGORY_ELITE,
			CATEGORY_BOSS,
			CATEGORY_CLASS_UPGRADE,
			CATEGORY_SHENTONG_EVOLVE,
		], "relic category", errors)
		_validate_hooks(definition, event_catalog, errors)
		_validate_modifiers(definition, piece_class_catalog, shentong_ids, errors)
	if not errors.is_empty():
		return {}

	var catalog := {}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.id] = definition.snapshot()
	return catalog


static func ids(catalog: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in catalog:
		result.append(id)
	return result


static func _validate_hooks(
	definition: Variant,
	event_catalog: Dictionary,
	errors: Array[String],
) -> void:
	for hook_index in definition.hooks.size():
		var hook: Variant = definition.hooks[hook_index]
		var path := "relic %s hook %d" % [definition.id, hook_index]
		if typeof(hook) != TYPE_DICTIONARY:
			errors.append("%s must be a dictionary" % path)
			continue
		_validate_exact_keys(hook, [
			"event", "condition_id", "effect_id", "limit",
			"limit_scope", "limit_value", "hook_index", "condition_params", "effect_params",
		], path, errors)
		var event: Variant = hook.get("event")
		if typeof(event) != TYPE_STRING or not event_catalog.has(event):
			errors.append("%s references unknown event: %s" % [path, str(event)])
		var condition_id: Variant = hook.get("condition_id")
		if typeof(condition_id) != TYPE_STRING:
			errors.append("%s condition_id must be a string" % path)
		var effect_id: Variant = hook.get("effect_id")
		if typeof(effect_id) != TYPE_STRING or str(effect_id).strip_edges().is_empty():
			errors.append("%s effect_id must be a non-empty string" % path)
		for params_field in ["condition_params", "effect_params"]:
			var params: Variant = hook.get(params_field)
			if typeof(params) != TYPE_DICTIONARY:
				errors.append("%s %s must be a dictionary" % [path, params_field])
			elif _contains_runtime_value(params):
				errors.append("%s %s must contain static data only" % [path, params_field])
		Validation.enum_value(hook.get("limit"), [
			LIMIT_NONE,
			LIMIT_PER_BATTLE,
			LIMIT_PER_ROUND,
			LIMIT_ONCE_PER_RUN,
			LIMIT_FIRST_N_ROUNDS_PER_BATTLE,
		], "%s limit" % path, errors)
		Validation.enum_value(hook.get("limit_scope"), [
			SCOPE_EVENT, SCOPE_ACTOR, SCOPE_TARGET,
		], "%s limit_scope" % path, errors)
		Validation.positive_int(hook.get("limit_value"), "%s limit_value" % path, errors)
		if hook.get("hook_index") != hook_index:
			errors.append("%s hook_index must equal %d" % [path, hook_index])


static func _validate_modifiers(
	definition: Variant,
	piece_class_catalog: Dictionary,
	shentong_ids: Array,
	errors: Array[String],
) -> void:
	for modifier_index in definition.modifiers.size():
		var modifier: Variant = definition.modifiers[modifier_index]
		var path := "relic %s modifier %d" % [definition.id, modifier_index]
		if typeof(modifier) != TYPE_DICTIONARY:
			errors.append("%s must be a dictionary" % path)
			continue
		if _contains_runtime_value(modifier):
			errors.append("%s must contain static data only" % path)
		var modifier_type: Variant = modifier.get("type")
		Validation.enum_value(modifier_type, MODIFIER_TYPES, "%s type" % path, errors)
		if modifier_type in MODIFIER_TYPES:
			_validate_modifier_shape(modifier, modifier_type, path, errors)
		var handler_id: Variant = modifier.get("handler_id")
		if handler_id != "relic.modifier.%s" % str(modifier_type):
			errors.append("%s handler_id must match its modifier type" % path)
		if modifier.has("classId"):
			var class_id: Variant = modifier["classId"]
			if typeof(class_id) != TYPE_STRING or not piece_class_catalog.has(class_id):
				errors.append("%s references unknown piece class: %s" % [path, str(class_id)])
		if modifier.has("shentongId"):
			var shentong_id: Variant = modifier["shentongId"]
			if typeof(shentong_id) != TYPE_STRING or shentong_id not in shentong_ids:
				errors.append("%s references unknown shentong: %s" % [path, str(shentong_id)])
		if modifier.has("skillKinds"):
			var skill_kinds: Variant = modifier["skillKinds"]
			if typeof(skill_kinds) != TYPE_ARRAY:
				errors.append("%s skillKinds must be an array" % path)
			else:
				Validation.string_array(skill_kinds, "%s skillKinds" % path, errors, false)
				for skill_kind in skill_kinds:
					Validation.enum_value(skill_kind, ["freeSkill", "exclusive"], "%s skill kind" % path, errors)
		if not modifier.has("value"):
			errors.append("%s value is required" % path)
		elif typeof(modifier["value"]) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
			errors.append("%s value must be a bool or finite number" % path)
		elif typeof(modifier["value"]) != TYPE_BOOL:
			Validation.finite_number(modifier["value"], "%s value" % path, errors)


static func _validate_modifier_shape(
	modifier: Dictionary,
	modifier_type: String,
	path: String,
	errors: Array[String],
) -> void:
	var allowed := ["type", "handler_id", "value"]
	match modifier_type:
		"skillPointCostOverride":
			allowed.append_array(["side", "skillKinds", "maxRound"])
			_validate_side(modifier.get("side"), path, errors)
			Validation.positive_int(modifier.get("maxRound"), "%s maxRound" % path, errors)
		"healingReceivedMultiplier":
			allowed.append("side")
			_validate_side(modifier.get("side"), path, errors)
		"classMaxHpFlat", "pursuitChanceFlat":
			allowed.append_array(["side", "classId"])
			_validate_side(modifier.get("side"), path, errors)
		"critRateFlatBelowHp":
			allowed.append_array(["side", "classId", "hpRatio"])
			_validate_side(modifier.get("side"), path, errors)
			_validate_unit_ratio(modifier.get("hpRatio"), "%s hpRatio" % path, errors)
		"shentongDamageMultiplier", "shentongEnergyGain":
			allowed.append("shentongId")
	_validate_exact_keys(modifier, allowed, path, errors)
	if modifier_type == "canSellFreeSkills" and typeof(modifier.get("value")) != TYPE_BOOL:
		errors.append("%s value must be a bool" % path)
	elif modifier_type != "canSellFreeSkills" and typeof(modifier.get("value")) == TYPE_BOOL:
		errors.append("%s value must be a finite number" % path)
	if modifier_type in ["currencyCostMultiplier", "healingReceivedMultiplier", "pursuitChanceFlat"]:
		_validate_unit_ratio(modifier.get("value"), "%s value" % path, errors)


static func _validate_side(value: Variant, path: String, errors: Array[String]) -> void:
	Validation.enum_value(value, ["ally", "enemy"], "%s side" % path, errors)


static func _validate_unit_ratio(value: Variant, path: String, errors: Array[String]) -> void:
	if not Validation.non_negative_number(value, path, errors):
		return
	if value > 1.0:
		errors.append("%s must not exceed 1" % path)


static func _validate_exact_keys(
	value: Dictionary,
	allowed_keys: Array,
	path: String,
	errors: Array[String],
) -> void:
	for key in allowed_keys:
		if not value.has(key):
			errors.append("%s is missing field %s" % [path, key])
	for key in value:
		if key not in allowed_keys:
			errors.append("%s has unknown field %s" % [path, str(key)])


static func _contains_runtime_value(value: Variant) -> bool:
	if value is Callable or value is Object:
		return true
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if _contains_runtime_value(item):
				return true
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if _contains_runtime_value(key) or _contains_runtime_value(value[key]):
				return true
	return false


static func _hook(
	event: String,
	condition_id: String,
	effect_id: String,
	limit: String = LIMIT_NONE,
	limit_scope: String = SCOPE_EVENT,
	limit_value: int = 1,
	hook_index: int = 0,
	condition_params: Dictionary = {},
	effect_params: Dictionary = {},
) -> Dictionary:
	return {
		"event": event,
		"condition_id": condition_id,
		"effect_id": effect_id,
		"limit": limit,
		"limit_scope": limit_scope,
		"limit_value": limit_value,
		"hook_index": hook_index,
		"condition_params": condition_params.duplicate(true),
		"effect_params": effect_params.duplicate(true),
	}


static func _modifier(type: String, fields: Dictionary) -> Dictionary:
	var result := fields.duplicate(true)
	result["type"] = type
	result["handler_id"] = "relic.modifier.%s" % type
	return result


static func _source_definitions() -> Array:
	return [
		Relic.new("spLimitPlus", "01号遗物", CATEGORY_COMMON, "技能点上限 +1。", [], [
			_modifier("skillPointMaxFlat", {"value": 1}),
		]),
		Relic.new("trueNameUnseal", "真名解放", CATEGORY_COMMON, "每场战斗的前两回合，释放自由技或专属不消耗技能点。", [], [
			_modifier("skillPointCostOverride", {"side": "ally", "skillKinds": ["freeSkill", "exclusive"], "maxRound": 2, "value": 0}),
		]),
		Relic.new("ultPursuitMark", "余韵追击", CATEGORY_COMMON, "每场战斗，我方首次释放大招后，全体棋子获得一层追击。", [
			_hook("ultimateCast", "relic.condition.source_effect_is_ally", "relic.effect.apply_pursuit_to_alive_allies", LIMIT_PER_BATTLE, SCOPE_EVENT, 1, 0, {"source_side": "ally"}, {"stacks": 1}),
		]),
		Relic.new("arcConductor", "奥术导体", CATEGORY_COMMON, "我方消耗 SP 时，对敌方全体造成队伍平均攻击 x 0.6 x 消耗 SP 的遗物伤害。", [
			_hook("skillPointSpent", "relic.condition.ally_spent_positive_sp", "relic.effect.deal_arc_conductor_damage_to_all_enemies", LIMIT_NONE, SCOPE_EVENT, 1, 0, {"source_side": "ally", "minimum_amount": 1}, {"team_average_attack_multiplier_per_sp": 0.6, "source_id": "arcConductor", "source_name": "奥术导体"}),
		]),
		Relic.new("emberStorm", "余烬风暴", CATEGORY_COMMON, "带灼烧的敌方阵亡时，灼烧层数扩散并立即结算一次。", [
			_hook("unitDied", "relic.condition.enemy_burn_death_allows_kill_effects", "relic.effect.spread_burn_on_enemy_death", LIMIT_NONE, SCOPE_EVENT, 1, 0, {"target_side": "enemy", "buff_id": "burn", "minimum_stacks": 1, "requires_enemy_kill_effects": true}, {}),
		]),
		Relic.new("executionAxe", "处刑巨斧", CATEGORY_COMMON, "敌方首次低于 30% 生命时，攻击最高的我方棋子获得并立即消耗一层追击。", [
			_hook("hpThresholdCrossed", "relic.condition.target_is_enemy", "relic.effect.trigger_strongest_ally_pursuit", LIMIT_NONE, SCOPE_EVENT, 1, 0, {"target_side": "enemy", "hp_ratio": 0.3}, {}),
		]),
		Relic.new("thornCrown", "荆棘王冠", CATEGORY_COMMON, "我方成功格挡时，对攻击者造成本次伤害 50% 的遗物反伤。", [
			_hook("unitBlocked", "relic.condition.ally_blocked_by_alive_actor", "relic.effect.reflect_blocked_raw_damage", LIMIT_NONE, SCOPE_EVENT, 1, 0, {"target_side": "ally", "actor_alive": true}, {"raw_damage_ratio": 0.5, "minimum_damage": 1, "source_id": "thornCrown", "source_name": "荆棘王冠"}),
		]),
		Relic.new("tradePermit", "交易许可", CATEGORY_COMMON, "商店页面解锁出售已有自由技，售价等于标准买入价。", [], [
			_modifier("canSellFreeSkills", {"value": true}),
		]),
		Relic.new("discountCard", "打折卡", CATEGORY_COMMON, "所有货币消耗降低 25%。", [], [
			_modifier("currencyCostMultiplier", {"value": 0.75}),
		]),
		Relic.new("witheredSeal", "凋零印记", CATEGORY_COMMON, "敌方受到的恢复效果降低 25%。", [], [
			_modifier("healingReceivedMultiplier", {"side": "enemy", "value": 0.75}),
		]),
		Relic.new("crossbowPlus", "连发PLUS", CATEGORY_CLASS_UPGRADE, "机弩额外追击概率 +10%，但生命 -20。", [], [
			_modifier("classMaxHpFlat", {"side": "ally", "classId": "crossbow", "value": -20}),
			_modifier("pursuitChanceFlat", {"side": "ally", "classId": "crossbow", "value": 0.1}),
		]),
		Relic.new("shieldPlus", "坚阵PLUS", CATEGORY_CLASS_UPGRADE, "甲卒格挡成功时回复 3% 已损生命。", [
			_hook("unitBlocked", "relic.condition.ally_shield_blocked", "relic.effect.heal_missing_hp_ratio", LIMIT_NONE, SCOPE_EVENT, 1, 0, {"target_side": "ally", "class_id": "shield"}, {"missing_hp_ratio": 0.03, "source_id": "shieldPlus", "source_name": "坚阵PLUS"}),
		]),
		Relic.new("assassinPlus", "破绽PLUS", CATEGORY_CLASS_UPGRADE, "死士血量低于 50% 时额外获得 30% 暴击率。", [], [
			_modifier("critRateFlatBelowHp", {"side": "ally", "classId": "assassin", "hpRatio": 0.5, "value": 0.3}),
		]),
		Relic.new("bannerPlus", "击鼓PLUS", CATEGORY_CLASS_UPGRADE, "旗兵每次攻击后额外给随机弈者回复 1 能量，追击也算。", [
			_hook("pieceAttackHit", "relic.condition.ally_banner_attack_hit", "relic.effect.gain_random_active_hero_energy", LIMIT_NONE, SCOPE_EVENT, 1, 0, {"actor_side": "ally", "class_id": "banner"}, {"amount": 1, "source_id": "bannerPlus", "source_name": "击鼓PLUS"}),
		]),
		Relic.new("shentongAssaultBurst", "终极爆发", CATEGORY_SHENTONG_EVOLVE, "神通【突击】的基础伤害增幅提升至 500%。", [], [
			_modifier("shentongDamageMultiplier", {"shentongId": "assault", "value": 5}),
		]),
		Relic.new("shentongChargeOverload", "能量过载", CATEGORY_SHENTONG_EVOLVE, "神通【蓄势】发动时，我方全体弈者回复 30 点能量。", [], [
			_modifier("shentongEnergyGain", {"shentongId": "charge", "value": 30}),
		]),
		Relic.new("rationChip", "配给筹码", CATEGORY_COMMON, "每场战斗开始时回复 1 点技能点。", [
			_hook("battleStart", "", "relic.effect.gain_skill_points", LIMIT_NONE, SCOPE_EVENT, 1, 0, {}, {"amount": 1}),
		]),
		Relic.new("zeroCostSpark", "零耗火花", CATEGORY_COMMON, "每回合首次释放实际消耗为 0 的我方自由技后，最低能量弈者回复 10 点能量。", [
			_hook("freeSkillCast", "relic.condition.ally_free_skill_actual_cost_zero", "relic.effect.gain_lowest_energy_active_hero_energy", LIMIT_PER_ROUND, SCOPE_EVENT, 1, 0, {"source_side": "ally", "actual_cost": 0}, {"amount": 10}),
		]),
		Relic.new("scorchShard", "焦痕弹片", CATEGORY_COMMON, "每回合我方每个棋子首次攻击命中后，对目标施加 1 层灼烧。", [
			_hook("pieceAttackHit", "relic.condition.ally_piece_hit_alive_target", "relic.effect.apply_burn", LIMIT_PER_ROUND, SCOPE_ACTOR, 1, 0, {"actor_side": "ally", "target_alive": true}, {"buff_id": "burn", "stacks": 1}),
		]),
		Relic.new("fieldBandage", "战地绷带", CATEGORY_COMMON, "每回合我方每个棋子首次受伤后，回复其生命上限的 2%。", [
			_hook("unitDamaged", "relic.condition.ally_target_alive", "relic.effect.heal_max_hp_ratio", LIMIT_PER_ROUND, SCOPE_TARGET, 1, 0, {"target_side": "ally", "target_alive": true}, {"max_hp_ratio": 0.02, "source_id": "fieldBandage", "source_name": "战地绷带"}),
		]),
		Relic.new("graveChange", "亡者零钱", CATEGORY_ELITE, "由我方击杀的敌人阵亡时回复 1 点技能点；我方献祭单位阵亡时同样生效。", [
			_hook("unitDied", "relic.condition.ally_kill_or_ally_sacrifice", "relic.effect.gain_skill_points", LIMIT_NONE, SCOPE_EVENT, 1, 0, {"accepted_cases": [{"target_side": "enemy", "source_side": "ally"}, {"target_side": "ally", "source_side": "ally", "source_type": "sacrifice"}]}, {"amount": 1}),
		]),
		Relic.new("lastEmber", "余命火种", CATEGORY_COMMON, "每场战斗首个敌方单位阵亡后，所有存活棋子各回复生命上限的 10%。", [
			_hook("unitDied", "relic.condition.target_is_enemy", "relic.effect.heal_alive_allies_ratio", LIMIT_PER_BATTLE, SCOPE_EVENT, 1, 0, {"target_side": "enemy"}, {"max_hp_ratio": 0.1, "source_id": "lastEmber", "source_name": "余命火种"}),
		]),
	]
