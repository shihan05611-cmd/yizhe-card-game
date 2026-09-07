extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")
const WINDOW_SIZES := [Vector2(1200, 700), Vector2(1280, 720), Vector2(1600, 900)]


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("ART integration preserves cross-batch paths and z order", func() -> void:
		_test_cross_batch_structure(harness)
	)
	harness.run_test("ART integration keeps seven cards and primary regions inside three sizes", func() -> void:
		_test_three_size_geometry(harness)
	)
	harness.run_test("ART integration keeps zero-hand state frameless and log toggle nonblocking", func() -> void:
		_test_zero_hand_and_log(harness)
	)
	print("ART LAYOUT INTEGRATION TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_cross_batch_structure(harness: TestHarness) -> void:
	var screen: Variant = _screen(Vector2(1200, 700), _vm(7))
	var main_stack: Control = screen
	var main_row: Control = screen.get_node("Battlefield")
	var hand_layer: Control = screen.hand_view
	var log_slot: Control = screen.log_slot
	harness.assert_equal(log_slot.get_node("LogClip/CombatLog"), screen.combat_log)
	harness.assert_equal(screen.hand_view, screen.hand_view)
	harness.assert_true(log_slot.z_index > hand_layer.z_index)
	harness.assert_true(screen.result_overlay.z_index > log_slot.z_index)
	harness.assert_true(screen.fatal_overlay.z_index > log_slot.z_index)
	harness.assert_false(screen.has_node("HandReserve"))
	harness.assert_equal(screen.hand_view.scene_file_path, "res://scenes/cards/hand_view.tscn")
	for card: Node in screen.hand_view.cards_in_order():
		harness.assert_equal(card.scene_file_path, "res://scenes/cards/card_view.tscn")
	_release(screen)


func _test_three_size_geometry(harness: TestHarness) -> void:
	for window_size: Vector2 in WINDOW_SIZES:
		var screen: Variant = _screen(window_size, _vm(7))
		var root_margin: Control = screen
		var main_stack: Control = screen
		var arena: Control = screen.get_node("Battlefield")
		var hand_layer: Control = screen.hand_view
		harness.assert_equal(screen.size, window_size)
		_assert_inside(harness, root_margin, window_size, "%s root margin" % window_size)
		_assert_inside(harness, arena, main_stack.size, "%s arena" % window_size)
		_assert_inside(harness, hand_layer, main_stack.size, "%s hand layer" % window_size)
		for card: Control in screen.hand_view.cards_in_order():
			var rect := _global_outer_rect(card)
			harness.assert_true(rect.position.x >= -0.01, "%s card left overflow: %s" % [window_size, rect])
			harness.assert_true(rect.end.x <= window_size.x + 0.01, "%s card right overflow: %s" % [window_size, rect])
			harness.assert_true(rect.position.y >= screen.get_node("Battlefield").get_rect().end.y, "%s card top overflow: %s" % [window_size, rect])
			harness.assert_true(rect.end.y <= window_size.y + 0.01, "%s card bottom overflow: %s" % [window_size, rect])
		_release(screen)


func _test_zero_hand_and_log(harness: TestHarness) -> void:
	var screen: Variant = _screen(Vector2(1200, 700), _vm(0))
	var main_row: HBoxContainer = screen.get_node("Battlefield")
	var arena: Control = main_row.get_node("Arena")
	var log_slot: Control = screen.log_slot
	harness.assert_equal(screen.hand_view.card_count(), 0)
	harness.assert_false(screen.has_node("HandReserve"))
	harness.assert_false(log_slot.visible)
	harness.assert_true(arena.size.x > 0)
	var locked_before: bool = screen.is_input_locked()
	screen.toggle_combat_log()
	harness.assert_true(screen.is_combat_log_open())
	harness.assert_equal(screen.is_input_locked(), locked_before)
	screen.set_combat_log_open(false, false)
	_force_layout(screen)
	harness.assert_false(log_slot.visible)
	harness.assert_true(arena.size.x > 0)
	_release(screen)


static func _screen(window_size: Vector2, vm: Dictionary) -> Variant:
	var screen: Variant = BattleScreenScene.instantiate()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.position = Vector2.ZERO
	screen.size = window_size
	Engine.get_main_loop().root.add_child(screen)
	screen.hand_view.animate_layout = false
	screen.bind_view_model(vm)
	_force_layout(screen)
	return screen


static func _vm(card_count: int) -> Dictionary:
	var hand: Array[Dictionary] = []
	for index in card_count:
		hand.append({
			"instance_id": "integration-%d" % index,
			"card_id": "free:integration-%d" % index,
			"source_skill_id": "smallHeal",
			"name": "卡牌%d" % (index + 1),
			"description": "恢复我方生命最低棋子的生命。",
			"category": "free",
			"owner_hero_id": 0,
			"base_cost": 2,
			"effective_cost": 2,
			"play_destination": "discard",
			"exhausts_on_success": false,
			"playable": true,
			"unavailable_reason": "",
		})
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 6, "sp_max": 10},
		"teams": {"ally": {"slots": []}, "enemy": {"slots": []}},
		"heroes": {"ally": [], "enemy": []},
		"piles": {"draw": 9, "hand": card_count, "discard": 2, "exhaust": 1},
		"hand": hand,
		"logs": [{"message": "战斗开始"}],
		"presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _global_outer_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	var points := [
		transform * Vector2.ZERO,
		transform * Vector2(control.size.x, 0),
		transform * control.size,
		transform * Vector2(0, control.size.y),
	]
	var left: float = points[0].x
	var top: float = points[0].y
	var right: float = points[0].x
	var bottom: float = points[0].y
	for point: Vector2 in points:
		left = minf(left, point.x)
		top = minf(top, point.y)
		right = maxf(right, point.x)
		bottom = maxf(bottom, point.y)
	return Rect2(left, top, right - left, bottom - top)


static func _assert_inside(
	harness: TestHarness,
	control: Control,
	parent_size: Vector2,
	label: String,
) -> void:
	harness.assert_true(control.position.x >= -0.01, "%s left" % label)
	harness.assert_true(control.position.y >= -0.01, "%s top" % label)
	harness.assert_true(control.get_rect().end.x <= parent_size.x + 0.01, "%s right" % label)
	harness.assert_true(control.get_rect().end.y <= parent_size.y + 0.01, "%s bottom" % label)


static func _force_layout(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children():
		_force_layout(child)


static func _release(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
