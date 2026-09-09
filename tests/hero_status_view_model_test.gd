extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("hero status VM projects live momentum and run growth without mutating state", func() -> void:
		_test_status_projection(harness)
	)
	print("HERO STATUS VIEW MODEL TESTS: tests=1 assertions=%d failures=%d" % [harness.assertions, harness.failures])


func _test_status_projection(harness: TestHarness) -> void:
	var manager := HandManagerScript.new()
	var controller := ControllerScript.new(manager)
	var started: Variant = controller.start({
		"battle_seed": "hero-status-vm",
		"deployed_hero_ids": [5, 6, 8],
		"free_skill_ids": ["pieceBlock", "pieceDamageUp", "markBurn", "executeStrike"],
		"stage_id": "counter",
	})
	harness.assert_true(started.ok, started.message)
	if not started.ok:
		manager.free()
		return
	var state: Dictionary = controller._runtime.component("state")
	var growth_port: Variant = controller._runtime.component("growth_port")
	var growth_result: Dictionary = growth_port.stage_batch({"requests": [
		{"id": "fistMastery", "target": {"type": "hero", "id": 6}, "stacks": 3},
		{"id": "flamePractice", "target": {"type": "hero", "id": 5}, "stacks": 2},
	]})
	harness.assert_true(growth_result.get("ok", false), "real GrowthPort staging must succeed")
	for momentum in [0, 3, 5]:
		for hero: Dictionary in state["player_heroes"]:
			if int(hero["id"]) == 6:
				hero["fist_momentum"] = momentum
		var momentum_vm: Dictionary = controller.view_model()
		harness.assert_equal(_hero(momentum_vm["heroes"]["ally"], 6)["statuses"].size(), 1 if momentum == 0 else 2)
		if momentum > 0:
			harness.assert_equal(_hero(momentum_vm["heroes"]["ally"], 6)["statuses"][0]["stacks"], momentum)
	var source_before: Dictionary = state.duplicate(true)
	state["ally_puppet_martyr_active"] = true
	state["battle_growth_flags"]["flame_investment_used"] = true
	var vm: Dictionary = controller.view_model()
	var heroes: Array = vm["heroes"]["ally"]
	var ning: Dictionary = _hero(heroes, 6)
	var flame: Dictionary = _hero(heroes, 5)
	var qianji: Dictionary = _hero(heroes, 8)
	harness.assert_equal(ning["status_lines"], ["拳势 ×5", "拳意 ×3"])
	harness.assert_equal(flame["status_lines"], ["炎华 ×2", "引火已用"])
	harness.assert_equal(qianji["status_lines"], ["殉道"])
	harness.assert_equal(ning["permanent_growth"]["fistMastery"], 3)
	harness.assert_equal(flame["permanent_growth"]["flamePractice"], 2)
	harness.assert_true(qianji["ally_puppet_martyr_active"])
	harness.assert_equal(
		ControllerScript._hero_status_lines({"id": 301, "ex_skill": "fist", "fist_momentum": 3}),
		["拳势 ×3"],
		"enemy fist heroes must expose momentum too",
	)
	vm["heroes"]["ally"][1]["statuses"].clear()
	vm["heroes"]["ally"][1]["status_lines"].clear()
	harness.assert_equal(_hero(controller.view_model()["heroes"]["ally"], 6)["status_lines"], ["拳势 ×5", "拳意 ×3"])
	harness.assert_equal(state["player_heroes"], source_before["player_heroes"], "view_model must not mutate hero state")
	harness.assert_true(state["ally_puppet_martyr_active"])
	manager.free()


static func _hero(heroes: Array, hero_id: int) -> Dictionary:
	for hero: Dictionary in heroes:
		if int(hero.get("id", 0)) == hero_id:
			return hero
	return {}

