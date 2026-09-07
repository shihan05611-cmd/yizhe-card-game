extends Resource

var id := ""
var value: Variant = null


func _init(definition_id: String = "", definition_value: Variant = null) -> void:
	id = definition_id
	value = definition_value


func snapshot() -> Resource:
	return get_script().new(id, value)
