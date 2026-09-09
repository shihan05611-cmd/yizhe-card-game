extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")
const QueueScript = preload("res://app/battle_presentation_queue.gd")
const StreamScript = preload("res://app/combat_presentation_stream.gd")
const DamageFloatScene: PackedScene = preload("res://scenes/effects/damage_float.tscn")


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("one resolved hit emits one source action while counter and pursuit remain independent", func() -> void:
		_test_action_cues(harness)
	)
	harness.run_test("stream preserves actual strike boundaries for multi-target, extra and blocked hits", func() -> void:
		_test_stream_action_boundaries(harness)
	)
	harness.run_test("damage waves start all targets together while envelopes and reactions remain ordered", func() -> void:
		_test_damage_wave_grouping(harness)
	)
	harness.run_test("burn visual follows buff state, clears on removal and honors presentation speed/reset", func() -> void:
		_test_burn_lifecycle(harness)
	)
	harness.run_test("piece strike timing is readable at 1x and preserves four-to-one queue speed", func() -> void:
		_test_strike_timing(harness)
	)
	harness.run_test("combat float holds at impact before it rises and fades", func() -> void:
		_test_float_hold(harness)
	)
	harness.run_test("interrupted pulses restore the stable slot tint", func() -> void:
		_test_pulse_reset(harness)
	)
	print("COMBAT MOTION PRESENTATION TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests, harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_action_cues(harness: TestHarness) -> void:
	var screen: Variant = _screen()
	screen.bind_view_model(_vm())
	var ally: Node = screen.ally_board.slot_for_target({"slot": 1, "unit_id": 1})
	var enemy: Node = screen.enemy_board.slot_for_target({"slot": 1, "unit_id": 101})
	var basic := _damage(1, "damage_applied", "basic_attack", "ally", 1)
	screen.present_event(basic, 0.44)
	var damaged := _damage(2, "unit_damaged", "basic_attack", "ally", 1)
	var blocked := _damage(3, "unit_blocked", "basic_attack", "ally", 1)
	screen.present_event(damaged, 0.10)
	screen.present_event(blocked, 0.16)
	harness.assert_equal(ally.action_presentation_count(), 1, "one hit feedback envelope must not restart its source action")
	screen.present_event(_damage(4, "damage_applied", "counter", "enemy", 101), 0.44)
	screen.present_event(_damage(5, "damage_applied", "pursuit", "ally", 1), 0.44)
	harness.assert_equal(enemy.action_presentation_count(), 1, "counter is its own action")
	harness.assert_equal(ally.action_presentation_count(), 2, "pursuit is its own action")
	screen.free()


func _test_burn_lifecycle(harness: TestHarness) -> void:
	var screen: Variant = _screen()
	screen.bind_view_model(_vm())
	var target: Node = screen.enemy_board.slot_for_target({"slot": 1, "unit_id": 101})
	var aura: Node = target.get_node("Content/ChessArt/BurnAura")
	harness.assert_equal(aura.get("_stacks"), 0)
	screen.present_event(_buff(1, "buff_applied", 3), 0.18)
	harness.assert_equal(aura.get("_stacks"), 3, "visual state comes from this buff event snapshot")
	screen.present_event(_buff(2, "buff_consumed", 1), 0.18)
	harness.assert_equal(aura.get("_stacks"), 1)
	screen.present_event(_buff(3, "buff_cleared", -1), 0.18)
	harness.assert_equal(aura.get("_stacks"), 0, "clear events remove the aura before a final VM bind")
	screen.present_event(_buff(4, "buff_applied", 2), 0.18)
	screen.set_presentation_speed(0.0)
	harness.assert_false(aura.is_processing(), "presentation pause freezes burn animation")
	screen.set_presentation_speed(4.0)
	harness.assert_true(aura.is_processing(), "resuming a visible aura restarts processing")
	target.set_empty(1)
	harness.assert_equal(aura.get("_stacks"), 0, "removed unit clears burn visual")
	var dead_vm := _vm()
	dead_vm["teams"]["enemy"]["slots"][0]["alive"] = false
	dead_vm["teams"]["enemy"]["slots"][0]["hp"] = 0.0
	dead_vm["teams"]["enemy"]["slots"][0]["buffs"] = [{"id": "burn", "stacks": 4}]
	screen.bind_view_model(dead_vm)
	harness.assert_equal(aura.get("_stacks"), 0, "dead VM cannot retain a burn aura")
	screen.reset_presentation()
	harness.assert_equal(aura.get("_stacks"), 0, "presentation reset clears lingering burn visual")
	screen.free()


func _test_stream_action_boundaries(harness: TestHarness) -> void:
	var stream := StreamScript.new()
	stream.begin_batch("boundaries")
	stream.capture_damage("damage_applied", _stream_damage_payload(true))
	stream.capture_damage("unit_damaged", _stream_damage_payload(true))
	stream.capture_damage("unit_blocked", _stream_damage_payload(true))
	stream.capture_damage("damage_applied", _stream_damage_payload(false))
	var events: Array = stream.all_events()
	var action := str(events[0]["source"].get("presentation_action_id", ""))
	harness.assert_false(action.is_empty())
	harness.assert_equal(events[1]["source"].get("presentation_action_id"), action)
	harness.assert_equal(events[2]["source"].get("presentation_action_id"), action)
	harness.assert_equal(events[3]["source"].get("presentation_action_id"), action, "same strike groups a column hit")
	stream.capture_damage("damage_applied", _stream_damage_payload(true))
	events = stream.all_events()
	harness.assert_false(events[4]["source"].get("presentation_action_id") == action, "extra strike starts a new action")
	stream.capture_damage("damage_applied", _stream_damage_payload(null, "counter", "enemy", 101))
	stream.capture_damage("unit_blocked", _stream_damage_payload(null, "counter", "enemy", 101))
	stream.capture_damage("damage_applied", _stream_damage_payload(true, "pursuit", "ally", 1))
	stream.capture_damage("damage_applied", _stream_damage_payload(true, "pursuit", "ally", 1))
	events = stream.all_events()
	harness.assert_equal(events[6]["source"].get("presentation_action_id"), events[5]["source"].get("presentation_action_id"), "blocked counter feedback stays in its counter action")
	harness.assert_false(events[8]["source"].get("presentation_action_id") == events[7]["source"].get("presentation_action_id"), "each pursuit is an independent action")
	stream.begin_batch("next-round")
	stream.capture_damage("damage_applied", _stream_damage_payload(true))
	events = stream.all_events()
	harness.assert_false(events[9]["source"].get("presentation_action_id") == action, "same actor next batch starts a new action")


func _test_strike_timing(harness: TestHarness) -> void:
	var queue: Node = QueueScript.new()
	var event := _damage(1, "damage_applied", "basic_attack", "ally", 1)
	harness.assert_equal(queue.event_duration_ms(event), 440)
	harness.assert_true(queue.set_speed(1.0))
	harness.assert_true(queue.enqueue([event], {}))
	var one: float = queue.drain_for_test()
	queue.reset()
	harness.assert_true(queue.set_speed(4.0))
	harness.assert_true(queue.enqueue([event], {}))
	var four: float = queue.drain_for_test()
	harness.assert_true(absf(one / four - 4.0) < 0.08, "strike timing must retain queue speed semantics")
	queue.free()


func _test_damage_wave_grouping(harness: TestHarness) -> void:
	var stream := StreamScript.new()
	stream.begin_batch("wave-boundaries")
	# A column strike has two primary targets, with the first target's feedback
	# and counter nested before the second primary target resolves.
	stream.capture_damage("damage_applied", _stream_damage_payload(true))
	stream.capture_damage("unit_damaged", _stream_damage_payload(true))
	stream.capture_damage("unit_blocked", _stream_damage_payload(true))
	stream.capture_damage("damage_applied", _stream_damage_payload(true, "counter", "enemy", 101))
	stream.capture_damage("damage_applied", _stream_damage_payload(false))
	var queue: Node = QueueScript.new()
	var started: Array[int] = []
	queue.event_started.connect(func(event: Dictionary, _duration: float) -> void:
		started.append(int(event["sequence"])))
	harness.assert_true(queue.enqueue(stream.all_events(), {}))
	harness.assert_equal(started, [1, 5], "one piece action waves both column targets before its feedback and counter")
	queue.drain_for_test()
	harness.assert_equal(started, [1, 5, 2, 3, 4], "feedback and counter retain their source order after the wave")
	harness.assert_equal(queue.completed_sequences(), [1, 5, 2, 3, 4], "out-of-order visual completion remains explicit until final batch acknowledgement")

	stream = StreamScript.new()
	stream.begin_batch("ultimate-waves")
	stream.capture_damage("damage_applied", _skill_damage_payload(0, 101))
	stream.capture_damage("unit_damaged", _skill_damage_payload(0, 101))
	stream.capture_damage("damage_applied", _skill_damage_payload(0, 102))
	stream.capture_damage("damage_applied", _skill_damage_payload(1, 101))
	queue.reset()
	started.clear()
	harness.assert_true(queue.enqueue(stream.all_events(), {}))
	harness.assert_equal(started, [1, 3], "one skill hit groups its targets despite the first target envelope")
	queue.drain_for_test()
	harness.assert_equal(started, [1, 3, 2, 4], "the next ultimate hit stays a later wave")

	var one := _wave_elapsed(stream.all_events(), 1.0)
	var four := _wave_elapsed(stream.all_events(), 4.0)
	harness.assert_true(absf(one / four - 4.0) < 0.08, "wave grouping preserves 1x/4x timing")
	queue.free()


func _test_float_hold(harness: TestHarness) -> void:
	var node: Node = DamageFloatScene.instantiate()
	Engine.get_main_loop().root.add_child(node)
	node.configure(_damage(1, "damage_applied", "basic_attack", "ally", 1), {"position": Vector2(300, 200)})
	var initial_y: float = node.position.y
	node.play(0.40)
	var tween: Tween = node.get("_play_tween")
	tween.custom_step(0.10)
	harness.assert_equal(node.position.y, initial_y, "hold must keep the number at the impact point")
	harness.assert_equal(node.modulate.a, 1.0, "hold must keep the number opaque")
	tween.custom_step(0.05)
	harness.assert_true(node.position.y < initial_y)
	harness.assert_true(node.modulate.a < 1.0)
	node.free()


func _test_pulse_reset(harness: TestHarness) -> void:
	var screen: Variant = _screen()
	screen.bind_view_model(_vm())
	var target: Node = screen.enemy_board.slot_for_target({"slot": 1, "unit_id": 101})
	target.present_pulse(0.40, Color(1.25, 0.62, 0.58, 1.0))
	var first: Tween = target.get("_pulse_tween")
	first.custom_step(0.10)
	target.present_pulse(0.40, Color(1.10, 0.69, 0.38, 1.0))
	var second: Tween = target.get("_pulse_tween")
	second.custom_step(0.45)
	harness.assert_equal(target.modulate, Color.WHITE, "interrupted pulses must not leave an intermediate tint")
	screen.free()


func _screen() -> Variant:
	var screen: Variant = BattleScreenScene.instantiate()
	Engine.get_main_loop().root.add_child(screen)
	return screen


static func _vm() -> Dictionary:
	var allies: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	for slot in range(1, 7):
		allies.append(_unit(slot, "ally"))
		enemies.append(_unit(slot, "enemy"))
	return {
		"initialized": true, "session": {"active": true, "halted": false, "settled": false},
		"battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null},
		"resources": {"sp": 10, "sp_max": 10}, "teams": {"ally": {"slots": allies}, "enemy": {"slots": enemies}},
		"heroes": {"ally": [], "enemy": []}, "piles": {"draw": 0, "hand": 0, "discard": 0, "exhaust": 0},
		"hand": [], "logs": [], "presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []}, "fatal": null,
	}


static func _unit(slot: int, side: String) -> Dictionary:
	return {"id": slot if side == "ally" else 100 + slot, "slot": slot, "side": side, "class_id": "default", "class_name": "棋子", "hp": 100.0, "max_hp": 100.0, "alive": true, "buffs": []}


static func _damage(sequence: int, event_id: String, type: String, side: String, actor_id: int) -> Dictionary:
	return {"sequence": sequence, "batch_id": "motion", "kind": "damage", "event_id": event_id, "source": {"type": type, "id": type, "side": side, "actor_id": actor_id, "action_phase": "piece_action"}, "visual_target": {"kind": "unit", "side": "enemy" if side == "ally" else "ally", "unit_id": 101 if side == "ally" else 1, "slot": 1}, "payload": {"amount": 10.0, "old_hp": 100.0, "new_hp": 90.0, "target": {"max_hp": 100.0}}}


static func _buff(sequence: int, event_id: String, stacks: int) -> Dictionary:
	return {"sequence": sequence, "batch_id": "burn", "kind": "buff", "event_id": event_id, "source": {"action_phase": "system"}, "visual_target": {"kind": "unit", "side": "enemy", "unit_id": 101, "slot": 1}, "payload": {"buff_id": "burn", "state": {"stacks": stacks} if stacks >= 0 else null}}


static func _stream_damage_payload(starts_action: Variant, source_type := "basic_attack", side := "ally", actor_id: int = 1) -> Dictionary:
	var metadata := {}
	if starts_action != null:
		metadata["presentation_starts_action"] = starts_action
	return {"target": {"id": 101 if side == "ally" else 1, "slot": 1, "side": "enemy" if side == "ally" else "ally", "max_hp": 100.0}, "amount": 10.0, "metadata": metadata, "effect_context": {"source_type": source_type, "source_id": "normalAttack" if source_type == "basic_attack" else source_type, "source_name": "测试", "source_side": side, "source_actor_id": actor_id}}


static func _skill_damage_payload(hit_index: int, target_id: int) -> Dictionary:
	return {
		"target": {"id": target_id, "slot": target_id - 100, "side": "enemy", "max_hp": 100.0},
		"amount": 10.0,
		"metadata": {"presentation_wave_index": hit_index},
		"effect_context": {
			"source_type": "ultimate", "source_id": "fist", "source_name": "宁不凡",
			"source_side": "ally", "source_actor_id": 6,
		},
	}


static func _wave_elapsed(events: Array, speed: float) -> float:
	var queue: Node = QueueScript.new()
	assert(queue.set_speed(speed))
	assert(queue.enqueue(events, {}))
	var elapsed: float = queue.drain_for_test()
	queue.free()
	return elapsed
