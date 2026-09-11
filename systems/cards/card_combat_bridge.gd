class_name CardCombatBridge
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CardDefinitionScript = preload("res://data/definitions/card_definition.gd")
const Result = preload("res://core/card_runtime_result.gd")
const RequestScript = preload("res://systems/cards/card_play_request.gd")
const HandRuntimeScript = preload("res://systems/cards/hand_runtime.gd")
const PlayerEnergyCoordinatorScript = preload("res://systems/cards/player_energy_coordinator.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")
const FreeSkillEffectsScript = preload("res://systems/effects/free_skill_effects.gd")
const FlameFateEffectsScript = preload("res://systems/effects/hero_effects_flame_fate.gd")
const MarshalFistEffectsScript = preload("res://systems/effects/hero_effects_marshal_fist.gd")
const SiegePuppetShadowEffectsScript = preload("res://systems/effects/hero_effects_siege_puppet_shadow.gd")
const HeroCardCatalog = preload("res://data/catalogs/hero_card_catalog.gd")
const TargetingRulesScript = preload("res://systems/targeting/targeting_rules.gd")
const PieceAttackScript = preload("res://systems/combat/piece_attack.gd")

const CONFIG_KEYS := [
	"state", "hand_runtime", "card_catalog", "registry", "ports",
	"relic_system", "energy_coordinator",
]
const FORBIDDEN_SOURCE_SKILL_IDS: Array[String] = ["basicDamage"]
const TARGETABLE_SOURCE_SKILL_IDS: Array[String] = [
	"executeStrike", "pieceAction", "ascend", "puppetAttunement",
]

var _state: Dictionary
var _hand_runtime: Variant
var _card_catalog: Dictionary = {}
var _registry: Variant
var _ports: Variant
var _relic_system: Variant
var _energy_coordinator: Variant
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if not _exact_keys(config, CONFIG_KEYS, "card combat bridge config", errors):
		return
	var state_errors: Array[String] = []
	if typeof(config["state"]) != TYPE_DICTIONARY or not BattleStateScript.validate(config["state"], state_errors):
		errors.append("card combat bridge requires canonical BattleState%s" % _error_suffix(state_errors))
		return
	if not _exact_object(config["hand_runtime"], HandRuntimeScript):
		errors.append("card combat bridge requires exact HandRuntime")
		return
	if not _exact_object(config["registry"], EffectRegistryScript) or config["registry"].handler_ids().is_empty():
		errors.append("card combat bridge requires valid exact EffectRegistry")
		return
	if not _exact_object(config["ports"], CombatPortsScript) or not config["ports"].is_valid():
		errors.append("card combat bridge requires valid exact CombatPorts")
		return
	if not _exact_object(config["relic_system"], RelicSystemScript) or not config["relic_system"].is_valid():
		errors.append("card combat bridge requires valid exact RelicSystem")
		return
	if (
		not _exact_object(config["energy_coordinator"], PlayerEnergyCoordinatorScript)
		or not config["energy_coordinator"].is_valid()
	):
		errors.append("card combat bridge requires valid exact PlayerEnergyCoordinator")
		return
	if not _validate_catalog(config["card_catalog"], errors):
		return
	_state = config["state"]
	_hand_runtime = config["hand_runtime"]
	_registry = config["registry"]
	_ports = config["ports"]
	_relic_system = config["relic_system"]
	_energy_coordinator = config["energy_coordinator"]
	for card_id: Variant in config["card_catalog"]:
		_card_catalog[card_id] = config["card_catalog"][card_id].snapshot()
	_valid = true


func is_valid() -> bool:
	return _valid


func inspect_playability(request: Variant) -> RefCounted:
	if not _valid:
		return _failure(Result.INVALID_ARGUMENT, "card combat bridge is invalid")
	var request_error := _request_error(request)
	if not request_error.is_empty():
		return _failure(Result.INVALID_ARGUMENT, request_error)
	var command: Variant = request.snapshot()
	if command.expected_source_skill_id in FORBIDDEN_SOURCE_SKILL_IDS:
		return _failure(Result.INVALID_CARD, "player card requests exclude basicDamage")
	var instance: Variant = _hand_runtime.get_instance_snapshot(command.instance_id)
	if instance == null:
		return _failure(Result.CARD_NOT_FOUND, "unknown card instance: %s" % command.instance_id)
	var authority_error := _authority_error(command, instance)
	if not authority_error.is_empty():
		return _failure(Result.INVALID_CARD, authority_error)
	var definition: Variant = _card_catalog[instance.definition.id]
	var scheduled_base_cost: int = int(definition.base_sp_cost)
	var display_effective_cost: int = instance.effective_sp_cost()
	var scheduled_result := _scheduled_base_cost(definition)
	if scheduled_result["ok"]:
		scheduled_base_cost = int(scheduled_result["value"])
	var display_cost_result := _dynamic_effective_cost(definition, instance)
	if display_cost_result["ok"]:
		display_effective_cost = int(display_cost_result["value"])

	var unavailable_code := ""
	var unavailable_reason := ""
	if command.instance_id not in _hand_runtime.pile_instance_ids(CardDefinitionScript.PILE_HAND):
		unavailable_code = Result.CARD_NOT_FOUND
		unavailable_reason = "card command requires an instance in hand: %s" % command.instance_id
	elif _hand_runtime.is_queue_halted():
		unavailable_code = Result.QUEUE_HALTED
		unavailable_reason = "card command queue is halted after a committed failure"
	elif _hand_runtime.is_queue_busy():
		unavailable_code = Result.QUEUE_BUSY
		unavailable_reason = "another card command is already resolving"
	else:
		var success_limit: int = instance.definition.max_successful_plays_per_combat
		if success_limit > 0 and _hand_runtime.successful_play_count(command.instance_id) >= success_limit:
			unavailable_code = Result.SUCCESS_LIMIT_REACHED
			unavailable_reason = "card instance reached its successful play limit"

	var prepared: Dictionary = {}
	if unavailable_code.is_empty():
		var preflight: Dictionary = _preflight(command, instance, true)
		if not preflight["ok"]:
			unavailable_code = Result.VALIDATOR_REJECTED
			unavailable_reason = preflight["error"]
		else:
			prepared = preflight["value"]
	return Result.new(true, Result.OK, "", {
		"instance_id": command.instance_id,
		"card_id": definition.id,
		"playable": unavailable_code.is_empty(),
		"unavailable_code": unavailable_code,
		"reason": unavailable_reason,
		"base_cost": int(prepared.get("base_cost", scheduled_base_cost)),
		"effective_cost": int(prepared.get("effective_cost", display_effective_cost)),
		"actual_cost": (
			int(prepared.get("actual_cost", display_effective_cost))
			if unavailable_code.is_empty() else null
		),
	})


func play(request: Variant) -> RefCounted:
	if not _valid:
		return _failure(Result.INVALID_ARGUMENT, "card combat bridge is invalid")
	var request_error := _request_error(request)
	if not request_error.is_empty():
		return _failure(Result.INVALID_ARGUMENT, request_error)
	var command: Variant = request.snapshot()
	if command.expected_source_skill_id in FORBIDDEN_SOURCE_SKILL_IDS:
		return _failure(Result.INVALID_CARD, "player card requests exclude basicDamage")
	var instance: Variant = _hand_runtime.get_instance_snapshot(command.instance_id)
	if instance == null:
		return _failure(Result.CARD_NOT_FOUND, "unknown card instance: %s" % command.instance_id)
	var authority_error := _authority_error(command, instance)
	if not authority_error.is_empty():
		return _failure(Result.INVALID_CARD, authority_error)

	var prepared: Dictionary = {}
	var validate := func(card_snapshot: Variant) -> Dictionary:
		# Empty optimistic guards identify the internal automatic-play path used by
		# battle simulation. It may choose the canonical fallback target; guarded
		# UI commands must carry their explicit required target.
		var preflight := _preflight(
			command, card_snapshot, command.expected_card_id.is_empty(),
		)
		if not preflight["ok"]:
			return {
				"ok": false, "message": preflight["error"],
				"details": {"phase": "preflight", "committed_prefix": false},
			}
		prepared.clear()
		prepared.merge(preflight["value"], true)
		return {"ok": true}
	var execute := func(_card_snapshot: Variant) -> Dictionary:
		var sp_before := float(_state["sp"])
		_state["sp"] = sp_before - float(prepared["actual_cost"])
		var execute_errors: Array[String] = []
		var executed: Dictionary = _registry.execute(
			prepared["definition"].effect_id,
			prepared["context"],
			_ports,
			execute_errors,
		)
		if not executed["ok"]:
			return {
				"ok": false,
				"message": "player card effect failed after SP committed: %s" % executed["error"],
				"committed": true,
				"details": {
					"phase": "effect", "actual_cost": prepared["actual_cost"],
					"sp_before": sp_before, "sp_after": _state["sp"],
					"effect_id": prepared["definition"].effect_id,
					"effect_call_count": 1,
				},
			}
		var effect_value: Dictionary = executed["value"]
		if prepared["definition"].source_skill_id == "executeStrike":
			var attack: Dictionary = PieceAttackScript.consume_plan({
				"state": _state,
				"plan": effect_value["plan"],
				"permanent_buffs": [],
				"relic_system": _relic_system,
			}, _ports)
			if not attack["ok"]:
				return {
					"ok": false,
					"message": "executeStrike attack failed after SP committed: %s" % attack["error"],
					"committed": true,
					"details": {
						"phase": "effect", "actual_cost": prepared["actual_cost"],
						"sp_before": sp_before, "sp_after": _state["sp"],
						"effect_id": prepared["definition"].effect_id,
						"effect_call_count": 1,
					},
				}
			effect_value = attack["value"]
			if bool(effect_value.get("primary_died", false)):
				_state["sp"] = float(_state["sp"]) + 1.0
			effect_value["kill_sp_gained"] = 1 if bool(effect_value.get("primary_died", false)) else 0
		prepared["sp_before"] = sp_before
		prepared["sp_after"] = float(_state["sp"])
		prepared["effect_result"] = effect_value
		return {
			"ok": true,
			"details": {
				"committed": true,
				"actual_cost": prepared["actual_cost"],
				"effective_cost": prepared["effective_cost"],
				"base_cost": prepared["base_cost"],
				"sp_before": sp_before, "sp_after": _state["sp"],
				"effect_id": prepared["definition"].effect_id,
				"effect_call_count": 1,
				"effect_result": effect_value,
			},
		}
	var post_success := func(_card_snapshot: Variant, destination: String) -> Dictionary:
		var post := _post_success(command, prepared, destination)
		if not post["ok"]:
			return {
				"ok": false, "message": post["error"], "committed": true,
				"details": {
					"phase": "post_success", "actual_cost": prepared["actual_cost"],
					"sp_before": prepared["sp_before"], "sp_after": prepared["sp_after"],
					"effect_id": prepared["definition"].effect_id,
					"effect_call_count": 1,
				},
			}
		return {"ok": true, "details": post["value"]}
	var definition: Variant = instance.definition
	return _hand_runtime.process_play_command(
		command.instance_id,
		validate,
		execute,
		definition.card_play_destination == CardDefinitionScript.PILE_HAND,
		post_success,
	)


func _preflight(
	command: Variant,
	instance: Variant,
	allow_default_required_target: bool = false,
) -> Dictionary:
	var state_errors: Array[String] = []
	if not BattleStateScript.validate(_state, state_errors):
		return CombatPortsScript.fail("player card state is non-canonical%s" % _error_suffix(state_errors))
	if _state["game_over"]:
		return CombatPortsScript.fail("player cards are unavailable after battle end")
	if _state["phase"] != "player_input":
		return CombatPortsScript.fail("player cards require player_input phase")
	var authority_error := _authority_error(command, instance)
	if not authority_error.is_empty():
		return CombatPortsScript.fail(authority_error)
	var definition: Variant = _card_catalog[instance.definition.id]
	var card_runtime_error := _card_runtime_preflight_error(definition)
	if not card_runtime_error.is_empty():
		return CombatPortsScript.fail(card_runtime_error)
	var requires_target := _card_requires_explicit_target(definition)
	if command.target != null and definition.source_skill_id not in TARGETABLE_SOURCE_SKILL_IDS:
		return CombatPortsScript.fail("this player card does not accept a target")
	if requires_target and command.target == null and not allow_default_required_target:
		return CombatPortsScript.fail("this player card requires a target")
	var target_result := _prepare_target(
		definition, command.target, allow_default_required_target, requires_target,
	)
	if not target_result["ok"]:
		return target_result
	var target: Variant = target_result["value"]
	var owner: Variant = null
	if definition.card_category == CardDefinitionScript.CATEGORY_FREE:
		if command.owner_hero_id != null:
			return CombatPortsScript.fail("free cards do not select a caster")
	elif definition.card_category in [
		CardDefinitionScript.CATEGORY_EXCLUSIVE,
		CardDefinitionScript.CATEGORY_ULTIMATE,
	]:
		owner = _player_hero(definition.owner_hero_id)
		if owner == null or not owner["deployed"]:
			return CombatPortsScript.fail("card owner must be a deployed player hero")
		if command.owner_hero_id != null and command.owner_hero_id != definition.owner_hero_id:
			return CombatPortsScript.fail("requested owner conflicts with authoritative card owner")
	else:
		return CombatPortsScript.fail("unknown player card category")

	var cost_result := _dynamic_effective_cost(definition, instance)
	if not cost_result["ok"]:
		return cost_result
	var effective_cost: int = int(cost_result["value"])
	var actual_cost := 0
	if definition.card_category != CardDefinitionScript.CATEGORY_ULTIMATE:
		actual_cost = _relic_system.get_effective_skill_point_cost(
			effective_cost,
			"ally",
			_state["round"],
			"freeSkill" if definition.card_category == CardDefinitionScript.CATEGORY_FREE else "exclusive",
		)
	if float(_state["sp"]) < float(actual_cost):
		return CombatPortsScript.fail("insufficient player SP")
	var context_result := _build_context(definition, owner, actual_cost, target)
	if not context_result["ok"]:
		return context_result
	var context: Dictionary = context_result["value"]
	var usable_errors: Array[String] = []
	if not _is_usable(definition, context, usable_errors):
		return CombatPortsScript.fail(
			"player card validator rejected: %s"
			% (usable_errors[0] if not usable_errors.is_empty() else "unusable")
		)
	return CombatPortsScript.ok({
		"definition": definition,
		"owner": owner,
		"base_cost": int(_scheduled_base_cost(definition)["value"]),
		"effective_cost": effective_cost,
		"actual_cost": actual_cost,
		"context": context,
	})


func _prepare_target(
	definition: Variant,
	requested_target: Variant,
	allow_default_required_target: bool,
	requires_target: bool,
) -> Dictionary:
	if requested_target == null:
		if definition.source_skill_id == "puppetAttunement" or (requires_target and allow_default_required_target):
			var fallback: Variant = _default_target(definition.source_skill_id)
			return (
				CombatPortsScript.ok(fallback)
				if fallback != null else CombatPortsScript.fail("this player card has no valid target")
			)
		return CombatPortsScript.ok(null)
	if typeof(requested_target) != TYPE_DICTIONARY:
		return CombatPortsScript.fail("player card target must be a Dictionary")
	var expected_keys := ["side", "unit_id", "slot"]
	if requested_target.size() != expected_keys.size():
		return CombatPortsScript.fail("player card target must have a canonical closed shape")
	for key: String in expected_keys:
		if not requested_target.has(key):
			return CombatPortsScript.fail("player card target is missing %s" % key)
	if requested_target["side"] not in ["ally", "enemy"]:
		return CombatPortsScript.fail("player card target side must be ally or enemy")
	if not _stable_id(requested_target["unit_id"]):
		return CombatPortsScript.fail("player card target unit_id must be a stable id")
	if typeof(requested_target["slot"]) != TYPE_INT or int(requested_target["slot"]) < 1 or int(requested_target["slot"]) > 6:
		return CombatPortsScript.fail("player card target slot must be from 1 through 6")
	var expected_side := "enemy" if definition.source_skill_id == "executeStrike" else "ally"
	if requested_target["side"] != expected_side:
		return CombatPortsScript.fail("player card target is on the wrong side")
	var unit: Variant = _unit_by_id(expected_side, requested_target["unit_id"])
	if unit == null or int(unit["slot"]) != int(requested_target["slot"]):
		return CombatPortsScript.fail("player card target identity no longer matches battle state")
	if not bool(unit["alive"]):
		return CombatPortsScript.fail("player card target is no longer alive")
	return CombatPortsScript.ok(unit)


func _card_requires_explicit_target(definition: Variant) -> bool:
	if definition.card_requires_target:
		return true
	if definition.source_skill_id != "ascend":
		return false
	for unit: Dictionary in _state["allies"]:
		if unit["alive"] and unit["general"]:
			return false
	return true


func _default_target(source_skill_id: String) -> Variant:
	if source_skill_id == "executeStrike":
		return TargetingRulesScript.lowest_current_hp_lockable(_state, "enemy")
	if source_skill_id == "pieceAction":
		return TargetingRulesScript.highest_atk_alive(_state, "ally")
	if source_skill_id == "ascend":
		for unit: Dictionary in _state["allies"]:
			if unit["alive"] and not unit["is_puppet"]:
				return unit
	if source_skill_id == "puppetAttunement":
		var errors: Array[String] = []
		var buffs: Variant = _ports.service("buffs", errors)
		if not errors.is_empty():
			return null
		for unit: Dictionary in _state["allies"]:
			if unit["alive"] and unit["is_puppet"] and buffs.get_unit_enchantment_capacity(unit) == 0:
				return unit
	return null


func _dynamic_effective_cost(definition: Variant, instance: Variant) -> Dictionary:
	var scheduled_result := _scheduled_base_cost(definition)
	if not scheduled_result["ok"]:
		return scheduled_result
	var modifiers: Dictionary = instance.cost_modifiers()
	var modifier_total := (
		int(modifiers["until_played"])
		+ int(modifiers["until_turn"])
		+ int(modifiers["until_combat"])
	)
	return CombatPortsScript.ok(maxi(
		0, int(scheduled_result["value"]) + modifier_total,
	))


func _scheduled_base_cost(definition: Variant) -> Dictionary:
	if definition.card_category != CardDefinitionScript.CATEGORY_EXCLUSIVE:
		return CombatPortsScript.ok(int(definition.base_sp_cost))
	match definition.source_skill_id:
		"burn01":
			var successful_casts := int(_state["burn_ex_cast_count"])
			return CombatPortsScript.ok(
				1 if successful_casts == 0
				else 2 if successful_casts == 1
				else 4 if successful_casts == 2
				else 8
			)
		"burnEnchant":
			var errors: Array[String] = []
			var buffs: Variant = _ports.service("buffs", errors)
			if not errors.is_empty():
				return CombatPortsScript.fail("dynamic card cost requires buffs service: %s" % errors[0])
			var successful_casts: int = int(buffs.get_side_stacks("ally", "flameCastCount"))
			return CombatPortsScript.ok(1 if successful_casts == 0 else (2 if successful_casts < 3 else 4))
	return CombatPortsScript.ok(int(definition.base_sp_cost))


func _card_runtime_preflight_error(definition: Variant) -> String:
	if definition.source_skill_id != "tacticalDraw":
		return ""
	var hand_state: Dictionary = _hand_runtime.snapshot()
	var piles: Dictionary = hand_state.get("piles", {})
	var hand_count: int = piles.get(CardDefinitionScript.PILE_HAND, []).size()
	if hand_count > HandRuntimeScript.HAND_LIMIT - 1:
		return "tacticalDraw requires room for both drawn cards"
	var available: int = (
		piles.get(CardDefinitionScript.PILE_DRAW, []).size()
		+ piles.get(CardDefinitionScript.PILE_DISCARD, []).size()
	)
	if available < 2:
		return "tacticalDraw requires at least two cards in draw/discard piles"
	return ""


func _build_context(
	definition: Variant,
	owner: Variant,
	actual_cost: int,
	target: Variant = null,
) -> Dictionary:
	var source_name := _source_name(definition)
	if source_name.is_empty():
		return CombatPortsScript.fail("player card source name is unavailable")
	var source_type := ContextsScript.EFFECT_SOURCE_TYPE["FREE_SKILL"]
	var source_actor_id: Variant = "player_cards"
	if definition.card_category == CardDefinitionScript.CATEGORY_EXCLUSIVE:
		source_type = ContextsScript.EFFECT_SOURCE_TYPE["EXCLUSIVE_SKILL"]
		source_actor_id = owner["id"]
	elif definition.card_category == CardDefinitionScript.CATEGORY_ULTIMATE:
		source_type = ContextsScript.EFFECT_SOURCE_TYPE["ULTIMATE"]
		source_actor_id = owner["id"]
	var effect_errors: Array[String] = []
	var source_effect := ContextsScript.create_effect_context({
		"source_type": source_type,
		"source_id": definition.source_skill_id,
		"source_name": source_name,
		"source_side": "ally",
		"source_actor_id": source_actor_id,
		"counts_as_skill_cast": true,
		"spent_skill_points": actual_cost > 0,
		"free_cast": actual_cost == 0,
		"counts_as_basic_attack": false,
		"counts_as_attack": false,
		"triggers_enemy_kill_effects": true,
	}, effect_errors)
	if not effect_errors.is_empty():
		return CombatPortsScript.fail("player card effect context failed: %s" % effect_errors[0])
	if definition.card_category == CardDefinitionScript.CATEGORY_FREE:
		var free_context := {
			"state": _state,
			"caster_side": "ally",
			"caster_id": source_actor_id,
			"caster_name": "我方",
			"caster_base_crit_rate": 0.0,
			"source_effect": source_effect,
		}
		if target != null:
			free_context["target_unit_id"] = target["id"]
		return CombatPortsScript.ok(free_context)
	var hero_context := {
		"state": _state,
		"caster": owner,
		"source_effect": source_effect,
	}
	if target != null:
		hero_context["target_unit_id"] = target["id"]
	return CombatPortsScript.ok(hero_context)


func _is_usable(definition: Variant, context: Dictionary, errors: Array[String]) -> bool:
	if definition.card_category == CardDefinitionScript.CATEGORY_FREE:
		return FreeSkillEffectsScript.is_usable(definition.source_skill_id, context, _ports, errors)
	var is_ultimate: bool = definition.card_category == CardDefinitionScript.CATEGORY_ULTIMATE
	if FlameFateEffectsScript.handler_map().has(definition.effect_id):
		return FlameFateEffectsScript.is_usable(definition.effect_id, context, _ports, errors)
	if MarshalFistEffectsScript.handler_map().has(definition.effect_id):
		return MarshalFistEffectsScript.is_usable(
			definition.source_skill_id, is_ultimate, context, _ports, errors
		)
	if SiegePuppetShadowEffectsScript.handler_map().has(definition.effect_id):
		return SiegePuppetShadowEffectsScript.is_usable(
			definition.source_skill_id, is_ultimate, context, _ports, errors
		)
	errors.append("player card has no M2 validator authority")
	return false


func _post_success(command: Variant, prepared: Dictionary, destination: String) -> Dictionary:
	var definition: Variant = prepared["definition"]
	var draw_result: Variant = null
	var draw_count := int(prepared.get("effect_result", {}).get("draw_count", 0))
	if draw_count > 0:
		# The played card has already moved to its battle-long exhaust pile, so it
		# cannot be drawn by its own effect after a discard reshuffle.
		draw_result = _hand_runtime.draw_cards(draw_count)
	var event_id := "freeSkillCast"
	if definition.card_category == CardDefinitionScript.CATEGORY_EXCLUSIVE:
		event_id = "exclusiveCast"
	elif definition.card_category == CardDefinitionScript.CATEGORY_ULTIMATE:
		event_id = "ultimateCast"
	var event_payload := {
		"round": _state["round"],
		"amount": prepared["actual_cost"],
		"actual_cost": prepared["actual_cost"],
		"effective_cost": prepared["effective_cost"],
		"base_cost": prepared["base_cost"],
		"card_instance_id": command.instance_id,
		"card_id": definition.id,
		"card_category": definition.card_category,
		"owner_hero_id": definition.owner_hero_id,
		"destination": destination,
		"source_effect": ContextsScript.snapshot(prepared["context"]["source_effect"]),
	}
	if int(prepared["actual_cost"]) > 0:
		var spend_payload: Dictionary = event_payload.duplicate(true)
		spend_payload["source_side"] = "ally"
		var spent: Dictionary = _ports.call_action("emit_content_event", {
			"event_id": "skillPointSpent",
			"payload": spend_payload,
		})
		if not spent["ok"]:
			return CombatPortsScript.fail(
				"player card SP-spent event failed after card/effect commit: %s" % spent["error"]
			)
	var emitted: Dictionary = _ports.call_action("emit_content_event", {
		"event_id": event_id,
		"payload": event_payload,
	})
	if not emitted["ok"]:
		return CombatPortsScript.fail(
			"player card success event failed after card/effect commit: %s" % emitted["error"]
		)

	var energy_changes: Array[Dictionary] = []
	var energy_amount := 0
	if definition.card_category == CardDefinitionScript.CATEGORY_FREE:
		energy_amount = 5 + prepared["actual_cost"] * 5
		var team_result: Dictionary = _energy_coordinator.apply_to_all_deployed(energy_amount, {
			"kind": "card_play", "instance_id": command.instance_id,
			"card_id": definition.id, "actual_cost": prepared["actual_cost"],
		})
		if not team_result["ok"]:
			return CombatPortsScript.fail(
				"player free-card energy failed after card/effect commit: %s" % team_result["error"]
			)
		energy_changes = team_result["value"]
	elif definition.card_category == CardDefinitionScript.CATEGORY_EXCLUSIVE:
		energy_amount = 10 + prepared["actual_cost"] * 10
		var owner_result: Dictionary = _energy_coordinator.apply_energy({
			"hero_id": definition.owner_hero_id,
			"amount": energy_amount,
			"source": {
				"kind": "card_play", "instance_id": command.instance_id,
				"card_id": definition.id, "actual_cost": prepared["actual_cost"],
			},
		})
		if not owner_result["ok"]:
			return CombatPortsScript.fail(
				"player exclusive-card energy failed after card/effect commit: %s" % owner_result["error"]
			)
		energy_changes.append(owner_result["value"])
	return CombatPortsScript.ok({
		"event_id": event_id,
		"event": event_payload,
		"draw": null if draw_result == null else draw_result.to_dict(),
		"energy_amount": energy_amount,
		"energy_changes": energy_changes,
		"fatal": false,
	})


func _authority_error(command: Variant, instance: Variant) -> String:
	if instance.source_skill_id in FORBIDDEN_SOURCE_SKILL_IDS:
		return "player card authority excludes basicDamage"
	var definition: Variant = instance.definition
	if not _card_catalog.has(definition.id):
		return "card instance is absent from authoritative card catalog"
	var authority: Variant = _card_catalog[definition.id]
	if authority.to_dict() != definition.to_dict():
		return "card instance definition diverges from authoritative card catalog"
	if not command.expected_card_id.is_empty() and command.expected_card_id != definition.id:
		return "requested card id conflicts with authoritative card instance"
	if not command.expected_source_skill_id.is_empty() and command.expected_source_skill_id != definition.source_skill_id:
		return "requested source skill conflicts with authoritative card instance"
	return ""


func _source_name(definition: Variant) -> String:
	var extended_display := HeroCardCatalog.display(definition.id)
	if not extended_display.is_empty():
		return str(extended_display.get("name", ""))
	var errors: Array[String] = []
	var catalogs: Variant = _ports.service("catalogs", errors)
	if not errors.is_empty():
		return ""
	if definition.card_category == CardDefinitionScript.CATEGORY_FREE:
		var skill: Variant = catalogs.get("skills", {}).get(definition.source_skill_id)
		return skill.name if skill != null else ""
	var group := "ultimate" if definition.card_category == CardDefinitionScript.CATEGORY_ULTIMATE else "exclusive"
	var ability: Variant = catalogs.get("hero_abilities", {}).get(group, {}).get(definition.source_skill_id)
	return ability.name if ability != null else ""


func _player_hero(hero_id: Variant) -> Variant:
	for hero: Dictionary in _state["player_heroes"]:
		if hero["id"] == hero_id:
			return hero
	return null


func _unit_by_id(side: String, unit_id: Variant) -> Variant:
	var team: Array = _state["allies" if side == "ally" else "enemies"]
	for unit: Dictionary in team:
		if unit["id"] == unit_id:
			return unit
	return null


static func _request_error(value: Variant) -> String:
	if not _exact_object(value, RequestScript):
		return "player card play requires exact CardPlayRequest"
	if value.instance_id.strip_edges().is_empty():
		return "player card request instance_id must not be empty"
	if value.expected_card_id != value.expected_card_id.strip_edges():
		return "player card expected_card_id must be trimmed"
	if value.expected_source_skill_id != value.expected_source_skill_id.strip_edges():
		return "player card expected_source_skill_id must be trimmed"
	if value.owner_hero_id != null and not _stable_id(value.owner_hero_id):
		return "player card owner_hero_id must be null or a stable id"
	if value.target != null and typeof(value.target) != TYPE_DICTIONARY:
		return "player card target must be null or a Dictionary"
	return ""


static func _validate_catalog(value: Variant, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.is_empty():
		errors.append("card combat bridge card_catalog must be non-empty")
		return false
	for card_id: Variant in value:
		var definition: Variant = value[card_id]
		if (
			typeof(card_id) != TYPE_STRING
			or not definition is Resource
			or definition.get_script() != CardDefinitionScript
			or definition.id != card_id
		):
			errors.append("card combat bridge card_catalog contains an invalid entry")
			return false
		if definition.source_skill_id in FORBIDDEN_SOURCE_SKILL_IDS:
			errors.append("player card authority excludes basicDamage")
			return false
	return true


static func _failure(code: String, message: String, details: Dictionary = {}) -> RefCounted:
	return Result.new(false, code, message, details)


static func _exact_object(value: Variant, script: Script) -> bool:
	return typeof(value) == TYPE_OBJECT and value != null and value.get_script() == script


static func _exact_keys(value: Variant, keys: Array, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		errors.append("%s must have a canonical closed shape" % path)
		return false
	for key: String in keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
			return false
	return true


static func _stable_id(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT and value >= 0) or (
		typeof(value) == TYPE_STRING and not value.strip_edges().is_empty()
	)


static func _error_suffix(errors: Array[String]) -> String:
	return "" if errors.is_empty() else ": %s" % errors[0]
