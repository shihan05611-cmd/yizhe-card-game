extends RefCounted

const RngScript = preload("res://core/rng.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")

signal deferred_result


class CountedSource extends RefCounted:
	var random: DeterministicRng
	var calls := 0

	func _init(seed: Variant) -> void:
		random = RngScript.seeded(seed)

	func next() -> float:
		calls += 1
		return random.next()


func run(harness: TestHarness) -> void:
	harness.run_test("Run random commit preserves mixed helpers and primitive count", func() -> void:
		_test_commit_helpers(harness)
	)
	harness.run_test("Run random false and command error replay primitive draws", func() -> void:
		_test_failure_replay(harness)
	)
	harness.run_test("Run random transaction tokens are opaque and single-use", func() -> void:
		_test_tokens(harness)
	)
	harness.run_test("Run random rejects nesting and asynchronous results", func() -> void:
		_test_reentry_and_async(harness)
	)
	harness.run_test("Run random rollback never rewinds shared raw entropy", func() -> void:
		_test_shared_source_boundary(harness)
	)


func _test_commit_helpers(harness: TestHarness) -> void:
	var source := CountedSource.new("M5-01-success")
	var control := RngScript.seeded("M5-01-success")
	var errors: Array[String] = []
	var random := TransactionalRandomScript.new(source, errors)
	harness.assert_true(random.is_valid(), "; ".join(errors))
	var actual: Variant = random.with_transaction(func() -> Array:
		return [
			random.next(),
			random.float_range(-2.0, 7.0),
			random.int_range(4, 19),
			random.pick(["a", "b", "c", "d"]),
			random.shuffle([1, 2, 3, 4, 5]),
		]
	, errors)
	var expected := [
		control.next(),
		control.float_range(-2.0, 7.0),
		control.int_range(4, 19),
		control.pick(["a", "b", "c", "d"]),
		control.shuffle([1, 2, 3, 4, 5]),
	]
	harness.assert_equal(errors, [])
	harness.assert_equal(actual, expected)
	harness.assert_equal(source.calls, 8)
	harness.assert_equal(random.next(), control.next())
	harness.assert_equal(source.calls, 9)


func _test_failure_replay(harness: TestHarness) -> void:
	var control := RngScript.seeded("M5-01-replay")
	var random := TransactionalRandomScript.new(RngScript.seeded("M5-01-replay"))
	var errors: Array[String] = []
	harness.assert_equal(random.with_transaction(func() -> bool:
		random.shuffle([1, 2, 3, 4])
		return false
	, errors), false)
	harness.assert_equal(errors, [])
	harness.assert_equal(random.with_transaction(func() -> Array:
		return [random.int_range(0, 10), random.float_range(10.0, 20.0), random.next()]
	, errors), [control.int_range(0, 10), control.float_range(10.0, 20.0), control.next()])

	var expected_after_error := control.shuffle(["x", "y", "z"])
	var failed: Variant = random.with_transaction(func() -> Variant:
		random.pick([1, 2, 3])
		random.next()
		return random.command_error("transaction failed")
	, errors)
	harness.assert_equal(failed, null)
	harness.assert_contains(errors[0], "transaction failed")
	harness.assert_equal(random.shuffle(["x", "y", "z"]), expected_after_error)


func _test_tokens(harness: TestHarness) -> void:
	var left := TransactionalRandomScript.new(RngScript.seeded("left"))
	var right := TransactionalRandomScript.new(RngScript.seeded("right"))
	var errors: Array[String] = []
	var first: Variant = left.begin_transaction(errors)
	left.next()
	for fake: Variant in [null, [], {}]:
		errors.clear()
		harness.assert_false(left.commit_transaction(fake, errors))
		harness.assert_contains(errors[0], "token")
	errors.clear()
	harness.assert_false(right.commit_transaction(first, errors))
	harness.assert_contains(errors[0], "token")
	errors.clear()
	harness.assert_true(left.rollback_transaction(first, errors))
	harness.assert_equal(errors, [])
	for method in [Callable(left, "commit_transaction"), Callable(left, "rollback_transaction")]:
		errors.clear()
		harness.assert_false(method.call(first, errors))
		harness.assert_contains(errors[0], "token")
	var second: Variant = left.begin_transaction(errors)
	harness.assert_true(left.commit_transaction(second, errors))
	errors.clear()
	harness.assert_false(left.commit_transaction(second, errors))
	harness.assert_contains(errors[0], "token")


func _test_reentry_and_async(harness: TestHarness) -> void:
	var random := TransactionalRandomScript.new(RngScript.seeded("reentry"))
	var control := RngScript.seeded("reentry")
	var errors: Array[String] = []
	var result: Variant = random.with_transaction(func() -> bool:
		random.next()
		var nested_errors: Array[String] = []
		random.begin_transaction(nested_errors)
		return true
	, errors)
	harness.assert_equal(result, null)
	harness.assert_contains(errors[0], "active")
	harness.assert_false(random.has_active_transaction())
	harness.assert_equal(random.next(), control.next(), "outer nesting fault must replay its draw")

	errors.clear()
	result = random.with_transaction(func() -> Signal:
		return deferred_result
	, errors)
	harness.assert_equal(result, null)
	harness.assert_contains(errors[0], "synchronous")
	harness.assert_false(random.has_active_transaction())
	harness.assert_equal(random.with_transaction(func() -> bool: return true, errors), true)


func _test_shared_source_boundary(harness: TestHarness) -> void:
	var raw := CountedSource.new("shared-raw")
	var control := RngScript.seeded("shared-raw")
	var random := TransactionalRandomScript.new(raw)
	var errors: Array[String] = []
	harness.assert_equal(random.with_transaction(func() -> bool:
		harness.assert_equal(random.next(), control.next())
		return false
	, errors), false)
	harness.assert_equal(raw.calls, 1)
	var raw_combat_value: float = raw.next()
	harness.assert_equal(raw_combat_value, control.next())
	harness.assert_equal(raw.calls, 2)
	harness.assert_true(random.next() != raw_combat_value)
	harness.assert_equal(raw.calls, 2, "Run replay must consume no additional raw entropy")
