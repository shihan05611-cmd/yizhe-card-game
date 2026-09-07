class_name FreeSkillEffects
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const StatsScript = preload("res://core/stats.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const TargetingRulesScript = preload("res://systems/targeting/targeting_rules.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")

## M2-only free-skill effect handlers. Payment, cards, cast events, hero action
## quotas, and kill-SP rewards belong to M3 and are deliberately absent.

const SKILL_IDS := [
	"burnStackBase", "burnDetonate", "executeStrike", "pieceAction",
	"pieceBlock", "pieceDamageUp", "pieceHealAll", "smallHeal", "markBurn",
	"bloodShift", "basicDamage",
]
const CONTEXT_KEYS := [
	"state", "caster_side", "caster_id", "caster_name",
	"caster_base_crit_rate", "source_effect",
]
const EFFECT_CONTEXT_KEYS := [
	"source_type", "source_id", "source_name", "source_side", "source_actor_id",
	"counts_as_skill_cast", "spent_skill_points", "free_cast",
	"counts_as_basic_attack", "counts_as_attack", "triggers_enemy_kill_effects",
]

const BURN_ID := "burn"
const TEMP_BLOCK_ID := "tempBlock"
const PIECE_DAMAGE_UP_ID := "pieceDamageUp"
const BLOOD_SHIFT_VULNERABLE_ID := "bloodShiftVulnerable"
const BLOOD_SHIFT_GUARD_ID := "bloodShiftGuard"


static func handler_map() -> Dictionary:
	return {
		_effect_id("burnStackBase"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("burnStackBase", context, ports),
		_effect_id("burnDetonate"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("burnDetonate", context, ports),
		_effect_id("executeStrike"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("executeStrike", context, ports),
		_effect_id("pieceAction"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("pieceAction", context, ports),
		_effect_id("pieceBlock"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("pieceBlock", context, ports),
		_effect_id("pieceDamageUp"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("pieceDamageUp", context, ports),
		_effect_id("pieceHealAll"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("pieceHealAll", context, ports),
		_effect_id("smallHeal"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("smallHeal", context, ports),
		_effect_id("markBurn"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("markBurn", context, ports),
		_effect_id("bloodShift"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("bloodShift", context, ports),
		_effect_id("basicDamage"): func(context: Dictionary, ports: Variant) -> Dictionary:
			return _execute("basicDamage", context, ports),
	}


static func is_usable(
	skill_id: Variant,
	context: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if skill_id not in SKILL_IDS:
		errors.append("unknown free skill id: %s" % str(skill_id))
		return false
	if not _validate_context(String(skill_id), context, ports, errors):
		return false
	return _is_usable_validated(String(skill_id), context, errors)


static func _execute(skill_id: String, context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _validate_context(skill_id, context, ports, errors):
		return CombatPortsScript.fail(errors[0] if not errors.is_empty() else "invalid free skill context")
	if not _is_usable_validated(skill_id, context, errors):
		return CombatPortsScript.fail("free skill %s is unusable" % skill_id)
	match skill_id:
		"burnStackBase":
			return _burn_stack_base(context, ports)
		"burnDetonate":
			return _burn_detonate(context, ports)
		"executeStrike":
			return _execute_strike_plan(context)
		"pieceAction":
			return _piece_action(context, ports)
		"pieceBlock":
			return _side_buff(context, ports, "pieceBlock", TEMP_BLOCK_ID, "提升全体格挡率。")
		"pieceDamageUp":
			return _side_buff(context, ports, "pieceDamageUp", PIECE_DAMAGE_UP_ID, "提升棋子直接伤害。")
		"pieceHealAll":
			return _piece_heal_all(context, ports)
		"smallHeal":
			return _small_heal(context, ports)
		"markBurn":
			return _mark_burn(context, ports)
		"bloodShift":
			return _blood_shift(context, ports)
		"basicDamage":
			return _basic_damage(context, ports)
	return CombatPortsScript.fail("unknown free skill id: %s" % skill_id)


static func _is_usable_validated(skill_id: String, context: Dictionary, errors: Array[String]) -> bool:
	var state: Dictionary = context["state"]
	var friendly_side: String = context["caster_side"]
	var opposing_side := _other_side(friendly_side)
	match skill_id:
		"burnStackBase", "pieceBlock", "pieceDamageUp":
			return true
		"burnDetonate":
			return TargetingRulesScript.burn_detonate_target(state, opposing_side, errors) != null
		"executeStrike":
			return (
				TargetingRulesScript.highest_atk_alive(state, friendly_side, errors) != null
				and TargetingRulesScript.lowest_current_hp_lockable(state, opposing_side, errors) != null
			)
		"pieceAction", "bloodShift":
			return not TargetingRulesScript.alive(state, friendly_side, errors).is_empty()
		"pieceHealAll", "smallHeal":
			for unit: Dictionary in TargetingRulesScript.alive(state, friendly_side, errors):
				if float(unit["hp"]) < float(unit["max_hp"]):
					return true
			return false
		"markBurn", "basicDamage":
			return not TargetingRulesScript.lockable(state, opposing_side, errors).is_empty()
	return false


static func _burn_stack_base(context: Dictionary, ports: Variant) -> Dictionary:
	var service_errors: Array[String] = []
	var tuning: Variant = ports.service("tuning", service_errors)
	if not service_errors.is_empty():
		return CombatPortsScript.fail("burnStackBase tuning unavailable: %s" % service_errors[0])
	var chance := _tuning_number(tuning, "burnBonusChance", service_errors)
	if not service_errors.is_empty() or chance < 0.0 or chance > 1.0:
		return CombatPortsScript.fail("burnBonusChance must be a finite rate from 0 through 1")
	var buffs: Variant = ports.service("buffs", service_errors)
	var rng: Variant = ports.service("combat_rng", service_errors)
	if not service_errors.is_empty():
		return CombatPortsScript.fail("burnStackBase services unavailable: %s" % service_errors[0])
	var targets := TargetingRulesScript.alive(context["state"], _other_side(context["caster_side"]))
	var applied := 0
	for target: Dictionary in targets:
		if not buffs.apply_unit(target, BURN_ID, 1, null, service_errors):
			return _committed_failure("burnStackBase base burn failed", applied > 0, service_errors)
		applied += 1
		var roll: Variant = rng.next()
		if not _finite_number(roll) or float(roll) < 0.0 or float(roll) >= 1.0:
			return _committed_failure(
				"burnStackBase combat_rng.next must return a finite value in [0, 1)",
				true,
				[],
			)
		if float(roll) < chance:
			if not buffs.apply_unit(target, BURN_ID, 1, null, service_errors):
				return _committed_failure("burnStackBase bonus burn failed", true, service_errors)
			applied += 1
	var logged := _log(context, ports, "释放基础叠层：敌方全体获得灼烧。")
	if not logged["ok"]:
		return _after_commit_failure("burnStackBase log failed", logged, applied > 0)
	return CombatPortsScript.ok({"skill_id": "burnStackBase", "committed": applied > 0, "applied_stacks": applied})


static func _burn_detonate(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var target: Variant = TargetingRulesScript.burn_detonate_target(
		context["state"], _other_side(context["caster_side"]), errors,
	)
	if target == null:
		return CombatPortsScript.fail("free skill burnDetonate is unusable")
	var buffs: Variant = ports.service("buffs", errors)
	var tuning: Variant = ports.service("tuning", errors)
	var damage: Variant = ports.service("damage", errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("burnDetonate services unavailable: %s" % errors[0])
	var per_stack := _tuning_number(tuning, "burnDetonatePerStack", errors)
	if not errors.is_empty() or per_stack < 0.0:
		return CombatPortsScript.fail("burnDetonatePerStack must be a non-negative finite number")
	var stacks: int = buffs.get_unit_stacks(target, BURN_ID)
	var damage_context := _damage_context(
		context, target, float(stacks) * per_stack, "灼烧引爆", errors,
	)
	if not errors.is_empty():
		return CombatPortsScript.fail(errors[0])
	var result: Variant = damage.apply(target, damage_context, {}, errors)
	if not _valid_damage_result(result):
		return CombatPortsScript.fail(
			"burnDetonate damage failed before commit%s" % _error_suffix(errors)
		)
	if not buffs.clear_unit(target, BURN_ID, errors):
		return _committed_failure("burnDetonate clear burn failed", true, errors)
	var spread := 0
	if result["died"] and stacks > 0:
		var remaining := TargetingRulesScript.alive(
			context["state"], _other_side(context["caster_side"]), errors,
		)
		if not remaining.is_empty():
			var average: int = floori(float(stacks) / float(remaining.size()))
			var remainder := stacks % remaining.size()
			for unit: Dictionary in remaining:
				var plus: int = average + (1 if remainder > 0 else 0)
				if remainder > 0:
					remainder -= 1
				if plus > 0:
					if not buffs.apply_unit(unit, BURN_ID, plus, null, errors):
						return _committed_failure("burnDetonate spread failed", true, errors)
					spread += plus
	var logged := _log(context, ports, "引爆目标灼烧。")
	if not logged["ok"]:
		return _after_commit_failure("burnDetonate log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "burnDetonate", "committed": true, "target_id": target["id"],
		"stacks": stacks, "dealt": result["dealt"], "died": result["died"],
		"spread_stacks": spread,
	})


static func _execute_strike_plan(context: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var attacker: Variant = TargetingRulesScript.highest_atk_alive(
		context["state"], context["caster_side"], errors,
	)
	var target: Variant = TargetingRulesScript.lowest_current_hp_lockable(
		context["state"], _other_side(context["caster_side"]), errors,
	)
	if attacker == null or target == null:
		return CombatPortsScript.fail("free skill executeStrike is unusable")
	return CombatPortsScript.ok({
		"skill_id": "executeStrike",
		"committed": false,
		"plan": {
			"kind": "execute_piece_attack",
			"attacker_side": attacker["side"],
			"attacker_id": attacker["id"],
			"attacker_slot": attacker["slot"],
			"target_side": target["side"],
			"target_id": target["id"],
			"target_slot": target["slot"],
			"attack_name": "斩杀",
			"damage_multiplier": 1.5,
			"trigger_extra_action": false,
			"trigger_pursuit": false,
			"damage_kind_override": "execute",
			"source_effect": ContextsScript.snapshot(context["source_effect"]),
		},
	})


static func _piece_action(context: Dictionary, ports: Variant) -> Dictionary:
	var target: Variant = TargetingRulesScript.highest_atk_alive(
		context["state"], context["caster_side"],
	)
	if target == null:
		return CombatPortsScript.fail("free skill pieceAction is unusable")
	target["extra_action_charges"] += 1
	var logged := _log(context, ports, "令目标获得额外行动。")
	if not logged["ok"]:
		return _after_commit_failure("pieceAction log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "pieceAction", "committed": true,
		"target_id": target["id"], "extra_action_charges": target["extra_action_charges"],
	})


static func _side_buff(
	context: Dictionary,
	ports: Variant,
	skill_id: String,
	buff_id: String,
	message: String,
) -> Dictionary:
	var errors: Array[String] = []
	var buffs: Variant = ports.service("buffs", errors)
	if not errors.is_empty() or not buffs.apply_side(context["caster_side"], buff_id, 1, null, errors):
		return _committed_failure("%s side buff failed" % buff_id, false, errors)
	var logged := _log(context, ports, message)
	if not logged["ok"]:
		return _after_commit_failure("%s log failed" % buff_id, logged, true)
	return CombatPortsScript.ok({"skill_id": skill_id, "committed": true, "buff_id": buff_id})


static func _piece_heal_all(context: Dictionary, ports: Variant) -> Dictionary:
	var targets := TargetingRulesScript.alive(context["state"], context["caster_side"])
	var total := 0.0
	var healed_count := 0
	for target: Dictionary in targets:
		var healed := _heal_and_record(target, float(target["max_hp"]) * 0.05, "棋子回血", context, ports)
		if not healed["ok"]:
			# Zero-heal targets never call the port, so a record failure implies this
			# target was already healed before the external failure was observed.
			return _after_commit_failure("pieceHealAll record failed", healed, true)
		total += float(healed["value"])
		if float(healed["value"]) > 0.0:
			healed_count += 1
	var logged := _log(context, ports, "回复全体棋子生命。")
	if not logged["ok"]:
		return _after_commit_failure("pieceHealAll log failed", logged, total > 0.0)
	return CombatPortsScript.ok({
		"skill_id": "pieceHealAll", "committed": total > 0.0,
		"total_healed": total, "healed_count": healed_count,
	})


static func _small_heal(context: Dictionary, ports: Variant) -> Dictionary:
	var target: Variant = TargetingRulesScript.lowest_hp_percent_alive(
		context["state"], context["caster_side"],
	)
	if target == null:
		return CombatPortsScript.fail("free skill smallHeal is unusable")
	var healed := _heal_and_record(
		target, float(target["max_hp"]) * 0.05, "小回血", context, ports,
	)
	if not healed["ok"]:
		return _after_commit_failure("smallHeal record failed", healed, true)
	var logged := _log(context, ports, "为目标回复生命。")
	if not logged["ok"]:
		return _after_commit_failure("smallHeal log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "smallHeal", "committed": float(healed["value"]) > 0.0,
		"target_id": target["id"], "healed": healed["value"],
	})


static func _mark_burn(context: Dictionary, ports: Variant) -> Dictionary:
	var target: Variant = TargetingRulesScript.mark_burn_target(
		context["state"], _other_side(context["caster_side"]),
	)
	if target == null:
		return CombatPortsScript.fail("free skill markBurn is unusable")
	var errors: Array[String] = []
	var buffs: Variant = ports.service("buffs", errors)
	if not errors.is_empty() or not buffs.apply_unit(target, BURN_ID, 1, null, errors):
		return _committed_failure("markBurn apply failed", false, errors)
	var logged := _log(context, ports, "为目标添加灼痕。")
	if not logged["ok"]:
		return _after_commit_failure("markBurn log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "markBurn", "committed": true, "target_id": target["id"],
	})


static func _blood_shift(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var allies := TargetingRulesScript.alive(context["state"], context["caster_side"], errors)
	var anchor: Variant = TargetingRulesScript.highest_current_hp_alive(
		context["state"], context["caster_side"], errors,
	)
	if anchor == null:
		return CombatPortsScript.fail("free skill bloodShift is unusable")
	var buffs: Variant = ports.service("buffs", errors)
	if not errors.is_empty() or not buffs.apply_unit(anchor, BLOOD_SHIFT_VULNERABLE_ID, 1, null, errors):
		return _committed_failure("bloodShift anchor buff failed", false, errors)
	var applied := 1
	for unit: Dictionary in allies:
		if unit["id"] == anchor["id"]:
			continue
		if not buffs.apply_unit(unit, BLOOD_SHIFT_GUARD_ID, 1, null, errors):
			return _committed_failure("bloodShift guard buff failed", true, errors)
		applied += 1
	var logged := _log(context, ports, "施放血移。")
	if not logged["ok"]:
		return _after_commit_failure("bloodShift log failed", logged, true)
	return CombatPortsScript.ok({
		"skill_id": "bloodShift", "committed": true,
		"anchor_id": anchor["id"], "applied_buffs": applied,
	})


static func _basic_damage(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var target: Variant = TargetingRulesScript.lowest_hp_percent_lockable_by_id(
		context["state"], _other_side(context["caster_side"]), errors,
	)
	if target == null:
		return CombatPortsScript.fail("free skill basicDamage is unusable")
	var amount := StatsScript.team_average_atk(context["state"], context["caster_side"]) * 2.0
	var damage_context := _damage_context(context, target, amount, "基础伤害", errors)
	if not errors.is_empty():
		return CombatPortsScript.fail(errors[0])
	var damage: Variant = ports.service("damage", errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("basicDamage service unavailable: %s" % errors[0])
	var result: Variant = damage.apply(target, damage_context, {}, errors)
	if not _valid_damage_result(result):
		return CombatPortsScript.fail("basicDamage damage failed before commit%s" % _error_suffix(errors))
	var logged := _log(context, ports, "对目标造成基础伤害。")
	if not logged["ok"]:
		return _after_commit_failure("basicDamage log failed", logged, float(result["dealt"]) > 0.0)
	return CombatPortsScript.ok({
		"skill_id": "basicDamage", "committed": float(result["dealt"]) > 0.0,
		"target_id": target["id"], "raw_amount": amount, "dealt": result["dealt"],
		"died": result["died"],
	})


static func _heal_and_record(
	target: Dictionary,
	amount: float,
	source_name: String,
	context: Dictionary,
	ports: Variant,
) -> Dictionary:
	var old_hp := float(target["hp"])
	var new_hp := minf(float(target["max_hp"]), old_hp + maxf(0.0, amount))
	var healed := new_hp - old_hp
	target["hp"] = new_hp
	if healed <= 0.0:
		return CombatPortsScript.ok(0.0)
	var recorded: Dictionary = ports.call_action("record_heal", {
		"target_id": target["id"],
		"target_side": target["side"],
		"amount": healed,
		"source_name": source_name,
		"source_effect": ContextsScript.snapshot(context["source_effect"]),
		"old_hp": old_hp,
		"new_hp": new_hp,
	})
	if not recorded["ok"]:
		return recorded
	return CombatPortsScript.ok(healed)


static func _damage_context(
	context: Dictionary,
	target: Dictionary,
	raw_amount: float,
	source_name: String,
	errors: Array[String],
) -> Dictionary:
	return ContextsScript.create_damage_context({
		"target_id": target["id"],
		"raw_amount": raw_amount,
		"category": ContextsScript.DAMAGE_CATEGORY["DIRECT"],
		"effect": ContextsScript.snapshot(context["source_effect"]),
		"dealer_type": "free_skill",
		"dealer_name": context["caster_name"],
		"dealer_id": context["caster_id"],
		"attacker_unit_id": 0,
		"can_crit": true,
		"crit_rate": context["caster_base_crit_rate"],
		"guaranteed_crit": false,
		"can_block": true,
	}, errors)


static func _log(context: Dictionary, ports: Variant, message: String) -> Dictionary:
	return ports.call_action("log", {
		"message": "%s%s" % [context["caster_name"], message],
		"class": "ok" if context["caster_side"] == "ally" else "bad",
		"source_effect": ContextsScript.snapshot(context["source_effect"]),
	})


static func _validate_context(
	skill_id: String,
	context: Variant,
	ports: Variant,
	errors: Array[String],
) -> bool:
	if not _closed_dictionary(context, CONTEXT_KEYS, "free skill context", errors):
		return false
	if (
		typeof(ports) != TYPE_OBJECT
		or ports == null
		or ports.get_script() != CombatPortsScript
		or ports.is_valid() != true
	):
		errors.append("free skill execution requires valid CombatPorts")
		return false
	if context["caster_side"] not in ["ally", "enemy"]:
		errors.append("free skill context.caster_side must be ally or enemy")
		return false
	if not _stable_id(context["caster_id"]):
		errors.append("free skill context.caster_id must be a stable id")
		return false
	if typeof(context["caster_name"]) != TYPE_STRING or context["caster_name"].strip_edges().is_empty():
		errors.append("free skill context.caster_name must be a non-empty string")
		return false
	if not _finite_number(context["caster_base_crit_rate"]) or float(context["caster_base_crit_rate"]) < 0.0:
		errors.append("free skill context.caster_base_crit_rate must be non-negative and finite")
		return false
	var state_errors: Array[String] = []
	if not BattleStateScript.validate(context["state"], state_errors):
		errors.append("free skill context.state is non-canonical: %s" % state_errors[0])
		return false
	var effect: Variant = context["source_effect"]
	if not _closed_dictionary(effect, EFFECT_CONTEXT_KEYS, "free skill source_effect", errors):
		return false
	for key in [
		"counts_as_skill_cast", "spent_skill_points", "free_cast",
		"counts_as_basic_attack", "counts_as_attack", "triggers_enemy_kill_effects",
	]:
		if typeof(effect[key]) != TYPE_BOOL:
			errors.append("free skill source_effect.%s must be a boolean" % key)
			return false
	var normalized_errors: Array[String] = []
	var normalized := ContextsScript.create_effect_context(effect, normalized_errors)
	if not normalized_errors.is_empty() or normalized != effect:
		errors.append("free skill source_effect must be canonical")
		return false
	if effect["source_type"] != ContextsScript.EFFECT_SOURCE_TYPE["FREE_SKILL"]:
		errors.append("free skill source_effect.source_type must be free_skill")
		return false
	if effect["source_id"] != skill_id:
		errors.append("free skill source_effect.source_id must match handler id")
		return false
	if effect["source_side"] != context["caster_side"] or effect["source_actor_id"] != context["caster_id"]:
		errors.append("free skill source_effect caster identity mismatch")
		return false
	if effect["counts_as_skill_cast"] != true:
		errors.append("free skill source_effect must count as a skill cast")
		return false
	return true


static func _closed_dictionary(
	value: Variant,
	keys: Array,
	label: String,
	errors: Array[String],
) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		errors.append("%s must have a canonical closed shape" % label)
		return false
	for key in keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [label, key])
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			errors.append("%s contains an unknown field" % label)
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
		_finite_number(result["dealt"])
		and float(result["dealt"]) >= 0.0
		and typeof(result["blocked"]) == TYPE_BOOL
		and typeof(result["died"]) == TYPE_BOOL
		and typeof(result["crit"]) == TYPE_BOOL
		and typeof(result["damage_context"]) == TYPE_DICTIONARY
		and (result["death_context"] == null or typeof(result["death_context"]) == TYPE_DICTIONARY)
	)


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


static func _committed_failure(
	message: String,
	committed: bool,
	errors: Array[String],
) -> Dictionary:
	return CombatPortsScript.fail(
		"%s (%s)%s" % [message, "state committed" if committed else "no state committed", _error_suffix(errors)]
	)


static func _after_commit_failure(
	message: String,
	result: Dictionary,
	committed: bool,
) -> Dictionary:
	return CombatPortsScript.fail(
		"%s (%s): %s" % [
			message, "state committed" if committed else "no state committed", result["error"],
		]
	)


static func _error_suffix(errors: Array[String]) -> String:
	return "" if errors.is_empty() else ": %s" % errors[0]


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _stable_id(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT and value > 0)
		or (
			typeof(value) == TYPE_STRING
			and value == value.strip_edges()
			and not value.is_empty()
		)
	)


static func _other_side(side: String) -> String:
	return "enemy" if side == "ally" else "ally"


static func _effect_id(skill_id: String) -> String:
	return "free_skill.%s.effect" % skill_id
