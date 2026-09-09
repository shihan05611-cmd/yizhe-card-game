extends RefCounted

const RunSessionScript = preload("res://app/run_session.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("RunSession publishes catalog-backed views and routes lifecycle commands", func() -> void:
		_test_command_routing(harness)
	)
	harness.run_test("RunSession rejects deployment and economy mutations during battle", func() -> void:
		_test_fighting_gate(harness)
	)
	harness.run_test("RunSession reports save warnings without replaying committed commands", func() -> void:
		_test_save_warning_and_battle_checkpoint(harness)
	)


func _test_command_routing(harness: TestHarness) -> void:
	var session := RunSessionScript.new({}, "res://.godot/test-logs/run-session-routing-save.json")
	var errors: Array[String] = []
	harness.assert_true(session.new_run("run-session-routing", errors), "; ".join(errors))
	var initial: Dictionary = session.snapshot(errors)
	harness.assert_equal(initial["status"], "heroSelect")
	harness.assert_equal(initial["initial_hero_choice_ids"].size(), 3)
	var vm: Dictionary = session.view_model(errors)
	harness.assert_equal(vm["catalog"]["heroes"].size(), 9)
	harness.assert_true(vm["catalog"]["skills"].has("smallHeal"))
	var knight := _hero_by_id(vm["catalog"]["heroes"], 4)
	harness.assert_equal(knight["exclusive_name"], "反击")
	harness.assert_true(knight["is_passive"])
	harness.assert_equal(knight["base_sp_cost"], 0)
	harness.assert_equal(
		vm["catalog"]["abilities"]["counterAura"]["description"], knight["exclusive_description"],
	)
	var hero_id: int = initial["initial_hero_choice_ids"][0]
	harness.assert_true(session.execute({"type": "choose_starting_hero", "hero_id": hero_id}, errors), "; ".join(errors))
	var map: Dictionary = session.snapshot(errors)
	harness.assert_equal(map["status"], "map")
	harness.assert_equal(map["hero_deployment_slots"], {str(hero_id): 1})
	harness.assert_true(session.view_model()["can_continue"])
	var restored := RunSessionScript.new({}, "res://.godot/test-logs/run-session-routing-save.json")
	harness.assert_true(restored.continue_run(errors), "; ".join(errors))
	var restored_map: Dictionary = restored.snapshot(errors)
	harness.assert_equal(restored_map["status"], map["status"])
	harness.assert_equal(restored_map["hero_deployment_slots"], map["hero_deployment_slots"])
	harness.assert_equal(restored_map["map_nodes"].size(), map["map_nodes"].size())
	harness.assert_equal(restored_map["free_skill_ids"], map["free_skill_ids"])
	harness.assert_false(session.execute({"type": "unknown"}, errors))
	harness.assert_contains("; ".join(errors), "Unknown Run command")


func _test_fighting_gate(harness: TestHarness) -> void:
	var session := RunSessionScript.new({}, "res://.godot/test-logs/run-session-fighting-save.json")
	var errors: Array[String] = []
	harness.assert_true(session.new_run("run-session-fighting", errors), "; ".join(errors))
	var start: Dictionary = session.snapshot(errors)
	harness.assert_true(session.execute({
		"type": "choose_starting_hero", "hero_id": start["initial_hero_choice_ids"][0],
	}, errors), "; ".join(errors))
	for _step in range(10):
		var run: Dictionary = session.snapshot(errors)
		if run["status"] == "fighting":
			break
		var node := _first_available(run)
		harness.assert_false(node.is_empty(), "map must have an available node")
		if node.is_empty():
			return
		harness.assert_true(session.execute({"type": "choose_node", "node_id": node["id"]}, errors), "; ".join(errors))
		run = session.snapshot(errors)
		if run["status"] != "fighting":
			harness.assert_true(session.execute({"type": "leave_node"}, errors), "; ".join(errors))
	var fighting: Dictionary = session.snapshot(errors)
	harness.assert_equal(fighting["status"], "fighting")
	var before := fighting.duplicate(true)
	harness.assert_false(session.execute({
		"type": "set_hero_deployment_slot",
		"hero_id": fighting["front_hero_ids"][0],
		"slot": 2,
	}, errors))
	harness.assert_contains("; ".join(errors), "unavailable while a battle is active")
	harness.assert_equal(session.snapshot(), before)
	harness.assert_not_null(session.battle_lifecycle(errors), "; ".join(errors))


func _test_save_warning_and_battle_checkpoint(harness: TestHarness) -> void:
	# An invalid store is a deterministic stand-in for an I/O failure.  Starting
	# and ordinary commands remain committed, while a battle launch is blocked
	# until the map checkpoint is durable.
	var session := RunSessionScript.new({}, "")
	var errors: Array[String] = []
	harness.assert_true(session.new_run("run-session-save-warning", errors), "; ".join(errors))
	harness.assert_equal(session.view_model()["save_warning"].get("code"), "save_failed")
	var choice: Dictionary = session.snapshot(errors)
	harness.assert_true(session.execute({
		"type": "choose_starting_hero", "hero_id": choice["initial_hero_choice_ids"][0],
	}, errors), "; ".join(errors))
	var map: Dictionary = session.snapshot(errors)
	var node := _first_available(map)
	harness.assert_false(session.execute({"type": "choose_node", "node_id": node["id"]}, errors))
	harness.assert_contains("; ".join(errors), "Run save path must be a non-empty String")
	harness.assert_equal(session.snapshot(), map)


func _first_available(run: Dictionary) -> Dictionary:
	for node: Dictionary in run["map_nodes"]:
		if node["available"]:
			return node
	return {}


func _hero_by_id(heroes: Array, hero_id: int) -> Dictionary:
	for hero: Dictionary in heroes:
		if hero["id"] == hero_id:
			return hero
	return {}
