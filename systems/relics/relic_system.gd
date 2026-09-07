class_name RelicSystem
extends RefCounted

## Injected action ports must match the argument signatures used below and must
## not raise runtime errors. Void/plain returns are wrapped as {"ok": true}; a
## recoverable failure must return {"ok": false, "error": "..."}.

const DEFAULT_ASSAULT_MULTIPLIER := 3.0

var catalog := {}
var _dispatcher: Variant
var _get_owned_relic_ids: Callable
var _actions := {}
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("relic system config must be a Dictionary")
		return
	var configured_catalog: Variant = config.get("catalog")
	var dispatcher: Variant = config.get("dispatcher")
	var get_owned: Variant = config.get("get_owned_relic_ids")
	var actions: Variant = config.get("actions", {})
	if typeof(configured_catalog) != TYPE_DICTIONARY or configured_catalog.is_empty():
		errors.append("relic catalog must be a non-empty Dictionary")
	if dispatcher == null or not dispatcher.has_method("register_catalog"):
		errors.append("hook dispatcher is required")
	if not _valid_callable(get_owned):
		errors.append("get_owned_relic_ids must be an injected valid Callable")
	if typeof(actions) != TYPE_DICTIONARY:
		errors.append("relic actions must be an injected Dictionary")
	if not errors.is_empty():
		return
	catalog = configured_catalog.duplicate(true)
	_dispatcher = dispatcher
	_get_owned_relic_ids = get_owned
	_actions = actions.duplicate(true)
	var registration_errors: Array[String] = []
	var registered: bool = _dispatcher.register_catalog(catalog, {
		"is_enabled": func(definition: Dictionary, _context: Dictionary) -> bool:
			return has(definition["id"]),
		"resolver_registry": _resolver_registry(),
		"actions": _actions,
	}, registration_errors)
	for message in registration_errors:
		errors.append(message)
	_valid = registered and errors.is_empty()
	# The dispatcher owns bound resolver Callables after registration. Drop the
	# reverse reference so pure RefCounted systems do not form a lifetime cycle.
	_dispatcher = null


func is_valid() -> bool:
	return _valid


func has(relic_id: Variant) -> bool:
	return typeof(relic_id) == TYPE_STRING and catalog.has(relic_id) and relic_id in _owned_ids()


func get_definition(relic_id: Variant) -> Variant:
	if typeof(relic_id) != TYPE_STRING or not catalog.has(relic_id):
		return null
	var definition: Variant = catalog[relic_id]
	return definition.snapshot() if definition is Resource and definition.has_method("snapshot") else _snapshot(definition)


func get_effective_skill_point_cost(
	base_cost: Variant,
	side: String,
	round_number: Variant,
	skill_kind: String = "freeSkill",
) -> int:
	var normalized: int = maxi(0, int(floor(_finite(base_cost))))
	for modifier in _modifiers("skillPointCostOverride"):
		if modifier.get("side") == side \
		and skill_kind in modifier.get("skillKinds", []) \
		and _finite(round_number) <= _finite(modifier.get("maxRound")):
			return maxi(0, int(floor(_finite(modifier.get("value")))))
	return normalized


func get_skill_point_max_adjustment() -> float:
	return _sum_modifier_values("skillPointMaxFlat")


func get_class_max_hp_adjustment(class_id: String, side: String) -> float:
	var total := 0.0
	for modifier in _modifiers("classMaxHpFlat"):
		if modifier.get("classId") == class_id and modifier.get("side") == side:
			total += _finite(modifier.get("value"))
	return total


func get_crossbow_pursuit_chance(base_chance: Variant, unit: Variant) -> float:
	var chance := _finite(base_chance)
	for modifier in _modifiers("pursuitChanceFlat"):
		if _matches_unit(modifier, unit):
			chance += _finite(modifier.get("value"))
	return clampf(chance, 0.0, 1.0)


func get_effective_crit_rate(base_rate: Variant, unit: Variant) -> float:
	var rate := _finite(base_rate)
	if typeof(unit) != TYPE_DICTIONARY:
		return clampf(rate, 0.0, 0.95)
	var max_hp: float = _finite(_field(unit, "max_hp", "maxHp", 0))
	var hp: float = _finite(unit.get("hp", 0))
	for modifier in _modifiers("critRateFlatBelowHp"):
		if _matches_unit(modifier, unit) and max_hp > 0.0 and hp / max_hp < _finite(modifier.get("hpRatio")):
			rate += _finite(modifier.get("value"))
	return clampf(rate, 0.0, 0.95)


func can_sell_free_skills() -> bool:
	for modifier in _modifiers("canSellFreeSkills"):
		if modifier.get("value") == true:
			return true
	return false


func get_currency_cost(base_cost: Variant) -> int:
	var normalized: int = maxi(0, int(floor(_finite(base_cost))))
	var multiplier := 1.0
	for modifier in _modifiers("currencyCostMultiplier"):
		multiplier *= _finite(modifier.get("value"), 1.0)
	return maxi(0, int(ceil(float(normalized) * multiplier)))


func get_effective_healing_amount(base_amount: Variant, unit: Variant) -> float:
	var amount := maxf(0.0, _finite(base_amount))
	var side: Variant = unit.get("side") if typeof(unit) == TYPE_DICTIONARY else null
	for modifier in _modifiers("healingReceivedMultiplier"):
		if modifier.get("side") == side:
			amount *= maxf(0.0, _finite(modifier.get("value"), 1.0))
	return amount


func get_shentong_assault_damage_multiplier(selected_shentong_id: String) -> float:
	for modifier in _modifiers("shentongDamageMultiplier"):
		if modifier.get("shentongId") == selected_shentong_id:
			return _finite(modifier.get("value"), DEFAULT_ASSAULT_MULTIPLIER)
	return DEFAULT_ASSAULT_MULTIPLIER


func get_shentong_charge_energy_gain(selected_shentong_id: String) -> float:
	for modifier in _modifiers("shentongEnergyGain"):
		if modifier.get("shentongId") == selected_shentong_id:
			return _finite(modifier.get("value"))
	return 0.0


func _resolver_registry() -> Dictionary:
	return {
		"conditions": {
			"relic.condition.source_effect_is_ally": Callable(self, "_condition_source_effect_is_ally"),
			"relic.condition.ally_spent_positive_sp": Callable(self, "_condition_ally_spent_positive_sp"),
			"relic.condition.enemy_burn_death_allows_kill_effects": Callable(self, "_condition_enemy_burn_death"),
			"relic.condition.target_is_enemy": Callable(self, "_condition_target_is_enemy"),
			"relic.condition.ally_blocked_by_alive_actor": Callable(self, "_condition_ally_blocked"),
			"relic.condition.ally_shield_blocked": Callable(self, "_condition_ally_shield_blocked"),
			"relic.condition.ally_banner_attack_hit": Callable(self, "_condition_ally_banner_hit"),
			"relic.condition.ally_free_skill_actual_cost_zero": Callable(self, "_condition_ally_free_skill_zero"),
			"relic.condition.ally_piece_hit_alive_target": Callable(self, "_condition_ally_piece_hit"),
			"relic.condition.ally_target_alive": Callable(self, "_condition_ally_target_alive"),
			"relic.condition.ally_kill_or_ally_sacrifice": Callable(self, "_condition_kill_or_sacrifice"),
		},
		"effects": {
			"relic.effect.apply_pursuit_to_alive_allies": Callable(self, "_effect_apply_pursuit"),
			"relic.effect.deal_arc_conductor_damage_to_all_enemies": Callable(self, "_effect_arc_conductor"),
			"relic.effect.spread_burn_on_enemy_death": Callable(self, "_effect_spread_burn"),
			"relic.effect.trigger_strongest_ally_pursuit": Callable(self, "_effect_trigger_pursuit"),
			"relic.effect.reflect_blocked_raw_damage": Callable(self, "_effect_reflect"),
			"relic.effect.heal_missing_hp_ratio": Callable(self, "_effect_heal_missing"),
			"relic.effect.gain_random_active_hero_energy": Callable(self, "_effect_gain_random_energy"),
			"relic.effect.gain_skill_points": Callable(self, "_effect_gain_skill_points"),
			"relic.effect.gain_lowest_energy_active_hero_energy": Callable(self, "_effect_gain_lowest_energy"),
			"relic.effect.apply_burn": Callable(self, "_effect_apply_burn"),
			"relic.effect.heal_max_hp_ratio": Callable(self, "_effect_heal_max"),
			"relic.effect.heal_alive_allies_ratio": Callable(self, "_effect_heal_allies"),
		},
	}


func _condition_source_effect_is_ally(context: Dictionary, _subject: Variant, _params: Dictionary) -> bool:
	return _source_effect(context).get("source_side") == "ally"


func _condition_ally_spent_positive_sp(context: Dictionary, _subject: Variant, params: Dictionary) -> bool:
	return _field(context, "source_side", "sourceSide", "") == params.get("source_side", "ally") \
		and _finite(context.get("amount")) >= _finite(params.get("minimum_amount", 1))


func _condition_enemy_burn_death(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	var target: Variant = context.get("target", context.get("unit"))
	if typeof(target) != TYPE_DICTIONARY or target.get("side") != params.get("target_side", "enemy"):
		return false
	var death: Variant = context.get("death_context", {})
	var effect: Dictionary = _source_effect(context)
	if typeof(death) == TYPE_DICTIONARY and death.get("triggers_enemy_kill_effects", true) == false:
		return false
	if effect.get("triggers_enemy_kill_effects", true) == false:
		return false
	var stacks_result: Dictionary = _call_action(context, "get_buff_stacks", [target, params.get("buff_id", "burn")])
	if stacks_result.get("ok") == false:
		return stacks_result
	if not _is_finite(stacks_result.get("value")):
		return {"ok": false, "error": "get_buff_stacks must return a finite number"}
	return float(stacks_result["value"]) >= _finite(params.get("minimum_stacks", 1))


func _condition_target_is_enemy(context: Dictionary, _subject: Variant, params: Dictionary) -> bool:
	var target: Variant = context.get("target", context.get("unit"))
	return typeof(target) == TYPE_DICTIONARY and target.get("side") == params.get("target_side", "enemy")


func _condition_ally_blocked(context: Dictionary, _subject: Variant, params: Dictionary) -> bool:
	var target: Variant = context.get("target", context.get("defender"))
	var actor: Variant = context.get("actor", context.get("attacker"))
	return typeof(target) == TYPE_DICTIONARY and target.get("side") == params.get("target_side", "ally") \
		and typeof(actor) == TYPE_DICTIONARY and bool(actor.get("alive", false))


func _condition_ally_shield_blocked(context: Dictionary, _subject: Variant, params: Dictionary) -> bool:
	var target: Variant = context.get("target", context.get("defender"))
	return typeof(target) == TYPE_DICTIONARY and target.get("side") == params.get("target_side", "ally") \
		and _unit_class(target) == params.get("class_id", "shield")


func _condition_ally_banner_hit(context: Dictionary, _subject: Variant, params: Dictionary) -> bool:
	var actor: Variant = context.get("actor")
	return typeof(actor) == TYPE_DICTIONARY and actor.get("side") == params.get("actor_side", "ally") \
		and _unit_class(actor) == params.get("class_id", "banner")


func _condition_ally_free_skill_zero(context: Dictionary, _subject: Variant, params: Dictionary) -> bool:
	return _source_effect(context).get("source_side") == params.get("source_side", "ally") \
		and _finite(context.get("amount")) == _finite(params.get("actual_cost", 0))


func _condition_ally_piece_hit(context: Dictionary, _subject: Variant, params: Dictionary) -> bool:
	var actor: Variant = context.get("actor")
	var target: Variant = context.get("target")
	return typeof(actor) == TYPE_DICTIONARY and actor.get("side") == params.get("actor_side", "ally") \
		and typeof(target) == TYPE_DICTIONARY and bool(target.get("alive", false))


func _condition_ally_target_alive(context: Dictionary, _subject: Variant, params: Dictionary) -> bool:
	var target: Variant = context.get("target")
	return typeof(target) == TYPE_DICTIONARY and target.get("side") == params.get("target_side", "ally") \
		and bool(target.get("alive", false))


func _condition_kill_or_sacrifice(context: Dictionary, _subject: Variant, _params: Dictionary) -> bool:
	var target: Variant = context.get("target", context.get("unit"))
	if typeof(target) != TYPE_DICTIONARY:
		return false
	var effect: Dictionary = _source_effect(context)
	return (target.get("side") == "enemy" and effect.get("source_side") == "ally") \
		or (target.get("side") == "ally" and effect.get("source_type") == "sacrifice" and effect.get("source_side") == "ally")


func _effect_apply_pursuit(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	return _call_action(context, "apply_pursuit_to_alive_allies", [params.get("stacks", 1)])


func _effect_arc_conductor(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	var average_result: Dictionary = _call_action(context, "get_team_average_atk", ["ally"])
	if average_result.get("ok") == false:
		return average_result
	if not _is_finite(average_result.get("value")):
		return {"ok": false, "error": "get_team_average_atk must return a finite number"}
	var raw := float(average_result["value"]) \
		* _finite(params.get("team_average_attack_multiplier_per_sp", 0.6)) \
		* _finite(context.get("amount"))
	return _call_action(context, "deal_relic_damage_to_all_enemies", [
		raw, params.get("source_id", "arcConductor"), params.get("source_name", "奥术导体"),
	])


func _effect_spread_burn(context: Dictionary, _subject: Variant, _params: Dictionary) -> Variant:
	return _call_action(context, "spread_burn_on_enemy_death", [context.get("target", context.get("unit"))])


func _effect_trigger_pursuit(context: Dictionary, _subject: Variant, _params: Dictionary) -> Variant:
	return _call_action(context, "trigger_strongest_ally_pursuit", [context.get("target")])


func _effect_reflect(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	var actor: Variant = context.get("actor", context.get("attacker"))
	var raw := maxf(
		_finite(params.get("minimum_damage", 1)),
		_finite(context.get("raw_amount", context.get("amount", 0))) * _finite(params.get("raw_damage_ratio", 0.5)),
	)
	return _call_action(context, "apply_relic_damage", [actor, raw, params.get("source_id"), params.get("source_name")])


func _effect_heal_missing(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	var target: Variant = context.get("target", context.get("defender"))
	var amount := maxf(0.0, _unit_max_hp(target) - _finite(target.get("hp", 0))) \
		* _finite(params.get("missing_hp_ratio", 0.03))
	return _call_action(context, "heal", [target, amount, params.get("source_id"), params.get("source_name")])


func _effect_gain_random_energy(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	return _call_action(context, "gain_random_active_hero_energy", [params.get("amount", 1), params.get("source_id"), params.get("source_name")])


func _effect_gain_skill_points(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	return _call_action(context, "gain_skill_points", [params.get("amount", 1)])


func _effect_gain_lowest_energy(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	return _call_action(context, "gain_lowest_energy_active_hero_energy", [params.get("amount", 10)])


func _effect_apply_burn(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	return _call_action(context, "apply_burn", [context.get("target"), params.get("stacks", 1)])


func _effect_heal_max(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	var target: Variant = context.get("target")
	var amount := _unit_max_hp(target) * _finite(params.get("max_hp_ratio", 0.02))
	return _call_action(context, "heal", [target, amount, params.get("source_id"), params.get("source_name")])


func _effect_heal_allies(context: Dictionary, _subject: Variant, params: Dictionary) -> Variant:
	return _call_action(context, "heal_alive_allies", [params.get("max_hp_ratio", 0.1), params.get("source_id"), params.get("source_name")])


func _call_action(context: Dictionary, action_id: String, arguments: Array) -> Dictionary:
	var actions: Variant = context.get("actions")
	if typeof(actions) != TYPE_DICTIONARY:
		return {"ok": false, "error": "relic actions are unavailable"}
	var action: Variant = actions.get(action_id)
	if not _valid_callable(action):
		return {"ok": false, "error": "missing relic action: %s" % action_id}
	var result: Variant = action.callv(arguments)
	if typeof(result) == TYPE_DICTIONARY and result.get("ok") == false:
		return {"ok": false, "error": str(result.get("error", "%s failed" % action_id))}
	return {"ok": true, "value": result}


func _owned_ids() -> Array:
	var value: Variant = _get_owned_relic_ids.call()
	if typeof(value) != TYPE_ARRAY:
		return []
	var result: Array = []
	for id in value:
		if typeof(id) == TYPE_STRING and id not in result:
			result.append(id)
	return result


func _owned_definitions() -> Array:
	var ids: Array = _owned_ids()
	var definitions: Array = []
	for id in catalog:
		if id in ids:
			definitions.append(catalog[id])
	return definitions


func _modifiers(type_id: String) -> Array:
	var result: Array = []
	for definition in _owned_definitions():
		for modifier in definition.get("modifiers"):
			if modifier.get("type") == type_id:
				result.append(modifier)
	return result


func _sum_modifier_values(type_id: String) -> float:
	var total := 0.0
	for modifier in _modifiers(type_id):
		total += _finite(modifier.get("value"))
	return total


func _matches_unit(modifier: Dictionary, unit: Variant) -> bool:
	return typeof(unit) == TYPE_DICTIONARY \
		and modifier.get("side") == unit.get("side") \
		and modifier.get("classId") == _unit_class(unit)


func _source_effect(context: Dictionary) -> Dictionary:
	var effect: Variant = context.get("source_effect", context.get("effect_context", {}))
	if typeof(effect) != TYPE_DICTIONARY:
		return {}
	var normalized: Dictionary = effect.duplicate(true)
	for field_pair in [["source_side", "sourceSide"], ["source_type", "sourceType"], ["triggers_enemy_kill_effects", "triggersEnemyKillEffects"]]:
		if not normalized.has(field_pair[0]) and normalized.has(field_pair[1]):
			normalized[field_pair[0]] = normalized[field_pair[1]]
	return normalized


static func _field(value: Dictionary, snake_name: String, camel_name: String, fallback: Variant = null) -> Variant:
	return value.get(snake_name, value.get(camel_name, fallback))


static func _unit_class(unit: Variant) -> Variant:
	return _field(unit, "class_id", "classId") if typeof(unit) == TYPE_DICTIONARY else null


static func _unit_max_hp(unit: Variant) -> float:
	return _finite(_field(unit, "max_hp", "maxHp", 0)) if typeof(unit) == TYPE_DICTIONARY else 0.0


static func _finite(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if _is_finite(value) else fallback


static func _is_finite(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _valid_callable(value: Variant) -> bool:
	return typeof(value) == TYPE_CALLABLE and value.is_valid()


static func _snapshot(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item in value:
			result.append(_snapshot(item))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key in value:
			result[_snapshot(key)] = _snapshot(value[key])
		return result
	return value
