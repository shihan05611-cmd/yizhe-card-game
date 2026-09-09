extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OUTPUT := "res://tests/artifacts/card_arrival"
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await process_frame
	DisplayServer.window_set_size(Vector2i(1200, 700))
	root.size = Vector2i(1200, 700)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var battle: Variant = MainScene.instantiate()
	battle.battle_seed = "pending-card-queue-capture"
	root.add_child(battle)
	if not battle.has_method("queue_play_card") or battle.battle_screen == null:
		push_error("arrival capture cannot load battle")
		quit(1)
		return
	battle.presentation_queue.drain_for_test()
	# Freeze only settlement advancement so the same active card remains visible
	# while this fixture records its independent presentation tween.
	battle.presentation_queue.set_process(false)
	await process_frame
	await process_frame
	var card: Variant = null
	for item: Variant in battle.battle_screen.hand_view.cards_in_order():
		if item.is_playable():
			card = item
			break
	if card == null:
		push_error("arrival fixture needs a playable card")
		quit(1)
		return
	var origin: Vector2 = card.global_position + card.size * 0.5
	var release := origin - Vector2(-80.0, 150.0)
	card.begin_drag_at(origin)
	card.drag_to(release)
	card.end_drag_at(release)
	await _shot("01_release.png")
	await create_timer(0.11).timeout
	await _shot("02_in_flight.png")
	await create_timer(0.30).timeout
	await _shot("03_arrived.png")
	print("CARD ARRIVAL CAPTURE failures=%d" % failures.size())
	battle.free()
	quit(0 if failures.is_empty() else 1)

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(filename))) != OK:
		failures.append(filename)
