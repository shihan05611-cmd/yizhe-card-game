extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const BattleViewModelTestScript = preload("res://tests/battle_view_model_test.gd")
const CombatPresentationEventTestScript = preload("res://tests/combat_presentation_event_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	BattleViewModelTestScript.new().run(harness)
	CombatPresentationEventTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
