extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const CombatMotionPresentationTestScript = preload("res://tests/combat_motion_presentation_test.gd")
const PieceAttackTestScript = preload("res://tests/piece_attack_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	PieceAttackTestScript.new().run(harness)
	CombatMotionPresentationTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
