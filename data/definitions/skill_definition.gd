extends Resource

var id := ""
var name := ""
var tip := ""
var condition_id := ""
var targeting_id := ""
var effect_id := ""
## Web catalog's stable base SP cost. This is metadata only; payment behavior
## belongs to the future card/runtime layer.
var base_sp_cost := 0


func _init(
	definition_id: String = "",
	display_name: String = "",
	description: String = "",
	definition_condition_id: String = "",
	definition_targeting_id: String = "",
	definition_effect_id: String = "",
	definition_base_sp_cost: int = 0,
) -> void:
	id = definition_id
	name = display_name
	tip = description
	condition_id = definition_condition_id
	targeting_id = definition_targeting_id
	effect_id = definition_effect_id
	base_sp_cost = definition_base_sp_cost


func snapshot() -> Resource:
	return get_script().new(
		id,
		name,
		tip,
		condition_id,
		targeting_id,
		effect_id,
		base_sp_cost,
	)


func to_source_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"cost": base_sp_cost,
		"tip": tip,
	}
