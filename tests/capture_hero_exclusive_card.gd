extends SceneTree

const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const BattleScreenScene = preload("res://scenes/battle/battle_screen.tscn")

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1200, 700))
	root.size = Vector2i(1200, 700)
	var manager := HandManagerScript.new()
	var controller := ControllerScript.new(manager)
	var started: Variant = controller.start({
		"battle_seed": "hero-exclusive-card-capture",
		"deployed_hero_ids": [7],
		"free_skill_ids": ["smallHeal", "markBurn"],
		"stage_id": "counter",
		"exclusive_card_ids": ["exclusive:pressOpening"],
	})
	if not started.ok:
		push_error(started.message)
		quit(1)
		return
	var state: Dictionary = controller._runtime.component("state")
	var buffs: Variant = controller._runtime.component("buffs")
	if not buffs.apply_unit(state["enemies"][0], "breakMarked"):
		push_error("failed to apply real breakMarked")
		quit(1)
		return
	var screen := BattleScreenScene.instantiate()
	root.add_child(screen)
	screen.bind_view_model(controller.view_model())
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var output := "res://tests/artifacts/hero_exclusive/press_opening.png"
	var result := image.save_png(ProjectSettings.globalize_path(output))
	if result != OK:
		push_error("screenshot save failed")
		quit(1)
		return
	print("HERO EXCLUSIVE CAPTURE: %s size=%s" % [output, str(image.get_size())])
	screen.free()
	manager.free()
	quit(0)
