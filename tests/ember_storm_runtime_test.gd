extends RefCounted

const BridgeFixture = preload("res://tests/m5_battle_bridge_test.gd")
const ContextsScript = preload("res://core/contexts.gd")

func run(harness: TestHarness) -> void:
	harness.run_test("Ember Storm live death hook does not amplify a single burn layer", func() -> void:
		_check_spread(harness, 1)
	)
	harness.run_test("Ember Storm live death hook spreads integer layers and settles immediately", func() -> void:
		_check_spread(harness, 11)
	)

func _check_spread(harness: TestHarness, stacks: int) -> void:
	var helper := BridgeFixture.new()
	var fixture: Dictionary = helper._fighting_fixture("ember-runtime-%d" % stacks, harness)
	fixture.state.relic_ids = ["emberStorm"]
	var started: Dictionary = helper._start_adapter(fixture, harness)
	if not started.result.ok: return
	var controller: Variant = started.adapter.controller()
	var runtime: Variant = controller._runtime
	var state: Dictionary = runtime.component("state")
	var buffs: Variant = runtime.component("buffs")
	var target: Dictionary = state.enemies[0]
	var remaining: Array = state.enemies.filter(func(unit: Dictionary) -> bool:
		return unit.alive and unit.id != target.id
	)
	harness.assert_true(remaining.size() > 1)
	var before := {}
	for unit: Dictionary in remaining: before[unit.id] = unit.hp
	var errors: Array[String] = []
	harness.assert_true(buffs.apply_unit(target, "burn", stacks, null, errors), "; ".join(errors))
	var effect := ContextsScript.create_effect_context({
		"source_type":"free_skill", "source_id":"ember_probe", "source_name":"灼烧扩散验证",
		"source_side":"ally", "source_actor_id":0,
		"counts_as_basic_attack":false, "counts_as_attack":false,
	}, errors)
	var context := ContextsScript.create_damage_context({
		"target_id":target.id, "raw_amount":float(target.max_hp)*10.0, "category":"direct",
		"effect":effect, "dealer_type":"hero", "dealer_name":"灼烧扩散验证", "dealer_id":0,
		"attacker_unit_id":0, "can_crit":false, "crit_rate":0.0,
		"guaranteed_crit":false, "can_block":false,
	}, errors)
	harness.assert_equal(errors, [])
	var result: Dictionary = runtime.component("damage").apply(target, context, {}, errors)
	harness.assert_equal(errors, [])
	harness.assert_true(result.get("died",false))
	var each := stacks / remaining.size()
	for unit: Dictionary in remaining:
		harness.assert_equal(buffs.get_unit_stacks(unit,"burn"),each)
		if each == 0:
			harness.assert_equal(unit.hp,before[unit.id],"A single layer must not grow to one layer per survivor")
		else:
			harness.assert_true(unit.hp < before[unit.id],"Spread burn must deal damage before a turn ends")
	harness.assert_equal(controller.view_model().fatal,null)
	started.manager.free()
