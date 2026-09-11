class_name RunCardIdentity
extends RefCounted

## Stable, Run-scoped identities for individual card copies. Acquisitions append;
## selling a free-skill copy removes its key and shifts later free indices with it.

const CardCatalogScript = preload("res://data/catalogs/card_catalog.gd")
const HeroCardCatalogScript = preload("res://data/catalogs/hero_card_catalog.gd")


static func enumerate_candidates(
	run_state: Variant,
	catalogs: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	errors.clear()
	if not _basic_shape(run_state, catalogs, errors):
		return []
	var card_catalog: Dictionary = CardCatalogScript.build(
		catalogs["skills"], catalogs["hero_abilities"]
	)
	if card_catalog.is_empty():
		errors.append("Run card identity requires the player card catalog")
		return []
	var retained: Dictionary = _key_set(run_state["retained_card_keys"])
	var result: Array[Dictionary] = []
	var ordinals := {}
	for index in run_state["free_skill_ids"].size():
		var skill_id: String = str(run_state["free_skill_ids"][index])
		var card_id := "free:%s" % skill_id
		var skill: Variant = catalogs["skills"].get(skill_id)
		var card: Variant = card_catalog.get(card_id)
		if skill == null or card == null:
			errors.append("Run card identity references unknown free skill copy %d" % index)
			return []
		var key := "free:%d" % index
		var ordinal := _next_ordinal(ordinals, card_id)
		result.append(_candidate(
			key, card_id, skill.name, skill.tip, int(card.base_sp_cost),
			"free", 0, index, ordinal, retained.has(key),
		))

	var hero_entries: Array[Dictionary] = []
	for raw_owner_id: String in run_state["hero_deployment_slots"]:
		hero_entries.append({
			"owner_id": int(raw_owner_id),
			"slot": int(run_state["hero_deployment_slots"][raw_owner_id]),
		})
	hero_entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left["slot"] < right["slot"]
	)
	for entry: Dictionary in hero_entries:
		var owner_id: int = entry["owner_id"]
		var player: Variant = catalogs["characters"]["players"].get(owner_id)
		if player == null:
			errors.append("Run card identity references unknown hero %d" % owner_id)
			return []
		var ability: Variant = catalogs["hero_abilities"]["exclusive"].get(player.exclusive_skill_id)
		if ability == null or ability.is_passive:
			continue
		var card_id := "exclusive:%s" % ability.id
		var card: Variant = card_catalog.get(card_id)
		if card == null:
			errors.append("Run card identity cannot find hero %d exclusive card" % owner_id)
			return []
		var key := "hero:%d" % owner_id
		var ordinal := _next_ordinal(ordinals, card_id)
		result.append(_candidate(
			key, card_id, ability.name, ability.tip, int(card.base_sp_cost),
			"hero", owner_id, null, ordinal, retained.has(key),
		))

	for index in run_state["exclusive_card_ids"].size():
		var card_id: String = str(run_state["exclusive_card_ids"][index])
		var card: Variant = card_catalog.get(card_id)
		if card == null or str(card.card_category) != "exclusive":
			errors.append("Run card identity references unknown extra exclusive copy %d" % index)
			return []
		var details := _exclusive_details(card, catalogs)
		if details.is_empty():
			errors.append("Run card identity cannot display extra exclusive copy %d" % index)
			return []
		var key := "exclusive:%d" % index
		var ordinal := _next_ordinal(ordinals, card_id)
		result.append(_candidate(
			key, card_id, details["name"], details["description"], int(card.base_sp_cost),
			"exclusive", int(card.owner_hero_id), index, ordinal, retained.has(key),
		))
	return result


static func unretained_candidates(
	run_state: Variant,
	catalogs: Variant,
	errors: Array[String] = [],
) -> Array[Dictionary]:
	var all := enumerate_candidates(run_state, catalogs, errors)
	if not errors.is_empty():
		return []
	return all.filter(func(candidate: Dictionary) -> bool: return not candidate["retained"])


static func retained_keys_for_battle(
	run_state: Variant,
	deployed_hero_ids: Array,
	catalogs: Variant,
	errors: Array[String] = [],
) -> Array[String]:
	var candidates := enumerate_candidates(run_state, catalogs, errors)
	if not errors.is_empty():
		return []
	var candidate_by_key := {}
	for candidate: Dictionary in candidates:
		candidate_by_key[candidate["key"]] = candidate
	var retained: Array = run_state["retained_card_keys"]
	for key: String in retained:
		if not candidate_by_key.has(key):
			errors.append("Run retained card key no longer identifies an owned copy: %s" % key)
			return []
	var result: Array[String] = []
	for index in run_state["free_skill_ids"].size():
		var key := "free:%d" % index
		if key in retained:
			result.append(key)
	for owner_id: Variant in deployed_hero_ids:
		var key := "hero:%d" % int(owner_id)
		if key in retained:
			result.append(key)
	var launch_index := 0
	for inventory_index in run_state["exclusive_card_ids"].size():
		var candidate: Dictionary = candidate_by_key["exclusive:%d" % inventory_index]
		if candidate["owner_hero_id"] not in deployed_hero_ids:
			continue
		if candidate["key"] in retained:
			result.append("exclusive:%d" % launch_index)
		launch_index += 1
	return result


static func after_free_copy_removed(keys: Array, removed_index: int) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in keys:
		var key := str(raw_key)
		if not key.begins_with("free:"):
			result.append(key)
			continue
		var index := int(key.trim_prefix("free:"))
		if index == removed_index:
			continue
		result.append("free:%d" % (index - 1 if index > removed_index else index))
	return result


static func _candidate(
	key: String,
	card_id: String,
	name: String,
	description: String,
	base_cost: int,
	kind: String,
	owner_hero_id: int,
	inventory_index: Variant,
	copy_ordinal: int,
	retained: bool,
) -> Dictionary:
	return {
		"id": key,
		"key": key,
		"card_id": card_id,
		"name": name,
		"description": description,
		"base_cost": base_cost,
		"kind": kind,
		"owner_hero_id": owner_hero_id,
		"inventory_index": inventory_index,
		"copy_ordinal": copy_ordinal,
		"retained": retained,
	}


static func _exclusive_details(card: Variant, catalogs: Dictionary) -> Dictionary:
	var ability: Variant = catalogs["hero_abilities"]["exclusive"].get(card.source_skill_id)
	if ability != null and not ability.is_passive:
		return {"name": ability.name, "description": ability.tip}
	var display: Variant = HeroCardCatalogScript.display(card.id)
	return display.duplicate(true) if typeof(display) == TYPE_DICTIONARY else {}


static func _next_ordinal(ordinals: Dictionary, card_id: String) -> int:
	var next := int(ordinals.get(card_id, 0)) + 1
	ordinals[card_id] = next
	return next


static func _key_set(keys: Array) -> Dictionary:
	var result := {}
	for key: String in keys:
		result[key] = true
	return result


static func _basic_shape(run_state: Variant, catalogs: Variant, errors: Array[String]) -> bool:
	if typeof(run_state) != TYPE_DICTIONARY:
		errors.append("Run card identity requires a Run Dictionary")
		return false
	for field: String in [
		"free_skill_ids", "exclusive_card_ids", "hero_deployment_slots", "retained_card_keys",
	]:
		if not run_state.has(field):
			errors.append("Run card identity is missing %s" % field)
			return false
	if (
		typeof(run_state["free_skill_ids"]) != TYPE_ARRAY
		or typeof(run_state["exclusive_card_ids"]) != TYPE_ARRAY
		or typeof(run_state["hero_deployment_slots"]) != TYPE_DICTIONARY
		or typeof(run_state["retained_card_keys"]) != TYPE_ARRAY
	):
		errors.append("Run card identity inventory fields are invalid")
		return false
	if (
		typeof(catalogs) != TYPE_DICTIONARY
		or typeof(catalogs.get("skills")) != TYPE_DICTIONARY
		or typeof(catalogs.get("hero_abilities")) != TYPE_DICTIONARY
		or typeof(catalogs.get("characters")) != TYPE_DICTIONARY
		or typeof(catalogs["characters"].get("players")) != TYPE_DICTIONARY
	):
		errors.append("Run card identity catalog groups are missing")
		return false
	return true
