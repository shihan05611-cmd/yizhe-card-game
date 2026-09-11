extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const HandScene: PackedScene = preload("res://scenes/cards/hand_view.tscn")
const CardScene: PackedScene = preload("res://scenes/cards/card_view.tscn")
const PieceScene: PackedScene = preload("res://scenes/battle/piece_slot.tscn")
const HeroItemScene: PackedScene = preload("res://scenes/battle/hero_energy_item.tscn")
const ResultScene: PackedScene = preload("res://scenes/battle/battle_result_overlay.tscn")
const FatalScene: PackedScene = preload("res://scenes/battle/fatal_overlay.tscn")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("ART-2 card uses compact safe-zone information structure", func() -> void:
		_test_card_structure(harness)
	)
	harness.run_test("ART-2 hand keeps zero one and seven cards inside rotated bounds", func() -> void:
		_test_hand_layout(harness)
	)
	harness.run_test("ART-2 right cards cover left right edges and hover drag do not reflow", func() -> void:
		_test_layering_and_interaction(harness)
	)
	harness.run_test("ART-2 piece slot localizes classes and represents death with nodes", func() -> void:
		_test_piece_slot(harness)
	)
	harness.run_test("ART-2 titles overlays and hero portraits use production nodes", func() -> void:
		_test_battle_components(harness)
	)
	print("ART-2 HAND COMPONENT TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_card_structure(harness: TestHarness) -> void:
	var card: Variant = CardScene.instantiate()
	_attach(card)
	card.bind_card(_card_vm(1, "这是一段用于验证三行截断的完整卡牌说明，悬停提示必须保留全部文字。"))
	harness.assert_equal(card.custom_minimum_size, Vector2(150, 210))
	harness.assert_false(card.has_node("CardSurface/InstanceId"))
	var description: Label = card.get_node("CardSurface/CardDescription")
	harness.assert_equal(description.max_lines_visible, 3)
	harness.assert_equal(description.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	harness.assert_contains(card.get_node("InputButton").tooltip_text, "悬停提示必须保留全部文字")
	var cost: Label = card.get_node("CardSurface/Cost")
	harness.assert_equal(cost.size, Vector2(32, 30))
	harness.assert_true(card.has_node("CardSurface/CostSeal"))
	harness.assert_true(card.has_node("CardSurface/TagRow/Owner"))
	harness.assert_true(card.has_node("CardSurface/TagRow/Tags"))
	var retained_vm := _card_vm(1, "保留牌的原始描述")
	retained_vm["retained"] = true
	retained_vm["exhausts_on_success"] = false
	retained_vm["play_destination"] = "discard"
	card.bind_card(retained_vm)
	harness.assert_equal(card.get_node("CardSurface/TagRow/Tags").text, "保留 / 弃牌")
	harness.assert_contains(card.get_node("InputButton").tooltip_text, "仍占手牌上限")
	retained_vm["exhausts_on_success"] = true
	card.bind_card(retained_vm)
	harness.assert_equal(card.get_node("CardSurface/TagRow/Tags").text, "保留 / 消耗")
	retained_vm["exhausts_on_success"] = false
	retained_vm["play_destination"] = "hand"
	card.bind_card(retained_vm)
	harness.assert_equal(card.get_node("CardSurface/TagRow/Tags").text, "保留 / 回手")
	for safe_node_path in ["CardSurface/Category", "CardSurface/Cost", "CardSurface/CardName"]:
		var safe_node: Control = card.get_node(safe_node_path)
		harness.assert_true(safe_node.get_rect().end.x <= 140.01, "card primary information overflowed: %s" % safe_node_path)
	_release(card)


func _test_hand_layout(harness: TestHarness) -> void:
	var hand: Variant = _hand(Vector2(1200, 300))
	hand.apply_view_model(_vm(0))
	harness.assert_equal(hand.card_count(), 0)
	harness.assert_equal(hand.get_node("CardContainer").get_child_count(), 0)
	hand.apply_view_model(_vm(1))
	harness.assert_equal(hand.card_count(), 1)
	harness.assert_equal(hand.cards_in_order()[0].rotation, 0.0)
	hand.apply_view_model(_vm(7))
	var bounds := _hand_bounds(hand.cards_in_order())
	harness.assert_true(bounds["width"] <= 1000.01, "1200 hand width: %s" % str(bounds))
	harness.assert_true(bounds["left"] >= -0.01, "1200 hand left: %s" % str(bounds))
	harness.assert_true(bounds["right"] <= 1200.01, "1200 hand right: %s" % str(bounds))
	harness.assert_true(bounds["top"] >= -0.01, "1200 hand top: %s" % str(bounds))
	harness.assert_true(bounds["bottom"] <= 300.01, "1200 hand bottom: %s" % str(bounds))
	harness.assert_equal(hand.last_layout_scale(), 1.0)
	harness.assert_true(hand.last_unscaled_spacing() >= 150.0 * 0.72)
	_release(hand)

	var narrow_hand: Variant = _hand(Vector2(700, 300))
	narrow_hand.apply_view_model(_vm(7))
	harness.assert_true(narrow_hand.last_layout_scale() < 1.0)
	harness.assert_true(narrow_hand.last_unscaled_spacing() >= 150.0 * 0.72)
	var narrow_bounds := _hand_bounds(narrow_hand.cards_in_order())
	harness.assert_true(narrow_bounds["left"] >= -0.01, "narrow hand left: %s" % str(narrow_bounds))
	harness.assert_true(narrow_bounds["right"] <= 700.01, "narrow hand right: %s" % str(narrow_bounds))
	_release(narrow_hand)


func _test_layering_and_interaction(harness: TestHarness) -> void:
	var hand: Variant = _hand(Vector2(1200, 300))
	hand.apply_view_model(_vm(7))
	var cards: Array = hand.cards_in_order()
	for index in range(cards.size() - 1):
		var current_center: float = cards[index].position.x + cards[index].size.x * 0.5
		var next_center: float = cards[index + 1].position.x + cards[index + 1].size.x * 0.5
		harness.assert_true(next_center - current_center >= 108.0)
		harness.assert_true(cards[index + 1].z_index > cards[index].z_index)

	var neighbor_poses := _poses(cards)
	var hovered: Variant = cards[3]
	var base_position: Vector2 = hovered.position
	hovered.hover_changed.emit(hovered, true)
	harness.assert_equal(hovered.scale, Vector2.ONE * 1.08)
	harness.assert_equal(hovered.position, base_position + Vector2.UP * 28.0)
	harness.assert_equal(hovered.z_index, 900)
	harness.assert_true(hovered.is_hover_shadow_visible())
	_assert_other_poses_unchanged(harness, cards, neighbor_poses, 3)
	hovered.hover_changed.emit(hovered, false)

	var origin: Vector2 = hovered.global_position + hovered.size * 0.5
	harness.assert_true(hovered.begin_drag_at(origin))
	harness.assert_equal(hovered.z_index, 1000)
	harness.assert_true(hovered.is_hover_shadow_visible())
	_assert_other_poses_unchanged(harness, cards, neighbor_poses, 3)
	hovered.cancel_drag(false)
	_release(hand)


func _test_piece_slot(harness: TestHarness) -> void:
	var piece: Variant = PieceScene.instantiate()
	_attach(piece)
	piece.bind_slot(_slot_vm("guard", true, []))
	harness.assert_equal(piece.get_node("Content/ClassLine/ClassLabel").text, "甲卒")
	harness.assert_false(piece.get_node("Content/BuffLabel").visible)
	harness.assert_false(piece.get_node("DeathMark").visible)
	harness.assert_false(piece.has_node("Content/Header/StateLabel"))
	harness.assert_equal(piece.get_node("Content/HpStack/HpLabel").text, "80 / 100")
	harness.assert_equal(piece.get_node("Content/HpStack/HpLabel").get_parent().name, "HpStack")
	piece.bind_slot(_slot_vm("archer", false, [{"id": "guard", "stacks": 2}]))
	harness.assert_equal(piece.get_node("Content/ClassLine/ClassLabel").text, "机弩")
	harness.assert_true(piece.get_node("Content/BuffLabel").visible)
	harness.assert_true(piece.get_node("DeathMark").visible)
	harness.assert_true(piece.get_node("Content/ClassLine/NameStrike").visible)
	harness.assert_true(piece.modulate.r < 0.7)
	_release(piece)


func _test_battle_components(harness: TestHarness) -> void:
	var screen: Variant = BattleScreenScene.instantiate()
	_attach(screen)
	harness.assert_equal(screen.ally_heroes.title_label.text, "我方弈者")
	harness.assert_equal(screen.enemy_heroes.title_label.text, "敌方弈者")
	_release(screen)

	var enemy_item: Variant = HeroItemScene.instantiate()
	_attach(enemy_item)
	enemy_item.bind_hero({"id": 101, "name": "敌方弈者", "side":"enemy", "energy": 0, "max_energy": 100})
	var placeholder: Panel = enemy_item.get_node("Row/PortraitFrame/PortraitPlaceholder")
	harness.assert_false(placeholder.visible)
	harness.assert_true(enemy_item.get_node("Row/PortraitFrame/EnemyPortrait").visible)
	var portrait: TextureRect = enemy_item.get_node("Row/PortraitFrame/Portrait")
	harness.assert_false(portrait.visible)
	harness.assert_equal(enemy_item.placeholder_label.text, "敌方弈者")
	for id: int in [1,3,4,5,6,7,8,9]:
		enemy_item.bind_hero({"id":id,"name":"立绘验证","side":"ally","energy":0,"max_energy":100})
		harness.assert_true(portrait.visible,"Existing hero portrait must remain visible: %d" % id)
		harness.assert_true(portrait.texture != null)
		harness.assert_false(placeholder.visible)
	_release(enemy_item)

	var result: Variant = ResultScene.instantiate()
	_attach(result)
	result.bind_result("win")
	harness.assert_true(result.visible)
	harness.assert_true(result.has_node("Center/ResultCard/Margin/Content/RestartButton"))
	harness.assert_equal(result.get_node("Center/ResultCard/Margin/Content/IconLabel").text, "胜")
	_release(result)
	var fatal: Variant = FatalScene.instantiate()
	_attach(fatal)
	fatal.bind_fatal({"code": "committed_failure", "message": "不可恢复"})
	harness.assert_true(fatal.visible)
	harness.assert_true(fatal.has_node("Center/FatalCard/Margin/Content/RestartButton"))
	harness.assert_equal(fatal.get_node("Center/FatalCard/Margin/Content/IconLabel").text, "!")
	_release(fatal)


func _hand(hand_size: Vector2) -> Variant:
	var hand: Variant = HandScene.instantiate()
	hand.animate_layout = false
	hand.size = hand_size
	_attach(hand)
	return hand


func _vm(count: int) -> Dictionary:
	var cards: Array[Dictionary] = []
	for index in count:
		cards.append(_card_vm(index + 1, "恢复我方生命最低棋子的生命。"))
	return {
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null},
		"hand": cards,
		"fatal": null,
	}


func _card_vm(index: int, description: String) -> Dictionary:
	return {
		"instance_id": "art2-instance-%d" % index,
		"card_id": "art2-card-%d" % index,
		"source_skill_id": "smallHeal",
		"name": "卡牌%d" % index,
		"description": description,
		"category": "free",
		"owner_hero_id": 0,
		"base_cost": 2,
		"effective_cost": 2,
		"play_destination": "discard",
		"exhausts_on_success": false,
		"playable": true,
		"unavailable_code": "",
		"unavailable_reason": "",
	}


func _slot_vm(class_id: String, alive: bool, buffs: Array) -> Dictionary:
	return {
		"id": 1,
		"slot": 1,
		"side": "ally",
		"class_id": class_id,
		"class_name": class_id,
		"hp": 80.0 if alive else 0.0,
		"max_hp": 100.0,
		"alive": alive,
		"buffs": buffs,
	}


func _hand_bounds(cards: Array) -> Dictionary:
	var left := INF
	var top := INF
	var right := -INF
	var bottom := -INF
	for card: Control in cards:
		for corner: Vector2 in [Vector2.ZERO, Vector2(card.size.x, 0), card.size, Vector2(0, card.size.y)]:
			var transformed := card.get_transform() * corner
			left = minf(left, transformed.x)
			top = minf(top, transformed.y)
			right = maxf(right, transformed.x)
			bottom = maxf(bottom, transformed.y)
	return {"left": left, "top": top, "right": right, "bottom": bottom, "width": right - left}


func _poses(cards: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card: Control in cards:
		result.append({"position": card.position, "rotation": card.rotation, "scale": card.scale, "z": card.z_index})
	return result


func _assert_other_poses_unchanged(
	harness: TestHarness,
	cards: Array,
	poses: Array[Dictionary],
	excluded_index: int,
) -> void:
	for index in cards.size():
		if index == excluded_index:
			continue
		harness.assert_equal(cards[index].position, poses[index]["position"])
		harness.assert_equal(cards[index].rotation, poses[index]["rotation"])
		harness.assert_equal(cards[index].scale, poses[index]["scale"])
		harness.assert_equal(cards[index].z_index, poses[index]["z"])


static func _attach(node: Node) -> void:
	Engine.get_main_loop().root.add_child(node)


static func _release(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
