extends RefCounted

const ArchitectureGuardScript = preload("res://tests/support/architecture_guard.gd")
const FIXTURE_ROOT := "res://tests/fixtures/architecture_violation"


func run(harness: TestHarness) -> void:
	harness.run_test("real production layers have zero architecture violations", func() -> void:
		_test_real_project(harness)
	)
	harness.run_test("violation fixture reports every expected rule", func() -> void:
		_test_violation_fixture(harness)
	)
	harness.run_test("comments strings and longer identifiers do not trigger rules", func() -> void:
		_test_safe_fixture(harness)
	)
	harness.run_test("missing roots and unreadable files fail closed", func() -> void:
		_test_scan_failures(harness)
	)


func _test_real_project(harness: TestHarness) -> void:
	var guard := ArchitectureGuardScript.new()
	var violations: Array[Dictionary] = guard.scan_production()
	print("ARCHITECTURE REAL violations=%d" % violations.size())
	for violation in violations:
		print(_format_violation(violation))
	harness.assert_equal(violations.size(), 0, "production architecture violations must be zero")


func _test_violation_fixture(harness: TestHarness) -> void:
	var guard := ArchitectureGuardScript.new()
	var violations: Array[Dictionary] = guard.scan_fixture(
		FIXTURE_ROOT.path_join("core_violations.gd.fixture"),
		"core"
	)
	violations.append_array(guard.scan_fixture(
		FIXTURE_ROOT.path_join("timer_base.gd.fixture"),
		"core"
	))
	_sort_violations(violations)
	var rule_counts := _count_rule_ids(violations)
	var expected_counts := {
		"LAYER_UPWARD_DEPENDENCY": 2,
		"PURE_FILE_IO": 2,
		"PURE_GET_TREE": 1,
		"PURE_GLOBAL_RANDOM": 2,
		"PURE_NODE_BASE": 2,
		"PURE_RANDOM_SOURCE": 1,
		"PURE_SCENE_DEPENDENCY": 1,
	}
	print(
		"ARCHITECTURE FIXTURE violations=%d rule_ids=%s" % [
			violations.size(),
			",".join(rule_counts.keys()),
		]
	)
	harness.assert_equal(violations.size(), 11)
	harness.assert_equal(rule_counts, expected_counts)
	harness.assert_true(
		_has_message_fragment(violations, "PURE_NODE_BASE", "CharacterBody2D"),
		"CharacterBody2D must be recognized through ClassDB"
	)
	harness.assert_true(
		_has_message_fragment(violations, "PURE_NODE_BASE", "Timer"),
		"Timer must be recognized through ClassDB"
	)
	harness.assert_true(
		_has_violation(violations, "LAYER_UPWARD_DEPENDENCY", 3),
		"multiline preload must report the call's starting line"
	)
	harness.assert_true(
		_has_violation(violations, "PURE_SCENE_DEPENDENCY", 6),
		"multiline scene load must report the call's starting line"
	)

	var previous_key := ""
	for violation in violations:
		harness.assert_true(violation["line"] > 0, "violation must include a positive line number")
		harness.assert_true(not violation["path"].is_empty(), "violation must include a relative path")
		harness.assert_true(not violation["message"].is_empty(), "violation must include a message")
		var current_key := _sort_key(violation)
		harness.assert_true(previous_key <= current_key, "violations must use stable sort order")
		previous_key = current_key


func _test_safe_fixture(harness: TestHarness) -> void:
	var guard := ArchitectureGuardScript.new()
	var violations: Array[Dictionary] = guard.scan_fixture(
		FIXTURE_ROOT.path_join("safe_text.gd.fixture"),
		"core"
	)
	print("ARCHITECTURE SAFE_FIXTURE violations=%d" % violations.size())
	for violation in violations:
		print(_format_violation(violation))
	harness.assert_equal(violations.size(), 0, "non-code text and longer identifiers must not trigger rules")


func _test_scan_failures(harness: TestHarness) -> void:
	var guard := ArchitectureGuardScript.new()
	var missing_root_violations: Array[Dictionary] = guard.scan_production(
		FIXTURE_ROOT.path_join("missing_project"),
		["core"]
	)
	var missing_file_violations: Array[Dictionary] = guard.scan_file(
		FIXTURE_ROOT.path_join("missing_script.gd"),
		"core/missing_script.gd",
		"core"
	)
	var violations := missing_root_violations + missing_file_violations
	_sort_violations(violations)
	var rule_counts := _count_rule_ids(violations)
	print(
		"ARCHITECTURE SCAN_FAILURE violations=%d rule_ids=%s" % [
			violations.size(),
			",".join(rule_counts.keys()),
		]
	)
	harness.assert_equal(violations.size(), 2)
	harness.assert_equal(rule_counts, {
		"SCAN_FILE_UNREADABLE": 1,
		"SCAN_ROOT_UNREADABLE": 1,
	})
	for violation in violations:
		harness.assert_equal(violation["line"], 1)
		harness.assert_true(not violation["path"].is_empty())
		harness.assert_true(not violation["message"].is_empty())


func _count_rule_ids(violations: Array[Dictionary]) -> Dictionary:
	var counts := {}
	for violation in violations:
		var rule_id: String = violation["rule_id"]
		counts[rule_id] = counts.get(rule_id, 0) + 1
	var sorted_counts := {}
	var rule_ids := counts.keys()
	rule_ids.sort()
	for rule_id in rule_ids:
		sorted_counts[rule_id] = counts[rule_id]
	return sorted_counts


func _sort_key(violation: Dictionary) -> String:
	return "%s|%09d|%s|%s" % [
		violation["path"],
		violation["line"],
		violation["rule_id"],
		violation["message"],
	]


func _sort_violations(violations: Array[Dictionary]) -> void:
	violations.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _sort_key(left) < _sort_key(right)
	)


func _has_violation(violations: Array[Dictionary], rule_id: String, line_number: int) -> bool:
	for violation in violations:
		if violation["rule_id"] == rule_id and violation["line"] == line_number:
			return true
	return false


func _has_message_fragment(
	violations: Array[Dictionary],
	rule_id: String,
	fragment: String,
) -> bool:
	for violation in violations:
		if violation["rule_id"] == rule_id and violation["message"].contains(fragment):
			return true
	return false


func _format_violation(violation: Dictionary) -> String:
	return "%s:%d [%s] %s" % [
		violation["path"],
		violation["line"],
		violation["rule_id"],
		violation["message"],
	]
