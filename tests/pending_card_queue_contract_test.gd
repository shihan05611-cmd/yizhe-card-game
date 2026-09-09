extends RefCounted

## Contract coverage for the queue in BattleSceneCoordinator.  These paths use
## the production Controller and real presentation queue rather than a visual
## queue fixture, so a waiting card cannot accidentally bypass card authority.

const TestHarness = preload("res://tests/support/test_harness.gd")
const MainScene: PackedScene = preload("res://scenes/main.tscn")


func run(harness: TestHarness) -> void:
	harness.run_test("pending queue submits a distinct second card only after the first presentation completes", func() -> void:
		_test_distinct_second_waits(harness)
	)
	harness.run_test("pending queue cancellation preserves waiting card SP and hand membership", func() -> void:
		_test_cancel_waiting_card(harness)
	)
	harness.run_test("invalid guarded waiting card returns without spending or leaving a queue entry", func() -> void:
		_test_invalid_waiting_card(harness)
	)
	harness.run_test("pending pump does not submit while the Run root is process-disabled", func() -> void:
		_test_run_pause_does_not_submit(harness)
	)
	harness.run_test("terminal state clears waiting entries and never submits the next card", func() -> void:
		_test_terminal_clears_waiting(harness)
	)
	harness.run_test("duplicate instance cannot be queued or submitted twice", func() -> void:
		_test_duplicate_instance(harness)
	)


func _test_distinct_second_waits(harness: TestHarness) -> void:
	var root: Variant = _root("pending-distinct")
	root.presentation_queue.drain_for_test()
	var cards: Array[Dictionary] = _two_playable(root.controller.view_model())
	harness.assert_equal(cards.size(), 2)
	if cards.size() != 2:
		root.free()
		return
	harness.assert_true(root.queue_play_card(_guard(cards[0])))
	harness.assert_true(root.queue_play_card(_guard(cards[1])))
	harness.assert_equal(root.logic_submission_count(), 1)
	harness.assert_equal(root.battle_screen.pending_card_count(), 2)
	harness.assert_true(_hand_has(root.controller.view_model(), cards[1]["instance_id"]))
	root.presentation_queue.drain_for_test()
	harness.assert_equal(root.logic_submission_count(), 2)
	harness.assert_equal(root.battle_screen.pending_card_count(), 0)
	harness.assert_equal(_count_events(root.controller.presentation_events(), "card"), 2)
	root.free()


func _test_cancel_waiting_card(harness: TestHarness) -> void:
	var root: Variant = _root("pending-cancel")
	root.presentation_queue.drain_for_test()
	var cards: Array[Dictionary] = _two_playable(root.controller.view_model())
	harness.assert_equal(cards.size(), 2)
	if cards.size() != 2:
		root.free()
		return
	harness.assert_true(root.queue_play_card(_guard(cards[0])))
	var sp_after_first: float = float(root.controller.view_model()["resources"]["sp"])
	harness.assert_true(root.queue_play_card(_guard(cards[1])))
	harness.assert_equal(root.battle_screen.pending_card_count(), 2)
	root.battle_screen.pending_card_cancel_requested.emit(str(cards[1]["instance_id"]))
	harness.assert_equal(root.battle_screen.pending_card_count(), 1)
	harness.assert_equal(float(root.controller.view_model()["resources"]["sp"]), sp_after_first)
	harness.assert_true(_hand_has(root.controller.view_model(), cards[1]["instance_id"]))
	root.presentation_queue.drain_for_test()
	harness.assert_equal(root.logic_submission_count(), 1)
	harness.assert_equal(_count_events(root.controller.presentation_events(), "card"), 1)
	root.free()


func _test_invalid_waiting_card(harness: TestHarness) -> void:
	var root: Variant = _root("pending-invalid")
	root.presentation_queue.drain_for_test()
	var cards: Array[Dictionary] = _two_playable(root.controller.view_model())
	harness.assert_equal(cards.size(), 2)
	if cards.size() != 2:
		root.free()
		return
	harness.assert_true(root.queue_play_card(_guard(cards[0])))
	var sp_after_first: float = float(root.controller.view_model()["resources"]["sp"])
	var stale := _guard(cards[1])
	stale["expected_card_id"] = "expired-card"
	harness.assert_true(root.queue_play_card(stale))
	root.presentation_queue.drain_for_test()
	harness.assert_equal(root.logic_submission_count(), 2, "the stale head reaches authority once")
	harness.assert_equal(float(root.controller.view_model()["resources"]["sp"]), sp_after_first)
	harness.assert_true(_hand_has(root.controller.view_model(), cards[1]["instance_id"]))
	harness.assert_equal(root.battle_screen.pending_card_count(), 0)
	harness.assert_equal(_count_events(root.controller.presentation_events(), "card"), 1)
	root.free()


func _test_run_pause_does_not_submit(harness: TestHarness) -> void:
	var root: Variant = _root("pending-run-pause")
	root.presentation_queue.drain_for_test()
	var cards: Array[Dictionary] = _two_playable(root.controller.view_model())
	harness.assert_equal(cards.size(), 2)
	if cards.size() != 2:
		root.free()
		return
	root.process_mode = Node.PROCESS_MODE_DISABLED
	harness.assert_false(root.can_process())
	harness.assert_equal(root.queue_play_card(_guard(cards[0])), null)
	root.call("_pump_pending_cards")
	harness.assert_equal(root.logic_submission_count(), 0)
	harness.assert_equal(root.battle_screen.pending_card_count(), 0)
	root.process_mode = Node.PROCESS_MODE_INHERIT
	harness.assert_true(root.can_process())
	harness.assert_true(root.queue_play_card(_guard(cards[0])))
	harness.assert_equal(root.logic_submission_count(), 1)
	root.presentation_queue.drain_for_test()
	root.free()


func _test_terminal_clears_waiting(harness: TestHarness) -> void:
	var root: Variant = _root("pending-terminal")
	root.presentation_queue.drain_for_test()
	var cards: Array[Dictionary] = _two_playable(root.controller.view_model())
	harness.assert_equal(cards.size(), 2)
	if cards.size() != 2:
		root.free()
		return
	harness.assert_true(root.queue_play_card(_guard(cards[0])))
	harness.assert_true(root.queue_play_card(_guard(cards[1])))
	var state: Dictionary = root.controller._runtime.component("state")
	state["game_over"] = true
	state["battle_result"] = "win"
	root.presentation_queue.drain_for_test()
	harness.assert_equal(root.logic_submission_count(), 1)
	harness.assert_equal(root.battle_screen.pending_card_count(), 0)
	harness.assert_equal(_count_events(root.controller.presentation_events(), "card"), 1)
	root.free()


func _test_duplicate_instance(harness: TestHarness) -> void:
	var root: Variant = _root("pending-duplicate")
	root.presentation_queue.drain_for_test()
	var cards: Array[Dictionary] = _two_playable(root.controller.view_model())
	harness.assert_equal(cards.size(), 2)
	if cards.size() != 2:
		root.free()
		return
	var card: Dictionary = cards[0]
	harness.assert_true(root.queue_play_card(_guard(card)))
	harness.assert_equal(root.queue_play_card(_guard(card)), null)
	harness.assert_equal(root.logic_submission_count(), 1)
	harness.assert_equal(root.battle_screen.pending_card_count(), 1)
	root.presentation_queue.drain_for_test()
	harness.assert_equal(_count_events(root.controller.presentation_events(), "card"), 1)
	root.free()


static func _root(seed: String) -> Variant:
	var root: Variant = MainScene.instantiate()
	root.battle_seed = seed
	Engine.get_main_loop().root.add_child(root)
	return root


static func _two_playable(vm: Dictionary) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for card: Dictionary in vm.get("hand", []):
		if bool(card.get("playable", false)):
			cards.append(card)
			if cards.size() == 2:
				break
	return cards


static func _guard(card: Dictionary) -> Dictionary:
	return {"type": "play_card", "instance_id": card["instance_id"], "expected_card_id": card["card_id"], "expected_source_skill_id": card["source_skill_id"], "owner_hero_id": card["owner_hero_id"]}


static func _hand_has(vm: Dictionary, instance_id: String) -> bool:
	return vm.get("hand", []).any(func(card: Dictionary) -> bool: return card["instance_id"] == instance_id)


static func _count_events(events: Array, kind: String) -> int:
	return events.filter(func(event: Dictionary) -> bool: return event.get("kind") == kind).size()
