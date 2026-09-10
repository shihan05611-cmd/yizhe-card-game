class_name BattlePieceSlot
extends PanelContainer

const BurnAuraScript = preload("res://ui/effects/burn_aura.gd")

@onready var slot_label: Label = %SlotLabel
@onready var class_label: Label = %ClassLabel
@onready var hp_bar: ProgressBar = %HpBar
@onready var hp_label: Label = %HpLabel
@onready var buff_label: Label = %BuffLabel
@onready var name_strike: ColorRect = %NameStrike
@onready var death_mark: Control = %DeathMark

@onready var chess_art: Control = %ChessArt

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
var _shot_tween: Tween
var _burn_aura: Control
var _action_presentation_count := 0
var _action_pose := 0.0:
	set(value):
		_action_pose = value
		if is_instance_valid(chess_art):
			chess_art.pose = value
var _display_hp := 0.0:
	set(value):
		_display_hp = value
		if is_node_ready():
			hp_bar.value = value
			hp_label.text = "%d / %d" % [roundi(value), roundi(hp_bar.max_value)]


func _ready() -> void:
	_ensure_burn_aura()
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
	chess_art.visible = false
	slot_label.visible = false
	class_label.text = ""
	hp_bar.visible = false
	hp_bar.max_value = 1.0
	_display_hp = 0.0
	hp_label.text = ""
	tooltip_text = ""
	buff_label.text = ""
	buff_label.visible = false
	name_strike.visible = false
	death_mark.visible = false
	modulate = Color(1, 1, 1, 0.55)
	_reset_burn_visuals()


func _apply(slot_vm: Dictionary) -> void:
	if not bool(slot_vm.get("occupied", float(slot_vm.get("max_hp", 1.0)) > 0.0)):
		set_empty(int(slot_vm.get("slot", _anchor_slot)))
		return
	_ensure_burn_aura()
	_anchor_slot = int(slot_vm.get("slot", _anchor_slot))
	var alive := bool(slot_vm.get("alive", false))
	var hp := float(slot_vm.get("hp", 0.0))
	var max_hp := maxf(1.0, float(slot_vm.get("max_hp", 1.0)))
	slot_label.visible = false
	hp_bar.visible = true
	var side := "ally" if slot_vm.get("side") == "ally" else "enemy"
	var art_kind := "puppet" if bool(slot_vm.get("is_puppet", false)) else str(slot_vm.get("class_id", "default"))
	if slot_vm.get("special_id") in ["devourer", "echo"]:
		art_kind = str(slot_vm["special_id"])
	chess_art.configure(art_kind, side == "enemy")
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	_action_pose = 0.0
	if _shot_tween != null and _shot_tween.is_valid():
		_shot_tween.kill()
	chess_art.shot_progress = -1.0
	tooltip_text = "%s  %d / %d" % [_localized_class_name(slot_vm), hp, max_hp]
	tooltip_text += "\n" + _enchantment_summary(slot_vm)
	if slot_vm.get("special_id") == "devourer":
		tooltip_text += "\n占据2格 · 每次攻击命中最多吞噬1 SP；SP耗尽时吞噬弈者最多10能量。"
	elif slot_vm.get("special_id") == "echo":
		tooltip_text += "\n占据3格 · 每次受到伤害，伤害加成增加1%。"
	class_label.text = _localized_class_name(slot_vm)
	var meter := StyleBoxFlat.new()
	meter.bg_color = Color("8cbaa7") if side == "ally" else Color("bf8873")
	meter.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", meter)
	hp_bar.max_value = max_hp
	_kill_hp_tween()
	_display_hp = hp
	buff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buff_label.max_lines_visible = 2
	buff_label.text = _status_text(slot_vm)
	buff_label.tooltip_text = buff_label.text
	if not buff_label.text.is_empty(): tooltip_text += "\n" + buff_label.text
	buff_label.visible = not buff_label.text.is_empty()
	_set_burn_stacks(_burn_stacks(slot_vm.get("buffs", [])) if alive else 0)
	name_strike.visible = not alive
	death_mark.visible = not alive
	modulate = Color.WHITE if alive else Color(0.55, 0.55, 0.55, 0.8)


func present_hp_change(old_hp: float, new_hp: float, max_hp: float, duration: float) -> void:
	if not is_node_ready():
		return
	_kill_hp_tween()
	hp_bar.max_value = maxf(1.0, max_hp)
	_display_hp = old_hp
	if new_hp <= 0.0:
		_reset_burn_visuals()
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
	var resting := _resting_modulate()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "modulate", tint, maxf(0.03, duration * 0.35))
	_pulse_tween.tween_property(self, "modulate", resting, maxf(0.03, duration * 0.65))


func present_buff_event(event: Dictionary) -> void:
	var payload: Dictionary = event.get("payload", {})
	var buff_id := str(payload.get("buff_id", ""))
	if buff_id.is_empty(): return
	var state: Variant = payload.get("state")
	var buffs: Array = _pending.get("buffs", []).duplicate(true)
	for index in range(buffs.size() - 1, -1, -1):
		if str(buffs[index].get("id", "")) == buff_id:
			buffs.remove_at(index)
	if typeof(state) == TYPE_DICTIONARY:
		var next: Dictionary = state.duplicate(true)
		next["id"] = buff_id
		buffs.append(next)
	_pending["buffs"] = buffs
	buff_label.text = _status_text(_pending)
	buff_label.tooltip_text = buff_label.text
	tooltip_text = "%s  %d / %d" % [_localized_class_name(_pending), roundi(hp_bar.value), roundi(hp_bar.max_value)]
	tooltip_text += "\n" + _enchantment_summary(_pending)
	if not buff_label.text.is_empty(): tooltip_text += "\n" + buff_label.text
	buff_label.visible = not buff_label.text.is_empty()
	_set_burn_stacks(_burn_stacks(buffs) if bool(_pending.get("alive", false)) else 0)


func set_presentation_speed(speed: float) -> void:
	_ensure_burn_aura()
	_burn_aura.set_presentation_speed(speed)


func reset_visuals() -> void:
	_kill_hp_tween()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	_action_pose = 0.0
	if _shot_tween != null and _shot_tween.is_valid():
		_shot_tween.kill()
	if is_instance_valid(chess_art):
		chess_art.shot_progress = -1.0
	_reset_burn_visuals()
	modulate = _resting_modulate()


func _kill_hp_tween() -> void:
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = null


func present_action(duration: float) -> void:
	_action_presentation_count += 1
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	_action_pose = 0.0
	_action_tween = create_tween()
	_action_tween.tween_property(self, "_action_pose", 1.0, maxf(0.02, duration * 0.38))
	_action_tween.tween_property(self, "_action_pose", 0.0, maxf(0.02, duration * 0.62))
	if _shot_tween != null and _shot_tween.is_valid():
		_shot_tween.kill()
	if chess_art.kind == "crossbow":
		chess_art.shot_progress = 0.0
		_shot_tween = create_tween()
		_shot_tween.tween_property(chess_art, "shot_progress", 1.0, maxf(0.04, duration))


func action_presentation_count() -> int:
	return _action_presentation_count


static func _buff_text(buffs: Variant) -> String:
	if typeof(buffs) != TYPE_ARRAY or buffs.is_empty():
		return ""
	var values: Array[String] = []
	for buff: Dictionary in buffs:
		if str(buff.get("id", "")) == "nextRoundAction":
			var ready := 0
			var waiting := 0
			for remaining: int in buff.get("layer_turns", []):
				if remaining <= 1: ready += 1
				else: waiting += 1
			if ready + waiting == 0:
				if int(buff.get("turns", 2)) <= 1: ready = int(buff.get("stacks", 0))
				else: waiting = int(buff.get("stacks", 0))
			if ready > 0: values.append("本回合额外行动×%d" % ready)
			if waiting > 0: values.append("下回合额外行动×%d" % waiting)
			continue
		var text := "%s×%s" % [_buff_display_name(buff), str(buff.get("stacks", 0))]
		var turns := int(buff.get("turns", 0))
		if turns > 0:
			text += "·%d回合" % turns
		values.append(text)
	return "  ".join(values)


static func _status_text(slot_vm: Dictionary) -> String:
	var text := _buff_text(slot_vm.get("buffs", []))
	var disarm := int(slot_vm.get("disarm_turns", 0))
	if disarm > 0:
		text += ("  " if not text.is_empty() else "") + "缴械·%d回合" % disarm
	return text


static func _enchantment_summary(slot_vm: Dictionary) -> String:
	var capacity := int(slot_vm.get("enchantment_capacity", 0 if slot_vm.get("is_puppet", false) else 2))
	if capacity == 0:
		return "附魔：未开放（可由千机·点化开放）"
	var names: Array[String] = []
	for buff: Dictionary in slot_vm.get("buffs", []):
		if buff.get("id") in ["general", "enchant"]:
			names.append("将军" if buff["id"] == "general" else "炎华")
	var text := "附魔 %d/%d" % [names.size(), capacity]
	if not names.is_empty():
		text += "：" + " → ".join(names) + "（从早到晚，满槽替换最早一种）"
	return text


static func _buff_display_name(buff: Dictionary) -> String:
	var provided := str(buff.get("name", ""))
	if not provided.is_empty():
		return provided
	return {
		"burn": "灼烧", "enchant": "附魔", "knightChivalry": "骑士道",
		"march": "出征", "stealth": "潜行", "vexed": "困扰",
		"breakMarked": "破势", "tempBlock": "临时格挡", "pieceDamageUp": "棋子增伤",
		"bloodShiftVulnerable": "血移易伤", "bloodShiftGuard": "血移庇护",
		"flameLeech": "炎汲", "breakFormation": "破阵领域", "pursuit": "追击",
		"general": "将军·附魔", "puppetAttunement": "傀儡附魔资格",
		"nextRoundAction": "额外行动",
	}.get(str(buff.get("id", "?")), str(buff.get("id", "?")))


func _ensure_burn_aura() -> void:
	if is_instance_valid(_burn_aura):
		return
	if not is_instance_valid(chess_art):
		return
	_burn_aura = BurnAuraScript.new()
	_burn_aura.name = "BurnAura"
	_burn_aura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chess_art.add_child(_burn_aura)


func _set_burn_stacks(stacks: int) -> void:
	_ensure_burn_aura()
	if is_instance_valid(_burn_aura):
		_burn_aura.set_burn_stacks(stacks)


func _reset_burn_visuals() -> void:
	if is_instance_valid(_burn_aura):
		_burn_aura.reset_visuals()


static func _burn_stacks(buffs: Variant) -> int:
	if typeof(buffs) != TYPE_ARRAY:
		return 0
	for buff: Dictionary in buffs:
		if str(buff.get("id", "")) == "burn":
			return maxi(0, int(buff.get("stacks", 0)))
	return 0


func _resting_modulate() -> Color:
	if _pending.is_empty():
		return Color(1, 1, 1, 0.55)
	return Color.WHITE if bool(_pending.get("alive", false)) else Color(0.55, 0.55, 0.55, 0.8)


static func _localized_class_name(slot_vm: Dictionary) -> String:
	if slot_vm.get("special_id") in ["devourer", "echo"]:
		return "噬元兽" if slot_vm["special_id"] == "devourer" else "回响"
	var class_id := str(slot_vm.get("class_id", ""))
	if CLASS_NAMES.has(class_id):
		return CLASS_NAMES[class_id]
	var authored_name := str(slot_vm.get("class_name", class_id))
	if authored_name == "默认":
		return "棋子"
	return CLASS_NAMES.get(
		authored_name.to_lower(), authored_name if not authored_name.is_empty() else "棋子"
	)
