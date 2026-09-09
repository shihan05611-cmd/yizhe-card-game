extends SceneTree

const HarnessScript = preload("res://tests/support/test_harness.gd")
const SuiteScript = preload("res://tests/hero_status_view_model_test.gd")

func _init() -> void:
	var harness := HarnessScript.new()
	SuiteScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
