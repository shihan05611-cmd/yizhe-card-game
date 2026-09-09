class_name BattleHeroEnergyPanel
extends PanelContainer

const HeroItemScene = preload("res://scenes/battle/hero_energy_item.tscn")

@export var side_title := "弈者"

@onready var title_label: Label = %TitleLabel
@onready var item_container: VBoxContainer = %Items

var _items: Array[Node] = []
var _pending: Array = []


func _ready() -> void:
	title_label.text = side_title
	if not _pending.is_empty():
		_apply(_pending)


func bind_heroes(hero_vms: Array) -> void:
	_pending = hero_vms.duplicate(true)
	if is_node_ready():
		_apply(_pending)


func item_nodes() -> Array[Node]:
	return _items.duplicate()


func active_item_count() -> int:
	var count := 0
	for item: Node in _items:
		if item.visible:
			count += 1
	return count


func item_for_hero(hero_id: Variant) -> Variant:
	for item: Node in _items:
		if item.visible and item.hero_id() == hero_id:
			return item
	return null


func _apply(hero_vms: Array) -> void:
	while _items.size() < hero_vms.size():
		var item := HeroItemScene.instantiate()
		item_container.add_child(item)
		_items.append(item)
	for index in _items.size():
		var active := index < hero_vms.size()
		_items[index].visible = active
		if active:
			_items[index].set_compact(hero_vms.size() > 1)
			_items[index].bind_hero(hero_vms[index])
