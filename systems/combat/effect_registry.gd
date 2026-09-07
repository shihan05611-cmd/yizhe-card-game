class_name EffectRegistry
extends RefCounted

const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")

## Handler signature: handler(context: Dictionary, ports: CombatPorts) must return
## exactly {ok:true,value} or {ok:false,error}. GDScript has no general catch, so
## handlers must never raise runtime errors and their declared signature must match.
## Each B3 module owns its handler map; B3-6 is responsible for the final total map.

var _handlers: Dictionary = {}
var _registration_in_progress := false
var _execution_in_progress := false


func register_map(handler_map: Variant, errors: Array[String] = []) -> bool:
	return merge([handler_map], errors)


func merge(handler_maps: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if _registration_in_progress or _execution_in_progress:
		errors.append("effect registry rejects reentrant registration")
		return false
	_registration_in_progress = true
	var succeeded := _merge_once(handler_maps, errors)
	_registration_in_progress = false
	return succeeded


func handler_ids() -> Array[String]:
	var result: Array[String] = []
	for id: Variant in _handlers:
		result.append(id)
	result.sort()
	return result


func handlers_snapshot() -> Dictionary:
	return _handlers.duplicate(false)


func has(effect_id: Variant) -> bool:
	return typeof(effect_id) == TYPE_STRING and _handlers.has(effect_id)


func get_handler(effect_id: Variant, errors: Array[String] = []) -> Callable:
	errors.clear()
	if typeof(effect_id) != TYPE_STRING or effect_id != effect_id.strip_edges() or effect_id.is_empty():
		errors.append("effect id must be a non-empty trimmed string")
		return Callable()
	if not _handlers.has(effect_id):
		errors.append("unknown effect id: %s" % effect_id)
		return Callable()
	return _handlers[effect_id]


func execute(
	effect_id: Variant,
	context: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if _execution_in_progress or _registration_in_progress:
		return _reject("effect registry rejects reentrant execution", errors)
	var handler: Callable = get_handler(effect_id, errors)
	if not handler.is_valid():
		return CombatPortsScript.fail(errors[0] if not errors.is_empty() else "effect handler is unavailable")
	if typeof(context) != TYPE_DICTIONARY:
		return _reject("effect context must be a Dictionary", errors)
	if (
		typeof(ports) != TYPE_OBJECT
		or ports == null
		or ports.get_script() != CombatPortsScript
		or ports.is_valid() != true
	):
		return _reject("effect execution requires valid CombatPorts", errors)
	_execution_in_progress = true
	var result: Variant = handler.call(context, ports)
	_execution_in_progress = false
	if not CombatPortsScript.is_result(result):
		return _reject("effect handler %s returned a non-canonical result" % effect_id, errors)
	if result["ok"]:
		return CombatPortsScript.ok(result["value"])
	return CombatPortsScript.fail(result["error"])


func _merge_once(handler_maps: Variant, errors: Array[String]) -> bool:
	if typeof(handler_maps) != TYPE_ARRAY or handler_maps.is_empty():
		errors.append("handler_maps must be a non-empty Array")
		return false
	var pending: Dictionary = {}
	for map_index in handler_maps.size():
		var handler_map: Variant = handler_maps[map_index]
		if typeof(handler_map) != TYPE_DICTIONARY or handler_map.is_empty():
			errors.append("handler_maps[%d] must be a non-empty Dictionary" % map_index)
			continue
		for effect_id: Variant in handler_map:
			if typeof(effect_id) != TYPE_STRING or effect_id != effect_id.strip_edges() or effect_id.is_empty():
				errors.append("handler_maps[%d] contains an invalid effect id" % map_index)
				continue
			var handler: Variant = handler_map[effect_id]
			if typeof(handler) != TYPE_CALLABLE or not handler.is_valid():
				errors.append("effect handler %s must be a valid Callable" % effect_id)
				continue
			if _handlers.has(effect_id) or pending.has(effect_id):
				errors.append("duplicate effect id: %s" % effect_id)
				continue
			pending[effect_id] = handler
	if not errors.is_empty():
		return false
	var next := _handlers.duplicate(false)
	for effect_id in pending:
		next[effect_id] = pending[effect_id]
	_handlers = next
	return true


static func _reject(message: String, errors: Array[String]) -> Dictionary:
	errors.append(message)
	return CombatPortsScript.fail(message)
