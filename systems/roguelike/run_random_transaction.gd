class_name TransactionalRunRandom
extends RefCounted

## A Run-only replay transaction over an injected primitive random source.
## Rollback never rewinds the source. Values already drawn are prepended to this
## adapter's replay tape, matching the Web transaction boundary.

class TransactionToken extends RefCounted:
	var owner_id: int
	var serial: int
	var consumed := false

	func _init(source_owner_id: int, source_serial: int) -> void:
		owner_id = source_owner_id
		serial = source_serial


class CommandError extends RefCounted:
	var message: String

	func _init(error_message: String) -> void:
		message = error_message


const CHECKPOINT_VERSION := 1
const CHECKPOINT_KEYS := ["version", "source_state", "replay_queue"]

var _source: Variant
var _valid := false
var _active_token: TransactionToken
var _active_draws: Array[float] = []
var _replay_queue: Array[float] = []
var _next_serial := 1
var _active_fault := ""


func _init(source: Variant = null, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(source) != TYPE_OBJECT or source == null or not source.has_method("next"):
		errors.append("Run random source.next must be callable")
		return
	_source = source
	_valid = true


func is_valid() -> bool:
	return _valid


func next(errors: Array[String] = []) -> Variant:
	errors.clear()
	if not _valid:
		errors.append("Run random adapter is invalid")
		return null
	var value: Variant
	if not _replay_queue.is_empty():
		value = _replay_queue.pop_front()
	else:
		value = _source.next()
	if not _is_random_value(value):
		_fault("Run random source must return a finite number in [0, 1)")
		errors.append("Run random source must return a finite number in [0, 1)")
		return null
	if _active_token != null:
		_active_draws.append(float(value))
	return float(value)


func float_range(
	minimum: float = 0.0,
	maximum: float = 1.0,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	if not is_finite(minimum) or not is_finite(maximum) or maximum < minimum:
		_fault("Run random float range must be finite and maximum must be >= minimum")
		errors.append("Run random float range must be finite and maximum must be >= minimum")
		return null
	var value: Variant = next(errors)
	if value == null:
		return null
	return minimum + float(value) * (maximum - minimum)


func int_range(minimum: int, maximum: int, errors: Array[String] = []) -> Variant:
	errors.clear()
	if maximum < minimum:
		_fault("Run random integer maximum must be >= minimum")
		errors.append("Run random integer maximum must be >= minimum")
		return null
	var value: Variant = float_range(float(minimum), float(maximum) + 1.0, errors)
	return null if value == null else int(floor(value))


func pick(values: Array, errors: Array[String] = []) -> Variant:
	errors.clear()
	if values.is_empty():
		_fault("Run random pick requires a non-empty Array")
		errors.append("Run random pick requires a non-empty Array")
		return null
	var index: Variant = int_range(0, values.size() - 1, errors)
	return null if index == null else values[int(index)]


func shuffle(values: Array, errors: Array[String] = []) -> Array:
	errors.clear()
	var copy := values.duplicate(false)
	for index in range(copy.size() - 1, 0, -1):
		var swap_index: Variant = int_range(0, index, errors)
		if swap_index == null:
			return []
		var temporary: Variant = copy[index]
		copy[index] = copy[int(swap_index)]
		copy[int(swap_index)] = temporary
	return copy


func begin_transaction(errors: Array[String] = []) -> Variant:
	errors.clear()
	if not _valid:
		errors.append("Run random adapter is invalid")
		return null
	if _active_token != null:
		_fault("a Run random transaction is already active; re-entrant transactions are forbidden")
		errors.append(_active_fault)
		return null
	var token := TransactionToken.new(get_instance_id(), _next_serial)
	_next_serial += 1
	_active_token = token
	_active_draws = []
	_active_fault = ""
	return token


func commit_transaction(token: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_active_token(token, errors):
		return false
	if not _active_fault.is_empty():
		var fault := _active_fault
		rollback_transaction(token)
		errors.append(fault)
		return false
	_consume_active_token()
	return true


func rollback_transaction(token: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_active_token(token, errors):
		return false
	var draws := _active_draws.duplicate()
	_consume_active_token()
	if not draws.is_empty():
		_replay_queue = draws + _replay_queue
	return true


func command_error(message: String) -> CommandError:
	return CommandError.new(message if not message.is_empty() else "Run random transaction command failed")


func with_transaction(command: Callable, errors: Array[String] = []) -> Variant:
	errors.clear()
	if not command.is_valid():
		errors.append("Run random transaction command must be callable")
		return null
	var token: Variant = begin_transaction(errors)
	if token == null:
		return null
	var result: Variant = command.call()
	var rejection := _result_rejection(result)
	if not _active_fault.is_empty():
		rejection = _active_fault
	if not rejection.is_empty():
		rollback_transaction(token)
		errors.append(rejection)
		return null
	if typeof(result) == TYPE_BOOL and not result:
		rollback_transaction(token)
		return false
	commit_transaction(token)
	return result


func has_active_transaction() -> bool:
	return _active_token != null


func replay_count() -> int:
	return _replay_queue.size()


func export_checkpoint(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _valid:
		errors.append("Run random adapter is invalid")
		return {}
	if _active_token != null:
		errors.append("cannot checkpoint an active Run random transaction")
		return {}
	if not _source.has_method("state_snapshot"):
		errors.append("Run random source does not expose a restorable state")
		return {}
	var source_state: Variant = _source.state_snapshot()
	if not _is_uint32(source_state):
		errors.append("Run random source state must be an unsigned 32-bit integer")
		return {}
	var serialized_replay: Array[String] = []
	for value: Variant in _replay_queue:
		if not _is_random_value(value):
			errors.append("Run random replay queue contains an invalid value")
			return {}
		serialized_replay.append(String.num(float(value), 17))
	return {
		"version": CHECKPOINT_VERSION,
		"source_state": source_state,
		"replay_queue": serialized_replay,
	}


static func restore_checkpoint(
	checkpoint: Variant,
	source: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	if not _has_checkpoint_shape(checkpoint):
		errors.append("Run random checkpoint must be a closed version-1 Dictionary")
		return null
	var normalized_version: Variant = _normalized_integer(checkpoint["version"])
	var normalized_source_state: Variant = _normalized_integer(checkpoint["source_state"])
	if normalized_version != CHECKPOINT_VERSION:
		errors.append("unsupported Run random checkpoint version")
		return null
	if not _is_uint32(normalized_source_state):
		errors.append("Run random checkpoint source_state must be an unsigned 32-bit integer")
		return null
	if (
		typeof(source) != TYPE_OBJECT
		or source == null
		or not source.has_method("next")
		or not source.has_method("state_snapshot")
	):
		errors.append("Run random restore requires a stateful random source")
		return null
	var actual_state: Variant = source.state_snapshot()
	if actual_state != normalized_source_state:
		errors.append("Run random source state does not match its checkpoint")
		return null
	var raw_replay: Variant = checkpoint["replay_queue"]
	if typeof(raw_replay) != TYPE_ARRAY:
		errors.append("Run random checkpoint replay_queue must be an Array")
		return null
	var replay: Array[float] = []
	for encoded_value: Variant in raw_replay:
		if (
			typeof(encoded_value) != TYPE_STRING
			or encoded_value != encoded_value.strip_edges()
			or not encoded_value.is_valid_float()
		):
			errors.append("Run random checkpoint replay_queue contains an invalid value")
			return null
		var value := float(encoded_value)
		if not _is_random_value(value):
			errors.append("Run random checkpoint replay_queue contains an invalid value")
			return null
		replay.append(value)
	var restored := TransactionalRunRandom.new(source, errors)
	if not errors.is_empty() or not restored.is_valid():
		return null
	restored._replay_queue = replay
	return restored


func _result_rejection(result: Variant) -> String:
	if result is CommandError:
		return result.message
	if typeof(result) == TYPE_SIGNAL:
		return "Run random transactions must be synchronous and cannot return a Signal"
	if typeof(result) == TYPE_OBJECT and result != null and result.get_class() == "GDScriptFunctionState":
		return "Run random transactions must be synchronous and cannot return a function state"
	return ""


func _require_active_token(token: Variant, errors: Array[String]) -> bool:
	if not token is TransactionToken:
		errors.append("invalid, foreign, or already-consumed Run random transaction token")
		return false
	var typed_token := token as TransactionToken
	if typed_token.consumed or typed_token.owner_id != get_instance_id() or _active_token != typed_token:
		errors.append("invalid, foreign, or already-consumed Run random transaction token")
		return false
	return true


func _consume_active_token() -> void:
	_active_token.consumed = true
	_active_token = null
	_active_draws = []
	_active_fault = ""


func _fault(message: String) -> void:
	if _active_token != null and _active_fault.is_empty():
		_active_fault = message


static func _is_random_value(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and float(value) >= 0.0
		and float(value) < 1.0
	)


static func _has_checkpoint_shape(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != CHECKPOINT_KEYS.size():
		return false
	for key: String in CHECKPOINT_KEYS:
		if not value.has(key):
			return false
	return true


static func _normalized_integer(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value):
		return int(value)
	return null


static func _is_uint32(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= 0xffffffff
