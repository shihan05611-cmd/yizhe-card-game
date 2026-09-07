extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const SUITES := [
	preload("res://tests/battle_view_model_test.gd"),
	preload("res://tests/combat_presentation_event_test.gd"),
	preload("res://tests/battle_scene_test.gd"),
	preload("res://tests/hand_ui_test.gd"),
	preload("res://tests/skill_fx_catalog_test.gd"),
	preload("res://tests/skill_fx_scene_player_test.gd"),
	preload("res://tests/card_queue_presentation_test.gd"),
	preload("res://tests/combat_presentation_integration_test.gd"),
	preload("res://tests/auto_battle_e2e_test.gd"),
	preload("res://tests/scene_instantiation_test.gd"),
	preload("res://tests/m4_graphical_smoke_test.gd"),
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	var skip_e2e := "--skip-e2e" in OS.get_cmdline_user_args()
	for suite_script: Script in SUITES:
		if skip_e2e and suite_script.resource_path == "res://tests/auto_battle_e2e_test.gd":
			print("M4 RUNNER INCREMENTAL SKIP: auto_battle_e2e_test.gd (run separately in this evidence cycle)")
			continue
		suite_script.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
