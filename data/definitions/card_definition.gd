class_name CardDefinition
extends Resource

const CATEGORY_FREE := "free"
const CATEGORY_EXCLUSIVE := "exclusive"
const CATEGORY_ULTIMATE := "ultimate"

const PILE_DRAW := "draw"
const PILE_HAND := "hand"
const PILE_DISCARD := "discard"
const PILE_EXHAUST := "exhaust"

const INSERT_TOP := "top"
const INSERT_BOTTOM := "bottom"
const INSERT_RANDOM := "random"

var id := ""
var source_skill_id := ""
var source_kind := ""
var card_category := ""
var base_sp_cost := 0
var owner_hero_id := 0
var card_play_destination := PILE_DISCARD
var card_end_of_turn_destination := PILE_DISCARD
var card_requires_target := false
var exhausts_on_success := false
var validator_id := ""
var effect_id := ""
var card_first_shuffle_priority := 0
var card_reshuffle_priority := 0
var card_shuffle_weighting := 1.0
var max_successful_plays_per_combat := 0


func _init(
	definition_id: String = "",
	definition_source_skill_id: String = "",
	definition_source_kind: String = "",
	definition_card_category: String = "",
	definition_base_sp_cost: int = 0,
	definition_owner_hero_id: int = 0,
	definition_play_destination: String = PILE_DISCARD,
	definition_end_of_turn_destination: String = PILE_DISCARD,
	definition_exhausts_on_success: bool = false,
	definition_validator_id: String = "",
	definition_effect_id: String = "",
	definition_requires_target: bool = false,
	definition_first_shuffle_priority: int = 0,
	definition_reshuffle_priority: int = 0,
	definition_shuffle_weight: float = 1.0,
	definition_max_successful_plays_per_combat: int = 0,
) -> void:
	id = definition_id
	source_skill_id = definition_source_skill_id
	source_kind = definition_source_kind
	card_category = definition_card_category
	base_sp_cost = definition_base_sp_cost
	owner_hero_id = definition_owner_hero_id
	card_play_destination = definition_play_destination
	card_end_of_turn_destination = definition_end_of_turn_destination
	exhausts_on_success = definition_exhausts_on_success
	validator_id = definition_validator_id
	effect_id = definition_effect_id
	card_requires_target = definition_requires_target
	card_first_shuffle_priority = definition_first_shuffle_priority
	card_reshuffle_priority = definition_reshuffle_priority
	card_shuffle_weighting = definition_shuffle_weight
	max_successful_plays_per_combat = definition_max_successful_plays_per_combat


func snapshot() -> Resource:
	return get_script().new(
		id,
		source_skill_id,
		source_kind,
		card_category,
		base_sp_cost,
		owner_hero_id,
		card_play_destination,
		card_end_of_turn_destination,
		exhausts_on_success,
		validator_id,
		effect_id,
		card_requires_target,
		card_first_shuffle_priority,
		card_reshuffle_priority,
		card_shuffle_weighting,
		max_successful_plays_per_combat,
	)


func does_card_exhaust() -> bool:
	return exhausts_on_success


func to_dict() -> Dictionary:
	return {
		"id": id,
		"source_skill_id": source_skill_id,
		"source_kind": source_kind,
		"card_category": card_category,
		"base_sp_cost": base_sp_cost,
		"owner_hero_id": owner_hero_id,
		"card_play_destination": card_play_destination,
		"card_end_of_turn_destination": card_end_of_turn_destination,
		"card_requires_target": card_requires_target,
		"exhausts_on_success": exhausts_on_success,
		"validator_id": validator_id,
		"effect_id": effect_id,
		"card_first_shuffle_priority": card_first_shuffle_priority,
		"card_reshuffle_priority": card_reshuffle_priority,
		"card_shuffle_weighting": card_shuffle_weighting,
		"max_successful_plays_per_combat": max_successful_plays_per_combat,
	}
