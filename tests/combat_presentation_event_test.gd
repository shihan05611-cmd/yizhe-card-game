extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const StreamScript = preload("res://app/combat_presentation_stream.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("piece damage events include action phase and stable target side", func() -> void:
		_test_piece_target(harness)
	)
	harness.run_test("unit and side Buff targets remain distinct JSON-safe locations", func() -> void:
		_test_buff_targets(harness)
	)
	harness.run_test("group Buff events share one explicit visual batch", func() -> void:
		_test_group_batch(harness)
	)
	harness.run_test("relic damage retains an independent visual source", func() -> void:
		_test_relic_source(harness)
	)
	harness.run_test("round card log and fatal categories use the same event envelope", func() -> void:
		_test_envelope_categories(harness)
	)
	print("M4-1 COMBAT PRESENTATION EVENT TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_piece_target(harness: TestHarness) -> void:
	var stream := StreamScript.new()
	stream.begin_batch("piece")
	stream.capture_damage("unit_damaged", _damage_payload("basic_attack", "ally", 1))
	var event: Dictionary = stream.all_events()[0]
	harness.assert_equal(event["kind"], "damage")
	harness.assert_equal(event["source"]["action_phase"], "piece_action")
	harness.assert_equal(event["source"]["side"], "ally")
	harness.assert_equal(event["visual_target"], {
		"kind": "unit", "side": "enemy", "unit_id": 101, "slot": 1,
	})
	_assert_envelope(harness, event)


func _test_buff_targets(harness: TestHarness) -> void:
	var stream := StreamScript.new()
	stream.begin_batch("buff")
	stream.capture_buff("buff_applied", {
		"buff_id": "burn", "scope": "unit", "side": "enemy",
		"target_id": 101, "amount": 2, "state": {"stacks": 2},
	})
	stream.capture_buff("side_buff_applied", {
		"buff_id": "pieceDamageUp", "scope": "side", "side": "ally",
		"target_id": 0, "amount": 1, "state": {"stacks": 1},
	})
	var events: Array = stream.all_events()
	harness.assert_equal(events[0]["visual_target"]["kind"], "unit")
	harness.assert_equal(events[0]["visual_target"]["unit_id"], 101)
	harness.assert_equal(events[1]["visual_target"], {"kind": "side", "side": "ally"})
	_assert_envelope(harness, events[0])
	_assert_envelope(harness, events[1])


func _test_group_batch(harness: TestHarness) -> void:
	var stream := StreamScript.new()
	var batch: String = stream.begin_batch("exclusive_group")
	stream.capture_buff("buff_applied", {
		"buff_id": "march", "scope": "unit", "side": "ally",
		"target_id": 1, "amount": 1, "state": {"stacks": 1},
	})
	stream.capture_buff("buff_applied", {
		"buff_id": "march", "scope": "unit", "side": "ally",
		"target_id": 2, "amount": 1, "state": {"stacks": 1},
	})
	var events: Array = stream.all_events()
	harness.assert_equal(events[0]["batch_id"], batch)
	harness.assert_equal(events[1]["batch_id"], batch)
	harness.assert_equal(events[1]["sequence"], events[0]["sequence"] + 1)


func _test_relic_source(harness: TestHarness) -> void:
	var stream := StreamScript.new()
	stream.begin_batch("relic")
	stream.capture_damage("unit_damaged", _damage_payload("relic", "ally", "arcConductor"))
	var event: Dictionary = stream.all_events()[0]
	harness.assert_equal(event["source"]["type"], "relic")
	harness.assert_equal(event["source"]["id"], "arcConductor")
	harness.assert_equal(event["source"]["action_phase"], "effect_action")
	harness.assert_false(event["source"]["type"] in ["basic_attack", "free_skill", "exclusive_skill"])


func _test_envelope_categories(harness: TestHarness) -> void:
	var stream := StreamScript.new()
	stream.begin_batch("contract")
	stream.capture_content({"event_id": "roundStart", "payload": {"round": 2}})
	stream.capture_content({
		"event_id": "freeSkillCast",
		"payload": {
			"owner_hero_id": 0,
			"source_effect": _effect("free_skill", "ally", "pieceBlock"),
		},
	})
	stream.capture_log({"message": "ok", "class": "ok"})
	stream.capture_fatal("committed_failure", "stopped", {"fatal": true})
	var events: Array = stream.all_events()
	harness.assert_equal(_kinds(events), ["round", "card", "log", "fatal"])
	for event: Dictionary in events:
		_assert_envelope(harness, event)
	var isolated: Array = stream.pending_events()
	isolated[0]["payload"]["round"] = 99
	harness.assert_equal(stream.pending_events()[0]["payload"]["round"], 2)
	stream.acknowledge_through(events[1]["sequence"])
	harness.assert_equal(stream.pending_events().size(), 2)


static func _damage_payload(source_type: String, source_side: String, source_id: Variant) -> Dictionary:
	return {
		"target": {
			"id": 101, "slot": 1, "side": "enemy", "hp": 80.0,
		},
		"amount": 20.0,
		"effect_context": _effect(source_type, source_side, source_id),
	}


static func _effect(source_type: String, source_side: String, source_id: Variant) -> Dictionary:
	return {
		"source_type": source_type,
		"source_id": source_id,
		"source_name": "source",
		"source_side": source_side,
		"source_actor_id": source_id,
	}


static func _kinds(events: Array) -> Array:
	var result: Array = []
	for event: Dictionary in events:
		result.append(event["kind"])
	return result


func _assert_envelope(harness: TestHarness, event: Dictionary) -> void:
	for key in ["sequence", "batch_id", "event_id", "kind", "source", "visual_target", "payload"]:
		harness.assert_true(event.has(key), "missing event envelope key: %s" % key)
	var json_text := JSON.stringify(event)
	harness.assert_false(json_text.is_empty())
	var parsed: Variant = JSON.parse_string(json_text)
	harness.assert_true(typeof(parsed) == TYPE_DICTIONARY)
	if typeof(parsed) == TYPE_DICTIONARY:
		harness.assert_equal(parsed["event_id"], event["event_id"])
