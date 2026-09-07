extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const Art3TestScript = preload("res://tests/art3_hud_log_drawer_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	Art3TestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
