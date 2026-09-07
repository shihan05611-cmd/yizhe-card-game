class_name CombatPorts
extends RefCounted

const BuffDefinition = preload("res://data/definitions/buff_definition.gd")
const ContentEventDefinition = preload("res://data/definitions/content_event_definition.gd")
const EnemyCharacterDefinition = preload("res://data/definitions/enemy_character_definition.gd")
const EnemySpecialDefinition = preload("res://data/definitions/enemy_special_definition.gd")
const HeroAbilityDefinition = preload("res://data/definitions/hero_ability_definition.gd")
const PieceClassDefinition = preload("res://data/definitions/piece_class_definition.gd")
const PlayerCharacterDefinition = preload("res://data/definitions/player_character_definition.gd")
const RelicDefinition = preload("res://data/definitions/relic_definition.gd")
const RoguelikeContentDefinition = preload("res://data/definitions/roguelike_content_definition.gd")
const SkillDefinition = preload("res://data/definitions/skill_definition.gd")
const StageDefinition = preload("res://data/definitions/stage_definition.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")

## Shared M2 boundary. Every external action has the single-argument signature
## action(request: Dictionary) -> {ok:true,value} | {ok:false,error}. GDScript
## cannot catch arbitrary runtime errors, so a port with a mismatched signature or
## one that throws is an application-boundary fault. Non-canonical results fail.
## Player SP payment, card ownership and action quotas deliberately do not exist
## in this contract; they belong to M3.

const REQUIRED_ACTION_IDS := [
	"emit_combat_event",
	"emit_content_event",
	"log",
	"on_battle_resolved",
	"record_damage",
	"record_heal",
	"resolve_battle_end",
]
const REQUIRED_SERVICE_IDS := [
	"combat_rng", "enemy_policy_rng", "damage", "buffs", "tuning", "catalogs",
]
const REQUIRED_RNG_METHODS := ["next", "int_range", "pick"]
const REQUIRED_DAMAGE_METHODS := ["is_valid", "apply", "kill"]
const REQUIRED_BUFF_METHODS := [
	"is_valid", "validate_unit_holder", "validate_side_state", "definition_for",
	"apply_unit", "apply_side", "clear_unit", "clear_side", "consume_unit",
	"consume_side", "duplicate_layers", "decay_layers", "decay_round", "reset_unit",
	"reset_sides", "get_unit_state", "get_unit_stacks", "get_unit_turns", "has_unit",
	"get_side_state", "get_side_stacks", "get_side_turns", "has_side",
]
const MAX_DATA_DEPTH := 128

var _actions: Dictionary = {}
var _services: Dictionary = {}
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if not _validate_config(config, errors):
		return
	_actions = config["actions"].duplicate(false)
	_services = config["services"].duplicate(false)
	# M1 data authorities are immutable inputs from the perspective of combat.
	# Preserve service Object identity, but own and return isolated data containers.
	var tuning_snapshot: Variant = _data_snapshot(
		config["services"]["tuning"], "services.tuning", errors
	)
	if not errors.is_empty():
		return
	var catalogs_snapshot: Variant = _data_snapshot(
		config["services"]["catalogs"], "services.catalogs", errors
	)
	if not errors.is_empty():
		return
	_services["tuning"] = tuning_snapshot
	_services["catalogs"] = catalogs_snapshot
	_valid = true


func is_valid() -> bool:
	return _valid


func action_ids() -> Array[String]:
	var result: Array[String] = []
	for id: Variant in _actions:
		result.append(id)
	result.sort()
	return result


func has_action(id: Variant) -> bool:
	return _valid and typeof(id) == TYPE_STRING and _actions.has(id)


func service(id: Variant, errors: Array[String] = []) -> Variant:
	errors.clear()
	if not _valid:
		errors.append("combat ports config is invalid")
		return null
	if typeof(id) != TYPE_STRING or not _services.has(id):
		errors.append("unknown combat service id: %s" % str(id))
		return null
	if id in ["tuning", "catalogs"]:
		var snapshot: Variant = _data_snapshot(_services[id], "services.%s" % id, errors)
		return null if not errors.is_empty() else snapshot
	return _services[id]


func call_action(
	action_id: Variant,
	request: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _valid:
		return _reject("combat ports config is invalid", errors)
	if typeof(action_id) != TYPE_STRING or not _actions.has(action_id):
		return _reject("unknown combat action id: %s" % str(action_id), errors)
	if typeof(request) != TYPE_DICTIONARY:
		return _reject("combat action request must be a Dictionary", errors)
	var result: Variant = _actions[action_id].call(request)
	if not is_result(result):
		return _reject("combat action %s returned a non-canonical result" % action_id, errors)
	if result["ok"]:
		return ok(result["value"])
	return fail(result["error"])


static func validate(config: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	return _validate_config(config, errors)


static func ok(value: Variant = null) -> Dictionary:
	return {"ok": true, "value": value}


static func fail(error: Variant) -> Dictionary:
	var message := str(error).strip_edges()
	if message.is_empty():
		message = "unspecified combat port failure"
	return {"ok": false, "error": message}


static func is_result(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or typeof(value.get("ok")) != TYPE_BOOL:
		return false
	if value["ok"]:
		return value.size() == 2 and value.has("value")
	return (
		value.size() == 2
		and value.has("error")
		and typeof(value["error"]) == TYPE_STRING
		and value["error"] == value["error"].strip_edges()
		and not value["error"].is_empty()
	)


static func _validate_config(config: Variant, errors: Array[String]) -> bool:
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("combat ports config must be a Dictionary")
		return false
	var actions: Variant = config.get("actions")
	var services: Variant = config.get("services")
	if typeof(actions) != TYPE_DICTIONARY:
		errors.append("combat ports actions must be an injected Dictionary")
		return false
	if typeof(services) != TYPE_DICTIONARY:
		errors.append("combat ports services must be an injected Dictionary")
		return false
	for action_id in REQUIRED_ACTION_IDS:
		if not _valid_callable(actions.get(action_id)):
			errors.append("actions.%s must be an injected valid Callable" % action_id)
	for action_id: Variant in actions:
		if typeof(action_id) != TYPE_STRING or action_id != action_id.strip_edges() or action_id.is_empty():
			errors.append("combat action ids must be non-empty trimmed strings")
		elif not _valid_callable(actions[action_id]):
			errors.append("actions.%s must be a valid Callable" % action_id)
	for service_id in REQUIRED_SERVICE_IDS:
		if not services.has(service_id):
			errors.append("services.%s is required" % service_id)
	if not errors.is_empty():
		return false
	var combat_rng: Variant = services["combat_rng"]
	var enemy_policy_rng: Variant = services["enemy_policy_rng"]
	if not _object_has_methods(combat_rng, REQUIRED_RNG_METHODS, "services.combat_rng", errors):
		return false
	if not _object_has_methods(enemy_policy_rng, REQUIRED_RNG_METHODS, "services.enemy_policy_rng", errors):
		return false
	if is_same(combat_rng, enemy_policy_rng):
		errors.append("combat_rng and enemy_policy_rng must be distinct injected streams")
		return false
	var damage: Variant = services["damage"]
	if not _object_has_methods(damage, REQUIRED_DAMAGE_METHODS, "services.damage", errors):
		return false
	var buffs: Variant = services["buffs"]
	if not _object_has_methods(buffs, REQUIRED_BUFF_METHODS, "services.buffs", errors):
		return false
	if typeof(services["tuning"]) != TYPE_DICTIONARY or services["tuning"].is_empty():
		errors.append("services.tuning must be an injected non-empty M1 tuning Dictionary")
	if typeof(services["catalogs"]) != TYPE_DICTIONARY or services["catalogs"].is_empty():
		errors.append("services.catalogs must be an injected non-empty M1 content Dictionary")
	if errors.is_empty():
		_validate_data_tree(services["tuning"], "services.tuning", errors)
		_validate_data_tree(services["catalogs"], "services.catalogs", errors)
	if errors.is_empty():
		# validate(config) exercises the same trusted snapshots as construction and
		# therefore catches broken M1 snapshot implementations without publishing.
		_data_snapshot(services["tuning"], "services.tuning", errors)
		if errors.is_empty():
			_data_snapshot(services["catalogs"], "services.catalogs", errors)
	# These are trusted internal B0/B1 services. Calling is_valid is safe only
	# because its zero-argument signature is part of the frozen shape above.
	if damage.is_valid() != true:
		errors.append("services.damage must be a valid B0 DamagePipeline")
	if buffs.is_valid() != true:
		errors.append("services.buffs must be a valid B1 BuffSystem")
	return errors.is_empty()


static func _object_has_methods(
	value: Variant,
	methods: Array,
	path: String,
	errors: Array[String],
) -> bool:
	if typeof(value) != TYPE_OBJECT or value == null:
		errors.append("%s must be an injected service Object" % path)
		return false
	for method in methods:
		if not value.has_method(method):
			errors.append("%s must provide %s" % [path, method])
	return errors.is_empty()


static func _valid_callable(value: Variant) -> bool:
	return typeof(value) == TYPE_CALLABLE and value.is_valid()


static func _validate_data_tree(
	value: Variant,
	path: String,
	errors: Array[String],
	depth: int = 0,
) -> bool:
	if depth > MAX_DATA_DEPTH:
		errors.append("%s exceeds the M1 data nesting limit" % path)
		return false
	if value is Resource:
		var resource_script: Variant = value.get_script()
		if not _is_allowed_m1_resource_script(resource_script):
			errors.append("%s contains a Resource outside the explicit M1 allowlist" % path)
			return false
		for property: Dictionary in resource_script.get_script_property_list():
			var property_name: String = str(property["name"])
			if not _validate_data_tree(value.get(property_name), "%s.%s" % [path, property_name], errors, depth + 1):
				return false
		return true
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			if is_finite(value):
				return true
			errors.append("%s contains a non-finite number" % path)
			return false
		TYPE_ARRAY:
			for index in value.size():
				if not _validate_data_tree(value[index], "%s[%d]" % [path, index], errors, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_INT]:
					errors.append("%s contains a non-scalar Dictionary key" % path)
					return false
				if not _validate_data_tree(value[key], "%s[%s]" % [path, str(key)], errors, depth + 1):
					return false
			return true
	errors.append("%s contains a non-M1 data value" % path)
	return false


static func _data_snapshot(
	value: Variant,
	path: String,
	errors: Array[String],
	depth: int = 0,
) -> Variant:
	if depth > MAX_DATA_DEPTH:
		errors.append("%s exceeds the M1 data nesting limit" % path)
		return null
	if value is Resource:
		var source_script: Variant = value.get_script()
		if not _is_allowed_m1_resource_script(source_script):
			errors.append("%s contains a Resource outside the explicit M1 allowlist" % path)
			return null
		# Exact script identity is checked before this trusted call. Unknown or
		# duck-typed Resources never have snapshot invoked.
		var copied: Variant = value.snapshot()
		if not copied is Resource or copied == null:
			errors.append("%s M1 snapshot must return a non-null Resource" % path)
			return null
		if is_same(value, copied):
			errors.append("%s M1 snapshot must return a new Resource identity" % path)
			return null
		if copied.get_script() != source_script:
			errors.append("%s M1 snapshot must preserve its definition script" % path)
			return null
		if not _validate_data_tree(copied, "%s.snapshot" % path, errors, depth + 1):
			return null
		if not _validate_snapshot_isolation(value, copied, path, errors, depth + 1):
			return null
		return copied
	if typeof(value) == TYPE_ARRAY:
		var copied_array: Array = []
		for index in value.size():
			copied_array.append(_data_snapshot(value[index], "%s[%d]" % [path, index], errors, depth + 1))
			if not errors.is_empty():
				return null
		return copied_array
	if typeof(value) == TYPE_DICTIONARY:
		var copied_dictionary := {}
		for key: Variant in value:
			if typeof(key) not in [TYPE_STRING, TYPE_INT]:
				errors.append("%s contains a non-scalar Dictionary key" % path)
				return null
			copied_dictionary[key] = _data_snapshot(value[key], "%s[%s]" % [path, str(key)], errors, depth + 1)
			if not errors.is_empty():
				return null
		return copied_dictionary
	# RNG and B0/B1 service Objects intentionally keep their injected identity.
	return value


static func _validate_snapshot_isolation(
	source: Variant,
	copied: Variant,
	path: String,
	errors: Array[String],
	depth: int,
) -> bool:
	if depth > MAX_DATA_DEPTH:
		errors.append("%s snapshot exceeds the M1 data nesting limit" % path)
		return false
	if source is Resource:
		if not copied is Resource or copied == null:
			errors.append("%s snapshot changed Resource shape" % path)
			return false
		if is_same(source, copied):
			errors.append("%s snapshot shares a nested Resource identity" % path)
			return false
		if source.get_script() != copied.get_script():
			errors.append("%s snapshot changed Resource script identity" % path)
			return false
		for property: Dictionary in source.get_script().get_script_property_list():
			var property_name: String = str(property["name"])
			if not _validate_snapshot_isolation(
				source.get(property_name), copied.get(property_name),
				"%s.%s" % [path, property_name], errors, depth + 1
			):
				return false
		return true
	if typeof(source) != typeof(copied):
		errors.append("%s snapshot changed value type" % path)
		return false
	if typeof(source) == TYPE_ARRAY:
		if is_same(source, copied):
			errors.append("%s snapshot shares an Array identity" % path)
			return false
		if source.size() != copied.size():
			errors.append("%s snapshot changed Array size" % path)
			return false
		for index in source.size():
			if not _validate_snapshot_isolation(source[index], copied[index], "%s[%d]" % [path, index], errors, depth + 1):
				return false
		return true
	if typeof(source) == TYPE_DICTIONARY:
		if is_same(source, copied):
			errors.append("%s snapshot shares a Dictionary identity" % path)
			return false
		if source.size() != copied.size():
			errors.append("%s snapshot changed Dictionary size" % path)
			return false
		for key: Variant in source:
			if not copied.has(key):
				errors.append("%s snapshot removed Dictionary key: %s" % [path, str(key)])
				return false
			if not _validate_snapshot_isolation(source[key], copied[key], "%s[%s]" % [path, str(key)], errors, depth + 1):
				return false
		return true
	if source != copied:
		errors.append("%s snapshot changed an authored value" % path)
		return false
	return true


static func _is_allowed_m1_resource_script(resource_script: Variant) -> bool:
	return (
		resource_script == BuffDefinition
		or resource_script == ContentEventDefinition
		or resource_script == EnemyCharacterDefinition
		or resource_script == EnemySpecialDefinition
		or resource_script == HeroAbilityDefinition
		or resource_script == PieceClassDefinition
		or resource_script == PlayerCharacterDefinition
		or resource_script == RelicDefinition
		or resource_script == RoguelikeContentDefinition
		or resource_script == SkillDefinition
		or resource_script == StageDefinition
		or resource_script == TuningValueDefinition
	)


static func _reject(message: String, errors: Array[String]) -> Dictionary:
	errors.append(message)
	return fail(message)
