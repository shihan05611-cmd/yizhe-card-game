extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const Fixture = preload("res://tests/support/m3_card_fixture.gd")
const Request = preload("res://systems/cards/card_play_request.gd")
const CardDefinitionScript = preload("res://data/definitions/card_definition.gd")
const Controller = preload("res://app/battle_controller.gd")
const HandManager = preload("res://autoload/hand_manager.gd")
const CardViewScene: PackedScene = preload("res://scenes/cards/card_view.tscn")


func run(harness: TestHarness) -> void:
	harness.run_test("resource cards exhaust and SP gain can overflow during the turn", func() -> void:
		var fixture := Fixture.create({"sp": 4.0})
		fixture["state"]["sp_max"] = 4.0
		fixture["state"]["base_sp_max"] = 4.0
		var ids := Fixture.put_cards_in_hand(fixture, ["free:spSurge"])
		var result: Variant = fixture["runtime"].play_player_card(Request.new(ids[0]))
		harness.assert_true(result.ok, result.message)
		harness.assert_equal(fixture["state"]["sp"], 5.0)
		harness.assert_equal(result.details["actual_cost"], 1)
		harness.assert_equal(result.details["effect_result"]["sp_gained"], 2)
		harness.assert_equal(result.details["destination"], CardDefinitionScript.PILE_EXHAUST)
		harness.assert_equal(
			fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_EXHAUST), ids,
		)
	)
	harness.run_test("draw card preflights atomically then draws two after exhausting itself", func() -> void:
		_test_tactical_draw(harness)
	)
	harness.run_test("executeStrike locks the chosen enemy and invalid target rejects before payment", func() -> void:
		_test_execute_target_lock(harness)
	)
	harness.run_test("pieceAction requires the chosen living ally and internal play selects one", func() -> void:
		_test_piece_action_target_lock(harness)
	)
	harness.run_test("controller publishes pieceAction ally targeting and legacy auto play supplies a target", func() -> void:
		_test_piece_action_controller_targeting(harness)
	)
	harness.run_test("ending the player turn removes overflow and capped recovery restores two", func() -> void:
		var manager := HandManager.new()
		var controller := Controller.new(manager)
		var started: Variant = controller.start({
			"battle_seed": "sp-overflow-end-turn",
			"deployed_hero_ids": [1],
			"free_skill_ids": ["pieceBlock", "pieceAction"],
			"stage_id": "counter",
		})
		harness.assert_true(started.ok, started.message)
		if not started.ok:
			manager.free()
			return
		var state: Dictionary = controller._runtime.component("state")
		state["sp"] = 6.0
		var ended: Variant = controller.end_player_turn()
		harness.assert_true(ended.ok, ended.message)
		if ended.ok:
			harness.assert_equal(ended.details["sp_overflow_removed"], 2.0)
			harness.assert_equal(state["sp"], state["sp_max"])
			harness.assert_equal(state["round"], 2)
		manager.free()
	)
	harness.run_test("flame enchant successful casts use the 1 2 2 4 cost schedule", func() -> void:
		var fixture := Fixture.create({"sp": 20.0})
		var heroes: Array = fixture["state"]["player_heroes"].duplicate(true)
		heroes.append({
			"id": 5, "name": "炎术士", "deployed": true, "ex_skill": "burnEnchant",
			"energy": 0.0, "max_energy": 100.0, "base_crit_rate": 0.0,
			"fist_momentum": 0,
		})
		fixture["state"]["player_heroes"] = heroes
		var ids := Fixture.put_cards_in_hand(fixture, [
			"exclusive:burnEnchant", "exclusive:burnEnchant", "exclusive:burnEnchant",
			"exclusive:burnEnchant", "exclusive:burnEnchant",
		])
		var actual_costs: Array[int] = []
		for instance_id: String in ids:
			var result: Variant = fixture["runtime"].play_player_card(Request.new(instance_id))
			harness.assert_true(result.ok, result.message)
			if result.ok:
				actual_costs.append(int(result.details["actual_cost"]))
		harness.assert_equal(actual_costs, [1, 2, 2, 4, 4])
		harness.assert_equal(fixture["state"]["sp"], 7.0)
	)
	harness.run_test("controller and card label expose flame schedule while ultimate remains zero cost", func() -> void:
		_test_controller_flame_cost_display(harness)
	)
	harness.run_test("burn01 uses its successful battle cast schedule in controller label and payment", func() -> void:
		_test_controller_burn01_cost_display(harness)
	)


func _test_tactical_draw(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 4.0})
	var definitions := [
		fixture["cards"]["free:tacticalDraw"],
		fixture["cards"]["free:pieceBlock"],
		fixture["cards"]["free:pieceDamageUp"],
	]
	var initialized: Variant = fixture["hand"].initialize_deck(definitions, false)
	harness.assert_true(initialized.ok, initialized.message)
	var tactical_id := _instance_id_for_source(fixture["hand"], "tacticalDraw")
	var moved: Variant = fixture["hand"].move_card_to_pile(
		tactical_id, CardDefinitionScript.PILE_HAND,
	)
	harness.assert_true(moved.ok, moved.message)
	var played: Variant = fixture["runtime"].play_player_card(Request.new(tactical_id))
	harness.assert_true(played.ok, played.message)
	if played.ok:
		harness.assert_equal(played.details["destination"], CardDefinitionScript.PILE_EXHAUST)
		harness.assert_equal(played.details["draw"]["details"]["drawn_instance_ids"].size(), 2)
		harness.assert_equal(fixture["hand"].pile_instance_ids(CardDefinitionScript.PILE_HAND).size(), 2)

	var rejected := Fixture.create({"sp": 4.0})
	var only_ids := Fixture.put_cards_in_hand(rejected, ["free:tacticalDraw"])
	var state_before: Dictionary = rejected["state"].duplicate(true)
	var hand_before: Dictionary = rejected["hand"].snapshot()
	var denied: Variant = rejected["runtime"].play_player_card(Request.new(only_ids[0]))
	harness.assert_false(denied.ok)
	if not denied.ok:
		harness.assert_contains(denied.message, "at least two cards")
		harness.assert_equal(rejected["state"], state_before)
		harness.assert_equal(rejected["hand"].snapshot(), hand_before)


func _test_execute_target_lock(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 4.0})
	var ids := Fixture.put_cards_in_hand(fixture, ["free:executeStrike"])
	fixture["state"]["enemies"][0]["hp"] = 1.0
	fixture["state"]["enemies"][1]["hp"] = 5.0
	var selected: Dictionary = fixture["state"]["enemies"][1]
	var request := Request.new(
		ids[0], "free:executeStrike", "executeStrike", null,
		{"side": "enemy", "unit_id": selected["id"], "slot": selected["slot"]},
	)
	var result: Variant = fixture["runtime"].play_player_card(request)
	harness.assert_true(result.ok, result.message)
	if result.ok:
		harness.assert_false(selected["alive"])
		harness.assert_true(fixture["state"]["enemies"][0]["alive"], "explicit target overrides lower-HP enemy")
		harness.assert_equal(fixture["state"]["sp"], 3.0, "kill refunds one SP after paying two")

	var invalid := Fixture.create({"sp": 4.0})
	ids = Fixture.put_cards_in_hand(invalid, ["free:executeStrike"])
	var dead: Dictionary = invalid["state"]["enemies"][2]
	dead["alive"] = false
	dead["hp"] = 0.0
	var invalid_state_before: Dictionary = invalid["state"].duplicate(true)
	var invalid_hand_before: Dictionary = invalid["hand"].snapshot()
	var denied: Variant = invalid["runtime"].play_player_card(Request.new(
		ids[0], "free:executeStrike", "executeStrike", null,
		{"side": "enemy", "unit_id": dead["id"], "slot": dead["slot"]},
	))
	harness.assert_false(denied.ok)
	if not denied.ok:
		harness.assert_equal(invalid["state"], invalid_state_before)
		harness.assert_equal(invalid["hand"].snapshot(), invalid_hand_before)


func _test_piece_action_target_lock(harness: TestHarness) -> void:
	var fixture := Fixture.create({"sp": 4.0})
	var ids := Fixture.put_cards_in_hand(fixture, ["free:pieceAction"])
	var selected: Dictionary = fixture["state"]["allies"][3]
	var played: Variant = fixture["runtime"].play_player_card(Request.new(
		ids[0], "free:pieceAction", "pieceAction", null,
		{"side": "ally", "unit_id": selected["id"], "slot": selected["slot"]},
	))
	harness.assert_true(played.ok, played.message)
	if played.ok:
		harness.assert_equal(played.details["effect_result"].get("target_id"), selected["id"])

	var invalid := Fixture.create({"sp": 4.0})
	ids = Fixture.put_cards_in_hand(invalid, ["free:pieceAction"])
	var dead: Dictionary = invalid["state"]["allies"][2]
	dead["alive"] = false
	dead["hp"] = 0.0
	var state_before: Dictionary = invalid["state"].duplicate(true)
	var hand_before: Dictionary = invalid["hand"].snapshot()
	var denied: Variant = invalid["runtime"].play_player_card(Request.new(
		ids[0], "free:pieceAction", "pieceAction", null,
		{"side": "ally", "unit_id": dead["id"], "slot": dead["slot"]},
	))
	harness.assert_false(denied.ok)
	harness.assert_equal(invalid["state"], state_before)
	harness.assert_equal(invalid["hand"].snapshot(), hand_before)

	var automatic := Fixture.create({"sp": 4.0})
	automatic["state"]["allies"][4]["atk"] = 99.0
	ids = Fixture.put_cards_in_hand(automatic, ["free:pieceAction"])
	var auto_played: Variant = automatic["runtime"].play_player_card(Request.new(ids[0]))
	harness.assert_true(auto_played.ok, auto_played.message)
	if auto_played.ok:
		harness.assert_equal(auto_played.details["effect_result"].get("target_id"), automatic["state"]["allies"][4]["id"])


func _test_piece_action_controller_targeting(harness: TestHarness) -> void:
	var manager := HandManager.new()
	var controller := Controller.new(manager)
	var started: Variant = controller.start({
		"battle_seed": "piece-action-controller-target",
		"deployed_hero_ids": [1],
		"free_skill_ids": ["pieceAction", "smallHeal"],
		"stage_id": "counter",
	})
	harness.assert_true(started.ok, started.message)
	if not started.ok:
		manager.free()
		return
	var piece_card: Dictionary = {}
	for card: Dictionary in controller.view_model().get("hand", []):
		if str(card.get("source_skill_id", "")) == "pieceAction":
			piece_card = card
			break
	harness.assert_false(piece_card.is_empty())
	if not piece_card.is_empty():
		harness.assert_equal(piece_card["targeting"], {
			"mode": "required", "side": "ally", "filter": "living",
		})
		var state: Dictionary = controller._runtime.component("state")
		state["allies"][5]["atk"] = 999.0
		var played: Variant = controller.play_card(str(piece_card["instance_id"]))
		harness.assert_true(played.ok, played.message)
		if played.ok:
			harness.assert_equal(played.details["effect_result"].get("target_id"), state["allies"][5]["id"])
	manager.free()


static func _instance_id_for_source(hand: Variant, source_skill_id: String) -> String:
	for instance_id: String in hand.snapshot()["piles"][CardDefinitionScript.PILE_DRAW]:
		if hand.get_instance_snapshot(instance_id).source_skill_id == source_skill_id:
			return instance_id
	return ""


func _test_controller_flame_cost_display(harness: TestHarness) -> void:
	var manager := HandManager.new()
	var controller := Controller.new(manager)
	var started: Variant = controller.start({
		"battle_seed": "flame-cost-display",
		"deployed_hero_ids": [5],
		"free_skill_ids": ["smallHeal", "markBurn"],
		"stage_id": "counter",
	})
	harness.assert_true(started.ok, started.message)
	if not started.ok:
		manager.free()
		return
	var state: Dictionary = controller._runtime.component("state")
	state["sp"] = 30.0
	var session: Variant = manager._session
	var hand: Variant = session.component("hand_runtime")
	var cards: Dictionary = session.component("card_catalog")
	var sp_before := float(state["sp"])
	for expected_cost: int in [1, 2, 2, 4, 4]:
		var created: Variant = hand.create_card(
			cards["exclusive:burnEnchant"], CardDefinitionScript.PILE_HAND,
		)
		harness.assert_true(created.ok, created.message)
		if not created.ok:
			continue
		var instance_id := str(created.details["instance_id"])
		var card_vm := _controller_card_vm(controller, instance_id)
		harness.assert_equal(card_vm.get("base_cost"), expected_cost)
		harness.assert_equal(card_vm.get("effective_cost"), expected_cost)
		harness.assert_equal(card_vm.get("actual_cost"), expected_cost)
		harness.assert_equal(_rendered_cost(card_vm), str(expected_cost))
		var played: Variant = controller.play_card(instance_id)
		harness.assert_true(played.ok, played.message)
		if played.ok:
			harness.assert_equal(played.details["base_cost"], expected_cost)
			harness.assert_equal(played.details["effective_cost"], expected_cost)
			harness.assert_equal(played.details["actual_cost"], expected_cost)
			sp_before -= expected_cost
			harness.assert_equal(float(state["sp"]), sp_before)

	var discounted: Variant = hand.create_card(
		cards["exclusive:burnEnchant"], CardDefinitionScript.PILE_HAND,
	)
	harness.assert_true(discounted.ok, discounted.message)
	var discounted_id := str(discounted.details["instance_id"])
	var modified: Variant = hand.set_card_cost_modifiers(discounted_id, {
		"until_played": -2, "until_turn": 0, "until_combat": 0,
	})
	harness.assert_true(modified.ok, modified.message)
	var discounted_vm := _controller_card_vm(controller, discounted_id)
	harness.assert_equal(discounted_vm.get("base_cost"), 4)
	harness.assert_equal(discounted_vm.get("effective_cost"), 2)
	harness.assert_equal(_rendered_cost(discounted_vm), "2\n原4")

	var unavailable: Variant = hand.create_card(
		cards["exclusive:burnEnchant"], CardDefinitionScript.PILE_HAND,
	)
	harness.assert_true(unavailable.ok, unavailable.message)
	state["sp"] = 0.0
	var unavailable_vm := _controller_card_vm(controller, str(unavailable.details["instance_id"]))
	harness.assert_false(bool(unavailable_vm.get("playable", true)))
	harness.assert_equal(unavailable_vm.get("base_cost"), 4)
	harness.assert_equal(unavailable_vm.get("effective_cost"), 4)
	harness.assert_equal(_rendered_cost(unavailable_vm), "4")

	var ultimate: Variant = hand.create_card(
		cards["ultimate:burnEnchant"], CardDefinitionScript.PILE_HAND,
	)
	harness.assert_true(ultimate.ok, ultimate.message)
	var ultimate_vm := _controller_card_vm(controller, str(ultimate.details["instance_id"]))
	harness.assert_equal(ultimate_vm.get("base_cost"), 0)
	harness.assert_equal(ultimate_vm.get("effective_cost"), 0)
	harness.assert_equal(_rendered_cost(ultimate_vm), "0")
	manager.free()


func _test_controller_burn01_cost_display(harness: TestHarness) -> void:
	var manager := HandManager.new()
	var controller := Controller.new(manager)
	var started: Variant = controller.start({
		"battle_seed": "burn01-cost-display",
		"deployed_hero_ids": [1],
		"free_skill_ids": ["smallHeal", "markBurn"],
		"stage_id": "counter",
	})
	harness.assert_true(started.ok, started.message)
	if not started.ok:
		manager.free()
		return
	var state: Dictionary = controller._runtime.component("state")
	state["sp"] = 60.0
	var session: Variant = manager._session
	var hand: Variant = session.component("hand_runtime")
	var cards: Dictionary = session.component("card_catalog")
	var buffs: Variant = controller._runtime.component("buffs")
	var errors: Array[String] = []
	harness.assert_true(buffs.apply_unit(state["enemies"][0], "burn", 1, 3, errors), "; ".join(errors))
	var sp_before := float(state["sp"])
	for expected_cost: int in [1, 2, 4, 8, 8]:
		var created: Variant = hand.create_card(
			cards["exclusive:burn01"], CardDefinitionScript.PILE_HAND,
		)
		harness.assert_true(created.ok, created.message)
		if not created.ok:
			continue
		var instance_id := str(created.details["instance_id"])
		var card_vm := _controller_card_vm(controller, instance_id)
		harness.assert_equal(card_vm.get("base_cost"), expected_cost)
		harness.assert_equal(card_vm.get("effective_cost"), expected_cost)
		harness.assert_equal(card_vm.get("actual_cost"), expected_cost)
		harness.assert_equal(_rendered_cost(card_vm), str(expected_cost))
		var count_before := int(state["burn_ex_cast_count"])
		var played: Variant = controller.play_card(instance_id)
		harness.assert_true(played.ok, played.message)
		if played.ok:
			harness.assert_equal(played.details["base_cost"], expected_cost)
			harness.assert_equal(played.details["effective_cost"], expected_cost)
			harness.assert_equal(played.details["actual_cost"], expected_cost)
			harness.assert_equal(int(state["burn_ex_cast_count"]), count_before + 1)
			sp_before -= expected_cost
			harness.assert_equal(float(state["sp"]), sp_before)

	var discounted: Variant = hand.create_card(
		cards["exclusive:burn01"], CardDefinitionScript.PILE_HAND,
	)
	harness.assert_true(discounted.ok, discounted.message)
	var discounted_id := str(discounted.details["instance_id"])
	var modified: Variant = hand.set_card_cost_modifiers(discounted_id, {
		"until_played": -3, "until_turn": 0, "until_combat": 0,
	})
	harness.assert_true(modified.ok, modified.message)
	var discounted_vm := _controller_card_vm(controller, discounted_id)
	harness.assert_equal(discounted_vm.get("base_cost"), 8)
	harness.assert_equal(discounted_vm.get("effective_cost"), 5)
	harness.assert_equal(discounted_vm.get("actual_cost"), 5)
	harness.assert_equal(_rendered_cost(discounted_vm), "5\n原8")
	var discounted_play: Variant = controller.play_card(discounted_id)
	harness.assert_true(discounted_play.ok, discounted_play.message)
	if discounted_play.ok:
		harness.assert_equal(discounted_play.details["base_cost"], 8)
		harness.assert_equal(discounted_play.details["effective_cost"], 5)
		harness.assert_equal(discounted_play.details["actual_cost"], 5)
		harness.assert_equal(int(state["burn_ex_cast_count"]), 6)

	errors.clear()
	harness.assert_true(buffs.clear_unit(state["enemies"][0], "burn", errors), "; ".join(errors))
	var rejected: Variant = hand.create_card(
		cards["exclusive:burn01"], CardDefinitionScript.PILE_HAND,
	)
	harness.assert_true(rejected.ok, rejected.message)
	var rejected_id := str(rejected.details["instance_id"])
	var rejected_vm := _controller_card_vm(controller, rejected_id)
	harness.assert_false(bool(rejected_vm.get("playable", true)))
	harness.assert_equal(rejected_vm.get("base_cost"), 8)
	harness.assert_equal(rejected_vm.get("effective_cost"), 8)
	harness.assert_equal(_rendered_cost(rejected_vm), "8")
	var count_before_failure := int(state["burn_ex_cast_count"])
	var sp_before_failure := float(state["sp"])
	var failed: Variant = controller.play_card(rejected_id)
	harness.assert_false(failed.ok)
	harness.assert_equal(int(state["burn_ex_cast_count"]), count_before_failure)
	harness.assert_equal(float(state["sp"]), sp_before_failure)

	var ultimate: Variant = hand.create_card(
		cards["ultimate:burn01"], CardDefinitionScript.PILE_HAND,
	)
	harness.assert_true(ultimate.ok, ultimate.message)
	var ultimate_vm := _controller_card_vm(controller, str(ultimate.details["instance_id"]))
	harness.assert_equal(ultimate_vm.get("base_cost"), 0)
	harness.assert_equal(ultimate_vm.get("effective_cost"), 0)
	harness.assert_equal(_rendered_cost(ultimate_vm), "0")
	manager.free()

	var next_manager := HandManager.new()
	var next_controller := Controller.new(next_manager)
	var next_started: Variant = next_controller.start({
		"battle_seed": "burn01-cost-reset",
		"deployed_hero_ids": [1],
		"free_skill_ids": ["smallHeal", "markBurn"],
		"stage_id": "counter",
	})
	harness.assert_true(next_started.ok, next_started.message)
	if next_started.ok:
		var next_session: Variant = next_manager._session
		var next_hand: Variant = next_session.component("hand_runtime")
		var next_cards: Dictionary = next_session.component("card_catalog")
		var next_created: Variant = next_hand.create_card(
			next_cards["exclusive:burn01"], CardDefinitionScript.PILE_HAND,
		)
		harness.assert_true(next_created.ok, next_created.message)
		if next_created.ok:
			var next_vm := _controller_card_vm(next_controller, str(next_created.details["instance_id"]))
			harness.assert_equal(next_vm.get("base_cost"), 1)
			harness.assert_equal(next_vm.get("effective_cost"), 1)
			harness.assert_equal(_rendered_cost(next_vm), "1")
	next_manager.free()


static func _controller_card_vm(controller: Variant, instance_id: String) -> Dictionary:
	for card: Dictionary in controller.view_model().get("hand", []):
		if str(card.get("instance_id", "")) == instance_id:
			return card
	return {}


static func _rendered_cost(card_vm: Dictionary) -> String:
	var view: Variant = CardViewScene.instantiate()
	Engine.get_main_loop().root.add_child(view)
	view.bind_card(card_vm)
	var text_value := str(view.get_node("CardSurface/Cost").text)
	view.get_parent().remove_child(view)
	view.free()
	return text_value
