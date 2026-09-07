extends Resource

var id := ""
var name := ""
var grid_cells := 1
var piece_class_id: Variant = null
var hp_scale: Variant = 1
var atk_scale: Variant = 1
var hooks: Array[Dictionary] = []
var modifiers: Array = []


func _init(
	definition_id: String = "",
	display_name: String = "",
	definition_grid_cells: int = 1,
	definition_piece_class_id: Variant = null,
	definition_hp_scale: Variant = 1,
	definition_atk_scale: Variant = 1,
	definition_hooks: Array[Dictionary] = [],
	definition_modifiers: Array = [],
) -> void:
	id = definition_id
	name = display_name
	grid_cells = definition_grid_cells
	piece_class_id = definition_piece_class_id
	hp_scale = definition_hp_scale
	atk_scale = definition_atk_scale
	hooks = definition_hooks.duplicate(true)
	modifiers = definition_modifiers.duplicate(true)


func snapshot() -> Resource:
	return get_script().new(
		id,
		name,
		grid_cells,
		piece_class_id,
		hp_scale,
		atk_scale,
		hooks,
		modifiers,
	)


func to_source_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"gridCells": grid_cells,
		"pieceClassId": piece_class_id,
		"hpScale": hp_scale,
		"atkScale": atk_scale,
		"hooks": hooks.duplicate(true),
		"modifiers": modifiers.duplicate(true),
	}
