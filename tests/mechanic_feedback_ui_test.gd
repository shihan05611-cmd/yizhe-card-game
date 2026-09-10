extends RefCounted

const Screen = preload("res://scenes/battle/battle_screen.tscn")
const Fixture = preload("res://tests/battle_scene_test.gd")

func run(harness: RefCounted) -> void:
	harness.run_test("relic trigger and devour resource events visibly update their real HUD controls", func() -> void:
		var screen: Control = Screen.instantiate()
		Engine.get_main_loop().root.add_child(screen)
		screen.bind_view_model(fixture_vm())
		harness.assert_equal(screen.battle_hud.sp_label.text, "4")
		harness.assert_false(screen.battle_hud.sp_drain_notice.visible)
		screen.present_event(devour_event(), 0.5)
		harness.assert_equal(screen.battle_hud.sp_label.text, "3")
		harness.assert_true(screen.battle_hud.sp_drain_notice.visible)
		harness.assert_true(screen.battle_hud.sp_drain_notice.text.contains("1 SP"))
		harness.assert_true(screen.feedback_instances().any(func(node: Node) -> bool: return node.get_script() == preload("res://ui/art/devour_pulse.gd")))
		screen.present_event(relic_event(), 0.5)
		harness.assert_equal(screen.battle_hud.relic_strip.last_trigger_id, "arcConductor")
		harness.assert_true(screen.battle_hud.relic_strip._items["arcConductor"].get_node("TriggerGlow").visible)
		harness.assert_true(screen.battle_hud.relic_trigger_notice.visible)
		harness.assert_equal(screen.battle_hud.relic_trigger_notice.text, "奥术导体 · 已触发")
		var fallback := devour_event()
		fallback["payload"].merge({"kind": "energy_drain", "old_sp": 0.0, "new_sp": 0.0, "amount": 10, "target": {"hero_id": 1, "old_energy": 20, "new_energy": 10}}, true)
		screen.present_event(fallback, 0.5)
		harness.assert_equal(screen.battle_hud.sp_label.text, "0")
		harness.assert_equal(screen.ally_heroes.item_for_hero(1).energy_bar.value, 10.0)
		screen.present_event({"kind": "combat", "event_id": "resourceChanged", "payload": {"resource": "sp", "old_sp": 0.0, "new_sp": 2.0, "reason": "round_recovery"}}, 0.2)
		harness.assert_equal(screen.battle_hud.sp_label.text, "2")
		screen.reset_presentation()
		harness.assert_false(screen.battle_hud.relic_trigger_notice.visible)
		harness.assert_false(screen.battle_hud.sp_drain_notice.visible)
		harness.assert_equal(screen.feedback_instances().size(), 0)
		screen.free()
	)

static func fixture_vm() -> Dictionary:
	var vm := Fixture._vm()
	vm["resources"] = {"sp": 4.0, "sp_max": 4.0}
	vm["relics"] = [{"id": "arcConductor", "name": "奥术导体", "description": "消耗SP时对敌方全体造成遗物伤害"}]
	vm["teams"]["enemy"]["slots"][0]["special_id"] = "devourer"
	vm["teams"]["enemy"]["slots"][0]["occupied_slot_ids"] = [1, 2]
	vm["teams"]["enemy"]["slots"][1]["occupied"] = false
	vm["teams"]["enemy"]["slots"][1]["alive"] = false
	return vm

static func devour_event() -> Dictionary:
	return {"kind": "combat", "event_id": "enemySpecialTriggered", "source": {"type": "enemy_special", "id": "devourer"}, "visual_target": {"kind": "unit", "side": "enemy", "unit_id": 101, "slot": 1}, "payload": {"special_id": "devourer", "kind": "sp_drain", "actor": {"id": 101, "side": "enemy", "slot": 1}, "old_sp": 4.0, "new_sp": 3.0, "amount": 1}}

static func relic_event() -> Dictionary:
	return {"kind": "combat", "event_id": "relicTriggered", "source": {"type": "relic", "id": "arcConductor"}, "payload": {"relic_id": "arcConductor", "relic_name": "奥术导体", "trigger_phase": "resolved"}}
