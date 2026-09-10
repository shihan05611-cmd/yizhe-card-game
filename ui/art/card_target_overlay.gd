extends Control

var candidates: Array[Rect2] = []
var selected := Rect2()
var origin := Vector2.ZERO
var endpoint := Vector2.ZERO
var caption := ""
var hostile := true
var locked := false

func show_aim(from: Vector2, to: Vector2, rects: Array[Rect2], picked: Rect2, message: String, enemy: bool) -> void:
	origin = from - global_position
	endpoint = to - global_position
	candidates.clear()
	for rect in rects:
		candidates.append(Rect2(rect.position - global_position, rect.size))
	selected = Rect2(picked.position - global_position, picked.size)
	locked = picked.has_area()
	caption = message
	hostile = enemy
	visible = true
	queue_redraw()

func clear_aim() -> void:
	visible = false
	candidates.clear()
	selected = Rect2()
	caption = ""
	locked = false
	queue_redraw()

func _draw() -> void:
	if caption.is_empty():
		return
	var color := Color("ffad86") if hostile else Color("91e0bd")
	for rect in candidates:
		draw_rect(rect.grow(-2), Color(color, 0.08), true)
		draw_rect(rect.grow(-2), Color(color, 0.5), false, 1.5)
	if locked:
		draw_rect(selected.grow(2), Color(color, 0.2), true)
		draw_rect(selected.grow(2), color, false, 3.0)
	var points := PackedVector2Array()
	var bend := (origin + endpoint) * 0.5 + Vector2(0, -85)
	for i in range(33):
		var t := float(i) / 32.0
		points.append(origin.lerp(bend, t).lerp(bend.lerp(endpoint, t), t))
	draw_polyline(points, Color(0.04, 0.07, 0.08, 0.95), 8.0, true)
	draw_polyline(points, color if locked else Color(color, 0.6), 3.0, true)
	var direction := (endpoint - points[30]).normalized()
	var wing := direction.orthogonal() * 7
	draw_colored_polygon(PackedVector2Array([endpoint, endpoint-direction*18+wing, endpoint-direction*18-wing]), color)
	if locked:
		draw_arc(endpoint, 17, 0, TAU, 40, color, 2.0, true)
		for axis in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			draw_line(endpoint+axis*22, endpoint+axis*11, color, 2.0, true)
	else:
		draw_circle(endpoint, 5.0, color)
	var font := get_theme_default_font()
	var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var caption_y := selected.position.y-text_size.y-24 if locked else endpoint.y-65
	var box := Rect2(Vector2(clampf(endpoint.x-text_size.x/2-12, 8, maxf(8, size.x-text_size.x-32)), clampf(caption_y, 8, maxf(8, size.y-42))), text_size+Vector2(24, 16))
	draw_rect(box, Color("152429"), true)
	draw_rect(box, color, false, 1.0)
	draw_string(font, box.position+Vector2(12, 8+font.get_ascent(16)), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
