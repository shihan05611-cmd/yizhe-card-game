extends SceneTree

## Windowed evidence for the Run formation vacancy and relic-strip presentation.
## This intentionally uses a separate fixture and does not alter existing captures.

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const MapSystemScript = preload("res://systems/roguelike/map_system.gd")
const ControllerScript = preload("res://app/battle_controller.gd")
const HandManagerScript = preload("res://autoload/hand_manager.gd")
const BattleScreenScene: PackedScene = preload("res://scenes/battle/battle_screen.tscn")
const OUTPUT_DIR := "res://tests/artifacts/inkjade_relic_formation"

var _errors: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)) != OK:
		_errors.append("cannot create relic formation evidence directory")
		_finish()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1200, 700))
	await _frames(8)
	await _capture("01_real_run_four_piece_relics.png", false)
	await _capture("02_real_run_elite_vacancies.png", true)
	_finish()


func _capture(filename: String, elite: bool) -> void:
	var launched := _launch("inkjade-capture-elite" if elite else "inkjade-capture-four", elite)
	if not launched["errors"].is_empty() or launched["controller"] == null:
		_errors.append("%s launch: %s" % [filename, "; ".join(launched["errors"])])
		return
	var screen: Variant = BattleScreenScene.instantiate()
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1200, 700)
	root.add_child(screen)
	screen.hand_view.animate_layout = false
	screen.bind_view_model(launched["controller"].view_model())
	await _frames(10)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var save_error := image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename)))
	if save_error != OK:
		_errors.append("%s save: %s" % [filename, error_string(save_error)])
	else:
		print("RELIC FORMATION CAPTURE: %s" % ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename)))
	screen.free()
	launched["manager"].free()
	await _frames(3)


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
	if state["piece_slots"][1]["piece_class_id"] != "shield":
		errors.append("new Run shield must occupy the middle front slot")
		return {"errors": errors, "controller": null}
	state["relic_ids"] = ["spLimitPlus", "fieldBandage", "arcConductor", "emberStorm", "rationChip"]
	var battle: Dictionary = state["map_nodes"].filter(func(node: Dictionary) -> bool:
		return bool(node["available"]) and node["type"] == "battle"
	)[0]
	if not lifecycle.choose_node(battle["id"], errors):
		return {"errors": errors, "controller": null}
	var launch := lifecycle.begin_current_battle(errors)
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
	return {"errors": errors, "controller": controller, "manager": manager}


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _finish() -> void:
	for error: String in _errors:
		push_error(error)
	print("RELIC FORMATION CAPTURE failures=%d" % _errors.size())
	quit(0 if _errors.is_empty() else 1)
