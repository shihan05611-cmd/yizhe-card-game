class_name DormantShentongBattlePort
extends RefCounted

## Dormant M5-06 boundary only. No production composition root constructs this
## port until a later milestone explicitly chooses a player-facing shentong flow.

const CONFIG_KEYS := ["snapshot", "restore", "view", "actions"]
const ACTION_IDS := [
	"consume_player_turn",
	"heal_alive_allies",
	"extend_enemy_burn",
	"gain_hero_energy",
	"gain_skill_points",
	"mark_player_action",
	"cast_exclusive_free",
	"sacrifice_unit",
	"detect_battle_result",
	"settle_battle",
]

var _snapshot: Callable
var _restore: Callable
var _view: Callable
var _actions: Dictionary = {}
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	if not _exact_keys(config, CONFIG_KEYS):
		errors.append("dormant shentong battle port config must keep its canonical closed shape")
		return
	for callback_id in ["snapshot", "restore", "view"]:
		if not _valid_callable(config[callback_id]):
			errors.append("dormant shentong battle port.%s must be callable" % callback_id)
	if typeof(config["actions"]) != TYPE_DICTIONARY:
		errors.append("dormant shentong battle port.actions must be a Dictionary")
	else:
		for action_id: String in ACTION_IDS:
			if not _valid_callable(config["actions"].get(action_id)):
				errors.append("dormant shentong battle port action is missing: %s" % action_id)
		for action_id: Variant in config["actions"]:
			if typeof(action_id) != TYPE_STRING or action_id not in ACTION_IDS:
				errors.append("dormant shentong battle port has an unknown action")
	if not errors.is_empty():
		return
	_snapshot = config["snapshot"]
	_restore = config["restore"]
	_view = config["view"]
	_actions = config["actions"].duplicate(false)
	_valid = true


func is_valid() -> bool:
	return _valid


func snapshot(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _valid:
		errors.append("dormant shentong battle port is invalid")
		return {}
	var value: Variant = _snapshot.call()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("dormant shentong battle snapshot must be a Dictionary")
		return {}
	return value.duplicate(true)


func restore(value: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _valid or typeof(value) != TYPE_DICTIONARY:
		errors.append("dormant shentong battle restore requires a snapshot Dictionary")
		return false
	if _restore.call(value.duplicate(true)) != true:
		errors.append("dormant shentong battle restore was rejected")
		return false
	return true


func view(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _valid:
		errors.append("dormant shentong battle port is invalid")
		return {}
	var value: Variant = _view.call()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("dormant shentong battle view must be a Dictionary")
		return {}
	return value.duplicate(true)


func call_action(
	action_id: Variant,
	request: Variant = {},
	errors: Array[String] = [],
) -> Dictionary:
	errors.clear()
	if not _valid or typeof(action_id) != TYPE_STRING or not _actions.has(action_id):
		return _reject("unknown dormant shentong battle action", errors)
	if typeof(request) != TYPE_DICTIONARY:
		return _reject("dormant shentong battle action request must be a Dictionary", errors)
	var result: Variant = _actions[action_id].call(request.duplicate(true))
	if not is_result(result):
		return _reject("dormant shentong battle action returned a non-canonical result", errors)
	if result["ok"]:
		return ok(result["value"])
	return _reject(result["error"], errors)


static func ok(value: Variant = null) -> Dictionary:
	return {"ok": true, "value": value}


static func fail(message: Variant) -> Dictionary:
	var text := str(message).strip_edges()
	return {"ok": false, "error": text if not text.is_empty() else "dormant shentong action failed"}


static func is_result(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or typeof(value.get("ok")) != TYPE_BOOL:
		return false
	if value["ok"]:
		return value.size() == 2 and value.has("value")
	return (
		value.size() == 2 and typeof(value.get("error")) == TYPE_STRING
		and value["error"] == value["error"].strip_edges() and not value["error"].is_empty()
	)


static func _reject(message: String, errors: Array[String]) -> Dictionary:
	errors.append(message)
	return fail(message)


static func _valid_callable(value: Variant) -> bool:
	return typeof(value) == TYPE_CALLABLE and value.is_valid()


static func _exact_keys(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true
