class_name BattleHeroEnergyItem
extends PanelContainer

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
@onready var placeholder: Panel = %PortraitPlaceholder
@onready var placeholder_label: Label = %PlaceholderLabel
@onready var name_label: Label = %NameLabel
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var energy_label: Label = %EnergyLabel

var _pending: Dictionary = {}


func _ready() -> void:
	if not _pending.is_empty():
		_apply(_pending)


func bind_hero(hero_vm: Dictionary) -> void:
	_pending = hero_vm.duplicate(true)
	if is_node_ready():
		_apply(_pending)


func hero_id() -> Variant:
	return _pending.get("id")


func _apply(hero_vm: Dictionary) -> void:
	var id: Variant = hero_vm.get("id", 0)
	name_label.text = str(hero_vm.get("name", "未知弈者"))
	var energy := float(hero_vm.get("energy", 0.0))
	var max_energy := maxf(1.0, float(hero_vm.get("max_energy", 1.0)))
	energy_bar.max_value = max_energy
	energy_bar.value = energy
	energy_label.text = "%d / %d" % [roundi(energy), roundi(max_energy)]
	var path := str(PORTRAITS.get(id, ""))
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
	portrait.texture = texture
	portrait.visible = texture != null
	placeholder.visible = texture == null
	name_label.visible = texture != null
	placeholder_label.text = str(hero_vm.get("name", "?"))
