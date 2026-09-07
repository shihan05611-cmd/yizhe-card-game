extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const HookDispatcherScript = preload("res://systems/relics/hook_dispatcher.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")
const FreeEffectsScript = preload("res://systems/effects/free_skill_effects.gd")
const FlameEffectsScript = preload("res://systems/effects/hero_effects_flame_fate.gd")
const MarshalEffectsScript = preload("res://systems/effects/hero_effects_marshal_fist.gd")
const SiegeEffectsScript = preload("res://systems/effects/hero_effects_siege_puppet_shadow.gd")
const PolicyScript = preload("res://systems/enemy_ai/enemy_skill_policy.gd")
const AdapterScript = preload("res://systems/enemy_ai/enemy_skill_adapter.gd")


class FixedRng:
	extends RefCounted
	var values: Array[int] = []
	var cursor := 0

	func _init(initial: Array[int] = []) -> void:
		values = initial.duplicate()

	func next() -> float:
		cursor += 1
		return 0.0

	func int_range(minimum: int, maximum: int) -> int:
		var raw := values[cursor % values.size()] if not values.is_empty() else 0
		cursor += 1
		return minimum + posmod(raw, maximum - minimum + 1)

	func pick(items: Array) -> Variant:
		return null if items.is_empty() else items[int_range(0, items.size() - 1)]


class DamageStub:
	extends RefCounted
	func is_valid() -> bool: return true
	func apply(target: Variant, context: Variant, _metadata: Variant = {}, errors: Array[String] = []) -> Dictionary:
		errors.clear()
		var dealt := minf(float(target["hp"]), float(context["raw_amount"]))
		target["hp"] = float(target["hp"]) - dealt
		if float(target["hp"]) <= 0.0:
			target["hp"] = 0.0
			target["alive"] = false
		return {"dealt": dealt, "blocked": false, "died": not target["alive"], "crit": false, "damage_context": context, "death_context": null}
	func kill(target: Variant, _context: Variant = {}, errors: Array[String] = []) -> Dictionary:
		errors.clear()
		target["hp"] = 0.0
		target["alive"] = false
		return {"died": true}


class FakeRelicCostService:
	extends RefCounted
	func is_valid() -> bool: return true
	func get_effective_skill_point_cost(base: Variant, _side: String, _round: Variant, _kind: String = "freeSkill") -> int:
		return int(base)


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("enemy pool falls back deduplicates filters unknown unusable and uses effective cost", func() -> void:
		_test_pool_and_cost(harness)
	)
	harness.run_test("duck-typed relic cost service fails closed before policy or combat side effects", func() -> void:
		_test_relic_identity_guard(harness)
	)
	harness.run_test("fist and burnEnchant force exclusive while other choices use policy RNG only", func() -> void:
		_test_priority_and_rng(harness)
	)
	harness.run_test("all enemy exclusive costs match Web and passive exclusives remain unavailable", func() -> void:
		_test_exclusive_costs(harness)
	)
	harness.run_test("every selectable exclusive pays its exact authored enemy cost", func() -> void:
		_test_exclusive_payments(harness)
	)
	harness.run_test("Fate locks no-choice recovery and skill Fate cap match both field authorities", func() -> void:
		_test_fate_and_skip(harness)
	)
	harness.run_test("free and exclusive casts pay then effect event legacy energy and clamp", func() -> void:
		_test_skill_commit_order(harness)
	)
	harness.run_test("enemy hero phase preserves pre skill post ultimate order and one ultimate maximum", func() -> void:
		_test_ultimate_order(harness)
	)
	harness.run_test("game over and both no-skill locks prevent handlers events and policy RNG", func() -> void:
		_test_guards(harness)
	)
	harness.run_test("handler and content event failures report already committed payment and effect", func() -> void:
		_test_failures(harness)
	)
	harness.run_test("real B3 free and hero handlers integrate without copied effects", func() -> void:
		_test_real_registry(harness)
	)
	print("B3-6 ENEMY SKILL ADAPTER TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_pool_and_cost(harness: TestHarness) -> void:
	var case := _case("counterAura", [])
	var kit := _kit(case["state"], [0])
	var registry: Variant = _spy_registry(kit["metrics"])
	var errors: Array[String] = []
	var plan := PolicyScript.build_plan(case["state"], case["hero"], registry, kit["ports"], errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(plan["pool"], PolicyScript.DEFAULT_FREE_SKILL_IDS)
	harness.assert_true(plan["eligible_choices"].size() >= 4)
	harness.assert_equal(kit["policy_rng"].cursor, 1)
	harness.assert_equal(kit["combat_rng"].cursor, 0)

	harness.assert_equal(
		PolicyScript.normalized_pool(["pieceBlock", "pieceBlock", "missing", "smallHeal"]),
		["pieceBlock", "missing", "smallHeal"],
	)
	case = _case("counterAura", ["pieceBlock", "missing", "smallHeal"])
	kit = _kit(case["state"], [0])
	registry = _spy_registry(kit["metrics"])
	plan = PolicyScript.build_plan(case["state"], case["hero"], registry, kit["ports"], errors)
	harness.assert_equal(plan["pool"], ["pieceBlock", "missing", "smallHeal"])
	harness.assert_equal(plan["eligible_choices"].size(), 1)
	harness.assert_equal(plan["skill_id"], "pieceBlock")
	harness.assert_equal(plan["actual_sp_cost"], 1)
	case["state"]["enemy_sp"] = 0.0
	plan = PolicyScript.build_plan(case["state"], case["hero"], registry, kit["ports"], errors)
	harness.assert_equal(plan["kind"], "skip")
	harness.assert_equal(plan["reason"], "no_choice")


func _test_relic_identity_guard(harness: TestHarness) -> void:
	var case := _case("counterAura", ["pieceBlock"])
	var before := BattleStateScript.snapshot(case["state"])
	var kit := _kit(case["state"], [0], false, FakeRelicCostService.new())
	var registry: Variant = _spy_registry(kit["metrics"])
	var errors: Array[String] = []
	var plan := PolicyScript.build_plan(case["state"], case["hero"], registry, kit["ports"], errors)
	harness.assert_equal(plan, {})
	harness.assert_equal(errors, ["enemy policy requires a valid exact B2 RelicSystem"])
	harness.assert_equal(BattleStateScript.snapshot(case["state"]), before)
	harness.assert_equal(kit["policy_rng"].cursor, 0)
	harness.assert_equal(kit["combat_rng"].cursor, 0)
	harness.assert_equal(kit["metrics"]["effect_calls"], [])
	harness.assert_equal(kit["metrics"]["events"], [])


func _test_priority_and_rng(harness: TestHarness) -> void:
	var fist_case := _case("fist", ["pieceBlock"])
	var fist_kit := _kit(fist_case["state"], [99])
	var registry: Variant = _spy_registry(fist_kit["metrics"])
	var errors: Array[String] = []
	var plan := PolicyScript.build_plan(fist_case["state"], fist_case["hero"], registry, fist_kit["ports"], errors)
	harness.assert_equal(plan["action"], "exclusive")
	harness.assert_equal(plan["weighted_choices"].filter(func(choice: Dictionary) -> bool: return choice["kind"] == "exclusive").size(), 3)
	harness.assert_equal(fist_kit["policy_rng"].cursor, 0)
	harness.assert_equal(fist_kit["combat_rng"].cursor, 0)

	var enchant_case := _case("burnEnchant", ["pieceBlock"])
	var enchant_kit := _kit(enchant_case["state"], [99])
	registry = _spy_registry(enchant_kit["metrics"])
	plan = PolicyScript.build_plan(enchant_case["state"], enchant_case["hero"], registry, enchant_kit["ports"], errors)
	harness.assert_equal(plan["action"], "exclusive")
	harness.assert_equal(enchant_kit["policy_rng"].cursor, 0)

	var siege_case := _case("siege", ["pieceBlock", "pieceDamageUp"])
	var siege_kit := _kit(siege_case["state"], [1])
	registry = _spy_registry(siege_kit["metrics"])
	plan = PolicyScript.build_plan(siege_case["state"], siege_case["hero"], registry, siege_kit["ports"], errors)
	harness.assert_equal(plan["action"], "free")
	harness.assert_equal(plan["skill_id"], "pieceDamageUp")
	harness.assert_equal(siege_kit["policy_rng"].cursor, 1)
	harness.assert_equal(siege_kit["combat_rng"].cursor, 0)


func _test_exclusive_costs(harness: TestHarness) -> void:
	var expected := {"fate": 1, "burnEnchant": 2, "puppet": 1, "ascend": 2, "fist": 1, "siege": 1}
	for skill_id: String in expected:
		var case := _case(skill_id, [])
		var kit := _kit(case["state"])
		var errors: Array[String] = []
		harness.assert_equal(PolicyScript.exclusive_cost(case["state"], case["hero"], kit["ports"], errors), expected[skill_id])
		harness.assert_equal(errors, [])
	var burn_case := _case("burn01", [])
	var burn_kit := _kit(burn_case["state"])
	for index in 4:
		burn_case["state"]["enemy_burn_ex_cast_count"] = index
		harness.assert_equal(PolicyScript.exclusive_cost(burn_case["state"], burn_case["hero"], burn_kit["ports"]), [1, 2, 4, 8][index])
	for passive in ["counterAura", "shadow"]:
		var passive_case := _case(passive, [])
		var passive_kit := _kit(passive_case["state"])
		var registry: Variant = _spy_registry(passive_kit["metrics"])
		var plan := PolicyScript.build_plan(passive_case["state"], passive_case["hero"], registry, passive_kit["ports"])
		harness.assert_false(plan["eligible_choices"].any(func(choice: Dictionary) -> bool: return choice["kind"] == "exclusive"))


func _test_exclusive_payments(harness: TestHarness) -> void:
	var expected := {"burn01": 8, "fate": 1, "burnEnchant": 2, "puppet": 1, "ascend": 2, "fist": 1, "siege": 1}
	for skill_id: String in expected:
		var case := _case(skill_id, [])
		case["state"]["enemy_sp"] = 8.0
		case["state"]["enemy_sp_max"] = 8.0
		if skill_id == "burn01":
			case["state"]["enemy_burn_ex_cast_count"] = 3
		if skill_id == "puppet":
			_kill(case["state"]["enemies"][5])
		var kit := _kit(case["state"], [0])
		if skill_id == "burn01":
			var buff_errors: Array[String] = []
			harness.assert_true(kit["buffs"].apply_unit(case["state"]["allies"][0], "burn", 1, null, buff_errors))
			harness.assert_equal(buff_errors, [])
		var result := AdapterScript.cast_enemy_exclusive(
			case["state"], case["hero"], _spy_registry(kit["metrics"]), kit["ports"],
		)
		harness.assert_true(result["ok"], "%s: %s" % [skill_id, str(result)])
		harness.assert_equal(case["state"]["enemy_sp"], 8.0 - float(expected[skill_id]))
		harness.assert_equal(kit["metrics"]["events"][0]["payload"]["amount"], expected[skill_id])


func _test_fate_and_skip(harness: TestHarness) -> void:
	for lock_kind in ["player", "piece"]:
		var case := _case("counterAura", ["pieceBlock"])
		if lock_kind == "player":
			case["state"]["fate"]["enemy_lock"] = "noSkill"
		else:
			case["state"]["enemy_fate"]["active"] = true
			case["state"]["enemy_fate"]["mode"] = "棋子命运"
		var kit := _kit(case["state"])
		var result := AdapterScript.cast_enemy_random_skill(case["state"], case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
		harness.assert_true(result["ok"])
		harness.assert_equal(result["value"]["status"], "skipped")
		harness.assert_equal(case["state"]["enemy_sp"], 5.0)

	var no_choice := _case("counterAura", ["missing"])
	no_choice["state"]["enemy_fate"]["active"] = true
	no_choice["state"]["enemy_fate"]["mode"] = "技能命运"
	var kit := _kit(no_choice["state"])
	var result := AdapterScript.cast_enemy_random_skill(no_choice["state"], no_choice["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(result["value"]["reason"], "enemy_skill_fate_no_choice")
	harness.assert_equal(no_choice["state"]["enemy_sp"], 4.0)
	var ordinary_no_choice := _case("counterAura", ["missing"])
	kit = _kit(ordinary_no_choice["state"])
	result = AdapterScript.cast_enemy_random_skill(ordinary_no_choice["state"], ordinary_no_choice["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(ordinary_no_choice["state"]["enemy_sp"], 5.0)

	var fate_case := _case("counterAura", ["pieceBlock"])
	fate_case["state"]["enemy_fate"]["active"] = true
	fate_case["state"]["enemy_fate"]["mode"] = "技能命运"
	fate_case["state"]["enemy_fate"]["skill_sp_gain_this_round"] = 2
	kit = _kit(fate_case["state"], [0])
	var registry: Variant = _spy_registry(kit["metrics"])
	result = AdapterScript.cast_enemy_random_skill(fate_case["state"], fate_case["hero"], registry, kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(fate_case["state"]["enemy_fate"]["skill_sp_gain_this_round"], 3)
	harness.assert_equal(fate_case["state"]["enemy_sp"], 4.0)
	result = AdapterScript.cast_enemy_random_skill(fate_case["state"], fate_case["hero"], registry, kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(fate_case["state"]["enemy_fate"]["skill_sp_gain_this_round"], 3)
	harness.assert_equal(fate_case["state"]["enemy_sp"], 3.0)

	var all_in_case := _case("counterAura", ["pieceBlock"])
	all_in_case["state"]["enemy_fate"]["active"] = true
	all_in_case["state"]["enemy_fate"]["mode"] = "棋子命运"
	all_in_case["state"]["enemy_fate"]["all_in_turns"] = 1
	kit = _kit(all_in_case["state"], [0])
	result = AdapterScript.cast_enemy_random_skill(all_in_case["state"], all_in_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_equal(all_in_case["state"]["enemy_sp"], 4.0)
	harness.assert_equal(all_in_case["state"]["enemy_fate"]["skill_sp_gain_this_round"], 1)


func _test_skill_commit_order(harness: TestHarness) -> void:
	var free_case := _case("counterAura", ["pieceBlock"])
	free_case["hero"]["energy"] = 90.0
	var kit := _kit(free_case["state"], [0])
	var result := AdapterScript.cast_enemy_random_skill(free_case["state"], free_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(free_case["state"]["enemy_sp"], 3.0)
	harness.assert_equal(free_case["hero"]["energy"], 100.0)
	harness.assert_equal(kit["metrics"]["events"][0]["event_id"], "freeSkillCast")
	var payload: Dictionary = kit["metrics"]["events"][0]["payload"]
	harness.assert_equal(payload["amount"], 1)
	harness.assert_equal(payload["source_effect"]["source_side"], "enemy")
	harness.assert_false(payload["source_effect"]["spent_skill_points"])

	var ex_case := _case("ascend", [])
	ex_case["hero"]["energy"] = 40.0
	kit = _kit(ex_case["state"])
	result = AdapterScript.cast_enemy_exclusive(ex_case["state"], ex_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_true(result["ok"])
	harness.assert_equal(ex_case["state"]["enemy_sp"], 2.0)
	harness.assert_equal(ex_case["hero"]["energy"], 80.0)
	harness.assert_equal(kit["metrics"]["events"][0]["event_id"], "exclusiveCast")
	harness.assert_equal(kit["metrics"]["events"][0]["payload"]["amount"], 2)


func _test_ultimate_order(harness: TestHarness) -> void:
	var pre_case := _case("ascend", ["pieceBlock"])
	pre_case["hero"]["energy"] = 100.0
	var kit := _kit(pre_case["state"], [0])
	var result := AdapterScript.resolve_hero_phase(pre_case["state"], pre_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_true(result["value"]["pre_ultimate"])
	harness.assert_false(result["value"]["post_ultimate"])
	harness.assert_equal(result["value"]["ultimate_casts"], 1)
	harness.assert_equal(pre_case["hero"]["energy"], 50.0)
	harness.assert_equal(kit["metrics"]["events"].map(func(event: Dictionary) -> String: return event["event_id"]), ["ultimateCast", "freeSkillCast"])

	var post_case := _case("ascend", ["pieceBlock"])
	post_case["hero"]["energy"] = 80.0
	kit = _kit(post_case["state"], [0])
	result = AdapterScript.resolve_hero_phase(post_case["state"], post_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_false(result["value"]["pre_ultimate"])
	harness.assert_true(result["value"]["post_ultimate"])
	harness.assert_equal(result["value"]["ultimate_casts"], 1)
	harness.assert_equal(post_case["hero"]["energy"], 20.0)
	harness.assert_equal(kit["metrics"]["events"].map(func(event: Dictionary) -> String: return event["event_id"]), ["freeSkillCast", "ultimateCast"])

	var cost120_case := _case("fate", ["pieceBlock"])
	cost120_case["hero"]["energy"] = 100.0
	kit = _kit(cost120_case["state"], [0])
	result = AdapterScript.resolve_hero_phase(cost120_case["state"], cost120_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_true(result["value"]["post_ultimate"])
	harness.assert_equal(cost120_case["hero"]["energy"], 20.0)
	harness.assert_equal(kit["metrics"]["events"].map(func(event: Dictionary) -> String: return event["event_id"]), ["freeSkillCast", "ultimateCast"])


func _test_guards(harness: TestHarness) -> void:
	for guard in ["game_over", "player_lock", "piece_fate"]:
		var case := _case("ascend", ["pieceBlock"])
		case["hero"]["energy"] = 100.0
		if guard == "game_over":
			case["state"]["game_over"] = true
			case["state"]["battle_result"] = "win"
		elif guard == "player_lock":
			case["state"]["fate"]["enemy_lock"] = "noSkill"
		else:
			case["state"]["enemy_fate"]["active"] = true
			case["state"]["enemy_fate"]["mode"] = "棋子命运"
		var kit := _kit(case["state"], [0])
		var result := AdapterScript.resolve_hero_phase(case["state"], case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
		harness.assert_true(result["ok"])
		harness.assert_equal(result["value"]["status"], "skipped")
		harness.assert_equal(case["hero"]["energy"], 100.0)
		harness.assert_equal(kit["metrics"]["effect_calls"], [])
		harness.assert_equal(kit["metrics"]["events"], [])
		harness.assert_equal(kit["policy_rng"].cursor, 0)


func _test_failures(harness: TestHarness) -> void:
	var handler_case := _case("counterAura", ["pieceBlock"])
	var kit := _kit(handler_case["state"], [0])
	kit["metrics"]["fail_source"] = "free_skill:pieceBlock"
	var result := AdapterScript.cast_enemy_random_skill(handler_case["state"], handler_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "SP committed")
	harness.assert_equal(handler_case["state"]["enemy_sp"], 3.0)
	harness.assert_equal(handler_case["hero"]["energy"], 0.0)
	harness.assert_equal(kit["metrics"]["events"], [])

	var event_case := _case("counterAura", ["pieceBlock"])
	kit = _kit(event_case["state"], [0], true)
	result = AdapterScript.cast_enemy_random_skill(event_case["state"], event_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "SP/effect committed")
	harness.assert_equal(event_case["state"]["enemy_sp"], 3.0)
	harness.assert_equal(event_case["hero"]["energy"], 0.0)

	var ult_case := _case("ascend", ["pieceBlock"])
	ult_case["hero"]["energy"] = 100.0
	kit = _kit(ult_case["state"])
	kit["metrics"]["fail_source"] = "ultimate:ascend"
	result = AdapterScript.resolve_hero_phase(ult_case["state"], ult_case["hero"], _spy_registry(kit["metrics"]), kit["ports"])
	harness.assert_false(result["ok"])
	harness.assert_contains(result["error"], "100 energy committed")
	harness.assert_equal(ult_case["hero"]["energy"], 0.0)
	harness.assert_equal(ult_case["state"]["enemy_sp"], 4.0)


func _test_real_registry(harness: TestHarness) -> void:
	var free_case := _case("counterAura", ["pieceBlock"])
	var kit := _kit(free_case["state"], [0])
	var registry: Variant = _real_registry()
	var result := AdapterScript.cast_enemy_random_skill(free_case["state"], free_case["hero"], registry, kit["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_true(kit["buffs"].has_side("enemy", "tempBlock"))
	harness.assert_equal(free_case["hero"]["energy"], 30.0)

	var ascend_case := _case("ascend", [])
	kit = _kit(ascend_case["state"])
	registry = _real_registry()
	result = AdapterScript.cast_enemy_exclusive(ascend_case["state"], ascend_case["hero"], registry, kit["ports"])
	harness.assert_true(result["ok"], str(result))
	harness.assert_true(ascend_case["state"]["enemies"][0]["general"])
	harness.assert_equal(ascend_case["state"]["enemy_sp"], 2.0)


func _case(skill_id: String, pool: Array) -> Dictionary:
	var max_energy := 120.0 if skill_id in ["fate", "puppet"] else 100.0
	var hero := {
		"id": 900, "name": "敌方测试弈者", "ex_skill": skill_id,
		"skills": [], "skill_pool": pool.duplicate(), "energy": 0.0,
		"max_energy": max_energy, "base_crit_rate": 0.05, "fist_momentum": 0,
	}
	var source := {
		"round": 1, "phase": "enemy_yizhe",
		"sp": 4.0, "sp_max": 6.0, "base_sp_max": 6.0,
		"enemy_sp": 4.0, "enemy_sp_max": 6.0,
		"allies": _team("ally"), "enemies": _team("enemy"),
		"player_heroes": [], "enemy_heroes": [hero],
		"side_buffs": {"ally": [], "enemy": []},
		"fate": {"active": false, "mode": null, "cast_used": false, "chaos_used": false, "enemy_lock": null, "all_in_turns": 0, "roll_index": 0, "skill_sp_gain_this_round": 0},
		"enemy_fate": {"active": false, "mode": null, "cast_used": false, "chaos_used": false, "ally_lock": null, "all_in_turns": 0, "skill_sp_gain_this_round": 0},
		"battle_growth_flags": {"flame_investment_used": false},
		"burn_ex_cast_count": 0, "enemy_burn_ex_cast_count": 0,
		"counter_threshold": 4, "marshal_target_id": 1,
		"ally_puppet_martyr_active": false, "game_over": false, "battle_result": null,
	}
	var errors: Array[String] = []
	var state := BattleStateScript.create(source, errors)
	assert(errors.is_empty(), str(errors))
	return {"state": state, "hero": state["enemy_heroes"][0]}


func _team(side: String) -> Array:
	var result: Array = []
	for slot in range(1, 7):
		result.append({
			"id": slot, "slot": slot, "side": side, "class_id": "default", "class_name": "棋子",
			"hp": 100.0, "max_hp": 100.0, "atk": 10.0, "crit_rate": 0.05,
			"alive": true, "general": false, "base_block_rate": 0.1,
			"extra_action_charges": 0, "buffs": [], "is_puppet": false,
			"fixed_max_hp": null, "puppet_martyr": false, "disarm_turns": 0,
			"stealth_attack_ready": false, "special_id": null,
			"echo_damage_bonus": 0.0, "hp_threshold_crossed": false,
		})
	return result


func _kill(unit: Dictionary) -> void:
	unit["hp"] = 0.0
	unit["alive"] = false


func _kit(
	state: Dictionary,
	policy_values: Array[int] = [],
	fail_event: bool = false,
	relic_service_override: Variant = null,
) -> Dictionary:
	var catalog_errors: Array[String] = []
	var catalog := ContentCatalogScript.build(catalog_errors)
	assert(catalog_errors.is_empty(), str(catalog_errors))
	var buff_errors: Array[String] = []
	var buffs := BuffSystemScript.new({
		"state": state, "catalog": catalog["buffs"],
		"on_event": func(_type: String, _payload: Dictionary) -> void: pass,
	}, buff_errors)
	assert(buff_errors.is_empty(), str(buff_errors))
	var metrics := {"events": [], "logs": [], "effect_calls": [], "fail_source": ""}
	var actions := {
		"emit_combat_event": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"emit_content_event": func(request: Dictionary) -> Dictionary:
			metrics["events"].append(request.duplicate(true))
			return CombatPortsScript.fail("injected event failure") if fail_event else CombatPortsScript.ok(null),
		"log": func(request: Dictionary) -> Dictionary:
			metrics["logs"].append(request.duplicate(true))
			return CombatPortsScript.ok(null),
		"on_battle_resolved": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_damage": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"record_heal": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(null),
		"resolve_battle_end": func(_request: Dictionary) -> Dictionary: return CombatPortsScript.ok(true),
	}
	var combat_rng := FixedRng.new([0])
	var policy_rng := FixedRng.new(policy_values)
	var relics: Variant = _real_relic_system(catalog)
	if relic_service_override != null:
		relics = relic_service_override
	var port_errors: Array[String] = []
	var ports := CombatPortsScript.new({
		"actions": actions,
		"services": {
			"combat_rng": combat_rng, "enemy_policy_rng": policy_rng,
			"damage": DamageStub.new(), "buffs": buffs,
			"tuning": catalog["tuning"], "catalogs": catalog, "relics": relics,
		},
	}, port_errors)
	assert(port_errors.is_empty(), str(port_errors))
	return {"ports": ports, "metrics": metrics, "combat_rng": combat_rng, "policy_rng": policy_rng, "relics": relics, "buffs": buffs}


func _real_relic_system(catalog: Dictionary) -> Variant:
	var dispatcher_errors: Array[String] = []
	var dispatcher := HookDispatcherScript.new({
		"event_catalog": catalog["events"],
		"on_error": func(_message: String, _metadata: Dictionary) -> void: pass,
	}, dispatcher_errors)
	assert(dispatcher_errors.is_empty(), str(dispatcher_errors))
	var relic_errors: Array[String] = []
	var relics := RelicSystemScript.new({
		"catalog": catalog["relics"],
		"dispatcher": dispatcher,
		"get_owned_relic_ids": func() -> Array: return [],
		"actions": {},
	}, relic_errors)
	assert(relic_errors.is_empty(), str(relic_errors))
	assert(relics.is_valid())
	return relics


func _spy_registry(metrics: Dictionary) -> Variant:
	var catalog_errors: Array[String] = []
	var catalog := ContentCatalogScript.build(catalog_errors)
	assert(catalog_errors.is_empty())
	var handler := func(context: Dictionary, _ports: Variant) -> Dictionary:
		var source: Dictionary = context["source_effect"]
		var marker := "%s:%s" % [source["source_type"], source["source_id"]]
		metrics["effect_calls"].append(marker)
		if metrics["fail_source"] == marker:
			return CombatPortsScript.fail("injected handler failure")
		return CombatPortsScript.ok({"marker": marker})
	var map := {}
	for definition: Variant in catalog["skills"].values():
		map[definition.effect_id] = handler
	for group in ["exclusive", "ultimate"]:
		for definition: Variant in catalog["hero_abilities"][group].values():
			map[definition.handler_id] = handler
	var registry := EffectRegistryScript.new()
	var errors: Array[String] = []
	assert(registry.register_map(map, errors), str(errors))
	return registry


func _real_registry() -> Variant:
	var registry := EffectRegistryScript.new()
	var errors: Array[String] = []
	assert(registry.merge([
		FreeEffectsScript.handler_map(), FlameEffectsScript.handler_map(),
		MarshalEffectsScript.handler_map(), SiegeEffectsScript.handler_map(),
	], errors), str(errors))
	return registry
