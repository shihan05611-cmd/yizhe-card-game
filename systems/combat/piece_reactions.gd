class_name PieceReactions
extends RefCounted

const BattleStateScript = preload("res://core/battle_state.gd")
const ContextsScript = preload("res://core/contexts.gd")
const CombatPortsScript = preload("res://systems/combat/combat_ports.gd")
const PermanentBuffStoreScript = preload("res://systems/buffs/permanent_buff_store.gd")
const TuningValueDefinition = preload("res://data/definitions/tuning_value_definition.gd")

## M2 post-hit reactions extracted from Web executePieceAttack.resolveStrike.
## The primary hit belongs to the caller. This component commits only the
## ordered aftermath and reports the committed prefix if an injected runtime
## boundary fails. It deliberately contains no target selection or attack loop.

const REQUEST_KEYS := [
	"state", "attacker_side", "attacker_id", "defender_side", "defender_id",
	"primary_hit", "defender_alive_after_primary_hit", "permanent_buffs",
]
const DAMAGE_RESULT_KEYS := [
	"dealt", "blocked", "died", "crit", "damage_context", "death_context",
]
const BURN_ID := "burn"
const ENCHANT_ID := "enchant"
const FLAME_ENCHANT_ID := "flameEnchant"
const FLAME_LEECH_ID := "flameLeech"
const KNIGHT_CHIVALRY_ID := "knightChivalry"
const VEXED_ID := "vexed"


static func resolve(request: Variant, ports: Variant) -> Dictionary:
	var prepared := _preflight(request, ports)
	if not prepared["ok"]:
		return CombatPortsScript.fail(prepared["error"])
	return _commit(request, ports, prepared["value"])


static func _commit(request: Dictionary, ports: Variant, prepared: Dictionary) -> Dictionary:
	var state: Dictionary = request["state"]
	var attacker: Dictionary = prepared["attacker"]
	var defender: Dictionary = prepared["defender"]
	var buffs: Variant = prepared["buffs"]
	var damage: Variant = prepared["damage"]
	var tuning: Dictionary = prepared["tuning"]
	var steps: Array[String] = []
	var errors: Array[String] = []

	# Web order 1: a killed martyr puppet explodes before any on-attack add-on.
	if (
		request["primary_hit"]["died"]
		and defender["is_puppet"]
		and defender["puppet_martyr"]
		and attacker["alive"]
	):
		var martyr_context := _damage_context(
			attacker,
			float(attacker["max_hp"]) * 0.05,
			"puppet_martyr",
			"殉道自爆",
			defender["side"],
			defender["id"],
			"piece",
			false,
			0.0,
			0.0,
			errors,
		)
		if martyr_context.is_empty():
			return _failure("martyr damage context failed", steps, errors)
		var martyr_hit: Variant = damage.apply(
			attacker, martyr_context, {"attacker_unit": defender}, errors
		)
		if not _valid_damage_result(martyr_hit):
			return _failure("martyr damage failed", steps, errors)
		steps.append("martyr_damage")
		# BuffSystem intentionally rejects dead holders. Web therefore leaves a
		# lethal martyr victim dead and unbuffed, but vexes every survivor.
		if attacker["alive"]:
			if not buffs.apply_unit(attacker, VEXED_ID, 1, null, errors):
				return _failure("martyr vexed failed", steps, errors)
			steps.append("martyr_vexed")

	# Web order 2: primary attacker's battle + permanent enchant.
	var addon: Dictionary = _apply_enchant(
		attacker, defender, request["permanent_buffs"], prepared, steps, errors
	)
	if not addon["ok"]:
		return addon

	# Web order 3: flame leech heals the defender from the attacker's burn.
	if attacker["alive"] and defender["alive"]:
		var defender_side: String = defender["side"]
		if buffs.has_side(defender_side, FLAME_LEECH_ID):
			var burn_stacks: int = buffs.get_unit_stacks(attacker, BURN_ID)
			if burn_stacks > 0:
				var missing := maxf(0.0, float(defender["max_hp"]) - float(defender["hp"]))
				var heal := _fmt(missing * tuning["ultFlameLeechRatio"] * float(burn_stacks))
				if heal > 0.0:
					var old_hp := float(defender["hp"])
					defender["hp"] = minf(float(defender["max_hp"]), old_hp + heal)
					steps.append("flame_leech_heal")
					var record: Dictionary = ports.call_action("record_heal", {
						"target_id": defender["id"],
						"target_side": defender_side,
						"amount": float(defender["hp"]) - old_hp,
						"source_name": "炎汲",
						"source_effect": ContextsScript.snapshot(request["primary_hit"]["damage_context"]["effect"]),
						"old_hp": old_hp,
						"new_hp": defender["hp"],
					})
					if not record["ok"]:
						return _failure("flame leech record action failed: %s" % record["error"], steps, [])

	# Web order 4: a blocked primary hit can trigger the defending side counter.
	var counter_kind := "none"
	var counter_dealt := 0.0
	if (
		request["primary_hit"]["blocked"]
		and attacker["alive"]
		and defender["alive"]
	):
		var aura_hero: Variant = _counter_aura_hero(state, defender["side"])
		var has_chivalry: bool = buffs.has_unit(defender, KNIGHT_CHIVALRY_ID)
		if aura_hero != null or has_chivalry:
			var super_counter := false
			var attack_up_rate := 0.0
			if has_chivalry:
				if buffs.consume_unit(defender, KNIGHT_CHIVALRY_ID, 1, errors) != 1:
					return _failure("knight chivalry consume failed", steps, errors)
				steps.append("knight_chivalry_consumed")
				attack_up_rate = tuning["ultKnightSuperBonus"]
				super_counter = true
			else:
				var sp_field := "sp" if defender["side"] == "ally" else "enemy_sp"
				var available := float(state[sp_field])
				if available > float(state["counter_threshold"]):
					state[sp_field] = available - 1.0
					steps.append("counter_sp_spent")
					if defender["side"] == "ally":
						var spent_effect := ContextsScript.create_effect_context({
							"source_type": "counter", "source_id": "superCounter",
							"source_name": "超级反击", "source_side": "ally",
							"source_actor_id": defender["id"],
							"spent_skill_points": true, "counts_as_attack": true,
						}, errors)
						if spent_effect.is_empty():
							return _failure("counter SP event context failed", steps, errors)
						var spent: Dictionary = ports.call_action("emit_content_event", {
							"event_id": "skillPointSpent",
							"payload": {
								"round": state["round"], "amount": 1,
								"source_side": "ally", "attacker_id": attacker["id"],
								"defender_id": defender["id"], "source_effect": spent_effect,
							},
						})
						if not spent["ok"]:
							return _failure(
								"counter SP-spent event failed: %s" % spent["error"], steps, [],
							)
					super_counter = true

			var ratio: float = (
				tuning["superCounterDamageRatio"]
				if super_counter
				else tuning["counterDamageRatio"]
			)
			counter_kind = "super" if super_counter else "normal"
			var counter_context := _damage_context(
				attacker,
				float(defender["atk"]) * ratio,
				"counter",
				"超级反击" if super_counter else "反击",
				defender["side"],
				defender["id"],
				"counter",
				true,
				float(defender["crit_rate"]),
				attack_up_rate,
				errors,
			)
			if counter_context.is_empty():
				return _failure("counter damage context failed", steps, errors)
			var counter_hit: Variant = damage.apply(attacker, counter_context, {
				"attacker_unit": defender, "attack_up_rate": attack_up_rate,
			}, errors)
			if not _valid_damage_result(counter_hit):
				return _failure("counter damage failed", steps, errors)
			counter_dealt = float(counter_hit["dealt"])
			steps.append("%s_counter_damage" % counter_kind)
			if super_counter and aura_hero != null:
				if defender["side"] == "ally" and ports.has_action("apply_player_energy"):
					var energy_result: Dictionary = ports.call_action("apply_player_energy", {
						"hero_id": aura_hero["id"], "amount": 5.0,
						"source": {
							"kind": "counter_aura", "defender_id": defender["id"],
							"attacker_id": attacker["id"],
						},
					})
					if not energy_result["ok"]:
						return _failure(
							"counter aura player energy failed after counter commit: %s" % energy_result["error"],
							steps,
							[],
						)
				else:
					aura_hero["energy"] = minf(
						float(aura_hero["max_energy"]), float(aura_hero["energy"]) + 5.0
					)
				steps.append("counter_aura_energy")

			# Web order 5: the countering defender's enchant, guarded by life.
			addon = _apply_enchant(
				defender, attacker, request["permanent_buffs"], prepared, steps, errors
			)
			if not addon["ok"]:
				return addon

	return CombatPortsScript.ok({
		"committed": not steps.is_empty(),
		"steps": steps.duplicate(),
		"counter_kind": counter_kind,
		"counter_dealt": counter_dealt,
	})


static func _apply_enchant(
	source: Dictionary,
	target: Dictionary,
	permanent_buffs: Array,
	prepared: Dictionary,
	steps: Array[String],
	errors: Array[String],
) -> Dictionary:
	if not source["alive"] or not target["alive"]:
		return CombatPortsScript.ok(null)
	var buffs: Variant = prepared["buffs"]
	var stacks: int = buffs.get_unit_stacks(source, ENCHANT_ID)
	if source["side"] == "ally":
		stacks += PermanentBuffStoreScript.get_stacks_from_instances(
			permanent_buffs,
			{"id": FLAME_ENCHANT_ID, "target": {"type": "pieceSlot", "id": source["slot"]}},
			prepared["buff_catalog"], prepared["valid_hero_ids"], errors,
		)
		if not errors.is_empty():
			return _failure("permanent enchant snapshot failed", steps, errors)
	if stacks <= 0:
		return CombatPortsScript.ok(null)
	if not buffs.apply_unit(
		target, BURN_ID, stacks, int(prepared["tuning"]["burnBaseDuration"]), errors
	):
		return _failure("attack enchant burn failed", steps, errors)
	steps.append("attack_enchant_burn")
	return CombatPortsScript.ok(null)


static func _preflight(request: Variant, ports: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _closed_dictionary(request, REQUEST_KEYS):
		return CombatPortsScript.fail("piece reaction request must have a canonical closed shape")
	if (
		typeof(ports) != TYPE_OBJECT or ports == null
		or ports.get_script() != CombatPortsScript or ports.is_valid() != true
	):
		return CombatPortsScript.fail("piece reactions require valid CombatPorts")
	if request["attacker_side"] not in ["ally", "enemy"]:
		return CombatPortsScript.fail("attacker_side must be ally or enemy")
	if request["defender_side"] != _other_side(request["attacker_side"]):
		return CombatPortsScript.fail("defender_side must oppose attacker_side")
	if not _stable_id(request["attacker_id"]) or not _stable_id(request["defender_id"]):
		return CombatPortsScript.fail("attacker_id and defender_id must be stable ids")
	if typeof(request["permanent_buffs"]) != TYPE_ARRAY:
		return CombatPortsScript.fail("permanent_buffs must be a read-only Array snapshot")
	if not BattleStateScript.validate(request["state"], errors):
		return CombatPortsScript.fail("piece reaction state is non-canonical: %s" % errors[0])
	var attacker: Variant = _unit(request["state"], request["attacker_side"], request["attacker_id"])
	var defender: Variant = _unit(request["state"], request["defender_side"], request["defender_id"])
	if attacker == null or defender == null:
		return CombatPortsScript.fail("piece reaction unit identity is absent from state")
	if not _valid_damage_result(request["primary_hit"]):
		return CombatPortsScript.fail("primary_hit must be a canonical B0 damage result")
	var hit: Dictionary = request["primary_hit"]
	var context_errors: Array[String] = []
	var normalized_context := ContextsScript.create_damage_context(hit["damage_context"], context_errors)
	if not context_errors.is_empty() or normalized_context != hit["damage_context"]:
		return CombatPortsScript.fail("primary_hit.damage_context must be canonical")
	if hit["damage_context"]["target_id"] != defender["id"]:
		return CombatPortsScript.fail("primary_hit target identity must match defender")
	if hit["damage_context"]["effect"]["source_side"] != attacker["side"]:
		return CombatPortsScript.fail("primary_hit source side must match attacker")
	if typeof(request["defender_alive_after_primary_hit"]) != TYPE_BOOL:
		return CombatPortsScript.fail("primary hit defender snapshot must be boolean")
	# `primary_hit` is historical B0 output. Content hooks intentionally run
	# between the primary damage and this reaction and may kill the defender, so
	# compare it with the captured immediate post-hit state, not mutable current
	# state. The current defender remains authoritative for reaction guards.
	if bool(hit["died"]) != (not bool(request["defender_alive_after_primary_hit"])):
		return CombatPortsScript.fail("primary_hit death flag must match its post-hit defender snapshot")

	var buffs: Variant = ports.service("buffs", errors)
	var damage: Variant = ports.service("damage", errors)
	var tuning_service: Variant = ports.service("tuning", errors)
	var catalogs: Variant = ports.service("catalogs", errors)
	if not errors.is_empty():
		return CombatPortsScript.fail("piece reaction services unavailable: %s" % errors[0])
	if not buffs.validate_unit_holder(attacker, errors) or not buffs.validate_unit_holder(defender, errors):
		return CombatPortsScript.fail("piece reaction buff holder invalid: %s" % errors[0])
	if not buffs.validate_side_state(errors):
		return CombatPortsScript.fail("piece reaction side buffs invalid: %s" % errors[0])
	for definition_request: Array in [
		[BURN_ID, "unit"], [ENCHANT_ID, "unit"], [KNIGHT_CHIVALRY_ID, "unit"],
		[VEXED_ID, "unit"], [FLAME_LEECH_ID, "side"],
	]:
		if buffs.definition_for(definition_request[0], definition_request[1], errors) == null:
			return CombatPortsScript.fail("piece reaction Buff authority invalid: %s" % errors[0])
	if typeof(catalogs) != TYPE_DICTIONARY or typeof(catalogs.get("buffs")) != TYPE_DICTIONARY:
		return CombatPortsScript.fail("catalogs.buffs authority is required")
	var valid_hero_ids: Array = []
	for hero: Dictionary in request["state"]["player_heroes"]:
		valid_hero_ids.append(hero["id"])
	# Validate the complete permanent snapshot even when the current attacker is
	# enemy; malformed run data must never be skipped by a branch guard.
	PermanentBuffStoreScript.normalize_instances(
		request["permanent_buffs"], catalogs["buffs"], valid_hero_ids, errors
	)
	if not errors.is_empty():
		return CombatPortsScript.fail("permanent_buffs snapshot is invalid: %s" % errors[0])

	var tuning := {}
	for id: String in [
		"burnBaseDuration", "ultFlameLeechRatio", "counterDamageRatio",
		"superCounterDamageRatio", "ultKnightSuperBonus",
	]:
		tuning[id] = _tuning_number(tuning_service, id, errors)
		if not errors.is_empty():
			return CombatPortsScript.fail(errors[0])
	if tuning["burnBaseDuration"] < 1.0 or tuning["burnBaseDuration"] != floorf(tuning["burnBaseDuration"]):
		return CombatPortsScript.fail("burnBaseDuration must be a positive integer")
	for id: String in ["ultFlameLeechRatio", "counterDamageRatio", "superCounterDamageRatio", "ultKnightSuperBonus"]:
		if tuning[id] < 0.0:
			return CombatPortsScript.fail("tuning.%s must be non-negative" % id)
	return CombatPortsScript.ok({
		"attacker": attacker, "defender": defender, "buffs": buffs, "damage": damage,
		"tuning": tuning, "buff_catalog": catalogs["buffs"],
		"valid_hero_ids": valid_hero_ids,
	})


static func _damage_context(
	target: Dictionary,
	raw_amount: float,
	source_id: String,
	source_name: String,
	source_side: String,
	source_actor_id: Variant,
	dealer_type: String,
	can_crit: bool,
	crit_rate: float,
	_attack_up_rate: float,
	errors: Array[String],
) -> Dictionary:
	var effect := ContextsScript.create_effect_context({
		"source_type": "counter" if dealer_type == "counter" else "system",
		"source_id": source_id,
		"source_name": source_name,
		"source_side": source_side,
		"source_actor_id": source_actor_id,
		"counts_as_skill_cast": false,
		"spent_skill_points": false,
		"free_cast": false,
		"counts_as_basic_attack": false,
		"counts_as_attack": dealer_type == "counter",
		"triggers_enemy_kill_effects": false,
	}, errors)
	if effect.is_empty():
		return {}
	return ContextsScript.create_damage_context({
		"target_id": target["id"], "raw_amount": raw_amount,
		"category": "direct", "effect": effect,
		"dealer_type": dealer_type, "dealer_name": source_name,
		"dealer_id": source_actor_id, "attacker_unit_id": source_actor_id,
		"can_crit": can_crit, "crit_rate": crit_rate,
		"guaranteed_crit": false, "can_block": true,
	}, errors)


static func _counter_aura_hero(state: Dictionary, side: String) -> Variant:
	if side == "ally":
		for hero: Dictionary in state["player_heroes"]:
			if hero["deployed"] and hero["ex_skill"] == "counterAura":
				return hero
		return null
	for hero: Dictionary in state["enemy_heroes"]:
		if hero["ex_skill"] == "counterAura":
			return hero
	return null


static func _unit(state: Dictionary, side: String, id: Variant) -> Variant:
	var units: Array = state["allies" if side == "ally" else "enemies"]
	for unit: Dictionary in units:
		if unit["id"] == id:
			return unit
	return null


static func _tuning_number(tuning: Variant, id: String, errors: Array[String]) -> float:
	if typeof(tuning) != TYPE_DICTIONARY:
		errors.append("tuning service must return a Dictionary")
		return 0.0
	var definition: Variant = tuning.get(id)
	if not definition is Resource or definition.get_script() != TuningValueDefinition:
		errors.append("tuning.%s must be a TuningValueDefinition" % id)
		return 0.0
	if not _finite_number(definition.value):
		errors.append("tuning.%s.value must be finite" % id)
		return 0.0
	return float(definition.value)


static func _valid_damage_result(result: Variant) -> bool:
	if not _closed_dictionary(result, DAMAGE_RESULT_KEYS):
		return false
	return (
		_finite_number(result["dealt"]) and float(result["dealt"]) >= 0.0
		and typeof(result["blocked"]) == TYPE_BOOL
		and typeof(result["died"]) == TYPE_BOOL
		and typeof(result["crit"]) == TYPE_BOOL
		and typeof(result["damage_context"]) == TYPE_DICTIONARY
		and (result["death_context"] == null or typeof(result["death_context"]) == TYPE_DICTIONARY)
	)


static func _closed_dictionary(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			return false
	return true


static func _failure(message: String, steps: Array[String], errors: Array[String]) -> Dictionary:
	var suffix := "" if errors.is_empty() else ": %s" % errors[0]
	var prefix := "none" if steps.is_empty() else ",".join(steps)
	return CombatPortsScript.fail("%s (committed steps: %s)%s" % [message, prefix, suffix])


static func _stable_id(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT and value > 0)
		or (typeof(value) == TYPE_STRING and value == value.strip_edges() and not value.is_empty())
	)


static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


static func _fmt(value: float) -> float:
	return maxf(0.0, roundf(value * 10.0) / 10.0)


static func _other_side(side: String) -> String:
	return "enemy" if side == "ally" else "ally"
