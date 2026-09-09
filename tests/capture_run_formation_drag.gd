extends SceneTree

const RunScene = preload("res://scenes/run.tscn")

var screen: Variant
var errors: Array[String] = []
var _last_mouse := Vector2.ZERO


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await process_frame
	DisplayServer.window_set_size(Vector2i(1200, 700))
	root.size = Vector2i(1200, 700)
	screen = RunScene.instantiate()
	screen.save_path = "res://.godot/test-logs/formation-drag.json"
	root.add_child(screen)
	await process_frame
	var start_errors: Array[String] = []
	if not screen.session.new_run("formation-drag", start_errors): errors.append("new run failed")
	var selection: Dictionary = screen.session.snapshot()
	if not screen.session.execute({"type":"choose_starting_hero","hero_id":selection["initial_hero_choice_ids"][0]}, start_errors): errors.append("choice failed")
	screen._home = false
	screen._formation_expanded = false
	screen._render()
	await process_frame
	await _capture("map-collapsed.png")
	screen._show_formation_dialog(screen.session.snapshot())
	await process_frame
	await process_frame
	await _capture("map-expanded.png")
	var source: Control = _slot(4)
	var target: Control = _slot(2)
	if source == null or target == null:
		errors.append("formation slots missing")
	else:
		var from: Vector2 = source.get_global_rect().get_center()
		var to: Vector2 = target.get_global_rect().get_center()
		_hover(from)
		await process_frame
		_mouse(from, true)
		await process_frame
		_drag(from + Vector2(16, 12))
		await process_frame
		_drag(to)
		await process_frame
		_mouse(to, false)
		await process_frame
		await process_frame
		var slots: Array = screen.session.snapshot()["piece_slots"]
		if slots[1]["piece_class_id"] != "assassin" or slots[3]["piece_class_id"] != "shield":
			errors.append("gui drag did not swap slot 4 with slot 2")
		var token: Control = _token("banner")
		var replacement: Control = _slot(4)
		if token == null or replacement == null:
			errors.append("formation inventory token missing")
		else:
			var token_from: Vector2 = token.get_global_rect().get_center()
			var replacement_to: Vector2 = replacement.get_global_rect().get_center()
			_hover(token_from)
			await process_frame
			_mouse(token_from, true)
			await process_frame
			_drag(token_from + Vector2(18, 12))
			await process_frame
			_drag(replacement_to)
			await process_frame
			_mouse(replacement_to, false)
			await process_frame
			if screen.session.snapshot()["piece_slots"][3]["piece_class_id"] != "banner":
				errors.append("gui inventory drag did not replace slot 4")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/artifacts/formation"))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/artifacts/formation/map-drag-expanded.png"))
	for message: String in errors: push_error(message)
	print("FORMATION DRAG failures=%d" % errors.size())
	quit(0 if errors.is_empty() else 1)


func _slot(slot: int) -> Variant:
	for node: Node in _descendants(screen):
		if node.get_script() != null and node.get("slot") == slot:
			return node
	return null


func _token(class_id: String) -> Variant:
	for node: Node in _descendants(screen):
		if node is Button and node.get("piece_class_id") == class_id:
			return node
	return null


func _descendants(node: Node) -> Array:
	var result: Array = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _drag(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - _last_mouse
	event.velocity = event.relative * 60.0
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	_last_mouse = position


func _hover(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)
	_last_mouse = position


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/artifacts/formation"))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/artifacts/formation/" + name))
