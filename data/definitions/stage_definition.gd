extends Resource

var id := ""
var name := ""
var archetype := ""
var description := ""
var enemy_yizhes: Array[Dictionary] = []


func _init(
	definition_id: String = "",
	display_name: String = "",
	definition_archetype: String = "",
	definition_description: String = "",
	definition_enemy_yizhes: Array[Dictionary] = [],
) -> void:
	id = definition_id
	name = display_name
	archetype = definition_archetype
	description = definition_description
	enemy_yizhes = definition_enemy_yizhes.duplicate(true)


func snapshot() -> Resource:
	return get_script().new(id, name, archetype, description, enemy_yizhes)


func to_source_dict() -> Dictionary:
	var source_enemies: Array[Dictionary] = []
	for enemy in enemy_yizhes:
		source_enemies.append({
			"id": enemy.get("id"),
			"name": enemy.get("name"),
			"exSkill": enemy.get("exclusive_skill_id"),
			"skills": enemy.get("source_skill_names", []).duplicate(),
			"skillPool": enemy.get("free_skill_ids", []).duplicate(),
			"maxEnergy": enemy.get("source_max_energy"),
			"baseCritRate": enemy.get("base_crit_rate"),
		})
	return {
		"id": id,
		"name": name,
		"archetype": archetype,
		"description": description,
		"enemyYizhes": source_enemies,
	}
