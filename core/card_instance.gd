class_name CardInstance
extends RefCounted

const CardDefinitionScript = preload("res://data/definitions/card_definition.gd")

var instance_id := ""
var source_skill_id := ""
var definition: Resource
var cost_until_played_delta := 0
var cost_until_turn_delta := 0
var cost_until_combat_delta := 0


func _init(
	runtime_instance_id: String,
	card_definition: Resource,
	cost_modifiers: Dictionary = {},
) -> void:
	instance_id = runtime_instance_id
	definition = card_definition.snapshot()
	source_skill_id = definition.source_skill_id
	cost_until_played_delta = int(cost_modifiers.get("until_played", 0))
	cost_until_turn_delta = int(cost_modifiers.get("until_turn", 0))
	cost_until_combat_delta = int(cost_modifiers.get("until_combat", 0))


func snapshot() -> RefCounted:
	return get_script().new(instance_id, definition, cost_modifiers())


func effective_sp_cost() -> int:
	return maxi(
		0,
		definition.base_sp_cost
		+ cost_until_played_delta
		+ cost_until_turn_delta
		+ cost_until_combat_delta,
	)


func set_cost_modifiers(modifiers: Dictionary) -> void:
	cost_until_played_delta = int(modifiers["until_played"])
	cost_until_turn_delta = int(modifiers["until_turn"])
	cost_until_combat_delta = int(modifiers["until_combat"])


func clear_until_played_cost() -> void:
	cost_until_played_delta = 0


func clear_until_turn_cost() -> void:
	cost_until_turn_delta = 0


func cost_modifiers() -> Dictionary:
	return {
		"until_played": cost_until_played_delta,
		"until_turn": cost_until_turn_delta,
		"until_combat": cost_until_combat_delta,
	}


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"source_skill_id": source_skill_id,
		"card_id": definition.id,
		"card_category": definition.card_category,
		"owner_hero_id": definition.owner_hero_id,
		"effective_sp_cost": effective_sp_cost(),
		"cost_modifiers": cost_modifiers(),
	}
