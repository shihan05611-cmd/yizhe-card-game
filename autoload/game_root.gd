extends Node

const BattleControllerScript = preload("res://app/battle_controller.gd")
const RoguelikeBattleAdapterScript = preload("res://app/roguelike_battle_adapter.gd")
const Result = preload("res://core/card_runtime_result.gd")

var _battle_controller: Variant = null
var _run_battle_adapter: Variant = null
var _run_lifecycle: Variant = null


func _ready() -> void:
	Signals.application_ready.emit()


func start_battle(config: Dictionary) -> Variant:
	if _battle_controller != null and _battle_controller.is_initialized():
		return Result.new(false, Result.INVALID_ARGUMENT, "a battle is already active")
	_battle_controller = BattleControllerScript.new(HandManager)
	_run_battle_adapter = null
	_run_lifecycle = null
	var result: Variant = _battle_controller.start(config)
	if result.ok:
		Signals.battle_started.emit(_battle_controller.view_model())
	else:
		_emit_fatal_if_present()
	return result


func start_roguelike_battle(lifecycle: Variant) -> Variant:
	if _battle_controller != null and _battle_controller.is_initialized():
		return Result.new(false, Result.INVALID_ARGUMENT, "a battle is already active")
	var adapter := RoguelikeBattleAdapterScript.new(lifecycle, HandManager)
	var errors: Array[String] = []
	var result: Variant = adapter.start(errors)
	if not result.ok:
		return result
	_run_battle_adapter = adapter
	_run_lifecycle = lifecycle
	_battle_controller = adapter.controller()
	Signals.battle_started.emit(_battle_controller.view_model())
	return result


func battle_view_model() -> Dictionary:
	return {} if _battle_controller == null else _battle_controller.view_model()


func play_card(instance_id: String) -> Variant:
	if _battle_controller == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle is not initialized")
	var result: Variant = _battle_controller.play_card(instance_id)
	_after_command(result)
	return result


func end_player_turn() -> Variant:
	if _battle_controller == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle is not initialized")
	var result: Variant = _battle_controller.end_player_turn()
	_after_command(result)
	return result


func set_presentation_speed(value: float) -> Variant:
	if _battle_controller == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle is not initialized")
	var result: Variant = _battle_controller.set_presentation_speed(value)
	_after_command(result)
	return result


func set_auto_battle(enabled: bool) -> Variant:
	if _battle_controller == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle is not initialized")
	var result: Variant = _battle_controller.set_auto_battle(enabled)
	_after_command(result)
	return result


func acknowledge_presentation_through(sequence: int) -> void:
	if _battle_controller == null:
		return
	_battle_controller.acknowledge_presentation_through(sequence)
	Signals.battle_view_model_changed.emit(_battle_controller.view_model())


func clear_battle() -> void:
	if _run_battle_adapter != null and not _run_battle_adapter.is_settled():
		var errors: Array[String] = []
		_run_battle_adapter.cancel_open_launch(errors)
	HandManager.clear_battle()
	_battle_controller = null
	_run_battle_adapter = null
	_run_lifecycle = null
	Signals.battle_view_model_changed.emit({})


func _after_command(result: Variant) -> void:
	Signals.battle_command_finished.emit(result)
	Signals.battle_view_model_changed.emit(_battle_controller.view_model())
	_emit_fatal_if_present()
	_settle_roguelike_if_terminal()


func _settle_roguelike_if_terminal() -> void:
	if _run_battle_adapter == null or _run_battle_adapter.is_settled():
		return
	var settlement: Dictionary = _battle_controller.settlement_snapshot()
	if settlement.is_empty() or not settlement["game_over"]:
		return
	var errors: Array[String] = []
	if not _run_battle_adapter.settle_if_terminal(errors):
		Signals.battle_fatal.emit({
			"code": Result.COMMITTED_FAILURE,
			"message": errors[0] if not errors.is_empty() else "Run battle settlement failed",
			"details": {"fatal": true},
		})
		return
	var snapshot_errors: Array[String] = []
	var run_snapshot: Dictionary = _run_lifecycle.snapshot(snapshot_errors)
	if snapshot_errors.is_empty():
		Signals.roguelike_battle_settled.emit(run_snapshot)


func _emit_fatal_if_present() -> void:
	if _battle_controller == null:
		return
	var fatal: Variant = _battle_controller.view_model().get("fatal")
	if typeof(fatal) == TYPE_DICTIONARY:
		Signals.battle_fatal.emit(fatal)
