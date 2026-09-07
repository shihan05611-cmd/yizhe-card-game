extends RefCounted

const Contexts = preload("res://core/contexts.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("context enums preserve Web stable values", func() -> void:
		_test_enum_values(harness)
	)
	harness.run_test("effect context snapshots metadata and removes hero action quota", func() -> void:
		_test_effect_context(harness)
	)
	harness.run_test("context factories reject enum id and finite-number violations", func() -> void:
		_test_invalid_contexts(harness)
	)
	harness.run_test("delayed context forcibly disables crit guaranteed crit and block", func() -> void:
		_test_delayed_context(harness)
	)
	harness.run_test("legacy adapter labels basic pursuit counter and delayed damage", func() -> void:
		_test_legacy_adapter(harness)
	)
	harness.run_test("death contexts derive source and sacrifice suppresses kill effects", func() -> void:
		_test_death_contexts(harness)
	)
	harness.run_test("nested effect and death contexts are isolated snapshots", func() -> void:
		_test_context_isolation(harness)
	)


func _test_enum_values(harness: TestHarness) -> void:
	harness.assert_equal(Contexts.UNIT_SIDE.values(), ["unknown", "ally", "enemy"])
	harness.assert_equal(Contexts.DAMAGE_CATEGORY.values(), ["direct", "delayed", "effect"])
	harness.assert_equal(
		Contexts.DEATH_SOURCE_KIND.values(),
		["unknown", "ally", "enemy", "system", "sacrifice"],
	)
	harness.assert_equal(Contexts.EFFECT_SOURCE_TYPE.values().size(), 14)
	harness.assert_equal(Contexts.EFFECT_SOURCE_TYPE["ENEMY_SPECIAL"], "enemy_special")


func _test_effect_context(harness: TestHarness) -> void:
	var input := {
		"source_type": Contexts.EFFECT_SOURCE_TYPE["FREE_SKILL"],
		"source_id": "burnStackBase",
		"source_name": "基础叠层",
		"source_side": Contexts.UNIT_SIDE["ALLY"],
		"source_actor_id": 2,
		"counts_as_skill_cast": true,
		"counts_as_hero_action": true,
		"spent_skill_points": true,
		"free_cast": false,
		"counts_as_attack": false,
		"triggers_enemy_kill_effects": false,
	}
	var errors: Array[String] = []
	var context := Contexts.create_effect_context(input, errors)
	harness.assert_equal(errors, [])
	harness.assert_equal(context["source_id"], "burnStackBase")
	harness.assert_true(context["counts_as_skill_cast"])
	harness.assert_true(context["spent_skill_points"])
	harness.assert_false(context["free_cast"])
	harness.assert_false(context["triggers_enemy_kill_effects"])
	harness.assert_false(context.has("counts_as_hero_action"))
	input["source_id"] = "changed"
	harness.assert_equal(context["source_id"], "burnStackBase")


func _test_invalid_contexts(harness: TestHarness) -> void:
	var errors: Array[String] = []
	harness.assert_equal(Contexts.create_effect_context({"source_type": "spell"}, errors), {})
	harness.assert_true(not errors.is_empty())
	harness.assert_contains(errors[0], "source_type")
	harness.assert_equal(Contexts.create_effect_context({"source_actor_id": []}, errors), {})
	harness.assert_contains(errors[0], "source_actor_id")
	harness.assert_equal(Contexts.create_damage_context({"raw_amount": NAN}, errors), {})
	harness.assert_contains(errors[0], "raw_amount")
	harness.assert_equal(Contexts.create_damage_context({"crit_rate": INF}, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("crit_rate")))
	harness.assert_equal(Contexts.create_damage_context({"target_id": false}, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("target_id")))
	harness.assert_equal(Contexts.create_death_context({"source_kind": "damage"}, errors), {})
	harness.assert_true(errors.any(func(message: String) -> bool: return message.contains("source_kind")))
	harness.assert_equal(Contexts.create_effect_context([], errors), {})
	harness.assert_contains(errors[0], "Dictionary")


func _test_delayed_context(harness: TestHarness) -> void:
	var delayed := Contexts.create_damage_context({
		"target_id": 1,
		"raw_amount": 50,
		"category": Contexts.DAMAGE_CATEGORY["DELAYED"],
		"effect": _effect({"source_type": Contexts.EFFECT_SOURCE_TYPE["DELAYED_DAMAGE"]}),
		"can_crit": true,
		"guaranteed_crit": true,
		"can_block": true,
	})
	harness.assert_false(delayed["can_crit"])
	harness.assert_false(delayed["guaranteed_crit"])
	harness.assert_false(delayed["can_block"])
	harness.assert_equal(delayed["category"], "delayed")


func _test_legacy_adapter(harness: TestHarness) -> void:
	var basic := _legacy("normal", "ally", "piece")
	var pursuit := Contexts.create_legacy_damage_context({
		"target_id": 1,
		"raw_amount": 10,
		"source": "遗物追击",
		"dealer_side": "ally",
		"dealer_type": "piece",
		"damage_kind": "pursuit",
	})
	var counter := _legacy("反击", "enemy", "counter")
	var delayed := Contexts.create_legacy_damage_context({
		"target_id": 1,
		"raw_amount": 10,
		"source": "灼烧",
		"dealer_side": "ally",
		"dealer_type": "dot",
		"can_crit": true,
		"guaranteed_crit": true,
		"can_block": true,
	})
	harness.assert_equal(
		[basic["effect"]["counts_as_attack"], basic["effect"]["counts_as_basic_attack"], basic["effect"]["source_type"]],
		[true, true, "basic_attack"],
	)
	harness.assert_equal(
		[pursuit["effect"]["counts_as_attack"], pursuit["effect"]["counts_as_basic_attack"], pursuit["effect"]["source_type"]],
		[true, false, "pursuit"],
	)
	harness.assert_equal(
		[counter["effect"]["counts_as_attack"], counter["effect"]["counts_as_basic_attack"], counter["effect"]["source_type"]],
		[true, false, "counter"],
	)
	harness.assert_equal(delayed["effect"]["source_type"], "delayed_damage")
	harness.assert_false(delayed["can_crit"])
	harness.assert_false(delayed["can_block"])


func _test_death_contexts(harness: TestHarness) -> void:
	var damage := Contexts.create_damage_context({
		"target_id": 1,
		"raw_amount": 20,
		"effect": _effect(),
	})
	var death := Contexts.create_death_context_from_damage(damage)
	harness.assert_equal(death["source_kind"], Contexts.DEATH_SOURCE_KIND["ALLY"])
	harness.assert_equal(death["source_side"], Contexts.UNIT_SIDE["ALLY"])
	harness.assert_equal(death["source_actor_id"], 9)
	var sacrifice := Contexts.create_sacrifice_death_context({
		"source_side": Contexts.UNIT_SIDE["ALLY"],
		"source_name": "献祭",
		"source_actor_id": 3,
	})
	harness.assert_equal(sacrifice["source_kind"], Contexts.DEATH_SOURCE_KIND["SACRIFICE"])
	harness.assert_equal(sacrifice["effect"]["source_type"], Contexts.EFFECT_SOURCE_TYPE["SACRIFICE"])
	harness.assert_false(sacrifice["triggers_enemy_kill_effects"])
	harness.assert_false(sacrifice["effect"]["triggers_enemy_kill_effects"])


func _test_context_isolation(harness: TestHarness) -> void:
	var effect_input := _effect()
	var damage_input := {
		"target_id": 1,
		"raw_amount": 10,
		"effect": effect_input,
	}
	var first := Contexts.create_damage_context(damage_input)
	var second := Contexts.create_damage_context(damage_input)
	effect_input["source_id"] = "mutated-input"
	first["effect"]["source_id"] = "mutated-output"
	harness.assert_equal(second["effect"]["source_id"], "basic_attack")
	harness.assert_equal(Contexts.create_damage_context(damage_input)["effect"]["source_id"], "mutated-input")
	var death := Contexts.create_death_context_from_damage(second)
	second["effect"]["source_id"] = "later-damage-mutation"
	harness.assert_equal(death["effect"]["source_id"], "basic_attack")


func _effect(overrides: Dictionary = {}) -> Dictionary:
	var input := {
		"source_type": Contexts.EFFECT_SOURCE_TYPE["BASIC_ATTACK"],
		"source_id": "basic_attack",
		"source_name": "普攻",
		"source_side": Contexts.UNIT_SIDE["ALLY"],
		"source_actor_id": 9,
		"counts_as_attack": true,
		"counts_as_basic_attack": true,
	}
	input.merge(overrides, true)
	return Contexts.create_effect_context(input)


func _legacy(source: String, side: String, dealer_type: String) -> Dictionary:
	return Contexts.create_legacy_damage_context({
		"target_id": 1,
		"raw_amount": 10,
		"source": source,
		"dealer_side": side,
		"dealer_type": dealer_type,
	})
