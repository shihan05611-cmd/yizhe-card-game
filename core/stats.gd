class_name BattleStats
extends RefCounted

const TEAM_SLOT_DIVISOR := 6.0


static func team_average_atk(state: Variant, side: Variant) -> float:
	return average_atk_for_team(_team_from_state(state, side))


static func team_average_max_hp(
	state: Variant,
	side: Variant,
	exclude_puppet: bool = false,
) -> float:
	return average_max_hp_for_team(_team_from_state(state, side), exclude_puppet)


static func average_atk_for_team(team: Variant) -> float:
	if typeof(team) != TYPE_ARRAY:
		return 0.0
	var total := 0.0
	for unit in team:
		if typeof(unit) != TYPE_DICTIONARY or not bool(unit.get("alive", false)):
			continue
		total += _safe_number(unit.get("atk", 0))
	return total / TEAM_SLOT_DIVISOR


static func average_max_hp_for_team(team: Variant, exclude_puppet: bool = false) -> float:
	if typeof(team) != TYPE_ARRAY:
		return 0.0
	var total := 0.0
	for unit in team:
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		if exclude_puppet and bool(unit.get("is_puppet", false)):
			continue
		total += _safe_number(unit.get("max_hp", 0))
	return total / TEAM_SLOT_DIVISOR


static func _team_from_state(state: Variant, side: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY:
		return null
	return state.get("enemies" if side == "enemy" else "allies")


static func _safe_number(value: Variant) -> float:
	if typeof(value) == TYPE_INT:
		return float(value)
	if typeof(value) == TYPE_FLOAT:
		return value if is_finite(value) else 0.0
	if typeof(value) == TYPE_STRING:
		var text := String(value).strip_edges()
		if text.is_empty():
			return 0.0
		if text.is_valid_float():
			var parsed := text.to_float()
			return parsed if is_finite(parsed) else 0.0
	return 0.0
