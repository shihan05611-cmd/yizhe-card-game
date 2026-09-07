class_name EventCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const ContentEvent = preload("res://data/definitions/content_event_definition.gd")


static func build() -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(), errors)


static func build_from(definitions: Array, errors: Array[String]) -> Dictionary:
	errors.clear()
	var seen_ids := {}
	var seen_constants := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != ContentEvent:
			errors.append("event entries must be ContentEventDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.non_empty_id(definition.id, "event", errors):
			Validation.unique_id(definition.id, seen_ids, "event", errors)
		if Validation.non_empty_string(definition.constant_name, "event constant name", errors):
			Validation.unique_id(definition.constant_name, seen_constants, "event constant", errors)
	if not errors.is_empty():
		return {}

	var catalog := {}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.id] = definition.snapshot()
	return catalog


static func content_event(catalog: Dictionary) -> Dictionary:
	var source_enum := {}
	for definition in catalog.values():
		if definition is Resource and definition.get_script() == ContentEvent:
			source_enum[definition.constant_name] = definition.id
	return source_enum


static func types(catalog: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in catalog:
		result.append(id)
	return result


static func _source_definitions() -> Array:
	return [
		ContentEvent.new("BATTLE_START", "battleStart"),
		ContentEvent.new("ROUND_START", "roundStart"),
		ContentEvent.new("ROUND_END", "roundEnd"),
		ContentEvent.new("SKILL_POINT_SPENT", "skillPointSpent"),
		ContentEvent.new("BASIC_ATTACK_HIT", "basicAttackHit"),
		ContentEvent.new("PIECE_ATTACK_HIT", "pieceAttackHit"),
		ContentEvent.new("UNIT_DAMAGED", "unitDamaged"),
		ContentEvent.new("UNIT_BLOCKED", "unitBlocked"),
		ContentEvent.new("UNIT_DIED", "unitDied"),
		ContentEvent.new("ULTIMATE_CAST", "ultimateCast"),
		ContentEvent.new("EXCLUSIVE_CAST", "exclusiveCast"),
		ContentEvent.new("FREE_SKILL_CAST", "freeSkillCast"),
		ContentEvent.new("HP_THRESHOLD_CROSSED", "hpThresholdCrossed"),
	]
