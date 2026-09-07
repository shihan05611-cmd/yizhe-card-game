class_name PieceAttack
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const PermanentBuffStoreScript = preload("res://systems/buffs/permanent_buff_store.gd")
const PieceReactionsScript = preload("res://systems/combat/piece_reactions.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")
const TargetingRulesScript = preload("res://systems/targeting/targeting_rules.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")
const PieceClassDefinition = preload("res://data/definitions/piece_class_definition.gd")

## M2 piece-attack orchestration. It owns target/hit loops and piece passives,
## while every post-hit reaction remains delegated to PieceReactions. The two
## plan consumers are pure one-shot boundaries: callers replace a pending plan
## with the returned completed_b4_execution envelope; no hidden pending state is
## introduced here.

const EXECUTE_KEYS := [
	"state", "attacker_side", "attacker_id", "attacker_slot",
	"forced_target_side", "forced_target_id", "forced_target_slot",
	"attack_name", "damage_multiplier", "trigger_extra_action",
	"trigger_pursuit", "trigger_banner_action", "damage_kind_override",
	"source_effect", "permanent_buffs", "relic_system",
]
const CONSUME_KEYS := ["state", "plan", "permanent_buffs", "relic_system"]
const PLAN_KEYS := [
	"kind", "attacker_side", "attacker_id", "attacker_slot", "target_side",
	"target_id", "target_slot", "attack_name", "damage_multiplier",
	"trigger_extra_action", "trigger_pursuit", "damage_kind_override", "source_effect",
]
const SEQUENCE_KEYS := [
	"kind", "status", "initial_target_side", "initial_target_id",
	"initial_target_slot", "retarget_on_target_death", "retarget_policy", "plans",
]
const EFFECT_KEYS := [
	"source_type", "source_id", "source_name", "source_side", "source_actor_id",
	"counts_as_skill_cast", "spent_skill_points", "free_cast",
	"counts_as_basic_attack", "counts_as_attack", "triggers_enemy_kill_effects",
]
const DAMAGE_RESULT_KEYS := [
	"dealt", "blocked", "died", "crit", "damage_context", "death_context",
]

const STEALTH_ID := "stealth"
const MARCH_ID := "march"
const PURSUIT_ID := "pursuit"
const BREAK_FORMATION_ID := "breakFormation"
const BREAK_MARKED_ID := "breakMarked"
const MAX_PURSUITS := 12


static func execute(request: Variant, ports: Variant) -> Dictionary:
	var prepared: Dictionary = _preflight_execute(request, ports)
	if not prepared["ok"]:
		return prepared
	return _commit_execute(request, ports, prepared["value"])


static func consume_plan(request: Variant, ports: Variant) -> Dictionary:
	var prepared := _preflight_consume(request, ports, false)
	if not prepared["ok"]:
		return prepared
	var plan: Dictionary = request["plan"]
	var execute_request := _request_from_plan(request, plan)
	var execution: Dictionary = execute(execute_request, ports)
	if not execution["ok"]:
		return CombatPortsScript.fail("piece plan execution failed (committed plan prefix: none): %s" % execution["error"])
	return CombatPortsScript.ok({
		"kind": "execute_piece_attack_result",
		"status": "completed_b4_execution",
		"source_plan_kind": "execute_piece_attack",
		"primary_died": execution["value"]["primary_died"],
		"attack_result": execution["value"],
	})


static func consume_sequence(request: Variant, ports: Variant) -> Dictionary:
	var prepared := _preflight_consume(request, ports, true)
	if not prepared["ok"]:
		return prepared
	var sequence: Dictionary = request["plan"]
	var results: Array = []
	var current_target: Variant = prepared["value"]["initial_target"]
	for index in sequence["plans"].size():
		var source_plan: Dictionary = sequence["plans"][index]
		if current_target == null or not current_target["alive"]:
			current_target = TargetingRulesScript.lowest_hp_percent_lockable(
				request["state"], source_plan["target_side"]
			)
		if current_target == null:
			results.append({"index": index, "status": "skipped_no_target"})
			continue
		var plan: Dictionary = source_plan.duplicate(true)
		plan["target_side"] = current_target["side"]
		plan["target_id"] = current_target["id"]
		plan["target_slot"] = current_target["slot"]
		var execution: Dictionary = execute(_request_from_plan(request, plan), ports)
		if not execution["ok"]:
			return CombatPortsScript.fail(
				"piece sequence execution failed (committed plan prefix: %d): %s"
				% [results.size(), execution["error"]]
			)
		results.append({
			"index": index, "status": "completed_b4_execution",
			"attacker_id": plan["attacker_id"], "target_id": current_target["id"],
			"attack_result": execution["value"],
		})
	return CombatPortsScript.ok({
		"kind": "execute_piece_attack_sequence_result",
		"status": "completed_b4_execution",
		"source_plan_kind": "execute_piece_attack_sequence",
		"plan_results": results,
	})


static func _commit_execute(request: Dictionary, ports: Variant, prepared: Dictionary) -> Dictionary:
	var state: Dictionary = request["state"]
	var attacker: Dictionary = prepared["attacker"]
	var buffs: Variant = prepared["buffs"]
	var steps: Array[String] = []

	if not attacker["alive"]:
		return CombatPortsScript.ok(_empty_result("dead", steps))
	if attacker["disarm_turns"] > 0:
		attacker["disarm_turns"] -= 1
		steps.append("disarm_consumed")
		return CombatPortsScript.ok(_empty_result("disarmed", steps))

	var target: Variant = prepared["forced_target"]
	if target == null or not target["alive"]:
		target = TargetingRulesScript.target_by_lane(
			state, attacker["side"], attacker["slot"]
		)
	var forced_active: bool = prepared["forced_target"] != null and prepared["forced_target"]["alive"]
	if (
		not forced_active
		and request["attack_name"] == "普攻"
		and attacker["stealth_attack_ready"]
	):
		var stealth_target: Variant = TargetingRulesScript.lowest_current_hp_alive(
			state, _other_side(attacker["side"])
		)
		if stealth_target != null:
			target = stealth_target
		attacker["stealth_attack_ready"] = false
		if buffs.has_unit(attacker, STEALTH_ID):
			var clear_errors: Array[String] = []
			if not buffs.clear_unit(attacker, STEALTH_ID, clear_errors):
				return _failure("stealth clear failed", steps, clear_errors)
		steps.append("stealth_consumed")
	if target == null:
		return CombatPortsScript.ok(_empty_result("no_target", steps))

	var hit_count := 1
	if request["trigger_extra_action"] and attacker["extra_action_charges"] > 0:
		attacker["extra_action_charges"] -= 1
		hit_count = 2
		steps.append("extra_action_consumed")

	var total_dealt := 0.0
	var primary_died := false
	var strikes := 0
	for _hit_index in hit_count:
		var march_active: bool = (
			attacker["side"] == "ally" and attacker["general"]
			and buffs.has_unit(attacker, MARCH_ID)
		)
		if not target["alive"] and not march_active:
			break
		var strike := _resolve_strike(
			request, ports, prepared, attacker, target, forced_active, march_active, steps
		)
		if not strike["ok"]:
			return strike
		total_dealt += float(strike["value"]["dealt"])
		primary_died = primary_died or strike["value"]["primary_died"]
		strikes += int(strike["value"]["strikes"])

	# Web performs the crossbow roll after the main hit loop and before pursuit.
	if request["attack_name"] == "普攻" and attacker["class_id"] == "crossbow" and strikes > 0:
		var roll: Variant = prepared["combat_rng"].next()
		if not _finite_number(roll) or float(roll) < 0.0 or float(roll) >= 1.0:
			return _failure("crossbow combat_rng.next returned outside [0,1)", steps, [])
		steps.append("crossbow_roll")
		var chance: float = prepared["relic_system"].get_crossbow_pursuit_chance(0.5, attacker)
		if float(roll) < chance:
			var buff_errors: Array[String] = []
			if not buffs.apply_unit(attacker, PURSUIT_ID, 1, null, buff_errors):
				return _failure("crossbow pursuit apply failed", steps, buff_errors)
			steps.append("crossbow_pursuit_applied")

	var pursuit_count := 0
	if request["trigger_pursuit"]:
		var pursuit := _consume_pursuits(
			request, ports, prepared, attacker, target, steps
		)
		if not pursuit["ok"]:
			return pursuit
		pursuit_count = pursuit["value"]["count"]
		total_dealt += pursuit["value"]["dealt"]

	if (
		request["trigger_banner_action"] and attacker["side"] == "ally"
		and attacker["class_id"] == "banner" and attacker["alive"]
	):
		var hero: Variant = _banner_hero(state)
		if hero != null:
			if ports.has_action("apply_player_energy"):
				var energy_result: Dictionary = ports.call_action("apply_player_energy", {
					"hero_id": hero["id"], "amount": 4.0,
					"source": {
						"kind": "banner_action", "attacker_id": attacker["id"],
						"attack_name": request["attack_name"],
					},
				})
				if not energy_result["ok"]:
					return _failure(
						"banner player energy failed after attack commit: %s" % energy_result["error"],
						steps,
						[],
					)
			else:
				hero["energy"] = minf(float(hero["max_energy"]), float(hero["energy"]) + 4.0)
			steps.append("banner_energy")

	return CombatPortsScript.ok({
		"status": "resolved", "reason": "completed", "committed": not steps.is_empty(),
		"primary_died": primary_died, "total_dealt": total_dealt,
		"primary_target_id": target["id"], "strikes": strikes,
		"pursuit_count": pursuit_count, "steps": steps.duplicate(),
	})


static func _resolve_strike(
	request: Dictionary,
	ports: Variant,
	prepared: Dictionary,
	attacker: Dictionary,
	base_target: Dictionary,
	forced_active: bool,
	march_active: bool,
	steps: Array[String],
) -> Dictionary:
	var damage_kind: String = request["damage_kind_override"]
	if damage_kind.is_empty():
		damage_kind = "pursuit" if request["attack_name"].contains("追击") else "normalAttack"
	var multiplier: float = (
		prepared["tuning"]["pursuitDamageRatio"]
		if request["attack_name"] == "追击" else float(request["damage_multiplier"])
	)
	if attacker["class_id"] == "crossbow" and request["attack_name"] == "普攻":
		multiplier *= 0.75
	var raw := _fmt(float(attacker["atk"]) * multiplier)
	var targets: Array[Dictionary] = [base_target]
	if march_active:
		var lane_slot: int = base_target["slot"] if forced_active else attacker["slot"]
		targets = _column_alive(request["state"], _other_side(attacker["side"]), lane_slot)
	var dealt := 0.0
	var primary_died := false
	var strikes := 0
	for target: Dictionary in targets:
		if not target["alive"]:
			continue
		var effect_errors: Array[String] = []
		var effect := _attack_effect(attacker, request["attack_name"], damage_kind, effect_errors)
		if effect.is_empty():
			return _failure("piece attack effect context failed", steps, effect_errors)
		var extra_crit := 0.0
		if (
			prepared["buffs"].has_side(attacker["side"], BREAK_FORMATION_ID)
			and prepared["buffs"].has_unit(target, BREAK_MARKED_ID)
		):
			extra_crit = 0.2
		var crit_rate: float = prepared["relic_system"].get_effective_crit_rate(
			1.0 if march_active else attacker["crit_rate"], attacker
		) + extra_crit
		var damage_context := ContextsScript.create_damage_context({
			"target_id": target["id"], "raw_amount": raw, "category": "direct",
			"effect": effect, "dealer_type": "piece",
			"dealer_name": "%s棋子%s" % ["我方" if attacker["side"] == "ally" else "敌方", str(attacker["id"])],
			"dealer_id": attacker["id"], "attacker_unit_id": attacker["id"],
			"can_crit": true, "crit_rate": crit_rate,
			"guaranteed_crit": march_active, "can_block": true,
		}, effect_errors)
		if damage_context.is_empty():
			return _failure("piece attack damage context failed", steps, effect_errors)
		var hit: Variant = prepared["damage"].apply(target, damage_context, {
			"attacker_unit": attacker, "damage_kind": damage_kind,
			"parent_source_effect": ContextsScript.snapshot(request["source_effect"]),
		}, effect_errors)
		if not _valid_damage_result(hit):
			return _failure("piece attack damage failed", steps, effect_errors)
		steps.append("damage:%s" % str(target["id"]))
		dealt += float(hit["dealt"])
		strikes += 1

		var event_payload := {
			"actor": attacker, "target": target, "amount": hit["dealt"],
			"source_effect": ContextsScript.snapshot(effect),
		}
		var emitted: Dictionary = ports.call_action("emit_content_event", {
			"event_id": "pieceAttackHit", "payload": event_payload,
		})
		if not emitted["ok"]:
			return _failure("pieceAttackHit event failed: %s" % emitted["error"], steps, [])
		steps.append("event:pieceAttackHit")
		if effect["counts_as_basic_attack"] and attacker["side"] == "ally":
			emitted = ports.call_action("emit_content_event", {
				"event_id": "basicAttackHit", "payload": event_payload,
			})
			if not emitted["ok"]:
				return _failure("basicAttackHit event failed: %s" % emitted["error"], steps, [])
			steps.append("event:basicAttackHit")

		var reaction: Dictionary = PieceReactionsScript.resolve({
			"state": request["state"], "attacker_side": attacker["side"],
			"attacker_id": attacker["id"], "defender_side": target["side"],
			"defender_id": target["id"], "primary_hit": hit,
			"permanent_buffs": request["permanent_buffs"],
		}, ports)
		if not reaction["ok"]:
			return _failure("piece reaction failed: %s" % reaction["error"], steps, [])
		steps.append("reactions:%s" % str(target["id"]))
		if is_same(target, base_target) and not target["alive"]:
			primary_died = true
	return CombatPortsScript.ok({
		"dealt": dealt, "primary_died": primary_died, "strikes": strikes,
	})


static func _consume_pursuits(
	request: Dictionary,
	ports: Variant,
	prepared: Dictionary,
	attacker: Dictionary,
	preferred_target: Dictionary,
	steps: Array[String],
) -> Dictionary:
	var count := 0
	var dealt := 0.0
	while (
		attacker["alive"] and prepared["buffs"].has_unit(attacker, PURSUIT_ID)
		and not TargetingRulesScript.alive(request["state"], _other_side(attacker["side"])).is_empty()
		and count < MAX_PURSUITS
	):
		var target: Variant = preferred_target if preferred_target["alive"] else null
		if target == null:
			target = TargetingRulesScript.lowest_hp_percent_lockable(
				request["state"], _other_side(attacker["side"])
			)
		if target == null:
			break
		var pursuit_request: Dictionary = request.duplicate(false)
		pursuit_request["forced_target_side"] = target["side"]
		pursuit_request["forced_target_id"] = target["id"]
		pursuit_request["forced_target_slot"] = target["slot"]
		pursuit_request["attack_name"] = "追击"
		pursuit_request["damage_multiplier"] = prepared["tuning"]["pursuitDamageRatio"]
		pursuit_request["trigger_extra_action"] = false
		pursuit_request["trigger_pursuit"] = false
		pursuit_request["trigger_banner_action"] = false
		pursuit_request["damage_kind_override"] = "pursuit"
		var pursuit_preflight := _preflight_execute(pursuit_request, ports)
		if not pursuit_preflight["ok"]:
			return _failure("pursuit preflight failed: %s" % pursuit_preflight["error"], steps, [])
		var consume_errors: Array[String] = []
		if prepared["buffs"].consume_unit(attacker, PURSUIT_ID, 1, consume_errors) != 1:
			return _failure("pursuit consume failed", steps, consume_errors)
		steps.append("pursuit_consumed")
		var result := _commit_execute(pursuit_request, ports, pursuit_preflight["value"])
		if not result["ok"]:
			return _failure("pursuit execution failed: %s" % result["error"], steps, [])
		count += 1
		dealt += float(result["value"]["total_dealt"])
	return CombatPortsScript.ok({"count": count, "dealt": dealt})


static func _preflight_execute(request: Variant, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _closed_dictionary(request, EXECUTE_KEYS):
		return CombatPortsScript.fail("piece attack request must have a canonical closed shape")
	if not _valid_ports(ports):
		return CombatPortsScript.fail("piece attack requires valid CombatPorts")
	if not BattleStateScript.validate(request["state"], errors):
		return CombatPortsScript.fail("piece attack state is non-canonical: %s" % errors[0])
	if request["attacker_side"] not in ["ally", "enemy"]:
		return CombatPortsScript.fail("attacker_side must be ally or enemy")
	if not _stable_id(request["attacker_id"]) or not _slot(request["attacker_slot"]):
		return CombatPortsScript.fail("attacker identity and slot are invalid")
	var attacker: Variant = _unit(request["state"], request["attacker_side"], request["attacker_id"])
	if attacker == null or attacker["slot"] != request["attacker_slot"]:
		return CombatPortsScript.fail("attacker identity/slot does not match canonical state")
	if typeof(request["attack_name"]) != TYPE_STRING or request["attack_name"].strip_edges().is_empty():
		return CombatPortsScript.fail("attack_name must be a non-empty string")
	if not _finite_number(request["damage_multiplier"]) or float(request["damage_multiplier"]) < 0.0:
		return CombatPortsScript.fail("damage_multiplier must be non-negative and finite")
	for key: String in ["trigger_extra_action", "trigger_pursuit", "trigger_banner_action"]:
		if typeof(request[key]) != TYPE_BOOL:
			return CombatPortsScript.fail("%s must be boolean" % key)
	if typeof(request["damage_kind_override"]) != TYPE_STRING:
		return CombatPortsScript.fail("damage_kind_override must be a String")
	if not _validate_effect(request["source_effect"], request["attacker_side"], errors):
		return CombatPortsScript.fail(errors[0])
	if typeof(request["permanent_buffs"]) != TYPE_ARRAY:
		return CombatPortsScript.fail("permanent_buffs must be an Array snapshot")
	if (
		typeof(request["relic_system"]) != TYPE_OBJECT or request["relic_system"] == null
		or request["relic_system"].get_script() != RelicSystemScript
		or request["relic_system"].is_valid() != true
	):
		return CombatPortsScript.fail("relic_system must be an exact valid B2 RelicSystem")
	var forced: Variant = null
	var forced_values := [
		request["forced_target_side"], request["forced_target_id"], request["forced_target_slot"],
	]
	if forced_values != [null, null, null]:
		if (
			request["forced_target_side"] != _other_side(request["attacker_side"])
			or not _stable_id(request["forced_target_id"])
			or not _slot(request["forced_target_slot"])
		):
			return CombatPortsScript.fail("forced target fields must be all-null or canonical opposing identity")
		forced = _unit(request["state"], request["forced_target_side"], request["forced_target_id"])
		if forced == null or forced["slot"] != request["forced_target_slot"]:
			return CombatPortsScript.fail("forced target identity/slot does not match canonical state")

	var buffs: Variant = ports.service("buffs", errors)
	var damage: Variant = ports.service("damage", errors)
	var tuning_service: Variant = ports.service("tuning", errors)
	var catalogs: Variant = ports.service("catalogs", errors)
	var combat_rng: Variant = ports.service("combat_rng", errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("piece attack services unavailable: %s" % errors[0])
	for side: String in ["ally", "enemy"]:
		for unit: Dictionary in request["state"]["allies" if side == "ally" else "enemies"]:
			if not buffs.validate_unit_holder(unit, errors):
				return CombatPortsScript.fail("piece attack Buff holder invalid: %s" % errors[0])
	if not buffs.validate_side_state(errors):
		return CombatPortsScript.fail("piece attack side Buffs invalid: %s" % errors[0])
	for definition_request: Array in [
		[STEALTH_ID, "unit"], [MARCH_ID, "unit"], [PURSUIT_ID, "unit"],
		[BREAK_MARKED_ID, "unit"], [BREAK_FORMATION_ID, "side"],
	]:
		if buffs.definition_for(definition_request[0], definition_request[1], errors) == null:
			return CombatPortsScript.fail("piece attack Buff authority invalid: %s" % errors[0])
	if typeof(catalogs) != TYPE_DICTIONARY or typeof(catalogs.get("piece_classes")) != TYPE_DICTIONARY:
		return CombatPortsScript.fail("catalogs.piece_classes authority is required")
	if typeof(catalogs.get("buffs")) != TYPE_DICTIONARY:
		return CombatPortsScript.fail("catalogs.buffs authority is required")
	var valid_hero_ids: Array = []
	for hero: Dictionary in request["state"]["player_heroes"]:
		valid_hero_ids.append(hero["id"])
	for hero: Dictionary in request["state"]["enemy_heroes"]:
		valid_hero_ids.append(hero["id"])
	PermanentBuffStoreScript.normalize_instances(
		request["permanent_buffs"], catalogs["buffs"], valid_hero_ids, errors
	)
	if not errors.is_empty():
		return CombatPortsScript.fail("piece attack permanent Buff snapshot invalid: %s" % errors[0])
	if attacker["class_id"] != "puppet":
		var class_definition: Variant = catalogs["piece_classes"].get(attacker["class_id"])
		if not class_definition is Resource or class_definition.get_script() != PieceClassDefinition:
			return CombatPortsScript.fail("attacker class_id is absent from M1 PieceClass authority")
	var pursuit_ratio := _tuning_number(tuning_service, "pursuitDamageRatio", errors)
	if not errors.is_empty() or pursuit_ratio < 0.0:
		return CombatPortsScript.fail("pursuitDamageRatio must be non-negative and finite")
	return CombatPortsScript.ok({
		"attacker": attacker, "forced_target": forced, "buffs": buffs,
		"damage": damage, "combat_rng": combat_rng,
		"tuning": {"pursuitDamageRatio": pursuit_ratio},
		"relic_system": request["relic_system"],
	})


static func _preflight_consume(request: Variant, ports: Variant, sequence: bool) -> Dictionary:
	var errors: Array[String] = []
	if not _closed_dictionary(request, CONSUME_KEYS):
		return CombatPortsScript.fail("piece plan consume request must have a canonical closed shape")
	if not _valid_ports(ports):
		return CombatPortsScript.fail("piece plan consumption requires valid CombatPorts")
	if not BattleStateScript.validate(request["state"], errors):
		return CombatPortsScript.fail("piece plan state is non-canonical: %s" % errors[0])
	if typeof(request["permanent_buffs"]) != TYPE_ARRAY:
		return CombatPortsScript.fail("piece plan permanent_buffs must be an Array snapshot")
	if (
		typeof(request["relic_system"]) != TYPE_OBJECT or request["relic_system"] == null
		or request["relic_system"].get_script() != RelicSystemScript
		or request["relic_system"].is_valid() != true
	):
		return CombatPortsScript.fail("piece plan relic_system must be exact valid B2 RelicSystem")
	if not _json_safe(request["plan"], "plan", [], errors):
		return CombatPortsScript.fail(errors[0])
	if sequence:
		return _validate_sequence(request, ports, errors)
	if not _validate_plan(request["plan"], request["state"], false, errors):
		return CombatPortsScript.fail(errors[0])
	var execute_preflight := _preflight_execute(_request_from_plan(request, request["plan"]), ports)
	if not execute_preflight["ok"]:
		return CombatPortsScript.fail("piece plan execute preflight failed: %s" % execute_preflight["error"])
	return CombatPortsScript.ok({})


static func _validate_sequence(request: Dictionary, ports: Variant, errors: Array[String]) -> Dictionary:
	var sequence: Variant = request["plan"]
	if not _closed_dictionary(sequence, SEQUENCE_KEYS):
		return CombatPortsScript.fail("piece attack sequence must have a canonical closed shape")
	if sequence["kind"] != "execute_piece_attack_sequence" or sequence["status"] != "pending_b4_execution":
		return CombatPortsScript.fail("piece attack sequence kind/status is invalid or already consumed")
	if sequence["retarget_on_target_death"] != true or sequence["retarget_policy"] != "lowest_hp_percent_lockable":
		return CombatPortsScript.fail("piece attack sequence retarget policy is unsupported")
	if typeof(sequence["plans"]) != TYPE_ARRAY:
		return CombatPortsScript.fail("piece attack sequence plans must be an Array")
	var initial: Variant = null
	var initial_values := [sequence["initial_target_side"], sequence["initial_target_id"], sequence["initial_target_slot"]]
	if initial_values != [null, null, null]:
		if (
			sequence["initial_target_side"] not in ["ally", "enemy"]
			or not _stable_id(sequence["initial_target_id"])
			or not _slot(sequence["initial_target_slot"])
		):
			return CombatPortsScript.fail("sequence initial target identity is invalid")
		initial = _unit(request["state"], sequence["initial_target_side"], sequence["initial_target_id"])
		if initial == null or initial["slot"] != sequence["initial_target_slot"]:
			return CombatPortsScript.fail("sequence initial target does not match canonical state")
	elif not sequence["plans"].is_empty():
		return CombatPortsScript.fail("sequence with plans requires an initial target")
	for index in sequence["plans"].size():
		var plan: Variant = sequence["plans"][index]
		if not _validate_plan(plan, request["state"], true, errors):
			return CombatPortsScript.fail("sequence plan[%d] invalid: %s" % [index, errors[0]])
		if initial != null and plan["target_side"] != initial["side"]:
			return CombatPortsScript.fail("sequence plan target side must match initial target side")
		var execute_preflight := _preflight_execute(_request_from_plan(request, plan), ports)
		if not execute_preflight["ok"]:
			return CombatPortsScript.fail("sequence plan[%d] execute preflight failed: %s" % [index, execute_preflight["error"]])
	return CombatPortsScript.ok({"initial_target": initial})


static func _validate_plan(plan: Variant, state: Dictionary, shadow: bool, errors: Array[String]) -> bool:
	if not _closed_dictionary(plan, PLAN_KEYS):
		errors.append("execute piece attack plan must have a canonical closed shape")
		return false
	if plan["kind"] != "execute_piece_attack":
		errors.append("execute piece attack plan kind is invalid or already consumed")
		return false
	if plan["attacker_side"] not in ["ally", "enemy"] or plan["target_side"] != _other_side(plan["attacker_side"]):
		errors.append("plan sides are invalid")
		return false
	if not _stable_id(plan["attacker_id"]) or not _stable_id(plan["target_id"]):
		errors.append("plan ids must be stable")
		return false
	if not _slot(plan["attacker_slot"]) or not _slot(plan["target_slot"]):
		errors.append("plan slots must be canonical")
		return false
	var attacker: Variant = _unit(state, plan["attacker_side"], plan["attacker_id"])
	var target: Variant = _unit(state, plan["target_side"], plan["target_id"])
	if attacker == null or attacker["slot"] != plan["attacker_slot"]:
		errors.append("plan attacker identity/slot mismatch")
		return false
	if target == null or target["slot"] != plan["target_slot"]:
		errors.append("plan target identity/slot mismatch")
		return false
	if typeof(plan["attack_name"]) != TYPE_STRING or plan["attack_name"].strip_edges().is_empty():
		errors.append("plan attack_name must be non-empty")
		return false
	if not _finite_number(plan["damage_multiplier"]) or float(plan["damage_multiplier"]) < 0.0:
		errors.append("plan damage_multiplier must be non-negative and finite")
		return false
	if typeof(plan["trigger_extra_action"]) != TYPE_BOOL or typeof(plan["trigger_pursuit"]) != TYPE_BOOL:
		errors.append("plan trigger flags must be boolean")
		return false
	if typeof(plan["damage_kind_override"]) != TYPE_STRING or plan["damage_kind_override"].is_empty():
		errors.append("plan damage_kind_override must be non-empty")
		return false
	if not _validate_effect(plan["source_effect"], plan["attacker_side"], errors):
		return false
	if shadow and (
		plan["attack_name"] != "潜行追击" or float(plan["damage_multiplier"]) != 0.5
		or plan["trigger_extra_action"] != false or plan["trigger_pursuit"] != false
		or plan["damage_kind_override"] != "pursuit"
		or plan["source_effect"]["source_type"] != "ultimate"
		or plan["source_effect"]["source_id"] != "shadow"
		or plan["source_effect"]["counts_as_skill_cast"] != true
	):
		errors.append("shadow sequence plan policy is invalid")
		return false
	return true


static func _request_from_plan(wrapper: Dictionary, plan: Dictionary) -> Dictionary:
	return {
		"state": wrapper["state"], "attacker_side": plan["attacker_side"],
		"attacker_id": plan["attacker_id"], "attacker_slot": plan["attacker_slot"],
		"forced_target_side": plan["target_side"], "forced_target_id": plan["target_id"],
		"forced_target_slot": plan["target_slot"], "attack_name": plan["attack_name"],
		"damage_multiplier": plan["damage_multiplier"],
		"trigger_extra_action": plan["trigger_extra_action"],
		"trigger_pursuit": plan["trigger_pursuit"], "trigger_banner_action": true,
		"damage_kind_override": plan["damage_kind_override"],
		"source_effect": ContextsScript.snapshot(plan["source_effect"]),
		"permanent_buffs": wrapper["permanent_buffs"],
		"relic_system": wrapper["relic_system"],
	}


static func _attack_effect(
	attacker: Dictionary, attack_name: String, damage_kind: String, errors: Array[String]
) -> Dictionary:
	var counts_basic := attack_name == "普攻" and damage_kind == "normalAttack"
	return ContextsScript.create_effect_context({
		"source_type": "pursuit" if damage_kind == "pursuit" else "basic_attack",
		"source_id": damage_kind, "source_name": attack_name,
		"source_side": attacker["side"], "source_actor_id": attacker["id"],
		"counts_as_skill_cast": false, "spent_skill_points": false, "free_cast": false,
		"counts_as_basic_attack": counts_basic, "counts_as_attack": true,
		"triggers_enemy_kill_effects": true,
	}, errors)


static func _validate_effect(effect: Variant, side: String, errors: Array[String]) -> bool:
	if not _closed_dictionary(effect, EFFECT_KEYS):
		errors.append("source_effect must have a canonical closed shape")
		return false
	var normalized_errors: Array[String] = []
	var normalized := ContextsScript.create_effect_context(effect, normalized_errors)
	if not normalized_errors.is_empty() or normalized != effect:
		errors.append("source_effect must be canonical")
		return false
	if effect["source_side"] != side:
		errors.append("source_effect side must match attacker side")
		return false
	return true


static func _banner_hero(state: Dictionary) -> Variant:
	var deployed: Array[Dictionary] = []
	for hero: Dictionary in state["player_heroes"]:
		if hero["deployed"]:
			deployed.append(hero)
	deployed.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left["energy"]) != float(right["energy"]):
			return float(left["energy"]) > float(right["energy"])
		return _id_less(left["id"], right["id"])
	)
	return deployed[0] if not deployed.is_empty() else null


static func _column_alive(state: Dictionary, side: String, reference_slot: int) -> Array[Dictionary]:
	var lane := ((reference_slot - 1) % 3) + 1
	var result: Array[Dictionary] = []
	for slot: int in [lane, lane + 3]:
		var unit: Variant = _unit_at_slot(state, side, slot)
		if unit != null and unit["alive"]:
			result.append(unit)
	return result


static func _empty_result(reason: String, steps: Array[String]) -> Dictionary:
	return {
		"status": "resolved", "reason": reason, "committed": not steps.is_empty(),
		"primary_died": false, "total_dealt": 0.0, "primary_target_id": null,
		"strikes": 0, "pursuit_count": 0, "steps": steps.duplicate(),
	}


static func _valid_ports(ports: Variant) -> bool:
	return (
		typeof(ports) == TYPE_OBJECT and ports != null
		and ports.get_script() == CombatPortsScript and ports.is_valid() == true
	)


static func _valid_damage_result(result: Variant) -> bool:
	if not _closed_dictionary(result, DAMAGE_RESULT_KEYS):
		return false
	return (
		_finite_number(result["dealt"]) and float(result["dealt"]) >= 0.0
		and typeof(result["blocked"]) == TYPE_BOOL and typeof(result["died"]) == TYPE_BOOL
		and typeof(result["crit"]) == TYPE_BOOL
		and typeof(result["damage_context"]) == TYPE_DICTIONARY
		and (result["death_context"] == null or typeof(result["death_context"]) == TYPE_DICTIONARY)
	)


static func _tuning_number(tuning: Variant, id: String, errors: Array[String]) -> float:
	if typeof(tuning) != TYPE_DICTIONARY:
		errors.append("tuning service must return a Dictionary")
		return 0.0
	var definition: Variant = tuning.get(id)
	if not definition is Resource or definition.get_script() != TuningValueDefinition:
		errors.append("tuning.%s must be a TuningValueDefinition" % id)
		return 0.0
	if not _finite_number(definition.value):
		errors.append("tuning.%s.value must be finite" % id)
		return 0.0
	return float(definition.value)


static func _json_safe(value: Variant, path: String, seen: Array, errors: Array[String]) -> bool:
	if value == null or typeof(value) in [TYPE_STRING, TYPE_BOOL, TYPE_INT]:
		return true
	if typeof(value) == TYPE_FLOAT:
		if is_finite(value):
			return true
		errors.append("%s contains a non-finite number" % path)
		return false
	if typeof(value) not in [TYPE_ARRAY, TYPE_DICTIONARY]:
		errors.append("%s contains a non-JSON-safe value" % path)
		return false
	for previous: Variant in seen:
		if is_same(previous, value):
			errors.append("%s contains a shared or circular reference" % path)
			return false
	seen.append(value)
	if typeof(value) == TYPE_ARRAY:
		for index in value.size():
			if not _json_safe(value[index], "%s[%d]" % [path, index], seen, errors):
				return false
		return true
	for key: Variant in value:
		if typeof(key) != TYPE_STRING:
			errors.append("%s contains a non-string key" % path)
			return false
		if not _json_safe(value[key], "%s.%s" % [path, key], seen, errors):
			return false
	return true


static func _closed_dictionary(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			return false
	return true


static func _unit(state: Dictionary, side: String, id: Variant) -> Variant:
	for unit: Dictionary in state["allies" if side == "ally" else "enemies"]:
		if unit["id"] == id:
			return unit
	return null


static func _unit_at_slot(state: Dictionary, side: String, slot: int) -> Variant:
	for unit: Dictionary in state["allies" if side == "ally" else "enemies"]:
		if unit["slot"] == slot:
			return unit
	return null


static func _failure(message: String, steps: Array[String], errors: Array[String]) -> Dictionary:
	var suffix := "" if errors.is_empty() else ": %s" % errors[0]
	var prefix := "none" if steps.is_empty() else ",".join(steps)
	return CombatPortsScript.fail("%s (committed steps: %s)%s" % [message, prefix, suffix])


static func _stable_id(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT and value > 0)
		or (typeof(value) == TYPE_STRING and value == value.strip_edges() and not value.is_empty())
	)


static func _slot(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 1 and value <= 6


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _fmt(value: float) -> float:
	return maxf(0.0, roundf(value * 10.0) / 10.0)


static func _id_less(left: Variant, right: Variant) -> bool:
	if typeof(left) == typeof(right):
		return left < right
	return typeof(left) < typeof(right)


static func _other_side(side: String) -> String:
	return "enemy" if side == "ally" else "ally"
