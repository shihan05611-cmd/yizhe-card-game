class_name SpOrb
extends Control
## Text is owned by the HUD; this only paints the resource setting and arc.

var _ratio := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)

func bind_resources(sp: float, sp_max: float) -> void:
	_ratio = clampf(sp / sp_max, 0.0, 1.0) if is_finite(sp) and is_finite(sp_max) and sp_max > 0.0 else 0.0
	queue_redraw()

func _draw() -> void:
	var unit := minf(size.x, size.y) / 70.0
	if unit <= 0.0:
		return
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * unit)
	# Opaque concentric washes approximate the concept's quiet radial jade fill.
	draw_circle(Vector2.ZERO, 33.0, Color("14271e"))
	for i in range(24):
		var t := float(i) / 23.0
		var wash := Color("172c21").lerp(Color("293b27"), t)
		draw_circle(Vector2(-1,-1), 31.0 - t * 27.0, wash)
	draw_circle(Vector2.ZERO, 33.0, Color(0.59,0.65,0.45,0.25), false, 0.85, true)
	draw_circle(Vector2.ZERO, 28.8, Color(0.59,0.65,0.45,0.09), false, 0.6, true)
	if _ratio > 0.0:
		draw_arc(Vector2.ZERO, 33.0, -PI*0.5, -PI*0.5 + TAU*_ratio, 96, Color("cabb86"), 1.6, true)
	draw_set_transform(Vector2.ZERO)
