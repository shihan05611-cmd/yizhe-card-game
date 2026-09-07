class_name StageCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const Stage = preload("res://data/definitions/stage_definition.gd")
const Skill = preload("res://data/definitions/skill_definition.gd")
const Ability = preload("res://data/definitions/hero_ability_definition.gd")

const EXCLUSIVE := "exclusive"
const ULTIMATE := "ultimate"


static func build(skill_catalog: Dictionary, ability_catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(), skill_catalog, ability_catalog, errors)


static func build_from(
	definitions: Array,
	skill_catalog: Dictionary,
	ability_catalog: Dictionary,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	_validate_skill_catalog(skill_catalog, errors)
	_validate_ability_catalog(ability_catalog, errors)
	var seen_stages := {}
	var seen_enemies := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != Stage:
			errors.append("stage entries must be StageDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.non_empty_id(definition.id, "stage", errors):
			Validation.unique_id(definition.id, seen_stages, "stage", errors)
		Validation.non_empty_string(definition.name, "stage name", errors)
		Validation.non_empty_string(definition.archetype, "stage archetype", errors)
		Validation.non_empty_string(definition.description, "stage description", errors)
		if definition.enemy_yizhes.is_empty():
			errors.append("stage enemyYizhes must not be empty")
		for enemy in definition.enemy_yizhes:
			_validate_enemy(definition.id, enemy, skill_catalog, ability_catalog, seen_enemies, errors)
	if not errors.is_empty():
		return {}

	var catalog := {}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.id] = definition.snapshot()
	return catalog


static func _validate_skill_catalog(catalog: Dictionary, errors: Array[String]) -> void:
	if catalog.is_empty():
		errors.append("stage skill catalog must not be empty")
		return
	for id in catalog:
		var definition: Variant = catalog[id]
		if not definition is Resource or definition.get_script() != Skill:
			errors.append("stage skill references must be SkillDefinition resources")
		elif id != definition.id:
			errors.append("stage skill catalog key does not match definition id: %s" % str(id))


static func _validate_ability_catalog(catalog: Dictionary, errors: Array[String]) -> void:
	for ability_type in [EXCLUSIVE, ULTIMATE]:
		if not catalog.has(ability_type) or typeof(catalog[ability_type]) != TYPE_DICTIONARY or catalog[ability_type].is_empty():
			errors.append("stage hero ability catalog is missing group: %s" % ability_type)
			continue
		for id in catalog[ability_type]:
			var definition: Variant = catalog[ability_type][id]
			if not definition is Resource or definition.get_script() != Ability:
				errors.append("stage hero ability references must be HeroAbilityDefinition resources")
			elif id != definition.id or definition.ability_type != ability_type:
				errors.append("stage hero ability catalog key/type mismatch: %s:%s" % [ability_type, str(id)])


static func _validate_enemy(
	stage_id: String,
	enemy: Dictionary,
	skill_catalog: Dictionary,
	ability_catalog: Dictionary,
	seen_enemies: Dictionary,
	errors: Array[String],
) -> void:
	var expected_keys := [
		"id",
		"name",
		"exclusive_skill_id",
		"source_skill_names",
		"free_skill_ids",
		"source_max_energy",
		"base_crit_rate",
	]
	for key in enemy:
		if key not in expected_keys:
			errors.append("unknown stage enemy metadata field: %s" % str(key))
	for key in expected_keys:
		if not enemy.has(key):
			errors.append("stage %s enemy is missing field: %s" % [stage_id, key])
	if not enemy.has("id"):
		return
	if typeof(enemy["id"]) != TYPE_INT:
		errors.append("stage enemy id must be a positive integer: %s" % str(enemy["id"]))
	elif Validation.positive_int_id(enemy["id"], "stage enemy", errors):
		Validation.unique_id(enemy["id"], seen_enemies, "stage enemy", errors)
	if typeof(enemy.get("name")) != TYPE_STRING:
		errors.append("stage enemy name must be a string")
	else:
		Validation.non_empty_string(enemy["name"], "stage enemy name", errors)
	var ability_id: Variant = enemy.get("exclusive_skill_id")
	if typeof(ability_id) != TYPE_STRING or str(ability_id).strip_edges().is_empty():
		errors.append("stage enemy exSkill must be a non-empty string")
	elif not _ability_has(ability_catalog, EXCLUSIVE, ability_id):
		errors.append("stage enemy references unknown exclusive ability: %s" % ability_id)
	elif not _ability_has(ability_catalog, ULTIMATE, ability_id):
		errors.append("stage enemy references unknown ultimate ability: %s" % ability_id)
	_validate_skill_references(enemy, skill_catalog, errors)
	Validation.positive_int(enemy.get("source_max_energy"), "stage enemy source maxEnergy", errors)
	if _ability_has(ability_catalog, ULTIMATE, ability_id):
		var ultimate: Variant = ability_catalog[ULTIMATE][ability_id]
		if ultimate.source_energy_requirement != enemy.get("source_max_energy"):
			errors.append("stage enemy maxEnergy does not match ultimate source cost: %s" % ability_id)
	_validate_ratio(enemy.get("base_crit_rate"), "stage enemy baseCritRate", errors)


static func _validate_skill_references(enemy: Dictionary, skill_catalog: Dictionary, errors: Array[String]) -> void:
	var names: Variant = enemy.get("source_skill_names")
	var ids: Variant = enemy.get("free_skill_ids")
	if typeof(names) != TYPE_ARRAY:
		errors.append("stage enemy source skills must be an array")
	else:
		Validation.string_array(names, "stage enemy source skills", errors, false)
	if typeof(ids) != TYPE_ARRAY:
		errors.append("stage enemy skillPool must be an array")
		return
	Validation.string_array(ids, "stage enemy skillPool", errors, false)
	var pool_names: Array[String] = []
	var seen_ids := {}
	for id in ids:
		Validation.unique_id(id, seen_ids, "stage enemy skillPool", errors)
		if not skill_catalog.has(id):
			errors.append("stage enemy references unknown free skill: %s" % id)
		elif skill_catalog[id] is Resource and skill_catalog[id].get_script() == Skill:
			pool_names.append(skill_catalog[id].name)
	if typeof(names) == TYPE_ARRAY:
		for source_name in names:
			if source_name not in pool_names:
				errors.append("stage enemy source skill name is not represented in skillPool: %s" % source_name)


static func _ability_has(catalog: Dictionary, ability_type: String, id: Variant) -> bool:
	if not catalog.has(ability_type) or typeof(catalog[ability_type]) != TYPE_DICTIONARY:
		return false
	if not catalog[ability_type].has(id):
		return false
	var definition: Variant = catalog[ability_type][id]
	return definition is Resource and definition.get_script() == Ability


static func _validate_ratio(value: Variant, field_name: String, errors: Array[String]) -> void:
	if not Validation.non_negative_number(value, field_name, errors):
		return
	if value > 1.0:
		errors.append("%s must not exceed 1" % field_name)


static func _enemy(
	id: int,
	name: String,
	exclusive_skill_id: String,
	source_skill_names: Array[String],
	free_skill_ids: Array[String],
	source_max_energy: int,
) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"exclusive_skill_id": exclusive_skill_id,
		"source_skill_names": source_skill_names.duplicate(),
		"free_skill_ids": free_skill_ids.duplicate(),
		"source_max_energy": source_max_energy,
		"base_crit_rate": 0.05,
	}


static func _source_definitions() -> Array:
	return [
		Stage.new("counter", "关卡1：反击流阵地", "反击流", "以格挡反击为核心，偏防守反打。", [
			_enemy(101, "敌·军令", "ascend", ["棋子增伤", "棋子行动"], ["pieceDamageUp", "pieceAction", "pieceBlock"], 100),
			_enemy(102, "敌·铁卫", "counterAura", ["棋子格挡", "棋子回血"], ["pieceBlock", "pieceHealAll", "pieceAction"], 100),
			_enemy(103, "敌·千机", "puppet", ["棋子格挡", "斩杀"], ["pieceBlock", "executeStrike", "pieceAction"], 120),
		]),
		Stage.new("burn", "关卡2：灼烧流熔炉", "灼烧流", "灼烧铺场与引爆联动，持续压血。", [
			_enemy(201, "敌·灼痕", "burn01", ["基础叠层", "灼烧引爆"], ["burnStackBase", "burnDetonate", "markBurn"], 100),
			_enemy(202, "敌·炎契", "burnEnchant", ["基础叠层", "棋子增伤"], ["burnStackBase", "pieceDamageUp", "pieceAction"], 100),
			_enemy(203, "敌·命巡", "fate", ["棋子格挡", "棋子行动"], ["pieceBlock", "pieceAction", "burnStackBase"], 120),
		]),
		Stage.new("core", "关卡3：弈者主核流", "弈者主核流", "以弈者直伤技能与大招为核心输出。", [
			_enemy(301, "敌·无锋", "fist", ["棋子行动", "小回血"], ["pieceAction", "smallHeal", "pieceDamageUp"], 100),
			_enemy(302, "敌·沉戈", "siege", ["棋子回血", "小回血"], ["pieceHealAll", "smallHeal", "pieceDamageUp"], 100),
			_enemy(303, "敌·命巡", "fate", ["棋子增伤", "棋子格挡"], ["pieceDamageUp", "pieceBlock", "pieceAction"], 120),
		]),
	]
