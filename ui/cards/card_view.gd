class_name CardView
extends Control

signal hover_changed(card: Control, hovered: bool)
signal drag_started(card: Control, pointer_global: Vector2)
signal drag_moved(card: Control, pointer_global: Vector2)
signal drag_finished(card: Control, pointer_global: Vector2)

const CATEGORY_NAMES := {
	"free": "自由技",
	"exclusive": "专属技",
	"ultimate": "大招",
}

const HERO_NAMES := {1: "赤焰", 3: "元帅", 4: "骑士", 5: "偃术师", 6: "宁不凡", 7: "辰歌", 8: "千机", 9: "影手"}

@export var hover_scale := 1.08
@export var hover_lift := 28.0

@onready var _hover_shadow: Panel = %HoverShadow
@onready var _surface: Panel = %CardSurface
@onready var _name_label: Label = %CardName
@onready var _description_label: Label = %CardDescription
@onready var _cost_label: Label = %Cost
@onready var _category_label: Label = %Category
@onready var _owner_label: Label = %Owner
@onready var _tags_label: Label = %Tags
@onready var _disabled_overlay: ColorRect = %DisabledOverlay
@onready var _reason_label: Label = %UnavailableReason
@onready var _input_button: Button = %InputButton

var _card_vm: Dictionary = {}
var _layout_position := Vector2.ZERO
var _layout_rotation := 0.0
var _layout_z := 0
var _layout_scale := 1.0
var _hovered := false
var _dragging := false
var _interaction_locked := false
var _interaction_lock_reason := ""
var _drag_pointer_offset := Vector2.ZERO
var _pose_tween: Tween
var _destination_tween: Tween


func _ready() -> void:
	pivot_offset = size * 0.5
	_input_button.gui_input.connect(_on_input_button_gui_input)
	_input_button.mouse_entered.connect(_on_mouse_entered)
	_input_button.mouse_exited.connect(_on_mouse_exited)
	_refresh_visual_state()


func bind_card(card_vm: Dictionary) -> void:
	_card_vm = card_vm.duplicate(true)
	_name_label.text = str(_card_vm.get("name", "未命名卡牌"))
	_description_label.text = str(_card_vm.get("description", ""))
	_category_label.text = CATEGORY_NAMES.get(str(_card_vm.get("category", "")), "卡牌")
	var owner: Variant = _card_vm.get("owner_hero_id")
	_owner_label.text = "公共" if owner == null or int(owner) == 0 else str(HERO_NAMES.get(int(owner), "弈者"))
	_cost_label.text = _cost_text()
	_tags_label.text = _tag_text()
	var complete_tooltip := str(_card_vm.get("description", ""))
	var unavailable_reason := _display_reason(str(_card_vm.get("unavailable_reason", "")))
	if not unavailable_reason.is_empty():
		complete_tooltip += "\n\n不可使用：%s" % unavailable_reason
	tooltip_text = complete_tooltip
	_input_button.tooltip_text = complete_tooltip
	_refresh_visual_state()


func view_model() -> Dictionary:
	return _card_vm.duplicate(true)


func instance_id() -> String:
	return str(_card_vm.get("instance_id", ""))


func is_playable() -> bool:
	return bool(_card_vm.get("playable", false))


func displayed_unavailable_reason() -> String:
	return _reason_label.text


func set_interaction_lock(locked: bool, reason: String = "") -> void:
	_interaction_locked = locked
	_interaction_lock_reason = reason
	_refresh_visual_state()


func apply_layout_pose(
	target_position: Vector2,
	target_rotation: float,
	target_z: int,
	target_scale: float = 1.0,
	animate: bool = false,
) -> void:
	_layout_position = target_position
	_layout_rotation = target_rotation
	_layout_z = target_z
	_layout_scale = target_scale
	if not _dragging:
		_apply_rest_pose(animate)


func set_hovered(hovered: bool, animate: bool = true) -> void:
	_hovered = hovered
	_hover_shadow.visible = hovered
	if not _dragging:
		_apply_rest_pose(animate)


func begin_drag_at(pointer_global: Vector2) -> bool:
	if _dragging or _interaction_locked or not is_playable():
		return false
	_kill_pose_tween()
	_dragging = true
	_drag_pointer_offset = global_position - pointer_global
	rotation = 0.0
	scale = Vector2.ONE * _layout_scale * hover_scale
	z_index = 1000
	_hover_shadow.visible = true
	drag_started.emit(self, pointer_global)
	return true


func drag_to(pointer_global: Vector2) -> void:
	if not _dragging:
		return
	global_position = pointer_global + _drag_pointer_offset
	drag_moved.emit(self, pointer_global)


func end_drag_at(pointer_global: Vector2) -> void:
	if not _dragging:
		return
	drag_finished.emit(self, pointer_global)
	if _dragging:
		cancel_drag()


func cancel_drag(animate: bool = true) -> void:
	_dragging = false
	_hover_shadow.visible = _hovered
	_apply_rest_pose(animate)


func is_dragging() -> bool:
	return _dragging


func layout_position() -> Vector2:
	return _layout_position


func layout_rotation() -> float:
	return _layout_rotation


func layout_z_index() -> int:
	return _layout_z


func layout_scale() -> float:
	return _layout_scale


func is_hover_shadow_visible() -> bool:
	return _hover_shadow.visible


func present_destination(destination: String, duration: float) -> void:
	set_meta("last_presented_destination", destination)
	if _destination_tween != null and _destination_tween.is_valid():
		_destination_tween.kill()
	if not is_inside_tree() or duration <= 0.0:
		return
	_destination_tween = create_tween()
	_destination_tween.tween_property(self, "self_modulate:a", 0.55, duration * 0.45)
	_destination_tween.tween_property(self, "self_modulate:a", 1.0, duration * 0.55)


func _cost_text() -> String:
	var effective := int(_card_vm.get("effective_cost", _card_vm.get("base_cost", 0)))
	var base := int(_card_vm.get("base_cost", effective))
	return str(effective) if effective == base else "%d\n原%d" % [effective, base]


func _tag_text() -> String:
	var tags: Array[String] = []
	if bool(_card_vm.get("exhausts_on_success", false)):
		tags.append("消耗")
	if str(_card_vm.get("play_destination", "")) == "hand":
		tags.append("回手")
	if tags.is_empty():
		tags.append("弃牌")
	return " / ".join(tags)


func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	var authoritative_reason := str(_card_vm.get("unavailable_reason", ""))
	if authoritative_reason.is_empty():
		authoritative_reason = str(_card_vm.get("unavailable_code", ""))
	var disabled := not is_playable() or _interaction_locked
	var reason := authoritative_reason if not is_playable() else _interaction_lock_reason
	_disabled_overlay.visible = disabled
	_reason_label.visible = disabled and not reason.is_empty()
	_reason_label.text = _display_reason(reason)
	_surface.self_modulate = Color(0.58, 0.6, 0.64, 1.0) if disabled else Color.WHITE
	_input_button.mouse_default_cursor_shape = (
		Control.CURSOR_FORBIDDEN if disabled else Control.CURSOR_POINTING_HAND
	)


func _apply_rest_pose(animate: bool) -> void:
	_kill_pose_tween()
	var target_position := _layout_position + (Vector2.UP * hover_lift if _hovered else Vector2.ZERO)
	var target_scale := Vector2.ONE * _layout_scale * (hover_scale if _hovered else 1.0)
	var target_z := 900 if _hovered else _layout_z
	z_index = target_z
	if not animate or not is_inside_tree():
		position = target_position
		rotation = _layout_rotation
		scale = target_scale
		return
	_pose_tween = create_tween().set_parallel(true)
	_pose_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(self, "position", target_position, 0.12)
	_pose_tween.tween_property(self, "rotation", _layout_rotation, 0.12)
	_pose_tween.tween_property(self, "scale", target_scale, 0.12)


static func _display_reason(reason: String) -> String:
	# Translate presentation text only; availability remains authoritative in the VM.
	if reason.contains("requires at least one living target with Burn"):
		return "需要存在带灼烧的存活目标"
	if reason.begins_with("player_card_validator") or reason.begins_with("player card validator"):
		return "当前条件不满足"
	return reason


func _kill_pose_tween() -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = null


func _on_input_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if begin_drag_at(event.global_position):
				accept_event()
		elif _dragging:
			end_drag_at(event.global_position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		drag_to(event.global_position)
		accept_event()


func _on_mouse_entered() -> void:
	hover_changed.emit(self, true)


func _on_mouse_exited() -> void:
	if not _dragging:
		hover_changed.emit(self, false)
