class_name BattleContexts
extends RefCounted

const UNIT_SIDE := {
	"UNKNOWN": "unknown",
	"ALLY": "ally",
	"ENEMY": "enemy",
}
const EFFECT_SOURCE_TYPE := {
	"UNKNOWN": "unknown",
	"FREE_SKILL": "free_skill",
	"EXCLUSIVE_SKILL": "exclusive_skill",
	"ULTIMATE": "ultimate",
	"BASIC_ATTACK": "basic_attack",
	"PURSUIT": "pursuit",
	"COUNTER": "counter",
	"DELAYED_DAMAGE": "delayed_damage",
	"SHENTONG": "shentong",
	"RELIC": "relic",
	"ASSIST": "assist",
	"SACRIFICE": "sacrifice",
	"ENEMY_SPECIAL": "enemy_special",
	"SYSTEM": "system",
}
const DAMAGE_CATEGORY := {
	"DIRECT": "direct",
	"DELAYED": "delayed",
	"EFFECT": "effect",
}
const DEATH_SOURCE_KIND := {
	"UNKNOWN": "unknown",
	"ALLY": "ally",
	"ENEMY": "enemy",
	"SYSTEM": "system",
	"SACRIFICE": "sacrifice",
}

const _LEGACY_SOURCE_TYPES := {
	"counter": "counter",
	"dot": "delayed_damage",
	"shentong": "shentong",
	"relic": "relic",
	"ultimate": "ultimate",
	"yizhe": "exclusive_skill",
	"effect": "system",
}


static func create_effect_context(
	input: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	return _create_effect_context(input, errors)


static func create_legacy_effect_context(
	input: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _require_dictionary(input, "legacy effect context", errors):
		return {}
	var source_side: Variant = input.get("source_side", UNIT_SIDE["UNKNOWN"])
	var source_id: Variant = input.get("source_id", "")
	var source_name: String = _string_value(input.get("source_name", ""))
	var dealer_type: String = _string_value(input.get("dealer_type", ""))
	var source_actor_id: Variant = input.get("source_actor_id", 0)
	var is_piece_attack := dealer_type == "piece"
	var source_type: String
	if is_piece_attack:
		source_type = EFFECT_SOURCE_TYPE["PURSUIT"] if _string_value(source_id).contains("pursuit") else EFFECT_SOURCE_TYPE["BASIC_ATTACK"]
	else:
		source_type = _LEGACY_SOURCE_TYPES.get(dealer_type, EFFECT_SOURCE_TYPE["UNKNOWN"])
	var is_pursuit := source_type == EFFECT_SOURCE_TYPE["PURSUIT"]
	return _create_effect_context({
		"source_type": source_type,
		"source_id": source_id if _truthy(source_id) else dealer_type,
		"source_name": source_name if not source_name.is_empty() else _string_value(source_id),
		"source_side": source_side,
		"source_actor_id": source_actor_id,
		"counts_as_skill_cast": dealer_type in ["yizhe", "ultimate"],
		"counts_as_basic_attack": is_piece_attack and not is_pursuit,
		"counts_as_attack": is_piece_attack or dealer_type == "counter",
	}, errors)


static func create_damage_context(
	input: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	return _create_damage_context(input, errors)


static func create_legacy_damage_context(
	input: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _require_dictionary(input, "legacy damage context", errors):
		return {}
	var dealer_type := _string_value(input.get("dealer_type", ""))
	var delayed := dealer_type == "dot"
	var effect_errors: Array[String] = []
	var effect := create_legacy_effect_context({
		"source_side": input.get("dealer_side", UNIT_SIDE["UNKNOWN"]),
		"source_id": input.get("source", ""),
		"source_name": input.get("dealer_name", ""),
		"dealer_type": dealer_type,
		"source_actor_id": input.get("dealer_id", 0),
	}, effect_errors)
	_append_errors(effect_errors, errors)
	if effect.is_empty():
		return {}
	if _string_value(input.get("damage_kind", "")) == "pursuit" and effect["source_type"] != EFFECT_SOURCE_TYPE["PURSUIT"]:
		var pursuit_effect := effect.duplicate(true)
		pursuit_effect["source_type"] = EFFECT_SOURCE_TYPE["PURSUIT"]
		pursuit_effect["counts_as_attack"] = true
		pursuit_effect["counts_as_basic_attack"] = false
		effect = _create_effect_context(pursuit_effect, errors)
	if not errors.is_empty():
		return {}
	return _create_damage_context({
		"target_id": input.get("target_id", 0),
		"raw_amount": input.get("raw_amount", 0),
		"category": DAMAGE_CATEGORY["DELAYED"] if delayed else DAMAGE_CATEGORY["DIRECT"],
		"effect": effect,
		"dealer_type": dealer_type,
		"dealer_name": input.get("dealer_name", ""),
		"dealer_id": input.get("dealer_id", 0),
		"attacker_unit_id": input.get("attacker_unit_id", 0),
		"can_crit": input.get("can_crit", false),
		"crit_rate": input.get("crit_rate", 0),
		"guaranteed_crit": input.get("guaranteed_crit", false),
		"can_block": input.get("can_block", true),
	}, errors)


static func create_death_context(
	input: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	return _create_death_context(input, errors)


static func create_death_context_from_damage(
	damage: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	var damage_context := _create_damage_context(damage, errors)
	if damage_context.is_empty():
		return {}
	var effect: Dictionary = damage_context["effect"]
	var source_kind := DEATH_SOURCE_KIND["UNKNOWN"]
	if effect["source_side"] == UNIT_SIDE["ALLY"]:
		source_kind = DEATH_SOURCE_KIND["ALLY"]
	elif effect["source_side"] == UNIT_SIDE["ENEMY"]:
		source_kind = DEATH_SOURCE_KIND["ENEMY"]
	return _create_death_context({
		"source_kind": source_kind,
		"effect": effect,
		"source_side": effect["source_side"],
		"source_actor_id": effect["source_actor_id"],
		"triggers_enemy_kill_effects": effect["triggers_enemy_kill_effects"],
	}, errors)


static func create_sacrifice_death_context(
	input: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _require_dictionary(input, "sacrifice death context", errors):
		return {}
	var effect := _create_effect_context({
		"source_type": EFFECT_SOURCE_TYPE["SACRIFICE"],
		"source_id": "sacrifice",
		"source_name": input.get("source_name", ""),
		"source_side": input.get("source_side", UNIT_SIDE["UNKNOWN"]),
		"source_actor_id": input.get("source_actor_id", 0),
		"triggers_enemy_kill_effects": false,
	}, errors)
	if effect.is_empty():
		return {}
	return _create_death_context({
		"source_kind": DEATH_SOURCE_KIND["SACRIFICE"],
		"effect": effect,
		"source_side": effect["source_side"],
		"source_actor_id": effect["source_actor_id"],
		"triggers_enemy_kill_effects": false,
	}, errors)


static func snapshot(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var array_snapshot: Array = []
		for item in value:
			array_snapshot.append(snapshot(item))
		return array_snapshot
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary_snapshot := {}
		for key in value:
			dictionary_snapshot[snapshot(key)] = snapshot(value[key])
		return dictionary_snapshot
	return value


static func _create_effect_context(input: Variant, errors: Array[String]) -> Dictionary:
	if not _require_dictionary(input, "effect context", errors):
		return {}
	var source_type: Variant = input.get("source_type", EFFECT_SOURCE_TYPE["UNKNOWN"])
	var source_side: Variant = input.get("source_side", UNIT_SIDE["UNKNOWN"])
	var source_id: Variant = input.get("source_id", "")
	var source_actor_id: Variant = input.get("source_actor_id", 0)
	_validate_enum(source_type, EFFECT_SOURCE_TYPE.values(), "source_type", errors)
	_validate_enum(source_side, UNIT_SIDE.values(), "source_side", errors)
	_validate_stable_id(source_id, "source_id", errors)
	_validate_stable_id(source_actor_id, "source_actor_id", errors)
	if not errors.is_empty():
		return {}
	# The removed per-hero action quota is intentionally absent from this contract.
	return {
		"source_type": source_type,
		"source_id": source_id,
		"source_name": _string_value(input.get("source_name", "")),
		"source_side": source_side,
		"source_actor_id": source_actor_id,
		"counts_as_skill_cast": bool(input.get("counts_as_skill_cast", false)),
		"spent_skill_points": bool(input.get("spent_skill_points", false)),
		"free_cast": bool(input.get("free_cast", false)),
		"counts_as_basic_attack": bool(input.get("counts_as_basic_attack", false)),
		"counts_as_attack": bool(input.get("counts_as_attack", false)),
		"triggers_enemy_kill_effects": bool(input.get("triggers_enemy_kill_effects", true)),
	}


static func _create_damage_context(input: Variant, errors: Array[String]) -> Dictionary:
	if not _require_dictionary(input, "damage context", errors):
		return {}
	var target_id: Variant = input.get("target_id", 0)
	var raw_amount: Variant = input.get("raw_amount", 0)
	var category: Variant = input.get("category", DAMAGE_CATEGORY["DIRECT"])
	var dealer_id: Variant = input.get("dealer_id", 0)
	var attacker_unit_id: Variant = input.get("attacker_unit_id", 0)
	var crit_rate: Variant = input.get("crit_rate", 0)
	_validate_stable_id(target_id, "target_id", errors)
	_validate_finite(raw_amount, "raw_amount", errors)
	_validate_enum(category, DAMAGE_CATEGORY.values(), "category", errors)
	_validate_stable_id(dealer_id, "dealer_id", errors)
	_validate_stable_id(attacker_unit_id, "attacker_unit_id", errors)
	_validate_finite(crit_rate, "crit_rate", errors)
	var effect := _create_effect_context(input.get("effect", {}), errors)
	if not errors.is_empty():
		return {}
	var delayed: bool = category == DAMAGE_CATEGORY["DELAYED"]
	return {
		"target_id": target_id,
		"raw_amount": raw_amount,
		"category": category,
		"effect": snapshot(effect),
		"dealer_type": _string_value(input.get("dealer_type", "")),
		"dealer_name": _string_value(input.get("dealer_name", "")),
		"dealer_id": dealer_id,
		"attacker_unit_id": attacker_unit_id,
		"can_crit": false if delayed else bool(input.get("can_crit", false)),
		"crit_rate": crit_rate,
		"guaranteed_crit": false if delayed else bool(input.get("guaranteed_crit", false)),
		"can_block": false if delayed else bool(input.get("can_block", true)),
	}


static func _create_death_context(input: Variant, errors: Array[String]) -> Dictionary:
	if not _require_dictionary(input, "death context", errors):
		return {}
	var effect := _create_effect_context(input.get("effect", {}), errors)
	if effect.is_empty():
		return {}
	var source_kind: Variant = input.get("source_kind", DEATH_SOURCE_KIND["UNKNOWN"])
	var source_side: Variant = input.get("source_side", effect["source_side"])
	var source_actor_id: Variant = input.get("source_actor_id", effect["source_actor_id"])
	_validate_enum(source_kind, DEATH_SOURCE_KIND.values(), "source_kind", errors)
	_validate_enum(source_side, UNIT_SIDE.values(), "source_side", errors)
	_validate_stable_id(source_actor_id, "source_actor_id", errors)
	if not errors.is_empty():
		return {}
	return {
		"source_kind": source_kind,
		"effect": snapshot(effect),
		"source_side": source_side,
		"source_actor_id": source_actor_id,
		"triggers_enemy_kill_effects": bool(input.get(
			"triggers_enemy_kill_effects", effect["triggers_enemy_kill_effects"],
		)),
	}


static func _require_dictionary(value: Variant, label: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_DICTIONARY:
		return true
	errors.append("%s must be a Dictionary" % label)
	return false


static func _validate_enum(
	value: Variant,
	allowed: Array,
	field_name: String,
	errors: Array[String],
) -> void:
	if value not in allowed:
		errors.append("%s must be one of: %s" % [field_name, ", ".join(allowed)])


static func _validate_stable_id(value: Variant, field_name: String, errors: Array[String]) -> void:
	if typeof(value) not in [TYPE_STRING, TYPE_INT]:
		errors.append("%s must be a string or integer" % field_name)


static func _validate_finite(value: Variant, field_name: String, errors: Array[String]) -> void:
	if typeof(value) == TYPE_INT:
		return
	if typeof(value) == TYPE_FLOAT and is_finite(value):
		return
	errors.append("%s must be a finite number" % field_name)


static func _string_value(value: Variant) -> String:
	return "" if value == null else str(value)


static func _truthy(value: Variant) -> bool:
	if value == null:
		return false
	if typeof(value) == TYPE_STRING:
		return not value.is_empty()
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return value != 0
	return bool(value)


static func _append_errors(source: Array[String], destination: Array[String]) -> void:
	for message in source:
		destination.append(message)
