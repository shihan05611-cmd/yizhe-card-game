extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const RunContractTestScript = preload("res://tests/m5_run_contract_test.gd")
const RunRandomTransactionTestScript = preload("res://tests/m5_run_random_transaction_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	for suite_script in [RunContractTestScript, RunRandomTransactionTestScript]:
		var suite: Variant = suite_script.new()
		suite.run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
