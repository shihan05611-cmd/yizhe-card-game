extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const MainScene: PackedScene = preload("res://scenes/main.tscn")


func run(harness: TestHarness) -> void:
	var before_tests := harness.tests
	var before_assertions := harness.assertions
	var before_failures := harness.failures
	harness.run_test("auto battle serially reaches one terminal result at 1x and 4x", func() -> void:
		_test_speed_equivalent_auto_battles(harness)
	)
	harness.run_test("return-to-hand auto policy advances and cannot loop one card forever", func() -> void:
		_test_return_to_hand_progress(harness)
	)
	harness.run_test("terminal result requires and honors explicit overlay restart", func() -> void:
		_test_explicit_restart(harness)
	)
	print("M4-6 AUTO BATTLE E2E TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - before_tests,
		harness.assertions - before_assertions,
		harness.failures - before_failures,
	])


func _test_speed_equivalent_auto_battles(harness: TestHarness) -> void:
	var one: Variant = _root("m4-auto-speed")
	var four: Variant = _root("m4-auto-speed")
	one.presentation_queue.drain_for_test()
	four.presentation_queue.drain_for_test()
	for speed in [1.0, 2.0, 3.0, 4.0]:
		harness.assert_true(one.set_presentation_speed(speed), "speed option should be accepted: %s" % speed)
	one.set_presentation_speed(1.0)
	four.set_presentation_speed(4.0)
	var run_one: Dictionary = one.drive_auto_for_test(256)
	var run_four: Dictionary = four.drive_auto_for_test(256)
	harness.assert_true(run_one["complete"], str(run_one))
	harness.assert_true(run_four["complete"], str(run_four))
	harness.assert_true(run_one["commands"] > 0)
	harness.assert_equal(run_one["commands"], run_four["commands"])
	harness.assert_equal(one.max_logic_depth(), 1)
	harness.assert_equal(four.max_logic_depth(), 1)
	var vm_one: Dictionary = one.controller.view_model()
	var vm_four: Dictionary = four.controller.view_model()
	harness.assert_true(vm_one["battle"]["result"] in ["win", "lose"])
	harness.assert_equal(vm_one["battle"]["result"], vm_four["battle"]["result"])
	harness.assert_false(vm_one["presentation"]["auto_battle"])
	harness.assert_false(vm_four["presentation"]["auto_battle"])
	harness.assert_equal(_logic_vm(vm_one), _logic_vm(vm_four))
	var events_one: Array = one.controller.presentation_events()
	var events_four: Array = four.controller.presentation_events()
	harness.assert_equal(events_one, events_four)
	_assert_strict_sequences(harness, events_four)
	var duration_one := float(run_one["presentation_seconds"])
	var duration_four := float(run_four["presentation_seconds"])
	harness.assert_true(duration_four > 0.0)
	var ratio := duration_one / duration_four if duration_four > 0.0 else 0.0
	print("M4-6 AUTO SPEED: 1x=%.3fs 4x=%.3fs ratio=%.3f commands=%d events=%d" % [
		duration_one, duration_four, ratio, run_one["commands"], events_one.size(),
	])
	harness.assert_true(ratio >= 3.9 and ratio <= 4.1, "expected ~4:1 full-battle duration, got %.3f" % ratio)
	one.free()
	four.free()


func _test_return_to_hand_progress(harness: TestHarness) -> void:
	var root: Variant = _root("m4-auto-shadow", [9], [])
	root.presentation_queue.drain_for_test()
	root.set_presentation_speed(4.0)
	var before_round := int(root.controller.view_model()["battle"]["round"])
	var progress: Dictionary = root.drive_auto_for_test(2)
	harness.assert_false(progress["complete"], "two-command probe intentionally stops before battle end")
	harness.assert_equal(progress["commands"], 2)
	harness.assert_true(
		int(root.controller.view_model()["battle"]["round"]) > before_round,
		"after one returned-card attempt, auto must end the round instead of replaying forever",
	)
	harness.assert_equal(root.max_logic_depth(), 1)
	root.free()


func _test_explicit_restart(harness: TestHarness) -> void:
	var root: Variant = _root("m4-auto-restart")
	root.presentation_queue.drain_for_test()
	root.set_presentation_speed(4.0)
	var completed: Dictionary = root.drive_auto_for_test(256)
	harness.assert_true(completed["complete"], str(completed))
	var old_controller: Variant = root.controller
	harness.assert_true(root.battle_screen.result_overlay.visible)
	root.battle_screen.result_overlay.restart_button.pressed.emit()
	harness.assert_false(root.controller == old_controller)
	harness.assert_true(root.presentation_queue.is_busy(), "restart must enqueue the new battleStart presentation")
	root.presentation_queue.drain_for_test()
	var restarted: Dictionary = root.controller.view_model()
	harness.assert_equal(restarted["battle"]["round"], 1)
	harness.assert_equal(restarted["battle"]["result"], null)
	harness.assert_false(restarted["battle"]["game_over"])
	harness.assert_false(root.battle_screen.result_overlay.visible)
	harness.assert_equal(_event_count(root.controller.presentation_events(), "battleStart"), 1)
	root.free()


func _root(seed: String, heroes: Array[int] = [1], skills: Array[String] = [
	"pieceBlock", "pieceDamageUp", "markBurn", "executeStrike",
]) -> Variant:
	var root: Variant = MainScene.instantiate()
	root.battle_seed = seed
	root.deployed_hero_ids = heroes.duplicate()
	root.free_skill_ids = skills.duplicate()
	Engine.get_main_loop().root.add_child(root)
	return root


static func _logic_vm(vm: Dictionary) -> Dictionary:
	var copy := vm.duplicate(true)
	copy.erase("presentation")
	return copy


static func _event_count(events: Array, event_id: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if event.get("event_id") == event_id:
			count += 1
	return count


static func _assert_strict_sequences(harness: TestHarness, events: Array) -> void:
	var previous := 0
	var seen := {}
	for event: Dictionary in events:
		var sequence := int(event.get("sequence", 0))
		harness.assert_true(sequence > previous, "presentation sequences must stay strictly ordered")
		harness.assert_false(seen.has(sequence), "presentation sequence must not be duplicated")
		seen[sequence] = true
		previous = sequence
