extends SceneTree
const H = preload("res://tests/support/test_harness.gd")
const S = preload("res://tests/hero_expansion_card_test.gd")
func _init() -> void:
	var h := H.new(); S.new().run(h); quit(0 if h.failures == 0 else 1)
