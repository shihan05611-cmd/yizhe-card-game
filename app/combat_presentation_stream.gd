class_name CombatPresentationStream
extends RefCounted

const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")

const EVENT_KINDS := ["damage", "heal", "buff", "round", "card", "log", "fatal", "combat"]

var _sequence := 0
var _batch_sequence := 0
var _batch_id := "batch-00000000"
var _events: Array[Dictionary] = []
var _acknowledged_sequence := 0
var _presentation_action_sequence := 0
var _piece_actions: Dictionary = {}


func begin_batch(_reason: String) -> String:
	_batch_sequence += 1
	_batch_id = "batch-%08d" % _batch_sequence
	_piece_actions.clear()
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
	var source := _source_from_payload(payload, "damage")
	_source_presentation_action(source, event_id, payload)
	_source_presentation_wave(source, event_id, payload)
	append(
		"damage",
		event_id,
		source,
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
	var source := _source_from_payload(request, "combat")
	# Combat feedback emitted from inside a piece hit (for example an enemy
	# special resource drain) belongs to that strike's visual segment.
	_source_presentation_action(source, event_id, request)
	append(
		"combat",
		event_id,
		source,
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


func _source_presentation_action(source: Dictionary, event_id: String, payload: Dictionary) -> void:
	if source.get("action_phase") != "piece_action":
		return
	var signature := "%s|%s|%s|%s" % [
		str(source.get("type", "")), str(source.get("id", "")),
		str(source.get("side", "")), str(source.get("actor_id", "")),
	]
	var metadata: Dictionary = payload.get("metadata", {})
	var starts_action := bool(metadata.get("presentation_starts_action", false))
	var current: Dictionary = _piece_actions.get(signature, {})
	if event_id == "damage_applied":
		# PieceAttack marks the first actual target of every strike. Thus an
		# extra shot, a repeat execute, and every pursuit begin a new action,
		# while all targets of a general's column strike reuse the same one.
		# Legacy reaction damage has no marker, so each damage_applied starts it.
		if starts_action or current.is_empty() or not metadata.has("presentation_starts_action"):
			_presentation_action_sequence += 1
			current = {
				"id": "piece-action-%d" % _presentation_action_sequence,
			}
			_piece_actions[signature] = current
	if not current.is_empty():
		source["presentation_action_id"] = current["id"]


func _source_presentation_wave(source: Dictionary, event_id: String, payload: Dictionary) -> void:
	# Effect adapters can provide an explicit per-trigger wave id. This lets a
	# single-hit area effect present every target together while keeping repeated
	# triggers and multi-hit effects in separate waves.
	if event_id != "damage_applied":
		return
	var metadata: Variant = payload.get("metadata", {})
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	var explicit_wave_id: Variant = metadata.get("presentation_wave_id")
	if typeof(explicit_wave_id) == TYPE_STRING and not explicit_wave_id.strip_edges().is_empty():
		source["presentation_wave_id"] = explicit_wave_id
		var explicit_hit_index: Variant = metadata.get("presentation_hit_index")
		if typeof(explicit_hit_index) == TYPE_INT and int(explicit_hit_index) >= 0:
			source["presentation_hit_index"] = int(explicit_hit_index)
		return
	# Hero handlers opt in with a per-cast hit index. The batch and canonical
	# source signature keep two casts of the same skill distinct, while targets
	# belonging to one hit resolve in one visual wave.
	if source.get("action_phase") != "skill_action" or not metadata.has("presentation_wave_index"):
		return
	var wave_index: Variant = metadata["presentation_wave_index"]
	if typeof(wave_index) != TYPE_INT or int(wave_index) < 0:
		return
	source["presentation_wave_id"] = "skill-wave:%s:%s|%s|%s|%s:%d" % [
		_batch_id,
		str(source.get("type", "")), str(source.get("id", "")),
		str(source.get("side", "")), str(source.get("actor_id", "")),
		int(wave_index),
	]
	source["presentation_hit_index"] = int(wave_index)


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
