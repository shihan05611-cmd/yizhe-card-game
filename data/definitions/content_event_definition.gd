extends Resource

var constant_name := ""
var id := ""


func _init(source_constant_name: String = "", definition_id: String = "") -> void:
	constant_name = source_constant_name
	id = definition_id


func snapshot() -> Resource:
	return get_script().new(constant_name, id)
