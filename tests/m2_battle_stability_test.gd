extends RefCounted

const BattleRuntimeScript = preload("res://systems/combat/battle_runtime.gd")
const BattleStateScript = preload("res://core/battle_state.gd")
const DeterministicRngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")

const REQUESTED_BATTLES := 1000
const MAX_ROUNDS := 2
const ROOT_SEED := "M2-BATTLE-STABILITY-2026-09-02-v1"
const BATTLE_SEED_NAME := "battle/%04d"
const COMBAT_STREAM_NAME := "combat"
const POLICY_STREAM_NAME := "enemyPolicy"
const RNG_DRAW_SEARCH_LIMIT := 10000
const REPLAY_INDICES := [0, 499, 999]
const ACTION_MODEL := "player_input -> real BattleRuntime.resolve_round; ally actions are only RoundResolver PieceAttack phases; no M3 cards/payment/quota/pending ultimate"


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("1000 exact-seed M2 battles settle without invalid numeric or terminal state", func() -> void:
		_test_stability_gate(harness)
	)
	print("B4-4B M2 BATTLE STABILITY TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_stability_gate(harness: TestHarness) -> void:
	var catalog_errors: Array[String] = []
	var catalogs: Dictionary = ContentCatalogScript.build(catalog_errors)
	harness.assert_equal(catalog_errors, [])
	if not catalog_errors.is_empty():
		return
	var summary := {
		"requested": REQUESTED_BATTLES,
		"completed": 0,
		"settled": 0,
		"errors": 0,
		"timeouts": 0,
		"non_finite": 0,
		"negative_hp": 0,
		"wins": 0,
		"losses": 0,
		"total_rounds": 0,
		"max_rounds": 0,
		"combat_rng_draws": 0,
		"policy_rng_draws": 0,
		"burn_settlements": 0,
		"relic_owned_queries": 0,
		"relic_heals": 0,
		"hook_errors": 0,
		"digest": 2166136261,
	}
	var replay_fingerprints := {}
	var started_ms := Time.get_ticks_msec()
	for battle_index in REQUESTED_BATTLES:
		var result := _simulate_battle(battle_index, catalogs)
		if not result["ok"]:
			var category: String = result["category"]
			if summary.has(category):
				summary[category] += 1
			else:
				summary["errors"] += 1
			harness.fail(
				"M2 stability failed seed_index=%d battle_seed=%s round=%s category=%s detail=%s"
				% [
					battle_index, str(result["battle_seed"]), str(result["round"]),
					category, result["error"],
				]
			)
			break
		summary["completed"] += 1
		summary["settled"] += 1
		summary["wins" if result["outcome"] == "win" else "losses"] += 1
		summary["total_rounds"] += result["rounds"]
		summary["max_rounds"] = maxi(summary["max_rounds"], result["rounds"])
		summary["combat_rng_draws"] += result["combat_rng_draws"]
		summary["policy_rng_draws"] += result["policy_rng_draws"]
		summary["burn_settlements"] += result["burn_settlements"]
		summary["relic_owned_queries"] += result["relic_owned_queries"]
		summary["relic_heals"] += result["relic_heals"]
		summary["hook_errors"] += result["hook_errors"]
		summary["digest"] = DeterministicRngScript.hash_utf16_fnv1a(
			"%d|%s" % [summary["digest"], result["fingerprint"]]
		)
		if battle_index in REPLAY_INDICES:
			replay_fingerprints[battle_index] = result["fingerprint"]
		if summary["completed"] % 100 == 0:
			print("M2 STABILITY PROGRESS completed=%d requested=%d wallMs=%d" % [
				summary["completed"], REQUESTED_BATTLES,
				Time.get_ticks_msec() - started_ms,
			])

	var replayed := 0
	if summary["completed"] == REQUESTED_BATTLES:
		for battle_index in REPLAY_INDICES:
			var replay := _simulate_battle(battle_index, catalogs)
			harness.assert_true(replay["ok"], "representative replay failed index=%d: %s" % [battle_index, replay.get("error", "")])
			if not replay["ok"]:
				continue
			harness.assert_equal(
				replay["fingerprint"], replay_fingerprints[battle_index],
				"representative seed replay diverged at index=%d" % battle_index,
			)
			replayed += 1
	var elapsed_ms := Time.get_ticks_msec() - started_ms

	harness.assert_equal(summary["requested"], 1000)
	harness.assert_equal(summary["completed"], summary["requested"])
	harness.assert_equal(summary["settled"], summary["requested"])
	harness.assert_equal(summary["errors"], 0)
	harness.assert_equal(summary["timeouts"], 0)
	harness.assert_equal(summary["non_finite"], 0)
	harness.assert_equal(summary["negative_hp"], 0)
	harness.assert_equal(summary["wins"] + summary["losses"], summary["requested"])
	harness.assert_true(summary["max_rounds"] <= MAX_ROUNDS)
	harness.assert_true(summary["total_rounds"] >= summary["settled"])
	harness.assert_true(summary["combat_rng_draws"] > 0, "combat RNG must be consumed by real combat")
	harness.assert_true(summary["policy_rng_draws"] > 0, "enemyPolicy RNG must be consumed by real enemy choices")
	harness.assert_true(summary["burn_settlements"] > 0, "real BurnSettlement must execute")
	harness.assert_true(summary["relic_owned_queries"] > 0, "real RelicSystem policy must query ownership")
	harness.assert_true(summary["relic_heals"] > 0, "real relic heal action must execute")
	harness.assert_equal(summary["hook_errors"], 0)
	harness.assert_equal(replayed, REPLAY_INDICES.size())
	print(
		"M2 STABILITY SUMMARY root_seed=%s seed_formula=derive_seed(ROOT_SEED,'%s'%%index)->derive_seed(battle_seed,'%s'/'%s') action_model=%s requested=%d completed=%d settled=%d errors=%d timeouts=%d nonFinite=%d negativeHp=%d win=%d loss=%d totalRounds=%d maxRounds=%d maxRoundsLimit=%d combatRngDraws=%d enemyPolicyRngDraws=%d burnSettlements=%d relicQueries=%d relicHeals=%d hookErrors=%d replayed=%d digest=%d wallMs=%d"
		% [
			ROOT_SEED, BATTLE_SEED_NAME, COMBAT_STREAM_NAME, POLICY_STREAM_NAME,
			ACTION_MODEL, summary["requested"], summary["completed"], summary["settled"],
			summary["errors"], summary["timeouts"], summary["non_finite"],
			summary["negative_hp"], summary["wins"], summary["losses"],
			summary["total_rounds"], summary["max_rounds"], MAX_ROUNDS,
			summary["combat_rng_draws"], summary["policy_rng_draws"],
			summary["burn_settlements"], summary["relic_owned_queries"],
			summary["relic_heals"], summary["hook_errors"], replayed,
			summary["digest"], elapsed_ms,
		]
	)


func _simulate_battle(battle_index: int, catalogs: Dictionary) -> Dictionary:
	var battle_seed: Variant = DeterministicRngScript.derive_seed(
		ROOT_SEED, BATTLE_SEED_NAME % battle_index
	)
	var combat_seed: Variant = DeterministicRngScript.derive_seed(battle_seed, COMBAT_STREAM_NAME)
	var policy_seed: Variant = DeterministicRngScript.derive_seed(battle_seed, POLICY_STREAM_NAME)
	var combat_rng := DeterministicRngScript.new(combat_seed)
	var policy_rng := DeterministicRngScript.new(policy_seed)
	var built := _build_runtime(catalogs, combat_rng, policy_rng)
	if not built["ok"]:
		return _failure(battle_seed, 0, "errors", built["error"])
	var runtime: Variant = built["runtime"]
	var state: Dictionary = built["state"]
	var rounds := 0
	while not state["game_over"] and rounds < MAX_ROUNDS:
		if not runtime.is_valid():
			return _failure(battle_seed, state["round"], "errors", "runtime became invalid")
		if state["phase"] != "player_input":
			return _failure(battle_seed, state["round"], "errors", "round entry phase is %s" % state["phase"])
		if state["round"] != rounds + 1:
			return _failure(
				battle_seed, state["round"], "errors",
				"round counter diverged expected=%d actual=%d" % [rounds + 1, state["round"]],
			)
		var result: Dictionary = runtime.resolve_round()
		rounds += 1
		if not result["ok"]:
			return _failure(battle_seed, state["round"], "errors", result["error"])
		if built["metrics"]["hook_errors"] > 0:
			return _failure(
				battle_seed, state["round"], "errors",
				"HookDispatcher reported %d callback error(s)" % built["metrics"]["hook_errors"],
			)
		var value: Dictionary = result["value"]
		if value["status"] not in ["completed", "settled"]:
			return _failure(
				battle_seed, state["round"], "errors",
				"unexpected round status: %s" % str(value["status"]),
			)
		var invariant := _validate_live_state(state)
		if not invariant["ok"]:
			return _failure(
				battle_seed, state["round"], invariant["category"], invariant["error"]
			)
	if not state["game_over"]:
		return _failure(
			battle_seed, state["round"], "timeouts",
			"battle did not settle within maxRounds=%d" % MAX_ROUNDS,
		)
	if state["phase"] != "settled" or state["battle_result"] not in ["win", "lose"]:
		return _failure(
			battle_seed, state["round"], "errors",
			"terminal state is inconsistent phase=%s result=%s" % [state["phase"], str(state["battle_result"])],
		)
	var combat_draws := _draw_count(combat_seed, combat_rng)
	var policy_draws := _draw_count(policy_seed, policy_rng)
	if combat_draws < 0 or policy_draws < 0:
		return _failure(
			battle_seed, state["round"], "errors",
			"RNG draw probe exceeded search limit combat=%d policy=%d" % [combat_draws, policy_draws],
		)
	var fingerprint := "%s|%d|%s|%s|%d|%d" % [
		state["battle_result"], rounds,
		_hp_fingerprint(state["allies"]), _hp_fingerprint(state["enemies"]),
		combat_draws, policy_draws,
	]
	return {
		"ok": true,
		"battle_seed": battle_seed,
		"outcome": state["battle_result"],
		"rounds": rounds,
		"combat_rng_draws": combat_draws,
		"policy_rng_draws": policy_draws,
		"burn_settlements": built["metrics"]["burn_settlements"],
		"relic_owned_queries": built["metrics"]["relic_owned_queries"],
		"relic_heals": built["metrics"]["relic_heals"],
		"hook_errors": built["metrics"]["hook_errors"],
		"fingerprint": fingerprint,
	}


func _build_runtime(catalogs: Dictionary, combat_rng: Variant, policy_rng: Variant) -> Dictionary:
	var state := _state()
	var run_state := {"permanent_buffs": []}
	var metrics := {
		"burn_settlements": 0,
		"relic_owned_queries": 0,
		"relic_heals": 0,
		"deaths": 0,
		"hook_errors": 0,
	}
	var actions := {
		"emit_combat_event": func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.ok(null),
		"emit_content_event": func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.ok(null),
		"log": func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.ok(null),
		"on_battle_resolved": func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.ok(null),
		"record_damage": func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.ok(null),
		"record_heal": func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.ok(null),
		"resolve_battle_end": func(_request: Dictionary) -> Dictionary:
			return CombatPortsScript.ok(true),
	}
	var config := {
		"state": state,
		"run_state": run_state,
		"catalogs": catalogs,
		"tuning": catalogs["tuning"],
		"combat_rng": combat_rng,
		"enemy_policy_rng": policy_rng,
		"actions": actions,
		"relic_actions": {
			"heal": func(target: Dictionary, amount: float, _source_id: String, _source_name: String) -> Dictionary:
				metrics["relic_heals"] += 1
				target["hp"] = minf(float(target["max_hp"]), float(target["hp"]) + amount)
				return CombatPortsScript.ok(null),
		},
		"get_owned_relic_ids": func() -> Array:
			metrics["relic_owned_queries"] += 1
			return ["fieldBandage"],
		"format_damage": func(value: float) -> float:
			return maxf(0.0, roundf(value * 10.0) / 10.0),
		"get_block_rate": func(unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return float(unit["base_block_rate"]),
		"get_damage_multiplier": func(_unit: Dictionary, _context: Dictionary, _metadata: Dictionary) -> float:
			return 1.0,
		"on_damage_event": func(_event_id: String, _payload: Dictionary) -> void:
			pass,
		"on_death": func(_unit: Dictionary, _context: Dictionary, _payload: Dictionary) -> void:
			metrics["deaths"] += 1,
		"on_buff_event": func(_event_id: String, _payload: Dictionary) -> void:
			pass,
		"on_burn_settled": func(_result: Dictionary) -> void:
			metrics["burn_settlements"] += 1,
		"on_hook_error": func(_message: String, _metadata: Dictionary) -> void:
			metrics["hook_errors"] += 1,
	}
	var errors: Array[String] = []
	var runtime := BattleRuntimeScript.new(config, errors)
	if not errors.is_empty() or not runtime.is_valid():
		return {
			"ok": false,
			"error": errors[0] if not errors.is_empty() else "BattleRuntime is invalid",
		}
	return {
		"ok": true,
		"runtime": runtime,
		"state": state,
		"run_state": run_state,
		"metrics": metrics,
	}


func _state() -> Dictionary:
	var source := {
		"round": 1,
		"phase": "player_input",
		"sp": 4.0,
		"sp_max": 6.0,
		"base_sp_max": 6.0,
		"enemy_sp": 6.0,
		"enemy_sp_max": 6.0,
		"allies": _team("ally"),
		"enemies": _team("enemy"),
		"player_heroes": [_player_hero()],
		"enemy_heroes": [_enemy_hero()],
		"side_buffs": {"ally": [], "enemy": []},
		"fate": {
			"active": false, "mode": null, "cast_used": false, "chaos_used": false,
			"enemy_lock": null, "all_in_turns": 0, "roll_index": 0,
			"skill_sp_gain_this_round": 0,
		},
		"enemy_fate": {
			"active": false, "mode": null, "cast_used": false, "chaos_used": false,
			"ally_lock": null, "all_in_turns": 0, "skill_sp_gain_this_round": 0,
		},
		"battle_growth_flags": {"flame_investment_used": false},
		"burn_ex_cast_count": 0,
		"enemy_burn_ex_cast_count": 0,
		"counter_threshold": 4,
		"marshal_target_id": 1,
		"ally_puppet_martyr_active": false,
		"game_over": false,
		"battle_result": null,
	}
	var errors: Array[String] = []
	var state: Dictionary = BattleStateScript.create(source, errors)
	assert(errors.is_empty(), str(errors))
	return state


func _team(side: String) -> Array:
	var result: Array = []
	for slot in range(1, 7):
		result.append({
			"id": slot,
			"slot": slot,
			"side": side,
			"class_id": "default",
			"class_name": "棋子",
			"hp": 100.0 + float((slot % 3) * 10),
			"max_hp": 100.0 + float((slot % 3) * 10),
			"atk": 180.0 + float(slot * 10),
			"crit_rate": 0.08 + float(slot % 2) * 0.04,
			"alive": true,
			"general": slot == 1,
			"base_block_rate": 0.04 + float(slot % 3) * 0.02,
			"extra_action_charges": 0,
			"buffs": [],
			"is_puppet": false,
			"fixed_max_hp": null,
			"puppet_martyr": false,
			"disarm_turns": 0,
			"stealth_attack_ready": false,
			"special_id": null,
			"echo_damage_bonus": 0.0,
			"hp_threshold_crossed": false,
		})
	return result


func _player_hero() -> Dictionary:
	return {
		"id": 2,
		"name": "假想玩家弈者",
		"deployed": true,
		"ex_skill": "fate",
		"energy": 0.0,
		"max_energy": 100.0,
		"base_crit_rate": 0.05,
		"fist_momentum": 0,
	}


func _enemy_hero() -> Dictionary:
	return {
		"id": 101,
		"name": "稳定性敌弈者",
		"ex_skill": "counterAura",
		"skills": [],
		"skill_pool": ["basicDamage", "burnStackBase", "pieceDamageUp", "markBurn"],
		"energy": 0.0,
		"max_energy": 100.0,
		"base_crit_rate": 0.05,
		"fist_momentum": 0,
	}


func _validate_live_state(state: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if not BattleStateScript.validate(state, errors):
		return {"ok": false, "category": "errors", "error": errors[0]}
	var non_finite_path := _first_non_finite(state, "state")
	if not non_finite_path.is_empty():
		return {
			"ok": false,
			"category": "non_finite",
			"error": "non-finite numeric value at %s" % non_finite_path,
		}
	for unit: Dictionary in state["allies"] + state["enemies"]:
		var hp := float(unit["hp"])
		var max_hp := float(unit["max_hp"])
		if hp < 0.0:
			return {
				"ok": false,
				"category": "negative_hp",
				"error": "unit %s hp=%s" % [str(unit["id"]), str(hp)],
			}
		if hp > max_hp:
			return {
				"ok": false,
				"category": "errors",
				"error": "unit %s hp exceeds max_hp" % str(unit["id"]),
			}
		if bool(unit["alive"]) != (hp > 0.0):
			return {
				"ok": false,
				"category": "errors",
				"error": "unit %s alive/hp mismatch" % str(unit["id"]),
			}
	for hero: Dictionary in state["player_heroes"] + state["enemy_heroes"]:
		if float(hero["energy"]) < 0.0 or float(hero["energy"]) > float(hero["max_energy"]):
			return {
				"ok": false,
				"category": "errors",
				"error": "hero %s energy out of range" % str(hero["id"]),
			}
	for field in ["sp", "enemy_sp"]:
		var maximum_field := "sp_max" if field == "sp" else "enemy_sp_max"
		if float(state[field]) < 0.0 or float(state[field]) > float(state[maximum_field]):
			return {"ok": false, "category": "errors", "error": "%s out of range" % field}
	for fate: Dictionary in [state["fate"], state["enemy_fate"]]:
		for field in ["all_in_turns", "skill_sp_gain_this_round"]:
			if typeof(fate[field]) != TYPE_INT or fate[field] < 0:
				return {"ok": false, "category": "errors", "error": "Fate %s invalid" % field}
	return {"ok": true}


func _first_non_finite(value: Variant, path: String) -> String:
	if typeof(value) == TYPE_FLOAT:
		return "" if is_finite(value) else path
	if typeof(value) == TYPE_ARRAY:
		for index in value.size():
			var found := _first_non_finite(value[index], "%s[%d]" % [path, index])
			if not found.is_empty():
				return found
	if typeof(value) == TYPE_DICTIONARY:
		for key: Variant in value:
			var found := _first_non_finite(value[key], "%s.%s" % [path, str(key)])
			if not found.is_empty():
				return found
	return ""


func _draw_count(seed: Variant, consumed: Variant) -> int:
	# Runtime requires the exact DeterministicRng script, so consumption is measured
	# without a duck wrapper: probe its next value after settlement and align an
	# untouched exact control stream from the same derived seed.
	var probe: float = consumed.next()
	var control := DeterministicRngScript.new(seed)
	for draw_count in RNG_DRAW_SEARCH_LIMIT:
		if control.next() == probe:
			return draw_count
	return -1


func _hp_fingerprint(team: Array) -> String:
	var values: Array[String] = []
	for unit: Dictionary in team:
		values.append("%.1f" % float(unit["hp"]))
	return ",".join(values)


func _failure(seed: Variant, round_value: int, category: String, detail: String) -> Dictionary:
	return {
		"ok": false,
		"battle_seed": seed,
		"round": round_value,
		"category": category,
		"error": detail,
	}
