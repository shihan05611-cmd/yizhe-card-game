extends RefCounted

## Contract coverage for the queue in BattleSceneCoordinator.  These paths use
## the production Controller and real presentation queue rather than a visual
## queue fixture, so a waiting card cannot accidentally bypass card authority.

const TestHarness = preload("res://tests/support/test_harness.gd")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const CardDefinition = preload("res://data/definitions/card_definition.gd")


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
	harness.run_test("queued execute target death returns the card without spending or retargeting", func() -> void:
		_test_target_dies_while_waiting(harness, "free:executeStrike", "executeStrike", "enemy")
	)
	harness.run_test("queued pieceAction target death returns the card without spending or retargeting", func() -> void:
		_test_target_dies_while_waiting(harness, "free:pieceAction", "pieceAction", "ally")
	)
	harness.run_test("auto battle supplies a legal explicit target for pieceAction", func() -> void:
		_test_piece_action_auto_target(harness)
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
	harness.assert_equal(cards.size(), 2, "two non-targeted playable setup cards")
	if cards.size() != 2:
		root.free()
		return
	harness.assert_true(root.queue_play_card(_guard(cards[0])))
	harness.assert_true(root.queue_play_card(_guard(cards[1])))
	harness.assert_equal(root.logic_submission_count(), 1)
	harness.assert_equal(root.battle_screen.pending_card_count(), 2, "active and waiting card are both visible")
	harness.assert_true(_hand_has(root.controller.view_model(), cards[1]["instance_id"]))
	root.presentation_queue.drain_for_test()
	harness.assert_equal(root.logic_submission_count(), 2, "waiting card submits after the active presentation")
	harness.assert_equal(root.battle_screen.pending_card_count(), 0)
	harness.assert_equal(_count_events(root.controller.presentation_events(), "card"), 2, "both cards produce one presentation")
	root.free()


func _test_cancel_waiting_card(harness: TestHarness) -> void:
	var root: Variant = _root("pending-cancel")
	root.presentation_queue.drain_for_test()
	var cards: Array[Dictionary] = _two_playable(root.controller.view_model())
	harness.assert_equal(cards.size(), 2, "two non-targeted playable setup cards")
	if cards.size() != 2:
		root.free()
		return
	harness.assert_true(root.queue_play_card(_guard(cards[0])))
	var sp_after_first: float = float(root.controller.view_model()["resources"]["sp"])
	harness.assert_true(root.queue_play_card(_guard(cards[1])))
	harness.assert_equal(root.battle_screen.pending_card_count(), 2, "active and cancellable waiting card are both visible")
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


func _test_target_dies_while_waiting(
	harness: TestHarness,
	card_id: String,
	source_skill_id: String,
	target_side: String,
) -> void:
	var root: Variant = _root("pending-%s-target-dies" % source_skill_id)
	root.presentation_queue.drain_for_test()
	var cards: Array[Dictionary] = _two_playable(root.controller.view_model())
	harness.assert_true(not cards.is_empty())
	if cards.is_empty():
		root.free()
		return
	var session: Variant = root.controller._hand_manager._session
	var created: Variant = session.component("hand_runtime").create_card(
		session.component("card_catalog")[card_id],
		CardDefinition.PILE_HAND,
	)
	harness.assert_true(created.ok, created.message)
	if not created.ok:
		root.free()
		return
	var execute_id := str(created.details["instance_id"])
	var state: Dictionary = root.controller._runtime.component("state")
	var target: Dictionary = state["allies" if target_side == "ally" else "enemies"].filter(
		func(unit: Dictionary) -> bool: return unit["alive"]
	)[0]
	harness.assert_true(root.queue_play_card(_guard(cards[0])))
	var sp_after_first := float(state["sp"])
	var execute_guard := {
		"type": "play_card",
		"instance_id": execute_id,
		"expected_card_id": card_id,
		"expected_source_skill_id": source_skill_id,
		"owner_hero_id": null,
		"target": {"side": target_side, "unit_id": target["id"], "slot": target["slot"]},
	}
	harness.assert_true(root.queue_play_card(execute_guard))
	target["alive"] = false
	target["hp"] = 0.0
	root.presentation_queue.drain_for_test()
	harness.assert_equal(float(state["sp"]), sp_after_first)
	harness.assert_true(_hand_has(root.controller.view_model(), execute_id))
	harness.assert_equal(root.battle_screen.pending_card_count(), 0)
	root.free()


func _test_piece_action_auto_target(harness: TestHarness) -> void:
	var root: Variant = _root("pending-piece-action-auto-target")
	root.presentation_queue.drain_for_test()
	var session: Variant = root.controller._hand_manager._session
	var hand: Variant = session.component("hand_runtime")
	for instance_id: String in hand.pile_instance_ids(CardDefinition.PILE_HAND):
		var moved: Variant = hand.move_card_to_pile(instance_id, CardDefinition.PILE_DISCARD)
		harness.assert_true(moved.ok, moved.message)
	var created: Variant = hand.create_card(
		session.component("card_catalog")["free:pieceAction"], CardDefinition.PILE_HAND,
	)
	harness.assert_true(created.ok, created.message)
	var piece_action_id := str(created.details["instance_id"])
	var auto_enabled: Variant = root.controller.set_auto_battle(true)
	harness.assert_true(auto_enabled.ok, auto_enabled.message)
	harness.assert_true(root.call("_drive_auto_once"))
	harness.assert_equal(root.logic_submission_count(), 1)
	harness.assert_false(_hand_has(root.controller.view_model(), piece_action_id), "auto-targeted card commits instead of returning")
	root.presentation_queue.drain_for_test()
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
		if not bool(card.get("playable", false)):
			continue
		var prepared: Dictionary = card.duplicate(true)
		var targeting: Dictionary = prepared.get("targeting", {})
		if str(targeting.get("mode", "automatic")) == "required":
			var target: Variant = _first_matching_target(vm, targeting)
			if target == null:
				continue
			prepared["test_target"] = target
		cards.append(prepared)
		if cards.size() == 2:
			break
	return cards


static func _guard(card: Dictionary) -> Dictionary:
	var guard := {"type": "play_card", "instance_id": card["instance_id"], "expected_card_id": card["card_id"], "expected_source_skill_id": card["source_skill_id"], "owner_hero_id": card["owner_hero_id"]}
	if card.has("test_target"):
		guard["target"] = card["test_target"].duplicate(true)
	return guard


static func _first_matching_target(vm: Dictionary, targeting: Dictionary) -> Variant:
	var side := str(targeting.get("side", ""))
	var filter_id := str(targeting.get("filter", ""))
	for unit: Dictionary in vm.get("teams", {}).get(side, {}).get("slots", []):
		if not bool(unit.get("occupied", true)) or not bool(unit.get("alive", false)):
			continue
		if filter_id == "living_non_puppet" and bool(unit.get("is_puppet", false)):
			continue
		if filter_id == "lockable" and unit.get("buffs", []).any(
			func(buff: Dictionary) -> bool: return str(buff.get("id", "")) == "stealth"
		):
			continue
		return {"side": side, "unit_id": unit["id"], "slot": int(unit["slot"])}
	return null


static func _hand_has(vm: Dictionary, instance_id: String) -> bool:
	return vm.get("hand", []).any(func(card: Dictionary) -> bool: return card["instance_id"] == instance_id)


static func _count_events(events: Array, kind: String) -> int:
	return events.filter(func(event: Dictionary) -> bool: return event.get("kind") == kind).size()
