class_name DormantShentongDomain
extends RefCounted

const ContextsScript = preload("res://core/contexts.gd")
const ContentDefinition = preload("res://data/definitions/roguelike_content_definition.gd")
const PortScript = preload("res://systems/roguelike/dormant_shentong_battle_port.gd")

## Intentionally dormant M5-06 domain. Production Run state does not contain
## shentong selection/uses, and no app/autoload/UI code preloads this module.

const CONFIG_KEYS := [
	"shentong_definition", "owned_relic_ids", "battle_port", "random",
]
const SHENTONG_IDS := ["charge", "assault", "sacrifice"]
const HANDLER_BY_ID := {
	"charge": "shentong.charge",
	"assault": "shentong.assault",
	"sacrifice": "shentong.sacrifice",
}
const EVOLUTION_RELIC_IDS := [
	"shentongAssaultBurst", "shentongChargeOverload",
]

var _definition: Variant = null
var _owned_relic_ids: Array = []
var _battle_port: Variant = null
var _random: Variant = null
var _uses_left := 0
var _assault_damage_multiplier := 1.0
var _charge_defense_round: Variant = null
var _charge_damage_round: Variant = null
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if not _exact_keys(config, CONFIG_KEYS):
		errors.append("dormant shentong config must keep its canonical closed shape")
		return
	var definition: Variant = config["shentong_definition"]
	if (
		not definition is Resource or definition.get_script() != ContentDefinition
		or definition.kind != "shentong" or definition.id not in SHENTONG_IDS
		or definition.metadata.get("handler_id") != HANDLER_BY_ID.get(definition.id)
		or typeof(definition.metadata.get("usesPerBattle")) != TYPE_INT
		or definition.metadata["usesPerBattle"] <= 0
	):
		errors.append("dormant shentong requires one authoritative M1 definition")
		return
	if not _valid_relic_ids(config["owned_relic_ids"]):
		errors.append("dormant shentong relic ids must be unique non-empty strings")
		return
	var battle_port: Variant = config["battle_port"]
	if battle_port == null or battle_port.get_script() != PortScript or not battle_port.is_valid():
		errors.append("dormant shentong requires its exact battle port")
		return
	var random: Variant = config["random"]
	if (
		random == null or not random.has_method("with_transaction")
		or not random.has_method("pick") or not random.has_method("command_error")
	):
		errors.append("dormant shentong requires TransactionalRunRandom")
		return
	_definition = definition.snapshot()
	_owned_relic_ids = config["owned_relic_ids"].duplicate()
	_battle_port = battle_port
	_random = random
	_uses_left = int(_definition.metadata["usesPerBattle"])
	_valid = true


func is_valid() -> bool:
	return _valid


func snapshot(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _valid:
		errors.append("dormant shentong domain is invalid")
		return {}
	return {
		"id": _definition.id,
		"handler_id": _definition.metadata["handler_id"],
		"uses_max": int(_definition.metadata["usesPerBattle"]),
		"uses_left": _uses_left,
		"owned_evolution_relic_ids": _owned_evolution_relic_ids(),
		"charge_defense_round": _charge_defense_round,
		"charge_damage_round": _charge_damage_round,
		"assault_damage_multiplier": _assault_damage_multiplier,
	}


func evolution_effects() -> Dictionary:
	return {
		"assault_damage_multiplier": 5.0 if "shentongAssaultBurst" in _owned_relic_ids else 3.0,
		"charge_energy_gain": 30.0 if "shentongChargeOverload" in _owned_relic_ids else 0.0,
	}


func _owned_evolution_relic_ids() -> Array:
	var result: Array = []
	for id: String in _owned_relic_ids:
		if id in EVOLUTION_RELIC_IDS:
			result.append(id)
	return result


func can_use(errors: Array[String] = []) -> bool:
	errors.clear()
	if not _valid or _uses_left <= 0:
		return false
	var view: Dictionary = _battle_port.view(errors)
	if not errors.is_empty() or not _valid_view(view, errors) or view["game_over"]:
		return false
	match _definition.id:
		"charge":
			return not view["player_action_taken"]
		"assault":
			return _assault_caster(view) != null
		"sacrifice":
			return not _active_heroes(view).is_empty() and _sacrifice_target(view) != null
	return false


func use(errors: Array[String] = []) -> bool:
	errors.clear()
	if not can_use(errors):
		return false
	var battle_before: Dictionary = _battle_port.snapshot(errors)
	if not errors.is_empty():
		return false
	var domain_before := _domain_state()
	var operation_errors: Array[String] = []
	var rolled_back := false
	var random_errors: Array[String] = []
	var result: Variant = _random.with_transaction(func() -> bool:
		_uses_left -= 1
		var applied := false
		match _definition.id:
			"charge": applied = _use_charge(operation_errors)
			"assault": applied = _use_assault(operation_errors)
			"sacrifice": applied = _use_sacrifice(operation_errors)
		if applied and operation_errors.is_empty():
			applied = _settle_detected_result(operation_errors)
		if applied and operation_errors.is_empty():
			return true
		rolled_back = _rollback(battle_before, domain_before, operation_errors)
		return false
	, random_errors)
	_append_errors(random_errors, errors)
	_append_errors(operation_errors, errors)
	if result == true:
		return true
	if not rolled_back:
		_rollback(battle_before, domain_before, errors)
	return false


func get_damage_multiplier(context: Variant, errors: Array[String] = []) -> float:
	errors.clear()
	if not _valid or typeof(context) != TYPE_DICTIONARY:
		errors.append("dormant shentong damage query requires a Dictionary")
		return 1.0
	for key in ["source_side", "source_type", "target_side", "round"]:
		if not context.has(key):
			errors.append("dormant shentong damage query is missing %s" % key)
	if typeof(context.get("round")) != TYPE_INT:
		errors.append("dormant shentong damage query round must be an integer")
	if not errors.is_empty():
		return 1.0
	var multiplier := 1.0
	if context["target_side"] == "ally" and context["round"] == _charge_defense_round:
		multiplier *= 0.8
	if context["source_side"] == "ally" and context["round"] == _charge_damage_round:
		multiplier *= 2.0
	if (
		context["source_side"] == "ally"
		and context["source_type"] in ["exclusiveSkill", "exclusive_skill"]
	):
		multiplier *= _assault_damage_multiplier
	return multiplier


func _use_charge(errors: Array[String]) -> bool:
	var view: Dictionary = _battle_port.view(errors)
	if not errors.is_empty() or view["player_action_taken"]:
		return false
	for action in [
		["consume_player_turn", {}],
		["heal_alive_allies", {"ratio": 0.1}],
		["extend_enemy_burn", {"turns": 1}],
	]:
		if not _battle_port.call_action(action[0], action[1], errors)["ok"]:
			return false
	var energy: float = evolution_effects()["charge_energy_gain"]
	if energy > 0.0:
		for hero: Dictionary in _active_heroes(view):
			if not _battle_port.call_action("gain_hero_energy", {
				"hero_id": hero["id"], "amount": energy,
			}, errors)["ok"]:
				return false
	if not _battle_port.call_action("mark_player_action", {}, errors)["ok"]:
		return false
	_charge_defense_round = view["round"]
	_charge_damage_round = int(view["round"]) + 1
	return true


func _use_assault(errors: Array[String]) -> bool:
	var view: Dictionary = _battle_port.view(errors)
	if not errors.is_empty():
		return false
	var caster: Variant = _assault_caster(view)
	if caster == null:
		return false
	_assault_damage_multiplier = evolution_effects()["assault_damage_multiplier"]
	var cast: Dictionary = _battle_port.call_action("cast_exclusive_free", {
		"hero_id": caster["id"], "damage_multiplier": _assault_damage_multiplier,
	}, errors)
	var marked := false
	if cast["ok"]:
		marked = _battle_port.call_action("mark_player_action", {}, errors)["ok"]
	_assault_damage_multiplier = 1.0
	return cast["ok"] and marked


func _use_sacrifice(errors: Array[String]) -> bool:
	var view: Dictionary = _battle_port.view(errors)
	if not errors.is_empty():
		return false
	var target: Variant = _sacrifice_target(view)
	var active: Array = _active_heroes(view)
	if target == null or active.is_empty():
		return false
	var death_context := ContextsScript.create_sacrifice_death_context({
		"source_side": "ally", "source_name": "神通【献祭】", "source_actor_id": 0,
	}, errors)
	if not errors.is_empty():
		return false
	if not _battle_port.call_action("sacrifice_unit", {
		"unit_id": target["id"], "death_context": death_context,
	}, errors)["ok"]:
		return false
	var puppet: bool = target["is_puppet"]
	if not _battle_port.call_action("gain_skill_points", {
		"amount": 1 if puppet else 2,
	}, errors)["ok"]:
		return false
	var hero: Variant = _random.pick(active, errors)
	if hero == null or not errors.is_empty():
		return false
	if not _battle_port.call_action("gain_hero_energy", {
		"hero_id": hero["id"], "amount": 15 if puppet else 30,
	}, errors)["ok"]:
		return false
	return _battle_port.call_action("mark_player_action", {}, errors)["ok"]


func _settle_detected_result(errors: Array[String]) -> bool:
	var detected: Dictionary = _battle_port.call_action("detect_battle_result", {}, errors)
	if not detected["ok"]:
		return false
	var result: Variant = detected["value"]
	if result == null:
		return true
	if result not in ["win", "lose"]:
		errors.append("dormant shentong battle result must be null, win, or lose")
		return false
	return _battle_port.call_action("settle_battle", {"result": result}, errors)["ok"]


func _rollback(
	battle_before: Dictionary,
	domain_before: Dictionary,
	errors: Array[String],
) -> bool:
	_restore_domain(domain_before)
	var restore_errors: Array[String] = []
	var restored: bool = _battle_port.restore(battle_before, restore_errors)
	_append_errors(restore_errors, errors)
	return restored


func _domain_state() -> Dictionary:
	return {
		"uses_left": _uses_left,
		"assault_damage_multiplier": _assault_damage_multiplier,
		"charge_defense_round": _charge_defense_round,
		"charge_damage_round": _charge_damage_round,
	}


func _restore_domain(value: Dictionary) -> void:
	_uses_left = value["uses_left"]
	_assault_damage_multiplier = value["assault_damage_multiplier"]
	_charge_defense_round = value["charge_defense_round"]
	_charge_damage_round = value["charge_damage_round"]


func _assault_caster(view: Dictionary) -> Variant:
	var active: Array = _active_heroes(view)
	for hero: Dictionary in active:
		if hero["id"] == view["selected_hero_id"] and hero["can_cast_exclusive"]:
			return hero
	for hero: Dictionary in active:
		if hero["can_cast_exclusive"]:
			return hero
	return null


func _sacrifice_target(view: Dictionary) -> Variant:
	var alive: Array = view["allies"].filter(func(unit: Dictionary) -> bool:
		return unit["alive"]
	)
	alive.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_ratio := float(left["hp"]) / float(left["max_hp"])
		var right_ratio := float(right["hp"]) / float(right["max_hp"])
		return left_ratio < right_ratio or (left_ratio == right_ratio and left["id"] < right["id"])
	)
	return null if alive.is_empty() else alive[0]


func _active_heroes(view: Dictionary) -> Array:
	var result: Array = view["heroes"].filter(func(hero: Dictionary) -> bool:
		return hero["deployed"]
	)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left["deployment_slot"] < right["deployment_slot"] or (
			left["deployment_slot"] == right["deployment_slot"] and left["id"] < right["id"]
		)
	)
	return result


func _valid_view(view: Variant, errors: Array[String]) -> bool:
	if typeof(view) != TYPE_DICTIONARY:
		errors.append("dormant shentong battle view must be a Dictionary")
		return false
	for key in [
		"round", "game_over", "player_action_taken", "selected_hero_id", "heroes", "allies",
	]:
		if not view.has(key):
			errors.append("dormant shentong battle view is missing %s" % key)
	if not errors.is_empty():
		return false
	if (
		typeof(view["round"]) != TYPE_INT or view["round"] < 1
		or typeof(view["game_over"]) != TYPE_BOOL
		or typeof(view["player_action_taken"]) != TYPE_BOOL
		or typeof(view["heroes"]) != TYPE_ARRAY or typeof(view["allies"]) != TYPE_ARRAY
	):
		errors.append("dormant shentong battle view has invalid scalar or collection fields")
		return false
	for hero: Variant in view["heroes"]:
		if (
			typeof(hero) != TYPE_DICTIONARY or typeof(hero.get("id")) != TYPE_INT
			or typeof(hero.get("deployed")) != TYPE_BOOL
			or typeof(hero.get("deployment_slot")) != TYPE_INT
			or typeof(hero.get("can_cast_exclusive")) != TYPE_BOOL
		):
			errors.append("dormant shentong hero view is invalid")
			return false
	for unit: Variant in view["allies"]:
		if (
			typeof(unit) != TYPE_DICTIONARY or typeof(unit.get("id")) != TYPE_INT
			or typeof(unit.get("alive")) != TYPE_BOOL or typeof(unit.get("is_puppet")) != TYPE_BOOL
			or not _positive_number(unit.get("max_hp")) or not _non_negative_number(unit.get("hp"))
			or float(unit["hp"]) > float(unit["max_hp"])
		):
			errors.append("dormant shentong ally view is invalid")
			return false
	return true


static func _valid_relic_ids(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var seen := {}
	for id: Variant in value:
		if typeof(id) != TYPE_STRING or id.strip_edges().is_empty() or seen.has(id):
			return false
		seen[id] = true
	return true


static func _positive_number(value: Variant) -> bool:
	return _non_negative_number(value) and float(value) > 0.0


static func _non_negative_number(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT and value >= 0
		or typeof(value) == TYPE_FLOAT and is_finite(value) and value >= 0.0
	)


static func _exact_keys(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message: String in source:
		destination.append(message)
