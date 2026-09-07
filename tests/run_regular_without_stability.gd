extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const TEST_ROOT := "res://tests"
const SKIPPED_DIRECTORIES := ["support", "fixtures"]
const OMITTED_STABILITY_SUITES := ["res://tests/m2_battle_stability_test.gd"]
const FOCUSED_ONLY_SUITES := ["res://tests/auto_battle_e2e_test.gd"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	var test_scripts := _discover_test_scripts(TEST_ROOT)
	for script_path in test_scripts:
		if script_path in OMITTED_STABILITY_SUITES or script_path in FOCUSED_ONLY_SUITES:
			continue
		var suite_script := load(script_path) as Script
		if suite_script == null or not suite_script.can_instantiate():
			harness.fail("suite could not be loaded or instantiated: %s" % script_path)
			continue
		var suite: Variant = suite_script.new()
		if suite == null or not suite.has_method("run"):
			harness.fail("suite must implement run(harness): %s" % script_path)
			continue
		suite.run(harness)
	print("OMITTED BY USER REQUEST: %s" % ", ".join(OMITTED_STABILITY_SUITES))
	print("FOCUSED E2E SUITES RUN SEPARATELY: %s" % ", ".join(FOCUSED_ONLY_SUITES))
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
