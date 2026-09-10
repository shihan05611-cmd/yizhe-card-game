extends RefCounted

const Fixture = preload("res://tests/m5_battle_bridge_test.gd")
const MapSystem = preload("res://systems/roguelike/map_system.gd")
const Rng = preload("res://core/rng.gd")
const Controller = preload("res://app/battle_controller.gd")
const HandManager = preload("res://autoload/hand_manager.gd")
const Contexts = preload("res://core/contexts.gd")
const PresentationQueue = preload("res://app/battle_presentation_queue.gd")

func run(harness: RefCounted) -> void:
	harness.run_test("production Run special monsters occupy once and execute live drain and echo hooks", func() -> void:
		for chapter in [1, 2]:
			var fixture: Dictionary = Fixture.new()._fighting_fixture("special-live-%d" % chapter, harness)
			var lifecycle: Variant = fixture["lifecycle"]
			var errors: Array[String] = []
			var launch: Dictionary = lifecycle.begin_current_battle(errors)
			launch["encounter"] = MapSystem.resolve_encounter(lifecycle._roguelike_catalog,
				{"chapter": chapter, "row": 0, "column": 6, "type": "elite"}, Rng.seeded("special"), errors)
			harness.assert_equal(errors, [])
			var manager := HandManager.new()
			var controller := Controller.new(manager)
			var started: Variant = controller.start(launch)
			harness.assert_true(started.ok, started.message)
			if not started.ok:
				manager.free()
				continue
			var state: Dictionary = controller._runtime.component("state")
			var special_id := "devourer" if chapter == 1 else "echo"
			var monsters: Array = state["enemies"].filter(func(unit: Dictionary) -> bool: return unit["special_id"] == special_id)
			harness.assert_equal(monsters.size(), 1, "one special entity, not one per cell")
			var monster: Dictionary = monsters[0]
			var vm: Dictionary = controller.view_model()
			var shown: Dictionary = vm["teams"]["enemy"]["slots"][int(monster["slot"])-1]
			harness.assert_equal(shown["occupied_slot_ids"].size(), 2 if chapter == 1 else 3)
			for cell in shown["occupied_slot_ids"].slice(1):
				harness.assert_false(state["enemies"][int(cell)-1]["alive"])
				harness.assert_equal(state["enemies"][int(cell)-1]["max_hp"], 0.0)
			if chapter == 1:
				_test_live_devourer_timing(controller, state, monster, harness)
				var dispatcher: Variant = controller._runtime.component("hook_dispatcher")
				state["sp"] = 3.0
				dispatcher.dispatch("pieceAttackHit", {
					"actor": monster, "target": state["allies"][1],
					"source_effect": _source_effect(monster, "manual-devour"),
				}, errors)
				harness.assert_equal(errors, [])
				harness.assert_equal(state["sp"], 2.0, "real monster hook drains one SP")
				state["sp"] = 0.0
				var deployed: Array = state["player_heroes"].filter(func(hero: Dictionary) -> bool: return hero["deployed"])
				for hero in deployed:
					hero["energy"] = 30.0
				dispatcher.dispatch("pieceAttackHit", {
					"actor": monster, "target": state["allies"][1],
					"source_effect": _source_effect(monster, "manual-devour"),
				}, errors)
				var total := 0.0
				for hero in deployed:
					total += float(hero["energy"])
				harness.assert_equal(total, 30.0*deployed.size()-10.0, "zero SP falls back to hero energy drain")
			else:
				var damage: Variant = controller._runtime.component("damage")
				var attack := _damage_context(monster, state["allies"][1], errors)
				var before: Dictionary = damage.apply(state["allies"][1], attack, {}, errors)
				harness.assert_equal(errors, [])
				var hit := _damage_context(state["allies"][1], monster, errors)
				damage.apply(monster, hit, {}, errors)
				harness.assert_equal(errors, [])
				harness.assert_true(is_equal_approx(monster["echo_damage_bonus"], 0.01))
				var after: Dictionary = damage.apply(state["allies"][1], attack, {}, errors)
				harness.assert_equal(errors, [])
				harness.assert_true(float(after["dealt"]) > float(before["dealt"]), "echo growth modifies actual outgoing damage")
			manager.free()
	)


func _test_live_devourer_timing(
	controller: Variant,
	state: Dictionary,
	monster: Dictionary,
	harness: RefCounted,
) -> void:
	var prior: Array[Dictionary] = controller.presentation_events()
	if not prior.is_empty():
		controller.acknowledge_presentation_through(int(prior[-1]["sequence"]))
	# Keep the production round deterministic: the Devourer remains the only
	# enemy piece, while neither side can end the battle before its slot acts.
	for ally: Dictionary in state["allies"]:
		ally["atk"] = 0.0
		if ally["alive"]:
			ally["hp"] = 10000.0
			ally["max_hp"] = 10000.0
	for enemy: Dictionary in state["enemies"]:
		if not is_same(enemy, monster):
			enemy["alive"] = false
			enemy["hp"] = 0.0
	monster["atk"] = 1.0
	monster["hp"] = maxf(float(monster["hp"]), 10000.0)
	monster["max_hp"] = maxf(float(monster["max_hp"]), 10000.0)
	state["sp"] = 3.0
	var settled: Variant = controller.end_player_turn()
	harness.assert_true(settled.ok, settled.message)
	if not settled.ok:
		return
	var events: Array[Dictionary] = controller.presentation_events()
	var drain: Dictionary = {}
	var monster_hit: Dictionary = {}
	var recovery: Dictionary = {}
	for event: Dictionary in events:
		if (
			event["event_id"] == "damage_applied"
			and event["source"].get("actor_id") == monster["id"]
		):
			monster_hit = event
		if event["event_id"] == "enemySpecialTriggered":
			drain = event
		if event["event_id"] == "resourceChanged" and event["payload"].get("reason") == "round_recovery":
			recovery = event
	harness.assert_false(monster_hit.is_empty(), "production piece attack emits the Devourer hit")
	harness.assert_false(drain.is_empty(), "the hit emits one visible resource-drain event")
	harness.assert_false(recovery.is_empty(), "round recovery emits a visible resource baseline")
	if monster_hit.is_empty() or drain.is_empty() or recovery.is_empty():
		return
	harness.assert_true(int(monster_hit["sequence"]) < int(drain["sequence"]))
	harness.assert_true(int(drain["sequence"]) < int(recovery["sequence"]))
	harness.assert_equal(drain["source"]["presentation_action_id"], monster_hit["source"]["presentation_action_id"])
	harness.assert_equal(drain["payload"]["actor"], {
		"id": monster["id"], "side": "enemy", "slot": monster["slot"],
	})
	harness.assert_equal([
		drain["payload"]["source_action_id"], drain["payload"]["resource"],
		drain["payload"]["old_sp"], drain["payload"]["new_sp"], drain["payload"]["amount"],
	], ["normalAttack", "sp", 3.0, 2.0, 1.0])
	harness.assert_equal([
		recovery["payload"]["old_sp"], recovery["payload"]["new_sp"],
		recovery["payload"]["amount"], controller.view_model()["resources"]["sp"],
	], [2.0, 4.0, 2.0, 4.0])
	# The queue owns one impact segment for both events, so UI receives the SP
	# mutation at the same visual instant as the hit rather than a later beat.
	var queue := PresentationQueue.new()
	queue.enqueue(events, controller.view_model())
	var grouped := false
	for segment: Dictionary in queue._segments:
		var ids: Array = segment["events"].map(func(event: Dictionary) -> String: return event["event_id"])
		if "damage_applied" in ids and "enemySpecialTriggered" in ids:
			grouped = true
			break
	harness.assert_true(grouped, "Devourer drain shares its hit presentation segment")
	queue.free()

static func _damage_context(attacker: Dictionary, target: Dictionary, errors: Array[String]) -> Dictionary:
	var effect := Contexts.create_effect_context(_source_effect(attacker, "special_probe"), errors)
	return Contexts.create_damage_context({
		"target_id": target["id"], "raw_amount": 20.0, "category": "direct", "effect": effect,
		"dealer_type": "piece", "dealer_id": attacker["id"], "dealer_name": "特殊怪实测",
		"attacker_unit_id": attacker["id"], "can_crit": false, "can_block": false,
	}, errors)


static func _source_effect(attacker: Dictionary, source_id: String) -> Dictionary:
	return {
		"source_type": "basic_attack", "source_id": source_id, "source_name": "特殊怪实测",
		"source_side": attacker["side"], "source_actor_id": attacker["id"],
		"counts_as_skill_cast": false, "spent_skill_points": false, "free_cast": false,
		"counts_as_basic_attack": true, "counts_as_attack": true,
		"triggers_enemy_kill_effects": true,
	}
