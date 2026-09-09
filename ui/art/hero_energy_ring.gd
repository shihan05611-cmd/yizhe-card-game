extends Control
## The ring itself is the energy meter; its centre stays transparent for art.

var _ratio := 0.0
var _enemy := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_energy(current: float, maximum: float, enemy: bool = false) -> void:
	var next_ratio := clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	if not is_finite(next_ratio):
		next_ratio = 0.0
	if is_equal_approx(_ratio, next_ratio) and _enemy == enemy:
		return
	_ratio = next_ratio
	_enemy = enemy
	queue_redraw()

func ratio() -> float:
	return _ratio

func _draw() -> void:
	var diameter := minf(size.x, size.y)
	var radius := diameter * 0.5 - 3.0
	if radius <= 0.0:
		return
	var center := size * 0.5
	var width := clampf(diameter * 0.035, 1.8, 3.0)
	var track := Color("554738") if _enemy else Color("374b42")
	track.a = 0.78
	draw_arc(center, radius, -PI * 0.5, PI * 1.5, 128, track, width, true)
	if _ratio <= 0.0:
		return
	var fill := Color("ca9670") if _enemy else Color("a6c3a0")
	var end_angle := -PI * 0.5 + TAU * _ratio
	var segments := maxi(2, ceili(128.0 * _ratio))
	draw_arc(center, radius, -PI * 0.5, end_angle, segments, fill, width, true)
	# A fine warm edge gives the complete meter a quiet, unmistakable finish.
	if _ratio >= 1.0:
		var full_edge := Color("e3bc88") if _enemy else Color("d5c394")
		draw_arc(center, radius + width * 0.33, -PI * 0.5, PI * 1.5, 128, full_edge, 0.7, true)
