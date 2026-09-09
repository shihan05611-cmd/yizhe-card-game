extends SceneTree

const Harness = preload("res://tests/support/test_harness.gd")
const OutcomeTest = preload("res://tests/battle_outcome_test.gd")
const SceneTest = preload("res://tests/battle_scene_test.gd")
const Slot = preload("res://scenes/battle/piece_slot.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var harness := Harness.new()
	OutcomeTest.new().run(harness)
	SceneTest.new().run(harness)
	harness.run_test("summon identity overrides ordinary class artwork and rebinding clears it", func() -> void:
		var slot := Slot.instantiate()
		root.add_child(slot)
		var unit := {"id":1,"slot":1,"class_id":"shield","class_name":"傀儡","is_puppet":true,"side":"enemy","alive":true,"hp":100,"max_hp":100,"buffs":[]}
		slot.bind_slot(unit)
		harness.assert_equal(slot.chess_art.kind, "puppet")
		harness.assert_true(slot.chess_art.enemy)
		unit["is_puppet"] = false
		unit["side"] = "ally"
		slot.bind_slot(unit)
		harness.assert_equal(slot.chess_art.kind, "shield")
		harness.assert_false(slot.chess_art.enemy)
		slot.free()
	)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
