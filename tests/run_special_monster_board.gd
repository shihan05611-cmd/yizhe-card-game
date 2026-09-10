extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var harness = preload("res://tests/support/test_harness.gd").new()
	preload("res://tests/special_monster_board_test.gd").new().run(harness)
	preload("res://tests/special_monster_runtime_test.gd").new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
