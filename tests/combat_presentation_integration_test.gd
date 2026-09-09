extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")
const QueueScript = preload("res://app/battle_presentation_queue.gd")
const StreamScript = preload("res://app/combat_presentation_stream.gd")


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("formal composition instantiates battle hand FX queue and unified duration clock", func() -> void:
		_test_composition_and_clock(harness)
	)
	harness.run_test("piece damage heal crit and block use stable anchors and PackedScene floats", func() -> void:
		_test_damage_heal_and_markers(harness)
	)
	harness.run_test("same-batch Buffs flush together and relic damage retains its source", func() -> void:
		_test_buff_wave_and_relic(harness)
	)
	harness.run_test("unit and side statuses update from events and retain complete inspection text", func() -> void:
		_test_status_updates(harness)
	)
	harness.run_test("card destination FX and fatal terminal state are visible without mutating authority", func() -> void:
		_test_card_fx_and_terminal(harness)
	)
	print("M4-5 COMBAT PRESENTATION INTEGRATION TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_composition_and_clock(harness: TestHarness) -> void:
	var root: Variant = MainScene.instantiate()
	root.auto_start = false
	Engine.get_main_loop().root.add_child(root)
	harness.assert_equal(root.scene_file_path, "res://scenes/main.tscn")
	harness.assert_equal(root.battle_screen.scene_file_path, "res://scenes/battle/battle_screen.tscn")
	harness.assert_equal(root.battle_screen.hand_view.scene_file_path, "res://scenes/cards/hand_view.tscn")
	harness.assert_equal(root.battle_screen.fx_player.scene_file_path, "res://scenes/effects/skill_fx_player.tscn")
	harness.assert_true(root.presentation_queue.set_speed(1.0))
	var segment_event := _event(
		1, "clock", "card", "freeSkillCast", _source("system", "clock"),
		{"kind": "battle"}, {"card_category": "free"},
	)
	harness.assert_true(root.presentation_queue.enqueue([segment_event], {}))
	root.battle_screen.fx_player.start_skill_fx("ult", "fist", {})
	harness.assert_true(root.presentation_queue.set_speed(4.0))
	harness.assert_false(root.presentation_queue.set_speed(2.5))
	harness.assert_equal(root.battle_screen.fx_player.call("_seconds", 1000), 1.0, "active FX must keep its segment speed")
	root.presentation_queue.drain_for_test()
	root.battle_screen.fx_player.clear_visual_effect()
	root.battle_screen.fx_player.start_skill_fx("ult", "fist", {})
	harness.assert_equal(root.battle_screen.fx_player.call("_seconds", 1000), 0.25, "next FX segment must use the new speed")
	root.battle_screen.fx_player.clear_visual_effect()
	harness.assert_equal(
		str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"res://scenes/run.tscn",
		"the journey entry must host the reusable formal battle composition",
	)
	root.free()


func _test_damage_heal_and_markers(harness: TestHarness) -> void:
	var screen: Variant = _screen()
	screen.bind_view_model(_vm())
	var damage := _event(
		1,
		"batch-hit",
		"damage",
		"damage_applied",
		{"type": "basic_attack", "id": "basic", "side": "ally", "actor_id": 1, "action_phase": "piece_action"},
		{"kind": "unit", "side": "enemy", "unit_id": 101, "slot": 1},
		{"amount": 30.0, "old_hp": 100.0, "new_hp": 70.0, "crit": true, "blocked": false, "target": {"max_hp": 100.0}},
	)
	screen.present_event(damage, 0.0)
	var enemy_slot: Node = screen.enemy_board.slot_for_target(damage["visual_target"])
	harness.assert_equal(enemy_slot.hp_bar.value, 70.0)
	harness.assert_equal(screen.feedback_instances().size(), 2)
	harness.assert_equal(screen.feedback_instances()[0].scene_file_path, "res://scenes/effects/damage_float.tscn")
	harness.assert_equal(screen.feedback_instances()[1].scene_file_path, "res://scenes/effects/combat_marker.tscn")
	harness.assert_equal(screen.feedback_instances()[1].value_label.text, "暴击")

	var stream := StreamScript.new()
	stream.begin_batch("heal")
	stream.capture_heal({
		"target_id": 1, "target_side": "ally", "amount": 15.0,
		"old_hp": 50.0, "new_hp": 65.0,
	})
	var heal: Dictionary = stream.all_events()[0]
	harness.assert_equal(heal["visual_target"], {"kind": "unit", "side": "ally", "unit_id": 1, "slot": null})
	screen.present_event(heal, 0.0)
	var ally_slot: Node = screen.ally_board.slot_for_target(heal["visual_target"])
	harness.assert_equal(ally_slot.hp_bar.value, 65.0)
	harness.assert_equal(screen.feedback_instances()[-1].scene_file_path, "res://scenes/effects/heal_float.tscn")

	var blocked := damage.duplicate(true)
	blocked["sequence"] = 2
	blocked["payload"]["blocked"] = true
	blocked["payload"]["new_hp"] = 100.0
	blocked["payload"]["amount"] = 0.0
	screen.present_event(blocked, 0.0)
	harness.assert_equal(screen.feedback_instances()[-1].value_label.text, "暴击·格挡")
	harness.assert_equal(screen.feedback_instances()[-2].value_label.text, "−0")
	var feedback_before: int = screen.feedback_instances().size()
	blocked["event_id"] = "unit_blocked"
	screen.present_event(blocked, 0.0)
	harness.assert_equal(screen.feedback_instances().size(), feedback_before, "blocked envelope does not duplicate a float or marker")
	blocked["event_id"] = "damage_applied"
	blocked["payload"]["amount"] = 12.0
	screen.present_event(blocked, 0.0)
	harness.assert_equal(screen.feedback_instances()[-2].value_label.text, "−12", "settled amount takes precedence over HP fallback")
	screen.free()


func _test_status_updates(harness: TestHarness) -> void:
	var screen: Variant = _screen()
	var vm := _vm()
	vm["teams"]["ally"]["slots"][0]["disarm_turns"] = 2
	screen.bind_view_model(vm)
	var slot: Variant = screen.ally_board.slot_for_target({"slot": 1})
	harness.assert_true(slot.buff_label.text.contains("缴械·2回合"))
	var event := _event(1, "statuses", "buff", "buff_applied", _source("system", "buff"),
		{"kind": "unit", "side": "ally", "slot": 1},
		{"buff_id": "enchant", "state": {"stacks": 3, "turns": 0, "layer_turns": []}})
	screen.present_event(event, 0.0)
	harness.assert_true(slot.buff_label.text.contains("附魔×3"))
	harness.assert_true(slot.tooltip_text.contains("附魔×3"))
	event["payload"]["state"] = null
	screen.present_event(event, 0.0)
	harness.assert_false(slot.buff_label.text.contains("附魔"))
	event["visual_target"] = {"kind": "side", "side": "ally"}
	event["event_id"] = "side_buff_applied"
	event["payload"] = {"buff_id": "tempBlock", "state": {"stacks": 1, "turns": 2, "layer_turns": []}}
	screen.present_event(event, 0.0)
	harness.assert_true(screen.ally_side_buffs.text.contains("临时格挡×1·2回合"))
	harness.assert_equal(screen.enemy_side_buffs.text, "")
	harness.assert_true(screen.ally_side_buffs.tooltip_text.contains("临时格挡"))
	event["payload"]["state"] = null
	event["event_id"] = "side_buff_expired"
	screen.present_event(event, 0.0)
	harness.assert_equal(screen.ally_side_buffs.text, "")
	screen.free()


func _test_buff_wave_and_relic(harness: TestHarness) -> void:
	var screen: Variant = _screen()
	screen.bind_view_model(_vm())
	var queue: Node = QueueScript.new()
	screen.add_child(queue)
	queue.event_started.connect(screen.present_event)
	var started: Array[int] = []
	queue.event_started.connect(func(event: Dictionary, _duration: float) -> void:
		started.append(int(event["sequence"]))
	)
	var events := [
		_event(1, "batch-buffs", "buff", "buff_applied", _source("system", "buff"), {"kind": "unit", "side": "ally", "unit_id": 1, "slot": 1}, {"buff_id": "guard", "amount": 1}),
		_event(2, "batch-buffs", "buff", "buff_applied", _source("system", "buff"), {"kind": "unit", "side": "ally", "unit_id": 2, "slot": 2}, {"buff_id": "guard", "amount": 1}),
		_event(3, "batch-buffs", "damage", "damage_applied", {"type": "relic", "id": "arcConductor", "side": "ally", "actor_id": 0, "action_phase": "effect_action"}, {"kind": "unit", "side": "enemy", "unit_id": 101, "slot": 1}, {"amount": 12.0, "old_hp": 100.0, "new_hp": 88.0, "target": {"max_hp": 100.0}}),
	]
	harness.assert_true(queue.enqueue(events, _vm()))
	harness.assert_equal(started, [1, 2], "same-batch Buff events must start in one flush wave")
	queue.advance_for_test(0.18)
	harness.assert_equal(started, [1, 2, 3])
	var float_node: Node = screen.feedback_instances()[-1]
	harness.assert_equal(float_node.scene_file_path, "res://scenes/effects/damage_float.tscn")
	harness.assert_equal(float_node.get_meta("presentation_event")["source"]["type"], "relic")
	harness.assert_equal(float_node.get_meta("presentation_event")["source"]["id"], "arcConductor")
	queue.drain_for_test()
	harness.assert_equal(queue.completed_sequences(), [1, 2, 3])
	screen.free()


func _test_card_fx_and_terminal(harness: TestHarness) -> void:
	var screen: Variant = _screen()
	var vm := _vm()
	vm["hand"] = [_card_vm()]
	vm["piles"]["hand"] = 1
	screen.bind_view_model(vm)
	var card_node: Node = screen.hand_view.card_for_instance("ultimate-shadow-1")
	var card_node_id := card_node.get_instance_id()
	var card_event := _event(
		1, "batch-card", "card", "ultimateCast",
		{"type": "ultimate", "id": "shadow", "side": "ally", "actor_id": 9, "action_phase": "skill_action"},
		{"kind": "hero", "side": "ally", "hero_id": 9},
		{
			"card_instance_id": "ultimate-shadow-1", "card_id": "ultimate:shadow",
			"card_category": "ultimate", "destination": "exhaust", "owner_hero_id": 9,
			"source_effect": {"source_type": "ultimate", "source_id": "shadow", "source_side": "ally"},
		},
	)
	screen.present_event(card_event, 1.5)
	harness.assert_equal(card_node.get_instance_id(), card_node_id)
	harness.assert_equal(card_node.get_meta("last_presented_destination"), "exhaust")
	harness.assert_equal(screen.fx_player.get_active_effect()["namespace"], "ult")
	harness.assert_equal(screen.fx_player.get_active_effect()["skill_key"], "shadow")
	var result_queue: Node = QueueScript.new()
	screen.add_child(result_queue)
	result_queue.busy_changed.connect(screen.set_queue_busy)
	result_queue.event_started.connect(screen.present_event)
	result_queue.batch_finished.connect(func(final_vm: Dictionary, _sequence: int) -> void:
		screen.bind_view_model(final_vm)
	)
	var result_vm := vm.duplicate(true)
	result_vm["battle"]["game_over"] = true
	result_vm["battle"]["result"] = "win"
	var result_event := _event(
		2, "batch-result", "round", "battleResolved", _source("system", "battle"),
		{"kind": "battle"}, {"result": "win"},
	)
	harness.assert_true(result_queue.enqueue([result_event], result_vm))
	result_queue.drain_for_test()
	harness.assert_true(screen.result_overlay.visible)
	harness.assert_true(screen.is_input_locked())
	screen.bind_view_model(vm)

	var fatal := _event(
		3, "batch-fatal", "fatal", "fatal", _source("system", "application"),
		{"kind": "battle"},
		{"code": "committed_failure", "message": "不可恢复", "details": {"fatal": true}},
	)
	screen.present_event(fatal, 0.0)
	harness.assert_true(screen.fatal_overlay.visible)
	harness.assert_equal(screen.fatal_overlay.code_label.text, "committed_failure")
	harness.assert_true(screen.is_input_locked())
	harness.assert_true(screen.battle_hud.end_turn_button.disabled)
	harness.assert_false(screen.fatal_overlay.restart_button.disabled)
	screen.fx_player.clear_visual_effect()
	screen.free()


func _screen() -> Variant:
	var screen: Variant = BattleScreenScene.instantiate()
	Engine.get_main_loop().root.add_child(screen)
	return screen


static func _vm() -> Dictionary:
	var allies: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	for slot in range(1, 7):
		allies.append(_unit(slot, "ally", 50.0 if slot == 1 else 100.0))
		enemies.append(_unit(slot, "enemy", 100.0))
	return {
		"initialized": true,
		"session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 10, "sp_max": 10},
		"teams": {"ally": {"slots": allies}, "enemy": {"slots": enemies}},
		"heroes": {"ally": [{"id": 9, "name": "影狩", "energy": 100, "max_energy": 100}], "enemy": []},
		"piles": {"draw": 0, "hand": 0, "discard": 0, "exhaust": 0},
		"hand": [],
		"logs": [],
		"presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []},
		"fatal": null,
	}


static func _unit(slot: int, side: String, hp: float) -> Dictionary:
	return {
		"id": slot if side == "ally" else 100 + slot,
		"slot": slot,
		"side": side,
		"class_id": "default",
		"class_name": "棋子",
		"hp": hp,
		"max_hp": 100.0,
		"alive": hp > 0.0,
		"buffs": [],
	}


static func _card_vm() -> Dictionary:
	return {
		"instance_id": "ultimate-shadow-1", "card_id": "ultimate:shadow",
		"source_skill_id": "shadow", "name": "影·狩", "description": "测试大招",
		"category": "ultimate", "owner_hero_id": 9, "base_cost": 0, "effective_cost": 0,
		"play_destination": "exhaust", "exhausts_on_success": true,
		"playable": true, "unavailable_reason": "",
	}


static func _source(source_type: String, source_id: String) -> Dictionary:
	return {"type": source_type, "id": source_id, "side": "unknown", "actor_id": 0, "action_phase": "system"}


static func _event(
	sequence: int,
	batch: String,
	kind: String,
	event_id: String,
	source: Dictionary,
	target: Dictionary,
	payload: Dictionary,
) -> Dictionary:
	return {
		"sequence": sequence, "batch_id": batch, "kind": kind, "event_id": event_id,
		"source": source, "visual_target": target, "payload": payload,
	}
