extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1200, 700))
	root.size = Vector2i(1200, 700)
	var manager := preload("res://autoload/hand_manager.gd").new()
	var controller := preload("res://app/battle_controller.gd").new(manager)
	var started: Variant = controller.start({
		"battle_seed": "retained-hand-capture", "deployed_hero_ids": [1],
		"free_skill_ids": ["pieceAction", "pieceAction", "smallHeal"],
		"retained_card_keys": ["free:0"], "stage_id": "counter",
	})
	if not started.ok:
		push_error(started.message)
		quit(1)
		return
	# Four cards fit in the opening hand; keep one concrete duplicate across a turn.
	var result: Variant = controller.end_player_turn()
	if not result.ok:
		push_error(result.message)
		quit(1)
		return
	var screen: Control = preload("res://scenes/battle/battle_screen.tscn").instantiate()
	root.add_child(screen)
	screen.hand_view.animate_layout = false
	screen.bind_view_model(controller.view_model())
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := "res://tests/artifacts/retained_hand.png"
	var saved := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("RETAINED HAND CAPTURE: %s result=%s" % [output, saved])
	screen.free()
	manager.free()
	quit(0 if saved == OK else 1)
