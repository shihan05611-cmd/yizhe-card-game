extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const AutoBattleTestScript = preload("res://tests/auto_battle_e2e_test.gd")
const SceneInstantiationTestScript = preload("res://tests/scene_instantiation_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	AutoBattleTestScript.new().run(harness)
	SceneInstantiationTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
