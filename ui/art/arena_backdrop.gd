extends Control
## Presentation only. Shared jade board and the approved ink/paper palette.

func _ready() -> void:
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
	draw_rect(Rect2(Vector2.ZERO, size), Color("18261f"))
	var board := Rect2(219, 70, size.x - 438, size.y - 327)
	var slab := StyleBoxFlat.new()
	slab.bg_color = Color("34473b")
	slab.border_color = Color("7a7954")
	slab.set_border_width_all(1)
	slab.set_corner_radius_all(12)
	slab.shadow_color = Color(0, 0, 0, 0.22)
	slab.shadow_size = 15
	draw_style_box(slab, board)
	draw_rect(board.grow(-9), Color("6c7452"), false, 1)
	var mid := size.x * 0.5
	draw_line(Vector2(mid, board.position.y + 24), Vector2(mid, board.end.y - 24), Color(0.72, 0.69, 0.47, 0.22), 1)
	for row in range(1, 3):
		var y := board.position.y + board.size.y * row / 3.0
		draw_line(Vector2(board.position.x + 20, y), Vector2(board.end.x - 20, y), Color(0.72, 0.69, 0.47, 0.09), 1)
	draw_line(Vector2(30, 66), Vector2(size.x - 30, 66), Color("48503a"), 1)
	draw_line(Vector2(155, size.y - 255), Vector2(size.x - 155, size.y - 255), Color("48503a"), 1)
