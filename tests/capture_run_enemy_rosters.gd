extends SceneTree

## Visual acceptance evidence for the chapter-scaled Run enemy Yizhe roster.
## Each capture starts from a genuine lifecycle battle launch and binds the
## controller's view model to the production BattleScreen scene.

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")
const OUTPUT_DIR := "res://tests/artifacts/run_enemy_rosters"
const EXPECTED_ENEMY_IDS := {1: [101], 2: [101, 102], 3: [101, 102, 103]}

var _errors: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)) != OK:
		_errors.append("cannot create Run enemy roster evidence directory")
		_finish()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1200, 700))
	await _frames(10)
	var launched := _new_run("run-enemy-rosters")
	if launched.is_empty():
		_finish()
		return
	for chapter in range(1, 4):
		if not await _capture_chapter(launched, chapter):
			break
		if chapter < 3 and not _advance_to_next_chapter(launched):
			break
	_finish()


func _new_run(seed: String) -> Dictionary:
	var errors: Array[String] = []
	var catalogs := ContentCatalogScript.build(errors)
	var state := RunContractScript.create()
	var random := TransactionalRandomScript.new(RngScript.seeded(seed), errors)
	var lifecycle := RunLifecycleScript.new(state, catalogs, random, errors)
	if not errors.is_empty() or not lifecycle.start_run(errors):
		_errors.append("Run setup failed: %s" % "; ".join(errors))
		return {}
	var selected: Dictionary = lifecycle._state
	if not lifecycle.choose_starting_hero(selected["initial_hero_choice_ids"][0], errors):
		_errors.append("Run hero selection failed: %s" % "; ".join(errors))
		return {}
	return {"lifecycle": lifecycle}


func _capture_chapter(fixture: Dictionary, chapter: int) -> bool:
	var lifecycle: Variant = fixture["lifecycle"]
	var state: Dictionary = lifecycle._state
	if state["chapter"] != chapter:
		_errors.append("expected chapter %d launch, got %d" % [chapter, state["chapter"]])
		return false
	var battle := _first_available_battle(state)
	if battle.is_empty():
		_errors.append("chapter %d has no available battle node" % chapter)
		return false
	var errors: Array[String] = []
	if not lifecycle.choose_node(battle["id"], errors):
		_errors.append("chapter %d node launch failed: %s" % [chapter, "; ".join(errors)])
		return false
	var launch: Dictionary = lifecycle.begin_current_battle(errors)
	if launch.is_empty():
		_errors.append("chapter %d battle bootstrap launch failed: %s" % [chapter, "; ".join(errors)])
		return false
	var manager := HandManagerScript.new()
	var controller := ControllerScript.new(manager)
	var started: Variant = controller.start(launch)
	if not started.ok:
		_errors.append("chapter %d controller start failed: %s" % [chapter, started.message])
		manager.free()
		return false
	var vm: Dictionary = controller.view_model()
	var enemy_heroes: Array = vm["heroes"]["enemy"]
	var actual_ids := enemy_heroes.map(func(hero: Dictionary) -> Variant: return hero["id"])
	if actual_ids != EXPECTED_ENEMY_IDS[chapter]:
		_errors.append("chapter %d enemy ids expected %s, got %s" % [chapter, str(EXPECTED_ENEMY_IDS[chapter]), str(actual_ids)])
		manager.free()
		return false
	var screen: Control = BattleScreenScene.instantiate()
	if not screen.has_method("bind_view_model"):
		_errors.append("chapter %d BattleScreen script failed to load" % chapter)
		screen.free()
		manager.free()
		return false
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1200, 700)
	root.add_child(screen)
	screen.hand_view.animate_layout = false
	screen.bind_view_model(vm)
	await _frames(10)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_size() != Vector2i(1200, 700):
		_errors.append("chapter %d capture expected 1200x700, got %s" % [chapter, image.get_size()])
	else:
		var output := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("chapter_%d.png" % chapter))
		var save_error := image.save_png(output)
		if save_error != OK:
			_errors.append("chapter %d capture save failed: %s" % [chapter, error_string(save_error)])
		else:
			print("RUN ENEMY ROSTER CAPTURE: %s" % output)
	screen.queue_free()
	manager.free()
	await _frames(3)
	if not lifecycle.cancel_current_battle_launch(launch["run_progress"], errors):
		_errors.append("chapter %d launch cancel failed: %s" % [chapter, "; ".join(errors)])
		return false
	if not lifecycle.complete_current_battle(true, errors):
		_errors.append("chapter %d battle completion failed: %s" % [chapter, "; ".join(errors)])
		return false
	if not _resolve_rewards(lifecycle):
		return false
	return true


func _advance_to_next_chapter(fixture: Dictionary) -> bool:
	var lifecycle: Variant = fixture["lifecycle"]
	var original_chapter: int = lifecycle._state["chapter"]
	var guard := 0
	while lifecycle._state["chapter"] == original_chapter and guard < 20:
		guard += 1
		var state: Dictionary = lifecycle._state
		var node := _first_available_node(state)
		if node.is_empty():
			_errors.append("chapter %d has no route to its next chapter" % original_chapter)
			return false
		var errors: Array[String] = []
		if not lifecycle.choose_node(node["id"], errors):
			_errors.append("chapter %d route node failed: %s" % [original_chapter, "; ".join(errors)])
			return false
		if lifecycle._state["status"] == "fighting":
			if not lifecycle.complete_current_battle(true, errors):
				_errors.append("chapter %d route battle failed: %s" % [original_chapter, "; ".join(errors)])
				return false
		else:
			var completed_node: bool = (
				lifecycle.skip_retained_card_event(errors)
				if lifecycle._state["status"] == "event" and lifecycle._state["current_event_kind"] == "retain_card"
				else lifecycle.complete_current_node(errors)
			)
			if not completed_node:
				_errors.append("chapter %d route node completion failed: %s" % [original_chapter, "; ".join(errors)])
				return false
		if not _resolve_rewards(lifecycle):
			return false
	if lifecycle._state["chapter"] != original_chapter + 1:
		_errors.append("chapter %d route did not reach next chapter" % original_chapter)
		return false
	return true


func _resolve_rewards(lifecycle: Variant) -> bool:
	var guard := 0
	while lifecycle._state["status"] == "reward" and guard < 4:
		guard += 1
		var option: Dictionary = lifecycle._state["reward_options"][0]
		var errors: Array[String] = []
		var accepted: bool = (
			lifecycle.recruit_hero(option["payload_id"], errors)
			if option["type"] == "hero"
			else lifecycle.select_reward(option["id"], errors)
		)
		if not accepted:
			_errors.append("reward resolution failed: %s" % "; ".join(errors))
			return false
	if lifecycle._state["status"] == "reward":
		_errors.append("reward chain did not resolve")
		return false
	return true


func _first_available_battle(state: Dictionary) -> Dictionary:
	for node: Dictionary in state["map_nodes"]:
		if node["available"] and node["type"] == "battle":
			return node
	return {}


func _first_available_node(state: Dictionary) -> Dictionary:
	for node: Dictionary in state["map_nodes"]:
		if node["available"]:
			return node
	return {}


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _finish() -> void:
	for error: String in _errors:
		push_error(error)
	print("RUN ENEMY ROSTER CAPTURE failures=%d" % _errors.size())
	quit(0 if _errors.is_empty() else 1)
