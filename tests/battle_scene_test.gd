extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const BattleScreenScene = preload("res://scenes/battle/battle_screen.tscn")
const BoardGridScene = preload("res://scenes/battle/board_grid.tscn")

const SCENE_PATHS := [
	"res://scenes/battle/piece_slot.tscn",
	"res://scenes/battle/board_grid.tscn",
	"res://scenes/battle/hero_energy_item.tscn",
	"res://scenes/battle/hero_energy_panel.tscn",
	"res://scenes/battle/battle_hud.tscn",
	"res://scenes/battle/combat_log_entry.tscn",
	"res://scenes/battle/combat_log.tscn",
	"res://scenes/battle/battle_result_overlay.tscn",
	"res://scenes/battle/fatal_overlay.tscn",
	"res://scenes/battle/battle_screen.tscn",
]


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("every M4 battle scene instantiates with resolved scripts and paths", func() -> void:
		_test_scene_instantiation(harness)
	)
	harness.run_test("board keeps six stable 2x3 slot scene anchors in canonical order", func() -> void:
		_test_six_slot_board(harness)
	)
	harness.run_test("view model updates reuse board hero and log nodes", func() -> void:
		_test_vm_reuses_nodes(harness)
	)
	harness.run_test("result and fatal overlays lock battle inputs but retain restart slots", func() -> void:
		_test_overlay_input_lock(harness)
	)
	harness.run_test("battle layout keeps outer heroes shared arena and reserved hand", func() -> void:
		_test_layout_bounds(harness)
	)
	harness.run_test("battle binding scripts instantiate scenes while drawing stays in ui/art", func() -> void:
		_test_no_immediate_drawing(harness)
	)
	print("M4-2 BATTLE SCENE TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_scene_instantiation(harness: TestHarness) -> void:
	for path: String in SCENE_PATHS:
		var packed := load(path) as PackedScene
		harness.assert_not_null(packed, "scene failed to load: %s" % path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		harness.assert_not_null(instance, "scene failed to instantiate: %s" % path)
		if instance == null:
			continue
		_attach(instance)
		harness.assert_true(instance.is_node_ready(), "scene did not enter ready state: %s" % path)
		_release(instance)


func _test_six_slot_board(harness: TestHarness) -> void:
	var board := BoardGridScene.instantiate()
	_attach(board)
	board.bind_team({"slots": [_unit(1, "ally", 75.0), _unit(3, "ally", 0.0)]})
	var slots: Array[Node] = board.slot_nodes()
	harness.assert_equal(slots.size(), 6)
	for index in slots.size():
		harness.assert_equal(slots[index].anchor_slot(), index + 1)
		harness.assert_equal(slots[index].scene_file_path, "res://scenes/battle/piece_slot.tscn")
	harness.assert_equal(board.get_node("Grid").columns, 2)
	harness.assert_equal(slots[0].get_node("Content/ClassLine/ClassLabel").text, "棋子")
	harness.assert_equal(slots[1].get_node("Content/ClassLine/ClassLabel").text, "空位")
	harness.assert_true(slots[2].get_node("DeathMark").visible)
	harness.assert_true(slots[2].get_node("Content/ClassLine/NameStrike").visible)
	_release(board)


func _test_vm_reuses_nodes(harness: TestHarness) -> void:
	var screen := BattleScreenScene.instantiate()
	_attach(screen)
	screen.bind_view_model(_vm())
	var ally_slots: Array[Node] = screen.ally_board.slot_nodes()
	var slot_ids := _instance_ids(ally_slots)
	var ally_hero_items: Array[Node] = screen.ally_heroes.item_nodes()
	var hero_ids := _instance_ids(ally_hero_items)
	var log_entries: Array[Node] = screen.combat_log.entry_nodes()
	var log_ids := _instance_ids(log_entries)
	harness.assert_equal(screen.ally_heroes.active_item_count(), 2)
	harness.assert_equal(screen.enemy_heroes.active_item_count(), 1)
	harness.assert_equal(screen.combat_log.active_entry_count(), 2)

	var updated := _vm()
	updated["teams"]["ally"]["slots"][0]["hp"] = 25.0
	updated["heroes"]["ally"][0]["energy"] = 80.0
	updated["logs"][0]["message"] = "复用后的日志"
	screen.bind_view_model(updated)
	harness.assert_equal(_instance_ids(screen.ally_board.slot_nodes()), slot_ids)
	harness.assert_equal(_instance_ids(screen.ally_heroes.item_nodes()), hero_ids)
	harness.assert_equal(_instance_ids(screen.combat_log.entry_nodes()), log_ids)
	harness.assert_equal(ally_slots[0].get_node("Content/HpStack/HpLabel").text, "25 / 100")
	harness.assert_equal(
		ally_hero_items[0].get_node("Row/Info/EnergyLabel").text, "80 / 100"
	)
	harness.assert_equal(log_entries[0].get_node("MessageLabel").text, "复用后的日志")
	_release(screen)


func _test_overlay_input_lock(harness: TestHarness) -> void:
	var screen := BattleScreenScene.instantiate()
	_attach(screen)
	var live_vm := _vm()
	screen.bind_view_model(live_vm)
	harness.assert_false(screen.is_input_locked())
	harness.assert_false(screen.battle_hud.end_turn_button.disabled)

	var result_vm := _vm()
	result_vm["battle"]["game_over"] = true
	result_vm["battle"]["result"] = "win"
	screen.bind_view_model(result_vm)
	harness.assert_true(screen.is_input_locked())
	harness.assert_true(screen.result_overlay.visible)
	harness.assert_true(screen.battle_hud.end_turn_button.disabled)
	harness.assert_false(screen.result_overlay.restart_button.disabled)

	var fatal_vm := _vm()
	fatal_vm["fatal"] = {
		"code": "committed_failure", "message": "不可恢复", "details": {"fatal": true},
	}
	screen.bind_view_model(fatal_vm)
	harness.assert_true(screen.is_input_locked())
	harness.assert_true(screen.fatal_overlay.visible)
	harness.assert_equal(screen.fatal_overlay.code_label.text, "committed_failure")
	harness.assert_false(screen.fatal_overlay.restart_button.disabled)
	_release(screen)


func _test_layout_bounds(harness: TestHarness) -> void:
	var screen := BattleScreenScene.instantiate()
	_attach(screen)
	var field: HBoxContainer = screen.get_node("Battlefield")
	harness.assert_equal(field.get_child(0), screen.ally_heroes)
	harness.assert_equal(field.get_child(2), screen.enemy_heroes)
	harness.assert_equal(screen.ally_board.get_parent(), screen.enemy_board.get_parent())
	harness.assert_equal(screen.hand_view.get_parent(), screen)
	harness.assert_equal(screen.log_slot.get_node("LogClip/CombatLog"), screen.combat_log)
	harness.assert_true(screen.log_slot.z_index > screen.hand_view.z_index)
	_release(screen)


func _test_no_immediate_drawing(harness: TestHarness) -> void:
	var scripts := _gd_files("res://ui/battle")
	harness.assert_true(scripts.size() >= 8)
	var instantiate_count := 0
	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)
		harness.assert_false(source.contains("func _draw("), "immediate _draw found: %s" % path)
		harness.assert_false(source.contains("draw_"), "immediate draw_* found: %s" % path)
		harness.assert_false(source.contains("Control.new("), "Control.new found: %s" % path)
		harness.assert_false(source.contains("Label.new("), "Label.new found: %s" % path)
		instantiate_count += source.count(".instantiate()")
	harness.assert_true(instantiate_count >= 2, "dynamic hero/log units must instantiate PackedScenes")


static func _vm() -> Dictionary:
	var ally_slots: Array[Dictionary] = []
	var enemy_slots: Array[Dictionary] = []
	for slot in range(1, 7):
		ally_slots.append(_unit(slot, "ally", 100.0))
		enemy_slots.append(_unit(slot, "enemy", 100.0))
	ally_slots[0]["buffs"] = [{"id": "guard", "stacks": 2}]
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 2, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 7.0, "sp_max": 10.0},
		"teams": {
			"ally": {"slots": ally_slots, "health_percent": 1.0},
			"enemy": {"slots": enemy_slots, "health_percent": 1.0},
		},
		"heroes": {
			"ally": [
				{"id": 1, "name": "赤焰", "side": "ally", "energy": 20.0, "max_energy": 100.0},
				{"id": 4, "name": "骑士", "side": "ally", "energy": 40.0, "max_energy": 100.0},
			],
			"enemy": [
				{"id": 101, "name": "敌·军令", "side": "enemy", "energy": 0.0, "max_energy": 100.0},
			],
		},
		"piles": {"draw": 8, "hand": 4, "discard": 2, "exhaust": 1},
		"hand": [],
		"logs": [
			{"message": "战斗开始", "class": "ok"},
			{"message": "敌方准备行动", "class": "bad"},
		],
		"presentation": {"speed": 2.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _unit(slot: int, side: String, hp: float) -> Dictionary:
	return {
		"id": slot if side == "ally" else 100 + slot,
		"slot": slot,
		"side": side,
		"class_id": "default",
		"class_name": "棋子",
		"hp": hp,
		"max_hp": 100.0,
		"alive": hp > 0.0,
		"buffs": [],
	}


static func _instance_ids(nodes: Array[Node]) -> Array:
	var ids: Array = []
	for node: Node in nodes:
		ids.append(node.get_instance_id())
	return ids


static func _attach(node: Node) -> void:
	Engine.get_main_loop().root.add_child(node)


static func _release(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


static func _gd_files(root_path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var path := root_path.path_join(entry)
			if directory.current_is_dir():
				result.append_array(_gd_files(path))
			elif entry.ends_with(".gd"):
				result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result
