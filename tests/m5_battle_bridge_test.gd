extends RefCounted

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const RunProgressScript = preload("res://systems/roguelike/run_battle_progress.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const AdapterScript = preload("res://app/roguelike_battle_adapter.gd")
const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const RngScript = preload("res://core/rng.gd")
const ContextsScript = preload("res://core/contexts.gd")
const StatsScript = preload("res://core/stats.gd")
const PieceReactionsScript = preload("res://systems/combat/piece_reactions.gd")
const BattleBootstrapScript = preload("res://app/battle_bootstrap.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("M5 Run launch injects roster duplicate cards encounter and non-shentong relics", func() -> void:
		_test_launch_projection(harness)
	)
	harness.run_test("M5 Run trigger relic actions execute through the live combat graph", func() -> void:
		_test_trigger_relic_actions(harness)
	)
	harness.run_test("M5 paid card drives Arc Conductor through the live adapter and can kill the last enemies", func() -> void:
		_test_arc_conductor_from_paid_card(harness)
	)
	harness.run_test("M5 paid super counter triggers Arc Conductor before safely hitting a dead attacker", func() -> void:
		_test_arc_conductor_from_super_counter(harness)
	)
	harness.run_test("M5 Run victory atomically commits HP growth and enters reward", func() -> void:
		_test_victory_commit(harness)
	)
	harness.run_test("M5 Run defeat discards HP and permanent growth draft", func() -> void:
		_test_defeat_discard(harness)
	)
	harness.run_test("M5 fake stale repeat settlement preserves Run and transaction RNG", func() -> void:
		_test_settlement_authority(harness)
	)
	harness.run_test("M5 bridge preserves the frozen M4 direct battle config", func() -> void:
		_test_direct_battle_compatibility(harness)
	)
	harness.run_test("Run enemy Yizhes progress from 军令 to 铁卫 to 千机 by chapter", func() -> void:
		_test_run_enemy_yizhe_layers(harness)
	)


func _test_launch_projection(harness: TestHarness) -> void:
	var fixture := _fighting_fixture("m5-05-launch", harness)
	var state: Dictionary = fixture["state"]
	state["free_skill_ids"] = ["smallHeal", "smallHeal", "pieceBlock"]
	state["relic_ids"] = ["spLimitPlus", "shieldPlus", "crossbowPlus", "shentongAssaultBurst", "shentongChargeOverload"]
	state["piece_slots"][0]["hp_ratio"] = 0.0
	state["piece_slots"][3]["hp_ratio"] = 0.5
	var started := _start_adapter(fixture, harness)
	if not started["result"].ok:
		return
	var controller: Variant = started["adapter"].controller()
	var runtime_state: Dictionary = controller._runtime.component("state")
	var session: Dictionary = started["manager"].session_snapshot()
	harness.assert_equal(session["deployed_hero_ids"], state["front_hero_ids"] + state["back_hero_ids"])
	harness.assert_equal(session["free_skill_ids"], ["smallHeal", "smallHeal", "pieceBlock"])
	harness.assert_equal(session["deck_card_ids"].count("free:smallHeal"), 2)
	harness.assert_equal(runtime_state["sp_max"], 11.0)
	harness.assert_equal(runtime_state["allies"][0]["hp"], 0.0)
	harness.assert_false(runtime_state["allies"][0]["alive"])
	harness.assert_equal(runtime_state["allies"][3]["hp"], roundf(runtime_state["allies"][3]["max_hp"] * 0.5))
	harness.assert_equal(runtime_state["allies"].map(func(unit: Dictionary) -> String:
		return unit["class_id"]
	), ["default", "shield", "default", "assassin", "crossbow", "banner"])
	harness.assert_equal(runtime_state["allies"][3]["max_hp"], 240.0)
	harness.assert_equal(runtime_state["allies"][3]["atk"], 42.0)
	harness.assert_true(is_equal_approx(runtime_state["allies"][3]["crit_rate"], 0.15))
	harness.assert_false(runtime_state["allies"][2]["alive"], "empty slot is not a dead deployed piece")
	harness.assert_equal(runtime_state["allies"][4]["max_hp"], 280.0)
	harness.assert_equal(runtime_state["allies"][4]["atk"], 30.0)
	harness.assert_equal(runtime_state["allies"][5]["max_hp"], 360.0)
	harness.assert_equal(runtime_state["allies"][5]["atk"], 26.0)
	harness.assert_equal(controller._runtime.component("relic_system").has("spLimitPlus"), true)
	harness.assert_equal(controller._runtime.component("relic_system").has("shieldPlus"), true)
	harness.assert_equal(controller._runtime.component("relic_system").has("crossbowPlus"), true)
	harness.assert_equal(
		controller._runtime.component("relic_system").get_crossbow_pursuit_chance(
			0.5, runtime_state["allies"][4],
		),
		0.6,
	)
	harness.assert_equal(
		controller._runtime.component("relic_system").get_crossbow_pursuit_chance(
			0.5, runtime_state["allies"][5],
		),
		0.5,
	)
	var shield: Dictionary = runtime_state["allies"][1]
	shield["hp"] = shield["max_hp"] - 100.0
	shield["alive"] = true
	shield["base_block_rate"] = 1.0
	var block_errors: Array[String] = []
	var block_effect := ContextsScript.create_effect_context({
		"source_type": "basic_attack", "source_id": "class_mapping_probe",
		"source_name": "职业投影探针", "source_side": "enemy", "source_actor_id": 101,
		"counts_as_basic_attack": true, "counts_as_attack": true,
	}, block_errors)
	var block_context := ContextsScript.create_damage_context({
		"target_id": shield["id"], "raw_amount": 20.0, "category": "direct",
		"effect": block_effect, "dealer_type": "piece", "dealer_name": "职业投影探针",
		"dealer_id": 101, "attacker_unit_id": 101, "can_crit": false,
		"crit_rate": 0.0, "guaranteed_crit": false, "can_block": true,
	}, block_errors)
	harness.assert_equal(block_errors, [])
	var block_result: Dictionary = controller._runtime.component("damage").apply(
		shield, block_context, {"attacker_unit": runtime_state["enemies"][0]}, block_errors,
	)
	harness.assert_true(block_result["blocked"], "; ".join(block_errors))
	harness.assert_equal(shield["hp"], 343.3)
	harness.assert_true(controller.presentation_events().any(func(event: Dictionary) -> bool:
		return event["kind"] == "heal" and event["source"].get("id") == "shieldPlus"
	))
	harness.assert_false(controller._runtime.component("relic_system").has("shentongAssaultBurst"))
	harness.assert_false(controller._runtime.component("relic_system").has("shentongChargeOverload"))
	var alive_enemies: Array = runtime_state["enemies"].filter(func(unit: Dictionary) -> bool:
		return unit["alive"]
	)
	harness.assert_true(alive_enemies.size() > 0)
	for enemy: Dictionary in alive_enemies:
		harness.assert_true(enemy["hp"] > 0.0)
		harness.assert_true(enemy["atk"] >= 0.0)
	started["manager"].free()


func _test_trigger_relic_actions(harness: TestHarness) -> void:
	var fixture := _fighting_fixture("m5-05-trigger-relics", harness)
	var state: Dictionary = fixture["state"]
	state["relic_ids"] = ["rationChip", "fieldBandage"]
	var started := _start_adapter(fixture, harness)
	if not started["result"].ok:
		return
	var controller: Variant = started["adapter"].controller()
	var battle_state: Dictionary = controller._runtime.component("state")
	# The final four-unit Run formation keeps slot 1 empty; the shield occupies
	# slot 2 and is the live target for the relic-heal integration path.
	var target: Dictionary = battle_state["allies"][1]
	var errors: Array[String] = []
	var effect := ContextsScript.create_effect_context({
		"source_type": "basic_attack", "source_id": "test_attack",
		"source_name": "测试攻击", "source_side": "enemy", "source_actor_id": 101,
		"counts_as_basic_attack": true, "counts_as_attack": true,
	}, errors)
	var context := ContextsScript.create_damage_context({
		"target_id": target["id"], "raw_amount": 20.0, "category": "direct",
		"effect": effect, "dealer_type": "piece", "dealer_name": "测试攻击",
		"dealer_id": 101, "attacker_unit_id": 101, "can_crit": false,
		"crit_rate": 0.0, "guaranteed_crit": false, "can_block": false,
	}, errors)
	harness.assert_equal(errors, [])
	var before: float = target["hp"]
	var damage_result: Dictionary = controller._runtime.component("damage").apply(
		target, context, {}, errors,
	)
	harness.assert_false(damage_result.is_empty(), "; ".join(errors))
	harness.assert_equal(errors, [])
	harness.assert_equal(
		target["hp"],
		before - 20.0 + roundf(float(target["max_hp"]) * 0.02 * 10.0) / 10.0,
	)
	harness.assert_equal(controller.view_model()["fatal"], null)
	harness.assert_true(controller.presentation_events().any(func(event: Dictionary) -> bool:
		return event["kind"] == "heal" and event["source"].get("id") == "fieldBandage"
	))
	harness.assert_false(controller.presentation_events().any(func(event: Dictionary) -> bool:
		return event["kind"] == "fatal"
	))
	started["manager"].free()


func _test_arc_conductor_from_paid_card(harness: TestHarness) -> void:
	var fixture := _fighting_fixture("m5-05-arc-conductor-card", harness)
	var state: Dictionary = fixture["state"]
	state["free_skill_ids"] = ["pieceDamageUp", "pieceBlock"]
	state["relic_ids"] = ["arcConductor"]
	var started := _start_adapter(fixture, harness)
	if not started["result"].ok:
		return
	var controller: Variant = started["adapter"].controller()
	var battle_state: Dictionary = controller._runtime.component("state")
	var card_id := ""
	for card: Dictionary in controller.view_model()["hand"]:
		if card["source_skill_id"] == "pieceDamageUp":
			card_id = card["instance_id"]
			break
	harness.assert_false(card_id.is_empty(), "paid fixture card must be in the opening hand")
	if card_id.is_empty():
		started["manager"].free()
		return

	var expected_damage := roundf(
		StatsScript.team_average_atk(battle_state, "ally") * 0.6 * 10.0
	) / 10.0
	var targets: Array[Dictionary] = []
	for enemy: Dictionary in battle_state["enemies"]:
		if not enemy["alive"]:
			continue
		enemy["base_block_rate"] = 0.0
		enemy["hp"] = expected_damage
		targets.append(enemy)
	harness.assert_true(targets.size() > 0)
	var events_before: int = controller.presentation_events().size()
	var result: Variant = controller.play_card(card_id)
	harness.assert_true(result.ok, result.message)
	harness.assert_equal(result.details["actual_cost"], 1)
	harness.assert_equal(battle_state["sp"], 9.0)
	for enemy: Dictionary in targets:
		harness.assert_equal(enemy["hp"], 0.0)
		harness.assert_false(enemy["alive"])

	var arc_damage_events: Array[Dictionary] = []
	var arc_death_events: Array[Dictionary] = []
	for event: Dictionary in controller.presentation_events().slice(events_before):
		if event["source"].get("id") != "arcConductor":
			continue
		if event["event_id"] == "unit_damaged":
			arc_damage_events.append(event)
		elif event["event_id"] == "unit_died":
			arc_death_events.append(event)
	harness.assert_equal(arc_damage_events.size(), targets.size())
	harness.assert_equal(arc_death_events.size(), targets.size())
	for event: Dictionary in arc_damage_events:
		harness.assert_equal(event["source"]["type"], "relic")
		harness.assert_equal(event["source"]["side"], "ally")
		harness.assert_equal(event["payload"]["amount"], expected_damage)
		harness.assert_equal(event["payload"]["damage_context"]["raw_amount"], expected_damage)
		harness.assert_equal(event["payload"]["damage_context"]["effect"]["source_id"], "arcConductor")
		harness.assert_true(event["payload"]["died"])
	for enemy: Dictionary in targets:
		harness.assert_true(arc_damage_events.any(func(event: Dictionary) -> bool:
			return event["visual_target"]["unit_id"] == enemy["id"]
		))
		harness.assert_true(arc_death_events.any(func(event: Dictionary) -> bool:
			return event["visual_target"]["unit_id"] == enemy["id"] \
				and event["payload"]["death_context"]["effect"]["source_id"] == "arcConductor"
		))
	harness.assert_equal(controller.view_model()["fatal"], null)
	harness.assert_true(
		card_id in started["manager"].session_snapshot()["hand"]["piles"]["discard"],
		"lethal Arc Conductor damage must not strand the successfully played card",
	)
	started["manager"].free()


func _test_arc_conductor_from_super_counter(harness: TestHarness) -> void:
	var fixture := _fighting_fixture("m5-05-arc-conductor-counter", harness)
	fixture["state"]["relic_ids"] = ["arcConductor"]
	var started := _start_adapter(fixture, harness)
	if not started["result"].ok:
		return
	var controller: Variant = started["adapter"].controller()
	var battle_state: Dictionary = controller._runtime.component("state")
	var attacker: Dictionary = battle_state["enemies"].filter(func(unit: Dictionary) -> bool:
		return unit["alive"]
	)[0]
	var defender: Dictionary = battle_state["allies"].filter(func(unit: Dictionary) -> bool:
		return unit["alive"]
	)[0]
	for hero: Dictionary in battle_state["player_heroes"]:
		hero["deployed"] = hero["ex_skill"] == "counterAura"
	battle_state["sp"] = 5.0
	attacker["base_block_rate"] = 0.0
	attacker["hp"] = roundf(
		StatsScript.team_average_atk(battle_state, "ally") * 0.6 * 10.0
	) / 10.0
	var context_errors: Array[String] = []
	var attack_effect := ContextsScript.create_effect_context({
		"source_type": "basic_attack", "source_id": "counter_trigger_probe",
		"source_name": "反击触发探针", "source_side": "enemy",
		"source_actor_id": attacker["id"], "counts_as_basic_attack": true,
		"counts_as_attack": true,
	}, context_errors)
	var primary_context := ContextsScript.create_damage_context({
		"target_id": defender["id"], "raw_amount": 1.0, "category": "direct",
		"effect": attack_effect, "dealer_type": "piece", "dealer_name": "反击触发探针",
		"dealer_id": attacker["id"], "attacker_unit_id": attacker["id"],
		"can_crit": false, "crit_rate": 0.0, "guaranteed_crit": false, "can_block": true,
	}, context_errors)
	harness.assert_equal(context_errors, [])
	var events_before: int = controller.presentation_events().size()
	var result: Dictionary = PieceReactionsScript.resolve({
		"state": battle_state,
		"attacker_side": "enemy", "attacker_id": attacker["id"],
		"defender_side": "ally", "defender_id": defender["id"],
		"primary_hit": {
			"dealt": 1.0, "blocked": true, "died": false, "crit": false,
			"damage_context": primary_context, "death_context": null,
		},
		"defender_alive_after_primary_hit": true,
		"permanent_buffs": [],
	}, controller._runtime.component("ports"))
	harness.assert_true(result["ok"], result.get("error", ""))
	harness.assert_equal(result["value"]["counter_kind"], "super")
	harness.assert_equal(result["value"]["counter_dealt"], 0.0)
	harness.assert_equal(battle_state["sp"], 4.0)
	harness.assert_equal(attacker["hp"], 0.0)
	harness.assert_false(attacker["alive"])
	var new_events: Array[Dictionary] = controller.presentation_events().slice(events_before)
	harness.assert_equal(new_events.filter(func(event: Dictionary) -> bool:
		return event["event_id"] == "skillPointSpent"
	).size(), 1)
	harness.assert_equal(new_events.filter(func(event: Dictionary) -> bool:
		return event["event_id"] == "unit_died" \
			and event["source"].get("id") == "arcConductor" \
			and event["visual_target"].get("unit_id") == attacker["id"]
	).size(), 1)
	harness.assert_equal(controller.view_model()["fatal"], null)
	started["manager"].free()


func _test_victory_commit(harness: TestHarness) -> void:
	var fixture := _fighting_fixture("m5-05-victory", harness)
	var state: Dictionary = fixture["state"]
	var started := _start_adapter(fixture, harness)
	if not started["result"].ok:
		return
	var adapter: Variant = started["adapter"]
	var controller: Variant = adapter.controller()
	var battle_state: Dictionary = controller._runtime.component("state")
	var port_errors: Array[String] = []
	var growth_result: Dictionary = controller._runtime.component("ports").call_action(
		"stage_permanent_growth",
		{"requests": [{
			"id": "fistMastery", "target": {"type": "hero", "id": 6}, "stacks": 1,
		}]},
		port_errors,
	)
	harness.assert_true(growth_result["ok"], growth_result.get("error", ""))
	for index in battle_state["allies"].size():
		var unit: Dictionary = battle_state["allies"][index]
		unit["hp"] = 0.0 if index == 1 else float(unit["max_hp"]) * 0.25
		unit["alive"] = index != 1
	battle_state["game_over"] = true
	battle_state["battle_result"] = "win"
	var before_currency: int = state["currency"]
	var errors: Array[String] = []
	harness.assert_true(adapter.settle_if_terminal(errors), "; ".join(errors))
	harness.assert_equal(state["status"], "reward")
	harness.assert_equal(state["currency"], before_currency + 15)
	harness.assert_equal(state["piece_slots"][1]["hp_ratio"], 0.0)
	harness.assert_equal(_piece_ratios(state), [1.0, 0.0, 1.0, 0.25, 0.25, 0.25])
	harness.assert_equal(state["permanent_buffs"], [{
		"id": "fistMastery", "target": {"type": "hero", "id": 6}, "stacks": 1,
	}])
	var committed := state.duplicate(true)
	var rng_before: int = fixture["raw"].state_snapshot()
	harness.assert_false(adapter.settle_if_terminal(errors))
	harness.assert_equal(state, committed)
	harness.assert_equal(fixture["raw"].state_snapshot(), rng_before)
	started["manager"].free()


func _test_defeat_discard(harness: TestHarness) -> void:
	var fixture := _fighting_fixture("m5-05-defeat", harness)
	var state: Dictionary = fixture["state"]
	state["piece_slots"][2]["hp_ratio"] = 0.6
	var committed_progress := {
		"piece_slots": state["piece_slots"].duplicate(true),
		"permanent_buffs": state["permanent_buffs"].duplicate(true),
	}
	var started := _start_adapter(fixture, harness)
	if not started["result"].ok:
		return
	var controller: Variant = started["adapter"].controller()
	var battle_state: Dictionary = controller._runtime.component("state")
	var port_errors: Array[String] = []
	var growth: Dictionary = controller._runtime.component("ports").call_action(
		"stage_permanent_growth",
		{"requests": [{
			"id": "flamePractice", "target": {"type": "hero", "id": 5}, "stacks": 1,
		}]},
		port_errors,
	)
	harness.assert_true(growth["ok"], growth.get("error", ""))
	battle_state["allies"][2]["hp"] = 0.0
	battle_state["allies"][2]["alive"] = false
	battle_state["game_over"] = true
	battle_state["battle_result"] = "lose"
	var errors: Array[String] = []
	harness.assert_true(started["adapter"].settle_if_terminal(errors), "; ".join(errors))
	harness.assert_equal(state["status"], "failed")
	harness.assert_equal(state["piece_slots"], committed_progress["piece_slots"])
	harness.assert_equal(state["permanent_buffs"], committed_progress["permanent_buffs"])
	started["manager"].free()


func _test_settlement_authority(harness: TestHarness) -> void:
	var fixture := _fighting_fixture("m5-05-authority", harness)
	var state: Dictionary = fixture["state"]
	var launch_errors: Array[String] = []
	var launch: Dictionary = fixture["lifecycle"].begin_current_battle(launch_errors)
	harness.assert_false(launch.is_empty(), "; ".join(launch_errors))
	if launch.is_empty():
		return
	var fake_errors: Array[String] = []
	var fake := RunProgressScript.new({
		"run_state": state,
		"buff_catalog": fixture["catalogs"]["buffs"],
		"valid_hero_ids": fixture["catalogs"]["characters"]["players"].keys(),
	}, fake_errors)
	harness.assert_equal(fake_errors, [])
	var before := state.duplicate(true)
	var rng_before: int = fixture["raw"].state_snapshot()
	harness.assert_false(fixture["lifecycle"].settle_current_battle(fake, "win", _allies(), fake_errors))
	harness.assert_false(fixture["lifecycle"].settle_current_battle(launch["run_progress"], "stale", _allies(), fake_errors))
	harness.assert_equal(state, before)
	harness.assert_equal(fixture["raw"].state_snapshot(), rng_before)
	harness.assert_true(fixture["lifecycle"].cancel_current_battle_launch(launch["run_progress"], fake_errors))
	harness.assert_equal(state, before)


func _test_direct_battle_compatibility(harness: TestHarness) -> void:
	var manager := HandManagerScript.new()
	var controller := ControllerScript.new(manager)
	var result: Variant = controller.start({
		"battle_seed": "m5-05-m4-direct",
		"deployed_hero_ids": [1],
		"free_skill_ids": ["pieceBlock", "smallHeal"],
		"stage_id": "counter",
	})
	harness.assert_true(result.ok, result.message)
	if result.ok:
		harness.assert_true(controller.view_model()["initialized"])
		harness.assert_equal(manager.session_snapshot()["free_skill_ids"], ["pieceBlock", "smallHeal"])
		harness.assert_equal(controller._runtime.component("state")["allies"].map(
			func(unit: Dictionary) -> String: return unit["class_id"]
		), ["default", "default", "default", "default", "default", "default"])
	manager.free()


func _test_run_enemy_yizhe_layers(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var catalogs := ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	for stage_id in ["counter", "burn", "core"]:
		var definitions: Array = BattleBootstrapScript._enemy_yizhe_definitions(
			{"stage_id": stage_id, "run_progress": true}, catalogs,
			catalogs["stages"][stage_id], errors,
		)
		harness.assert_equal(errors, [])
		var expected_ids: Array = BattleBootstrapScript.RUN_ENEMY_HERO_IDS_BY_STAGE[stage_id]
		harness.assert_equal(definitions.map(func(enemy: Dictionary) -> Variant: return enemy["id"]), expected_ids)
		harness.assert_equal(definitions.map(func(enemy: Dictionary) -> Variant: return enemy["name"]), [
			"敌·军令", "敌·铁卫", "敌·千机",
		].slice(0, expected_ids.size()))
	# Direct stage selection still uses that stage's whole authored roster.
	var direct: Array = BattleBootstrapScript._enemy_yizhe_definitions(
		{"stage_id": "burn"}, catalogs, catalogs["stages"]["burn"], errors,
	)
	harness.assert_equal(errors, [])
	harness.assert_equal(direct.map(func(enemy: Dictionary) -> Variant: return enemy["id"]), [201, 202, 203])


func _fighting_fixture(seed: String, harness: TestHarness) -> Dictionary:
	var errors: Array[String] = []
	var catalogs := ContentCatalogScript.build(errors)
	harness.assert_equal(errors, [])
	var state := RunContractScript.create()
	var raw := RngScript.seeded(seed)
	var random := TransactionalRandomScript.new(raw, errors)
	var lifecycle := RunLifecycleScript.new(state, catalogs, random, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	harness.assert_true(lifecycle.choose_starting_hero(state["initial_hero_choice_ids"][0], errors), "; ".join(errors))
	var battle: Dictionary = {}
	for node: Dictionary in state["map_nodes"]:
		if battle.is_empty() and node["available"] and node["type"] == "battle":
			battle = node
	if battle.is_empty():
		for node: Dictionary in state["map_nodes"]:
			node["available"] = false
			if battle.is_empty() and node["type"] == "battle":
				battle = node
		battle["available"] = true
	harness.assert_false(battle.is_empty())
	harness.assert_true(lifecycle.choose_node(battle["id"], errors), "; ".join(errors))
	return {
		"catalogs": catalogs, "state": state, "raw": raw,
		"random": random, "lifecycle": lifecycle,
	}


func _start_adapter(fixture: Dictionary, harness: TestHarness) -> Dictionary:
	var manager := HandManagerScript.new()
	var adapter := AdapterScript.new(fixture["lifecycle"], manager)
	var errors: Array[String] = []
	var result: Variant = adapter.start(errors)
	harness.assert_true(result.ok, result.message if not result.ok else "; ".join(errors))
	return {"manager": manager, "adapter": adapter, "result": result}


func _allies() -> Array:
	var result: Array = []
	for slot in range(1, 7):
		result.append({
			"slot": slot, "side": "ally", "hp": 100.0, "max_hp": 100.0,
			"alive": true, "is_puppet": false,
		})
	return result


func _piece_ratios(state: Dictionary) -> Array:
	return state["piece_slots"].map(func(entry: Dictionary) -> float: return float(entry["hp_ratio"]))
