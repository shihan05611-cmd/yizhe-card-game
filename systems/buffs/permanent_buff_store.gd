class_name PermanentBuffStore
extends RefCounted

const BuffDefinition = preload("res://data/definitions/buff_definition.gd")

const PERSISTENCE_BATTLE := "battle"
const PERSISTENCE_PERMANENT := "permanent"
const TARGET_PIECE_SLOT := "pieceSlot"
const TARGET_HERO := "hero"
const MAX_SAFE_INTEGER := 9007199254740991
const DANGEROUS_KEYS := ["__proto__", "constructor", "prototype"]

var _run_state: Dictionary
var _authority: Dictionary = {}
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("permanent Buff store config must be a Dictionary")
		return
	var run_state_value: Variant = config.get("run_state")
	if typeof(run_state_value) != TYPE_DICTIONARY:
		errors.append("run_state must be an explicitly injected Dictionary")
		return
	var authority := _build_authority(
		config.get("catalog"), config.get("valid_hero_ids"), errors
	)
	if not errors.is_empty():
		return
	if not run_state_value.has("permanent_buffs"):
		errors.append("run_state.permanent_buffs is required")
		return
	if typeof(run_state_value["permanent_buffs"]) != TYPE_ARRAY:
		errors.append("run_state.permanent_buffs must be an Array")
		return
	var canonical := _merge_instances(run_state_value["permanent_buffs"], authority, errors)
	if not errors.is_empty():
		return
	_run_state = run_state_value
	_authority = authority
	# Construction canonicalizes only after the complete backing array succeeds.
	_run_state["permanent_buffs"] = _clone_instances(canonical)
	_valid = true


func is_valid() -> bool:
	return _valid


func list(errors: Array[String] = []) -> Array[Dictionary]:
	errors.clear()
	var current := _current_instances(errors)
	if not errors.is_empty():
		return []
	var normalized := _merge_instances(current, _authority, errors)
	return _clone_instances(normalized) if errors.is_empty() else []


func get_stacks(request: Variant, errors: Array[String] = []) -> int:
	errors.clear()
	var current := _current_instances(errors)
	if not errors.is_empty():
		return 0
	var normalized := _merge_instances(current, _authority, errors)
	var query := _copy_request(request, _authority, false, errors)
	if not errors.is_empty():
		return 0
	var identity := _identity_of(query)
	for instance: Dictionary in normalized:
		if _identity_of(instance) == identity:
			return instance["stacks"]
	return 0


func add_buff(request: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	var current := _current_instances(errors)
	if not errors.is_empty():
		return {}
	var normalized := _merge_instances(current, _authority, errors)
	var addition := _copy_request(request, _authority, true, errors)
	if not errors.is_empty():
		return {}
	var identity := _identity_of(addition)
	var stored: Dictionary = {}
	for instance: Dictionary in normalized:
		if _identity_of(instance) != identity:
			continue
		var definition: Dictionary = _authority["definitions"][addition["id"]]
		var next_stacks := _add_stacks(
			instance["stacks"], addition["stacks"], definition,
			"permanent_buff.stacks", errors,
		)
		if not errors.is_empty():
			return {}
		instance["stacks"] = next_stacks
		stored = instance
		break
	if stored.is_empty():
		stored = _clone_instance(addition)
		normalized.append(stored)
	# The injected run_state is the sole intentional mutable reference.
	_run_state["permanent_buffs"] = _clone_instances(normalized)
	return _clone_instance(stored)


static func normalize_instances(
	instances: Variant,
	catalog: Variant,
	valid_hero_ids: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	errors.clear()
	var authority := _build_authority(catalog, valid_hero_ids, errors)
	if not errors.is_empty():
		return []
	return _merge_instances(instances, authority, errors)


static func merge_instances(
	instances: Variant,
	catalog: Variant,
	valid_hero_ids: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	return normalize_instances(instances, catalog, valid_hero_ids, errors)


static func get_stacks_from_instances(
	instances: Variant,
	request: Variant,
	catalog: Variant,
	valid_hero_ids: Variant,
	errors: Array[String] = [],
) -> int:
	errors.clear()
	var authority := _build_authority(catalog, valid_hero_ids, errors)
	if not errors.is_empty():
		return 0
	var normalized := _merge_instances(instances, authority, errors)
	var query := _copy_request(request, authority, false, errors)
	if not errors.is_empty():
		return 0
	var identity := _identity_of(query)
	for instance: Dictionary in normalized:
		if _identity_of(instance) == identity:
			return instance["stacks"]
	return 0


static func add_to_instances(
	instances: Variant,
	request: Variant,
	catalog: Variant,
	valid_hero_ids: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	errors.clear()
	var authority := _build_authority(catalog, valid_hero_ids, errors)
	if not errors.is_empty():
		return []
	var normalized := _merge_instances(instances, authority, errors)
	var addition := _copy_request(request, authority, true, errors)
	if not errors.is_empty():
		return []
	var identity := _identity_of(addition)
	for instance: Dictionary in normalized:
		if _identity_of(instance) != identity:
			continue
		instance["stacks"] = _add_stacks(
			instance["stacks"], addition["stacks"],
			authority["definitions"][addition["id"]],
			"permanent_buff.stacks", errors,
		)
		return [] if not errors.is_empty() else _clone_instances(normalized)
	normalized.append(_clone_instance(addition))
	return _clone_instances(normalized)


static func stack_limit_for(definition: Variant, errors: Array[String] = []) -> int:
	errors.clear()
	var normalized := _snapshot_definition(definition, "definition", errors)
	if not errors.is_empty():
		return 0
	var declared_limit: int = (
		normalized["max_stacks"] if normalized["max_stacks"] > 0 else MAX_SAFE_INTEGER
	)
	return declared_limit if normalized["stackable"] else mini(1, declared_limit)


func _current_instances(errors: Array[String]) -> Array:
	if not _valid:
		errors.append("permanent Buff store config is invalid")
		return []
	if not _run_state.has("permanent_buffs"):
		errors.append("run_state.permanent_buffs is required")
		return []
	if typeof(_run_state["permanent_buffs"]) != TYPE_ARRAY:
		errors.append("run_state.permanent_buffs must be an Array")
		return []
	return _run_state["permanent_buffs"]


static func _build_authority(
	catalog: Variant,
	valid_hero_ids: Variant,
	errors: Array[String],
) -> Dictionary:
	if typeof(catalog) != TYPE_DICTIONARY:
		errors.append("catalog must be an explicitly injected Dictionary")
		return {}
	var definitions := {}
	for key: Variant in catalog:
		if typeof(key) != TYPE_STRING or String(key).is_empty():
			errors.append("catalog keys must be non-empty strings")
			continue
		if key in DANGEROUS_KEYS:
			errors.append("catalog.%s uses a dangerous key" % key)
			continue
		var definition := _snapshot_definition(catalog[key], "catalog.%s" % key, errors)
		if definition.is_empty():
			continue
		if definition["id"] != key:
			errors.append("catalog.%s.id must match its catalog key" % key)
			continue
		definitions[key] = definition
	if typeof(valid_hero_ids) != TYPE_ARRAY:
		errors.append("valid_hero_ids must be an explicitly injected Array")
		return {}
	var seen: Array = []
	_assert_json_safe(valid_hero_ids, "valid_hero_ids", seen, errors)
	var hero_ids := {}
	for hero_id: Variant in valid_hero_ids:
		var normalized_id := _positive_safe_integer(hero_id, "valid_hero_ids entry", errors)
		if normalized_id > 0:
			hero_ids[normalized_id] = true
	if not errors.is_empty():
		return {}
	return {"definitions": definitions.duplicate(true), "hero_ids": hero_ids.duplicate()}


static func _snapshot_definition(
	definition: Variant,
	path: String,
	errors: Array[String],
) -> Dictionary:
	if not definition is Resource or definition.get_script() != BuffDefinition:
		errors.append("%s must be an M1 BuffDefinition resource" % path)
		return {}
	if typeof(definition.id) != TYPE_STRING or definition.id.is_empty():
		errors.append("%s.id must be a non-empty string" % path)
		return {}
	if definition.persistence not in [PERSISTENCE_BATTLE, PERSISTENCE_PERMANENT]:
		errors.append("%s.persistence must be battle or permanent" % path)
	if typeof(definition.target_types) != TYPE_ARRAY:
		errors.append("%s.target_types must be an Array" % path)
		return {}
	var target_types: Array[String] = []
	for index in range(definition.target_types.size()):
		var target_type: Variant = definition.target_types[index]
		if target_type not in [TARGET_PIECE_SLOT, TARGET_HERO]:
			errors.append("%s.target_types[%d] must be pieceSlot or hero" % [path, index])
			continue
		if target_type in target_types:
			errors.append("%s.target_types must not contain duplicates" % path)
			continue
		target_types.append(target_type)
	if definition.persistence == PERSISTENCE_PERMANENT and target_types.is_empty():
		errors.append("%s.target_types must declare a target for a permanent Buff" % path)
	if typeof(definition.stackable) != TYPE_BOOL:
		errors.append("%s.stackable must be a boolean" % path)
	if typeof(definition.max_stacks) != TYPE_INT or definition.max_stacks < 0 or definition.max_stacks > MAX_SAFE_INTEGER:
		errors.append("%s.max_stacks must be a non-negative safe integer" % path)
	if not errors.is_empty():
		return {}
	return {
		"id": definition.id,
		"persistence": definition.persistence,
		"target_types": target_types.duplicate(),
		"stackable": definition.stackable,
		"max_stacks": definition.max_stacks,
	}


static func _definition_for(id: Variant, authority: Dictionary, errors: Array[String]) -> Dictionary:
	if typeof(id) != TYPE_STRING or String(id).is_empty():
		errors.append("permanent_buff.id must be a non-empty string")
		return {}
	var definition: Variant = authority["definitions"].get(id)
	if definition == null:
		errors.append("permanent_buff.id references unknown Buff (%s)" % id)
		return {}
	if definition["persistence"] != PERSISTENCE_PERMANENT:
		errors.append("permanent_buff.id references non-permanent Buff (%s)" % id)
		return {}
	return definition


static func _stack_limit(definition: Dictionary) -> int:
	var declared_limit: int = (
		definition["max_stacks"] if definition["max_stacks"] > 0 else MAX_SAFE_INTEGER
	)
	return declared_limit if definition["stackable"] else mini(1, declared_limit)


static func _within_stack_limit(
	stacks: int,
	definition: Dictionary,
	path: String,
	errors: Array[String],
) -> int:
	var limit := _stack_limit(definition)
	if stacks <= limit:
		return stacks
	if definition["stackable"]:
		errors.append("%s exceeds max_stacks %d for Buff %s" % [path, limit, definition["id"]])
	else:
		errors.append("%s exceeds the non-stackable limit of 1 for Buff %s" % [path, definition["id"]])
	return 0


static func _add_stacks(
	current: int,
	addition: int,
	definition: Dictionary,
	path: String,
	errors: Array[String],
) -> int:
	if current > MAX_SAFE_INTEGER - addition:
		errors.append("%s would overflow the maximum safe integer" % path)
		return 0
	return _within_stack_limit(current + addition, definition, path, errors)


static func _copy_target(
	target: Variant,
	definition: Dictionary,
	authority: Dictionary,
	path: String,
	errors: Array[String],
) -> Dictionary:
	if typeof(target) != TYPE_DICTIONARY:
		errors.append("%s must be a Dictionary" % path)
		return {}
	if not _assert_exact_keys(target, ["type", "id"], path, errors):
		return {}
	var target_type: Variant = target["type"]
	if target_type not in [TARGET_PIECE_SLOT, TARGET_HERO]:
		errors.append("%s.type must be pieceSlot or hero" % path)
		return {}
	if target_type not in definition["target_types"]:
		errors.append("%s.type is not allowed by Buff %s" % [path, definition["id"]])
		return {}
	var target_id := _positive_safe_integer(target["id"], "%s.id" % path, errors)
	if not errors.is_empty():
		return {}
	if target_type == TARGET_PIECE_SLOT and target_id > 6:
		errors.append("%s.id must be a piece slot from 1 to 6" % path)
		return {}
	if target_type == TARGET_HERO and not authority["hero_ids"].has(target_id):
		errors.append("%s.id is not an authoritative hero ID (%d)" % [path, target_id])
		return {}
	return {"type": target_type, "id": target_id}


static func _copy_instance(
	value: Variant,
	authority: Dictionary,
	path: String,
	errors: Array[String],
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be a Dictionary" % path)
		return {}
	if not _assert_exact_keys(value, ["id", "target", "stacks"], path, errors):
		return {}
	var definition := _definition_for(value["id"], authority, errors)
	if definition.is_empty():
		return {}
	var target := _copy_target(value["target"], definition, authority, "%s.target" % path, errors)
	var stacks := _positive_safe_integer(value["stacks"], "%s.stacks" % path, errors)
	if not errors.is_empty():
		return {}
	stacks = _within_stack_limit(stacks, definition, "%s.stacks" % path, errors)
	if not errors.is_empty():
		return {}
	return {"id": definition["id"], "target": target, "stacks": stacks}


static func _copy_request(
	value: Variant,
	authority: Dictionary,
	with_stacks: bool,
	errors: Array[String],
) -> Dictionary:
	var seen: Array = []
	_assert_json_safe(value, "permanent_buff", seen, errors)
	if not errors.is_empty():
		return {}
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("permanent_buff must be a Dictionary")
		return {}
	var expected := ["id", "target", "stacks"] if with_stacks else ["id", "target"]
	if not _assert_exact_keys(value, expected, "permanent_buff", errors):
		return {}
	var definition := _definition_for(value["id"], authority, errors)
	if definition.is_empty():
		return {}
	var target := _copy_target(value["target"], definition, authority, "permanent_buff.target", errors)
	if not errors.is_empty():
		return {}
	var result := {"id": definition["id"], "target": target}
	if with_stacks:
		var stacks := _positive_safe_integer(value["stacks"], "permanent_buff.stacks", errors)
		if errors.is_empty():
			stacks = _within_stack_limit(stacks, definition, "permanent_buff.stacks", errors)
		if not errors.is_empty():
			return {}
		result["stacks"] = stacks
	return result


static func _merge_instances(
	instances: Variant,
	authority: Dictionary,
	errors: Array[String],
) -> Array[Dictionary]:
	var seen_references: Array = []
	_assert_json_safe(instances, "permanent_buffs", seen_references, errors)
	if not errors.is_empty():
		return []
	if typeof(instances) != TYPE_ARRAY:
		errors.append("permanent_buffs must be an Array")
		return []
	var merged: Array[Dictionary] = []
	var indexes := {}
	for index in range(instances.size()):
		var instance := _copy_instance(
			instances[index], authority, "permanent_buffs[%d]" % index, errors
		)
		if not errors.is_empty():
			return []
		var identity := _identity_of(instance)
		if not indexes.has(identity):
			indexes[identity] = merged.size()
			merged.append(instance)
			continue
		var existing_index: int = indexes[identity]
		var definition: Dictionary = authority["definitions"][instance["id"]]
		merged[existing_index]["stacks"] = _add_stacks(
			merged[existing_index]["stacks"], instance["stacks"], definition,
			"permanent_buffs[%d].stacks" % index, errors,
		)
		if not errors.is_empty():
			return []
	return _clone_instances(merged)


static func _identity_of(instance: Dictionary) -> String:
	return "%s|%s|%d" % [instance["id"], instance["target"]["type"], instance["target"]["id"]]


static func _clone_instance(instance: Dictionary) -> Dictionary:
	return {
		"id": instance["id"],
		"target": {
			"type": instance["target"]["type"],
			"id": instance["target"]["id"],
		},
		"stacks": instance["stacks"],
	}


static func _clone_instances(instances: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for instance: Dictionary in instances:
		result.append(_clone_instance(instance))
	return result


static func _assert_exact_keys(
	value: Dictionary,
	expected_keys: Array,
	path: String,
	errors: Array[String],
) -> bool:
	for key: Variant in value:
		if typeof(key) != TYPE_STRING:
			errors.append("%s contains a non-string JSON key" % path)
		elif key not in expected_keys:
			errors.append("%s.%s is an unknown field" % [path, key])
	for key: String in expected_keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
	return errors.is_empty()


static func _positive_safe_integer(value: Variant, path: String, errors: Array[String]) -> int:
	if typeof(value) == TYPE_INT:
		if value > 0 and value <= MAX_SAFE_INTEGER:
			return value
		errors.append("%s must be a positive safe integer" % path)
		return 0
	if typeof(value) == TYPE_FLOAT:
		if not is_finite(value):
			errors.append("%s must be a finite number" % path)
			return 0
		if value > 0.0 and value <= float(MAX_SAFE_INTEGER) and value == floorf(value):
			return int(value)
		errors.append("%s must be a positive safe integer" % path)
		return 0
	errors.append("%s must be a positive safe integer" % path)
	return 0


static func _assert_json_safe(
	value: Variant,
	path: String,
	seen: Array,
	errors: Array[String],
) -> void:
	if value == null or typeof(value) in [TYPE_STRING, TYPE_BOOL, TYPE_INT]:
		return
	if typeof(value) == TYPE_FLOAT:
		if not is_finite(value):
			errors.append("%s must be a finite number" % path)
		elif value == 0.0 and str(value).begins_with("-"):
			errors.append("%s must not be negative zero" % path)
		return
	if typeof(value) not in [TYPE_ARRAY, TYPE_DICTIONARY]:
		errors.append("%s contains a non-JSON value" % path)
		return
	for previous: Variant in seen:
		if is_same(previous, value):
			errors.append("%s contains a circular or shared reference" % path)
			return
	seen.append(value)
	if typeof(value) == TYPE_ARRAY:
		for index in range(value.size()):
			_assert_json_safe(value[index], "%s[%d]" % [path, index], seen, errors)
		return
	for key: Variant in value:
		if typeof(key) != TYPE_STRING:
			errors.append("%s contains a non-string JSON key" % path)
			continue
		if key in DANGEROUS_KEYS:
			errors.append("%s.%s uses a dangerous key" % [path, key])
		_assert_json_safe(value[key], "%s.%s" % [path, key], seen, errors)
