extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1200, 700))
	var fixture = preload("res://tests/mechanic_feedback_ui_test.gd")
	var screen: Control = preload("res://scenes/battle/battle_screen.tscn").instantiate()
	root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1200, 700)
	screen.bind_view_model(fixture.fixture_vm())
	for i in 12: await process_frame
	screen.present_event(fixture.devour_event(), 1.0)
	screen.present_event(fixture.relic_event(), 1.0)
	await create_timer(0.28).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/artifacts/mechanic_feedback.png"))
	screen.free()
	quit()
