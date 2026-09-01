class_name Invariant
extends RefCounted


static func require(condition: bool, message: String) -> bool:
	if condition:
		return true

	var detail := message.strip_edges()
	if detail.is_empty():
		detail = "contract failed without a diagnostic message"
	var failure_message := "Invariant violation: %s" % detail
	push_error(failure_message)
	assert(condition, failure_message)
	return false
