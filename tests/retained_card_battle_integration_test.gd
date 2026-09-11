extends RefCounted

const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const RunContract = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycle = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandom = preload("res://systems/roguelike/run_random_transaction.gd")
const Rng = preload("res://core/rng.gd")
const RoguelikeBattleAdapter = preload("res://app/roguelike_battle_adapter.gd")
const HandManager = preload("res://autoload/hand_manager.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("retain event selection reaches the exact live Controller card copy", func() -> void:
		_test_event_to_controller(harness)
	)


func _test_event_to_controller(harness: TestHarness) -> void:
	var fixture := _retain_event_fixture(harness)
	if fixture.is_empty():
		return
	var lifecycle: Variant = fixture["lifecycle"]
	var state: Dictionary = fixture["state"]
	var errors: Array[String] = []
	var event: Dictionary = lifecycle.get_current_event(errors)
	var free_options: Array = event["options"].filter(func(option: Dictionary) -> bool:
		return str(option["key"]).begins_with("free:")
	)
	harness.assert_true(not free_options.is_empty(), "retain event must expose an owned free-card copy")
	if free_options.is_empty():
		return
	var selected_key := str(free_options[0]["key"])
	var free_index := int(selected_key.trim_prefix("free:"))
	var expected_skill_id := str(state["free_skill_ids"][free_index])
	harness.assert_true(lifecycle.select_retained_card(selected_key, errors), "; ".join(errors))
	harness.assert_equal(state["retained_card_keys"], [selected_key])

	var battle_node: Dictionary = {}
	for node: Dictionary in state["map_nodes"]:
		node["available"] = false
		if battle_node.is_empty() and node["type"] == "battle" and not node["completed"]:
			battle_node = node
	harness.assert_false(battle_node.is_empty())
	if battle_node.is_empty():
		return
	battle_node["available"] = true
	harness.assert_true(lifecycle.choose_node(battle_node["id"], errors), "; ".join(errors))
	harness.assert_equal(state["status"], "fighting")

	var manager := HandManager.new()
	var adapter := RoguelikeBattleAdapter.new(lifecycle, manager)
	var started: Variant = adapter.start(errors)
	harness.assert_true(started.ok, started.message)
	if not started.ok:
		manager.free()
		return
	var controller: Variant = adapter.controller()
	var hand: Variant = manager._session.component("hand_runtime")
	var retained_ids: Array[String] = []
	var matching_source_ids: Array[String] = []
	for pile_name: String in ["draw", "hand", "discard", "exhaust"]:
		for instance_id: String in hand.pile_instance_ids(pile_name):
			var instance: Variant = hand.get_instance_snapshot(instance_id)
			if instance.source_skill_id == expected_skill_id:
				matching_source_ids.append(instance_id)
			if instance.retained:
				retained_ids.append(instance_id)
	harness.assert_equal(retained_ids.size(), 1)
	if retained_ids.size() == 1:
		var retained_id := retained_ids[0]
		var retained_instance: Variant = hand.get_instance_snapshot(retained_id)
		harness.assert_equal(retained_instance.source_skill_id, expected_skill_id)
		harness.assert_equal(retained_id, "card-%08d" % (free_index + 1))
		harness.assert_equal(matching_source_ids.filter(func(instance_id: String) -> bool:
			return hand.get_instance_snapshot(instance_id).retained
		).size(), 1, "duplicate cards retain only the selected copy")
		if retained_id not in hand.pile_instance_ids("hand"):
			harness.assert_true(hand.move_card_to_pile(retained_id, "hand", "top").ok)
		var vm_card: Dictionary = {}
		for card: Dictionary in controller.view_model()["hand"]:
			if card["instance_id"] == retained_id:
				vm_card = card
				break
		harness.assert_false(vm_card.is_empty())
		if not vm_card.is_empty():
			harness.assert_true(vm_card["retained"])
			harness.assert_equal(vm_card["source_skill_id"], expected_skill_id)
	harness.assert_true(adapter.cancel_open_launch(errors), "; ".join(errors))
	manager.free()


func _retain_event_fixture(harness: TestHarness) -> Dictionary:
	for seed_index in 64:
		var errors: Array[String] = []
		var catalogs: Dictionary = ContentCatalog.build(errors)
		var state: Dictionary = RunContract.create()
		var random := TransactionalRandom.new(Rng.seeded("retain-live-%d" % seed_index), errors)
		var lifecycle := RunLifecycle.new(state, catalogs, random, errors)
		if not errors.is_empty() or not lifecycle.start_run(errors):
			continue
		if not lifecycle.choose_starting_hero(state["initial_hero_choice_ids"][0], errors):
			continue
		var event_node: Dictionary = {}
		for node: Dictionary in state["map_nodes"]:
			node["available"] = false
			if event_node.is_empty() and node["type"] == "event" and not node["completed"]:
				event_node = node
		if event_node.is_empty():
			continue
		event_node["available"] = true
		if lifecycle.choose_node(event_node["id"], errors) and state["current_event_kind"] == "retain_card":
			return {
				"state": state, "catalogs": catalogs,
				"random": random, "lifecycle": lifecycle,
			}
	harness.fail("fixture seeds must reach a retain-card event")
	return {}
