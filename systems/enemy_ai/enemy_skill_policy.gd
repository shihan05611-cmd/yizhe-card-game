class_name EnemySkillPolicy
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")
const FreeSkillEffectsScript = preload("res://systems/effects/free_skill_effects.gd")
const FlameFateEffectsScript = preload("res://systems/effects/hero_effects_flame_fate.gd")
const MarshalFistEffectsScript = preload("res://systems/effects/hero_effects_marshal_fist.gd")
const SiegePuppetShadowEffectsScript = preload("res://systems/effects/hero_effects_siege_puppet_shadow.gd")

## The default list is the frozen M1 mirror of Web DEFAULT_ENEMY_FREE_SKILL_IDS.
## An authored non-empty pool is preserved in order; duplicates are removed.
const DEFAULT_FREE_SKILL_IDS := [
	"burnStackBase", "pieceBlock", "pieceDamageUp", "pieceAction", "burnDetonate",
]
const PLAN_KEYS := [
	"kind", "reason", "skip_recover", "action", "skill_id", "effect_id",
	"actual_sp_cost", "pool", "eligible_choices", "weighted_choices",
]


static func build_plan(
	state: Variant,
	hero: Variant,
	registry: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_inputs(state, hero, registry, ports, errors):
		return {}
	if state["game_over"]:
		return _skip("game_over", false, [])
	var enemy_all_in := int(state["enemy_fate"]["all_in_turns"]) > 0
	if state["fate"]["enemy_lock"] == "noSkill":
		return _skip("player_fate_no_skill", true, [])
	if (
		state["enemy_fate"]["active"]
		and state["enemy_fate"]["mode"] == "棋子命运"
		and not enemy_all_in
	):
		return _skip("enemy_piece_fate", true, [])

	var catalogs: Variant = ports.service("catalogs", errors)
	var relics: Variant = ports.service("relics", errors)
	if not errors.is_empty():
		return {}
	if typeof(catalogs) != TYPE_DICTIONARY or typeof(catalogs.get("skills")) != TYPE_DICTIONARY:
		errors.append("enemy policy requires the canonical M1 skill catalog")
		return {}
	if (
		typeof(relics) != TYPE_OBJECT or relics == null
		or relics.get_script() != RelicSystemScript
		or relics.is_valid() != true
	):
		errors.append("enemy policy requires a valid exact B2 RelicSystem")
		return {}

	var pool := normalized_pool(hero["skill_pool"])
	var eligible: Array[Dictionary] = []
	for skill_id: String in pool:
		var definition: Variant = catalogs["skills"].get(skill_id)
		if definition == null:
			continue
		var effect_id: Variant = definition.effect_id
		if typeof(effect_id) != TYPE_STRING or not registry.has(effect_id):
			continue
		var cost: int = relics.get_effective_skill_point_cost(
			definition.base_sp_cost, "enemy", state["round"], "freeSkill",
		)
		if cost < 0 or float(state["enemy_sp"]) < float(cost):
			continue
		var context := _free_context(state, hero, skill_id, str(definition.name))
		var usable_errors: Array[String] = []
		if not FreeSkillEffectsScript.is_usable(skill_id, context, ports, usable_errors):
			continue
		eligible.append(_choice("free", skill_id, effect_id, cost))

	var exclusive := _exclusive_choice(state, hero, registry, ports, catalogs, errors)
	if not errors.is_empty():
		return {}
	if not exclusive.is_empty():
		eligible.append(exclusive)

	var weighted: Array[Dictionary] = eligible.duplicate(true)
	if not exclusive.is_empty() and hero["ex_skill"] == "fist":
		weighted.append(exclusive.duplicate(true))
		weighted.append(exclusive.duplicate(true))
	if weighted.is_empty():
		var skill_fate: bool = bool(
			state["enemy_fate"]["active"]
			and state["enemy_fate"]["mode"] == "技能命运"
			and not enemy_all_in
		)
		return _skip("enemy_skill_fate_no_choice" if skill_fate else "no_choice", not skill_fate, pool)

	var selected: Dictionary
	if not exclusive.is_empty() and hero["ex_skill"] in ["fist", "burnEnchant"]:
		selected = exclusive
	else:
		var rng: Variant = ports.service("enemy_policy_rng", errors)
		if not errors.is_empty():
			return {}
		var index: Variant = rng.int_range(0, weighted.size() - 1)
		if typeof(index) != TYPE_INT or index < 0 or index >= weighted.size():
			errors.append("enemy_policy_rng.int_range returned an out-of-range choice")
			return {}
		selected = weighted[index]
	return _plan(selected, pool, eligible, weighted)


static func ultimate_plan(
	state: Variant,
	hero: Variant,
	registry: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_inputs(state, hero, registry, ports, errors):
		return {}
	if state["game_over"] or _skill_locked(state):
		return {"castable": false, "effect_id": "", "energy_cost": 0, "source_name": ""}
	var catalogs: Variant = ports.service("catalogs", errors)
	if not errors.is_empty():
		return {}
	var ability: Variant = catalogs.get("hero_abilities", {}).get("ultimate", {}).get(hero["ex_skill"])
	if ability == null:
		return {"castable": false, "effect_id": "", "energy_cost": 0, "source_name": ""}
	var effect_id: Variant = ability.handler_id
	var cost: Variant = ability.source_energy_requirement
	if typeof(effect_id) != TYPE_STRING or not registry.has(effect_id):
		errors.append("enemy ultimate handler is unavailable: %s" % str(effect_id))
		return {}
	if typeof(cost) != TYPE_INT or cost <= 0:
		errors.append("enemy ultimate energy requirement must be a positive integer")
		return {}
	if float(hero["energy"]) < float(cost):
		return {"castable": false, "effect_id": effect_id, "energy_cost": cost, "source_name": str(ability.name)}
	var context := _hero_context(state, hero, hero["ex_skill"], true, str(ability.name))
	var usable_errors: Array[String] = []
	if not _hero_usable(hero["ex_skill"], true, effect_id, context, ports, usable_errors):
		if not usable_errors.is_empty():
			errors.append("enemy ultimate usability failed: %s" % usable_errors[0])
			return {}
		return {"castable": false, "effect_id": effect_id, "energy_cost": cost, "source_name": str(ability.name)}
	return {"castable": true, "effect_id": effect_id, "energy_cost": cost, "source_name": str(ability.name)}


static func free_context(state: Dictionary, hero: Dictionary, skill_id: String, source_name: String) -> Dictionary:
	return _free_context(state, hero, skill_id, source_name)


static func normalized_pool(authored_pool: Array) -> Array[String]:
	var result := _unique_pool(authored_pool)
	return _unique_pool(DEFAULT_FREE_SKILL_IDS) if result.is_empty() else result


static func hero_context(state: Dictionary, hero: Dictionary, source_name: String, ultimate: bool) -> Dictionary:
	return _hero_context(state, hero, hero["ex_skill"], ultimate, source_name)


static func _exclusive_choice(
	state: Dictionary,
	hero: Dictionary,
	registry: Variant,
	ports: Variant,
	catalogs: Dictionary,
	errors: Array[String],
) -> Dictionary:
	var skill_id: String = hero["ex_skill"]
	# These two Web enemy exclusives are never selectable.
	if skill_id in ["counterAura", "shadow"]:
		return {}
	var ability: Variant = catalogs.get("hero_abilities", {}).get("exclusive", {}).get(skill_id)
	if ability == null:
		return {}
	var effect_id: Variant = ability.handler_id
	if typeof(effect_id) != TYPE_STRING or not registry.has(effect_id):
		return {}
	var cost := exclusive_cost(state, hero, ports, errors)
	if not errors.is_empty() or cost < 0 or float(state["enemy_sp"]) < float(cost):
		return {}
	var context := _hero_context(state, hero, skill_id, false, str(hero["name"]))
	var usable_errors: Array[String] = []
	if not _hero_usable(skill_id, false, effect_id, context, ports, usable_errors):
		return {}
	return _choice("exclusive", skill_id, effect_id, cost)


static func exclusive_cost(
	state: Dictionary,
	hero: Dictionary,
	ports: Variant,
	errors: Array[String] = [],
) -> int:
	errors.clear()
	match hero.get("ex_skill"):
		"burn01":
			var next_cast := int(state["enemy_burn_ex_cast_count"]) + 1
			return 1 if next_cast == 1 else 2 if next_cast == 2 else 4 if next_cast == 3 else 8
		"fate", "puppet", "fist", "siege":
			return 1
		"burnEnchant":
			return 2
		"ascend":
			var tuning: Variant = ports.service("tuning", errors)
			if not errors.is_empty():
				return -1
			var value: Variant = _tuning_value(tuning, "ascendCost")
			if typeof(value) != TYPE_INT or value < 0:
				errors.append("ascendCost must be a non-negative integer")
				return -1
			return value
	return -1


static func _hero_usable(
	skill_id: String,
	ultimate: bool,
	effect_id: String,
	context: Dictionary,
	ports: Variant,
	errors: Array[String],
) -> bool:
	if skill_id in ["burn01", "fate", "burnEnchant"]:
		return FlameFateEffectsScript.is_usable(effect_id, context, ports, errors)
	if skill_id in ["ascend", "counterAura", "fist"]:
		return MarshalFistEffectsScript.is_usable(skill_id, ultimate, context, ports, errors)
	if skill_id in ["siege", "puppet", "shadow"]:
		return SiegePuppetShadowEffectsScript.is_usable(skill_id, ultimate, context, ports, errors)
	errors.append("unknown enemy hero ability: %s" % skill_id)
	return false


static func _free_context(state: Dictionary, hero: Dictionary, skill_id: String, source_name: String) -> Dictionary:
	return {
		"state": state,
		"caster_side": "enemy",
		"caster_id": hero["id"],
		"caster_name": hero["name"],
		"caster_base_crit_rate": hero["base_crit_rate"],
		"source_effect": _source_effect("free_skill", skill_id, source_name, hero),
	}


static func _hero_context(
	state: Dictionary,
	hero: Dictionary,
	skill_id: String,
	ultimate: bool,
	source_name: String,
) -> Dictionary:
	return {
		"state": state,
		"caster": hero,
		"source_effect": _source_effect("ultimate" if ultimate else "exclusive_skill", skill_id, source_name, hero),
	}


static func _source_effect(source_type: String, source_id: String, source_name: String, hero: Dictionary) -> Dictionary:
	return {
		"source_type": source_type,
		"source_id": source_id,
		"source_name": source_name,
		"source_side": "enemy",
		"source_actor_id": hero["id"],
		"counts_as_skill_cast": true,
		"spent_skill_points": false,
		"free_cast": false,
		"counts_as_basic_attack": false,
		"counts_as_attack": false,
		"triggers_enemy_kill_effects": true,
	}


static func _validate_inputs(
	state: Variant,
	hero: Variant,
	registry: Variant,
	ports: Variant,
	errors: Array[String],
) -> bool:
	if not BattleStateScript.validate(state, errors):
		return false
	if typeof(hero) != TYPE_DICTIONARY:
		errors.append("enemy policy hero must be a Dictionary")
		return false
	var canonical: Variant = null
	for candidate: Dictionary in state["enemy_heroes"]:
		if candidate["id"] == hero.get("id"):
			canonical = candidate
			break
	if canonical == null or not is_same(canonical, hero):
		errors.append("enemy policy hero must be the canonical state enemy hero reference")
		return false
	if (
		typeof(registry) != TYPE_OBJECT or registry == null
		or registry.get_script() != EffectRegistryScript
	):
		errors.append("enemy policy requires EffectRegistry")
		return false
	if (
		typeof(ports) != TYPE_OBJECT or ports == null
		or ports.get_script() != CombatPortsScript or not ports.is_valid()
	):
		errors.append("enemy policy requires valid CombatPorts")
		return false
	return true


static func _skill_locked(state: Dictionary) -> bool:
	return (
		state["fate"]["enemy_lock"] == "noSkill"
		or (
			state["enemy_fate"]["active"]
			and state["enemy_fate"]["mode"] == "棋子命运"
			and int(state["enemy_fate"]["all_in_turns"]) <= 0
		)
	)


static func _unique_pool(value: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in value:
		if typeof(raw_id) == TYPE_STRING and raw_id not in result:
			result.append(raw_id)
	return result


static func _choice(kind: String, skill_id: String, effect_id: String, cost: int) -> Dictionary:
	return {"kind": kind, "skill_id": skill_id, "effect_id": effect_id, "actual_sp_cost": cost}


static func _skip(reason: String, recover: bool, pool: Array) -> Dictionary:
	return _closed_plan({
		"kind": "skip", "reason": reason, "skip_recover": recover,
		"action": "", "skill_id": "", "effect_id": "", "actual_sp_cost": 0,
		"pool": pool.duplicate(true), "eligible_choices": [], "weighted_choices": [],
	})


static func _plan(
	selected: Dictionary,
	pool: Array,
	eligible: Array[Dictionary],
	weighted: Array[Dictionary],
) -> Dictionary:
	return _closed_plan({
		"kind": "action", "reason": "", "skip_recover": false,
		"action": selected["kind"], "skill_id": selected["skill_id"],
		"effect_id": selected["effect_id"], "actual_sp_cost": selected["actual_sp_cost"],
		"pool": pool.duplicate(true), "eligible_choices": eligible.duplicate(true),
		"weighted_choices": weighted.duplicate(true),
	})


static func _closed_plan(value: Dictionary) -> Dictionary:
	var result := {}
	for key in PLAN_KEYS:
		result[key] = value[key]
	return result


static func _tuning_value(tuning: Dictionary, id: String) -> Variant:
	var definition: Variant = tuning.get(id)
	return definition.get("value") if definition != null else null
