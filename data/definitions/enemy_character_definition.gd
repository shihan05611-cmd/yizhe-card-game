extends Resource

var id := 0
var name := ""
var exclusive_skill_id := ""
var skills: Array[String] = []
var energy := 0
var max_energy := 0
var base_crit_rate := 0.0


func _init(
	definition_id: int,
	display_name: String,
	exclusive_skill: String,
	definition_skills: Array[String],
	definition_energy: int,
	definition_max_energy: int,
	definition_base_crit_rate: float,
) -> void:
	id = definition_id
	name = display_name
	exclusive_skill_id = exclusive_skill
	skills = definition_skills.duplicate()
	energy = definition_energy
	max_energy = definition_max_energy
	base_crit_rate = definition_base_crit_rate


func snapshot() -> Resource:
	return get_script().new(id, name, exclusive_skill_id, skills, energy, max_energy, base_crit_rate)


func to_source_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"exSkill": exclusive_skill_id,
		"skills": skills.duplicate(),
		"energy": energy,
		"maxEnergy": max_energy,
		"baseCritRate": base_crit_rate,
	}
