class_name RoguelikeContentCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const ContentDefinition = preload("res://data/definitions/roguelike_content_definition.gd")
const RelicCatalogScript = preload("res://data/catalogs/relic_catalog.gd")
const PieceClassCatalogScript = preload("res://data/catalogs/piece_class_catalog.gd")
const EventCatalogScript = preload("res://data/catalogs/event_catalog.gd")
const SkillCatalogScript = preload("res://data/catalogs/skill_catalog.gd")
const EnemySpecialCatalogScript = preload("res://data/catalogs/enemy_special_catalog.gd")

const KIND_CHAPTER := "chapter"
const KIND_ENCOUNTER := "encounter"
const KIND_SHENTONG := "shentong"

const NODE_TYPES := ["battle", "elite", "boss", "forge", "shop", "event"]
const REQUIRED_CHAPTER_IDS := [1, 2, 3]
const DEFAULT_ENCOUNTER_ORDER := [
	"boss_devourer", "boss_echo", "elite_devourer", "elite_echo",
	"normal_ambush", "normal_crossfire", "normal_phalanx", "normal_pressure",
	"normal_siege", "normal_vanguard", "normal", "elite_core", "boss_core",
]
const REQUIRED_SHENTONG_IDS := ["charge", "assault", "sacrifice"]


static func build() -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(), _default_references(), errors)


static func build_from(
	definitions: Array,
	references: Dictionary,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	var reference_snapshot := _validate_and_snapshot_references(references, errors)
	var chapters := {}
	var encounters := {}
	var shentongs := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != ContentDefinition:
			errors.append("roguelike content entries must be RoguelikeContentDefinition resources")
			continue
		var definition: Variant = raw_definition
		Validation.enum_value(definition.kind, [
			KIND_CHAPTER, KIND_ENCOUNTER, KIND_SHENTONG,
		], "roguelike content kind", errors)
		match definition.kind:
			KIND_CHAPTER:
				_validate_chapter(definition, chapters, errors)
			KIND_ENCOUNTER:
				_validate_encounter(definition, encounters, reference_snapshot, errors)
			KIND_SHENTONG:
				_validate_shentong(definition, shentongs, errors)

	_validate_complete_chapters(chapters, errors)
	_validate_complete_shentongs(shentongs, errors)
	_validate_chapter_encounter_references(chapters, encounters, errors)
	if not errors.is_empty():
		return {}

	return {
		"node_types": NODE_TYPES.duplicate(),
		"chapters": _snapshot_definition_dictionary(chapters, REQUIRED_CHAPTER_IDS),
		"encounters": _snapshot_definition_dictionary(encounters, DEFAULT_ENCOUNTER_ORDER),
		"shentongs": _snapshot_definition_dictionary(shentongs, REQUIRED_SHENTONG_IDS),
		"free_skills": reference_snapshot["free_skills"].duplicate(true),
		"relics": reference_snapshot["relics"].duplicate(true),
		"piece_classes": reference_snapshot["piece_classes"].duplicate(true),
		"enemy_specials": reference_snapshot["enemy_specials"].duplicate(true),
	}


static func _validate_chapter(
	definition: Variant,
	chapters: Dictionary,
	errors: Array[String],
) -> void:
	if typeof(definition.id) != TYPE_INT or definition.id < 1 or definition.id > 3:
		errors.append("chapter id must be an integer from 1 to 3: %s" % str(definition.id))
		return
	if not Validation.unique_id(definition.id, chapters, "chapter", errors):
		return
	var data: Dictionary = definition.metadata
	var path := "chapter %d" % definition.id
	_validate_exact_keys(data, [
		"chapter", "rows", "columns", "columnRules", "battleEncounterIds",
		"eliteEncounterIds", "bossEncounterId", "battleReward", "eliteReward", "bossReward",
	], path, errors)
	if data.get("chapter") != definition.id:
		errors.append("%s metadata chapter must equal its id" % path)
	if data.get("rows") != 3 or data.get("columns") != 10:
		errors.append("%s must use exactly 3 rows and 10 columns" % path)
	_validate_column_rules(data.get("columnRules"), definition.id, errors)
	_validate_id_array(data.get("battleEncounterIds"), "%s battleEncounterIds" % path, errors)
	_validate_id_array(data.get("eliteEncounterIds"), "%s eliteEncounterIds" % path, errors)
	if typeof(data.get("bossEncounterId")) != TYPE_STRING or str(data.get("bossEncounterId")).strip_edges().is_empty():
		errors.append("%s bossEncounterId must be a non-empty string" % path)
	_validate_reward(data.get("battleReward"), "%s battleReward" % path, errors)
	_validate_reward(data.get("eliteReward"), "%s eliteReward" % path, errors)
	_validate_reward(data.get("bossReward"), "%s bossReward" % path, errors)
	chapters[definition.id] = definition


static func _validate_column_rules(value: Variant, chapter_id: int, errors: Array[String]) -> void:
	var path := "chapter %d columnRules" % chapter_id
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an array" % path)
		return
	var rules: Array = value
	if rules.size() != 10:
		errors.append("%s must contain exactly 10 columns" % path)
	var seen_columns := {}
	for rule_index in rules.size():
		var rule: Variant = rules[rule_index]
		var rule_path := "%s[%d]" % [path, rule_index]
		if typeof(rule) != TYPE_DICTIONARY:
			errors.append("%s must be a dictionary" % rule_path)
			continue
		_validate_exact_keys(rule, ["column", "fixedByRow", "pool"], rule_path, errors)
		var column: Variant = rule.get("column")
		if typeof(column) != TYPE_INT or column < 0 or column > 9:
			errors.append("%s column must be an integer from 0 to 9" % rule_path)
		else:
			Validation.unique_id(column, seen_columns, "chapter %d column" % chapter_id, errors)
		var fixed_by_row: Variant = rule.get("fixedByRow")
		var pool: Variant = rule.get("pool")
		if fixed_by_row != null:
			if typeof(fixed_by_row) != TYPE_ARRAY or fixed_by_row.size() != 3:
				errors.append("%s fixedByRow must contain exactly 3 rows" % rule_path)
			else:
				for node_type in fixed_by_row:
					Validation.enum_value(node_type, NODE_TYPES, "%s node type" % rule_path, errors)
		if typeof(pool) != TYPE_ARRAY:
			errors.append("%s pool must be an array" % rule_path)
		else:
			for pool_index in pool.size():
				var weighted: Variant = pool[pool_index]
				var weighted_path := "%s pool[%d]" % [rule_path, pool_index]
				if typeof(weighted) != TYPE_DICTIONARY:
					errors.append("%s must be a dictionary" % weighted_path)
					continue
				_validate_exact_keys(weighted, ["type", "weight"], weighted_path, errors)
				Validation.enum_value(weighted.get("type"), NODE_TYPES, "%s type" % weighted_path, errors)
				Validation.positive_int(weighted.get("weight"), "%s weight" % weighted_path, errors)
		if fixed_by_row == null and (typeof(pool) != TYPE_ARRAY or pool.is_empty()):
			errors.append("%s must define fixedByRow or a positive weighted pool" % rule_path)
	for column in range(10):
		if not seen_columns.has(column):
			errors.append("chapter %d is missing column %d" % [chapter_id, column])
	var fixed_requirements := {
		0: ["battle", "battle", "battle"],
		3: ["forge", "event", "shop"],
		6: ["shop", "elite", "forge"],
		9: ["boss", "boss", "boss"],
	}
	for column in fixed_requirements:
		for rule in rules:
			if typeof(rule) == TYPE_DICTIONARY and rule.get("column") == column:
				if rule.get("fixedByRow") != fixed_requirements[column]:
					errors.append("chapter %d column %d does not match the required fixed rows" % [chapter_id, column])
				break


static func _validate_reward(value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be a dictionary" % path)
		return
	_validate_exact_keys(value, ["freeSkillCount", "relicCount", "currency"], path, errors)
	for field in ["freeSkillCount", "relicCount", "currency"]:
		Validation.non_negative_int(value.get(field), "%s %s" % [path, field], errors)


static func _validate_encounter(
	definition: Variant,
	encounters: Dictionary,
	references: Dictionary,
	errors: Array[String],
) -> void:
	if typeof(definition.id) != TYPE_STRING or str(definition.id).strip_edges().is_empty():
		errors.append("encounter id must be a non-empty string")
		return
	if not Validation.unique_id(definition.id, encounters, "encounter", errors):
		return
	var data: Dictionary = definition.metadata
	var path := "encounter %s" % definition.id
	_validate_exact_keys(data, ["id", "name", "hpScale", "atkScale", "slots"], path, errors)
	if data.get("id") != definition.id:
		errors.append("%s metadata id must equal its id" % path)
	if typeof(data.get("name")) != TYPE_STRING:
		errors.append("%s name must be a string" % path)
	_validate_positive_scale(data.get("hpScale"), "%s hpScale" % path, errors)
	_validate_positive_scale(data.get("atkScale"), "%s atkScale" % path, errors)
	var slots: Variant = data.get("slots")
	if typeof(slots) != TYPE_ARRAY:
		errors.append("%s slots must be an array" % path)
		encounters[definition.id] = definition
		return
	var seen_slots := {}
	for slot_index in slots.size():
		var slot: Variant = slots[slot_index]
		var slot_path := "%s slot %d" % [path, slot_index]
		if typeof(slot) != TYPE_DICTIONARY:
			errors.append("%s must be a dictionary" % slot_path)
			continue
		_validate_exact_keys(slot, [
			"unitId", "pieceClassId", "specialId", "className", "hpScale", "atkScale", "empty", "occupiesSlots",
		], slot_path, errors)
		var unit_id: Variant = slot.get("unitId")
		if typeof(unit_id) != TYPE_INT or unit_id < 1 or unit_id > 6:
			errors.append("%s unitId must be an integer from 1 to 6" % slot_path)
		else:
			Validation.unique_id(unit_id, seen_slots, "%s slot" % path, errors)
		var piece_class_id: Variant = slot.get("pieceClassId")
		if piece_class_id != null and (
			typeof(piece_class_id) != TYPE_STRING
			or not references["piece_classes"].has(piece_class_id)
		):
			errors.append("%s references missing piece class %s" % [path, str(piece_class_id)])
		var special_id: Variant = slot.get("specialId")
		if special_id != null and (
			typeof(special_id) != TYPE_STRING
			or not references["enemy_specials"].has(special_id)
		):
			errors.append("%s references missing special %s" % [path, str(special_id)])
		if typeof(slot.get("className")) != TYPE_STRING:
			errors.append("%s className must be a string" % slot_path)
		_validate_positive_scale(slot.get("hpScale"), "%s hpScale" % slot_path, errors)
		_validate_positive_scale(slot.get("atkScale"), "%s atkScale" % slot_path, errors)
		if typeof(slot.get("empty")) != TYPE_BOOL:
			errors.append("%s empty must be a bool" % slot_path)
		var occupies_slots: Variant = slot.get("occupiesSlots", [])
		if typeof(occupies_slots) != TYPE_ARRAY:
			errors.append("%s occupiesSlots must be an array" % slot_path)
		elif not occupies_slots.is_empty():
			if special_id == null:
				errors.append("%s occupiesSlots requires a specialId" % slot_path)
			elif typeof(special_id) != TYPE_STRING or not references["enemy_specials"].has(special_id):
				pass
			elif occupies_slots[0] != unit_id or occupies_slots.size() != int(references["enemy_specials"][special_id].get("gridCells", 0)):
				errors.append("%s occupiesSlots must begin at unitId and match special gridCells" % slot_path)
			if occupies_slots != range(unit_id, unit_id + occupies_slots.size()) or (unit_id - 1) / 3 != (unit_id + occupies_slots.size() - 2) / 3:
				errors.append("%s occupiesSlots must be consecutive slots in one board column" % slot_path)
			for occupied_id: Variant in occupies_slots:
				if typeof(occupied_id) != TYPE_INT or occupied_id < 1 or occupied_id > 6:
					errors.append("%s occupiesSlots must contain slot ids 1 through 6" % slot_path)
	for slot: Dictionary in slots:
		for occupied_id: Variant in slot.get("occupiesSlots", []):
			if occupied_id == slot.get("unitId"):
				continue
			var covered: Array = slots.filter(func(candidate: Dictionary) -> bool: return candidate.get("unitId") == occupied_id)
			if covered.size() != 1 or not covered[0].get("empty", false):
				errors.append("%s occupied slot %s must be authored as empty" % [path, str(occupied_id)])
	encounters[definition.id] = definition


static func _validate_shentong(
	definition: Variant,
	shentongs: Dictionary,
	errors: Array[String],
) -> void:
	if typeof(definition.id) != TYPE_STRING or str(definition.id).strip_edges().is_empty():
		errors.append("shentong id must be a non-empty string")
		return
	if not Validation.unique_id(definition.id, shentongs, "shentong", errors):
		return
	var data: Dictionary = definition.metadata
	var path := "shentong %s" % definition.id
	_validate_exact_keys(data, [
		"id", "name", "description", "restriction", "usesPerBattle", "handler_id",
	], path, errors)
	if data.get("id") != definition.id:
		errors.append("%s metadata id must equal its id" % path)
	for field in ["name", "description", "restriction", "handler_id"]:
		if typeof(data.get(field)) != TYPE_STRING or str(data.get(field)).strip_edges().is_empty():
			errors.append("%s %s must be a non-empty string" % [path, field])
	Validation.positive_int(data.get("usesPerBattle"), "%s usesPerBattle" % path, errors)
	shentongs[definition.id] = definition


static func _validate_complete_chapters(chapters: Dictionary, errors: Array[String]) -> void:
	if chapters.size() != REQUIRED_CHAPTER_IDS.size():
		errors.append("chapters must contain exactly chapter ids 1, 2, 3")
		return
	for chapter_id in REQUIRED_CHAPTER_IDS:
		if not chapters.has(chapter_id):
			errors.append("chapters must contain exactly chapter ids 1, 2, 3")
			return


static func _validate_complete_shentongs(shentongs: Dictionary, errors: Array[String]) -> void:
	if shentongs.size() != REQUIRED_SHENTONG_IDS.size():
		errors.append("shentongs must contain exactly charge, assault, sacrifice")
		return
	for shentong_id in REQUIRED_SHENTONG_IDS:
		if not shentongs.has(shentong_id):
			errors.append("shentongs must contain exactly charge, assault, sacrifice")
			return


static func _validate_chapter_encounter_references(
	chapters: Dictionary,
	encounters: Dictionary,
	errors: Array[String],
) -> void:
	for chapter_id in chapters:
		var data: Dictionary = chapters[chapter_id].metadata
		var ids: Array = []
		if typeof(data.get("battleEncounterIds")) == TYPE_ARRAY:
			ids.append_array(data["battleEncounterIds"])
		if typeof(data.get("eliteEncounterIds")) == TYPE_ARRAY:
			ids.append_array(data["eliteEncounterIds"])
		ids.append(data.get("bossEncounterId"))
		for encounter_id in ids:
			if not encounters.has(encounter_id):
				errors.append("chapter %d references missing encounter %s" % [chapter_id, str(encounter_id)])


static func _validate_and_snapshot_references(
	references: Dictionary,
	errors: Array[String],
) -> Dictionary:
	_validate_exact_keys(references, [
		"free_skills", "relics", "piece_classes", "enemy_specials",
	], "roguelike references", errors)
	var output := {
		"free_skills": {},
		"relics": {},
		"piece_classes": {},
		"enemy_specials": {},
	}
	for catalog_name in output:
		var catalog: Variant = references.get(catalog_name)
		if typeof(catalog) != TYPE_DICTIONARY:
			errors.append("roguelike reference %s must be a dictionary" % catalog_name)
			continue
		for catalog_id in catalog:
			if typeof(catalog_id) != TYPE_STRING or str(catalog_id).strip_edges().is_empty():
				errors.append("roguelike reference %s has invalid id %s" % [catalog_name, str(catalog_id)])
				continue
			var snapshot := _snapshot_reference_entry(catalog_name, catalog[catalog_id], errors)
			if snapshot.is_empty() or snapshot.get("id") != catalog_id:
				errors.append("roguelike reference %s.%s id must equal catalog key" % [catalog_name, catalog_id])
				continue
			output[catalog_name][catalog_id] = snapshot
	return output


static func _snapshot_reference_entry(
	catalog_name: String,
	value: Variant,
	errors: Array[String],
) -> Dictionary:
	var source := _reference_to_dictionary(value)
	if source.is_empty():
		return {}
	var fields: Array
	match catalog_name:
		"free_skills":
			fields = [["name", "", TYPE_STRING], ["cost", 0, TYPE_FLOAT], ["tip", "", TYPE_STRING]]
		"relics":
			fields = [["name", "", TYPE_STRING], ["description", "", TYPE_STRING], ["category", "common", TYPE_STRING]]
		"piece_classes":
			fields = [["name", "", TYPE_STRING], ["blockBonus", 0.0, TYPE_FLOAT], ["critBonus", 0.0, TYPE_FLOAT]]
		"enemy_specials":
			fields = [["name", "", TYPE_STRING], ["gridCells", 1, TYPE_INT], ["pieceClassId", null, TYPE_NIL], ["hpScale", 1.0, TYPE_FLOAT], ["atkScale", 1.0, TYPE_FLOAT]]
	var output := {"id": source.get("id")}
	for field_spec in fields:
		var field_name: String = field_spec[0]
		var fallback: Variant = field_spec[1]
		var expected_type: int = field_spec[2]
		var field_value: Variant = source.get(field_name, fallback)
		if expected_type == TYPE_STRING and typeof(field_value) != TYPE_STRING:
			errors.append("roguelike reference %s %s must be a string" % [catalog_name, field_name])
		elif expected_type == TYPE_FLOAT and not Validation.finite_number(field_value, "roguelike reference %s %s" % [catalog_name, field_name], errors):
			pass
		elif expected_type == TYPE_INT and (typeof(field_value) != TYPE_INT or field_value < 1):
			errors.append("roguelike reference %s %s must be a positive integer" % [catalog_name, field_name])
		elif expected_type == TYPE_NIL and field_value != null and typeof(field_value) != TYPE_STRING:
			errors.append("roguelike reference %s %s must be a string or null" % [catalog_name, field_name])
		output[field_name] = field_value
	return output


static func _reference_to_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	if value is Resource:
		if value.has_method("to_source_dict"):
			return value.to_source_dict().duplicate(true)
		var result := {}
		for property in value.get_property_list():
			var property_name: String = property["name"]
			if property_name in ["resource_local_to_scene", "resource_path", "resource_name", "script"]:
				continue
			if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				result[property_name] = value.get(property_name)
		return result.duplicate(true)
	return {}


static func _snapshot_definition_dictionary(
	source: Dictionary,
	preferred_order: Array,
) -> Dictionary:
	var result := {}
	var remaining_ids := source.keys()
	for id in preferred_order:
		if not source.has(id):
			continue
		result[id] = source[id].snapshot()
		remaining_ids.erase(id)
	remaining_ids.sort()
	for id in remaining_ids:
		result[id] = source[id].snapshot()
	return result


static func _validate_id_array(value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		errors.append("%s must be a non-empty array" % path)
		return
	Validation.string_array(value, path, errors, false)


static func _validate_positive_scale(value: Variant, path: String, errors: Array[String]) -> void:
	if not Validation.finite_number(value, path, errors):
		return
	if value <= 0:
		errors.append("%s must be positive" % path)


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


static func _default_references() -> Dictionary:
	var free_skills := {}
	var skill_catalog := SkillCatalogScript.build()
	for id in skill_catalog:
		free_skills[id] = skill_catalog[id].to_source_dict()
	var relics := {}
	var relic_catalog := RelicCatalogScript.build()
	for id in relic_catalog:
		var definition: Variant = relic_catalog[id]
		relics[id] = {
			"id": definition.id,
			"name": definition.name,
			"description": definition.description,
			"category": definition.category,
		}
	var piece_classes := {}
	var piece_class_catalog := PieceClassCatalogScript.build()
	for id in piece_class_catalog:
		var definition: Variant = piece_class_catalog[id]
		piece_classes[id] = {
			"id": definition.id,
			"name": definition.name,
			"blockBonus": definition.block_bonus,
			"critBonus": definition.crit_bonus,
		}
	var enemy_specials := {}
	var enemy_special_catalog := EnemySpecialCatalogScript.build(
		EventCatalogScript.build(), piece_class_catalog,
	)
	for id in enemy_special_catalog:
		enemy_specials[id] = enemy_special_catalog[id].to_source_dict()
	return {
		"free_skills": free_skills,
		"relics": relics,
		"piece_classes": piece_classes,
		"enemy_specials": enemy_specials,
	}


static func _chapter(
	chapter_id: int,
	columns: Array,
) -> Resource:
	var column_rules: Array = []
	for column in range(columns.size()):
		column_rules.append({"column": column, "fixedByRow": columns[column], "pool": []})
	return ContentDefinition.new(KIND_CHAPTER, chapter_id, {
		"chapter": chapter_id,
		"rows": 3,
		"columns": 10,
		"columnRules": column_rules,
		"battleEncounterIds": ["normal_vanguard", "normal_crossfire"] if chapter_id == 1 else (["normal_ambush", "normal_siege"] if chapter_id == 2 else ["normal_pressure", "normal_phalanx"]),
		"eliteEncounterIds": ["elite_devourer"] if chapter_id == 1 else (["elite_echo"] if chapter_id == 2 else ["elite_devourer", "elite_echo"]),
		"bossEncounterId": "boss_devourer" if chapter_id == 1 else ("boss_echo" if chapter_id == 2 else "boss_devourer"),
		"battleReward": {"freeSkillCount": 3, "relicCount": 0, "currency": 15},
		"eliteReward": {"freeSkillCount": 2, "relicCount": 1, "currency": 25},
		"bossReward": {"freeSkillCount": 1, "relicCount": 2, "currency": 40},
	})


static func _slot(
	unit_id: int,
	display_class_name: String,
	hp_scale: float,
	empty: bool,
	piece_class_id: Variant = null,
	special_id: Variant = null,
	occupies_slots: Array = [],
) -> Dictionary:
	return {
		"unitId": unit_id,
		"pieceClassId": piece_class_id,
		"specialId": special_id,
		"className": display_class_name,
		"hpScale": hp_scale,
		"atkScale": 1.0,
		"empty": empty,
		"occupiesSlots": occupies_slots,
	}


static func _source_definitions() -> Array:
	var normal_vanguard := [_slot(1, "敌方甲卒", 1.0, false, "shield"), _slot(2, "敌方死士", 1.0, false, "assassin"), _slot(3, "敌方甲卒", 1.0, false, "shield"), _slot(4, "空位", 1.0, true), _slot(5, "敌方机弩", 1.0, false, "crossbow"), _slot(6, "敌方旗兵", 1.0, false, "banner")]
	var normal_crossfire := [_slot(1, "敌方甲卒", 1.1, false, "shield"), _slot(2, "空位", 1.0, true), _slot(3, "敌方死士", 1.0, false, "assassin"), _slot(4, "敌方机弩", 1.0, false, "crossbow"), _slot(5, "敌方机弩", 0.9, false, "crossbow"), _slot(6, "敌方旗兵", 1.0, false, "banner")]
	var normal_ambush := [_slot(1, "敌方死士", 1.1, false, "assassin"), _slot(2, "敌方甲卒", 1.2, false, "shield"), _slot(3, "空位", 1.0, true), _slot(4, "敌方死士", 1.0, false, "assassin"), _slot(5, "敌方机弩", 1.0, false, "crossbow"), _slot(6, "敌方旗兵", 1.0, false, "banner")]
	var normal_siege := [_slot(1, "敌方甲卒", 1.4, false, "shield"), _slot(2, "敌方甲卒", 1.2, false, "shield"), _slot(3, "敌方甲卒", 1.0, false, "shield"), _slot(4, "空位", 1.0, true), _slot(5, "敌方机弩", 1.2, false, "crossbow"), _slot(6, "敌方机弩", 1.0, false, "crossbow")]
	var normal_pressure := [_slot(1, "敌方死士", 1.2, false, "assassin"), _slot(2, "敌方甲卒", 1.3, false, "shield"), _slot(3, "敌方死士", 1.1, false, "assassin"), _slot(4, "敌方机弩", 1.1, false, "crossbow"), _slot(5, "敌方旗兵", 1.0, false, "banner"), _slot(6, "空位", 1.0, true)]
	var normal_phalanx := [_slot(1, "敌方甲卒", 1.5, false, "shield"), _slot(2, "敌方甲卒", 1.4, false, "shield"), _slot(3, "敌方甲卒", 1.2, false, "shield"), _slot(4, "敌方机弩", 1.2, false, "crossbow"), _slot(5, "敌方旗兵", 1.1, false, "banner"), _slot(6, "敌方机弩", 1.0, false, "crossbow")]
	var elite_devourer := [_slot(1, "噬元兽", 1.0, false, null, "devourer", [1, 2]), _slot(2, "噬元兽躯体", 1.0, true), _slot(3, "敌方甲卒", 1.3, false, "shield"), _slot(4, "敌方机弩", 1.2, false, "crossbow"), _slot(5, "空位", 1.0, true), _slot(6, "敌方旗兵", 1.0, false, "banner")]
	var elite_echo := [_slot(1, "敌方甲卒", 1.4, false, "shield"), _slot(2, "敌方死士", 1.2, false, "assassin"), _slot(3, "空位", 1.0, true), _slot(4, "回响", 1.0, false, null, "echo", [4, 5, 6]), _slot(5, "回响躯体", 1.0, true), _slot(6, "回响躯体", 1.0, true)]
	var boss_devourer := [_slot(1, "噬元兽", 1.7, false, null, "devourer", [1, 2]), _slot(2, "噬元兽躯体", 1.0, true), _slot(3, "敌方甲卒", 1.6, false, "shield"), _slot(4, "敌方死士", 1.4, false, "assassin"), _slot(5, "敌方机弩", 1.4, false, "crossbow"), _slot(6, "敌方旗兵", 1.3, false, "banner")]
	var boss_echo := [_slot(1, "敌方甲卒", 1.8, false, "shield"), _slot(2, "敌方死士", 1.6, false, "assassin"), _slot(3, "敌方机弩", 1.5, false, "crossbow"), _slot(4, "回响", 1.7, false, null, "echo", [4, 5, 6]), _slot(5, "回响躯体", 1.0, true), _slot(6, "回响躯体", 1.0, true)]
	return [
		_chapter(1, [
			["battle", "battle", "battle"], ["battle", "shop", "battle"],
			["battle", "battle", "shop"], ["forge", "event", "shop"],
			["event", "forge", "battle"], ["battle", "event", "forge"],
			["shop", "elite", "forge"], ["event", "elite", "battle"],
			["battle", "event", "elite"], ["boss", "boss", "boss"],
		]),
		_chapter(2, [
			["battle", "battle", "battle"], ["battle", "battle", "shop"],
			["forge", "battle", "battle"], ["forge", "event", "shop"],
			["battle", "event", "forge"], ["elite", "battle", "event"],
			["shop", "elite", "forge"], ["battle", "event", "elite"],
			["battle", "battle", "event"], ["boss", "boss", "boss"],
		]),
		_chapter(3, [
			["battle", "battle", "battle"], ["forge", "battle", "battle"],
			["event", "forge", "battle"], ["forge", "event", "shop"],
			["elite", "battle", "event"], ["event", "elite", "battle"],
			["shop", "elite", "forge"], ["battle", "battle", "event"],
			["shop", "battle", "battle"], ["boss", "boss", "boss"],
		]),
		ContentDefinition.new(KIND_ENCOUNTER, "normal_vanguard", {"id": "normal_vanguard", "name": "前卫小队", "hpScale": 1.0, "atkScale": 1.0, "slots": normal_vanguard}),
		ContentDefinition.new(KIND_ENCOUNTER, "normal_crossfire", {"id": "normal_crossfire", "name": "交叉火力", "hpScale": 1.0, "atkScale": 1.0, "slots": normal_crossfire}),
		ContentDefinition.new(KIND_ENCOUNTER, "normal_ambush", {"id": "normal_ambush", "name": "伏击小队", "hpScale": 1.0, "atkScale": 1.0, "slots": normal_ambush}),
		ContentDefinition.new(KIND_ENCOUNTER, "normal_siege", {"id": "normal_siege", "name": "攻城编队", "hpScale": 1.0, "atkScale": 1.0, "slots": normal_siege}),
		ContentDefinition.new(KIND_ENCOUNTER, "normal_pressure", {"id": "normal_pressure", "name": "压迫小队", "hpScale": 1.0, "atkScale": 1.0, "slots": normal_pressure}),
		ContentDefinition.new(KIND_ENCOUNTER, "normal_phalanx", {"id": "normal_phalanx", "name": "方阵推进", "hpScale": 1.0, "atkScale": 1.0, "slots": normal_phalanx}),
		ContentDefinition.new(KIND_ENCOUNTER, "elite_devourer", {"id": "elite_devourer", "name": "噬元兽精英", "hpScale": 1.0, "atkScale": 1.0, "slots": elite_devourer}),
		ContentDefinition.new(KIND_ENCOUNTER, "elite_echo", {"id": "elite_echo", "name": "回响精英", "hpScale": 1.0, "atkScale": 1.0, "slots": elite_echo}),
		ContentDefinition.new(KIND_ENCOUNTER, "boss_devourer", {"id": "boss_devourer", "name": "噬元兽首领", "hpScale": 1.0, "atkScale": 1.0, "slots": boss_devourer}),
		ContentDefinition.new(KIND_ENCOUNTER, "boss_echo", {"id": "boss_echo", "name": "回响首领", "hpScale": 1.0, "atkScale": 1.0, "slots": boss_echo}),
		# These IDs remain resolvable only for pre-migration Run snapshots.
		# Fresh chapter encounter lists above never include them.
		ContentDefinition.new(KIND_ENCOUNTER, "normal", {
			"id": "normal", "name": "旧版普通战斗", "hpScale": 1.0, "atkScale": 1.0,
			"slots": [_slot(1, "旧版敌兵", 1.0, false), _slot(2, "旧版敌兵", 1.0, false), _slot(3, "旧版敌兵", 1.0, false), _slot(4, "旧版敌兵", 1.0, false), _slot(5, "旧版敌兵", 1.0, false), _slot(6, "旧版敌兵", 1.0, false)],
		}),
		ContentDefinition.new(KIND_ENCOUNTER, "elite_core", {
			"id": "elite_core", "name": "旧版精英核心", "hpScale": 1.0, "atkScale": 1.0,
			"slots": [_slot(1, "肉鸽精英", 1.6, false), _slot(2, "肉鸽精英", 1.6, false), _slot(3, "肉鸽精英", 1.6, false), _slot(4, "空位", 1.0, true), _slot(5, "空位", 1.0, true), _slot(6, "空位", 1.0, true)],
		}),
		ContentDefinition.new(KIND_ENCOUNTER, "boss_core", {
			"id": "boss_core", "name": "旧版首领", "hpScale": 1.0, "atkScale": 1.0,
			"slots": [_slot(1, "肉鸽Boss", 5.0, false), _slot(2, "空位", 1.0, true), _slot(3, "空位", 1.0, true), _slot(4, "空位", 1.0, true), _slot(5, "空位", 1.0, true), _slot(6, "空位", 1.0, true)],
		}),
		ContentDefinition.new(KIND_SHENTONG, "charge", {
			"id": "charge", "name": "蓄势",
			"description": "全体消耗本回合行动，回复存活棋子并延长敌方灼烧；本回合减伤，下一有效回合增伤。",
			"restriction": "必须是本回合第一个玩家行动。", "usesPerBattle": 1,
			"handler_id": "shentong.charge",
		}),
		ContentDefinition.new(KIND_SHENTONG, "assault", {
			"id": "assault", "name": "突击",
			"description": "选择可释放专属技的弈者免费施放，并强化该次伤害。",
			"restriction": "需要至少一名上阵弈者当前可释放主动专属技。", "usesPerBattle": 1,
			"handler_id": "shentong.assault",
		}),
		ContentDefinition.new(KIND_SHENTONG, "sacrifice", {
			"id": "sacrifice", "name": "献祭",
			"description": "献祭生命比例最低的存活棋子，获得技能点并为随机上阵弈者回复能量。",
			"restriction": "场上必须有可献祭的存活我方棋子。", "usesPerBattle": 2,
			"handler_id": "shentong.sacrifice",
		}),
	]
