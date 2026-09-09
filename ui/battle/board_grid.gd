class_name BattleBoardGrid
extends PanelContainer

## Slots 1–3 are the rules-authoritative front row.  The display is mirrored
## across the river while Slot1…Slot6 keep their stable VM/target identities.
@export var front_column_on_right := false

var _pending_team: Dictionary = {}

@onready var _grid: GridContainer = $Grid
@onready var _slots: Array[Node] = [
	%Slot1, %Slot2, %Slot3, %Slot4, %Slot5, %Slot6,
]


func _ready() -> void:
	resized.connect(_sync_backdrop_board_rect)
	_apply_formation_order()
	for index in _slots.size():
		_slots[index].set_anchor_slot(index + 1)
	if not _pending_team.is_empty():
		_apply(_pending_team)
	call_deferred("_sync_backdrop_board_rect")


func bind_team(team_vm: Dictionary) -> void:
	_pending_team = team_vm.duplicate(true)
	if is_node_ready():
		_apply(_pending_team)


func slot_nodes() -> Array[Node]:
	return _slots.duplicate()


func visual_slot_order() -> Array[int]:
	return [4, 1, 5, 2, 6, 3] if front_column_on_right else [1, 4, 2, 5, 3, 6]


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


func _apply_formation_order() -> void:
	# GridContainer places children row-major.  Reorder only the visual children:
	# ally [4,1]/[5,2]/[6,3], enemy [1,4]/[2,5]/[3,6].
	for visual_index in visual_slot_order().size():
		_grid.move_child(_slots[visual_slot_order()[visual_index] - 1], visual_index)


func _sync_backdrop_board_rect() -> void:
	# The backdrop is an art-only sibling.  Give it the combined arena bounds
	# after containers have resolved so its quiet geometry stays behind the 6v6 grid.
	var arena := get_parent() as Control
	if arena == null or arena.size.x <= 0.0 or arena.size.y <= 0.0:
		return
	var backdrop := get_node_or_null("../../../Background")
	if backdrop != null and backdrop.has_method("set_board_rect"):
		backdrop.call("set_board_rect", arena.get_global_rect())
