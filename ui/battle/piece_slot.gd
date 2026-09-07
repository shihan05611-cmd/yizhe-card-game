class_name BattlePieceSlot
extends PanelContainer

@onready var slot_label: Label = %SlotLabel
@onready var class_label: Label = %ClassLabel
@onready var hp_bar: ProgressBar = %HpBar
@onready var hp_label: Label = %HpLabel
@onready var buff_label: Label = %BuffLabel
@onready var name_strike: ColorRect = %NameStrike
@onready var death_mark: Control = %DeathMark

@onready var chess_art: TextureRect = %ChessArt

const ART_KINDS := {"shield": "guard", "crossbow": "crossbow", "assassin": "assassin", "banner": "standard", "guard": "guard", "archer": "crossbow"}
const CLASS_NAMES := {
	"shield": "甲卒", "crossbow": "机弩", "assassin": "刺客", "banner": "旗兵",
	"guard": "甲卒",
	"warrior": "战士",
	"archer": "机弩",
}

var _anchor_slot := 0
var _pending: Dictionary = {}
var _hp_tween: Tween
var _pulse_tween: Tween
var _action_tween: Tween
var _art_atlas := AtlasTexture.new()
var _action_pose := 0.0:
	set(value):
		_action_pose = value
		_art_atlas.region = Rect2(roundi(value * 8) * 220, 0, 220, 252)
var _display_hp := 0.0:
	set(value):
		_display_hp = value
		if is_node_ready():
			hp_bar.value = value
			hp_label.text = "%d / %d" % [roundi(value), roundi(hp_bar.max_value)]


func _ready() -> void:
	if not _pending.is_empty():
		_apply(_pending)


func set_anchor_slot(slot: int) -> void:
	_anchor_slot = slot
	if is_node_ready() and _pending.is_empty():
		set_empty(slot)


func anchor_slot() -> int:
	return _anchor_slot


func unit_id() -> Variant:
	return _pending.get("id")


func bind_slot(slot_vm: Dictionary) -> void:
	_pending = slot_vm.duplicate(true)
	if is_node_ready():
		_apply(_pending)


func set_empty(slot: int = 0) -> void:
	_anchor_slot = slot if slot > 0 else _anchor_slot
	_pending = {}
	if not is_node_ready():
		return
	chess_art.texture = null
	slot_label.text = str(_anchor_slot)
	class_label.text = "空位"
	hp_bar.max_value = 1.0
	_display_hp = 0.0
	hp_label.text = "—"
	buff_label.text = ""
	buff_label.visible = false
	name_strike.visible = false
	death_mark.visible = false
	modulate = Color(1, 1, 1, 0.55)


func _apply(slot_vm: Dictionary) -> void:
	_anchor_slot = int(slot_vm.get("slot", _anchor_slot))
	var alive := bool(slot_vm.get("alive", false))
	var hp := float(slot_vm.get("hp", 0.0))
	var max_hp := maxf(1.0, float(slot_vm.get("max_hp", 1.0)))
	slot_label.text = str(_anchor_slot)
	var art_kind: String = ART_KINDS.get(str(slot_vm.get("class_id", "")), "guard")
	var side := "ally" if slot_vm.get("side") == "ally" else "enemy"
	_art_atlas.atlas = load("res://ui/art/pieces/%s-%s.svg" % [art_kind, side])
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	_action_pose = 0.0
	chess_art.texture = _art_atlas
	tooltip_text = "%s  %d / %d" % [_localized_class_name(slot_vm), hp, max_hp]
	class_label.text = _localized_class_name(slot_vm)
	var meter := StyleBoxFlat.new()
	meter.bg_color = Color("8cbaa7") if side == "ally" else Color("bf8873")
	meter.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", meter)
	hp_bar.max_value = max_hp
	_kill_hp_tween()
	_display_hp = hp
	buff_label.text = _buff_text(slot_vm.get("buffs", []))
	buff_label.visible = not buff_label.text.is_empty()
	name_strike.visible = not alive
	death_mark.visible = not alive
	modulate = Color.WHITE if alive else Color(0.55, 0.55, 0.55, 0.8)


func present_hp_change(old_hp: float, new_hp: float, max_hp: float, duration: float) -> void:
	if not is_node_ready():
		return
	_kill_hp_tween()
	hp_bar.max_value = maxf(1.0, max_hp)
	_display_hp = old_hp
	if duration <= 0.0 or not is_inside_tree():
		_display_hp = new_hp
		return
	_hp_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_property(self, "_display_hp", new_hp, duration)


func present_pulse(duration: float, tint: Color = Color(1.18, 1.18, 1.18, 1.0)) -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var resting := modulate
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "modulate", tint, maxf(0.03, duration * 0.35))
	_pulse_tween.tween_property(self, "modulate", resting, maxf(0.03, duration * 0.65))


func _kill_hp_tween() -> void:
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = null


func present_action(duration: float) -> void:
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	_action_pose = 0.0
	_action_tween = create_tween()
	_action_tween.tween_property(self, "_action_pose", 1.0, maxf(0.02, duration * 0.35))
	_action_tween.tween_property(self, "_action_pose", 0.0, maxf(0.02, duration * 0.65))


static func _buff_text(buffs: Variant) -> String:
	if typeof(buffs) != TYPE_ARRAY or buffs.is_empty():
		return ""
	var values: Array[String] = []
	for buff: Dictionary in buffs:
		values.append("%s×%s" % [str(buff.get("id", "?")), str(buff.get("stacks", 0))])
	return "  ".join(values)


static func _localized_class_name(slot_vm: Dictionary) -> String:
	var class_id := str(slot_vm.get("class_id", ""))
	if CLASS_NAMES.has(class_id):
		return CLASS_NAMES[class_id]
	var authored_name := str(slot_vm.get("class_name", class_id))
	if authored_name == "默认":
		return "棋子"
	return CLASS_NAMES.get(
		authored_name.to_lower(), authored_name if not authored_name.is_empty() else "棋子"
	)
