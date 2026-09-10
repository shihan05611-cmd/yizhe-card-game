extends SceneTree

const Fixture = preload("res://tests/m5_battle_bridge_test.gd")
const MapSystem = preload("res://systems/roguelike/map_system.gd")
const Rng = preload("res://core/rng.gd")
const Controller = preload("res://app/battle_controller.gd")
const HandManager = preload("res://autoload/hand_manager.gd")
const ScreenScene = preload("res://scenes/battle/battle_screen.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var harness = preload("res://tests/support/test_harness.gd").new()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1200, 700))
	for chapter in [1, 2]:
		var fixture: Dictionary = Fixture.new()._fighting_fixture("polish-screen-%d" % chapter, harness)
		var lifecycle: Variant = fixture["lifecycle"]
		var errors: Array[String] = []
		var launch: Dictionary = lifecycle.begin_current_battle(errors)
		launch["encounter"] = MapSystem.resolve_encounter(lifecycle._roguelike_catalog,
			{"chapter": chapter, "row": 0, "column": 6, "type": "elite"}, Rng.seeded("capture"), errors)
		var manager := HandManager.new()
		var controller := Controller.new(manager)
		var started: Variant = controller.start(launch)
		if not started.ok:
			push_error(started.message)
			quit(1)
			return
		var screen: Control = ScreenScene.instantiate()
		screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
		screen.size = Vector2(1200, 700)
		root.add_child(screen)
		screen.hand_view.animate_layout = false
		screen.bind_view_model(controller.view_model())
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "res://tests/artifacts/polished_battle_%d.png" % chapter
		var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			push_error(error_string(error))
			quit(1)
			return
		print("POLISHED BATTLE CAPTURE: %s" % path)
		screen.queue_free()
		manager.free()
		await process_frame
	quit(0 if harness.failures == 0 else 1)
