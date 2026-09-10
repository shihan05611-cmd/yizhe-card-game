extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const SUITES := [
	preload("res://tests/free_skill_effects_test.gd"),
	preload("res://tests/card_resource_target_test.gd"),
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	for suite: Script in SUITES:
		suite.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
