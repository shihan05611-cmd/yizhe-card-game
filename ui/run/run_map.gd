extends Control
## A readable three-lane route. The lifecycle owns availability and edges.
signal node_selected(node_id: String)
const NAMES := {"battle": "交锋", "elite": "强敌", "boss": "关主", "shop": "商旅", "forge": "锻坊", "event": "奇遇"}
const MARKS := {"battle": "弈", "elite": "锋", "boss": "关", "shop": "商", "forge": "锻", "event": "遇"}
var nodes: Array = []
var buttons: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(660, 302)
	resized.connect(_layout)

func bind_nodes(value: Array) -> void:
	nodes = value.duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	for node: Dictionary in nodes:
		var button := Button.new()
		var done := bool(node.completed)
		var available := bool(node.available)
		button.text = "%s\n%s" % ["已过" if done else MARKS.get(node.type, "·"), NAMES.get(node.type, node.type)]
		button.disabled = not available or done
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = "第 %d 步 · %s%s" % [int(node.column)+1, NAMES.get(node.type, node.type), " · 可前往" if available else ""]
		button.add_theme_font_size_override("font_size", 13)
		var box := StyleBoxFlat.new()
		box.bg_color = Color("c4b78b") if available else (Color("476354") if done else Color("23362d"))
		box.border_color = Color("f0dfaa") if available else Color("52634e")
		box.set_border_width_all(2 if available else 1)
		box.set_corner_radius_all(8)
		button.add_theme_stylebox_override("normal", box)
		button.add_theme_stylebox_override("disabled", box)
		button.add_theme_color_override("font_color", Color("1a3027"))
		button.add_theme_color_override("font_disabled_color", Color("d0d5be") if done else Color("8b9a85"))
		button.pressed.connect(func() -> void: node_selected.emit(str(node.id)))
		add_child(button)
		buttons[node.id] = button
	_layout()

func _center(node: Dictionary) -> Vector2:
	return Vector2(36 + float(node.column) * (size.x-72) / 9.0, 48 + float(node.row) * (size.y-96) / 2.0)

func _layout() -> void:
	for node: Dictionary in nodes:
		if buttons.has(node.id):
			buttons[node.id].size = Vector2(58,64)
			buttons[node.id].position = _center(node)-Vector2(29,32)
	queue_redraw()

func _draw() -> void:
	var by_id := {}
	for node: Dictionary in nodes:
		by_id[node.id] = node
	for node: Dictionary in nodes:
		for next_id: String in node.next_node_ids:
			if by_id.has(next_id):
				var followed: bool = node.completed and (by_id[next_id].completed or by_id[next_id].available)
				draw_line(_center(node), _center(by_id[next_id]), Color("a6ac82") if followed else Color("3e5143"), 2.0 if followed else 1.0, true)
