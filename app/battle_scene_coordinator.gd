class_name BattleSceneCoordinator
extends Control

signal command_rejected(code: String, message: String)

const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")

@export var auto_start := true
@export var battle_seed := "m4-presentation"
@export var deployed_hero_ids: Array[int] = [1]
@export var free_skill_ids: Array[String] = [
	"pieceBlock", "pieceDamageUp", "markBurn", "executeStrike",
]
@export var stage_id := "counter"

@onready var battle_screen: Node = %BattleScreen
@onready var presentation_queue: Node = %PresentationQueue

var controller: Variant = null
var hand_manager: Node = null
var _logic_submission_count := 0
var _logic_depth := 0
var _max_logic_depth := 0
var _auto_attempted_round := -1
var _auto_attempted_instances: Dictionary = {}
var _auto_step_scheduled := false


func _ready() -> void:
	battle_screen.play_card_requested.connect(_on_play_card_requested)
	battle_screen.end_turn_requested.connect(_on_end_turn_requested)
	battle_screen.speed_requested.connect(_on_speed_requested)
	battle_screen.auto_battle_requested.connect(_on_auto_battle_requested)
	battle_screen.restart_requested.connect(_on_restart_requested)
	presentation_queue.busy_changed.connect(battle_screen.set_queue_busy)
	presentation_queue.event_started.connect(battle_screen.present_event)
	presentation_queue.event_finished.connect(battle_screen.finish_event)
	presentation_queue.batch_finished.connect(_on_presentation_finished)
	battle_screen.set_duration_clock(Callable(presentation_queue, "seconds_for_ms"))
	battle_screen.set_anchor_resolver(Callable(battle_screen, "resolve_visual_anchor"))
	if auto_start:
		start_battle()


func start_battle() -> bool:
	if controller != null:
		return false
	hand_manager = HandManagerScript.new()
	add_child(hand_manager)
	controller = ControllerScript.new(hand_manager)
	var result: Variant = controller.start({
		"battle_seed": battle_seed,
		"deployed_hero_ids": deployed_hero_ids.duplicate(),
		"free_skill_ids": free_skill_ids.duplicate(),
		"stage_id": stage_id,
	})
	if not result.ok:
		battle_screen.bind_view_model({
			"initialized": false,
			"battle": {"phase": "halted", "game_over": false, "result": null},
			"session": {"active": false, "halted": true, "settled": false},
			"hand": [],
			"fatal": {"code": result.code, "message": result.message, "details": result.details},
		})
		return false
	var vm: Dictionary = controller.view_model()
	battle_screen.bind_view_model(vm)
	_enqueue_vm_events(vm)
	return true


func logic_submission_count() -> int:
	return _logic_submission_count


func max_logic_depth() -> int:
	return _max_logic_depth


func submit_play_card(command: Dictionary) -> Variant:
	if controller == null or presentation_queue.is_busy() or battle_screen.is_input_locked():
		return null
	battle_screen.set_queue_busy(true)
	_logic_submission_count += 1
	_begin_logic_submission()
	var result: Variant = controller.play_card_guarded(command)
	_end_logic_submission()
	_complete_logic_command(result)
	return result


func submit_end_turn() -> Variant:
	if controller == null or presentation_queue.is_busy() or battle_screen.is_input_locked():
		return null
	battle_screen.set_queue_busy(true)
	_logic_submission_count += 1
	_begin_logic_submission()
	var result: Variant = controller.end_player_turn()
	_end_logic_submission()
	_complete_logic_command(result)
	return result


func set_presentation_speed(speed: float) -> bool:
	if controller == null:
		return false
	var result: Variant = controller.set_presentation_speed(speed)
	if not result.ok or not presentation_queue.set_speed(speed):
		command_rejected.emit(result.code, result.message)
		return false
	battle_screen.set_presentation_speed(speed)
	return true


func set_auto_battle(enabled: bool) -> bool:
	if controller == null:
		return false
	var vm: Dictionary = controller.view_model()
	if enabled and _is_terminal(vm):
		return false
	var result: Variant = controller.set_auto_battle(enabled)
	if not result.ok:
		command_rejected.emit(result.code, result.message)
		return false
	battle_screen.bind_view_model(controller.view_model())
	if enabled:
		_schedule_auto_step()
	else:
		_auto_step_scheduled = false
	return true


func restart_battle() -> bool:
	if controller == null:
		return start_battle()
	_auto_step_scheduled = false
	controller.set_auto_battle(false)
	presentation_queue.reset()
	battle_screen.reset_presentation()
	if is_instance_valid(hand_manager):
		remove_child(hand_manager)
		hand_manager.free()
	hand_manager = null
	controller = null
	_logic_submission_count = 0
	_logic_depth = 0
	_max_logic_depth = 0
	_auto_attempted_round = -1
	_auto_attempted_instances.clear()
	return start_battle()


func drive_auto_for_test(max_commands: int = 256) -> Dictionary:
	var elapsed := 0.0
	var iterations := 0
	if controller == null or not set_auto_battle(true):
		return {"complete": false, "presentation_seconds": elapsed, "commands": 0, "iterations": 0}
	var submissions_at_start := _logic_submission_count
	while iterations < max_commands * 4:
		iterations += 1
		if presentation_queue.is_busy():
			# Every production base duration is divisible by 20 ms. A 5 ms virtual
			# tick therefore preserves exact 1x/4x timing while keeping e2e fast.
			elapsed += presentation_queue.drain_for_test(0.005, 60.0)
		var vm: Dictionary = controller.view_model()
		if _is_terminal(vm):
			_stop_auto_for_terminal()
			return {
				"complete": true,
				"presentation_seconds": elapsed,
				"commands": _logic_submission_count - submissions_at_start,
				"iterations": iterations,
			}
		if _logic_submission_count - submissions_at_start >= max_commands:
			break
		_auto_step_scheduled = false
		if not _drive_auto_once():
			break
	return {
		"complete": false,
		"presentation_seconds": elapsed,
		"commands": _logic_submission_count - submissions_at_start,
		"iterations": iterations,
	}


func _complete_logic_command(result: Variant) -> void:
	var vm: Dictionary = controller.view_model()
	if not result.ok and vm.get("fatal") == null:
		battle_screen.bind_view_model(vm)
		battle_screen.set_queue_busy(false)
		command_rejected.emit(result.code, result.message)
		_schedule_auto_step()
		return
	_enqueue_vm_events(vm)


func _enqueue_vm_events(vm: Dictionary) -> void:
	var events: Array = vm.get("presentation", {}).get("pending_events", [])
	if events.is_empty():
		battle_screen.bind_view_model(vm)
		battle_screen.set_queue_busy(false)
		if _is_terminal(vm):
			_stop_auto_for_terminal()
		else:
			_schedule_auto_step()
		return
	if not presentation_queue.enqueue(events, vm):
		battle_screen.set_queue_busy(true)


func _on_play_card_requested(command: Dictionary) -> void:
	submit_play_card(command)


func _on_end_turn_requested() -> void:
	submit_end_turn()


func _on_speed_requested(speed: float) -> void:
	set_presentation_speed(speed)


func _on_auto_battle_requested(enabled: bool) -> void:
	set_auto_battle(enabled)


func _on_restart_requested() -> void:
	restart_battle()


func _on_presentation_finished(_final_vm: Dictionary, last_sequence: int) -> void:
	if controller == null:
		return
	controller.acknowledge_presentation_through(last_sequence)
	battle_screen.clear_transient_feedback()
	var vm: Dictionary = controller.view_model()
	if _is_terminal(vm):
		_stop_auto_for_terminal()
		vm = controller.view_model()
	battle_screen.bind_view_model(vm)
	if not _is_terminal(vm):
		_schedule_auto_step()


func _schedule_auto_step() -> void:
	if controller == null or _auto_step_scheduled or presentation_queue.is_busy():
		return
	var vm: Dictionary = controller.view_model()
	if not bool(vm.get("presentation", {}).get("auto_battle", false)) or _is_terminal(vm):
		return
	_auto_step_scheduled = true
	call_deferred("_run_scheduled_auto_step")


func _run_scheduled_auto_step() -> void:
	_auto_step_scheduled = false
	_drive_auto_once()


func _drive_auto_once() -> bool:
	if controller == null or presentation_queue.is_busy() or battle_screen.is_input_locked():
		return false
	var vm: Dictionary = controller.view_model()
	if not bool(vm.get("presentation", {}).get("auto_battle", false)) or _is_terminal(vm):
		return false
	var round_number := int(vm.get("battle", {}).get("round", -1))
	if round_number != _auto_attempted_round:
		_auto_attempted_round = round_number
		_auto_attempted_instances.clear()
	for card: Dictionary in vm.get("hand", []):
		var instance_id := str(card.get("instance_id", ""))
		if not bool(card.get("playable", false)) or _auto_attempted_instances.has(instance_id):
			continue
		_auto_attempted_instances[instance_id] = true
		return submit_play_card(_guard_for(card)) != null
	var end_result: Variant = submit_end_turn()
	if end_result != null and not end_result.ok:
		# A rejected card advances to the next authoritative card. A rejected
		# end-turn has no further valid action, so stop instead of retrying forever.
		set_auto_battle(false)
		return false
	return end_result != null


func _stop_auto_for_terminal() -> void:
	_auto_step_scheduled = false
	if controller != null:
		controller.set_auto_battle(false)


func _begin_logic_submission() -> void:
	_logic_depth += 1
	_max_logic_depth = maxi(_max_logic_depth, _logic_depth)


func _end_logic_submission() -> void:
	_logic_depth -= 1


static func _is_terminal(vm: Dictionary) -> bool:
	return bool(vm.get("battle", {}).get("game_over", false)) or vm.get("fatal") != null


static func _guard_for(card: Dictionary) -> Dictionary:
	return {
		"type": "play_card",
		"instance_id": str(card.get("instance_id", "")),
		"expected_card_id": str(card.get("card_id", "")),
		"expected_source_skill_id": str(card.get("source_skill_id", "")),
		"owner_hero_id": card.get("owner_hero_id"),
	}
