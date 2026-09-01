class_name DeterministicRng
extends RefCounted

const UINT32_MASK := 0xffffffff
const UINT32_MODULUS := 4294967296.0
const FNV_OFFSET_BASIS := 2166136261
const FNV_PRIME := 16777619
const GOLDEN_RATIO_U32 := 0x9e3779b9
const MULBERRY_INCREMENT := 0x6d2b79f5
const DEFAULT_STREAM_NAMES: Array[String] = [
	"combat",
	"allyPolicy",
	"enemyPolicy",
	"run",
]

var _state: int


func _init(seed: Variant = 0) -> void:
	_state = normalize_seed(seed)
	if _state == 0:
		_state = MULBERRY_INCREMENT


static func seeded(seed: Variant) -> DeterministicRng:
	return DeterministicRng.new(seed)


static func normalize_seed(seed: Variant) -> int:
	if typeof(seed) == TYPE_INT:
		return _u32(seed)
	if typeof(seed) == TYPE_FLOAT:
		if is_nan(seed):
			return hash_utf16_fnv1a("NaN")
		if is_inf(seed):
			return hash_utf16_fnv1a("-Infinity" if seed < 0.0 else "Infinity")
		var truncated: float = floor(seed) if seed >= 0.0 else ceil(seed)
		var reduced := fmod(truncated, UINT32_MODULUS)
		if reduced < 0.0:
			reduced += UINT32_MODULUS
		return int(reduced)

	var text := "" if seed == null else str(seed)
	return hash_utf16_fnv1a(text)


static func hash_utf16_fnv1a(text: String) -> int:
	var hash_value := FNV_OFFSET_BASIS
	for code_unit in _utf16_code_units(text):
		hash_value = _u32(hash_value ^ code_unit)
		hash_value = _imul_u32(hash_value, FNV_PRIME)
	return hash_value


static func derive_seed(seed: Variant, stream_name: Variant) -> Variant:
	var name := "" if stream_name == null else str(stream_name)
	if name.is_empty():
		return null

	var hash_value := _u32(normalize_seed(seed) ^ GOLDEN_RATIO_U32)
	for code_unit in _utf16_code_units(name):
		hash_value = _u32(hash_value ^ code_unit)
		hash_value = _imul_u32(hash_value, FNV_PRIME)
		hash_value = _u32(hash_value ^ _urshift_u32(hash_value, 13))
	return hash_value


static func create_named_streams(
	seed: Variant,
	names: Array = DEFAULT_STREAM_NAMES,
) -> Dictionary:
	if names.is_empty():
		return {}

	var streams := {}
	for raw_name in names:
		var name := "" if raw_name == null else str(raw_name)
		if name.is_empty() or streams.has(name):
			return {}
		var derived: Variant = derive_seed(seed, name)
		if derived == null:
			return {}
		streams[name] = DeterministicRng.new(derived)
	return streams


func next_u32() -> int:
	_state = _u32(_state + MULBERRY_INCREMENT)
	var value := _state
	value = _imul_u32(_u32(value ^ _urshift_u32(value, 15)), _u32(value | 1))
	var mixed := _imul_u32(_u32(value ^ _urshift_u32(value, 7)), _u32(value | 61))
	value = _u32(value ^ _u32(value + mixed))
	return _u32(value ^ _urshift_u32(value, 14))


func next() -> float:
	return float(next_u32()) / UINT32_MODULUS


func float_range(minimum: float = 0.0, maximum: float = 1.0) -> Variant:
	if not is_finite(minimum) or not is_finite(maximum) or maximum < minimum:
		return null
	return minimum + next() * (maximum - minimum)


func int_range(minimum: int, maximum: int) -> Variant:
	if maximum < minimum:
		return null
	var sampled: Variant = float_range(float(minimum), float(maximum) + 1.0)
	if sampled == null:
		return null
	return int(floor(sampled))


func pick(values: Array) -> Variant:
	if values.is_empty():
		return null
	var index: Variant = int_range(0, values.size() - 1)
	if index == null:
		return null
	return values[int(index)]


func shuffle(values: Array) -> Array:
	var copy := values.duplicate(false)
	for index in range(copy.size() - 1, 0, -1):
		var swap_index: Variant = int_range(0, index)
		if swap_index == null:
			return []
		var temporary: Variant = copy[index]
		copy[index] = copy[int(swap_index)]
		copy[int(swap_index)] = temporary
	return copy


static func _utf16_code_units(text: String) -> Array[int]:
	var code_units: Array[int] = []
	for index in range(text.length()):
		var codepoint := text.unicode_at(index)
		if codepoint <= 0xffff:
			code_units.append(codepoint)
		else:
			var surrogate_value := codepoint - 0x10000
			code_units.append(0xd800 + (surrogate_value >> 10))
			code_units.append(0xdc00 + (surrogate_value & 0x3ff))
	return code_units


static func _u32(value: int) -> int:
	return value & UINT32_MASK


static func _urshift_u32(value: int, bits: int) -> int:
	return _u32(value) >> bits


static func _imul_u32(left: int, right: int) -> int:
	var left_low := _u32(left) & 0xffff
	var left_high := (_u32(left) >> 16) & 0xffff
	var right_low := _u32(right) & 0xffff
	var right_high := (_u32(right) >> 16) & 0xffff
	var low_product := left_low * right_low
	var cross_product := left_high * right_low + left_low * right_high
	return _u32(low_product + (cross_product << 16))
