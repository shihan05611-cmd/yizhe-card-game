extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const SuiteScript = preload("res://tests/retained_card_battle_integration_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	SuiteScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
