extends SceneTree

const TestHarness = preload("res://tests/support/test_harness.gd")
const FormationTest = preload("res://tests/battle_board_formation_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarness.new()
	FormationTest.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
