extends Control

var _from := Vector2.ZERO
var _mouth := Vector2.ZERO
var _progress := 0.0
var _duration := 0.6
var _active := false

func play(resource_position: Vector2, mouth_position: Vector2, duration: float) -> void:
	_from = resource_position - global_position
	_mouth = mouth_position - global_position
	_duration = maxf(0.12, duration)
	_progress = 0.0
	_active = true
	queue_redraw()

func _process(delta: float) -> void:
	if not _active: return
	_progress = minf(1.0, _progress + delta / _duration)
	queue_redraw()
	if _progress >= 1.0:
		_active = false
		queue_free()

func _draw() -> void:
	if not _active: return
	var fade := 1.0 - pow(_progress, 3)
	var violet := Color(0.78, 0.5, 1.0, fade)
	var jade := Color(0.62, 1.0, 0.83, fade)
	var mid := (_from + _mouth) * 0.5 + Vector2(0, -60)
	var path := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24
		path.append(_from.lerp(mid, t).lerp(mid.lerp(_mouth, t), t))
	draw_polyline(path, Color(violet, fade*0.18), 5, true)
	for i in 5:
		var t := clampf(_progress*1.4-float(i)*0.1, 0, 1)
		var point := _from.lerp(mid, t).lerp(mid.lerp(_mouth, t), t)
		draw_circle(point, 3.5-float(i)*0.3, jade)
		draw_circle(point, 7.0, Color(violet, fade*0.2))
	var radius := 35.0 - _progress*17
	draw_arc(_mouth, radius, _progress*TAU, _progress*TAU+PI*1.5, 35, violet, 2.5, true)
	for side in [-1, 1]:
		var offset := float(side)*(15+sin(_progress*PI)*10)
		var triangle := PackedVector2Array([_mouth+Vector2(offset,-16), _mouth+Vector2(offset,16), _mouth+Vector2(offset-float(side)*10,0)])
		draw_colored_polygon(triangle, jade)
