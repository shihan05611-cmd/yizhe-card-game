extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const SUITES := [
	preload("res://tests/art1_responsive_battle_skeleton_test.gd"),
	preload("res://tests/art2_hand_component_test.gd"),
	preload("res://tests/art3_hud_log_drawer_test.gd"),
	preload("res://tests/art_layout_integration_test.gd"),
	preload("res://tests/art_layout_graphical_smoke_test.gd"),
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	for suite_script: Script in SUITES:
		suite_script.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
