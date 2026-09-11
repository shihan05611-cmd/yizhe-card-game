extends RefCounted

const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const RunContract = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycle = preload("res://systems/roguelike/run_lifecycle.gd")
const RunCardIdentity = preload("res://systems/cards/run_card_identity.gd")
const TransactionalRandom = preload("res://systems/roguelike/run_random_transaction.gd")
const Rng = preload("res://core/rng.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("Run card identities distinguish duplicate copies and remap filtered extras", func() -> void:
		_test_card_identity(harness)
	)
	harness.run_test("留墨 selects one unretained copy once and can be skipped", func() -> void:
		_test_retention_event(harness)
	)
	harness.run_test("留墨 and legacy currency event checkpoints resume without reroll or duplicate reward", func() -> void:
		_test_event_persistence(harness)
	)
	harness.run_test("selling a free copy removes its retain key and shifts later identities", func() -> void:
		_test_sale_reindex(harness)
	)


func _test_card_identity(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalog.build(errors)
	var state: Dictionary = RunContract.create()
	state["free_skill_ids"] = ["pieceAction", "pieceAction", "smallHeal"]
	state["hero_deployment_slots"] = {"7": 1}
	state["front_hero_ids"] = [7]
	state["exclusive_card_ids"] = ["exclusive:puppetAttunement", "exclusive:pressOpening"]
	state["retained_card_keys"] = ["free:1", "hero:7", "exclusive:1"]
	var candidates: Array[Dictionary] = RunCardIdentity.enumerate_candidates(state, catalogs, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(candidates.filter(func(value: Dictionary) -> bool:
		return value["card_id"] == "free:pieceAction"
	).map(func(value: Dictionary) -> Array: return [value["key"], value["copy_ordinal"], value["retained"]]), [
		["free:0", 1, false], ["free:1", 2, true],
	])
	harness.assert_false(candidates.any(func(value: Dictionary) -> bool:
		return str(value["card_id"]).begins_with("ultimate:")
	), "ultimates never enter 留墨 candidates")
	var battle_keys: Array[String] = RunCardIdentity.retained_keys_for_battle(
		state, [7], catalogs, errors
	)
	harness.assert_equal(errors, [])
	harness.assert_equal(battle_keys, ["free:1", "hero:7", "exclusive:0"])


func _test_retention_event(harness: TestHarness) -> void:
	var pair: Dictionary = _find_event_kinds("retain-event", harness)
	var retained: Dictionary = pair["retain_card"]
	var errors: Array[String] = []
	var lifecycle: Variant = retained["lifecycle"]
	var state: Dictionary = retained["state"]
	var event: Dictionary = lifecycle.get_current_event(errors)
	harness.assert_equal(event["kind"], "retain_card")
	harness.assert_true(event["options"].size() >= 4)
	var piece_copies: Array = event["options"].filter(func(option: Dictionary) -> bool:
		return option["card_id"] == "free:pieceAction"
	)
	harness.assert_equal(piece_copies.size(), 2)
	var selected_key: String = piece_copies[1]["key"]
	harness.assert_true(lifecycle.select_retained_card(selected_key, errors), "select 留墨: %s" % "; ".join(errors))
	harness.assert_equal(state["retained_card_keys"], [selected_key])
	harness.assert_equal(state["status"], "map")
	var after_once: Dictionary = state.duplicate(true)
	harness.assert_false(lifecycle.select_retained_card(selected_key, errors))
	harness.assert_equal(state, after_once)

	var skipped: Dictionary = _find_event_kinds("skip-event", harness)["retain_card"]
	harness.assert_true(skipped["lifecycle"].skip_retained_card_event(errors), "skip 留墨: %s" % "; ".join(errors))
	harness.assert_equal(skipped["state"]["retained_card_keys"], [])
	harness.assert_equal(skipped["state"]["status"], "map")


func _test_event_persistence(harness: TestHarness) -> void:
	var pair: Dictionary = _find_event_kinds("persist-event", harness)
	var retained: Dictionary = pair["retain_card"]
	var errors: Array[String] = []
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(
		retained["lifecycle"].export_checkpoint(errors)
	))
	var restored: Variant = RunLifecycle.restore_checkpoint(
		checkpoint, retained["catalogs"], retained["random"], errors
	)
	harness.assert_not_null(restored, "; ".join(errors))
	var restored_event: Dictionary = restored.get_current_event(errors)
	harness.assert_equal(restored_event["kind"], "retain_card")
	harness.assert_equal(
		restored_event["options"].map(func(option: Dictionary) -> String: return option["key"]),
		retained["lifecycle"].get_current_event(errors)["options"].map(
			func(option: Dictionary) -> String: return option["key"]
		),
	)

	var currency: Dictionary = pair["currency"]
	var awarded: int = currency["state"]["currency"]
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(
		currency["lifecycle"].export_checkpoint(errors)
	))
	legacy["version"] = 3
	legacy["state"].erase("retained_card_keys")
	legacy["state"].erase("current_event_kind")
	var legacy_restored: Variant = RunLifecycle.restore_checkpoint(
		legacy, currency["catalogs"], currency["random"], errors
	)
	harness.assert_not_null(legacy_restored, "; ".join(errors))
	harness.assert_equal(legacy_restored.get_current_event(errors)["kind"], "currency")
	harness.assert_equal(legacy_restored.snapshot(errors)["currency"], awarded)
	harness.assert_true(legacy_restored.complete_current_node(errors), "; ".join(errors))
	harness.assert_equal(legacy_restored.snapshot(errors)["currency"], awarded)


func _test_sale_reindex(harness: TestHarness) -> void:
	var fixture: Dictionary = _started("sale-retain", harness)
	var state: Dictionary = fixture["state"]
	var lifecycle: Variant = fixture["lifecycle"]
	var errors: Array[String] = []
	var first_piece_index: int = state["free_skill_ids"].find("pieceAction")
	state["retained_card_keys"] = [
		"free:%d" % first_piece_index,
		"free:%d" % (first_piece_index + 1),
	]
	state["relic_ids"].append("tradePermit")
	_force_node(lifecycle, state, "shop", errors)
	harness.assert_true(lifecycle.sell_free_skill("pieceAction", errors), "; ".join(errors))
	harness.assert_equal(state["free_skill_ids"].count("pieceAction"), 1)
	harness.assert_equal(state["retained_card_keys"], ["free:%d" % first_piece_index])


func _find_event_kinds(prefix: String, harness: TestHarness) -> Dictionary:
	var found := {}
	for index in 64:
		var fixture: Dictionary = _started("%s-%d" % [prefix, index], harness)
		var errors: Array[String] = []
		_force_node(fixture["lifecycle"], fixture["state"], "event", errors)
		if not errors.is_empty():
			continue
		var kind: String = fixture["state"]["current_event_kind"]
		if not found.has(kind):
			found[kind] = fixture
		if found.size() == 2:
			break
	harness.assert_true(found.has("currency"), "event RNG must reach the currency event")
	harness.assert_true(found.has("retain_card"), "event RNG must reach 留墨")
	return found


func _started(seed: String, harness: TestHarness) -> Dictionary:
	var errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalog.build(errors)
	var state: Dictionary = RunContract.create()
	var random := TransactionalRandom.new(Rng.seeded(seed), errors)
	var lifecycle := RunLifecycle.new(state, catalogs, random, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	harness.assert_true(lifecycle.choose_starting_hero(
		state["initial_hero_choice_ids"][0], errors
	), "; ".join(errors))
	return {
		"state": state, "catalogs": catalogs, "random": random, "lifecycle": lifecycle,
	}


func _force_node(
	lifecycle: Variant,
	state: Dictionary,
	type: String,
	errors: Array[String],
) -> void:
	var selected: Dictionary = {}
	for node: Dictionary in state["map_nodes"]:
		node["available"] = false
		if selected.is_empty() and node["type"] == type:
			selected = node
	if selected.is_empty():
		errors.append("map has no %s node" % type)
		return
	selected["available"] = true
	lifecycle.choose_node(selected["id"], errors)
