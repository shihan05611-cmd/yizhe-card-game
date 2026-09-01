extends Node

const INFO := "info"
const WARNING := "warning"
const ERROR := "error"
const SEVERITIES := [INFO, WARNING, ERROR]

var _records: Array[Dictionary] = []


func info(message: String, context: Dictionary = {}) -> bool:
	return log_message(INFO, message, context)


func warning(message: String, context: Dictionary = {}) -> bool:
	return log_message(WARNING, message, context)


func error(message: String, context: Dictionary = {}) -> bool:
	return log_message(ERROR, message, context)


func log_message(severity: String, message: String, context: Dictionary = {}) -> bool:
	if severity not in SEVERITIES or message.strip_edges().is_empty():
		return false

	var record := {
		"severity": severity,
		"message": message,
		"context": context.duplicate(true),
	}
	_records.append(record)

	var context_suffix := ""
	if not context.is_empty():
		context_suffix = " " + JSON.stringify(context)
	print("[M0][%s] %s%s" % [severity.to_upper(), message, context_suffix])
	return true


func get_records() -> Array[Dictionary]:
	return _records.duplicate(true)


func clear() -> void:
	_records.clear()
