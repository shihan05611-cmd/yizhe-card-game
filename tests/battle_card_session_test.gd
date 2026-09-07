extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const SessionScript = preload("res://systems/cards/battle_card_session.gd")
const RequestScript = preload("res://systems/cards/card_play_request.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const M3Fixture = preload("res://tests/support/m3_card_fixture.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("complete session plays repeatedly then discards resolves and draws next turn", func() -> void:
		_test_complete_loop(harness)
	)
	harness.run_test("resolution-generated ultimate survives discard boundary before additive draw", func() -> void:
		_test_resolution_ultimate_timing(harness)
	)
	harness.run_test("full-hand ultimate is draw top and generation does not consume turn draw", func() -> void:
		_test_full_hand_ultimate_next_draw(harness)
	)
	harness.run_test("terminal round settles once without another draw", func() -> void:
		_test_terminal_stops(harness)
	)
	harness.run_test("committed card failure halts session before round resolution", func() -> void:
		_test_committed_failure_stops(harness)
	)
	harness.run_test("same seed and input produce identical complete session trace", func() -> void:
		_test_session_determinism(harness)
	)
	harness.run_test("extra deck reshuffle does not change combat or enemy policy result", func() -> void:
		_test_deck_stream_isolation(harness)
	)
	harness.run_test("HandManager delegates lifecycle and blocks raw session mutations", func() -> void:
		_test_hand_manager_session_adapter(harness)
	)
	harness.run_test("new battle input changes deck size and additive opening draw count", func() -> void:
		_test_new_battle_input(harness)
	)
	harness.run_test("session assembly rejects basicDamage before installing runtime", func() -> void:
		_test_session_rejects_basic_damage(harness)
	)
	harness.run_test("round failure after discard halts session without a second resolve", func() -> void:
		_test_round_failure_stops(harness)
	)
	print("M3-3 BATTLE CARD SESSION TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_complete_loop(harness: TestHarness) -> void:
	var created := _session({
		"deployed_hero_ids": [9], "sp": 20.0,
	}, ["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"], "loop")
	var session: Variant = created["session"]
	var fixture: Dictionary = created["fixture"]
	harness.assert_true(session.is_valid(), str(created["errors"]))
	harness.assert_equal(session.snapshot()["opening_draw"]["details"]["requested"], 3)
	harness.assert_equal(session.snapshot()["hand"]["piles"]["hand"].size(), 3)
	for _play_index in range(2):
		var instance_id: String = _find_hand_source(session, "pieceBlock")
		harness.assert_false(instance_id.is_empty())
		var played: Variant = session.play_card(_request_for(session, instance_id))
		harness.assert_true(played.ok, played.message)
	var before_round: int = fixture["state"]["round"]
	var ended: Variant = session.end_player_turn()
	harness.assert_true(ended.ok, ended.message)
	if not ended.ok:
		return
	harness.assert_equal(ended.details["status"], "player_input")
	harness.assert_equal(ended.details["round"]["round_before"], before_round)
	harness.assert_equal(ended.details["round"]["round_after"], before_round + 1)
	harness.assert_equal(fixture["state"]["phase"], "player_input")
	harness.assert_equal(ended.details["next_draw"]["details"]["requested"], 3)
	harness.assert_equal(ended.details["next_draw"]["details"]["attempted"], 3)
	harness.assert_equal(ended.details["m3_obligations"], [
		{"id": "discard_hand_before_resolution", "status": "fulfilled"},
		{"id": "preserve_resolution_generated_cards", "status": "fulfilled"},
		{"id": "draw_next_player_turn_after_finalize", "status": "fulfilled"},
	])
	harness.assert_true(_has_round_phase(ended.details["round"]["trace"], "enemy_yizhe"))
	harness.assert_true(_has_round_phase(ended.details["round"]["trace"], "ally_piece"))
	harness.assert_true(_has_round_phase(ended.details["round"]["trace"], "burn"))
	harness.assert_true(_has_round_phase(ended.details["round"]["trace"], "finalize"))


func _test_resolution_ultimate_timing(harness: TestHarness) -> void:
	var created := _session({
		"deployed_hero_ids": [1],
		"round_end_energy_requests": [{
			"hero_id": 1, "amount": 100.0, "source": {"kind": "m2_round_test"},
		}],
	}, ["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"], "round-ult")
	var session: Variant = created["session"]
	var ended: Variant = session.end_player_turn()
	harness.assert_true(ended.ok, ended.message)
	if not ended.ok:
		return
	var before_draw: Dictionary = ended.details["before_next_draw"]
	harness.assert_equal(before_draw["piles"]["hand"].size(), 1)
	var ultimate_id: String = before_draw["piles"]["hand"][0]
	var ultimate: Variant = session.component("hand_runtime").get_instance_snapshot(ultimate_id)
	harness.assert_equal(ultimate.definition.id, "ultimate:burn01")
	harness.assert_equal(ended.details["next_draw"]["details"]["requested"], 3)
	harness.assert_equal(ended.details["next_draw"]["details"]["attempted"], 3)
	harness.assert_equal(session.snapshot()["hand"]["piles"]["hand"].size(), 4)
	harness.assert_true(session.snapshot()["hand"]["piles"]["hand"].has(ultimate_id))


func _test_full_hand_ultimate_next_draw(harness: TestHarness) -> void:
	var roster := [1, 2, 3, 4, 9]
	var created := _session({
		"deployed_hero_ids": roster,
	}, ["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"], "draw-top")
	var session: Variant = created["session"]
	var fixture: Dictionary = created["fixture"]
	harness.assert_equal(session.snapshot()["hand"]["piles"]["hand"].size(), 7)
	var before_generation: Dictionary = session.snapshot()["hand"]
	var generated: Dictionary = fixture["runtime"].apply_player_energy({
		"hero_id": 1, "amount": 100.0, "source": {"kind": "full_hand_test"},
	})
	harness.assert_true(generated["ok"], str(generated))
	if not generated["ok"]:
		return
	var generated_id: String = generated["value"]["generated_card"]["instance_id"]
	harness.assert_equal(generated["value"]["generated_card"]["destination"], "draw")
	harness.assert_equal(
		session.snapshot()["hand"]["piles"]["hand"],
		before_generation["piles"]["hand"],
	)
	var ended: Variant = session.end_player_turn()
	harness.assert_true(ended.ok, ended.message)
	if not ended.ok:
		return
	harness.assert_equal(ended.details["next_draw"]["details"]["requested"], 7)
	harness.assert_equal(ended.details["next_draw"]["details"]["attempted"], 7)
	harness.assert_equal(ended.details["next_draw"]["details"]["drawn_instance_ids"][0], generated_id)


func _test_terminal_stops(harness: TestHarness) -> void:
	var created := _session({
		"deployed_hero_ids": [1], "ally_attack": 500.0, "enemy_hp": 1.0,
		"accept_battle_end": true,
	}, ["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"], "terminal")
	var session: Variant = created["session"]
	var fixture: Dictionary = created["fixture"]
	var ended: Variant = session.end_player_turn()
	harness.assert_true(ended.ok, ended.message)
	if not ended.ok:
		return
	harness.assert_equal(ended.details["status"], "settled")
	harness.assert_true(session.is_settled())
	harness.assert_true(fixture["state"]["game_over"])
	harness.assert_equal(fixture["state"]["phase"], "settled")
	harness.assert_equal(ended.details["next_draw"], null)
	harness.assert_equal(ended.details["m3_obligations"][2]["status"], "skipped_terminal")
	harness.assert_false(session.component("hand_runtime").is_queue_busy())
	harness.assert_false(session.component("hand_runtime").is_queue_halted())
	var trace_before: Array = session.snapshot()["trace"]
	var second: Variant = session.end_player_turn()
	harness.assert_false(second.ok)
	harness.assert_contains(second.message, "settled")
	harness.assert_equal(session.snapshot()["trace"], trace_before)


func _test_committed_failure_stops(harness: TestHarness) -> void:
	var created := _session({
		"deployed_hero_ids": [1], "sp": 20.0, "fail_content_event": true,
	}, ["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"], "fatal")
	var session: Variant = created["session"]
	var fixture: Dictionary = created["fixture"]
	var instance_id: String = _find_hand_source(session, "pieceBlock")
	harness.assert_false(instance_id.is_empty())
	var played: Variant = session.play_card(_request_for(session, instance_id))
	harness.assert_false(played.ok)
	harness.assert_true(played.details["fatal"])
	harness.assert_true(played.details["committed_prefix"])
	harness.assert_true(session.is_halted())
	var round_before: int = fixture["state"]["round"]
	var ended: Variant = session.end_player_turn()
	harness.assert_false(ended.ok)
	harness.assert_equal(ended.code, "queue_halted")
	harness.assert_equal(fixture["state"]["round"], round_before)
	harness.assert_equal(fixture["state"]["phase"], "player_input")


func _test_session_determinism(harness: TestHarness) -> void:
	var first := _session({
		"deployed_hero_ids": [4], "combat_seed": "same-combat", "enemy_seed": "same-enemy",
	}, ["pieceBlock", "pieceBlock", "pieceBlock"], "same-root")
	var second := _session({
		"deployed_hero_ids": [4], "combat_seed": "same-combat", "enemy_seed": "same-enemy",
	}, ["pieceBlock", "pieceBlock", "pieceBlock"], "same-root")
	var first_end: Variant = first["session"].end_player_turn()
	var second_end: Variant = second["session"].end_player_turn()
	harness.assert_true(first_end.ok, first_end.message)
	harness.assert_true(second_end.ok, second_end.message)
	harness.assert_equal(first["session"].snapshot(), second["session"].snapshot())
	harness.assert_equal(first["fixture"]["state"], second["fixture"]["state"])


func _test_deck_stream_isolation(harness: TestHarness) -> void:
	var first := _session({
		"deployed_hero_ids": [4], "combat_seed": "isolated-combat", "enemy_seed": "isolated-enemy",
	}, ["pieceBlock", "pieceBlock", "pieceBlock"], "isolated-root")
	var second := _session({
		"deployed_hero_ids": [4], "combat_seed": "isolated-combat", "enemy_seed": "isolated-enemy",
	}, ["pieceBlock", "pieceBlock", "pieceBlock"], "isolated-root")
	var changed_hand: Variant = first["session"].component("hand_runtime")
	for instance_id: String in changed_hand.pile_instance_ids("hand"):
		harness.assert_true(changed_hand.move_card_to_pile(instance_id, "discard", "top").ok)
	var extra_draw: Variant = changed_hand.draw_cards(1)
	harness.assert_true(extra_draw.ok, extra_draw.message)
	harness.assert_true(extra_draw.details["outcomes"][0]["details"]["reshuffled"])
	var first_end: Variant = first["session"].end_player_turn()
	var second_end: Variant = second["session"].end_player_turn()
	harness.assert_true(first_end.ok, first_end.message)
	harness.assert_true(second_end.ok, second_end.message)
	harness.assert_equal(first_end.details["round"]["trace"], second_end.details["round"]["trace"])
	harness.assert_equal(first["fixture"]["state"], second["fixture"]["state"])
	harness.assert_equal(
		first["fixture"]["combat_rng"].state_snapshot(),
		second["fixture"]["combat_rng"].state_snapshot(),
	)
	harness.assert_equal(
		first["fixture"]["enemy_rng"].state_snapshot(),
		second["fixture"]["enemy_rng"].state_snapshot(),
	)
	harness.assert_false(
		first["session"].snapshot()["hand"]["deck_rng_state"]
		== second["session"].snapshot()["hand"]["deck_rng_state"]
	)


func _test_hand_manager_session_adapter(harness: TestHarness) -> void:
	var fixture: Dictionary = M3Fixture.create({
		"install_card_runtime": false, "deployed_hero_ids": [1],
	})
	var manager := HandManagerScript.new()
	var errors: Array[String] = []
	var started: Variant = manager.start_battle_session({
		"battle_runtime": fixture["runtime"],
		"battle_seed": "manager-session",
		"deployed_hero_ids": [1],
		"free_skill_ids": ["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"],
	}, errors)
	harness.assert_true(started.ok, started.message)
	harness.assert_true(errors.is_empty(), str(errors))
	harness.assert_true(manager.has_runtime())
	harness.assert_true(manager.has_session())
	harness.assert_equal(manager.session_snapshot()["opening_draw"]["details"]["requested"], 3)
	harness.assert_false(manager.draw_cards(1).ok)
	harness.assert_false(manager.process_play_command("x", Callable(), Callable()).ok)
	var ended: Variant = manager.end_player_turn()
	harness.assert_true(ended.ok, ended.message)
	harness.assert_equal(fixture["state"]["round"], 4)
	manager.clear_battle()
	harness.assert_false(manager.has_runtime())
	harness.assert_false(manager.has_session())
	manager.free()


func _test_new_battle_input(harness: TestHarness) -> void:
	var first := _session(
		{"deployed_hero_ids": [1]},
		["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"],
		"new-battle-one",
	)
	var recruited_input := _session(
		{"deployed_hero_ids": [1, 4, 9]},
		["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"],
		"new-battle-three",
	)
	harness.assert_true(first["session"].is_valid(), str(first["errors"]))
	harness.assert_true(recruited_input["session"].is_valid(), str(recruited_input["errors"]))
	harness.assert_equal(first["session"].snapshot()["deck_card_ids"].size(), 5)
	harness.assert_equal(recruited_input["session"].snapshot()["deck_card_ids"].size(), 6)
	harness.assert_equal(first["session"].snapshot()["opening_draw"]["details"]["requested"], 3)
	harness.assert_equal(recruited_input["session"].snapshot()["opening_draw"]["details"]["requested"], 5)
	harness.assert_false(
		recruited_input["session"].snapshot()["deck_card_ids"].has("exclusive:counterAura")
	)


func _test_session_rejects_basic_damage(harness: TestHarness) -> void:
	var fixture: Dictionary = M3Fixture.create({
		"install_card_runtime": false, "deployed_hero_ids": [1],
	})
	var state_before: Dictionary = fixture["state"].duplicate(true)
	var errors: Array[String] = []
	var session := SessionScript.new({
		"battle_runtime": fixture["runtime"],
		"battle_seed": "reject-basic",
		"deployed_hero_ids": [1],
		"free_skill_ids": ["pieceBlock", "basicDamage"],
	}, errors)
	harness.assert_false(session.is_valid())
	harness.assert_true(not errors.is_empty())
	harness.assert_contains(errors[0], "explicitly rejects")
	harness.assert_equal(fixture["state"], state_before)
	harness.assert_equal(fixture["runtime"].component("card_bridge"), null)


func _test_round_failure_stops(harness: TestHarness) -> void:
	var created := _session({
		"deployed_hero_ids": [1], "fail_content_event": true,
	}, ["pieceBlock", "pieceBlock", "pieceBlock", "pieceBlock"], "round-failure")
	var session: Variant = created["session"]
	var fixture: Dictionary = created["fixture"]
	var ended: Variant = session.end_player_turn()
	harness.assert_false(ended.ok)
	harness.assert_equal(ended.code, "committed_failure")
	harness.assert_true(ended.details["fatal"])
	harness.assert_true(ended.details["committed_prefix"])
	harness.assert_true(session.is_halted())
	var state_after_failure: Dictionary = fixture["state"].duplicate(true)
	var trace_after_failure: Array = session.snapshot()["trace"]
	var second: Variant = session.end_player_turn()
	harness.assert_false(second.ok)
	harness.assert_equal(second.code, "queue_halted")
	harness.assert_equal(fixture["state"], state_after_failure)
	harness.assert_equal(session.snapshot()["trace"], trace_after_failure)


func _session(options: Dictionary, free_skill_ids: Array, battle_seed: Variant) -> Dictionary:
	var fixture_options := options.duplicate(true)
	fixture_options["install_card_runtime"] = false
	var fixture: Dictionary = M3Fixture.create(fixture_options)
	var errors: Array[String] = []
	var session := SessionScript.new({
		"battle_runtime": fixture["runtime"],
		"battle_seed": battle_seed,
		"deployed_hero_ids": options.get("deployed_hero_ids", [2, 3, 4, 9]),
		"free_skill_ids": free_skill_ids,
	}, errors)
	return {"fixture": fixture, "session": session, "errors": errors}


func _find_hand_source(session: Variant, source_skill_id: String) -> String:
	var hand: Variant = session.component("hand_runtime")
	for instance_id: String in hand.pile_instance_ids("hand"):
		var instance: Variant = hand.get_instance_snapshot(instance_id)
		if instance.source_skill_id == source_skill_id:
			return instance_id
	return ""


func _request_for(session: Variant, instance_id: String) -> RefCounted:
	var instance: Variant = session.component("hand_runtime").get_instance_snapshot(instance_id)
	return RequestScript.new(
		instance_id,
		instance.definition.id,
		instance.source_skill_id,
	)


func _has_round_phase(trace: Array, phase: String) -> bool:
	for entry: Dictionary in trace:
		if entry["phase"] == phase:
			return true
	return false
