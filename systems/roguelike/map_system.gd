class_name RoguelikeMapSystem
extends RefCounted

## Pure M5 map and encounter calculations. This module neither selects Run
## nodes nor starts battles; callers inject the M1 catalog and M5 Run RNG.

const NODE_TYPES := ["battle", "elite", "boss", "forge", "shop", "event"]
const BATTLE_NODE_TYPES := ["battle", "elite", "boss"]
const BASE_SCALE_ANCHORS := [
	{"chapter": 1, "column": 0, "hp": 0.35, "atk": 0.3},
	{"chapter": 1, "column": 3, "hp": 0.7, "atk": 0.5},
	{"chapter": 2, "column": 0, "hp": 1.0, "atk": 0.8},
	{"chapter": 3, "column": 0, "hp": 1.0, "atk": 0.8},
]
const HP_PROGRESS_PER_COLUMN := 0.05
const ENCOUNTER_BUDGET_TYPE_FACTORS := {
	"battle": {"hp": 1.0, "atk": 1.0},
	"elite": {"hp": 1.3, "atk": 0.6},
	"boss": {"hp": 1.8, "atk": 0.3},
}


static func build_chapter_map(
	catalog: Variant,
	chapter: Variant,
	rng: Variant,
	errors: Array[String] = [],
) -> Array:
	errors.clear()
	if not _require_catalog(catalog, false, errors) or not _require_rng(rng, errors):
		return []
	if typeof(chapter) != TYPE_INT or not catalog["chapters"].has(chapter):
		errors.append("unknown roguelike chapter: %s" % str(chapter))
		return []
	var template := _definition_data(catalog["chapters"][chapter], "chapter %s" % str(chapter), errors)
	if template.is_empty() or not _validate_chapter_template(template, chapter, errors):
		return []
	var nodes: Array = []
	for rule: Variant in template["columnRules"]:
		for row in range(int(template["rows"])):
			var column: int = rule["column"]
			var node_type: Variant
			if rule["fixedByRow"] != null:
				node_type = rule["fixedByRow"][row]
			else:
				node_type = _resolve_weighted_type(rule, rng, errors)
				if node_type == null:
					return []
			var next_ids: Array[String] = []
			if column < int(template["columns"]) - 1:
				for next_row in [row - 1, row, row + 1]:
					if next_row >= 0 and next_row < int(template["rows"]):
						next_ids.append(_node_id(chapter, next_row, column + 1))
			nodes.append({
				"id": _node_id(chapter, row, column),
				"chapter": chapter,
				"row": row,
				"column": column,
				"type": node_type,
				"available": column == 0,
				"completed": false,
				"next_node_ids": next_ids,
			})
	nodes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return (
			left["column"] < right["column"]
			or (left["column"] == right["column"] and left["row"] < right["row"])
		)
	)
	if not _validate_built_graph(nodes, chapter, int(template["rows"]), int(template["columns"]), errors):
		return []
	return _deep_copy(nodes)


static func get_encounter_budget(node: Variant, errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _require_node(node, errors):
		return {}
	var base: Dictionary = BASE_SCALE_ANCHORS[0]
	for anchor: Dictionary in BASE_SCALE_ANCHORS:
		if anchor["chapter"] < node["chapter"] or (
			anchor["chapter"] == node["chapter"] and anchor["column"] <= node["column"]
		):
			base = anchor
	var factors: Dictionary = ENCOUNTER_BUDGET_TYPE_FACTORS.get(
		node["type"], ENCOUNTER_BUDGET_TYPE_FACTORS["battle"]
	)
	return {
		"lineup_hp_scale": float(base["hp"]) * (1.0 + int(node["column"]) * HP_PROGRESS_PER_COLUMN) * float(factors["hp"]),
		"lineup_atk_scale": float(base["atk"]) * float(factors["atk"]),
	}


static func get_node_scales(node: Variant, errors: Array[String] = []) -> Dictionary:
	var budget := get_encounter_budget(node, errors)
	if budget.is_empty():
		return {}
	return {"hp": budget["lineup_hp_scale"], "atk": budget["lineup_atk_scale"]}


static func resolve_encounter(
	catalog: Variant,
	node: Variant,
	rng: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _require_catalog(catalog, true, errors) or not _require_rng(rng, errors):
		return {}
	if not _require_node(node, errors):
		return {}
	if node["type"] not in BATTLE_NODE_TYPES:
		errors.append("node %s is not a battle node" % str(node.get("id", "<unknown>")))
		return {}
	if not catalog["chapters"].has(node["chapter"]):
		errors.append("missing chapter %d" % int(node["chapter"]))
		return {}
	var chapter := _definition_data(
		catalog["chapters"][node["chapter"]], "chapter %d" % int(node["chapter"]), errors
	)
	if chapter.is_empty():
		return {}
	var encounter_ids: Variant
	match node["type"]:
		"boss": encounter_ids = [chapter.get("bossEncounterId")]
		"elite": encounter_ids = chapter.get("eliteEncounterIds")
		_: encounter_ids = chapter.get("battleEncounterIds")
	if typeof(encounter_ids) != TYPE_ARRAY or encounter_ids.is_empty():
		errors.append("chapter %d has no encounter ids for %s" % [node["chapter"], node["type"]])
		return {}
	var encounter_id: Variant = encounter_ids[0] if encounter_ids.size() == 1 else rng.pick(encounter_ids)
	if typeof(encounter_id) != TYPE_STRING or not catalog["encounters"].has(encounter_id):
		errors.append("node %s references missing encounter %s" % [str(node.get("id", "<unknown>")), str(encounter_id)])
		return {}
	var encounter := _definition_data(
		catalog["encounters"][encounter_id], "encounter %s" % encounter_id, errors
	)
	if encounter.is_empty() or not _validate_encounter_template(encounter, encounter_id, errors):
		return {}
	var scales := get_node_scales(node, errors)
	if scales.is_empty():
		return {}
	var authored_by_id := {}
	for slot: Dictionary in encounter["slots"]:
		authored_by_id[slot["unitId"]] = slot
	var slots: Array = []
	for index in range(6):
		var unit_id := index + 1
		var authored: Dictionary = authored_by_id.get(unit_id, {
			"unitId": unit_id,
			"pieceClassId": null,
			"specialId": null,
			"className": "",
			"hpScale": 1.0,
			"atkScale": 1.0,
			"empty": false,
		})
		var special: Variant = null
		if authored["specialId"] != null:
			if not catalog["enemy_specials"].has(authored["specialId"]):
				errors.append("encounter %s references missing special %s" % [encounter_id, authored["specialId"]])
				return {}
			special = catalog["enemy_specials"][authored["specialId"]]
		var piece_class: Variant = null
		if authored["pieceClassId"] != null:
			if not catalog["piece_classes"].has(authored["pieceClassId"]):
				errors.append("encounter %s references missing piece class %s" % [encounter_id, authored["pieceClassId"]])
				return {}
			piece_class = catalog["piece_classes"][authored["pieceClassId"]]
		var special_hp := float(special.get("hpScale", 1.0)) if special != null else 1.0
		var special_atk := float(special.get("atkScale", 1.0)) if special != null else 1.0
		var display_name: String = authored["className"]
		if display_name.is_empty() and special != null:
			display_name = str(special.get("name", ""))
		if display_name.is_empty() and piece_class != null:
			display_name = str(piece_class.get("name", ""))
		if display_name.is_empty():
			display_name = "敌兵"
		slots.append({
			"unit_id": unit_id,
			"piece_class_id": authored["pieceClassId"],
			"special_id": authored["specialId"],
			"class_name": display_name,
			"hp_scale": float(authored["hpScale"]),
			"atk_scale": float(authored["atkScale"]),
			"special_hp_scale": special_hp,
			"special_atk_scale": special_atk,
			"total_hp_scale": 0.0,
			"total_atk_scale": 0.0,
			"empty": authored["empty"],
		})
	var active: Array = slots.filter(func(slot: Dictionary) -> bool: return not slot["empty"])
	if active.is_empty():
		errors.append("encounter %s must keep at least one active enemy slot" % encounter_id)
		return {}
	var hp_weight_total := 0.0
	var atk_weight_total := 0.0
	for slot: Dictionary in active:
		hp_weight_total += slot["hp_scale"] * slot["special_hp_scale"]
		atk_weight_total += slot["atk_scale"] * slot["special_atk_scale"]
	if hp_weight_total <= 0.0 or atk_weight_total <= 0.0:
		errors.append("encounter %s active slot weights must be positive" % encounter_id)
		return {}
	for slot: Dictionary in active:
		slot["total_hp_scale"] = scales["hp"] * (
			6.0 * slot["hp_scale"] * slot["special_hp_scale"] / hp_weight_total
		)
		slot["total_atk_scale"] = scales["atk"] * (
			6.0 * slot["atk_scale"] * slot["special_atk_scale"] / atk_weight_total
		)
	return {
		"id": encounter["id"],
		"name": encounter["name"],
		"hp_scale": scales["hp"],
		"atk_scale": scales["atk"],
		"slots": _deep_copy(slots),
	}


static func _resolve_weighted_type(rule: Dictionary, rng: Variant, errors: Array[String]) -> Variant:
	var total := 0
	for item: Variant in rule["pool"]:
		if typeof(item) != TYPE_DICTIONARY or item.get("type") not in NODE_TYPES or typeof(item.get("weight")) != TYPE_INT or item["weight"] <= 0:
			errors.append("column %s contains an invalid weighted node pool" % str(rule.get("column")))
			return null
		total += int(item["weight"])
	var roll: Variant = rng.int_range(1, total)
	if typeof(roll) != TYPE_INT:
		errors.append("column %s weighted node pool could not draw from RNG" % str(rule.get("column")))
		return null
	for item: Dictionary in rule["pool"]:
		roll -= item["weight"]
		if roll <= 0:
			return item["type"]
	errors.append("column %s weighted node pool could not resolve" % str(rule.get("column")))
	return null


static func _validate_chapter_template(
	template: Dictionary,
	chapter: int,
	errors: Array[String],
) -> bool:
	for key in ["chapter", "rows", "columns", "columnRules"]:
		if not template.has(key):
			errors.append("chapter %d is missing %s" % [chapter, key])
			return false
	if template["chapter"] != chapter or template["rows"] != 3 or template["columns"] != 10:
		errors.append("chapter %d must declare its id and a 3x10 map" % chapter)
		return false
	if typeof(template["columnRules"]) != TYPE_ARRAY or template["columnRules"].size() != 10:
		errors.append("chapter %d must contain exactly ten column rules" % chapter)
		return false
	var columns := {}
	for raw_rule: Variant in template["columnRules"]:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			errors.append("chapter %d column rule must be a Dictionary" % chapter)
			return false
		for key in ["column", "fixedByRow", "pool"]:
			if not raw_rule.has(key):
				errors.append("chapter %d column rule is missing %s" % [chapter, key])
				return false
		var column: Variant = raw_rule.get("column")
		if typeof(column) != TYPE_INT or column < 0 or column > 9 or columns.has(column):
			errors.append("chapter %d has an invalid or duplicate column rule" % chapter)
			return false
		columns[column] = true
		var fixed: Variant = raw_rule.get("fixedByRow")
		var pool: Variant = raw_rule.get("pool")
		if fixed != null:
			if typeof(fixed) != TYPE_ARRAY or fixed.size() != 3:
				errors.append("chapter %d column %d fixed rows must contain three types" % [chapter, column])
				return false
			for node_type: Variant in fixed:
				if node_type not in NODE_TYPES:
					errors.append("chapter %d column %d contains an invalid node type" % [chapter, column])
					return false
		elif typeof(pool) != TYPE_ARRAY or pool.is_empty():
			errors.append("chapter %d column %d requires fixed rows or a weighted pool" % [chapter, column])
			return false
	return true


static func _validate_encounter_template(
	encounter: Dictionary,
	encounter_id: String,
	errors: Array[String],
) -> bool:
	for key in ["id", "name", "hpScale", "atkScale", "slots"]:
		if not encounter.has(key):
			errors.append("encounter %s is missing %s" % [encounter_id, key])
			return false
	if encounter["id"] != encounter_id or typeof(encounter["name"]) != TYPE_STRING:
		errors.append("encounter %s has an invalid identity" % encounter_id)
		return false
	if not _positive_number(encounter["hpScale"]) or not _positive_number(encounter["atkScale"]):
		errors.append("encounter %s scales must be positive finite numbers" % encounter_id)
		return false
	if typeof(encounter["slots"]) != TYPE_ARRAY:
		errors.append("encounter %s slots must be an Array" % encounter_id)
		return false
	var seen := {}
	for raw_slot: Variant in encounter["slots"]:
		if typeof(raw_slot) != TYPE_DICTIONARY:
			errors.append("encounter %s slot must be a Dictionary" % encounter_id)
			return false
		for key in ["unitId", "pieceClassId", "specialId", "className", "hpScale", "atkScale", "empty"]:
			if not raw_slot.has(key):
				errors.append("encounter %s slot is missing %s" % [encounter_id, key])
				return false
		var unit_id: Variant = raw_slot["unitId"]
		if typeof(unit_id) != TYPE_INT or unit_id < 1 or unit_id > 6 or seen.has(unit_id):
			errors.append("encounter %s has an invalid or duplicate slot" % encounter_id)
			return false
		seen[unit_id] = true
		if not _positive_number(raw_slot["hpScale"]) or not _positive_number(raw_slot["atkScale"]):
			errors.append("encounter %s slot weights must be positive" % encounter_id)
			return false
		if typeof(raw_slot["className"]) != TYPE_STRING or typeof(raw_slot["empty"]) != TYPE_BOOL:
			errors.append("encounter %s slot presentation fields are invalid" % encounter_id)
			return false
		for id_key in ["pieceClassId", "specialId"]:
			if raw_slot[id_key] != null and typeof(raw_slot[id_key]) != TYPE_STRING:
				errors.append("encounter %s slot %s must be null or a string" % [encounter_id, id_key])
				return false
	return true


static func _validate_built_graph(
	nodes: Array,
	chapter: int,
	rows: int,
	columns: int,
	errors: Array[String],
) -> bool:
	if nodes.size() != rows * columns:
		errors.append("chapter %d map must contain exactly %d nodes" % [chapter, rows * columns])
		return false
	var by_id := {}
	for node: Dictionary in nodes:
		if by_id.has(node["id"]):
			errors.append("chapter %d map contains duplicate node %s" % [chapter, node["id"]])
			return false
		by_id[node["id"]] = node
	for node: Dictionary in nodes:
		var successors := {}
		for next_id: String in node["next_node_ids"]:
			if successors.has(next_id) or not by_id.has(next_id) or by_id[next_id]["column"] != node["column"] + 1:
				errors.append("map node %s has invalid successor %s" % [node["id"], next_id])
				return false
			successors[next_id] = true
	return true


static func _require_catalog(catalog: Variant, encounter_fields: bool, errors: Array[String]) -> bool:
	if typeof(catalog) != TYPE_DICTIONARY:
		errors.append("roguelike content catalog is required")
		return false
	var fields := ["chapters", "encounters"]
	if encounter_fields:
		fields.append_array(["piece_classes", "enemy_specials"])
	for field in fields:
		if typeof(catalog.get(field)) != TYPE_DICTIONARY:
			errors.append("roguelike content catalog.%s must be a Dictionary" % field)
			return false
	return true


static func _require_rng(rng: Variant, errors: Array[String]) -> bool:
	if typeof(rng) != TYPE_OBJECT or rng == null or not rng.has_method("int_range") or not rng.has_method("pick"):
		errors.append("roguelike map operations require an injected RNG")
		return false
	return true


static func _require_node(node: Variant, errors: Array[String]) -> bool:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("roguelike node is required")
		return false
	if typeof(node.get("chapter")) != TYPE_INT or node["chapter"] < 1 or node["chapter"] > 3:
		errors.append("node chapter must be from 1 to 3")
		return false
	if typeof(node.get("row")) != TYPE_INT or node["row"] < 0 or node["row"] > 2:
		errors.append("node row must be from 0 to 2")
		return false
	if typeof(node.get("column")) != TYPE_INT or node["column"] < 0 or node["column"] > 9:
		errors.append("node column must be from 0 to 9")
		return false
	if node.get("type") not in NODE_TYPES:
		errors.append("invalid roguelike node type: %s" % str(node.get("type")))
		return false
	return true


static func _definition_data(value: Variant, path: String, errors: Array[String]) -> Dictionary:
	if value is Resource:
		var metadata: Variant = value.get("metadata")
		if typeof(metadata) == TYPE_DICTIONARY:
			return metadata.duplicate(true)
	if typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	errors.append("%s must be an M1 roguelike content definition" % path)
	return {}


static func _node_id(chapter: int, row: int, column: int) -> String:
	return "c%d-r%d-n%d" % [chapter, row, column]


static func _positive_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and float(value) > 0.0
	)


static func _deep_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var copy: Array = []
		for item: Variant in value:
			copy.append(_deep_copy(item))
		return copy
	if typeof(value) == TYPE_DICTIONARY:
		var copy := {}
		for key: Variant in value:
			copy[_deep_copy(key)] = _deep_copy(value[key])
		return copy
	return value
