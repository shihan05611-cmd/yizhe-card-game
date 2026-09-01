extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const TEST_ROOT := "res://tests"
const SKIPPED_DIRECTORIES := ["support", "fixtures"]
const SELF_TEST_FAILURE_ARGUMENT := "--self-test-failure"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	var test_scripts := _discover_test_scripts(TEST_ROOT)
	if test_scripts.is_empty():
		harness.fail("no *_test.gd suites discovered under %s" % TEST_ROOT)

	for script_path in test_scripts:
		_run_suite(script_path, harness)

	if SELF_TEST_FAILURE_ARGUMENT in OS.get_cmdline_user_args():
		harness.run_test("runner self-test failure", func() -> void:
			harness.assert_true(false, "intentional runner self-test failure")
		)

	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)


func _discover_test_scripts(directory_path: String) -> Array[String]:
	var discovered: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return discovered

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var entry_path := directory_path.path_join(entry)
			if directory.current_is_dir():
				if entry not in SKIPPED_DIRECTORIES:
					discovered.append_array(_discover_test_scripts(entry_path))
			elif entry.ends_with("_test.gd"):
				discovered.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
	discovered.sort()
	return discovered


func _run_suite(script_path: String, harness: TestHarness) -> void:
	var suite_script := load(script_path)
	if suite_script == null:
		harness.fail("could not load suite %s" % script_path)
		return
	var suite: Variant = suite_script.new()
	if suite == null or not suite.has_method("run"):
		harness.fail("suite must implement run(harness): %s" % script_path)
		return
	suite.run(harness)
