extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const HandScene: PackedScene = preload("res://scenes/cards/hand_view.tscn")
const CardScene: PackedScene = preload("res://scenes/cards/card_view.tscn")
const HandViewScript = preload("res://ui/cards/hand_view.gd")
const CardViewScript = preload("res://ui/cards/card_view.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("card and hand are instantiated from packed scenes", func() -> void:
		_test_packed_scene_instantiation(harness)
	)
	harness.run_test("hand lays out one three and seven cards within 1200 by 300", func() -> void:
		_test_layout_boundaries(harness)
	)
	harness.run_test("hover raises and restores the authoritative layout pose", func() -> void:
		_test_hover(harness)
	)
	harness.run_test("drag cancels below threshold and emits guarded command above threshold", func() -> void:
		_test_drag_cancel_and_success(harness)
	)
	harness.run_test("queue phase fatal and authoritative unavailable states block commands", func() -> void:
		_test_interaction_locks(harness)
	)
	harness.run_test("same card identity keeps distinct instance nodes", func() -> void:
		_test_duplicate_card_instances(harness)
	)
	print("M4-3 HAND UI TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_packed_scene_instantiation(harness: TestHarness) -> void:
	var standalone: Node = CardScene.instantiate()
	harness.assert_equal(standalone.get_script(), CardViewScript)
	harness.assert_equal(standalone.scene_file_path, "res://scenes/cards/card_view.tscn")
	standalone.free()
	var hand: Variant = _hand()
	hand.apply_view_model(_vm(1))
	var card: Variant = hand.cards_in_order()[0]
	harness.assert_equal(card.get_script(), CardViewScript)
	harness.assert_equal(card.scene_file_path, "res://scenes/cards/card_view.tscn")
	harness.assert_true(hand.card_scene is PackedScene)
	hand.free()


func _test_layout_boundaries(harness: TestHarness) -> void:
	var hand: Variant = _hand()
	for count in [1, 3, 7]:
		hand.apply_view_model(_vm(count))
		var cards: Array = hand.cards_in_order()
		harness.assert_equal(cards.size(), count)
		for card: Variant in cards:
			harness.assert_true(card.position.x >= -0.01, "%d-card layout crossed left edge" % count)
			harness.assert_true(card.position.x + card.size.x <= 1200.01, "%d-card layout crossed right edge" % count)
			harness.assert_true(card.position.y >= -0.01, "%d-card layout crossed top edge" % count)
			harness.assert_true(card.position.y + card.size.y <= 300.01, "%d-card layout crossed bottom edge" % count)
			for corner: Vector2 in [Vector2.ZERO, Vector2(card.size.x, 0.0), card.size, Vector2(0.0, card.size.y)]:
				var transformed: Vector2 = card.get_transform() * corner
				harness.assert_true(transformed.x >= -0.01 and transformed.x <= 1200.01, "%d-card transformed corner crossed horizontal edge" % count)
				harness.assert_true(transformed.y >= -0.01 and transformed.y <= 300.01, "%d-card transformed corner crossed vertical edge" % count)
		if count == 1:
			harness.assert_equal(cards[0].position.x, (1200.0 - cards[0].size.x) * 0.5)
			harness.assert_equal(cards[0].rotation, 0.0)
		else:
			for index in range(1, cards.size()):
				harness.assert_true(cards[index].position.x > cards[index - 1].position.x)
			harness.assert_true(cards[0].rotation < 0.0)
			harness.assert_true(cards[-1].rotation > 0.0)
	hand.free()


func _test_hover(harness: TestHarness) -> void:
	var hand: Variant = _hand()
	hand.apply_view_model(_vm(3))
	var card: Variant = hand.cards_in_order()[0]
	var base_position: Vector2 = card.layout_position()
	var base_z: int = card.layout_z_index()
	card.hover_changed.emit(card, true)
	harness.assert_true(card.position.y < base_position.y)
	harness.assert_true(card.z_index > base_z)
	harness.assert_true(card.scale.x > 1.0)
	card.hover_changed.emit(card, false)
	harness.assert_equal(card.position, base_position)
	harness.assert_equal(card.z_index, base_z)
	harness.assert_equal(card.scale, Vector2.ONE)
	hand.free()


func _test_drag_cancel_and_success(harness: TestHarness) -> void:
	var hand: Variant = _hand()
	var commands: Array[Dictionary] = []
	hand.play_card_requested.connect(func(command: Dictionary) -> void:
		commands.append(command.duplicate(true))
	)
	hand.apply_view_model(_vm(1))
	var card: Variant = hand.cards_in_order()[0]
	var original_node_id: int = card.get_instance_id()
	var origin: Vector2 = card.global_position + card.size * 0.5
	harness.assert_true(card.begin_drag_at(origin))
	card.drag_to(origin + Vector2(0.0, -40.0))
	card.end_drag_at(origin + Vector2(0.0, -40.0))
	harness.assert_equal(commands.size(), 0)
	harness.assert_equal(card.position, card.layout_position())

	origin = card.global_position + card.size * 0.5
	harness.assert_true(card.begin_drag_at(origin))
	card.drag_to(origin + Vector2(0.0, -100.0))
	card.end_drag_at(origin + Vector2(0.0, -100.0))
	harness.assert_equal(commands.size(), 1)
	harness.assert_equal(commands[0], {
		"type": "play_card",
		"instance_id": "instance-1",
		"expected_card_id": "card-shared",
		"expected_source_skill_id": "smallHeal",
		"owner_hero_id": 4,
	})
	harness.assert_equal(card.get_instance_id(), original_node_id, "drag must not delete or replace visual card")
	harness.assert_equal(hand.card_count(), 1, "visual card waits for a new authoritative VM")
	hand.free()


func _test_interaction_locks(harness: TestHarness) -> void:
	var hand: Variant = _hand()
	var commands: Array[Dictionary] = []
	hand.play_card_requested.connect(func(command: Dictionary) -> void:
		commands.append(command)
	)
	var unavailable: Dictionary = _vm(1)
	unavailable["hand"][0]["playable"] = false
	unavailable["hand"][0]["unavailable_code"] = "validator_rejected"
	unavailable["hand"][0]["unavailable_reason"] = "需要至少一枚可治疗棋子"
	hand.apply_view_model(unavailable)
	var card: Variant = hand.cards_in_order()[0]
	var origin: Vector2 = card.global_position + card.size * 0.5
	harness.assert_false(card.begin_drag_at(origin))
	harness.assert_equal(card.displayed_unavailable_reason(), "需要至少一枚可治疗棋子")

	hand.apply_view_model(_vm(1))
	card = hand.cards_in_order()[0]
	origin = card.global_position + card.size * 0.5
	hand.set_queue_busy(true)
	harness.assert_false(card.begin_drag_at(origin))
	harness.assert_equal(card.displayed_unavailable_reason(), "正在结算上一张牌")
	hand.set_interaction_state(false, false, "round_resolution")
	harness.assert_false(card.begin_drag_at(origin))
	hand.set_interaction_state(false, true, "player_input")
	harness.assert_false(card.begin_drag_at(origin))
	harness.assert_equal(commands.size(), 0)
	hand.free()


func _test_duplicate_card_instances(harness: TestHarness) -> void:
	var hand: Variant = _hand()
	var vm: Dictionary = _vm(2)
	vm["hand"][1]["card_id"] = vm["hand"][0]["card_id"]
	vm["hand"][1]["source_skill_id"] = vm["hand"][0]["source_skill_id"]
	vm["hand"][1]["name"] = vm["hand"][0]["name"]
	hand.apply_view_model(vm)
	var first: Variant = hand.card_for_instance("instance-1")
	var second: Variant = hand.card_for_instance("instance-2")
	harness.assert_not_null(first)
	harness.assert_not_null(second)
	harness.assert_false(is_same(first, second))
	harness.assert_equal(first.view_model()["name"], second.view_model()["name"])
	var first_node_id: int = first.get_instance_id()
	vm["hand"].reverse()
	hand.apply_view_model(vm)
	harness.assert_equal(hand.cards_in_order()[1].get_instance_id(), first_node_id)
	hand.free()


func _hand() -> Variant:
	var hand: Variant = HandScene.instantiate()
	assert(hand.get_script() == HandViewScript)
	hand.animate_layout = false
	hand.size = Vector2(1200.0, 300.0)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(hand)
	return hand


func _vm(count: int) -> Dictionary:
	var hand: Array[Dictionary] = []
	for index in count:
		hand.append(_card_vm(index + 1))
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null},
		"hand": hand,
		"fatal": null,
	}


func _card_vm(index: int) -> Dictionary:
	return {
		"instance_id": "instance-%d" % index,
		"card_id": "card-shared" if index <= 2 else "card-%d" % index,
		"source_skill_id": "smallHeal" if index <= 2 else "skill-%d" % index,
		"name": "小回血" if index <= 2 else "卡牌 %d" % index,
		"description": "恢复我方生命最低棋子的生命。",
		"category": "exclusive" if index == 1 else "free",
		"owner_hero_id": 4 if index == 1 else 0,
		"base_cost": 2,
		"effective_cost": 2,
		"actual_cost": 2,
		"play_destination": "discard",
		"end_of_turn_destination": "discard",
		"exhausts_on_success": false,
		"playable": true,
		"unavailable_code": "",
		"unavailable_reason": "",
	}
