class_name RoundResolver
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const EnemySkillAdapterScript = preload("res://systems/enemy_ai/enemy_skill_adapter.gd")
const PieceAttackScript = preload("res://systems/combat/piece_attack.gd")
const BurnSettlementScript = preload("res://systems/buffs/burn.gd")
const BattleOutcomeScript = preload("res://systems/combat/battle_outcome.gd")
const FateSystemScript = preload("res://systems/combat/fate_system.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const PermanentBuffStoreScript = preload("res://systems/buffs/permanent_buff_store.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")
const HookDispatcherScript = preload("res://systems/relics/hook_dispatcher.gd")
const PieceClassDefinition = preload("res://data/definitions/piece_class_definition.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")

const REQUEST_KEYS := [
	"state", "registry", "burn_settlement", "permanent_buffs",
	"relic_system", "hook_dispatcher",
]
const ENTRY_KEYS := ["phase", "side", "slot", "status", "result"]
const START_PHASES := ["player_input", "resolution"]
const M3_SESSION_RESPONSIBILITIES := [
	{"id": "discard_hand_before_resolution", "status": "battle_card_session"},
	{"id": "preserve_resolution_generated_cards", "status": "battle_card_session"},
	{"id": "draw_next_player_turn_after_finalize", "status": "battle_card_session"},
]


static func resolve(request: Variant, ports: Variant) -> Dictionary:
	var prepared := _preflight(request, ports)
	if not prepared["ok"]:
		return prepared
	var config: Dictionary = prepared["value"]
	var state: Dictionary = request["state"]
	var round_before: int = state["round"]
	var trace: Array[Dictionary] = []
	if state["game_over"]:
		return CombatPortsScript.ok(_round_result(
			"already_settled", state, round_before, trace
		))

	state["phase"] = "enemy_yizhe"
	trace.append(_entry("enemy_yizhe", "enemy", null, "entered", {}))
	for hero: Dictionary in state["enemy_heroes"]:
		var hero_result: Dictionary = EnemySkillAdapterScript.resolve_hero_phase(
			state, hero, request["registry"], ports
		)
		if not hero_result["ok"]:
			return _failure("enemy hero %s failed: %s" % [str(hero["id"]), hero_result["error"]], state, trace)
		trace.append(_entry(
			"enemy_yizhe", "enemy", null, hero_result["value"]["status"],
			_enemy_summary(hero_result["value"]),
		))
		var outcome := _outcome(state, ports, trace, "enemy_yizhe", "enemy", null)
		if not outcome["ok"]:
			return outcome
		if state["game_over"]:
			break

	if not state["game_over"]:
		for slot in range(1, 7):
			state["phase"] = "ally_piece"
			var ally: Variant = _unit_at_slot(state["allies"], slot)
			if ally == null or not ally["alive"]:
				trace.append(_entry("ally_piece", "ally", slot, "skipped_dead", {}))
			else:
				var ally_attack := PieceAttackScript.execute(
					_piece_request(request, state, ally), ports
				)
				if not ally_attack["ok"]:
					return _failure("ally piece slot %d failed: %s" % [slot, ally_attack["error"]], state, trace)
				trace.append(_entry(
					"ally_piece", "ally", slot, ally_attack["value"]["reason"],
					_attack_summary(ally_attack["value"]),
				))
				var outcome := _outcome(state, ports, trace, "ally_piece", "ally", slot)
				if not outcome["ok"]:
					return outcome
				if state["game_over"]:
					break

			state["phase"] = "enemy_piece"
			var enemy: Variant = _unit_at_slot(state["enemies"], slot)
			if enemy == null or not enemy["alive"]:
				trace.append(_entry("enemy_piece", "enemy", slot, "skipped_dead", {}))
			else:
				var enemy_attack := PieceAttackScript.execute(
					_piece_request(request, state, enemy), ports
				)
				if not enemy_attack["ok"]:
					return _failure("enemy piece slot %d failed: %s" % [slot, enemy_attack["error"]], state, trace)
				trace.append(_entry(
					"enemy_piece", "enemy", slot, enemy_attack["value"]["reason"],
					_attack_summary(enemy_attack["value"]),
				))
				var outcome := _outcome(state, ports, trace, "enemy_piece", "enemy", slot)
				if not outcome["ok"]:
					return outcome
				if state["game_over"]:
					break

	# Web intentionally enters burn even if an earlier outcome settled the battle.
	state["phase"] = "burn"
	for side: String in ["enemy", "ally"]:
		var burn_errors: Array[String] = []
		var units: Array = state["enemies" if side == "enemy" else "allies"]
		var burn_results: Array[Dictionary] = request["burn_settlement"].settle(
			units, true, burn_errors
		)
		if not burn_errors.is_empty():
			trace.append(_entry(
				"burn", side, null, "failed", {"settled_prefix": _burn_summary(burn_results)}
			))
			return _failure("%s burn failed: %s" % [side, burn_errors[0]], state, trace)
		trace.append(_entry(
			"burn", side, null, "settled", {"units": _burn_summary(burn_results)}
		))
		var outcome := _outcome(state, ports, trace, "burn", side, null)
		if not outcome["ok"]:
			return outcome

	state["phase"] = "finalize"
	if state["game_over"]:
		state["phase"] = "settled"
		trace.append(_entry("finalize", null, null, "terminal", {
			"battle_result": state["battle_result"],
		}))
		return CombatPortsScript.ok(_round_result("settled", state, round_before, trace))

	var round_end: Dictionary = ports.call_action("emit_content_event", {
		"event_id": "roundEnd", "payload": {"round": state["round"]},
	})
	if not round_end["ok"]:
		return _failure("roundEnd event failed before round increment: %s" % round_end["error"], state, trace)
	trace.append(_entry("finalize", null, null, "round_end", {"round": state["round"]}))

	state["round"] += 1
	state["fate"]["skill_sp_gain_this_round"] = 0
	state["enemy_fate"]["skill_sp_gain_this_round"] = 0
	var recover: float = config["round_recover"]
	state["sp"] = minf(float(state["sp_max"]), float(state["sp"]) + recover)
	state["enemy_sp"] = minf(float(state["enemy_sp_max"]), float(state["enemy_sp"]) + recover)
	trace.append(_entry("finalize", null, null, "round_resources", {
		"round": state["round"], "sp": state["sp"], "enemy_sp": state["enemy_sp"],
	}))

	var had_stealth: Array[Dictionary] = []
	var all_units: Array = []
	all_units.append_array(state["allies"])
	all_units.append_array(state["enemies"])
	for unit: Dictionary in all_units:
		if config["buffs"].has_unit(unit, "stealth"):
			had_stealth.append(unit)
	var decay_errors: Array[String] = []
	var expired: Array[Dictionary] = config["buffs"].decay_round(all_units, decay_errors)
	if not decay_errors.is_empty():
		return _failure("round Buff decay failed after resources committed: %s" % decay_errors[0], state, trace)
	var cleared_ready: Array = []
	for unit: Dictionary in had_stealth:
		if not config["buffs"].has_unit(unit, "stealth"):
			unit["stealth_attack_ready"] = false
			cleared_ready.append(unit["id"])
	trace.append(_entry("finalize", null, null, "buff_decay", {
		"expired_count": expired.size(), "stealth_ready_cleared_ids": cleared_ready,
	}))

	_decay_all_in(state["fate"], "enemy_lock")
	_decay_all_in(state["enemy_fate"], "ally_lock")
	trace.append(_entry("finalize", null, null, "all_in_decay", {
		"ally_turns": state["fate"]["all_in_turns"],
		"enemy_turns": state["enemy_fate"]["all_in_turns"],
	}))

	for side: String in ["ally", "enemy"]:
		var fate_errors: Array[String] = []
		var fate_result: Dictionary = FateSystemScript.roll(
			state, side, config["tuning"], config["combat_rng"],
			config["buffs"], fate_errors,
		)
		if not fate_errors.is_empty() or fate_result.is_empty():
			var detail := fate_errors[0] if not fate_errors.is_empty() else "empty Fate result"
			return _failure("%s Fate roll failed after round commit: %s" % [side, detail], state, trace)
		trace.append(_entry("finalize", side, null, "fate", _fate_summary(fate_result)))

	request["hook_dispatcher"].reset_round()
	trace.append(_entry("finalize", null, null, "hook_reset", {}))
	var round_start: Dictionary = ports.call_action("emit_content_event", {
		"event_id": "roundStart", "payload": {"round": state["round"]},
	})
	if not round_start["ok"]:
		return _failure("roundStart event failed after round/finalize committed: %s" % round_start["error"], state, trace)
	trace.append(_entry("finalize", null, null, "round_start", {"round": state["round"]}))
	state["phase"] = "player_input"
	return CombatPortsScript.ok(_round_result("completed", state, round_before, trace))


static func _preflight(request: Variant, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _closed_dictionary(request, REQUEST_KEYS):
		return CombatPortsScript.fail("round request must have a canonical closed shape")
	if not _exact_valid(ports, CombatPortsScript):
		return CombatPortsScript.fail("round resolver requires exact valid CombatPorts")
	if not BattleStateScript.validate(request["state"], errors):
		return CombatPortsScript.fail("round state is non-canonical: %s" % errors[0])
	var state: Dictionary = request["state"]
	if not state["game_over"] and state["phase"] not in START_PHASES:
		return CombatPortsScript.fail("round phase gate rejects %s" % state["phase"])
	if typeof(request["registry"]) != TYPE_OBJECT or request["registry"] == null or request["registry"].get_script() != EffectRegistryScript:
		return CombatPortsScript.fail("registry must be an exact EffectRegistry")
	if not _exact_valid(request["burn_settlement"], BurnSettlementScript):
		return CombatPortsScript.fail("burn_settlement must be exact valid BurnSettlement")
	if request["burn_settlement"].is_active():
		return CombatPortsScript.fail("burn_settlement must be inactive before round resolution")
	if not _exact_valid(request["relic_system"], RelicSystemScript):
		return CombatPortsScript.fail("relic_system must be exact valid RelicSystem")
	if not _exact_valid(request["hook_dispatcher"], HookDispatcherScript):
		return CombatPortsScript.fail("hook_dispatcher must be exact valid HookDispatcher")
	if typeof(request["permanent_buffs"]) != TYPE_ARRAY:
		return CombatPortsScript.fail("permanent_buffs must be an Array snapshot")

	var buffs: Variant = ports.service("buffs", errors)
	var tuning: Variant = ports.service("tuning", errors)
	var catalogs: Variant = ports.service("catalogs", errors)
	var combat_rng: Variant = ports.service("combat_rng", errors)
	var policy_relics: Variant = ports.service("relics", errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("round services unavailable: %s" % errors[0])
	if not _exact_valid(policy_relics, RelicSystemScript):
		return CombatPortsScript.fail("ports relics must be an exact valid RelicSystem")
	if not is_same(policy_relics, request["relic_system"]):
		return CombatPortsScript.fail("ports relics and request.relic_system must be the same instance")
	if not _exact_valid(buffs, BuffSystemScript):
		return CombatPortsScript.fail("round buffs must be exact valid BuffSystem")
	if typeof(catalogs) != TYPE_DICTIONARY or typeof(catalogs.get("buffs")) != TYPE_DICTIONARY or typeof(catalogs.get("piece_classes")) != TYPE_DICTIONARY:
		return CombatPortsScript.fail("round catalogs require buffs and piece_classes authorities")
	if not buffs.validate_side_state(errors):
		return CombatPortsScript.fail("round side Buff state invalid: %s" % errors[0])
	for unit: Dictionary in state["allies"] + state["enemies"]:
		if not buffs.validate_unit_holder(unit, errors):
			return CombatPortsScript.fail("round unit Buff holder invalid: %s" % errors[0])
		if unit["class_id"] != "puppet":
			var definition: Variant = catalogs["piece_classes"].get(unit["class_id"])
			if not definition is Resource or definition.get_script() != PieceClassDefinition:
				return CombatPortsScript.fail("round unit class_id is absent from M1 authority")
	if buffs.definition_for("stealth", "unit", errors) == null:
		return CombatPortsScript.fail("round stealth Buff authority invalid: %s" % errors[0])
	if not FateSystemScript.preflight(state, "ally", buffs, errors):
		return CombatPortsScript.fail("ally Fate preflight failed: %s" % errors[0])
	if not FateSystemScript.preflight(state, "enemy", buffs, errors):
		return CombatPortsScript.fail("enemy Fate preflight failed: %s" % errors[0])

	var hero_ids: Array = []
	for hero: Dictionary in state["player_heroes"] + state["enemy_heroes"]:
		hero_ids.append(hero["id"])
	PermanentBuffStoreScript.normalize_instances(
		request["permanent_buffs"], catalogs["buffs"], hero_ids, errors
	)
	if not errors.is_empty():
		return CombatPortsScript.fail("round permanent Buff snapshot invalid: %s" % errors[0])
	var recover := _tuning_number(tuning, "roundRecover", errors)
	if not errors.is_empty() or recover < 0.0:
		return CombatPortsScript.fail("roundRecover must be non-negative and finite")
	return CombatPortsScript.ok({
		"buffs": buffs, "tuning": tuning, "combat_rng": combat_rng,
		"round_recover": recover,
	})


static func _piece_request(wrapper: Dictionary, state: Dictionary, attacker: Dictionary) -> Dictionary:
	var effect_errors: Array[String] = []
	var effect := ContextsScript.create_effect_context({
		"source_type": "basic_attack", "source_id": "normalAttack",
		"source_name": "普攻", "source_side": attacker["side"],
		"source_actor_id": attacker["id"], "counts_as_skill_cast": false,
		"spent_skill_points": false, "free_cast": false,
		"counts_as_basic_attack": true, "counts_as_attack": true,
		"triggers_enemy_kill_effects": true,
	}, effect_errors)
	if not effect_errors.is_empty():
		return {}
	return {
		"state": state, "attacker_side": attacker["side"],
		"attacker_id": attacker["id"], "attacker_slot": attacker["slot"],
		"forced_target_side": null, "forced_target_id": null, "forced_target_slot": null,
		"attack_name": "普攻", "damage_multiplier": 1.0,
		"trigger_extra_action": true, "trigger_pursuit": true,
		"trigger_banner_action": true, "damage_kind_override": "",
		"source_effect": effect, "permanent_buffs": wrapper["permanent_buffs"],
		"relic_system": wrapper["relic_system"],
	}


static func _outcome(
	state: Dictionary, ports: Variant, trace: Array[Dictionary],
	phase: String, side: Variant, slot: Variant,
) -> Dictionary:
	var checked: Dictionary = BattleOutcomeScript.check(state, ports)
	if not checked["ok"]:
		return _failure("battle outcome failed: %s" % checked["error"], state, trace)
	trace.append(_entry(phase, side, slot, "outcome", {
		"status": checked["value"]["status"], "result": checked["value"]["result"],
		"committed": checked["value"]["committed"],
	}))
	return CombatPortsScript.ok(null)


static func _round_result(
	status: String, state: Dictionary, round_before: int, trace: Array[Dictionary]
) -> Dictionary:
	return {
		"status": status, "result": state["battle_result"],
		"round_before": round_before, "round_after": state["round"],
		"phase": state["phase"], "trace": trace.duplicate(true),
		# Compatibility field retained for M2 consumers. The obsolete action-quota
		# and pending-ultimate placeholders are replaced by the real owner and
		# responsibilities used by BattleCardSession.
		"m3_obligations": M3_SESSION_RESPONSIBILITIES.duplicate(true),
	}


static func _entry(
	phase: String, side: Variant, slot: Variant, status: String, result: Dictionary
) -> Dictionary:
	var values := {
		"phase": phase, "side": side, "slot": slot,
		"status": status, "result": result.duplicate(true),
	}
	var closed := {}
	for key: String in ENTRY_KEYS:
		closed[key] = values[key]
	return closed


static func _enemy_summary(value: Dictionary) -> Dictionary:
	return {
		"hero_id": value["hero_id"], "skill_kind": value["skill_kind"],
		"skill_id": value["skill_id"], "actual_sp_cost": value["actual_sp_cost"],
		"pre_ultimate": value["pre_ultimate"], "post_ultimate": value["post_ultimate"],
		"ultimate_casts": value["ultimate_casts"],
		"enemy_sp_before": value["enemy_sp_before"], "enemy_sp_after": value["enemy_sp_after"],
		"energy_before": value["energy_before"], "energy_after": value["energy_after"],
	}


static func _attack_summary(value: Dictionary) -> Dictionary:
	return {
		"primary_died": value["primary_died"], "total_dealt": value["total_dealt"],
		"primary_target_id": value["primary_target_id"], "strikes": value["strikes"],
		"pursuit_count": value["pursuit_count"], "steps": value["steps"].duplicate(),
	}


static func _burn_summary(results: Array[Dictionary]) -> Array:
	var summary: Array = []
	for result: Dictionary in results:
		summary.append({
			"unit_id": result["unit"]["id"], "dealt": result["damage"]["dealt"],
			"died": result["damage"]["died"], "stacks_before": result["stacks_before"],
			"stacks_after": result["stacks_after"], "expired_stacks": result["expired_stacks"],
		})
	return summary


static func _fate_summary(result: Dictionary) -> Dictionary:
	return {
		"applied": result["applied"], "side": result["side"], "mode": result["mode"],
		"all_in": result["all_in"], "next_roll_index": result["next_roll_index"],
		"used_rng": result["used_rng"],
		"pursuit_target_ids": result["pursuit_target_ids"].duplicate(),
	}


static func _decay_all_in(fate: Dictionary, lock_field: String) -> void:
	if fate["all_in_turns"] <= 0:
		return
	fate["all_in_turns"] -= 1
	if fate["all_in_turns"] <= 0:
		fate[lock_field] = null


static func _failure(message: String, state: Dictionary, trace: Array[Dictionary]) -> Dictionary:
	return CombatPortsScript.fail(
		"%s (current_phase=%s; committed_trace=%s)" % [message, state["phase"], str(trace)]
	)


static func _unit_at_slot(team: Array, slot: int) -> Variant:
	for unit: Dictionary in team:
		if unit["slot"] == slot:
			return unit
	return null


static func _exact_valid(value: Variant, script: Script) -> bool:
	return (
		typeof(value) == TYPE_OBJECT and value != null
		and value.get_script() == script and value.has_method("is_valid")
		and value.is_valid() == true
	)


static func _closed_dictionary(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			return false
	return true


static func _tuning_number(tuning: Variant, id: String, errors: Array[String]) -> float:
	if typeof(tuning) != TYPE_DICTIONARY:
		errors.append("tuning must be a Dictionary")
		return 0.0
	var definition: Variant = tuning.get(id)
	if not definition is Resource or definition.get_script() != TuningValueDefinition:
		errors.append("tuning.%s must be a TuningValueDefinition" % id)
		return 0.0
	var value: Variant = definition.value
	if typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value)):
		return float(value)
	errors.append("tuning.%s.value must be finite" % id)
	return 0.0
