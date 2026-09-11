extends SceneTree

const RunScene = preload("res://scenes/run.tscn")
var screen: Variant
var errors: Array[String] = []
var output := "res://tests/artifacts/journey"

func _init() -> void:
	call_deferred("_run")

func _frames(count: int = 4) -> void:
	for i in count: await process_frame

func _shot(filename: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var result := image.save_png(output.path_join(filename))
		if result != OK: errors.append("Screenshot: " + error_string(result))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1200,700)
	screen = RunScene.instantiate()
	screen.save_path = "res://.godot/test-logs/journey-visual-save.json"
	root.add_child(screen)
	await _shot("01_title.png")
	if not screen.start_new_run("journey-ui-2026-09-08"): errors.append("new_run failed")
	await _shot("02_choose_hero.png")
	var state: Dictionary = screen.session.snapshot()
	var hero_id: int = state.initial_hero_choice_ids[0]
	if not _command({"type":"choose_starting_hero","hero_id":hero_id}): errors.append("hero choice failed")
	await _shot("03_map.png")
	state = screen.session.snapshot()
	for node: Dictionary in state.map_nodes:
		if node.available and node.type == "battle":
			if not _command({"type":"choose_node","node_id":node.id}): errors.append("battle launch failed")
			break
	await _frames(20)
	if not is_instance_valid(screen.battle):
		errors.append("battle scene missing")
	else:
		screen.battle.presentation_queue.drain_for_test()
		await _shot("04_battle.png")
		var end: Variant = screen.battle.submit_end_turn()
		if end == null or not end.ok: errors.append("end turn rejected")
		screen.battle.presentation_queue.drain_for_test()
		await _shot("05_next_turn.png")
		screen._toggle_pause()
		await _shot("06_pause.png")
		screen._toggle_pause()
		var complete: Dictionary = screen.battle.drive_auto_for_test(512)
		if not complete.get("complete",false): errors.append("real first battle did not finish")
		if screen.session.snapshot().get("status") != "reward": errors.append("first battle did not yield reward")
		await _shot("07_battle_result.png")
		screen.battle.battle_screen.result_overlay.restart_button.pressed.emit()
		await _frames()
		if is_instance_valid(screen.battle): errors.append("continue failed to dispose battle")
		await _shot("08_reward.png")
		await _exercise_nodes()
	# Let every control finish freeing while its scene ownership is valid.
	screen.queue_free()
	await _frames(3)
	for message: String in errors: push_error(message)
	print("JOURNEY UI SMOKE failures=%d" % errors.size())
	quit(0 if errors.is_empty() else 1)

func _exercise_nodes() -> void:
	var captured := {}
	for step in 14:
		var state: Dictionary = screen.session.snapshot()
		match str(state.get("status","")):
			"reward":
				if state.reward_options.is_empty():
					errors.append("empty reward")
					return
				var option: Dictionary = state.reward_options[0]
				if option.type == "hero":
					await _shot("09_recruit.png")
					_command({"type":"recruit_hero","hero_id":int(option.payload_id)})
				else: _command({"type":"select_reward","option_id":option.id})
			"map":
				var chosen := {}
				for kind: String in ["forge","shop","event","battle"]:
					for node: Dictionary in state.map_nodes:
						if node.available and node.type == kind:
							chosen = node
							break
					if not chosen.is_empty(): break
				if chosen.is_empty(): return
				_command({"type":"choose_node","node_id":chosen.id})
			"fighting":
				if not is_instance_valid(screen.battle):
					errors.append("later battle scene missing")
					return
				var result: Dictionary = screen.battle.drive_auto_for_test(512)
				if not result.get("complete",false):
					errors.append("later real battle did not finish")
					return
				screen.battle.battle_screen.result_overlay.restart_button.pressed.emit()
			"shop", "forge", "event":
				if not captured.has(state.status):
					await _shot("10_%s.png" % state.status)
					captured[state.status] = true
				if state.status == "forge" and screen.session.view_model().costs.has("forge:heal"):
					_command({"type":"use_forge_heal"})
				var command: Dictionary = {"type":"skip_retained_card_event"} if state.status == "event" and screen.session.snapshot().current_event_kind == "retain_card" else {"type":"leave_node"}
				_command(command)
			"failed", "cleared": return
		await _frames(2)
	root.size = Vector2i(1600,900)
	await _shot("11_large_window.png")
	if screen.session.snapshot().hero_deployment_slots.size() < 2: errors.append("recruitment did not progress")
	if captured.size() < 2: errors.append("economic node navigation did not progress")

func _command(payload: Dictionary) -> bool:
	var ok: bool = screen.command(payload)
	if not ok: errors.append("UI command rejected: %s; %s" % [str(payload), screen._feedback])
	return ok
