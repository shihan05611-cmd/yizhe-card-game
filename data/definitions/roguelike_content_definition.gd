extends Resource

var kind := ""
var id: Variant = null
## Exact source metadata plus stable handler references where runtime behavior
## will eventually be supplied by systems/. This data never stores Callables.
var metadata: Dictionary = {}


func _init(
	definition_kind: String = "",
	definition_id: Variant = null,
	definition_metadata: Dictionary = {},
) -> void:
	kind = definition_kind
	id = definition_id
	metadata = definition_metadata.duplicate(true)


func snapshot() -> Resource:
	return get_script().new(kind, id, metadata)
