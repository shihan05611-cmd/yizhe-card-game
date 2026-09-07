extends RefCounted

const Dispatcher = preload("res://systems/relics/hook_dispatcher.gd")
const EventCatalog = preload("res://data/catalogs/event_catalog.gd")


class ReentrantDefinition extends Resource:
	var target_dispatcher: Variant
	var registration_options := {}
	var nested_errors: Array[String] = []
	var hooks: Array = []
	var id: String:
		get:
			target_dispatcher.register_catalog({}, registration_options, nested_errors)
			return "outer"


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("dispatcher validates atomically and recovers after rejected registration", func() -> void:
		_test_atomic_validation(harness)
	)
	harness.run_test("dispatcher rejects nested registration while outer registration remains atomic", func() -> void:
		_test_reentrant_registration(harness)
	)
	harness.run_test("dispatcher implements all limits and reset lifetimes", func() -> void:
		_test_limits_and_resets(harness)
	)
	harness.run_test("dispatcher keys per-round counters by actor target and side", func() -> void:
		_test_scopes(harness)
	)
	harness.run_test("dispatcher isolates resolver failures and counts only successful effects", func() -> void:
		_test_error_isolation(harness)
	)
	harness.run_test("dispatcher requires explicit structured effect success", func() -> void:
		_test_explicit_success_protocol(harness)
	)
	harness.run_test("dispatcher snapshots definitions params payloads and results deeply", func() -> void:
		_test_deep_snapshots(harness)
	)
	harness.run_test("dispatcher accepts B0 snake-case event aliases", func() -> void:
		_test_snake_case_event_alias(harness)
	)
	print("B2 HOOK DISPATCHER TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_atomic_validation(harness: TestHarness) -> void:
	var invalid_overrides := [
		{"event": "missingEvent"},
		{"limit": "sometimes"},
		{"limit_scope": "party"},
		{"limit_value": 0},
		{"hook_index": 2},
		{"effect_id": "missing.effect"},
	]
	for index in invalid_overrides.size():
		var reports: Array = []
		var dispatcher: Variant = _dispatcher(reports)
		var registry := _registry({"ok.effect": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary: return {"ok": true}})
		var valid_before := _definition("before-%d" % index, "roundStart", "ok.effect")
		var invalid := _definition("invalid-%d" % index, "roundStart", "ok.effect")
		invalid["hooks"][0].merge(invalid_overrides[index], true)
		var errors: Array[String] = []
		harness.assert_false(dispatcher.register_catalog({"before": valid_before, "invalid": invalid}, {
			"resolver_registry": registry,
		}, errors))
		harness.assert_true(not errors.is_empty())
		harness.assert_equal(dispatcher.dispatch("roundStart", {"round": 1}), {"event": "roundStart", "delivered": 0})
		harness.assert_equal(dispatcher.get_trigger_count(valid_before["id"], 0), 0)
		harness.assert_true(dispatcher.register_catalog({"recovery": valid_before}, {"resolver_registry": registry}, errors))
		harness.assert_equal(errors, [])

	var dispatcher: Variant = _dispatcher([])
	var registry := _registry({"ok.effect": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary: return {"ok": true}})
	var errors: Array[String] = []
	harness.assert_true(dispatcher.register_catalog({"first": _definition("same", "roundStart", "ok.effect")}, {"resolver_registry": registry}, errors))
	harness.assert_false(dispatcher.register_catalog({
		"fresh": _definition("fresh", "roundStart", "ok.effect"),
		"duplicate": _definition("same", "roundStart", "ok.effect"),
	}, {"resolver_registry": registry}, errors))
	harness.assert_equal(dispatcher.get_trigger_count("fresh", 0), 0)


func _test_reentrant_registration(harness: TestHarness) -> void:
	var dispatcher: Variant = _dispatcher([])
	var registry := _registry({"ok.effect": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary: return {"ok": true}})
	var definition := ReentrantDefinition.new()
	definition.target_dispatcher = dispatcher
	definition.registration_options = {"resolver_registry": registry}
	definition.hooks = [_hook("roundStart", "ok.effect")]
	var errors: Array[String] = []
	harness.assert_true(dispatcher.register_catalog({"outer": definition}, definition.registration_options, errors))
	harness.assert_equal(errors, [])
	harness.assert_equal(definition.nested_errors.size(), 1)
	harness.assert_contains(definition.nested_errors[0], "reentrant")
	harness.assert_equal(dispatcher.dispatch("roundStart", {"round": 1})["delivered"], 1)


func _test_limits_and_resets(harness: TestHarness) -> void:
	var counts := {"none": 0, "battle": 0, "round": 0, "run": 0, "first": 0}
	var effects := {}
	for id in counts:
		effects["effect.%s" % id] = func(_context: Dictionary, _subject: Variant, params: Dictionary) -> Dictionary:
			counts[params["id"]] += 1
			return {"ok": true}
	var catalog := {
		"none": _definition("none", "roundStart", "effect.none", Dispatcher.LIMIT_NONE, 1, Dispatcher.SCOPE_EVENT, {"id": "none"}),
		"battle": _definition("battle", "roundStart", "effect.battle", Dispatcher.LIMIT_PER_BATTLE, 1, Dispatcher.SCOPE_EVENT, {"id": "battle"}),
		"round": _definition("round", "roundStart", "effect.round", Dispatcher.LIMIT_PER_ROUND, 1, Dispatcher.SCOPE_EVENT, {"id": "round"}),
		"run": _definition("run", "roundStart", "effect.run", Dispatcher.LIMIT_ONCE_PER_RUN, 1, Dispatcher.SCOPE_EVENT, {"id": "run"}),
		"first": _definition("first", "roundStart", "effect.first", Dispatcher.LIMIT_FIRST_N_ROUNDS, 2, Dispatcher.SCOPE_EVENT, {"id": "first"}),
	}
	var dispatcher: Variant = _dispatcher([])
	var errors: Array[String] = []
	harness.assert_true(dispatcher.register_catalog(catalog, {"resolver_registry": _registry(effects)}, errors))
	dispatcher.dispatch("roundStart", {"round": 1})
	dispatcher.dispatch("roundStart", {"round": 1})
	harness.assert_equal(counts, {"none": 2, "battle": 1, "round": 1, "run": 1, "first": 2})
	dispatcher.reset_round()
	dispatcher.dispatch("roundStart", {"round": 2})
	dispatcher.dispatch("roundStart", {"round": 3})
	harness.assert_equal(counts, {"none": 4, "battle": 1, "round": 2, "run": 1, "first": 3})
	dispatcher.reset_battle()
	dispatcher.dispatch("roundStart", {"round": 1})
	harness.assert_equal(counts, {"none": 5, "battle": 2, "round": 3, "run": 1, "first": 4})
	harness.assert_equal(dispatcher.get_trigger_count("run", 0), 1)
	dispatcher.reset_run()
	harness.assert_equal(dispatcher.get_trigger_count("run", 0), 0)


func _test_scopes(harness: TestHarness) -> void:
	var calls: Array[String] = []
	var registry := _registry({
		"actor.effect": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary:
			calls.append("actor")
			return {"ok": true},
		"target.effect": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary:
			calls.append("target")
			return {"ok": true},
	})
	var dispatcher: Variant = _dispatcher([])
	var errors: Array[String] = []
	harness.assert_true(dispatcher.register_catalog({
		"actor": _definition("actor", "pieceAttackHit", "actor.effect", Dispatcher.LIMIT_PER_ROUND, 1, Dispatcher.SCOPE_ACTOR),
		"target": _definition("target", "unitDamaged", "target.effect", Dispatcher.LIMIT_PER_ROUND, 1, Dispatcher.SCOPE_TARGET),
	}, {"resolver_registry": registry}, errors))
	var ally_one := {"id": 1, "side": "ally"}
	var ally_two := {"id": 2, "side": "ally"}
	var enemy_one := {"id": 1, "side": "enemy"}
	dispatcher.dispatch("pieceAttackHit", {"round": 1, "actor": ally_one})
	dispatcher.dispatch("pieceAttackHit", {"round": 1, "actor": ally_one})
	dispatcher.dispatch("pieceAttackHit", {"round": 1, "actor": ally_two})
	dispatcher.dispatch("unitDamaged", {"round": 1, "target": ally_one})
	dispatcher.dispatch("unitDamaged", {"round": 1, "target": ally_one})
	dispatcher.dispatch("unitDamaged", {"round": 1, "target": enemy_one})
	harness.assert_equal(calls, ["actor", "actor", "target", "target"])
	harness.assert_equal(dispatcher.get_trigger_count("actor", 0, "actor:ally:1"), 1)
	harness.assert_equal(dispatcher.get_trigger_count("target", 0, "target:enemy:1"), 1)
	dispatcher.reset_round()
	dispatcher.dispatch("pieceAttackHit", {"round": 2, "actor": ally_one})
	harness.assert_equal(calls.size(), 5)


func _test_error_isolation(harness: TestHarness) -> void:
	var reports: Array = []
	var calls: Array[String] = []
	var registry := {
		"conditions": {
			"condition.fail": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary: return {"ok": false, "error": "condition failed"},
		},
		"effects": {
			"effect.fail": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary:
				calls.append("failed")
				return {"ok": false, "error": "effect failed"},
			"effect.ok": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary:
				calls.append("ok")
				return {"ok": true},
		},
	}
	var dispatcher: Variant = _dispatcher(reports)
	var condition_failure := _definition("condition", "roundStart", "effect.ok")
	condition_failure["hooks"][0]["condition_id"] = "condition.fail"
	var errors: Array[String] = []
	harness.assert_true(dispatcher.register_catalog({
		"condition": condition_failure,
		"effect": _definition("effect", "roundStart", "effect.fail"),
		"last": _definition("last", "roundStart", "effect.ok"),
	}, {"resolver_registry": registry}, errors))
	var result: Dictionary = dispatcher.dispatch("roundStart", {"round": 1})
	harness.assert_equal(result["delivered"], 1)
	harness.assert_equal(calls, ["failed", "ok"])
	harness.assert_equal(reports.map(func(report: Dictionary) -> String: return report["metadata"]["phase"]), ["condition", "effect"])
	harness.assert_equal(dispatcher.get_trigger_count("condition", 0), 0)
	harness.assert_equal(dispatcher.get_trigger_count("effect", 0), 0)
	harness.assert_equal(dispatcher.get_trigger_count("last", 0), 1)


func _test_explicit_success_protocol(harness: TestHarness) -> void:
	var reports: Array = []
	var dispatcher: Variant = _dispatcher(reports)
	var errors: Array[String] = []
	var registry := _registry({
		"nil.effect": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Variant: return null,
		"bool.effect": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> bool: return true,
		"ok.effect": func(_c: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary: return {"ok": true},
	})
	harness.assert_true(dispatcher.register_catalog({
		"nil": _definition("nil", "roundStart", "nil.effect"),
		"bool": _definition("bool", "roundStart", "bool.effect"),
		"ok": _definition("ok", "roundStart", "ok.effect"),
	}, {"resolver_registry": registry}, errors))
	harness.assert_equal(dispatcher.dispatch("roundStart", {"round": 1})["delivered"], 1)
	harness.assert_equal(dispatcher.get_trigger_count("nil", 0), 0)
	harness.assert_equal(dispatcher.get_trigger_count("bool", 0), 0)
	harness.assert_equal(dispatcher.get_trigger_count("ok", 0), 1)
	harness.assert_equal(reports.size(), 2)
	harness.assert_true(reports.all(func(report: Dictionary) -> bool: return report["metadata"]["phase"] == "effect"))
	harness.assert_true(reports.all(func(report: Dictionary) -> bool: return report["message"].contains("{ok:true}")))


func _test_deep_snapshots(harness: TestHarness) -> void:
	var seen: Array = []
	var source := _definition("snapshot", "roundStart", "snapshot.effect", Dispatcher.LIMIT_NONE, 1, Dispatcher.SCOPE_EVENT, {
		"nested": {"values": ["original"]},
	})
	var registry := _registry({
		"snapshot.effect": func(context: Dictionary, _subject: Variant, params: Dictionary) -> Dictionary:
			seen.append({"context": context, "params": params})
			params["nested"]["values"].append("resolver")
			context["nested"]["values"].append("resolver")
			return {"ok": true},
	})
	var dispatcher: Variant = _dispatcher([])
	var errors: Array[String] = []
	harness.assert_true(dispatcher.register_catalog({"snapshot": source}, {
		"resolver_registry": registry,
		"is_enabled": func(definition: Dictionary, _context: Dictionary) -> bool:
			definition["hooks"][0]["effect_params"]["nested"]["values"].append("enabled")
			return true,
	}, errors))
	source["hooks"][0]["event"] = "roundEnd"
	source["hooks"][0]["effect_params"]["nested"]["values"].append("caller")
	var payload := {"round": 1, "nested": {"values": ["payload"]}}
	var first: Dictionary = dispatcher.dispatch("roundStart", payload)
	first["event"] = "mutated"
	var second: Dictionary = dispatcher.dispatch("roundStart", payload)
	harness.assert_equal(first["delivered"], 1)
	harness.assert_equal(second, {"event": "roundStart", "delivered": 1})
	harness.assert_equal(payload["nested"]["values"], ["payload"])
	harness.assert_equal(seen[0]["params"]["nested"]["values"], ["original", "resolver"])
	harness.assert_equal(seen[1]["params"]["nested"]["values"], ["original", "resolver"])


func _test_snake_case_event_alias(harness: TestHarness) -> void:
	var calls := [0]
	var dispatcher: Variant = _dispatcher([])
	var errors: Array[String] = []
	harness.assert_true(dispatcher.register_catalog({
		"alias": _definition("alias", "unitDamaged", "alias.effect"),
	}, {"resolver_registry": _registry({
		"alias.effect": func(context: Dictionary, _s: Variant, _p: Dictionary) -> Dictionary:
			harness.assert_equal(context["event"], "unitDamaged")
			calls[0] += 1
			return {"ok": true},
	})}, errors))
	harness.assert_equal(dispatcher.dispatch("unit_damaged", {"round": 1}), {"event": "unitDamaged", "delivered": 1})
	harness.assert_equal(calls[0], 1)


func _dispatcher(reports: Array) -> Variant:
	var errors: Array[String] = []
	var dispatcher: Variant = Dispatcher.new({
		"event_catalog": EventCatalog.build(),
		"on_error": func(message: String, metadata: Dictionary) -> void:
			reports.append({"message": message, "metadata": metadata}),
	}, errors)
	assert(errors.is_empty())
	assert(dispatcher.is_valid())
	return dispatcher


func _registry(effects: Dictionary, conditions: Dictionary = {}) -> Dictionary:
	return {"conditions": conditions, "effects": effects}


func _definition(
	id: String,
	event: String,
	effect_id: String,
	limit: String = Dispatcher.LIMIT_NONE,
	limit_value: int = 1,
	limit_scope: String = Dispatcher.SCOPE_EVENT,
	effect_params: Dictionary = {},
) -> Dictionary:
	return {"id": id, "hooks": [_hook(event, effect_id, limit, limit_value, limit_scope, effect_params)]}


func _hook(
	event: String,
	effect_id: String,
	limit: String = Dispatcher.LIMIT_NONE,
	limit_value: int = 1,
	limit_scope: String = Dispatcher.SCOPE_EVENT,
	effect_params: Dictionary = {},
) -> Dictionary:
	return {
		"event": event,
		"condition_id": "",
		"effect_id": effect_id,
		"limit": limit,
		"limit_scope": limit_scope,
		"limit_value": limit_value,
		"hook_index": 0,
		"condition_params": {},
		"effect_params": effect_params.duplicate(true),
	}
