extends RefCounted

const BattleBootstrap = preload("res://app/battle_bootstrap.gd")
const CombatPresentationStream = preload("res://app/combat_presentation_stream.gd")
const Contexts = preload("res://core/contexts.gd")


func run(harness: RefCounted) -> void:
	harness.run_test("production BattleBootstrap wires authored damage and block Buffs into DamagePipeline", func() -> void:
		var errors: Array[String] = []
		var built := BattleBootstrap.create({
			"battle_seed": 260910,
			"deployed_hero_ids": [1],
			"free_skill_ids": [],
			"stage_id": "counter",
		}, CombatPresentationStream.new(), errors)
		harness.assert_equal(errors, [])
		harness.assert_false(built.is_empty())
		if built.is_empty():
			return
		var runtime: Variant = built["runtime"]
		var state: Dictionary = built["state"]
		var buffs: Variant = runtime.component("buffs", errors)
		var damage: Variant = runtime.component("damage", errors)
		harness.assert_equal(errors, [])
		var attacker: Dictionary = state["allies"][0]
		var target: Dictionary = state["enemies"][0]
		target["hp"] = 1000.0
		target["max_hp"] = 1000.0
		target["base_block_rate"] = 0.0

		var baseline := _deal(damage, attacker, target, false, errors)
		harness.assert_equal(errors, [])
		harness.assert_equal(baseline["dealt"], 20.0)

		harness.assert_true(buffs.apply_side("ally", "pieceDamageUp", 1, 1, errors))
		var increased := _deal(damage, attacker, target, false, errors)
		harness.assert_equal(increased["dealt"], 25.0, "pieceDamageUp applies +25% in the production pipeline")
		harness.assert_true(buffs.clear_side("ally", "pieceDamageUp", errors))

		harness.assert_true(buffs.apply_unit(attacker, "vexed", 1, 1, errors))
		var vexed := _deal(damage, attacker, target, false, errors)
		harness.assert_equal(vexed["dealt"], 15.0, "vexed reduces the attacker's direct damage by 25%")
		harness.assert_true(buffs.clear_unit(attacker, "vexed", errors))

		harness.assert_true(buffs.apply_unit(target, "bloodShiftVulnerable", 1, 1, errors))
		var vulnerable := _deal(damage, attacker, target, false, errors)
		harness.assert_equal(vulnerable["dealt"], 25.0, "blood shift vulnerable raises received direct damage by 25%")
		harness.assert_true(buffs.clear_unit(target, "bloodShiftVulnerable", errors))
		harness.assert_true(buffs.apply_unit(target, "bloodShiftGuard", 1, 1, errors))
		var guarded := _deal(damage, attacker, target, false, errors)
		harness.assert_equal(guarded["dealt"], 15.0, "blood shift guard lowers received direct damage by 25%")
		harness.assert_true(buffs.clear_unit(target, "bloodShiftGuard", errors))

		# Use the live bootstrap catalog object to make the authored block bonus
		# deterministic. The callback must read it after construction.
		built["catalogs"]["tuning"]["tempBlockBonus"].value = 1.0
		harness.assert_true(buffs.apply_side("enemy", "tempBlock", 1, 1, errors))
		var blocked := _deal(damage, attacker, target, true, errors)
		harness.assert_true(blocked["blocked"])
		harness.assert_equal(blocked["dealt"], 10.0, "temporary block reaches the production block callback")
		harness.assert_equal(errors, [])
	)


static func _deal(
	damage: Variant,
	attacker: Dictionary,
	target: Dictionary,
	can_block: bool,
	errors: Array[String],
) -> Dictionary:
	target["hp"] = 1000.0
	target["alive"] = true
	var effect := Contexts.create_effect_context({
		"source_type": "basic_attack",
		"source_id": "buff_runtime_probe",
		"source_name": "Buff实测",
		"source_side": attacker["side"],
		"source_actor_id": attacker["id"],
		"counts_as_basic_attack": true,
		"counts_as_attack": true,
	}, errors)
	var context := Contexts.create_damage_context({
		"target_id": target["id"],
		"raw_amount": 20.0,
		"category": "direct",
		"effect": effect,
		"dealer_type": "piece",
		"dealer_id": attacker["id"],
		"dealer_name": "Buff实测",
		"attacker_unit_id": attacker["id"],
		"can_crit": false,
		"can_block": can_block,
	}, errors)
	return damage.apply(target, context, {}, errors)
