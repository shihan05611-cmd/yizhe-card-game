extends RefCounted

const RunScreenScript = preload("res://ui/run/run_screen.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("Run normal rewards render cards before independent relic choices", func() -> void:
		_test_normal_reward_stage(harness)
	)


func _test_normal_reward_stage(harness: TestHarness) -> void:
	var cards := [
		{"id": "reward:skill:smallHeal", "type": "freeSkill", "name": "小回血", "description": ""},
		{"id": "reward:exclusive:exclusive:siege", "type": "exclusiveCard", "name": "破势", "description": ""},
	]
	var relics := [
		{"id": "reward:relic:fieldBandage", "type": "relic", "name": "军医绷带", "description": ""},
		{"id": "reward:relic:spLimitPlus", "type": "relic", "name": "配给筹码", "description": ""},
	]
	harness.assert_equal(RunScreenScript.normal_reward_stage(cards + relics), "card")
	harness.assert_equal(RunScreenScript.normal_reward_stage(relics), "relic")
	harness.assert_equal(RunScreenScript.normal_reward_stage(cards), "card")
	harness.assert_equal(RunScreenScript.normal_reward_stage([]), "")
	var state := {
		"current_node_id": "battle-node",
		"map_nodes": [{"id": "battle-node", "type": "battle"}],
	}
	var initial_text := _rendered_text(state, cards + relics)
	harness.assert_true("战利品 · 卡牌三选一" in initial_text)
	harness.assert_true("卡牌三选一" in initial_text)
	harness.assert_false("遗物三选一" in initial_text)
	harness.assert_true("跳过卡牌" in initial_text)
	var relic_text := _rendered_text(state, relics)
	harness.assert_true("战利品 · 遗物三选一" in relic_text)
	harness.assert_true("遗物三选一" in relic_text)
	harness.assert_false("卡牌三选一" in relic_text)
	harness.assert_true("跳过遗物" in relic_text)


func _rendered_text(state: Dictionary, options: Array) -> Array[String]:
	var screen := RunScreenScript.new()
	var page := VBoxContainer.new()
	screen._reward_page(page, state.merged({"reward_options": options}))
	var result: Array[String] = []
	_collect_text(page, result)
	page.free()
	screen.free()
	return result


func _collect_text(node: Node, output: Array[String]) -> void:
	if node is Label or node is Button:
		output.append(node.text)
	for child: Node in node.get_children():
		_collect_text(child, output)