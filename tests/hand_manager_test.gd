extends RefCounted

const Card = preload("res://data/definitions/card_definition.gd")
const Result = preload("res://core/card_runtime_result.gd")
const RngScript = preload("res://core/rng.gd")
const HandRuntimeScript = preload("res://systems/cards/hand_runtime.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("card copies have unique deterministic instance identity", func() -> void:
		_test_instance_identity(harness)
	)
	harness.run_test("test_draw_two_plus_n_additively", func() -> void:
		_test_draw_two_plus_n_additively(harness)
	)
	harness.run_test("test_hand_limit_seven_no_replacement", func() -> void:
		_test_hand_limit_seven_no_replacement(harness)
	)
	harness.run_test("test_deterministic_reshuffle", func() -> void:
		_test_deterministic_reshuffle(harness)
	)
	harness.run_test("first shuffle and reshuffle priority buckets control draw top", func() -> void:
		_test_shuffle_priorities(harness)
	)
	harness.run_test("test_end_turn_destinations", func() -> void:
		_test_end_turn_destinations(harness)
	)
	harness.run_test("deck RNG is independent from combat and enemyPolicy", func() -> void:
		_test_deck_rng_independence(harness)
	)
	harness.run_test("return hand outranks exhaust without duplicating instances", func() -> void:
		_test_destination_priority(harness)
	)
	harness.run_test("validator rejection and queue reentry preserve runtime state", func() -> void:
		_test_command_rejections(harness)
	)
	harness.run_test("successful play limits commit only after success", func() -> void:
		_test_success_limit(harness)
	)
	harness.run_test("generic creation and pile moves conserve instances", func() -> void:
		_test_creation_and_conservation(harness)
	)
	harness.run_test("basicDamage is rejected by the runtime deck boundary", func() -> void:
		_test_forbidden_source(harness)
	)
	harness.run_test("HandManager thin adapter matches pure HandRuntime", func() -> void:
		_test_adapter_parity(harness)
	)


func _test_instance_identity(harness: TestHarness) -> void:
	var definition := _card("same")
	var runtime := HandRuntimeScript.new("identity")
	var initialized: Variant = runtime.initialize_deck([definition, definition, definition], false)
	harness.assert_true(initialized.ok)
	var ids: Array = runtime.pile_instance_ids(Card.PILE_DRAW)
	harness.assert_equal(ids, ["card-00000001", "card-00000002", "card-00000003"])
	harness.assert_equal(_unique_count(ids), 3)
	for instance_id in ids:
		harness.assert_equal(runtime.get_instance_snapshot(instance_id).source_skill_id, "same")


func _test_draw_two_plus_n_additively(harness: TestHarness) -> void:
	var runtime := _runtime_with_copies("additive", 8, false)
	harness.assert_true(runtime.draw_cards(2).ok)
	var result: Variant = runtime.draw_for_turn(3)
	harness.assert_true(result.ok)
	harness.assert_equal(result.details["requested"], 5)
	harness.assert_equal(result.details["attempted"], 5)
	harness.assert_equal(result.details["drawn_instance_ids"].size(), 5)
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_HAND).size(), 7)
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_DRAW).size(), 1)


func _test_hand_limit_seven_no_replacement(harness: TestHarness) -> void:
	var runtime := _runtime_with_copies("limit", 9, false)
	harness.assert_true(runtime.draw_cards(7).ok)
	var draw_before: Array = runtime.pile_instance_ids(Card.PILE_DRAW)
	var result: Variant = runtime.draw_cards(2)
	harness.assert_false(result.ok)
	harness.assert_equal(result.code, Result.HAND_FULL)
	harness.assert_equal(result.details["attempted"], 2)
	harness.assert_equal(result.details["drawn_instance_ids"], [])
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_DRAW), draw_before)
	harness.assert_equal(runtime.total_instance_count(), 9)


func _test_deterministic_reshuffle(harness: TestHarness) -> void:
	var first := _runtime_with_copies("reshuffle-seed", 5, true)
	var second := _runtime_with_copies("reshuffle-seed", 5, true)
	var first_sequences: Array = []
	var second_sequences: Array = []
	for _round in range(3):
		var first_draw: Variant = first.draw_cards(5)
		var second_draw: Variant = second.draw_cards(5)
		harness.assert_true(first_draw.ok and second_draw.ok)
		first_sequences.append(first_draw.details["drawn_instance_ids"].duplicate())
		second_sequences.append(second_draw.details["drawn_instance_ids"].duplicate())
		harness.assert_true(first.end_player_turn().ok)
		harness.assert_true(second.end_player_turn().ok)
	harness.assert_equal(first_sequences, second_sequences)
	harness.assert_equal(first.snapshot(), second.snapshot())
	harness.assert_equal(first.snapshot()["shuffle_count"], 3)


func _test_shuffle_priorities(harness: TestHarness) -> void:
	var first_top := _card("first-top")
	first_top.card_first_shuffle_priority = 1
	first_top.card_reshuffle_priority = -1
	var neutral := _card("neutral")
	var reshuffle_top := _card("reshuffle-top")
	reshuffle_top.card_first_shuffle_priority = -1
	reshuffle_top.card_reshuffle_priority = 1
	var runtime := HandRuntimeScript.new("priorities")
	harness.assert_true(runtime.initialize_deck([first_top, neutral, reshuffle_top], true).ok)
	var first_draw: Variant = runtime.draw_one()
	harness.assert_equal(first_draw.details["instance_id"], "card-00000001")
	harness.assert_true(runtime.draw_cards(2).ok)
	harness.assert_true(runtime.end_player_turn().ok)
	var reshuffled_draw: Variant = runtime.draw_one()
	harness.assert_equal(reshuffled_draw.details["instance_id"], "card-00000003")


func _test_end_turn_destinations(harness: TestHarness) -> void:
	var runtime := HandRuntimeScript.new("destinations")
	var normal := _card("normal")
	var exhaust := _card("exhaust", Card.PILE_DISCARD, true)
	var returned := _card("returned")
	harness.assert_true(runtime.initialize_deck([normal, exhaust, returned], false).ok)
	harness.assert_true(runtime.draw_cards(3).ok)
	var hand: Array = runtime.pile_instance_ids(Card.PILE_HAND)
	var returned_id: String = hand[0]
	var exhaust_id: String = hand[1]
	var normal_id: String = hand[2]
	harness.assert_true(runtime.process_play_command(exhaust_id, Callable(), _success()).ok)
	harness.assert_true(runtime.process_play_command(normal_id, Callable(), _success()).ok)
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_HAND), [returned_id])
	harness.assert_true(runtime.end_player_turn().ok)
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_HAND), [])
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_EXHAUST), [exhaust_id])
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_DISCARD), [normal_id, returned_id])
	_assert_conserved(harness, runtime, 3)


func _test_deck_rng_independence(harness: TestHarness) -> void:
	var names := ["combat", "enemyPolicy", "deck"]
	var baseline := RngScript.create_named_streams("independent", names)
	var deck_consumed := RngScript.create_named_streams("independent", names)
	for _index in range(40):
		deck_consumed["deck"].next_u32()
	for stream_name in ["combat", "enemyPolicy"]:
		for index in range(20):
			harness.assert_equal(
				deck_consumed[stream_name].next_u32(),
				baseline[stream_name].next_u32(),
				"deck consumption leaked into %s at %d" % [stream_name, index],
			)

	var other_consumed := RngScript.create_named_streams("independent", names)
	var deck_baseline := RngScript.create_named_streams("independent", names)
	for _index in range(25):
		other_consumed["combat"].next_u32()
		other_consumed["enemyPolicy"].next_u32()
	for index in range(20):
		harness.assert_equal(
			other_consumed["deck"].next_u32(),
			deck_baseline["deck"].next_u32(),
			"combat/enemyPolicy consumption leaked into deck at %d" % index,
		)

	var runtime_streams := RngScript.create_named_streams("runtime-independent", names)
	var runtime_baseline := RngScript.create_named_streams("runtime-independent", names)
	var runtime := HandRuntimeScript.new(runtime_streams["deck"])
	harness.assert_true(runtime.initialize_deck(_copies(_card("rng-runtime"), 5), true).ok)
	harness.assert_true(runtime.draw_cards(5).ok)
	harness.assert_true(runtime.end_player_turn().ok)
	harness.assert_true(runtime.draw_cards(5).ok)
	for stream_name in ["combat", "enemyPolicy"]:
		for index in range(12):
			harness.assert_equal(
				runtime_streams[stream_name].next_u32(),
				runtime_baseline[stream_name].next_u32(),
				"HandRuntime deck operations leaked into %s at %d" % [stream_name, index],
			)


func _test_destination_priority(harness: TestHarness) -> void:
	var runtime := HandRuntimeScript.new("priority")
	var exhaust := _card("priority", Card.PILE_DISCARD, true)
	harness.assert_true(runtime.initialize_deck([exhaust], false).ok)
	harness.assert_true(runtime.draw_cards(1).ok)
	var instance_id: String = runtime.pile_instance_ids(Card.PILE_HAND)[0]
	var first: Variant = runtime.process_play_command(instance_id, Callable(), _success(), true)
	harness.assert_true(first.ok)
	harness.assert_equal(first.details["destination"], Card.PILE_HAND)
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_HAND), [instance_id])
	harness.assert_equal(runtime.successful_play_count(instance_id), 1)
	var second: Variant = runtime.process_play_command(instance_id, Callable(), _success())
	harness.assert_true(second.ok)
	harness.assert_equal(second.details["destination"], Card.PILE_EXHAUST)
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_EXHAUST), [instance_id])
	_assert_conserved(harness, runtime, 1)


func _test_command_rejections(harness: TestHarness) -> void:
	var runtime := _runtime_with_copies("rejections", 1, false)
	harness.assert_true(runtime.draw_cards(1).ok)
	var instance_id: String = runtime.pile_instance_ids(Card.PILE_HAND)[0]
	var before_validator: Dictionary = runtime.snapshot()
	var rejected: Variant = runtime.process_play_command(
		instance_id,
		func(_card_instance: Variant) -> bool: return false,
		_success(),
	)
	harness.assert_equal(rejected.code, Result.VALIDATOR_REJECTED)
	harness.assert_equal(runtime.snapshot(), before_validator)

	var observed_reentry: Array = []
	var before_reentry: Dictionary = runtime.snapshot()
	var outer: Variant = runtime.process_play_command(
		instance_id,
		Callable(),
		func(_card_instance: Variant) -> Dictionary:
			var inner: Variant = runtime.process_play_command(instance_id, Callable(), _success())
			observed_reentry.append(inner.to_dict())
			return {"ok": false, "message": "fixture stops outer commit"},
	)
	harness.assert_equal(outer.code, Result.EXECUTION_FAILED)
	harness.assert_equal(observed_reentry.size(), 1)
	harness.assert_equal(observed_reentry[0]["code"], Result.QUEUE_BUSY)
	harness.assert_equal(runtime.snapshot(), before_reentry)


func _test_success_limit(harness: TestHarness) -> void:
	var runtime := HandRuntimeScript.new("limit-success")
	var once := _card("once", Card.PILE_HAND, false, Card.PILE_DISCARD, 1)
	harness.assert_true(runtime.initialize_deck([once], false).ok)
	harness.assert_true(runtime.draw_cards(1).ok)
	var instance_id: String = runtime.pile_instance_ids(Card.PILE_HAND)[0]
	harness.assert_true(runtime.process_play_command(instance_id, Callable(), _success()).ok)
	harness.assert_equal(runtime.successful_play_count(instance_id), 1)
	var before: Dictionary = runtime.snapshot()
	var rejected: Variant = runtime.process_play_command(instance_id, Callable(), _success())
	harness.assert_equal(rejected.code, Result.SUCCESS_LIMIT_REACHED)
	harness.assert_equal(runtime.snapshot(), before)


func _test_creation_and_conservation(harness: TestHarness) -> void:
	var runtime := HandRuntimeScript.new("creation")
	harness.assert_true(runtime.initialize_deck([], false).ok)
	var definition := _card("generated")
	var discard: Variant = runtime.create_card(definition, Card.PILE_DISCARD, Card.INSERT_TOP)
	var draw_bottom: Variant = runtime.create_card(definition, Card.PILE_DRAW, Card.INSERT_BOTTOM)
	var draw_top: Variant = runtime.create_card(definition, Card.PILE_DRAW, Card.INSERT_TOP)
	harness.assert_true(discard.ok and draw_bottom.ok and draw_top.ok)
	harness.assert_equal(runtime.pile_instance_ids(Card.PILE_DRAW), [
		draw_bottom.details["instance_id"],
		draw_top.details["instance_id"],
	])
	harness.assert_true(runtime.move_card_to_pile(
		discard.details["instance_id"],
		Card.PILE_EXHAUST,
		Card.INSERT_TOP,
	).ok)
	_assert_conserved(harness, runtime, 3)


func _test_forbidden_source(harness: TestHarness) -> void:
	var runtime := HandRuntimeScript.new("forbidden")
	var before: Dictionary = runtime.snapshot()
	var result: Variant = runtime.initialize_deck([_card("basicDamage")], true)
	harness.assert_equal(result.code, Result.INVALID_CARD)
	harness.assert_equal(runtime.snapshot(), before)


func _test_adapter_parity(harness: TestHarness) -> void:
	var definitions := _copies(_card("adapter"), 6)
	var pure := HandRuntimeScript.new("adapter-seed")
	harness.assert_true(pure.initialize_deck(definitions, true).ok)
	var adapter := HandManagerScript.new()
	harness.assert_true(adapter.start_battle("adapter-seed", definitions, true).ok)
	harness.assert_equal(adapter.runtime_snapshot(), pure.snapshot())
	harness.assert_equal(adapter.draw_for_turn(2).to_dict(), pure.draw_for_turn(2).to_dict())
	harness.assert_equal(adapter.runtime_snapshot(), pure.snapshot())
	harness.assert_equal(adapter.end_player_turn().to_dict(), pure.end_player_turn().to_dict())
	harness.assert_equal(adapter.runtime_snapshot(), pure.snapshot())
	adapter.free()


func _runtime_with_copies(seed: Variant, count: int, shuffle_initial: bool) -> RefCounted:
	var runtime := HandRuntimeScript.new(seed)
	var initialized: Variant = runtime.initialize_deck(_copies(_card("copy"), count), shuffle_initial)
	assert(initialized.ok)
	return runtime


func _copies(definition: Resource, count: int) -> Array:
	var copies: Array = []
	for _index in range(count):
		copies.append(definition)
	return copies


func _card(
	source_skill_id: String,
	play_destination: String = Card.PILE_DISCARD,
	exhausts: bool = false,
	end_destination: String = Card.PILE_DISCARD,
	max_successes: int = 0,
) -> Resource:
	return Card.new(
		"fixture:%s" % source_skill_id,
		source_skill_id,
		"fixture",
		Card.CATEGORY_FREE,
		0,
		0,
		play_destination,
		end_destination,
		exhausts,
		"fixture.validator",
		"fixture.effect",
		false,
		0,
		0,
		1.0,
		max_successes,
	)


func _success() -> Callable:
	return func(_card_instance: Variant) -> Dictionary: return {"ok": true}


func _unique_count(values: Array) -> int:
	var unique := {}
	for value in values:
		unique[value] = true
	return unique.size()


func _assert_conserved(harness: TestHarness, runtime: RefCounted, expected: int) -> void:
	var total := 0
	var all_ids: Array = []
	for pile_name in [Card.PILE_DRAW, Card.PILE_HAND, Card.PILE_DISCARD, Card.PILE_EXHAUST]:
		var ids: Array = runtime.pile_instance_ids(pile_name)
		total += ids.size()
		all_ids.append_array(ids)
	harness.assert_equal(total, expected)
	harness.assert_equal(_unique_count(all_ids), expected)
	harness.assert_equal(runtime.total_instance_count(), expected)
