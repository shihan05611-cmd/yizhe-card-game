extends Node

const HandRuntimeScript = preload("res://systems/cards/hand_runtime.gd")
const BattleCardSessionScript = preload("res://systems/cards/battle_card_session.gd")
const Result = preload("res://core/card_runtime_result.gd")

signal state_changed(snapshot: Dictionary)
signal command_finished(result: Variant)

var _runtime: Variant
var _session: Variant


func start_battle(
	battle_seed: Variant,
	card_definitions: Array,
	shuffle_initial: bool = true,
) -> Variant:
	var candidate := HandRuntimeScript.new(battle_seed)
	var result: Variant = candidate.initialize_deck(card_definitions, shuffle_initial)
	if not result.ok:
		return result
	_session = null
	_runtime = candidate
	state_changed.emit(_runtime.snapshot())
	return result


func start_battle_session(config: Variant, errors: Array[String] = []) -> Variant:
	errors.clear()
	var candidate := BattleCardSessionScript.new(config, errors)
	if not candidate.is_valid():
		return Result.new(
			false,
			Result.INVALID_ARGUMENT,
			errors[0] if not errors.is_empty() else "battle card session failed to start",
		)
	_session = candidate
	_runtime = candidate.component("hand_runtime")
	state_changed.emit(_runtime.snapshot())
	return Result.new(true, Result.OK, "", {"session": candidate.snapshot()})


func clear_battle() -> void:
	_session = null
	_runtime = null
	state_changed.emit({})


func has_runtime() -> bool:
	return _runtime != null


func has_session() -> bool:
	return _session != null


func session_snapshot() -> Dictionary:
	return {} if _session == null else _session.snapshot()


func runtime_snapshot() -> Dictionary:
	return {} if _runtime == null else _runtime.snapshot()


func card_instance_snapshot(instance_id: String) -> Variant:
	return null if _runtime == null else _runtime.get_instance_snapshot(instance_id)


func draw_cards(count: int) -> Variant:
	if _runtime == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "hand runtime is not initialized")
	if _session != null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle session owns turn draws")
	var result: Variant = _runtime.draw_cards(count)
	state_changed.emit(_runtime.snapshot())
	return result


func draw_for_turn(active_hero_count: int) -> Variant:
	if _runtime == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "hand runtime is not initialized")
	if _session != null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle session owns turn draws")
	var result: Variant = _runtime.draw_for_turn(active_hero_count)
	state_changed.emit(_runtime.snapshot())
	return result


func end_player_turn() -> Variant:
	if _runtime == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "hand runtime is not initialized")
	var result: Variant = (
		_session.end_player_turn() if _session != null else _runtime.end_player_turn()
	)
	state_changed.emit(_runtime.snapshot())
	return result


func play_card(request: Variant) -> Variant:
	if _session == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle card session is not initialized")
	var result: Variant = _session.play_card(request)
	command_finished.emit(result)
	state_changed.emit(_runtime.snapshot())
	return result


func inspect_card(request: Variant) -> Variant:
	if _session == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle card session is not initialized")
	return _session.inspect_card(request)


func process_play_command(
	instance_id: String,
	validator: Callable,
	executor: Callable,
	return_to_hand: bool = false,
) -> Variant:
	if _runtime == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "hand runtime is not initialized")
	if _session != null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle session requires CardPlayRequest")
	var result: Variant = _runtime.process_play_command(instance_id, validator, executor, return_to_hand)
	command_finished.emit(result)
	state_changed.emit(_runtime.snapshot())
	return result


func create_card(
	definition: Resource,
	destination: String,
	insertion_strategy: String,
) -> Variant:
	if _runtime == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "hand runtime is not initialized")
	if _session != null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle session owns card generation")
	var result: Variant = _runtime.create_card(definition, destination, insertion_strategy)
	state_changed.emit(_runtime.snapshot())
	return result


func move_card_to_pile(
	instance_id: String,
	destination: String,
	insertion_strategy: String,
) -> Variant:
	if _runtime == null:
		return Result.new(false, Result.INVALID_ARGUMENT, "hand runtime is not initialized")
	if _session != null:
		return Result.new(false, Result.INVALID_ARGUMENT, "battle session owns pile movement")
	var result: Variant = _runtime.move_card_to_pile(instance_id, destination, insertion_strategy)
	state_changed.emit(_runtime.snapshot())
	return result
