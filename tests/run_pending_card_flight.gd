extends SceneTree

const QueueScript = preload("res://ui/cards/pending_card_queue.gd")
const CardViewScene = preload("res://scenes/cards/card_view.tscn")
const MainScene = preload("res://scenes/main.tscn")
var failures := 0
var assertions := 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	Engine.max_fps = 60
	await _test_queue()
	await _test_real_drags()
	print("PENDING CARD FLIGHT TEST: assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_queue() -> void:
	var queue: Control = QueueScript.new()
	root.add_child(queue)
	queue.set_queue_anchor(Rect2(900, 450, 122, 230))
	var first := _entry("first", "灼痕标记")
	var second := _entry("second", "焚炎")
	queue.set_entries([first, second])
	await process_frame
	await process_frame
	var release := {"position": Vector2(180, 560), "rotation": -0.12, "scale": Vector2(0.82, 0.82)}
	queue.animate_arrival("first", first["card"], release, 0.2)
	queue.process_mode = Node.PROCESS_MODE_DISABLED
	var flying: Variant = queue.flight_card("first")
	check(is_instance_valid(flying), "first flight missing")
	if not is_instance_valid(flying):
		queue.free()
		return
	check(flying.global_position.distance_to(release["position"]) < 0.01, "rotated/scaled release origin must match exactly")
	check(not queue.get("_static_items")["first"].visible, "static lead hides during flight")
	queue._advance_arrival("first", 0.5)
	check(flying.global_position.distance_to(release["position"]) > 10.0, "midpoint must leave release origin")
	queue.set_entries([first, second])
	check(queue.flight_card("first") == flying, "refresh must preserve the same in-flight card")
	check(not queue.get("_static_items")["first"].visible, "refresh must not reveal duplicate preview")
	await process_frame
	queue._advance_arrival("first", 1.0)
	var expected: Rect2 = queue.get("_static_items")["first"].get_global_rect()
	var actual: Rect2 = flying.get_global_rect()
	check(actual.position.distance_to(expected.position) < 0.01, "flight endpoint must match preview position")
	check(actual.size.distance_to(expected.size) < 0.01, "flight endpoint must match preview scale")
	var paused_position: Vector2 = flying.global_position
	await create_timer(0.1).timeout
	check(flying.global_position == paused_position, "disabled parent freezes the flight")
	queue.process_mode = Node.PROCESS_MODE_INHERIT
	await create_timer(0.4).timeout
	check(queue.flight_count() == 0, "finished flight must be removed")
	check(queue.get("_static_items")["first"].visible, "current refreshed preview must appear on arrival")
	queue.animate_arrival("second", second["card"], release, 0.2)
	check(queue.flight_count() == 1, "waiting card begins moving immediately")
	queue.set_entries([first])
	check(queue.flight_count() == 0, "cancelling waiting entry clears its flight")
	var return_target: Control = CardViewScene.instantiate()
	return_target.position = Vector2(420, 520)
	root.add_child(return_target)
	return_target.bind_card(first["card"])
	return_target.visible = false
	await process_frame
	queue.animate_return("first", return_target, 0.2)
	var return_flight: Variant = queue.flight_card("first")
	check(is_instance_valid(return_flight), "returning card needs one flight instance")
	check(not return_target.visible, "hand target stays hidden before the return arrival")
	queue.set_entries([])
	check(queue.visible, "queue stays visible while a return flight survives settlement cleanup")
	queue.process_mode = Node.PROCESS_MODE_DISABLED
	var return_paused_position: Vector2 = return_flight.global_position
	await create_timer(0.1).timeout
	check(return_flight.global_position == return_paused_position, "paused queue freezes return flight")
	queue.process_mode = Node.PROCESS_MODE_INHERIT
	await create_timer(0.3).timeout
	check(queue.flight_count() == 0, "return flight cleans itself after settlement")
	check(return_target.visible, "original hand target appears after return arrival")
	check(not queue.visible, "empty queue hides after return cleanup")
	return_target.free()
	queue.free()

func _test_real_drags() -> void:
	var battle: Variant = MainScene.instantiate()
	battle.battle_seed = "pending-card-queue-capture"
	root.add_child(battle)
	check(battle.has_method("queue_play_card"), "real battle must compile")
	if not battle.has_method("queue_play_card"):
		battle.free()
		return
	battle.presentation_queue.drain_for_test()
	battle.presentation_queue.set_process(false)
	for index in 8: await process_frame
	var ids: Array[String] = []
	var queue: Variant = battle.battle_screen._pending_card_queue
	for index in 2:
		var card: Variant = null
		for candidate: Variant in battle.battle_screen.hand_view.cards_in_order():
			if candidate.is_playable():
				card = candidate
				break
		check(card != null, "real fixture needs two playable cards")
		if card == null: break
		var id: String = card.instance_id()
		ids.append(id)
		var origin: Vector2 = card.global_position + card.size * 0.5
		check(card.begin_drag_at(origin), "drag begins through actual CardView")
		card.drag_to(origin - Vector2(0, 130))
		var released: Vector2 = card.global_position
		card.end_drag_at(origin - Vector2(0, 130))
		var flight: Variant = queue.flight_card(id)
		check(is_instance_valid(flight), "both active and waiting drags start a flight")
		if is_instance_valid(flight):
			check(flight.global_position.distance_to(released) < 0.01, "real drag preserves released pose")
	check(queue.flight_count() == 2, "second queued card must move before it can resolve")
	check(battle.logic_submission_count() == 1, "waiting flight must not submit the second card")
	if ids.size() == 2:
		battle._cancel_pending_card(ids[1])
		check(queue.flight_count() == 1, "real waiting cancellation removes only its flight")
	battle.free()

static func _entry(id: String, name: String) -> Dictionary:
	return {"instance_id": id, "name": name, "state": "waiting", "card": {"instance_id": id, "name": name, "playable": true}}
