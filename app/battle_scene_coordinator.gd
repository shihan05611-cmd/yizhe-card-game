class_name BattleSceneCoordinator
extends Control

signal command_rejected(code: String, message: String)
signal run_battle_finished(snapshot: Dictionary)
signal run_continue_requested

const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const RoguelikeBattleAdapterScript = preload("res://app/roguelike_battle_adapter.gd")

@export var auto_start := true
@export var battle_seed := "m4-presentation"
@export var deployed_hero_ids: Array[int] = [1]
@export var free_skill_ids: Array[String] = [
	"pieceBlock", "pieceDamageUp", "markBurn", "executeStrike",
]
@export var retained_card_keys: Array[String] = []
@export var stage_id := "counter"

@onready var battle_screen: Node = %BattleScreen
@onready var presentation_queue: Node = %PresentationQueue

var controller: Variant = null
var hand_manager: Node = null
var _run_battle_adapter: Variant = null
var _run_lifecycle: Variant = null
var _run_finished_emitted := false
var _logic_submission_count := 0
var _logic_depth := 0
var _max_logic_depth := 0
var _auto_attempted_round := -1
var _auto_attempted_instances: Dictionary = {}
var _auto_step_scheduled := false
var _pending_cards: Array[Dictionary] = []
var _pending_card_submitting := false
var _active_pending_card: Dictionary = {}


func _ready() -> void:
	battle_screen.play_card_requested.connect(_on_play_card_requested)
	battle_screen.end_turn_requested.connect(_on_end_turn_requested)
	battle_screen.speed_requested.connect(_on_speed_requested)
	battle_screen.auto_battle_requested.connect(_on_auto_battle_requested)
	battle_screen.restart_requested.connect(_on_restart_requested)
	battle_screen.pending_card_cancel_requested.connect(_cancel_pending_card)
	presentation_queue.busy_changed.connect(battle_screen.set_queue_busy)
	presentation_queue.event_started.connect(_on_presentation_event_started)
	presentation_queue.event_finished.connect(battle_screen.finish_event)
	presentation_queue.batch_finished.connect(_on_presentation_finished)
	battle_screen.set_duration_clock(Callable(presentation_queue, "seconds_for_ms"))
	battle_screen.set_anchor_resolver(Callable(battle_screen, "resolve_visual_anchor"))
	if auto_start:
		start_battle()


func start_battle() -> bool:
	if controller != null:
		return false
	_run_battle_adapter = null
	_run_lifecycle = null
	_run_finished_emitted = false
	_set_run_result_mode(false)
	hand_manager = HandManagerScript.new()
	add_child(hand_manager)
	controller = ControllerScript.new(hand_manager)
	var result: Variant = controller.start({
		"battle_seed": battle_seed,
		"deployed_hero_ids": deployed_hero_ids.duplicate(),
		"free_skill_ids": free_skill_ids.duplicate(),
		"retained_card_keys": retained_card_keys.duplicate(),
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


## Starts the same presentation stack with the authoritative Run launch.  The
## adapter owns the one-shot RunBattleProgress session; this scene never writes
## Run state or battle deck data itself.
func start_run_battle(lifecycle: Variant) -> bool:
	if controller != null or lifecycle == null:
		return false
	_set_run_result_mode(true)
	hand_manager = HandManagerScript.new()
	add_child(hand_manager)
	var adapter := RoguelikeBattleAdapterScript.new(lifecycle, hand_manager)
	var errors: Array[String] = []
	var result: Variant = adapter.start(errors)
	if not result.ok:
		battle_screen.bind_view_model({
			"initialized": false,
			"battle": {"phase": "halted", "game_over": false, "result": null},
			"session": {"active": false, "halted": true, "settled": false},
			"hand": [],
			"fatal": {
				"code": result.code,
				"message": result.message,
				"details": result.details,
			},
		})
		remove_child(hand_manager)
		hand_manager.free()
		hand_manager = null
		_set_run_result_mode(false)
		return false
	_run_battle_adapter = adapter
	_run_lifecycle = lifecycle
	_run_finished_emitted = false
	controller = adapter.controller()
	var vm: Dictionary = controller.view_model()
	battle_screen.bind_view_model(vm)
	_enqueue_vm_events(vm)
	return true


func logic_submission_count() -> int:
	return _logic_submission_count


func max_logic_depth() -> int:
	return _max_logic_depth


func submit_play_card(command: Dictionary) -> Variant:
	return _submit_card_now(command)


func queue_play_card(command: Dictionary) -> Variant:
	if not can_process() or controller == null or _is_terminal(controller.view_model()):
		return null
	var vm: Dictionary = controller.view_model()
	if str(vm.get("battle", {}).get("phase", "")) != "player_input" or bool(vm.get("session", {}).get("halted", false)):
		return null
	var instance_id := str(command.get("instance_id", ""))
	var release_pose: Dictionary = battle_screen.take_card_release_pose(instance_id)
	if instance_id.is_empty() or str(_active_pending_card.get("instance_id", "")) == instance_id or _pending_cards.any(func(entry: Dictionary) -> bool: return entry["instance_id"] == instance_id):
		return null
	var name := instance_id
	var card_snapshot: Dictionary = {}
	for card: Dictionary in vm.get("hand", []):
		if str(card.get("instance_id", "")) == instance_id:
			name = str(card.get("name", instance_id))
			card_snapshot = card.duplicate(true)
	if card_snapshot.is_empty():
		return null
	_pending_cards.append({"instance_id": instance_id, "name": name, "card": card_snapshot, "release_pose": release_pose, "command": command.duplicate(true)})
	_sync_pending_cards()
	battle_screen.present_card_settlement(instance_id, card_snapshot, release_pose, 0.32 / presentation_queue.active_segment_speed())
	_pump_pending_cards()
	return true


func _submit_card_now(command: Dictionary) -> Variant:
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
	if not _pending_cards.is_empty():
		return null
	if controller == null or presentation_queue.is_busy() or battle_screen.is_input_locked():
		return null
	battle_screen.set_queue_busy(true)
	_logic_submission_count += 1
	_begin_logic_submission()
	var result: Variant = controller.end_player_turn()
	_end_logic_submission()
	if result.ok:
		# Non-retained cards have committed to their end-of-turn piles. Keep retained
		# instances visible while combat plays; the final ViewModel adds next-turn draws.
		var retained_ids: Array = result.details.get("discard", {}).get(
			"details", {},
		).get("retained_instance_ids", [])
		battle_screen.clear_hand_for_turn_settlement(retained_ids)
	_complete_logic_command(result)
	return result


func force_victory() -> Variant:
	if not can_process() or controller == null:
		return null
	var vm: Dictionary = controller.view_model()
	if _is_terminal(vm):
		return null
	# Discard visual-only work before creating the terminal batch. Acknowledging
	# its stream sequences prevents cancelled card/damage events from replaying.
	_stop_auto_for_terminal()
	_clear_pending_cards()
	presentation_queue.reset()
	battle_screen.reset_presentation()
	var prior_events: Array = controller.presentation_events()
	if not prior_events.is_empty():
		controller.acknowledge_presentation_through(int(prior_events[-1].get("sequence", 0)))
	_logic_submission_count += 1
	_begin_logic_submission()
	var result: Variant = controller.force_victory()
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
	# Queue changes speed at its next segment boundary; the HUD may update now,
	# but animated effects must stay on the active segment's clock.
	battle_screen.set_speed_display(speed)
	battle_screen.set_effect_speed(presentation_queue.active_segment_speed())
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
	if _run_battle_adapter != null:
		return false
	if controller == null:
		return start_battle()
	_auto_step_scheduled = false
	_clear_pending_cards()
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
	_set_run_result_mode(false)
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


func _pump_pending_cards() -> void:
	if not can_process() or _pending_card_submitting or _pending_cards.is_empty() or controller == null or presentation_queue.is_busy():
		return
	if _is_terminal(controller.view_model()) or battle_screen.is_input_locked():
		return
	_pending_card_submitting = true
	var entry: Dictionary = _pending_cards[0]
	var result: Variant = _submit_card_now(entry["command"])
	_pending_card_submitting = false
	if result == null:
		return
	_pending_cards.pop_front()
	if result.ok and presentation_queue.is_busy():
		_active_pending_card = entry.duplicate(true)
	_sync_pending_cards()
	if not result.ok:
		battle_screen.show_pending_card_notice("待出牌已退回：%s" % result.message)
		battle_screen.bind_view_model(controller.view_model())
		call_deferred("_pump_pending_cards")


func _cancel_pending_card(instance_id: String) -> void:
	for index in _pending_cards.size():
		if _pending_cards[index]["instance_id"] == instance_id:
			_pending_cards.remove_at(index)
			_sync_pending_cards()
			battle_screen.bind_view_model(controller.view_model())
			return


func _sync_pending_cards() -> void:
	var display_entries: Array[Dictionary] = []
	if not _active_pending_card.is_empty():
		var active := _active_pending_card.duplicate(true)
		active["state"] = "releasing"
		display_entries.append(active)
	for entry: Dictionary in _pending_cards:
		var waiting := entry.duplicate(true)
		waiting["state"] = "waiting"
		display_entries.append(waiting)
	battle_screen.set_pending_cards(display_entries)
	battle_screen.set_pending_card_instances(display_entries.map(func(entry: Dictionary) -> String: return str(entry.get("instance_id", ""))))
	if controller != null:
		battle_screen.refresh_visible_hand_availability(controller.view_model().get("hand", []))


func _clear_pending_cards() -> void:
	battle_screen.cancel_pending_return_flights()
	_pending_cards.clear()
	_active_pending_card.clear()
	_sync_pending_cards()


func _enqueue_vm_events(vm: Dictionary) -> void:
	var events: Array = vm.get("presentation", {}).get("pending_events", [])
	if events.is_empty():
		battle_screen.bind_view_model(vm)
		battle_screen.set_queue_busy(false)
		if _is_terminal(vm):
			_clear_pending_cards()
			_stop_auto_for_terminal()
			_settle_run_battle_after_presentation()
		elif not _pending_cards.is_empty():
			call_deferred("_pump_pending_cards")
		else:
			_schedule_auto_step()
		return
	if not presentation_queue.enqueue(events, vm):
		battle_screen.set_queue_busy(true)


func _on_play_card_requested(command: Dictionary) -> void:
	queue_play_card(command)


func _on_end_turn_requested() -> void:
	submit_end_turn()


func _on_speed_requested(speed: float) -> void:
	set_presentation_speed(speed)


func _on_auto_battle_requested(enabled: bool) -> void:
	set_auto_battle(enabled)


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		not event is InputEventKey
		or not event.pressed
		or event.echo
		or event.keycode != KEY_X
	):
		return
	if force_victory() != null:
		get_viewport().set_input_as_handled()


func _on_restart_requested() -> void:
	if _run_battle_adapter != null:
		var vm: Dictionary = controller.view_model() if controller != null else {}
		if bool(vm.get("battle", {}).get("game_over", false)) and _run_finished_emitted:
			run_continue_requested.emit()
		return
	restart_battle()


func _on_presentation_finished(_final_vm: Dictionary, last_sequence: int) -> void:
	if controller == null:
		return
	controller.acknowledge_presentation_through(last_sequence)
	battle_screen.clear_transient_feedback()
	_active_pending_card.clear()
	_sync_pending_cards()
	var vm: Dictionary = controller.view_model()
	if _is_terminal(vm):
		_clear_pending_cards()
		_stop_auto_for_terminal()
		vm = controller.view_model()
	battle_screen.bind_view_model(vm)
	if _is_terminal(vm):
		_settle_run_battle_after_presentation()
	if not _is_terminal(vm) and not _pending_cards.is_empty():
		_pump_pending_cards()
	if not _is_terminal(vm) and _pending_cards.is_empty():
		_schedule_auto_step()


func _on_presentation_event_started(event: Dictionary, duration: float) -> void:
	# Queue speed changes deliberately take effect on the next segment. Keep
	# perpetual effects on that same active-segment clock as piece tweens/FX.
	battle_screen.set_effect_speed(presentation_queue.active_segment_speed())
	battle_screen.present_event(event, duration)


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
		return submit_play_card(_automatic_guard_for(card, vm)) != null
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


func _settle_run_battle_after_presentation() -> void:
	if (
		_run_battle_adapter == null
		or _run_finished_emitted
		or not _run_battle_adapter.has_method("settle_if_terminal")
	):
		return
	var errors: Array[String] = []
	if not _run_battle_adapter.settle_if_terminal(errors):
		if not errors.is_empty():
			command_rejected.emit("run_battle_settlement_failed", errors[0])
		return
	var snapshot_errors: Array[String] = []
	var run_snapshot: Dictionary = _run_lifecycle.snapshot(snapshot_errors)
	if not snapshot_errors.is_empty():
		command_rejected.emit("run_battle_snapshot_failed", snapshot_errors[0])
		return
	_run_finished_emitted = true
	run_battle_finished.emit(run_snapshot)


func _set_run_result_mode(enabled: bool) -> void:
	if battle_screen != null and battle_screen.has_method("set_run_mode"):
		battle_screen.call("set_run_mode", enabled)
		return
	if battle_screen != null and battle_screen.get("result_overlay") != null:
		var overlay: Variant = battle_screen.get("result_overlay")
		if overlay != null and overlay.has_method("set_run_mode"):
			overlay.call("set_run_mode", enabled)


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


static func _automatic_guard_for(card: Dictionary, vm: Dictionary) -> Dictionary:
	var guard := _guard_for(card)
	var targeting: Dictionary = card.get("targeting", {})
	var mode := str(targeting.get("mode", "automatic"))
	if mode == "automatic":
		return guard
	var side := str(targeting.get("side", ""))
	var filter_id := str(targeting.get("filter", ""))
	for unit: Dictionary in vm.get("teams", {}).get(side, {}).get("slots", []):
		if not bool(unit.get("occupied", true)) or not bool(unit.get("alive", false)):
			continue
		if filter_id == "living_non_puppet" and bool(unit.get("is_puppet", false)):
			continue
		if filter_id == "living_puppet_without_enchant_slot" and (
			not bool(unit.get("is_puppet", false))
			or int(unit.get("enchantment_capacity", 0)) > 0
		):
			continue
		if filter_id == "lockable" and unit.get("buffs", []).any(
			func(buff: Dictionary) -> bool: return str(buff.get("id", "")) == "stealth"
		):
			continue
		guard["target"] = {"side": side, "unit_id": unit["id"], "slot": int(unit["slot"])}
		return guard
	return guard
