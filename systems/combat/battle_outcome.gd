class_name BattleOutcome
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")

## Web checkGameOver uses two independent if statements. Therefore a
## simultaneous effective-unit wipe assigns lose first and then overwrites it
## with win. This is compatibility, not a new product ruling.
const CURRENT_WEB_COMPAT_SIMULTANEOUS_WIPE_IS_WIN := true
const RESULT_KEYS := ["status", "result", "committed"]


static func check(
	state: Variant,
	ports: Variant,
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _validate_inputs(state, ports, errors):
		return _fail(errors)
	if state["game_over"]:
		return CombatPortsScript.ok(_result("already_settled", state["battle_result"], true))

	var candidate: Variant = _candidate(state)
	if candidate == null:
		return CombatPortsScript.ok(_result("none", null, false))

	var resolved: Dictionary = ports.call_action("resolve_battle_end", {"result": candidate})
	if not resolved["ok"]:
		return CombatPortsScript.fail("battle outcome resolve rejected before state commit: %s" % resolved["error"])
	if not _explicitly_accepted(resolved["value"]):
		return CombatPortsScript.fail("battle outcome resolve did not explicitly accept %s before state commit" % candidate)

	# Commit immediately after the external settlement accepts. Any later failure
	# must leave this terminal state in place so a retry cannot settle twice.
	state["game_over"] = true
	state["battle_result"] = candidate
	var logged: Dictionary = ports.call_action("log", {
		"message": _message(candidate),
		"class": "bad" if candidate == "lose" else "ok",
	})
	if not logged["ok"]:
		return CombatPortsScript.fail(
			"battle outcome committed=%s; log failed after resolve acceptance: %s" % [candidate, logged["error"]]
		)
	var notified: Dictionary = ports.call_action("on_battle_resolved", {"result": candidate})
	if not notified["ok"]:
		return CombatPortsScript.fail(
			"battle outcome committed=%s; on_battle_resolved failed after resolve acceptance and log: %s" % [candidate, notified["error"]]
		)
	return CombatPortsScript.ok(_result("settled", candidate, true))


static func candidate(state: Variant, errors: Array[String] = []) -> Variant:
	errors.clear()
	if not BattleStateScript.validate(state, errors):
		return null
	if state["game_over"]:
		return state["battle_result"]
	return _candidate(state)


static func _candidate(state: Dictionary) -> Variant:
	var result: Variant = null
	if not _has_effective_unit(state["allies"]):
		result = "lose"
	# Deliberately independent to preserve current Web simultaneous-wipe=win.
	if not _has_effective_unit(state["enemies"]):
		result = "win"
	return result


static func _has_effective_unit(team: Array) -> bool:
	for unit: Dictionary in team:
		if unit["alive"] and not unit["is_puppet"]:
			return true
	return false


static func _explicitly_accepted(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	return (
		typeof(value) == TYPE_DICTIONARY
		and value.size() == 1
		and value.get("accepted") == true
	)


static func _message(result: String) -> String:
	if result == "lose":
		return "我方有效作战单位全灭（仅剩傀儡不计存活），战斗失败。"
	return "敌方有效作战单位全灭（傀儡不计存活），战斗胜利。"


static func _validate_inputs(state: Variant, ports: Variant, errors: Array[String]) -> bool:
	if not BattleStateScript.validate(state, errors):
		return false
	if (
		typeof(ports) != TYPE_OBJECT or ports == null
		or ports.get_script() != CombatPortsScript or ports.is_valid() != true
	):
		errors.append("battle outcome requires exact valid CombatPorts")
		return false
	return true


static func _result(status: String, result: Variant, committed: bool) -> Dictionary:
	var values := {"status": status, "result": result, "committed": committed}
	var closed := {}
	for key in RESULT_KEYS:
		closed[key] = values[key]
	return closed


static func _fail(errors: Array[String]) -> Dictionary:
	return CombatPortsScript.fail(errors[0] if not errors.is_empty() else "invalid battle outcome input")
