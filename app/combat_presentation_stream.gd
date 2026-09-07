class_name CombatPresentationStream
extends RefCounted

const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")

const EVENT_KINDS := ["damage", "heal", "buff", "round", "card", "log", "fatal", "combat"]

var _sequence := 0
var _batch_sequence := 0
var _batch_id := "batch-00000000"
var _events: Array[Dictionary] = []
var _acknowledged_sequence := 0


func begin_batch(_reason: String) -> String:
	_batch_sequence += 1
	_batch_id = "batch-%08d" % _batch_sequence
	return _batch_id


func append(
	kind: String,
	event_id: String,
	source: Dictionary,
	visual_target: Dictionary,
	payload: Dictionary,
) -> Dictionary:
	assert(kind in EVENT_KINDS)
	assert(not event_id.strip_edges().is_empty())
	_sequence += 1
	var event := {
		"sequence": _sequence,
		"batch_id": _batch_id,
		"event_id": event_id,
		"kind": kind,
		"source": source.duplicate(true),
		"visual_target": visual_target.duplicate(true),
		"payload": _json_snapshot(payload),
	}
	assert(_is_json_safe(event))
	_events.append(event)
	return event.duplicate(true)


func capture_damage(event_id: String, payload: Dictionary) -> void:
	append(
		"damage",
		event_id,
		_source_from_payload(payload, "damage"),
		_target_from_payload(payload),
		_without_live_references(payload),
	)


func capture_buff(event_id: String, payload: Dictionary) -> void:
	append(
		"buff",
		event_id,
		_system_source("buff"),
		_buff_target(payload),
		_json_snapshot(payload),
	)


func capture_content(request: Dictionary) -> Dictionary:
	var event_id := str(request.get("event_id", ""))
	var payload: Dictionary = request.get("payload", {})
	var kind := "card" if event_id in ["freeSkillCast", "exclusiveCast", "ultimateCast"] else "round"
	append(
		kind,
		event_id,
		_source_from_payload(payload, "content"),
		_content_target(event_id, payload),
		payload,
	)
	return CombatPortsScript.ok(null)


func capture_combat(request: Dictionary) -> Dictionary:
	var event_id := str(request.get("event_id", request.get("event", "combatEvent")))
	append(
		"combat",
		event_id,
		_source_from_payload(request, "combat"),
		_target_from_payload(request),
		request,
	)
	return CombatPortsScript.ok(null)


func capture_log(request: Dictionary) -> Dictionary:
	append("log", "battleLog", _system_source("log"), _battle_target(), request)
	return CombatPortsScript.ok(null)


func capture_heal(request: Dictionary) -> Dictionary:
	append(
		"heal",
		"healApplied",
		_source_from_payload(request, "heal"),
		_target_from_payload(request),
		_without_live_references(request),
	)
	return CombatPortsScript.ok(null)


func capture_battle_resolved(request: Dictionary) -> Dictionary:
	append(
		"round", "battleResolved", _system_source("battle"), _battle_target(), request
	)
	return CombatPortsScript.ok(null)


func capture_fatal(code: String, message: String, details: Dictionary) -> Dictionary:
	return append(
		"fatal",
		"fatal",
		_system_source("application"),
		_battle_target(),
		{"code": code, "message": message, "details": details.duplicate(true)},
	)


func pending_events() -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for event: Dictionary in _events:
		if int(event["sequence"]) > _acknowledged_sequence:
			pending.append(event.duplicate(true))
	return pending


func all_events() -> Array[Dictionary]:
	return _events.duplicate(true)


func logs() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for event: Dictionary in _events:
		if event["kind"] == "log":
			values.append(event["payload"].duplicate(true))
	return values


func acknowledge_through(sequence: int) -> void:
	_acknowledged_sequence = clampi(sequence, _acknowledged_sequence, _sequence)


func sequence() -> int:
	return _sequence


static func _source_from_payload(payload: Dictionary, fallback: String) -> Dictionary:
	var effect: Variant = payload.get("effect_context")
	if typeof(effect) != TYPE_DICTIONARY:
		var damage_context: Variant = payload.get("damage_context")
		if typeof(damage_context) == TYPE_DICTIONARY:
			effect = damage_context.get("effect")
	if typeof(effect) != TYPE_DICTIONARY:
		effect = payload.get("source_effect")
	if typeof(effect) != TYPE_DICTIONARY:
		return _system_source(fallback)
	var source_type := str(effect.get("source_type", fallback))
	return {
		"type": source_type,
		"id": effect.get("source_id", fallback),
		"name": str(effect.get("source_name", "")),
		"side": str(effect.get("source_side", "unknown")),
		"actor_id": effect.get("source_actor_id", 0),
		"action_phase": _action_phase(source_type),
	}


static func _system_source(id: String) -> Dictionary:
	return {
		"type": "system",
		"id": id,
		"name": "",
		"side": "unknown",
		"actor_id": 0,
		"action_phase": "system",
	}


static func _action_phase(source_type: String) -> String:
	if source_type in ["basic_attack", "pursuit", "counter", "assist"]:
		return "piece_action"
	if source_type in ["free_skill", "exclusive_skill", "ultimate", "enemy_special"]:
		return "skill_action"
	if source_type in ["delayed_damage", "relic"]:
		return "effect_action"
	return "system"


static func _target_from_payload(payload: Dictionary) -> Dictionary:
	for key in ["target", "unit", "defender"]:
		var target: Variant = payload.get(key)
		if typeof(target) == TYPE_DICTIONARY:
			return _unit_target(target)
	if payload.has("target_id") and payload.has("side"):
		return {
			"kind": "unit",
			"side": str(payload["side"]),
			"unit_id": payload["target_id"],
			"slot": payload.get("slot"),
		}
	if payload.has("target_id") and payload.has("target_side"):
		return {
			"kind": "unit",
			"side": str(payload["target_side"]),
			"unit_id": payload["target_id"],
			"slot": payload.get("slot"),
		}
	return _battle_target()


static func _buff_target(payload: Dictionary) -> Dictionary:
	if payload.get("scope") == "side":
		return {"kind": "side", "side": str(payload.get("side", "unknown"))}
	return {
		"kind": "unit",
		"side": str(payload.get("side", "unknown")),
		"unit_id": payload.get("target_id", 0),
		"slot": payload.get("slot"),
	}


static func _content_target(event_id: String, payload: Dictionary) -> Dictionary:
	if event_id in ["freeSkillCast", "exclusiveCast", "ultimateCast"]:
		var owner: Variant = payload.get("owner_hero_id", 0)
		if owner != null and owner != 0:
			return {"kind": "hero", "side": "ally", "hero_id": owner}
		return {"kind": "side", "side": "ally"}
	return _battle_target()


static func _unit_target(unit: Dictionary) -> Dictionary:
	return {
		"kind": "unit",
		"side": str(unit.get("side", "unknown")),
		"unit_id": unit.get("id", 0),
		"slot": unit.get("slot"),
	}


static func _battle_target() -> Dictionary:
	return {"kind": "battle"}


static func _without_live_references(payload: Dictionary) -> Dictionary:
	var copy := payload.duplicate(true)
	for key in ["target", "unit", "defender", "attacker"]:
		if copy.has(key) and typeof(copy[key]) == TYPE_DICTIONARY:
			copy[key] = copy[key].duplicate(true)
	return _json_snapshot(copy)


static func _json_snapshot(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(_json_snapshot(item))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key: Variant in value:
			result[str(key)] = _json_snapshot(value[key])
		return result
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return value
	return str(value)


static func _is_json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_json_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or not _is_json_safe(value[key]):
					return false
			return true
	return false
