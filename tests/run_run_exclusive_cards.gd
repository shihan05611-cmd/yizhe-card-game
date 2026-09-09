extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const ExclusiveCardsTestScript = preload("res://tests/run_exclusive_cards_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	ExclusiveCardsTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
