extends RefCounted

const Contexts = preload("res://core/contexts.gd")
const Stats = preload("res://core/stats.gd")
const Damage = preload("res://core/damage.gd")
const Rng = preload("res://core/rng.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("team attack average counts alive units over six slots", func() -> void:
		_test_attack_average(harness)
	)
	harness.run_test("team max hp average includes dead units and optionally excludes puppets", func() -> void:
		_test_max_hp_average(harness)
	)
	harness.run_test("stats safely treat malformed state team and unit values as zero", func() -> void:
		_test_invalid_stats(harness)
	)
	harness.run_test("direct damage preserves multiplier crit raw block format and hp order", func() -> void:
		_test_direct_damage_order(harness)
	)
	harness.run_test("guaranteed crit skips crit RNG and delayed damage consumes no RNG", func() -> void:
		_test_rng_consumption(harness)
	)
	harness.run_test("crit and block rates clamp to zero through ninety five percent", func() -> void:
		_test_rate_clamp(harness)
	)
	harness.run_test("damage events record and death callbacks follow Web order", func() -> void:
		_test_event_order_and_death(harness)
	)
	harness.run_test("enemy thirty percent threshold triggers once and never on lethal damage", func() -> void:
		_test_threshold(harness)
	)
	harness.run_test("kill is idempotent and sacrifice death context is preserved", func() -> void:
		_test_kill_idempotence(harness)
	)
	harness.run_test("inactive targets return zero without callbacks or mutation", func() -> void:
		_test_inactive_target(harness)
	)
	harness.run_test("invalid config context callback outputs and target hp fail closed", func() -> void:
		_test_fail_closed(harness)
	)
	harness.run_test("context metadata result and callback payloads are deeply isolated", func() -> void:
		_test_payload_isolation(harness)
	)
	harness.run_test("fixed seeds reproduce damage event sequences through injected RNG", func() -> void:
		_test_fixed_seed_replay(harness)
	)


func _test_attack_average(harness: TestHarness) -> void:
	var state := {
		"allies": [
			{"alive": true, "atk": 60},
			{"alive": false, "atk": 600},
			{"alive": true, "atk": 30},
		],
		"enemies": [{"alive": true, "atk": 120}],
	}
	harness.assert_equal(Stats.team_average_atk(state, "ally"), 15.0)
	harness.assert_equal(Stats.team_average_atk(state, "enemy"), 20.0)
	harness.assert_equal(Stats.average_atk_for_team(state["allies"]), 15.0)
	harness.assert_equal(state["allies"][1]["atk"], 600, "stats must not mutate input")


func _test_max_hp_average(harness: TestHarness) -> void:
	var team := [
		{"alive": false, "max_hp": 300},
		{"alive": true, "max_hp": 180, "is_puppet": true},
		{"alive": true, "max_hp": 120},
	]
	var state := {"allies": team, "enemies": []}
	harness.assert_equal(Stats.team_average_max_hp(state, "ally"), 100.0)
	harness.assert_equal(Stats.team_average_max_hp(state, "ally", true), 70.0)
	harness.assert_equal(Stats.average_max_hp_for_team(team, true), 70.0)
	harness.assert_equal(team.size(), 3)


func _test_invalid_stats(harness: TestHarness) -> void:
	harness.assert_equal(Stats.team_average_atk(null, "enemy"), 0.0)
	harness.assert_equal(Stats.team_average_max_hp({"enemies": {}}, "enemy"), 0.0)
	var malformed := [
		null,
		"unit",
		{"alive": true, "atk": NAN, "max_hp": INF},
		{"alive": true, "atk": "12.5", "max_hp": "60"},
		{"alive": true, "atk": [], "max_hp": {}},
	]
	harness.assert_equal(Stats.average_atk_for_team(malformed), 12.5 / 6.0)
	harness.assert_equal(Stats.average_max_hp_for_team(malformed), 10.0)
	harness.assert_equal(
		Stats.team_average_atk({"allies": [{"alive": true, "atk": 6}]}, "unexpected"),
		1.0,
		"Web treats every non-enemy side as allies",
	)


func _test_direct_damage_order(harness: TestHarness) -> void:
	var rolls := [0.0, 0.0]
	var trace: Array[String] = []
	var events: Array = []
	var pipeline: Variant = _pipeline({
		"random": func() -> float:
			trace.append("random")
			return rolls.pop_front(),
		"format": func(value: float) -> float:
			trace.append("format:%s" % str(value))
			return roundf(value * 10.0) / 10.0,
		"get_block_rate": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			trace.append("block_rate")
			return 1.0,
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			trace.append("multiplier")
			return 1.0,
		"on_event": func(type: String, payload: Dictionary) -> void:
			events.append({"type": type, "payload": payload}),
	})
	var victim := _target()
	var result: Dictionary = pipeline.apply(victim, _damage_context(100, true, 1.0, true))
	harness.assert_equal(result["dealt"], 75.0)
	harness.assert_true(result["crit"])
	harness.assert_true(result["blocked"])
	harness.assert_equal(victim["hp"], 125.0)
	harness.assert_equal(events[0]["payload"]["raw_amount_before_block"], 150.0)
	harness.assert_equal(events[0]["payload"]["calculated_amount"], 75.0)
	harness.assert_equal(trace.slice(0, 4), ["multiplier", "random", "format:150.0", "random"])
	harness.assert_equal(trace[4], "block_rate")
	harness.assert_equal(rolls, [])


func _test_rng_consumption(harness: TestHarness) -> void:
	var guaranteed_rolls := [0.25]
	var guaranteed: Variant = _pipeline({
		"random": func() -> float: return guaranteed_rolls.pop_front(),
		"get_block_rate": func(_u: Dictionary, _c: Dictionary, _m: Dictionary) -> float: return 0.0,
	})
	var direct_target := _target()
	var direct_context := _damage_context(20, true, 0.0, true)
	direct_context = Contexts.create_damage_context({
		"target_id": 1,
		"raw_amount": 20,
		"effect": _effect(),
		"can_crit": true,
		"guaranteed_crit": true,
		"can_block": true,
	})
	var direct_result: Dictionary = guaranteed.apply(direct_target, direct_context)
	harness.assert_true(direct_result["crit"])
	harness.assert_false(direct_result["blocked"])
	harness.assert_equal(guaranteed_rolls, [], "only the block roll should be consumed")

	var delayed_roll_count := 0
	var block_rate_count := 0
	var delayed_pipeline: Variant = _pipeline({
		"random": func() -> float:
			delayed_roll_count += 1
			return 0.0,
		"get_block_rate": func(_u: Dictionary, _c: Dictionary, _m: Dictionary) -> float:
			block_rate_count += 1
			return 1.0,
	})
	var delayed_target := _target()
	var delayed_result: Dictionary = delayed_pipeline.apply(delayed_target, Contexts.create_damage_context({
		"target_id": 1,
		"raw_amount": 100,
		"category": Contexts.DAMAGE_CATEGORY["DELAYED"],
		"effect": _effect({"source_type": Contexts.EFFECT_SOURCE_TYPE["DELAYED_DAMAGE"]}),
		"can_crit": true,
		"guaranteed_crit": true,
		"can_block": true,
	}))
	harness.assert_equal(delayed_result["dealt"], 100.0)
	harness.assert_false(delayed_result["crit"])
	harness.assert_false(delayed_result["blocked"])
	harness.assert_equal(delayed_roll_count, 0)
	harness.assert_equal(block_rate_count, 0)


func _test_rate_clamp(harness: TestHarness) -> void:
	var rolls := [0.96, 0.94]
	var pipeline: Variant = _pipeline({
		"random": func() -> float: return rolls.pop_front(),
		"get_block_rate": func(_u: Dictionary, _c: Dictionary, _m: Dictionary) -> float: return 7.0,
	})
	var result: Dictionary = pipeline.apply(_target(), _damage_context(10, true, 99.0, true))
	harness.assert_false(result["crit"], "0.96 must miss a crit rate clamped to 0.95")
	harness.assert_true(result["blocked"], "0.94 must pass a block rate clamped to 0.95")
	var negative_rolls := [0.0, 0.0]
	var negative: Variant = _pipeline({
		"random": func() -> float: return negative_rolls.pop_front(),
		"get_block_rate": func(_u: Dictionary, _c: Dictionary, _m: Dictionary) -> float: return -1.0,
	})
	var negative_result: Dictionary = negative.apply(_target(), _damage_context(10, true, -2.0, true))
	harness.assert_false(negative_result["crit"])
	harness.assert_false(negative_result["blocked"])


func _test_event_order_and_death(harness: TestHarness) -> void:
	var order: Array[String] = []
	var death_contexts: Array = []
	var pipeline: Variant = _pipeline({
		"random": func() -> float: return 0.0,
		"get_block_rate": func(_u: Dictionary, _c: Dictionary, _m: Dictionary) -> float: return 1.0,
		"on_event": func(type: String, _payload: Dictionary) -> void: order.append(type),
		"record_damage": func(_payload: Dictionary) -> void: order.append("record"),
		"on_death": func(_unit: Dictionary, death: Dictionary, _payload: Dictionary) -> void:
			order.append("death_callback")
			death_contexts.append(death),
	})
	var victim := _target({"hp": 10, "max_hp": 10})
	var result: Dictionary = pipeline.apply(victim, _damage_context(50, false, 0.0, true))
	harness.assert_true(result["died"])
	harness.assert_equal(
		order,
		["damage_applied", "unit_damaged", "unit_blocked", "record", "unit_died", "death_callback"],
	)
	harness.assert_false(victim["alive"])
	harness.assert_equal(victim["hp"], 0.0)
	harness.assert_equal(result["death_context"]["source_kind"], Contexts.DEATH_SOURCE_KIND["ALLY"])
	harness.assert_equal(death_contexts[0]["effect"]["source_id"], "basic_attack")


func _test_threshold(harness: TestHarness) -> void:
	var threshold_events := [0]
	var pipeline: Variant = _pipeline({
		"on_event": func(type: String, _payload: Dictionary) -> void:
			if type == "hp_threshold_crossed":
				threshold_events[0] += 1,
	})
	var victim := _target({"hp": 40, "max_hp": 100})
	pipeline.apply(victim, _damage_context(15, false, 0.0, false))
	harness.assert_equal(victim["hp"], 25.0)
	harness.assert_true(victim["hp_threshold_crossed"])
	harness.assert_equal(threshold_events[0], 1)
	pipeline.apply(victim, _damage_context(1, false, 0.0, false))
	harness.assert_equal(threshold_events[0], 1)

	var lethal_events := [0]
	var lethal_pipeline: Variant = _pipeline({
		"on_event": func(type: String, _payload: Dictionary) -> void:
			if type == "hp_threshold_crossed":
				lethal_events[0] += 1,
	})
	var lethal := _target({"hp": 40, "max_hp": 100})
	lethal_pipeline.apply(lethal, _damage_context(50, false, 0.0, false))
	harness.assert_equal(lethal_events[0], 0)
	harness.assert_false(lethal.has("hp_threshold_crossed"))


func _test_kill_idempotence(harness: TestHarness) -> void:
	var events: Array[String] = []
	var deaths: Array = []
	var pipeline: Variant = _pipeline({
		"on_event": func(type: String, _payload: Dictionary) -> void: events.append(type),
		"on_death": func(unit: Dictionary, context: Dictionary, _payload: Dictionary) -> void:
			deaths.append({"unit": unit, "context": context}),
	})
	var victim := _target({"hp": 10, "max_hp": 10})
	var death := Contexts.create_sacrifice_death_context({
		"source_side": Contexts.UNIT_SIDE["ALLY"],
		"source_name": "献祭",
		"source_actor_id": 3,
	})
	harness.assert_true(pipeline.kill(victim, death))
	harness.assert_false(pipeline.kill(victim, death))
	harness.assert_equal(events, ["unit_died"])
	harness.assert_equal(deaths.size(), 1)
	harness.assert_equal(deaths[0]["context"]["source_kind"], Contexts.DEATH_SOURCE_KIND["SACRIFICE"])
	harness.assert_false(deaths[0]["context"]["triggers_enemy_kill_effects"])


func _test_inactive_target(harness: TestHarness) -> void:
	var callback_count := 0
	var pipeline: Variant = _pipeline({
		"random": func() -> float:
			callback_count += 1
			return 0.0,
		"get_damage_multiplier": func(_u: Dictionary, _c: Dictionary, _m: Dictionary) -> float:
			callback_count += 1
			return 1.0,
	})
	var dead := _target({"hp": 0, "alive": false})
	var result: Dictionary = pipeline.apply(dead, _damage_context(100, true, 1.0, true))
	harness.assert_equal(result["dealt"], 0.0)
	harness.assert_false(result["died"])
	harness.assert_equal(callback_count, 0)
	harness.assert_equal(dead, _target({"hp": 0, "alive": false}))


func _test_fail_closed(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var config := _pipeline_config()
	config["random"] = Callable()
	var invalid_config_pipeline: Variant = Damage.new(config, errors)
	harness.assert_false(invalid_config_pipeline.is_valid())
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("random")))
	var missing_config_pipeline: Variant = Damage.new({}, errors)
	harness.assert_false(missing_config_pipeline.is_valid())
	harness.assert_equal(errors.size(), Damage.REQUIRED_CALLBACKS.size())
	var untouched_by_invalid := _target()
	harness.assert_equal(invalid_config_pipeline.apply(untouched_by_invalid, _damage_context(), {}, errors), {})
	harness.assert_equal(untouched_by_invalid["hp"], 200)
	harness.assert_contains(errors[0], "config")

	var target := _target()
	var pipeline: Variant = _pipeline()
	harness.assert_equal(pipeline.apply(target, {"raw_amount": NAN}, {}, errors), {})
	harness.assert_equal(target["hp"], 200)
	harness.assert_true(not errors.is_empty())
	harness.assert_equal(pipeline.apply(target, _damage_context(), [], errors), {})
	harness.assert_equal(target["hp"], 200)

	var invalid_multiplier: Variant = _pipeline({
		"get_damage_multiplier": func(_u: Dictionary, _c: Dictionary, _m: Dictionary) -> float: return NAN,
	})
	harness.assert_equal(invalid_multiplier.apply(target, _damage_context(), {}, errors), {})
	harness.assert_equal(target["hp"], 200)
	harness.assert_contains(errors[0], "get_damage_multiplier")
	var invalid_format: Variant = _pipeline({
		"format": func(_value: float) -> Variant: return null,
	})
	harness.assert_equal(invalid_format.apply(target, _damage_context(), {}, errors), {})
	harness.assert_equal(target["hp"], 200)
	harness.assert_contains(errors[0], "format")
	var invalid_hp := _target({"hp": INF})
	harness.assert_equal(pipeline.apply(invalid_hp, _damage_context(), {}, errors), {})
	harness.assert_equal(invalid_hp["hp"], INF)
	harness.assert_contains(errors[0], "target.hp")


func _test_payload_isolation(harness: TestHarness) -> void:
	var event_payloads: Array = []
	var recorded: Array = []
	var pipeline: Variant = _pipeline({
		"on_event": func(_type: String, payload: Dictionary) -> void:
			event_payloads.append(payload)
			payload["damage_context"]["effect"]["source_id"] = "event-mutated"
			payload["metadata"]["nested"]["tags"].append("event"),
		"record_damage": func(payload: Dictionary) -> void: recorded.append(payload),
	})
	var context := _damage_context(10, false, 0.0, false)
	var metadata := {"nested": {"tags": ["original"]}}
	var victim := _target()
	var result: Dictionary = pipeline.apply(victim, context, metadata)
	metadata["nested"]["tags"].append("caller")
	context["effect"]["source_id"] = "caller-mutated"
	harness.assert_equal(result["damage_context"]["effect"]["source_id"], "basic_attack")
	harness.assert_equal(result["damage_context"]["effect"]["source_id"], recorded[0]["damage_context"]["effect"]["source_id"])
	harness.assert_equal(recorded[0]["metadata"]["nested"]["tags"], ["original"])
	harness.assert_equal(event_payloads[0]["target"], victim, "target remains the one explicit mutable reference")
	result["damage_context"]["effect"]["source_id"] = "result-mutated"
	harness.assert_equal(recorded[0]["damage_context"]["effect"]["source_id"], "basic_attack")


func _test_fixed_seed_replay(harness: TestHarness) -> void:
	var first := _run_seeded_damage("WEB-003")
	var replay := _run_seeded_damage("WEB-003")
	var other := _run_seeded_damage("WEB-003-other")
	harness.assert_equal(first, replay)
	harness.assert_true(first != other)
	harness.assert_equal(first["events"].size(), 8)
	harness.assert_true(first["hp"] >= 0.0)


func _run_seeded_damage(seed: String) -> Dictionary:
	var random: Variant = Rng.seeded(seed)
	var events: Array = []
	var pipeline: Variant = _pipeline({
		"random": Callable(random, "next"),
		"get_block_rate": func(_u: Dictionary, _c: Dictionary, _m: Dictionary) -> float: return 0.35,
		"on_event": func(type: String, payload: Dictionary) -> void:
			if type == "damage_applied":
				events.append({
					"amount": payload["amount"],
					"crit": payload["crit"],
					"blocked": payload["blocked"],
				}),
	})
	var victim := _target({"hp": 500, "max_hp": 500})
	for _index in range(8):
		pipeline.apply(victim, _damage_context(40, true, 0.45, true))
	return {"hp": victim["hp"], "events": events}


func _pipeline(overrides: Dictionary = {}) -> Variant:
	var config := _pipeline_config()
	config.merge(overrides, true)
	var errors: Array[String] = []
	var pipeline: Variant = Damage.new(config, errors)
	assert(errors.is_empty())
	assert(pipeline.is_valid())
	return pipeline


func _pipeline_config() -> Dictionary:
	return {
		"random": func() -> float: return 0.5,
		"format": func(value: float) -> float: return value,
		"get_block_rate": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 0.0,
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float: return 1.0,
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void: pass,
		"record_damage": func(_payload: Dictionary) -> void: pass,
	}


func _target(overrides: Dictionary = {}) -> Dictionary:
	var unit := {
		"id": 1,
		"side": "enemy",
		"hp": 200,
		"max_hp": 200,
		"alive": true,
	}
	unit.merge(overrides, true)
	return unit


func _effect(overrides: Dictionary = {}) -> Dictionary:
	var input := {
		"source_type": Contexts.EFFECT_SOURCE_TYPE["BASIC_ATTACK"],
		"source_id": "basic_attack",
		"source_name": "普攻",
		"source_side": Contexts.UNIT_SIDE["ALLY"],
		"source_actor_id": 9,
		"counts_as_attack": true,
		"counts_as_basic_attack": true,
	}
	input.merge(overrides, true)
	return Contexts.create_effect_context(input)


func _damage_context(
	amount: float = 10.0,
	can_crit: bool = false,
	crit_rate: float = 0.0,
	can_block: bool = false,
) -> Dictionary:
	return Contexts.create_damage_context({
		"target_id": 1,
		"raw_amount": amount,
		"effect": _effect(),
		"can_crit": can_crit,
		"crit_rate": crit_rate,
		"can_block": can_block,
	})
