class_name EnemySpecialCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const EnemySpecial = preload("res://data/definitions/enemy_special_definition.gd")
const ContentEvent = preload("res://data/definitions/content_event_definition.gd")
const PieceClass = preload("res://data/definitions/piece_class_definition.gd")

const CONDITION_IDS := "condition_ids"
const EFFECT_IDS := "effect_ids"


static func build(event_catalog: Dictionary, piece_class_catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return build_from(_source_definitions(), event_catalog, piece_class_catalog, reference_ids(), errors)


static func reference_ids() -> Dictionary:
	return {
		CONDITION_IDS: [
			"enemy_special.devourer.hook.0.when",
			"enemy_special.echo.hook.0.when",
		],
		EFFECT_IDS: [
			"enemy_special.devourer.hook.0.effect",
			"enemy_special.echo.hook.0.effect",
		],
	}


static func build_from(
	definitions: Array,
	event_catalog: Dictionary,
	piece_class_catalog: Dictionary,
	references: Dictionary,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	_validate_catalog_resources(event_catalog, ContentEvent, "event", errors)
	_validate_catalog_resources(piece_class_catalog, PieceClass, "piece class", errors)
	_validate_reference_registry(references, errors)
	var seen := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != EnemySpecial:
			errors.append("enemy special entries must be EnemySpecialDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.non_empty_id(definition.id, "enemy special", errors):
			Validation.unique_id(definition.id, seen, "enemy special", errors)
		Validation.non_empty_string(definition.name, "enemy special name", errors)
		Validation.positive_int(definition.grid_cells, "enemy special gridCells", errors)
		_validate_positive_number(definition.hp_scale, "enemy special hpScale", errors)
		_validate_positive_number(definition.atk_scale, "enemy special atkScale", errors)
		if definition.piece_class_id != null:
			if typeof(definition.piece_class_id) != TYPE_STRING or str(definition.piece_class_id).strip_edges().is_empty():
				errors.append("enemy special pieceClassId must be null or a non-empty string")
			elif not piece_class_catalog.has(definition.piece_class_id):
				errors.append("enemy special references unknown piece class: %s" % definition.piece_class_id)
		_validate_hooks(definition.id, definition.hooks, event_catalog, references, errors)
		if not definition.modifiers.is_empty():
			errors.append("enemy special modifiers must be empty for the current Web catalog")
	if not errors.is_empty():
		return {}

	var catalog := {}
	for raw_definition in definitions:
		var definition: Variant = raw_definition
		catalog[definition.id] = definition.snapshot()
	return catalog


static func _validate_catalog_resources(
	catalog: Dictionary,
	expected_script: Script,
	label: String,
	errors: Array[String],
) -> void:
	if catalog.is_empty():
		errors.append("enemy special %s catalog must not be empty" % label)
		return
	for id in catalog:
		var definition: Variant = catalog[id]
		if not definition is Resource or definition.get_script() != expected_script:
			errors.append("enemy special %s references must use the expected Resource definitions" % label)
		elif id != definition.id:
			errors.append("enemy special %s catalog key does not match definition id: %s" % [label, str(id)])


static func _validate_reference_registry(references: Dictionary, errors: Array[String]) -> void:
	for key in [CONDITION_IDS, EFFECT_IDS]:
		if not references.has(key) or typeof(references[key]) != TYPE_ARRAY:
			errors.append("enemy special reference registry is missing array: %s" % key)
			continue
		Validation.string_array(references[key], "enemy special %s" % key, errors)
		var seen := {}
		for reference_id in references[key]:
			Validation.unique_id(reference_id, seen, "enemy special %s" % key, errors)


static func _validate_positive_number(value: Variant, field_name: String, errors: Array[String]) -> void:
	if not Validation.finite_number(value, field_name, errors):
		return
	if value <= 0:
		errors.append("%s must be positive" % field_name)


static func _validate_hooks(
	special_id: String,
	hooks: Array[Dictionary],
	event_catalog: Dictionary,
	references: Dictionary,
	errors: Array[String],
) -> void:
	var seen_indices := {}
	for hook in hooks:
		for key in hook:
			if key not in ["event_id", "condition_id", "effect_id", "limit", "limit_value", "hook_index"]:
				errors.append("unknown enemy special hook metadata field: %s" % str(key))
		for required in ["event_id", "condition_id", "effect_id", "limit", "limit_value", "hook_index"]:
			if not hook.has(required):
				errors.append("enemy special %s hook is missing field: %s" % [special_id, required])
		if not hook.has("event_id") or not hook.has("condition_id") or not hook.has("effect_id"):
			continue
		var event_id: Variant = hook["event_id"]
		if typeof(event_id) != TYPE_STRING or str(event_id).strip_edges().is_empty():
			errors.append("enemy special hook event must be a non-empty string")
		elif not event_catalog.has(event_id):
			errors.append("enemy special references unknown hook event: %s" % event_id)
		_validate_reference(hook["condition_id"], references.get(CONDITION_IDS, []), "condition", errors)
		_validate_reference(hook["effect_id"], references.get(EFFECT_IDS, []), "effect", errors)
		if hook.get("limit") != "none":
			errors.append("enemy special hook limit must be none")
		Validation.positive_int(hook.get("limit_value"), "enemy special hook limitValue", errors)
		if Validation.non_negative_int(hook.get("hook_index"), "enemy special hookIndex", errors):
			Validation.unique_id(hook["hook_index"], seen_indices, "enemy special hook index", errors)


static func _validate_reference(value: Variant, known_ids: Array, label: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty():
		errors.append("enemy special hook %s id must not be empty" % label)
		return
	if value not in known_ids:
		errors.append("enemy special hook references unknown %s: %s" % [label, value])


static func _source_definitions() -> Array:
	return [
		EnemySpecial.new("devourer", "噬元兽", 2, null, 2, 1, [{
			"event_id": "pieceAttackHit",
			"condition_id": "enemy_special.devourer.hook.0.when",
			"effect_id": "enemy_special.devourer.hook.0.effect",
			"limit": "none",
			"limit_value": 1,
			"hook_index": 0,
		}]),
		EnemySpecial.new("echo", "回响", 3, null, 3, 1, [{
			"event_id": "unitDamaged",
			"condition_id": "enemy_special.echo.hook.0.when",
			"effect_id": "enemy_special.echo.hook.0.effect",
			"limit": "none",
			"limit_value": 1,
			"hook_index": 0,
		}]),
	]
