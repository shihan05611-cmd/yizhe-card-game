extends SceneTree

const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const BattleScreenScene = preload("res://scenes/battle/battle_screen.tscn")

var _manager: Node
var _screen: Node

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1200, 700))
	root.size = Vector2i(1200, 700)
	var controller := ControllerScript.new(HandManagerScript.new())
	_manager = controller._hand_manager
	var started: Variant = controller.start({
		"battle_seed": "hero-status-capture",
		"deployed_hero_ids": [5, 6, 8],
		"free_skill_ids": ["pieceBlock", "pieceDamageUp", "markBurn", "executeStrike"],
		"stage_id": "counter",
	})
	if not started.ok:
		push_error(started.message)
		quit(1)
		return
	var state: Dictionary = controller._runtime.component("state")
	var growth_port: Variant = controller._runtime.component("growth_port")
	growth_port.stage_batch({"requests": [
		{"id": "fistMastery", "target": {"type": "hero", "id": 6}, "stacks": 3},
		{"id": "flamePractice", "target": {"type": "hero", "id": 5}, "stacks": 2},
	]})
	for hero: Dictionary in state["player_heroes"]:
		if int(hero["id"]) == 6:
			hero["fist_momentum"] = 3
		hero["energy"] = {5: 25, 6: 60, 8: 90}.get(int(hero["id"]), 0)
	for hero: Dictionary in state["enemy_heroes"]:
		hero["energy"] = 45
	state["ally_puppet_martyr_active"] = true
	state["battle_growth_flags"]["flame_investment_used"] = true
	_screen = BattleScreenScene.instantiate()
	root.add_child(_screen)
	var vm: Dictionary = controller.view_model()
	_screen.bind_view_model(vm)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var output := "res://tests/artifacts/hero_status/hero_status_1200x700.png"
	var result := image.save_png(ProjectSettings.globalize_path(output))
	if result != OK:
		push_error("screenshot save failed")
		quit(1)
		return
	print("HERO STATUS CAPTURE: %s size=%s" % [output, str(image.get_size())])
	var single_vm := vm.duplicate(true)
	for hero: Dictionary in single_vm["heroes"]["ally"]:
		if int(hero.get("id", 0)) == 6:
			single_vm["heroes"]["ally"] = [hero]
			break
	_screen.bind_view_model(single_vm)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var single_image := root.get_viewport().get_texture().get_image()
	var single_output := "res://tests/artifacts/hero_status/hero_status_single_1200x700.png"
	result = single_image.save_png(ProjectSettings.globalize_path(single_output))
	if result != OK:
		push_error("single screenshot save failed")
		quit(1)
		return
	print("HERO STATUS CAPTURE: %s size=%s" % [single_output, str(single_image.get_size())])
	_screen.free()
	_manager.free()
	quit(0)

