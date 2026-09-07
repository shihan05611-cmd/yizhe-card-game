class_name HeroEffectsSiegePuppetShadow
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const StatsScript = preload("res://core/stats.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const TargetingRulesScript = preload("res://systems/targeting/targeting_rules.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")

## M2-only Siege, Puppet and Shadow effects. Payment, cards, hero action
## quotas, energy mutation, round advancement and presentation events are absent.
## Runtime service failures use sequential-commit semantics and never pretend to
## roll back damage or Buff mutations that an injected service already committed.

const EX_SIEGE := "battle.castExclusiveSkill.siege"
const EX_PUPPET := "battle.castExclusiveSkill.puppet"
const EX_SHADOW := "battle.castExclusiveSkill.shadow"
const ULT_SIEGE := "battle.castUltimateByHero.siege"
const ULT_PUPPET := "battle.castUltimateByHero.puppet"
const ULT_SHADOW := "battle.castUltimateByHero.shadow"

const CONTEXT_REQUIRED_KEYS := ["state", "caster", "source_effect"]
const CONTEXT_OPTIONAL_KEYS := ["growth_piece_ratios"]
const EFFECT_CONTEXT_KEYS := [
	"source_type", "source_id", "source_name", "source_side", "source_actor_id",
	"counts_as_skill_cast", "spent_skill_points", "free_cast",
	"counts_as_basic_attack", "counts_as_attack", "triggers_enemy_kill_effects",
]
const BREAK_MARKED_ID := "breakMarked"
const BREAK_FORMATION_ID := "breakFormation"
const STEALTH_ID := "stealth"
const PUPPET_HP := 100.0


static func handler_map() -> Dictionary:
	return {
		EX_SIEGE: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("siege", false, context, ports),
		EX_PUPPET: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("puppet", false, context, ports),
		EX_SHADOW: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("shadow", false, context, ports),
		ULT_SIEGE: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("siege", true, context, ports),
		ULT_PUPPET: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("puppet", true, context, ports),
		ULT_SHADOW: func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("shadow", true, context, ports),
	}


static func is_usable(
	skill_id: Variant,
	is_ultimate: Variant,
	context: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if skill_id not in ["siege", "puppet", "shadow"]:
		errors.append("unknown Siege/Puppet/Shadow hero skill id: %s" % str(skill_id))
		return false
	if typeof(is_ultimate) != TYPE_BOOL:
		errors.append("is_ultimate must be a boolean")
		return false
	if not _validate_context(String(skill_id), is_ultimate, context, ports, errors):
		return false
	return _is_usable_validated(String(skill_id), is_ultimate, context, ports, errors)


static func _execute(
	skill_id: String,
	is_ultimate: bool,
	context: Dictionary,
	ports: Variant,
) -> Dictionary:
	var errors: Array[String] = []
	if not _validate_context(skill_id, is_ultimate, context, ports, errors):
		return CombatPortsScript.fail(errors[0] if not errors.is_empty() else "invalid hero effect context")
	if not _is_usable_validated(skill_id, is_ultimate, context, ports, errors):
		return CombatPortsScript.fail(
			"%s %s is unusable%s" % [
				"ultimate" if is_ultimate else "exclusive", skill_id, _error_suffix(errors),
			]
		)
	if is_ultimate:
		match skill_id:
			"siege":
				return _siege_ultimate(context, ports)
			"puppet":
				return _puppet_ultimate(context, ports)
			"shadow":
				return _shadow_ultimate(context, ports)
	else:
		match skill_id:
			"siege":
				return _siege_exclusive(context, ports)
			"puppet":
				return _puppet_exclusive(context, ports)
			"shadow":
				return _shadow_exclusive(context, ports)
	return CombatPortsScript.fail("unreachable Siege/Puppet/Shadow hero effect branch")


static func _is_usable_validated(
	skill_id: String,
	is_ultimate: bool,
	context: Dictionary,
	ports: Variant,
	errors: Array[String],
) -> bool:
	if is_ultimate:
		# Web consumes all three ultimates even when they resolve a no-target/no-slot
		# no-op. Their handlers therefore remain usable in those states.
		return true
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	if skill_id == "siege":
		var opposing := _other_side(side)
		var lockable := TargetingRulesScript.lockable(state, opposing, errors)
		if not errors.is_empty():
			return false
		# Player Web treats an already-wiped opposing team as the successful
		# post-damage early-return case; all-living-stealthed is still unusable.
		return not lockable.is_empty() or TargetingRulesScript.alive(state, opposing, errors).is_empty()
	if skill_id == "puppet":
		return _dead_slots(state, side).size() > 0
	if skill_id == "shadow":
		var buffs: Variant = ports.service("buffs", errors)
		if not errors.is_empty() or not _preflight_unit_buff(buffs, _team(state, side), STEALTH_ID, errors):
			return false
		var non_puppets := _alive_non_puppets(state, side)
		var stealth_count := 0
		var eligible := false
		for unit: Dictionary in non_puppets:
			if buffs.has_unit(unit, STEALTH_ID):
				stealth_count += 1
			else:
				eligible = true
		return eligible and stealth_count < maxi(0, non_puppets.size() - 1)
	return false


static func _siege_exclusive(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var opposing := _other_side(side)
	var errors: Array[String] = []
	var lockable := TargetingRulesScript.lockable(state, opposing, errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("siege target preflight failed%s" % _error_suffix(errors))
	if lockable.is_empty():
		if not TargetingRulesScript.alive(state, opposing, errors).is_empty():
			return CombatPortsScript.fail("siege exclusive has no lockable target")
		var empty_log := _log(context, ports, "释放破势，但敌方已无存活目标。")
		if not empty_log["ok"]:
			return _after_commit_failure("siege empty-team log failed", empty_log, false)
		return CombatPortsScript.ok({
			"skill_id": "siege", "ultimate": false, "committed": false,
			"no_target": true, "target_id": null, "dealt": 0.0, "marked": false,
		})
	var buffs: Variant = ports.service("buffs", errors)
	if not _preflight_unit_buff(buffs, _team(state, opposing), BREAK_MARKED_ID, errors):
		return CombatPortsScript.fail("siege break-mark preflight failed%s" % _error_suffix(errors))
	if buffs.definition_for(BREAK_FORMATION_ID, "side", errors) == null or not buffs.validate_side_state(errors):
		return CombatPortsScript.fail("siege field preflight failed%s" % _error_suffix(errors))
	var unmarked: Array = lockable.filter(
		func(unit: Dictionary) -> bool: return not buffs.has_unit(unit, BREAK_MARKED_ID)
	)
	var pool: Array = unmarked if not unmarked.is_empty() else lockable
	var rng: Variant = ports.service("combat_rng", errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("siege RNG preflight failed%s" % _error_suffix(errors))
	var target: Variant = _random_pick(pool, rng, errors)
	if target == null or not errors.is_empty():
		return CombatPortsScript.fail("siege target draw failed%s" % _error_suffix(errors))
	var crit_rate := float(context["caster"]["base_crit_rate"])
	if buffs.has_side(side, BREAK_FORMATION_ID) and buffs.has_unit(target, BREAK_MARKED_ID):
		crit_rate += 0.2
	var damage_context := _damage_context(
		context, target, _fmt(StatsScript.team_average_atk(state, side) * 0.8),
		crit_rate, false, "破势", errors,
	)
	var damage: Variant = ports.service("damage", errors)
	if not errors.is_empty() or damage_context.is_empty() or damage == null or damage.is_valid() != true:
		return CombatPortsScript.fail("siege damage preflight failed%s" % _error_suffix(errors))
	var before_hp := float(target["hp"])
	var before_alive := bool(target["alive"])
	var result: Variant = damage.apply(target, damage_context, {}, errors)
	if not _valid_damage_result(result):
		if errors.is_empty():
			errors.append("damage service returned a non-canonical result")
		return _committed_failure(
			"siege damage failed", float(target["hp"]) != before_hp or bool(target["alive"]) != before_alive, errors,
		)
	var marked := false
	if target["alive"] and not buffs.has_unit(target, BREAK_MARKED_ID):
		if not buffs.apply_unit(target, BREAK_MARKED_ID, 1, null, errors):
			return _committed_failure("siege break mark failed", true, errors)
		marked = true
	var logged := _log(context, ports, "释放破势。")
	if not logged["ok"]:
		return _after_commit_failure("siege log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "siege", "ultimate": false, "committed": true,
		"no_target": false, "target_id": target["id"],
		"dealt": result["dealt"], "marked": marked,
	})


static func _siege_ultimate(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var targets := TargetingRulesScript.alive(state, _other_side(side))
	var errors: Array[String] = []
	var buffs: Variant = ports.service("buffs", errors)
	if (
		not errors.is_empty()
		or not _preflight_unit_buff(buffs, _team(state, _other_side(side)), BREAK_MARKED_ID, errors)
		or buffs.definition_for(BREAK_FORMATION_ID, "side", errors) == null
		or not buffs.validate_side_state(errors)
	):
		return CombatPortsScript.fail("siege ultimate Buff preflight failed%s" % _error_suffix(errors))
	var tuning: Variant = ports.service("tuning", errors)
	var turns := _tuning_integer(tuning, "ultBreakFormationTurns", errors)
	if turns <= 0:
		errors.append("ultBreakFormationTurns must be positive")
	if not errors.is_empty():
		return CombatPortsScript.fail("siege ultimate tuning preflight failed%s" % _error_suffix(errors))
	var marked := 0
	for target: Dictionary in targets:
		if not buffs.apply_unit(target, BREAK_MARKED_ID, 1, null, errors):
			return _committed_failure("siege ultimate target Buff failed", marked > 0, errors)
		marked += 1
	if not buffs.apply_side(side, BREAK_FORMATION_ID, 1, turns, errors):
		return _committed_failure("siege ultimate side Buff failed", marked > 0, errors)
	var logged := _log(context, ports, "释放摧城令。")
	if not logged["ok"]:
		return _after_commit_failure("siege ultimate log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "siege", "ultimate": true, "committed": true,
		"marked_target_ids": targets.map(func(unit: Dictionary) -> Variant: return unit["id"]),
		"turns": turns,
	})


static func _puppet_exclusive(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var dead := _dead_slots(state, side)
	if dead.is_empty():
		return CombatPortsScript.fail("puppet exclusive requires an empty slot")
	var target: Dictionary = dead[0]
	var projected := _puppet_projection(
		target, side == "ally" and state["ally_puppet_martyr_active"],
	)
	var errors: Array[String] = []
	var buffs: Variant = ports.service("buffs", errors)
	if not _preflight_puppet_projection(state, side, {target["slot"]: projected}, buffs, errors):
		return CombatPortsScript.fail("puppet summon preflight failed%s" % _error_suffix(errors))
	if not buffs.reset_unit(target, errors):
		return _committed_failure("puppet Buff reset failed", false, errors)
	_copy_unit(projected, target)
	var logged := _log(context, ports, "释放机巧造物。")
	if not logged["ok"]:
		return _after_commit_failure("puppet exclusive log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "puppet", "ultimate": false, "committed": true,
		"summoned_slot": target["slot"], "summoned_id": target["id"],
		"puppet_martyr": target["puppet_martyr"],
	})


static func _puppet_ultimate(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var team := _team(state, side)
	var dead := _dead_slots(state, side)
	var projections := {}
	for target: Dictionary in dead:
		projections[target["slot"]] = _puppet_projection(target, false)
	var errors: Array[String] = []
	var buffs: Variant = ports.service("buffs", errors)
	if not _preflight_puppet_projection(state, side, projections, buffs, errors):
		return CombatPortsScript.fail("puppet ultimate preflight failed%s" % _error_suffix(errors))
	for unit: Dictionary in team:
		if unit["alive"] and unit["is_puppet"] and (
			float(unit["max_hp"]) != PUPPET_HP or float(unit["fixed_max_hp"]) != PUPPET_HP
		):
			return CombatPortsScript.fail("existing puppet must retain the canonical fixed 100 max HP")
	var summoned := 0
	for target: Dictionary in dead:
		if not buffs.reset_unit(target, errors):
			return _committed_failure("puppet ultimate Buff reset failed", summoned > 0, errors)
		_copy_unit(projections[target["slot"]], target)
		summoned += 1
	var puppet_ids: Array = []
	for unit: Dictionary in _sorted_by_slot(team):
		if not unit["alive"] or not unit["is_puppet"]:
			continue
		unit["hp"] = PUPPET_HP
		if side == "ally":
			unit["puppet_martyr"] = true
		puppet_ids.append(unit["id"])
	if side == "ally":
		state["ally_puppet_martyr_active"] = true
	var logged := _log(context, ports, "释放森罗万象。")
	if not logged["ok"]:
		return _after_commit_failure(
			"puppet ultimate log failed", logged,
			side == "ally" or summoned > 0 or not puppet_ids.is_empty(),
		)
	return CombatPortsScript.ok({
		"skill_id": "puppet", "ultimate": true,
		"committed": side == "ally" or summoned > 0 or not puppet_ids.is_empty(),
		"summoned_count": summoned, "puppet_ids": puppet_ids,
		"martyr_granted": side == "ally",
	})


static func _shadow_exclusive(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var errors: Array[String] = []
	var buffs: Variant = ports.service("buffs", errors)
	if not _preflight_unit_buff(buffs, _team(state, side), STEALTH_ID, errors):
		return CombatPortsScript.fail("shadow exclusive Buff preflight failed%s" % _error_suffix(errors))
	var candidates: Array = _alive_non_puppets(state, side).filter(
		func(unit: Dictionary) -> bool: return not buffs.has_unit(unit, STEALTH_ID)
	)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left["atk"]) != float(right["atk"]):
			return float(left["atk"]) > float(right["atk"])
		return _stable_id_less(left, right)
	)
	if candidates.is_empty():
		return CombatPortsScript.fail("shadow exclusive has no eligible unit")
	var target: Dictionary = candidates[0]
	if not buffs.apply_unit(target, STEALTH_ID, 1, 1, errors):
		return _committed_failure("shadow exclusive stealth failed", false, errors)
	target["stealth_attack_ready"] = true
	var logged := _log(context, ports, "释放潜影。")
	if not logged["ok"]:
		return _after_commit_failure("shadow exclusive log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "shadow", "ultimate": false, "committed": true,
		"target_id": target["id"], "target_slot": target["slot"],
		"stealth_turns": 1,
	})


static func _shadow_ultimate(context: Dictionary, ports: Variant) -> Dictionary:
	var state: Dictionary = context["state"]
	var side: String = context["source_effect"]["source_side"]
	var opposing := _other_side(side)
	var errors: Array[String] = []
	var target: Variant = TargetingRulesScript.lowest_hp_percent_lockable(state, opposing, errors)
	var buffs: Variant = ports.service("buffs", errors)
	if not _preflight_unit_buff(buffs, _team(state, side), STEALTH_ID, errors):
		return CombatPortsScript.fail("shadow ultimate Buff preflight failed%s" % _error_suffix(errors))
	var attackers: Array[Dictionary] = []
	for unit: Dictionary in _sorted_by_slot(_team(state, side)):
		if unit["alive"] and buffs.has_unit(unit, STEALTH_ID):
			attackers.append(unit)
	if target == null:
		var empty_log := _log(context, ports, "释放影·狩，但当前没有可锁定目标。")
		if not empty_log["ok"]:
			return _after_commit_failure("shadow ultimate no-target log failed", empty_log, false)
		return CombatPortsScript.ok({
			"skill_id": "shadow", "ultimate": true, "committed": false,
			"no_target": true, "target_id": null, "dealt": 0.0,
			"forced_crit": false,
			"pursuit_sequence": _pursuit_sequence(null, []),
		})
	var forced_crit := float(target["hp"]) <= float(target["max_hp"]) * 0.5
	var damage_context := _damage_context(
		context, target, _fmt(StatsScript.team_average_atk(state, side) * 4.0),
		1.0 if forced_crit else float(context["caster"]["base_crit_rate"]),
		false, "影·狩", errors,
	)
	var damage: Variant = ports.service("damage", errors)
	if not errors.is_empty() or damage_context.is_empty() or damage == null or damage.is_valid() != true:
		return CombatPortsScript.fail("shadow ultimate damage preflight failed%s" % _error_suffix(errors))
	var before_hp := float(target["hp"])
	var before_alive := bool(target["alive"])
	var result: Variant = damage.apply(target, damage_context, {}, errors)
	if not _valid_damage_result(result):
		if errors.is_empty():
			errors.append("damage service returned a non-canonical result")
		return _committed_failure(
			"shadow ultimate damage failed",
			float(target["hp"]) != before_hp or bool(target["alive"]) != before_alive,
			errors,
		)
	var pursuit_target: Variant = target if target["alive"] else TargetingRulesScript.lowest_hp_percent_lockable(state, opposing, errors)
	if not errors.is_empty():
		return _committed_failure("shadow pursuit target query failed", true, errors)
	var plans: Array = []
	if pursuit_target != null:
		for attacker: Dictionary in attackers:
			plans.append(_piece_attack_plan(context, attacker, pursuit_target))
	var logged := _log(context, ports, "释放影·狩。")
	if not logged["ok"]:
		return _after_commit_failure("shadow ultimate log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "shadow", "ultimate": true, "committed": true,
		"no_target": false, "target_id": target["id"], "dealt": result["dealt"],
		"forced_crit": forced_crit,
		"pursuit_sequence": _pursuit_sequence(pursuit_target, plans),
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
	var heroes: Array = (
		context["state"]["player_heroes"]
		if effect["source_side"] == "ally" else context["state"]["enemy_heroes"]
	)
	var canonical: Variant = null
	for hero: Dictionary in heroes:
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
		errors.append("Siege/Puppet/Shadow effects do not own permanent Run growth")
		return false
	return true


static func _damage_context(
	context: Dictionary,
	target: Dictionary,
	raw: float,
	crit_rate: float,
	guaranteed_crit: bool,
	source_name: String,
	errors: Array[String],
) -> Dictionary:
	return ContextsScript.create_damage_context({
		"target_id": target["id"], "raw_amount": raw,
		"category": ContextsScript.DAMAGE_CATEGORY["DIRECT"],
		"effect": ContextsScript.snapshot(context["source_effect"]),
		"dealer_type": "yizhe", "dealer_name": context["caster"]["name"],
		"dealer_id": context["caster"]["id"], "attacker_unit_id": 0,
		"can_crit": true, "crit_rate": crit_rate,
		"guaranteed_crit": guaranteed_crit, "can_block": true,
	}, errors)


static func _piece_attack_plan(
	context: Dictionary,
	attacker: Dictionary,
	target: Dictionary,
) -> Dictionary:
	return {
		"kind": "execute_piece_attack",
		"attacker_side": attacker["side"], "attacker_id": attacker["id"],
		"attacker_slot": attacker["slot"], "target_side": target["side"],
		"target_id": target["id"], "target_slot": target["slot"],
		"attack_name": "潜行追击", "damage_multiplier": 0.5,
		"trigger_extra_action": false, "trigger_pursuit": false,
		"damage_kind_override": "pursuit",
		"source_effect": ContextsScript.snapshot(context["source_effect"]),
	}


static func _pursuit_sequence(initial_target: Variant, plans: Array) -> Dictionary:
	return {
		"kind": "execute_piece_attack_sequence",
		"status": "pending_b4_execution",
		"initial_target_side": null if initial_target == null else initial_target["side"],
		"initial_target_id": null if initial_target == null else initial_target["id"],
		"initial_target_slot": null if initial_target == null else initial_target["slot"],
		"retarget_on_target_death": true,
		"retarget_policy": "lowest_hp_percent_lockable",
		"plans": plans,
	}


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


static func _preflight_puppet_projection(
	state: Dictionary,
	side: String,
	projections: Dictionary,
	buffs: Variant,
	errors: Array[String],
) -> bool:
	if buffs == null or buffs.is_valid() != true:
		errors.append("Buff service is unavailable")
		return false
	for unit: Dictionary in _team(state, side):
		if not buffs.validate_unit_holder(unit, errors):
			return false
	var projected_state: Dictionary = BattleStateScript.snapshot(state, errors)
	if not errors.is_empty() or projected_state.is_empty():
		return false
	for unit: Dictionary in _team(projected_state, side):
		if projections.has(unit["slot"]):
			_copy_unit(projections[unit["slot"]], unit)
	return BattleStateScript.validate(projected_state, errors)


static func _puppet_projection(unit: Dictionary, martyr: bool) -> Dictionary:
	return {
		"id": unit["id"], "slot": unit["slot"], "side": unit["side"],
		"class_id": "puppet", "class_name": "傀儡",
		"hp": PUPPET_HP, "max_hp": PUPPET_HP, "atk": 0.0, "crit_rate": 0.0,
		"alive": true, "general": false, "base_block_rate": 0.0,
		"extra_action_charges": 0, "buffs": [], "is_puppet": true,
		"fixed_max_hp": PUPPET_HP, "puppet_martyr": martyr,
		"disarm_turns": 0, "stealth_attack_ready": false, "special_id": null,
		"echo_damage_bonus": 0.0, "hp_threshold_crossed": false,
	}


static func _copy_unit(source: Dictionary, target: Dictionary) -> void:
	for key in BattleStateScript.UNIT_KEYS:
		target[key] = source[key].duplicate(true) if source[key] is Array or source[key] is Dictionary else source[key]


static func _dead_slots(state: Dictionary, side: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: Dictionary in _team(state, side):
		if not unit["alive"]:
			result.append(unit)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["slot"]) < int(right["slot"])
	)
	return result


static func _alive_non_puppets(state: Dictionary, side: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: Dictionary in _team(state, side):
		if unit["alive"] and not unit["is_puppet"]:
			result.append(unit)
	return result


static func _sorted_by_slot(team: Array) -> Array:
	var result := team.duplicate(false)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left["slot"]) != int(right["slot"]):
			return int(left["slot"]) < int(right["slot"])
		return _stable_id_less(left, right)
	)
	return result


static func _random_pick(pool: Array, rng: Variant, errors: Array[String]) -> Variant:
	if pool.is_empty():
		return null
	var index: Variant = rng.int_range(0, pool.size() - 1)
	if typeof(index) != TYPE_INT or index < 0 or index >= pool.size():
		errors.append("combat_rng.int_range returned an out-of-range index")
		return null
	return pool[index]


static func _tuning_integer(tuning: Variant, id: String, errors: Array[String]) -> int:
	if typeof(tuning) != TYPE_DICTIONARY:
		errors.append("tuning service must return a Dictionary")
		return 0
	var definition: Variant = tuning.get(id)
	if not definition is Resource or definition.get_script() != TuningValueDefinition:
		errors.append("tuning.%s must be a TuningValueDefinition" % id)
		return 0
	var value: Variant = definition.value
	if not _finite_number(value) or float(value) != floorf(float(value)):
		errors.append("tuning.%s.value must be a finite integer" % id)
		return 0
	return int(value)


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


static func _stable_id_less(left: Dictionary, right: Dictionary) -> bool:
	var left_id: Variant = left["id"]
	var right_id: Variant = right["id"]
	return left_id < right_id if typeof(left_id) == typeof(right_id) else typeof(left_id) < typeof(right_id)


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


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))
