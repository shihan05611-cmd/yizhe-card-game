extends RefCounted

const RngScript = preload("res://core/rng.gd")
const FIXTURE_PATH := "res://tests/fixtures/web_rng_golden.json"


func run(harness: TestHarness) -> void:
	var fixture := _load_fixture(harness)
	if fixture.is_empty():
		return

	harness.run_test("Web fixture provenance and shape", func() -> void:
		_test_fixture_provenance(harness, fixture)
	)
	harness.run_test("direct seeded sequence matches 1000 Web uint32 values", func() -> void:
		_test_direct_golden_sequence(harness, fixture)
	)
	harness.run_test("four named streams match 4000 Web uint32 values", func() -> void:
		_test_named_stream_golden_sequences(harness, fixture)
	)
	harness.run_test("derive seed and named stream independence", func() -> void:
		_test_derive_and_independence(harness, fixture)
	)
	harness.run_test("UTF-16 numeric and zero seed behavior", func() -> void:
		_test_seed_edge_cases(harness, fixture)
	)
	harness.run_test("replay range pick and shuffle helpers", func() -> void:
		_test_random_source_helpers(harness)
	)


func _load_fixture(harness: TestHarness) -> Dictionary:
	var fixture_text := FileAccess.get_file_as_string(FIXTURE_PATH)
	if fixture_text.is_empty():
		harness.run_test("Web RNG fixture is readable", func() -> void:
			harness.assert_true(false, "missing or empty fixture: %s" % FIXTURE_PATH)
		)
		return {}
	var parsed: Variant = JSON.parse_string(fixture_text)
	if not parsed is Dictionary:
		harness.run_test("Web RNG fixture is valid JSON", func() -> void:
			harness.assert_true(false, "fixture root must be a JSON object")
		)
		return {}
	return parsed


func _test_fixture_provenance(harness: TestHarness, fixture: Dictionary) -> void:
	harness.assert_equal(fixture["schema_version"], 1.0)
	harness.assert_equal(fixture["sequence_length"], 1000.0)
	harness.assert_equal(
		fixture["default_stream_names"],
		["combat", "allyPolicy", "enemyPolicy", "run"]
	)
	harness.assert_equal(fixture["provenance"]["source_sha256"].length(), 64)
	var authoritative_module := str(fixture["provenance"]["authoritative_module"])
	harness.assert_true(
		authoritative_module.ends_with("新弈者/Html/scripts/core/random.js")
		or authoritative_module.ends_with("弈者-独立版/Html/scripts/core/random.js")
	)
	harness.assert_contains(fixture["provenance"]["algorithm"], "exact uint32 numerators")
	harness.assert_true(not fixture["provenance"]["generated_utc"].is_empty())
	harness.assert_equal(fixture["direct_seeded_u32"].size(), 1000)
	for stream_name in fixture["default_stream_names"]:
		harness.assert_equal(fixture["named_streams_u32"][stream_name].size(), 1000)


func _test_direct_golden_sequence(harness: TestHarness, fixture: Dictionary) -> void:
	var random := RngScript.seeded(fixture["master_seed"])
	var expected_values: Array = fixture["direct_seeded_u32"]
	for index in range(expected_values.size()):
		harness.assert_equal(
			random.next_u32(),
			int(expected_values[index]),
			"direct sequence mismatch at index %d" % index
		)


func _test_named_stream_golden_sequences(harness: TestHarness, fixture: Dictionary) -> void:
	var streams: Dictionary = RngScript.create_named_streams(fixture["master_seed"])
	for stream_name in fixture["default_stream_names"]:
		harness.assert_true(streams.has(stream_name), "missing named stream: %s" % stream_name)
		var expected_values: Array = fixture["named_streams_u32"][stream_name]
		for index in range(expected_values.size()):
			harness.assert_equal(
				streams[stream_name].next_u32(),
				int(expected_values[index]),
				"%s sequence mismatch at index %d" % [stream_name, index]
			)


func _test_derive_and_independence(harness: TestHarness, fixture: Dictionary) -> void:
	for stream_name in fixture["default_stream_names"]:
		harness.assert_equal(
			RngScript.derive_seed(fixture["master_seed"], stream_name),
			int(fixture["derive_seeds"][stream_name]),
			"derived seed mismatch: %s" % stream_name
		)

	var baseline: Dictionary = RngScript.create_named_streams(fixture["master_seed"])
	var consumed: Dictionary = RngScript.create_named_streams(fixture["master_seed"])
	for _index in range(25):
		consumed["combat"].next_u32()
	for stream_name in ["allyPolicy", "enemyPolicy", "run"]:
		for index in range(16):
			harness.assert_equal(
				consumed[stream_name].next_u32(),
				baseline[stream_name].next_u32(),
				"combat consumption leaked into %s at index %d" % [stream_name, index]
			)


func _test_seed_edge_cases(harness: TestHarness, fixture: Dictionary) -> void:
	var edge_cases: Dictionary = fixture["edge_cases"]
	var utf16_random := RngScript.seeded(edge_cases["utf16_seed"])
	for index in range(edge_cases["utf16_first_u32"].size()):
		harness.assert_equal(
			utf16_random.next_u32(),
			int(edge_cases["utf16_first_u32"][index]),
			"UTF-16 seed mismatch at index %d" % index
		)
	harness.assert_equal(
		RngScript.derive_seed(edge_cases["utf16_seed"], "流🎴"),
		int(edge_cases["utf16_derive_probe"]),
		"UTF-16 stream-name derivation must use surrogate code units"
	)

	var numeric_random := RngScript.seeded(edge_cases["numeric_seed"])
	var equivalent_random := RngScript.seeded(edge_cases["numeric_equivalent_seed"])
	for index in range(edge_cases["numeric_first_u32"].size()):
		var expected := int(edge_cases["numeric_first_u32"][index])
		harness.assert_equal(numeric_random.next_u32(), expected, "numeric seed mismatch at index %d" % index)
		harness.assert_equal(
			equivalent_random.next_u32(),
			expected,
			"numeric >>>0 normalization mismatch at index %d" % index
		)

	var zero_random := RngScript.seeded(edge_cases["zero_seed"])
	for index in range(edge_cases["zero_first_u32"].size()):
		harness.assert_equal(
			zero_random.next_u32(),
			int(edge_cases["zero_first_u32"][index]),
			"zero-seed fallback mismatch at index %d" % index
		)

	_test_edge_sequence(harness, RngScript.seeded(NAN), edge_cases["nan_first_u32"], "NaN seed")
	_test_edge_sequence(
		harness,
		RngScript.seeded(INF),
		edge_cases["positive_infinity_first_u32"],
		"positive Infinity seed"
	)
	_test_edge_sequence(
		harness,
		RngScript.seeded(-INF),
		edge_cases["negative_infinity_first_u32"],
		"negative Infinity seed"
	)


func _test_edge_sequence(
	harness: TestHarness,
	random: DeterministicRng,
	expected_values: Array,
	label: String,
) -> void:
	for index in range(expected_values.size()):
		harness.assert_equal(
			random.next_u32(),
			int(expected_values[index]),
			"%s mismatch at index %d" % [label, index]
		)


func _test_random_source_helpers(harness: TestHarness) -> void:
	harness.assert_equal(RngScript.derive_seed(1, ""), null, "empty stream names must be rejected")
	harness.assert_equal(RngScript.create_named_streams(1, []), {}, "empty stream lists must be rejected")
	harness.assert_equal(
		RngScript.create_named_streams(1, ["combat", "combat"]),
		{},
		"duplicate stream names must be rejected"
	)

	var replay_a := RngScript.seeded("helper-seed")
	var replay_b := RngScript.seeded("helper-seed")
	for index in range(32):
		harness.assert_equal(replay_a.next_u32(), replay_b.next_u32(), "replay mismatch at index %d" % index)

	var float_rng := RngScript.seeded(12345)
	var float_value: Variant = float_rng.float_range(-2.5, 7.5)
	harness.assert_true(float_value is float)
	harness.assert_true(float_value >= -2.5 and float_value < 7.5)

	var rejected_rng := RngScript.seeded(12345)
	var rejected_baseline := RngScript.seeded(12345)
	harness.assert_equal(rejected_rng.float_range(2.0, 1.0), null)
	harness.assert_equal(rejected_rng.int_range(2, 1), null)
	harness.assert_equal(rejected_rng.pick([]), null)
	harness.assert_equal(
		rejected_rng.next_u32(),
		rejected_baseline.next_u32(),
		"rejected helper input must not consume RNG state"
	)

	var int_rng := RngScript.seeded(12345)
	for _index in range(64):
		var int_value: Variant = int_rng.int_range(-3, 4)
		harness.assert_true(int_value is int)
		harness.assert_true(int_value >= -3 and int_value <= 4)

	var pick_rng := RngScript.seeded(12345)
	var picked: Variant = pick_rng.pick(["a", "b", "c"])
	harness.assert_true(picked in ["a", "b", "c"])

	var original := [1, 2, 3, 4, 5, 6]
	var shuffle_a: Array = RngScript.seeded("shuffle-seed").shuffle(original)
	var shuffle_b: Array = RngScript.seeded("shuffle-seed").shuffle(original)
	harness.assert_equal(original, [1, 2, 3, 4, 5, 6], "shuffle must not mutate its input")
	harness.assert_equal(shuffle_a, shuffle_b, "shuffle must replay with the same seed")
	var sorted_shuffle := shuffle_a.duplicate()
	sorted_shuffle.sort()
	harness.assert_equal(sorted_shuffle, original, "shuffle must preserve every element")
