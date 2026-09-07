class_name SkillFxScenePlayer
extends Control

const Catalog = preload("res://data/presentation/skill_fx_catalog.gd")
const INSTANCE_SCENE = preload("res://scenes/effects/fx_instance.tscn")
const VIGNETTE_SCENE = preload("res://scenes/effects/vignette.tscn")
const CAPTION_SCENE = preload("res://scenes/effects/caption.tscn")
const BURST_SCENE = preload("res://scenes/effects/burst.tscn")
const BEAM_SCENE = preload("res://scenes/effects/beam.tscn")
const STREAK_SCENE = preload("res://scenes/effects/streak.tscn")
const MULTI_TARGET_SCENE = preload("res://scenes/effects/multi_target.tscn")
const FIELD_SCENE = preload("res://scenes/effects/field.tscn")
const GENERIC_SCENE = preload("res://scenes/effects/generic_skill_fx.tscn")

var _active: Dictionary = {}
var _scheduled_tweens: Array[Tween] = []
var _diagnostics: Array[Dictionary] = []
var _anchor_resolver := Callable()
var _duration_clock := Callable()
var _reduced_motion := false


func set_anchor_resolver(resolver: Callable) -> void:
	_anchor_resolver = resolver


func set_duration_clock(clock: Callable) -> void:
	_duration_clock = clock


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func emit_visual_effect(effect_id: String, payload: Dictionary = {}) -> void:
	var parts := effect_id.split(".")
	if parts.size() < 3:
		_record_diagnostic("malformed_event", effect_id)
		return
	var fx_namespace := parts[0]
	var skill_key := parts[1]
	var phase := ".".join(parts.slice(2))
	if fx_namespace not in ["ult", "skill"]:
		_record_diagnostic("unknown_namespace", effect_id)
		return
	match phase:
		"start":
			start_skill_fx(fx_namespace, skill_key, payload)
		"target":
			retarget_skill_fx(fx_namespace, skill_key, payload)
		"targets":
			apply_multi_targets(fx_namespace, skill_key, payload)
		"end":
			end_skill_fx(fx_namespace, skill_key, payload)
		"preview":
			preview_skill_fx(fx_namespace, skill_key, payload)
		"preview.clear":
			clear_skill_fx_preview(fx_namespace, skill_key)
		_:
			_record_diagnostic("unknown_phase", effect_id)


func start_skill_fx(fx_namespace: String, skill_key: String, payload: Dictionary = {}) -> void:
	clear_visual_effect()
	var definition := Catalog.get_fx_definition(fx_namespace, skill_key)
	if definition.is_empty():
		_start_generic(fx_namespace, skill_key, payload)
		return
	var root := _create_instance_root(fx_namespace, skill_key, payload)
	_active = {
		"namespace": fx_namespace, "skill_key": skill_key, "phase": "running",
		"definition": definition, "payload": payload.duplicate(true), "root": root,
		"started_at_ms": Time.get_ticks_msec(),
		"seconds_per_ms": _current_seconds_per_ms(),
	}
	var timeline := Catalog.resolve_reduced_motion_timeline() if _reduced_motion else Catalog.resolve_start_timeline(definition, _active["payload"])
	_play_timeline(root, timeline, definition, _active["payload"])
	var hold_ms: Variant = Catalog.resolve_hold_ms(definition, _active["payload"])
	if hold_ms != null:
		_schedule(func() -> void:
			if _matches_active(fx_namespace, skill_key, "running"):
				_begin_end(fx_namespace, skill_key, _active["payload"])
		, int(hold_ms))


func retarget_skill_fx(fx_namespace: String, skill_key: String, payload: Dictionary = {}) -> void:
	if not _matches_active(fx_namespace, skill_key):
		return
	var root: Control = _active["root"]
	root.set_meta("visual_target", _normalized_target(payload))
	root.set_meta("anchor", _resolve_anchor(payload))


func apply_multi_targets(fx_namespace: String, skill_key: String, payload: Dictionary = {}) -> void:
	if not _matches_active(fx_namespace, skill_key):
		return
	_active["payload"]["targets"] = payload.get("targets", []).duplicate(true)


func end_skill_fx(fx_namespace: String, skill_key: String, payload: Dictionary = {}) -> void:
	if not _matches_active(fx_namespace, skill_key):
		return
	if _active["phase"] in ["ending_hold", "ending"]:
		return
	_begin_end(fx_namespace, skill_key, payload)


func _begin_end(fx_namespace: String, skill_key: String, payload: Dictionary) -> void:
	if not _matches_active(fx_namespace, skill_key):
		return
	if _active["phase"] in ["ending_hold", "ending"]:
		return
	retarget_skill_fx(fx_namespace, skill_key, payload)
	_active["phase"] = "ending_hold"
	var definition: Dictionary = _active["definition"]
	if not _reduced_motion:
		_play_timeline(_active["root"], Catalog.resolve_end_timeline(definition, payload), definition, payload)
	var delay := int(definition.get("end_hold_ms", 260))
	_schedule(func() -> void:
		if _matches_active(fx_namespace, skill_key):
			clear_visual_effect()
	, delay)


func preview_skill_fx(fx_namespace: String, skill_key: String, payload: Dictionary = {}) -> void:
	if _matches_active(fx_namespace, skill_key, "preview"):
		retarget_skill_fx(fx_namespace, skill_key, payload)
		return
	clear_visual_effect()
	var definition := Catalog.get_fx_definition(fx_namespace, skill_key)
	if definition.is_empty():
		_start_generic(fx_namespace, skill_key, payload, true)
		return
	var root := _create_instance_root(fx_namespace, skill_key, payload)
	_active = {
		"namespace": fx_namespace, "skill_key": skill_key, "phase": "preview",
		"definition": definition, "payload": payload.duplicate(true), "root": root,
		"started_at_ms": Time.get_ticks_msec(),
		"seconds_per_ms": _current_seconds_per_ms(),
	}
	var timeline := Catalog.resolve_reduced_motion_timeline() if _reduced_motion else Catalog.resolve_preview_timeline(definition)
	_play_timeline(root, timeline, definition, _active["payload"])


func clear_skill_fx_preview(fx_namespace: String, skill_key: String) -> void:
	if _matches_active(fx_namespace, skill_key, "preview"):
		clear_visual_effect()


func clear_visual_effect() -> void:
	for tween: Tween in _scheduled_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_scheduled_tweens.clear()
	if not _active.is_empty():
		var root: Node = _active.get("root")
		if is_instance_valid(root):
			var parent := root.get_parent()
			if parent != null:
				parent.remove_child(root)
			root.queue_free()
	_active = {}


func get_active_effect() -> Dictionary:
	if _active.is_empty():
		return {}
	return {
		"namespace": _active["namespace"], "skill_key": _active["skill_key"],
		"phase": _active["phase"], "definition": _active["definition"].duplicate(true),
		"payload": _active["payload"].duplicate(true),
	}


func diagnostics() -> Array:
	return _diagnostics.duplicate(true)


func instantiate_primitive(step: Dictionary, definition: Dictionary, payload: Dictionary = {}) -> Array:
	var prim := str(step.get("prim", ""))
	var scene: PackedScene
	match prim:
		"vignette": scene = VIGNETTE_SCENE
		"caption": scene = CAPTION_SCENE
		"burst": scene = BURST_SCENE
		"beam": scene = BEAM_SCENE
		"streak": scene = STREAK_SCENE
		"multiBurst", "multiMark": scene = MULTI_TARGET_SCENE
		"field": scene = FIELD_SCENE
		_:
			_record_diagnostic("unknown_primitive", prim)
			return []
	var contexts := _primitive_contexts(step, definition, payload)
	var result: Array = []
	for context: Dictionary in contexts:
		var node := scene.instantiate()
		node.configure(context)
		result.append(node)
	return result


func _primitive_contexts(step: Dictionary, definition: Dictionary, payload: Dictionary) -> Array:
	var contexts: Array = []
	var prim := str(step.get("prim", ""))
	if prim in ["multiBurst", "multiMark"]:
		var targets: Array = payload.get("targets", [])
		for index in targets.size():
			var target: Dictionary = targets[index]
			var context := _base_context(step, definition, payload)
			context["index"] = index
			context["anchor"] = _resolve_anchor(target)
			context["visual_target"] = _normalized_target(target)
			context["target_intensity"] = clampf(float(target.get("intensity", 1.0)), 0.4, 2.2)
			context["delay_ms"] = index * int(step.get("gap", 0))
			context["variant"] = "assemble" if step.get("variant", "") == "assemble" else ("mark" if prim == "multiMark" else str(target.get("ring", "impact")))
			contexts.append(context)
		return contexts
	var count := maxi(1, int(step.get("count", 1))) if prim == "streak" else 1
	for index in count:
		var context := _base_context(step, definition, payload)
		context["index"] = index
		context["delay_ms"] = index * int(step.get("gap", 0))
		contexts.append(context)
	return contexts


func _base_context(step: Dictionary, definition: Dictionary, payload: Dictionary) -> Dictionary:
	var context := step.duplicate(true)
	context["hue"] = definition.get("hue", 200.0)
	context["intensity"] = definition.get("intensity", 0.8)
	context["caption"] = definition.get("caption", {}).duplicate(true)
	context["payload"] = payload.duplicate(true)
	context["anchor"] = _resolve_anchor(payload)
	context["visual_target"] = _normalized_target(payload)
	return context


func _play_timeline(root: Control, timeline: Array, definition: Dictionary, payload: Dictionary) -> void:
	for step: Dictionary in timeline:
		_schedule(func() -> void:
			if not is_instance_valid(root):
				return
			for node in instantiate_primitive(step, definition, payload):
				root.add_child(node)
				node.play(_seconds(int(step.get("duration_ms", 260))), _seconds(int(node.get_meta("fx_context").get("delay_ms", 0))))
		, maxi(0, int(step.get("at", 0))))


func _create_instance_root(fx_namespace: String, skill_key: String, payload: Dictionary) -> Control:
	var root := INSTANCE_SCENE.instantiate() as Control
	root.set_meta("namespace", fx_namespace)
	root.set_meta("skill_key", skill_key)
	root.set_meta("visual_target", _normalized_target(payload))
	root.set_meta("anchor", _resolve_anchor(payload))
	add_child(root)
	return root


func _start_generic(fx_namespace: String, skill_key: String, payload: Dictionary, preview := false) -> void:
	var root := _create_instance_root(fx_namespace, skill_key, payload)
	var generic := GENERIC_SCENE.instantiate()
	var definition := {
		"hue": payload.get("hue", 200.0), "intensity": 0.65,
		"caption": {"title": str(payload.get("skill_name", payload.get("source_name", skill_key))), "subtitle": ""},
	}
	var context := _base_context({"prim": "generic", "duration_ms": 240}, definition, payload)
	generic.configure(context)
	root.add_child(generic)
	_active = {
		"namespace": fx_namespace, "skill_key": skill_key, "phase": "preview" if preview else "running",
		"definition": {}, "payload": payload.duplicate(true), "root": root,
		"started_at_ms": Time.get_ticks_msec(),
		"seconds_per_ms": _current_seconds_per_ms(),
	}
	generic.play(_seconds(240))
	_record_diagnostic("generic_fallback", "%s.%s" % [fx_namespace, skill_key])
	if not preview:
		_schedule(clear_visual_effect, 300)


func _schedule(callback: Callable, delay_ms: int) -> void:
	if not is_inside_tree():
		callback.call()
		return
	var tween := create_tween()
	_scheduled_tweens.append(tween)
	if delay_ms > 0:
		tween.tween_interval(_seconds(delay_ms))
	tween.tween_callback(callback)


func _seconds(duration_ms: int) -> float:
	if not _active.is_empty() and _active.has("seconds_per_ms"):
		return maxf(0.0, float(duration_ms) * float(_active["seconds_per_ms"]))
	if _duration_clock.is_valid():
		return maxf(0.0, float(_duration_clock.call(duration_ms)))
	return maxf(0.0, float(duration_ms) / 1000.0)


func _current_seconds_per_ms() -> float:
	if _duration_clock.is_valid():
		return maxf(0.0, float(_duration_clock.call(1000))) / 1000.0
	return 0.001


func _matches_active(fx_namespace: String, skill_key: String, phase: String = "") -> bool:
	if _active.is_empty():
		return false
	if _active.get("namespace", "") != fx_namespace or _active.get("skill_key", "") != skill_key:
		return false
	return phase.is_empty() or _active.get("phase", "") == phase


func _resolve_anchor(payload: Dictionary) -> Dictionary:
	var target := _normalized_target(payload)
	if _anchor_resolver.is_valid():
		var resolved: Variant = _anchor_resolver.call(target)
		if resolved is Dictionary:
			return resolved.duplicate(true)
	return {"position": Vector2(600.0, 350.0)}


func _normalized_target(payload: Dictionary) -> Dictionary:
	if payload.get("visual_target") is Dictionary:
		return payload["visual_target"].duplicate(true)
	if payload.get("target") is Dictionary:
		return payload["target"].duplicate(true)
	var target := {}
	for key in ["kind", "side", "slot", "hero_id", "unit_id"]:
		if payload.has(key):
			target[key] = payload[key]
	if payload.has("targetSide"):
		target["side"] = payload["targetSide"]
	if payload.has("targetId"):
		target["unit_id"] = payload["targetId"]
	if target.is_empty():
		target = {"kind": "screen"}
	return target


func _record_diagnostic(code: String, event_id: String) -> void:
	_diagnostics.append({"code": code, "event_id": event_id})
