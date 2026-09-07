class_name BurnSettlement
extends RefCounted

const Contexts = preload("res://core/contexts.gd")
const BURN_ID := "burn"

var _buff_system: Variant
var _damage_per_stack := 0.0
var _apply_damage_context: Callable
var _on_settled: Callable
var _valid := false

# Coordination belongs to this settlement service instance. Separate battles
# must construct separate instances; no cross-battle module/global marker exists.
var _settlement_depth := 0
var _settled_units: Array = []


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("burn settlement config must be a Dictionary")
		return
	var buffs: Variant = config.get("buff_system")
	if typeof(buffs) != TYPE_OBJECT:
		errors.append("buff_system must be an explicitly injected RefCounted service")
	elif (
		not buffs.has_method("validate_unit_holder")
		or not buffs.has_method("get_unit_stacks")
		or not buffs.has_method("decay_layers")
	):
		errors.append("buff_system must provide validation stack query and layer decay")
	var per_stack: Variant = config.get("damage_per_stack")
	if not _is_finite_number(per_stack):
		errors.append("damage_per_stack must be an explicitly injected finite number")
	var apply_value: Variant = config.get("apply_damage_context")
	if typeof(apply_value) != TYPE_CALLABLE or not apply_value.is_valid():
		errors.append("apply_damage_context must be an explicitly injected valid Callable")
	var settled_value: Variant = config.get("on_settled")
	if typeof(settled_value) != TYPE_CALLABLE or not settled_value.is_valid():
		errors.append("on_settled must be an explicitly injected valid Callable")
	if not errors.is_empty():
		return
	_buff_system = buffs
	_damage_per_stack = maxf(0.0, float(per_stack))
	_apply_damage_context = apply_value
	_on_settled = settled_value
	_valid = true


func is_valid() -> bool:
	return _valid


func is_active() -> bool:
	return _settlement_depth > 0


func settle(
	units: Variant,
	decay: bool = true,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	errors.clear()
	if not _valid:
		errors.append("burn settlement config is invalid")
		return []
	if typeof(units) != TYPE_ARRAY:
		errors.append("units must be an Array")
		return []
	# Static input is atomic: every candidate holder, Buff state, and initial
	# delayed context is validated before the first external damage call.
	if not _static_preflight(units, errors):
		return []

	var outermost := _settlement_depth == 0
	if outermost:
		_settled_units.clear()
	_settlement_depth += 1
	var results: Array[Dictionary] = []
	for candidate: Variant in units:
		# Calls are sequentially committed. A later callback/holder failure returns
		# the already committed result prefix; arbitrary external callbacks cannot
		# be transactionally rolled back by this pure coordinator.
		var holder_errors: Array[String] = []
		if not _buff_system.validate_unit_holder(candidate, holder_errors):
			_append_errors(holder_errors, errors)
			break
		if not bool(candidate["alive"]):
			continue
		var unit: Dictionary = candidate
		if _was_settled(unit):
			continue
		var stacks_before: int = _buff_system.get_unit_stacks(unit, BURN_ID)
		if stacks_before <= 0:
			continue

		# Mark before applying damage. Death callbacks may re-enter settle().
		_settled_units.append(unit)
		var context_errors: Array[String] = []
		var context := _create_burn_context(unit, stacks_before, context_errors)
		_append_errors(context_errors, errors)
		if context.is_empty():
			break

		var damage: Variant = _apply_damage_context.call(unit, Contexts.snapshot(context))
		var damage_errors: Array[String] = []
		if not _validate_damage_result(damage, context, damage_errors):
			_append_errors(damage_errors, errors)
			break
		var expired_stacks := 0
		if decay:
			var decay_errors: Array[String] = []
			expired_stacks = _buff_system.decay_layers(unit, BURN_ID, 1, decay_errors)
			_append_errors(decay_errors, errors)
			if not decay_errors.is_empty():
				break

		var result := {
			# unit is the sole intentional mutable reference in every result.
			"unit": unit,
			"stacks_before": stacks_before,
			"stacks_after": _buff_system.get_unit_stacks(unit, BURN_ID),
			"expired_stacks": expired_stacks,
			"damage": _deep_copy(damage),
			"damage_context": Contexts.snapshot(context),
		}
		results.append(_snapshot_result(result))
		_on_settled.call(_snapshot_result(result))

	_settlement_depth -= 1
	if outermost:
		_settled_units.clear()
	return _snapshot_results(results)


func _static_preflight(units: Array, errors: Array[String]) -> bool:
	for candidate: Variant in units:
		var holder_errors: Array[String] = []
		if not _buff_system.validate_unit_holder(candidate, holder_errors):
			_append_errors(holder_errors, errors)
			return false
		if not bool(candidate["alive"]):
			continue
		var stacks: int = _buff_system.get_unit_stacks(candidate, BURN_ID)
		if stacks <= 0:
			continue
		var context_errors: Array[String] = []
		if _create_burn_context(candidate, stacks, context_errors).is_empty():
			_append_errors(context_errors, errors)
			return false
	return true


func _create_burn_context(
	unit: Dictionary,
	stacks: int,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	var source_side := (
		Contexts.UNIT_SIDE["ENEMY"]
		if unit["side"] == Contexts.UNIT_SIDE["ALLY"]
		else Contexts.UNIT_SIDE["ALLY"]
	)
	var effect_errors: Array[String] = []
	var effect := Contexts.create_effect_context({
		"source_type": Contexts.EFFECT_SOURCE_TYPE["DELAYED_DAMAGE"],
		"source_id": "burn_tick",
		"source_name": "灼烧",
		"source_side": source_side,
		"source_actor_id": 0,
		"counts_as_attack": false,
		"counts_as_basic_attack": false,
	}, effect_errors)
	_append_errors(effect_errors, errors)
	if effect.is_empty():
		return {}
	var context_errors: Array[String] = []
	var context := Contexts.create_damage_context({
		"target_id": unit["id"],
		"raw_amount": stacks * _damage_per_stack,
		"category": Contexts.DAMAGE_CATEGORY["DELAYED"],
		"effect": effect,
		"dealer_type": "dot",
		"dealer_name": "灼烧",
		"dealer_id": 0,
		"can_crit": false,
		"guaranteed_crit": false,
		"can_block": false,
	}, context_errors)
	_append_errors(context_errors, errors)
	return context if errors.is_empty() else {}


static func _validate_damage_result(
	damage: Variant,
	expected_context: Dictionary,
	errors: Array[String],
) -> bool:
	if typeof(damage) != TYPE_DICTIONARY or damage.is_empty():
		errors.append("apply_damage_context must return a non-empty B0 DamagePipeline result")
		return false
	var required_keys := [
		"dealt", "blocked", "died", "crit", "damage_context", "death_context",
	]
	for key in required_keys:
		if not damage.has(key):
			errors.append("apply_damage_context result is missing required field: %s" % key)
	if not errors.is_empty():
		return false
	if not _is_finite_number(damage["dealt"]) or float(damage["dealt"]) < 0.0:
		errors.append("apply_damage_context result.dealt must be a non-negative finite number")
	for key in ["blocked", "died", "crit"]:
		if typeof(damage[key]) != TYPE_BOOL:
			errors.append("apply_damage_context result.%s must be a boolean" % key)
	if not errors.is_empty():
		return false
	if damage["blocked"] or damage["crit"]:
		errors.append("delayed burn result cannot be blocked or critical")
	if typeof(damage["damage_context"]) != TYPE_DICTIONARY:
		errors.append("apply_damage_context result.damage_context must be a Dictionary")
	else:
		var context_errors: Array[String] = []
		var normalized := Contexts.create_damage_context(damage["damage_context"], context_errors)
		_append_errors(context_errors, errors)
		if normalized != expected_context:
			errors.append("apply_damage_context result.damage_context must match the requested burn context")
	var death_context: Variant = damage["death_context"]
	if damage["died"]:
		if typeof(death_context) != TYPE_DICTIONARY:
			errors.append("lethal damage result must include death_context")
		else:
			var death_errors: Array[String] = []
			if Contexts.create_death_context(death_context, death_errors).is_empty():
				_append_errors(death_errors, errors)
	elif death_context != null:
		errors.append("non-lethal damage result.death_context must be null")
	return errors.is_empty()


func _was_settled(unit: Dictionary) -> bool:
	for settled: Variant in _settled_units:
		if is_same(settled, unit):
			return true
	return false


static func _snapshot_results(results: Array[Dictionary]) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for result: Dictionary in results:
		copied.append(_snapshot_result(result))
	return copied


static func _snapshot_result(result: Dictionary) -> Dictionary:
	var copied: Dictionary = _deep_copy(result)
	# Restore the documented mutable identity after copying all compound output.
	copied["unit"] = result["unit"]
	return copied


static func _deep_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var copied_array: Array = []
		for item: Variant in value:
			copied_array.append(_deep_copy(item))
		return copied_array
	if typeof(value) == TYPE_DICTIONARY:
		var copied_dictionary := {}
		for key: Variant in value:
			copied_dictionary[_deep_copy(key)] = _deep_copy(value[key])
		return copied_dictionary
	return value


static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message: String in source:
		destination.append(message)
