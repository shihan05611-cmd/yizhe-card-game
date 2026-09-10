extends SceneTree

const BoardScene = preload("res://scenes/battle/board_grid.tscn")
const OUTPUT := "res://tests/artifacts/special_monsters.png"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1200, 700))
	var background := ColorRect.new()
	background.color = Color("e6dfcf")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	for i in 2:
		var board: Control = BoardScene.instantiate()
		board.position = Vector2(190 + 440*i, 95)
		board.size = Vector2(310, 540)
		root.add_child(board)
		var cells := [1, 2] if i == 0 else [1, 2, 3]
		var special := "devourer" if i == 0 else "echo"
		var slots: Array = [{"id": 101, "slot": 1, "side": "enemy", "special_id": special,
			"class_id": "default", "occupied": true, "hp": 860.0, "max_hp": 860.0,
			"alive": true, "buffs": [], "occupied_slot_ids": cells}]
		for slot in [4, 5, 6]:
			slots.append({"id": 100+slot, "slot": slot, "side": "enemy", "class_id": ["banner", "crossbow", "assassin"][slot-4],
				"occupied": true, "hp": 120.0, "max_hp": 120.0, "alive": true, "buffs": []})
		board.bind_team({"slots": slots})
		var title := Label.new()
		title.position = Vector2(195+440*i, 42)
		title.text = "噬元兽 · 两格" if i == 0 else "回响 · 三格"
		title.add_theme_color_override("font_color", Color("302b28"))
		title.add_theme_font_size_override("font_size", 24)
		root.add_child(title)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT))
	print("SPECIAL MONSTERS CAPTURE: %s (%s)" % [OUTPUT, error_string(error)])
	quit(0 if error == OK else 1)
