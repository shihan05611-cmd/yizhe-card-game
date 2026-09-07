extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")
const WINDOW_SIZES := [Vector2(1200, 700), Vector2(1280, 720), Vector2(1600, 900)]


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("ART-1 scene uses container root mirrored columns and an overlay hand layer", func() -> void:
		_test_structure(harness)
	)
	harness.run_test("ART-1 responsive skeleton stays mirrored at three window sizes", func() -> void:
		_test_three_sizes(harness)
	)
	print("ART-1 RESPONSIVE BATTLE SKELETON TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_structure(harness: TestHarness) -> void:
	var screen: Variant = _screen(WINDOW_SIZES[0])
	var field: HBoxContainer = screen.get_node("Battlefield")
	harness.assert_equal(field.get_child(0), screen.ally_heroes)
	harness.assert_equal(field.get_child(2), screen.enemy_heroes)
	harness.assert_equal(screen.ally_board.get_parent(), screen.enemy_board.get_parent())
	harness.assert_equal(screen.hand_view.get_parent(), screen)
	harness.assert_true(screen.log_slot.z_index > screen.hand_view.z_index)
	harness.assert_true(screen.result_overlay.z_index > screen.log_slot.z_index)
	harness.assert_true(screen.fatal_overlay.z_index > screen.log_slot.z_index)
	_release(screen)


func _test_three_sizes(harness: TestHarness) -> void:
	for window_size: Vector2 in WINDOW_SIZES:
		var screen: Variant = _screen(window_size)
		var field: Control = screen.get_node("Battlefield")
		harness.assert_equal(screen.size, window_size)
		_assert_inside(harness, field, window_size, "battlefield")
		_assert_inside(harness, screen.hand_view, window_size, "hand")
		harness.assert_equal(screen.ally_board.size, screen.enemy_board.size)
		harness.assert_true(field.get_rect().end.y < screen.hand_view.position.y)
		for panel: Node in [screen.ally_heroes, screen.enemy_heroes]:
			for item: Control in panel.item_nodes():
				harness.assert_true(item.size.y >= 76)
		for board: Node in [screen.ally_board, screen.enemy_board]:
			harness.assert_equal(board.slot_nodes().size(), 6)
			for slot: Control in board.slot_nodes():
				harness.assert_true(slot.size.y >= 102)
		_release(screen)


func _screen(window_size: Vector2) -> Variant:
	var screen: Variant = BattleScreenScene.instantiate()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.position = Vector2.ZERO
	screen.size = window_size
	Engine.get_main_loop().root.add_child(screen)
	screen.bind_view_model(_vm())
	screen.set_combat_log_open(true, false)
	_force_layout(screen)
	_force_layout(screen)
	return screen


static func _force_layout(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children():
		_force_layout(child)


static func _release(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


static func _assert_column_order(
	harness: TestHarness,
	column: VBoxContainer,
	title_name: String,
	heroes: Node,
	board: Node,
) -> void:
	harness.assert_equal(column.get_child_count(), 3)
	harness.assert_equal(column.get_child(0).name, title_name)
	harness.assert_equal(column.get_child(1), heroes)
	harness.assert_equal(column.get_child(2), board)


static func _assert_inside(harness: TestHarness, control: Control, bounds: Vector2, label: String) -> void:
	var rect := control.get_rect()
	harness.assert_true(rect.position.x >= -0.01 and rect.position.y >= -0.01, "%s starts outside: %s" % [label, rect])
	harness.assert_true(rect.end.x <= bounds.x + 0.01 and rect.end.y <= bounds.y + 0.01, "%s ends outside: %s" % [label, rect])


static func _vm() -> Dictionary:
	var allies: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	for slot in range(1, 7):
		allies.append(_unit(slot, "ally"))
		enemies.append(_unit(slot, "enemy"))
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 7, "sp_max": 10},
		"teams": {"ally": {"slots": allies}, "enemy": {"slots": enemies}},
		"heroes": {
			"ally": [
				{"id": 1, "name": "赤焰", "side": "ally", "energy": 20, "max_energy": 100},
				{"id": 4, "name": "骑士", "side": "ally", "energy": 40, "max_energy": 100},
			],
			"enemy": [{"id": 101, "name": "敌·军令", "side": "enemy", "energy": 0, "max_energy": 100}],
		},
		"piles": {"draw": 8, "hand": 0, "discard": 2, "exhaust": 1},
		"hand": [],
		"logs": [],
		"presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _unit(slot: int, side: String) -> Dictionary:
	return {
		"id": slot if side == "ally" else 100 + slot,
		"slot": slot,
		"side": side,
		"class_id": "default",
		"class_name": "棋子",
		"hp": 100.0,
		"max_hp": 100.0,
		"alive": true,
		"buffs": [],
	}
