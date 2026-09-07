extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const SkillFxCatalogTestScript = preload("res://tests/skill_fx_catalog_test.gd")
const SkillFxScenePlayerTestScript = preload("res://tests/skill_fx_scene_player_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	SkillFxCatalogTestScript.new().run(harness)
	SkillFxScenePlayerTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
