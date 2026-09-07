extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const EVIDENCE := {
	"res://tests/artifacts/approved_m4/01_default_log_hidden.png": Vector2i(1200, 700),
	"res://tests/artifacts/approved_m4/02_log_opened.png": Vector2i(1200, 700),
	"res://tests/artifacts/approved_m4/03_hand_7.png": Vector2i(1200, 700),
	"res://tests/artifacts/approved_m4/04_hand_0.png": Vector2i(1200, 700),
	"res://tests/artifacts/approved_m4/05_hover_drag.png": Vector2i(1200, 700),
	"res://tests/artifacts/approved_m4/06_result.png": Vector2i(1200, 700),
	"res://tests/artifacts/approved_m4/07_1600x900.png": Vector2i(1600, 900),
	"res://tests/artifacts/approved_m4/08_1280x720.png": Vector2i(1280, 720),
}


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("ART evidence contains eight readable nonblank state captures", func() -> void:
		_test_images(harness)
	)
	harness.run_test("ART evidence state pairs are visually distinct", func() -> void:
		_test_state_hashes(harness)
	)
	print("ART LAYOUT GRAPHICAL SMOKE TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_images(harness: TestHarness) -> void:
	for path: String in EVIDENCE:
		var image := Image.new()
		var load_error := image.load(ProjectSettings.globalize_path(path))
		harness.assert_equal(load_error, OK, "evidence must load: %s" % path)
		if load_error != OK:
			continue
		harness.assert_equal(image.get_size(), EVIDENCE[path], "wrong evidence size: %s" % path)
		harness.assert_true(_sampled_color_count(image) >= 8, "evidence appears blank: %s" % path)


func _test_state_hashes(harness: TestHarness) -> void:
	_assert_distinct(harness, "01_default_log_hidden.png", "02_log_opened.png")
	_assert_distinct(harness, "03_hand_7.png", "04_hand_0.png")
	_assert_distinct(harness, "03_hand_7.png", "05_hover_drag.png")
	_assert_distinct(harness, "04_hand_0.png", "06_result.png")


func _assert_distinct(harness: TestHarness, left_name: String, right_name: String) -> void:
	var root_path := ProjectSettings.globalize_path("res://tests/artifacts/approved_m4")
	var left_hash := FileAccess.get_sha256(root_path.path_join(left_name))
	var right_hash := FileAccess.get_sha256(root_path.path_join(right_name))
	harness.assert_false(left_hash.is_empty(), "missing hash for %s" % left_name)
	harness.assert_false(right_hash.is_empty(), "missing hash for %s" % right_name)
	harness.assert_false(left_hash == right_hash, "captures must differ: %s and %s" % [left_name, right_name])


static func _sampled_color_count(image: Image) -> int:
	var colors := {}
	for y in range(0, image.get_height(), 20):
		for x in range(0, image.get_width(), 20):
			colors[image.get_pixel(x, y).to_html()] = true
			if colors.size() >= 8:
				return colors.size()
	return colors.size()

