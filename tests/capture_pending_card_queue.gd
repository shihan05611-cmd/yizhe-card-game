extends SceneTree

## Visual proof for the runtime overlay: two real CardView drags leave the
## active release plus one named waiting card over the end-turn location.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const OUTPUT := "res://tests/artifacts/pending_card_queue"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _capture_at_size(Vector2i(1920, 1080), "01_1920_three_cards.png")
	await _capture_at_size(Vector2i(1200, 700), "02_1200_three_cards.png")
	quit()


func _capture_at_size(window_size: Vector2i, filename: String) -> void:
	root.content_scale_size = window_size
	await process_frame
	var battle: Variant = MainScene.instantiate()
	battle.battle_seed = "pending-card-queue-capture"
	root.add_child(battle)
	battle.presentation_queue.drain_for_test()
	for count in 3:
		var next: Variant = null
		for candidate: Variant in battle.battle_screen.hand_view.cards_in_order():
			if candidate.is_playable():
				next = candidate
				break
		assert(next != null, "capture needs three playable cards")
		_drag(next)
	assert(battle.battle_screen.pending_card_count() == 3, "active plus two waiting entries must display")
	assert(not battle.battle_screen.battle_hud.end_turn_button.visible, "queue replaces end turn")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image.get_size() != window_size:
			image.resize(window_size.x, window_size.y, Image.INTERPOLATE_LANCZOS)
		image.save_png(ProjectSettings.globalize_path(OUTPUT.path_join(filename)))
	print("PENDING CARD QUEUE capture %s: entries=%d submissions=%d" % [filename, battle.battle_screen.pending_card_count(), battle.logic_submission_count()])
	battle.free()


static func _drag(card: Control) -> void:
	var origin := card.global_position + card.size * 0.5
	assert(card.begin_drag_at(origin), "drag must begin through CardView input")
	card.end_drag_at(origin - Vector2(0.0, 100.0))
