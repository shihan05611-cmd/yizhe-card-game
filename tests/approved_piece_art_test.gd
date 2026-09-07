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
				var atlas: AtlasTexture = piece.chess_art.texture
				harness.assert_equal(atlas.atlas.resource_path, "res://ui/art/pieces/%s-%s.svg" % [kinds[kind][1], side])
				harness.assert_equal(atlas.region, Rect2(0, 0, 220, 252))
				piece.present_action(1.0)
				piece._action_tween.custom_step(0.35)
				harness.assert_equal(atlas.region.position.x, 1760.0)
				piece.bind_slot(vm)
				harness.assert_equal(atlas.region.position.x, 0.0)
		piece.set_empty(1)
		harness.assert_equal(piece.chess_art.texture, null)
		piece.free()
	)
