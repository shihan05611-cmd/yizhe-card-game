class_name CombatLog
extends PanelContainer

const LogEntryScene = preload("res://scenes/battle/combat_log_entry.tscn")

@onready var entries: VBoxContainer = %Entries
@onready var scroll: ScrollContainer = %Scroll

var _entry_nodes: Array[Node] = []
var _pending: Array = []


func _ready() -> void:
	if not _pending.is_empty():
		_apply(_pending)


func bind_logs(logs: Array) -> void:
	_pending = logs.duplicate(true)
	if is_node_ready():
		_apply(_pending)


func entry_nodes() -> Array[Node]:
	return _entry_nodes.duplicate()


func active_entry_count() -> int:
	var count := 0
	for entry: Node in _entry_nodes:
		if entry.visible:
			count += 1
	return count


func _apply(logs: Array) -> void:
	while _entry_nodes.size() < logs.size():
		var entry := LogEntryScene.instantiate()
		entries.add_child(entry)
		_entry_nodes.append(entry)
	for index in _entry_nodes.size():
		var active := index < logs.size()
		_entry_nodes[index].visible = active
		if active:
			_entry_nodes[index].bind_entry(logs[index])
	call_deferred("scroll_to_bottom")


func scroll_to_bottom() -> void:
	if not is_node_ready():
		return
	var scroll_bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = maxi(0, int(scroll_bar.max_value))
