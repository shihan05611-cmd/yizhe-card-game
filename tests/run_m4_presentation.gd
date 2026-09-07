extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const CardQueueTestScript = preload("res://tests/card_queue_presentation_test.gd")
const IntegrationTestScript = preload("res://tests/combat_presentation_integration_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	CardQueueTestScript.new().run(harness)
	IntegrationTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
