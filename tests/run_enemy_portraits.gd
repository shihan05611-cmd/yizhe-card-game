extends SceneTree

const Harness = preload("res://tests/support/test_harness.gd")
const PortraitTest = preload("res://tests/enemy_hero_portrait_integration_test.gd")
const SceneTest = preload("res://tests/battle_scene_test.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var harness := Harness.new()
	PortraitTest.new().run(harness)
	SceneTest.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
