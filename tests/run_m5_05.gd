extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const RunContractTestScript = preload("res://tests/m5_run_contract_test.gd")
const RunRandomTransactionTestScript = preload("res://tests/m5_run_random_transaction_test.gd")
const MapSystemTestScript = preload("res://tests/m5_map_system_test.gd")
const RunLifecycleTestScript = preload("res://tests/m5_run_lifecycle_test.gd")
const EconomyNodesTestScript = preload("res://tests/m5_economy_nodes_test.gd")
const BattleBridgeTestScript = preload("res://tests/m5_battle_bridge_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	for suite_script in [
		RunContractTestScript,
		RunRandomTransactionTestScript,
		MapSystemTestScript,
		RunLifecycleTestScript,
		EconomyNodesTestScript,
		BattleBridgeTestScript,
	]:
		suite_script.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
