class_name RunFormationSlot
extends PanelContainer

signal slot_dropped(target_slot: int, payload: Dictionary)

const GeometryPieceScript = preload("res://ui/art/geometry_piece.gd")

var slot := 0
var occupied := false
var piece_class_id: Variant = null
var _caption: Label


func configure(entry: Dictionary, class_view: Dictionary, formation_position: String = "") -> void:
	slot = int(entry["slot"])
	piece_class_id = entry["piece_class_id"]
	occupied = piece_class_id != null
	tooltip_text = "槽位 %d · 空位" % slot if not occupied else (
		"槽位 %d · %s\n%s" % [slot, class_view.get("name", piece_class_id), class_view.get("description", "")]
	)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	if occupied:
		var piece := GeometryPieceScript.new()
		piece.custom_minimum_size = Vector2(54, 72)
		piece.size_flags_vertical = Control.SIZE_EXPAND_FILL
		piece.configure(str(piece_class_id), false)
		box.add_child(piece)
	else:
		var empty := Label.new()
		empty.text = "空位"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(empty)
	_caption = Label.new()
	_caption.text = "%s · %s" % [
		formation_position if not formation_position.is_empty() else "槽 %d" % slot,
		"空" if not occupied else class_view.get("name", piece_class_id),
	]
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_size_override("font_size", 12)
	box.add_child(_caption)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not occupied:
		return null
	var preview := Label.new()
	preview.text = _caption.text
	set_drag_preview(preview)
	return {"kind": "run_formation_slot", "slot": slot}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	return data.get("kind") == "run_formation_slot" or (
		occupied and data.get("kind") == "run_piece_class"
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) == TYPE_DICTIONARY:
		slot_dropped.emit(slot, data)
