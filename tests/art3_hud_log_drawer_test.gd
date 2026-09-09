extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")
const CombatLogScene: PackedScene = preload("res://scenes/battle/combat_log.tscn")


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("ART-3 HUD exposes three groups SP bar and four short pile labels", func() -> void:
		_test_hud_structure(harness)
	)
	harness.run_test("ART-3 button Tab and L share one nonblocking log entry", func() -> void:
		_test_log_entry_points(harness)
	)
	harness.run_test("ART-3 hidden log exits layout and unread badge clears on open", func() -> void:
		_test_layout_and_unread(harness)
	)
	harness.run_test("ART-3 log auto-scrolls and terminal state never forces it open", func() -> void:
		_test_scroll_and_terminal(harness)
	)
	print("ART-3 HUD AND LOG DRAWER TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_hud_structure(harness: TestHarness) -> void:
	var screen: Variant = _screen(_vm(2))
	var hud: Node = screen.battle_hud
	harness.assert_not_null(hud.get_node("Resources"))
	harness.assert_not_null(hud.get_node("Actions"))
	harness.assert_not_null(hud.get_node("RightGroup"))
	harness.assert_equal(hud.round_label.text, "回合 3")
	harness.assert_equal(hud.sp_bar.value, 6.0)
	harness.assert_equal(hud.sp_bar.max_value, 10.0)
	harness.assert_equal(hud.pile_count_draw.text, "9")
	harness.assert_equal(hud.hand_count.text, "4")
	harness.assert_equal(hud.discard_count.text, "2")
	harness.assert_equal(hud.exhaust_count.text, "1")
	for button: Button in hud.speed_buttons:
		harness.assert_true(button.custom_minimum_size.x >= 34.0)
		harness.assert_true(button.custom_minimum_size.y >= 28.0)
	harness.assert_true(hud.end_turn_button.custom_minimum_size.y >= 44.0)
	_release(screen)


func _test_log_entry_points(harness: TestHarness) -> void:
	var screen: Variant = _screen(_vm(0))
	harness.assert_true(InputMap.has_action("toggle_combat_log"))
	var keycodes: Array[int] = []
	for event: InputEvent in InputMap.action_get_events("toggle_combat_log"):
		if event is InputEventKey:
			keycodes.append(event.keycode)
	harness.assert_true(KEY_TAB in keycodes, "Tab missing: %s expected %s" % [str(keycodes), str(KEY_TAB)])
	harness.assert_true(KEY_L in keycodes, "L missing: %s expected %s" % [str(keycodes), str(KEY_L)])
	harness.assert_false(screen.is_combat_log_open())
	var locked_before: bool = screen.is_input_locked()
	screen.battle_hud.log_button.pressed.emit()
	harness.assert_true(screen.is_combat_log_open())
	harness.assert_equal(screen.log_transition_duration(), 0.18)
	harness.assert_equal(screen.is_input_locked(), locked_before)
	_send_key(screen, KEY_TAB)
	harness.assert_false(screen.is_combat_log_open())
	harness.assert_equal(screen.is_input_locked(), locked_before)
	_send_key(screen, KEY_L)
	harness.assert_true(screen.is_combat_log_open())
	harness.assert_equal(screen.is_input_locked(), locked_before)
	_release(screen)


func _test_layout_and_unread(harness: TestHarness) -> void:
	var screen: Variant = _screen(_vm(2))
	var main_row: HBoxContainer = screen.get_node("Battlefield")
	var arena: Control = main_row.get_node("Arena")
	var log_slot: Control = screen.log_slot
	_force_layout(screen)
	var arena_width := arena.size.x
	harness.assert_false(log_slot.visible)
	harness.assert_equal(arena.size.x, arena_width)
	harness.assert_equal(screen.unread_log_count(), 2)
	harness.assert_true(screen.battle_hud.log_unread_badge.visible)
	harness.assert_equal(screen.battle_hud.log_unread_badge.text, "2")
	screen.set_combat_log_open(true, false)
	_force_layout(screen)
	harness.assert_true(log_slot.visible)
	harness.assert_equal(log_slot.size.x, 308.0)
	harness.assert_equal(arena.size.x, arena_width)
	harness.assert_equal(screen.unread_log_count(), 0)
	harness.assert_false(screen.battle_hud.log_unread_badge.visible)
	var updated := _vm(105)
	screen.bind_view_model(updated)
	harness.assert_equal(screen.unread_log_count(), 0, "open logs must not accumulate unread entries")
	screen.set_combat_log_open(false, false)
	_force_layout(screen)
	harness.assert_false(log_slot.visible)
	harness.assert_equal(arena.size.x, arena_width)
	var newer := _vm(107)
	screen.bind_view_model(newer)
	harness.assert_equal(screen.unread_log_count(), 2)
	harness.assert_equal(screen.battle_hud.log_unread_badge.text, "2")
	var reset_then_many := _vm(0)
	screen.bind_view_model(reset_then_many)
	screen.bind_view_model(_vm(105))
	harness.assert_equal(screen.unread_log_count(), 100)
	harness.assert_equal(screen.battle_hud.log_unread_badge.text, "99+")
	_release(screen)


func _test_scroll_and_terminal(harness: TestHarness) -> void:
	var combat_log: Variant = CombatLogScene.instantiate()
	Engine.get_main_loop().root.add_child(combat_log)
	combat_log.size = Vector2(300, 390)
	combat_log.bind_logs(_logs(40))
	_force_layout(combat_log)
	combat_log.scroll_to_bottom()
	harness.assert_true(combat_log.scroll.scroll_vertical > 0)
	harness.assert_equal(combat_log.entry_nodes()[0].get_node("MessageLabel").text, "日志 0")
	harness.assert_equal(combat_log.entry_nodes()[39].get_node("MessageLabel").text, "日志 39")
	_release(combat_log)

	var screen: Variant = _screen(_vm(1))
	screen.set_combat_log_open(false, false)
	var terminal := _vm(2)
	terminal["battle"]["game_over"] = true
	terminal["battle"]["result"] = "win"
	screen.bind_view_model(terminal)
	harness.assert_false(screen.is_combat_log_open())
	harness.assert_false(screen.log_slot.visible)
	var fatal := _vm(3)
	fatal["fatal"] = {"code": "fatal", "message": "终止", "details": {}}
	screen.bind_view_model(fatal)
	harness.assert_false(screen.is_combat_log_open())
	harness.assert_false(screen.log_slot.visible)
	_release(screen)


static func _screen(vm: Dictionary) -> Variant:
	var screen: Variant = BattleScreenScene.instantiate()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.position = Vector2.ZERO
	screen.size = Vector2(1200, 700)
	Engine.get_main_loop().root.add_child(screen)
	screen.bind_view_model(vm)
	_force_layout(screen)
	return screen


static func _send_key(screen: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	screen._unhandled_input(event)


static func _vm(log_count: int) -> Dictionary:
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 3, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 6.0, "sp_max": 10.0},
		"teams": {"ally": {"slots": []}, "enemy": {"slots": []}},
		"heroes": {"ally": [], "enemy": []},
		"piles": {"draw": 9, "hand": 4, "discard": 2, "exhaust": 1},
		"hand": [],
		"logs": _logs(log_count),
		"presentation": {"speed": 2.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _logs(count: int) -> Array:
	var result: Array = []
	for index in count:
		result.append({"message": "日志 %d" % index, "class": "normal"})
	return result


static func _force_layout(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children():
		_force_layout(child)


static func _release(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
