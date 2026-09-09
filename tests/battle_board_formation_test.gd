extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const BattleScreenScene = preload("res://scenes/battle/battle_screen.tscn")


func run(harness: TestHarness) -> void:
	harness.run_test("battle boards mirror visual front rows without changing slot targets", func() -> void:
		var screen: Control = BattleScreenScene.instantiate()
		screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
		screen.size = Vector2(1200, 700)
		Engine.get_main_loop().root.add_child(screen)
		screen.bind_view_model(_vm())
		_force_layout(screen)
		var ally: Node = screen.ally_board
		var enemy: Node = screen.enemy_board
		harness.assert_equal(ally.visual_slot_order(), [4, 1, 5, 2, 6, 3])
		harness.assert_equal(enemy.visual_slot_order(), [1, 4, 2, 5, 3, 6])
		_assert_front_rows(harness, ally, true)
		_assert_front_rows(harness, enemy, false)
		for slot in range(1, 7):
			var ally_target: Control = ally.slot_for_target({"slot": slot, "unit_id": slot})
			var enemy_target: Control = enemy.slot_for_target({"slot": slot, "unit_id": 100 + slot})
			harness.assert_equal(ally_target.anchor_slot(), slot)
			harness.assert_equal(enemy_target.anchor_slot(), slot)
			var ally_anchor: Dictionary = screen.resolve_visual_anchor({"kind": "unit", "side": "ally", "slot": slot, "unit_id": slot})
			var enemy_anchor: Dictionary = screen.resolve_visual_anchor({"kind": "unit", "side": "enemy", "slot": slot, "unit_id": 100 + slot})
			harness.assert_equal(ally_anchor["position"], ally_target.get_global_rect().get_center() - screen.get_global_rect().position)
			harness.assert_equal(enemy_anchor["position"], enemy_target.get_global_rect().get_center() - screen.get_global_rect().position)
		screen.get_parent().remove_child(screen)
		screen.free()
	)


static func _assert_front_rows(harness: TestHarness, board: Node, front_on_right: bool) -> void:
	for slot in range(1, 4):
		var front: Control = board.slot_for_target({"slot": slot})
		var back: Control = board.slot_for_target({"slot": slot + 3})
		harness.assert_true(is_equal_approx(front.global_position.y, back.global_position.y))
		if front_on_right:
			harness.assert_true(front.global_position.x > back.global_position.x)
		else:
			harness.assert_true(front.global_position.x < back.global_position.x)


static func _vm() -> Dictionary:
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 0, "sp_max": 10},
		"teams": {"ally": {"slots": _slots("ally", 0)}, "enemy": {"slots": _slots("enemy", 100)}},
		"heroes": {"ally": [], "enemy": []}, "piles": {"draw": 0, "hand": 0, "discard": 0, "exhaust": 0},
		"hand": [], "logs": [], "presentation": {"speed": 1.0, "auto_battle": false}, "fatal": null,
	}


static func _slots(side: String, offset: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot in range(1, 7):
		slots.append({"id": offset + slot, "slot": slot, "side": side, "class_id": "shield", "hp": 100, "max_hp": 100, "alive": true, "buffs": []})
	return slots


static func _force_layout(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children():
		_force_layout(child)
