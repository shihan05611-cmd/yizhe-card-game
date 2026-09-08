class_name RoguelikeRelicActionAdapter
extends RefCounted

const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const ContextsScript = preload("res://core/contexts.gd")
const StatsScript = preload("res://core/stats.gd")
const PieceAttackScript = preload("res://systems/combat/piece_attack.gd")
const TargetingRulesScript = preload("res://systems/targeting/targeting_rules.gd")

const PURSUIT_ID := "pursuit"
const BURN_ID := "burn"

var _state: Dictionary
var _runtime: Variant = null
var _ports: Variant = null
var _damage: Variant = null
var _buffs: Variant = null
var _burn_settlement: Variant = null
var _relic_system: Variant = null


func _init(state: Dictionary) -> void:
	_state = state


func action_map() -> Dictionary:
	return {
		"apply_pursuit_to_alive_allies": Callable(self, "_apply_pursuit_to_alive_allies"),
		"get_team_average_atk": Callable(self, "_get_team_average_atk"),
		"get_buff_stacks": Callable(self, "_get_buff_stacks"),
		"deal_relic_damage_to_all_enemies": Callable(self, "_deal_relic_damage_to_all_enemies"),
		"spread_burn_on_enemy_death": Callable(self, "_spread_burn_on_enemy_death"),
		"trigger_strongest_ally_pursuit": Callable(self, "_trigger_strongest_ally_pursuit"),
		"apply_relic_damage": Callable(self, "_apply_relic_damage"),
		"heal": Callable(self, "_heal"),
		"gain_skill_points": Callable(self, "_gain_skill_points"),
		"apply_burn": Callable(self, "_apply_burn"),
		"heal_alive_allies": Callable(self, "_heal_alive_allies"),
	}


func bind_runtime(runtime: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if runtime == null or not runtime.has_method("component"):
		errors.append("relic action adapter requires a BattleRuntime")
		return false
	_runtime = runtime
	_ports = runtime.component("ports", errors)
	if errors.is_empty():
		_damage = runtime.component("damage", errors)
	if errors.is_empty():
		_buffs = runtime.component("buffs", errors)
	if errors.is_empty():
		_burn_settlement = runtime.component("burn_settlement", errors)
	if errors.is_empty():
		_relic_system = runtime.component("relic_system", errors)
	if not errors.is_empty():
		_runtime = null
		_ports = null
		_damage = null
		_buffs = null
		_burn_settlement = null
		_relic_system = null
		return false
	return true


func _apply_pursuit_to_alive_allies(stacks: Variant) -> Variant:
	if not _ready():
		return _failure("relic action adapter is not bound")
	var errors: Array[String] = []
	for ally: Dictionary in _state["allies"]:
		if ally["alive"] and not _buffs.apply_unit(ally, PURSUIT_ID, stacks, null, errors):
			return _failure("relic pursuit application failed%s" % _error_suffix(errors))
	return true


func _get_team_average_atk(side: Variant) -> float:
	return StatsScript.team_average_atk(_state, side)


func _get_buff_stacks(target: Variant, buff_id: Variant) -> int:
	if not _ready() or typeof(target) != TYPE_DICTIONARY or typeof(buff_id) != TYPE_STRING:
		return 0
	return _buffs.get_unit_stacks(target, buff_id)


func _deal_relic_damage_to_all_enemies(
	raw: Variant,
	source_id: Variant,
	source_name: Variant,
) -> Variant:
	if not _ready():
		return _failure("relic action adapter is not bound")
	for enemy: Dictionary in _state["enemies"].duplicate():
		if not enemy["alive"]:
			continue
		var result: Variant = _apply_relic_damage(enemy, raw, source_id, source_name)
		if typeof(result) == TYPE_DICTIONARY and result.get("ok") == false:
			return result
	return true


func _spread_burn_on_enemy_death(dead_enemy: Variant) -> Variant:
	if not _ready() or typeof(dead_enemy) != TYPE_DICTIONARY:
		return _failure("relic burn spread requires a bound runtime and dead enemy")
	var stacks: int = _buffs.get_unit_stacks(dead_enemy, BURN_ID)
	var remaining: Array = _state["enemies"].filter(func(enemy: Dictionary) -> bool:
		return enemy["alive"]
	)
	if stacks <= 0 or remaining.is_empty():
		return true
	var each: int = maxi(0, stacks / remaining.size())
	if each <= 0:
		return true
	var errors: Array[String] = []
	for enemy: Dictionary in remaining:
		if not _buffs.apply_unit(enemy, BURN_ID, each, null, errors):
			return _failure("relic burn spread application failed%s" % _error_suffix(errors))
	_burn_settlement.settle(remaining, false, errors)
	if not errors.is_empty():
		return _failure("relic burn spread settlement failed%s" % _error_suffix(errors))
	var logged: Dictionary = _ports.call_action("log", {
		"message": "余烬风暴触发：灼烧扩散。", "class": "warn",
	})
	return true if logged["ok"] else _failure(logged["error"])


func _trigger_strongest_ally_pursuit(preferred_target: Variant) -> Variant:
	if not _ready():
		return _failure("relic action adapter is not bound")
	var attackers: Array = _state["allies"].filter(func(ally: Dictionary) -> bool:
		return ally["alive"]
	)
	attackers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if float(left["atk"]) != float(right["atk"]):
			return float(left["atk"]) > float(right["atk"])
		return left["id"] < right["id"]
	)
	if attackers.is_empty():
		return true
	var attacker: Dictionary = attackers[0]
	var errors: Array[String] = []
	var target: Variant = preferred_target
	if typeof(target) != TYPE_DICTIONARY or not target.get("alive", false):
		target = TargetingRulesScript.lowest_hp_percent_lockable(_state, "enemy", errors)
	if not errors.is_empty():
		return _failure("relic pursuit target selection failed%s" % _error_suffix(errors))
	if target == null:
		return true
	if not _buffs.apply_unit(attacker, PURSUIT_ID, 1, null, errors):
		return _failure("relic pursuit application failed%s" % _error_suffix(errors))
	if _buffs.consume_unit(attacker, PURSUIT_ID, 1, errors) != 1:
		return _failure("relic pursuit consumption failed%s" % _error_suffix(errors))
	var growth: Variant = _runtime.component("growth_port", errors)
	var permanent_buffs: Array = [] if not errors.is_empty() else growth.snapshot(errors)
	if not errors.is_empty():
		return _failure("relic pursuit growth snapshot failed%s" % _error_suffix(errors))
	var effect := ContextsScript.create_effect_context({
		"source_type": "pursuit", "source_id": "pursuit", "source_name": "追击",
		"source_side": "ally", "source_actor_id": attacker["id"],
		"counts_as_attack": true,
	}, errors)
	if not errors.is_empty():
		return _failure("relic pursuit context failed%s" % _error_suffix(errors))
	var result: Dictionary = PieceAttackScript.execute({
		"state": _state,
		"attacker_side": "ally", "attacker_id": attacker["id"], "attacker_slot": attacker["slot"],
		"forced_target_side": target["side"], "forced_target_id": target["id"], "forced_target_slot": target["slot"],
		"attack_name": "追击", "damage_multiplier": 0.0,
		"trigger_extra_action": false, "trigger_pursuit": false,
		"trigger_banner_action": false, "damage_kind_override": "pursuit",
		"source_effect": effect, "permanent_buffs": permanent_buffs,
		"relic_system": _relic_system,
	}, _ports)
	return true if result["ok"] else _failure(result["error"])


func _apply_relic_damage(
	target: Variant,
	raw: Variant,
	source_id: Variant,
	source_name: Variant,
) -> Variant:
	if not _ready() or typeof(target) != TYPE_DICTIONARY:
		return _failure("relic damage requires a bound runtime and unit target")
	var errors: Array[String] = []
	var effect := _relic_effect(source_id, source_name, errors)
	if not errors.is_empty():
		return _failure("relic damage effect context failed%s" % _error_suffix(errors))
	var context := ContextsScript.create_damage_context({
		"target_id": target["id"], "raw_amount": raw,
		"category": ContextsScript.DAMAGE_CATEGORY["DIRECT"], "effect": effect,
		"dealer_type": "relic", "dealer_name": str(source_name), "dealer_id": 0,
		"attacker_unit_id": 0, "can_crit": false, "crit_rate": 0.0,
		"guaranteed_crit": false, "can_block": true,
	}, errors)
	if not errors.is_empty():
		return _failure("relic damage context failed%s" % _error_suffix(errors))
	var result: Dictionary = _damage.apply(target, context, {}, errors)
	if result.is_empty() or not errors.is_empty():
		return _failure("relic damage failed%s" % _error_suffix(errors))
	return result


func _heal(
	target: Variant,
	amount: Variant,
	source_id: Variant,
	source_name: Variant,
) -> Variant:
	if not _ready() or typeof(target) != TYPE_DICTIONARY:
		return _failure("relic heal requires a bound runtime and unit target")
	if not target.get("alive", false):
		return 0.0
	var effective: float = _relic_system.get_effective_healing_amount(amount, target)
	if effective <= 0.0:
		return 0.0
	var old_hp := float(target["hp"])
	var new_hp := minf(float(target["max_hp"]), _format(old_hp + effective))
	var healed := _format(new_hp - old_hp)
	target["hp"] = new_hp
	if healed <= 0.0:
		return 0.0
	var effect_errors: Array[String] = []
	var effect := _relic_effect(source_id, source_name, effect_errors)
	if not effect_errors.is_empty():
		return _failure("relic heal effect context failed%s" % _error_suffix(effect_errors))
	var recorded: Dictionary = _ports.call_action("record_heal", {
		"target_id": target["id"], "target_side": target["side"], "amount": healed,
		"source_name": str(source_name), "source_effect": effect,
		"old_hp": old_hp, "new_hp": new_hp,
	})
	return healed if recorded["ok"] else _failure(recorded["error"])


func _gain_skill_points(amount: Variant) -> Variant:
	if not _ready() or not _finite_number(amount):
		return _failure("relic skill point gain requires a finite amount")
	_state["sp"] = clampf(float(_state["sp"]) + float(amount), 0.0, float(_state["sp_max"]))
	return true


func _apply_burn(target: Variant, stacks: Variant, duration: Variant = null) -> Variant:
	if not _ready() or typeof(target) != TYPE_DICTIONARY:
		return _failure("relic burn requires a bound runtime and unit target")
	if not target.get("alive", false):
		return true
	var errors: Array[String] = []
	if not _buffs.apply_unit(target, BURN_ID, stacks, duration, errors):
		return _failure("relic burn application failed%s" % _error_suffix(errors))
	return true


func _heal_alive_allies(
	ratio: Variant,
	source_id: Variant,
	source_name: Variant,
) -> Variant:
	if not _ready() or not _finite_number(ratio):
		return _failure("relic ally heal requires a bound runtime and finite ratio")
	for ally: Dictionary in _state["allies"]:
		if not ally["alive"]:
			continue
		var result: Variant = _heal(
			ally, float(ally["max_hp"]) * float(ratio), source_id, source_name,
		)
		if typeof(result) == TYPE_DICTIONARY and result.get("ok") == false:
			return result
	return true


func _relic_effect(source_id: Variant, source_name: Variant, errors: Array[String]) -> Dictionary:
	return ContextsScript.create_effect_context({
		"source_type": "relic", "source_id": source_id, "source_name": str(source_name),
		"source_side": "ally", "source_actor_id": 0,
	}, errors)


func _ready() -> bool:
	return (
		_runtime != null and _ports != null and _damage != null and _buffs != null
		and _burn_settlement != null and _relic_system != null
	)


static func _failure(message: Variant) -> Dictionary:
	return CombatPortsScript.fail(message)


static func _error_suffix(errors: Array[String]) -> String:
	return "" if errors.is_empty() else ": %s" % errors[0]


static func _format(value: float) -> float:
	return maxf(0.0, roundf(value * 10.0) / 10.0)


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))
