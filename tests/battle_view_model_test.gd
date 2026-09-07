extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const Result = preload("res://core/card_runtime_result.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("production bootstrap publishes complete isolated battle view model", func() -> void:
		_test_view_model(harness)
	)
	harness.run_test("authoritative playability inspection has zero observable side effects", func() -> void:
		_test_inspection_is_read_only(harness)
	)
	harness.run_test("controller commands play cards end turns and expose interface settings", func() -> void:
		_test_commands(harness)
	)
	harness.run_test("fatal command result becomes visible and stops later commands", func() -> void:
		_test_fatal_state(harness)
	)
	print("M4-1 BATTLE VIEW MODEL TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_view_model(harness: TestHarness) -> void:
	var created := _controller("m4-vm")
	var controller: Variant = created["controller"]
	var manager: Node = created["manager"]
	harness.assert_true(created["result"].ok, created["result"].message)
	if not created["result"].ok:
		manager.free()
		return
	var vm: Dictionary = controller.view_model()
	harness.assert_true(vm["initialized"])
	harness.assert_equal(vm["battle"]["round"], 1)
	harness.assert_equal(vm["battle"]["phase"], "player_input")
	harness.assert_equal(vm["teams"]["ally"]["slots"].size(), 6)
	harness.assert_equal(vm["teams"]["enemy"]["slots"].size(), 6)
	harness.assert_equal(_slots(vm["teams"]["ally"]["slots"]), [1, 2, 3, 4, 5, 6])
	harness.assert_equal(_slots(vm["teams"]["enemy"]["slots"]), [1, 2, 3, 4, 5, 6])
	harness.assert_equal(vm["teams"]["ally"]["health_percent"], 1.0)
	harness.assert_equal(vm["teams"]["enemy"]["health_percent"], 1.0)
	var live_allies: Array = controller._runtime.component("state")["allies"]
	live_allies[0]["hp"] = float(live_allies[0]["max_hp"]) * 0.5
	var wounded_vm: Dictionary = controller.view_model()
	harness.assert_equal(
		wounded_vm["teams"]["ally"]["health_percent"],
		11.0 / 12.0,
		"team HP percent must aggregate all six current/max HP values",
	)
	harness.assert_equal(vm["heroes"]["ally"].size(), 1)
	harness.assert_equal(vm["heroes"]["ally"][0]["energy_percent"], 0.0)
	harness.assert_equal(vm["piles"]["hand"], vm["hand"].size())
	harness.assert_true(vm["hand"].size() > 0)
	for card: Dictionary in vm["hand"]:
		harness.assert_false(card["name"].is_empty())
		harness.assert_false(card["description"].is_empty())
		harness.assert_true(card.has("playable"))
		harness.assert_true(card.has("unavailable_reason"))
	var initial_events: Array = vm["presentation"]["pending_events"]
	harness.assert_equal(_count_event(initial_events, "battleStart"), 1)
	var duplicate_start: Variant = controller.start(_config("m4-vm"))
	harness.assert_false(duplicate_start.ok)
	harness.assert_equal(_count_event(controller.presentation_events(), "battleStart"), 1)

	vm["teams"]["ally"]["slots"][0]["hp"] = 0.0
	vm["hand"][0]["name"] = "tampered"
	vm["presentation"]["pending_events"].clear()
	var fresh: Dictionary = controller.view_model()
	harness.assert_true(fresh["teams"]["ally"]["slots"][0]["hp"] > 0.0)
	harness.assert_false(fresh["hand"][0]["name"] == "tampered")
	harness.assert_equal(_count_event(fresh["presentation"]["pending_events"], "battleStart"), 1)
	manager.free()


func _test_inspection_is_read_only(harness: TestHarness) -> void:
	var created := _controller("m4-inspect")
	var controller: Variant = created["controller"]
	var manager: Node = created["manager"]
	harness.assert_true(created["result"].ok, created["result"].message)
	if not created["result"].ok:
		manager.free()
		return
	var card: Dictionary = controller.view_model()["hand"][0]
	var session_before: Dictionary = manager.session_snapshot()
	var runtime_before: Dictionary = manager.runtime_snapshot()
	var combat_rng_before: int = controller._runtime.component("combat_rng").state_snapshot()
	var enemy_rng_before: int = controller._runtime.component("enemy_policy_rng").state_snapshot()
	var events_before: Array = controller.presentation_events()
	var vm_before: Dictionary = controller.view_model()
	var first: Variant = controller.inspect_card(card["instance_id"])
	var second: Variant = controller.inspect_card(card["instance_id"])
	harness.assert_true(first.ok, first.message)
	harness.assert_true(second.ok, second.message)
	harness.assert_equal(first.to_dict(), second.to_dict())
	harness.assert_equal(manager.session_snapshot(), session_before)
	harness.assert_equal(manager.runtime_snapshot(), runtime_before)
	harness.assert_equal(controller._runtime.component("combat_rng").state_snapshot(), combat_rng_before)
	harness.assert_equal(controller._runtime.component("enemy_policy_rng").state_snapshot(), enemy_rng_before)
	harness.assert_equal(controller.presentation_events(), events_before)
	harness.assert_equal(controller.view_model(), vm_before)
	manager.free()


func _test_commands(harness: TestHarness) -> void:
	var created := _controller("m4-commands")
	var controller: Variant = created["controller"]
	var manager: Node = created["manager"]
	harness.assert_true(created["result"].ok, created["result"].message)
	if not created["result"].ok:
		manager.free()
		return
	var playable_id := ""
	for card: Dictionary in controller.view_model()["hand"]:
		if card["playable"]:
			playable_id = card["instance_id"]
			break
	harness.assert_false(playable_id.is_empty())
	if not playable_id.is_empty():
		var played: Variant = controller.play_card(playable_id)
		harness.assert_true(played.ok, played.message)
		harness.assert_true(_count_kind(controller.presentation_events(), "card") >= 1)
	var round_before: int = controller.view_model()["battle"]["round"]
	var ended: Variant = controller.end_player_turn()
	harness.assert_true(ended.ok, ended.message)
	if ended.ok:
		harness.assert_equal(controller.view_model()["battle"]["round"], round_before + 1)
	harness.assert_true(controller.set_presentation_speed(4.0).ok)
	harness.assert_false(controller.set_presentation_speed(2.5).ok)
	harness.assert_true(controller.set_auto_battle(true).ok)
	harness.assert_equal(controller.view_model()["presentation"]["speed"], 4.0)
	harness.assert_true(controller.view_model()["presentation"]["auto_battle"])
	manager.free()


func _test_fatal_state(harness: TestHarness) -> void:
	var created := _controller("m4-fatal")
	var controller: Variant = created["controller"]
	var manager: Node = created["manager"]
	harness.assert_true(created["result"].ok, created["result"].message)
	if not created["result"].ok:
		manager.free()
		return
	var fatal_result := Result.new(false, Result.COMMITTED_FAILURE, "injected committed failure", {
		"fatal": true, "committed_prefix": true,
	})
	controller.call("_finish_command", fatal_result)
	var vm: Dictionary = controller.view_model()
	harness.assert_equal(vm["fatal"]["code"], Result.COMMITTED_FAILURE)
	harness.assert_equal(_count_kind(controller.presentation_events(), "fatal"), 1)
	var blocked: Variant = controller.end_player_turn()
	harness.assert_false(blocked.ok)
	harness.assert_equal(blocked.code, Result.QUEUE_HALTED)
	manager.free()


func _controller(seed: String) -> Dictionary:
	var manager := HandManagerScript.new()
	var controller := ControllerScript.new(manager)
	return {
		"manager": manager,
		"controller": controller,
		"result": controller.start(_config(seed)),
	}


func _config(seed: String) -> Dictionary:
	return {
		"battle_seed": seed,
		"deployed_hero_ids": [1],
		"free_skill_ids": ["pieceBlock", "pieceDamageUp", "markBurn", "executeStrike"],
		"stage_id": "counter",
	}


static func _slots(values: Array) -> Array:
	var slots: Array = []
	for value: Dictionary in values:
		slots.append(value["slot"])
	return slots


static func _count_event(events: Array, event_id: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if event["event_id"] == event_id:
			count += 1
	return count


static func _count_kind(events: Array, kind: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if event["kind"] == kind:
			count += 1
	return count
