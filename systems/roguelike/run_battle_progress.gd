class_name RoguelikeRunBattleProgress
extends RefCounted

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const GrowthPortScript = preload("res://systems/growth/growth_port.gd")

const CONFIG_KEYS := ["run_state", "buff_catalog", "valid_hero_ids"]

var _run_state: Dictionary
var _draft := {"permanent_buffs": []}
var _piece_slots: Array = []
var _growth_port: Variant = null
var _status := "invalid"


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if not _exact_keys(config, CONFIG_KEYS):
		errors.append("Run battle progress config must keep its canonical closed shape")
		return
	var run_errors: Array[String] = []
	if not RunContractScript.validate(config["run_state"], run_errors):
		errors.append("Run battle progress requires a canonical Run: %s" % run_errors[0])
		return
	if not config["run_state"]["active"] or config["run_state"]["status"] != "fighting":
		errors.append("Run battle progress requires an active fighting Run")
		return
	if typeof(config["buff_catalog"]) != TYPE_DICTIONARY:
		errors.append("Run battle progress requires the M1 Buff catalog")
		return
	if typeof(config["valid_hero_ids"]) != TYPE_ARRAY:
		errors.append("Run battle progress requires authoritative hero ids")
		return
	_run_state = config["run_state"]
	_piece_slots = _deep_copy(_run_state["piece_slots"])
	_draft = {"permanent_buffs": _deep_copy(_run_state["permanent_buffs"])}
	_growth_port = GrowthPortScript.new({
		"run_state": _draft,
		"catalog": config["buff_catalog"],
		"valid_hero_ids": config["valid_hero_ids"].duplicate(),
	}, errors)
	if not errors.is_empty() or not _growth_port.is_valid():
		if errors.is_empty():
			errors.append("Run battle progress could not construct its growth draft")
		return
	_status = "open"


func is_valid() -> bool:
	return _status != "invalid"


func status() -> String:
	return _status


func is_bound_to(run_state: Variant) -> bool:
	return _status == "open" and typeof(run_state) == TYPE_DICTIONARY and is_same(run_state, _run_state)


func runtime_draft_authority(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _require_open(errors):
		return {}
	return _draft


func snapshot(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _require_open(errors):
		return {}
	var buffs: Array = _growth_port.snapshot(errors)
	if not errors.is_empty():
		return {}
	return {
		"piece_slots": _deep_copy(_piece_slots),
		"permanent_buffs": _deep_copy(buffs),
	}


func project_allies(allies: Variant, errors: Array[String] = []) -> Array:
	errors.clear()
	if not _require_open(errors):
		return []
	var canonical := _canonical_allies(allies, false, errors)
	if not errors.is_empty():
		return []
	var ratios := {}
	for entry: Dictionary in _piece_slots:
		ratios[entry["slot"]] = float(entry["hp_ratio"])
	for unit: Dictionary in canonical:
		var ratio: float = ratios[unit["slot"]]
		if ratio == 0.0:
			unit["hp"] = 0.0
			unit["alive"] = false
		else:
			unit["hp"] = minf(float(unit["max_hp"]), maxf(1.0, roundf(float(unit["max_hp"]) * ratio)))
			unit["alive"] = true
	return canonical


func settlement_snapshot(allies: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _require_open(errors):
		return {}
	var canonical := _canonical_allies(allies, true, errors)
	if not errors.is_empty():
		return {}
	var slots: Array = []
	for unit: Dictionary in canonical:
		var ratio := 0.0
		if not unit["is_puppet"] and unit["alive"] and float(unit["hp"]) > 0.0:
			ratio = clampf(float(unit["hp"]) / float(unit["max_hp"]), 0.0, 1.0)
		slots.append({"slot": unit["slot"], "hp_ratio": ratio})
	var buffs: Array = _growth_port.snapshot(errors)
	if not errors.is_empty():
		return {}
	return {"piece_slots": slots, "permanent_buffs": _deep_copy(buffs)}


func close(outcome: String, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_open(errors):
		return false
	if outcome not in ["committed", "discarded"]:
		errors.append("Run battle progress outcome must be committed or discarded")
		return false
	_status = outcome
	return true


func _canonical_allies(value: Variant, allow_puppets: bool, errors: Array[String]) -> Array:
	if typeof(value) != TYPE_ARRAY or value.size() != 6:
		errors.append("Run battle progress requires exactly six ally units")
		return []
	var result: Array = []
	var slots := {}
	for index in value.size():
		var unit: Variant = value[index]
		if typeof(unit) != TYPE_DICTIONARY:
			errors.append("Run battle ally %d must be a Dictionary" % index)
			return []
		for field in ["slot", "side", "hp", "max_hp", "alive", "is_puppet"]:
			if not unit.has(field):
				errors.append("Run battle ally %d is missing %s" % [index, field])
				return []
		if (
			typeof(unit["slot"]) != TYPE_INT
			or unit["slot"] < 1 or unit["slot"] > 6
			or slots.has(unit["slot"])
			or unit["side"] != "ally"
			or not _finite_non_negative(unit["hp"])
			or not _finite_positive(unit["max_hp"])
			or float(unit["hp"]) > float(unit["max_hp"])
			or typeof(unit["alive"]) != TYPE_BOOL
			or typeof(unit["is_puppet"]) != TYPE_BOOL
			or (unit["alive"] and float(unit["hp"]) <= 0.0)
			or (not unit["alive"] and float(unit["hp"]) != 0.0)
			or (not allow_puppets and unit["is_puppet"])
		):
			errors.append("Run battle ally %d has invalid HP, slot, side, or puppet state" % index)
			return []
		slots[unit["slot"]] = true
		result.append(_deep_copy(unit))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left["slot"] < right["slot"]
	)
	return result


func _require_open(errors: Array[String]) -> bool:
	if _status == "open":
		return true
	errors.append("Run battle progress is closed (%s)" % _status)
	return false


static func _exact_keys(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true


static func _finite_non_negative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _finite_positive(value: Variant) -> bool:
	return _finite_non_negative(value) and float(value) > 0.0


static func _deep_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(_deep_copy(item))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key: Variant in value:
			result[_deep_copy(key)] = _deep_copy(value[key])
		return result
	return value
