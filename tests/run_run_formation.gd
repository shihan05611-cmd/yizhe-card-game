extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const FormationTestScript = preload("res://tests/run_formation_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	FormationTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
