extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const TEST_ROOT := "res://tests"
const SKIPPED_DIRECTORIES := ["support", "fixtures"]
const SELF_TEST_FAILURE_ARGUMENT := "--self-test-failure"
const SELF_TEST_COMPILE_FAILURE_ARGUMENT := "--self-test-compile-failure"
const COMPILE_FAILURE_FIXTURE := "res://tests/fixtures/runner_compile_failure/compile_failure_suite.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	var user_arguments := OS.get_cmdline_user_args()
	var test_scripts := _discover_test_scripts(TEST_ROOT)
	if test_scripts.is_empty():
		harness.fail("no *_test.gd suites discovered under %s" % TEST_ROOT)

	for script_path in test_scripts:
		_run_suite(script_path, harness)

	if SELF_TEST_FAILURE_ARGUMENT in user_arguments:
		harness.run_test("runner self-test failure", func() -> void:
			harness.assert_true(false, "intentional runner self-test failure")
		)
	if SELF_TEST_COMPILE_FAILURE_ARGUMENT in user_arguments:
		harness.run_test("runner compile failure self-test", func() -> void:
			_run_suite(COMPILE_FAILURE_FIXTURE, harness)
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
	var suite_script := load(script_path) as Script
	if suite_script == null:
		harness.fail("could not load suite %s" % script_path)
		return
	var reload_error: Error = suite_script.reload()
	if reload_error != OK:
		harness.fail("suite script compilation failed (%s): %s" % [error_string(reload_error), script_path])
		return
	if not suite_script.can_instantiate():
		harness.fail("suite script could not be instantiated: %s" % script_path)
		return
	var invalid_dependency := _find_uninstantiable_dependency(suite_script, {})
	if not invalid_dependency.is_empty():
		harness.fail("suite dependency could not be instantiated (compilation failure): %s (suite: %s)" % [invalid_dependency, script_path])
		return
	var suite: Variant = suite_script.new()
	if suite == null or not suite.has_method("run"):
		harness.fail("suite must implement run(harness): %s" % script_path)
		return
	suite.run(harness)


func _find_uninstantiable_dependency(script: Script, visited: Dictionary) -> String:
	var instance_id := script.get_instance_id()
	if visited.has(instance_id):
		return ""
	visited[instance_id] = true

	var base_script := script.get_base_script()
	if base_script != null:
		var invalid_base := _find_uninstantiable_script_value(base_script, visited)
		if not invalid_base.is_empty():
			return invalid_base

	for constant_value: Variant in script.get_script_constant_map().values():
		var invalid_dependency := _find_uninstantiable_script_value(constant_value, visited)
		if not invalid_dependency.is_empty():
			return invalid_dependency
	return ""


func _find_uninstantiable_script_value(value: Variant, visited: Dictionary) -> String:
	if value is Script:
		var dependency := value as Script
		if not dependency.can_instantiate() and not dependency.is_abstract():
			return dependency.resource_path
		return _find_uninstantiable_dependency(dependency, visited)
	if value is Array:
		for item: Variant in value:
			var invalid_array_item := _find_uninstantiable_script_value(item, visited)
			if not invalid_array_item.is_empty():
				return invalid_array_item
	if value is Dictionary:
		for item: Variant in value.keys():
			var invalid_dictionary_key := _find_uninstantiable_script_value(item, visited)
			if not invalid_dictionary_key.is_empty():
				return invalid_dictionary_key
		for item: Variant in value.values():
			var invalid_dictionary_value := _find_uninstantiable_script_value(item, visited)
			if not invalid_dictionary_value.is_empty():
				return invalid_dictionary_value
	return ""
