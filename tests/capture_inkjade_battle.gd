extends SceneTree
## Real-window evidence for the approved ink-jade battle layout.
## Static composition uses catalog IDs; the final captures launch through Run
## and send actual pointer events through the viewport input route.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const RunScene: PackedScene = preload("res://scenes/run.tscn")
const RunSessionScript = preload("res://app/run_session.gd")
const OUTPUT_DIR := "res://tests/artifacts/inkjade"

var _errors: Array[String] = []
var _root: Node
var _submissions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if dir_error != OK:
		_errors.append("cannot create screenshot directory: %s" % error_string(dir_error))
		_finish()
		return
	await _capture_catalog_layouts()
	await _capture_real_run_drag()
	_finish()


func _capture_catalog_layouts() -> void:
	await _set_window(Vector2i(1200, 700))
	var main := MainScene.instantiate()
	main.auto_start = false
	root.add_child(main)
	_root = main
	await _frames(5)
	main.battle_screen.hand_view.animate_layout = false
	main.battle_screen.play_card_requested.connect(func(_command: Dictionary) -> void: _submissions += 1)

	main.battle_screen.bind_view_model(_catalog_vm(false))
	await _frames(5)
	await _save("01_1200_single_rider_seven_cards.png", Vector2i(1200, 700))

	# This passes through CardView._on_input_button_gui_input. A short lift must
	# remain a hover/drag gesture and cannot issue a command.
	var cards: Array = main.battle_screen.hand_view.cards_in_order()
	if cards.is_empty():
		_errors.append("catalog evidence has no cards")
	else:
		var card: Control = cards[0]
		var center := card.get_global_rect().get_center()
		_pointer_press(center)
		_pointer_move(center + Vector2(0, -40))
		_pointer_release(center + Vector2(0, -40))
		await _frames(3)
		if _submissions != 0:
			_errors.append("short card drag submitted a command")
		_pointer_move(center)
		await _frames(2)
		await _save("02_1200_hover_real_pointer.png", Vector2i(1200, 700))
		_pointer_press(center)
		_pointer_move(center + Vector2(0, -150))
		await _frames(2)
		await _save("03_1200_drag_real_pointer.png", Vector2i(1200, 700))
		_pointer_release(center + Vector2(0, -150))
		await _frames(3)
		if _submissions != 1:
			_errors.append("long card drag did not submit exactly one command")
		_pointer_move(Vector2(600, 300))
		await _frames(2)
	main.battle_screen.set_combat_log_open(true, false)
	await _frames(3)
	await _save("04_1200_battle_log.png", Vector2i(1200, 700))

	main.battle_screen.set_combat_log_open(false, false)
	main.battle_screen.bind_view_model(_catalog_vm(true))
	await _frames(4)
	await _save("05_1200_three_heroes_mixed_six.png", Vector2i(1200, 700))
	await _set_window(Vector2i(1280, 720))
	await _frames(4)
	await _save("06_1280_three_heroes_seven_cards.png", Vector2i(1280, 720))
	await _set_window(Vector2i(1600, 900))
	await _frames(4)
	await _save("07_1600_three_heroes_seven_cards.png", Vector2i(1600, 900))
	_root.queue_free()
	_root = null
	await _frames(3)


func _capture_real_run_drag() -> void:
	await _set_window(Vector2i(1200, 700))
	var seed := _seed_with_knight()
	if seed.is_empty():
		_errors.append("could not find a deterministic Run seed offering rider")
		return
	var run := RunScene.instantiate()
	run.save_path = "res://.godot/test-logs/inkjade-run-save.json"
	root.add_child(run)
	_root = run
	await _frames(4)
	if not run.start_new_run(seed):
		_errors.append("Run entry could not start seed %s" % seed)
		return
	var state: Dictionary = run.session.snapshot()
	if 4 not in state.get("initial_hero_choice_ids", []):
		_errors.append("selected Run seed did not offer rider")
		return
	if not run.command({"type": "choose_starting_hero", "hero_id": 4}):
		_errors.append("legal Run rider selection was rejected")
		return
	state = run.session.snapshot()
	var battle_node := {}
	for node: Dictionary in state.get("map_nodes", []):
		if bool(node.get("available", false)) and str(node.get("type", "")) == "battle":
			battle_node = node
			break
	if battle_node.is_empty() or not run.command({"type": "choose_node", "node_id": battle_node["id"]}):
		_errors.append("Run battle node launch failed")
		return
	await _frames(16)
	if not is_instance_valid(run.battle):
		_errors.append("Run battle scene did not appear")
		return
	var battle: Node = run.battle
	battle.presentation_queue.drain_for_test()
	await _frames(4)
	await _save("08_real_run_rider_opening.png", Vector2i(1200, 700))
	var playable: Control = null
	for card: Node in battle.battle_screen.hand_view.cards_in_order():
		if card.is_playable():
			playable = card
			break
	if playable == null:
		_errors.append("real Run opening hand has no playable card")
		return
	var before: int = battle.logic_submission_count()
	var origin := playable.get_global_rect().get_center()
	_pointer_press(origin)
	_pointer_move(origin + Vector2(0, -45))
	_pointer_release(origin + Vector2(0, -45))
	await _frames(3)
	if battle.logic_submission_count() != before:
		_errors.append("real Run sub-threshold pointer drag submitted a command")
	_pointer_press(origin)
	_pointer_move(origin + Vector2(0, -150))
	_pointer_release(origin + Vector2(0, -150))
	await _frames(3)
	if battle.logic_submission_count() != before + 1:
		_errors.append("real Run pointer drag did not submit exactly one command")
	await _save("09_real_run_rider_drag_submitted.png", Vector2i(1200, 700))
	_root.queue_free()
	_root = null
	await _frames(3)


func _seed_with_knight() -> String:
	for index in range(80):
		var session := RunSessionScript.new({}, "res://.godot/test-logs/inkjade-seed-search.json")
		var errors: Array[String] = []
		var seed := "inkjade-rider-%d" % index
		if session.new_run(seed, errors) and 4 in session.snapshot().get("initial_hero_choice_ids", []):
			return seed
	return ""


func _pointer_press(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _pointer_move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = Vector2(0, -1)
	root.push_input(event, true)


func _pointer_release(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _set_window(size: Vector2i) -> void:
	# Evidence must use the approved fixed canvases even when a developer's
	# project setting starts the desktop client fullscreen.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	for _attempt in 45:
		if DisplayServer.window_get_size() == size:
			break
		await process_frame
	# Compatibility rendering clears the backbuffer briefly while a native
	# window resize settles; wait in real time before taking evidence.
	await create_timer(0.55).timeout
	await _frames(8)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _save(filename: String, expected_size: Vector2i) -> void:
	var image: Image
	for _attempt in 45:
		await RenderingServer.frame_post_draw
		image = root.get_texture().get_image()
		if image.get_size() == expected_size:
			break
		await process_frame
	if image.get_size() != expected_size:
		_errors.append("%s expected %s, got %s" % [filename, expected_size, image.get_size()])
		return
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename)))
	if error != OK:
		_errors.append("could not save %s: %s" % [filename, error_string(error)])
	else:
		print("INKJADE EVIDENCE: %s" % ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename)))


func _finish() -> void:
	for error: String in _errors:
		push_error(error)
	print("INKJADE CAPTURE failures=%d" % _errors.size())
	quit(0 if _errors.is_empty() else 1)


static func _catalog_vm(three_heroes: bool) -> Dictionary:
	var heroes := [{"id": 4, "name": "骑士", "side": "ally", "energy": 65, "max_energy": 100}]
	var enemies := [{"id": 101, "name": "敌·军令", "side": "enemy", "energy": 42, "max_energy": 100}]
	if three_heroes:
		heroes = [
			{"id": 1, "name": "赤焰", "side": "ally", "energy": 65, "max_energy": 100},
			{"id": 4, "name": "骑士", "side": "ally", "energy": 40, "max_energy": 100},
			{"id": 8, "name": "千机", "side": "ally", "energy": 80, "max_energy": 120},
		]
		enemies = [
			{"id": 201, "name": "敌·灼痕", "side": "enemy", "energy": 34, "max_energy": 100},
			{"id": 202, "name": "敌·炎契", "side": "enemy", "energy": 70, "max_energy": 100},
			{"id": 203, "name": "敌·命巡", "side": "enemy", "energy": 52, "max_energy": 120},
		]
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 3, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 7, "sp_max": 10},
		"teams": {"ally": {"slots": _slots("ally", 0)}, "enemy": {"slots": _slots("enemy", 100)}},
		"heroes": {"ally": heroes, "enemy": enemies},
		"piles": {"draw": 9, "hand": 7, "discard": 4, "exhaust": 1},
		"hand": _cards(),
		"logs": [{"message": "第 3 回合开始"}, {"message": "棋阵整备完成"}, {"message": "敌方正在观势"}],
		"presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _cards() -> Array[Dictionary]:
	return [
		_card("free-guard", "pieceBlock", "棋子格挡", "消耗1技能点。全体我方棋子获得15%临时格挡率，持续1回合。", "free", 0, 1),
		_card("free-power", "pieceDamageUp", "棋子增伤", "消耗1技能点。全体我方棋子直接伤害+30%，持续1回合。", "free", 0, 1),
		_card("free-burn", "markBurn", "灼痕标记", "消耗0技能点。对敌方灼烧层数最高单位施加1层灼烧。", "free", 0, 0),
		_card("free-execute", "executeStrike", "斩杀", "消耗2技能点。令我方攻击力最高的棋子立即攻击敌方血量最低棋子。", "free", 0, 2),
		_card("exclusive-shadow", "shadow", "潜影", "消耗1技能点。使我方攻击最高的非傀儡棋子进入潜行1回合。", "exclusive", 9, 1),
		_card("exclusive-fist", "fist", "拳势", "消耗1技能点。提升我方棋阵的连续进攻能力。", "exclusive", 6, 1),
		_card("ultimate-knight", "counterAura", "骑士道誓", "消耗100能量。全体我方棋子获得骑士道。", "ultimate", 4, 0),
	]


static func _card(id: String, skill_id: String, name: String, description: String, category: String, owner: int, cost: int) -> Dictionary:
	return {"instance_id": id, "card_id": "%s:%s" % [category, skill_id], "source_skill_id": skill_id, "name": name, "description": description, "category": category, "owner_hero_id": owner, "base_cost": cost, "effective_cost": cost, "play_destination": "discard", "exhausts_on_success": false, "playable": true, "unavailable_reason": ""}


static func _slots(side: String, offset: int) -> Array[Dictionary]:
	var classes := ["shield", "shield", "shield", "assassin", "crossbow", "banner"]
	var slots: Array[Dictionary] = []
	for index in 6:
		slots.append({"slot": index + 1, "id": offset + index + 1, "side": side, "class_id": classes[index], "class_name": classes[index], "hp": 58 + index * 6, "max_hp": 100, "alive": true, "buffs": []})
	return slots
