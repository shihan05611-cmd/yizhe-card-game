extends Resource

var id := ""
var name := ""
var scope: Variant = null
var is_debuff := false
var stackable := false
var max_stacks := 0
var default_duration := 0
var uses_layer_durations := false
var decays_at_round_end := false
var description := ""
var persistence := "battle"
var target_types: Array[String] = []


func _init(
	definition_id: String,
	display_name: String,
	definition_scope: Variant,
	definition_is_debuff: bool,
	definition_stackable: bool,
	definition_max_stacks: int,
	definition_default_duration: int,
	definition_uses_layer_durations: bool,
	definition_decays_at_round_end: bool,
	definition_description: String,
	definition_persistence: String = "battle",
	definition_target_types: Array[String] = [],
) -> void:
	id = definition_id
	name = display_name
	scope = definition_scope
	is_debuff = definition_is_debuff
	stackable = definition_stackable
	max_stacks = definition_max_stacks
	default_duration = definition_default_duration
	uses_layer_durations = definition_uses_layer_durations
	decays_at_round_end = definition_decays_at_round_end
	description = definition_description
	persistence = definition_persistence
	target_types = definition_target_types.duplicate()


func snapshot() -> Resource:
	return get_script().new(
		id,
		name,
		scope,
		is_debuff,
		stackable,
		max_stacks,
		default_duration,
		uses_layer_durations,
		decays_at_round_end,
		description,
		persistence,
		target_types,
	)


func to_source_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"scope": scope,
		"isDebuff": is_debuff,
		"stackable": stackable,
		"maxStacks": max_stacks,
		"defaultDuration": default_duration,
		"usesLayerDurations": uses_layer_durations,
		"decaysAtRoundEnd": decays_at_round_end,
		"description": description,
		"persistence": persistence,
		"targetTypes": target_types.duplicate(),
	}
