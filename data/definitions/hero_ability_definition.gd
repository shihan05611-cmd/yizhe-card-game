extends Resource

var id := ""
var owner_hero_id := 0
var ability_type := ""
var name := ""
var tip := ""
var condition_id := ""
var handler_id := ""
var is_passive := false
## Card-facing base SP metadata. Dynamic escalation remains the responsibility
## of the later player-card transaction layer.
var base_sp_cost := 0
## Old Web ultimate threshold mirrored from ULT_SKILLS.cost. It is not a card
## SP cost and does not authorize payment or energy-clearing behavior.
var source_energy_requirement := 0


func _init(
	definition_id: String = "",
	definition_owner_hero_id: int = 0,
	definition_ability_type: String = "",
	display_name: String = "",
	description: String = "",
	definition_condition_id: String = "",
	definition_handler_id: String = "",
	definition_is_passive: bool = false,
	definition_source_energy_requirement: int = 0,
	definition_base_sp_cost: int = 0,
) -> void:
	id = definition_id
	owner_hero_id = definition_owner_hero_id
	ability_type = definition_ability_type
	name = display_name
	tip = description
	condition_id = definition_condition_id
	handler_id = definition_handler_id
	is_passive = definition_is_passive
	source_energy_requirement = definition_source_energy_requirement
	base_sp_cost = definition_base_sp_cost


func snapshot() -> Resource:
	return get_script().new(
		id,
		owner_hero_id,
		ability_type,
		name,
		tip,
		condition_id,
		handler_id,
		is_passive,
		source_energy_requirement,
		base_sp_cost,
	)


func to_source_dict() -> Dictionary:
	var result := {"name": name, "tip": tip}
	if ability_type == "ultimate":
		result["cost"] = source_energy_requirement
	return result
