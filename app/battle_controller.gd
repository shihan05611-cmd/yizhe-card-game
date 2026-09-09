class_name BattleController
extends RefCounted

const BootstrapScript = preload("res://app/battle_bootstrap.gd")
const PresentationStreamScript = preload("res://app/combat_presentation_stream.gd")
const BattleStateScript = preload("res://core/battle_state.gd")
const Result = preload("res://core/card_runtime_result.gd")
const RequestScript = preload("res://systems/cards/card_play_request.gd")
const HeroCardCatalog = preload("res://data/catalogs/hero_card_catalog.gd")
const BattleOutcomeScript = preload("res://systems/combat/battle_outcome.gd")

const SPEED_OPTIONS := [1.0, 2.0, 3.0, 4.0]

var _hand_manager: Node
var _runtime: Variant = null
var _relic_action_adapter: Variant = null
var _catalogs: Dictionary = {}
var _stream: Variant
var _initialized := false
var _battle_start_emitted := false
var _fatal: Variant = null
var _presentation_speed := 1.0
var _auto_battle := false
var _relic_views: Array[Dictionary] = []
var _vacant_ally_slots: Dictionary = {}


func _init(hand_manager: Node) -> void:
	_hand_manager = hand_manager
	_stream = PresentationStreamScript.new()


func start(config: Variant) -> RefCounted:
	if _initialized:
		return _failure(Result.INVALID_ARGUMENT, "battle controller is already initialized")
	_stream.begin_batch("battle_start")
	var errors: Array[String] = []
	var built: Dictionary = BootstrapScript.create(config, _stream, errors)
	if built.is_empty():
		return _failure(
			Result.INVALID_ARGUMENT,
			errors[0] if not errors.is_empty() else "battle bootstrap failed",
		)
	var started: Variant = _hand_manager.start_battle_session({
		"battle_runtime": built["runtime"],
		"battle_seed": built["battle_seed"],
		"deployed_hero_ids": built["deployed_hero_ids"],
		"free_skill_ids": built["free_skill_ids"],
		"exclusive_card_ids": built["exclusive_card_ids"],
	}, errors)
	if not started.ok:
		return started
	_runtime = built["runtime"]
	_relic_action_adapter = built["relic_action_adapter"]
	_catalogs = built["catalogs"]
	for relic_id: String in built.get("relic_ids", []):
		var relic: Variant = _catalogs["relics"][relic_id]
		_relic_views.append({"id": relic_id, "name": relic.name, "description": relic.description})
	var progress: Variant = built.get("run_progress")
	if progress != null:
		for entry: Dictionary in progress.formation_slots(errors):
			if not bool(entry.get("occupied", true)):
				_vacant_ally_slots[int(entry["slot"])] = true
	_initialized = true
	var battle_start: Dictionary = _runtime.component("ports").call_action(
		"emit_content_event",
		{"event_id": "battleStart", "payload": {"round": 1}},
		errors,
	)
	_battle_start_emitted = true
	if not battle_start["ok"]:
		var failure := _failure(Result.COMMITTED_FAILURE, battle_start["error"], {
			"fatal": true, "committed_prefix": true,
		})
		_finish_command(failure)
		return failure
	return Result.new(true, Result.OK, "", {"view_model": view_model()})


func is_initialized() -> bool:
	return _initialized


func view_model() -> Dictionary:
	if not _initialized:
		return {
			"initialized": false,
			"fatal": null if _fatal == null else _fatal.duplicate(true),
			"presentation": _presentation_view(),
		}
	var state_errors: Array[String] = []
	var state: Dictionary = BattleStateScript.snapshot(_runtime.component("state"), state_errors)
	assert(state_errors.is_empty())
	var session: Dictionary = _hand_manager.session_snapshot()
	var hand_state: Dictionary = session["hand"]
	var cards: Array[Dictionary] = []
	for instance_id: String in hand_state["piles"]["hand"]:
		cards.append(_card_view(instance_id))
	var hero_growth := _hero_growth_by_id()
	var hero_status_context := {
		"ally_puppet_martyr_active": bool(state.get("ally_puppet_martyr_active", false)),
		"flame_investment_used": bool(state.get("battle_growth_flags", {}).get("flame_investment_used", false)),
	}
	var ally_heroes := _hero_views_with_status(state["player_heroes"], true, hero_growth, hero_status_context)
	var enemy_heroes := _hero_views_with_status(state["enemy_heroes"], false, {}, {})
	var vm := {
		"initialized": true,
		"session": {
			"active": session["active"],
			"halted": session["halted"],
			"settled": session["settled"],
		},
		"battle": {
			"round": state["round"],
			"phase": state["phase"],
			"game_over": state["game_over"],
			"result": state["battle_result"],
		},
		"resources": {
			"sp": state["sp"],
			"sp_max": state["sp_max"],
		},
		"teams": {
			"ally": _team_view(state["allies"], state.get("side_buffs", {}).get("ally", [])),
			"enemy": _team_view(state["enemies"], state.get("side_buffs", {}).get("enemy", [])),
		},
		"heroes": {
			"ally": ally_heroes,
			"enemy": enemy_heroes,
		},
		"piles": {
			"draw": hand_state["piles"]["draw"].size(),
			"hand": hand_state["piles"]["hand"].size(),
			"discard": hand_state["piles"]["discard"].size(),
			"exhaust": hand_state["piles"]["exhaust"].size(),
		},
		"hand": cards,
		"relics": _relic_views.duplicate(true),
		"logs": _stream.logs(),
		"presentation": _presentation_view(),
		"fatal": null if _fatal == null else _fatal.duplicate(true),
	}
	return vm.duplicate(true)


func inspect_card(instance_id: String) -> RefCounted:
	if not _initialized:
		return _failure(Result.INVALID_ARGUMENT, "battle controller is not initialized")
	var instance: Variant = _hand_manager.card_instance_snapshot(instance_id)
	if instance == null:
		return _failure(Result.CARD_NOT_FOUND, "unknown card instance: %s" % instance_id)
	return _hand_manager.inspect_card(_request_for(instance))


func play_card(instance_id: String) -> RefCounted:
	var gate: Variant = _command_gate()
	if gate != null:
		return gate
	var instance: Variant = _hand_manager.card_instance_snapshot(instance_id)
	if instance == null:
		return _failure(Result.CARD_NOT_FOUND, "unknown card instance: %s" % instance_id)
	_stream.begin_batch("play_card")
	var result: Variant = _hand_manager.play_card(_request_for(instance))
	_finish_command(result)
	return result


func play_card_guarded(command: Variant) -> RefCounted:
	var gate: Variant = _command_gate()
	if gate != null:
		return gate
	if typeof(command) != TYPE_DICTIONARY:
		return _failure(Result.INVALID_ARGUMENT, "play-card command must be a Dictionary")
	var required := [
		"instance_id", "expected_card_id", "expected_source_skill_id", "owner_hero_id",
	]
	for key: String in required:
		if not command.has(key):
			return _failure(Result.INVALID_ARGUMENT, "play-card command is missing guard: %s" % key)
	var instance_id := str(command["instance_id"])
	var instance: Variant = _hand_manager.card_instance_snapshot(instance_id)
	if instance == null:
		return _failure(Result.CARD_NOT_FOUND, "unknown card instance: %s" % instance_id)
	var definition: Variant = instance.definition
	if str(command["expected_card_id"]) != definition.id:
		return _failure(Result.INVALID_ARGUMENT, "stale card_id guard for: %s" % instance_id)
	if str(command["expected_source_skill_id"]) != definition.source_skill_id:
		return _failure(Result.INVALID_ARGUMENT, "stale source_skill_id guard for: %s" % instance_id)
	if command["owner_hero_id"] != definition.owner_hero_id:
		return _failure(Result.INVALID_ARGUMENT, "stale owner_hero_id guard for: %s" % instance_id)
	return play_card(instance_id)


func end_player_turn() -> RefCounted:
	var gate: Variant = _command_gate()
	if gate != null:
		return gate
	_stream.begin_batch("end_player_turn")
	var result: Variant = _hand_manager.end_player_turn()
	_finish_command(result)
	return result


## Settles the currently active battle through BattleOutcome's normal external
## settlement contract. It intentionally does not mutate either combat team.
func force_victory() -> RefCounted:
	var gate: Variant = _command_gate()
	if gate != null:
		return gate
	var state: Dictionary = _runtime.component("state")
	if state["game_over"]:
		return _failure(Result.INVALID_ARGUMENT, "battle controller is already settled")
	_stream.begin_batch("force_victory")
	var forced: Dictionary = BattleOutcomeScript.force_win(
		state, _runtime.component("ports")
	)
	if not forced["ok"]:
		var failure := _failure(Result.COMMITTED_FAILURE, forced["error"], {
			"fatal": bool(state["game_over"]),
			"committed_prefix": bool(state["game_over"]),
		})
		_finish_command(failure)
		return failure
	state["phase"] = "settled"
	return Result.new(true, Result.OK, "", {
		"result": "win", "forced": true, "outcome": forced["value"].duplicate(true),
	})


func set_presentation_speed(value: float) -> RefCounted:
	if value not in SPEED_OPTIONS:
		return _failure(Result.INVALID_ARGUMENT, "presentation speed must be 1x, 2x, 3x, or 4x")
	_presentation_speed = value
	return Result.new(true, Result.OK, "", {"speed": value})


func set_auto_battle(enabled: bool) -> RefCounted:
	_auto_battle = enabled
	return Result.new(true, Result.OK, "", {"enabled": enabled})


func acknowledge_presentation_through(sequence: int) -> void:
	_stream.acknowledge_through(sequence)


func presentation_events() -> Array[Dictionary]:
	return _stream.all_events()


func settlement_snapshot() -> Dictionary:
	if not _initialized:
		return {}
	var state_errors: Array[String] = []
	var state: Dictionary = BattleStateScript.snapshot(_runtime.component("state"), state_errors)
	if not state_errors.is_empty():
		return {}
	return {
		"game_over": state["game_over"],
		"battle_result": state["battle_result"],
		"allies": state["allies"].duplicate(true),
	}


func _card_view(instance_id: String) -> Dictionary:
	var instance: Variant = _hand_manager.card_instance_snapshot(instance_id)
	var definition: Variant = instance.definition
	var display: Dictionary = _card_display(definition)
	var inspected: Variant = _hand_manager.inspect_card(_request_for(instance))
	var availability: Dictionary = inspected.details if inspected.ok else {
		"playable": false,
		"unavailable_code": inspected.code,
		"reason": inspected.message,
		"actual_cost": null,
	}
	return {
		"instance_id": instance.instance_id,
		"card_id": definition.id,
		"source_skill_id": definition.source_skill_id,
		"name": display["name"],
		"description": display["description"],
		"category": definition.card_category,
		"owner_hero_id": definition.owner_hero_id,
		"base_cost": definition.base_sp_cost,
		"effective_cost": instance.effective_sp_cost(),
		"actual_cost": availability.get("actual_cost"),
		"play_destination": definition.card_play_destination,
		"end_of_turn_destination": definition.card_end_of_turn_destination,
		"exhausts_on_success": definition.does_card_exhaust(),
		"playable": bool(availability.get("playable", false)),
		"unavailable_code": str(availability.get("unavailable_code", "")),
		"unavailable_reason": str(availability.get("reason", "")),
	}


func _card_display(definition: Variant) -> Dictionary:
	var extended_display := HeroCardCatalog.display(definition.id)
	if not extended_display.is_empty():
		return extended_display
	if definition.card_category == "free":
		var skill: Variant = _catalogs["skills"][definition.source_skill_id]
		return {"name": skill.name, "description": skill.tip}
	var group := "ultimate" if definition.card_category == "ultimate" else "exclusive"
	var ability: Variant = _catalogs["hero_abilities"][group][definition.source_skill_id]
	return {"name": ability.name, "description": ability.tip}


func _request_for(instance: Variant) -> RefCounted:
	return RequestScript.new(
		instance.instance_id,
		instance.definition.id,
		instance.source_skill_id,
	)


func _command_gate() -> Variant:
	if not _initialized:
		return _failure(Result.INVALID_ARGUMENT, "battle controller is not initialized")
	if _fatal != null:
		return _failure(Result.QUEUE_HALTED, "battle controller is in a fatal state", {
			"fatal": true, "committed_prefix": true,
		})
	return null


func _finish_command(result: Variant) -> void:
	if result.ok or not bool(result.details.get("fatal", false)):
		return
	_fatal = {
		"code": result.code,
		"message": result.message,
		"details": result.details.duplicate(true),
	}
	_stream.capture_fatal(result.code, result.message, result.details)


func _presentation_view() -> Dictionary:
	return {
		"speed": _presentation_speed,
		"auto_battle": _auto_battle,
		"pending_events": _stream.pending_events(),
	}


func _team_view(units: Array, side_buffs: Array = []) -> Dictionary:
	var slots: Array[Dictionary] = []
	var total_hp := 0.0
	var total_max_hp := 0.0
	for unit: Dictionary in units:
		var slot := int(unit["slot"])
		var ally := str(unit.get("side", "")) == "ally"
		if ally and (bool(unit["alive"]) or bool(unit.get("is_puppet", false))):
			_vacant_ally_slots.erase(slot)
		var occupied := not _vacant_ally_slots.has(slot) if ally else float(unit["max_hp"]) > 0.0
		var slot_view := unit.duplicate(true)
		slot_view["occupied"] = occupied
		slots.append(slot_view)
		if not occupied:
			continue
		total_hp += float(unit["hp"])
		total_max_hp += float(unit["max_hp"])
	slots.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["slot"]) < int(right["slot"])
	)
	return {
		"slots": slots,
		"side_buffs": side_buffs.duplicate(true),
		"current_hp": total_hp,
		"max_hp": total_max_hp,
		"health_percent": 0.0 if total_max_hp <= 0.0 else total_hp / total_max_hp,
	}


func _hero_views_with_status(
	heroes: Array,
	player_side: bool,
	growth_by_id: Dictionary,
	status_context: Dictionary,
) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for hero: Dictionary in heroes:
		if player_side and not hero["deployed"]:
			continue
		var value := hero.duplicate(true)
		value["side"] = "ally" if player_side else "enemy"
		value["energy_percent"] = float(hero["energy"]) / float(hero["max_energy"])
		value["permanent_growth"] = growth_by_id.get(int(hero.get("id", 0)), {}).duplicate(true)
		value["ally_puppet_martyr_active"] = bool(status_context.get("ally_puppet_martyr_active", false))
		value["flame_investment_used"] = bool(status_context.get("flame_investment_used", false))
		value["statuses"] = _hero_status_entries(value, _catalogs.get("buffs", {}))
		value["status_lines"] = _status_entry_lines(value["statuses"])
		values.append(value)
	return values


func _hero_growth_by_id() -> Dictionary:
	var result := {}
	var growth_port: Variant = _runtime.component("growth_port")
	if growth_port == null:
		return result
	var errors: Array[String] = []
	var entries: Array = growth_port.snapshot(errors)
	if not errors.is_empty():
		return result
	for entry: Dictionary in entries:
		var target: Dictionary = entry.get("target", {})
		if str(target.get("type", "")) != "hero":
			continue
		var hero_id := int(target.get("id", 0))
		if hero_id <= 0:
			continue
		if not result.has(hero_id):
			result[hero_id] = {}
		result[hero_id][str(entry.get("id", ""))] = int(entry.get("stacks", 0))
	return result


static func _hero_status_lines(hero: Dictionary) -> Array[String]:
	return _status_entry_lines(_hero_status_entries(hero))


static func _hero_status_entries(hero: Dictionary, buff_catalog: Dictionary = {}) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var hero_id := int(hero.get("id", 0))
	var is_fist_hero := hero_id == 6 or str(hero.get("ex_skill", "")) == "fist"
	var momentum := clampi(int(hero.get("fist_momentum", 0)), 0, 5)
	if is_fist_hero and momentum > 0:
		entries.append({"id":"fistMomentum", "name":"拳势", "stacks":momentum, "kind":"buff", "description":"战内拳势，上限5层；提升拳系伤害、暴击率及攻击目标数。"})
	var growth: Dictionary = hero.get("permanent_growth", {})
	var short_names := {"flamePractice":"炎华", "fistMastery":"拳意"}
	var fallback_descriptions := {"flamePractice":"本轮Run中的永久投资次数。", "fistMastery":"每层拳系伤害+5%；每5层使大招基础段数+1。"}
	for id: String in growth:
		var stacks := int(growth[id])
		if stacks <= 0:
			continue
		var definition: Variant = buff_catalog.get(id)
		var name: String = str(short_names.get(id, definition.name if definition != null else id))
		var description: String = definition.description if definition != null else str(fallback_descriptions.get(id, "永久成长效果。"))
		entries.append({"id":id, "name":name, "stacks":stacks, "kind":"permanent", "description":description})
	if hero_id == 5 and bool(hero.get("flame_investment_used", false)):
		entries.append({"id":"flameInvestmentUsed", "name":"引火已用", "stacks":1, "kind":"cooldown", "description":"本场已完成永久投资，下一场战斗恢复。"})
	if hero_id == 8 and str(hero.get("side", "")) == "ally" and bool(hero.get("ally_puppet_martyr_active", false)):
		entries.append({"id":"puppetMartyr", "name":"殉道", "stacks":1, "kind":"buff", "description":"本场已启用傀儡殉道。"})
	return entries


static func _status_entry_lines(entries: Array) -> Array[String]:
	var lines: Array[String] = []
	for entry: Dictionary in entries:
		lines.append(str(entry["name"]) + (" ×%d" % int(entry["stacks"]) if int(entry["stacks"]) > 1 else ""))
	return lines


static func _failure(code: String, message: String, details: Dictionary = {}) -> RefCounted:
	return Result.new(false, code, message, details)
