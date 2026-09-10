extends RefCounted

const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const RngScript = preload("res://core/rng.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("Run exclusive-card inventory is a duplicate-safe closed state field", func() -> void:
		_test_contract_and_checkpoint_migration(harness)
	)
	harness.run_test("Run card candidates expose active hero exclusives and theme additions", func() -> void:
		_test_deployed_exclusive_candidates(harness)
	)
	harness.run_test("Run reward and shop commands acquire exclusive-card copies", func() -> void:
		_test_public_acquisition_commands(harness)
	)


func _catalogs(harness: TestHarness) -> Dictionary:
	var errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	return catalogs


func _new_lifecycle(catalogs: Dictionary, seed: String, harness: TestHarness) -> Variant:
	var errors: Array[String] = []
	var random := TransactionalRandomScript.new(RngScript.new(seed), errors)
	harness.assert_equal(errors, [])
	var lifecycle := RunLifecycleScript.new(RunContractScript.create(), catalogs, random, errors)
	harness.assert_true(lifecycle.is_valid(), "; ".join(errors))
	return lifecycle


func _test_contract_and_checkpoint_migration(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var idle: Dictionary = RunContractScript.create()
	harness.assert_equal(idle["exclusive_card_ids"], [])
	harness.assert_true(RunContractScript.validate(idle, errors), "; ".join(errors))

	var catalogs: Dictionary = _catalogs(harness)
	var lifecycle: Variant = _new_lifecycle(catalogs, "exclusive-checkpoint", harness)
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	var checkpoint: Dictionary = lifecycle.export_checkpoint(errors)
	harness.assert_false(checkpoint.is_empty(), "; ".join(errors))
	checkpoint["version"] = 2
	checkpoint["state"].erase("exclusive_card_ids")
	var restored: Variant = RunLifecycleScript.restore_checkpoint(
		checkpoint, catalogs,
		TransactionalRandomScript.new(RngScript.new("exclusive-checkpoint"), errors), errors,
	)
	harness.assert_true(restored != null, "; ".join(errors))
	if restored != null:
		harness.assert_equal(restored.snapshot(errors)["exclusive_card_ids"], [])

	# Only historical checkpoint versions get the default: a malformed current
	# checkpoint cannot silently remove claimed cards.
	var malformed: Dictionary = lifecycle.export_checkpoint(errors)
	malformed["state"].erase("exclusive_card_ids")
	var rejected: Variant = RunLifecycleScript.restore_checkpoint(
		malformed, catalogs,
		TransactionalRandomScript.new(RngScript.new("exclusive-current"), errors), errors,
	)
	harness.assert_true(rejected == null)
	harness.assert_true(not errors.is_empty(), "current malformed checkpoint must be rejected")


func _test_deployed_exclusive_candidates(harness: TestHarness) -> void:
	var catalogs: Dictionary = _catalogs(harness)
	var lifecycle: Variant = null
	var state: Dictionary = {}
	var errors: Array[String] = []
	for seed_index: int in 80:
		var candidate: Variant = _new_lifecycle(catalogs, "exclusive-hero7-%d" % seed_index, harness)
		harness.assert_true(candidate.start_run(errors), "; ".join(errors))
		state = candidate._state
		if 7 in state["initial_hero_choice_ids"]:
			harness.assert_true(candidate.choose_starting_hero(7, errors), "; ".join(errors))
			lifecycle = candidate
			break
	harness.assert_true(lifecycle != null, "fixture must be able to start with 沉戈")
	if lifecycle == null:
		return
	state = lifecycle._state
	var options: Array = lifecycle._draw_card_options(state, 99, "reward", 0, false, errors)
	harness.assert_equal(errors, [])
	var ids: Array = options.map(func(option: Dictionary) -> Variant: return option["payload_id"])
	harness.assert_true("exclusive:siege" in ids, "base active exclusive can be acquired again")
	harness.assert_true("exclusive:pressOpening" in ids, "theme exclusive can be acquired")
	for option: Dictionary in options:
		if option["type"] == "exclusiveCard":
			harness.assert_equal(option["price"], 0)
			harness.assert_true(str(option["id"]).begins_with("reward:exclusive:"))
			harness.assert_true(str(option["name"]).length() > 0)
			harness.assert_true(str(option["description"]).length() > 0)

	# The inventory intentionally permits distinct copies.  The battle payload
	# projects only cards belonging to heroes still deployed.
	state["exclusive_card_ids"] = ["exclusive:siege", "exclusive:siege", "exclusive:pressOpening"]
	harness.assert_true(lifecycle.validate(errors), "; ".join(errors))
	var projected: Array = lifecycle._deployed_exclusive_card_ids(state)
	harness.assert_equal(projected, state["exclusive_card_ids"])
	state["hero_deployment_slots"] = {"1": 1}
	harness.assert_equal(lifecycle._deployed_exclusive_card_ids(state), [])


func _test_public_acquisition_commands(harness: TestHarness) -> void:
	var catalogs: Dictionary = _catalogs(harness)
	var shop_result: Dictionary = _find_public_exclusive(catalogs, "shop", harness)
	harness.assert_true(not shop_result.is_empty(), "fixture must reach a shop exclusive card")
	if not shop_result.is_empty():
		var shop_lifecycle: Variant = shop_result["lifecycle"]
		var shop_option: Dictionary = shop_result["option"]
		var errors: Array[String] = []
		var shop_copies_before: int = shop_lifecycle._state["exclusive_card_ids"].count(shop_option["payload_id"])
		harness.assert_true(shop_lifecycle.buy_shop_option(shop_option["id"], errors), "; ".join(errors))
		harness.assert_equal(shop_lifecycle._state["exclusive_card_ids"].count(shop_option["payload_id"]), shop_copies_before + 1)
		harness.assert_true(shop_lifecycle.complete_current_node(errors), "; ".join(errors))
		var battle_node: Dictionary = {}
		# A shop may be followed by another safe node; use public map commands
		# until the next battle instead of assuming one is adjacent.
		for _step in 12:
			var map_state: Dictionary = shop_lifecycle.snapshot(errors)
			if map_state["status"] == "reward":
				var rewards: Array = map_state["reward_options"]
				if rewards.is_empty():
					break
				harness.assert_true(shop_lifecycle.select_reward(rewards[0]["id"], errors), "; ".join(errors))
				continue
			var available: Array = map_state["map_nodes"].filter(func(node: Dictionary) -> bool:
				return node["available"] and not node["completed"]
			)
			for node: Dictionary in available:
				if node["type"] in ["battle", "elite", "boss"]:
					battle_node = node
					break
			if not battle_node.is_empty() or available.is_empty():
				break
			harness.assert_true(shop_lifecycle.choose_node(available[0]["id"], errors), "; ".join(errors))
			harness.assert_true(shop_lifecycle.complete_current_node(errors), "; ".join(errors))
		harness.assert_false(battle_node.is_empty(), "post-shop route must eventually offer a real battle")
		if not battle_node.is_empty():
			harness.assert_true(shop_lifecycle.choose_node(battle_node["id"], errors), "; ".join(errors))
			var launch: Dictionary = shop_lifecycle.begin_current_battle(errors)
			harness.assert_equal(launch["exclusive_card_ids"], shop_lifecycle._state["exclusive_card_ids"])
			var manager := preload("res://autoload/hand_manager.gd").new()
			var controller := preload("res://app/battle_controller.gd").new(manager)
			var started: Variant = controller.start(launch)
			harness.assert_true(started.ok, started.message)
			if started.ok:
				var expected_copies: int = launch["exclusive_card_ids"].count(shop_option["payload_id"])
				if shop_option["payload_id"] == "exclusive:siege":
					expected_copies += 1
				harness.assert_equal(manager.session_snapshot()["deck_card_ids"].count(shop_option["payload_id"]), expected_copies)
			manager.free()

	var reward_result: Dictionary = _find_public_exclusive(catalogs, "reward", harness)
	harness.assert_true(not reward_result.is_empty(), "fixture must reach a battle reward exclusive card")
	if not reward_result.is_empty():
		var reward_lifecycle: Variant = reward_result["lifecycle"]
		var reward_option: Dictionary = reward_result["option"]
		var errors: Array[String] = []
		var reward_copies_before: int = reward_lifecycle._state["exclusive_card_ids"].count(reward_option["payload_id"])
		harness.assert_true(reward_lifecycle.select_reward(reward_option["id"], errors), "; ".join(errors))
		harness.assert_equal(reward_lifecycle._state["exclusive_card_ids"].count(reward_option["payload_id"]), reward_copies_before + 1)


func _find_public_exclusive(catalogs: Dictionary, target: String, harness: TestHarness) -> Dictionary:
	for seed_index: int in 80:
		var lifecycle: Variant = _new_lifecycle(catalogs, "exclusive-public-%s-%d" % [target, seed_index], harness)
		var errors: Array[String] = []
		if not lifecycle.start_run(errors):
			continue
		var state: Dictionary = lifecycle._state
		if 7 not in state["initial_hero_choice_ids"] or not lifecycle.choose_starting_hero(7, errors):
			continue
		for _guard: int in 36:
			state = lifecycle._state
			if state["status"] == target:
				var options: Array = state["shop_options"] if target == "shop" else state["reward_options"]
				for option: Dictionary in options:
					if option["type"] in ["shopExclusiveCard", "exclusiveCard"]:
						return {"lifecycle": lifecycle, "option": option}
				var continued: bool = (
					lifecycle.complete_current_node(errors)
					if target == "shop"
					else (not options.is_empty() and lifecycle.select_reward(options[0]["id"], errors))
				)
				if not continued:
					break
				continue
			if state["status"] == "map":
				var available: Array = state["map_nodes"].filter(func(node: Dictionary) -> bool:
					return node["available"] and not node["completed"]
				)
				var wanted_types: Array = ["shop"] if target == "shop" else ["elite", "boss"]
				var preferred: Array = available.filter(func(node: Dictionary) -> bool:
					return node["type"] in wanted_types
				)
				# The middle lane reaches chapter-one's verified elite route.  Prefer
				# it until an actual elite/boss is available, rather than repeatedly
				# walking the top-lane normal-battle-only route.
				var fallback: Dictionary = available[1] if available.size() > 1 else (available[0] if not available.is_empty() else {})
				var next_node: Dictionary = preferred[0] if not preferred.is_empty() else fallback
				if next_node.is_empty() or not lifecycle.choose_node(next_node["id"], errors):
					break
			elif state["status"] == "fighting":
				if not lifecycle.complete_current_battle(true, errors):
					break
			elif state["status"] == "reward":
				if state["reward_options"].is_empty() or not lifecycle.select_reward(state["reward_options"][0]["id"], errors):
					break
			elif state["status"] in ["shop", "forge", "event"]:
				if not lifecycle.complete_current_node(errors):
					break
			else:
				break
	return {}
