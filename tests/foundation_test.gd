extends RefCounted

const InvariantScript = preload("res://core/invariant.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("foundation directories and project configuration", func() -> void:
		_test_project_contract(harness)
	)
	harness.run_test("autoload boundaries are registered and parseable", func() -> void:
		_test_autoload_boundaries(harness)
	)
	harness.run_test("debug logger records stable in-memory entries", func() -> void:
		_test_debug_logger(harness)
	)
	harness.run_test("invariant success path", func() -> void:
		harness.assert_true(
			InvariantScript.require(true, "foundation success-path contract"),
			"a satisfied invariant must return true"
		)
	)


func _test_project_contract(harness: TestHarness) -> void:
	for directory_name in ["data", "core", "systems", "app", "ui", "autoload", "tests"]:
		harness.assert_true(
			DirAccess.open("res://%s" % directory_name) != null,
			"required directory is missing: res://%s" % directory_name
		)

	var project_file := FileAccess.open("res://project.godot", FileAccess.READ)
	harness.assert_not_null(project_file, "project.godot must be readable")
	if project_file == null:
		return
	var project_text := project_file.get_as_text()
	for expected_fragment in [
		"config/features=PackedStringArray(\"4.7\", \"GL Compatibility\")",
		"window/size/viewport_width=1200",
		"window/size/viewport_height=700",
		"window/stretch/mode=\"canvas_items\"",
		"window/stretch/aspect=\"expand\"",
		"left_click={",
		"right_click={",
		"toggle_combat_log={",
	]:
		harness.assert_contains(project_text, expected_fragment)

	var autoload_section := project_text.get_slice("[autoload]", 1).get_slice("[display]", 0)
	for singleton_name in ["Signals", "GameRoot", "RunState", "HandManager", "DebugLogger"]:
		harness.assert_contains(
			autoload_section,
			"%s=\"*res://autoload/" % singleton_name,
			"project.godot must register autoload: %s" % singleton_name
		)
	harness.assert_equal(
		autoload_section.count("=\"*res://autoload/"),
		5,
		"project.godot must register exactly the five M0 autoloads"
	)

	var input_section := project_text.get_slice("[input]", 1).get_slice("[physics]", 0)
	harness.assert_equal(
		input_section.count("\"deadzone\":"),
		3,
		"project.godot must define the two M0 mouse actions and ART log toggle"
	)
	harness.assert_false(input_section.contains("end_turn"), "gameplay actions do not belong to M0")


func _test_autoload_boundaries(harness: TestHarness) -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	harness.assert_not_null(scene_tree, "tests must run inside a SceneTree")
	if scene_tree == null:
		return

	for singleton_name in ["Signals", "GameRoot", "RunState", "HandManager", "DebugLogger"]:
		harness.assert_true(
			scene_tree.root.has_node(singleton_name),
			"autoload is not registered: %s" % singleton_name
		)

	for script_path in [
		"res://autoload/signals.gd",
		"res://autoload/game_root.gd",
		"res://autoload/run_state.gd",
		"res://autoload/hand_manager.gd",
		"res://autoload/debug_logger.gd",
	]:
		var boundary_script := load(script_path)
		harness.assert_not_null(boundary_script, "autoload script must parse: %s" % script_path)
		if boundary_script != null:
			var instance: Variant = boundary_script.new()
			harness.assert_true(instance is Node, "autoload boundary must extend Node: %s" % script_path)
			instance.free()


func _test_debug_logger(harness: TestHarness) -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var logger: Node = scene_tree.root.get_node("DebugLogger")
	logger.call("clear")

	harness.assert_true(logger.call("info", "foundation ready", {"milestone": "M0"}))
	harness.assert_true(logger.call("warning", "foundation warning path"))
	harness.assert_true(logger.call("error", "foundation error path"))
	var records: Array = logger.call("get_records")
	harness.assert_equal(records.size(), 3)
	harness.assert_equal(records[0]["severity"], "info")
	harness.assert_equal(records[0]["message"], "foundation ready")
	harness.assert_equal(records[0]["context"], {"milestone": "M0"})
	harness.assert_equal(records[1]["severity"], "warning")
	harness.assert_equal(records[2]["severity"], "error")

	harness.assert_false(
		logger.call("log_message", "fatal", "unsupported severity"),
		"unknown severity must be rejected"
	)
	harness.assert_equal(
		logger.call("get_records").size(),
		3,
		"rejected input must not mutate logger state"
	)
