extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const CardPlayFlowTestScript = preload("res://tests/card_play_flow_test.gd")
const PieceReactionsTestScript = preload("res://tests/piece_reactions_test.gd")
const BattleBridgeTestScript = preload("res://tests/m5_battle_bridge_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	CardPlayFlowTestScript.new().run(harness)
	PieceReactionsTestScript.new().run(harness)
	BattleBridgeTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
