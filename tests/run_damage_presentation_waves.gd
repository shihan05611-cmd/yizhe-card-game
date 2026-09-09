extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const MotionPresentationTestScript = preload("res://tests/combat_motion_presentation_test.gd")
const FlameFateTestScript = preload("res://tests/hero_effects_flame_fate_test.gd")
const MarshalFistTestScript = preload("res://tests/hero_effects_marshal_fist_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	MotionPresentationTestScript.new().run(harness)
	FlameFateTestScript.new().run(harness)
	MarshalFistTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
