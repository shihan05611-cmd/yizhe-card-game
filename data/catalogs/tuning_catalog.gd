class_name TuningCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const TuningValue = preload("res://data/definitions/tuning_value_definition.gd")


static func build() -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(), errors)


static func build_from(definitions: Array, errors: Array[String]) -> Dictionary:
	errors.clear()
	var seen := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != TuningValue:
			errors.append("tuning entries must be TuningValueDefinition resources")
			continue
		var definition: Variant = raw_definition
		var id_valid := Validation.non_empty_id(definition.id, "tuning", errors)
		if id_valid:
			Validation.unique_id(definition.id, seen, "tuning", errors)
		if definition.id == "fateFixedOrder":
			if typeof(definition.value) != TYPE_STRING:
				errors.append("tuning fateFixedOrder must be a string")
		else:
			Validation.non_negative_number(
				definition.value,
				"tuning %s" % definition.id,
				errors,
			)
	if not errors.is_empty():
		return {}

	var catalog := {}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.id] = definition.snapshot()
	return catalog


static func values(catalog: Dictionary) -> Dictionary:
	var snapshot := {}
	for id in catalog:
		var definition: Variant = catalog[id]
		if definition is Resource and definition.get_script() == TuningValue:
			snapshot[id] = definition.value
	return snapshot


static func _source_definitions() -> Array:
	return [
		TuningValue.new("allyBaseHp", 360),
		TuningValue.new("allyBaseAtk", 32),
		TuningValue.new("allyBaseBlock", 0.05),
		TuningValue.new("allyBaseCrit", 0.05),
		TuningValue.new("enemyBaseHp", 360),
		TuningValue.new("enemyBaseAtk", 30),
		TuningValue.new("enemyBaseBlock", 0.05),
		TuningValue.new("enemyBaseCrit", 0.05),
		TuningValue.new("yizheBaseCrit", 0.05),
		TuningValue.new("burnTickPerStack", 2),
		TuningValue.new("burnDetonatePerStack", 5),
		TuningValue.new("burnBonusChance", 0.3),
		TuningValue.new("burnBaseDuration", 2),
		TuningValue.new("burn01DurationBonus", 2),
		TuningValue.new("counterDamageRatio", 0.4),
		TuningValue.new("superCounterDamageRatio", 2.0),
		TuningValue.new("counterAuraBlockBonus", 0.1),
		TuningValue.new("tempBlockBonus", 0.15),
		TuningValue.new("pieceDamageUpRatio", 0.25),
		TuningValue.new("pursuitDamageRatio", 0.5),
		TuningValue.new("enchantStackCap", 5),
		TuningValue.new("skipRecover", 1),
		TuningValue.new("roundRecover", 1),
		TuningValue.new("ascendCost", 2),
		TuningValue.new("ascendAtkBonus", 0),
		TuningValue.new("ascendHpBonus", 80),
		TuningValue.new("ascendBlockBonus", 0.1),
		TuningValue.new("ascendRepeatAtkBonus", 1.5),
		TuningValue.new("ascendRepeatBlockBonus", 0.015),
		TuningValue.new("ascendRepeatCritBonus", 0.015),
		TuningValue.new("ascendRepeatMissingHpHealRatio", 0.05),
		TuningValue.new("fistMasteryDamageUpPerStack", 0.05),
		TuningValue.new("ultBurn01AtkFactor", 0.05),
		TuningValue.new("ultFateAllInTurns", 1),
		TuningValue.new("ultAscendHealRatio", 0.5),
		TuningValue.new("enemyUltAscendHealRatio", 0.25),
		TuningValue.new("ultAscendMarchTurns", 2),
		TuningValue.new("ultKnightSuperBonus", 0.25),
		TuningValue.new("ultFlameLeechRatio", 0.003),
		TuningValue.new("ultFlameLeechTurns", 2),
		TuningValue.new("ultBreakFormationTurns", 2),
		TuningValue.new("fateFixedOrder", ""),
	]
