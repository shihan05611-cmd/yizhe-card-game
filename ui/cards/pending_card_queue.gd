class_name PendingCardQueue
extends Control

signal cancel_requested(instance_id: String)

const CardViewScene: PackedScene = preload("res://scenes/cards/card_view.tscn")
const CARD_SCALE := 0.733
const CARD_SIZE := Vector2(122.0, 174.0)
const WAITING_STEP := 20.0
const MAX_WAITING_ROWS := 3

var _entries: Array[Dictionary] = []
var _panel: Panel
var _notice: Label
var _notice_serial := 0
var _static_items: Dictionary = {}
var _flights: Dictionary = {}
var _return_flights: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_notice = Label.new()
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_notice.size = Vector2(260.0, 42.0)
	_notice.position = Vector2(-138.0, -26.0)
	_notice.add_theme_color_override("font_color", Color("d9c88f"))
	_notice.visible = false
	add_child(_notice)
	_refresh()


func set_queue_anchor(rect: Rect2) -> void:
	var overlay_height := CARD_SIZE.y + WAITING_STEP * float(MAX_WAITING_ROWS)
	position = rect.position + Vector2((rect.size.x - CARD_SIZE.x) * 0.5, rect.size.y - overlay_height)
	size = Vector2(CARD_SIZE.x, overlay_height)


func set_entries(entries: Array) -> void:
	_entries.clear()
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			_entries.append(entry.duplicate(true))
	_refresh()


func flight_count() -> int:
	return _flights.size() + _return_flights.size()


func flight_card(instance_id: String) -> Variant:
	return _flights.get(instance_id, _return_flights.get(instance_id))


func animate_arrival(instance_id: String, card_vm: Dictionary, release_pose: Dictionary, duration: float) -> void:
	if release_pose.is_empty() or not _static_items.has(instance_id): return
	var target: Control = _static_items[instance_id]
	if not is_instance_valid(target): return
	var old: Variant = _flights.get(instance_id)
	if old != null and is_instance_valid(old): old.queue_free()
	if not target.has_meta("aggregate"): target.visible = false
	var card: Control = CardViewScene.instantiate()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	card.rotation = float(release_pose.get("rotation", 0.0))
	card.scale = release_pose.get("scale", Vector2.ONE)
	card.global_position = release_pose.get("position", card.global_position)
	card.call_deferred("bind_card", card_vm)
	card.set_meta("flight_pose", release_pose.duplicate(true))
	_flights[instance_id] = card
	var flight_time := maxf(0.08, duration)
	var tween := card.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(weight: float) -> void: _advance_arrival(instance_id, weight), 0.0, 1.0, flight_time)
	tween.chain().tween_callback(func() -> void:
		if _flights.get(instance_id) == card:
			_flights.erase(instance_id)
			var current: Variant = _static_items.get(instance_id)
			if is_instance_valid(current): current.visible = true
		card.queue_free()
	)
	card.get_node("InputButton").mouse_filter = Control.MOUSE_FILTER_IGNORE


## A return-on-play card is authoritative in hand before its presentation
## finishes. Fly the queue preview into the hidden hand node, then reveal that
## same node at arrival instead of creating a second visual instance.
func animate_return(instance_id: String, target: Control, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var source_position := Vector2.ZERO
	var source_rotation := 0.0
	var source_scale := Vector2.ONE * CARD_SCALE
	var active_flight: Variant = _flights.get(instance_id)
	if active_flight != null and is_instance_valid(active_flight):
		source_position = active_flight.global_position
		source_rotation = active_flight.rotation
		source_scale = active_flight.scale
		active_flight.queue_free()
		_flights.erase(instance_id)
	else:
		var preview: Variant = _static_items.get(instance_id)
		if preview != null and is_instance_valid(preview):
			source_position = preview.global_position
			source_rotation = preview.rotation
			source_scale = preview.scale
	var old_return: Variant = _return_flights.get(instance_id)
	if old_return != null and is_instance_valid(old_return):
		old_return.queue_free()
	var card: Control = CardViewScene.instantiate()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	card.bind_card(target.view_model())
	card.scale = source_scale
	card.rotation = source_rotation
	card.global_position = source_position
	card.set_meta("return_pose", {
		"position": source_position, "scale": source_scale, "rotation": source_rotation,
	})
	_return_flights[instance_id] = card
	visible = true
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		func(weight: float) -> void: _advance_return(instance_id, target, weight),
		0.0,
		1.0,
		maxf(0.08, duration),
	)
	tween.chain().tween_callback(func() -> void:
		if _return_flights.get(instance_id) == card:
			_return_flights.erase(instance_id)
			if is_instance_valid(target):
				target.visible = true
			card.queue_free()
			visible = not _entries.is_empty() or not _return_flights.is_empty()
	)
	var input: Control = card.get_node_or_null("InputButton")
	if input != null:
		input.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _advance_arrival(instance_id: String, weight: float) -> void:
	var card: Variant = _flights.get(instance_id)
	var target: Variant = _static_items.get(instance_id)
	if not is_instance_valid(card) or not is_instance_valid(target): return
	var pose: Dictionary = card.get_meta("flight_pose")
	var rect: Rect2 = target.get_global_rect()
	var end_scale: Vector2 = rect.size / card.size
	var origin: Vector2 = pose.get("position", card.global_position)
	var start_scale: Vector2 = pose.get("scale", Vector2.ONE)
	card.scale = start_scale.lerp(end_scale, weight)
	card.rotation = lerpf(float(pose.get("rotation", 0.0)), 0.0, weight)
	card.global_position = origin.lerp(rect.position, weight)


func _advance_return(instance_id: String, target: Control, weight: float) -> void:
	var card: Variant = _return_flights.get(instance_id)
	if not is_instance_valid(card) or not is_instance_valid(target):
		return
	var pose: Dictionary = card.get_meta("return_pose", {})
	# The queue and hand share the battle CanvasLayer with unit parent scale, so
	# the target's transform properties are the visual landing pose. A rotated
	# Control's global Rect is an axis-aligned bounding box and would snap here.
	card.scale = pose["scale"].lerp(target.scale, weight)
	card.rotation = lerpf(float(pose["rotation"]), target.rotation, weight)
	card.global_position = pose["position"].lerp(target.global_position, weight)


func cancel_return_flights() -> void:
	for flight: Variant in _return_flights.values():
		if is_instance_valid(flight):
			flight.queue_free()
	_return_flights.clear()
	if _entries.is_empty():
		visible = false


func is_occupied() -> bool:
	return not _entries.is_empty()


func show_notice(message: String) -> void:
	if not is_instance_valid(_notice): return
	_notice_serial += 1
	var serial := _notice_serial
	_notice.text = message
	_notice.visible = true
	visible = true
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if serial == _notice_serial and is_instance_valid(_notice):
			_notice.visible = false
			if _entries.is_empty() and _return_flights.is_empty(): visible = false
	)


func _refresh() -> void:
	if not is_instance_valid(_panel): return
	for child: Node in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	_static_items.clear()
	var live_ids: Dictionary = {}
	for entry: Dictionary in _entries: live_ids[str(entry.get("instance_id", ""))] = true
	for id: Variant in _flights.keys():
		if not live_ids.has(id):
			var flight: Variant = _flights[id]
			if flight != null and is_instance_valid(flight): flight.queue_free()
			_flights.erase(id)
	visible = not _entries.is_empty() or not _return_flights.is_empty()
	if _entries.is_empty(): return
	_add_lead_card(_entries[0])
	for index in range(1, mini(_entries.size(), MAX_WAITING_ROWS + 1)):
		_add_waiting_row(_entries[index], index - 1)
	if _entries.size() > MAX_WAITING_ROWS + 1:
		var more := Label.new()
		more.text = "+%d" % [_entries.size() - MAX_WAITING_ROWS - 1]
		more.position = Vector2(92.0, CARD_SIZE.y + WAITING_STEP * float(MAX_WAITING_ROWS - 1))
		more.size = Vector2(30.0, WAITING_STEP)
		more.set_meta("aggregate", true)
		more.tooltip_text = "还有 %d 张等待中的牌" % [_entries.size() - MAX_WAITING_ROWS - 1]
		_panel.add_child(more)
		for index in range(MAX_WAITING_ROWS + 1, _entries.size()):
			_static_items[str(_entries[index].get("instance_id", ""))] = more


func _add_lead_card(entry: Dictionary) -> void:
	var card := CardViewScene.instantiate()
	# CardView centers its own pivot in _ready; restore a top-left pivot after
	# that setup so this scaled preview stays inside its exact 122px column.
	card.position = Vector2((CARD_SIZE.x - 150.0 * CARD_SCALE) * 0.5, 20.0)
	card.scale = Vector2.ONE * CARD_SCALE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(card)
	_static_items[str(entry.get("instance_id", ""))] = card
	card.visible = not _flights.has(str(entry.get("instance_id", "")))
	call_deferred("_bind_lead_card", card, entry.get("card", {"name": entry.get("name", "卡牌")}))
	var state := Label.new()
	var releasing := str(entry.get("state", "waiting")) == "releasing"
	state.text = "释放中" if releasing else "待出"
	state.position = Vector2(4.0, 1.0)
	state.z_index = 100
	state.add_theme_color_override("font_color", Color("d9c88f"))
	state.tooltip_text = "当前表现完成前不能取消" if releasing else "点击取消这张等待中的牌"
	_panel.add_child(state)
	if not releasing:
		var cancel := Button.new()
		cancel.text = "取消"
		cancel.position = Vector2(76.0, 2.0)
		cancel.size = Vector2(42.0, 24.0)
		cancel.pressed.connect(func() -> void: cancel_requested.emit(str(entry.get("instance_id", ""))))
		_panel.add_child(cancel)


func _add_waiting_row(entry: Dictionary, index: int) -> void:
	var row := Button.new()
	row.text = str(entry.get("name", "卡牌"))
	row.tooltip_text = "等待中的牌；点击取消"
	row.position = Vector2(4.0, CARD_SIZE.y + WAITING_STEP * float(index))
	row.size = Vector2(114.0, WAITING_STEP)
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.pressed.connect(func() -> void: cancel_requested.emit(str(entry.get("instance_id", ""))))
	_panel.add_child(row)
	_static_items[str(entry.get("instance_id", ""))] = row
	row.visible = not _flights.has(str(entry.get("instance_id", "")))


func _bind_lead_card(card: Control, card_vm: Dictionary) -> void:
	if not is_instance_valid(card): return
	card.pivot_offset = Vector2.ZERO
	card.bind_card(card_vm)
	var input: Control = card.get_node_or_null("InputButton")
	if input != null:
		input.mouse_filter = Control.MOUSE_FILTER_IGNORE
