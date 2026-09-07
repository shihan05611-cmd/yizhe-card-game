class_name GrowthPort
extends RefCounted

const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const PermanentBuffStoreScript = preload("res://systems/buffs/permanent_buff_store.gd")
const BuffDefinition = preload("res://data/definitions/buff_definition.gd")

## M2 battle-draft adapter over the frozen B1 PermanentBuffStore shape. It owns
## no persistence: the injected run_state is a composition-root draft. A batch is
## fully preflighted through B1 helpers, then published with one array assignment.

const ACTION_PREVIEW := "preview_permanent_growth"
const ACTION_STAGE := "stage_permanent_growth"
const ACTION_GET_STACKS := "get_permanent_growth_stacks"
const ACTION_SNAPSHOT := "snapshot_permanent_growth"

var _run_state: Dictionary
var _catalog: Dictionary = {}
var _valid_hero_ids: Array = []
var _store: Variant = null
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("growth port config must be a Dictionary")
		return
	if not _exact_keys(config, ["run_state", "catalog", "valid_hero_ids"], "growth port config", errors):
		return
	if typeof(config["run_state"]) != TYPE_DICTIONARY:
		errors.append("growth port run_state must be an injected Dictionary")
		return
	if typeof(config["catalog"]) != TYPE_DICTIONARY:
		errors.append("growth port catalog must be an injected Dictionary")
		return
	if typeof(config["valid_hero_ids"]) != TYPE_ARRAY:
		errors.append("growth port valid_hero_ids must be an injected Array")
		return
	_catalog = _snapshot_catalog(config["catalog"], errors)
	_valid_hero_ids = config["valid_hero_ids"].duplicate(true)
	if not errors.is_empty():
		return
	_run_state = config["run_state"]
	_store = PermanentBuffStoreScript.new({
		"run_state": _run_state,
		"catalog": _catalog,
		"valid_hero_ids": _valid_hero_ids,
	}, errors)
	if not errors.is_empty() or _store == null or _store.get_script() != PermanentBuffStoreScript or not _store.is_valid():
		if errors.is_empty():
			errors.append("growth port requires a valid B1 PermanentBuffStore")
		return
	_valid = true


func is_valid() -> bool:
	return _valid


func action_map() -> Dictionary:
	return {
		ACTION_PREVIEW: Callable(self, "preview_batch"),
		ACTION_STAGE: Callable(self, "stage_batch"),
		ACTION_GET_STACKS: Callable(self, "get_stacks_action"),
		ACTION_SNAPSHOT: Callable(self, "snapshot_action"),
	}


func snapshot(errors: Array[String] = []) -> Array:
	errors.clear()
	if not _valid:
		errors.append("growth port config is invalid")
		return []
	return _store.list(errors)


func snapshot_action(request: Variant = {}) -> Dictionary:
	var errors: Array[String] = []
	if not _empty_request(request, "growth snapshot request", errors):
		return _fail(errors)
	var value := snapshot(errors)
	return _fail(errors) if not errors.is_empty() else CombatPortsScript.ok(value)


func get_stacks_action(request: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _valid:
		errors.append("growth port config is invalid")
		return _fail(errors)
	var value: int = _store.get_stacks(request, errors)
	return _fail(errors) if not errors.is_empty() else CombatPortsScript.ok(value)


func preview_batch(request: Variant) -> Dictionary:
	var errors: Array[String] = []
	var candidate := _candidate_for(request, errors)
	return _fail(errors) if not errors.is_empty() else CombatPortsScript.ok(candidate)


func stage_batch(request: Variant) -> Dictionary:
	var errors: Array[String] = []
	var before: Array = snapshot(errors)
	if not errors.is_empty():
		return _fail(errors)
	var candidate := _candidate_for(request, errors)
	if not errors.is_empty():
		return _fail(errors)
	# The B1 candidate was already validated in full. Publish once so malformed
	# later entries and overflow can never leave a partially staged draft.
	_run_state["permanent_buffs"] = candidate.duplicate(true)
	var published: Array = _store.list(errors)
	if not errors.is_empty() or published != candidate:
		# This branch indicates a broken frozen B1 contract, not caller input.
		_run_state["permanent_buffs"] = before.duplicate(true)
		return _fail(errors if not errors.is_empty() else ["growth stage publication disagrees with B1 Store"])
	return CombatPortsScript.ok(published)


func _candidate_for(request: Variant, errors: Array[String]) -> Array:
	if not _valid:
		errors.append("growth port config is invalid")
		return []
	if not _exact_keys(request, ["requests"], "growth batch request", errors):
		return []
	var requests: Variant = request["requests"]
	if typeof(requests) != TYPE_ARRAY or requests.is_empty():
		errors.append("growth batch requests must be a non-empty Array")
		return []
	var candidate: Array = _store.list(errors)
	if not errors.is_empty():
		return []
	var identities := {}
	for index in requests.size():
		var item: Variant = requests[index]
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("growth batch requests[%d] must be a Dictionary" % index)
			return []
		if not _exact_keys(item, ["id", "target", "stacks"], "growth batch requests[%d]" % index, errors):
			return []
		if typeof(item["target"]) != TYPE_DICTIONARY or not item["target"].has("type") or not item["target"].has("id"):
			errors.append("growth batch requests[%d].target is malformed" % index)
			return []
		var identity := "%s|%s|%s" % [str(item["id"]), str(item["target"]["type"]), str(item["target"]["id"])]
		if identities.has(identity):
			errors.append("growth batch contains duplicate request identity: %s" % identity)
			return []
		identities[identity] = true
		candidate = PermanentBuffStoreScript.add_to_instances(
			candidate, item, _catalog, _valid_hero_ids, errors
		)
		if not errors.is_empty():
			return []
	# Reconstructing an exact B1 Store validates the complete final shape before
	# the live battle draft changes.
	var probe_state := {"permanent_buffs": candidate.duplicate(true)}
	var probe := PermanentBuffStoreScript.new({
		"run_state": probe_state,
		"catalog": _catalog,
		"valid_hero_ids": _valid_hero_ids,
	}, errors)
	if not errors.is_empty() or probe == null or probe.get_script() != PermanentBuffStoreScript or not probe.is_valid():
		if errors.is_empty():
			errors.append("growth batch failed B1 final-shape validation")
		return []
	return probe.list(errors)


static func _snapshot_catalog(catalog: Dictionary, errors: Array[String]) -> Dictionary:
	var snapshot := {}
	for id: Variant in catalog:
		if typeof(id) != TYPE_STRING or String(id).is_empty():
			errors.append("growth port catalog ids must be non-empty strings")
			continue
		var definition: Variant = catalog[id]
		if not definition is Resource or definition.get_script() != BuffDefinition:
			errors.append("growth port catalog.%s must be an M1 BuffDefinition" % id)
			continue
		var copied: Variant = definition.snapshot()
		if not copied is Resource or copied.get_script() != BuffDefinition or is_same(copied, definition):
			errors.append("growth port catalog.%s snapshot is invalid" % id)
			continue
		snapshot[id] = copied
	return snapshot


static func _empty_request(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_DICTIONARY and value.is_empty():
		return true
	errors.append("%s must be an empty Dictionary" % path)
	return false


static func _exact_keys(value: Variant, keys: Array, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be a canonical Dictionary" % path)
		return false
	if value.size() != keys.size():
		errors.append("%s has a non-canonical field set" % path)
		return false
	for key in keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
			return false
	return true


static func _fail(errors: Array[String]) -> Dictionary:
	var message := "growth port request failed"
	if not errors.is_empty():
		message = errors[0]
	return CombatPortsScript.fail(message)
