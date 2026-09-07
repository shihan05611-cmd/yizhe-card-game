class_name CharacterCatalog
extends RefCounted

const Validation = preload("res://data/catalog_validation.gd")
const PlayerCharacter = preload("res://data/definitions/player_character_definition.gd")
const EnemyCharacter = preload("res://data/definitions/enemy_character_definition.gd")

const PLAYER := "players"
const ENEMY := "enemies"


static func build() -> Dictionary:
	var errors: Array[String] = []
	return build_from(_player_source_definitions(), _enemy_source_definitions(), errors)


static func avatar_colors() -> Array:
	return [
		["#ff7d6b", "#ffb26b"],
		["#6bc6ff", "#6be0c7"],
		["#9f7bff", "#ff7be9"],
		["#5ee07a", "#7ed0ff"],
		["#ffc66b", "#ff8b8b"],
	]


static func build_from(
	player_definitions: Array,
	enemy_definitions: Array,
	errors: Array[String],
) -> Dictionary:
	errors.clear()
	_validate_players(player_definitions, errors)
	_validate_enemies(enemy_definitions, errors)
	if not errors.is_empty():
		return {}

	var players := {}
	for raw_definition in player_definitions:
		var definition: Variant = raw_definition
		players[definition.id] = definition.snapshot()
	var enemies := {}
	for raw_definition in enemy_definitions:
		var definition: Variant = raw_definition
		enemies[definition.id] = definition.snapshot()
	return {
		PLAYER: players,
		ENEMY: enemies,
	}


static func _validate_players(definitions: Array, errors: Array[String]) -> void:
	var seen := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != PlayerCharacter:
			errors.append("player character entries must be PlayerCharacterDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.positive_int_id(definition.id, "player character", errors):
			Validation.unique_id(definition.id, seen, "player character", errors)
		Validation.non_empty_string(definition.name, "player character name", errors)
		Validation.non_empty_id(definition.exclusive_skill_id, "exclusive skill", errors)
		Validation.non_negative_int(definition.color_index, "player character colorIdx", errors)
		Validation.non_negative_int(definition.energy, "player character energy", errors)
		Validation.positive_int(definition.max_energy, "player character maxEnergy", errors)
		Validation.non_negative_int(definition.fist_momentum, "player character fistMomentum", errors)
		_validate_crit(definition.base_crit_rate, "player character baseCritRate", errors)
		_validate_legacy_metadata(definition.legacy_source_metadata, errors)


static func _validate_enemies(definitions: Array, errors: Array[String]) -> void:
	var seen := {}
	for raw_definition in definitions:
		if not raw_definition is Resource or raw_definition.get_script() != EnemyCharacter:
			errors.append("enemy character entries must be EnemyCharacterDefinition resources")
			continue
		var definition: Variant = raw_definition
		if Validation.positive_int_id(definition.id, "enemy character", errors):
			Validation.unique_id(definition.id, seen, "enemy character", errors)
		Validation.non_empty_string(definition.name, "enemy character name", errors)
		Validation.non_empty_id(definition.exclusive_skill_id, "enemy exclusive skill", errors)
		Validation.string_array(definition.skills, "enemy character skills", errors, false)
		Validation.non_negative_int(definition.energy, "enemy character energy", errors)
		Validation.positive_int(definition.max_energy, "enemy character maxEnergy", errors)
		_validate_crit(definition.base_crit_rate, "enemy character baseCritRate", errors)


static func _validate_crit(value: Variant, field_name: String, errors: Array[String]) -> void:
	if not Validation.non_negative_number(value, field_name, errors):
		return
	if value > 1.0:
		errors.append("%s must not exceed 1" % field_name)


static func _validate_legacy_metadata(metadata: Dictionary, errors: Array[String]) -> void:
	if not metadata.has("freeSlots") or not metadata.has("acted"):
		errors.append("player legacy/source-only metadata must contain freeSlots and acted")
		return
	var free_slots: Variant = metadata["freeSlots"]
	if typeof(free_slots) != TYPE_ARRAY:
		errors.append("player legacy/source-only freeSlots must be an array")
	else:
		Validation.string_array(free_slots, "player legacy/source-only freeSlots", errors)
	if typeof(metadata["acted"]) != TYPE_BOOL:
		errors.append("player legacy/source-only acted must be a bool")
	for key in metadata:
		if key not in ["freeSlots", "acted"]:
			errors.append("unknown player legacy/source-only metadata field: %s" % str(key))


static func _player_source_definitions() -> Array:
	return [
		PlayerCharacter.new(1, "赤焰", "burn01", 0, true, 0, 100, 0.05, 0, "assets/portraits/chiyan_lihui_transparent_v2.png", ["burnStackBase", "smallHeal"], false),
		PlayerCharacter.new(2, "命轮", "fate", 1, false, 0, 120, 0.05, 0, "", ["pieceAction", "pieceBlock"], false),
		PlayerCharacter.new(3, "元帅", "ascend", 2, false, 0, 100, 0.05, 0, "assets/portraits/yuanshuai_lihui.png", ["pieceDamageUp", "pieceAction"], false),
		PlayerCharacter.new(4, "骑士", "counterAura", 3, true, 0, 100, 0.05, 0, "assets/portraits/qishi_lihui_transparent.png", ["pieceBlock", "markBurn"], false),
		PlayerCharacter.new(5, "炎术士", "burnEnchant", 4, true, 0, 100, 0.05, 0, "assets/portraits/yanshushi_lihui_transparent_v2.png", ["smallHeal", "burnDetonate"], false),
		PlayerCharacter.new(6, "宁不凡", "fist", 0, false, 0, 100, 0.05, 0, "assets/portraits/ningbufan_lihui_transparent_v2.png", ["pieceAction", "smallHeal"], false),
		PlayerCharacter.new(7, "沉戈", "siege", 2, false, 0, 100, 0.05, 0, "assets/portraits/chenge_lihui_transparent.png", ["pieceHealAll", "smallHeal"], false),
		PlayerCharacter.new(8, "千机", "puppet", 1, false, 0, 120, 0.05, 0, "assets/portraits/qianji_lihui.png", ["pieceBlock", "executeStrike"], false),
		PlayerCharacter.new(9, "影狩", "shadow", 2, false, 0, 100, 0.05, 0, "assets/portraits/yingshou_lihui_transparent_v2.png", ["pieceAction", "pieceDamageUp"], false),
	]


static func _enemy_source_definitions() -> Array:
	return [
		EnemyCharacter.new(1, "敌弈者-灼痕", "burn01", ["基础叠层", "灼烧引爆"], 0, 100, 0.05),
		EnemyCharacter.new(2, "敌弈者-裂隙", "fate", ["棋子格挡", "棋子增伤"], 0, 120, 0.05),
		EnemyCharacter.new(3, "敌弈者-军械", "counterAura", ["棋子行动", "棋子格挡"], 0, 100, 0.05),
	]
