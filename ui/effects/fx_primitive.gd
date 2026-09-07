class_name FxPrimitive
extends Control

var _play_tween: Tween


func configure(context: Dictionary) -> void:
	set_meta("fx_primitive", str(context.get("prim", "")))
	set_meta("fx_context", context.duplicate(true))
	var prim := str(context.get("prim", ""))
	if prim not in ["vignette", "caption", "field"]:
		var anchor: Dictionary = context.get("anchor", {})
		if anchor.has("position") and anchor["position"] is Vector2:
			position = anchor["position"]
		elif anchor.has("x") and anchor.has("y"):
			position = Vector2(float(anchor["x"]), float(anchor["y"]))
	var hue := fmod(float(context.get("hue", 200.0)), 360.0) / 360.0
	var intensity := clampf(float(context.get("intensity", 0.8)), 0.2, 1.0)
	modulate = Color.from_hsv(hue, 0.62, 1.0, intensity)
	_configure_caption(context)
	_configure_variant(context)
	_configure_field(context)


func play(duration_seconds: float, delay_seconds: float = 0.0) -> void:
	if _play_tween != null and _play_tween.is_valid():
		_play_tween.kill()
	if not is_inside_tree():
		return
	var target_modulate := modulate
	modulate.a = 0.0
	_play_tween = create_tween()
	if delay_seconds > 0.0:
		_play_tween.tween_interval(delay_seconds)
	var fade_in := minf(0.08, duration_seconds * 0.25)
	_play_tween.tween_property(self, "modulate", target_modulate, fade_in)
	if duration_seconds > fade_in * 2.0:
		_play_tween.tween_interval(duration_seconds - fade_in * 2.0)
	_play_tween.tween_property(self, "modulate:a", 0.0, fade_in)


func _configure_caption(context: Dictionary) -> void:
	var title_label := get_node_or_null("Frame/Content/Title") as Label
	var subtitle_label := get_node_or_null("Frame/Content/Subtitle") as Label
	if title_label == null or subtitle_label == null:
		return
	var caption: Dictionary = context.get("caption", {})
	var payload: Dictionary = context.get("payload", {})
	var title := str(payload.get("hero_name", caption.get("title", "")))
	if bool(caption.get("titleless", false)):
		title = ""
	var subtitle := str(caption.get("subtitle", ""))
	if bool(payload.get("low_hp_crit", payload.get("lowHpCrit", false))):
		subtitle = str(caption.get("execute_subtitle", subtitle))
	title_label.text = title
	title_label.visible = not title.is_empty()
	subtitle_label.text = subtitle
	var placement := str(caption.get("placement", "below"))
	var frame := get_node_or_null("Frame") as Control
	if frame != null:
		frame.position.y = 72.0 if placement == "above" else 540.0


func _configure_variant(context: Dictionary) -> void:
	var variant := str(context.get("variant", context.get("ring", "impact")))
	for child_name in ["Impact", "Lock", "Implode", "Slash", "Sweep", "Column", "FistA", "FistB", "Mark", "Assemble"]:
		var child := get_node_or_null(child_name) as CanvasItem
		if child != null:
			child.visible = false
	var selected_name: String = {
		"impact": "Impact", "lock": "Lock", "implode": "Implode",
		"slash": "Slash", "sweep": "Sweep", "column": "Column",
		"mark": "Mark", "assemble": "Assemble",
	}.get(variant, "")
	if variant == "echo":
		selected_name = "FistA" if int(context.get("index", 0)) % 2 == 0 else "FistB"
	var selected := get_node_or_null(selected_name) as CanvasItem
	if selected == null and variant in ["impact", "lock", "implode"]:
		selected = get_node_or_null("Impact") as CanvasItem
	if selected != null:
		selected.visible = true
	rotation_degrees = float(context.get("angle", 0.0))
	var scale_factor := clampf(float(context.get("target_intensity", 1.0)), 0.4, 2.2)
	scale = Vector2.ONE * scale_factor


func _configure_field(context: Dictionary) -> void:
	var aura := get_node_or_null("Aura") as Control
	if aura == null:
		return
	var side := str(context.get("side", context.get("payload", {}).get("side", "ally")))
	if side == "enemy":
		aura.anchor_left = 0.5
		aura.anchor_right = 1.0
	else:
		aura.anchor_left = 0.0
		aura.anchor_right = 0.5
