extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const CardCatalogTestScript = preload("res://tests/card_catalog_test.gd")
const HandManagerTestScript = preload("res://tests/hand_manager_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	CardCatalogTestScript.new().run(harness)
	HandManagerTestScript.new().run(harness)
	# HandManagerTest owns the M3 deck determinism and named-stream isolation
	# checks. Full shared RNG golden coverage belongs to regular regression only.
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
