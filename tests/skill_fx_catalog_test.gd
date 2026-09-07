extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const Catalog = preload("res://data/presentation/skill_fx_catalog.gd")

const EARLY_WINDOW_MS := 50


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("six ultimate FX definitions preserve titles and start structure", func() -> void:
		_test_six_definitions(harness)
	)
	harness.run_test("fist echo count changes monotonically with hits and remains capped", func() -> void:
		_test_fist_dynamic(harness)
	)
	harness.run_test("shadow keeps lock start and explicit slash impact end", func() -> void:
		_test_shadow_two_phase(harness)
	)
	harness.run_test("all timelines and holds respect the 1500ms cap", func() -> void:
		_test_duration_cap(harness)
	)
	harness.run_test("unknown lookups are safe and reduced motion only keeps early signals", func() -> void:
		_test_safe_lookup_and_reduced_motion(harness)
	)
	print("M4-4 SKILL FX CATALOG TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_six_definitions(harness: TestHarness) -> void:
	var expected_titles := {
		"fist": "拳意·无量", "shadow": "影·狩", "ascend": "将军出征",
		"burn01": "焚界爆炎", "burnEnchant": "炎汲仪式", "puppet": "森罗万象",
	}
	harness.assert_equal(Catalog.known_keys(), expected_titles.keys())
	for key: String in Catalog.known_keys():
		var definition := Catalog.get_fx_definition("ult", key)
		harness.assert_false(definition.is_empty(), "%s definition must exist" % key)
		harness.assert_equal(definition["caption"]["title"], expected_titles[key])
		var timeline := Catalog.resolve_start_timeline(definition, {"hits": 5})
		harness.assert_true(not timeline.is_empty(), "%s start timeline must exist" % key)
		var caption := _find_step(timeline, "caption")
		var vignette := _find_step(timeline, "vignette")
		harness.assert_true(not caption.is_empty() and int(caption["at"]) <= EARLY_WINDOW_MS)
		harness.assert_true(not vignette.is_empty() and int(vignette["at"]) <= EARLY_WINDOW_MS)


func _test_fist_dynamic(harness: TestHarness) -> void:
	var definition := Catalog.get_fx_definition("ult", "fist")
	var counts: Array = []
	for hits in [3, 5, 8, 12]:
		var timeline := Catalog.resolve_start_timeline(definition, {"hits": hits})
		var streak := _find_step(timeline, "streak")
		counts.append(streak["count"])
		harness.assert_true(Catalog.timeline_end_ms(timeline) <= Catalog.FX_DURATION_CAP_MS)
	for index in range(1, counts.size()):
		harness.assert_true(counts[index] >= counts[index - 1])
	harness.assert_true(counts[0] != counts[counts.size() - 1], "fist echo count must actually change")
	var burst := _find_step(Catalog.resolve_start_timeline(definition, {"hits": 5}), "burst")
	harness.assert_equal(burst.get("ring"), "impact")


func _test_shadow_two_phase(harness: TestHarness) -> void:
	var definition := Catalog.get_fx_definition("ult", "shadow")
	var start := Catalog.resolve_start_timeline(definition)
	var finish := Catalog.resolve_end_timeline(definition)
	harness.assert_true(_find_step(start, "streak").is_empty())
	harness.assert_equal(_find_step(start, "burst").get("ring"), "lock")
	harness.assert_equal(_find_step(finish, "streak").get("variant"), "slash")
	harness.assert_equal(_find_step(finish, "burst").get("ring"), "impact")
	harness.assert_equal(Catalog.resolve_hold_ms(definition), null)
	harness.assert_equal(definition["caption"]["subtitle"], "猎杀锁定")
	harness.assert_equal(definition["caption"]["execute_subtitle"], "处决锁定")
	harness.assert_true(definition["caption"]["titleless"])


func _test_duration_cap(harness: TestHarness) -> void:
	for key: String in Catalog.known_keys():
		var definition := Catalog.get_fx_definition("ult", key)
		var start := Catalog.resolve_start_timeline(definition, {"hits": 12})
		var finish := Catalog.resolve_end_timeline(definition)
		harness.assert_true(Catalog.timeline_end_ms(start) <= Catalog.FX_DURATION_CAP_MS)
		harness.assert_true(Catalog.timeline_end_ms(finish) <= Catalog.FX_DURATION_CAP_MS)
		var hold: Variant = Catalog.resolve_hold_ms(definition, {"hits": 12})
		if hold != null:
			harness.assert_true(int(hold) <= Catalog.FX_DURATION_CAP_MS)


func _test_safe_lookup_and_reduced_motion(harness: TestHarness) -> void:
	harness.assert_true(Catalog.get_fx_definition("skill", "fist").is_empty())
	harness.assert_true(Catalog.get_fx_definition("unknown", "fist").is_empty())
	harness.assert_true(Catalog.get_fx_definition("ult", "does-not-exist").is_empty())
	harness.assert_equal(Catalog.get_skill_fx_definition("fist"), Catalog.get_fx_definition("ult", "fist"))
	var reduced := Catalog.resolve_reduced_motion_timeline()
	harness.assert_equal(reduced.size(), 2)
	harness.assert_equal(reduced.map(func(step: Dictionary) -> String: return step["prim"]), ["caption", "vignette"])


static func _find_step(timeline: Array, prim: String) -> Dictionary:
	for step: Dictionary in timeline:
		if step.get("prim", "") == prim:
			return step
	return {}

