extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const Catalog = preload("res://data/presentation/skill_fx_catalog.gd")
const PlayerScene = preload("res://scenes/effects/skill_fx_player.tscn")

const EXPECTED_SCENES := {
	"vignette": "res://scenes/effects/vignette.tscn",
	"caption": "res://scenes/effects/caption.tscn",
	"burst": "res://scenes/effects/burst.tscn",
	"beam": "res://scenes/effects/beam.tscn",
	"streak": "res://scenes/effects/streak.tscn",
	"multiBurst": "res://scenes/effects/multi_target.tscn",
	"multiMark": "res://scenes/effects/multi_target.tscn",
	"field": "res://scenes/effects/field.tscn",
}


func run(harness: TestHarness) -> void:
	var tests_before := harness.tests
	var assertions_before := harness.assertions
	var failures_before := harness.failures
	harness.run_test("every visible primitive comes from its PackedScene", func() -> void:
		_test_packed_scene_instances(harness)
	)
	harness.run_test("multi-target markers resolve stable side and slot anchors", func() -> void:
		_test_multi_target_anchors(harness)
	)
	harness.run_test("preview cleanup removes the active scene tree", func() -> void:
		_test_cleanup(harness)
	)
	harness.run_test("unknown skill uses generic scene while unknown event is diagnostic only", func() -> void:
		_test_fallback_and_unknown_event(harness)
	)
	print("M4-4 SKILL FX SCENE PLAYER TESTS: tests=%d assertions=%d failures=%d" % [
		harness.tests - tests_before,
		harness.assertions - assertions_before,
		harness.failures - failures_before,
	])


func _test_packed_scene_instances(harness: TestHarness) -> void:
	var player: Control = PlayerScene.instantiate()
	var definition := Catalog.get_fx_definition("ult", "fist")
	var steps := {
		"vignette": {"prim": "vignette"},
		"caption": {"prim": "caption"},
		"burst": {"prim": "burst", "ring": "impact"},
		"beam": {"prim": "beam"},
		"streak": {"prim": "streak", "variant": "slash", "count": 1},
		"multiBurst": {"prim": "multiBurst"},
		"multiMark": {"prim": "multiMark"},
		"field": {"prim": "field"},
	}
	for prim: String in steps:
		var payload := {"targets": [{"side": "enemy", "slot": 1}]} if prim.begins_with("multi") else {}
		var nodes: Array = player.instantiate_primitive(steps[prim], definition, payload)
		harness.assert_true(not nodes.is_empty(), "%s should instantiate" % prim)
		for node in nodes:
			harness.assert_equal(node.scene_file_path, EXPECTED_SCENES[prim])
			harness.assert_equal(node.get_meta("fx_primitive"), prim)
			node.free()
	player.free()


func _test_multi_target_anchors(harness: TestHarness) -> void:
	var player: Control = PlayerScene.instantiate()
	player.set_anchor_resolver(func(target: Dictionary) -> Dictionary:
		return {"position": Vector2(100.0 + 80.0 * int(target.get("slot", 0)), 250.0 if target.get("side") == "ally" else 120.0)}
	)
	var payload := {"targets": [
		{"side": "enemy", "slot": 1, "intensity": 0.5},
		{"side": "enemy", "slot": 4, "intensity": 1.8},
	]}
	var nodes: Array = player.instantiate_primitive(
		{"prim": "multiBurst", "gap": 60, "duration_ms": 320},
		Catalog.get_fx_definition("ult", "burn01"), payload
	)
	harness.assert_equal(nodes.size(), 2)
	harness.assert_equal(nodes[0].position, Vector2(180.0, 120.0))
	harness.assert_equal(nodes[1].position, Vector2(420.0, 120.0))
	harness.assert_equal(nodes[0].get_meta("fx_context")["visual_target"]["slot"], 1)
	harness.assert_equal(nodes[1].get_meta("fx_context")["delay_ms"], 60)
	for node in nodes:
		node.free()
	player.free()


func _test_cleanup(harness: TestHarness) -> void:
	var player: Control = PlayerScene.instantiate()
	player.preview_skill_fx("ult", "shadow", {"side": "enemy", "slot": 2})
	harness.assert_false(player.get_active_effect().is_empty())
	harness.assert_equal(player.get_child_count(), 1)
	player.clear_visual_effect()
	harness.assert_true(player.get_active_effect().is_empty())
	harness.assert_equal(player.get_child_count(), 0)
	player.free()


func _test_fallback_and_unknown_event(harness: TestHarness) -> void:
	var player: Control = PlayerScene.instantiate()
	player.preview_skill_fx("skill", "unmapped", {"skill_name": "通用技能", "side": "ally", "slot": 0})
	harness.assert_equal(player.get_child_count(), 1)
	var root: Node = player.get_child(0)
	harness.assert_equal(root.scene_file_path, "res://scenes/effects/fx_instance.tscn")
	harness.assert_equal(root.get_child(0).scene_file_path, "res://scenes/effects/generic_skill_fx.tscn")
	player.clear_visual_effect()
	var diagnostic_count: int = player.diagnostics().size()
	player.emit_visual_effect("invalid-event", {})
	harness.assert_equal(player.get_child_count(), 0)
	harness.assert_equal(player.diagnostics().size(), diagnostic_count + 1)
	player.free()
