class_name PlayerEnergyCoordinator
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const CardDefinitionScript = preload("res://data/definitions/card_definition.gd")
const HandRuntimeScript = preload("res://systems/cards/hand_runtime.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")

const CONFIG_KEYS := ["state", "hand_runtime", "card_catalog"]
const REQUEST_KEYS := ["hero_id", "amount", "source"]

var _state: Dictionary
var _hand_runtime: Variant
var _card_catalog: Dictionary = {}
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if not _exact_keys(config, CONFIG_KEYS, "player energy coordinator config", errors):
		return
	if typeof(config["state"]) != TYPE_DICTIONARY:
		errors.append("player energy coordinator state must be a Dictionary")
		return
	var state_errors: Array[String] = []
	if not BattleStateScript.validate(config["state"], state_errors):
		errors.append("player energy coordinator requires canonical BattleState: %s" % state_errors[0])
		return
	if (
		typeof(config["hand_runtime"]) != TYPE_OBJECT
		or config["hand_runtime"] == null
		or config["hand_runtime"].get_script() != HandRuntimeScript
	):
		errors.append("player energy coordinator requires exact HandRuntime")
		return
	if not _validate_catalog(config["card_catalog"], errors):
		return
	_state = config["state"]
	_hand_runtime = config["hand_runtime"]
	for card_id: Variant in config["card_catalog"]:
		_card_catalog[card_id] = config["card_catalog"][card_id].snapshot()
	_valid = true


func is_valid() -> bool:
	return _valid


func apply_energy(request: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _valid:
		return CombatPortsScript.fail("player energy coordinator is invalid")
	if not _exact_keys(request, REQUEST_KEYS, "player energy request", errors):
		return CombatPortsScript.fail(errors[0])
	if not _stable_id(request["hero_id"]):
		return CombatPortsScript.fail("player energy hero_id must be a stable id")
	if not _finite_number(request["amount"]) or float(request["amount"]) < 0.0:
		return CombatPortsScript.fail("player energy amount must be non-negative and finite")
	if typeof(request["source"]) != TYPE_DICTIONARY:
		return CombatPortsScript.fail("player energy source must be a Dictionary")
	var hero: Variant = _player_hero(request["hero_id"])
	if hero == null:
		return CombatPortsScript.fail("player energy hero is not in canonical player roster")
	if not hero["deployed"]:
		return CombatPortsScript.fail("player energy can only be granted to a deployed hero")
	var before := float(hero["energy"])
	var amount := float(request["amount"])
	var reaches_threshold := before + amount >= float(hero["max_energy"])
	var ultimate_definition: Variant = null
	if reaches_threshold:
		var ultimate_card_id := "ultimate:%s" % hero["ex_skill"]
		ultimate_definition = _card_catalog.get(ultimate_card_id)
		if (
			not ultimate_definition is Resource
			or ultimate_definition.get_script() != CardDefinitionScript
			or ultimate_definition.card_category != CardDefinitionScript.CATEGORY_ULTIMATE
			or ultimate_definition.owner_hero_id != hero["id"]
		):
			return CombatPortsScript.fail("player hero has no authoritative ultimate card: %s" % ultimate_card_id)

	if not reaches_threshold:
		hero["energy"] = before + amount
		return CombatPortsScript.ok({
			"hero_id": hero["id"], "before": before, "amount": amount,
			"after": hero["energy"], "threshold_crossed": false,
			"generated_card": null, "source": request["source"].duplicate(true),
		})

	# The first-version rule triggers once for one event even if amount spans
	# multiple thresholds. Clear before publishing the generated ultimate.
	hero["energy"] = 0.0
	var destination := (
		CardDefinitionScript.PILE_HAND
		if _hand_runtime.pile_instance_ids(CardDefinitionScript.PILE_HAND).size() < HandRuntimeScript.HAND_LIMIT
		else CardDefinitionScript.PILE_DRAW
	)
	var created: Variant = _hand_runtime.create_card(
		ultimate_definition,
		destination,
		CardDefinitionScript.INSERT_TOP,
	)
	if not created.ok:
		return CombatPortsScript.fail(
			"ultimate generation failed after energy clear: %s" % created.message
		)
	return CombatPortsScript.ok({
		"hero_id": hero["id"], "before": before, "amount": amount,
		"after": hero["energy"], "threshold_crossed": true,
		"generated_card": {
			"instance_id": created.details["instance_id"],
			"card_id": ultimate_definition.id,
			"destination": destination,
		},
		"source": request["source"].duplicate(true),
	})


func apply_to_all_deployed(amount: Variant, source: Dictionary) -> Dictionary:
	if not _finite_number(amount) or float(amount) < 0.0:
		return CombatPortsScript.fail("player team energy amount must be non-negative and finite")
	var changes: Array[Dictionary] = []
	for hero: Dictionary in _state["player_heroes"]:
		if not hero["deployed"]:
			continue
		var result := apply_energy({
			"hero_id": hero["id"], "amount": amount,
			"source": source,
		})
		if not result["ok"]:
			return result
		changes.append(result["value"])
	return CombatPortsScript.ok(changes)


func _player_hero(hero_id: Variant) -> Variant:
	for hero: Dictionary in _state["player_heroes"]:
		if hero["id"] == hero_id:
			return hero
	return null


static func _validate_catalog(value: Variant, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.is_empty():
		errors.append("player energy coordinator card_catalog must be non-empty")
		return false
	for card_id: Variant in value:
		var definition: Variant = value[card_id]
		if (
			typeof(card_id) != TYPE_STRING
			or not definition is Resource
			or definition.get_script() != CardDefinitionScript
			or definition.id != card_id
		):
			errors.append("player energy coordinator card_catalog contains an invalid entry")
			return false
		if definition.source_skill_id == "basicDamage":
			errors.append("player card authority excludes basicDamage")
			return false
	return true


static func _exact_keys(value: Variant, keys: Array, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		errors.append("%s must have a canonical closed shape" % path)
		return false
	for key: String in keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			errors.append("%s contains an unknown field" % path)
			return false
	return true


static func _stable_id(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT and value >= 0) or (
		typeof(value) == TYPE_STRING and not value.strip_edges().is_empty()
	)


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))
