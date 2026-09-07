class_name EnemySkillAdapter
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const PolicyScript = preload("res://systems/enemy_ai/enemy_skill_policy.gd")

const EVENT_FREE := "freeSkillCast"
const EVENT_EXCLUSIVE := "exclusiveCast"
const EVENT_ULTIMATE := "ultimateCast"
const RESULT_KEYS := [
	"hero_id", "status", "skip_reason", "skill_kind", "skill_id",
	"actual_sp_cost", "pre_ultimate", "post_ultimate", "ultimate_casts",
	"enemy_sp_before", "enemy_sp_after", "energy_before", "energy_after",
	"fate_sp_gained",
]


static func resolve_hero_phase(
	state: Variant,
	hero: Variant,
	registry: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_inputs(state, hero, registry, ports, errors):
		return _fail(errors)
	var sp_before: float = float(state["enemy_sp"])
	var energy_before: float = float(hero["energy"])
	var pre_ultimate := false
	var post_ultimate := false
	var fate_before := int(state["enemy_fate"]["skill_sp_gain_this_round"])

	var ult_plan := PolicyScript.ultimate_plan(state, hero, registry, ports, errors)
	if not errors.is_empty():
		return _fail(errors)
	if ult_plan["castable"]:
		var pre_result := _cast_ultimate(state, hero, ult_plan, registry, ports)
		if not pre_result["ok"]:
			return _phase_failure("pre-skill ultimate failed", pre_result["error"], true, false)
		pre_ultimate = true

	var plan := PolicyScript.build_plan(state, hero, registry, ports, errors)
	if not errors.is_empty() or plan.is_empty():
		return _fail(errors)
	if plan["kind"] == "skip":
		if plan["skip_recover"]:
			var recovered := _skip_recover(state, ports, errors)
			if not errors.is_empty():
				return _phase_failure("skip recovery failed", errors[0], pre_ultimate, false)
			if recovered < 0:
				return _phase_failure("skip recovery failed", "invalid recovery", pre_ultimate, false)
		return CombatPortsScript.ok(_result({
			"hero_id": hero["id"], "status": "skipped", "skip_reason": plan["reason"],
			"skill_kind": "", "skill_id": "", "actual_sp_cost": 0,
			"pre_ultimate": pre_ultimate, "post_ultimate": false,
			"ultimate_casts": 1 if pre_ultimate else 0,
			"enemy_sp_before": sp_before, "enemy_sp_after": state["enemy_sp"],
			"energy_before": energy_before, "energy_after": hero["energy"],
			"fate_sp_gained": int(state["enemy_fate"]["skill_sp_gain_this_round"]) - fate_before,
		}))

	var skill_result := _cast_plan(state, hero, plan, registry, ports)
	if not skill_result["ok"]:
		return _phase_failure("enemy skill failed", skill_result["error"], pre_ultimate, false)

	# The initial threshold check owns the single ultimate allowance for this hero.
	# Only a hero that did not cast before its skill may cast immediately afterwards.
	if not pre_ultimate:
		ult_plan = PolicyScript.ultimate_plan(state, hero, registry, ports, errors)
		if not errors.is_empty():
			return _phase_failure("post-skill ultimate preflight failed", errors[0], false, false)
		if ult_plan["castable"]:
			var post_result := _cast_ultimate(state, hero, ult_plan, registry, ports)
			if not post_result["ok"]:
				return _phase_failure("post-skill ultimate failed", post_result["error"], false, true)
			post_ultimate = true

	return CombatPortsScript.ok(_result({
		"hero_id": hero["id"], "status": "cast", "skip_reason": "",
		"skill_kind": plan["action"], "skill_id": plan["skill_id"],
		"actual_sp_cost": plan["actual_sp_cost"],
		"pre_ultimate": pre_ultimate, "post_ultimate": post_ultimate,
		"ultimate_casts": (1 if pre_ultimate or post_ultimate else 0),
		"enemy_sp_before": sp_before, "enemy_sp_after": state["enemy_sp"],
		"energy_before": energy_before, "energy_after": hero["energy"],
		"fate_sp_gained": int(state["enemy_fate"]["skill_sp_gain_this_round"]) - fate_before,
	}))


static func cast_enemy_random_skill(
	state: Variant,
	hero: Variant,
	registry: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_inputs(state, hero, registry, ports, errors):
		return _fail(errors)
	var plan := PolicyScript.build_plan(state, hero, registry, ports, errors)
	if not errors.is_empty() or plan.is_empty():
		return _fail(errors)
	if plan["kind"] == "skip":
		if plan["skip_recover"]:
			_skip_recover(state, ports, errors)
			if not errors.is_empty():
				return _fail(errors)
		return CombatPortsScript.ok({
			"status": "skipped", "reason": plan["reason"], "recovered": plan["skip_recover"],
		})
	return _cast_plan(state, hero, plan, registry, ports)


static func cast_enemy_exclusive(
	state: Variant,
	hero: Variant,
	registry: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_inputs(state, hero, registry, ports, errors):
		return _fail(errors)
	var catalogs: Variant = ports.service("catalogs", errors)
	if not errors.is_empty():
		return _fail(errors)
	var skill_id: String = hero["ex_skill"]
	if skill_id in ["counterAura", "shadow"]:
		return CombatPortsScript.fail("enemy exclusive %s is not selectable" % skill_id)
	var ability: Variant = catalogs.get("hero_abilities", {}).get("exclusive", {}).get(skill_id)
	if ability == null:
		return CombatPortsScript.fail("unknown enemy exclusive: %s" % skill_id)
	var cost := PolicyScript.exclusive_cost(state, hero, ports, errors)
	if not errors.is_empty() or cost < 0:
		return _fail(errors)
	var plan := {
		"kind": "action", "action": "exclusive", "skill_id": skill_id,
		"effect_id": str(ability.handler_id), "actual_sp_cost": cost,
	}
	# Reuse the complete policy preflight so direct calls cannot bypass usability.
	var policy_plan := PolicyScript.build_plan(state, hero, registry, ports, errors)
	if not errors.is_empty():
		return _fail(errors)
	var eligible := false
	for choice: Dictionary in policy_plan.get("eligible_choices", []):
		if choice["kind"] == "exclusive" and choice["skill_id"] == skill_id:
			eligible = true
			break
	if not eligible:
		return CombatPortsScript.fail("enemy exclusive %s is unusable or unaffordable" % skill_id)
	return _cast_plan(state, hero, plan, registry, ports)


static func _cast_plan(
	state: Dictionary,
	hero: Dictionary,
	plan: Dictionary,
	registry: Variant,
	ports: Variant,
) -> Dictionary:
	var cost := int(plan["actual_sp_cost"])
	if float(state["enemy_sp"]) < float(cost):
		return CombatPortsScript.fail("enemy skill payment preflight failed: insufficient enemy SP")
	var catalogs_errors: Array[String] = []
	var catalogs: Variant = ports.service("catalogs", catalogs_errors)
	if not catalogs_errors.is_empty():
		return CombatPortsScript.fail(catalogs_errors[0])
	var context: Dictionary
	var event_id: String
	if plan["action"] == "free":
		var definition: Variant = catalogs["skills"].get(plan["skill_id"])
		if definition == null:
			return CombatPortsScript.fail("enemy free skill disappeared after preflight")
		context = PolicyScript.free_context(state, hero, plan["skill_id"], str(definition.name))
		event_id = EVENT_FREE
	else:
		context = PolicyScript.hero_context(state, hero, str(hero["name"]), false)
		event_id = EVENT_EXCLUSIVE

	# Web payment occurs after usable/preflight and before the effect itself.
	state["enemy_sp"] = float(state["enemy_sp"]) - float(cost)
	var registry_errors: Array[String] = []
	var executed: Dictionary = registry.execute(plan["effect_id"], context, ports, registry_errors)
	if not executed["ok"]:
		return CombatPortsScript.fail(
			"enemy %s handler failed after SP committed (%d): %s" % [
				plan["action"], cost, executed["error"],
			]
		)
	var event := _emit_cast_event(state, hero, event_id, cost, context["source_effect"], ports)
	if not event["ok"]:
		return CombatPortsScript.fail(
			"enemy %s content event failed after SP/effect committed: %s" % [plan["action"], event["error"]]
		)
	_gain_legacy_energy(hero, 20 + 10 * cost)
	var fate_gained := _grant_enemy_fate_sp(state)
	return CombatPortsScript.ok({
		"status": "cast", "kind": plan["action"], "skill_id": plan["skill_id"],
		"effect_id": plan["effect_id"], "actual_sp_cost": cost,
		"energy_gain": 20 + 10 * cost, "fate_sp_gained": fate_gained,
		"effect_value": ContextsScript.snapshot(executed["value"]),
	})


static func _cast_ultimate(
	state: Dictionary,
	hero: Dictionary,
	plan: Dictionary,
	registry: Variant,
	ports: Variant,
) -> Dictionary:
	var cost := int(plan["energy_cost"])
	if float(hero["energy"]) < float(cost):
		return CombatPortsScript.fail("enemy ultimate energy preflight failed")
	var context := PolicyScript.hero_context(state, hero, plan["source_name"], true)
	hero["energy"] = maxf(0.0, float(hero["energy"]) - float(cost))
	var registry_errors: Array[String] = []
	var executed: Dictionary = registry.execute(plan["effect_id"], context, ports, registry_errors)
	if not executed["ok"]:
		return CombatPortsScript.fail(
			"enemy ultimate handler failed after %d energy committed: %s" % [cost, executed["error"]]
		)
	var event := _emit_cast_event(state, hero, EVENT_ULTIMATE, 0, context["source_effect"], ports)
	if not event["ok"]:
		return CombatPortsScript.fail(
			"enemy ultimate content event failed after energy/effect committed: %s" % event["error"]
		)
	# This +20 is intentionally the enemy legacy formula only. Player M3 must not
	# call or reuse this adapter.
	_gain_legacy_energy(hero, 20)
	return CombatPortsScript.ok({
		"status": "cast", "kind": "ultimate", "skill_id": hero["ex_skill"],
		"effect_id": plan["effect_id"], "energy_cost": cost, "energy_gain": 20,
		"effect_value": ContextsScript.snapshot(executed["value"]),
	})


static func _emit_cast_event(
	state: Dictionary,
	hero: Dictionary,
	event_id: String,
	amount: int,
	source_effect: Dictionary,
	ports: Variant,
) -> Dictionary:
	var payload := {
		"round": state["round"],
		"hero": ContextsScript.snapshot(hero),
		"source_effect": ContextsScript.snapshot(source_effect),
	}
	if event_id != EVENT_ULTIMATE:
		payload["amount"] = amount
	return ports.call_action("emit_content_event", {
		"event_id": event_id,
		"payload": payload,
	})


static func _grant_enemy_fate_sp(state: Dictionary) -> int:
	var fate: Dictionary = state["enemy_fate"]
	var enabled: bool = bool(fate["active"]) and (
		fate["mode"] == "技能命运" or int(fate["all_in_turns"]) > 0
	)
	if not enabled or int(fate["skill_sp_gain_this_round"]) >= 3:
		return 0
	state["enemy_sp"] = minf(float(state["enemy_sp_max"]), float(state["enemy_sp"]) + 1.0)
	fate["skill_sp_gain_this_round"] = int(fate["skill_sp_gain_this_round"]) + 1
	return 1


static func _skip_recover(state: Dictionary, ports: Variant, errors: Array[String]) -> int:
	var tuning: Variant = ports.service("tuning", errors)
	if not errors.is_empty():
		return -1
	var definition: Variant = tuning.get("skipRecover")
	var amount: Variant = definition.get("value") if definition != null else null
	if typeof(amount) != TYPE_INT or amount < 0:
		errors.append("skipRecover must be a non-negative integer")
		return -1
	state["enemy_sp"] = minf(float(state["enemy_sp_max"]), float(state["enemy_sp"]) + float(amount))
	return amount


static func _gain_legacy_energy(hero: Dictionary, amount: int) -> void:
	hero["energy"] = minf(float(hero["max_energy"]), float(hero["energy"]) + float(amount))


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
		errors.append("enemy adapter hero must be a Dictionary")
		return false
	var found := false
	for candidate: Dictionary in state["enemy_heroes"]:
		if candidate["id"] == hero.get("id") and is_same(candidate, hero):
			found = true
			break
	if not found:
		errors.append("enemy adapter hero must be the canonical state enemy hero reference")
		return false
	if (
		typeof(registry) != TYPE_OBJECT or registry == null
		or registry.get_script() != EffectRegistryScript
	):
		errors.append("enemy adapter requires EffectRegistry")
		return false
	if (
		typeof(ports) != TYPE_OBJECT or ports == null
		or ports.get_script() != CombatPortsScript or not ports.is_valid()
	):
		errors.append("enemy adapter requires valid CombatPorts")
		return false
	return true


static func _result(values: Dictionary) -> Dictionary:
	var result := {}
	for key in RESULT_KEYS:
		result[key] = values[key]
	return result


static func _phase_failure(prefix: String, detail: String, pre: bool, post_started: bool) -> Dictionary:
	return CombatPortsScript.fail(
		"%s (pre_ultimate_committed=%s, prior_skill_or_post_payment_committed=%s): %s" % [
			prefix, str(pre), str(post_started), detail,
		]
	)


static func _fail(errors: Array[String]) -> Dictionary:
	return CombatPortsScript.fail(errors[0] if not errors.is_empty() else "invalid enemy skill adapter input")
