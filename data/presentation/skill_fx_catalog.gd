class_name SkillFxCatalog
extends RefCounted

const FX_DURATION_CAP_MS := 1500
const PRESENTATION_STEP_BASE_MS := 100

const _KNOWN_KEYS := ["fist", "shadow", "ascend", "burn01", "burnEnchant", "puppet"]


static func known_keys() -> Array:
	return _KNOWN_KEYS.duplicate()


static func get_fx_definition(fx_namespace: String, skill_key: String) -> Dictionary:
	if fx_namespace != "ult":
		return {}
	var definitions := _definitions()
	if not definitions.has(skill_key):
		return {}
	return definitions[skill_key].duplicate(true)


static func get_skill_fx_definition(skill_key: String) -> Dictionary:
	return get_fx_definition("ult", skill_key)


static func resolve_start_timeline(definition: Dictionary, payload: Dictionary = {}) -> Array:
	if definition.is_empty():
		return []
	var timeline: Array = definition.get("start_timeline", []).duplicate(true)
	if definition.get("key", "") == "fist":
		var plan := _resolve_fist_streak_plan(payload)
		for step: Dictionary in timeline:
			if step.get("prim", "") == "streak":
				step["count"] = plan["count"]
				step["gap"] = plan["gap"]
			elif step.get("prim", "") == "burst" and not step.has("at"):
				step["at"] = 60 + 420 + (plan["count"] - 1) * plan["gap"]
	return _clamp_timeline_duration(timeline)


static func resolve_end_timeline(definition: Dictionary, _payload: Dictionary = {}) -> Array:
	if definition.is_empty():
		return []
	return _clamp_timeline_duration(definition.get("end_timeline", []).duplicate(true))


static func resolve_preview_timeline(definition: Dictionary) -> Array:
	if definition.is_empty():
		return []
	if definition.has("preview_timeline"):
		return definition["preview_timeline"].duplicate(true)
	return definition.get("start_timeline", []).duplicate(true)


static func resolve_hold_ms(definition: Dictionary, payload: Dictionary = {}) -> Variant:
	if definition.is_empty():
		return 0
	if definition.get("key", "") == "fist":
		var plan := _resolve_fist_streak_plan(payload)
		return clampi(480 + (plan["count"] - 1) * plan["gap"], 480, 930)
	return definition.get("hold_ms", null)


static func resolve_reduced_motion_timeline() -> Array:
	return [
		{"at": 0, "prim": "caption"},
		{"at": 0, "prim": "vignette"},
	]


static func timeline_end_ms(timeline: Array) -> int:
	var max_end := 0
	for step: Dictionary in timeline:
		var count := maxi(1, int(step.get("count", 1)))
		var end := int(step.get("at", 0)) + int(step.get("duration_ms", 0))
		end += maxi(0, count - 1) * int(step.get("gap", 0))
		max_end = maxi(max_end, end)
	return max_end


static func _clamp_timeline_duration(timeline: Array) -> Array:
	var max_end := timeline_end_ms(timeline)
	if max_end <= FX_DURATION_CAP_MS or max_end == 0:
		return timeline
	var scale := float(FX_DURATION_CAP_MS) / float(max_end)
	var result: Array = []
	for raw_step: Dictionary in timeline:
		var step := raw_step.duplicate(true)
		step["at"] = roundi(int(step.get("at", 0)) * scale)
		if step.has("duration_ms") and int(step["duration_ms"]) != 0:
			step["duration_ms"] = roundi(int(step["duration_ms"]) * scale)
		if step.has("gap") and int(step["gap"]) != 0:
			step["gap"] = maxi(18, roundi(int(step["gap"]) * scale))
		result.append(step)
	return result


static func _resolve_fist_streak_plan(payload: Dictionary) -> Dictionary:
	var raw_hits: Variant = payload.get("hits", 3)
	var hits := 3
	if raw_hits is int or raw_hits is float:
		hits = clampi(roundi(float(raw_hits)), 3, 12)
	var count := clampi(hits, 3, 8)
	var gap_max := roundi(PRESENTATION_STEP_BASE_MS * 0.75)
	var gap_step := roundi(PRESENTATION_STEP_BASE_MS * 0.05)
	var gap_min := roundi(PRESENTATION_STEP_BASE_MS * 0.4)
	var gap := clampi(gap_max - maxi(0, count - 3) * gap_step, gap_min, gap_max)
	return {"count": count, "gap": gap}


static func _definitions() -> Dictionary:
	return {
		"fist": {
			"key": "fist", "hue": 32.0, "intensity": 0.85,
			"caption": {"title": "拳意·无量", "subtitle": "拳影掠阵", "side": "left", "placement": "below"},
			"start_timeline": [
				{"at": 0, "prim": "vignette"},
				{"at": 0, "prim": "caption"},
				{"at": 60, "prim": "streak", "variant": "echo", "count": 3, "gap": 75, "angle": -16.0, "duration_ms": 420},
				{"prim": "burst", "ring": "impact", "duration_ms": 400},
			],
			"end_timeline": [], "end_hold_ms": 260,
		},
		"shadow": {
			"key": "shadow", "hue": 262.0, "intensity": 0.8,
			"caption": {"title": "影·狩", "subtitle": "猎杀锁定", "execute_subtitle": "处决锁定", "side": "left", "placement": "above", "titleless": true},
			"start_timeline": [
				{"at": 0, "prim": "vignette"},
				{"at": 0, "prim": "caption"},
				{"at": 20, "prim": "burst", "ring": "lock", "duration_ms": 360},
			],
			"hold_ms": null,
			"end_timeline": [
				{"at": 0, "prim": "streak", "variant": "slash", "count": 1, "gap": 0, "angle": -18.0, "duration_ms": 480},
				{"at": 170, "prim": "burst", "ring": "impact", "duration_ms": 400},
			],
			"end_hold_ms": 520,
			"preview_timeline": [
				{"at": 0, "prim": "vignette"},
				{"at": 0, "prim": "caption"},
				{"at": 20, "prim": "burst", "ring": "lock", "duration_ms": 360},
			],
		},
		"ascend": {
			"key": "ascend", "hue": 45.0, "intensity": 0.8,
			"caption": {"title": "将军出征", "subtitle": "出征列阵", "side": "left", "placement": "below"},
			"start_timeline": [
				{"at": 0, "prim": "vignette"},
				{"at": 0, "prim": "caption"},
				{"at": 180, "prim": "beam", "duration_ms": 420},
				{"at": 620, "prim": "streak", "variant": "column", "count": 1, "gap": 0, "duration_ms": 480},
			],
			"hold_ms": 1100, "end_hold_ms": 260, "end_timeline": [],
		},
		"burn01": {
			"key": "burn01", "hue": 12.0, "intensity": 0.85,
			"caption": {"title": "焚界爆炎", "subtitle": "烈焰横扫", "side": "left", "placement": "below"},
			"start_timeline": [
				{"at": 0, "prim": "vignette"},
				{"at": 0, "prim": "caption"},
				{"at": 120, "prim": "streak", "variant": "sweep", "count": 1, "gap": 0, "angle": 0.0, "duration_ms": 320},
				{"at": 360, "prim": "multiBurst", "gap": 60, "duration_ms": 320},
			],
			"hold_ms": 1200, "end_hold_ms": 260, "end_timeline": [],
		},
		"burnEnchant": {
			"key": "burnEnchant", "hue": 350.0, "intensity": 0.8,
			"caption": {"title": "炎汲仪式", "subtitle": "烈焰内收", "side": "left", "placement": "below"},
			"start_timeline": [
				{"at": 0, "prim": "vignette"},
				{"at": 0, "prim": "caption"},
				{"at": 140, "prim": "burst", "ring": "implode", "duration_ms": 420},
				{"at": 600, "prim": "multiMark", "gap": 50, "duration_ms": 300},
			],
			"hold_ms": 1150, "end_hold_ms": 260, "end_timeline": [],
		},
		"puppet": {
			"key": "puppet", "hue": 185.0, "intensity": 0.75,
			"caption": {"title": "森罗万象", "subtitle": "傀儡列阵", "side": "left", "placement": "below"},
			"start_timeline": [
				{"at": 0, "prim": "vignette"},
				{"at": 0, "prim": "caption"},
				{"at": 160, "prim": "multiMark", "variant": "assemble", "gap": 50, "duration_ms": 340},
			],
			"hold_ms": 1100, "end_hold_ms": 260, "end_timeline": [],
		},
	}
