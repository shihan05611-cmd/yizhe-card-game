extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1200, 700))
	var screen: Control = preload("res://scenes/battle/battle_screen.tscn").instantiate()
	root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1200, 700)
	screen.hand_view.animate_layout = false
	screen.bind_view_model(preload("res://tests/card_target_preview_test.gd").fixture_vm())
	for i in 10:
		await process_frame
	var card: Control = screen.hand_view.card_for_instance("aim-test")
	card.begin_drag_at(card.get_global_rect().get_center())
	var slot: Control = screen.enemy_board.slot_for_target({"unit_id": 102, "slot": 2})
	card.drag_to(slot.get_global_rect().get_center())
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/artifacts/card_target_preview.png"))
	card.cancel_drag(false)
	var vm := preload("res://tests/card_target_preview_test.gd").fixture_vm()
	vm["hand"][0].merge({"card_id": "free:pieceAction", "source_skill_id": "pieceAction", "name": "棋子行动", "base_cost": 1, "effective_cost": 1, "targeting": {"mode": "required", "side": "ally", "filter": "living"}}, true)
	vm["teams"]["ally"]["slots"][1]["buffs"] = [{"id": "nextRoundAction", "stacks": 2, "turns": 2, "layer_turns": [2, 2]}]
	screen.bind_view_model(vm)
	for i in 3:
		await process_frame
	card.begin_drag_at(card.get_global_rect().get_center())
	slot = screen.ally_board.slot_for_target({"unit_id": 2, "slot": 2})
	card.drag_to(slot.get_global_rect().get_center())
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/artifacts/action_buff_preview.png"))
	screen.free()
	quit()
