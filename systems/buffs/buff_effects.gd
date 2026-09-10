class_name BuffEffects
extends RefCounted

const TEMP_BLOCK_ID := "tempBlock"
const PIECE_DAMAGE_UP_ID := "pieceDamageUp"
const VEXED_ID := "vexed"
const BLOOD_SHIFT_VULNERABLE_ID := "bloodShiftVulnerable"
const BLOOD_SHIFT_GUARD_ID := "bloodShiftGuard"
const BREAK_MARKED_ID := "breakMarked"
const BREAK_FORMATION_ID := "breakFormation"


static func effective_block_rate(
	target: Dictionary,
	buffs: Variant,
	tuning: Dictionary,
) -> float:
	var result := maxf(0.0, float(target.get("base_block_rate", 0.0)))
	if buffs != null and buffs.has_side(str(target.get("side", "")), TEMP_BLOCK_ID):
		result += _tuning(tuning, "tempBlockBonus", 0.15)
	return maxf(0.0, result)


static func damage_multiplier(
	target: Dictionary,
	damage_context: Dictionary,
	metadata: Dictionary,
	buffs: Variant,
	tuning: Dictionary,
) -> float:
	if buffs == null:
		return 1.0
	if damage_context.get("category") != "direct":
		return 1.0
	var result := 1.0
	var attacker: Variant = metadata.get("attacker_unit")
	var source_side := ""
	if typeof(attacker) == TYPE_DICTIONARY:
		source_side = str(attacker.get("side", ""))
	else:
		source_side = str(damage_context.get("effect", {}).get("source_side", ""))

	if damage_context.get("dealer_type") == "piece" and buffs.has_side(source_side, PIECE_DAMAGE_UP_ID):
		result *= 1.0 + _tuning(tuning, "pieceDamageUpRatio", 0.25)
	if typeof(attacker) == TYPE_DICTIONARY:
		if buffs.has_unit(attacker, VEXED_ID):
			result *= 1.0 - _tuning(tuning, "vexedDamageDownRatio", 0.25)
		result *= 1.0 + maxf(0.0, float(attacker.get("echo_damage_bonus", 0.0)))
	if buffs.has_side(source_side, BREAK_FORMATION_ID):
		result *= 1.0 + _tuning(tuning, "breakFormationDamageUpRatio", 0.25)

	if buffs.has_unit(target, BLOOD_SHIFT_VULNERABLE_ID):
		result *= 1.0 + _tuning(tuning, "bloodShiftVulnerableRatio", 0.25)
	if buffs.has_unit(target, BLOOD_SHIFT_GUARD_ID):
		result *= 1.0 - _tuning(tuning, "bloodShiftGuardRatio", 0.25)
	if buffs.has_unit(target, BREAK_MARKED_ID):
		result *= 1.0 + _tuning(tuning, "breakMarkedDamageUpRatio", 0.25)
	return maxf(0.0, result)


static func _tuning(catalog: Dictionary, id: String, fallback: float) -> float:
	var definition: Variant = catalog.get(id)
	if definition is Resource and typeof(definition.get("value")) in [TYPE_INT, TYPE_FLOAT]:
		return maxf(0.0, float(definition.value))
	return fallback
