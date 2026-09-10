class_name EnemySpecialSystem
extends RefCounted

## Injected dependency ports and RNG must match their documented signatures and
## must not raise runtime errors; GDScript has no catch boundary. Recoverable
## mutator failures use {"ok": false, "error": "..."} before notifications.

const DEVOURER_ID := "devourer"
const ECHO_ID := "echo"
const ECHO_GROWTH := 0.01
const ENERGY_DRAIN := 10

var catalog := {}
var _dispatcher: Variant
var _get_enemies: Callable
var _get_active_heroes: Callable
var _get_skill_points: Callable
var _set_skill_points: Callable
var _gain_hero_energy: Callable
var _log: Callable
var _on_triggered: Callable
var _rng: Variant
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(config) != TYPE_DICTIONARY:
		errors.append("enemy special system config must be a Dictionary")
		return
	var configured_catalog: Variant = config.get("catalog")
	_dispatcher = config.get("dispatcher")
	_get_enemies = config.get("get_enemies", Callable())
	_get_active_heroes = config.get("get_active_heroes", Callable())
	_get_skill_points = config.get("get_skill_points", Callable())
	_set_skill_points = config.get("set_skill_points", Callable())
	_gain_hero_energy = config.get("gain_hero_energy", Callable())
	_log = config.get("log", Callable())
	_on_triggered = config.get("on_triggered", Callable())
	_rng = config.get("rng")
	if typeof(configured_catalog) != TYPE_DICTIONARY or configured_catalog.is_empty():
		errors.append("enemy special catalog must be a non-empty Dictionary")
	if _dispatcher == null or not _dispatcher.has_method("register_catalog"):
		errors.append("hook dispatcher is required")
	var dependencies := {
		"get_enemies": _get_enemies,
		"get_active_heroes": _get_active_heroes,
		"get_skill_points": _get_skill_points,
		"set_skill_points": _set_skill_points,
		"gain_hero_energy": _gain_hero_energy,
		"log": _log,
		"on_triggered": _on_triggered,
	}
	for dependency in dependencies:
		if not _valid_callable(dependencies[dependency]):
			errors.append("%s must be an injected valid Callable" % dependency)
	if _rng == null or not _rng.has_method("pick"):
		errors.append("injected RNG with pick(Array) is required")
	if not errors.is_empty():
		return
	catalog = configured_catalog.duplicate(true)
	var registration_errors: Array[String] = []
	var registered: bool = _dispatcher.register_catalog(catalog, {
		"get_subjects": Callable(self, "_subjects_for"),
		"resolver_registry": _resolver_registry(),
		"actions": {},
	}, registration_errors)
	for message in registration_errors:
		errors.append(message)
	_valid = registered and errors.is_empty()
	# Registration transfers the bound resolvers to the dispatcher; retaining it
	# here would create a RefCounted cycle at shutdown.
	_dispatcher = null


func is_valid() -> bool:
	return _valid


func get_definition(special_id: Variant) -> Variant:
	if typeof(special_id) != TYPE_STRING or not catalog.has(special_id):
		return null
	var definition: Variant = catalog[special_id]
	return definition.snapshot() if definition is Resource and definition.has_method("snapshot") else definition.duplicate(true)


func initialize_unit(
	unit: Variant,
	special_id: Variant,
	scale_stats: bool = true,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if not _valid:
		errors.append("enemy special system config is invalid")
		return false
	if typeof(unit) != TYPE_DICTIONARY:
		errors.append("unit must be a Dictionary")
		return false
	if typeof(special_id) != TYPE_STRING or not catalog.has(special_id):
		errors.append("unknown enemy special id: %s" % str(special_id))
		return false
	var definition: Variant = catalog[special_id]
	var next_max_hp: Variant = unit.get("max_hp")
	var next_hp: Variant = unit.get("hp")
	var next_atk: Variant = unit.get("atk")
	if scale_stats:
		for field in ["max_hp", "hp", "atk"]:
			if not _is_finite(unit.get(field)):
				errors.append("unit.%s must be a finite number" % field)
		if not _is_finite(definition.hp_scale) or float(definition.hp_scale) <= 0.0 \
		or not _is_finite(definition.atk_scale) or float(definition.atk_scale) <= 0.0:
			errors.append("enemy special stat scales must be positive finite numbers")
		if not errors.is_empty():
			return false
		next_max_hp = float(unit["max_hp"]) * float(definition.hp_scale)
		next_hp = float(unit["hp"]) * float(definition.hp_scale)
		next_atk = float(unit["atk"]) * float(definition.atk_scale)
	unit["special_id"] = definition.id
	unit["echo_damage_bonus"] = 0.0
	if scale_stats:
		unit["max_hp"] = next_max_hp
		unit["hp"] = next_hp
		unit["atk"] = next_atk
	return true


func devour_skill_point(
	self_unit: Variant,
	errors: Array[String] = [],
	source_context: Dictionary = {},
) -> bool:
	errors.clear()
	if not _valid:
		errors.append("enemy special system config is invalid")
		return false
	if typeof(self_unit) != TYPE_DICTIONARY or not bool(self_unit.get("alive", false)) \
	or self_unit.get("special_id") != DEVOURER_ID or not _is_current_enemy(self_unit):
		return false
	var skill_points: Variant = _get_skill_points.call()
	if not _is_finite(skill_points) or float(skill_points) < 0.0:
		errors.append("get_skill_points must return a non-negative finite number")
		return false
	if float(skill_points) > 0.0:
		var old_sp: float = float(skill_points)
		var new_sp: float = maxf(0.0, old_sp - 1.0)
		var set_result: Variant = _set_skill_points.call(new_sp)
		if _failed_result(set_result, "set_skill_points", errors):
			return false
		_notify_trigger({
			"special_id": DEVOURER_ID,
			"kind": "sp_drain",
			"actor": _actor_snapshot(self_unit),
			"source_action_id": _source_action_id(source_context),
			"source_effect": _source_effect(source_context),
			"resource": "sp",
			"old_sp": old_sp,
			"new_sp": new_sp,
			"amount": old_sp - new_sp,
		})
		_log.call("%s吞噬1点我方技能点。" % str(self_unit.get("name", "噬元兽")), "bad")
		return true

	var raw_heroes: Variant = _get_active_heroes.call()
	if typeof(raw_heroes) != TYPE_ARRAY:
		errors.append("get_active_heroes must return an Array")
		return false
	var heroes: Array = []
	# get_active_heroes is the authoritative deployed/active list. Hero records in
	# the Web schema do not carry unit.alive; only reject null/non-Dictionary data.
	for hero in raw_heroes:
		if typeof(hero) == TYPE_DICTIONARY:
			heroes.append(hero)
	if heroes.is_empty():
		return false
	var hero: Variant = _rng.pick(heroes)
	if typeof(hero) != TYPE_DICTIONARY or not _contains_same_unit(heroes, hero):
		errors.append("injected RNG returned a hero outside the surviving candidates")
		return false
	var old_energy: float = float(hero.get("energy", 0.0))
	var gain_result: Variant = _gain_hero_energy.call(hero, -ENERGY_DRAIN)
	if _failed_result(gain_result, "gain_hero_energy", errors):
		return false
	var new_energy: float = float(hero.get("energy", old_energy))
	_notify_trigger({
		"special_id": DEVOURER_ID,
		"kind": "energy_drain",
		"actor": _actor_snapshot(self_unit),
		"source_action_id": _source_action_id(source_context),
		"source_effect": _source_effect(source_context),
		"resource": "hero_energy",
		"old_sp": 0.0,
		"new_sp": 0.0,
		"amount": maxf(0.0, old_energy - new_energy),
		"target": {
			"hero_id": hero.get("id", 0),
			"old_energy": old_energy,
			"new_energy": new_energy,
		},
	})
	_log.call("%s吞噬%s10点能量。" % [str(self_unit.get("name", "噬元兽")), str(hero.get("name", hero.get("id", "")))], "bad")
	return true


func reset_battle(errors: Array[String] = []) -> bool:
	errors.clear()
	var enemies: Array = _current_enemies(errors)
	if not errors.is_empty():
		return false
	for enemy in enemies:
		if typeof(enemy) == TYPE_DICTIONARY and catalog.has(enemy.get("special_id")):
			enemy["echo_damage_bonus"] = 0.0
	return true


func get_echo_damage_bonus(unit: Variant) -> float:
	if typeof(unit) != TYPE_DICTIONARY or unit.get("special_id") != ECHO_ID or not _is_current_enemy(unit):
		return 0.0
	var value: Variant = unit.get("echo_damage_bonus", 0.0)
	return maxf(0.0, float(value)) if _is_finite(value) else 0.0


func get_outgoing_damage_multiplier(unit: Variant, base_multiplier: Variant = 1.0) -> float:
	var base: float = maxf(0.0, float(base_multiplier)) if _is_finite(base_multiplier) else 1.0
	return base * (1.0 + get_echo_damage_bonus(unit))


func _resolver_registry() -> Dictionary:
	return {
		"conditions": {
			"enemy_special.devourer.hook.0.when": Callable(self, "_condition_devourer"),
			"enemy_special.echo.hook.0.when": Callable(self, "_condition_echo"),
		},
		"effects": {
			"enemy_special.devourer.hook.0.effect": Callable(self, "_effect_devourer"),
			"enemy_special.echo.hook.0.effect": Callable(self, "_effect_echo"),
		},
	}


func _subjects_for(definition: Dictionary, _context: Dictionary) -> Variant:
	var errors: Array[String] = []
	var enemies: Array = _current_enemies(errors)
	if not errors.is_empty():
		return {"ok": false, "error": errors[0]}
	var subjects: Array = []
	for enemy in enemies:
		if typeof(enemy) == TYPE_DICTIONARY and bool(enemy.get("alive", false)) \
		and enemy.get("special_id") == definition["id"]:
			subjects.append(enemy)
	return subjects


func _condition_devourer(context: Dictionary, subject: Variant, _params: Dictionary) -> bool:
	return _same_unit(context.get("actor"), subject)


func _condition_echo(context: Dictionary, subject: Variant, _params: Dictionary) -> bool:
	if not _same_unit(context.get("target"), subject):
		return false
	var damage_context: Variant = context.get("damage_context", {})
	if typeof(damage_context) == TYPE_DICTIONARY and damage_context.has("category") \
	and damage_context.get("category") != "direct":
		return false
	var effect: Variant = context.get("source_effect", context.get("effect_context", {}))
	if typeof(effect) != TYPE_DICTIONARY:
		return false
	var source_type: Variant = effect.get("source_type", effect.get("sourceType", ""))
	return source_type != "delayed_damage"


func _effect_devourer(context: Dictionary, subject: Variant, _params: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var triggered: bool = devour_skill_point(subject, errors, context)
	if not errors.is_empty():
		return {"ok": false, "error": errors[0]}
	return {"ok": true, "triggered": triggered}


func _effect_echo(_context: Dictionary, subject: Variant, _params: Dictionary) -> Dictionary:
	if typeof(subject) != TYPE_DICTIONARY or not _is_current_enemy(subject):
		return {"ok": false, "error": "echo subject is not a current enemy"}
	var current: Variant = subject.get("echo_damage_bonus", 0.0)
	if not _is_finite(current) or float(current) < 0.0:
		return {"ok": false, "error": "echo_damage_bonus must be a non-negative finite number"}
	subject["echo_damage_bonus"] = float(current) + ECHO_GROWTH
	return {"ok": true}


func _current_enemies(errors: Array[String]) -> Array:
	var value: Variant = _get_enemies.call()
	if typeof(value) != TYPE_ARRAY:
		errors.append("get_enemies must return an Array")
		return []
	return value.duplicate(false)


func _is_current_enemy(candidate: Variant) -> bool:
	var errors: Array[String] = []
	for enemy in _current_enemies(errors):
		if _same_unit(enemy, candidate):
			return true
	return false


func _notify_trigger(payload: Dictionary) -> void:
	_on_triggered.call(payload.duplicate(true))


static func _actor_snapshot(unit: Dictionary) -> Dictionary:
	return {
		"id": unit.get("id", 0),
		"side": str(unit.get("side", "unknown")),
		"slot": unit.get("slot"),
	}


static func _source_effect(context: Dictionary) -> Dictionary:
	var raw: Variant = context.get("source_effect", context.get("effect_context", {}))
	return raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}


static func _source_action_id(context: Dictionary) -> String:
	var explicit: String = str(context.get("source_action_id", ""))
	if not explicit.is_empty():
		return explicit
	return str(_source_effect(context).get("source_id", ""))


static func _same_unit(left: Variant, right: Variant) -> bool:
	return typeof(left) == TYPE_DICTIONARY and typeof(right) == TYPE_DICTIONARY and is_same(left, right)


static func _contains_same_unit(units: Array, candidate: Dictionary) -> bool:
	for unit in units:
		if typeof(unit) == TYPE_DICTIONARY and is_same(unit, candidate):
			return true
	return false


static func _failed_result(result: Variant, label: String, errors: Array[String]) -> bool:
	if typeof(result) == TYPE_DICTIONARY and result.get("ok") == false:
		errors.append(str(result.get("error", "%s failed" % label)))
		return true
	return false


static func _valid_callable(value: Variant) -> bool:
	return typeof(value) == TYPE_CALLABLE and value.is_valid()


static func _is_finite(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))
