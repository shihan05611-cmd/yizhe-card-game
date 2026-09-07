extends Resource

var id := 0
var name := ""
var exclusive_skill_id := ""
var color_index := 0
var deployed := false
var energy := 0
var max_energy := 0
var base_crit_rate := 0.0
var fist_momentum := 0
var source_portrait_path := ""
## Faithful Web-source snapshot only. Gameplay systems must not consume these
## removed player-action/loadout semantics as a future combat interface.
var legacy_source_metadata: Dictionary = {}


func _init(
	definition_id: int,
	display_name: String,
	exclusive_skill: String,
	definition_color_index: int,
	definition_deployed: bool,
	definition_energy: int,
	definition_max_energy: int,
	definition_base_crit_rate: float,
	definition_fist_momentum: int,
	portrait_path: String,
	legacy_free_slots: Array[String],
	legacy_acted: bool,
) -> void:
	id = definition_id
	name = display_name
	exclusive_skill_id = exclusive_skill
	color_index = definition_color_index
	deployed = definition_deployed
	energy = definition_energy
	max_energy = definition_max_energy
	base_crit_rate = definition_base_crit_rate
	fist_momentum = definition_fist_momentum
	source_portrait_path = portrait_path
	legacy_source_metadata = {
		"freeSlots": legacy_free_slots.duplicate(),
		"acted": legacy_acted,
	}


func snapshot() -> Resource:
	return get_script().new(
		id,
		name,
		exclusive_skill_id,
		color_index,
		deployed,
		energy,
		max_energy,
		base_crit_rate,
		fist_momentum,
		source_portrait_path,
		legacy_source_metadata.get("freeSlots", []),
		legacy_source_metadata.get("acted", false),
	)


func to_source_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"exSkill": exclusive_skill_id,
		"freeSlots": legacy_source_metadata.get("freeSlots", []).duplicate(),
		"acted": legacy_source_metadata.get("acted", false),
		"colorIdx": color_index,
		"deployed": deployed,
		"energy": energy,
		"maxEnergy": max_energy,
		"baseCritRate": base_crit_rate,
		"fistMomentum": fist_momentum,
		"portraitSourcePath": source_portrait_path,
	}
