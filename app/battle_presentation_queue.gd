class_name BattlePresentationQueue
extends Node

signal busy_changed(busy: bool)
signal event_started(event: Dictionary, duration_seconds: float)
signal event_finished(event: Dictionary)
signal batch_finished(final_view_model: Dictionary, last_sequence: int)

const SPEED_OPTIONS := [1.0, 2.0, 3.0, 4.0]

var _speed := 1.0
var _busy := false
var _segments: Array[Dictionary] = []
var _active_segment: Dictionary = {}
var _active_speed := 1.0
var _remaining_seconds := 0.0
var _final_view_model: Dictionary = {}
var _last_sequence := 0
var _completed_sequences: Array[int] = []


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_advance(maxf(0.0, delta))


func set_speed(speed: float) -> bool:
	if speed not in SPEED_OPTIONS:
		return false
	_speed = speed
	return true


func speed() -> float:
	return _speed


func active_segment_speed() -> float:
	return _active_speed if not _active_segment.is_empty() else _speed


func seconds_for_ms(duration_ms: int) -> float:
	return maxf(0.0, float(duration_ms) / 1000.0 / active_segment_speed())


func is_busy() -> bool:
	return _busy


func reset() -> void:
	var was_busy := _busy
	_busy = false
	_segments.clear()
	_active_segment = {}
	_remaining_seconds = 0.0
	_final_view_model = {}
	_last_sequence = 0
	_completed_sequences.clear()
	_active_speed = _speed
	if was_busy:
		busy_changed.emit(false)


func completed_sequences() -> Array[int]:
	return _completed_sequences.duplicate()


func enqueue(events: Array, final_view_model: Dictionary) -> bool:
	if _busy:
		return false
	var ordered := _canonical_events(events)
	if ordered.is_empty():
		batch_finished.emit(final_view_model.duplicate(true), _last_sequence)
		return true
	_segments = _build_segments(ordered)
	_final_view_model = final_view_model.duplicate(true)
	_busy = true
	busy_changed.emit(true)
	_begin_next_segment()
	return true


func advance_for_test(delta: float) -> void:
	_advance(maxf(0.0, delta))


func drain_for_test(step_seconds: float = 0.002, limit_seconds: float = 30.0) -> float:
	var elapsed := 0.0
	while _busy and elapsed < limit_seconds:
		advance_for_test(step_seconds)
		elapsed += step_seconds
	return elapsed


func event_duration_ms(event: Dictionary) -> int:
	var kind := str(event.get("kind", ""))
	var event_id := str(event.get("event_id", ""))
	if kind == "card":
		return 1500 if event.get("payload", {}).get("card_category") == "ultimate" else 360
	if kind == "damage":
		if event_id == "damage_applied":
			return 280
		if event_id == "unit_blocked":
			return 160
		return 100
	if kind == "heal":
		return 280
	if kind == "buff":
		return 180
	if kind == "combat":
		return 160
	if kind == "round":
		return 320 if event_id == "battleResolved" else 120
	if kind == "log":
		return 40
	return 0


func _advance(delta: float) -> void:
	if not _busy or _active_segment.is_empty():
		return
	var carry := delta
	while _busy and not _active_segment.is_empty():
		if carry + 0.000001 < _remaining_seconds:
			_remaining_seconds -= carry
			return
		carry = maxf(0.0, carry - _remaining_seconds)
		_finish_active_segment()
		if carry <= 0.0:
			return


func _begin_next_segment() -> void:
	while _busy:
		if _segments.is_empty():
			_finish_batch()
			return
		_active_segment = _segments.pop_front()
		_active_speed = _speed
		_remaining_seconds = float(_active_segment["base_duration_ms"]) / 1000.0 / _active_speed
		for event: Dictionary in _active_segment["events"]:
			event_started.emit(event.duplicate(true), _remaining_seconds)
		if _remaining_seconds > 0.0:
			return
		_finish_active_segment()


func _finish_active_segment() -> void:
	for event: Dictionary in _active_segment.get("events", []):
		var sequence := int(event.get("sequence", 0))
		_last_sequence = maxi(_last_sequence, sequence)
		_completed_sequences.append(sequence)
		event_finished.emit(event.duplicate(true))
	_active_segment = {}
	_remaining_seconds = 0.0
	_begin_next_segment()


func _finish_batch() -> void:
	var final_snapshot := _final_view_model.duplicate(true)
	_final_view_model = {}
	_busy = false
	busy_changed.emit(false)
	batch_finished.emit(final_snapshot, _last_sequence)


func _canonical_events(events: Array) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for value: Variant in events:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = value
		if int(event.get("sequence", 0)) <= _last_sequence:
			continue
		ordered.append(event.duplicate(true))
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("sequence", 0)) < int(right.get("sequence", 0))
	)
	return ordered


func _build_segments(events: Array[Dictionary]) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for event: Dictionary in events:
		var duration := event_duration_ms(event)
		var group_with_previous: bool = (
			event.get("kind") == "buff"
			and not segments.is_empty()
			and segments[-1]["events"][-1].get("kind") == "buff"
			and segments[-1]["events"][-1].get("batch_id") == event.get("batch_id")
		)
		if group_with_previous:
			segments[-1]["events"].append(event)
			segments[-1]["base_duration_ms"] = maxi(
				int(segments[-1]["base_duration_ms"]), duration
			)
		else:
			segments.append({"events": [event], "base_duration_ms": duration})
	return segments
