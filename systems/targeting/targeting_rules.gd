class_name TargetingRules
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")

## Pure M2 target queries. Every public query accepts a complete canonical
## BattleState snapshot, validates it before reading, and never mutates it.
## Returned unit Dictionaries are references inside that caller-owned snapshot so
## later rule modules can pass the selected target to the frozen damage/buff ports.

const SIDE_ALLY := "ally"
const SIDE_ENEMY := "enemy"
const STEALTH_BUFF_ID := "stealth"
const BURN_BUFF_ID := "burn"


static func alive(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	errors.clear()
	var team := _validated_team(state, side, errors)
	return [] if not errors.is_empty() else _alive_sorted(team)


static func lockable(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	errors.clear()
	var team := _validated_team(state, side, errors)
	return [] if not errors.is_empty() else _lockable_sorted(team)


static func is_alive_at_slot(
	state: Variant,
	side: Variant,
	slot: Variant,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	var team := _validated_team_and_slot(state, side, slot, errors)
	if not errors.is_empty():
		return false
	var unit: Variant = _unit_at_slot(team, int(slot))
	return unit != null and bool(unit["alive"])


static func is_lockable_at_slot(
	state: Variant,
	side: Variant,
	slot: Variant,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	var team := _validated_team_and_slot(state, side, slot, errors)
	if not errors.is_empty():
		return false
	var unit: Variant = _unit_at_slot(team, int(slot))
	return unit != null and _is_lockable(unit)


## Web pickLowestHpPercentTarget: ratio, then current HP, then stable id.
static func lowest_hp_percent_lockable(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	return null if not errors.is_empty() else _first_by_hp_percent(_lockable_sorted(team), true)


## skills.js smallHeal: ratio, then stable id (no stealth exclusion).
static func lowest_hp_percent_alive(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	return null if not errors.is_empty() else _first_by_hp_percent(_alive_sorted(team), false)


## skills.js basicDamage: lockable ratio, then stable id. This intentionally
## differs from battle.js pickLowestHpPercentTarget's extra current-HP tie-break.
static func lowest_hp_percent_lockable_by_id(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	return null if not errors.is_empty() else _first_by_hp_percent(_lockable_sorted(team), false)


## skills.js executeStrike and the stealth basic-attack override use current HP,
## not HP percentage. They differ only in whether stealth prevents locking.
static func lowest_current_hp_lockable(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	return null if not errors.is_empty() else _first_by_current_hp(_lockable_sorted(team))


static func lowest_current_hp_alive(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	return null if not errors.is_empty() else _first_by_current_hp(_alive_sorted(team))


## skills.js pieceAction and Web shadow use ATK descending, then stable id.
static func highest_atk_alive(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	if not errors.is_empty():
		return null
	var candidates := _alive_sorted(team)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left["atk"]) != float(right["atk"]):
			return float(left["atk"]) > float(right["atk"])
		return _id_less(left, right)
	)
	return candidates[0] if not candidates.is_empty() else null


## skills.js bloodShift uses current HP descending, then stable id.
static func highest_current_hp_alive(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	if not errors.is_empty():
		return null
	var candidates := _alive_sorted(team)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left["hp"]) != float(right["hp"]):
			return float(left["hp"]) > float(right["hp"])
		return _id_less(left, right)
	)
	return candidates[0] if not candidates.is_empty() else null


## skills.js burnDetonate: positive burn descending, HP percentage ascending,
## then stable id. Stealthed units are not single-target lockable.
static func burn_detonate_target(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	if not errors.is_empty():
		return null
	var candidates: Array[Dictionary] = []
	for unit: Dictionary in _lockable_sorted(team):
		if BuffSystemScript.get_buff_stacks(unit, BURN_BUFF_ID) > 0:
			candidates.append(unit)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_stacks := BuffSystemScript.get_buff_stacks(left, BURN_BUFF_ID)
		var right_stacks := BuffSystemScript.get_buff_stacks(right, BURN_BUFF_ID)
		if left_stacks != right_stacks:
			return left_stacks > right_stacks
		var left_ratio := _hp_percent(left)
		var right_ratio := _hp_percent(right)
		if left_ratio != right_ratio:
			return left_ratio < right_ratio
		return _id_less(left, right)
	)
	return candidates[0] if not candidates.is_empty() else null


## skills.js markBurn: burn descending, then stable id; zero-stack lockable
## targets remain valid candidates.
static func mark_burn_target(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var team := _validated_team(state, side, errors)
	if not errors.is_empty():
		return null
	var candidates := _lockable_sorted(team)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_stacks := BuffSystemScript.get_buff_stacks(left, BURN_BUFF_ID)
		var right_stacks := BuffSystemScript.get_buff_stacks(right, BURN_BUFF_ID)
		if left_stacks != right_stacks:
			return left_stacks > right_stacks
		return _id_less(left, right)
	)
	return candidates[0] if not candidates.is_empty() else null


## The Web randomAliveEnemies/randomAliveAllies loops randomize this pool without
## replacement. This layer returns the stable candidate set and consumes no RNG.
static func random_lockable_candidates(
	state: Variant,
	side: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	return lockable(state, side, errors)


## Web calls this a lane although UI text sometimes says column. Slots 1/4,
## 2/5, and 3/6 share lanes 1, 2, and 3 respectively.
static func lane_by_slot(slot: Variant, errors: Array[String] = []) -> int:
	errors.clear()
	if not _validate_slot(slot, errors):
		return 0
	return ((int(slot) - 1) % 3) + 1


static func lane_priority(lane: Variant, errors: Array[String] = []) -> Array[int]:
	errors.clear()
	if typeof(lane) != TYPE_INT or int(lane) < 1 or int(lane) > 3:
		errors.append("lane must be an integer from 1 through 3")
		return []
	if int(lane) == 1:
		return [1, 2, 3]
	if int(lane) == 2:
		return [2, 1, 3]
	return [3, 2, 1]


## Web pickTargetByLane: prioritized front row first, then prioritized back row.
## Unlike single-target skills, ordinary positional targeting does not filter
## stealth. Canonical slot replaces Web's overloaded numeric unit id here.
static func target_by_lane(
	state: Variant,
	attacker_side: Variant,
	attacker_slot: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	var attackers := _validated_team_and_slot(state, attacker_side, attacker_slot, errors)
	if not errors.is_empty():
		return null
	var attacker: Variant = _unit_at_slot(attackers, int(attacker_slot))
	if attacker == null or not bool(attacker["alive"]):
		return null
	var defenders: Array = state["enemies" if attacker_side == SIDE_ALLY else "allies"]
	var lane := ((int(attacker_slot) - 1) % 3) + 1
	var priority: Array[int] = _lane_priority_unchecked(lane)
	for front_lane: int in priority:
		var front: Variant = _unit_at_slot(defenders, front_lane)
		if front != null and bool(front["alive"]):
			return front
	for back_lane: int in priority:
		var back: Variant = _unit_at_slot(defenders, back_lane + 3)
		if back != null and bool(back["alive"]):
			return back
	return null


static func column_targets_by_attacker(
	state: Variant,
	attacker_side: Variant,
	attacker_slot: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	errors.clear()
	var attackers := _validated_team_and_slot(state, attacker_side, attacker_slot, errors)
	if not errors.is_empty():
		return []
	var attacker: Variant = _unit_at_slot(attackers, int(attacker_slot))
	if attacker == null or not bool(attacker["alive"]):
		return []
	var defenders: Array = state["enemies" if attacker_side == SIDE_ALLY else "allies"]
	return _column_alive(defenders, ((int(attacker_slot) - 1) % 3) + 1)


static func column_targets_by_target(
	state: Variant,
	target_side: Variant,
	target_slot: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	errors.clear()
	var targets := _validated_team_and_slot(state, target_side, target_slot, errors)
	if not errors.is_empty():
		return []
	var target: Variant = _unit_at_slot(targets, int(target_slot))
	if target == null or not bool(target["alive"]):
		return []
	return _column_alive(targets, ((int(target_slot) - 1) % 3) + 1)


static func _validated_team(state: Variant, side: Variant, errors: Array[String]) -> Array:
	if side not in [SIDE_ALLY, SIDE_ENEMY]:
		errors.append("side must be ally or enemy")
		return []
	var state_errors: Array[String] = []
	if not BattleStateScript.validate(state, state_errors):
		for message: String in state_errors:
			errors.append(message)
		return []
	return state["allies" if side == SIDE_ALLY else "enemies"]


static func _validated_team_and_slot(
	state: Variant,
	side: Variant,
	slot: Variant,
	errors: Array[String],
) -> Array:
	var team := _validated_team(state, side, errors)
	if not errors.is_empty():
		return []
	if not _validate_slot(slot, errors):
		return []
	return team


static func _validate_slot(slot: Variant, errors: Array[String]) -> bool:
	if typeof(slot) == TYPE_INT and int(slot) >= 1 and int(slot) <= 6:
		return true
	errors.append("slot must be an integer from 1 through 6")
	return false


static func _alive_sorted(team: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: Dictionary in team:
		if bool(unit["alive"]):
			result.append(unit)
	result.sort_custom(_id_less)
	return result


static func _lockable_sorted(team: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: Dictionary in team:
		if _is_lockable(unit):
			result.append(unit)
	result.sort_custom(_id_less)
	return result


static func _is_lockable(unit: Dictionary) -> bool:
	return bool(unit["alive"]) and not BuffSystemScript.has_buff(unit, STEALTH_BUFF_ID)


static func _first_by_hp_percent(candidates: Array[Dictionary], hp_tiebreak: bool) -> Variant:
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_ratio := _hp_percent(left)
		var right_ratio := _hp_percent(right)
		if left_ratio != right_ratio:
			return left_ratio < right_ratio
		if hp_tiebreak and float(left["hp"]) != float(right["hp"]):
			return float(left["hp"]) < float(right["hp"])
		return _id_less(left, right)
	)
	return candidates[0] if not candidates.is_empty() else null


static func _first_by_current_hp(candidates: Array[Dictionary]) -> Variant:
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left["hp"]) != float(right["hp"]):
			return float(left["hp"]) < float(right["hp"])
		return _id_less(left, right)
	)
	return candidates[0] if not candidates.is_empty() else null


static func _hp_percent(unit: Dictionary) -> float:
	return float(unit["hp"]) / float(unit["max_hp"]) if float(unit["max_hp"]) > 0.0 else 1.0


static func _id_less(left: Dictionary, right: Dictionary) -> bool:
	var left_id: Variant = left["id"]
	var right_id: Variant = right["id"]
	if typeof(left_id) == typeof(right_id):
		return left_id < right_id
	# Mixed int/string IDs are legal canonical stable IDs. Use a declared type
	# order so selection never depends on Dictionary or Array iteration order.
	return typeof(left_id) < typeof(right_id)


static func _unit_at_slot(team: Array, slot: int) -> Variant:
	for unit: Dictionary in team:
		if int(unit["slot"]) == slot:
			return unit
	return null


static func _column_alive(team: Array, lane: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: int in [lane, lane + 3]:
		var unit: Variant = _unit_at_slot(team, slot)
		if unit != null and bool(unit["alive"]):
			result.append(unit)
	return result


static func _lane_priority_unchecked(lane: int) -> Array[int]:
	if lane == 1:
		return [1, 2, 3]
	if lane == 2:
		return [2, 1, 3]
	return [3, 2, 1]
