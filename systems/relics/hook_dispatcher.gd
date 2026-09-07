class_name HookDispatcher
extends RefCounted

## Resolver contract: condition/effect/adaptor Callables must have the declared
## signature and must report failures as structured data. GDScript cannot catch
## arbitrary runtime errors. Effect resolvers count only when returning
## {"ok": true}; any other result is reported and isolated from later hooks.

const LIMIT_NONE := "none"
const LIMIT_PER_BATTLE := "perBattle"
const LIMIT_PER_ROUND := "perRound"
const LIMIT_ONCE_PER_RUN := "oncePerRun"
const LIMIT_FIRST_N_ROUNDS := "firstNRoundsPerBattle"
const SCOPE_EVENT := "event"
const SCOPE_ACTOR := "actor"
const SCOPE_TARGET := "target"

const LIMITS := [
	LIMIT_NONE,
	LIMIT_PER_BATTLE,
	LIMIT_PER_ROUND,
	LIMIT_ONCE_PER_RUN,
	LIMIT_FIRST_N_ROUNDS,
]
const SCOPES := [SCOPE_EVENT, SCOPE_ACTOR, SCOPE_TARGET]
const EVENT_ALIASES := {
	"battle_start": "battleStart",
	"round_start": "roundStart",
	"round_end": "roundEnd",
	"skill_point_spent": "skillPointSpent",
	"basic_attack_hit": "basicAttackHit",
	"piece_attack_hit": "pieceAttackHit",
	"unit_damaged": "unitDamaged",
	"unit_blocked": "unitBlocked",
	"unit_died": "unitDied",
	"ultimate_cast": "ultimateCast",
	"exclusive_cast": "exclusiveCast",
	"free_skill_cast": "freeSkillCast",
	"hp_threshold_crossed": "hpThresholdCrossed",
}

var _event_ids := {}
var _on_error: Callable
var _valid := false
var _listeners := {}
var _definition_ids := {}
var _trigger_counts := {}
var _registration_in_progress := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("hook dispatcher config must be a Dictionary")
		return
	var event_catalog: Variant = config.get("event_catalog")
	if typeof(event_catalog) != TYPE_DICTIONARY or event_catalog.is_empty():
		errors.append("event_catalog must be a non-empty Dictionary")
	else:
		for event_id in event_catalog:
			if typeof(event_id) != TYPE_STRING or str(event_id).strip_edges().is_empty():
				errors.append("event_catalog keys must be non-empty strings")
			else:
				_event_ids[event_id] = true
	var on_error: Variant = config.get("on_error")
	if typeof(on_error) != TYPE_CALLABLE or not on_error.is_valid():
		errors.append("on_error must be an explicitly injected valid Callable")
	else:
		_on_error = on_error
	_valid = errors.is_empty()


func is_valid() -> bool:
	return _valid


func register_catalog(
	catalog: Variant,
	options: Variant = {},
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if not _valid:
		errors.append("hook dispatcher config is invalid")
		return false
	if _registration_in_progress:
		errors.append("register_catalog does not allow reentrant registration")
		return false
	_registration_in_progress = true
	var succeeded: bool = _register_catalog_once(catalog, options, errors)
	_registration_in_progress = false
	return succeeded


func dispatch(
	event_id: Variant,
	payload: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _valid:
		errors.append("hook dispatcher config is invalid")
		return {}
	var event: String = _canonical_event(event_id)
	if event.is_empty() or not _event_ids.has(event):
		errors.append("unknown content event: %s" % str(event_id))
		return {}
	if payload == null:
		payload = {}
	if typeof(payload) != TYPE_DICTIONARY:
		errors.append("hook dispatch payload must be a Dictionary")
		return {}
	var delivered := 0
	var bucket: Array = _listeners.get(event, []).duplicate(false)
	for listener in bucket:
		var context: Dictionary = _context_snapshot(payload, event, listener["actions"])
		var enabled_result: Dictionary = _call_gate(
			listener["is_enabled"],
			[_snapshot(listener["definition"]), _snapshot(context)],
			"enabled",
			listener,
		)
		if not enabled_result["ok"] or not enabled_result["matched"]:
			continue
		if not _is_allowed(listener["definition"], listener["hook"], context):
			continue
		var subjects_result: Dictionary = _call_subjects(listener, context)
		if not subjects_result["ok"]:
			continue
		for subject in subjects_result["subjects"]:
			var condition_result: Dictionary = _resolve_condition(listener, context, subject)
			if not condition_result["ok"] or not condition_result["matched"]:
				continue
			var effect_result: Variant = listener["effect_resolver"].call(
				_context_snapshot(context, event, listener["actions"]),
				subject,
				_snapshot(listener["hook"]["effect_params"]),
			)
			if not _successful_effect(effect_result):
				_report(_result_error(effect_result, "effect resolver must return {ok:true}"), listener, "effect")
				continue
			var scope_key: String = _scope_key(listener["hook"], context)
			if scope_key.is_empty():
				continue
			var key: String = _trigger_key(listener["definition"]["id"], listener["hook"]["hook_index"], scope_key)
			_trigger_counts[key] = int(_trigger_counts.get(key, 0)) + 1
			delivered += 1
			if not _is_allowed(listener["definition"], listener["hook"], context):
				break
	return {"event": event, "delivered": delivered}


func reset_battle() -> void:
	_reset_where(func(hook: Dictionary) -> bool:
		return hook["limit"] in [LIMIT_PER_BATTLE, LIMIT_PER_ROUND, LIMIT_FIRST_N_ROUNDS]
	)


func reset_round() -> void:
	_reset_where(func(hook: Dictionary) -> bool: return hook["limit"] == LIMIT_PER_ROUND)


func reset_run() -> void:
	_trigger_counts.clear()


func get_trigger_count(
	definition_id: String,
	hook_index: int,
	scope_key: String = SCOPE_EVENT,
) -> int:
	return int(_trigger_counts.get(_trigger_key(definition_id, hook_index, scope_key), 0))


func _register_catalog_once(catalog: Variant, options: Variant, errors: Array[String]) -> bool:
	if typeof(catalog) != TYPE_DICTIONARY:
		errors.append("catalog must be a Dictionary")
		return false
	if typeof(options) != TYPE_DICTIONARY:
		errors.append("catalog listener options must be a Dictionary")
		return false
	var is_enabled: Variant = options.get("is_enabled", func(_definition: Dictionary, _context: Dictionary) -> bool: return true)
	var get_subjects: Variant = options.get("get_subjects", func(_definition: Dictionary, _context: Dictionary) -> Array: return [null])
	var registry: Variant = options.get("resolver_registry")
	var actions: Variant = options.get("actions", {})
	if not _valid_callable(is_enabled) or not _valid_callable(get_subjects):
		errors.append("catalog listener adapters must be valid Callables")
	if typeof(registry) != TYPE_DICTIONARY:
		errors.append("resolver_registry must be an injected Dictionary")
		return false
	if typeof(actions) != TYPE_DICTIONARY:
		errors.append("actions must be an injected Dictionary")
		return false
	var conditions: Variant = registry.get("conditions")
	var effects: Variant = registry.get("effects")
	if typeof(conditions) != TYPE_DICTIONARY or typeof(effects) != TYPE_DICTIONARY:
		errors.append("resolver_registry must contain conditions and effects Dictionaries")
		return false
	if not errors.is_empty():
		return false

	var pending_definitions: Array = []
	var incoming_ids := {}
	for catalog_key in catalog:
		var normalized: Dictionary = _normalize_definition(catalog[catalog_key], str(catalog_key), conditions, effects, errors)
		if normalized.is_empty():
			continue
		var definition_id: String = normalized["definition"]["id"]
		if incoming_ids.has(definition_id):
			errors.append("duplicate definition id in catalog: %s" % definition_id)
		elif _definition_ids.has(definition_id):
			errors.append("duplicate registered definition id: %s" % definition_id)
		else:
			incoming_ids[definition_id] = true
		pending_definitions.append(normalized)
	if not errors.is_empty():
		return false

	var next_listeners: Dictionary = _listeners.duplicate(true)
	var next_definition_ids: Dictionary = _definition_ids.duplicate(true)
	for normalized in pending_definitions:
		var definition: Dictionary = normalized["definition"]
		next_definition_ids[definition["id"]] = true
		for hook in definition["hooks"]:
			var bucket: Array = next_listeners.get(hook["event"], [])
			bucket.append({
				"definition": _snapshot(definition),
				"hook": _snapshot(hook),
				"condition_resolver": normalized["condition_resolvers"].get(hook["hook_index"]),
				"effect_resolver": normalized["effect_resolvers"][hook["hook_index"]],
				"is_enabled": is_enabled,
				"get_subjects": get_subjects,
				"actions": actions.duplicate(true),
			})
			next_listeners[hook["event"]] = bucket
	_listeners = next_listeners
	_definition_ids = next_definition_ids
	return true


func _normalize_definition(
	raw_definition: Variant,
	catalog_key: String,
	conditions: Dictionary,
	effects: Dictionary,
	errors: Array[String],
) -> Dictionary:
	if typeof(raw_definition) != TYPE_DICTIONARY and not raw_definition is Resource:
		errors.append("catalog entry %s definition must be a Dictionary or Resource" % catalog_key)
		return {}
	var definition_id: Variant = raw_definition.get("id")
	var raw_hooks: Variant = raw_definition.get("hooks")
	if typeof(definition_id) != TYPE_STRING or definition_id != str(definition_id).strip_edges() or definition_id.is_empty():
		errors.append("catalog entry %s definition id must be a non-empty trimmed string" % catalog_key)
		return {}
	if typeof(raw_hooks) != TYPE_ARRAY:
		errors.append("definition %s hooks must be an Array" % definition_id)
		return {}
	var hooks: Array = []
	var condition_resolvers := {}
	var effect_resolvers := {}
	for hook_index in raw_hooks.size():
		var hook: Dictionary = _normalize_hook(raw_hooks[hook_index], definition_id, hook_index, conditions, effects, errors)
		if hook.is_empty():
			continue
		hooks.append(hook)
		if not hook["condition_id"].is_empty():
			condition_resolvers[hook_index] = conditions[hook["condition_id"]]
		effect_resolvers[hook_index] = effects[hook["effect_id"]]
	return {
		"definition": {"id": definition_id, "hooks": hooks},
		"condition_resolvers": condition_resolvers,
		"effect_resolvers": effect_resolvers,
	}


func _normalize_hook(
	raw_hook: Variant,
	definition_id: String,
	hook_index: int,
	conditions: Dictionary,
	effects: Dictionary,
	errors: Array[String],
) -> Dictionary:
	var path := "definition %s hook[%d]" % [definition_id, hook_index]
	if typeof(raw_hook) != TYPE_DICTIONARY:
		errors.append("%s must be a Dictionary" % path)
		return {}
	var event: Variant = raw_hook.get("event", raw_hook.get("event_id"))
	var limit: Variant = raw_hook.get("limit")
	var limit_scope: Variant = raw_hook.get("limit_scope", SCOPE_EVENT)
	var limit_value: Variant = raw_hook.get("limit_value")
	var declared_index: Variant = raw_hook.get("hook_index")
	var condition_id: Variant = raw_hook.get("condition_id", "")
	var effect_id: Variant = raw_hook.get("effect_id")
	if typeof(event) != TYPE_STRING or not _event_ids.has(event):
		errors.append("%s event must be a known content event: %s" % [path, str(event)])
	if limit not in LIMITS:
		errors.append("%s limit is invalid: %s" % [path, str(limit)])
	if limit_scope not in SCOPES:
		errors.append("%s limit_scope is invalid: %s" % [path, str(limit_scope)])
	if typeof(limit_value) != TYPE_INT or limit_value < 1:
		errors.append("%s limit_value must be a positive integer" % path)
	if typeof(declared_index) != TYPE_INT or declared_index != hook_index:
		errors.append("%s hook_index must equal %d" % [path, hook_index])
	if typeof(condition_id) != TYPE_STRING:
		errors.append("%s condition_id must be a string" % path)
	elif not condition_id.is_empty() and (not conditions.has(condition_id) or not _valid_callable(conditions[condition_id])):
		errors.append("%s references unknown condition resolver: %s" % [path, condition_id])
	if typeof(effect_id) != TYPE_STRING or effect_id.strip_edges().is_empty():
		errors.append("%s effect_id must be a non-empty string" % path)
	elif not effects.has(effect_id) or not _valid_callable(effects[effect_id]):
		errors.append("%s references unknown effect resolver: %s" % [path, str(effect_id)])
	var condition_params: Variant = raw_hook.get("condition_params", {})
	var effect_params: Variant = raw_hook.get("effect_params", {})
	if typeof(condition_params) != TYPE_DICTIONARY or _contains_callable(condition_params):
		errors.append("%s condition_params must contain static Dictionary data" % path)
	if typeof(effect_params) != TYPE_DICTIONARY or _contains_callable(effect_params):
		errors.append("%s effect_params must contain static Dictionary data" % path)
	if not errors.is_empty():
		return {}
	return {
		"event": event,
		"limit": limit,
		"limit_scope": limit_scope,
		"limit_value": limit_value,
		"hook_index": hook_index,
		"condition_id": condition_id,
		"effect_id": effect_id,
		"condition_params": condition_params.duplicate(true),
		"effect_params": effect_params.duplicate(true),
	}


func _resolve_condition(listener: Dictionary, context: Dictionary, subject: Variant) -> Dictionary:
	var resolver: Variant = listener["condition_resolver"]
	if resolver == null:
		return {"ok": true, "matched": true}
	var result: Variant = resolver.call(
		_context_snapshot(context, listener["hook"]["event"], listener["actions"]),
		subject,
		_snapshot(listener["hook"]["condition_params"]),
	)
	if typeof(result) == TYPE_BOOL:
		return {"ok": true, "matched": result}
	if typeof(result) == TYPE_DICTIONARY and typeof(result.get("ok")) == TYPE_BOOL:
		if not result["ok"]:
			_report(_result_error(result, "condition resolver failed"), listener, "condition")
			return {"ok": false, "matched": false}
		if typeof(result.get("matched")) == TYPE_BOOL:
			return {"ok": true, "matched": result["matched"]}
	_report("condition resolver returned an invalid result", listener, "condition")
	return {"ok": false, "matched": false}


func _call_gate(callback: Callable, arguments: Array, phase: String, listener: Dictionary) -> Dictionary:
	var result: Variant = callback.callv(arguments)
	if typeof(result) == TYPE_BOOL:
		return {"ok": true, "matched": result}
	if typeof(result) == TYPE_DICTIONARY and result.get("ok") == false:
		_report(_result_error(result, "%s adapter failed" % phase), listener, phase)
		return {"ok": false, "matched": false}
	_report("%s adapter must return bool or {ok:false,error}" % phase, listener, phase)
	return {"ok": false, "matched": false}


func _call_subjects(listener: Dictionary, context: Dictionary) -> Dictionary:
	var result: Variant = listener["get_subjects"].call(_snapshot(listener["definition"]), _snapshot(context))
	if typeof(result) == TYPE_DICTIONARY and result.get("ok") == false:
		_report(_result_error(result, "subjects adapter failed"), listener, "subjects")
		return {"ok": false, "subjects": []}
	if result == null:
		return {"ok": true, "subjects": []}
	if typeof(result) == TYPE_ARRAY:
		return {"ok": true, "subjects": result.duplicate(false)}
	return {"ok": true, "subjects": [result]}


func _is_allowed(definition: Dictionary, hook: Dictionary, context: Dictionary) -> bool:
	var scope_key: String = _scope_key(hook, context)
	if scope_key.is_empty():
		return false
	var count: int = get_trigger_count(definition["id"], hook["hook_index"], scope_key)
	match hook["limit"]:
		LIMIT_NONE:
			return true
		LIMIT_PER_BATTLE, LIMIT_PER_ROUND, LIMIT_ONCE_PER_RUN:
			return count < hook["limit_value"]
		LIMIT_FIRST_N_ROUNDS:
			var round_value: Variant = context.get("round", 0)
			return _finite_number(round_value) and float(round_value) <= float(hook["limit_value"])
	return false


func _scope_key(hook: Dictionary, context: Dictionary) -> String:
	var scope: String = hook["limit_scope"]
	if scope == SCOPE_EVENT:
		return SCOPE_EVENT
	var subject: Variant = context.get(scope)
	if typeof(subject) != TYPE_DICTIONARY:
		return ""
	var id: Variant = subject.get("id")
	if typeof(id) not in [TYPE_STRING, TYPE_INT]:
		return ""
	return "%s:%s:%s" % [scope, str(subject.get("side", "unknown")), str(id)]


func _reset_where(predicate: Callable) -> void:
	for bucket in _listeners.values():
		for listener in bucket:
			if not predicate.call(listener["hook"]):
				continue
			var prefix: String = "%s#%d#" % [listener["definition"]["id"], listener["hook"]["hook_index"]]
			for key in _trigger_counts.keys():
				if str(key).begins_with(prefix):
					_trigger_counts.erase(key)


func _context_snapshot(payload: Dictionary, event: String, actions: Dictionary) -> Dictionary:
	var context: Dictionary = _snapshot(payload)
	for reference_key in ["actor", "target", "unit", "attacker", "defender"]:
		if payload.has(reference_key):
			context[reference_key] = payload[reference_key]
	# Current Web payloads are camelCase while B0 emits snake_case. Preserve the
	# source keys for golden diagnostics and publish one snake_case system boundary.
	_copy_alias(context, "source_effect", "sourceEffect")
	_copy_alias(context, "source_side", "sourceSide")
	_copy_alias(context, "effect_context", "effectContext")
	_copy_alias(context, "damage_context", "damageContext")
	_copy_alias(context, "death_context", "deathContext")
	_copy_alias(context, "raw_amount_before_block", "rawAmountBeforeBlock")
	if typeof(context.get("source_effect")) == TYPE_DICTIONARY:
		context["source_effect"] = _normalized_effect_context(context["source_effect"])
	if typeof(context.get("effect_context")) == TYPE_DICTIONARY:
		context["effect_context"] = _normalized_effect_context(context["effect_context"])
	if typeof(context.get("damage_context")) == TYPE_DICTIONARY:
		context["damage_context"] = _normalized_damage_context(context["damage_context"])
	if typeof(context.get("death_context")) == TYPE_DICTIONARY:
		context["death_context"] = _normalized_death_context(context["death_context"])
	context["event"] = event
	context["actions"] = actions.duplicate(true)
	if not context.has("source_effect"):
		if context.has("effect_context"):
			context["source_effect"] = _snapshot(context["effect_context"])
		elif typeof(context.get("damage_context")) == TYPE_DICTIONARY:
			context["source_effect"] = _normalized_effect_context(context["damage_context"].get("effect", {}))
	if not context.has("death_context") and typeof(context.get("damage_context")) == TYPE_DICTIONARY:
		context["death_context"] = _snapshot(context["damage_context"].get("death_context", {}))
	if not context.has("raw_amount") and context.has("raw_amount_before_block"):
		context["raw_amount"] = context["raw_amount_before_block"]
	return context


func _canonical_event(event_id: Variant) -> String:
	if typeof(event_id) != TYPE_STRING:
		return ""
	return EVENT_ALIASES.get(event_id, event_id)


func _successful_effect(result: Variant) -> bool:
	return typeof(result) == TYPE_DICTIONARY and result.get("ok") == true


func _result_error(result: Variant, fallback: String) -> String:
	if typeof(result) == TYPE_DICTIONARY and result.has("error"):
		return str(result["error"])
	return fallback


func _report(message: String, listener: Dictionary, phase: String) -> void:
	# on_error is an explicit trusted port. A runtime error inside it cannot be
	# recovered by GDScript and therefore remains an application-boundary fault.
	_on_error.call(message, {
		"definition_id": listener["definition"]["id"],
		"hook_index": listener["hook"]["hook_index"],
		"event": listener["hook"]["event"],
		"phase": phase,
	})


static func _trigger_key(definition_id: String, hook_index: int, scope_key: String) -> String:
	return "%s#%d#%s" % [definition_id, hook_index, scope_key]


static func _copy_alias(target: Dictionary, snake_name: String, camel_name: String) -> void:
	if not target.has(snake_name) and target.has(camel_name):
		target[snake_name] = _snapshot(target[camel_name])


static func _normalized_effect_context(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var result: Dictionary = _snapshot(value)
	for field_pair in [
		["source_type", "sourceType"],
		["source_id", "sourceId"],
		["source_name", "sourceName"],
		["source_side", "sourceSide"],
		["source_actor_id", "sourceActorId"],
		["counts_as_skill_cast", "countsAsSkillCast"],
		["spent_skill_points", "spentSkillPoints"],
		["free_cast", "freeCast"],
		["counts_as_basic_attack", "countsAsBasicAttack"],
		["counts_as_attack", "countsAsAttack"],
		["triggers_enemy_kill_effects", "triggersEnemyKillEffects"],
	]:
		_copy_alias(result, field_pair[0], field_pair[1])
	return result


static func _normalized_damage_context(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var result: Dictionary = _snapshot(value)
	for field_pair in [
		["target_id", "targetId"],
		["raw_amount", "rawAmount"],
		["dealer_type", "dealerType"],
		["dealer_name", "dealerName"],
		["dealer_id", "dealerId"],
		["attacker_unit_id", "attackerUnitId"],
		["can_crit", "canCrit"],
		["crit_rate", "critRate"],
		["guaranteed_crit", "guaranteedCrit"],
		["can_block", "canBlock"],
	]:
		_copy_alias(result, field_pair[0], field_pair[1])
	if typeof(result.get("effect")) == TYPE_DICTIONARY:
		result["effect"] = _normalized_effect_context(result["effect"])
	return result


static func _normalized_death_context(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var result: Dictionary = _snapshot(value)
	for field_pair in [
		["source_kind", "sourceKind"],
		["source_side", "sourceSide"],
		["source_actor_id", "sourceActorId"],
		["triggers_enemy_kill_effects", "triggersEnemyKillEffects"],
	]:
		_copy_alias(result, field_pair[0], field_pair[1])
	if typeof(result.get("effect")) == TYPE_DICTIONARY:
		result["effect"] = _normalized_effect_context(result["effect"])
	return result


static func _valid_callable(value: Variant) -> bool:
	return typeof(value) == TYPE_CALLABLE and value.is_valid()


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _contains_callable(value: Variant) -> bool:
	if value is Callable or value is Object:
		return true
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if _contains_callable(item):
				return true
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if _contains_callable(key) or _contains_callable(value[key]):
				return true
	return false


static func _snapshot(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var copied: Array = []
		for item in value:
			copied.append(_snapshot(item))
		return copied
	if typeof(value) == TYPE_DICTIONARY:
		var copied := {}
		for key in value:
			copied[_snapshot(key)] = _snapshot(value[key])
		return copied
	return value
