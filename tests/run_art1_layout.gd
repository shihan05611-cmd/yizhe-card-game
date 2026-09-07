extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const Art1TestScript = preload("res://tests/art1_responsive_battle_skeleton_test.gd")
const BattleSceneTestScript = preload("res://tests/battle_scene_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	Art1TestScript.new().run(harness)
	BattleSceneTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
