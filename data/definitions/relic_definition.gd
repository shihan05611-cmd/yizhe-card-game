extends Resource

var id := ""
var name := ""
var category := ""
var description := ""
## Static dispatch metadata only. Each hook contains event, condition_id,
## effect_id, limit, limit_scope, limit_value, and hook_index.
var hooks: Array = []
## Static modifier metadata only. Runtime interpretation belongs to systems/.
var modifiers: Array = []


func _init(
	definition_id: String = "",
	display_name: String = "",
	definition_category: String = "",
	definition_description: String = "",
	definition_hooks: Array = [],
	definition_modifiers: Array = [],
) -> void:
	id = definition_id
	name = display_name
	category = definition_category
	description = definition_description
	hooks = definition_hooks.duplicate(true)
	modifiers = definition_modifiers.duplicate(true)


func snapshot() -> Resource:
	return get_script().new(id, name, category, description, hooks, modifiers)
