class_name CardFace
extends Control
## Full-rect paper face beneath all card contents. No hover/input ownership.

var _category := "free"

func bind_card(card_vm: Dictionary) -> void:
	set_category(str(card_vm.get("category", "free")))

func set_category(category: String) -> void:
	_category = category if category in ["free", "exclusive", "ultimate"] else "free"
	queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x < 16 or size.y < 16:
		return
	var bounds := Rect2(Vector2.ZERO, size)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("dfd6b9")
	paper.border_color = Color("b6a679")
	if _category == "exclusive":
		paper.border_color = Color("547462")
	elif _category == "ultimate":
		paper.border_color = Color("b4934c")
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(4)
	paper.shadow_color = Color(0.01,0.04,0.025,0.42)
	paper.shadow_size = 5
	paper.shadow_offset = Vector2(1,5)
	draw_style_box(paper, bounds)
	# Inset strips retain rounded outside corners while giving paper a warm slope.
	var inner := bounds.grow(-3)
	for i in range(64):
		var t := float(i)/63.0
		var tone := Color("e7dfc5").lerp(Color("d6ccad"), t)
		draw_rect(Rect2(inner.position+Vector2(0,inner.size.y*t),Vector2(inner.size.x,minf(inner.size.y/63.0+0.5,inner.size.y*(1-t)))),tone)
	# Sparse, reproducible fibers; no frame-time RNG or crawling texture.
	var rng := RandomNumberGenerator.new()
	rng.seed = 39061
	for i in range(300):
		var point := inner.position + Vector2(rng.randf()*inner.size.x,rng.randf()*inner.size.y)
		var fiber := Vector2(rng.randf_range(0.5,1.7),0.25)
		var end := Vector2(minf(point.x+fiber.x,inner.end.x),minf(point.y+fiber.y,inner.end.y))
		draw_line(point,end,Color(0.43,0.36,0.22,rng.randf_range(0.025,0.055)),0.5,true)
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = Color(0.53,0.49,0.34,0.29)
	if _category == "exclusive":
		frame.border_color = Color(0.24,0.39,0.30,0.52)
	elif _category == "ultimate":
		frame.border_color = Color(0.63,0.48,0.21,0.64)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(2)
	draw_style_box(frame,bounds.grow(-5))
	draw_line(Vector2(7,7),Vector2(size.x-7,7),Color(0.98,0.95,0.80,0.28),0.7,true)
	if _category != "free":
		# Margin-only accents preserve the room reserved for rules and owner text.
		var accent := Color("466654") if _category == "exclusive" else Color("ad8640")
		for side in [0,1]:
			var x := 8.0 if side == 0 else size.x-8.0
			draw_line(Vector2(x,14),Vector2(x,36),accent,1.2,true)
			var marker := Vector2(x,size.y-17)
			draw_colored_polygon(PackedVector2Array([marker+Vector2(0,-3),marker+Vector2(2,0),marker+Vector2(0,3),marker+Vector2(-2,0)]),accent)
		if _category == "ultimate":
			draw_line(Vector2(15,9),Vector2(size.x-15,9),Color(0.67,0.49,0.22,0.5),1,true)
			draw_line(Vector2(15,size.y-9),Vector2(size.x-15,size.y-9),Color(0.67,0.49,0.22,0.5),1,true)
