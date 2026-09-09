extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")

const FORMAL_VISIBLE_SCENES := [
	"res://scenes/run.tscn",
	"res://scenes/main.tscn",
	"res://scenes/battle/battle_screen.tscn",
	"res://scenes/battle/board_grid.tscn",
	"res://scenes/battle/piece_slot.tscn",
	"res://scenes/battle/hero_energy_item.tscn",
	"res://scenes/cards/hand_view.tscn",
	"res://scenes/cards/card_view.tscn",
	"res://scenes/effects/damage_float.tscn",
	"res://scenes/effects/heal_float.tscn",
	"res://scenes/effects/combat_marker.tscn",
	"res://scenes/effects/skill_fx_player.tscn",
	"res://scenes/effects/fx_instance.tscn",
]

const SCRIPT_ROOTS := ["res://app", "res://ui/battle", "res://ui/cards", "res://ui/effects"]
const APPROVED_DRAW_SCRIPTS := ["res://ui/effects/burn_aura.gd", "res://ui/effects/fx_primitive.gd"]
const APPROVED_RUNTIME_CONTROL_SCRIPTS := ["res://ui/cards/pending_card_queue.gd"]


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("project main and all formal dynamic visuals instantiate PackedScenes", func() -> void:
		_test_formal_scene_instantiation(harness)
	)
	harness.run_test("formal presentation scripts do not draw or assemble Control trees", func() -> void:
		_test_no_immediate_rendering(harness)
	)
	print("M4-6 SCENE INSTANTIATION TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_formal_scene_instantiation(harness: TestHarness) -> void:
	harness.assert_equal(
		str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"res://scenes/run.tscn",
	)
	for scene_path: String in FORMAL_VISIBLE_SCENES:
		var resource: Resource = load(scene_path)
		harness.assert_true(resource is PackedScene, "expected PackedScene: %s" % scene_path)
		if resource is not PackedScene:
			continue
		var node: Node = (resource as PackedScene).instantiate()
		harness.assert_not_null(node, "scene should instantiate: %s" % scene_path)
		if node != null:
			node.free()


func _test_no_immediate_rendering(harness: TestHarness) -> void:
	var scripts: Array[String] = []
	for root: String in SCRIPT_ROOTS:
		scripts.append_array(_gd_scripts(root))
	harness.assert_true(scripts.size() >= 10, "guard should inspect the production presentation scripts")
	for script_path: String in scripts:
		var source := FileAccess.get_file_as_string(script_path)
		if script_path in APPROVED_DRAW_SCRIPTS:
			continue
		if script_path in APPROVED_RUNTIME_CONTROL_SCRIPTS:
			continue
		harness.assert_false(source.contains("func _draw("), "immediate _draw forbidden: %s" % script_path)
		harness.assert_false(source.contains("draw_"), "draw_* forbidden: %s" % script_path)
		harness.assert_false(source.contains("Control.new("), "Control.new tree assembly forbidden: %s" % script_path)
		harness.assert_false(source.contains("Label.new("), "Label.new tree assembly forbidden: %s" % script_path)


static func _gd_scripts(directory_path: String) -> Array[String]:
	var discovered: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return discovered
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var path := directory_path.path_join(entry)
			if directory.current_is_dir():
				discovered.append_array(_gd_scripts(path))
			elif entry.ends_with(".gd"):
				discovered.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	discovered.sort()
	return discovered
