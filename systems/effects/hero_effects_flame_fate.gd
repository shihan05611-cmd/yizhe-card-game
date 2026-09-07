class_name HeroEffectsFlameFate
extends RefCounted

const BattleContexts = preload("res://core/contexts.gd")
const BattleStateScript = preload("res://core/battle_state.gd")
const BattleStats = preload("res://core/stats.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const FateSystem = preload("res://systems/combat/fate_system.gd")
const PermanentGrowth = preload("res://systems/growth/permanent_growth.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")

const EX_BURN01 := "battle.castExclusiveSkill.burn01"
const EX_FATE := "battle.castExclusiveSkill.fate"
const EX_BURN_ENCHANT := "battle.castExclusiveSkill.burnEnchant"
const ULT_BURN01 := "battle.castUltimateByHero.burn01"
const ULT_FATE := "battle.castUltimateByHero.fate"
const ULT_BURN_ENCHANT := "battle.castUltimateByHero.burnEnchant"

const GROWTH_PREVIEW_ACTION := "preview_permanent_growth"
const GROWTH_STAGE_ACTION := "stage_permanent_growth"
const GROWTH_GET_STACKS_ACTION := "get_permanent_growth_stacks"
const BURN_ID := "burn"
const ENCHANT_ID := "enchant"
const PURSUIT_ID := "pursuit"
const FLAME_LEECH_ID := "flameLeech"
const MAX_SAFE_INTEGER := 9007199254740991


static func handler_map() -> Dictionary:
	return {
		EX_BURN01: Callable(HeroEffectsFlameFate, "_handle_ex_burn01"),
		EX_FATE: Callable(HeroEffectsFlameFate, "_handle_ex_fate"),
		EX_BURN_ENCHANT: Callable(HeroEffectsFlameFate, "_handle_ex_burn_enchant"),
		ULT_BURN01: Callable(HeroEffectsFlameFate, "_handle_ult_burn01"),
		ULT_FATE: Callable(HeroEffectsFlameFate, "_handle_ult_fate"),
		ULT_BURN_ENCHANT: Callable(HeroEffectsFlameFate, "_handle_ult_burn_enchant"),
	}


static func is_usable(
	effect_id: Variant,
	context: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if typeof(effect_id) != TYPE_STRING or not handler_map().has(effect_id):
		errors.append("unknown Flame/Fate hero effect id: %s" % str(effect_id))
		return false
	return not _plan(effect_id, context, ports, errors).is_empty()


static func _handle_ex_burn01(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var plan := _plan(EX_BURN01, context, ports, errors)
	if plan.is_empty():
		return _fail(errors)
	var buffs: Variant = plan["buffs"]
	for target: Dictionary in plan["targets"]:
		var duplicated: int = buffs.duplicate_layers(
			target, BURN_ID, plan["duration_bonus"], errors
		)
		if not errors.is_empty() or duplicated <= 0:
			if errors.is_empty():
				errors.append("burn01 failed while duplicating a preflighted Burn holder")
			return _fail(errors)
	var state: Dictionary = plan["state"]
	state[plan["count_field"]] = int(state[plan["count_field"]]) + 1
	return CombatPortsScript.ok({
		"effect_id": EX_BURN01,
		"side": plan["side"],
		"target_ids": _unit_ids(plan["targets"]),
		"successful_cast_count": state[plan["count_field"]],
	})


static func _handle_ex_fate(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var plan := _plan(EX_FATE, context, ports, errors)
	if plan.is_empty():
		return _fail(errors)
	var selection_state := BattleStateScript.snapshot(plan["state"], errors)
	if selection_state.is_empty():
		return _fail(errors)
	selection_state["fate" if plan["side"] == "ally" else "enemy_fate"]["active"] = true
	var combat_rng: Variant = ports.service("combat_rng", errors)
	if not errors.is_empty():
		return _fail(errors)
	var selection := FateSystem.select_mode(
		selection_state, plan["side"], plan["tuning"], combat_rng, errors
	)
	if selection.is_empty():
		return _fail(errors)
	var applied := FateSystem.apply_mode(
		plan["state"], plan["side"], selection, plan["buffs"], errors
	)
	if applied.is_empty():
		return _fail(errors)
	var fate: Dictionary = plan["fate"]
	fate["active"] = true
	fate["cast_used"] = true
	return CombatPortsScript.ok({
		"effect_id": EX_FATE,
		"side": plan["side"],
		"mode": applied["mode"],
		"pursuit_target_ids": applied["pursuit_target_ids"],
	})


static func _handle_ex_burn_enchant(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var plan := _plan(EX_BURN_ENCHANT, context, ports, errors)
	if plan.is_empty():
		return _fail(errors)
	if plan["run_growth"]:
		var staged: Dictionary = ports.call_action(GROWTH_STAGE_ACTION, {
			"requests": plan["growth_plan"]["requests"],
		}, errors)
		if not staged["ok"]:
			return staged
		plan["state"]["battle_growth_flags"]["flame_investment_used"] = true
		return CombatPortsScript.ok({
			"effect_id": EX_BURN_ENCHANT,
			"side": plan["side"],
			"mode": "run_growth",
			"base_cost": plan["growth_plan"]["base_cost"],
			"eligible_slots": plan["growth_plan"]["eligible_slots"].duplicate(),
			"permanent_buffs": staged["value"],
		})
	var buffs: Variant = plan["buffs"]
	for unit: Dictionary in plan["own_alive"]:
		if not buffs.apply_unit(unit, ENCHANT_ID, 1, null, errors):
			if errors.is_empty():
				errors.append("burnEnchant failed while applying enchant to a preflighted unit")
			return _fail(errors)
	return CombatPortsScript.ok({
		"effect_id": EX_BURN_ENCHANT,
		"side": plan["side"],
		"mode": "battle",
		"target_ids": _unit_ids(plan["own_alive"]),
	})


static func _handle_ult_burn01(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var plan := _plan(ULT_BURN01, context, ports, errors)
	if plan.is_empty():
		return _fail(errors)
	var damage: Variant = plan["damage"]
	var total := 0.0
	var damaged_ids: Array = []
	for entry: Dictionary in plan["damage_entries"]:
		var result: Dictionary = damage.apply(
			entry["target"], entry["damage_context"], entry["metadata"], errors
		)
		if not errors.is_empty() or result.is_empty():
			if errors.is_empty():
				errors.append("burn01 ultimate DamagePipeline returned an empty result")
			return _fail(errors)
		total += float(result["dealt"])
		damaged_ids.append(entry["target"]["id"])
	return CombatPortsScript.ok({
		"effect_id": ULT_BURN01,
		"side": plan["side"],
		"target_ids": damaged_ids,
		"total_dealt": _fmt(total),
	})


static func _handle_ult_fate(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var plan := _plan(ULT_FATE, context, ports, errors)
	if plan.is_empty():
		return _fail(errors)
	var buffs: Variant = plan["buffs"]
	for unit: Dictionary in plan["own_alive"]:
		if not buffs.apply_unit(unit, PURSUIT_ID, 1, null, errors):
			if errors.is_empty():
				errors.append("Fate ultimate failed while applying pursuit to a preflighted unit")
			return _fail(errors)
	var fate: Dictionary = plan["fate"]
	fate["active"] = true
	fate["cast_used"] = true
	fate["mode"] = FateSystem.MODE_ALL
	fate["all_in_turns"] = maxi(int(fate["all_in_turns"]), plan["all_in_turns"])
	fate[plan["lock_field"]] = "noSkill"
	return CombatPortsScript.ok({
		"effect_id": ULT_FATE,
		"side": plan["side"],
		"all_in_turns": fate["all_in_turns"],
		"pursuit_target_ids": _unit_ids(plan["own_alive"]),
	})


static func _handle_ult_burn_enchant(context: Dictionary, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	var plan := _plan(ULT_BURN_ENCHANT, context, ports, errors)
	if plan.is_empty():
		return _fail(errors)
	var buffs: Variant = plan["buffs"]
	if not buffs.apply_side(plan["side"], FLAME_LEECH_ID, 1, plan["duration"], errors):
		if errors.is_empty():
			errors.append("burnEnchant ultimate failed while applying the side Buff")
		return _fail(errors)
	return CombatPortsScript.ok({
		"effect_id": ULT_BURN_ENCHANT,
		"side": plan["side"],
		"duration": plan["duration"],
	})


static func _plan(
	effect_id: String,
	context: Variant,
	ports: Variant,
	errors: Array[String],
) -> Dictionary:
	var common := _validate_common(effect_id, context, ports, errors)
	if common.is_empty():
		return {}
	var state: Dictionary = common["state"]
	var side: String = common["side"]
	var target_side := "enemy" if side == "ally" else "ally"
	var own_team: Array = state["allies" if side == "ally" else "enemies"]
	var target_team: Array = state["enemies" if side == "ally" else "allies"]
	var buffs: Variant = ports.service("buffs", errors)
	var tuning: Variant = ports.service("tuning", errors)
	if not errors.is_empty():
		return {}
	common["buffs"] = buffs
	common["tuning"] = tuning
	common["own_alive"] = _alive_units(own_team)
	common["target_alive"] = _alive_units(target_team)
	if effect_id == EX_BURN01:
		if not _preflight_unit_buff(buffs, BURN_ID, target_team, errors):
			return {}
		var burn_targets: Array[Dictionary] = []
		for unit: Dictionary in common["target_alive"]:
			if buffs.get_unit_stacks(unit, BURN_ID) > 0:
				burn_targets.append(unit)
		if burn_targets.is_empty():
			errors.append("burn01 requires at least one living target with Burn")
			return {}
		var duration_bonus := _tuning_int(tuning, "burn01DurationBonus", errors)
		var count_field := "burn_ex_cast_count" if side == "ally" else "enemy_burn_ex_cast_count"
		if duration_bonus < 0:
			errors.append("burn01DurationBonus must be non-negative")
		if int(state[count_field]) >= MAX_SAFE_INTEGER:
			errors.append("burn01 successful cast count would overflow")
		if not errors.is_empty():
			return {}
		common["targets"] = burn_targets
		common["duration_bonus"] = duration_bonus
		common["count_field"] = count_field
		return common
	if effect_id == EX_FATE:
		var fate: Dictionary = state["fate" if side == "ally" else "enemy_fate"]
		if fate["cast_used"]:
			errors.append("Fate exclusive is limited to one successful cast per battle")
			return {}
		if not FateSystem.preflight(state, side, buffs, errors):
			return {}
		common["fate"] = fate
		return common
	if effect_id == EX_BURN_ENCHANT:
		var ratios: Variant = context.get("growth_piece_ratios")
		var run_growth := ratios != null
		if run_growth:
			if side != "ally":
				errors.append("permanent Flame growth is player-side only")
				return {}
			var stacks_result: Dictionary = ports.call_action(GROWTH_GET_STACKS_ACTION, {
				"id": PermanentGrowth.FLAME_PRACTICE_ID,
				"target": {"type": "hero", "id": PermanentGrowth.FLAME_HERO_ID},
			}, errors)
			if not stacks_result["ok"]:
				errors.append(stacks_result["error"])
				return {}
			if typeof(stacks_result["value"]) != TYPE_INT:
				errors.append("permanent growth stacks action returned a non-integer")
				return {}
			var growth_errors: Array[String] = []
			var growth_plan := PermanentGrowth.flame_investment_plan(
				own_team,
				ratios,
				stacks_result["value"],
				state["battle_growth_flags"]["flame_investment_used"],
				growth_errors,
			)
			_append_errors(growth_errors, errors)
			if growth_plan.is_empty() or not growth_plan["available"]:
				if errors.is_empty():
					errors.append("permanent Flame investment is unavailable: %s" % str(growth_plan.get("reason")))
				return {}
			var preview: Dictionary = ports.call_action(GROWTH_PREVIEW_ACTION, {
				"requests": growth_plan["requests"],
			}, errors)
			if not preview["ok"]:
				errors.append(preview["error"])
				return {}
			common["run_growth"] = true
			common["growth_plan"] = growth_plan
			return common
		if not _preflight_unit_buff(buffs, ENCHANT_ID, own_team, errors):
			return {}
		var cap := _tuning_int(tuning, "enchantStackCap", errors)
		if cap <= 0:
			errors.append("enchantStackCap must be positive")
			return {}
		var eligible := false
		for unit: Dictionary in common["own_alive"]:
			if not unit["is_puppet"] and buffs.get_unit_stacks(unit, ENCHANT_ID) < cap:
				eligible = true
				break
		if not eligible:
			errors.append("burnEnchant requires a living non-puppet unit below the Enchant cap")
			return {}
		common["run_growth"] = false
		return common
	if effect_id == ULT_BURN01:
		var damage: Variant = ports.service("damage", errors)
		if not _preflight_unit_buff(buffs, BURN_ID, target_team, errors):
			return {}
		var factor := _tuning_number(tuning, "ultBurn01AtkFactor", errors)
		if factor < 0.0:
			errors.append("ultBurn01AtkFactor must be non-negative")
		if not errors.is_empty():
			return {}
		var average_atk := BattleStats.team_average_atk(state, side)
		var crit_rate := clampf(float(common["caster"]["base_crit_rate"]), 0.0, 0.95)
		var damage_entries: Array[Dictionary] = []
		for target: Dictionary in common["target_alive"]:
			var raw := _fmt(average_atk * float(buffs.get_unit_stacks(target, BURN_ID)) * factor)
			if raw <= 0.0:
				continue
			var damage_errors: Array[String] = []
			var damage_context := BattleContexts.create_damage_context({
				"target_id": target["id"],
				"raw_amount": raw,
				"category": BattleContexts.DAMAGE_CATEGORY["DIRECT"],
				"effect": common["source_effect"],
				"dealer_type": "yizhe",
				"dealer_name": common["caster"]["name"],
				"dealer_id": common["caster"]["id"],
				"attacker_unit_id": 0,
				"can_crit": true,
				"crit_rate": crit_rate,
				"guaranteed_crit": false,
				"can_block": true,
			}, damage_errors)
			_append_errors(damage_errors, errors)
			if damage_context.is_empty():
				return {}
			damage_entries.append({
				"target": target,
				"damage_context": damage_context,
				"metadata": {"hero_id": common["caster"]["id"], "target_side": target_side},
			})
		common["damage"] = damage
		common["damage_entries"] = damage_entries
		return common
	if effect_id == ULT_FATE:
		if not _preflight_unit_buff(buffs, PURSUIT_ID, own_team, errors):
			return {}
		var turns := _tuning_int(tuning, "ultFateAllInTurns", errors)
		if turns <= 0:
			errors.append("ultFateAllInTurns must be positive")
			return {}
		common["fate"] = state["fate" if side == "ally" else "enemy_fate"]
		common["lock_field"] = "enemy_lock" if side == "ally" else "ally_lock"
		common["all_in_turns"] = turns
		return common
	if effect_id == ULT_BURN_ENCHANT:
		if buffs.definition_for(FLAME_LEECH_ID, "side", errors) == null:
			return {}
		if not buffs.validate_side_state(errors):
			return {}
		var duration := _tuning_int(tuning, "ultFlameLeechTurns", errors)
		if duration <= 0:
			errors.append("ultFlameLeechTurns must be positive")
			return {}
		common["duration"] = duration
		return common
	errors.append("unsupported Flame/Fate effect id: %s" % effect_id)
	return {}


static func _validate_common(
	effect_id: String,
	context: Variant,
	ports: Variant,
	errors: Array[String],
) -> Dictionary:
	if (
		typeof(ports) != TYPE_OBJECT
		or ports == null
		or ports.get_script() != CombatPortsScript
		or not ports.is_valid()
	):
		errors.append("Flame/Fate effects require valid CombatPorts")
		return {}
	if typeof(context) != TYPE_DICTIONARY:
		errors.append("hero effect context must be a Dictionary")
		return {}
	var allowed := ["state", "caster", "source_effect", "growth_piece_ratios"]
	for required in ["state", "caster", "source_effect"]:
		if not context.has(required):
			errors.append("hero effect context.%s is required" % required)
	for key: Variant in context:
		if typeof(key) != TYPE_STRING or key not in allowed:
			errors.append("hero effect context contains an unknown field: %s" % str(key))
	if context.has("growth_piece_ratios") and context["growth_piece_ratios"] != null and typeof(context["growth_piece_ratios"]) != TYPE_DICTIONARY:
		errors.append("hero effect context.growth_piece_ratios must be a Dictionary or null")
	if not errors.is_empty():
		return {}
	var state_errors: Array[String] = []
	if not BattleStateScript.validate(context["state"], state_errors):
		_append_errors(state_errors, errors)
		return {}
	var side := _side_for_source(context["source_effect"])
	if side.is_empty():
		errors.append("source_effect.source_side must be ally or enemy")
		return {}
	var ability_id := _ability_id(effect_id)
	var expected_type := (
		BattleContexts.EFFECT_SOURCE_TYPE["EXCLUSIVE_SKILL"]
		if effect_id.begins_with("battle.castExclusiveSkill.")
		else BattleContexts.EFFECT_SOURCE_TYPE["ULTIMATE"]
	)
	var source_errors: Array[String] = []
	var normalized_source := BattleContexts.create_effect_context(context["source_effect"], source_errors)
	_append_errors(source_errors, errors)
	if normalized_source.is_empty() or normalized_source != context["source_effect"]:
		if errors.is_empty():
			errors.append("source_effect must be a complete canonical EffectContext")
		return {}
	if (
		normalized_source["source_type"] != expected_type
		or normalized_source["source_id"] != ability_id
		or not normalized_source["counts_as_skill_cast"]
		or normalized_source["counts_as_attack"]
		or normalized_source["counts_as_basic_attack"]
	):
		errors.append("source_effect does not match the requested hero ability")
		return {}
	var caster: Variant = context["caster"]
	if typeof(caster) != TYPE_DICTIONARY:
		errors.append("hero effect context.caster must be a canonical hero Dictionary")
		return {}
	var heroes: Array = context["state"]["player_heroes" if side == "ally" else "enemy_heroes"]
	var matched: Variant = null
	for hero: Dictionary in heroes:
		if is_same(hero, caster):
			matched = hero
			break
	if matched == null:
		errors.append("caster must be the canonical hero reference from the source side")
		return {}
	if (
		caster["ex_skill"] != ability_id
		or caster["id"] != normalized_source["source_actor_id"]
		or normalized_source["source_side"] != side
	):
		errors.append("caster and source_effect identities disagree")
		return {}
	if side == "ally" and not caster["deployed"]:
		errors.append("player caster must be deployed")
		return {}
	if context["state"]["game_over"]:
		errors.append("hero effects are unavailable after battle end")
		return {}
	if side == "ally":
		if context["state"]["enemy_fate"]["ally_lock"] == "noSkill":
			errors.append("enemy Fate currently prevents player hero skills")
			return {}
		if (
			context["state"]["fate"]["active"]
			and context["state"]["fate"]["mode"] == FateSystem.MODE_PIECE
			and context["state"]["fate"]["all_in_turns"] <= 0
		):
			errors.append("piece Fate currently prevents player hero skills")
			return {}
	else:
		if context["state"]["fate"]["enemy_lock"] == "noSkill":
			errors.append("player Fate currently prevents enemy hero skills")
			return {}
		if (
			context["state"]["enemy_fate"]["active"]
			and context["state"]["enemy_fate"]["mode"] == FateSystem.MODE_PIECE
			and context["state"]["enemy_fate"]["all_in_turns"] <= 0
		):
			errors.append("piece Fate currently prevents enemy hero skills")
			return {}
	return {
		"state": context["state"],
		"caster": caster,
		"source_effect": normalized_source,
		"side": side,
	}


static func _preflight_unit_buff(
	buffs: Variant,
	buff_id: String,
	team: Array,
	errors: Array[String],
) -> bool:
	if buffs.definition_for(buff_id, "unit", errors) == null:
		return false
	for unit: Dictionary in team:
		if not buffs.validate_unit_holder(unit, errors):
			return false
	return true


static func _alive_units(team: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: Dictionary in team:
		if unit["alive"]:
			result.append(unit)
	return result


static func _unit_ids(units: Array) -> Array:
	var result: Array = []
	for unit: Dictionary in units:
		result.append(unit["id"])
	return result


static func _ability_id(effect_id: String) -> String:
	return effect_id.get_slice(".", effect_id.get_slice_count(".") - 1)


static func _side_for_source(source: Variant) -> String:
	if typeof(source) != TYPE_DICTIONARY:
		return ""
	var side: Variant = source.get("source_side")
	return side if side in ["ally", "enemy"] else ""


static func _tuning_value(tuning: Variant, id: String, errors: Array[String]) -> Variant:
	if typeof(tuning) != TYPE_DICTIONARY or not tuning.has(id):
		errors.append("M1 tuning is missing %s" % id)
		return null
	var value: Variant = tuning[id]
	if value is Resource:
		if value.get_script() != TuningValueDefinition or value.id != id:
			errors.append("M1 tuning.%s has an invalid definition" % id)
			return null
		return value.value
	return value


static func _tuning_number(tuning: Variant, id: String, errors: Array[String]) -> float:
	var value: Variant = _tuning_value(tuning, id, errors)
	if typeof(value) == TYPE_INT:
		return float(value)
	if typeof(value) == TYPE_FLOAT and is_finite(value):
		return value
	errors.append("M1 tuning.%s must be finite" % id)
	return 0.0


static func _tuning_int(tuning: Variant, id: String, errors: Array[String]) -> int:
	var value: Variant = _tuning_value(tuning, id, errors)
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		return int(value)
	errors.append("M1 tuning.%s must be an integer" % id)
	return 0


static func _fmt(value: float) -> float:
	return maxf(0.0, roundf(value * 10.0) / 10.0)


static func _fail(errors: Array[String]) -> Dictionary:
	return CombatPortsScript.fail(
		errors[0] if not errors.is_empty() else "Flame/Fate hero effect failed"
	)


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message in source:
		destination.append(message)
