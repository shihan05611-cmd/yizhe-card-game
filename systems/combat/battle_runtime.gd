class_name BattleRuntime
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const DamagePipelineScript = preload("res://core/damage.gd")
const DeterministicRngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const EffectRegistryScript = preload("res://systems/combat/effect_registry.gd")
const RoundResolverScript = preload("res://systems/combat/round_resolver.gd")
const BuffSystemScript = preload("res://systems/buffs/buff_system.gd")
const BurnSettlementScript = preload("res://systems/buffs/burn.gd")
const PermanentBuffStoreScript = preload("res://systems/buffs/permanent_buff_store.gd")
const FreeSkillEffectsScript = preload("res://systems/effects/free_skill_effects.gd")
const FlameFateEffectsScript = preload("res://systems/effects/hero_effects_flame_fate.gd")
const MarshalFistEffectsScript = preload("res://systems/effects/hero_effects_marshal_fist.gd")
const SiegePuppetShadowEffectsScript = preload("res://systems/effects/hero_effects_siege_puppet_shadow.gd")
const GrowthPortScript = preload("res://systems/growth/growth_port.gd")
const HookDispatcherScript = preload("res://systems/relics/hook_dispatcher.gd")
const RelicSystemScript = preload("res://systems/relics/relic_system.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")
const CardCombatBridgeScript = preload("res://systems/cards/card_combat_bridge.gd")
const PlayerEnergyCoordinatorScript = preload("res://systems/cards/player_energy_coordinator.gd")

## Pure M2 composition root. It owns one authoritative object graph for one live
## battle and one injected run draft. No Node, Autoload, persistence, or M3
## player-action state is introduced here.

const CONFIG_KEYS := [
	"state", "run_state", "catalogs", "tuning",
	"combat_rng", "enemy_policy_rng", "actions", "relic_actions",
	"get_owned_relic_ids", "format_damage", "get_block_rate",
	"get_damage_multiplier", "on_damage_event", "on_death",
	"on_buff_event", "on_burn_settled", "on_hook_error",
]
const CALLBACK_KEYS := [
	"get_owned_relic_ids", "format_damage", "get_block_rate",
	"get_damage_multiplier", "on_damage_event", "on_death",
	"on_buff_event", "on_burn_settled", "on_hook_error",
]
const COMPONENT_IDS := [
	"state", "run_state", "catalogs", "tuning", "combat_rng",
	"enemy_policy_rng", "registry", "ports", "damage", "buffs",
	"burn_settlement", "hook_dispatcher", "relic_system", "growth_port",
	"card_bridge", "player_energy_coordinator",
]
const DAMAGE_HOOK_EVENTS := [
	"unit_damaged", "unit_blocked", "unit_died", "hp_threshold_crossed",
]

var _state: Dictionary
var _run_state: Dictionary
var _catalogs: Dictionary
var _tuning: Dictionary
var _combat_rng: Variant
var _enemy_policy_rng: Variant
var _external_actions: Dictionary = {}
var _on_damage_event: Callable
var _on_death: Callable
var _on_buff_event: Callable
var _on_burn_settled: Callable

var _registry: Variant = null
var _ports: Variant = null
var _damage: Variant = null
var _buffs: Variant = null
var _burn_settlement: Variant = null
var _hook_dispatcher: Variant = null
var _relic_system: Variant = null
var _growth_port: Variant = null
var _card_bridge: Variant = null
var _player_energy_coordinator: Variant = null
var _callback_errors: Array[String] = []
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	var prepared: Dictionary = _preflight(config, errors)
	if prepared.is_empty():
		return

	# Keep the caller-owned live authorities by identity. Catalog services are
	# snapshotted only by the frozen CombatPorts boundary, as designed there.
	_state = config["state"]
	_run_state = config["run_state"]
	_catalogs = config["catalogs"]
	_tuning = config["tuning"]
	_combat_rng = config["combat_rng"]
	_enemy_policy_rng = config["enemy_policy_rng"]
	_external_actions = config["actions"].duplicate(false)
	_on_damage_event = config["on_damage_event"]
	_on_death = config["on_death"]
	_on_buff_event = config["on_buff_event"]
	_on_burn_settled = config["on_burn_settled"]

	_registry = EffectRegistryScript.new()
	if not _registry.merge([
		FreeSkillEffectsScript.handler_map(), FlameFateEffectsScript.handler_map(),
		MarshalFistEffectsScript.handler_map(), SiegePuppetShadowEffectsScript.handler_map(),
	], errors):
		return
	if _registry.handler_ids() != prepared["handler_ids"]:
		errors.append("effect registry ids diverged from the validated M1 authority")
		return

	_hook_dispatcher = HookDispatcherScript.new({
		"event_catalog": _catalogs["events"],
		"on_error": config["on_hook_error"],
	}, errors)
	if not _exact_valid(_hook_dispatcher, HookDispatcherScript):
		_append_missing_error(errors, "failed to construct exact HookDispatcher")
		return

	var composed_relic_actions: Dictionary = config["relic_actions"].duplicate(false)
	composed_relic_actions["gain_lowest_energy_active_hero_energy"] = Callable(
		self, "_relic_gain_lowest_player_energy"
	)
	composed_relic_actions["gain_random_active_hero_energy"] = Callable(
		self, "_relic_gain_random_player_energy"
	)
	_relic_system = RelicSystemScript.new({
		"catalog": _catalogs["relics"],
		"dispatcher": _hook_dispatcher,
		"get_owned_relic_ids": config["get_owned_relic_ids"],
		"actions": composed_relic_actions,
	}, errors)
	if not _exact_valid(_relic_system, RelicSystemScript):
		_append_missing_error(errors, "failed to construct exact RelicSystem")
		return

	_damage = DamagePipelineScript.new({
		"random": Callable(self, "_next_combat"),
		"format": config["format_damage"],
		"get_block_rate": config["get_block_rate"],
		"get_damage_multiplier": config["get_damage_multiplier"],
		"on_event": Callable(self, "_forward_damage_event"),
		"on_death": _on_death,
		"record_damage": Callable(self, "_record_damage"),
	}, errors)
	if not _exact_valid(_damage, DamagePipelineScript):
		_append_missing_error(errors, "failed to construct exact DamagePipeline")
		return

	# BuffSystem starts a battle by publishing fresh side holders. Preflight
	# requires both injected holders empty, so this successful-only publication
	# cannot erase already committed battle Buffs.
	_buffs = BuffSystemScript.new({
		"state": _state, "catalog": _catalogs["buffs"],
		"on_event": _on_buff_event,
	}, errors)
	if not _exact_valid(_buffs, BuffSystemScript):
		_append_missing_error(errors, "failed to construct exact BuffSystem")
		return

	_burn_settlement = BurnSettlementScript.new({
		"buff_system": _buffs,
		"damage_per_stack": prepared["burn_damage_per_stack"],
		"apply_damage_context": Callable(self, "_apply_burn_damage"),
		"on_settled": _on_burn_settled,
	}, errors)
	if not _exact_valid(_burn_settlement, BurnSettlementScript):
		_append_missing_error(errors, "failed to construct exact BurnSettlement")
		return

	_growth_port = GrowthPortScript.new({
		"run_state": _run_state, "catalog": _catalogs["buffs"],
		"valid_hero_ids": prepared["valid_hero_ids"],
	}, errors)
	if not _exact_valid(_growth_port, GrowthPortScript):
		_append_missing_error(errors, "failed to construct exact GrowthPort")
		return

	var composed_actions: Dictionary = _external_actions.duplicate(false)
	composed_actions["emit_content_event"] = Callable(self, "_emit_content_event")
	composed_actions["apply_player_energy"] = Callable(self, "_apply_player_energy")
	for action_id: String in _growth_port.action_map():
		composed_actions[action_id] = _growth_port.action_map()[action_id]
	_ports = CombatPortsScript.new({
		"actions": composed_actions,
		"services": {
			"combat_rng": _combat_rng, "enemy_policy_rng": _enemy_policy_rng,
			"damage": _damage, "buffs": _buffs, "tuning": _tuning,
			"catalogs": _catalogs, "relics": _relic_system,
		},
	}, errors)
	if not _exact_valid(_ports, CombatPortsScript):
		_append_missing_error(errors, "failed to construct exact CombatPorts")
		return
	_valid = true


func is_valid() -> bool:
	return _valid


func handler_ids() -> Array[String]:
	return _registry.handler_ids() if _valid else []


func component(id: Variant, errors: Array[String] = []) -> Variant:
	errors.clear()
	if not _valid:
		errors.append("battle runtime config is invalid")
		return null
	if typeof(id) != TYPE_STRING or id not in COMPONENT_IDS:
		errors.append("unknown battle runtime component id: %s" % str(id))
		return null
	match id:
		"state": return _state
		"run_state": return _run_state
		"catalogs": return _catalogs
		"tuning": return _tuning
		"combat_rng": return _combat_rng
		"enemy_policy_rng": return _enemy_policy_rng
		"registry": return _registry
		"ports": return _ports
		"damage": return _damage
		"buffs": return _buffs
		"burn_settlement": return _burn_settlement
		"hook_dispatcher": return _hook_dispatcher
		"relic_system": return _relic_system
		"growth_port": return _growth_port
		"card_bridge": return _card_bridge
		"player_energy_coordinator": return _player_energy_coordinator
	return null


func install_player_card_runtime(config: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _valid:
		errors.append("battle runtime config is invalid")
		return false
	if _card_bridge != null:
		errors.append("player card runtime is already installed")
		return false
	if not _exact_keys(config, ["hand_runtime", "card_catalog"], "player card runtime config", errors):
		return false
	var coordinator := PlayerEnergyCoordinatorScript.new({
		"state": _state,
		"hand_runtime": config["hand_runtime"],
		"card_catalog": config["card_catalog"],
	}, errors)
	if (
		not _exact_valid(coordinator, PlayerEnergyCoordinatorScript)
		or not errors.is_empty()
	):
		_append_missing_error(errors, "failed to construct exact PlayerEnergyCoordinator")
		return false
	var bridge := CardCombatBridgeScript.new({
		"state": _state,
		"hand_runtime": config["hand_runtime"],
		"card_catalog": config["card_catalog"],
		"registry": _registry,
		"ports": _ports,
		"relic_system": _relic_system,
		"energy_coordinator": coordinator,
	}, errors)
	if not _exact_valid(bridge, CardCombatBridgeScript) or not errors.is_empty():
		_append_missing_error(errors, "failed to construct exact CardCombatBridge")
		return false
	_player_energy_coordinator = coordinator
	_card_bridge = bridge
	return true


func play_player_card(request: Variant) -> RefCounted:
	if _card_bridge == null:
		return CardCombatBridgeScript.Result.new(
			false,
			CardCombatBridgeScript.Result.INVALID_ARGUMENT,
			"player card runtime is not installed",
		)
	return _card_bridge.play(request)


func inspect_player_card(request: Variant) -> RefCounted:
	if _card_bridge == null:
		return CardCombatBridgeScript.Result.new(
			false,
			CardCombatBridgeScript.Result.INVALID_ARGUMENT,
			"player card runtime is not installed",
		)
	return _card_bridge.inspect_playability(request)


func apply_player_energy(request: Variant) -> Dictionary:
	return _apply_player_energy(request)


func resolve_round() -> Dictionary:
	if not _valid:
		return CombatPortsScript.fail("battle runtime config is invalid")
	_callback_errors.clear()
	var snapshot_errors: Array[String] = []
	var permanent_buffs: Array = _growth_port.snapshot(snapshot_errors)
	if not snapshot_errors.is_empty():
		return CombatPortsScript.fail(
			"battle runtime permanent Buff snapshot failed: %s" % snapshot_errors[0]
		)
	var result: Dictionary = RoundResolverScript.resolve({
		"state": _state, "registry": _registry,
		"burn_settlement": _burn_settlement,
		"permanent_buffs": permanent_buffs,
		"relic_system": _relic_system,
		"hook_dispatcher": _hook_dispatcher,
	}, _ports)
	if not _callback_errors.is_empty():
		return CombatPortsScript.fail(
			"battle runtime callback failed after sequential commits: %s; round_result=%s"
			% [_callback_errors[0], str(result)]
		)
	return result


func _next_combat() -> Variant:
	return _combat_rng.next()


func _forward_damage_event(event_id: String, payload: Dictionary) -> void:
	_on_damage_event.call(event_id, payload.duplicate(true))
	if event_id not in DAMAGE_HOOK_EVENTS:
		return
	var hook_errors: Array[String] = []
	_hook_dispatcher.dispatch(event_id, payload, hook_errors)
	if not hook_errors.is_empty():
		_callback_errors.append("damage hook dispatch failed: %s" % hook_errors[0])


func _record_damage(payload: Dictionary) -> void:
	var errors: Array[String] = []
	var result: Dictionary = _ports.call_action("record_damage", payload, errors)
	if not result["ok"]:
		_callback_errors.append(
			"record_damage failed: %s" % (errors[0] if not errors.is_empty() else result["error"])
		)


func _apply_burn_damage(unit: Dictionary, context: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return _damage.apply(unit, context, {"damage_kind": "burn"}, errors)


func _emit_content_event(request: Dictionary) -> Dictionary:
	if request.size() != 2 or not request.has("event_id") or not request.has("payload"):
		return CombatPortsScript.fail("content event request must have event_id and payload")
	var external: Variant = _external_actions["emit_content_event"].call(request)
	if not CombatPortsScript.is_result(external):
		return CombatPortsScript.fail("external emit_content_event returned a non-canonical result")
	if not external["ok"]:
		return CombatPortsScript.fail(external["error"])
	var hook_errors: Array[String] = []
	_hook_dispatcher.dispatch(request["event_id"], request["payload"], hook_errors)
	if not hook_errors.is_empty():
		return CombatPortsScript.fail("content hook dispatch failed: %s" % hook_errors[0])
	return CombatPortsScript.ok(external["value"])


func _apply_player_energy(request: Variant) -> Dictionary:
	if _player_energy_coordinator != null:
		return _player_energy_coordinator.apply_energy(request)
	# M2-only runtimes retain their legacy clamp until M3 installs the card
	# authority. This keeps enemy and existing headless callers unchanged.
	if (
		typeof(request) != TYPE_DICTIONARY
		or request.size() != 3
		or not request.has("hero_id")
		or not request.has("amount")
		or not request.has("source")
		or not _finite_number(request["amount"])
		or float(request["amount"]) < 0.0
	):
		return CombatPortsScript.fail("legacy player energy request is invalid")
	for hero: Dictionary in _state["player_heroes"]:
		if hero["id"] == request["hero_id"]:
			var before := float(hero["energy"])
			hero["energy"] = minf(
				float(hero["max_energy"]),
				before + float(request["amount"]),
			)
			return CombatPortsScript.ok({
				"hero_id": hero["id"], "before": before,
				"amount": float(request["amount"]), "after": hero["energy"],
				"threshold_crossed": false, "generated_card": null,
				"source": request["source"].duplicate(true) if request["source"] is Dictionary else {},
			})
	return CombatPortsScript.fail("legacy player energy hero is unknown")


func _relic_gain_lowest_player_energy(amount: Variant) -> Dictionary:
	var deployed: Array[Dictionary] = _deployed_player_heroes()
	if deployed.is_empty():
		return CombatPortsScript.ok(null)
	deployed.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left["energy"]) != float(right["energy"]):
			return float(left["energy"]) < float(right["energy"])
		return _stable_id_less(left["id"], right["id"])
	)
	return _apply_player_energy({
		"hero_id": deployed[0]["id"], "amount": amount,
		"source": {"kind": "relic", "effect": "gain_lowest_energy_active_hero_energy"},
	})


func _relic_gain_random_player_energy(
	amount: Variant,
	source_id: Variant,
	source_name: Variant,
) -> Dictionary:
	var deployed: Array[Dictionary] = _deployed_player_heroes()
	if deployed.is_empty():
		return CombatPortsScript.ok(null)
	deployed.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _stable_id_less(left["id"], right["id"])
	)
	var index: int = _combat_rng.int_range(0, deployed.size() - 1)
	return _apply_player_energy({
		"hero_id": deployed[index]["id"], "amount": amount,
		"source": {
			"kind": "relic", "effect": "gain_random_active_hero_energy",
			"source_id": source_id, "source_name": source_name,
		},
	})


func _deployed_player_heroes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hero: Dictionary in _state["player_heroes"]:
		if hero["deployed"]:
			result.append(hero)
	return result


static func _stable_id_less(left: Variant, right: Variant) -> bool:
	return left < right if typeof(left) == typeof(right) else typeof(left) < typeof(right)


static func _preflight(config: Variant, errors: Array[String]) -> Dictionary:
	if not _exact_keys(config, CONFIG_KEYS, "battle runtime config", errors):
		return {}
	for callback_id: String in CALLBACK_KEYS:
		if not _valid_callable(config[callback_id]):
			errors.append("%s must be an injected valid Callable" % callback_id)
	if not errors.is_empty():
		return {}

	if not _exact_rng(config["combat_rng"]):
		errors.append("combat_rng must be an exact M0 DeterministicRng")
	if not _exact_rng(config["enemy_policy_rng"]):
		errors.append("enemy_policy_rng must be an exact M0 DeterministicRng")
	if is_same(config["combat_rng"], config["enemy_policy_rng"]):
		errors.append("combat_rng and enemy_policy_rng must be distinct streams")
	if not errors.is_empty():
		return {}

	var actions: Variant = config["actions"]
	if typeof(actions) != TYPE_DICTIONARY:
		errors.append("actions must be an injected Dictionary")
		return {}
	for growth_action_id: String in [
		GrowthPortScript.ACTION_PREVIEW, GrowthPortScript.ACTION_STAGE,
		GrowthPortScript.ACTION_GET_STACKS, GrowthPortScript.ACTION_SNAPSHOT,
	]:
		if actions.has(growth_action_id):
			errors.append("external action collides with owned GrowthPort action: %s" % growth_action_id)
	for action_id: String in CombatPortsScript.REQUIRED_ACTION_IDS:
		if not _valid_callable(actions.get(action_id)):
			errors.append("actions.%s must be an injected valid Callable" % action_id)
	for action_id: Variant in actions:
		if typeof(action_id) != TYPE_STRING or action_id not in CombatPortsScript.REQUIRED_ACTION_IDS:
			errors.append("unknown external combat action id: %s" % str(action_id))
	if not errors.is_empty():
		return {}

	var relic_actions: Variant = config["relic_actions"]
	if typeof(relic_actions) != TYPE_DICTIONARY:
		errors.append("relic_actions must be an injected Dictionary")
		return {}
	for action_id: Variant in relic_actions:
		if (
			typeof(action_id) != TYPE_STRING or str(action_id).strip_edges().is_empty()
			or not _valid_callable(relic_actions[action_id])
		):
			errors.append("relic_actions must map non-empty ids to valid Callables")
	if not errors.is_empty():
		return {}

	var catalogs: Variant = config["catalogs"]
	if typeof(catalogs) != TYPE_DICTIONARY:
		errors.append("catalogs must be an injected M1 content Dictionary")
		return {}
	var catalog_errors: Array[String] = []
	var validated_catalog: Dictionary = ContentCatalogScript.build_from(catalogs, catalog_errors)
	if validated_catalog.is_empty() or not catalog_errors.is_empty():
		errors.append(
			"catalogs must be the complete M1 authority: %s"
			% (catalog_errors[0] if not catalog_errors.is_empty() else "validation returned empty")
		)
		return {}
	if typeof(config["tuning"]) != TYPE_DICTIONARY or not is_same(config["tuning"], catalogs["tuning"]):
		errors.append("tuning must be the exact catalogs.tuning Dictionary instance")
		return {}

	if not BattleStateScript.validate(config["state"], errors):
		var state_error := errors[0] if not errors.is_empty() else "unknown state validation error"
		errors.clear()
		errors.append("state must be a canonical BattleState: %s" % state_error)
		return {}
	if not config["state"]["side_buffs"]["ally"].is_empty() or not config["state"]["side_buffs"]["enemy"].is_empty():
		errors.append("battle runtime must be constructed before side Buffs are committed")
		return {}
	if typeof(config["run_state"]) != TYPE_DICTIONARY or typeof(config["run_state"].get("permanent_buffs")) != TYPE_ARRAY:
		errors.append("run_state must be the injected battle draft with permanent_buffs Array")
		return {}

	var valid_hero_ids: Array = []
	for hero: Dictionary in config["state"]["player_heroes"]:
		valid_hero_ids.append(hero["id"])
	var permanent_errors: Array[String] = []
	var normalized: Array[Dictionary] = PermanentBuffStoreScript.normalize_instances(
		config["run_state"]["permanent_buffs"], catalogs["buffs"],
		valid_hero_ids, permanent_errors,
	)
	if not permanent_errors.is_empty():
		errors.append("run_state permanent Buffs are invalid: %s" % permanent_errors[0])
		return {}
	if normalized != config["run_state"]["permanent_buffs"]:
		errors.append("run_state permanent Buffs must already be canonical")
		return {}

	var expected_ids: Array[String] = []
	for definition: Variant in catalogs["skills"].values():
		expected_ids.append(definition.effect_id)
	for group: String in ["exclusive", "ultimate"]:
		for definition: Variant in catalogs["hero_abilities"][group].values():
			expected_ids.append(definition.handler_id)
	expected_ids.sort()
	if expected_ids.size() != 29 or _has_duplicate(expected_ids):
		errors.append("M1 effect authority must expose 29 unique handler ids")
		return {}
	var authored_ids: Array[String] = []
	for handler_map: Dictionary in [
		FreeSkillEffectsScript.handler_map(), FlameFateEffectsScript.handler_map(),
		MarshalFistEffectsScript.handler_map(), SiegePuppetShadowEffectsScript.handler_map(),
	]:
		for effect_id: Variant in handler_map:
			if typeof(effect_id) == TYPE_STRING:
				authored_ids.append(effect_id)
	authored_ids.sort()
	if authored_ids != expected_ids or _has_duplicate(authored_ids):
		errors.append("authored M2 handler maps must exactly equal all M1 effect ids")
		return {}

	var burn_definition: Variant = config["tuning"].get("burnTickPerStack")
	if not burn_definition is Resource or burn_definition.get_script() != TuningValueDefinition:
		errors.append("tuning.burnTickPerStack must be an M1 TuningValueDefinition")
		return {}
	var burn_value: Variant = burn_definition.value
	if not _finite_number(burn_value) or float(burn_value) < 0.0:
		errors.append("burnTickPerStack must be non-negative and finite")
		return {}
	return {
		"handler_ids": expected_ids,
		"valid_hero_ids": valid_hero_ids,
		"burn_damage_per_stack": float(burn_value),
	}


static func _exact_rng(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and value != null and value.get_script() == DeterministicRngScript


static func _exact_valid(value: Variant, script: Script) -> bool:
	return (
		typeof(value) == TYPE_OBJECT and value != null and value.get_script() == script
		and value.has_method("is_valid") and value.is_valid() == true
	)


static func _valid_callable(value: Variant) -> bool:
	return typeof(value) == TYPE_CALLABLE and value.is_valid()


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _has_duplicate(values: Array[String]) -> bool:
	for index in values.size():
		if index > 0 and values[index] == values[index - 1]:
			return true
	return false


static func _exact_keys(value: Variant, keys: Array, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		errors.append("%s must have a canonical closed shape" % path)
		return false
	for key: String in keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			errors.append("%s contains an unknown field: %s" % [path, str(key)])
			return false
	return true


static func _append_missing_error(errors: Array[String], fallback: String) -> void:
	if errors.is_empty():
		errors.append(fallback)
