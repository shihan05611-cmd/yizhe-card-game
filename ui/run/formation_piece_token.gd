class_name RunFormationPieceToken
extends Button

var piece_class_id := ""


func configure(class_id: String, class_view: Dictionary, remaining: int) -> void:
	piece_class_id = class_id
	text = "%s · 库存 %d" % [class_view.get("name", class_id), remaining]
	tooltip_text = str(class_view.get("description", ""))
	disabled = remaining <= 0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled:
		return null
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return {"kind": "run_piece_class", "piece_class_id": piece_class_id}
