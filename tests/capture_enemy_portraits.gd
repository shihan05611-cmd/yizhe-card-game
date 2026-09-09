extends SceneTree

const ItemScene = preload("res://scenes/battle/hero_energy_item.tscn")
const ScreenScene = preload("res://scenes/battle/battle_screen.tscn")
const Controller = preload("res://app/battle_controller.gd")
const Manager = preload("res://autoload/hand_manager.gd")
const OUTPUT := "res://tests/artifacts/enemy_portraits/"

func _init() -> void:
	call_deferred("_capture")

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT + name)
	if result != OK:
		push_error("portrait capture failed: " + name)
		quit(1)
	print("PORTRAIT CAPTURE: " + name)

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DisplayServer.window_set_size(Vector2i(1200, 700))
	root.size = Vector2i(1200, 700)
	var gallery := ColorRect.new()
	gallery.color = Color("182b23")
	gallery.size = Vector2(1200, 700)
	root.add_child(gallery)
	var portraits := [[101,"军令","ascend"],[102,"铁卫","counterAura"],[103,"千机","puppet"],[201,"灼痕","burn01"],[202,"炎契","burnEnchant"],[203,"命巡","fate"],[301,"无锋","fist"],[302,"沉戈","siege"]]
	for index in portraits.size():
		var item := ItemScene.instantiate()
		gallery.add_child(item)
		item.position = Vector2(32 + (index % 4) * 294, 24 + (index / 4) * 330)
		item.size = Vector2(260, 310)
		item.bind_hero({"id":portraits[index][0],"name":portraits[index][1],"ex_skill":portraits[index][2],"side":"enemy","energy":35,"max_energy":100})
	await _shot("gallery.png")
	gallery.free()
	var manager := Manager.new()
	var controller := Controller.new(manager)
	var started: Variant = controller.start({"battle_seed":"enemy-portrait-capture","deployed_hero_ids":[6],"free_skill_ids":["smallHeal","markBurn"],"stage_id":"counter"})
	if not started.ok:
		push_error(started.message)
		manager.free()
		quit(1)
		return
	var screen := ScreenScene.instantiate()
	root.add_child(screen)
	var vm: Dictionary = controller.view_model()
	screen.bind_view_model(vm)
	await _shot("battle_three.png")
	vm["heroes"]["enemy"] = vm["heroes"]["enemy"].slice(0, 1)
	screen.bind_view_model(vm)
	await _shot("battle_one.png")
	screen.free()
	manager.free()
	quit(0)
