extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const EVIDENCE_PATHS := [
	"res://tests/artifacts/m4/01_battle_ui_7_cards.png",
	"res://tests/artifacts/m4/02_card_hover.png",
	"res://tests/artifacts/m4/03_card_drag.png",
	"res://tests/artifacts/m4/04_same_action_1x.png",
	"res://tests/artifacts/m4/05_same_action_4x.png",
	"res://tests/artifacts/m4/06_battle_result.png",
]


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("M4 evidence images are readable nonblank 1200x700 captures", func() -> void:
		_test_images(harness)
	)
	print("M4-6 GRAPHICAL SMOKE TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_images(harness: TestHarness) -> void:
	for path: String in EVIDENCE_PATHS:
		var image := Image.new()
		var load_error := image.load(ProjectSettings.globalize_path(path))
		harness.assert_equal(load_error, OK, "evidence must load: %s" % path)
		if load_error != OK:
			continue
		harness.assert_equal(image.get_size(), Vector2i(1200, 700), "evidence must use frozen viewport: %s" % path)
		harness.assert_true(_sampled_color_count(image) >= 8, "evidence appears blank: %s" % path)


static func _sampled_color_count(image: Image) -> int:
	var colors := {}
	for y in range(0, image.get_height(), 20):
		for x in range(0, image.get_width(), 20):
			colors[image.get_pixel(x, y).to_html()] = true
			if colors.size() >= 8:
				return colors.size()
	return colors.size()
