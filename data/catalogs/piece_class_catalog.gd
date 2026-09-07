class_name PieceClassCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const PieceClass = preload("res://data/definitions/piece_class_definition.gd")


static func build() -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(), errors)


static func build_from(definitions: Array, errors: Array[String]) -> Dictionary:
	errors.clear()
	var seen := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != PieceClass:
			errors.append("piece class entries must be PieceClassDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.non_empty_id(definition.id, "piece class", errors):
			Validation.unique_id(definition.id, seen, "piece class", errors)
		Validation.non_empty_string(definition.name, "piece class name", errors)
		Validation.positive_int(definition.hp, "piece class hp", errors)
		Validation.non_negative_int(definition.attack, "piece class atk", errors)
		_validate_ratio(definition.block_bonus, "piece class blockBonus", errors)
		_validate_ratio(definition.crit_bonus, "piece class critBonus", errors)
		Validation.non_empty_string(definition.tip, "piece class tip", errors)
	if not errors.is_empty():
		return {}

	var catalog := {}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.id] = definition.snapshot()
	return catalog


static func build_default_ally_mapping(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return build_mapping_from({
		1: "shield",
		2: "shield",
		3: "shield",
		4: "crossbow",
		5: "crossbow",
		6: "crossbow",
	}, catalog, errors)


static func build_mapping_from(
	source_mapping: Dictionary,
	catalog: Dictionary,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	if source_mapping.size() != 6:
		errors.append("default ally piece class mapping must contain exactly 6 slots")
	for slot in range(1, 7):
		if not source_mapping.has(slot):
			errors.append("default ally piece class mapping is missing slot %d" % slot)
			continue
		var class_id: Variant = source_mapping[slot]
		if typeof(class_id) != TYPE_STRING or str(class_id).strip_edges().is_empty():
			errors.append("default ally piece class mapping slot %d must use a non-empty class id" % slot)
		elif not catalog.has(class_id):
			errors.append("default ally piece class mapping slot %d references unknown class: %s" % [slot, class_id])
	for raw_slot in source_mapping:
		if typeof(raw_slot) != TYPE_INT or raw_slot < 1 or raw_slot > 6:
			errors.append("default ally piece class mapping has invalid slot: %s" % str(raw_slot))
	if not errors.is_empty():
		return {}
	return source_mapping.duplicate(true)


static func _validate_ratio(value: Variant, field_name: String, errors: Array[String]) -> void:
	if not Validation.non_negative_number(value, field_name, errors):
		return
	if value > 1.0:
		errors.append("%s must not exceed 1" % field_name)


static func _source_definitions() -> Array:
	return [
		PieceClass.new("default", "默认", 360, 32, 0.0, 0.0, "生命360，攻击32。无特殊效果。"),
		PieceClass.new("shield", "甲卒", 450, 24, 0.10, 0.0, "生命450，攻击24。被动【坚阵】：天生+10%格挡。"),
		PieceClass.new("assassin", "死士", 240, 42, 0.0, 0.10, "生命240，攻击42。被动【破绽】：天生+10%暴击。"),
		PieceClass.new("crossbow", "机弩", 300, 30, 0.0, 0.0, "生命300，攻击30。被动【连发】：普攻75%倍率，50%概率追加一段50%追击。"),
		PieceClass.new("banner", "旗兵", 360, 26, 0.0, 0.0, "生命360，攻击26。被动【击鼓】：行动后为我方当前能量最高弈者回复4能量。"),
	]
