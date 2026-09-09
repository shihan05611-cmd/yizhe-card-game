extends RefCounted
const TestHarness = preload("res://tests/support/test_harness.gd")
const Controller = preload("res://app/battle_controller.gd")
const Hand = preload("res://autoload/hand_manager.gd")

func run(harness: TestHarness) -> void:
	harness.run_test("pressOpening validates break mark and applies two pursuit stacks", func() -> void:
		var manager := Hand.new()
		var controller := Controller.new(manager)
		var started: Variant = controller.start({"battle_seed":"press-opening", "deployed_hero_ids":[6, 7], "free_skill_ids":["pieceBlock"], "stage_id":"counter", "exclusive_card_ids":["exclusive:pressOpening"]})
		harness.assert_true(started.ok, started.message)
		if not started.ok: return
		var state: Dictionary = controller._runtime.component("state")
		var buffs: Variant = controller._runtime.component("buffs")
		var card: Dictionary = {}
		for item: Dictionary in controller.view_model()["hand"]:
			if item["card_id"] == "exclusive:pressOpening": card = item
		harness.assert_false(card.is_empty())
		var before_sp: float = float(state["sp"])
		var no_mark_play := controller.play_card(card["instance_id"])
		harness.assert_false(no_mark_play.ok)
		var blocked := controller.inspect_card(card["instance_id"])
		harness.assert_false(blocked.details["playable"])
		harness.assert_equal(state["sp"], before_sp)
		harness.assert_true(buffs.apply_unit(state["enemies"][0], "breakMarked"))
		var ally: Dictionary = state["allies"][0]
		ally["atk"] = 99.0
		var siege_hero: Dictionary = _hero(state["player_heroes"], 7)
		var hero_energy_before: float = float(siege_hero["energy"])
		var other_hero: Dictionary = _hero(state["player_heroes"], 6)
		var other_energy_before: float = float(other_hero["energy"])
		var enemy_hp_before: float = float(state["enemies"][0]["hp"])
		state["allies"][1]["atk"] = 99.0
		state["allies"][0]["atk"] = 99.0
		var usable := controller.inspect_card(card["instance_id"])
		harness.assert_true(usable.details["playable"], usable.message)
		var played := controller.play_card(card["instance_id"])
		harness.assert_true(played.ok, played.message)
		harness.assert_equal(state["sp"], before_sp - 1.0)
		harness.assert_equal(siege_hero["energy"], hero_energy_before + 20.0)
		harness.assert_equal(other_hero["energy"], other_energy_before)
		harness.assert_equal(buffs.get_unit_stacks(ally, "pursuit"), 2)
		harness.assert_equal(played.details["effect_result"]["target_slot"], 1, "atk tie chooses lowest slot")
		harness.assert_equal(state["enemies"][0]["hp"], enemy_hp_before, "pressOpening does not attack immediately")
		manager.free()
	)

static func _hero(heroes: Array, hero_id: int) -> Dictionary:
	for hero: Dictionary in heroes:
		if int(hero.get("id", 0)) == hero_id:
			return hero
	return {}
