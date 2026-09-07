extends SceneTree

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const OUTPUT_DIR := "res://tests/artifacts/approved_m4"
const DEFAULT_SIZE := Vector2i(1200, 700)

var _failures: Array[String] = []
var _layout_root: Variant


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if directory_error != OK:
		_failures.append("cannot create evidence directory: %s" % error_string(directory_error))
		_finish()
		return

	await _set_window_size(DEFAULT_SIZE)
	_layout_root = MainScene.instantiate()
	_layout_root.auto_start = false
	root.add_child(_layout_root)
	await _settle_frames(4)
	_layout_root.battle_screen.hand_view.animate_layout = false

	_layout_root.battle_screen.bind_view_model(_visual_vm(3))
	_layout_root.battle_screen.set_combat_log_open(false, false)
	await _settle_frames(4)
	_save_viewport("01_default_log_hidden.png", DEFAULT_SIZE)

	_layout_root.battle_screen.set_combat_log_open(true, false)
	await _settle_frames(4)
	_save_viewport("02_log_opened.png", DEFAULT_SIZE)

	_layout_root.battle_screen.set_combat_log_open(false, false)
	_layout_root.battle_screen.bind_view_model(_visual_vm(7))
	await _settle_frames(4)
	_save_viewport("03_hand_7.png", DEFAULT_SIZE)

	_layout_root.battle_screen.bind_view_model(_visual_vm(0))
	await _settle_frames(4)
	_save_viewport("04_hand_0.png", DEFAULT_SIZE)

	_layout_root.battle_screen.bind_view_model(_visual_vm(7))
	await _settle_frames(4)
	var cards: Array = _layout_root.battle_screen.hand_view.cards_in_order()
	if cards.size() < 5:
		_failures.append("hover/drag evidence requires at least five cards")
	else:
		var hovered: Variant = cards[1]
		var dragged: Variant = cards[4]
		hovered.set_hovered(true, false)
		var drag_origin: Vector2 = dragged.get_global_rect().get_center()
		if not dragged.begin_drag_at(drag_origin):
			_failures.append("evidence card did not enter drag state")
		else:
			dragged.drag_to(drag_origin + Vector2(0, -72))
		await _settle_frames(3)
		_save_viewport("05_hover_drag.png", DEFAULT_SIZE)
		dragged.cancel_drag(false)
		hovered.set_hovered(false, false)

	var result_vm := _visual_vm(0)
	result_vm["battle"]["game_over"] = true
	result_vm["battle"]["result"] = "win"
	_layout_root.battle_screen.bind_view_model(result_vm)
	await _settle_frames(4)
	_save_viewport("06_result.png", DEFAULT_SIZE)

	await _set_window_size(Vector2i(1600, 900))
	_layout_root.battle_screen.bind_view_model(_visual_vm(7))
	_layout_root.battle_screen.set_combat_log_open(false, false)
	await _settle_frames(4)
	_save_viewport("07_1600x900.png", Vector2i(1600, 900))

	await _set_window_size(Vector2i(1280, 720))
	_layout_root.battle_screen.bind_view_model(_visual_vm(7))
	_layout_root.battle_screen.set_combat_log_open(false, false)
	await _settle_frames(4)
	_save_viewport("08_1280x720.png", Vector2i(1280, 720))

	await _set_window_size(DEFAULT_SIZE)
	var multi := _visual_vm(7)
	multi["heroes"]["ally"] = [_visual_hero(1, "赤焰", "ally", 65), _visual_hero(6, "宁不凡", "ally", 45), _visual_hero(8, "千机", "ally", 80)]
	multi["heroes"]["enemy"] = [_visual_hero(6, "宁不凡", "enemy", 40), _visual_hero(8, "千机", "enemy", 70), _visual_hero(1, "赤焰", "enemy", 20)]
	_layout_root.battle_screen.bind_view_model(multi)
	await _settle_frames(4)
	_save_viewport("09_three_heroes.png", DEFAULT_SIZE)

	# Actual coordinator, actual deck, actual commands; fixture captures above are separate.
	_layout_root.free()
	_layout_root = MainScene.instantiate()
	root.add_child(_layout_root)
	await _wait_idle()
	_save_viewport("10_actual_game.png", DEFAULT_SIZE)
	var played := false
	for card: Node in _layout_root.battle_screen.hand_view.cards_in_order():
		if card.is_playable():
			var origin: Vector2 = card.get_global_rect().get_center()
			if card.begin_drag_at(origin):
				card.drag_to(origin + Vector2(0, -160))
				card.end_drag_at(origin + Vector2(0, -160))
				played = true
				break
	if not played:
		_failures.append("actual hand had no playable drag command")
	await _wait_idle()
	_save_viewport("11_actual_card_played.png", DEFAULT_SIZE)
	if _layout_root.logic_submission_count() != 1:
		_failures.append("actual drag did not submit exactly one command")
	_layout_root.set_presentation_speed(4.0)
	_layout_root.battle_screen.battle_hud.end_turn_button.pressed.emit()
	await _settle_frames(10)
	_save_viewport("12_actual_combat.png", DEFAULT_SIZE)
	await _wait_idle()
	_save_viewport("13_actual_next_round.png", DEFAULT_SIZE)
	if _layout_root.logic_submission_count() != 2:
		_failures.append("actual end-turn did not submit exactly one additional command")

	_layout_root.free()
	_layout_root = null
	await _settle_frames(2)
	_finish()


func _set_window_size(target: Vector2i) -> void:
	DisplayServer.window_set_size(target)
	await _settle_frames(5)


func _wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while _layout_root.presentation_queue.is_busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	if _layout_root.presentation_queue.is_busy():
		_failures.append("presentation did not finish within 60 seconds")
	await _settle_frames(8)


func _save_viewport(filename: String, expected_size: Vector2i) -> void:
	var image := root.get_texture().get_image()
	if image.get_size() != expected_size:
		_failures.append("%s has wrong size: expected %s, got %s" % [
			filename, expected_size, image.get_size(),
		])
		return
	var path := OUTPUT_DIR.path_join(filename)
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		_failures.append("cannot save %s: %s" % [path, error_string(error)])
	else:
		print("ART LAYOUT EVIDENCE: %s" % ProjectSettings.globalize_path(path))


func _settle_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _finish() -> void:
	for failure: String in _failures:
		print("ART LAYOUT VISUAL FAILURE: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


static func _visual_vm(hand_count: int) -> Dictionary:
	var hand: Array[Dictionary] = []
	var names := ["棋子格挡", "棋子强化", "施加灼烧", "处决一击", "小型治疗", "获得技能点", "生命强化"]
	for index in hand_count:
		hand.append({
			"instance_id": "art-card-%02d" % index,
			"card_id": "free:art-%02d" % index,
			"source_skill_id": "art-%02d" % index,
			"name": names[index],
			"description": "恢复生命、强化棋子或改变本回合的战斗节奏。",
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
			"ally": {"slots": _visual_slots("ally", 0)},
			"enemy": {"slots": _visual_slots("enemy", 100)},
		},
		"heroes": {
			"ally": [_visual_hero(1, "赤焰", "ally", 65.0)],
			"enemy": [_visual_hero(6, "宁不凡", "enemy", 40.0)],
		},
		"piles": {"draw": 9, "hand": hand_count, "discard": 4, "exhaust": 1},
		"hand": hand,
		"logs": [
			{"message": "第 3 回合开始", "source": {"side": "ally"}},
			{"message": "我方棋阵获得先手机会", "source": {"side": "ally"}},
			{"message": "敌方守卫准备格挡", "source": {"side": "enemy"}},
			{"message": "等待玩家行动", "source": {"side": "system"}},
		],
		"presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _visual_slots(side: String, id_offset: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var classes := ["shield", "crossbow", "assassin", "banner", "shield", "crossbow"]
	for index in 6:
		var alive := index != 5 or side == "ally"
		slots.append({
			"slot": index + 1,
			"id": 1000 + id_offset + index,
			"side": side,
			"name": ("我方" if side == "ally" else "敌方") + "棋子 %d" % (index + 1),
			"class_id": classes[index],
			"hp": float(55 + index * 7) if alive else 0.0,
			"max_hp": 100.0,
			"attack": 24 + index * 3,
			"alive": alive,
			"buffs": [] if index % 2 == 0 else [{"id": "guard", "stacks": 2}],
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

