extends RefCounted

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const MapSystemScript = preload("res://systems/roguelike/map_system.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("M5 battle elite and boss rewards match Web scales and filters", func() -> void:
		_test_reward_scales_and_filters(harness)
	)
	harness.run_test("M5 reward skills add duplicate copies and heal never revives", func() -> void:
		_test_reward_multiset_and_heal(harness)
	)
	harness.run_test("M5 normal reward groups can be skipped independently", func() -> void:
		_test_normal_reward_groups(harness)
	)
	harness.run_test("M5 shops publish 3 plus 3 at chapter prices and allow duplicate skills", func() -> void:
		_test_shop_options_and_prices(harness)
	)
	harness.run_test("M5 shop purchases apply discounts and reject insufficient or repeated buys", func() -> void:
		_test_shop_purchase_atomicity(harness)
	)
	harness.run_test("M5 tradePermit sells exactly one skill copy at undiscounted price", func() -> void:
		_test_trade_permit_single_copy(harness)
	)
	harness.run_test("M5 forge offers class upgrades and restores for free then rising prices", func() -> void:
		_test_forge_options_and_restore(harness)
	)
	harness.run_test("M5 events grant chapter currency once on authoritative entry", func() -> void:
		_test_event_currency(harness)
	)
	harness.run_test("M5 option tampering stale ids and duplicate submissions preserve Run and RNG", func() -> void:
		_test_option_authority_and_rng(harness)
	)
	harness.run_test("M5 active option snapshots cannot be re-authorized from Run payload", func() -> void:
		_test_option_reload_rejected(harness)
	)
	harness.run_test("M5 reward currency overflow is rejected before reward RNG", func() -> void:
		_test_reward_overflow_preflight(harness)
	)


func _test_reward_scales_and_filters(harness: TestHarness) -> void:
	var cases := {
		"battle": {"skills": 3, "relics": -1, "currency": 15},
		"elite": {"skills": 2, "relics": 1, "currency": 25},
		"boss": {"skills": 1, "relics": 2, "currency": 40},
	}
	for node_type: String in cases:
		var fixture := _started_fixture("m5-04-reward-%s" % node_type, 1, harness)
		var state: Dictionary = fixture["state"]
		var lifecycle: Variant = fixture["lifecycle"]
		var catalogs: Dictionary = fixture["catalogs"]
		var errors: Array[String] = []
		_choose_type(lifecycle, state, node_type, harness, errors)
		var before_currency: int = state["currency"]
		harness.assert_true(lifecycle.complete_current_battle(true, errors), "; ".join(errors))
		harness.assert_equal(state["status"], "reward")
		harness.assert_equal(state["currency"], before_currency + cases[node_type]["currency"])
		var cards: Array = state["reward_options"].filter(func(option: Dictionary) -> bool:
			return option["type"] != "relic"
		)
		var relics: Array = state["reward_options"].filter(func(option: Dictionary) -> bool:
			return option["type"] == "relic"
		)
		harness.assert_equal(cards.size(), cases[node_type]["skills"])
		if node_type == "battle":
			harness.assert_true(relics.size() in [0, 3])
		else:
			harness.assert_equal(relics.size(), cases[node_type]["relics"])
		for option: Dictionary in cards:
			harness.assert_true(option["type"] in ["freeSkill", "exclusiveCard"])
			if option["type"] == "freeSkill":
				harness.assert_false(option["payload_id"] == "basicDamage")
				harness.assert_false(option["payload_id"] == "pieceAction")
			harness.assert_equal(option["price"], 0)
		for option: Dictionary in relics:
			var definition: Variant = catalogs["relics"][option["payload_id"]]
			harness.assert_false(option["payload_id"] in [
				"shentongAssaultBurst", "shentongChargeOverload",
			])
			harness.assert_false(definition.category in ["classUpgrade", "shentongEvolve"])
			harness.assert_equal(option["price"], 0)


func _test_reward_multiset_and_heal(harness: TestHarness) -> void:
	var duplicate := _started_fixture("m5-04-reward-duplicate", 1, harness)
	var duplicate_state: Dictionary = duplicate["state"]
	var duplicate_lifecycle: Variant = duplicate["lifecycle"]
	var duplicate_errors: Array[String] = []
	duplicate_state["free_skill_ids"] = _player_free_skill_ids(duplicate["catalogs"])
	_choose_type(duplicate_lifecycle, duplicate_state, "elite", harness, duplicate_errors)
	harness.assert_true(
		duplicate_lifecycle.complete_current_battle(true, duplicate_errors),
		"; ".join(duplicate_errors),
	)
	var skill_option: Dictionary = duplicate_state["reward_options"].filter(
		func(option: Dictionary) -> bool: return option["type"] == "freeSkill"
	)[0]
	var count_before: int = duplicate_state["free_skill_ids"].count(skill_option["payload_id"])
	harness.assert_true(
		duplicate_lifecycle.select_reward(skill_option["id"], duplicate_errors),
		"; ".join(duplicate_errors),
	)
	harness.assert_equal(
		duplicate_state["free_skill_ids"].count(skill_option["payload_id"]), count_before + 1,
	)

	var healing := _started_fixture("m5-04-reward-heal", 1, harness)
	var heal_state: Dictionary = healing["state"]
	var heal_lifecycle: Variant = healing["lifecycle"]
	var heal_errors: Array[String] = []
	heal_state["relic_ids"] = _standard_relic_ids(healing["catalogs"])
	var ratios := [0.0, 0.2, 0.8, 1.0, 0.5, 0.01]
	for index in ratios.size():
		heal_state["piece_slots"][index]["hp_ratio"] = ratios[index]
	_choose_type(heal_lifecycle, heal_state, "battle", harness, heal_errors)
	harness.assert_true(heal_lifecycle.complete_current_battle(true, heal_errors), "; ".join(heal_errors))
	harness.assert_equal(heal_state["reward_options"].filter(
		func(option: Dictionary) -> bool: return option["type"] != "relic"
	).size(), 3)
	harness.assert_true(heal_lifecycle.skip_normal_reward_group("card", heal_errors), "; ".join(heal_errors))
	if heal_state["status"] == "reward":
		harness.assert_true(heal_lifecycle.skip_normal_reward_group("relic", heal_errors), "; ".join(heal_errors))
	# Skipping both groups leaves formation health untouched, including empty and
	# defeated positions.
	harness.assert_equal(_piece_ratios(heal_state), ratios)


func _test_normal_reward_groups(harness: TestHarness) -> void:
	var fixture := _started_fixture("m5-04-normal-groups", 1, harness)
	var state: Dictionary = fixture["state"]
	var lifecycle: Variant = fixture["lifecycle"]
	var errors: Array[String] = []
	_choose_type(lifecycle, state, "battle", harness, errors)
	harness.assert_true(lifecycle.complete_current_battle(true, errors), "; ".join(errors))
	var cards: Array = state["reward_options"].filter(func(option: Dictionary) -> bool:
		return option["type"] != "relic"
	)
	harness.assert_equal(cards.size(), 3)
	harness.assert_true(lifecycle.skip_normal_reward_group("card", errors), "; ".join(errors))
	if state["status"] == "reward":
		harness.assert_true(state["reward_options"].all(func(option: Dictionary) -> bool:
			return option["type"] == "relic"
		))
		harness.assert_true(lifecycle.skip_normal_reward_group("relic", errors), "; ".join(errors))
	harness.assert_equal(state["status"], "map")


func _test_shop_options_and_prices(harness: TestHarness) -> void:
	for chapter in [1, 2, 3]:
		var fixture := _started_fixture("m5-04-shop-%d" % chapter, chapter, harness)
		var state: Dictionary = fixture["state"]
		var lifecycle: Variant = fixture["lifecycle"]
		var catalogs: Dictionary = fixture["catalogs"]
		var errors: Array[String] = []
		state["free_skill_ids"] = _player_free_skill_ids(catalogs)
		_choose_type(lifecycle, state, "shop", harness, errors)
		var cards: Array = state["shop_options"].filter(func(option: Dictionary) -> bool:
			return option["type"] in ["shopFreeSkill", "shopExclusiveCard"]
		)
		var skills: Array = cards.filter(func(option: Dictionary) -> bool:
			return option["type"] == "shopFreeSkill"
		)
		var relics: Array = state["shop_options"].filter(func(option: Dictionary) -> bool:
			return option["type"] == "shopRelic"
		)
		harness.assert_equal(cards.size(), 3)
		harness.assert_equal(relics.size(), 3)
		for option: Dictionary in cards:
			harness.assert_equal(option["price"], 18 + chapter * 2)
			if option["type"] == "shopFreeSkill":
				harness.assert_true(option["payload_id"] in state["free_skill_ids"])
				harness.assert_false(option["payload_id"] == "basicDamage")
				harness.assert_false(option["payload_id"] == "pieceAction")
		for option: Dictionary in relics:
			harness.assert_equal(option["price"], 35 + chapter * 5)
			harness.assert_false(option["payload_id"] in [
				"shentongAssaultBurst", "shentongChargeOverload",
			])
			harness.assert_false(catalogs["relics"][option["payload_id"]].category in [
				"classUpgrade", "shentongEvolve",
			])
		state["currency"] = 100
		var bought: Dictionary = skills[0]
		var copies_before: int = state["free_skill_ids"].count(bought["payload_id"])
		harness.assert_true(lifecycle.buy_shop_option(bought["id"], errors), "; ".join(errors))
		harness.assert_equal(state["free_skill_ids"].count(bought["payload_id"]), copies_before + 1)


func _test_shop_purchase_atomicity(harness: TestHarness) -> void:
	var fixture := _started_fixture("m5-04-shop-atomic", 1, harness)
	var state: Dictionary = fixture["state"]
	var lifecycle: Variant = fixture["lifecycle"]
	var raw: Variant = fixture["raw"]
	var errors: Array[String] = []
	state["relic_ids"].append("discountCard")
	_choose_type(lifecycle, state, "shop", harness, errors)
	var option: Dictionary = state["shop_options"][0]
	var expected_cost := int(ceil(float(option["price"]) * 0.75))
	harness.assert_equal(lifecycle.get_option_cost(option["id"], errors), expected_cost)
	state["currency"] = expected_cost - 1
	var before := state.duplicate(true)
	var rng_before: int = raw.state_snapshot()
	harness.assert_false(lifecycle.buy_shop_option(option["id"], errors))
	harness.assert_equal(state, before)
	harness.assert_equal(raw.state_snapshot(), rng_before)
	state["currency"] = 100
	harness.assert_true(lifecycle.buy_shop_option(option["id"], errors), "; ".join(errors))
	harness.assert_equal(state["currency"], 100 - expected_cost)
	harness.assert_true(state["shop_options"][0]["purchased"])
	var purchased := state.duplicate(true)
	rng_before = raw.state_snapshot()
	harness.assert_false(lifecycle.buy_shop_option(option["id"], errors))
	harness.assert_equal(state, purchased)
	harness.assert_equal(raw.state_snapshot(), rng_before)
	harness.assert_equal(lifecycle.get_option_cost(option["id"], errors), null)

	var readonly: Array = lifecycle.get_shop_options(errors)
	readonly[0]["price"] = 0
	harness.assert_false(state["shop_options"][0]["price"] == 0)


func _test_trade_permit_single_copy(harness: TestHarness) -> void:
	var denied := _started_fixture("m5-04-trade-denied", 1, harness)
	var denied_errors: Array[String] = []
	denied["state"]["free_skill_ids"] = ["smallHeal", "smallHeal", "markBurn"]
	_choose_type(denied["lifecycle"], denied["state"], "shop", harness, denied_errors)
	var denied_before: Dictionary = denied["state"].duplicate(true)
	harness.assert_false(denied["lifecycle"].sell_free_skill("smallHeal", denied_errors))
	harness.assert_equal(denied["state"], denied_before)

	var fixture := _started_fixture("m5-04-trade", 1, harness)
	var state: Dictionary = fixture["state"]
	var lifecycle: Variant = fixture["lifecycle"]
	var errors: Array[String] = []
	state["free_skill_ids"] = ["smallHeal", "smallHeal", "markBurn"]
	state["relic_ids"].append_array(["tradePermit", "discountCard"])
	_choose_type(lifecycle, state, "shop", harness, errors)
	state["currency"] = 0
	harness.assert_true(lifecycle.sell_free_skill("smallHeal", errors), "; ".join(errors))
	harness.assert_equal(state["free_skill_ids"].count("smallHeal"), 1)
	harness.assert_equal(state["currency"], 20, "sale price must ignore discountCard")
	harness.assert_true(lifecycle.sell_free_skill("smallHeal", errors), "; ".join(errors))
	harness.assert_equal(state["free_skill_ids"].count("smallHeal"), 0)
	harness.assert_equal(state["free_skill_ids"], ["markBurn"])


func _test_forge_options_and_restore(harness: TestHarness) -> void:
	for chapter in [1, 2, 3]:
		var priced := _started_fixture("m5-04-forge-%d" % chapter, chapter, harness)
		var priced_errors: Array[String] = []
		_choose_type(priced["lifecycle"], priced["state"], "forge", harness, priced_errors)
		harness.assert_equal(priced["state"]["shop_options"].size(), 3)
		for option: Dictionary in priced["state"]["shop_options"]:
			harness.assert_equal(option["type"], "forgeRelic")
			harness.assert_equal(option["price"], 30 + chapter * 5)
			harness.assert_equal(priced["catalogs"]["relics"][option["payload_id"]].category, "classUpgrade")

	var fixture := _started_fixture("m5-04-forge-restore", 1, harness)
	var state: Dictionary = fixture["state"]
	var lifecycle: Variant = fixture["lifecycle"]
	var errors: Array[String] = []
	_choose_type(lifecycle, state, "forge", harness, errors)
	harness.assert_equal(lifecycle.get_forge_heal_cost(errors), null)
	for index in state["piece_slots"].size():
		state["piece_slots"][index]["hp_ratio"] = 0.0 if index == 1 else 0.4
	state["currency"] = 100
	harness.assert_equal(lifecycle.get_forge_heal_cost(errors), 0)
	harness.assert_true(lifecycle.use_forge_heal(errors), "; ".join(errors))
	harness.assert_equal(_piece_ratios(state), [0.4, 1.0, 0.4, 1.0, 1.0, 1.0])
	harness.assert_equal(state["forge_uses_this_node"], 1)
	harness.assert_equal(lifecycle.get_forge_heal_cost(errors), null)
	state["piece_slots"][1]["hp_ratio"] = 0.5
	harness.assert_equal(lifecycle.get_forge_heal_cost(errors), 15)
	state["relic_ids"].append("discountCard")
	harness.assert_equal(lifecycle.get_forge_heal_cost(errors), 12)
	state["currency"] = 11
	var failed := state.duplicate(true)
	harness.assert_false(lifecycle.use_forge_heal(errors))
	harness.assert_equal(state, failed)
	state["currency"] = 12
	harness.assert_true(lifecycle.use_forge_heal(errors), "; ".join(errors))
	harness.assert_equal(state["currency"], 0)
	harness.assert_equal(state["forge_uses_this_node"], 2)
	state["piece_slots"][3]["hp_ratio"] = 0.5
	harness.assert_equal(lifecycle.get_forge_heal_cost(errors), 19)


func _test_event_currency(harness: TestHarness) -> void:
	for chapter in [1, 2, 3]:
		var fixture := _started_fixture("m5-04-event-%d" % chapter, chapter, harness)
		var state: Dictionary = fixture["state"]
		var lifecycle: Variant = fixture["lifecycle"]
		var errors: Array[String] = []
		var before: int = state["currency"]
		_choose_type(lifecycle, state, "event", harness, errors)
		harness.assert_equal(state["currency"], before + 10 + chapter * 2)
		harness.assert_equal(state["reward_options"], [])
		harness.assert_equal(state["shop_options"], [])
		harness.assert_true(lifecycle.complete_current_node(errors), "; ".join(errors))
		harness.assert_equal(state["currency"], before + 10 + chapter * 2)


func _test_option_authority_and_rng(harness: TestHarness) -> void:
	var tamper := _started_fixture("m5-04-tamper", 1, harness)
	var tamper_errors: Array[String] = []
	_choose_type(tamper["lifecycle"], tamper["state"], "shop", harness, tamper_errors)
	var original_id: String = tamper["state"]["shop_options"][0]["id"]
	tamper["state"]["shop_options"][0]["price"] = 0
	var tampered: Dictionary = tamper["state"].duplicate(true)
	var rng_before: int = tamper["raw"].state_snapshot()
	harness.assert_false(tamper["lifecycle"].buy_shop_option(original_id, tamper_errors))
	harness.assert_equal(tamper["state"], tampered)
	harness.assert_equal(tamper["raw"].state_snapshot(), rng_before)

	var stale := _started_fixture("m5-04-stale", 1, harness)
	var stale_errors: Array[String] = []
	_choose_type(stale["lifecycle"], stale["state"], "shop", harness, stale_errors)
	var stale_id: String = stale["state"]["shop_options"][0]["id"]
	harness.assert_true(stale["lifecycle"].complete_current_node(stale_errors), "; ".join(stale_errors))
	var after_leave: Dictionary = stale["state"].duplicate(true)
	rng_before = stale["raw"].state_snapshot()
	harness.assert_false(stale["lifecycle"].buy_shop_option(stale_id, stale_errors))
	harness.assert_equal(stale["state"], after_leave)
	harness.assert_equal(stale["raw"].state_snapshot(), rng_before)

	var reward := _started_fixture("m5-04-repeat-reward", 1, harness)
	var reward_errors: Array[String] = []
	_choose_type(reward["lifecycle"], reward["state"], "battle", harness, reward_errors)
	harness.assert_true(reward["lifecycle"].complete_current_battle(true, reward_errors), "; ".join(reward_errors))
	var reward_id: String = reward["state"]["reward_options"][0]["id"]
	harness.assert_true(reward["lifecycle"].select_reward(reward_id, reward_errors), "; ".join(reward_errors))
	var after_reward: Dictionary = reward["state"].duplicate(true)
	rng_before = reward["raw"].state_snapshot()
	harness.assert_false(reward["lifecycle"].select_reward(reward_id, reward_errors))
	harness.assert_equal(reward["state"], after_reward)
	harness.assert_equal(reward["raw"].state_snapshot(), rng_before)


func _test_option_reload_rejected(harness: TestHarness) -> void:
	var fixture := _started_fixture("m5-04-reload", 1, harness)
	var errors: Array[String] = []
	_choose_type(fixture["lifecycle"], fixture["state"], "shop", harness, errors)
	var copied_state: Dictionary = fixture["state"].duplicate(true)
	var copied_random := TransactionalRandomScript.new(RngScript.seeded("m5-04-reload-copy"), errors)
	var loaded := RunLifecycleScript.new(copied_state, fixture["catalogs"], copied_random, errors)
	harness.assert_false(loaded.is_valid())
	harness.assert_contains("; ".join(errors), "authoritative snapshots")


func _test_reward_overflow_preflight(harness: TestHarness) -> void:
	var fixture := _started_fixture("m5-04-overflow", 1, harness)
	var state: Dictionary = fixture["state"]
	var lifecycle: Variant = fixture["lifecycle"]
	var errors: Array[String] = []
	_choose_type(lifecycle, state, "battle", harness, errors)
	state["currency"] = 9223372036854775807
	var before := state.duplicate(true)
	var rng_before: int = fixture["raw"].state_snapshot()
	harness.assert_false(lifecycle.complete_current_battle(true, errors))
	harness.assert_equal(state, before)
	harness.assert_equal(fixture["raw"].state_snapshot(), rng_before)
	harness.assert_contains("; ".join(errors), "currency")


func _started_fixture(
	seed: String,
	chapter: int,
	harness: TestHarness,
) -> Dictionary:
	var errors: Array[String] = []
	var catalogs := ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	var state := RunContractScript.create()
	var raw := RngScript.seeded(seed)
	var random := TransactionalRandomScript.new(raw, errors)
	var lifecycle := RunLifecycleScript.new(state, catalogs, random, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	var hero_id: int = state["initial_hero_choice_ids"][0]
	harness.assert_true(lifecycle.choose_starting_hero(hero_id, errors), "; ".join(errors))
	if chapter != 1:
		state["chapter"] = chapter
		state["map_nodes"] = MapSystemScript.build_chapter_map(
			catalogs["roguelike_content"], chapter, RngScript.seeded("%s-map" % seed), errors,
		)
		harness.assert_equal(errors, [])
	return {
		"state": state,
		"catalogs": catalogs,
		"raw": raw,
		"random": random,
		"lifecycle": lifecycle,
	}


func _choose_type(
	lifecycle: Variant,
	state: Dictionary,
	node_type: String,
	harness: TestHarness,
	errors: Array[String],
) -> Dictionary:
	var selected: Dictionary = {}
	for node: Dictionary in state["map_nodes"]:
		node["available"] = false
		if selected.is_empty() and node["type"] == node_type:
			selected = node
	harness.assert_false(selected.is_empty(), "chapter must contain %s" % node_type)
	if selected.is_empty():
		return {}
	selected["available"] = true
	harness.assert_true(lifecycle.choose_node(selected["id"], errors), "; ".join(errors))
	return selected


func _player_free_skill_ids(catalogs: Dictionary) -> Array:
	return catalogs["skills"].keys().filter(func(skill_id: Variant) -> bool:
		return skill_id not in ["basicDamage", "pieceAction"]
	)


func _standard_relic_ids(catalogs: Dictionary) -> Array:
	return catalogs["relics"].keys().filter(func(relic_id: Variant) -> bool:
		return (
			catalogs["relics"][relic_id].category not in ["classUpgrade", "shentongEvolve"]
			and relic_id not in ["shentongAssaultBurst", "shentongChargeOverload"]
		)
	)


func _piece_ratios(state: Dictionary) -> Array:
	return state["piece_slots"].map(func(entry: Dictionary) -> float:
		return entry["hp_ratio"]
	)
