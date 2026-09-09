extends RefCounted

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const CardCatalogScript = preload("res://data/catalogs/card_catalog.gd")
const DeckAssemblerScript = preload("res://systems/cards/battle_deck_assembler.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("M5 lifecycle starts without shentong and creates the frozen initial deck", func() -> void:
		_test_start_and_choose(harness)
	)
	harness.run_test("M5 node selection is atomic and exposes only exact successors", func() -> void:
		_test_node_frontier(harness)
	)
	harness.run_test("M5 chapter-one milestones recruit into exact authoritative slots", func() -> void:
		_test_recruitment_and_deployment(harness)
	)
	harness.run_test("M5 recruited roster and free-skill multiset assemble the M3 deck", func() -> void:
		_test_deck_rebuild(harness)
	)
	harness.run_test("M5 lifecycle reaches failed and three-chapter cleared terminals", func() -> void:
		_test_terminals_and_quit(harness)
	)
	harness.run_test("M5 lifecycle rejects corrupt state and missing dependencies", func() -> void:
		_test_boundaries(harness)
	)


func _test_start_and_choose(harness: TestHarness) -> void:
	var fixture := _fixture("m5-03-start", harness)
	var lifecycle: Variant = fixture["lifecycle"]
	var state: Dictionary = fixture["state"]
	var errors: Array[String] = []
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	harness.assert_equal(state["status"], "heroSelect")
	harness.assert_equal(state["currency"], 30)
	harness.assert_equal(state["initial_hero_choice_ids"].size(), 3)
	harness.assert_equal(_unique(state["initial_hero_choice_ids"]).size(), 3)
	harness.assert_false(state["initial_hero_choice_ids"].has(2), "fate must not be a random choice")
	harness.assert_true(_contains_any(state["initial_hero_choice_ids"], [3, 5, 6]))
	harness.assert_false(state.has("selected_shentong_id"))

	var chosen: int = state["initial_hero_choice_ids"][0]
	harness.assert_true(lifecycle.choose_starting_hero(chosen, errors), "; ".join(errors))
	harness.assert_equal(state["status"], "map")
	harness.assert_equal(state["map_nodes"].size(), 30)
	harness.assert_equal(state["hero_deployment_slots"], {str(chosen): 1})
	harness.assert_equal(state["front_hero_ids"], [chosen])
	harness.assert_equal(state["back_hero_ids"], [])
	harness.assert_equal(state["free_skill_ids"].size(), 2)
	harness.assert_equal(_unique(state["free_skill_ids"]).size(), 2)
	harness.assert_equal(_sorted_strings(state["free_skill_ids"]), ["markBurn", "smallHeal"])
	harness.assert_false(state.has("equipped_free_skill_ids"))
	harness.assert_true(lifecycle.validate(errors), "; ".join(errors))


func _test_node_frontier(harness: TestHarness) -> void:
	var fixture := _started_fixture("m5-03-frontier", harness)
	var lifecycle: Variant = fixture["lifecycle"]
	var state: Dictionary = fixture["state"]
	var errors: Array[String] = []
	var before: Dictionary = lifecycle.snapshot(errors)
	harness.assert_false(lifecycle.choose_node("missing", errors))
	harness.assert_equal(state, before)

	var node: Dictionary = _first_available(state)
	var node_id: String = node["id"]
	var expected_next: Array = node["next_node_ids"].duplicate()
	harness.assert_true(lifecycle.choose_node(node_id, errors), "; ".join(errors))
	harness.assert_equal(state["current_node_id"], node_id)
	harness.assert_equal(_available_ids(state), [])
	harness.assert_equal(state["shop_options"], [], "M5-03 must not implement economy options")
	harness.assert_equal(state["currency"], 30, "M5-03 event entry must not implement currency")
	var selected: Dictionary = lifecycle.snapshot(errors)
	harness.assert_false(lifecycle.choose_node(node_id, errors))
	harness.assert_equal(state, selected)
	harness.assert_true(_complete_selected(lifecycle, state, true, errors), "; ".join(errors))
	_resolve_all_rewards(lifecycle, state, harness, errors)
	harness.assert_equal(state["status"], "map")
	harness.assert_equal(_available_ids(state), expected_next)
	harness.assert_true(_node_by_id(state, node_id)["completed"])
	harness.assert_false(lifecycle.choose_node(node_id, errors), "completed node cannot be selected again")


func _test_recruitment_and_deployment(harness: TestHarness) -> void:
	var fixture := _started_fixture("m5-03-recruit", harness)
	var lifecycle: Variant = fixture["lifecycle"]
	var state: Dictionary = fixture["state"]
	var errors: Array[String] = []
	_reach_column(lifecycle, state, 2, harness, errors)
	var milestone: Dictionary = _first_available(state)
	harness.assert_equal(milestone["column"], 2)
	harness.assert_true(lifecycle.choose_node(milestone["id"], errors), "; ".join(errors))
	harness.assert_true(_complete_selected(lifecycle, state, true, errors), "; ".join(errors))
	_resolve_battle_reward(lifecycle, state, harness, errors)
	harness.assert_equal(state["status"], "reward")
	harness.assert_true(state["reward_pending"])
	harness.assert_equal(state["reward_options"].size(), 3)
	var owned_before: Array[int] = lifecycle.deployed_hero_ids(errors)
	for option: Dictionary in state["reward_options"]:
		harness.assert_equal(option["type"], "hero")
		harness.assert_false(option["payload_id"] in owned_before)
		harness.assert_false(option["payload_id"] == 2)
	var recruit_id: int = state["reward_options"][0]["payload_id"]
	harness.assert_true(lifecycle.recruit_hero(recruit_id, errors), "; ".join(errors))
	harness.assert_equal(state["hero_deployment_slots"][str(recruit_id)], 4)
	harness.assert_equal(state["back_hero_ids"], [recruit_id])
	harness.assert_true(_node_by_id(state, milestone["id"])["completed"])

	var initial_id: int = owned_before[0]
	harness.assert_true(lifecycle.set_hero_deployment_slot(initial_id, 3, errors), "; ".join(errors))
	harness.assert_equal(state["hero_deployment_slots"][str(initial_id)], 3)
	harness.assert_equal(state["front_hero_ids"], [initial_id], "front is only a row view")
	var occupied_before: Dictionary = lifecycle.snapshot(errors)
	harness.assert_false(lifecycle.set_hero_deployment_slot(recruit_id, 3, errors))
	harness.assert_equal(state, occupied_before)
	harness.assert_true(lifecycle.set_hero_deployment_slot(recruit_id, 6, errors), "; ".join(errors))
	harness.assert_equal(state["hero_deployment_slots"][str(recruit_id)], 6)
	harness.assert_equal(state["back_hero_ids"], [recruit_id], "back is only a row view")
	harness.assert_equal(lifecycle.deployed_hero_ids(errors), [initial_id, recruit_id])

	while state["status"] == "map" and _first_available(state)["column"] < 9:
		var node := _first_available(state)
		harness.assert_true(lifecycle.choose_node(node["id"], errors), "; ".join(errors))
		harness.assert_true(_complete_selected(lifecycle, state, true, errors), "; ".join(errors))
		_resolve_all_rewards(lifecycle, state, harness, errors)
	var boss := _first_available(state)
	harness.assert_equal(boss["type"], "boss")
	harness.assert_true(lifecycle.choose_node(boss["id"], errors), "; ".join(errors))
	harness.assert_true(lifecycle.complete_current_battle(true, errors), "; ".join(errors))
	_resolve_battle_reward(lifecycle, state, harness, errors)
	harness.assert_equal(state["status"], "reward", "chapter-one boss is the second milestone")
	harness.assert_equal(state["reward_options"].size(), 3)
	var second_recruit_id: int = state["reward_options"][0]["payload_id"]
	harness.assert_true(lifecycle.recruit_hero(second_recruit_id, errors), "; ".join(errors))
	harness.assert_equal(
		state["hero_deployment_slots"][str(second_recruit_id)], 4,
		"recruitment fills the first free slot in Web's 4,5,6,1,2,3 order"
	)
	harness.assert_equal(state["chapter"], 2)
	harness.assert_equal(state["status"], "map")


func _test_deck_rebuild(harness: TestHarness) -> void:
	var fixture := _started_fixture("m5-03-deck", harness)
	var lifecycle: Variant = fixture["lifecycle"]
	var state: Dictionary = fixture["state"]
	var catalogs: Dictionary = fixture["catalogs"]
	var errors: Array[String] = []
	_reach_column(lifecycle, state, 2, harness, errors)
	var milestone := _first_available(state)
	harness.assert_true(lifecycle.choose_node(milestone["id"], errors), "; ".join(errors))
	harness.assert_true(_complete_selected(lifecycle, state, true, errors), "; ".join(errors))
	_resolve_battle_reward(lifecycle, state, harness, errors)
	var active_recruit_id := 0
	for option: Dictionary in state["reward_options"]:
		var hero: Variant = catalogs["characters"]["players"][option["payload_id"]]
		if not catalogs["hero_abilities"]["exclusive"][hero.exclusive_skill_id].is_passive:
			active_recruit_id = option["payload_id"]
			break
	harness.assert_true(active_recruit_id > 0, "four options must include an active-exclusive hero")
	harness.assert_true(lifecycle.recruit_hero(active_recruit_id, errors), "; ".join(errors))
	harness.assert_true(lifecycle.add_free_skill_copy("smallHeal", errors), "; ".join(errors))
	var cards := CardCatalogScript.build_from(
		catalogs["skills"], catalogs["hero_abilities"], errors
	)
	var result: Dictionary = DeckAssemblerScript.assemble({
		"card_catalog": cards,
		"player_catalog": catalogs["characters"]["players"],
		"exclusive_catalog": catalogs["hero_abilities"]["exclusive"],
		"deployed_hero_ids": lifecycle.deployed_hero_ids(errors),
		"free_skill_ids": state["free_skill_ids"],
	})
	harness.assert_true(result["ok"], str(result))
	if result["ok"]:
		harness.assert_equal(result["value"]["deployed_hero_ids"].size(), 2)
		harness.assert_equal(result["value"]["card_ids"].count("free:smallHeal"), 2)
		var exclusive_id: String = catalogs["characters"]["players"][active_recruit_id].exclusive_skill_id
		harness.assert_true(result["value"]["card_ids"].has("exclusive:%s" % exclusive_id))


func _test_terminals_and_quit(harness: TestHarness) -> void:
	var loss := _started_fixture("m5-03-loss", harness)
	var loss_lifecycle: Variant = loss["lifecycle"]
	var loss_state: Dictionary = loss["state"]
	var errors: Array[String] = []
	_reach_battle(loss_lifecycle, loss_state, harness, errors)
	harness.assert_true(loss_lifecycle.complete_current_battle(false, errors), "; ".join(errors))
	harness.assert_equal(loss_state["status"], "failed")
	harness.assert_true(loss_state["active"], "failed is an inspectable terminal before quit")
	var failed: Dictionary = loss_lifecycle.snapshot(errors)
	harness.assert_false(loss_lifecycle.complete_current_battle(false, errors))
	harness.assert_equal(loss_state, failed)
	harness.assert_true(loss_lifecycle.quit_run(errors), "; ".join(errors))
	harness.assert_equal(loss_state, RunContractScript.create())

	var clear := _started_fixture("m5-03-clear", harness)
	var lifecycle: Variant = clear["lifecycle"]
	var state: Dictionary = clear["state"]
	var previous_chapter := 1
	var guard := 0
	while state["status"] != "cleared" and guard < 100:
		guard += 1
		if state["status"] == "reward":
			_resolve_all_rewards(lifecycle, state, harness, errors)
			continue
		var node := _first_available(state)
		harness.assert_false(node.is_empty(), "map must expose a path to the boss")
		if node.is_empty():
			break
		harness.assert_true(lifecycle.choose_node(node["id"], errors), "; ".join(errors))
		harness.assert_true(_complete_selected(lifecycle, state, true, errors), "; ".join(errors))
		if state["chapter"] > previous_chapter:
			harness.assert_equal(state["chapter"], previous_chapter + 1)
			previous_chapter = state["chapter"]
	harness.assert_equal(state["status"], "cleared")
	harness.assert_equal(state["chapter"], 3)
	harness.assert_true(guard < 100)
	harness.assert_true(lifecycle.quit_run(errors), "; ".join(errors))
	harness.assert_equal(state, RunContractScript.create(), "cleared and failed both quit to canonical idle")


func _test_boundaries(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var invalid := RunLifecycleScript.new(RunContractScript.create(), {}, null, errors)
	harness.assert_false(invalid.is_valid())
	harness.assert_true(not errors.is_empty())
	var fixture := _started_fixture("m5-03-corrupt", harness)
	var lifecycle: Variant = fixture["lifecycle"]
	var state: Dictionary = fixture["state"]
	state["front_hero_ids"] = []
	var before: Dictionary = state.duplicate(true)
	harness.assert_false(lifecycle.choose_node(_first_available(state)["id"], errors))
	harness.assert_equal(state, before)
	harness.assert_contains("; ".join(errors), "slot-sorted row views")


func _fixture(seed: String, harness: TestHarness) -> Dictionary:
	var errors: Array[String] = []
	var catalogs := ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	var state := RunContractScript.create()
	var random := TransactionalRandomScript.new(RngScript.seeded(seed), errors)
	harness.assert_equal(errors, [])
	var lifecycle := RunLifecycleScript.new(state, catalogs, random, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(lifecycle.is_valid())
	return {"state": state, "catalogs": catalogs, "random": random, "lifecycle": lifecycle}


func _started_fixture(seed: String, harness: TestHarness) -> Dictionary:
	var fixture := _fixture(seed, harness)
	var errors: Array[String] = []
	harness.assert_true(fixture["lifecycle"].start_run(errors), "; ".join(errors))
	var hero_id: int = fixture["state"]["initial_hero_choice_ids"][0]
	harness.assert_true(fixture["lifecycle"].choose_starting_hero(hero_id, errors), "; ".join(errors))
	return fixture


func _reach_column(
	lifecycle: Variant,
	state: Dictionary,
	column: int,
	harness: TestHarness,
	errors: Array[String],
) -> void:
	while state["status"] == "map" and _first_available(state)["column"] < column:
		var node := _first_available(state)
		harness.assert_true(lifecycle.choose_node(node["id"], errors), "; ".join(errors))
		harness.assert_true(_complete_selected(lifecycle, state, true, errors), "; ".join(errors))
		_resolve_all_rewards(lifecycle, state, harness, errors)


func _reach_battle(
	lifecycle: Variant,
	state: Dictionary,
	harness: TestHarness,
	errors: Array[String],
) -> void:
	for _step in range(10):
		var battle: Dictionary = {}
		for node: Dictionary in state["map_nodes"]:
			if node["available"] and node["type"] in ["battle", "elite", "boss"]:
				battle = node
				break
		var chosen := battle if not battle.is_empty() else _first_available(state)
		harness.assert_true(lifecycle.choose_node(chosen["id"], errors), "; ".join(errors))
		if state["status"] == "fighting":
			return
		harness.assert_true(lifecycle.complete_current_node(errors), "; ".join(errors))
	harness.fail("chapter path did not expose a battle node")


func _complete_selected(
	lifecycle: Variant,
	state: Dictionary,
	won: bool,
	errors: Array[String],
) -> bool:
	return (
		lifecycle.complete_current_battle(won, errors)
		if state["status"] == "fighting"
		else lifecycle.complete_current_node(errors)
	)


func _resolve_battle_reward(
	lifecycle: Variant,
	state: Dictionary,
	harness: TestHarness,
	errors: Array[String],
) -> void:
	if state["status"] != "reward" or state["reward_options"].is_empty():
		return
	if state["reward_options"][0]["type"] == "hero":
		return
	harness.assert_true(
		lifecycle.select_reward(state["reward_options"][0]["id"], errors),
		"; ".join(errors),
	)


func _resolve_all_rewards(
	lifecycle: Variant,
	state: Dictionary,
	harness: TestHarness,
	errors: Array[String],
) -> void:
	var guard := 0
	while state["status"] == "reward" and guard < 3:
		guard += 1
		var option: Dictionary = state["reward_options"][0]
		if option["type"] == "hero":
			harness.assert_true(lifecycle.recruit_hero(option["payload_id"], errors), "; ".join(errors))
		else:
			harness.assert_true(lifecycle.select_reward(option["id"], errors), "; ".join(errors))
	harness.assert_true(guard < 3, "reward chain must finish after battle loot and optional recruitment")


func _first_available(state: Dictionary) -> Dictionary:
	for node: Dictionary in state["map_nodes"]:
		if node["available"]:
			return node
	return {}


func _available_ids(state: Dictionary) -> Array:
	return state["map_nodes"].filter(func(node: Dictionary) -> bool:
		return node["available"]
	).map(func(node: Dictionary) -> String: return node["id"])


func _node_by_id(state: Dictionary, node_id: String) -> Dictionary:
	for node: Dictionary in state["map_nodes"]:
		if node["id"] == node_id:
			return node
	return {}


func _unique(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		if value not in result:
			result.append(value)
	return result


func _contains_any(values: Array, candidates: Array) -> bool:
	return candidates.any(func(value: Variant) -> bool: return value in values)


func _sorted_strings(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort()
	return copy
