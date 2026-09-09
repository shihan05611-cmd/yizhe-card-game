extends RefCounted

const PieceScene := preload("res://scenes/battle/piece_slot.tscn")

func run(harness: RefCounted) -> void:
	harness.run_test("approved four classes use side-specific art without mutating battle data", func() -> void:
		var piece: Variant = PieceScene.instantiate()
		Engine.get_main_loop().root.add_child(piece)
		var kinds := {"shield": ["甲卒", "guard"], "crossbow": ["机弩", "crossbow"], "assassin": ["刺客", "assassin"], "banner": ["旗兵", "standard"]}
		for kind: String in kinds:
			for side: String in ["ally", "enemy"]:
				var vm := {"id": 1, "slot": 1, "class_id": kind, "class_name": "死士" if kind == "assassin" else kinds[kind][0], "side": side, "alive": true, "hp": 80, "max_hp": 100, "buffs": []}
				var before := vm.duplicate(true)
				piece.bind_slot(vm)
				harness.assert_equal(vm, before)
				harness.assert_equal(piece.class_label.text, kinds[kind][0])
				# The approved HTML now renders natively; verify identity and clock,
				# replacing the obsolete SVG-atlas frame assertions.
				harness.assert_equal(piece.chess_art.kind, kind)
				harness.assert_equal(piece.chess_art.enemy, side == "enemy")
				harness.assert_equal(piece.chess_art.pose, 0.0)
				piece.present_action(1.0)
				piece._action_tween.custom_step(0.35)
				# The approved presentation reaches its peak at 38% of the action,
				# so 0.35s is intentionally still in the rising segment (0.35/0.38).
				# Verify a pronounced action pose without freezing that timing ratio.
				harness.assert_true(piece.chess_art.pose > 0.9 and piece.chess_art.pose < 1.0)
				if kind == "crossbow":
					piece._shot_tween.custom_step(0.35)
					var progress: float = piece.chess_art.shot_progress
					piece._shot_tween.custom_step(0.35)
					harness.assert_true(piece.chess_art.shot_progress > progress, "projectile moves forward while the body returns")
				piece.bind_slot(vm)
				harness.assert_equal(piece.chess_art.pose, 0.0)
				harness.assert_equal(piece.chess_art.shot_progress, -1.0)
		piece.set_empty(1)
		harness.assert_false(piece.chess_art.visible)
		piece.free()
	)
