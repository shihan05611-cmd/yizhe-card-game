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
	harness.run_test("ending a turn immediately clears every displayed card until next-turn bind", func() -> void:
		_test_end_turn_clears_displayed_hand(harness)
	)
	harness.run_test("a rejected end turn retains the displayed hand", func() -> void:
		_test_rejected_end_turn_retains_displayed_hand(harness)
	)
	harness.run_test("waiting queue accepts a rapid second drag, blocks end turn, and returns stale cards", func() -> void:
		_test_waiting_queue(harness)
	)
	harness.run_test("burn setup refreshes a visible detonation card before the first presentation finishes", func() -> void:
		_test_burn_followup_availability(harness)
	)
	harness.run_test("return-on-play card flies from settlement back to its original hand instance", func() -> void:
		_test_return_to_hand_presentation(harness)
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
	root.battle_screen.hand_view.play_card_requested.emit(_guard(card))
	harness.assert_true(root.presentation_queue.is_busy())
	harness.assert_true(root.battle_screen.is_input_locked())
	root.battle_screen.hand_view.play_card_requested.emit(_guard(card))
	harness.assert_equal(root.logic_submission_count(), 1)
	harness.assert_equal(root.battle_screen.hand_view.card_count(), root.controller.view_model()["hand"].size(), "the releasing card leaves the hand fan for its queue representation")
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


func _test_end_turn_clears_displayed_hand(harness: TestHarness) -> void:
	var root: Variant = _root("m4-end-turn-discard-display")
	root.presentation_queue.drain_for_test()
	var old_hand: Array = root.controller.view_model()["hand"]
	harness.assert_true(old_hand.size() > 0, "production battle starts with cards to discard")
	if old_hand.is_empty():
		root.free()
		return
	var ended: Variant = root.submit_end_turn()
	harness.assert_not_null(ended)
	harness.assert_true(ended.ok, ended.message)
	harness.assert_true(root.presentation_queue.is_busy(), "round resolution stays presented after discard")
	harness.assert_equal(root.battle_screen.hand_view.card_count(), 0, "all prior-turn cards leave the hand immediately")
	harness.assert_equal(root.controller.view_model()["piles"]["hand"], root.controller.view_model()["hand"].size())
	root.presentation_queue.drain_for_test()
	harness.assert_equal(
		root.battle_screen.hand_view.card_count(),
		root.controller.view_model()["hand"].size(),
		"only the authoritative next-turn hand appears after resolution presentation",
	)
	root.free()


func _test_rejected_end_turn_retains_displayed_hand(harness: TestHarness) -> void:
	var root: Variant = _root("m4-end-turn-rejection-display")
	root.presentation_queue.drain_for_test()
	var displayed_before: int = int(root.battle_screen.hand_view.card_count())
	harness.assert_true(displayed_before > 0, "production battle starts with a visible hand")
	if displayed_before == 0:
		root.free()
		return
	root.controller._runtime.component("state")["phase"] = "round_resolution"
	var rejected: Variant = root.submit_end_turn()
	harness.assert_not_null(rejected)
	harness.assert_false(rejected.ok)
	harness.assert_equal(root.battle_screen.hand_view.card_count(), displayed_before)
	harness.assert_false(root.presentation_queue.is_busy())
	root.free()


func _test_waiting_queue(harness: TestHarness) -> void:
	var root: Variant = _root("m4-waiting-queue")
	root.presentation_queue.drain_for_test()
	var card := _first_playable(root.controller.view_model())
	harness.assert_false(card.is_empty())
	if card.is_empty():
		root.free()
		return
	var card_view: Variant = root.battle_screen.hand_view.card_for_instance(str(card.get("instance_id", "")))
	harness.assert_not_null(card_view, "the real hand card is available for drag input")
	if card_view == null:
		root.free()
		return
	_drag_play(card_view)
	_drag_play(card_view)
	harness.assert_equal(root.logic_submission_count(), 1, "only queue head submits during its animation")
	harness.assert_equal(root.battle_screen.pending_card_count(), 1, "duplicate drag does not enter a second time while its first release is active")
	harness.assert_equal(root.battle_screen.hand_view.call("_global_lock_reason"), "", "presentation busy does not disable the rest of the hand")
	harness.assert_false(root.battle_screen.battle_hud.end_turn_button.visible)
	harness.assert_equal(root.submit_end_turn(), null, "end turn cannot move behind waiting cards")
	root.presentation_queue.drain_for_test()
	harness.assert_equal(root.battle_screen.pending_card_count(), 0, "stale waiting card is returned, not retained")
	harness.assert_true(root.battle_screen.battle_hud.end_turn_button.visible)
	harness.assert_equal(_count_event(root.controller.presentation_events(), "card"), 1, "duplicate did not spend or replay a card")
	root.free()


func _test_burn_followup_availability(harness: TestHarness) -> void:
	var root: Variant = MainScene.instantiate()
	root.auto_start = false
	root.battle_seed = "m4-burn-followup"
	var skills: Array[String] = ["markBurn", "pieceBlock"]
	root.free_skill_ids = skills
	Engine.get_main_loop().root.add_child(root)
	harness.assert_true(root.start_battle())
	root.presentation_queue.drain_for_test()
	var burn := _card_by_skill(root.controller.view_model(), "markBurn")
	var detonate := _card_by_skill(root.controller.view_model(), "burn01")
	harness.assert_false(burn.is_empty())
	harness.assert_false(detonate.is_empty())
	if burn.is_empty() or detonate.is_empty():
		root.free()
		return
	harness.assert_false(bool(detonate.get("playable", true)), "焚炎 is unavailable before an enemy has burn")
	var burn_view: Variant = root.battle_screen.hand_view.card_for_instance(str(burn.get("instance_id", "")))
	_drag_play(burn_view)
	harness.assert_true(root.presentation_queue.is_busy(), "burn presentation must still be active")
	var detonate_view: Variant = root.battle_screen.hand_view.card_for_instance(str(detonate.get("instance_id", "")))
	harness.assert_not_null(detonate_view)
	harness.assert_true(bool(_card_by_skill(root.controller.view_model(), "burn01").get("playable", false)), "controller enables 焚炎 immediately")
	harness.assert_true(detonate_view.is_playable(), "current controller availability enables the visible burn follow-up")
	_drag_play(detonate_view)
	harness.assert_equal(root.battle_screen.pending_card_count(), 2, "enabled follow-up enters waiting during burn presentation")
	root.free()


func _test_return_to_hand_presentation(harness: TestHarness) -> void:
	var screen: Variant = BattleScreenScene.instantiate()
	Engine.get_main_loop().root.add_child(screen)
	var vm := _static_vm(2)
	var shadow: Dictionary = vm["hand"][0]
	shadow["card_id"] = "exclusive:shadow"
	shadow["source_skill_id"] = "shadow"
	shadow["category"] = "exclusive"
	shadow["play_destination"] = "hand"
	screen.bind_view_model(vm)
	var instance_id := str(shadow["instance_id"])
	screen.set_pending_cards([{
		"instance_id": instance_id, "name": shadow["name"], "state": "releasing", "card": shadow,
	}])
	screen.set_pending_card_instances([instance_id])
	harness.assert_equal(screen.hand_view.card_count(), 1)
	screen.present_event({
		"kind": "card", "payload": {"card_instance_id": instance_id, "destination": "hand"},
	}, 0.2)
	var returned: Variant = screen.hand_view.card_for_instance(instance_id)
	harness.assert_not_null(returned)
	harness.assert_equal(screen.hand_view.card_count(), 2)
	harness.assert_false(returned.visible, "hand target remains hidden until the settlement flight arrives")
	harness.assert_true(absf(returned.rotation) > 0.001, "test uses a real fanned hand rotation")
	harness.assert_not_null(screen._pending_card_queue.flight_card(instance_id))
	screen._pending_card_queue._advance_return(instance_id, returned, 0.5)
	var flight: Variant = screen._pending_card_queue.flight_card(instance_id)
	harness.assert_true(flight.global_position.distance_to(returned.global_position) > 1.0)
	screen._pending_card_queue._advance_return(instance_id, returned, 1.0)
	harness.assert_true(flight.global_position.distance_to(returned.global_position) < 0.01)
	harness.assert_true(flight.scale.distance_to(returned.scale) < 0.01)
	harness.assert_true(is_equal_approx(flight.rotation, returned.rotation))
	screen.cancel_pending_return_flights()
	screen.set_pending_cards([])
	harness.assert_equal(screen._pending_card_queue.flight_count(), 0)
	harness.assert_false(screen._pending_card_queue.visible, "terminal cleanup removes an unfinished return flight")
	screen.free()


static func _drag_play(card_view: Control) -> void:
	var origin := card_view.global_position + card_view.size * 0.5
	card_view.begin_drag_at(origin)
	card_view.end_drag_at(origin - Vector2(0.0, 100.0))


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


static func _card_by_skill(vm: Dictionary, skill_id: String) -> Dictionary:
	for card: Dictionary in vm.get("hand", []):
		if str(card.get("source_skill_id", "")) == skill_id:
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
