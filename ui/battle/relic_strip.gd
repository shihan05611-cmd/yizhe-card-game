class_name BattleRelicStrip
extends ScrollContainer

const ItemScene = preload("res://scenes/battle/relic_item.tscn")
@onready var _row: HBoxContainer = $Row
var _bound: Array = []

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_PASS

func bind_relics(relics: Array) -> void:
	if _row == null or relics == _bound:
		return
	_bound = relics.duplicate(true)
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for relic: Dictionary in relics:
		var item := ItemScene.instantiate()
		item.tooltip_text = "%s\n%s" % [relic.get("name", relic.get("id", "")), relic.get("description", "")]
		_row.add_child(item)
		var icon: Control = item.get_node("Icon")
		icon.bind_relic(relic)

func relic_count() -> int:
	return _bound.size()
