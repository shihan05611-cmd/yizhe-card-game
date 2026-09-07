class_name BattleBoardGrid
extends PanelContainer

var _pending_team: Dictionary = {}

@onready var _slots: Array[Node] = [
	%Slot1, %Slot2, %Slot3, %Slot4, %Slot5, %Slot6,
]


func _ready() -> void:
	for index in _slots.size():
		_slots[index].set_anchor_slot(index + 1)
	if not _pending_team.is_empty():
		_apply(_pending_team)


func bind_team(team_vm: Dictionary) -> void:
	_pending_team = team_vm.duplicate(true)
	if is_node_ready():
		_apply(_pending_team)


func slot_nodes() -> Array[Node]:
	return _slots.duplicate()


func slot_for_target(target: Dictionary) -> Variant:
	var raw_slot: Variant = target.get("slot")
	var slot := int(raw_slot) if raw_slot is int or raw_slot is float else 0
	if slot >= 1 and slot <= _slots.size():
		return _slots[slot - 1]
	if target.has("unit_id"):
		for slot_node: Node in _slots:
			if slot_node.unit_id() == target["unit_id"]:
				return slot_node
	return null


func _apply(team_vm: Dictionary) -> void:
	var by_slot := {}
	for slot_vm: Dictionary in team_vm.get("slots", []):
		by_slot[int(slot_vm.get("slot", 0))] = slot_vm
	for index in _slots.size():
		var anchor := index + 1
		if by_slot.has(anchor):
			_slots[index].bind_slot(by_slot[anchor])
		else:
			_slots[index].set_empty(anchor)
