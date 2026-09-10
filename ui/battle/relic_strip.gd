class_name BattleRelicStrip
extends ScrollContainer

const ItemScene = preload("res://scenes/battle/relic_item.tscn")
@onready var _row: HBoxContainer = $Row
var _bound: Array = []
var _items: Dictionary = {}
var _trigger_tweens: Dictionary = {}
var last_trigger_id := ""

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_PASS

func bind_relics(relics: Array) -> void:
	if _row == null or relics == _bound:
		return
	_bound = relics.duplicate(true)
	reset_triggers()
	_items.clear()
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for relic: Dictionary in relics:
		var item := ItemScene.instantiate()
		item.tooltip_text = "%s\n%s" % [relic.get("name", relic.get("id", "")), relic.get("description", "")]
		_row.add_child(item)
		_items[str(relic.get("id", ""))] = item
		var icon: Control = item.get_node("Icon")
		icon.bind_relic(relic)

func relic_count() -> int:
	return _bound.size()

func present_trigger(relic_id: String, duration: float) -> String:
	var item: Control = _items.get(relic_id)
	if not is_instance_valid(item):
		return ""
	last_trigger_id = relic_id
	if _trigger_tweens.has(relic_id) and _trigger_tweens[relic_id].is_valid():
		_trigger_tweens[relic_id].kill()
	ensure_control_visible(item)
	var glow: Control = item.get_node("TriggerGlow")
	glow.visible = true
	glow.modulate.a = 1.0
	var tween := create_tween()
	_trigger_tweens[relic_id] = tween
	tween.tween_interval(maxf(0.18, duration * 0.5))
	tween.tween_property(glow, "modulate:a", 0.0, maxf(0.22, duration))
	tween.tween_callback(func() -> void: glow.visible = false)
	for relic: Dictionary in _bound:
		if str(relic.get("id", "")) == relic_id:
			return str(relic.get("name", relic_id))
	return relic_id

func reset_triggers() -> void:
	for tween: Tween in _trigger_tweens.values():
		if tween.is_valid(): tween.kill()
	_trigger_tweens.clear()
	for item: Control in _items.values():
		if is_instance_valid(item): item.get_node("TriggerGlow").visible = false
	last_trigger_id = ""
