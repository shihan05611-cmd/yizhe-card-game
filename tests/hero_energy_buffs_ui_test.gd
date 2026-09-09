extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const HeroEnergyItemScene: PackedScene = preload("res://scenes/battle/hero_energy_item.tscn")


func run(harness: TestHarness) -> void:
	await _test_energy_meter_and_legacy_nodes(harness)
	await _test_statuses_refresh_without_legacy_fallback(harness)
	await _test_portrait_frame_layouts(harness)


func _test_energy_meter_and_legacy_nodes(harness: TestHarness) -> void:
	harness.tests += 1
	var item := await _item()
	item.bind_hero(_hero({"energy": 60.0, "max_energy": 120.0}))
	await _frames(2)
	var ring: Control = item.get_node("Row/PortraitFrame/EnergyRing")
	harness.assert_equal(ring.ratio(), 0.5)
	_assert_legacy_nodes_hidden(harness, item)

	item.bind_hero(_hero({"energy": 240.0, "max_energy": 120.0}))
	await _frames(2)
	harness.assert_equal(ring.ratio(), 1.0, "energy above its maximum must clamp the ring")
	_assert_legacy_nodes_hidden(harness, item)
	_release(item)


func _test_statuses_refresh_without_legacy_fallback(harness: TestHarness) -> void:
	harness.tests += 1
	var item := await _item()
	item.bind_hero(_hero({
		"status_lines": ["旧版状态 不应显示"],
		"statuses": [
			{"id": "fist", "name": "拳势", "stacks": 3, "description": "拳势说明"},
			{"id": "flame", "name": "炎华", "stacks": 1, "description": "炎华说明"},
			{"id": "expired", "name": "失效", "stacks": 0, "description": "零层不显示"},
		],
	}))
	await _frames(2)
	var flow: HFlowContainer = item.get_node("Row/Info/StatusFlow")
	harness.assert_true(flow.visible)
	harness.assert_equal(flow.get_child_count(), 2, "zero-stack statuses must not create labels")
	var fist: Label = flow.get_child(0)
	var flame: Label = flow.get_child(1)
	harness.assert_equal(fist.text, "拳势 ×3")
	harness.assert_equal(fist.tooltip_text, "拳势说明")
	harness.assert_equal(flame.text, "炎华")
	harness.assert_equal(flame.tooltip_text, "炎华说明")

	item.bind_hero(_hero({
		"status_lines": ["旧版状态 即使非空也不能回退"],
		"statuses": [],
	}))
	await _frames(2)
	harness.assert_false(flow.visible, "an explicit empty statuses list must suppress legacy status_lines")
	harness.assert_equal(flow.get_child_count(), 0)

	item.bind_hero(_hero({
		"statuses": [{"id": "guard", "name": "守势", "stacks": 2, "description": "守势说明"}],
	}))
	await _frames(2)
	harness.assert_equal(flow.get_child_count(), 1, "rebinding must remove old status labels")
	var guard: Label = flow.get_child(0)
	harness.assert_equal(guard.text, "守势 ×2")
	harness.assert_equal(guard.tooltip_text, "守势说明")
	_release(item)


func _test_portrait_frame_layouts(harness: TestHarness) -> void:
	harness.tests += 1
	var item := await _item()
	item.bind_hero(_hero({"statuses": []}))
	await _frames(2)
	var portrait_frame: Control = item.get_node("Row/PortraitFrame")
	harness.assert_true(is_equal_approx(portrait_frame.size.x, portrait_frame.size.y), "single portrait frame must be square")

	item.set_compact(true)
	await _frames(2)
	harness.assert_true(is_equal_approx(portrait_frame.size.x, portrait_frame.size.y), "compact portrait frame must be square")
	_release(item)


func _assert_legacy_nodes_hidden(harness: TestHarness, item: Control) -> void:
	harness.assert_false((item.get_node("Row/Info/EnergyBar") as Control).visible)
	harness.assert_false((item.get_node("Row/Info/EnergyLabel") as Control).visible)
	harness.assert_false((item.get_node("Row/Info/RoleLabel") as Control).visible)
	harness.assert_false((item.get_node("Row/PortraitFrame/PortraitHalo") as Control).visible)


func _item() -> Control:
	var host := Control.new()
	host.size = Vector2(400, 260)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var item: Control = HeroEnergyItemScene.instantiate()
	item.position = Vector2(80, 50)
	item.size = Vector2(220, 160)
	host.add_child(item)
	await _frames(2)
	return item


func _hero(overrides: Dictionary = {}) -> Dictionary:
	var hero := {
		"id": 1,
		"name": "赤焰",
		"side": "ally",
		"energy": 0.0,
		"max_energy": 120.0,
	}
	for key: String in overrides:
		hero[key] = overrides[key]
	return hero


func _frames(count: int) -> void:
	for _index in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _release(item: Control) -> void:
	var host := item.get_parent()
	if host != null:
		host.queue_free()
