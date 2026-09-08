extends RefCounted

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const AdapterScript = preload("res://app/roguelike_battle_adapter.gd")
const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const RngScript = preload("res://core/rng.gd")

const SEED := "m5-06-three-chapter-no-shentong"
const EVOLUTION_RELIC_IDS := ["shentongAssaultBurst", "shentongChargeOverload"]
const DORMANT_CALL_TOKENS := [
	"dormant_shentong_domain.gd",
	"dormant_shentong_battle_port.gd",
	"DormantShentongDomain",
	"DormantShentongBattlePort",
	"shentong.charge",
	"shentong.assault",
	"shentong.sacrifice",
	"use_shentong",
]


func run(harness: TestHarness) -> void:
	harness.run_test("M5 fixed seed clears all three chapters without shentong", func() -> void:
		_test_three_chapter_clear(harness)
	)
	harness.run_test("M5 production composition UI and InputMap keep shentong dormant", func() -> void:
		_test_no_production_wiring(harness)
	)


func _test_three_chapter_clear(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	var state: Dictionary = RunContractScript.create()
	var raw: Variant = RngScript.seeded(SEED)
	var random: Variant = TransactionalRandomScript.new(raw, errors)
	var lifecycle: Variant = RunLifecycleScript.new(state, catalogs, random, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	var starting_hero_id: int = state["initial_hero_choice_ids"][0]
	harness.assert_true(lifecycle.choose_starting_hero(starting_hero_id, errors), "; ".join(errors))
	harness.assert_false(state.has("selected_shentong_id"))

	var trace := {
		"node_ids": [],
		"battle_commits": 0,
		"boss_wins": [],
		"normal_relic_acquired": false,
		"economy_purchase": false,
		"recruits": 0,
	}
	var guard := 0
	while state["status"] != "cleared" and guard < 40:
		guard += 1
		harness.assert_equal(state["status"], "map")
		if state["status"] != "map":
			return
		var node: Dictionary = _choose_path_node(state, trace)
		harness.assert_false(node.is_empty(), "the fixed path must expose a next node")
		if node.is_empty():
			return
		trace["node_ids"].append(node["id"])
		harness.assert_true(lifecycle.choose_node(node["id"], errors), "; ".join(errors))
		match state["status"]:
			"fighting":
				if not _win_through_real_adapter(lifecycle, state, node, trace, harness):
					return
			"shop":
				_use_economy_once(lifecycle, state, trace, harness)
				harness.assert_true(lifecycle.complete_current_node(errors), "; ".join(errors))
			"forge", "event":
				harness.assert_true(lifecycle.complete_current_node(errors), "; ".join(errors))
			_:
				harness.fail("unexpected M5 node status: %s" % state["status"])
				return
		_resolve_reward_chain(lifecycle, state, catalogs, trace, harness)

	harness.assert_true(guard < 40, "three chapters must terminate after exactly thirty nodes")
	harness.assert_equal(state["status"], "cleared")
	harness.assert_equal(state["chapter"], 3)
	harness.assert_equal(trace["node_ids"].size(), 30)
	harness.assert_equal(trace["boss_wins"], [1, 2, 3])
	harness.assert_true(trace["battle_commits"] >= 3)
	harness.assert_true(trace["normal_relic_acquired"])
	harness.assert_true(trace["economy_purchase"])
	harness.assert_true(trace["recruits"] >= 2)
	harness.assert_true(lifecycle.validate(errors), "; ".join(errors))
	harness.assert_false(state.has("selected_shentong_id"))
	for relic_id: String in state["relic_ids"]:
		harness.assert_false(relic_id in EVOLUTION_RELIC_IDS)


func _choose_path_node(state: Dictionary, trace: Dictionary) -> Dictionary:
	var available: Array = state["map_nodes"].filter(func(node: Dictionary) -> bool:
		return node["available"] and not node["completed"]
	)
	if available.is_empty():
		return {}
	available.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left["row"] < right["row"]
	)
	var column: int = available[0]["column"]
	# Chapter one deliberately stays on row two through the first economy column.
	# The authored column-three row is a shop, so this fixed path always exercises
	# a purchase without mutating map authority or manufacturing availability.
	if state["chapter"] == 1 and column <= 3:
		for node: Dictionary in available:
			if node["row"] == 2:
				return node
	if not trace["economy_purchase"]:
		for node: Dictionary in available:
			if node["type"] == "shop":
				return node
	return available[0]


func _win_through_real_adapter(
	lifecycle: Variant,
	state: Dictionary,
	node: Dictionary,
	trace: Dictionary,
	harness: TestHarness,
) -> bool:
	var manager := HandManagerScript.new()
	var adapter: Variant = AdapterScript.new(lifecycle, manager)
	var errors: Array[String] = []
	var started: Variant = adapter.start(errors)
	harness.assert_true(started.ok, started.message if not started.ok else "; ".join(errors))
	if not started.ok:
		manager.free()
		return false
	var controller: Variant = adapter.controller()
	harness.assert_false(controller.has_method("use_shentong"))
	var battle_state: Dictionary = controller._runtime.component("state")
	if trace["battle_commits"] == 0:
		battle_state["allies"][0]["hp"] = float(battle_state["allies"][0]["max_hp"]) * 0.75
		battle_state["allies"][0]["alive"] = true
	battle_state["game_over"] = true
	battle_state["battle_result"] = "win"
	harness.assert_true(adapter.settle_if_terminal(errors), "; ".join(errors))
	harness.assert_true(adapter.is_settled())
	trace["battle_commits"] += 1
	if trace["battle_commits"] == 1:
		harness.assert_equal(state["piece_slots"][0]["hp_ratio"], 0.75)
	if node["type"] == "boss":
		trace["boss_wins"].append(node["chapter"])
	manager.free()
	return true


func _use_economy_once(
	lifecycle: Variant,
	state: Dictionary,
	trace: Dictionary,
	harness: TestHarness,
) -> void:
	if trace["economy_purchase"]:
		return
	var errors: Array[String] = []
	var option: Dictionary = {}
	for candidate: Dictionary in state["shop_options"]:
		if candidate["type"] == "shopFreeSkill":
			option = candidate
			break
	harness.assert_false(option.is_empty(), "the authored shop must expose free skills")
	if option.is_empty():
		return
	var currency_before: int = state["currency"]
	var copies_before: int = state["free_skill_ids"].count(option["payload_id"])
	var cost: Variant = lifecycle.get_option_cost(option["id"], errors)
	harness.assert_true(typeof(cost) == TYPE_INT and cost <= currency_before)
	harness.assert_true(lifecycle.buy_shop_option(option["id"], errors), "; ".join(errors))
	harness.assert_equal(state["currency"], currency_before - int(cost))
	harness.assert_equal(state["free_skill_ids"].count(option["payload_id"]), copies_before + 1)
	trace["economy_purchase"] = true


func _resolve_reward_chain(
	lifecycle: Variant,
	state: Dictionary,
	catalogs: Dictionary,
	trace: Dictionary,
	harness: TestHarness,
) -> void:
	var errors: Array[String] = []
	var guard := 0
	while state["status"] == "reward" and guard < 3:
		guard += 1
		var options: Array = state["reward_options"]
		harness.assert_false(options.is_empty(), "reward status must expose authoritative options")
		if options.is_empty():
			return
		if options[0]["type"] == "hero":
			var roster_before: int = state["hero_deployment_slots"].size()
			harness.assert_true(lifecycle.recruit_hero(options[0]["payload_id"], errors), "; ".join(errors))
			harness.assert_equal(state["hero_deployment_slots"].size(), roster_before + 1)
			trace["recruits"] += 1
			continue
		var selected: Dictionary = options[0]
		if not trace["normal_relic_acquired"]:
			for option: Dictionary in options:
				if option["type"] == "relic":
					selected = option
					break
		if selected["type"] == "relic":
			var relic: Variant = catalogs["relics"][selected["payload_id"]]
			harness.assert_false(selected["payload_id"] in EVOLUTION_RELIC_IDS)
			harness.assert_false(relic.category in ["classUpgrade", "shentongEvolve"])
		harness.assert_true(lifecycle.select_reward(selected["id"], errors), "; ".join(errors))
		if selected["type"] == "relic":
			harness.assert_true(selected["payload_id"] in state["relic_ids"])
			trace["normal_relic_acquired"] = true
	harness.assert_true(guard < 3, "reward plus recruitment chain must terminate")


func _test_no_production_wiring(harness: TestHarness) -> void:
	var production_files := [
		"res://systems/roguelike/run_contract.gd",
		"res://systems/roguelike/run_lifecycle.gd",
		"res://systems/roguelike/run_battle_progress.gd",
		"res://autoload/game_root.gd",
		"res://app/battle_controller.gd",
		"res://project.godot",
	]
	_collect_source_files("res://ui", production_files)
	for path: String in production_files:
		var file := FileAccess.open(path, FileAccess.READ)
		harness.assert_not_null(file, "must read production boundary: %s" % path)
		if file == null:
			continue
		var source: String = file.get_as_text()
		for token: String in DORMANT_CALL_TOKENS:
			harness.assert_false(
				source.contains(token),
				"%s must not wire dormant token %s" % [path, token],
			)
	for action: StringName in InputMap.get_actions():
		harness.assert_false(str(action).to_lower().contains("shentong"))
	var manager := HandManagerScript.new()
	var controller: Variant = ControllerScript.new(manager)
	harness.assert_false(controller.has_method("use_shentong"))
	controller = null
	manager.free()


func _collect_source_files(path: String, destination: Array) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			_collect_source_files(path.path_join(entry), destination)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
			destination.append(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
