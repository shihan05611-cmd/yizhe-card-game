extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const AdapterScript = preload("res://app/roguelike_battle_adapter.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const RngScript = preload("res://core/rng.gd")
const GrowthPortScript = preload("res://systems/growth/growth_port.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("X shortcut ignores echo, refuses pause, and settles a live battle once", func() -> void:
		_test_x_shortcut(harness)
	)
	harness.run_test("forced victory settles a direct Run adapter once with rewards and HP ratios", func() -> void:
		_test_run_settlement(harness)
	)
	harness.run_test("X drains a live Run presentation then commits reward, HP, and staged growth once", func() -> void:
		_test_run_shortcut_settlement(harness)
	)
	harness.run_test("X clears a busy card presentation and waiting queue before terminal events", func() -> void:
		_test_x_clears_busy_card_queue(harness)
	)


func _test_x_shortcut(harness: TestHarness) -> void:
	var root: Variant = MainScene.instantiate()
	root.battle_seed = "instant-victory-input"
	Engine.get_main_loop().root.add_child(root)
	root.presentation_queue.drain_for_test()
	var before_events: int = root.controller.presentation_events().size()
	var x := InputEventKey.new()
	x.keycode = KEY_X
	x.pressed = true
	x.echo = false
	var echo := InputEventKey.new()
	echo.keycode = KEY_X
	echo.pressed = true
	echo.echo = true
	root._unhandled_key_input(echo)
	harness.assert_false(root.controller.view_model()["battle"]["game_over"], "echo must not trigger victory")
	harness.assert_equal(root.controller.presentation_events().size(), before_events)
	root.process_mode = Node.PROCESS_MODE_DISABLED
	harness.assert_true(root.force_victory() == null, "the same process gate used by Run pause blocks X")
	harness.assert_false(root.controller.view_model()["battle"]["game_over"])
	root.process_mode = Node.PROCESS_MODE_INHERIT
	root._unhandled_key_input(x)
	harness.assert_true(root.controller.view_model()["battle"]["game_over"])
	harness.assert_equal(root.controller.view_model()["battle"]["result"], "win")
	harness.assert_true(root.presentation_queue.is_busy())
	root.presentation_queue.drain_for_test()
	harness.assert_true(root.battle_screen.result_overlay.visible)
	var settled_events: int = root.controller.presentation_events().size()
	harness.assert_true(settled_events > before_events)
	root._unhandled_key_input(x)
	harness.assert_equal(root.controller.presentation_events().size(), settled_events)
	root.free()


func _test_run_settlement(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	var state: Dictionary = RunContractScript.create()
	var random := TransactionalRandomScript.new(RngScript.seeded("instant-victory-run"), errors)
	var lifecycle := RunLifecycleScript.new(state, catalogs, random, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	harness.assert_true(lifecycle.choose_starting_hero(state["initial_hero_choice_ids"][0], errors), "; ".join(errors))
	var node := _first_battle_node(state)
	harness.assert_false(node.is_empty())
	if node.is_empty():
		return
	harness.assert_true(lifecycle.choose_node(node["id"], errors), "; ".join(errors))
	var manager := HandManagerScript.new()
	var adapter := AdapterScript.new(lifecycle, manager)
	var started: Variant = adapter.start(errors)
	harness.assert_true(started.ok, started.message)
	if not started.ok:
		manager.free()
		return
	var controller: Variant = adapter.controller()
	var battle_state: Dictionary = controller._runtime.component("state")
	var target: Dictionary = battle_state["allies"][1]
	target["hp"] = float(target["max_hp"]) * 0.6
	target["alive"] = true
	var enemies_before: Array = battle_state["enemies"].duplicate(true)
	var won: Variant = controller.force_victory()
	harness.assert_true(won.ok, won.message)
	harness.assert_true(battle_state["game_over"])
	harness.assert_equal(battle_state["battle_result"], "win")
	harness.assert_equal(battle_state["enemies"], enemies_before, "shortcut must not fabricate enemy deaths")
	harness.assert_true(adapter.settle_if_terminal(errors), "; ".join(errors))
	harness.assert_true(adapter.is_settled())
	harness.assert_equal(state["status"], "reward")
	harness.assert_equal(state["piece_slots"][1]["hp_ratio"], 0.6)
	var snapshot: Dictionary = state.duplicate(true)
	harness.assert_false(adapter.settle_if_terminal(errors), "terminal settlement is one-shot")
	harness.assert_equal(state, snapshot)
	manager.free()


func _test_run_shortcut_settlement(harness: TestHarness) -> void:
	var setup := _fighting_run(harness, "instant-victory-real-run")
	if setup.is_empty():
		return
	var state: Dictionary = setup["state"]
	var lifecycle: Variant = setup["lifecycle"]
	var root: Variant = MainScene.instantiate()
	root.auto_start = false
	Engine.get_main_loop().root.add_child(root)
	harness.assert_true(root.start_run_battle(lifecycle))
	root.presentation_queue.drain_for_test()
	var controller: Variant = root.controller
	var battle_state: Dictionary = controller._runtime.component("state")
	var staged: Dictionary = controller._runtime.component("ports").call_action(
		GrowthPortScript.ACTION_STAGE,
		{"requests": [{
			"id": "fistMastery", "target": {"type": "hero", "id": 6}, "stacks": 1,
		}]},
	)
	harness.assert_true(staged["ok"], staged.get("error", ""))
	var target: Dictionary = battle_state["allies"][1]
	target["hp"] = float(target["max_hp"]) * 0.6
	target["alive"] = true
	var finished_count := [0]
	root.run_battle_finished.connect(func(_snapshot: Dictionary) -> void: finished_count[0] += 1)
	var x := InputEventKey.new()
	x.keycode = KEY_X
	x.pressed = true
	root._unhandled_key_input(x)
	harness.assert_true(battle_state["game_over"])
	harness.assert_true(root.presentation_queue.is_busy(), "terminal outcome remains queued until presentation drains")
	root.presentation_queue.drain_for_test()
	harness.assert_false(root.presentation_queue.is_busy())
	harness.assert_true(root._run_battle_adapter.is_settled())
	harness.assert_equal(finished_count[0], 1)
	harness.assert_equal(state["status"], "reward")
	harness.assert_equal(state["piece_slots"][1]["hp_ratio"], 0.6)
	harness.assert_equal(state["permanent_buffs"], [{
		"id": "fistMastery", "target": {"type": "hero", "id": 6}, "stacks": 1,
	}])
	var committed: Dictionary = state.duplicate(true)
	root._unhandled_key_input(x)
	harness.assert_equal(finished_count[0], 1)
	harness.assert_equal(state, committed)
	root.free()


func _test_x_clears_busy_card_queue(harness: TestHarness) -> void:
	var root: Variant = MainScene.instantiate()
	root.battle_seed = "instant-victory-busy-card"
	Engine.get_main_loop().root.add_child(root)
	root.presentation_queue.drain_for_test()
	var cards: Array = root.controller.view_model()["hand"]
	var card: Dictionary = _first_playable(cards)
	harness.assert_false(card.is_empty())
	if card.is_empty():
		root.free()
		return
	harness.assert_true(root.queue_play_card(_guard(card)) != null)
	harness.assert_true(root.presentation_queue.is_busy())
	harness.assert_true(root.battle_screen.pending_card_count() > 0)
	var x := InputEventKey.new()
	x.keycode = KEY_X
	x.pressed = true
	root._unhandled_key_input(x)
	harness.assert_true(root.controller.view_model()["battle"]["game_over"])
	harness.assert_equal(root.battle_screen.pending_card_count(), 0)
	root.presentation_queue.drain_for_test()
	harness.assert_false(root.presentation_queue.is_busy())
	harness.assert_equal(root.battle_screen.pending_card_count(), 0)
	root.free()


func _fighting_run(harness: TestHarness, seed: String) -> Dictionary:
	var errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	var state: Dictionary = RunContractScript.create()
	var random := TransactionalRandomScript.new(RngScript.seeded(seed), errors)
	var lifecycle := RunLifecycleScript.new(state, catalogs, random, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	harness.assert_true(lifecycle.choose_starting_hero(state["initial_hero_choice_ids"][0], errors), "; ".join(errors))
	var node := _first_battle_node(state)
	harness.assert_false(node.is_empty())
	if node.is_empty():
		return {}
	harness.assert_true(lifecycle.choose_node(node["id"], errors), "; ".join(errors))
	return {"state": state, "lifecycle": lifecycle}


static func _first_playable(cards: Array) -> Dictionary:
	for card: Dictionary in cards:
		if bool(card.get("playable", false)):
			return card
	return {}


static func _guard(card: Dictionary) -> Dictionary:
	return {
		"type": "play_card",
		"instance_id": card.get("instance_id", ""),
		"expected_card_id": card.get("card_id", ""),
		"expected_source_skill_id": card.get("source_skill_id", ""),
		"owner_hero_id": card.get("owner_hero_id"),
	}


func _first_battle_node(state: Dictionary) -> Dictionary:
	for node: Dictionary in state["map_nodes"]:
		if node["available"] and node["type"] == "battle":
			return node
	return {}
