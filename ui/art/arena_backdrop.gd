extends Control
## Presentation only. Shared jade board and the approved ink/paper palette.

var _board_rect := Rect2()

## Bounds in this Control's local coordinates; layout owns the final placement.
func set_board_rect(rect: Rect2) -> void:
	_board_rect = rect
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	var palette := Theme.new()
	var typeface := SystemFont.new()
	typeface.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	palette.default_font = typeface
	palette.default_font_size = 14
	palette.set_color("font_color", "Label", Color("d7d5bd"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("283c33") if state == "normal" else Color("405548")
		if state == "disabled": style.bg_color = Color("29342e")
		style.border_color = Color("8d8056")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		palette.set_stylebox(state, "Button", style)
	palette.set_color("font_color", "Button", Color("e5dfc5"))
	palette.set_color("font_disabled_color", "Button", Color("7c8575"))
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color("1f2c25")
	trough.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("a79b68")
	fill.set_corner_radius_all(2)
	palette.set_stylebox("background", "ProgressBar", trough)
	palette.set_stylebox("fill", "ProgressBar", fill)
	get_parent().theme = palette

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	# A continuous dark surface: the army positions supply order, not grid lines.
	for row in range(64):
		var t := float(row) / 64.0
		var wash := Color("1b2d25").lerp(Color("13221c"),t)
		draw_rect(Rect2(0,size.y*t,size.x,size.y/64.0),wash)
	var center := size*Vector2(0.5,0.4)
	var extent := size*Vector2(0.47,0.44)
	if _board_rect.has_area():
		center = _board_rect.get_center()
		extent = _board_rect.size*Vector2(0.72,0.82)
	# A feathered wash has no visible rectangular edge or river division.
	for i in range(64):
		var first := center+Vector2(cos(TAU*i/64.0),sin(TAU*i/64.0))*extent
		var last := center+Vector2(cos(TAU*(i+1)/64.0),sin(TAU*(i+1)/64.0))*extent
		draw_polygon(PackedVector2Array([center,first,last]),PackedColorArray([Color(0.30,0.39,0.29,0.13),Color(0.30,0.39,0.29,0),Color(0.30,0.39,0.29,0)]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 74129
	for i in range(1500):
		var point := Vector2(rng.randf()*size.x,rng.randf()*size.y)
		draw_rect(Rect2(point,Vector2.ONE*0.7),Color(0.68,0.74,0.59,rng.randf_range(0.009,0.022)))
