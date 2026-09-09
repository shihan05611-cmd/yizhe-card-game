extends SceneTree

## Non-headless visual evidence. Run with the desktop console executable, not
## --headless; PNGs intentionally capture the formal battle viewport over time.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const OUTPUT := "res://tests/artifacts/inkjade_motion"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var one := await _play_round(1.0, true)
	var four := await _play_round(4.0, false)
	assert(JSON.stringify(one) == JSON.stringify(four), "1x and 4x must settle to the same authority snapshot")
	print("INKJADE MOTION evidence: 1x=%s 4x=%s" % [JSON.stringify(one), JSON.stringify(four)])
	quit()


func _play_round(speed: float, capture: bool) -> Dictionary:
	var battle: Variant = MainScene.instantiate()
	battle.auto_start = false
	battle.battle_seed = "inkjade-motion"
	root.add_child(battle)
	battle.start_battle()
	await process_frame
	if capture:
		await _capture("01_controller_start.png")
		var screen: Variant = battle.battle_screen
		var burn3 := _burn_event(3)
		screen.present_event(burn3, 0.18)
		await create_timer(0.28).timeout
		var aura: Control = screen.enemy_board.slot_for_target(burn3["visual_target"]).get_node("Content/ChessArt/BurnAura")
		assert(aura.size.x > 0.0 and aura.size.y > 0.0 and aura.get("_stacks") == 3, "burn 3 aura must be sized and active")
		print("BURN AURA 3 size=%s stacks=%s" % [aura.size, aura.get("_stacks")])
		await _capture("02_burn_3.png")
		await _capture_close("02_burn_3_close.png", aura)
		screen.present_event(_burn_event(8), 0.18)
		await create_timer(0.28).timeout
		assert(aura.size.x > 0.0 and aura.size.y > 0.0 and aura.get("_stacks") == 8, "burn 8 aura must be sized and active")
		print("BURN AURA 8 size=%s stacks=%s" % [aura.size, aura.get("_stacks")])
		await _capture("03_burn_8.png")
		await _capture_close("03_burn_8_close.png", aura)
		var phase_before_pause := float(aura.get("_phase"))
		screen.set_effect_speed(0.0)
		await create_timer(0.15).timeout
		assert(is_equal_approx(float(aura.get("_phase")), phase_before_pause), "paused burn phase advanced")
		await _capture("04_burn_paused.png")
		screen.set_effect_speed(speed)
		await create_timer(0.10).timeout
		assert(not is_equal_approx(float(aura.get("_phase")), phase_before_pause), "resumed burn phase did not advance")
		screen.present_event(_burn_event(-1), 0.18)
		await create_timer(0.28).timeout
		await _capture("05_burn_cleared.png")
		var action := {
			"kind": "damage", "event_id": "damage_applied", "source": {
				"type": "basic_attack", "id": "normalAttack", "side": "ally", "actor_id": 1,
				"action_phase": "piece_action", "presentation_action_id": "evidence-action",
			}, "visual_target": {"kind": "unit", "side": "enemy", "unit_id": 101, "slot": 1},
			"payload": {"amount": 10.0, "old_hp": 100.0, "new_hp": 90.0, "target": {"max_hp": 100.0}},
		}
		screen.present_event(action, 0.44 / speed)
		await create_timer(0.17 / speed).timeout
		await _capture("06_attack_windup.png")
		await create_timer(0.30 / speed).timeout
		await _capture("07_attack_recovery.png")
	battle.set_presentation_speed(speed)
	battle.submit_end_turn()
	while battle.presentation_queue.is_busy():
		await process_frame
	var result: Dictionary = battle.controller.settlement_snapshot()
	battle.free()
	return result


func _capture(name: String) -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(name)))


func _capture_close(name: String, control: Control) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var rect := Rect2i(control.get_global_rect().grow(34.0))
	rect.position = rect.position.max(Vector2i.ZERO)
	rect.size.x = mini(rect.size.x, image.get_width() - rect.position.x)
	rect.size.y = mini(rect.size.y, image.get_height() - rect.position.y)
	image.get_region(rect).save_png(ProjectSettings.globalize_path(OUTPUT.path_join(name)))


static func _burn_event(stacks: int) -> Dictionary:
	return {
		"kind": "buff", "event_id": "buff_cleared" if stacks < 0 else "buff_applied",
		"source": {"action_phase": "system"},
		"visual_target": {"kind": "unit", "side": "enemy", "unit_id": 101, "slot": 1},
		"payload": {"buff_id": "burn", "state": null if stacks < 0 else {"stacks": stacks}},
	}
