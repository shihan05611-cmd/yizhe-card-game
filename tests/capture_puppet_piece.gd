extends SceneTree

const Controller = preload("res://app/battle_controller.gd")
const Manager = preload("res://autoload/hand_manager.gd")
const Screen = preload("res://scenes/battle/battle_screen.tscn")
const Slot = preload("res://scenes/battle/piece_slot.tscn")
const OUTPUT := "res://tests/artifacts/puppet_piece/"

func _init() -> void:
	call_deferred("_capture")

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT + name)
	if result != OK:
		push_error("puppet screenshot failed")
		quit(1)
	print("PUPPET CAPTURE: " + name)

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DisplayServer.window_set_size(Vector2i(1200, 700))
	root.size = Vector2i(1200, 700)
	var manager := Manager.new()
	var controller := Controller.new(manager)
	var started: Variant = controller.start({"battle_seed":"puppet-art","deployed_hero_ids":[8],"free_skill_ids":[],"stage_id":"counter"})
	if not started.ok:
		push_error(started.message)
		quit(1)
		return
	var state: Dictionary = controller._runtime.component("state")
	# Establish an available summon slot, then use the actual exclusive handler.
	state["allies"][0]["hp"] = 0.0
	state["allies"][0]["alive"] = false
	var card: Dictionary = controller.view_model()["hand"][0]
	var played: Variant = controller.play_card(card["instance_id"])
	if not played.ok:
		push_error(played.message)
		quit(1)
		return
	var vm: Dictionary = controller.view_model()
	var screen := Screen.instantiate()
	root.add_child(screen)
	screen.bind_view_model(vm)
	await _shot("battle.png")
	screen.free()
	var backdrop := ColorRect.new()
	backdrop.color = Color("182b23")
	backdrop.size = Vector2(1200, 700)
	root.add_child(backdrop)
	var puppet: Dictionary = state["allies"][0].duplicate(true)
	for index in 3:
		var entry := puppet.duplicate(true)
		entry["side"] = "enemy" if index == 1 else "ally"
		if index == 2:
			entry["alive"] = false
			entry["hp"] = 0.0
		var slot := Slot.instantiate()
		backdrop.add_child(slot)
		slot.position = Vector2(50 + index * 385, 70)
		slot.size = Vector2(330, 550)
		slot.bind_slot(entry)
	await _shot("gallery.png")
	backdrop.free()
	manager.free()
	quit(0)
