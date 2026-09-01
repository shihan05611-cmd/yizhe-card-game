class_name TestHarness
extends RefCounted

var tests := 0
var assertions := 0
var failures := 0

var _current_test := ""
var _failure_messages: Array[String] = []


func run_test(test_name: String, callback: Callable) -> void:
	tests += 1
	_current_test = test_name
	if not callback.is_valid():
		fail("test callback is not callable")
		_current_test = ""
		return
	callback.call()
	_current_test = ""


func assert_true(value: bool, message: String = "expected true") -> void:
	assertions += 1
	if not value:
		fail(message)


func assert_false(value: bool, message: String = "expected false") -> void:
	assertions += 1
	if value:
		fail(message)


func assert_equal(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if actual == expected:
		return
	var detail := message
	if detail.is_empty():
		detail = "expected %s, got %s" % [str(expected), str(actual)]
	fail(detail)


func assert_not_null(value: Variant, message: String = "expected a non-null value") -> void:
	assertions += 1
	if value == null:
		fail(message)


func assert_contains(text: String, fragment: String, message: String = "") -> void:
	assertions += 1
	if text.contains(fragment):
		return
	var detail := message
	if detail.is_empty():
		detail = "expected text to contain: %s" % fragment
	fail(detail)


func fail(message: String) -> void:
	failures += 1
	var label := _current_test if not _current_test.is_empty() else "runner"
	var detail := "%s: %s" % [label, message]
	_failure_messages.append(detail)
	print("FAIL: %s" % detail)


func print_summary() -> void:
	print("TEST SUMMARY: tests=%d assertions=%d failures=%d" % [tests, assertions, failures])
	for detail in _failure_messages:
		print("  - %s" % detail)
