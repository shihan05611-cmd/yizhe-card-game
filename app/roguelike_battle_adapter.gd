class_name RoguelikeBattleAdapter
extends RefCounted

const ControllerScript = preload("res://app/battle_controller.gd")
const Result = preload("res://core/card_runtime_result.gd")

var _lifecycle: Variant
var _hand_manager: Node
var _controller: Variant = null
var _progress: Variant = null
var _settled := false


func _init(lifecycle: Variant, hand_manager: Node) -> void:
	_lifecycle = lifecycle
	_hand_manager = hand_manager


func start(errors: Array[String] = []) -> RefCounted:
	errors.clear()
	if _controller != null:
		return Result.new(false, Result.INVALID_ARGUMENT, "Run battle adapter is already started")
	if (
		_lifecycle == null
		or not _lifecycle.has_method("begin_current_battle")
		or _hand_manager == null
	):
		return Result.new(false, Result.INVALID_ARGUMENT, "Run battle adapter dependencies are invalid")
	var launch: Dictionary = _lifecycle.begin_current_battle(errors)
	if launch.is_empty():
		return Result.new(
			false, Result.INVALID_ARGUMENT,
			errors[0] if not errors.is_empty() else "Run battle launch was rejected",
		)
	_progress = launch["run_progress"]
	var candidate := ControllerScript.new(_hand_manager)
	var result: Variant = candidate.start(launch)
	if not result.ok:
		var cancel_errors: Array[String] = []
		_lifecycle.cancel_current_battle_launch(_progress, cancel_errors)
		_progress = null
		for message: String in cancel_errors:
			errors.append(message)
		return result
	_controller = candidate
	return result


func controller() -> Variant:
	return _controller


func is_settled() -> bool:
	return _settled


func settle_if_terminal(errors: Array[String] = []) -> bool:
	errors.clear()
	if _controller == null or _progress == null or _settled:
		return false
	var snapshot: Dictionary = _controller.settlement_snapshot()
	if snapshot.is_empty() or not snapshot["game_over"]:
		return false
	if not _lifecycle.settle_current_battle(
		_progress, snapshot["battle_result"], snapshot["allies"], errors,
	):
		return false
	_settled = true
	return true


func cancel_open_launch(errors: Array[String] = []) -> bool:
	errors.clear()
	if _progress == null or _settled:
		return false
	var cancelled: bool = _lifecycle.cancel_current_battle_launch(_progress, errors)
	if cancelled:
		_progress = null
	return cancelled
