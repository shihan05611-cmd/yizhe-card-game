extends SceneTree

## A bounded, deterministic smoke simulation of the production M5 Run path.
## It deliberately uses only lifecycle authority plus BattleController commands.

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const AdapterScript = preload("res://app/roguelike_battle_adapter.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const RngScript = preload("res://core/rng.gd")

const SEEDS := ["real-run-001", "real-run-002", "real-run-003"]
const MAX_NODES := 30
const DEFAULT_MAX_TURNS_PER_BATTLE := 60
const MAX_CARD_COMMANDS_PER_TURN := 128
const MAX_COMMANDS_PER_BATTLE := 4096
const GROWTH_HERO_IDS := [6, 3, 5] # 宁不凡、元帅、炎术士

var _catalogs: Dictionary = {}
var _results: Array[Dictionary] = []
var _exceptions: Array[String] = []
var _strategy := "baseline"
var _max_turns_per_battle := DEFAULT_MAX_TURNS_PER_BATTLE
var _seeds: Array = SEEDS.duplicate()
var _inspect_choices := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--conservative-growth":
			_strategy = "conservative_growth"
		elif argument == "--inspect-choices":
			_inspect_choices = true
		elif argument.begins_with("--max-turns="):
			var value := argument.trim_prefix("--max-turns=")
			if value.is_valid_int() and int(value) > 0:
				_max_turns_per_battle = int(value)
		elif argument.begins_with("--seed="):
			var seed := argument.trim_prefix("--seed=")
			if seed in SEEDS:
				_seeds = [seed]
	var catalog_errors: Array[String] = []
	_catalogs = ContentCatalogScript.build(catalog_errors)
	if not catalog_errors.is_empty():
		_exceptions.append("content catalog: %s" % "; ".join(catalog_errors))
		_print_report()
		quit(1)
		return
	if _inspect_choices:
		_inspect_starting_choices()
		quit(0)
		return
	for seed: String in _seeds:
		var completed := _simulate_seed(seed)
		_results.append(completed)
		_print_seed_progress(completed)
	_print_report()
	quit(0 if _exceptions.is_empty() else 1)


func _simulate_seed(seed: String) -> Dictionary:
	var result := {
		"seed": seed,
		"start_hero": "",
		"start_hero_id": 0,
		"status": "setup_failed",
		"chapter": 0,
		"nodes": [],
		"battles": 0,
		"wins": 0,
		"losses": 0,
		"turns": 0,
		"cards_played": 0,
		"relics": 0,
		"heals": 0,
		"shop_purchases": 0,
		"recruits": 0,
		"cap_diagnostics": [],
		"notes": [],
	}
	var errors: Array[String] = []
	var state: Dictionary = RunContractScript.create()
	var random: Variant = TransactionalRandomScript.new(RngScript.seeded(seed), errors)
	var lifecycle: Variant = RunLifecycleScript.new(state, _catalogs, random, errors)
	if not errors.is_empty() or not lifecycle.start_run(errors):
		_note_failure(result, "start_run", errors)
		return result
	var hero_id := _preferred_starting_hero(state["initial_hero_choice_ids"])
	result["start_hero_id"] = hero_id
	result["start_hero"] = _hero_name(hero_id)
	if not lifecycle.choose_starting_hero(hero_id, errors):
		_note_failure(result, "choose_starting_hero", errors)
		return result

	var node_guard := 0
	while state["status"] == "map" and node_guard < MAX_NODES:
		node_guard += 1
		var node := _choose_node(state)
		if node.is_empty():
			_note_failure(result, "choose_node", ["no authoritative available node"])
			break
		result["nodes"].append("C%d-N%d-%s" % [node["chapter"], node["column"], node["type"]])
		if not lifecycle.choose_node(node["id"], errors):
			_note_failure(result, "choose_node", errors)
			break
		match str(state["status"]):
			"fighting":
				if not _fight(lifecycle, state, result):
					break
			"reward":
				if not _resolve_rewards(lifecycle, state, result):
					break
			"shop":
				_purchase_shop(lifecycle, state, result)
				if not _complete_node(lifecycle, result):
					break
			"forge":
				_use_forge(lifecycle, state, result)
				if not _complete_node(lifecycle, result):
					break
			"event":
				if not _complete_node(lifecycle, result):
					break
			_:
				_note_failure(result, "node", ["unexpected status %s" % str(state["status"])])
				break
		if state["status"] == "reward" and not _resolve_rewards(lifecycle, state, result):
			break
		if state["status"] == "failed":
			break
	if node_guard >= MAX_NODES and state["status"] == "map":
		_note_failure(result, "node_cap", ["reached %d nodes without terminal state" % MAX_NODES])
	result["status"] = str(state["status"])
	result["chapter"] = int(state["chapter"])
	return result


func _inspect_starting_choices() -> void:
	for seed: String in _seeds:
		var errors: Array[String] = []
		var state: Dictionary = RunContractScript.create()
		var random: Variant = TransactionalRandomScript.new(RngScript.seeded(seed), errors)
		var lifecycle: Variant = RunLifecycleScript.new(state, _catalogs, random, errors)
		if not errors.is_empty() or not lifecycle.start_run(errors):
			print("REAL RUN CHOICES: seed=%s error=%s" % [seed, "; ".join(errors)])
			continue
		var choices: Array[String] = []
		for hero_id: Variant in state["initial_hero_choice_ids"]:
			choices.append("%s(%d)" % [_hero_name(int(hero_id)), int(hero_id)])
		print("REAL RUN CHOICES: seed=%s choices=%s" % [seed, ", ".join(choices)])


func _fight(lifecycle: Variant, state: Dictionary, result: Dictionary) -> bool:
	var errors: Array[String] = []
	var manager := HandManagerScript.new()
	var adapter: Variant = AdapterScript.new(lifecycle, manager)
	var started: Variant = adapter.start(errors)
	if not started.ok:
		_note_failure(result, "battle_start", errors if not errors.is_empty() else [started.message])
		manager.free()
		return false
	var controller: Variant = adapter.controller()
	result["battles"] += 1
	var terminal := false
	var commands_this_battle := 0
	for turn in _max_turns_per_battle:
		var played_this_turn := {}
		var commands_this_turn := 0
		while not terminal:
			var view := _view_and_ack(controller)
			var instance_id := _next_playable_instance(view, played_this_turn)
			if instance_id.is_empty():
				break
			if (
				commands_this_turn >= MAX_CARD_COMMANDS_PER_TURN
				or commands_this_battle >= MAX_COMMANDS_PER_BATTLE
			):
				_stop_for_command_cap(state, controller, adapter, manager, result,
					commands_this_turn, commands_this_battle)
				return false
			played_this_turn[instance_id] = true
			var played: Variant = controller.play_card(instance_id)
			if not played.ok:
				_note_failure(result, "play_card", [played.message])
				_cancel_battle(adapter, manager)
				return false
			commands_this_turn += 1
			commands_this_battle += 1
			result["cards_played"] += 1
			if bool(_view_and_ack(controller)["battle"]["game_over"]):
				terminal = true
				break
		if terminal:
			break
		if commands_this_battle >= MAX_COMMANDS_PER_BATTLE:
			_stop_for_command_cap(state, controller, adapter, manager, result,
				commands_this_turn, commands_this_battle)
			return false
		var ended: Variant = controller.end_player_turn()
		if not ended.ok:
			_note_failure(result, "end_player_turn", [ended.message])
			_cancel_battle(adapter, manager)
			return false
		commands_this_battle += 1
		result["turns"] += 1
		if bool(_view_and_ack(controller)["battle"]["game_over"]):
			terminal = true
			break
	if not terminal:
		var diagnostic := _cap_diagnostic(state, _view_and_ack(controller))
		result["cap_diagnostics"].append(diagnostic)
		print("REAL RUN BATTLE CAP: seed=%s battle=%d %s" % [
			result["seed"], result["battles"], JSON.stringify(diagnostic),
		])
		_note_failure(result, "battle_turn_cap", ["reached %d turns" % _max_turns_per_battle])
		_cancel_battle(adapter, manager)
		return false
	var settlement: Dictionary = controller.settlement_snapshot()
	if not adapter.settle_if_terminal(errors):
		_note_failure(result, "battle_settlement", errors)
		manager.free()
		return false
	if settlement["battle_result"] == "win":
		result["wins"] += 1
	else:
		result["losses"] += 1
	print("REAL RUN BATTLE COMPLETE: seed=%s battle=%d node=%s result=%s turn=%d" % [
		result["seed"], result["battles"], JSON.stringify(_current_node_brief(state)),
		settlement["battle_result"], _view_and_ack(controller)["battle"]["round"],
	])
	manager.free()
	return settlement["battle_result"] == "win" or state["status"] == "failed"


func _resolve_rewards(lifecycle: Variant, state: Dictionary, result: Dictionary) -> bool:
	var guard := 0
	while state["status"] == "reward" and guard < 2:
		guard += 1
		var options: Array = state["reward_options"]
		if options.is_empty():
			_note_failure(result, "reward", ["authoritative options were empty"])
			return false
		var choice := _preferred_reward(state, options)
		var errors: Array[String] = []
		var ok := false
		if choice["type"] == "hero":
			ok = lifecycle.recruit_hero(choice["payload_id"], errors)
			if ok:
				result["recruits"] += 1
		else:
			ok = lifecycle.select_reward(choice["id"], errors)
			if ok and choice["type"] == "relic":
				result["relics"] += 1
			elif ok and choice["type"] == "heal":
				result["heals"] += 1
		if not ok:
			_note_failure(result, "reward", errors)
			return false
	if guard >= 2 and state["status"] == "reward":
		_note_failure(result, "reward_cap", ["reward chain did not close"])
		return false
	return true


func _purchase_shop(lifecycle: Variant, state: Dictionary, result: Dictionary) -> void:
	while true:
		var affordable: Dictionary = {}
		var wanted_types: Array = ["shopRelic", "shopFreeSkill"]
		if _strategy == "conservative_growth":
			wanted_types = ["shopRelic"]
		for wanted_type: String in wanted_types:
			for option: Dictionary in state["shop_options"]:
				if option["purchased"] or option["type"] != wanted_type:
					continue
				var cost: Variant = lifecycle.get_option_cost(option["id"])
				if typeof(cost) == TYPE_INT and int(cost) <= int(state["currency"]):
					affordable = option
					break
			if not affordable.is_empty():
				break
		if affordable.is_empty():
			return
		var errors: Array[String] = []
		if not lifecycle.buy_shop_option(affordable["id"], errors):
			_note_failure(result, "shop_purchase", errors)
			return
		result["shop_purchases"] += 1
		if affordable["type"] == "shopRelic":
			result["relics"] += 1


func _use_forge(lifecycle: Variant, state: Dictionary, result: Dictionary) -> void:
	var errors: Array[String] = []
	var heal_cost: Variant = lifecycle.get_forge_heal_cost(errors)
	if typeof(heal_cost) == TYPE_INT and int(heal_cost) <= int(state["currency"]):
		if lifecycle.use_forge_heal(errors):
			result["heals"] += 1
		else:
			_note_failure(result, "forge_heal", errors)
			return
	for option: Dictionary in state["shop_options"]:
		if option["purchased"]:
			continue
		var cost: Variant = lifecycle.get_option_cost(option["id"])
		if typeof(cost) != TYPE_INT or int(cost) > int(state["currency"]):
			continue
		if lifecycle.buy_forge_option(option["id"], errors):
			result["relics"] += 1
			result["shop_purchases"] += 1
		else:
			_note_failure(result, "forge_purchase", errors)
		return


func _complete_node(lifecycle: Variant, result: Dictionary) -> bool:
	var errors: Array[String] = []
	if lifecycle.complete_current_node(errors):
		return true
	_note_failure(result, "complete_node", errors)
	return false


func _choose_node(state: Dictionary) -> Dictionary:
	var available: Array = state["map_nodes"].filter(func(node: Dictionary) -> bool:
		return node["available"] and not node["completed"]
	)
	if available.is_empty():
		return {}
	available.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if left["column"] == right["column"]:
			return left["row"] < right["row"]
		return left["column"] < right["column"]
	)
	var priorities: Array = ["shop", "forge", "elite", "battle", "event", "boss"]
	if _strategy == "conservative_growth":
		var wounded: bool = state["piece_slots"].any(func(entry: Dictionary) -> bool:
			return float(entry["hp_ratio"]) < 0.999
		)
		priorities = ["forge", "battle", "event", "shop", "elite", "boss"] if wounded else [
			"battle", "event", "shop", "forge", "elite", "boss",
		]
	for wanted_type: String in priorities:
		for node: Dictionary in available:
			if node["type"] == wanted_type:
				return node
	return available[0]


func _preferred_reward(state: Dictionary, options: Array) -> Dictionary:
	if _strategy == "conservative_growth":
		for hero_id: int in GROWTH_HERO_IDS:
			for option: Dictionary in options:
				if option["type"] == "hero" and int(option["payload_id"]) == hero_id:
					return option
	for wanted_type: String in ["hero", "relic"]:
		for option: Dictionary in options:
			if option["type"] == wanted_type:
				return option
	var wounded: bool = state["piece_slots"].any(func(entry: Dictionary) -> bool:
		return float(entry["hp_ratio"]) < 0.999
	)
	if wounded:
		for option: Dictionary in options:
			if option["type"] == "heal":
				return option
	return options[0]


func _cancel_battle(adapter: Variant, manager: Node) -> void:
	var ignored: Array[String] = []
	adapter.cancel_open_launch(ignored)
	manager.free()


func _next_playable_instance(view: Dictionary, played_this_turn: Dictionary) -> String:
	for card: Dictionary in view["hand"]:
		var instance_id := str(card["instance_id"])
		if bool(card["playable"]) and not played_this_turn.has(instance_id):
			return instance_id
	return ""


func _view_and_ack(controller: Variant) -> Dictionary:
	var view: Dictionary = controller.view_model()
	var events: Array = view["presentation"]["pending_events"]
	if not events.is_empty():
		controller.acknowledge_presentation_through(int(events[-1]["sequence"]))
	return view


func _cap_diagnostic(state: Dictionary, view: Dictionary) -> Dictionary:
	var node := _current_node_brief(state)
	var hand: Array[String] = []
	for card: Dictionary in view["hand"]:
		hand.append("%s:%s" % [card["card_id"], card["name"]])
	return {
		"node": node,
		"round": view["battle"]["round"],
		"resources": view["resources"].duplicate(true),
		"piles": view["piles"].duplicate(true),
		"ally_hp": _team_hp(view["teams"]["ally"]),
		"enemy_hp": _team_hp(view["teams"]["enemy"]),
		"hand": hand,
	}


func _stop_for_command_cap(
	state: Dictionary,
	controller: Variant,
	adapter: Variant,
	manager: Node,
	result: Dictionary,
	commands_this_turn: int,
	commands_this_battle: int,
) -> void:
	var diagnostic := _cap_diagnostic(state, _view_and_ack(controller))
	diagnostic["reason"] = "command_cap"
	diagnostic["commands_this_turn"] = commands_this_turn
	diagnostic["commands_this_battle"] = commands_this_battle
	result["cap_diagnostics"].append(diagnostic)
	print("REAL RUN COMMAND CAP: seed=%s battle=%d %s" % [
		result["seed"], result["battles"], JSON.stringify(diagnostic),
	])
	_note_failure(result, "battle_command_cap", [
		"reached turn=%d battle=%d" % [MAX_CARD_COMMANDS_PER_TURN, MAX_COMMANDS_PER_BATTLE],
	])
	_cancel_battle(adapter, manager)


func _current_node_brief(state: Dictionary) -> Dictionary:
	for candidate: Dictionary in state["map_nodes"]:
		if candidate["id"] == state["current_node_id"]:
			return {
				"id": candidate["id"], "type": candidate["type"],
				"chapter": candidate["chapter"], "column": candidate["column"],
			}
	return {}


func _team_hp(team: Dictionary) -> Dictionary:
	var slots: Array[String] = []
	for unit: Dictionary in team["slots"]:
		slots.append("%d:%d/%d" % [unit["slot"], roundi(unit["hp"]), roundi(unit["max_hp"])])
	return {
		"current": roundi(team["current_hp"]), "max": roundi(team["max_hp"]), "slots": slots,
	}


func _hero_name(hero_id: int) -> String:
	var hero: Variant = _catalogs["characters"]["players"].get(hero_id)
	return str(hero.name) if hero != null else "未知弈者"


func _preferred_starting_hero(choice_ids: Array) -> int:
	if _strategy == "conservative_growth":
		for hero_id: int in GROWTH_HERO_IDS:
			if hero_id in choice_ids:
				return hero_id
	return int(choice_ids[0])


func _note_failure(result: Dictionary, scope: String, errors: Array) -> void:
	var detail := "; ".join(errors)
	if detail.length() > 420:
		detail = detail.left(417) + "..."
	var message := "%s: %s" % [scope, detail if not detail.is_empty() else "rejected without error"]
	result["notes"].append(message)
	_exceptions.append("%s / %s" % [result["seed"], message])


func _print_report() -> void:
	var clears := 0
	var failures := 0
	var battles := 0
	var turns := 0
	print("REAL RUN SIMULATION: strategy=%s seeds=%d max_turns_per_battle=%d" % [
		_strategy, _seeds.size(), _max_turns_per_battle,
	])
	for result: Dictionary in _results:
		clears += 1 if result["status"] == "cleared" else 0
		failures += 1 if result["status"] == "failed" else 0
		battles += int(result["battles"])
		turns += int(result["turns"])
		print("REAL RUN seed=%s hero=%s(%d) status=%s chapter=%d nodes=%d battles=%d wins=%d losses=%d turns=%d notes=%s" % [
			result["seed"], result["start_hero"], result["start_hero_id"], result["status"],
			result["chapter"], result["nodes"].size(), result["battles"], result["wins"],
			result["losses"], result["turns"], "; ".join(result["notes"]),
		])
		for diagnostic: Dictionary in result["cap_diagnostics"]:
			print("REAL RUN CAP: seed=%s %s" % [result["seed"], JSON.stringify(diagnostic)])
	print("REAL RUN SUMMARY: clears=%d failures=%d battles=%d avg_turns=%.2f exceptions=%d" % [
		clears, failures, battles, float(turns) / maxf(1.0, float(battles)), _exceptions.size(),
	])


func _print_seed_progress(result: Dictionary) -> void:
	print("REAL RUN COMPLETE: seed=%s status=%s chapter=%d nodes=%s battles=%d wins=%d losses=%d turns=%d" % [
		result["seed"], result["status"], result["chapter"], ",".join(result["nodes"]),
		result["battles"], result["wins"], result["losses"], result["turns"],
	])
