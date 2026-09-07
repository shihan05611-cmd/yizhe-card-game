extends RefCounted

const ContentCatalog = preload("res://data/catalogs/content_catalog.gd")
const BuffDefinition = preload("res://data/definitions/buff_definition.gd")
const StoreScript = preload("res://systems/buffs/permanent_buff_store.gd")


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("permanent Store canonicalizes duplicate backing data and isolates aliases", func() -> void:
		_test_store_merge_and_isolation(harness)
	)
	harness.run_test("pure permanent helpers preserve input and merge by id target identity", func() -> void:
		_test_pure_helpers(harness)
	)
	harness.run_test("permanent Store rejects unknown battle mismatched and illegal targets atomically", func() -> void:
		_test_illegal_targets(harness)
	)
	harness.run_test("permanent Store enforces JSON-safe exact shape before writes", func() -> void:
		_test_json_shape(harness)
	)
	harness.run_test("permanent Store enforces nonstackable caps and safe integer overflow", func() -> void:
		_test_caps_and_overflow(harness)
	)
	harness.run_test("invalid initial backing data fails construction without canonicalizing", func() -> void:
		_test_constructor_atomicity(harness)
	)
	print("B1 PERMANENT BUFF TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_store_merge_and_isolation(harness: TestHarness) -> void:
	var source := [
		{"id": "flameEnchant", "target": _piece_slot(2), "stacks": 1},
		{"id": "flameEnchant", "target": _piece_slot(2), "stacks": 2},
	]
	var run_state := {"permanent_buffs": source}
	var errors: Array[String] = []
	var store := StoreScript.new(_config(run_state), errors)
	harness.assert_equal(errors, [])
	harness.assert_true(store.is_valid())
	harness.assert_equal(run_state["permanent_buffs"], [
		{"id": "flameEnchant", "target": _piece_slot(2), "stacks": 3},
	])
	harness.assert_false(is_same(run_state["permanent_buffs"], source))
	harness.assert_false(is_same(run_state["permanent_buffs"][0]["target"], source[0]["target"]))
	source[0]["target"]["id"] = 5
	source[0]["stacks"] = 99
	harness.assert_equal(store.get_stacks({"id": "flameEnchant", "target": _piece_slot(2)}), 3)

	var added: Dictionary = store.add_buff({
		"id": "flameEnchant", "target": _piece_slot(2), "stacks": 4,
	}, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(added["stacks"], 7)
	added["target"]["id"] = 6
	var listed: Array[Dictionary] = store.list(errors)
	listed[0]["target"]["id"] = 4
	listed[0]["stacks"] = 100
	harness.assert_equal(run_state["permanent_buffs"], [
		{"id": "flameEnchant", "target": _piece_slot(2), "stacks": 7},
	])
	harness.assert_equal(JSON.stringify(store.list()), JSON.stringify(run_state["permanent_buffs"]))


func _test_pure_helpers(harness: TestHarness) -> void:
	var source := [
		{"id": "flameEnchant", "target": _piece_slot(2), "stacks": 1},
		{"id": "flameEnchant", "target": _piece_slot(2), "stacks": 2},
	]
	var before := source.duplicate(true)
	var authority := _authority()
	var errors: Array[String] = []
	var normalized: Array[Dictionary] = StoreScript.normalize_instances(
		source, authority["catalog"], authority["valid_hero_ids"], errors
	)
	harness.assert_equal(errors, [])
	harness.assert_equal(source, before)
	harness.assert_equal(normalized, [
		{"id": "flameEnchant", "target": _piece_slot(2), "stacks": 3},
	])
	harness.assert_false(is_same(normalized[0], source[0]))
	harness.assert_false(is_same(normalized[0]["target"], source[0]["target"]))
	harness.assert_equal(StoreScript.get_stacks_from_instances(
		source,
		{"id": "flameEnchant", "target": _piece_slot(2)},
		authority["catalog"], authority["valid_hero_ids"], errors,
	), 3)
	var added: Array[Dictionary] = StoreScript.add_to_instances(
		source,
		{"id": "flameEnchant", "target": _piece_slot(2), "stacks": 4},
		authority["catalog"], authority["valid_hero_ids"], errors,
	)
	harness.assert_equal(added[0]["stacks"], 7)
	harness.assert_equal(source, before)


func _test_illegal_targets(harness: TestHarness) -> void:
	var invalid_cases := [
		{"request": {"id": "missing", "target": _piece_slot(1), "stacks": 1}, "message": "unknown Buff"},
		{"request": {"id": "burn", "target": _piece_slot(1), "stacks": 1}, "message": "non-permanent"},
		{"request": {"id": "fistMastery", "target": _piece_slot(1), "stacks": 1}, "message": "not allowed"},
		{"request": {"id": "flameEnchant", "target": _hero(6), "stacks": 1}, "message": "not allowed"},
		{"request": {"id": "flameEnchant", "target": _piece_slot(0), "stacks": 1}, "message": "positive safe integer"},
		{"request": {"id": "flameEnchant", "target": _piece_slot(7), "stacks": 1}, "message": "1 to 6"},
		{"request": {"id": "fistMastery", "target": _hero(99), "stacks": 1}, "message": "authoritative hero ID"},
		{"request": {"id": "fistMastery", "target": {"type": "side", "id": 1}, "stacks": 1}, "message": "pieceSlot or hero"},
		{"request": {"id": "fistMastery", "target": _hero(6), "stacks": 0}, "message": "positive safe integer"},
		{"request": {"id": "fistMastery", "target": _hero(6), "stacks": 1.5}, "message": "positive safe integer"},
		{"request": {"id": "fistMastery", "target": _hero(6), "stacks": NAN}, "message": "finite number"},
		{"request": {"id": "fistMastery", "target": {"type": "hero", "id": 6, "extra": true}, "stacks": 1}, "message": "unknown field"},
	]
	for invalid: Dictionary in invalid_cases:
		var run_state := {"permanent_buffs": []}
		var store := StoreScript.new(_config(run_state))
		var before: Array = run_state["permanent_buffs"]
		var errors: Array[String] = []
		harness.assert_equal(store.add_buff(invalid["request"], errors), {})
		harness.assert_true(errors.any(func(message: String) -> bool: return message.contains(invalid["message"])), invalid["message"])
		harness.assert_true(is_same(run_state["permanent_buffs"], before))
		harness.assert_equal(run_state["permanent_buffs"], [])


func _test_json_shape(harness: TestHarness) -> void:
	var run_state := {"permanent_buffs": []}
	var store := StoreScript.new(_config(run_state))
	var invalid_requests := [
		{"id": "fistMastery", "target": _hero(6), "stacks": 1, "__proto__": {}},
		{"id": "fistMastery", "target": _hero(6), "stacks": INF},
		{"id": "fistMastery", "target": _hero(6), "stacks": "1"},
		{"id": "fistMastery", "target": _hero(6), "stacks": 1, "callback": func() -> void: pass},
	]
	for request: Dictionary in invalid_requests:
		var before: Array = run_state["permanent_buffs"]
		var errors: Array[String] = []
		harness.assert_equal(store.add_buff(request, errors), {})
		harness.assert_true(not errors.is_empty())
		harness.assert_true(is_same(run_state["permanent_buffs"], before))

	var shared_target := _hero(6)
	var shared := [
		{"id": "fistMastery", "target": shared_target, "stacks": 1},
		{"id": "fistMastery", "target": shared_target, "stacks": 1},
	]
	var authority := _authority()
	var errors: Array[String] = []
	harness.assert_equal(StoreScript.normalize_instances(
		shared, authority["catalog"], authority["valid_hero_ids"], errors
	), [])
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("shared reference")))


func _test_caps_and_overflow(harness: TestHarness) -> void:
	var capped := BuffDefinition.new(
		"capped", "Capped", null, false, true, 3, 0, false, false,
		"capped", "permanent", ["hero"],
	)
	var capped_run := {"permanent_buffs": []}
	var capped_store := StoreScript.new({
		"run_state": capped_run, "catalog": {"capped": capped}, "valid_hero_ids": [6],
	})
	harness.assert_equal(capped_store.add_buff({"id": "capped", "target": _hero(6), "stacks": 2})["stacks"], 2)
	var capped_before: Array = capped_run["permanent_buffs"]
	var errors: Array[String] = []
	harness.assert_equal(capped_store.add_buff({"id": "capped", "target": _hero(6), "stacks": 2}, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("max_stacks 3")))
	harness.assert_true(is_same(capped_run["permanent_buffs"], capped_before))

	var unique := BuffDefinition.new(
		"unique", "Unique", null, false, false, 3, 0, false, false,
		"unique", "permanent", ["hero"],
	)
	var unique_run := {"permanent_buffs": []}
	var unique_store := StoreScript.new({
		"run_state": unique_run, "catalog": {"unique": unique}, "valid_hero_ids": [6],
	})
	harness.assert_equal(unique_store.add_buff({"id": "unique", "target": _hero(6), "stacks": 1})["stacks"], 1)
	var unique_before: Array = unique_run["permanent_buffs"]
	errors.clear()
	harness.assert_equal(unique_store.add_buff({"id": "unique", "target": _hero(6), "stacks": 1}, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("non-stackable")))
	harness.assert_true(is_same(unique_run["permanent_buffs"], unique_before))

	var authority := _authority()
	var overflow_run := {"permanent_buffs": [{
		"id": "fistMastery", "target": _hero(6), "stacks": StoreScript.MAX_SAFE_INTEGER,
	}]}
	var overflow_store := StoreScript.new(_config(overflow_run))
	var overflow_before: Array = overflow_run["permanent_buffs"]
	errors.clear()
	harness.assert_equal(overflow_store.add_buff({
		"id": "fistMastery", "target": _hero(6), "stacks": 1,
	}, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("overflow")))
	harness.assert_true(is_same(overflow_run["permanent_buffs"], overflow_before))
	harness.assert_equal(StoreScript.stack_limit_for(authority["catalog"]["fistMastery"]), StoreScript.MAX_SAFE_INTEGER)


func _test_constructor_atomicity(harness: TestHarness) -> void:
	var initial := [
		{"id": "flameEnchant", "target": _piece_slot(3), "stacks": 1},
		{"id": "flameEnchant", "target": _piece_slot(3), "stacks": 2},
		{"id": "missing", "target": _piece_slot(3), "stacks": 1},
	]
	var run_state := {"permanent_buffs": initial}
	var before := initial.duplicate(true)
	var errors: Array[String] = []
	var store := StoreScript.new(_config(run_state), errors)
	harness.assert_false(store.is_valid())
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("unknown Buff")))
	harness.assert_true(is_same(run_state["permanent_buffs"], initial))
	harness.assert_equal(run_state["permanent_buffs"], before)


func _config(run_state: Dictionary) -> Dictionary:
	var authority := _authority()
	return {
		"run_state": run_state,
		"catalog": authority["catalog"],
		"valid_hero_ids": authority["valid_hero_ids"],
	}


func _authority() -> Dictionary:
	var catalog := _catalog()
	return {
		"catalog": catalog["buffs"],
		"valid_hero_ids": catalog["characters"]["players"].keys(),
	}


func _catalog() -> Dictionary:
	var errors: Array[String] = []
	var catalog: Dictionary = ContentCatalog.build(errors)
	assert(errors.is_empty())
	return catalog


func _piece_slot(id: int) -> Dictionary:
	return {"type": "pieceSlot", "id": id}


func _hero(id: int) -> Dictionary:
	return {"type": "hero", "id": id}
