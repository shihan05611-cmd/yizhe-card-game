class_name HandView
extends Control

signal play_card_requested(command: Dictionary)

@export var card_scene: PackedScene = preload("res://scenes/cards/card_view.tscn")
@export_range(1, 7, 1) var supported_hand_size := 7
@export var horizontal_edge_padding := 32.0
@export var preferred_card_spacing := 116.0
@export_range(0.72, 1.0, 0.01) var minimum_visible_ratio := 0.72
@export var maximum_rotation_degrees := 7.0
@export var arc_height := 24.0
@export var bottom_padding := 20.0
@export var drag_play_threshold := 82.0
@export var animate_layout := true

@onready var _card_container: Control = %CardContainer

var _cards_by_instance: Dictionary = {}
var _ordered_instance_ids: Array[String] = []
var _drag_origins: Dictionary = {}
var _release_poses: Dictionary = {}
var _queue_busy := false
var _fatal := false
var _session_halted := false
var _battle_phase := "player_input"
var _last_layout_scale := 1.0
var _last_unscaled_spacing := 0.0
var _queued_instance_ids: Dictionary = {}
var _queued_positions: Dictionary = {}
var _returning_instance_ids: Dictionary = {}


func _ready() -> void:
	resized.connect(_on_resized)
	layout_cards(false)


func apply_view_model(view_model: Dictionary) -> void:
	var battle: Dictionary = view_model.get("battle", {})
	var session: Dictionary = view_model.get("session", {})
	var interaction: Dictionary = view_model.get("interaction", {})
	_battle_phase = str(battle.get("phase", ""))
	_fatal = view_model.get("fatal") != null
	_session_halted = bool(session.get("halted", false))
	_queue_busy = bool(interaction.get("queue_busy", false))
	_sync_cards(view_model.get("hand", []))
	_refresh_interaction_locks()
	layout_cards(animate_layout)


func set_queue_busy(busy: bool) -> void:
	_queue_busy = busy
	_refresh_interaction_locks()


func set_queued_instance_ids(instance_ids: Array) -> void:
	_queued_instance_ids.clear()
	for instance_id: Variant in instance_ids:
		_queued_instance_ids[str(instance_id)] = true
	for instance_id: String in _ordered_instance_ids.duplicate():
		if _queued_instance_ids.has(instance_id):
			var card: Variant = _cards_by_instance.get(instance_id)
			if not _queued_positions.has(instance_id):
				_queued_positions[instance_id] = _ordered_instance_ids.find(instance_id)
			_ordered_instance_ids.erase(instance_id)
			if card != null:
				card.visible = false
	for instance_id: Variant in _queued_positions.keys():
		if not _queued_instance_ids.has(instance_id):
			_queued_positions.erase(instance_id)
			_returning_instance_ids.erase(instance_id)
	layout_cards(animate_layout)


## Restores a successful return-on-play card as the hidden target for the
## settlement queue's flight. The instance remains queued for input purposes
## until presentation completes, so it cannot be submitted a second time.
func prepare_queued_return(instance_id: String) -> Variant:
	if not _queued_instance_ids.has(instance_id):
		return null
	var card: Variant = _cards_by_instance.get(instance_id)
	if card == null:
		return null
	_returning_instance_ids[instance_id] = true
	if not _ordered_instance_ids.has(instance_id):
		var original_index := int(_queued_positions.get(instance_id, _ordered_instance_ids.size()))
		var restored_index := clampi(original_index, 0, _ordered_instance_ids.size())
		_ordered_instance_ids.insert(restored_index, instance_id)
		_card_container.move_child(card, clampi(restored_index, 0, _card_container.get_child_count() - 1))
	card.visible = false
	layout_cards(false)
	return card


## Keep already-visible cards responsive to authoritative prerequisite/cost
## changes while a prior card's presentation is still playing.  This never
## creates cards or applies unrelated battle/HP snapshots.
func refresh_visible_availability(authoritative_hand: Array) -> void:
	var by_instance: Dictionary = {}
	for value: Variant in authoritative_hand:
		if typeof(value) == TYPE_DICTIONARY:
			by_instance[str(value.get("instance_id", ""))] = value
	for instance_id: String in _ordered_instance_ids:
		var card: Variant = _cards_by_instance.get(instance_id)
		var current: Dictionary = by_instance.get(instance_id, {})
		if card == null or current.is_empty():
			continue
		var shown: Dictionary = card.view_model()
		for field: String in ["playable", "effective_cost", "unavailable_reason"]:
			shown[field] = current.get(field, shown.get(field))
		card.bind_card(shown)
	_refresh_interaction_locks()


func set_interaction_state(
	queue_busy: bool,
	fatal: bool,
	battle_phase: String,
	session_halted: bool = false,
) -> void:
	_queue_busy = queue_busy
	_fatal = fatal
	_battle_phase = battle_phase
	_session_halted = session_halted
	_refresh_interaction_locks()


func card_count() -> int:
	return _ordered_instance_ids.size()


func card_for_instance(instance_id: String) -> Variant:
	return _cards_by_instance.get(instance_id)


func cards_in_order() -> Array:
	var cards: Array = []
	for instance_id: String in _ordered_instance_ids:
		var card: Variant = card_for_instance(instance_id)
		if card != null:
			cards.append(card)
	return cards


func last_layout_scale() -> float:
	return _last_layout_scale


func last_unscaled_spacing() -> float:
	return _last_unscaled_spacing


func present_card_event(event: Dictionary, duration: float) -> void:
	var payload: Dictionary = event.get("payload", {})
	var instance_id := str(payload.get("card_instance_id", ""))
	var card: Variant = card_for_instance(instance_id)
	if card != null:
		card.present_destination(str(payload.get("destination", "discard")), duration)


func layout_cards(animate: bool = false) -> void:
	if not is_node_ready():
		return
	var cards: Array = cards_in_order()
	var count: int = cards.size()
	if count == 0:
		_last_layout_scale = 1.0
		_last_unscaled_spacing = 0.0
		return
	var available_size := _card_container.size
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		available_size = size
	# An instanced Control can retain its source-scene offsets until the parent
	# layout pass completes. Clamp to the actual reserve so rotated outer cards
	# never spill below the 1200x700 battle window.
	var parent_control := get_parent_control()
	if parent_control != null and parent_control.size.x > 0.0 and parent_control.size.y > 0.0:
		available_size = Vector2(
			minf(available_size.x, parent_control.size.x),
			minf(available_size.y, parent_control.size.y),
		)
	var card_size: Vector2 = cards[0].size
	if card_size.x <= 0.0 or card_size.y <= 0.0:
		card_size = cards[0].custom_minimum_size
	var minimum_spacing := card_size.x * minimum_visible_ratio
	var unscaled_spacing := 0.0 if count == 1 else maxf(preferred_card_spacing, minimum_spacing)
	var max_rotation := deg_to_rad(maximum_rotation_degrees)
	var rotated_half_width := (
		absf(cos(max_rotation)) * card_size.x * 0.5
		+ absf(sin(max_rotation)) * card_size.y * 0.5
	)
	var unscaled_required_width := card_size.x if count == 1 else (
		unscaled_spacing * float(count - 1) + rotated_half_width * 2.0
	)
	var usable_width := maxf(1.0, available_size.x - horizontal_edge_padding * 2.0)
	var layout_scale := minf(1.0, usable_width / unscaled_required_width)
	var spacing := unscaled_spacing * layout_scale
	_last_layout_scale = layout_scale
	_last_unscaled_spacing = unscaled_spacing
	var center_x := available_size.x * 0.5
	var outer_half_height := (
		absf(sin(max_rotation)) * card_size.x * layout_scale * 0.5
		+ absf(cos(max_rotation)) * card_size.y * layout_scale * 0.5
	)
	var baseline_center_y := available_size.y - bottom_padding - outer_half_height
	for index in count:
		var normalized := 0.5 if count == 1 else float(index) / float(count - 1)
		var centered_index := float(index) - float(count - 1) * 0.5
		var card_center_x := center_x + centered_index * spacing
		var curve_height := -sin(normalized * PI) * arc_height * layout_scale
		var rotation_radians := deg_to_rad(lerpf(-maximum_rotation_degrees, maximum_rotation_degrees, normalized))
		if count == 1:
			rotation_radians = 0.0
		var target_position := Vector2(
			card_center_x - card_size.x * 0.5,
			baseline_center_y + curve_height - card_size.y * 0.5,
		)
		# Increasing z order means the later/right card covers only the previous
		# card's right edge. Hover and drag use their own higher layers.
		cards[index].apply_layout_pose(target_position, rotation_radians, index, layout_scale, animate)


func _sync_cards(hand_vm: Array) -> void:
	var desired_ids: Array[String] = []
	var desired_lookup := {}
	for card_value: Variant in hand_vm:
		if typeof(card_value) != TYPE_DICTIONARY:
			continue
		var card_vm: Dictionary = card_value
		var instance_id := str(card_vm.get("instance_id", ""))
		if (
			instance_id.is_empty()
			or desired_lookup.has(instance_id)
			or (_queued_instance_ids.has(instance_id) and not _returning_instance_ids.has(instance_id))
		):
			continue
		desired_ids.append(instance_id)
		desired_lookup[instance_id] = card_vm

	for existing_id: Variant in _cards_by_instance.keys():
		if desired_lookup.has(existing_id):
			continue
		var removed: Variant = _cards_by_instance[existing_id]
		_cards_by_instance.erase(existing_id)
		_drag_origins.erase(existing_id)
		if removed != null:
			_card_container.remove_child(removed)
			removed.queue_free()

	for index in desired_ids.size():
		var instance_id := desired_ids[index]
		var card: Variant = card_for_instance(instance_id)
		if card == null:
			card = card_scene.instantiate()
			_card_container.add_child(card)
			card.hover_changed.connect(_on_card_hover_changed)
			card.drag_started.connect(_on_card_drag_started)
			card.drag_moved.connect(_on_card_drag_moved)
			card.drag_finished.connect(_on_card_drag_finished)
			_cards_by_instance[instance_id] = card
		card.bind_card(desired_lookup[instance_id])
		_card_container.move_child(card, index)
	_ordered_instance_ids = desired_ids


func _refresh_interaction_locks() -> void:
	if not is_node_ready():
		return
	var reason := _global_lock_reason()
	for card: Variant in cards_in_order():
		card.set_interaction_lock(not reason.is_empty(), reason)


func _global_lock_reason() -> String:
	if _fatal:
		return "战斗已终止"
	if _session_halted:
		return "战斗会话已停止"
	if _queue_busy:
		return "正在结算上一张牌"
	if _battle_phase != "player_input":
		return "当前不是玩家出牌阶段"
	return ""


func _on_card_hover_changed(card: Control, hovered: bool) -> void:
	card.set_hovered(hovered, animate_layout)


func _on_card_drag_started(card: Control, pointer_global: Vector2) -> void:
	if not _can_issue_for(card):
		card.cancel_drag(animate_layout)
		return
	_drag_origins[card.instance_id()] = pointer_global


func _on_card_drag_moved(_card: Control, _pointer_global: Vector2) -> void:
	pass


func _on_card_drag_finished(card: Control, pointer_global: Vector2) -> void:
	var instance_id: String = card.instance_id()
	var origin: Vector2 = _drag_origins.get(instance_id, pointer_global)
	_drag_origins.erase(instance_id)
	var crossed_threshold := origin.y - pointer_global.y >= drag_play_threshold
	if crossed_threshold and _can_issue_for(card):
		_release_poses[instance_id] = {"position": card.global_position, "rotation": card.rotation, "scale": card.scale}
		var vm: Dictionary = card.view_model()
		play_card_requested.emit({
			"type": "play_card",
			"instance_id": instance_id,
			"expected_card_id": str(vm.get("card_id", "")),
			"expected_source_skill_id": str(vm.get("source_skill_id", "")),
			"owner_hero_id": vm.get("owner_hero_id"),
		})
	card.cancel_drag(animate_layout)


func take_release_pose(instance_id: String) -> Dictionary:
	var pose: Dictionary = _release_poses.get(instance_id, {}).duplicate(true)
	_release_poses.erase(instance_id)
	return pose


func _can_issue_for(card: Control) -> bool:
	return _global_lock_reason().is_empty() and card.is_playable()


func _on_resized() -> void:
	layout_cards(animate_layout)
