extends SceneTree

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const OUTPUT_DIR := "res://tests/artifacts/m4"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1200, 700))
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if directory_error != OK:
		_failures.append("cannot create evidence directory: %s" % error_string(directory_error))
		_finish()
		return

	var layout_root: Variant = MainScene.instantiate()
	layout_root.auto_start = false
	root.add_child(layout_root)
	await _settle_frames(3)
	layout_root.battle_screen.hand_view.animate_layout = false
	layout_root.battle_screen.bind_view_model(_seven_card_vm())
	await _settle_frames(3)
	_save_viewport("01_battle_ui_7_cards.png")

	var first_card: Variant = layout_root.battle_screen.hand_view.cards_in_order()[0]
	first_card.set_hovered(true, false)
	await _settle_frames(2)
	_save_viewport("02_card_hover.png")
	first_card.set_hovered(false, false)
	var drag_origin: Vector2 = first_card.get_global_rect().get_center()
	if not first_card.begin_drag_at(drag_origin):
		_failures.append("first evidence card did not enter drag state")
	else:
		first_card.drag_to(drag_origin + Vector2(0, -96))
		await _settle_frames(2)
		_save_viewport("03_card_drag.png")
		first_card.cancel_drag(false)
	layout_root.free()
	await _settle_frames(2)

	var one: Variant = _production_root("m4-visual-same-action")
	one.presentation_queue.drain_for_test()
	one.set_presentation_speed(1.0)
	var one_card := _first_playable(one.controller.view_model())
	one.submit_play_card(_guard(one_card))
	await _settle_frames(2)
	_save_viewport("04_same_action_1x.png")
	one.free()
	await _settle_frames(2)

	var four: Variant = _production_root("m4-visual-same-action")
	four.presentation_queue.drain_for_test()
	four.set_presentation_speed(4.0)
	var four_card := _first_playable(four.controller.view_model())
	four.submit_play_card(_guard(four_card))
	await _settle_frames(2)
	_save_viewport("05_same_action_4x.png")
	if "--cards-only" in OS.get_cmdline_user_args():
		four.free()
		_finish()
		return
	four.presentation_queue.drain_for_test()
	var completed: Dictionary = four.drive_auto_for_test(256)
	if not completed.get("complete", false):
		_failures.append("visual evidence auto battle did not reach a terminal result: %s" % str(completed))
	await _settle_frames(3)
	_save_viewport("06_battle_result.png")
	four.free()
	_finish()


func _production_root(seed: String) -> Variant:
	var battle_root: Variant = MainScene.instantiate()
	battle_root.battle_seed = seed
	root.add_child(battle_root)
	return battle_root


func _save_viewport(filename: String) -> void:
	var image := root.get_texture().get_image()
	if image.get_size() != Vector2i(1200, 700):
		_failures.append("%s has wrong size: %s" % [filename, image.get_size()])
		return
	var path := OUTPUT_DIR.path_join(filename)
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		_failures.append("cannot save %s: %s" % [path, error_string(error)])
	else:
		print("M4 VISUAL EVIDENCE: %s" % ProjectSettings.globalize_path(path))


func _settle_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _finish() -> void:
	for failure in _failures:
		print("M4 VISUAL FAILURE: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


static func _first_playable(vm: Dictionary) -> Dictionary:
	for card: Dictionary in vm.get("hand", []):
		if card.get("playable", false):
			return card
	return {}


static func _guard(card: Dictionary) -> Dictionary:
	return {
		"type": "play_card",
		"instance_id": card.get("instance_id", ""),
		"expected_card_id": card.get("card_id", ""),
		"expected_source_skill_id": card.get("source_skill_id", ""),
		"owner_hero_id": card.get("owner_hero_id"),
	}


static func _seven_card_vm() -> Dictionary:
	var hand: Array[Dictionary] = []
	var names := ["棋子格挡", "棋子强化", "施加灼烧", "处决一击", "小型治疗", "获得技能点", "生命强化"]
	for index in 7:
		hand.append({
			"instance_id": "visual-card-%02d" % index,
			"card_id": "free:visual-%02d" % index,
			"source_skill_id": "visual-%02d" % index,
			"name": names[index],
			"description": "同一 1200×700 窗口下的七张手牌布局证据。",
			"category": "free",
			"owner_hero_id": 0,
			"base_cost": 1 + index % 3,
			"effective_cost": 1 + index % 3,
			"play_destination": "discard",
			"exhausts_on_success": false,
			"playable": true,
			"unavailable_reason": "",
		})
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 3, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 7, "sp_max": 10},
		"teams": {
			"ally": {"slots": _visual_slots("ally", 800.0, 1000.0)},
			"enemy": {"slots": _visual_slots("enemy", 610.0, 1000.0)},
		},
		"heroes": {
			"ally": [_visual_hero(1, "灼华", "ally", 65.0)],
			"enemy": [_visual_hero(101, "试炼敌手", "enemy", 40.0)],
		},
		"piles": {"draw": 9, "hand": 7, "discard": 4, "exhaust": 1},
		"hand": hand,
		"logs": [
			{"message": "第 3 回合开始", "source": {"side": "ally"}},
			{"message": "双方棋阵已就绪", "source": {"side": "system"}},
		],
		"presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _visual_slots(side: String, current_total: float, max_total: float) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for index in 6:
		var max_hp := max_total / 6.0
		var hp := current_total / 6.0
		slots.append({
			"slot": index + 1,
			"id": 1000 + index + (0 if side == "ally" else 100),
			"side": side,
			"name": ("我方" if side == "ally" else "敌方") + "棋子 %d" % (index + 1),
			"class_id": ["guard", "warrior", "archer"][index % 3],
			"hp": hp,
			"max_hp": max_hp,
			"attack": 24 + index * 3,
			"alive": true,
		})
	return slots


static func _visual_hero(hero_id: int, name: String, side: String, energy: float) -> Dictionary:
	return {
		"hero_id": hero_id,
		"id": hero_id,
		"name": name,
		"side": side,
		"energy": energy,
		"max_energy": 100.0,
		"energy_percent": energy / 100.0,
		"portrait": "",
	}
