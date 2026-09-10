class_name MarshalGrowth
extends RefCounted

## Pure M2 Marshal growth rules. This module never pays SP, writes a save, or
## mutates the supplied battle state. Concrete skill/death handlers consume the
## returned projections and permanent-Buff requests in later B3 batches.

const BUFF_ID := "marshalPromotion"
const MAX_SAFE_INTEGER := 9007199254740991
const RATE_CAP := 0.95
const DEFAULTS := {
	"first_atk": 0.0,
	"first_max_hp": 80.0,
	"first_block": 0.1,
	"first_crit": 0.05,
	"repeat_atk": 3.0,
	"repeat_block": 0.03,
	"repeat_crit": 0.03,
	"repeat_missing_hp_heal_ratio": 0.05,
}


static func promotion_bonuses(
	stacks: Variant,
	tuning: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	var count := _non_negative_safe_integer(stacks, "marshalPromotion stacks", errors)
	var values := _tuning_values(tuning, errors)
	if not errors.is_empty():
		return {}
	if count == 0:
		return {"atk": 0.0, "max_hp": 0.0, "block": 0.0, "crit": 0.0}
	return {
		"atk": values["first_atk"] + float(count - 1) * values["repeat_atk"],
		"max_hp": values["first_max_hp"],
		"block": minf(RATE_CAP, values["first_block"] + float(count - 1) * values["repeat_block"]),
		"crit": minf(RATE_CAP, values["first_crit"] + float(count - 1) * values["repeat_crit"]),
	}


static func promotion_delta(
	before: Variant,
	after: Variant,
	tuning: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	var from := _non_negative_safe_integer(before, "marshalPromotion before", errors)
	var to := _non_negative_safe_integer(after, "marshalPromotion after", errors)
	var values := _tuning_values(tuning, errors)
	if not errors.is_empty():
		return {}
	if from == MAX_SAFE_INTEGER or to != from + 1:
		errors.append("marshalPromotion delta must add exactly one safe stack")
		return {}
	return {
		"atk": values["first_atk"] if from == 0 else values["repeat_atk"],
		"max_hp": values["first_max_hp"] if from == 0 else 0.0,
		"block": values["first_block"] if from == 0 else values["repeat_block"],
		"crit": values["first_crit"] if from == 0 else values["repeat_crit"],
	}


static func promotion_request(slot: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _slot(slot, "marshal target slot", errors):
		return {}
	return {
		"id": BUFF_ID,
		"target": {"type": "pieceSlot", "id": slot},
		"stacks": 1,
	}


static func promotion_plan(
	slot: Variant,
	before: Variant,
	tuning: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	var request_errors: Array[String] = []
	var request := promotion_request(slot, request_errors)
	_append_errors(request_errors, errors)
	var count := _non_negative_safe_integer(before, "marshalPromotion before", errors)
	if count == MAX_SAFE_INTEGER:
		errors.append("marshalPromotion cannot grow beyond the maximum safe integer")
	if not errors.is_empty():
		return {}
	var delta_errors: Array[String] = []
	var delta := promotion_delta(count, count + 1, tuning, delta_errors)
	_append_errors(delta_errors, errors)
	if not errors.is_empty():
		return {}
	return {
		"slot": slot,
		"before_stacks": count,
		"after_stacks": count + 1,
		"request": request,
		"delta": delta,
	}


static func slot_ratios(snapshot: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _exact_dictionary(snapshot, ["piece_slots", "permanent_buffs"], "growth snapshot", errors):
		return {}
	var piece_slots: Variant = snapshot["piece_slots"]
	if typeof(piece_slots) != TYPE_ARRAY or piece_slots.size() != 6:
		errors.append("growth snapshot.piece_slots must contain exactly six entries")
		return {}
	var ratios := {}
	for index in piece_slots.size():
		var entry: Variant = piece_slots[index]
		var path := "growth snapshot.piece_slots[%d]" % index
		if not _exact_dictionary(entry, ["slot", "hp_ratio"], path, errors):
			return {}
		if not _slot(entry["slot"], "%s.slot" % path, errors) or entry["slot"] != index + 1:
			errors.append("%s must use its ordered slot" % path)
			return {}
		if not _rate(entry["hp_ratio"], "%s.hp_ratio" % path, errors):
			return {}
		ratios[entry["slot"]] = float(entry["hp_ratio"])
	var permanent_buffs: Variant = snapshot["permanent_buffs"]
	if typeof(permanent_buffs) != TYPE_ARRAY:
		errors.append("growth snapshot.permanent_buffs must be an Array")
		return {}
	var identities := {}
	for index in permanent_buffs.size():
		var entry: Variant = permanent_buffs[index]
		var path := "growth snapshot.permanent_buffs[%d]" % index
		if not _valid_permanent_entry(entry, path, errors):
			return {}
		var identity := "%s|%s|%d" % [entry["id"], entry["target"]["type"], entry["target"]["id"]]
		if identities.has(identity):
			errors.append("growth snapshot contains duplicate permanent Buff identity: %s" % identity)
			return {}
		identities[identity] = true
	return ratios


static func choose_target(
	allies: Variant,
	preferred_slot: Variant,
	ratios: Variant = null,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	if typeof(allies) != TYPE_ARRAY:
		errors.append("Marshal allies must be an Array")
		return null
	if not _slot(preferred_slot, "marshal preferred slot", errors):
		return null
	if ratios != null and typeof(ratios) != TYPE_DICTIONARY:
		errors.append("Marshal ratios must be a Dictionary or null")
		return null
	var eligible: Array[Dictionary] = []
	var seen_slots := {}
	for index in allies.size():
		var unit: Variant = allies[index]
		if not _valid_target_unit(unit, "Marshal allies[%d]" % index, errors):
			return null
		var slot: int = unit["slot"]
		if seen_slots.has(slot):
			errors.append("Marshal allies contains duplicate slot: %d" % slot)
			return null
		seen_slots[slot] = true
		if unit["side"] != "ally" or not unit["alive"] or unit["is_puppet"]:
			continue
		if ratios != null:
			if not ratios.has(slot) or not _rate(ratios[slot], "Marshal ratios[%d]" % slot, errors):
				return null
			if float(ratios[slot]) <= 0.0:
				continue
		eligible.append(unit)
	if eligible.is_empty():
		return null
	for unit: Dictionary in eligible:
		if unit["slot"] == preferred_slot:
			return unit
	eligible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["slot"]) < int(right["slot"])
	)
	return eligible[0]


static func death_growth_plan(
	dead_unit: Variant,
	side_units: Variant,
	ratios: Variant,
	before_stacks: Variant,
	tuning: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _valid_target_unit(dead_unit, "Marshal dead unit", errors):
		return {}
	if dead_unit["alive"]:
		errors.append("Marshal dead unit must already be dead")
		return {}
	if typeof(side_units) != TYPE_ARRAY:
		errors.append("Marshal side units must be an Array")
		return {}
	if ratios != null and typeof(ratios) != TYPE_DICTIONARY:
		errors.append("Marshal ratios must be a Dictionary or null")
		return {}
	var general: Variant = null
	for index in side_units.size():
		var unit: Variant = side_units[index]
		if not _valid_target_unit(unit, "Marshal side units[%d]" % index, errors):
			return {}
		if unit["side"] != dead_unit["side"] or not unit["alive"] or not unit["general"]:
			continue
		if ratios != null:
			if not ratios.has(unit["slot"]) or not _rate(ratios[unit["slot"]], "Marshal ratios[%d]" % unit["slot"], errors):
				return {}
			if float(ratios[unit["slot"]]) <= 0.0:
				continue
		if general != null:
			errors.append("Marshal side units contains more than one living general")
			return {}
		general = unit
	if dead_unit["general"]:
		return {"eligible": false, "reason": "general_died"}
	if general == null:
		return {"eligible": false, "reason": "no_living_general"}
	var count := _non_negative_safe_integer(before_stacks, "marshalPromotion before", errors)
	if count == MAX_SAFE_INTEGER:
		errors.append("marshalPromotion cannot grow beyond the maximum safe integer")
		return {}
	if not errors.is_empty():
		return {}
	# Web stages before+1 but applies at least the repeat (1->2) combat delta.
	var growth_before := maxi(1, count)
	var delta_errors: Array[String] = []
	var delta := promotion_delta(growth_before, growth_before + 1, tuning, delta_errors)
	_append_errors(delta_errors, errors)
	var request_errors: Array[String] = []
	var request := promotion_request(general["slot"], request_errors)
	_append_errors(request_errors, errors)
	if not errors.is_empty():
		return {}
	return {
		"eligible": true,
		"reason": null,
		"slot": general["slot"],
		"before_stacks": count,
		"after_stacks": count + 1,
		"request": request,
		"delta": delta,
	}


static func project_unit(unit: Variant, delta: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if typeof(unit) != TYPE_DICTIONARY:
		errors.append("Marshal unit must be a Dictionary")
		return {}
	for field in ["atk", "max_hp", "hp", "base_block_rate", "crit_rate"]:
		if not unit.has(field) or not _finite_number(unit[field]):
			errors.append("Marshal unit.%s must be finite" % field)
			return {}
	if not _exact_dictionary(delta, ["atk", "max_hp", "block", "crit"], "Marshal delta", errors):
		return {}
	for field in ["atk", "max_hp", "block", "crit"]:
		if not _finite_number(delta[field]):
			errors.append("Marshal delta.%s must be finite" % field)
			return {}
	var result: Dictionary = unit.duplicate(true)
	result["atk"] = float(unit["atk"]) + float(delta["atk"])
	result["max_hp"] = float(unit["max_hp"]) + float(delta["max_hp"])
	result["hp"] = minf(result["max_hp"], float(unit["hp"]) + float(delta["max_hp"]))
	result["base_block_rate"] = minf(RATE_CAP, float(unit["base_block_rate"]) + float(delta["block"]))
	result["crit_rate"] = minf(RATE_CAP, float(unit["crit_rate"]) + float(delta["crit"]))
	for field in ["atk", "max_hp", "hp", "base_block_rate", "crit_rate"]:
		if not _finite_number(result[field]) or float(result[field]) < 0.0:
			errors.append("Marshal projection produced invalid %s" % field)
			return {}
	return result


static func repeat_heal_amount(unit: Variant, tuning: Variant = {}, errors: Array[String] = []) -> float:
	errors.clear()
	if typeof(unit) != TYPE_DICTIONARY or not unit.has("hp") or not unit.has("max_hp"):
		errors.append("Marshal heal unit must provide hp and max_hp")
		return 0.0
	if not _finite_number(unit["hp"]) or not _finite_number(unit["max_hp"]):
		errors.append("Marshal heal unit hp and max_hp must be finite")
		return 0.0
	if float(unit["hp"]) < 0.0 or float(unit["max_hp"]) < float(unit["hp"]):
		errors.append("Marshal heal unit hp range is invalid")
		return 0.0
	var values := _tuning_values(tuning, errors)
	if not errors.is_empty():
		return 0.0
	return (float(unit["max_hp"]) - float(unit["hp"])) * values["repeat_missing_hp_heal_ratio"]


static func _tuning_values(tuning: Variant, errors: Array[String]) -> Dictionary:
	if typeof(tuning) != TYPE_DICTIONARY:
		errors.append("Marshal tuning must be a Dictionary")
		return {}
	var result := DEFAULTS.duplicate()
	var mapping := {
		"ascendAtkBonus": "first_atk",
		"ascendHpBonus": "first_max_hp",
		"ascendBlockBonus": "first_block",
		"ascendRepeatAtkBonus": "repeat_atk",
		"ascendRepeatBlockBonus": "repeat_block",
		"ascendRepeatCritBonus": "repeat_crit",
		"ascendRepeatMissingHpHealRatio": "repeat_missing_hp_heal_ratio",
	}
	for source_id: String in mapping:
		if not tuning.has(source_id):
			continue
		if not _finite_number(tuning[source_id]):
			errors.append("Marshal tuning.%s must be finite" % source_id)
			continue
		result[mapping[source_id]] = float(tuning[source_id])
	for rate_field in ["first_block", "repeat_block", "repeat_crit", "repeat_missing_hp_heal_ratio"]:
		if result[rate_field] < 0.0:
			errors.append("Marshal tuning.%s must be non-negative" % rate_field)
	for amount_field in ["first_atk", "first_max_hp", "repeat_atk"]:
		if result[amount_field] < 0.0:
			errors.append("Marshal tuning.%s must be non-negative" % amount_field)
	return result


static func _valid_target_unit(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be a Dictionary" % path)
		return false
	for field in ["slot", "side", "alive", "is_puppet", "general"]:
		if not value.has(field):
			errors.append("%s.%s is required" % [path, field])
			return false
	if not _slot(value["slot"], "%s.slot" % path, errors):
		return false
	if value["side"] not in ["ally", "enemy"]:
		errors.append("%s.side must be ally or enemy" % path)
		return false
	for field in ["alive", "is_puppet", "general"]:
		if typeof(value[field]) != TYPE_BOOL:
			errors.append("%s.%s must be a boolean" % [path, field])
			return false
	return true


static func _valid_permanent_entry(value: Variant, path: String, errors: Array[String]) -> bool:
	if not _exact_dictionary(value, ["id", "target", "stacks"], path, errors):
		return false
	if typeof(value["id"]) != TYPE_STRING or value["id"].is_empty():
		errors.append("%s.id must be a non-empty string" % path)
		return false
	if not _exact_dictionary(value["target"], ["type", "id"], "%s.target" % path, errors):
		return false
	if value["target"]["type"] == "pieceSlot":
		if not _slot(value["target"]["id"], "%s.target.id" % path, errors):
			return false
	elif value["target"]["type"] == "hero":
		if typeof(value["target"]["id"]) != TYPE_INT or value["target"]["id"] <= 0:
			errors.append("%s.target.id must be a positive hero id" % path)
			return false
	else:
		errors.append("%s.target.type must be pieceSlot or hero" % path)
		return false
	return _positive_safe_integer(value["stacks"], "%s.stacks" % path, errors) > 0


static func _exact_dictionary(value: Variant, keys: Array, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be a canonical Dictionary" % path)
		return false
	if value.size() != keys.size():
		errors.append("%s has a non-canonical field set" % path)
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


static func _slot(value: Variant, path: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_INT and value >= 1 and value <= 6:
		return true
	errors.append("%s must be an integer from 1 through 6" % path)
	return false


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


static func _positive_safe_integer(value: Variant, path: String, errors: Array[String]) -> int:
	if typeof(value) == TYPE_INT and value > 0 and value <= MAX_SAFE_INTEGER:
		return value
	errors.append("%s must be a positive safe integer" % path)
	return 0


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message in source:
		destination.append(message)
