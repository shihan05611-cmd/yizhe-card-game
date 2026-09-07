class_name CatalogValidation
extends RefCounted


static func non_empty_id(value: String, label: String, errors: Array[String]) -> bool:
	if not value.strip_edges().is_empty():
		return true
	errors.append("%s id must not be empty" % label)
	return false


static func positive_int_id(value: int, label: String, errors: Array[String]) -> bool:
	if value > 0:
		return true
	errors.append("%s id must be a positive integer: %d" % [label, value])
	return false


static func unique_id(
	value: Variant,
	seen: Dictionary,
	label: String,
	errors: Array[String],
) -> bool:
	if seen.has(value):
		errors.append("duplicate %s id: %s" % [label, str(value)])
		return false
	seen[value] = true
	return true


static func enum_value(
	value: Variant,
	allowed: Array,
	field_name: String,
	errors: Array[String],
) -> bool:
	if value in allowed:
		return true
	errors.append("invalid %s: %s" % [field_name, str(value)])
	return false


static func finite_number(value: Variant, field_name: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT and is_finite(value):
		return true
	errors.append("%s must be a finite number" % field_name)
	return false


static func non_negative_number(
	value: Variant,
	field_name: String,
	errors: Array[String],
) -> bool:
	if not finite_number(value, field_name, errors):
		return false
	if value >= 0:
		return true
	errors.append("%s must be non-negative" % field_name)
	return false


static func non_negative_int(value: Variant, field_name: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_INT and value >= 0:
		return true
	errors.append("%s must be a non-negative integer" % field_name)
	return false


static func positive_int(value: Variant, field_name: String, errors: Array[String]) -> bool:
	if typeof(value) == TYPE_INT and value > 0:
		return true
	errors.append("%s must be a positive integer" % field_name)
	return false


static func non_empty_string(value: String, field_name: String, errors: Array[String]) -> bool:
	if not value.strip_edges().is_empty():
		return true
	errors.append("%s must not be empty" % field_name)
	return false


static func string_array(
	values: Array,
	field_name: String,
	errors: Array[String],
	allow_empty: bool = true,
) -> bool:
	var valid := true
	if not allow_empty and values.is_empty():
		errors.append("%s must not be empty" % field_name)
		valid = false
	for value in values:
		if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty():
			errors.append("%s entries must be non-empty strings" % field_name)
			valid = false
	return valid
