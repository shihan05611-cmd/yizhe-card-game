class_name DamagePipeline
extends RefCounted

const ContextsScript = preload("res://core/contexts.gd")
const REQUIRED_CALLBACKS := [
	"random",
	"format",
	"get_block_rate",
	"get_damage_multiplier",
	"on_event",
	"on_death",
	"record_damage",
]

var _random: Callable
var _format: Callable
var _get_block_rate: Callable
var _get_damage_multiplier: Callable
var _on_event: Callable
var _on_death: Callable
var _record_damage: Callable
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("damage pipeline config must be a Dictionary")
		return
	for callback_name in REQUIRED_CALLBACKS:
		var callback: Variant = config.get(callback_name)
		if typeof(callback) != TYPE_CALLABLE or not callback.is_valid():
			errors.append("%s must be an injected valid Callable" % callback_name)
	if not errors.is_empty():
		return
	_random = config["random"]
	_format = config["format"]
	_get_block_rate = config["get_block_rate"]
	_get_damage_multiplier = config["get_damage_multiplier"]
	_on_event = config["on_event"]
	_on_death = config["on_death"]
	_record_damage = config["record_damage"]
	_valid = true


func is_valid() -> bool:
	return _valid


func apply(
	target: Variant,
	damage_context: Variant,
	metadata: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _valid:
		errors.append("damage pipeline config is invalid")
		return {}
	var context_errors: Array[String] = []
	var context: Dictionary = ContextsScript.create_damage_context(damage_context, context_errors)
	_append_errors(context_errors, errors)
	if context.is_empty():
		return {}
	if metadata == null:
		metadata = {}
	if typeof(metadata) != TYPE_DICTIONARY:
		errors.append("damage metadata must be a Dictionary")
		return {}
	if target == null:
		return _zero_result(context)
	if typeof(target) != TYPE_DICTIONARY:
		errors.append("damage target must be a Dictionary or null")
		return {}
	if not bool(target.get("alive", false)):
		return _zero_result(context)

	var old_hp_value: Variant = target.get("hp", 0)
	if not _is_finite_number(old_hp_value):
		errors.append("target.hp must be a finite number")
		return {}
	var old_hp := float(old_hp_value)
	var target_view: Dictionary = ContextsScript.snapshot(target)
	var metadata_snapshot: Dictionary = ContextsScript.snapshot(metadata)
	var multiplier_value: Variant = _get_damage_multiplier.call(
		target_view,
		ContextsScript.snapshot(context),
		ContextsScript.snapshot(metadata_snapshot),
	)
	if not _validate_callback_number(multiplier_value, "get_damage_multiplier", errors):
		return {}
	var multiplier := maxf(0.0, float(multiplier_value))
	var amount := maxf(0.0, float(context["raw_amount"])) * multiplier

	var crit := bool(context["guaranteed_crit"])
	if not crit and bool(context["can_crit"]):
		var crit_roll: Variant = _random.call()
		if not _validate_callback_number(crit_roll, "random", errors):
			return {}
		crit = float(crit_roll) < _clamp_rate(context["crit_rate"])
	if crit:
		amount *= 1.5

	var raw_before_value: Variant = _format.call(amount)
	if not _validate_callback_number(raw_before_value, "format", errors):
		return {}
	var raw_amount_before_block := maxf(0.0, float(raw_before_value))

	var blocked := false
	if bool(context["can_block"]):
		# Preserve Web evaluation order: consume the block roll before reading block rate.
		var block_roll: Variant = _random.call()
		if not _validate_callback_number(block_roll, "random", errors):
			return {}
		var block_rate_value: Variant = _get_block_rate.call(
			ContextsScript.snapshot(target_view),
			ContextsScript.snapshot(context),
			ContextsScript.snapshot(metadata_snapshot),
		)
		if not _validate_callback_number(block_rate_value, "get_block_rate", errors):
			return {}
		blocked = float(block_roll) < _clamp_rate(block_rate_value)
	if blocked:
		amount *= 0.5

	var calculated_value: Variant = _format.call(amount)
	if not _validate_callback_number(calculated_value, "format", errors):
		return {}
	var calculated_amount := maxf(0.0, float(calculated_value))
	var dealt_value: Variant = _format.call(minf(old_hp, calculated_amount))
	if not _validate_callback_number(dealt_value, "format", errors):
		return {}
	var dealt := maxf(0.0, float(dealt_value))
	var new_hp_value: Variant = _format.call(old_hp - calculated_amount)
	if not _validate_callback_number(new_hp_value, "format", errors):
		return {}
	var new_hp := maxf(0.0, float(new_hp_value))

	var threshold_crossed := false
	if target.get("side", "") == ContextsScript.UNIT_SIDE["ENEMY"] and not bool(target.get("hp_threshold_crossed", false)):
		var max_hp_value: Variant = target.get("max_hp", 0)
		if not _is_finite_number(max_hp_value):
			errors.append("enemy target.max_hp must be a finite number")
			return {}
		var threshold := float(max_hp_value) * 0.3
		threshold_crossed = old_hp > threshold and new_hp <= threshold and new_hp > 0.0

	target["hp"] = new_hp
	var died := new_hp <= 0.0
	var death_context: Variant = null
	if died:
		death_context = ContextsScript.create_death_context_from_damage(context, context_errors)
		_append_errors(context_errors, errors)
		if death_context.is_empty():
			# Context was already normalized; this is defensive and occurs before events.
			target["hp"] = old_hp
			return {}

	var event_payload := {
		"target": target,
		"amount": dealt,
		"calculated_amount": calculated_amount,
		"blocked": blocked,
		"crit": crit,
		"died": died,
		"damage_context": ContextsScript.snapshot(context),
		"effect_context": ContextsScript.snapshot(context["effect"]),
		"old_hp": old_hp,
		"new_hp": new_hp,
		"raw_amount_before_block": raw_amount_before_block,
		"metadata": ContextsScript.snapshot(metadata_snapshot),
	}
	_emit("damage_applied", event_payload)
	if dealt > 0.0:
		_emit("unit_damaged", event_payload)
	if blocked:
		var blocked_payload := _payload_copy(event_payload)
		blocked_payload["defender"] = target
		blocked_payload["attacker"] = metadata.get("attacker_unit")
		_emit("unit_blocked", blocked_payload)
	if threshold_crossed:
		target["hp_threshold_crossed"] = true
		_emit("hp_threshold_crossed", {
			"target": target,
			"amount": dealt,
			"raw_amount": raw_amount_before_block,
			"damage_context": ContextsScript.snapshot(context),
			"effect_context": ContextsScript.snapshot(context["effect"]),
			"metadata": ContextsScript.snapshot(metadata_snapshot),
		})
	_record_damage.call(_payload_copy(event_payload))
	if died:
		kill(target, death_context, {
			"damage_context": ContextsScript.snapshot(context),
			"metadata": ContextsScript.snapshot(metadata_snapshot),
		}, errors)

	return {
		"dealt": dealt,
		"blocked": blocked,
		"died": died,
		"crit": crit,
		"damage_context": ContextsScript.snapshot(context),
		"death_context": ContextsScript.snapshot(death_context) if death_context != null else null,
	}


func kill(
	target: Variant,
	death_context: Variant,
	payload: Variant = {},
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if not _valid:
		errors.append("damage pipeline config is invalid")
		return false
	var context_errors: Array[String] = []
	var normalized_death := ContextsScript.create_death_context(death_context, context_errors)
	_append_errors(context_errors, errors)
	if normalized_death.is_empty():
		return false
	if payload == null:
		payload = {}
	if typeof(payload) != TYPE_DICTIONARY:
		errors.append("death payload must be a Dictionary")
		return false
	if target == null:
		return false
	if typeof(target) != TYPE_DICTIONARY:
		errors.append("death target must be a Dictionary or null")
		return false
	if not bool(target.get("alive", false)):
		return false
	var old_hp_value: Variant = target.get("hp", 0)
	if not _is_finite_number(old_hp_value):
		errors.append("target.hp must be a finite number")
		return false
	var death_payload: Dictionary = ContextsScript.snapshot(payload)
	target["hp"] = 0.0
	target["alive"] = false
	death_payload["unit"] = target
	death_payload["death_context"] = ContextsScript.snapshot(normalized_death)
	death_payload["effect_context"] = ContextsScript.snapshot(normalized_death["effect"])
	death_payload["old_hp"] = float(old_hp_value)
	_emit("unit_died", death_payload)
	_on_death.call(
		target,
		ContextsScript.snapshot(normalized_death),
		_payload_copy(death_payload),
	)
	return true


func _emit(event_name: String, payload: Dictionary) -> void:
	_on_event.call(event_name, _payload_copy(payload))


func _payload_copy(payload: Dictionary) -> Dictionary:
	var result: Dictionary = ContextsScript.snapshot(payload)
	for reference_key in ["target", "unit", "defender", "attacker"]:
		if payload.has(reference_key):
			result[reference_key] = payload[reference_key]
	return result


func _zero_result(context: Dictionary) -> Dictionary:
	return {
		"dealt": 0.0,
		"blocked": false,
		"died": false,
		"crit": false,
		"damage_context": ContextsScript.snapshot(context),
		"death_context": null,
	}


static func _clamp_rate(value: Variant) -> float:
	return clampf(float(value), 0.0, 0.95)


static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _validate_callback_number(
	value: Variant,
	callback_name: String,
	errors: Array[String],
) -> bool:
	if _is_finite_number(value):
		return true
	errors.append("%s callback must return a finite number" % callback_name)
	return false


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message in source:
		destination.append(message)
