extends RefCounted

const MainScene = preload("res://scenes/main.tscn")

func run(harness: TestHarness) -> void:
	harness.run_test("Battle restart isolates old halted settled card and presentation state", func() -> void:
		var scene: Variant = MainScene.instantiate()
		scene.auto_start = false
		Engine.get_main_loop().root.add_child(scene)
		harness.assert_true(scene.start_battle())
		var old_controller: Variant = scene.controller
		var old_manager: Variant = scene.hand_manager
		var old_session: Variant = old_manager._session
		var old_hand: Variant = old_manager._runtime
		# Reproduce all stale terminal/queue flags at the restart boundary.
		old_session._halted = true
		old_session._settled = true
		old_hand._queue_busy = true
		old_hand._queue_halted = true
		scene._auto_attempted_instances["old-instance"] = true
		scene._logic_depth = 1
		scene.presentation_queue._final_view_model = {"old_run_marker":true}
		scene.presentation_queue._completed_sequences.append(99999)
		harness.assert_true(scene.restart_battle())
		harness.assert_false(is_instance_valid(old_manager))
		harness.assert_true(scene.controller != old_controller)
		harness.assert_true(scene.hand_manager._session != old_session)
		harness.assert_false(scene.hand_manager._runtime._queue_busy)
		harness.assert_false(scene.hand_manager._runtime._queue_halted)
		var vm: Dictionary = scene.controller.view_model()
		harness.assert_false(vm.session.halted)
		harness.assert_false(vm.session.settled)
		harness.assert_false(vm.battle.game_over)
		harness.assert_equal(vm.fatal,null)
		harness.assert_equal(scene._auto_attempted_instances,{})
		harness.assert_equal(scene._logic_depth,0)
		harness.assert_false(scene.presentation_queue._final_view_model.has("old_run_marker"))
		harness.assert_false(99999 in scene.presentation_queue._completed_sequences)
		scene.presentation_queue.drain_for_test()
		harness.assert_true(scene.submit_end_turn().ok,"New battle accepts a command after stale queue disposal")
		scene.free()
	)
