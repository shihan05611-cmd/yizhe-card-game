class_name PermanentGrowth
extends RefCounted

## Pure M2 Flame/Ning formulas and canonical permanent-growth request builders.
## SP payment, card use, action quotas, save settlement, and concrete handlers are
## intentionally outside this module.

const MAX_SAFE_INTEGER := 9007199254740991
const FLAME_PRACTICE_ID := "flamePractice"
const FLAME_ENCHANT_ID := "flameEnchant"
const FIST_MASTERY_ID := "fistMastery"
const FLAME_HERO_ID := 5
const FIST_HERO_ID := 6
const PERMANENT_GROWTH_HERO_EX_SKILLS := ["ascend", "burnEnchant", "fist"]


static func flame_investment_base_cost(
	completed_investments: Variant,
	errors: Array[String] = [],
) -> int:
	errors.clear()
	var count := _non_negative_safe_integer(
		completed_investments, "completed investments", errors
	)
	if not errors.is_empty():
		return 0
	if count <= 2:
		return 2
	if count <= 6:
		return 3
	return 4


static func fist_mastery_damage_up_rate(
	stacks: Variant,
	per_stack: Variant = 0.05,
	errors: Array[String] = [],
) -> float:
	errors.clear()
	var count := _non_negative_safe_integer(stacks, "fistMastery stacks", errors)
	if not _finite_number(per_stack) or float(per_stack) < 0.0:
		errors.append("fistMastery per_stack must be finite and non-negative")
	if not errors.is_empty():
		return 0.0
	var result := float(count) * float(per_stack)
	if not is_finite(result):
		errors.append("fistMastery damage rate overflowed")
		return 0.0
	return result


static func fist_mastery_ultimate_bonus_hits(
	stacks: Variant,
	errors: Array[String] = [],
) -> int:
	errors.clear()
	var count := _non_negative_safe_integer(stacks, "fistMastery stacks", errors)
	return 0 if not errors.is_empty() else count / 5


static func fist_momentum_effects(momentum: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if typeof(momentum) != TYPE_INT or momentum < 0 or momentum > 5:
		errors.append("fist momentum must be an integer from 0 through 5")
		return {}
	var extra_targets := 2 if momentum >= 4 else (1 if momentum >= 2 else 0)
	return {
		"momentum": momentum,
		"damage_up_rate": float(momentum) * 0.15,
		"crit_rate_up": float(momentum) * 0.04,
		"extra_targets": extra_targets,
		"target_count": 1 + extra_targets,
		"ultimate_hits": 3 + momentum,
	}


static func flame_investment_plan(
	allies: Variant,
	ratios: Variant,
	completed_investments: Variant,
	used_this_battle: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if typeof(allies) != TYPE_ARRAY:
		errors.append("Flame allies must be an Array")
		return {}
	# Permanent Flame investment exists only when an active Run progress snapshot
	# supplied canonical per-slot ratios. Non-Run Flame remains a battle Buff rule.
	if typeof(ratios) != TYPE_DICTIONARY:
		errors.append("permanent Flame ratios must be an injected Dictionary")
		return {}
	if typeof(used_this_battle) != TYPE_BOOL:
		errors.append("used_this_battle must be a boolean")
		return {}
	var cost_errors: Array[String] = []
	var base_cost := flame_investment_base_cost(completed_investments, cost_errors)
	_append_errors(cost_errors, errors)
	if not errors.is_empty():
		return {}
	var eligible_slots: Array[int] = []
	var seen_slots := {}
	for index in allies.size():
		var unit: Variant = allies[index]
		var path := "Flame allies[%d]" % index
		if typeof(unit) != TYPE_DICTIONARY:
			errors.append("%s must be a Dictionary" % path)
			return {}
		for field in ["slot", "side", "alive", "is_puppet"]:
			if not unit.has(field):
				errors.append("%s.%s is required" % [path, field])
				return {}
		if typeof(unit["slot"]) != TYPE_INT or unit["slot"] < 1 or unit["slot"] > 6:
			errors.append("%s.slot must be an integer from 1 through 6" % path)
			return {}
		if seen_slots.has(unit["slot"]):
			errors.append("Flame allies contains duplicate slot: %d" % unit["slot"])
			return {}
		seen_slots[unit["slot"]] = true
		if unit["side"] not in ["ally", "enemy"]:
			errors.append("%s.side must be ally or enemy" % path)
			return {}
		if typeof(unit["alive"]) != TYPE_BOOL or typeof(unit["is_puppet"]) != TYPE_BOOL:
			errors.append("%s alive and is_puppet must be booleans" % path)
			return {}
		if unit["side"] != "ally" or not unit["alive"] or unit["is_puppet"]:
			continue
		if not ratios.has(unit["slot"]) or not _rate(ratios[unit["slot"]], "Flame ratios[%d]" % unit["slot"], errors):
			return {}
		if float(ratios[unit["slot"]]) <= 0.0:
			continue
		eligible_slots.append(unit["slot"])
	eligible_slots.sort()
	if used_this_battle:
		return {
			"available": false, "reason": "used_this_battle", "base_cost": base_cost,
			"eligible_slots": eligible_slots, "requests": [],
		}
	if eligible_slots.is_empty():
		return {
			"available": false, "reason": "no_eligible_slots", "base_cost": base_cost,
			"eligible_slots": [], "requests": [],
		}
	var requests: Array[Dictionary] = [{
		"id": FLAME_PRACTICE_ID,
		"target": {"type": "hero", "id": FLAME_HERO_ID},
		"stacks": 1,
	}]
	for slot in eligible_slots:
		requests.append({
			"id": FLAME_ENCHANT_ID,
			"target": {"type": "pieceSlot", "id": slot},
			"stacks": 1,
		})
	return {
		"available": true, "reason": null, "base_cost": base_cost,
		"eligible_slots": eligible_slots, "requests": requests,
	}


static func fist_growth_plan(
	momentum: Variant,
	mastery_stacks: Variant,
	per_stack: Variant = 0.05,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	var effects_errors: Array[String] = []
	var effects := fist_momentum_effects(momentum, effects_errors)
	_append_errors(effects_errors, errors)
	var count := _non_negative_safe_integer(mastery_stacks, "fistMastery stacks", errors)
	if count == MAX_SAFE_INTEGER:
		errors.append("fistMastery cannot grow beyond the maximum safe integer")
	var rate_errors: Array[String] = []
	var mastery_rate := fist_mastery_damage_up_rate(count, per_stack, rate_errors)
	_append_errors(rate_errors, errors)
	if not errors.is_empty():
		return {}
	return {
		"momentum_effects": effects,
		"mastery_damage_up_rate": mastery_rate,
		"mastery_before_stacks": count,
		"mastery_after_stacks": count + 1,
		"next_momentum": mini(5, momentum + 1),
		"request": {
			"id": FIST_MASTERY_ID,
			"target": {"type": "hero", "id": FIST_HERO_ID},
			"stacks": 1,
		},
	}


static func _rate(value: Variant, path: String, errors: Array[String]) -> bool:
	if _finite_number(value) and float(value) >= 0.0 and float(value) <= 1.0:
		return true
	errors.append("%s must be a finite rate from 0 through 1" % path)
	return false


static func _non_negative_safe_integer(value: Variant, path: String, errors: Array[String]) -> int:
	if typeof(value) == TYPE_INT and value >= 0 and value <= MAX_SAFE_INTEGER:
		return value
	errors.append("%s must be a non-negative safe integer" % path)
	return 0


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message in source:
		destination.append(message)
