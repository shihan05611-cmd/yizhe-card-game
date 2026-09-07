extends RefCounted

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunStateAdapterScript = preload("res://autoload/run_state.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("M5 Run default is closed and excludes removed authorities", func() -> void:
		_test_default_shape(harness)
	)
	harness.run_test("M5 Run snapshot isolates nested ownership arrays", func() -> void:
		_test_snapshot_isolation(harness)
	)
	harness.run_test("M5 Run transition publishes only a valid true result", func() -> void:
		_test_atomic_transition(harness)
	)
	harness.run_test("M5 Run reset preserves the authority Dictionary identity", func() -> void:
		_test_reset_in_place(harness)
	)
	harness.run_test("RunState autoload remains a thin contract adapter", func() -> void:
		_test_autoload_adapter(harness)
	)


func _test_default_shape(harness: TestHarness) -> void:
	var state: Dictionary = RunContractScript.create()
	var errors: Array[String] = []
	harness.assert_true(RunContractScript.validate(state, errors), "; ".join(errors))
	harness.assert_equal(state["status"], "idle")
	harness.assert_false(state["active"])
	harness.assert_equal(state["chapter"], 0)
	harness.assert_equal(state["max_chapters"], 3)
	harness.assert_equal(state["map_rows"], 3)
	harness.assert_equal(state["map_columns"], 10)
	harness.assert_equal(state["free_skill_ids"], [])
	harness.assert_equal(state["hero_deployment_slots"], {})
	harness.assert_equal(state["piece_slots"].size(), 6)
	harness.assert_false(state.has("skill_library"), "Web skillLibrary authority must not survive")
	harness.assert_false(state.has("equipped_free_skill_ids"), "equipment slots must not survive")
	harness.assert_false(state.has("selected_shentong_id"), "dormant shentong is not active Run state")
	harness.assert_false(state.has("shentong_uses_left"), "shentong uses are not active Run state")

	state["free_skill_ids"] = ["smallHeal", "smallHeal", "markBurn"]
	state["hero_deployment_slots"] = {"1": 3, "4": 6}
	state["front_hero_ids"] = [1]
	state["back_hero_ids"] = [4]
	errors.clear()
	harness.assert_true(
		RunContractScript.validate(state, errors),
		"free-skill ownership is a multiset: %s" % "; ".join(errors)
	)
	state["front_hero_ids"] = [4]
	errors.clear()
	harness.assert_false(RunContractScript.validate(state, errors))
	harness.assert_contains(errors[0], "slot-sorted row views")
	state["front_hero_ids"] = [1]
	state["hero_deployment_slots"]["4"] = 3
	errors.clear()
	harness.assert_false(RunContractScript.validate(state, errors))
	harness.assert_contains(errors[0], "unique slots")
	state["hero_deployment_slots"]["4"] = 6
	state["unexpected"] = true
	errors.clear()
	harness.assert_false(RunContractScript.validate(state, errors))
	harness.assert_contains(errors[0], "non-canonical")


func _test_snapshot_isolation(harness: TestHarness) -> void:
	var state: Dictionary = RunContractScript.create()
	state["free_skill_ids"] = ["smallHeal", "smallHeal"]
	state["piece_slots"][0]["hp_ratio"] = 0.25
	var errors: Array[String] = []
	var copy: Dictionary = RunContractScript.snapshot(state, errors)
	harness.assert_equal(errors, [])
	copy["free_skill_ids"].append("markBurn")
	copy["piece_slots"][0]["hp_ratio"] = 1.0
	harness.assert_equal(state["free_skill_ids"], ["smallHeal", "smallHeal"])
	harness.assert_equal(state["piece_slots"][0]["hp_ratio"], 0.25)


func _test_atomic_transition(harness: TestHarness) -> void:
	var state: Dictionary = RunContractScript.create()
	var identity := state
	var errors: Array[String] = []
	var committed := RunContractScript.transition(state, func(candidate: Dictionary) -> bool:
		candidate["active"] = true
		candidate["status"] = "heroSelect"
		candidate["chapter"] = 1
		candidate["currency"] = 30
		candidate["free_skill_ids"] = ["smallHeal", "smallHeal"]
		return true
	, errors)
	harness.assert_true(committed, "; ".join(errors))
	harness.assert_true(state == identity)
	harness.assert_equal(state["currency"], 30)
	harness.assert_equal(state["free_skill_ids"], ["smallHeal", "smallHeal"])

	var before := RunContractScript.snapshot(state)
	harness.assert_false(RunContractScript.transition(state, func(candidate: Dictionary) -> bool:
		candidate["currency"] = 999
		return false
	, errors))
	harness.assert_equal(state, before, "false transition must not publish its candidate")

	errors.clear()
	harness.assert_false(RunContractScript.transition(state, func(candidate: Dictionary) -> bool:
		candidate["currency"] = -1
		return true
	, errors))
	harness.assert_equal(state, before, "invalid candidate must not publish")
	harness.assert_contains(errors[0], "currency")

	errors.clear()
	harness.assert_false(RunContractScript.transition(state, func(_candidate: Dictionary) -> Variant:
		return "not-a-boolean"
	, errors))
	harness.assert_equal(state, before)
	harness.assert_contains(errors[0], "boolean")


func _test_reset_in_place(harness: TestHarness) -> void:
	var state: Dictionary = RunContractScript.create()
	var alias := state
	state["active"] = true
	state["status"] = "map"
	state["chapter"] = 2
	state["currency"] = 77
	state["free_skill_ids"] = ["markBurn", "markBurn"]
	state["temporary"] = "remove me"
	var errors: Array[String] = []
	harness.assert_true(RunContractScript.reset(state, errors), "; ".join(errors))
	harness.assert_true(state == alias)
	harness.assert_equal(state, RunContractScript.create())
	harness.assert_false(state.has("temporary"))


func _test_autoload_adapter(harness: TestHarness) -> void:
	var adapter: Node = RunStateAdapterScript.new()
	var errors: Array[String] = []
	harness.assert_equal(adapter.snapshot(errors), RunContractScript.create())
	harness.assert_equal(errors, [])
	harness.assert_false(adapter.has_active_run())
	harness.assert_true(adapter.transition(func(candidate: Dictionary) -> bool:
		candidate["active"] = true
		candidate["status"] = "heroSelect"
		candidate["chapter"] = 1
		return true
	, errors), "; ".join(errors))
	harness.assert_true(adapter.has_active_run())
	harness.assert_true(adapter.reset_run(errors), "; ".join(errors))
	harness.assert_false(adapter.has_active_run())
	adapter.free()
