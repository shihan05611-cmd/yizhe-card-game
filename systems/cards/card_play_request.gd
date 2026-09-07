class_name CardPlayRequest
extends RefCounted

## Immutable player-card command. Expected card/source fields are optimistic
## identity guards for UI callers; the HandRuntime instance remains authoritative.

var instance_id := ""
var expected_card_id := ""
var expected_source_skill_id := ""
var owner_hero_id: Variant = null
var target: Variant = null


func _init(
	request_instance_id: String = "",
	request_expected_card_id: String = "",
	request_expected_source_skill_id: String = "",
	request_owner_hero_id: Variant = null,
	request_target: Variant = null,
) -> void:
	instance_id = request_instance_id
	expected_card_id = request_expected_card_id
	expected_source_skill_id = request_expected_source_skill_id
	owner_hero_id = request_owner_hero_id
	target = request_target


func snapshot() -> RefCounted:
	return get_script().new(
		instance_id,
		expected_card_id,
		expected_source_skill_id,
		owner_hero_id,
		target.duplicate(true) if target is Array or target is Dictionary else target,
	)


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"expected_card_id": expected_card_id,
		"expected_source_skill_id": expected_source_skill_id,
		"owner_hero_id": owner_hero_id,
		"target": target.duplicate(true) if target is Array or target is Dictionary else target,
	}
