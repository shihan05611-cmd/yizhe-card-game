extends RefCounted

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")
const RngScript = preload("res://core/rng.gd")
const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const SaveStoreScript = preload("res://app/run_save_store.gd")


func run(harness: TestHarness) -> void:
	harness.run_test("M6 random checkpoint preserves source and rollback replay", func() -> void:
		_test_random_roundtrip(harness)
	)
	harness.run_test("M6 lifecycle checkpoint restores JSON-normalized map state", func() -> void:
		_test_lifecycle_map_roundtrip(harness)
	)
	harness.run_test("M6 reward authority survives restore and rejects tampering", func() -> void:
		_test_reward_authority(harness)
	)
	harness.run_test("M6 purchased shop authority cannot charge twice after restore", func() -> void:
		_test_shop_purchase(harness)
	)
	harness.run_test("M6 migrates stale pieceAction offers without accepting forged authority", func() -> void:
		_test_piece_action_checkpoint_authority(harness)
	)
	harness.run_test("M6 restores legacy normal relic rewards without discarding their authority", func() -> void:
		_test_legacy_normal_relic_reward_restore(harness)
	)
	harness.run_test("M6 save store replaces valid JSON and rejects corrupt files", func() -> void:
		_test_save_store(harness)
	)
	harness.run_test("M6 save store recovers interrupted backup layouts", func() -> void:
		_test_save_store_interrupted_replace(harness)
	)


func _test_random_roundtrip(harness: TestHarness) -> void:
	var errors: Array[String] = []
	var random := TransactionalRandomScript.new(RngScript.seeded("m6-random"), errors)
	var token: Variant = random.begin_transaction(errors)
	random.next(errors)
	random.next(errors)
	harness.assert_true(random.rollback_transaction(token, errors), "; ".join(errors))
	harness.assert_equal(random.replay_count(), 2)
	var checkpoint: Dictionary = random.export_checkpoint(errors)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(checkpoint))
	var source: Variant = RngScript.from_state(parsed["source_state"], errors)
	var restored: Variant = TransactionalRandomScript.restore_checkpoint(parsed, source, errors)
	harness.assert_not_null(restored, "; ".join(errors))
	for _index in 5:
		harness.assert_equal(restored.next(errors), random.next(errors))
	var active: Variant = random.begin_transaction(errors)
	harness.assert_equal(random.export_checkpoint(errors), {})
	harness.assert_contains("; ".join(errors), "active")
	harness.assert_true(random.rollback_transaction(active, errors))
	parsed["version"] = 2
	harness.assert_equal(TransactionalRandomScript.restore_checkpoint(parsed, source, errors), null)
	harness.assert_contains("; ".join(errors), "version")


func _test_lifecycle_map_roundtrip(harness: TestHarness) -> void:
	var fixture: Dictionary = _started_fixture("m6-map", harness)
	var errors: Array[String] = []
	var lifecycle: Variant = fixture["lifecycle"]
	var exported: Dictionary = lifecycle.export_checkpoint(errors)
	var checkpoint: Dictionary = _json_roundtrip(exported)
	var restored: Variant = _restore_lifecycle(checkpoint, fixture["random"], fixture["catalogs"], harness)
	harness.assert_not_null(restored)
	harness.assert_equal(restored.snapshot(errors), exported["state"])
	var fighting_fixture: Dictionary = _started_fixture("m6-fighting", harness)
	_reach_activity(fighting_fixture, ["battle", "elite", "boss"], harness, errors)
	harness.assert_equal(fighting_fixture["state"]["status"], "fighting")
	harness.assert_equal(fighting_fixture["lifecycle"].export_checkpoint(errors), {})
	harness.assert_contains("; ".join(errors), "battle")


func _test_reward_authority(harness: TestHarness) -> void:
	var fixture: Dictionary = _started_fixture("m6-reward", harness)
	var errors: Array[String] = []
	_reach_activity(fixture, ["battle", "elite", "boss"], harness, errors)
	harness.assert_equal(fixture["state"]["status"], "fighting")
	harness.assert_true(fixture["lifecycle"].complete_current_battle(true, errors), "; ".join(errors))
	harness.assert_equal(fixture["state"]["status"], "reward")
	var checkpoint: Dictionary = _json_roundtrip(fixture["lifecycle"].export_checkpoint(errors))
	var restored: Variant = _restore_lifecycle(checkpoint, fixture["random"], fixture["catalogs"], harness)
	harness.assert_not_null(restored)
	var restored_state: Dictionary = restored.snapshot(errors)
	var option: Dictionary = restored_state["reward_options"][0]
	var selected: bool = (
		restored.recruit_hero(option["payload_id"], errors)
		if option["type"] == "hero"
		else restored.select_reward(option["id"], errors)
	)
	harness.assert_true(selected, "; ".join(errors))
	var after_once: Dictionary = restored.snapshot(errors)
	harness.assert_false(restored.select_reward(option["id"], errors))
	harness.assert_equal(restored.snapshot(errors), after_once)
	var tampered: Dictionary = _json_roundtrip(checkpoint)
	tampered["state"]["reward_options"][0]["price"] = 999
	harness.assert_equal(_restore_lifecycle_raw(tampered, fixture["random"], fixture["catalogs"], errors), null)
	harness.assert_contains("; ".join(errors), "authoritative")


func _test_shop_purchase(harness: TestHarness) -> void:
	var fixture: Dictionary = _started_fixture("m6-shop", harness)
	var errors: Array[String] = []
	_reach_activity(fixture, ["shop"], harness, errors)
	harness.assert_equal(fixture["state"]["status"], "shop")
	var option: Dictionary = fixture["state"]["shop_options"].filter(func(value: Dictionary) -> bool:
		return value["type"] == "shopFreeSkill"
	)[0]
	harness.assert_true(fixture["lifecycle"].buy_shop_option(option["id"], errors), "; ".join(errors))
	var paid_currency: int = fixture["state"]["currency"]
	var paid_skill_count: int = fixture["state"]["free_skill_ids"].count(option["payload_id"])
	var checkpoint: Dictionary = _json_roundtrip(fixture["lifecycle"].export_checkpoint(errors))
	var restored: Variant = _restore_lifecycle(checkpoint, fixture["random"], fixture["catalogs"], harness)
	harness.assert_not_null(restored)
	harness.assert_false(restored.buy_shop_option(option["id"], errors))
	var after: Dictionary = restored.snapshot(errors)
	harness.assert_equal(after["currency"], paid_currency)
	harness.assert_equal(after["free_skill_ids"].count(option["payload_id"]), paid_skill_count)


func _test_piece_action_checkpoint_authority(harness: TestHarness) -> void:
	var fixture: Dictionary = _started_fixture("m6-piece-action-authority", harness)
	var errors: Array[String] = []
	var state: Dictionary = fixture["state"]
	harness.assert_equal(state["free_skill_ids"].count("pieceAction"), 2)
	var map_checkpoint: Dictionary = _json_roundtrip(fixture["lifecycle"].export_checkpoint(errors))
	var restored: Variant = _restore_lifecycle(map_checkpoint, fixture["random"], fixture["catalogs"], harness)
	harness.assert_not_null(restored, "owned initial pieceAction copies remain save-compatible")

	_reach_activity(fixture, ["shop"], harness, errors)
	var checkpoint: Dictionary = _json_roundtrip(fixture["lifecycle"].export_checkpoint(errors))
	var option: Dictionary = checkpoint["state"]["shop_options"].filter(func(value: Dictionary) -> bool:
		return value["type"] == "shopFreeSkill"
	)[0]
	var original_option_id: String = option["id"]
	option["payload_id"] = "pieceAction"
	option["id"] = "shop:skill:pieceAction"
	checkpoint["shop_option_authority"].erase(original_option_id)
	checkpoint["shop_option_authority"][option["id"]] = option.duplicate(true)
	var restored_shop: Variant = _restore_lifecycle_raw(checkpoint, fixture["random"], fixture["catalogs"], errors)
	harness.assert_not_null(restored_shop, "; ".join(errors))
	harness.assert_false(restored_shop.snapshot(errors)["shop_options"].any(func(value: Dictionary) -> bool:
		return value["payload_id"] == "pieceAction"
	))

	var purchased_history: Dictionary = _json_roundtrip(fixture["lifecycle"].export_checkpoint(errors))
	var history_option: Dictionary = purchased_history["state"]["shop_options"].filter(func(value: Dictionary) -> bool:
		return value["type"] == "shopFreeSkill"
	)[0]
	var history_option_id: String = history_option["id"]
	history_option["payload_id"] = "pieceAction"
	history_option["id"] = "shop:skill:pieceAction"
	history_option["purchased"] = true
	purchased_history["state"]["free_skill_ids"].append("pieceAction")
	purchased_history["shop_option_authority"].erase(history_option_id)
	purchased_history["shop_option_authority"][history_option["id"]] = history_option.duplicate(true)
	var restored_history: Variant = _restore_lifecycle_raw(
		purchased_history, fixture["random"], fixture["catalogs"], errors,
	)
	harness.assert_not_null(restored_history, "; ".join(errors))
	harness.assert_true(restored_history.snapshot(errors)["shop_options"].any(func(value: Dictionary) -> bool:
		return value["id"] == "shop:skill:pieceAction" and value["purchased"]
	))
	harness.assert_false(restored_history.buy_shop_option("shop:skill:pieceAction", errors))

	var forged: Dictionary = _json_roundtrip(fixture["lifecycle"].export_checkpoint(errors))
	var forged_option: Dictionary = forged["state"]["shop_options"].filter(func(value: Dictionary) -> bool:
		return value["type"] == "shopFreeSkill"
	)[0]
	forged_option["payload_id"] = "pieceAction"
	forged_option["id"] = "shop:skill:pieceAction"
	harness.assert_equal(_restore_lifecycle_raw(forged, fixture["random"], fixture["catalogs"], errors), null)
	harness.assert_contains("; ".join(errors), "authoritative snapshots")


func _test_legacy_normal_relic_reward_restore(harness: TestHarness) -> void:
	var restored: Variant = null
	var relic_option: Dictionary = {}
	for index in 32:
		var fixture: Dictionary = _started_fixture("m6-legacy-normal-relic-%d" % index, harness)
		var errors: Array[String] = []
		_reach_activity(fixture, ["battle"], harness, errors)
		if fixture["state"].get("status") != "fighting":
			continue
		harness.assert_true(fixture["lifecycle"].complete_current_battle(true, errors), "; ".join(errors))
		var relics: Array = fixture["state"]["reward_options"].filter(func(option: Dictionary) -> bool:
			return option["type"] == "relic"
		)
		if relics.is_empty():
			continue
		var checkpoint: Dictionary = _json_roundtrip(fixture["lifecycle"].export_checkpoint(errors))
		checkpoint["version"] = 2
		restored = _restore_lifecycle_raw(checkpoint, fixture["random"], fixture["catalogs"], errors)
		relic_option = relics[0]
		break
	harness.assert_not_null(restored, "a legacy normal relic reward checkpoint should restore")
	if restored == null:
		return
	var restored_options: Array = restored.snapshot()["reward_options"]
	harness.assert_true(restored_options.any(func(option: Dictionary) -> bool:
		return option["id"] == relic_option["id"] and option["type"] == "relic"
	))
	var errors: Array[String] = []
	harness.assert_true(restored.select_reward(relic_option["id"], errors), "; ".join(errors))


func _test_save_store(harness: TestHarness) -> void:
	var path := "res://.godot/test-logs/m6-run-save-store-test.json"
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(absolute_path)
	DirAccess.remove_absolute(absolute_path + ".tmp")
	DirAccess.remove_absolute(absolute_path + ".replace-backup")
	var errors: Array[String] = []
	var store := SaveStoreScript.new(path, errors)
	harness.assert_true(store.is_valid(), "; ".join(errors))
	harness.assert_true(store.save({"version": 1, "value": 7}, errors), "; ".join(errors))
	var loaded: Dictionary = store.load(errors)
	harness.assert_equal(loaded.get("version"), 1)
	harness.assert_equal(loaded.get("value"), 7)
	harness.assert_true(store.save({"version": 1, "value": 8}, errors), "; ".join(errors))
	loaded = store.load(errors)
	harness.assert_equal(loaded.get("version"), 1)
	harness.assert_equal(loaded.get("value"), 8)
	harness.assert_false(FileAccess.file_exists(absolute_path + ".tmp"))
	harness.assert_false(FileAccess.file_exists(absolute_path + ".replace-backup"))
	harness.assert_false(store.save({"bad": NAN}, errors))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	harness.assert_equal(store.load(errors), null)
	harness.assert_contains("; ".join(errors), "JSON")
	DirAccess.remove_absolute(absolute_path)


func _test_save_store_interrupted_replace(harness: TestHarness) -> void:
	var path := "res://.godot/test-logs/m6-run-save-interrupted-test.json"
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".replace-backup"
	for cleanup_path: String in [absolute_path, temporary_path, backup_path]:
		DirAccess.remove_absolute(cleanup_path)
	var backup := FileAccess.open(backup_path, FileAccess.WRITE)
	backup.store_string(JSON.stringify({"version": 1, "value": 21}, "", true, true))
	backup.close()
	var errors: Array[String] = []
	var store := SaveStoreScript.new(path, errors)
	harness.assert_true(store.has_save(), "a valid lone backup is resumable")
	var loaded: Dictionary = store.load(errors)
	harness.assert_equal(loaded.get("value"), 21)
	harness.assert_false(FileAccess.file_exists(absolute_path), "read fallback must preserve the crash layout")
	harness.assert_true(FileAccess.file_exists(backup_path))

	var temporary := FileAccess.open(temporary_path, FileAccess.WRITE)
	temporary.store_string("{interrupted")
	temporary.close()
	harness.assert_true(store.has_save(), "a stale tmp must not hide the valid backup")
	loaded = store.load(errors)
	harness.assert_equal(loaded.get("value"), 21)
	harness.assert_true(FileAccess.file_exists(temporary_path), "load must retain tmp for diagnosis")
	harness.assert_true(FileAccess.file_exists(backup_path))

	harness.assert_true(store.save({"version": 1, "value": 22}, errors), "; ".join(errors))
	loaded = store.load(errors)
	harness.assert_equal(loaded.get("value"), 22)
	harness.assert_true(FileAccess.file_exists(absolute_path))
	harness.assert_false(FileAccess.file_exists(temporary_path))
	harness.assert_false(FileAccess.file_exists(backup_path), "backup cleans only after verified main save")

	var corrupt_main := FileAccess.open(absolute_path, FileAccess.WRITE)
	corrupt_main.store_string("{damaged-main")
	corrupt_main.close()
	backup = FileAccess.open(backup_path, FileAccess.WRITE)
	backup.store_string(JSON.stringify({"version": 1, "value": 22}, "", true, true))
	backup.close()
	loaded = store.load(errors)
	harness.assert_equal(loaded.get("value"), 22, "load must fall back without mutating corrupt main")
	harness.assert_equal(FileAccess.get_file_as_string(absolute_path), "{damaged-main")
	harness.assert_true(store.save({"version": 1, "value": 23}, errors), "; ".join(errors))
	loaded = store.load(errors)
	harness.assert_equal(loaded.get("value"), 23, "a recovered save must remain writable")
	harness.assert_false(FileAccess.file_exists(backup_path))
	var corrupt_files: Array[String] = []
	var directory := DirAccess.open(absolute_path.get_base_dir())
	for file_name: String in directory.get_files():
		if file_name.begins_with(absolute_path.get_file() + ".corrupt."):
			corrupt_files.append(absolute_path.get_base_dir().path_join(file_name))
	harness.assert_equal(corrupt_files.size(), 1, "damaged main must move to one timestamped diagnostic file")
	if not corrupt_files.is_empty():
		harness.assert_equal(FileAccess.get_file_as_string(corrupt_files[0]), "{damaged-main")
		DirAccess.remove_absolute(corrupt_files[0])

	backup = FileAccess.open(backup_path, FileAccess.WRITE)
	backup.store_string(JSON.stringify({"version": 1, "value": 22}, "", true, true))
	backup.close()
	harness.assert_true(store.save({"version": 1, "value": 24}, errors), "; ".join(errors))
	loaded = store.load(errors)
	harness.assert_equal(loaded.get("value"), 24, "valid main plus stale backup must remain writable")
	harness.assert_false(FileAccess.file_exists(backup_path))
	DirAccess.remove_absolute(absolute_path)


func _started_fixture(seed: String, harness: TestHarness) -> Dictionary:
	var errors: Array[String] = []
	var catalogs := ContentCatalogScript.build(errors)
	var state := RunContractScript.create()
	var random := TransactionalRandomScript.new(RngScript.seeded(seed), errors)
	var lifecycle := RunLifecycleScript.new(state, catalogs, random, errors)
	harness.assert_true(errors.is_empty(), "; ".join(errors))
	harness.assert_true(lifecycle.start_run(errors), "; ".join(errors))
	var hero_id: int = state["initial_hero_choice_ids"][0]
	harness.assert_true(lifecycle.choose_starting_hero(hero_id, errors), "; ".join(errors))
	return {"catalogs": catalogs, "state": state, "random": random, "lifecycle": lifecycle}


func _restore_lifecycle(
	checkpoint: Dictionary,
	original_random: Variant,
	catalogs: Dictionary,
	harness: TestHarness,
) -> Variant:
	var errors: Array[String] = []
	var restored: Variant = _restore_lifecycle_raw(checkpoint, original_random, catalogs, errors)
	harness.assert_true(errors.is_empty(), "; ".join(errors))
	return restored


func _restore_lifecycle_raw(
	checkpoint: Dictionary,
	original_random: Variant,
	catalogs: Dictionary,
	errors: Array[String],
) -> Variant:
	var random_checkpoint: Dictionary = original_random.export_checkpoint(errors)
	if not errors.is_empty():
		return null
	var raw: Variant = RngScript.from_state(random_checkpoint["source_state"], errors)
	var restored_random: Variant = TransactionalRandomScript.restore_checkpoint(random_checkpoint, raw, errors)
	if not errors.is_empty():
		return null
	return RunLifecycleScript.restore_checkpoint(checkpoint, catalogs, restored_random, errors)


func _reach_activity(
	fixture: Dictionary,
	target_types: Array,
	harness: TestHarness,
	errors: Array[String],
) -> void:
	var path: Array = _path_to_type(fixture["state"], target_types)
	harness.assert_true(not path.is_empty(), "map must expose requested activity")
	for node_id: String in path:
		harness.assert_true(fixture["lifecycle"].choose_node(node_id, errors), "; ".join(errors))
		var node: Dictionary = _node_by_id(fixture["state"], node_id)
		if node["type"] in target_types:
			return
		if fixture["state"]["status"] == "fighting":
			harness.assert_true(fixture["lifecycle"].complete_current_battle(true, errors), "; ".join(errors))
		elif fixture["state"]["status"] == "event" and fixture["state"]["current_event_kind"] == "retain_card":
			harness.assert_true(fixture["lifecycle"].skip_retained_card_event(errors), "; ".join(errors))
		else:
			harness.assert_true(fixture["lifecycle"].complete_current_node(errors), "; ".join(errors))
		while fixture["state"]["status"] == "reward":
			var option: Dictionary = fixture["state"]["reward_options"][0]
			var resolved: bool = (
				fixture["lifecycle"].recruit_hero(option["payload_id"], errors)
				if option["type"] == "hero"
				else fixture["lifecycle"].select_reward(option["id"], errors)
			)
			harness.assert_true(resolved, "; ".join(errors))


func _path_to_type(state: Dictionary, target_types: Array) -> Array:
	var queue: Array = []
	var paths := {}
	for node: Dictionary in state["map_nodes"]:
		if node["available"]:
			queue.append(node["id"])
			paths[node["id"]] = [node["id"]]
	while not queue.is_empty():
		var node_id: String = queue.pop_front()
		var node := _node_by_id(state, node_id)
		if node["type"] in target_types:
			return paths[node_id]
		for next_id: String in node["next_node_ids"]:
			if not paths.has(next_id):
				paths[next_id] = paths[node_id] + [next_id]
				queue.append(next_id)
	return []


func _node_by_id(state: Dictionary, node_id: String) -> Dictionary:
	for node: Dictionary in state["map_nodes"]:
		if node["id"] == node_id:
			return node
	return {}


func _json_roundtrip(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))
