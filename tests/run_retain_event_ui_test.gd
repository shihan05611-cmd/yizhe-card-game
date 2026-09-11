extends RefCounted

const RunScreenScript = preload("res://ui/run/run_screen.gd")
const RunSessionScript = preload("res://app/run_session.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("Run retain-card event renders every duplicate card copy separately", func() -> void:
		_test_retain_event_page(harness)
	)
	harness.run_test("RunSession selects one concrete duplicate card from a real retain event", func() -> void:
		_test_session_retain_event(harness)
	)


func _test_retain_event_page(harness: TestHarness) -> void:
	var screen := RunScreenScript.new()
	screen._vm = {"event": {"kind": "retain_card", "name": "留墨", "description": "选择具体牌副本。", "options": [
		{"key": "free:0", "card_id": "free:pieceAction", "name": "棋子行动", "description": "额外行动。", "base_cost": 1, "inventory_index": 0, "copy_ordinal": 1, "retained": false},
		{"key": "free:1", "card_id": "free:pieceAction", "name": "棋子行动", "description": "额外行动。", "base_cost": 1, "inventory_index": 1, "copy_ordinal": 2, "retained": false},
		{"key": "free:2", "card_id": "free:smallHeal", "name": "小回血", "description": "回复。", "base_cost": 0, "inventory_index": 2, "copy_ordinal": 1, "retained": true},
	]}}
	var body := VBoxContainer.new()
	screen._event_page(body, {"chapter": 1})
	var labels: Array[String] = []
	var buttons: Array[String] = []
	_collect_text(body, labels, buttons)
	harness.assert_true("棋子行动 · 第 1 份" in labels)
	harness.assert_true("棋子行动 · 第 2 份" in labels)
	harness.assert_true("1 SP · 副本序号 1" in labels)
	harness.assert_true("1 SP · 副本序号 2" in labels)
	harness.assert_true("已留墨" in labels)
	harness.assert_true("保留：回合结束时不会被丢弃，仍占用手牌上限。" in labels)
	harness.assert_equal(buttons.count("留墨保留"), 2)
	harness.assert_true("跳过留墨" in buttons)
	screen._vm["catalog"] = {"skills": {"pieceAction": {"name": "棋子行动"}}}
	harness.assert_equal(screen._retained_card_display({"free_skill_ids": ["pieceAction", "pieceAction"]}, "free:1"), "棋子行动 · 第 2 份")
	body.free()
	screen.free()


func _test_session_retain_event(harness: TestHarness) -> void:
	var save_path := "res://.godot/test-logs/retain-event-ui-session.json"
	var absolute_path := ProjectSettings.globalize_path(save_path)
	DirAccess.remove_absolute(absolute_path)
	var session := RunSessionScript.new({}, save_path)
	var event := _reach_retain_event(session, harness)
	if event.is_empty():
		DirAccess.remove_absolute(absolute_path)
		return
	var options: Array = event["options"]
	var duplicate_actions: Array = options.filter(func(option: Dictionary) -> bool:
		return option["card_id"] == "free:pieceAction"
	)
	harness.assert_equal(duplicate_actions.size(), 2)
	harness.assert_true(duplicate_actions[0]["key"] != duplicate_actions[1]["key"])
	var selected_key: String = duplicate_actions[1]["key"]
	var errors: Array[String] = []
	harness.assert_true(session.execute({"type": "select_retained_card", "key": selected_key}, errors), "; ".join(errors))
	var state: Dictionary = session.snapshot()
	harness.assert_equal(state["status"], "map")
	harness.assert_equal(state["retained_card_keys"], [selected_key])
	DirAccess.remove_absolute(absolute_path)


func _reach_retain_event(session: Variant, harness: TestHarness) -> Dictionary:
	for seed_index in range(32):
		var errors: Array[String] = []
		if not session.new_run("retain-event-ui-%d" % seed_index, errors):
			continue
		var state: Dictionary = session.snapshot()
		if not session.execute({"type": "choose_starting_hero", "hero_id": state["initial_hero_choice_ids"][0]}, errors):
			continue
		for _step in range(16):
			state = session.snapshot()
			var status: String = state["status"]
			if status == "event":
				var event: Dictionary = session.view_model()["event"]
				if event.get("kind") == "retain_card":
					return event
				session.execute({"type": "leave_node"}, errors)
				continue
			if status == "fighting":
				session.lifecycle.complete_current_battle(true, errors)
				continue
			if status == "reward":
				var options: Array = state["reward_options"]
				if options.is_empty():
					break
				if options[0]["type"] == "hero":
					session.execute({"type": "recruit_hero", "hero_id": options[0]["payload_id"]}, errors)
				else:
					session.execute({"type": "select_reward", "option_id": options[0]["id"]}, errors)
				continue
			if status in ["shop", "forge"]:
				session.execute({"type": "leave_node"}, errors)
				continue
			if status != "map":
				break
			var chosen := {}
			for preferred_type in ["event", "battle", "shop", "forge"]:
				for node: Dictionary in state["map_nodes"]:
					if node["available"] and node["type"] == preferred_type:
						chosen = node
						break
				if not chosen.is_empty():
					break
			if chosen.is_empty() or not session.execute({"type": "choose_node", "node_id": chosen["id"]}, errors):
				break
	harness.fail("did not reach a retain-card event in deterministic Run paths")
	return {}


func _collect_text(node: Node, labels: Array[String], buttons: Array[String]) -> void:
	if node is Label:
		labels.append(node.text)
	elif node is Button:
		buttons.append(node.text)
	for child: Node in node.get_children():
		_collect_text(child, labels, buttons)