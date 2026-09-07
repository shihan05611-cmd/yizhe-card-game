extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const DamagePipelineScript = preload("res://core/damage.gd")
const DeterministicRngScript = preload("res://core/rng.gd")

const FIXTURE_PATH := "res://tests/fixtures/web_m2_damage_golden.json"
const EXPECTED_CASE_ORDER := [
	"direct_plain",
	"direct_crit",
	"direct_block",
	"direct_crit_block_order",
	"direct_lethal",
	"delayed_forces_no_rng",
]


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	var fixture := _load_fixture(harness)
	if fixture.is_empty():
		return
	harness.run_test("Web M2 damage golden provenance schema and coverage are closed", func() -> void:
		_test_fixture_contract(harness, fixture)
	)
	harness.run_test("real DamagePipeline and M0 combat stream exactly replay every Web case", func() -> void:
		_test_replay(harness, fixture)
	)
	print("B4-4A M2 DAMAGE GOLDEN TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _load_fixture(harness: TestHarness) -> Dictionary:
	var fixture_text := FileAccess.get_file_as_string(FIXTURE_PATH)
	if fixture_text.is_empty():
		harness.run_test("Web M2 damage fixture is readable", func() -> void:
			harness.assert_true(false, "missing or empty fixture: %s" % FIXTURE_PATH)
		)
		return {}
	var parsed: Variant = JSON.parse_string(fixture_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		harness.run_test("Web M2 damage fixture is valid JSON", func() -> void:
			harness.assert_true(false, "fixture root must be a JSON object")
		)
		return {}
	return parsed


func _test_fixture_contract(harness: TestHarness, fixture: Dictionary) -> void:
	harness.assert_equal(fixture.keys(), [
		"schema_version", "fixture_id", "authoritative_modules",
		"authoritative_sha256", "root_seed", "rng_stream", "format_policy",
		"case_count", "case_order", "cases",
	])
	harness.assert_equal(fixture["schema_version"], 1.0)
	harness.assert_equal(fixture["fixture_id"], "web-m2-damage-golden-v1")
	harness.assert_equal(fixture["root_seed"], "M2-DAMAGE-GOLDEN-v1")
	harness.assert_equal(fixture["rng_stream"], "combat")
	harness.assert_equal(fixture["case_count"], 6.0)
	harness.assert_equal(fixture["case_order"], EXPECTED_CASE_ORDER)
	harness.assert_equal(fixture["cases"].size(), EXPECTED_CASE_ORDER.size())
	harness.assert_equal(fixture["authoritative_modules"], {
		"damage": "scripts/core/damage.js",
		"contexts": "scripts/core/contexts.js",
		"random": "scripts/core/random.js",
	})
	for module_id: String in ["damage", "contexts", "random"]:
		var module_path: String = fixture["authoritative_modules"][module_id]
		harness.assert_false(module_path.contains(":"), "fixture must not contain a Windows absolute path")
		harness.assert_false(module_path.begins_with("/"), "fixture must not contain an absolute path")
		harness.assert_equal(fixture["authoritative_sha256"][module_id].length(), 64)

	var ids: Array = []
	var coverage: Array = []
	for case: Dictionary in fixture["cases"]:
		harness.assert_equal(case.keys(), ["id", "coverage", "input", "expected"])
		harness.assert_false(case["id"] in ids, "duplicate golden case id: %s" % case["id"])
		ids.append(case["id"])
		for tag: Variant in case["coverage"]:
			if tag not in coverage:
				coverage.append(tag)
	harness.assert_equal(ids, EXPECTED_CASE_ORDER)
	for required_tag: String in [
		"plain", "crit", "block", "crit_then_block_rng_order", "lethal",
		"death_context", "delayed", "forced_no_crit", "forced_no_block", "no_rng",
	]:
		harness.assert_true(required_tag in coverage, "missing coverage tag: %s" % required_tag)

	var by_id := _cases_by_id(fixture["cases"])
	harness.assert_true(by_id["direct_crit"]["expected"]["result"]["crit"])
	harness.assert_true(by_id["direct_block"]["expected"]["result"]["blocked"])
	harness.assert_true(by_id["direct_crit_block_order"]["expected"]["result"]["crit"])
	harness.assert_true(by_id["direct_crit_block_order"]["expected"]["result"]["blocked"])
	harness.assert_equal(by_id["direct_crit_block_order"]["expected"]["rng_trace"].size(), 2)
	harness.assert_true(by_id["direct_lethal"]["expected"]["result"]["died"])
	harness.assert_not_null(by_id["direct_lethal"]["expected"]["result"]["death_context"])
	harness.assert_false(by_id["direct_lethal"]["expected"]["target_after"]["alive"])
	var death_callbacks: Array = by_id["direct_lethal"]["expected"]["callback_trace"].filter(
		func(entry: Dictionary) -> bool: return entry["op"] == "death"
	)
	harness.assert_equal(death_callbacks.size(), 1)
	if death_callbacks.size() == 1:
		var death_callback: Dictionary = death_callbacks[0]
		harness.assert_equal(
			death_callback.keys(), ["op", "target", "death_context", "payload"]
		)
		harness.assert_equal(
			death_callback["target"], by_id["direct_lethal"]["expected"]["target_after"]
		)
		harness.assert_equal(
			death_callback["death_context"],
			by_id["direct_lethal"]["expected"]["result"]["death_context"],
		)
		harness.assert_equal(death_callback["payload"].keys(), [
			"target", "old_hp", "damage_context", "effect_context",
			"death_context", "metadata",
		])
	harness.assert_true(by_id["delayed_forces_no_rng"]["input"]["context"]["can_crit"])
	harness.assert_true(by_id["delayed_forces_no_rng"]["input"]["context"]["can_block"])
	harness.assert_false(by_id["delayed_forces_no_rng"]["expected"]["result"]["damage_context"]["can_crit"])
	harness.assert_false(by_id["delayed_forces_no_rng"]["expected"]["result"]["damage_context"]["can_block"])
	harness.assert_equal(by_id["delayed_forces_no_rng"]["expected"]["rng_trace"], [])


func _test_replay(harness: TestHarness, fixture: Dictionary) -> void:
	var streams: Dictionary = DeterministicRngScript.create_named_streams(
		fixture["root_seed"], [fixture["rng_stream"]]
	)
	harness.assert_true(streams.has("combat"))
	var combat: Variant = streams["combat"]
	harness.assert_true(combat.get_script() == DeterministicRngScript)
	var draw_counter := {"global": 0}
	for case: Dictionary in fixture["cases"]:
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var target: Dictionary = input["target"].duplicate(true)
		var rng_trace: Array = []
		var callback_trace: Array = []
		var event_trace: Array = []
		var recorded := {"value": null}
		var case_draw := {"value": 0}
		var pipeline_errors: Array[String] = []
		var pipeline := DamagePipelineScript.new({
			"random": func() -> float:
				var value: float = combat.next()
				rng_trace.append({
					"global_index": float(draw_counter["global"]),
					"case_index": float(case_draw["value"]),
					"value": value,
				})
				callback_trace.append({"op": "rng", "value": value})
				draw_counter["global"] += 1
				case_draw["value"] += 1
				return value,
			"format": func(value: float) -> float:
				var formatted := maxf(0.0, roundf(value * 10.0) / 10.0)
				callback_trace.append({"op": "format", "input": value, "output": formatted})
				return formatted,
			"get_block_rate": func(unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
				var value := float(unit["base_block_rate"])
				callback_trace.append({"op": "get_block_rate", "value": value})
				return value,
			"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, metadata: Dictionary) -> float:
				var value := float(metadata["damage_multiplier"])
				callback_trace.append({"op": "get_damage_multiplier", "value": value})
				return value,
			"on_event": func(type: String, payload: Dictionary) -> void:
				callback_trace.append({"op": "event", "type": type})
				event_trace.append(_normalize_event(type, payload)),
			"on_death": func(unit: Dictionary, context: Dictionary, payload: Dictionary) -> void:
				callback_trace.append({
					"op": "death",
					"target": _normalize_target(unit),
					"death_context": context.duplicate(true),
					"payload": _normalize_death_payload(payload),
				}),
			"record_damage": func(payload: Dictionary) -> void:
				callback_trace.append({"op": "record"})
				recorded["value"] = _normalize_damage_payload(payload),
		}, pipeline_errors)
		harness.assert_true(pipeline_errors.is_empty(), "%s: %s" % [case["id"], str(pipeline_errors)])
		harness.assert_true(pipeline.is_valid(), "%s: invalid real DamagePipeline" % case["id"])
		var errors: Array[String] = []
		var result: Dictionary = pipeline.apply(
			target, input["context"], input["metadata"], errors
		)
		harness.assert_true(errors.is_empty(), "%s: %s" % [case["id"], str(errors)])
		harness.assert_equal(result, expected["result"], "%s result mismatch" % case["id"])
		harness.assert_equal(target, expected["target_after"], "%s target mismatch" % case["id"])
		harness.assert_equal(recorded["value"], expected["record"], "%s record mismatch" % case["id"])
		harness.assert_equal(event_trace, expected["event_trace"], "%s event trace mismatch" % case["id"])
		harness.assert_equal(
			rng_trace, expected["rng_trace"],
			"%s RNG trace mismatch expected=%s actual=%s"
			% [case["id"], str(expected["rng_trace"]), str(rng_trace)],
		)
		harness.assert_equal(callback_trace, expected["callback_trace"], "%s callback trace mismatch" % case["id"])


func _normalize_damage_payload(payload: Dictionary) -> Dictionary:
	return {
		"amount": payload["amount"],
		"calculated_amount": payload["calculated_amount"],
		"blocked": payload["blocked"],
		"crit": payload["crit"],
		"died": payload["died"],
		"old_hp": payload["old_hp"],
		"new_hp": payload["new_hp"],
		"raw_amount_before_block": payload["raw_amount_before_block"],
		"damage_context": payload["damage_context"].duplicate(true),
		"death_context": null,
	}


func _normalize_death_payload(payload: Dictionary) -> Dictionary:
	return {
		"target": _normalize_target(payload["unit"]),
		"old_hp": payload["old_hp"],
		"damage_context": payload["damage_context"].duplicate(true),
		"effect_context": payload["effect_context"].duplicate(true),
		"death_context": payload["death_context"].duplicate(true),
		"metadata": payload["metadata"].duplicate(true),
	}


func _normalize_target(target: Dictionary) -> Dictionary:
	return {
		"id": target["id"],
		"side": target["side"],
		"hp": target["hp"],
		"max_hp": target["max_hp"],
		"alive": target["alive"],
		"hp_threshold_crossed": target["hp_threshold_crossed"],
		"base_block_rate": target["base_block_rate"],
	}


func _normalize_event(type: String, payload: Dictionary) -> Dictionary:
	return {
		"type": type,
		"amount": payload.get("amount"),
		"calculated_amount": payload.get("calculated_amount"),
		"blocked": payload.get("blocked"),
		"crit": payload.get("crit"),
		"died": payload.get("died"),
		"old_hp": payload.get("old_hp"),
		"new_hp": payload.get("new_hp"),
		"raw_amount_before_block": payload.get("raw_amount_before_block"),
		"damage_context": (
			payload["damage_context"].duplicate(true) if payload.has("damage_context") else null
		),
		"death_context": (
			payload["death_context"].duplicate(true) if payload.has("death_context") else null
		),
	}


func _cases_by_id(cases: Array) -> Dictionary:
	var result := {}
	for case: Dictionary in cases:
		result[case["id"]] = case
	return result
