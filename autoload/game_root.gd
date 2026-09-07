extends Node

const BattleControllerScript = preload("res://app/battle_controller.gd")
const Result = preload("res://core/card_runtime_result.gd")

var _battle_controller: Variant = null


func _ready() -> void:
	Signals.application_ready.emit()


func start_battle(config: Dictionary) -> Variant:
	if _battle_controller != null and _battle_controller.is_initialized():
		return Result.new(false, Result.INVALID_ARGUMENT, "a battle is already active")
	_battle_controller = BattleControllerScript.new(HandManager)
	var result: Variant = _battle_controller.start(config)
	if result.ok:
		Signals.battle_started.emit(_battle_controller.view_model())
	else:
		_emit_fatal_if_present()
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
	HandManager.clear_battle()
	_battle_controller = null
	Signals.battle_view_model_changed.emit({})


func _after_command(result: Variant) -> void:
	Signals.battle_command_finished.emit(result)
	Signals.battle_view_model_changed.emit(_battle_controller.view_model())
	_emit_fatal_if_present()


func _emit_fatal_if_present() -> void:
	if _battle_controller == null:
		return
	var fatal: Variant = _battle_controller.view_model().get("fatal")
	if typeof(fatal) == TYPE_DICTIONARY:
		Signals.battle_fatal.emit(fatal)
