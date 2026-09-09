extends "res://tests/capture_relic_formation_ui.gd"

## Visual fixture: real Run units and BuffSystem, with one explicit presentation hit.
func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await _frames(2)
	DisplayServer.window_set_size(Vector2i(1200, 700))
	root.size = Vector2i(1200, 700)
	var launched := _launch("status-feedback", false)
	_errors.append_array(launched["errors"])
	if launched["controller"] == null:
		_finish()
		return
	var controller: Variant = launched["controller"]
	var state: Dictionary = controller._runtime.component("state")
	var buffs: Variant = controller._runtime.component("buffs")
	for id: String in ["enchant", "knightChivalry", "march"]:
		if not buffs.apply_unit(state["allies"][1], id): _errors.append("apply " + id)
	if not buffs.apply_unit(state["enemies"][0], "burn", 3): _errors.append("burn")
	if not buffs.apply_unit(state["enemies"][0], "breakMarked"): _errors.append("breakMarked")
	for id: String in ["tempBlock", "pieceDamageUp", "flameLeech", "breakFormation"]:
		if not buffs.apply_side("ally", id): _errors.append("side " + id)
	state["allies"][3]["disarm_turns"] = 1
	var screen: Variant = BattleScreenScene.instantiate()
	root.add_child(screen)
	screen.hand_view.animate_layout = false
	screen.bind_view_model(controller.view_model())
	await _frames(10)
	var unit: Dictionary = state["enemies"][0]
	screen.present_event({
		"kind": "damage", "event_id": "damage_applied",
		"source": {}, "visual_target": {"kind": "unit", "side": "enemy", "slot": 1},
		"payload": {"amount": 18.0, "old_hp": unit["hp"], "new_hp": unit["hp"] - 18.0,
			"target": unit.duplicate(true), "crit": true, "blocked": true},
	}, 2.0)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var output := "res://tests/artifacts/inkjade_relic_formation/03_status_feedback.png"
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	if result != OK: _errors.append("save failed")
	print("STATUS FEEDBACK CAPTURE: " + output)
	screen.free()
	launched["manager"].free()
	_finish()
