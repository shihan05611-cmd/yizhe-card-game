extends RefCounted

const TestHarness = preload("res://tests/support/test_harness.gd")
const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const MapSystemScript = preload("res://systems/roguelike/map_system.gd")
const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")


func run(harness: TestHarness) -> void:
	harness.run_test("Inkjade real Run keeps four occupied pieces distinct from vacancies and deaths", func() -> void:
		_test_run_occupancy_and_death(harness)
	)
	harness.run_test("Inkjade elite vacancies are empty while relic VM supplies catalog tooltip data", func() -> void:
		_test_elite_and_relic_vm(harness)
	)
	harness.run_test("Inkjade relic strip stays inside the HUD width and keeps overflow scrollable", func() -> void:
		_test_relic_width(harness)
	)


func _test_run_occupancy_and_death(harness: TestHarness) -> void:
	var launched := _launch("inkjade-ui-four", false)
	harness.assert_equal(launched["errors"], [])
	if launched["controller"] == null:
		return
	var controller: Variant = launched["controller"]
	var vm: Dictionary = controller.view_model()
	harness.assert_equal(_occupied(vm["teams"]["ally"]["slots"]), [false, true, false, true, true, true])
	var screen: Variant = _screen(vm)
	for slot_number in [1, 3]:
		var empty: Control = screen.ally_board.slot_for_target({"slot": slot_number})
		harness.assert_false(empty.chess_art.visible)
		harness.assert_false(empty.hp_bar.visible)
		harness.assert_false(empty.death_mark.visible)
		harness.assert_equal(empty.tooltip_text, "")
		harness.assert_false(empty.slot_label.visible)
	var state: Dictionary = controller._runtime.component("state")
	state["allies"][1]["hp"] = 0.0
	state["allies"][1]["alive"] = false
	vm = controller.view_model()
	harness.assert_true(vm["teams"]["ally"]["slots"][1]["occupied"])
	screen.bind_view_model(vm)
	_force_layout(screen)
	var fallen: Control = screen.ally_board.slot_for_target({"slot": 2})
	harness.assert_true(fallen.chess_art.visible)
	harness.assert_true(fallen.hp_bar.visible)
	harness.assert_true(fallen.death_mark.visible)
	harness.assert_false(fallen.tooltip_text.is_empty())
	_release(screen)
	_cleanup(launched)


func _test_elite_and_relic_vm(harness: TestHarness) -> void:
	var launched := _launch("inkjade-ui-elite", true)
	harness.assert_equal(launched["errors"], [])
	if launched["controller"] == null:
		return
	var controller: Variant = launched["controller"]
	var vm: Dictionary = controller.view_model()
	harness.assert_equal(_occupied(vm["teams"]["enemy"]["slots"]), [true, true, true, false, false, false])
	var relics: Array = vm["relics"]
	harness.assert_equal(relics.map(func(relic: Dictionary) -> String: return relic["id"]), ["spLimitPlus", "fieldBandage"])
	for relic: Dictionary in relics:
		harness.assert_false(str(relic["name"]).is_empty())
		harness.assert_false(str(relic["description"]).is_empty())
	var screen: Variant = _screen(vm)
	var strip: Control = screen.battle_hud.relic_strip
	harness.assert_equal(strip.relic_count(), relics.size())
	var row: Control = strip.get("_row")
	for index in relics.size():
		var item: Control = row.get_child(index)
		harness.assert_equal(item.tooltip_text, "%s\n%s" % [relics[index]["name"], relics[index]["description"]])
	for slot_number in [4, 5, 6]:
		var empty: Control = screen.enemy_board.slot_for_target({"slot": slot_number})
		harness.assert_false(empty.chess_art.visible)
		harness.assert_false(empty.hp_bar.visible)
		harness.assert_false(empty.death_mark.visible)
		harness.assert_equal(empty.tooltip_text, "")
	_release(screen)
	_cleanup(launched)


func _test_relic_width(harness: TestHarness) -> void:
	var screen: Variant = _screen(_minimal_vm())
	var strip: Control = screen.battle_hud.relic_strip
	var relics: Array[Dictionary] = []
	for index in 30:
		relics.append({"id": "width-%d" % index, "name": "遗物%d" % index, "description": "宽度合同"})
	strip.bind_relics(relics)
	_force_layout(screen)
	var row: Control = strip.get("_row")
	harness.assert_equal(strip.position.y, 59.0)
	harness.assert_equal(strip.size.y, 39.0)
	harness.assert_true(strip.get_global_rect().end.x <= screen.size.x + 0.01)
	harness.assert_true(row.get_combined_minimum_size().x > strip.size.x)
	harness.assert_true(row.size.x >= row.get_combined_minimum_size().x)
	harness.assert_equal(strip.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	harness.assert_equal(strip.get_child_count(), 1)
	harness.assert_equal(row.get_child_count(), 30)
	_release(screen)


func _launch(seed: String, elite: bool) -> Dictionary:
	var errors: Array[String] = []
	var catalogs := ContentCatalogScript.build(errors)
	if not errors.is_empty():
		return {"errors": errors, "controller": null}
	var state := RunContractScript.create()
	var random := TransactionalRandomScript.new(RngScript.seeded(seed), errors)
	var lifecycle := RunLifecycleScript.new(state, catalogs, random, errors)
	if not lifecycle.start_run(errors) or not lifecycle.choose_starting_hero(state["initial_hero_choice_ids"][0], errors):
		return {"errors": errors, "controller": null}
	state["relic_ids"] = ["spLimitPlus", "fieldBandage"]
	var battle: Dictionary = state["map_nodes"].filter(func(node: Dictionary) -> bool:
		return bool(node["available"]) and node["type"] == "battle"
	)[0]
	if not lifecycle.choose_node(battle["id"], errors):
		return {"errors": errors, "controller": null}
	var launch := lifecycle.begin_current_battle(errors)
	if launch.is_empty():
		return {"errors": errors, "controller": null}
	if elite:
		var elite_node: Dictionary = state["map_nodes"].filter(func(node: Dictionary) -> bool:
			return node["type"] == "elite"
		)[0]
		launch["encounter"] = MapSystemScript.resolve_encounter(
			catalogs["roguelike_content"], elite_node, RngScript.seeded("%s-encounter" % seed), errors,
		)
	if not errors.is_empty():
		return {"errors": errors, "controller": null}
	var manager := HandManagerScript.new()
	var controller := ControllerScript.new(manager)
	var started: Variant = controller.start(launch)
	if not started.ok:
		errors.append(started.message)
		return {"errors": errors, "controller": null}
	return {"errors": errors, "controller": controller, "manager": manager, "lifecycle": lifecycle, "progress": launch["run_progress"]}


static func _occupied(slots: Array) -> Array:
	return slots.map(func(slot: Dictionary) -> bool: return bool(slot["occupied"]))


static func _screen(vm: Dictionary) -> Variant:
	var screen: Variant = BattleScreenScene.instantiate()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.position = Vector2.ZERO
	screen.size = Vector2(1200, 700)
	Engine.get_main_loop().root.add_child(screen)
	screen.hand_view.animate_layout = false
	screen.bind_view_model(vm)
	_force_layout(screen)
	return screen


static func _minimal_vm() -> Dictionary:
	return {"initialized": true, "session": {"active": true, "halted": false, "settled": false}, "battle": {"round": 1, "phase": "player_input", "game_over": false, "result": null}, "resources": {"sp": 6, "sp_max": 10}, "teams": {"ally": {"slots": []}, "enemy": {"slots": []}}, "heroes": {"ally": [], "enemy": []}, "piles": {"draw": 0, "hand": 0, "discard": 0, "exhaust": 0}, "hand": [], "relics": [], "logs": [], "presentation": {"speed": 1.0, "auto_battle": false, "pending_events": []}, "fatal": null}


static func _force_layout(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children():
		_force_layout(child)


static func _release(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


static func _cleanup(launched: Dictionary) -> void:
	if launched.get("manager") != null:
		launched["manager"].free()
