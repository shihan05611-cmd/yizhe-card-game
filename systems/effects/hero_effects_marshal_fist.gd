class_name HeroEffectsMarshalFist
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const StatsScript = preload("res://core/stats.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const TargetingRulesScript = preload("res://systems/targeting/targeting_rules.gd")
const MarshalGrowthScript = preload("res://systems/growth/marshal_growth.gd")
const PermanentGrowthScript = preload("res://systems/growth/permanent_growth.gd")
const GrowthPortScript = preload("res://systems/growth/growth_port.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")

## M2-only handlers for Knight, Marshal and Ning Bufan. These handlers never
## pay SP/energy, create cards, consume action quotas, or emit presentation FX.
## Runtime service failures use sequential-commit semantics: the returned error
## says whether an earlier growth, damage, heal or Buff mutation is already live.

const EX_COUNTER := "battle.castExclusiveSkill.counterAura"
const EX_ASCEND := "battle.castExclusiveSkill.ascend"
const EX_FIST := "battle.castExclusiveSkill.fist"
const ULT_COUNTER := "battle.castUltimateByHero.counterAura"
const ULT_ASCEND := "battle.castUltimateByHero.ascend"
const ULT_FIST := "battle.castUltimateByHero.fist"

const CONTEXT_REQUIRED_KEYS := ["state", "caster", "source_effect"]
const CONTEXT_OPTIONAL_KEYS := ["growth_piece_ratios"]
const EFFECT_CONTEXT_KEYS := [
	"source_type", "source_id", "source_name", "source_side", "source_actor_id",
	"counts_as_skill_cast", "spent_skill_points", "free_cast",
	"counts_as_basic_attack", "counts_as_attack", "triggers_enemy_kill_effects",
]
const KNIGHT_CHIVALRY_ID := "knightChivalry"
const MARCH_ID := "march"
const BREAK_MARKED_ID := "breakMarked"
const BREAK_FORMATION_ID := "breakFormation"


static func handler_map() -> Dictionary:
	return {
		EX_COUNTER: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("counterAura", false, context, ports),
		EX_ASCEND: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("ascend", false, context, ports),
		EX_FIST: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("fist", false, context, ports),
		ULT_COUNTER: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("counterAura", true, context, ports),
		ULT_ASCEND: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("ascend", true, context, ports),
		ULT_FIST: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("fist", true, context, ports),
	}


static func is_usable(
	skill_id: Variant,
	is_ultimate: Variant,
	context: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if skill_id not in ["counterAura", "ascend", "fist"]:
		errors.append("unknown Marshal/Fist hero skill id: %s" % str(skill_id))
		return false
	if typeof(is_ultimate) != TYPE_BOOL:
		errors.append("is_ultimate must be a boolean")
		return false
	if not _validate_context(String(skill_id), is_ultimate, context, ports, errors):
		return false
	return _is_usable_validated(String(skill_id), is_ultimate, context, errors)


static func _execute(
	skill_id: String,
	is_ultimate: bool,
	context: Dictionary,
	ports: Variant,
) -> Dictionary:
	var errors: Array[String] = []
	if not _validate_context(skill_id, is_ultimate, context, ports, errors):
		return CombatPortsScript.fail(errors[0] if not errors.is_empty() else "invalid hero effect context")
	if not is_ultimate and skill_id == "counterAura":
		return CombatPortsScript.fail("counterAura exclusive is passive and cannot be actively cast")
	if not _is_usable_validated(skill_id, is_ultimate, context, errors):
		return CombatPortsScript.fail("%s %s is unusable" % ["ultimate" if is_ultimate else "exclusive", skill_id])
	if is_ultimate:
		match skill_id:
			"counterAura":
				return _counter_ultimate(context, ports)
			"ascend":
				return _ascend_ultimate(context, ports)
			"fist":
				return _fist_ultimate(context, ports)
	else:
		match skill_id:
			"ascend":
				return _ascend_exclusive(context, ports)
			"fist":
				return _fist_exclusive(context, ports)
	return CombatPortsScript.fail("unreachable Marshal/Fist hero effect branch")


static func _is_usable_validated(
	skill_id: String,
	is_ultimate: bool,
	context: Dictionary,
	errors: Array[String],
) -> bool:
	if not is_ultimate and skill_id == "counterAura":
		return false
	var side: String = context["source_effect"]["source_side"]
	var state: Dictionary = context["state"]
	if skill_id == "ascend":
		# Web consumes an ultimate and resolves a real no-target no-op. Therefore
		# the effect remains usable even when no living General exists.
		if is_ultimate:
			return true
		return not _eligible_marshal_units(state, side, _growth_ratios(context), errors).is_empty()
	if skill_id == "fist":
		if is_ultimate:
			return true
		return not TargetingRulesScript.lockable(state, _other_side(side), errors).is_empty()
	return is_ultimate


static func _counter_ultimate(context: Dictionary, ports: Variant) -> Dictionary:
	var side: String = context["source_effect"]["source_side"]
	var targets := TargetingRulesScript.alive(context["state"], side)
	var errors: Array[String] = []
	var buffs: Variant = ports.service("buffs", errors)
	if not errors.is_empty() or not _preflight_unit_buff(buffs, targets, KNIGHT_CHIVALRY_ID, errors):
		return CombatPortsScript.fail("counterAura ultimate preflight failed%s" % _error_suffix(errors))
	var applied := 0
	for target: Dictionary in targets:
		if not buffs.apply_unit(target, KNIGHT_CHIVALRY_ID, 1, null, errors):
			return _committed_failure("counterAura ultimate Buff failed", applied > 0, errors)
		applied += 1
	var logged := _log(context, ports, "释放骑士道誓：存活同侧棋子获得骑士道。")
	if not logged["ok"]:
		return _after_commit_failure("counterAura ultimate log failed", logged, applied > 0)
	return CombatPortsScript.ok({
		"skill_id": "counterAura", "ultimate": true,
		"committed": applied > 0, "applied_count": applied,
	})


static func _ascend_exclusive(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var ratios: Variant = _growth_ratios(context)
	var errors: Array[String] = []
	var candidates := _eligible_marshal_units(state, side, ratios, errors)
	if not errors.is_empty() or candidates.is_empty():
		return CombatPortsScript.fail("ascend exclusive has no eligible unit%s" % _error_suffix(errors))
	var general: Variant = null
	for unit: Dictionary in candidates:
		if unit["general"]:
			general = unit
			break
	var repeated := general != null
	var target: Dictionary
	if repeated:
		target = general
	else:
		target = _marshal_target(candidates, int(state["marshal_target_id"]) if side == "ally" else 1)
	var tuning := _marshal_tuning(ports, errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("ascend tuning preflight failed%s" % _error_suffix(errors))

	var before_stacks := 1 if repeated else 0
	var growth_before_snapshot: Array = []
	var growth_preview: Variant = null
	if ratios != null:
		var read := _read_growth_stacks(
			ports, MarshalGrowthScript.BUFF_ID, "pieceSlot", target["slot"], errors,
		)
		if not errors.is_empty() or read.is_empty():
			return CombatPortsScript.fail("ascend growth stack preflight failed%s" % _error_suffix(errors))
		before_stacks = int(read["stacks"])
		growth_before_snapshot = read["snapshot"]
	# Run growth writes the actual permanent stack. A living General with a
	# historically missing stack still receives Web's repeat combat delta (1->2),
	# while the draft correctly grows 0->1.
	var growth_plan := MarshalGrowthScript.promotion_plan(target["slot"], before_stacks, tuning, errors)
	var combat_before := maxi(1, before_stacks) if repeated else before_stacks
	var combat_delta := MarshalGrowthScript.promotion_delta(combat_before, combat_before + 1, tuning, errors)
	if not errors.is_empty() or growth_plan.is_empty() or combat_delta.is_empty():
		return CombatPortsScript.fail("ascend projection preflight failed%s" % _error_suffix(errors))
	var projected := MarshalGrowthScript.project_unit(target, combat_delta, errors)
	if not errors.is_empty() or projected.is_empty():
		return CombatPortsScript.fail("ascend unit projection failed%s" % _error_suffix(errors))
	if ratios != null:
		growth_preview = _preview_growth_exact(
			ports, growth_before_snapshot, growth_plan["request"], errors,
		)
		if not errors.is_empty():
			return CombatPortsScript.fail("ascend growth preview failed%s" % _error_suffix(errors))

	# External Run draft is committed first, matching Web. Battle state changes only
	# after the atomic GrowthPort has confirmed the exact previewed final batch.
	var growth_committed := false
	if ratios != null:
		var staged: Dictionary = ports.call_action(GrowthPortScript.ACTION_STAGE, {"requests": [growth_plan["request"]]})
		if not staged["ok"]:
			return CombatPortsScript.fail("ascend growth stage failed (no battle state committed): %s" % staged["error"])
		growth_committed = true
		if staged["value"] != growth_preview:
			return CombatPortsScript.fail("ascend growth stage disagrees with preview (growth committed; no battle state committed)")

	for field in ["atk", "max_hp", "hp", "base_block_rate", "crit_rate"]:
		target[field] = projected[field]
	if not repeated:
		for unit: Dictionary in _team(state, side):
			unit["general"] = false
		target["general"] = true
	var healed := 0.0
	if repeated:
		healed = MarshalGrowthScript.repeat_heal_amount(target, tuning, errors)
		if not errors.is_empty():
			return _committed_failure("ascend repeat heal calculation failed", true, errors)
		var old_hp := float(target["hp"])
		target["hp"] = minf(float(target["max_hp"]), old_hp + healed)
		healed = float(target["hp"]) - old_hp
		if healed > 0.0:
			var recorded: Dictionary = ports.call_action("record_heal", _heal_record(context, target, healed, old_hp, "封命再塑"))
			if not recorded["ok"]:
				return _after_commit_failure("ascend repeat heal record failed", recorded, true)
	var logged := _log(context, ports, "释放封命。")
	if not logged["ok"]:
		return _after_commit_failure("ascend exclusive log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "ascend", "ultimate": false, "committed": true,
		"target_id": target["id"], "target_slot": target["slot"],
		"repeated": repeated, "healed": healed,
		"growth_committed": growth_committed,
		"growth_before_stacks": before_stacks,
		"growth_after_stacks": before_stacks + (1 if ratios != null else 0),
	})


static func _ascend_ultimate(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var general: Variant = null
	for unit: Dictionary in _team(state, side):
		if unit["alive"] and unit["general"]:
			general = unit
			break
	if general == null:
		var no_target_log := _log(context, ports, "释放将军出征，但将军未就位。")
		if not no_target_log["ok"]:
			return _after_commit_failure("ascend ultimate no-target log failed", no_target_log, false)
		return CombatPortsScript.ok({
			"skill_id": "ascend", "ultimate": true, "committed": false,
			"no_target": true, "target_id": null, "healed": 0.0,
		})
	var errors: Array[String] = []
	var tuning: Variant = ports.service("tuning", errors)
	var heal_id := "ultAscendHealRatio" if side == "ally" else "enemyUltAscendHealRatio"
	var heal_ratio := _tuning_number(tuning, heal_id, errors)
	var march_turns := _tuning_integer(tuning, "ultAscendMarchTurns", errors)
	var buffs: Variant = ports.service("buffs", errors)
	if (
		not errors.is_empty()
		or heal_ratio < 0.0 or heal_ratio > 1.0
		or march_turns < 1
		or not _preflight_unit_buff(buffs, [general], MARCH_ID, errors)
	):
		return CombatPortsScript.fail("ascend ultimate preflight failed%s" % _error_suffix(errors))
	var old_hp := float(general["hp"])
	var amount := (float(general["max_hp"]) - old_hp) * heal_ratio
	general["hp"] = minf(float(general["max_hp"]), old_hp + amount)
	var healed := float(general["hp"]) - old_hp
	if healed > 0.0:
		var recorded: Dictionary = ports.call_action("record_heal", _heal_record(context, general, healed, old_hp, "将军出征"))
		if not recorded["ok"]:
			return _after_commit_failure("ascend ultimate heal record failed", recorded, true)
	if not buffs.apply_unit(general, MARCH_ID, 1, march_turns, errors):
		return _committed_failure("ascend ultimate march failed", healed > 0.0, errors)
	var logged := _log(context, ports, "释放将军出征。")
	if not logged["ok"]:
		return _after_commit_failure("ascend ultimate log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "ascend", "ultimate": true, "committed": true,
		"no_target": false, "target_id": general["id"], "healed": healed,
		"march_turns": march_turns,
	})


static func _fist_exclusive(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var caster: Dictionary = context["caster"]
	var opposing := _other_side(side)
	var errors: Array[String] = []
	var candidates := TargetingRulesScript.lockable(state, opposing, errors)
	if not errors.is_empty() or candidates.is_empty():
		return CombatPortsScript.fail("fist exclusive target preflight failed%s" % _error_suffix(errors))
	var tuning: Variant = ports.service("tuning", errors)
	var per_stack := _tuning_number(tuning, "fistMasteryDamageUpPerStack", errors)
	var mastery_stacks := 0
	var growth_before_snapshot: Array = []
	var growth_enabled := _growth_ratios(context) != null
	if growth_enabled:
		var read := _read_growth_stacks(
			ports, PermanentGrowthScript.FIST_MASTERY_ID, "hero",
			PermanentGrowthScript.FIST_HERO_ID, errors,
		)
		if not errors.is_empty() or read.is_empty():
			return CombatPortsScript.fail("fist mastery stack preflight failed%s" % _error_suffix(errors))
		mastery_stacks = int(read["stacks"])
		growth_before_snapshot = read["snapshot"]
	var plan := PermanentGrowthScript.fist_growth_plan(
		caster["fist_momentum"], mastery_stacks, per_stack, errors,
	)
	if not errors.is_empty() or plan.is_empty():
		return CombatPortsScript.fail("fist exclusive formula preflight failed%s" % _error_suffix(errors))
	var raw := _fmt(StatsScript.team_average_atk(state, side)) * (
		1.0 + float(plan["momentum_effects"]["damage_up_rate"]) + float(plan["mastery_damage_up_rate"])
	)
	var all_damage_contexts := _prebuild_damage_contexts(
		context, candidates, raw,
		float(caster["base_crit_rate"]) + float(plan["momentum_effects"]["crit_rate_up"]),
		"拳劲", ports, errors,
	)
	if not errors.is_empty() or all_damage_contexts.size() != candidates.size():
		return CombatPortsScript.fail("fist exclusive damage preflight failed%s" % _error_suffix(errors))
	var contexts_by_id := {}
	for index in candidates.size():
		contexts_by_id[candidates[index]["id"]] = all_damage_contexts[index]
	var growth_preview: Variant = null
	if growth_enabled:
		growth_preview = _preview_growth_exact(
			ports, growth_before_snapshot, plan["request"], errors,
		)
		if not errors.is_empty():
			return CombatPortsScript.fail("fist mastery preview failed%s" % _error_suffix(errors))

	var growth_committed := false
	if growth_enabled:
		var staged: Dictionary = ports.call_action(GrowthPortScript.ACTION_STAGE, {"requests": [plan["request"]]})
		if not staged["ok"]:
			return CombatPortsScript.fail("fist mastery stage failed (no combat state committed): %s" % staged["error"])
		growth_committed = true
		if staged["value"] != growth_preview:
			return CombatPortsScript.fail("fist mastery stage disagrees with preview (growth committed; no combat state committed)")
	# Match Web ordering: permanent growth commits before random target draws.
	var rng: Variant = ports.service("combat_rng", errors)
	var targets := _random_unique_from_pool(
		candidates, int(plan["momentum_effects"]["target_count"]), rng, errors,
	)
	if not errors.is_empty() or targets.is_empty():
		return _committed_failure("fist exclusive target RNG failed", growth_committed, errors)
	var dealt_total := 0.0
	var hits := 0
	for target: Dictionary in targets:
		var result := _apply_damage(target, contexts_by_id[target["id"]], ports, errors)
		if result.is_empty():
			return _committed_failure(
				"fist exclusive damage failed", growth_committed or hits > 0, errors,
			)
		hits += 1
		dealt_total += float(result["dealt"])
	caster["fist_momentum"] = int(plan["next_momentum"])
	var logged := _log(context, ports, "释放拳劲，拳势+1。")
	if not logged["ok"]:
		return _after_commit_failure("fist exclusive log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "fist", "ultimate": false, "committed": true,
		"target_ids": targets.map(func(target: Dictionary) -> Variant: return target["id"]),
		"hits": hits, "dealt_total": dealt_total,
		"momentum_before": plan["momentum_effects"]["momentum"],
		"momentum_after": caster["fist_momentum"],
		"mastery_before_stacks": mastery_stacks,
		"mastery_after_stacks": mastery_stacks + (1 if growth_enabled else 0),
		"growth_committed": growth_committed,
	})


static func _fist_ultimate(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var caster: Dictionary = context["caster"]
	var opposing := _other_side(side)
	var errors: Array[String] = []
	var candidates := TargetingRulesScript.lockable(state, opposing, errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("fist ultimate target preflight failed%s" % _error_suffix(errors))
	var tuning: Variant = ports.service("tuning", errors)
	var per_stack := _tuning_number(tuning, "fistMasteryDamageUpPerStack", errors)
	var mastery_stacks := 0
	if _growth_ratios(context) != null:
		var read := _read_growth_stacks(
			ports, PermanentGrowthScript.FIST_MASTERY_ID, "hero",
			PermanentGrowthScript.FIST_HERO_ID, errors,
		)
		if not errors.is_empty() or read.is_empty():
			return CombatPortsScript.fail("fist ultimate mastery preflight failed%s" % _error_suffix(errors))
		mastery_stacks = int(read["stacks"])
	var momentum_effects := PermanentGrowthScript.fist_momentum_effects(caster["fist_momentum"], errors)
	var mastery_rate := PermanentGrowthScript.fist_mastery_damage_up_rate(mastery_stacks, per_stack, errors)
	var mastery_hits := PermanentGrowthScript.fist_mastery_ultimate_bonus_hits(mastery_stacks, errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("fist ultimate formula preflight failed%s" % _error_suffix(errors))
	if candidates.is_empty():
		var empty_log := _log(context, ports, "释放拳意·无量，但当前无可锁定目标。")
		if not empty_log["ok"]:
			return _after_commit_failure("fist ultimate no-target log failed", empty_log, false)
		return CombatPortsScript.ok({
			"skill_id": "fist", "ultimate": true, "committed": false,
			"no_target": true, "hits": 0, "kills": 0, "dealt_total": 0.0,
			"momentum": caster["fist_momentum"], "mastery_stacks": mastery_stacks,
		})
	var raw := _fmt(StatsScript.team_average_atk(state, side) * 0.6) * (
		1.0 + float(momentum_effects["damage_up_rate"]) + mastery_rate
	)
	# Every possible retarget receives a prebuilt canonical B0 context before the
	# first hit mutates HP. Later apply failures are the explicit sequential case.
	var contexts_by_id := {}
	var all_contexts := _prebuild_damage_contexts(
		context, candidates, raw,
		float(caster["base_crit_rate"]) + float(momentum_effects["crit_rate_up"]),
		"拳意·无量", ports, errors,
	)
	if not errors.is_empty() or all_contexts.size() != candidates.size():
		return CombatPortsScript.fail("fist ultimate damage preflight failed%s" % _error_suffix(errors))
	for index in candidates.size():
		contexts_by_id[candidates[index]["id"]] = all_contexts[index]
	var rng: Variant = ports.service("combat_rng", errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("fist ultimate RNG unavailable%s" % _error_suffix(errors))
	var current: Variant = _random_pick(candidates, rng, errors)
	if not errors.is_empty() or current == null:
		return CombatPortsScript.fail("fist ultimate initial target failed%s" % _error_suffix(errors))
	var remaining: int = int(momentum_effects["ultimate_hits"]) + mastery_hits
	var base_hits := remaining
	var hits := 0
	var kills := 0
	var dealt_total := 0.0
	while remaining > 0:
		if current == null or not current["alive"]:
			var alive := TargetingRulesScript.lockable(state, opposing, errors)
			if not errors.is_empty():
				return _committed_failure("fist ultimate retarget query failed", hits > 0, errors)
			if alive.is_empty():
				break
			current = _random_pick(alive, rng, errors)
			if not errors.is_empty() or current == null:
				return _committed_failure("fist ultimate retarget RNG failed", hits > 0, errors)
		var result := _apply_damage(current, contexts_by_id[current["id"]], ports, errors)
		if result.is_empty():
			return _committed_failure("fist ultimate damage failed", hits > 0, errors)
		remaining -= 1
		hits += 1
		dealt_total += float(result["dealt"])
		if result["died"]:
			kills += 1
			remaining += 2
	var logged := _log(context, ports, "释放拳意·无量。")
	if not logged["ok"]:
		return _after_commit_failure("fist ultimate log failed", logged, hits > 0)
	return CombatPortsScript.ok({
		"skill_id": "fist", "ultimate": true, "committed": hits > 0,
		"no_target": false, "base_hits": base_hits, "hits": hits, "kills": kills,
		"dealt_total": dealt_total, "momentum": caster["fist_momentum"],
		"mastery_stacks": mastery_stacks,
	})


static func _validate_context(
	skill_id: String,
	is_ultimate: bool,
	context: Variant,
	ports: Variant,
	errors: Array[String],
) -> bool:
	if not _closed_context(context, errors):
		return false
	if (
		typeof(ports) != TYPE_OBJECT or ports == null
		or ports.get_script() != CombatPortsScript or ports.is_valid() != true
	):
		errors.append("hero effect execution requires valid CombatPorts")
		return false
	var state_errors: Array[String] = []
	if not BattleStateScript.validate(context["state"], state_errors):
		errors.append("hero effect state is non-canonical: %s" % state_errors[0])
		return false
	if context["state"]["game_over"]:
		errors.append("hero effects are unavailable after battle end")
		return false
	var effect: Variant = context["source_effect"]
	if not _exact_dictionary(effect, EFFECT_CONTEXT_KEYS, "hero source_effect", errors):
		return false
	var normalized_errors: Array[String] = []
	var normalized := ContextsScript.create_effect_context(effect, normalized_errors)
	if not normalized_errors.is_empty() or normalized != effect:
		errors.append("hero source_effect must be canonical")
		return false
	var expected_type := (
		ContextsScript.EFFECT_SOURCE_TYPE["ULTIMATE"]
		if is_ultimate else ContextsScript.EFFECT_SOURCE_TYPE["EXCLUSIVE_SKILL"]
	)
	if effect["source_type"] != expected_type or effect["source_id"] != skill_id:
		errors.append("hero source_effect type/id does not match handler")
		return false
	if effect["source_side"] not in ["ally", "enemy"] or effect["counts_as_skill_cast"] != true:
		errors.append("hero source_effect must be a side-owned skill cast")
		return false
	var side: String = effect["source_side"]
	if side == "ally":
		if context["state"]["enemy_fate"]["ally_lock"] == "noSkill":
			errors.append("enemy Fate currently prevents player hero skills")
			return false
		if (
			context["state"]["fate"]["active"]
			and context["state"]["fate"]["mode"] == "棋子命运"
			and context["state"]["fate"]["all_in_turns"] <= 0
		):
			errors.append("piece Fate currently prevents player hero skills")
			return false
	else:
		if context["state"]["fate"]["enemy_lock"] == "noSkill":
			errors.append("player Fate currently prevents enemy hero skills")
			return false
		if (
			context["state"]["enemy_fate"]["active"]
			and context["state"]["enemy_fate"]["mode"] == "棋子命运"
			and context["state"]["enemy_fate"]["all_in_turns"] <= 0
		):
			errors.append("piece Fate currently prevents enemy hero skills")
			return false
	var caster: Variant = context["caster"]
	if typeof(caster) != TYPE_DICTIONARY:
		errors.append("hero effect caster must be a canonical hero Dictionary")
		return false
	var hero_list: Array = (
		context["state"]["player_heroes"]
		if effect["source_side"] == "ally" else context["state"]["enemy_heroes"]
	)
	var canonical: Variant = null
	for hero: Dictionary in hero_list:
		if hero["id"] == effect["source_actor_id"]:
			canonical = hero
			break
	if canonical == null or not is_same(caster, canonical):
		errors.append("hero effect caster must be the matching canonical state hero reference")
		return false
	if caster["ex_skill"] != skill_id:
		errors.append("hero effect caster.ex_skill does not match handler")
		return false
	if effect["source_side"] == "ally" and caster["deployed"] != true:
		errors.append("ally hero effect caster must be deployed")
		return false
	if context.has("growth_piece_ratios") and context["growth_piece_ratios"] != null:
		if effect["source_side"] != "ally":
			errors.append("permanent Run growth is ally-only")
			return false
		if skill_id not in ["ascend", "fist"]:
			errors.append("this hero effect does not own permanent Run growth")
			return false
		if not _validate_ratios(context["growth_piece_ratios"], errors):
			return false
		for action_id in [
			GrowthPortScript.ACTION_PREVIEW, GrowthPortScript.ACTION_STAGE,
			GrowthPortScript.ACTION_GET_STACKS, GrowthPortScript.ACTION_SNAPSHOT,
		]:
			if action_id not in ports.action_ids():
				errors.append("active Run growth requires GrowthPort action: %s" % action_id)
				return false
	return true


static func _eligible_marshal_units(
	state: Dictionary,
	side: String,
	ratios: Variant,
	errors: Array[String],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: Dictionary in _team(state, side):
		if not unit["alive"] or unit["is_puppet"]:
			continue
		if ratios != null:
			if not ratios.has(unit["slot"]):
				errors.append("growth ratios misses slot %s" % str(unit["slot"]))
				return []
			if float(ratios[unit["slot"]]) <= 0.0:
				continue
		result.append(unit)
	return result


static func _marshal_target(candidates: Array[Dictionary], preferred_slot: int) -> Dictionary:
	for unit: Dictionary in candidates:
		if int(unit["slot"]) == preferred_slot:
			return unit
	var sorted := candidates.duplicate(false)
	sorted.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["slot"]) < int(right["slot"])
	)
	return sorted[0]


static func _random_unique_from_pool(
	candidates: Array,
	count: int,
	rng: Variant,
	errors: Array[String],
) -> Array[Dictionary]:
	var pool := candidates.duplicate(false)
	var targets: Array[Dictionary] = []
	while not pool.is_empty() and targets.size() < count:
		var picked: Variant = _random_pick(pool, rng, errors)
		if not errors.is_empty() or picked == null:
			return []
		targets.append(picked)
		pool.erase(picked)
	return targets


static func _random_pick(pool: Array, rng: Variant, errors: Array[String]) -> Variant:
	if pool.is_empty():
		return null
	var index: Variant = rng.int_range(0, pool.size() - 1)
	if typeof(index) != TYPE_INT or index < 0 or index >= pool.size():
		errors.append("combat_rng.int_range returned an out-of-range index")
		return null
	return pool[index]


static func _prebuild_damage_contexts(
	context: Dictionary,
	targets: Array,
	raw: float,
	crit_rate: float,
	source_name: String,
	ports: Variant,
	errors: Array[String],
) -> Array[Dictionary]:
	var damage: Variant = ports.service("damage", errors)
	var buffs: Variant = ports.service("buffs", errors)
	if not errors.is_empty() or damage == null or damage.is_valid() != true:
		errors.append("damage service is unavailable")
		return []
	var side: String = context["source_effect"]["source_side"]
	var extra_field_crit: bool = buffs.has_side(side, BREAK_FORMATION_ID)
	var result: Array[Dictionary] = []
	for target: Dictionary in targets:
		var target_extra := 0.2 if extra_field_crit and buffs.has_unit(target, BREAK_MARKED_ID) else 0.0
		var local_errors: Array[String] = []
		var damage_context := ContextsScript.create_damage_context({
			"target_id": target["id"],
			"raw_amount": raw,
			"category": ContextsScript.DAMAGE_CATEGORY["DIRECT"],
			"effect": ContextsScript.snapshot(context["source_effect"]),
			"dealer_type": "yizhe",
			"dealer_name": context["caster"]["name"],
			"dealer_id": context["caster"]["id"],
			"attacker_unit_id": 0,
			"can_crit": true,
			"crit_rate": crit_rate + target_extra,
			"guaranteed_crit": false,
			"can_block": true,
		}, local_errors)
		_append_errors(local_errors, errors)
		if not local_errors.is_empty() or damage_context.is_empty():
			return []
		result.append(damage_context)
	return result


static func _apply_damage(
	target: Dictionary,
	damage_context: Dictionary,
	ports: Variant,
	errors: Array[String],
) -> Dictionary:
	var damage: Variant = ports.service("damage", errors)
	if not errors.is_empty():
		return {}
	var result: Variant = damage.apply(target, damage_context, {}, errors)
	if not _valid_damage_result(result):
		if errors.is_empty():
			errors.append("damage service returned a non-canonical result")
		return {}
	return result


static func _preflight_unit_buff(
	buffs: Variant,
	targets: Array,
	buff_id: String,
	errors: Array[String],
) -> bool:
	if buffs == null or buffs.is_valid() != true:
		errors.append("Buff service is unavailable")
		return false
	if buffs.definition_for(buff_id, "unit", errors) == null:
		return false
	for target: Dictionary in targets:
		if not buffs.validate_unit_holder(target, errors):
			return false
	return true


static func _marshal_tuning(ports: Variant, errors: Array[String]) -> Dictionary:
	var service: Variant = ports.service("tuning", errors)
	if not errors.is_empty():
		return {}
	var result := {}
	for id in [
		"ascendAtkBonus", "ascendHpBonus", "ascendBlockBonus",
		"ascendRepeatAtkBonus", "ascendRepeatBlockBonus",
		"ascendRepeatCritBonus", "ascendRepeatMissingHpHealRatio",
	]:
		result[id] = _tuning_number(service, id, errors)
	return result if errors.is_empty() else {}


static func _tuning_number(tuning: Variant, id: String, errors: Array[String]) -> float:
	if typeof(tuning) != TYPE_DICTIONARY:
		errors.append("tuning service must return a Dictionary")
		return 0.0
	var definition: Variant = tuning.get(id)
	if not definition is Resource or definition.get_script() != TuningValueDefinition:
		errors.append("tuning.%s must be a TuningValueDefinition" % id)
		return 0.0
	if not _finite_number(definition.value):
		errors.append("tuning.%s.value must be finite" % id)
		return 0.0
	return float(definition.value)


static func _tuning_integer(tuning: Variant, id: String, errors: Array[String]) -> int:
	var value := _tuning_number(tuning, id, errors)
	if not errors.is_empty():
		return 0
	if value != floorf(value):
		errors.append("tuning.%s.value must be an integer" % id)
		return 0
	return int(value)


static func _heal_record(
	context: Dictionary,
	target: Dictionary,
	amount: float,
	old_hp: float,
	source_name: String,
) -> Dictionary:
	return {
		"target_id": target["id"], "target_side": target["side"],
		"amount": amount, "source_name": source_name,
		"source_effect": ContextsScript.snapshot(context["source_effect"]),
		"old_hp": old_hp, "new_hp": target["hp"],
	}


static func _log(context: Dictionary, ports: Variant, message: String) -> Dictionary:
	return ports.call_action("log", {
		"message": "%s%s" % [context["caster"]["name"], message],
		"class": "ok" if context["source_effect"]["source_side"] == "ally" else "bad",
		"source_effect": ContextsScript.snapshot(context["source_effect"]),
	})


static func _closed_context(value: Variant, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("hero effect context must be a canonical Dictionary")
		return false
	if value.size() < CONTEXT_REQUIRED_KEYS.size() or value.size() > CONTEXT_REQUIRED_KEYS.size() + 1:
		errors.append("hero effect context has a non-canonical field set")
		return false
	for key in CONTEXT_REQUIRED_KEYS:
		if not value.has(key):
			errors.append("hero effect context.%s is required" % key)
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or (key not in CONTEXT_REQUIRED_KEYS and key not in CONTEXT_OPTIONAL_KEYS):
			errors.append("hero effect context contains an unknown field")
			return false
	return true


static func _validate_ratios(value: Variant, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != 6:
		errors.append("growth_piece_ratios must contain exactly six integer slots")
		return false
	for slot in range(1, 7):
		if not value.has(slot) or not _finite_number(value[slot]):
			errors.append("growth_piece_ratios[%d] must be a finite rate" % slot)
			return false
		if float(value[slot]) < 0.0 or float(value[slot]) > 1.0:
			errors.append("growth_piece_ratios[%d] must be from 0 through 1" % slot)
			return false
	return true


static func _read_growth_stacks(
	ports: Variant,
	buff_id: String,
	target_type: String,
	target_id: int,
	errors: Array[String],
) -> Dictionary:
	var snapshot_result: Dictionary = ports.call_action(GrowthPortScript.ACTION_SNAPSHOT, {})
	if not snapshot_result["ok"]:
		errors.append("growth snapshot failed: %s" % snapshot_result["error"])
		return {}
	if not _valid_permanent_array(snapshot_result["value"]):
		errors.append("growth snapshot returned a non-canonical permanent array")
		return {}
	var stacks := 0
	for entry: Dictionary in snapshot_result["value"]:
		if (
			entry["id"] == buff_id and entry["target"]["type"] == target_type
			and entry["target"]["id"] == target_id
		):
			stacks = int(entry["stacks"])
			break
	var query: Dictionary = ports.call_action(GrowthPortScript.ACTION_GET_STACKS, {
		"id": buff_id, "target": {"type": target_type, "id": target_id},
	})
	if not query["ok"]:
		errors.append("growth stack query failed: %s" % query["error"])
		return {}
	if not _safe_non_negative_integer(query["value"]) or int(query["value"]) != stacks:
		errors.append("growth stack query disagrees with canonical snapshot")
		return {}
	return {"stacks": stacks, "snapshot": snapshot_result["value"].duplicate(true)}


static func _preview_growth_exact(
	ports: Variant,
	before: Array,
	request: Dictionary,
	errors: Array[String],
) -> Array:
	var expected: Array = before.duplicate(true)
	var found := false
	for entry: Dictionary in expected:
		if (
			entry["id"] == request["id"]
			and entry["target"]["type"] == request["target"]["type"]
			and entry["target"]["id"] == request["target"]["id"]
		):
			if int(entry["stacks"]) > PermanentGrowthScript.MAX_SAFE_INTEGER - int(request["stacks"]):
				errors.append("growth preview would overflow safe stacks")
				return []
			entry["stacks"] = int(entry["stacks"]) + int(request["stacks"])
			found = true
			break
	if not found:
		expected.append(request.duplicate(true))
	var preview: Dictionary = ports.call_action(
		GrowthPortScript.ACTION_PREVIEW, {"requests": [request.duplicate(true)]},
	)
	if not preview["ok"]:
		errors.append("growth preview failed: %s" % preview["error"])
		return []
	if not _valid_permanent_array(preview["value"]) or preview["value"] != expected:
		errors.append("growth preview does not preserve the exact complete final set")
		return []
	return preview["value"].duplicate(true)


static func _valid_permanent_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var identities := {}
	for entry: Variant in value:
		if not _exact_dictionary(entry, ["id", "target", "stacks"], "permanent entry", []):
			return false
		if not _exact_dictionary(entry["target"], ["type", "id"], "permanent target", []):
			return false
		if (
			typeof(entry["id"]) != TYPE_STRING or entry["id"].is_empty()
			or entry["id"] != entry["id"].strip_edges()
		):
			return false
		if entry["target"]["type"] not in ["pieceSlot", "hero"]:
			return false
		if typeof(entry["target"]["id"]) != TYPE_INT or entry["target"]["id"] <= 0:
			return false
		if entry["target"]["type"] == "pieceSlot" and entry["target"]["id"] > 6:
			return false
		if (
			typeof(entry["stacks"]) != TYPE_INT or entry["stacks"] <= 0
			or entry["stacks"] > PermanentGrowthScript.MAX_SAFE_INTEGER
		):
			return false
		var identity := "%s|%s|%s" % [entry["id"], entry["target"]["type"], str(entry["target"]["id"])]
		if identities.has(identity):
			return false
		identities[identity] = true
	return true


static func _valid_damage_result(result: Variant) -> bool:
	if typeof(result) != TYPE_DICTIONARY:
		return false
	var keys := ["dealt", "blocked", "died", "crit", "damage_context", "death_context"]
	if result.size() != keys.size():
		return false
	for key in keys:
		if not result.has(key):
			return false
	return (
		_finite_number(result["dealt"]) and float(result["dealt"]) >= 0.0
		and typeof(result["blocked"]) == TYPE_BOOL
		and typeof(result["died"]) == TYPE_BOOL
		and typeof(result["crit"]) == TYPE_BOOL
		and typeof(result["damage_context"]) == TYPE_DICTIONARY
		and (result["death_context"] == null or typeof(result["death_context"]) == TYPE_DICTIONARY)
	)


static func _exact_dictionary(
	value: Variant,
	keys: Array,
	path: String,
	errors: Array[String],
) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		errors.append("%s must have a canonical closed shape" % path)
		return false
	for key in keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			errors.append("%s contains an unknown field" % path)
			return false
	return true


static func _safe_non_negative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= PermanentGrowthScript.MAX_SAFE_INTEGER


static func _growth_ratios(context: Dictionary) -> Variant:
	return context.get("growth_piece_ratios", null)


static func _team(state: Dictionary, side: String) -> Array:
	return state["allies"] if side == "ally" else state["enemies"]


static func _other_side(side: String) -> String:
	return "enemy" if side == "ally" else "ally"


static func _fmt(value: float) -> float:
	return maxf(0.0, roundf(value * 10.0) / 10.0)


static func _committed_failure(message: String, committed: bool, errors: Array[String]) -> Dictionary:
	return CombatPortsScript.fail(
		"%s (%s)%s" % [message, "state committed" if committed else "no state committed", _error_suffix(errors)]
	)


static func _after_commit_failure(message: String, result: Dictionary, committed: bool) -> Dictionary:
	return CombatPortsScript.fail(
		"%s (%s): %s" % [message, "state committed" if committed else "no state committed", result["error"]]
	)


static func _error_suffix(errors: Array[String]) -> String:
	return "" if errors.is_empty() else ": %s" % errors[0]


static func _result_suffix(result: Dictionary) -> String:
	return "" if result.get("ok", false) else ": %s" % result.get("error", "unknown failure")


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message in source:
		destination.append(message)
