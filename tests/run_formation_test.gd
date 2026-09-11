extends RefCounted

const RunSessionScript = preload("res://app/run_session.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("Run starts with four distinct deployed piece classes and enforces stock", func() -> void:
		_test_default_and_commands(harness)
	)
	harness.run_test("Run formation survives save and migrates legacy six-full saves", func() -> void:
		_test_save_and_legacy_migration(harness)
	)
	harness.run_test("Run restores verified legacy four-choice checkpoints without losing the chosen hero", func() -> void:
		_test_four_choice_checkpoint_migration(harness)
	)
	harness.run_test("Run restores a verified legacy four-option recruitment and accepts a retained option", func() -> void:
		_test_four_recruitment_checkpoint_migration(harness)
	)


func _started(path: String, harness: TestHarness) -> RunSession:
	var session := RunSessionScript.new({}, path)
	var errors: Array[String] = []
	harness.assert_true(session.new_run("formation-" + path, errors), "; ".join(errors))
	var selection: Dictionary = session.snapshot(errors)
	harness.assert_true(session.execute({
		"type": "choose_starting_hero", "hero_id": selection["initial_hero_choice_ids"][0],
	}, errors), "; ".join(errors))
	return session


func _test_default_and_commands(harness: TestHarness) -> void:
	var session := _started("res://.godot/test-logs/run-formation-default.json", harness)
	var errors: Array[String] = []
	var state: Dictionary = session.snapshot(errors)
	harness.assert_equal(_classes(state), [null, "shield", null, "assassin", "crossbow", "banner"])
	harness.assert_equal(_occupied(state), 4)
	var before_invalid := state.duplicate(true)
	harness.assert_false(session.execute({"type":"swap_piece_slots", "first_slot":null, "second_slot":1}, errors))
	harness.assert_equal(session.snapshot(errors), before_invalid)
	harness.assert_false(session.execute({"type":"swap_piece_slots", "first_slot":1, "second_slot":null}, errors))
	harness.assert_equal(session.snapshot(errors), before_invalid)
	harness.assert_true(session.execute({
		"type": "swap_piece_slots", "first_slot": 1, "second_slot": 5,
	}, errors), "; ".join(errors))
	state = session.snapshot(errors)
	harness.assert_equal(_classes(state), ["crossbow", "shield", null, "assassin", null, "banner"])
	harness.assert_true(session.execute({
		"type": "set_piece_class", "slot": 4, "piece_class_id": "shield",
	}, errors), "; ".join(errors))
	harness.assert_false(session.execute({
		"type": "set_piece_class", "slot": 6, "piece_class_id": "shield",
	}, errors), "third shield must exceed the inventory of two")
	harness.assert_contains("; ".join(errors), "库存已用尽")
	state = session.snapshot(errors)
	harness.assert_equal(_classes(state), ["crossbow", "shield", null, "shield", null, "banner"])
	harness.assert_false(session.execute({
		"type": "set_piece_class", "slot": 3, "piece_class_id": "banner",
	}, errors), "inventory cannot recruit into an empty slot")
	harness.assert_contains("; ".join(errors), "空位只能")


func _test_save_and_legacy_migration(harness: TestHarness) -> void:
	var path := "res://.godot/test-logs/run-formation-save.json"
	var session := _started(path, harness)
	var errors: Array[String] = []
	harness.assert_true(session.execute({
		"type": "set_piece_class", "slot": 4, "piece_class_id": "banner",
	}, errors), "; ".join(errors))
	var before: Dictionary = session.snapshot(errors)
	harness.assert_true(session.save_checkpoint(errors), "; ".join(errors))
	var restored := RunSessionScript.new({}, path)
	harness.assert_true(restored.continue_run(errors), "; ".join(errors))
	var restored_state: Dictionary = restored.snapshot(errors)
	harness.assert_equal(_classes(restored_state), _classes(before))
	harness.assert_equal(_ratios(restored_state), _ratios(before))

	# Model a pre-formation checkpoint: all six legacy units remain present and
	# migrate to their historical class mapping even though it has 3 shields.
	var envelope: Dictionary = session.save_store.load(errors)
	var old_slots: Array = envelope["lifecycle"]["state"]["piece_slots"]
	for entry: Dictionary in old_slots:
		entry.erase("piece_class_id")
	envelope["lifecycle"]["version"] = 1
	var migrated := RunSessionScript.new({}, "")
	harness.assert_true(migrated.restore_checkpoint(envelope, errors), "; ".join(errors))
	var migrated_state: Dictionary = migrated.snapshot(errors)
	harness.assert_equal(_classes(migrated_state), ["shield", "shield", "shield", "assassin", "crossbow", "banner"])
	harness.assert_true(migrated.execute({
		"type": "swap_piece_slots", "first_slot": 1, "second_slot": 6,
	}, errors), "legacy over-stock formation remains playable")
	harness.assert_false(migrated.execute({
		"type": "set_piece_class", "slot": 1, "piece_class_id": "shield",
	}, errors), "legacy save cannot add a fourth shield")


func _test_four_choice_checkpoint_migration(harness: TestHarness) -> void:
	var path := "res://.godot/test-logs/run-formation-four-choice.json"
	var session := _started(path, harness)
	var errors: Array[String] = []
	var envelope: Dictionary = session.save_store.load(errors)
	var lifecycle: Dictionary = envelope["lifecycle"]
	var selected_hero_id: int = lifecycle["state"]["initial_hero_choice_ids"][0]
	var old_choices: Array = []
	for hero_id: Variant in session.catalogs["characters"]["players"]:
		if hero_id != selected_hero_id and session.catalogs["characters"]["players"][hero_id].exclusive_skill_id != "fate":
			old_choices.append(hero_id)
			if old_choices.size() == 3:
				break
	old_choices.append(selected_hero_id)
	harness.assert_equal(old_choices.size(), 4, "fixture needs a real old four-choice candidate list")
	lifecycle["state"]["initial_hero_choice_ids"] = old_choices
	var restored := RunSessionScript.new({}, "")
	harness.assert_true(restored.restore_checkpoint(envelope, errors), "; ".join(errors))
	var restored_state: Dictionary = restored.snapshot(errors)
	harness.assert_equal(restored_state["initial_hero_choice_ids"].size(), 3)
	harness.assert_true(
		selected_hero_id in restored_state["initial_hero_choice_ids"],
		"the hero chosen from old choice four must remain authoritative",
	)

	# Any four valid non-fate candidates can be narrowed. The deployed choice
	# remains authoritative; no permanent-growth hero is required any more.
	var valid_ids: Array = []
	var chosen_hero: Variant = null
	for hero_id: Variant in session.catalogs["characters"]["players"]:
		var hero: Variant = session.catalogs["characters"]["players"][hero_id]
		if hero.exclusive_skill_id == "fate":
			continue
		valid_ids.append(hero_id)
		if chosen_hero == null:
			chosen_hero = hero_id
	harness.assert_true(valid_ids.size() >= 4)
	harness.assert_true(chosen_hero != null)
	var late_legacy: Dictionary = envelope["lifecycle"].duplicate(true)
	late_legacy["state"]["initial_hero_choice_ids"] = [
		valid_ids[0], valid_ids[1], valid_ids[2], valid_ids[3],
	]
	late_legacy["state"]["hero_deployment_slots"] = {str(chosen_hero): 1}
	var migration_errors: Array[String] = []
	var narrowed: Dictionary = RunLifecycleScript._migrate_four_choice_checkpoint(
		late_legacy, session.catalogs, migration_errors,
	)
	harness.assert_equal(migration_errors, [])
	harness.assert_equal(narrowed["state"]["initial_hero_choice_ids"].size(), 3)
	harness.assert_true(chosen_hero in narrowed["state"]["initial_hero_choice_ids"])
	harness.assert_true(narrowed["state"]["initial_hero_choice_ids"].all(func(hero_id: Variant) -> bool:
		return hero_id in valid_ids
	))

	# The fourth entry is still validated before migration; it cannot become a
	# loophole merely because the modern UI presents three choices.
	var malicious_choice: Dictionary = envelope.duplicate(true)
	malicious_choice["lifecycle"]["state"]["initial_hero_choice_ids"][3] = 999999
	var rejected_choice := RunSessionScript.new({}, "")
	harness.assert_false(rejected_choice.restore_checkpoint(malicious_choice, errors))
	harness.assert_contains("; ".join(errors), "invalid initial hero choices")

	# A real fourth recruitment option was historically valid, but its authority
	# must still be exactly one snapshot per option before the migration trims it.
	var excessive_authority: Dictionary = envelope.duplicate(true)
	var reward_state: Dictionary = excessive_authority["lifecycle"]["state"]
	reward_state["status"] = "reward"
	reward_state["reward_pending"] = true
	var reward_options: Array = []
	for hero_id: Variant in session.catalogs["characters"]["players"]:
		if str(hero_id) in reward_state["hero_deployment_slots"] or session.catalogs["characters"]["players"][hero_id].exclusive_skill_id == "fate":
			continue
		reward_options.append(_legacy_hero_option(session.catalogs, hero_id))
		if reward_options.size() == 4:
			break
	harness.assert_equal(reward_options.size(), 4, "fixture needs four legitimate historical recruit options")
	reward_state["reward_options"] = reward_options
	var authority := {}
	for option: Dictionary in reward_options:
		authority[option["id"]] = option.duplicate(true)
	authority["reward:hero:extra"] = reward_options[0].duplicate(true)
	excessive_authority["lifecycle"]["reward_option_authority"] = authority
	var rejected_authority := RunSessionScript.new({}, "")
	harness.assert_false(rejected_authority.restore_checkpoint(excessive_authority, errors))
	harness.assert_contains("; ".join(errors), "invalid authority")


func _legacy_hero_option(catalogs: Dictionary, hero_id: int) -> Dictionary:
	return {
		"id": "reward:hero:%d" % hero_id,
		"payload_id": hero_id,
		"name": catalogs["characters"]["players"][hero_id].name,
		"description": "招募后加入本局后台，可在整备区调整站位。",
		"type": "hero",
		"price": 0,
		"purchased": false,
	}


func _complete_activity(lifecycle: Variant, state: Dictionary, errors: Array[String]) -> bool:
	if state["status"] == "fighting":
		return lifecycle.complete_current_battle(true, errors)
	if state["status"] == "event" and state["current_event_kind"] == "retain_card":
		return lifecycle.skip_retained_card_event(errors)
	return lifecycle.complete_current_node(errors)

func _test_four_recruitment_checkpoint_migration(harness: TestHarness) -> void:
	var session := _started("res://.godot/test-logs/run-formation-four-recruit.json", harness)
	var errors: Array[String] = []
	var state: Dictionary = session.lifecycle._state
	var guard := 0
	while state["status"] == "map" and _first_available_node(state).get("column", 99) < 2 and guard < 8:
		guard += 1
		var node := _first_available_node(state)
		harness.assert_true(session.lifecycle.choose_node(node["id"], errors), "; ".join(errors))
		state = session.lifecycle._state
		var completed: bool = _complete_activity(session.lifecycle, state, errors)
		harness.assert_true(completed, "; ".join(errors))
		state = session.lifecycle._state
		while state["status"] == "reward" and not state["reward_options"].is_empty():
			harness.assert_true(
				session.lifecycle.select_reward(state["reward_options"][0]["id"], errors),
				"; ".join(errors),
			)
			state = session.lifecycle._state
	harness.assert_true(guard < 8, "fixture must reach the first recruitment milestone")
	var milestone := _first_available_node(state)
	harness.assert_equal(milestone.get("column"), 2)
	harness.assert_true(session.lifecycle.choose_node(milestone["id"], errors), "; ".join(errors))
	state = session.lifecycle._state
	var won: bool = _complete_activity(session.lifecycle, state, errors)
	harness.assert_true(won, "; ".join(errors))
	state = session.lifecycle._state
	harness.assert_equal(state["status"], "reward")
	while state["status"] == "reward" and not state["reward_options"].is_empty() and state["reward_options"][0]["type"] != "hero":
		harness.assert_true(
			session.lifecycle.select_reward(state["reward_options"][0]["id"], errors),
			"; ".join(errors),
		)
		state = session.lifecycle._state
	harness.assert_equal(state["reward_options"].size(), 3)
	harness.assert_true(state["reward_options"].all(func(option: Dictionary) -> bool:
		return option["type"] == "hero"
	))

	var envelope: Dictionary = session._checkpoint(errors)
	harness.assert_false(envelope.is_empty(), "; ".join(errors))
	var lifecycle_checkpoint: Dictionary = envelope["lifecycle"]
	var legacy_options: Array = lifecycle_checkpoint["state"]["reward_options"]
	for hero_id: Variant in session.catalogs["characters"]["players"]:
		if str(hero_id) in lifecycle_checkpoint["state"]["hero_deployment_slots"] or hero_id in legacy_options.map(func(option: Dictionary) -> Variant: return option["payload_id"]):
			continue
		if session.catalogs["characters"]["players"][hero_id].exclusive_skill_id == "fate":
			continue
		var fourth := _legacy_hero_option(session.catalogs, hero_id)
		legacy_options.append(fourth)
		lifecycle_checkpoint["reward_option_authority"][fourth["id"]] = fourth.duplicate(true)
		harness.assert_equal(lifecycle_checkpoint["reward_option_authority"][fourth["id"]], fourth)
		break
	harness.assert_equal(legacy_options.size(), 4)
	var restored := RunSessionScript.new({}, "")
	harness.assert_true(restored.restore_checkpoint(envelope, errors), "; ".join(errors))
	var restored_state: Dictionary = restored.snapshot(errors)
	harness.assert_equal(restored_state["reward_options"].size(), 3)
	if not restored_state["reward_options"].is_empty():
		var recruit_id: int = restored_state["reward_options"][0]["payload_id"]
		harness.assert_true(restored.execute({"type": "recruit_hero", "hero_id": recruit_id}, errors), "; ".join(errors))


func _first_available_node(state: Dictionary) -> Dictionary:
	for node: Dictionary in state["map_nodes"]:
		if node["available"]:
			return node
	return {}


func _classes(state: Dictionary) -> Array:
	return state["piece_slots"].map(func(entry: Dictionary) -> Variant: return entry["piece_class_id"])


func _occupied(state: Dictionary) -> int:
	return state["piece_slots"].filter(func(entry: Dictionary) -> bool:
		return entry["piece_class_id"] != null
	).size()


func _ratios(state: Dictionary) -> Array:
	return state["piece_slots"].map(func(entry: Dictionary) -> float: return float(entry["hp_ratio"]))
