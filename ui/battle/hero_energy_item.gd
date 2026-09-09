class_name BattleHeroEnergyItem
extends PanelContainer

const StatusTagScene = preload("res://scenes/battle/hero_status_tag.tscn")

const PORTRAITS := {
	1: "res://assets/portraits/chiyan_lihui_transparent_v2.png",
	3: "res://assets/portraits/yuanshuai_lihui.png",
	4: "res://assets/portraits/qishi_lihui_transparent.png",
	5: "res://assets/portraits/yanshushi_lihui_transparent_v2.png",
	6: "res://assets/portraits/ningbufan_lihui_transparent_v2.png",
	7: "res://assets/portraits/chenge_lihui_transparent.png",
	8: "res://assets/portraits/qianji_lihui.png",
	9: "res://assets/portraits/yingshou_lihui_transparent_v2.png",
}

@onready var portrait: TextureRect = %Portrait
@onready var enemy_portrait: Control = %EnemyPortrait
@onready var energy_ring: Control = %EnergyRing
@onready var placeholder: Panel = %PortraitPlaceholder
@onready var placeholder_label: Label = %PlaceholderLabel
@onready var portrait_halo: Control = %PortraitHalo
@onready var name_label: Label = %NameLabel
@onready var role_label: Label = %RoleLabel
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var energy_label: Label = %EnergyLabel
@onready var status_label: Label = %StatusLabel
@onready var status_flow: HFlowContainer = %StatusFlow

var _pending: Dictionary = {}
var _compact := false


func _ready() -> void:
	if not _pending.is_empty():
		_apply(_pending)


func bind_hero(hero_vm: Dictionary) -> void:
	_pending = hero_vm.duplicate(true)
	if is_node_ready():
		_apply(_pending)


func set_compact(compact: bool) -> void:
	_compact = compact
	if is_node_ready():
		_apply_layout()


func hero_id() -> Variant:
	return _pending.get("id")


func _apply(hero_vm: Dictionary) -> void:
	var id: Variant = hero_vm.get("id", 0)
	var side := str(hero_vm.get("side", ""))
	portrait_halo.visible = false
	enemy_portrait.visible = side == "enemy"
	if side == "enemy":
		enemy_portrait.bind_hero(hero_vm)
	name_label.text = str(hero_vm.get("name", "未知弈者"))
	role_label.text = "敌方弈者" if side == "enemy" else ("被动专属" if int(id) == 4 else "主动专属")
	var energy := float(hero_vm.get("energy", 0.0))
	var max_energy := maxf(1.0, float(hero_vm.get("max_energy", 1.0)))
	$Row/PortraitFrame.mouse_filter = Control.MOUSE_FILTER_PASS
	$Row/PortraitFrame.tooltip_text = "能量：%d / %d" % [roundi(energy), roundi(max_energy)]
	energy_bar.max_value = max_energy
	energy_bar.value = energy
	energy_label.text = "%d / %d" % [roundi(energy), roundi(max_energy)]
	energy_bar.visible = false
	energy_label.visible = false
	role_label.visible = false
	energy_ring.set_energy(energy, max_energy, side == "enemy")
	var status_lines: Array = hero_vm.get("status_lines", [])
	var statuses: Array = []
	if hero_vm.has("statuses"):
		statuses = hero_vm["statuses"].duplicate(true)
	else:
		for line: String in status_lines:
			statuses.append({"id": line, "name": line, "stacks": 1, "description": _status_tooltip(hero_vm, [line]), "kind": "legacy"})
	_apply_statuses(statuses)
	var path := str(PORTRAITS.get(id, ""))
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
	portrait.texture = texture
	portrait.visible = side != "enemy" and texture != null
	placeholder.visible = side != "enemy" and texture == null
	name_label.visible = side == "enemy" or texture != null
	placeholder_label.text = str(hero_vm.get("name", "?"))
	_apply_layout()


func _apply_layout() -> void:
	var portrait_frame := $Row/PortraitFrame as Control
	var info := $Row/Info as Control
	var has_status := status_flow.visible and not status_flow.get_children().is_empty()
	custom_minimum_size.y = 190.0 if not _compact else (92.0 if has_status else 76.0)
	if not _compact:
		portrait_frame.set_anchors_preset(Control.PRESET_CENTER)
		portrait_frame.offset_left = -60.0
		portrait_frame.offset_top = -87.0
		portrait_frame.offset_right = 60.0
		portrait_frame.offset_bottom = 33.0
		info.anchor_left = 0.0
		info.anchor_top = 0.5
		info.anchor_right = 1.0
		info.anchor_bottom = 0.5
		info.offset_left = 10.0
		info.offset_top = 41.0
		info.offset_right = -10.0
		info.offset_bottom = 87.0
		role_label.visible = false
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		return
	portrait_frame.anchor_left = 0.0
	portrait_frame.anchor_top = 0.5
	portrait_frame.anchor_right = 0.0
	portrait_frame.anchor_bottom = 0.5
	portrait_frame.offset_left = 8.0
	portrait_frame.offset_top = -38.0
	portrait_frame.offset_right = 84.0
	portrait_frame.offset_bottom = 38.0
	info.set_anchors_preset(Control.PRESET_FULL_RECT)
	info.offset_left = 92.0
	info.offset_top = 10.0
	info.offset_right = -8.0
	info.offset_bottom = -10.0
	role_label.visible = false
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_flow.alignment = FlowContainer.ALIGNMENT_BEGIN


func _apply_statuses(statuses: Array) -> void:
	for child: Node in status_flow.get_children():
		status_flow.remove_child(child)
		child.queue_free()
	for status: Dictionary in statuses:
		if int(status.get("stacks", 1)) <= 0:
			continue
		var label := StatusTagScene.instantiate() as Label
		label.text = str(status.get("name", status.get("id", "")))
		var stacks := int(status.get("stacks", 1))
		if stacks > 1:
			label.text += " ×%d" % stacks
		label.tooltip_text = str(status.get("description", label.text))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.38, 1))
		status_flow.add_child(label)
	status_flow.visible = status_flow.get_child_count() > 0
	status_flow.custom_minimum_size.y = 0.0
	status_label.visible = false


func _status_tooltip(hero_vm: Dictionary, status_lines: Array) -> String:
	if status_lines.is_empty():
		return ""
	var details: Array[String] = []
	for line: String in status_lines:
		if line.begins_with("拳势"):
			details.append("拳势：当前 %s（上限 5）" % line.trim_prefix("拳势 "))
		elif line.begins_with("拳意"):
			details.append("拳意：Run 永久成长 %s" % line.trim_prefix("拳意 "))
		elif line.begins_with("炎华"):
			if line == "炎华 本场已用":
				details.append("炎华：本场永久投资已使用")
			else:
				details.append("炎华：Run 永久投资次数（%s）" % line.trim_prefix("炎华 "))
		elif line.begins_with("殉道"):
			details.append("殉道：千机本场已启用傀儡殉道")
		else:
			details.append(line)
	return "自身状态\n" + "\n".join(details)
