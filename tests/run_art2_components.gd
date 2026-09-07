extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const Art2TestScript = preload("res://tests/art2_hand_component_test.gd")
const HandUiTestScript = preload("res://tests/hand_ui_test.gd")
const BattleSceneTestScript = preload("res://tests/battle_scene_test.gd")
const Art1TestScript = preload("res://tests/art1_responsive_battle_skeleton_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	Art2TestScript.new().run(harness)
	HandUiTestScript.new().run(harness)
	BattleSceneTestScript.new().run(harness)
	Art1TestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)

