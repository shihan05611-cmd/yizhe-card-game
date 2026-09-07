extends Resource

var id := ""
var name := ""
var hp := 0
var attack := 0
var block_bonus := 0.0
var crit_bonus := 0.0
var tip := ""


func _init(
	definition_id: String,
	display_name: String,
	definition_hp: int,
	definition_attack: int,
	definition_block_bonus: float,
	definition_crit_bonus: float,
	definition_tip: String,
) -> void:
	id = definition_id
	name = display_name
	hp = definition_hp
	attack = definition_attack
	block_bonus = definition_block_bonus
	crit_bonus = definition_crit_bonus
	tip = definition_tip


func snapshot() -> Resource:
	return get_script().new(id, name, hp, attack, block_bonus, crit_bonus, tip)


func to_source_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"hp": hp,
		"atk": attack,
		"blockBonus": block_bonus,
		"critBonus": crit_bonus,
		"tip": tip,
	}
