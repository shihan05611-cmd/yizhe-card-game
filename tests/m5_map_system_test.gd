extends RefCounted

const MapSystemScript = preload("res://systems/roguelike/map_system.gd")
const RngScript = preload("res://core/rng.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const RoguelikeCatalogScript = preload("res://data/catalogs/roguelike_content_catalog.gd")
const FIXTURE_PATH := "res://tests/fixtures/web_m5_map_golden.json"


func run(harness: TestHarness) -> void:
	var fixture := _load_fixture(harness)
	if fixture.is_empty():
		return
	harness.run_test("M5 map fixture records authoritative Web provenance", func() -> void:
		_test_fixture_provenance(harness, fixture)
	)
	harness.run_test("M5 three chapter maps match Web node-for-node", func() -> void:
		_test_map_golden(harness, fixture)
	)
	harness.run_test("M5 map graph exposes only first-column frontier and valid paths", func() -> void:
		_test_graph_reachability(harness, fixture)
	)
	harness.run_test("M5 weighted column consumes Run RNG and matches Web", func() -> void:
		_test_weighted_golden(harness, fixture)
	)
	harness.run_test("M5 encounter budgets preserve totals and publish authored formations", func() -> void:
		_test_encounter_golden(harness, fixture)
	)
	harness.run_test("M5 authored and special weights only redistribute total budget", func() -> void:
		_test_special_weight_distribution(harness)
	)
	harness.run_test("M5 map and encounter boundaries fail closed", func() -> void:
		_test_invalid_boundaries(harness)
	)


func _load_fixture(harness: TestHarness) -> Dictionary:
	var text := FileAccess.get_file_as_string(FIXTURE_PATH)
	if text.is_empty():
		harness.run_test("M5 map fixture is readable", func() -> void:
			harness.assert_true(false, "missing fixture: %s" % FIXTURE_PATH)
		)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		harness.run_test("M5 map fixture is valid JSON", func() -> void:
			harness.assert_true(false, "fixture root must be a Dictionary")
		)
		return {}
	return parsed


func _test_fixture_provenance(harness: TestHarness, fixture: Dictionary) -> void:
	harness.assert_equal(fixture["schema_version"], 1.0)
	harness.assert_equal(fixture["fixture_id"], "web-m5-map-golden-v1")
	harness.assert_equal(fixture["map_cases"].size(), 3)
	harness.assert_equal(fixture["encounter_cases"].size(), 3)
	harness.assert_equal(
		fixture["authoritative_modules"]["map_system"],
		"scripts/systems/roguelike/map-system.js"
	)
	harness.assert_equal(
		fixture["authoritative_modules"]["roguelike_content"],
		"scripts/data/roguelike-content.js"
	)
	for hash_value: Variant in fixture["authoritative_sha256"].values():
		harness.assert_equal(str(hash_value).length(), 64)
	harness.assert_true(not str(fixture["generated_utc"]).is_empty())


func _test_map_golden(harness: TestHarness, fixture: Dictionary) -> void:
	var catalog := RoguelikeCatalogScript.build()
	for map_case: Dictionary in fixture["map_cases"]:
		var raw_rng := RngScript.seeded(map_case["seed"])
		var initial_rng_state := raw_rng.state_snapshot()
		var random := TransactionalRandomScript.new(raw_rng)
		var errors: Array[String] = []
		var actual: Variant = random.with_transaction(func() -> Array:
			return MapSystemScript.build_chapter_map(catalog, int(map_case["chapter"]), random, errors)
		)
		harness.assert_equal(errors, [], "chapter %s: %s" % [map_case["chapter"], "; ".join(errors)])
		harness.assert_equal(actual.size(), 30)
		harness.assert_equal(actual, _normalize_nodes(map_case["nodes"]))
		harness.assert_equal(
			raw_rng.state_snapshot(), initial_rng_state,
			"fixed M1 column rules must not consume Run RNG"
		)


func _test_graph_reachability(harness: TestHarness, fixture: Dictionary) -> void:
	for map_case: Dictionary in fixture["map_cases"]:
		var nodes := _normalize_nodes(map_case["nodes"])
		var ids := {}
		for node: Dictionary in nodes:
			harness.assert_false(ids.has(node["id"]), "node ids must be unique")
			ids[node["id"]] = node
			harness.assert_equal(node["available"], node["column"] == 0)
			harness.assert_false(node["completed"])
			harness.assert_equal(node["id"], "c%d-r%d-n%d" % [node["chapter"], node["row"], node["column"]])
			for next_id: String in node["next_node_ids"]:
				harness.assert_true(ids.has(next_id) or _contains_node(nodes, next_id))
				harness.assert_equal(_node_by_id(nodes, next_id)["column"], node["column"] + 1)
		for start: Dictionary in nodes.filter(func(node: Dictionary) -> bool: return node["column"] == 0):
			var frontier: Array = [start["id"]]
			for column in range(1, 10):
				var next_frontier: Array = []
				for id: String in frontier:
					for next_id: String in ids[id]["next_node_ids"]:
						if next_id not in next_frontier:
							next_frontier.append(next_id)
				frontier = next_frontier
				harness.assert_true(not frontier.is_empty(), "every start must reach column %d" % column)


func _test_weighted_golden(harness: TestHarness, fixture: Dictionary) -> void:
	var weighted: Dictionary = fixture["weighted_case"]
	var catalog := RoguelikeCatalogScript.build()
	var weighted_catalog := catalog.duplicate(true)
	weighted_catalog["chapters"] = catalog["chapters"].duplicate()
	var chapter: Resource = catalog["chapters"][int(weighted["chapter"])].snapshot()
	var rules: Array = chapter.metadata["columnRules"].duplicate(true)
	var pool: Array = []
	for item: Dictionary in weighted["pool"]:
		pool.append({"type": item["type"], "weight": int(item["weight"])})
	rules[int(weighted["column"])] = {
		"column": int(weighted["column"]),
		"fixedByRow": null,
		"pool": pool,
	}
	chapter.metadata["columnRules"] = rules
	weighted_catalog["chapters"][int(weighted["chapter"])] = chapter

	var raw_rng := RngScript.seeded(weighted["seed"])
	var control := RngScript.seeded(weighted["seed"])
	for _index in range(3):
		control.int_range(1, 10)
	var random := TransactionalRandomScript.new(raw_rng)
	var errors: Array[String] = []
	var nodes := MapSystemScript.build_chapter_map(
		weighted_catalog, int(weighted["chapter"]), random, errors
	)
	harness.assert_equal(errors, [])
	var actual_column := nodes.filter(func(node: Dictionary) -> bool:
		return node["column"] == int(weighted["column"])
	)
	harness.assert_equal(actual_column, _normalize_nodes(weighted["expected_nodes"]))
	harness.assert_equal(
		raw_rng.state_snapshot(), control.state_snapshot(),
		"three weighted rows must consume exactly three primitive draws"
	)


func _test_encounter_golden(harness: TestHarness, fixture: Dictionary) -> void:
	var catalog := RoguelikeCatalogScript.build()
	for node: Dictionary in [
		{"chapter": 1, "row": 0, "column": 0, "type": "battle"},
		{"chapter": 2, "row": 1, "column": 6, "type": "elite"},
		{"chapter": 3, "row": 0, "column": 9, "type": "boss"},
	]:
		var errors: Array[String] = []
		var actual := MapSystemScript.resolve_encounter(
			catalog, node, RngScript.seeded("formation-%d-%s" % [node["chapter"], node["type"]]), errors
		)
		harness.assert_equal(errors, [], "; ".join(errors))
		harness.assert_true(actual["id"] != "normal")
		var active: Array = actual["slots"].filter(func(slot: Dictionary) -> bool: return not slot["empty"])
		var total_hp := 0.0
		var total_atk := 0.0
		for slot: Dictionary in active:
			total_hp += slot["total_hp_scale"]
			total_atk += slot["total_atk_scale"]
		harness.assert_true(is_equal_approx(total_hp, actual["hp_scale"] * 6.0))
		harness.assert_true(is_equal_approx(total_atk, actual["atk_scale"] * 6.0))
		for slot: Dictionary in actual["slots"]:
			if slot.has("occupied_by_unit_id"):
				harness.assert_equal(slot["total_hp_scale"], 0.0)
				harness.assert_equal(slot["total_atk_scale"], 0.0)

	var probes := [
		[{"chapter": 1, "row": 0, "column": 0, "type": "battle"}, 0.35, 0.3],
		[{"chapter": 1, "row": 0, "column": 3, "type": "battle"}, 0.805, 0.5],
		[{"chapter": 2, "row": 1, "column": 6, "type": "elite"}, 1.69, 0.48],
		[{"chapter": 3, "row": 0, "column": 9, "type": "boss"}, 2.61, 0.24],
	]
	for probe: Array in probes:
		var scales := MapSystemScript.get_node_scales(probe[0])
		harness.assert_true(is_equal_approx(scales["hp"], probe[1]))
		harness.assert_true(is_equal_approx(scales["atk"], probe[2]))


func _test_special_weight_distribution(harness: TestHarness) -> void:
	var catalog := RoguelikeCatalogScript.build()
	var custom := catalog.duplicate(true)
	custom["chapters"] = catalog["chapters"].duplicate()
	custom["encounters"] = catalog["encounters"].duplicate()
	var chapter: Resource = catalog["chapters"][1].snapshot()
	chapter.metadata["battleEncounterIds"] = ["special"]
	custom["chapters"][1] = chapter
	custom["encounters"]["special"] = {
		"id": "special",
		"name": "special",
		"hpScale": 1.2,
		"atkScale": 1.1,
		"slots": [{
			"unitId": 1,
			"pieceClassId": "shield",
			"specialId": "echo",
			"className": "",
			"hpScale": 1.5,
			"atkScale": 0.8,
			"empty": false,
		}],
	}
	var errors: Array[String] = []
	var encounter := MapSystemScript.resolve_encounter(custom, {
		"chapter": 1, "row": 0, "column": 0, "type": "battle",
	}, RngScript.seeded(9), errors)
	harness.assert_equal(errors, [])
	var echo: Dictionary = catalog["enemy_specials"]["echo"]
	var hp_denominator := 5.0 + 1.5 * float(echo["hpScale"])
	var atk_denominator := 5.0 + 0.8 * float(echo["atkScale"])
	harness.assert_equal(encounter["slots"][0]["piece_class_id"], "shield")
	harness.assert_equal(encounter["slots"][0]["special_id"], "echo")
	harness.assert_equal(encounter["slots"][0]["class_name"], echo["name"])
	harness.assert_true(is_equal_approx(
		encounter["slots"][0]["total_hp_scale"], 0.35 * (6.0 * 1.5 * echo["hpScale"] / hp_denominator)
	))
	harness.assert_true(is_equal_approx(
		encounter["slots"][0]["total_atk_scale"], 0.3 * (6.0 * 0.8 * echo["atkScale"] / atk_denominator)
	))
	harness.assert_true(is_equal_approx(
		encounter["slots"][1]["total_hp_scale"], 0.35 * (6.0 / hp_denominator)
	))


func _test_invalid_boundaries(harness: TestHarness) -> void:
	var catalog := RoguelikeCatalogScript.build()
	var rng := RngScript.seeded("invalid")
	var errors: Array[String] = []
	harness.assert_equal(MapSystemScript.build_chapter_map({}, 1, rng, errors), [])
	harness.assert_contains(errors[0], "catalog")
	errors.clear()
	harness.assert_equal(MapSystemScript.build_chapter_map(catalog, 4, rng, errors), [])
	harness.assert_contains(errors[0], "chapter")
	errors.clear()
	harness.assert_equal(MapSystemScript.build_chapter_map(catalog, 1, null, errors), [])
	harness.assert_contains(errors[0], "RNG")

	for invalid_node: Variant in [
		null,
		{"chapter": 0, "row": 0, "column": 0, "type": "battle"},
		{"chapter": 1, "row": 3, "column": 0, "type": "battle"},
		{"chapter": 1, "row": 0, "column": 10, "type": "battle"},
		{"chapter": 1, "row": 0, "column": 0, "type": "unknown"},
	]:
		errors.clear()
		harness.assert_equal(MapSystemScript.get_encounter_budget(invalid_node, errors), {})
		harness.assert_true(not errors.is_empty())

	errors.clear()
	harness.assert_equal(MapSystemScript.resolve_encounter(catalog, {
		"id": "c1-r0-n3", "chapter": 1, "row": 0, "column": 3, "type": "forge",
	}, rng, errors), {})
	harness.assert_contains(errors[0], "not a battle")

	var missing := catalog.duplicate(true)
	missing["encounters"] = catalog["encounters"].duplicate()
	missing["encounters"].erase("normal_vanguard")
	missing["encounters"].erase("normal_crossfire")
	errors.clear()
	harness.assert_equal(MapSystemScript.resolve_encounter(missing, {
		"chapter": 1, "row": 0, "column": 0, "type": "battle",
	}, rng, errors), {})
	harness.assert_contains(errors[0], "missing encounter")

	var empty := catalog.duplicate(true)
	empty["encounters"] = catalog["encounters"].duplicate()
	empty["chapters"] = catalog["chapters"].duplicate()
	var chapter: Resource = catalog["chapters"][1].snapshot()
	chapter.metadata["battleEncounterIds"] = ["empty"]
	empty["chapters"][1] = chapter
	var empty_slots: Array = []
	for unit_id in range(1, 7):
		empty_slots.append({
			"unitId": unit_id, "pieceClassId": null, "specialId": null,
			"className": "空位", "hpScale": 1.0, "atkScale": 1.0, "empty": true,
		})
	empty["encounters"]["empty"] = {
		"id": "empty", "name": "empty", "hpScale": 1.0, "atkScale": 1.0,
		"slots": empty_slots,
	}
	errors.clear()
	harness.assert_equal(MapSystemScript.resolve_encounter(empty, {
		"chapter": 1, "row": 0, "column": 0, "type": "battle",
	}, rng, errors), {})
	harness.assert_contains(errors[0], "active enemy")


func _normalize_nodes(raw_nodes: Array) -> Array:
	var nodes: Array = []
	for raw: Dictionary in raw_nodes:
		nodes.append({
			"id": raw["id"],
			"chapter": int(raw["chapter"]),
			"row": int(raw["row"]),
			"column": int(raw["column"]),
			"type": raw["type"],
			"available": raw["available"],
			"completed": raw["completed"],
			"next_node_ids": raw["next_node_ids"].duplicate(),
		})
	return nodes


func _contains_node(nodes: Array, id: String) -> bool:
	for node: Dictionary in nodes:
		if node["id"] == id:
			return true
	return false


func _node_by_id(nodes: Array, id: String) -> Dictionary:
	for node: Dictionary in nodes:
		if node["id"] == id:
			return node
	return {}


func _assert_approximately_equal(
	harness: TestHarness,
	actual: Variant,
	expected: Variant,
	path: String,
) -> void:
	if (typeof(actual) in [TYPE_INT, TYPE_FLOAT]) and (typeof(expected) in [TYPE_INT, TYPE_FLOAT]):
		harness.assert_true(is_equal_approx(float(actual), float(expected)), "%s numeric mismatch" % path)
		return
	if typeof(expected) == TYPE_ARRAY:
		harness.assert_equal(typeof(actual), TYPE_ARRAY, "%s must be an Array" % path)
		if typeof(actual) != TYPE_ARRAY:
			return
		harness.assert_equal(actual.size(), expected.size(), "%s size mismatch" % path)
		for index in range(mini(actual.size(), expected.size())):
			_assert_approximately_equal(harness, actual[index], expected[index], "%s[%d]" % [path, index])
		return
	if typeof(expected) == TYPE_DICTIONARY:
		harness.assert_equal(typeof(actual), TYPE_DICTIONARY, "%s must be a Dictionary" % path)
		if typeof(actual) != TYPE_DICTIONARY:
			return
		harness.assert_equal(actual.keys(), expected.keys(), "%s key order/shape mismatch" % path)
		for key: Variant in expected:
			if actual.has(key):
				_assert_approximately_equal(harness, actual[key], expected[key], "%s.%s" % [path, key])
		return
	harness.assert_equal(actual, expected, "%s value mismatch" % path)
