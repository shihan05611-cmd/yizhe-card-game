class_name CardView
extends Control

signal hover_changed(card: Control, hovered: bool)
signal drag_started(card: Control, pointer_global: Vector2)
signal drag_moved(card: Control, pointer_global: Vector2)
signal drag_finished(card: Control, pointer_global: Vector2)
signal drag_cancelled

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
@onready var _illustration: Control = %CardIllustration
@onready var _card_face: Control = $CardSurface/CardFace

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
	_description_label.text = _card_short_description()
	var category := str(_card_vm.get("category", ""))
	_category_label.text = _category_mark(category)
	_category_label.modulate = {
		"free": Color("395646"), "exclusive": Color("69583d"), "ultimate": Color("80503d"),
	}.get(category, Color("263c31"))
	var owner: Variant = _card_vm.get("owner_hero_id")
	_owner_label.text = "公共" if owner == null or int(owner) == 0 else str(HERO_NAMES.get(int(owner), "弈者"))
	_cost_label.text = _cost_text()
	_tags_label.text = _tag_text()
	_card_face.bind_card(_card_vm)
	_illustration.bind_card(_card_vm)
	var complete_tooltip := str(_card_vm.get("description", ""))
	if bool(_card_vm.get("retained", false)):
		complete_tooltip += "\n\n保留：回合结束时留在手牌中，仍占手牌上限；使用后的弃牌、消耗或回手规则不变。"
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
	modulate.a = 1.0
	drag_cancelled.emit()
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
	if bool(_card_vm.get("retained", false)):
		tags.append("保留")
	if bool(_card_vm.get("exhausts_on_success", false)):
		tags.append("消耗")
	if str(_card_vm.get("play_destination", "")) == "hand":
		tags.append("回手")
	if not bool(_card_vm.get("exhausts_on_success", false)) and str(_card_vm.get("play_destination", "")) != "hand":
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


func _card_short_description() -> String:
	# The hand uses deliberately short, accurate reading lines; the untouched
	# authored description remains on both tooltip targets for full rules text.
	if str(_card_vm.get("category", "")) == "ultimate":
		return _ultimate_short_line()
	var short_lines := {
		"pieceBlock": "我方全体格挡率 +15%\n持续 1 回合",
		"pieceAction": "拖到我方弈子\n下回合额外行动 1 次",
		"pieceDamageUp": "我方全体直接伤害 +25%\n持续 1 回合",
		"markBurn": "敌方灼烧层数最高单位\n施加 1 层灼烧",
		"executeStrike": "拖到指定敌人；攻击最高棋子出手\n造成 150% 直接伤害",
		"spSurge": "回复 2 技能点，可在本回合溢出\n本场消耗",
		"tacticalDraw": "抽 2 张牌\n本场消耗",
		"smallHeal": "我方当前生命最低棋子\n回复 5% 生命上限",
		"shadow": "攻击最高的非傀儡棋子进入潜行 1 回合\n结算后回到手牌",
		"pressOpening": "敌方有破势时\n攻击最高的非傀儡\n获得 2 层追击",
		"fist": "造成基于棋子平均攻击的直接伤害\n并叠加 1 层拳势",
		"siege": "对单体造成平均攻击的直接伤害\n并施加不可叠加的破势",
		"puppet": "在我方空位召唤傀儡\n固定 100 生命、攻击 0",
		"puppetAttunement": "指定傀儡获得 1 个附魔槽\n未指定时自动选择",
		"ascend": "目标位棋子升变为将军\n生命上限 +80，格挡率 +10%",
		"fate": "激活命运结界（每场一次）\n每回合随机切换命运",
		"burn01": "灼烧翻倍，持续 +2 回合\n费用 1/2/4/8，此后均 8",
		"burnEnchant": "可附魔弈子获得 1 层炎华\n费用 1/2/2/4，此后均 4",
	}
	return str(short_lines.get(str(_card_vm.get("source_skill_id", "")), _card_vm.get("description", "")))


func _ultimate_short_line() -> String:
	var lines := {
		"burn01": "敌方全体受到直接伤害\n伤害随灼烧层数提高",
		"fate": "1 回合内同时生效所有命运\n并剔除对己方的约束",
		"ascend": "将军回复已损生命的 50%\n获得出征 2 回合",
		"counterAura": "全体棋子获得骑士道\n受伤时直接超级反击",
		"burnEnchant": "全体获得炎汲 2 回合\n受灼烧敌人攻击时回复",
		"fist": "随机目标连续打击 3 段\n每层拳势额外 +1 段",
		"siege": "展开破阵领域 2 回合\n敌方直接伤害承受 +20%",
		"puppet": "所有空位召唤傀儡\n傀儡获得殉道",
		"shadow": "锁定敌方最低生命单位\n造成 400% 伤害，潜行者追击",
	}
	return str(lines.get(str(_card_vm.get("source_skill_id", "")), "发动弈者的大招效果。"))


static func _category_mark(category: String) -> String:
	match category:
		"free": return "◇ 自由"
		"exclusive": return "◆ 专属"
		"ultimate": return "◆ 大招"
	return "◇ 卡牌"


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
