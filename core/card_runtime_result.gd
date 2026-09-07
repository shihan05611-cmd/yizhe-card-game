class_name CardRuntimeResult
extends RefCounted

const OK := "ok"
const INVALID_ARGUMENT := "invalid_argument"
const INVALID_CARD := "invalid_card"
const INVALID_PILE := "invalid_pile"
const CARD_NOT_FOUND := "card_not_found"
const HAND_FULL := "hand_full"
const DECK_EMPTY := "deck_empty"
const VALIDATOR_REJECTED := "validator_rejected"
const SUCCESS_LIMIT_REACHED := "success_limit_reached"
const QUEUE_BUSY := "queue_busy"
const QUEUE_HALTED := "queue_halted"
const EXECUTION_FAILED := "execution_failed"
const COMMITTED_FAILURE := "committed_failure"

var ok := false
var code := ""
var message := ""
var details: Dictionary = {}


func _init(
	result_ok: bool = false,
	result_code: String = INVALID_ARGUMENT,
	result_message: String = "",
	result_details: Dictionary = {},
) -> void:
	ok = result_ok
	code = result_code
	message = result_message
	details = result_details.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"code": code,
		"message": message,
		"details": details.duplicate(true),
	}
