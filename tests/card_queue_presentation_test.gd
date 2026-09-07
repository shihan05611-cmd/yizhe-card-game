extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")
const QueueScript = preload("res://app/battle_presentation_queue.gd")


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("guarded card command is submitted once while repeated input stays locked", func() -> void:
		_test_single_submission(harness)
	)
	harness.run_test("stale HandView guards reject before card logic or presentation events", func() -> void:
		_test_guard_rejection(harness)
	)
	harness.run_test("1x and 4x keep one logic result and event sequence with four-to-one duration", func() -> void:
		_test_speed_equivalence(harness)
	)
	harness.run_test("seven hand nodes remain stable for the whole presentation queue", func() -> void:
		_test_seven_card_stability(harness)
	)
	print("M4-5 CARD QUEUE PRESENTATION TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_single_submission(harness: TestHarness) -> void:
	var root: Variant = _root("m4-queue-single")
	root.presentation_queue.drain_for_test()
	var vm: Dictionary = root.controller.view_model()
	var card := _first_playable(vm)
	harness.assert_false(card.is_empty(), "production hand needs one playable card")
	if card.is_empty():
		root.free()
		return
	var ids_before := _card_node_ids(root.battle_screen.hand_view)
	root.battle_screen.hand_view.play_card_requested.emit(_guard(card))
	harness.assert_true(root.presentation_queue.is_busy())
	harness.assert_true(root.battle_screen.is_input_locked())
	root.battle_screen.hand_view.play_card_requested.emit(_guard(card))
	harness.assert_equal(root.logic_submission_count(), 1)
	harness.assert_equal(_card_node_ids(root.battle_screen.hand_view), ids_before)
	root.presentation_queue.drain_for_test()
	harness.assert_false(root.presentation_queue.is_busy())
	harness.assert_equal(root.battle_screen.hand_view.card_count(), root.controller.view_model()["hand"].size())
	harness.assert_equal(_count_event(root.controller.presentation_events(), "card"), 1)
	harness.assert_true(root.controller.view_model()["presentation"]["pending_events"].is_empty())
	root.free()


func _test_guard_rejection(harness: TestHarness) -> void:
	var root: Variant = _root("m4-queue-guard")
	root.presentation_queue.drain_for_test()
	var card := _first_playable(root.controller.view_model())
	var before_events: Array = root.controller.presentation_events()
	var command := _guard(card)
	command["expected_card_id"] = "stale-card"
	var result: Variant = root.submit_play_card(command)
	harness.assert_not_null(result)
	harness.assert_false(result.ok)
	harness.assert_contains(result.message, "stale card_id guard")
	harness.assert_false(root.presentation_queue.is_busy())
	harness.assert_equal(root.controller.presentation_events(), before_events)
	harness.assert_equal(root.controller.view_model()["hand"].size(), root.battle_screen.hand_view.card_count())
	root.free()


func _test_speed_equivalence(harness: TestHarness) -> void:
	var one: Variant = _root("m4-speed-equivalence")
	var four: Variant = _root("m4-speed-equivalence")
	one.presentation_queue.drain_for_test()
	four.presentation_queue.drain_for_test()
	harness.assert_true(one.set_presentation_speed(1.0))
	harness.assert_true(four.set_presentation_speed(4.0))
	var card_one := _first_playable(one.controller.view_model())
	var card_four := _card_by_instance(four.controller.view_model(), card_one.get("instance_id", ""))
	harness.assert_false(card_one.is_empty())
	harness.assert_false(card_four.is_empty())
	var result_one: Variant = one.submit_play_card(_guard(card_one))
	var result_four: Variant = four.submit_play_card(_guard(card_four))
	harness.assert_true(result_one.ok, result_one.message)
	harness.assert_true(result_four.ok, result_four.message)
	var time_one: float = one.presentation_queue.drain_for_test(0.001)
	var time_four: float = four.presentation_queue.drain_for_test(0.001)
	harness.assert_equal(one.logic_submission_count(), 1)
	harness.assert_equal(four.logic_submission_count(), 1)
	harness.assert_equal(one.controller.presentation_events(), four.controller.presentation_events())
	harness.assert_equal(_logic_vm(one.controller.view_model()), _logic_vm(four.controller.view_model()))
	harness.assert_true(time_four > 0.0)
	var ratio := time_one / time_four if time_four > 0.0 else 0.0
	print("M4-5 SPEED MEASUREMENT: 1x=%.3fs 4x=%.3fs ratio=%.3f" % [time_one, time_four, ratio])
	harness.assert_true(ratio >= 3.9 and ratio <= 4.1, "expected ~4:1, got %.3f (%.3f / %.3f)" % [ratio, time_one, time_four])
	one.free()
	four.free()


func _test_seven_card_stability(harness: TestHarness) -> void:
	var screen: Variant = BattleScreenScene.instantiate()
	Engine.get_main_loop().root.add_child(screen)
	var vm := _static_vm(7)
	screen.bind_view_model(vm)
	var ids_before := _card_node_ids(screen.hand_view)
	var queue: Node = QueueScript.new()
	screen.add_child(queue)
	queue.busy_changed.connect(screen.set_queue_busy)
	queue.batch_finished.connect(func(final_vm: Dictionary, _sequence: int) -> void:
		screen.bind_view_model(final_vm)
	)
	var events := [_event(1, "batch-seven", "log", "battleLog", {"message": "hold"})]
	harness.assert_true(queue.enqueue(events, vm))
	harness.assert_true(screen.is_input_locked())
	harness.assert_equal(screen.hand_view.card_count(), 7)
	harness.assert_equal(_card_node_ids(screen.hand_view), ids_before)
	queue.drain_for_test()
	harness.assert_false(screen.is_input_locked())
	harness.assert_equal(screen.hand_view.card_count(), 7)
	harness.assert_equal(_card_node_ids(screen.hand_view), ids_before)
	screen.free()


func _root(seed: String) -> Variant:
	var root: Variant = MainScene.instantiate()
	root.battle_seed = seed
	Engine.get_main_loop().root.add_child(root)
	return root


static func _first_playable(vm: Dictionary) -> Dictionary:
	for card: Dictionary in vm.get("hand", []):
		if card.get("playable", false):
			return card
	return {}


static func _card_by_instance(vm: Dictionary, instance_id: String) -> Dictionary:
	for card: Dictionary in vm.get("hand", []):
		if card.get("instance_id") == instance_id:
			return card
	return {}


static func _guard(card: Dictionary) -> Dictionary:
	return {
		"type": "play_card",
		"instance_id": card.get("instance_id", ""),
		"expected_card_id": card.get("card_id", ""),
		"expected_source_skill_id": card.get("source_skill_id", ""),
		"owner_hero_id": card.get("owner_hero_id"),
	}


static func _card_node_ids(hand_view: Node) -> Array:
	return hand_view.cards_in_order().map(func(card: Node) -> int: return card.get_instance_id())


static func _count_event(events: Array, kind: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if event.get("kind") == kind:
			count += 1
	return count


static func _logic_vm(vm: Dictionary) -> Dictionary:
	var copy := vm.duplicate(true)
	copy.erase("presentation")
	return copy


static func _static_vm(count: int) -> Dictionary:
	var hand: Array[Dictionary] = []
	for index in count:
		hand.append({
			"instance_id": "seven-%d" % index,
			"card_id": "free:pieceBlock",
			"source_skill_id": "pieceBlock",
			"name": "棋子格挡",
			"description": "测试卡牌",
			"category": "free",
			"owner_hero_id": 0,
			"base_cost": 1,
			"effective_cost": 1,
			"play_destination": "discard",
			"exhausts_on_success": false,
			"playable": true,
			"unavailable_reason": "",
		})
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 10, "sp_max": 10},
		"teams": {"ally": {"slots": []}, "enemy": {"slots": []}},
		"heroes": {"ally": [], "enemy": []},
		"piles": {"draw": 0, "hand": count, "discard": 0, "exhaust": 0},
		"hand": hand,
		"logs": [],
		"presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _event(sequence: int, batch: String, kind: String, event_id: String, payload: Dictionary) -> Dictionary:
	return {
		"sequence": sequence,
		"batch_id": batch,
		"kind": kind,
		"event_id": event_id,
		"source": {"type": "system", "id": "test", "side": "unknown", "actor_id": 0, "action_phase": "system"},
		"visual_target": {"kind": "battle"},
		"payload": payload,
	}
