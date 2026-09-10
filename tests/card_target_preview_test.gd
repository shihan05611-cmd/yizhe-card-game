extends RefCounted

const Fixture = preload("res://tests/battle_scene_test.gd")
const Screen = preload("res://scenes/battle/battle_screen.tscn")
const Controller = preload("res://app/battle_controller.gd")
const HandManager = preload("res://autoload/hand_manager.gd")

func run(harness: RefCounted) -> void:
	harness.run_test("real targeted action card produces a visible next round Buff on chosen unit", func() -> void:
		var manager := HandManager.new()
		var controller := Controller.new(manager)
		var started: Variant = controller.start({"battle_seed": "action-status", "deployed_hero_ids": [1], "free_skill_ids": ["pieceAction", "smallHeal"], "stage_id": "counter"})
		harness.assert_true(started.ok, started.message)
		if not started.ok:
			manager.free()
			return
		var hand: Variant = manager._session.component("hand_runtime")
		var catalog: Dictionary = manager._session.component("card_catalog")
		var created: Variant = hand.create_card(catalog["free:pieceAction"], "hand")
		harness.assert_true(created.ok, created.message)
		var vm: Dictionary = controller.view_model()
		var chosen: Dictionary = vm["teams"]["ally"]["slots"][2]
		var played: Variant = controller.play_card_guarded({"instance_id": created.details["instance_id"], "expected_card_id": "free:pieceAction", "expected_source_skill_id": "pieceAction", "owner_hero_id": catalog["free:pieceAction"].owner_hero_id, "target": {"side": "ally", "unit_id": chosen["id"], "slot": chosen["slot"]}})
		harness.assert_true(played.ok, played.message)
		var screen: Control = Screen.instantiate()
		Engine.get_main_loop().root.add_child(screen)
		screen.bind_view_model(controller.view_model())
		var slot: Control = screen.ally_board.slot_for_target({"unit_id": chosen["id"], "slot": chosen["slot"]})
		harness.assert_true(slot.buff_label.visible)
		harness.assert_true(slot.buff_label.text.contains("下回合额外行动×1"), slot.buff_label.text)
		harness.assert_true(slot.buff_label.tooltip_text.contains("下回合额外行动×1"))
		screen.free()
		manager.free()
	)
	harness.run_test("drag aim agrees with release target and clears on cancel", func() -> void:
		var screen: Control = Screen.instantiate()
		Engine.get_main_loop().root.add_child(screen)
		screen.hand_view.animate_layout = false
		var vm := fixture_vm()
		screen.bind_view_model(vm)
		var slot: Control = screen.enemy_board.slot_for_target({"unit_id": 101, "slot": 1})
		var pointer := slot.get_global_rect().get_center()
		var origin := pointer + Vector2(0, 300)
		var card: Control = screen.hand_view.card_for_instance("aim-test")
		harness.assert_true(card.begin_drag_at(origin))
		card.drag_to(pointer)
		harness.assert_true(screen.target_overlay.visible)
		harness.assert_true(screen.target_overlay.locked)
		harness.assert_true(screen.target_overlay.caption.contains("松手斩杀"))
		harness.assert_equal(screen.target_overlay.candidates.size(), 6)
		harness.assert_equal(screen._resolve_card_target({"instance_id": "aim-test", "release_position": pointer})["target"]["unit_id"], 101)
		harness.assert_true(card.modulate.a < 0.3, "aiming card cannot obscure the target")
		card.drag_to(Vector2(-500, -500))
		harness.assert_false(screen.target_overlay.locked)
		harness.assert_true(screen.target_overlay.caption.contains("退回"))
		card.cancel_drag(false)
		harness.assert_false(screen.target_overlay.visible)
		harness.assert_equal(card.modulate.a, 1.0)
		vm["hand"][0]["source_skill_id"] = "pieceAction"
		vm["hand"][0]["targeting"] = {"mode": "required", "side": "ally", "filter": "living"}
		screen.bind_view_model(vm)
		var ally_slot: Control = screen.ally_board.slot_for_target({"unit_id": 1, "slot": 1})
		pointer = ally_slot.get_global_rect().get_center()
		card.begin_drag_at(pointer + Vector2(0, 300))
		card.drag_to(pointer)
		harness.assert_true(screen.target_overlay.locked)
		harness.assert_false(screen.target_overlay.hostile)
		harness.assert_true(screen.target_overlay.caption.contains("预备行动"))
		harness.assert_equal(screen._resolve_card_target({"instance_id": "aim-test", "release_position": pointer})["target"]["unit_id"], 1)
		ally_slot.bind_slot({"id": 1, "slot": 1, "side": "ally", "class_id": "shield", "alive": true, "hp": 100.0, "max_hp": 100.0, "buffs": [{"id": "nextRoundAction", "stacks": 3, "turns": 2, "layer_turns": [1, 2, 2]}]})
		harness.assert_true(ally_slot.buff_label.text.contains("本回合额外行动×1"))
		harness.assert_true(ally_slot.buff_label.text.contains("下回合额外行动×2"))
		screen.free()
	)
	harness.run_test("multi cell aim highlights one whole entity and dead targets disappear", func() -> void:
		var screen: Control = Screen.instantiate()
		Engine.get_main_loop().root.add_child(screen)
		var vm := fixture_vm()
		vm["teams"]["enemy"]["slots"][0]["special_id"] = "devourer"
		vm["teams"]["enemy"]["slots"][0]["occupied_slot_ids"] = [1, 2]
		vm["teams"]["enemy"]["slots"][1]["occupied"] = false
		vm["teams"]["enemy"]["slots"][1]["alive"] = false
		screen.bind_view_model(vm)
		screen.enemy_board._layout_large_entities()
		var monster: Control = screen.enemy_board.slot_for_target({"unit_id": 101, "slot": 1})
		var point := monster.get_global_rect().get_center()
		screen._show_card_target_preview(vm["hand"][0], point+Vector2(0, 300), point, true)
		harness.assert_true(screen.target_overlay.locked)
		harness.assert_equal(screen.target_overlay.candidates.size(), 5)
		harness.assert_equal(screen.target_overlay.selected.size, monster.size)
		harness.assert_equal(screen._resolve_card_target({"instance_id": "aim-test", "release_position": point})["target"]["unit_id"], 101)
		vm["teams"]["enemy"]["slots"][0]["alive"] = false
		screen.bind_view_model(vm)
		screen._show_card_target_preview(vm["hand"][0], point+Vector2(0, 300), point, true)
		harness.assert_equal(screen.target_overlay.candidates.size(), 4)
		screen.free()
	)

static func fixture_vm() -> Dictionary:
	var vm := Fixture._vm()
	vm["hand"] = [{"instance_id": "aim-test", "card_id": "free:executeStrike", "source_skill_id": "executeStrike", "name": "斩杀", "description": "指挥攻击最高弈子攻击指定敌人", "category": "free", "owner_hero_id": null, "base_cost": 2, "effective_cost": 2, "play_destination": "discard", "exhausts_on_success": false, "playable": true, "unavailable_code": "", "unavailable_reason": "", "targeting": {"mode": "required", "side": "enemy", "filter": "lockable"}}]
	return vm
