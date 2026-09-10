extends RefCounted

const BoardScene = preload("res://scenes/battle/board_grid.tscn")

func run(harness: RefCounted) -> void:
	harness.run_test("multi-cell special uses one portrait HP bar and target across covered cells", func() -> void:
		var board: Control = BoardScene.instantiate()
		Engine.get_main_loop().root.add_child(board)
		board.size = Vector2(350, 570)
		for cells in [[1, 2], [1, 2, 3]]:
			var special := "devourer" if cells.size() == 2 else "echo"
			var vm := {"id": 101, "slot": 1, "side": "enemy", "special_id": special,
				"class_id": "default", "class_name": special, "occupied": true,
				"hp": 500.0, "max_hp": 600.0, "alive": true, "buffs": [],
				"occupied_slot_ids": cells}
			board.bind_team({"slots": [vm]})
			_force_layout(board)
			board._layout_large_entities()
			var entity: Control = board.slot_for_target({"unit_id": 101})
			harness.assert_not_null(entity)
			harness.assert_equal(entity.chess_art.kind, special)
			harness.assert_equal(entity.hp_bar.value, 500.0)
			for cell in cells:
				harness.assert_true(is_same(board.slot_for_target({"slot": cell}), entity))
				harness.assert_true(entity.get_global_rect().encloses(board._slots[cell - 1].get_global_rect()))
				harness.assert_equal(board._slots[cell - 1].unit_id(), null, "covered cells must not be extra targets")
			harness.assert_equal(board.slot_nodes().filter(func(node: Node) -> bool: return node.unit_id() == 101).size(), 1)
			entity.present_hp_change(500, 350, 600, 0)
			harness.assert_equal(entity.hp_bar.value, 350.0)
		board.bind_team({"slots": []})
		harness.assert_equal(board._large_slots.size(), 0)
		board.free()
	)

static func _force_layout(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_force_layout(child)
