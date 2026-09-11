class_name RoguelikeRunLifecycle
extends RefCounted

## Pure M5 Run lifecycle through M5-04. Battle-world startup/settlement, UI and
## persistence remain intentionally absent; battle victory enters the reward
## phase through the pure piece-slot projection owned here.

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const MapSystemScript = preload("res://systems/roguelike/map_system.gd")
const RunBattleProgressScript = preload("res://systems/roguelike/run_battle_progress.gd")
const RunCardIdentityScript = preload("res://systems/cards/run_card_identity.gd")
const CardCatalogScript = preload("res://data/catalogs/card_catalog.gd")
const HeroCardCatalogScript = preload("res://data/catalogs/hero_card_catalog.gd")

const INITIAL_HERO_CHOICE_COUNT := 3
const INITIAL_FREE_SKILL_COUNT := 2
const INITIAL_PIECE_ACTION_COPIES := 2
const INITIAL_PIECE_ACTION_SKILL_ID := "pieceAction"
const UNOBTAINABLE_FREE_SKILL_IDS := ["basicDamage", INITIAL_PIECE_ACTION_SKILL_ID]
const RECRUITMENT_OPTION_COUNT := 3
const SHOP_SKILL_OPTION_COUNT := 3
const SHOP_RELIC_OPTION_COUNT := 3
const FORGE_RELIC_OPTION_COUNT := 3
const REWARD_HEAL_RATIO := 0.35
## First-pass normal-battle relic offer probability. The relic choice is
## independent from the normal card choice and never replaces it.
const NORMAL_RELIC_REWARD_CHANCE := 0.30
const BATTLE_NODE_TYPES := ["battle", "elite", "boss"]
const NON_BATTLE_STATUS_BY_TYPE := {"forge": "forge", "shop": "shop", "event": "event"}
const SHENTONG_EVOLUTION_RELIC_IDS := [
	"shentongAssaultBurst", "shentongChargeOverload",
]
const NODE_KEYS := [
	"id", "chapter", "row", "column", "type", "available", "completed", "next_node_ids",
]
const OPTION_KEYS := [
	"id", "payload_id", "name", "description", "type", "price", "purchased",
]
const REWARD_OPTION_TYPES := ["freeSkill", "exclusiveCard", "relic", "heal", "hero"]
const SHOP_OPTION_TYPES := ["shopFreeSkill", "shopExclusiveCard", "shopRelic"]
const FORGE_OPTION_TYPES := ["forgeRelic"]
const STAGE_ID_BY_CHAPTER := {1: "counter", 2: "burn", 3: "core"}
const CHECKPOINT_VERSION := 4
const LEGACY_RUN_ALLY_CLASS_BY_SLOT := {
	1: "shield", 2: "shield", 3: "shield", 4: "assassin", 5: "crossbow", 6: "banner",
}
const RUN_PIECE_CLASS_IDS := ["shield", "assassin", "crossbow", "banner"]
const RUN_PIECE_CLASS_STOCK := 2
const CHECKPOINT_KEYS := [
	"version", "state", "reward_option_authority", "shop_option_authority",
]
const CHECKPOINT_STATUSES := [
	"idle", "heroSelect", "map", "reward", "shop", "forge", "event", "cleared", "failed",
]

var _state: Dictionary
var _catalogs: Dictionary
var _players: Dictionary
var _skills: Dictionary
var _relics: Dictionary
var _card_catalog: Dictionary
var _roguelike_catalog: Dictionary
var _random: Variant
var _valid := false
var _dependency_error := ""
var _reward_option_authority := {}
var _shop_option_authority := {}
var _battle_launch_authority := {}
var _battle_progress_session: Variant = null


func _init(
	run_state: Variant = null,
	content_catalog: Variant = null,
	run_random: Variant = null,
	errors: Array[String] = [],
	restored_authority: Variant = null,
) -> void:
	errors.clear()
	if typeof(run_state) != TYPE_DICTIONARY:
		_dependency_error = "Run lifecycle requires the authoritative Run Dictionary"
	elif typeof(content_catalog) != TYPE_DICTIONARY:
		_dependency_error = "Run lifecycle requires the M1 content catalog"
	elif not _read_catalogs(content_catalog, errors):
		_dependency_error = errors[0] if not errors.is_empty() else "Run lifecycle catalogs are invalid"
	elif (
		typeof(run_random) != TYPE_OBJECT
		or run_random == null
		or not run_random.has_method("with_transaction")
		or not run_random.has_method("next")
		or not run_random.has_method("pick")
		or not run_random.has_method("shuffle")
	):
		_dependency_error = "Run lifecycle requires TransactionalRunRandom"
	else:
		var state_errors: Array[String] = []
		if not RunContractScript.validate(run_state, state_errors):
			_dependency_error = state_errors[0]
		else:
			# Legacy saves may still carry the retired field. Preserve its shape for
			# serialization, while ensuring it cannot affect this Run.
			run_state["permanent_buffs"] = []
			_state = run_state
			_catalogs = content_catalog
			_random = run_random
			if restored_authority != null:
				if (
					typeof(restored_authority) != TYPE_DICTIONARY
					or restored_authority.size() != 2
					or not restored_authority.has("reward_option_authority")
					or not restored_authority.has("shop_option_authority")
					or typeof(restored_authority["reward_option_authority"]) != TYPE_DICTIONARY
					or typeof(restored_authority["shop_option_authority"]) != TYPE_DICTIONARY
				):
					_dependency_error = "Run lifecycle restored authority is invalid"
				else:
					_reward_option_authority = _deep_copy(
						restored_authority["reward_option_authority"]
					)
					_shop_option_authority = _deep_copy(
						restored_authority["shop_option_authority"]
					)
			_valid = true
			if not _dependency_error.is_empty() or not _validate_state(_state, state_errors):
				_valid = false
				if _dependency_error.is_empty():
					_dependency_error = state_errors[0]
	if not _dependency_error.is_empty():
		errors.clear()
		errors.append(_dependency_error)


func is_valid() -> bool:
	return _valid


func snapshot(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return {}
	return RunContractScript.snapshot(_state, errors)


func validate(errors: Array[String] = []) -> bool:
	errors.clear()
	return _require_valid(errors) and _validate_state(_state, errors)


func export_checkpoint(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return {}
	if _state["status"] not in CHECKPOINT_STATUSES:
		errors.append("Run lifecycle cannot checkpoint during battle")
		return {}
	return {
		"version": CHECKPOINT_VERSION,
		"state": _normalize_json_numbers(RunContractScript.snapshot(_state, errors)),
		"reward_option_authority": _normalize_json_numbers(_reward_option_authority),
		"shop_option_authority": _normalize_json_numbers(_shop_option_authority),
	}


static func restore_checkpoint(
	checkpoint: Variant,
	content_catalog: Variant,
	run_random: Variant,
	errors: Array[String] = [],
) -> Variant:
	errors.clear()
	if typeof(content_catalog) != TYPE_DICTIONARY:
		errors.append("Run lifecycle checkpoint requires a Dictionary content catalog")
		return null
	if not _has_checkpoint_shape(checkpoint):
		errors.append("Run lifecycle checkpoint must be a closed Dictionary")
		return null
	var version: Variant = _normalized_integer(checkpoint["version"])
	if version not in [1, 2, 3, CHECKPOINT_VERSION]:
		errors.append("unsupported Run lifecycle checkpoint version")
		return null
	# Only legacy checkpoints gain newly introduced defaults.  A current-version
	# checkpoint must remain closed so a malformed save cannot silently erase a
	# claimed card inventory.
	var original_version: int = version
	var normalized: Dictionary = _normalize_json_numbers(checkpoint)
	if version == 1:
		normalized = _migrate_v1_checkpoint(normalized, errors)
		if not errors.is_empty():
			return null
	if original_version < CHECKPOINT_VERSION:
		normalized = _migrate_exclusive_cards_checkpoint(normalized, errors)
		if not errors.is_empty():
			return null
	normalized = _migrate_four_choice_checkpoint(normalized, content_catalog, errors)
	if not errors.is_empty():
		return null
	normalized = _migrate_piece_action_option_snapshots(normalized)
	if original_version < CHECKPOINT_VERSION:
		normalized = _migrate_retained_cards_checkpoint(normalized, errors)
		if not errors.is_empty():
			return null
	if (
		typeof(normalized["state"]) != TYPE_DICTIONARY
		or normalized["state"].get("status") not in CHECKPOINT_STATUSES
	):
		errors.append("Run lifecycle checkpoint contains an unsupported activity status")
		return null
	var restored := RoguelikeRunLifecycle.new(
		normalized["state"],
		content_catalog,
		run_random,
		errors,
		{
			"reward_option_authority": normalized["reward_option_authority"],
			"shop_option_authority": normalized["shop_option_authority"],
		},
	)
	if not errors.is_empty() or not restored.is_valid():
		return null
	return restored


func start_run(errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		var choices := _draw_initial_hero_choices(local_errors)
		if choices.size() != INITIAL_HERO_CHOICE_COUNT:
			return false
		_replace(candidate, RunContractScript.create())
		_reward_option_authority.clear()
		_shop_option_authority.clear()
		_battle_launch_authority.clear()
		_battle_progress_session = null
		candidate["active"] = true
		candidate["chapter"] = 1
		candidate["currency"] = 30
		candidate["status"] = "heroSelect"
		candidate["initial_hero_choice_ids"] = choices
		return true
	, errors)


func choose_starting_hero(hero_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			typeof(hero_id) != TYPE_INT
			or not candidate["active"]
			or candidate["status"] != "heroSelect"
			or hero_id not in candidate["initial_hero_choice_ids"]
		):
			return false
		var zero_cost_ids: Array = []
		for skill_id: Variant in _skills:
			var skill: Variant = _skills[skill_id]
			if skill.base_sp_cost == 0:
				zero_cost_ids.append(skill_id)
		if zero_cost_ids.size() < INITIAL_FREE_SKILL_COUNT:
			local_errors.append("Run initial loadout requires two distinct zero-SP free skills")
			return false
		var shuffled: Array = _random.shuffle(zero_cost_ids, local_errors)
		if not local_errors.is_empty():
			return false
		var map_nodes := MapSystemScript.build_chapter_map(
			_roguelike_catalog, 1, _random, local_errors
		)
		if not local_errors.is_empty() or map_nodes.size() != 30:
			return false
		candidate["hero_deployment_slots"] = {str(hero_id): 1}
		_sync_roster_views(candidate)
		candidate["free_skill_ids"] = shuffled.slice(0, INITIAL_FREE_SKILL_COUNT)
		for _copy_index in INITIAL_PIECE_ACTION_COPIES:
			candidate["free_skill_ids"].append(INITIAL_PIECE_ACTION_SKILL_ID)
		candidate["map_nodes"] = map_nodes
		candidate["status"] = "map"
		return true
	, errors)


func quit_run(errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		if not candidate["active"]:
			return false
		_replace(candidate, RunContractScript.create())
		_reward_option_authority.clear()
		_shop_option_authority.clear()
		_battle_launch_authority.clear()
		_battle_progress_session = null
		return true
	, errors)


func set_hero_deployment_slot(
	hero_id: Variant,
	slot: Variant,
	errors: Array[String] = [],
) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or typeof(hero_id) != TYPE_INT
			or typeof(slot) != TYPE_INT
			or slot < 1
			or slot > 6
			or not candidate["hero_deployment_slots"].has(str(hero_id))
		):
			return false
		for other_hero_id: Variant in candidate["hero_deployment_slots"]:
			if other_hero_id != str(hero_id) and candidate["hero_deployment_slots"][other_hero_id] == slot:
				return false
		candidate["hero_deployment_slots"][str(hero_id)] = slot
		_sync_roster_views(candidate)
		return true
	, errors)


func swap_piece_slots(first_slot: Variant, second_slot: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		if second_slot == null or not _formation_editable(candidate, first_slot, second_slot) or first_slot == second_slot:
			return false
		var first: Dictionary = _piece_slot_entry(candidate, int(first_slot))
		var second: Dictionary = _piece_slot_entry(candidate, int(second_slot))
		var moved_hp: float = float(first["hp_ratio"])
		var moved_class: Variant = first["piece_class_id"]
		first["hp_ratio"] = second["hp_ratio"]
		first["piece_class_id"] = second["piece_class_id"]
		second["hp_ratio"] = moved_hp
		second["piece_class_id"] = moved_class
		return true
	, errors)


func set_piece_class(slot: Variant, class_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if not _formation_editable(candidate, slot) or class_id not in RUN_PIECE_CLASS_IDS:
			return false
		var entry: Dictionary = _piece_slot_entry(candidate, int(slot))
		# Inventory describes alternative equipment for the four initial pieces;
		# it does not recruit a fifth or sixth piece into an empty position.
		if entry["piece_class_id"] == null:
			local_errors.append("空位只能通过拖拽现有棋子换位")
			return false
		if entry["piece_class_id"] == class_id:
			return true
		var already_owned := 0
		for other: Dictionary in candidate["piece_slots"]:
			if other["slot"] != int(slot) and other["piece_class_id"] == class_id:
				already_owned += 1
		# Legacy saves can retain three shields. They can move or replace one, but
		# may never add another copy until back under the normal stock cap.
		if already_owned >= RUN_PIECE_CLASS_STOCK:
			local_errors.append("该兵种库存已用尽")
			return false
		entry["piece_class_id"] = class_id
		return true
	, errors)


func deployed_hero_ids(errors: Array[String] = []) -> Array[int]:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return []
	return _sorted_deployment_ids(_state["hero_deployment_slots"])


func add_free_skill_copy(skill_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or typeof(skill_id) != TYPE_STRING
			or skill_id in UNOBTAINABLE_FREE_SKILL_IDS
			or not _skills.has(skill_id)
		):
			return false
		candidate["free_skill_ids"].append(skill_id)
		return true
	, errors)


func get_reward_options(errors: Array[String] = []) -> Array:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return []
	return _deep_copy(_state["reward_options"])


func get_shop_options(errors: Array[String] = []) -> Array:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return []
	return _deep_copy(_state["shop_options"])


func get_current_event(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors) \
	or _state["status"] != "event":
		return {}
	var kind: String = _state["current_event_kind"]
	if kind == "currency":
		return {
			"kind": kind,
			"name": "拾金",
			"description": "获得本章事件金币。",
			"currency_amount": 10 + int(_state["chapter"]) * 2,
			"options": [],
		}
	var candidates := RunCardIdentityScript.enumerate_candidates(_state, _catalogs, errors)
	if not errors.is_empty():
		return {}
	return {
		"kind": kind,
		"name": "留墨",
		"description": "选择一张牌，使这个具体副本在本次探索中获得保留。",
		"currency_amount": 0,
		"options": _deep_copy(candidates),
	}


func select_retained_card(key: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or candidate["status"] != "event"
			or candidate["current_event_kind"] != "retain_card"
			or typeof(key) != TYPE_STRING
			or key in candidate["retained_card_keys"]
		):
			return false
		var options := RunCardIdentityScript.unretained_candidates(
			candidate, _catalogs, local_errors
		)
		if not local_errors.is_empty() or not options.any(func(option: Dictionary) -> bool:
			return option["key"] == key
		):
			return false
		var node := _current_node(candidate)
		if node.is_empty() or node["type"] != "event":
			return false
		candidate["retained_card_keys"].append(key)
		return _finish_successful_node(candidate, node, local_errors)
	, errors)


func skip_retained_card_event(errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or candidate["status"] != "event"
			or candidate["current_event_kind"] != "retain_card"
		):
			return false
		var node := _current_node(candidate)
		return (
			not node.is_empty()
			and node["type"] == "event"
			and _finish_successful_node(candidate, node, local_errors)
		)
	, errors)


func get_option_cost(option_id: Variant, errors: Array[String] = []) -> Variant:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return null
	if typeof(option_id) != TYPE_STRING or _state["status"] not in ["shop", "forge"]:
		return null
	var option: Dictionary = _option_by_id(_state["shop_options"], option_id)
	var expected_types: Array = FORGE_OPTION_TYPES if _state["status"] == "forge" else SHOP_OPTION_TYPES
	if option.is_empty() or not _validate_option(
		option, expected_types, _shop_option_authority, true, _state,
	):
		return null
	return _currency_cost(option["price"], _state)


func choose_node(node_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if not candidate["active"] or candidate["status"] != "map" or typeof(node_id) != TYPE_STRING:
			return false
		var node: Dictionary = _node_by_id(candidate["map_nodes"], node_id)
		if node.is_empty() or not node["available"] or node["completed"]:
			return false
		var scales := MapSystemScript.get_node_scales(node, local_errors)
		var prepared_launch := {}
		if node["type"] in BATTLE_NODE_TYPES:
			var encounter := MapSystemScript.resolve_encounter(
				_roguelike_catalog, node, _random, local_errors,
			)
			var battle_seed: Variant = _random.int_range(0, 0xffffffff, local_errors)
			if not local_errors.is_empty() or encounter.is_empty() or battle_seed == null:
				return false
			scales = {"hp": encounter["hp_scale"], "atk": encounter["atk_scale"]}
			prepared_launch = {
				"node_id": node["id"],
				"battle_seed": battle_seed,
				"stage_id": STAGE_ID_BY_CHAPTER[node["chapter"]],
				"encounter": encounter,
			}
		if not local_errors.is_empty() or scales.is_empty():
			return false
		var prepared_options: Array = []
		var prepared_event_kind := ""
		if node["type"] == "shop":
			prepared_options.append_array(_draw_card_options(
				candidate, SHOP_SKILL_OPTION_COUNT, "shop", _skill_price(node["chapter"]), true,
				local_errors,
			))
			if not local_errors.is_empty():
				return false
			prepared_options.append_array(_draw_relic_options(
				SHOP_RELIC_OPTION_COUNT, "shop", "shopRelic", _relic_price(node["chapter"]),
				local_errors,
			))
		elif node["type"] == "forge":
			prepared_options = _draw_class_relic_options(
				FORGE_RELIC_OPTION_COUNT, _class_relic_price(node["chapter"]), local_errors,
			)
		if not local_errors.is_empty():
			return false
		if node["type"] == "event":
			var event_roll: Variant = _random.next(local_errors)
			if not local_errors.is_empty() or event_roll == null:
				return false
			prepared_event_kind = "retain_card" if float(event_roll) < 0.5 else "currency"
			if prepared_event_kind == "currency" and not _add_currency(
				candidate, 10 + node["chapter"] * 2, local_errors,
			):
				return false
		var prepared_authority := _publish_option_authority(prepared_options, local_errors)
		if not local_errors.is_empty():
			return false
		for other_node: Dictionary in candidate["map_nodes"]:
			other_node["available"] = false
		candidate["current_node_id"] = node_id
		candidate["reward_pending"] = false
		candidate["reward_options"] = []
		candidate["shop_options"] = prepared_options
		candidate["forge_uses_this_node"] = 0
		candidate["current_event_kind"] = prepared_event_kind
		_reward_option_authority.clear()
		_shop_option_authority = prepared_authority
		_battle_launch_authority = prepared_launch
		_battle_progress_session = null
		if node["type"] in BATTLE_NODE_TYPES:
			candidate["status"] = "fighting"
			candidate["enemy_hp_scale"] = scales["hp"]
			candidate["enemy_atk_scale"] = scales["atk"]
		elif NON_BATTLE_STATUS_BY_TYPE.has(node["type"]):
			candidate["status"] = NON_BATTLE_STATUS_BY_TYPE[node["type"]]
			candidate["enemy_hp_scale"] = 1.0
			candidate["enemy_atk_scale"] = 1.0
		else:
			local_errors.append("unsupported roguelike node type: %s" % str(node["type"]))
			return false
		return true
	, errors)


func complete_current_node(errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if not candidate["active"] or candidate["status"] not in NON_BATTLE_STATUS_BY_TYPE.values():
			return false
		if candidate["status"] == "event" and candidate["current_event_kind"] == "retain_card":
			return false
		var node := _current_node(candidate)
		if node.is_empty() or NON_BATTLE_STATUS_BY_TYPE.get(node["type"]) != candidate["status"]:
			return false
		return _finish_successful_node(candidate, node, local_errors)
	, errors)


func complete_current_battle(won: Variant, errors: Array[String] = []) -> bool:
	if _battle_progress_session != null:
		errors.clear()
		errors.append("an opened Run battle must settle through its progress session")
		return false
	return _complete_battle(won, {}, errors)


func begin_current_battle(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if (
		not _require_valid(errors)
		or not _validate_state(_state, errors)
		or _state["status"] != "fighting"
		or _battle_launch_authority.is_empty()
		or _battle_progress_session != null
	):
		return {}
	var deployed_ids: Array[int] = _sorted_deployment_ids(_state["hero_deployment_slots"])
	var battle_retained_keys := RunCardIdentityScript.retained_keys_for_battle(
		_state, deployed_ids, _catalogs, errors
	)
	if not errors.is_empty():
		return {}
	var progress := RunBattleProgressScript.new({
		"run_state": _state,
		"buff_catalog": _catalogs["buffs"],
		"valid_hero_ids": _players.keys(),
	}, errors)
	if not errors.is_empty() or not progress.is_valid():
		return {}
	_battle_progress_session = progress
	return {
		"battle_seed": _battle_launch_authority["battle_seed"],
		"deployed_hero_ids": deployed_ids,
		"free_skill_ids": _state["free_skill_ids"].duplicate(),
		# Extra exclusives remain in the Run inventory after an owner is taken out
		# of formation.  The battle only receives copies whose owner is deployed.
		"exclusive_card_ids": _deployed_exclusive_card_ids(_state),
		"retained_card_keys": battle_retained_keys,
		"stage_id": _battle_launch_authority["stage_id"],
		"relic_ids": _battle_relic_ids(),
		"encounter": _deep_copy(_battle_launch_authority["encounter"]),
		"run_progress": progress,
	}


func cancel_current_battle_launch(progress: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if progress == null or progress != _battle_progress_session or progress.status() != "open":
		return false
	if not progress.close("discarded", errors):
		return false
	_battle_progress_session = null
	return true


func settle_current_battle(
	progress: Variant,
	battle_result: Variant,
	allies: Variant,
	errors: Array[String] = [],
) -> bool:
	errors.clear()
	if (
		progress == null
		or progress != _battle_progress_session
		or progress.get_script() != RunBattleProgressScript
		or not progress.is_bound_to(_state)
		or battle_result not in ["win", "lose"]
	):
		return false
	var progress_snapshot := {}
	if battle_result == "win":
		progress_snapshot = progress.settlement_snapshot(allies, errors)
		if not errors.is_empty() or progress_snapshot.is_empty():
			return false
	var settled := _complete_battle(battle_result == "win", progress_snapshot, errors)
	if not settled:
		return false
	var close_errors: Array[String] = []
	var closed: bool = progress.close(
		"committed" if battle_result == "win" else "discarded", close_errors,
	)
	assert(closed and close_errors.is_empty())
	return true


func _complete_battle(
	won: Variant,
	progress_snapshot: Dictionary,
	errors: Array[String],
) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if not candidate["active"] or candidate["status"] != "fighting" or typeof(won) != TYPE_BOOL:
			return false
		var node := _current_node(candidate)
		if node.is_empty() or node["type"] not in BATTLE_NODE_TYPES:
			return false
		if not won:
			candidate["status"] = "failed"
			candidate["reward_pending"] = false
			candidate["reward_options"] = []
			_reward_option_authority.clear()
			_battle_launch_authority.clear()
			_battle_progress_session = null
			return true
		if not progress_snapshot.is_empty():
			if (
				progress_snapshot.keys() != ["piece_slots", "permanent_buffs"]
				or typeof(progress_snapshot["piece_slots"]) != TYPE_ARRAY
				or typeof(progress_snapshot["permanent_buffs"]) != TYPE_ARRAY
			):
				return false
			candidate["piece_slots"] = _deep_copy(progress_snapshot["piece_slots"])
			# Retain the field for checkpoint compatibility, but no longer carry
			# battle growth across encounters.
			candidate["permanent_buffs"] = []
		var reward := _reward_scale(node, local_errors)
		if reward.is_empty() or not _can_add_currency(candidate, reward["currency"], local_errors):
			return false
		var options := _build_battle_rewards(candidate, node, reward, local_errors)
		if not local_errors.is_empty():
			return false
		var authority := _publish_option_authority(options, local_errors)
		if not local_errors.is_empty() or not _add_currency(
			candidate, reward["currency"], local_errors,
		):
			return false
		candidate["reward_pending"] = true
		candidate["reward_options"] = options
		candidate["shop_options"] = []
		candidate["status"] = "reward"
		candidate["forge_uses_this_node"] = 0
		_reward_option_authority = authority
		_shop_option_authority.clear()
		_battle_launch_authority.clear()
		_battle_progress_session = null
		return true
	, errors)


func recruit_hero(hero_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or candidate["status"] != "reward"
			or not candidate["reward_pending"]
			or typeof(hero_id) != TYPE_INT
			or candidate["hero_deployment_slots"].has(str(hero_id))
		):
			return false
		var option: Dictionary = _option_by_id(
			candidate["reward_options"], "reward:hero:%d" % hero_id,
		)
		if option.is_empty() or not _validate_option(
			option, ["hero"], _reward_option_authority, true, candidate,
		):
			return false
		var node := _current_node(candidate)
		if node.is_empty():
			local_errors.append("recruitment requires the authoritative current node")
			return false
		if not _apply_hero_option(candidate, option, local_errors):
			return false
		candidate["reward_pending"] = false
		candidate["reward_options"] = []
		_reward_option_authority.clear()
		return _advance_after_node(candidate, node, local_errors)
	, errors)


func select_reward(option_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or candidate["status"] != "reward"
			or not candidate["reward_pending"]
			or typeof(option_id) != TYPE_STRING
		):
			return false
		var node := _current_node(candidate)
		var option: Dictionary = _option_by_id(candidate["reward_options"], option_id)
		if (
			node.is_empty()
			or option.is_empty()
			or not _validate_option(
				option, REWARD_OPTION_TYPES, _reward_option_authority, true, candidate,
			)
		):
			return false
		if not _apply_reward_option(candidate, option, local_errors):
			return false
		if node["type"] == "battle":
			_remove_normal_reward_group(candidate, _normal_reward_group(option))
			if not candidate["reward_options"].is_empty():
				return true
		candidate["reward_pending"] = false
		candidate["reward_options"] = []
		_reward_option_authority.clear()
		if option["type"] == "hero":
			return _advance_after_node(candidate, node, local_errors)
		return _finish_successful_node(candidate, node, local_errors)
	, errors)


func skip_normal_reward_group(group: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or candidate["status"] != "reward"
			or not candidate["reward_pending"]
			or group not in ["card", "relic"]
		):
			return false
		var node := _current_node(candidate)
		if node.is_empty() or node["type"] != "battle":
			return false
		if not candidate["reward_options"].any(func(option: Dictionary) -> bool:
			return _normal_reward_group(option) == group
		):
			return false
		_remove_normal_reward_group(candidate, group)
		if not candidate["reward_options"].is_empty():
			return true
		candidate["reward_pending"] = false
		_reward_option_authority.clear()
		return _finish_successful_node(candidate, node, local_errors)
	, errors)


func buy_shop_option(option_id: Variant, errors: Array[String] = []) -> bool:
	return _buy_option(option_id, "shop", SHOP_OPTION_TYPES, errors)


func buy_forge_option(option_id: Variant, errors: Array[String] = []) -> bool:
	return _buy_option(option_id, "forge", FORGE_OPTION_TYPES, errors)


func sell_free_skill(skill_id: Variant, errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or candidate["status"] != "shop"
			or "tradePermit" not in candidate["relic_ids"]
			or typeof(skill_id) != TYPE_STRING
			or skill_id not in candidate["free_skill_ids"]
			or skill_id == "basicDamage"
			or not _skills.has(skill_id)
		):
			return false
		var index: int = candidate["free_skill_ids"].find(skill_id)
		if index < 0 or not _add_currency(
			candidate, _skill_price(candidate["chapter"]), local_errors,
		):
			return false
		# The Godot Run owns card copies as a multiset. A sale consumes exactly
		# one copy, even when the same skill id appears several times.
		candidate["free_skill_ids"].remove_at(index)
		candidate["retained_card_keys"] = RunCardIdentityScript.after_free_copy_removed(
			candidate["retained_card_keys"], index
		)
		return true
	, errors)


func get_forge_heal_cost(errors: Array[String] = []) -> Variant:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return null
	return _forge_heal_cost(_state)


func use_forge_heal(errors: Array[String] = []) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		var cost: Variant = _forge_heal_cost(candidate)
		if cost == null or candidate["currency"] < cost:
			return false
		candidate["currency"] -= cost
		for entry: Dictionary in candidate["piece_slots"]:
			if entry["piece_class_id"] != null:
				entry["hp_ratio"] = 1.0
		candidate["forge_uses_this_node"] += 1
		return true
	, errors)


func _buy_option(
	option_id: Variant,
	status: String,
	allowed_types: Array,
	errors: Array[String],
) -> bool:
	return _atomic(func(candidate: Dictionary, _local_errors: Array[String]) -> bool:
		if (
			not candidate["active"]
			or candidate["status"] != status
			or typeof(option_id) != TYPE_STRING
		):
			return false
		var option: Dictionary = _option_by_id(candidate["shop_options"], option_id)
		if option.is_empty() or not _validate_option(
			option, allowed_types, _shop_option_authority, true, candidate,
		):
			return false
		var cost := _currency_cost(option["price"], candidate)
		if candidate["currency"] < cost:
			return false
		candidate["currency"] -= cost
		if option["type"] == "shopFreeSkill":
			candidate["free_skill_ids"].append(option["payload_id"])
		elif option["type"] == "shopExclusiveCard":
			candidate["exclusive_card_ids"].append(option["payload_id"])
		else:
			candidate["relic_ids"].append(option["payload_id"])
		option["purchased"] = true
		_shop_option_authority[option["id"]] = _deep_copy(option)
		return true
	, errors)


func _draw_skill_options(
	count: int,
	prefix: String,
	type_id: String,
	price: int,
	errors: Array[String],
) -> Array:
	var pool: Array = []
	for skill_id: Variant in _roguelike_catalog["free_skills"]:
		if skill_id not in UNOBTAINABLE_FREE_SKILL_IDS:
			pool.append(_roguelike_catalog["free_skills"][skill_id])
	var shuffled: Array = _random.shuffle(pool, errors)
	if not errors.is_empty():
		return []
	var options: Array = []
	for skill: Dictionary in shuffled.slice(0, mini(count, shuffled.size())):
		options.append({
			"id": "%s:skill:%s" % [prefix, skill["id"]],
			"payload_id": skill["id"],
			"name": skill["name"],
			"description": skill["tip"],
			"type": type_id,
			"price": price,
			"purchased": false,
		})
	return options


func _draw_card_options(
	candidate: Dictionary, count: int, prefix: String, price: int, shop: bool,
	errors: Array[String],
) -> Array:
	var pool: Array = []
	for skill_id: Variant in _roguelike_catalog["free_skills"]:
		if skill_id in UNOBTAINABLE_FREE_SKILL_IDS:
			continue
		var skill: Dictionary = _roguelike_catalog["free_skills"][skill_id]
		pool.append({
			"id": "%s:skill:%s" % [prefix, skill["id"]],
			"payload_id": skill["id"], "name": skill["name"],
			"description": skill["tip"],
			"type": "shopFreeSkill" if shop else "freeSkill",
			"price": price, "purchased": false,
		})
	for card_id: Variant in _card_catalog:
		var card: Variant = _card_catalog[card_id]
		if (
			card.card_category != "exclusive"
			or not candidate["hero_deployment_slots"].has(str(card.owner_hero_id))
		):
			continue
		var details := _exclusive_card_details(card)
		if details.is_empty():
			continue
		pool.append({
			"id": "%s:exclusive:%s" % [prefix, card.id],
			"payload_id": card.id, "name": details["name"],
			"description": details["description"],
			"type": "shopExclusiveCard" if shop else "exclusiveCard",
			"price": price, "purchased": false,
		})
	var shuffled: Array = _random.shuffle(pool, errors)
	if not errors.is_empty():
		return []
	return shuffled.slice(0, mini(count, shuffled.size()))


func _draw_relic_options(
	count: int,
	prefix: String,
	type_id: String,
	price: int,
	errors: Array[String],
) -> Array:
	var pool: Array = []
	for relic_id: Variant in _relics:
		var relic: Variant = _relics[relic_id]
		if (
			relic_id not in _state["relic_ids"]
			and relic_id not in SHENTONG_EVOLUTION_RELIC_IDS
			and relic.category != "classUpgrade"
			and relic.category != "shentongEvolve"
		):
			pool.append(relic)
	var shuffled: Array = _random.shuffle(pool, errors)
	if not errors.is_empty():
		return []
	var options: Array = []
	for relic: Variant in shuffled.slice(0, mini(count, shuffled.size())):
		options.append(_option_from_relic(relic, prefix, type_id, price))
	return options


func _draw_class_relic_options(
	count: int,
	price: int,
	errors: Array[String],
) -> Array:
	var pool: Array = []
	for relic_id: Variant in _relics:
		var relic: Variant = _relics[relic_id]
		if relic.category == "classUpgrade" and relic_id not in _state["relic_ids"]:
			pool.append(relic)
	var shuffled: Array = _random.shuffle(pool, errors)
	if not errors.is_empty():
		return []
	var options: Array = []
	for relic: Variant in shuffled.slice(0, mini(count, shuffled.size())):
		options.append(_option_from_relic(relic, "forge", "forgeRelic", price))
	return options


func _option_from_relic(
	relic: Variant,
	prefix: String,
	type_id: String,
	price: int,
) -> Dictionary:
	return {
		"id": "%s:relic:%s" % [prefix, relic.id],
		"payload_id": relic.id,
		"name": relic.name,
		"description": relic.description,
		"type": type_id,
		"price": price,
		"purchased": false,
	}


func _build_battle_rewards(
	candidate: Dictionary,
	_node: Dictionary,
	reward: Dictionary,
	errors: Array[String],
) -> Array:
	var options := _draw_card_options(
		candidate, reward["freeSkillCount"], "reward", 0, false, errors,
	)
	if not errors.is_empty():
		return []
	var relic_count: int = reward["relicCount"]
	if _node["type"] == "battle":
		var roll: Variant = _random.next(errors)
		if not errors.is_empty():
			return []
		relic_count = 3 if float(roll) < NORMAL_RELIC_REWARD_CHANCE else 0
	options.append_array(_draw_relic_options(relic_count, "reward", "relic", 0, errors))
	if not errors.is_empty():
		return []
	if not options.is_empty():
		return options
	return [{
		"id": "reward:heal",
		"payload_id": null,
		"name": "战后修整",
		"description": "全体存活棋子回复 35% 最大生命。",
		"type": "heal",
		"price": 0,
		"purchased": false,
	}]


func _normal_reward_group(option: Dictionary) -> String:
	return "relic" if option.get("type") == "relic" else "card"


func _remove_normal_reward_group(candidate: Dictionary, group: String) -> void:
	candidate["reward_options"] = candidate["reward_options"].filter(func(option: Dictionary) -> bool:
		return _normal_reward_group(option) != group
	)
	for option_id: Variant in _reward_option_authority.keys().duplicate():
		var option: Dictionary = _reward_option_authority[option_id]
		if _normal_reward_group(option) == group:
			_reward_option_authority.erase(option_id)


func _reward_scale(node: Dictionary, errors: Array[String]) -> Dictionary:
	var definition: Variant = _roguelike_catalog["chapters"].get(node["chapter"])
	if not definition is Resource or typeof(definition.get("metadata")) != TYPE_DICTIONARY:
		errors.append("battle reward requires an authoritative chapter definition")
		return {}
	var field := "battleReward"
	if node["type"] == "elite":
		field = "eliteReward"
	elif node["type"] == "boss":
		field = "bossReward"
	var reward: Variant = definition.metadata.get(field)
	if typeof(reward) != TYPE_DICTIONARY:
		errors.append("chapter %d is missing %s" % [node["chapter"], field])
		return {}
	for key in ["freeSkillCount", "relicCount", "currency"]:
		if typeof(reward.get(key)) != TYPE_INT or reward[key] < 0:
			errors.append("chapter %d %s.%s must be a non-negative integer" % [
				node["chapter"], field, key,
			])
			return {}
	return reward.duplicate(true)


func _publish_option_authority(options: Array, errors: Array[String]) -> Dictionary:
	var authority := {}
	for raw_option: Variant in options:
		if typeof(raw_option) != TYPE_DICTIONARY:
			errors.append("authoritative Run options must be Dictionaries")
			return {}
		var option: Dictionary = raw_option
		if typeof(option.get("id")) != TYPE_STRING or option["id"].is_empty():
			errors.append("authoritative Run option id must be a non-empty string")
			return {}
		if authority.has(option["id"]):
			errors.append("authoritative Run option ids must be unique")
			return {}
		authority[option["id"]] = _deep_copy(option)
	return authority


func _apply_reward_option(
	candidate: Dictionary,
	option: Dictionary,
	errors: Array[String],
) -> bool:
	match option["type"]:
		"freeSkill":
			candidate["free_skill_ids"].append(option["payload_id"])
			return true
		"exclusiveCard":
			candidate["exclusive_card_ids"].append(option["payload_id"])
			return true
		"relic":
			candidate["relic_ids"].append(option["payload_id"])
			return true
		"heal":
			for entry: Dictionary in candidate["piece_slots"]:
				if entry["piece_class_id"] != null and entry["hp_ratio"] > 0.0:
					entry["hp_ratio"] = minf(1.0, entry["hp_ratio"] + REWARD_HEAL_RATIO)
			return true
		"hero":
			return _apply_hero_option(candidate, option, errors)
	errors.append("unsupported reward option type: %s" % str(option.get("type")))
	return false


func _apply_hero_option(
	candidate: Dictionary,
	option: Dictionary,
	errors: Array[String],
) -> bool:
	var hero_id: int = option["payload_id"]
	if candidate["hero_deployment_slots"].has(str(hero_id)):
		return false
	var occupied: Array = candidate["hero_deployment_slots"].values()
	for preferred_slot in [4, 5, 6, 1, 2, 3]:
		if preferred_slot not in occupied:
			candidate["hero_deployment_slots"][str(hero_id)] = preferred_slot
			_sync_roster_views(candidate)
			return true
	errors.append("roguelike roster is full")
	return false


func _forge_heal_cost(state: Dictionary) -> Variant:
	if not state["active"] or state["status"] != "forge":
		return null
	if not state["piece_slots"].any(func(entry: Dictionary) -> bool:
		return entry["piece_class_id"] != null and entry["hp_ratio"] < 1.0
	):
		return null
	var base: int = 0 if state["forge_uses_this_node"] == 0 else (
		15 + (state["forge_uses_this_node"] - 1) * 10
	)
	return _currency_cost(base, state)


func _skill_price(chapter: int) -> int:
	return 18 + chapter * 2


func _relic_price(chapter: int) -> int:
	return 35 + chapter * 5


func _class_relic_price(chapter: int) -> int:
	return 30 + chapter * 5


func _currency_cost(base_cost: int, state: Dictionary) -> int:
	if base_cost == 0:
		return 0
	return int(ceil(float(base_cost) * 0.75)) if "discountCard" in state["relic_ids"] else base_cost


func _can_add_currency(state: Dictionary, amount: int, errors: Array[String]) -> bool:
	if amount < 0 or state["currency"] > 9223372036854775807 - amount:
		errors.append("currency change must remain a non-negative 64-bit integer")
		return false
	return true


func _add_currency(state: Dictionary, amount: int, errors: Array[String]) -> bool:
	if not _can_add_currency(state, amount, errors):
		return false
	state["currency"] += amount
	return true


func _finish_successful_node(
	candidate: Dictionary,
	node: Dictionary,
	errors: Array[String],
) -> bool:
	if _is_recruitment_milestone(node) and _prepare_recruitment(candidate, errors):
		return true
	if not errors.is_empty():
		return false
	return _advance_after_node(candidate, node, errors)


func _prepare_recruitment(candidate: Dictionary, errors: Array[String]) -> bool:
	var owned: Dictionary = candidate["hero_deployment_slots"]
	var candidates: Array = []
	for hero_id: Variant in _players:
		if not owned.has(str(hero_id)) and _players[hero_id].exclusive_skill_id != "fate":
			candidates.append(hero_id)
	var shuffled: Array = _random.shuffle(candidates, errors)
	if not errors.is_empty() or shuffled.is_empty():
		return false
	var options: Array = []
	for hero_id: Variant in shuffled.slice(0, RECRUITMENT_OPTION_COUNT):
		options.append({
			"id": "reward:hero:%d" % hero_id,
			"payload_id": hero_id,
			"name": _players[hero_id].name,
			"description": "招募后加入本局后台，可在整备区调整站位。",
			"type": "hero",
			"price": 0,
			"purchased": false,
		})
	var authority := _publish_option_authority(options, errors)
	if not errors.is_empty():
		return false
	for node: Dictionary in candidate["map_nodes"]:
		node["available"] = false
	candidate["reward_pending"] = true
	candidate["reward_options"] = options
	candidate["shop_options"] = []
	candidate["status"] = "reward"
	candidate["enemy_hp_scale"] = 1.0
	candidate["enemy_atk_scale"] = 1.0
	candidate["forge_uses_this_node"] = 0
	_reward_option_authority = authority
	_shop_option_authority.clear()
	return true


func _advance_after_node(
	candidate: Dictionary,
	node: Dictionary,
	errors: Array[String],
) -> bool:
	node["completed"] = true
	node["available"] = false
	_clear_node_runtime(candidate)
	if node["type"] == "boss":
		if candidate["chapter"] >= candidate["max_chapters"]:
			candidate["status"] = "cleared"
			return true
		var next_chapter: int = candidate["chapter"] + 1
		var next_map := MapSystemScript.build_chapter_map(
			_roguelike_catalog, next_chapter, _random, errors
		)
		if not errors.is_empty() or next_map.size() != 30:
			return false
		candidate["chapter"] = next_chapter
		candidate["map_nodes"] = next_map
		candidate["status"] = "map"
		return true
	var next_ids: Array = node["next_node_ids"]
	for candidate_node: Dictionary in candidate["map_nodes"]:
		candidate_node["available"] = (
			candidate_node["id"] in next_ids and not candidate_node["completed"]
		)
	candidate["status"] = "map"
	return true


func _clear_node_runtime(candidate: Dictionary) -> void:
	candidate["current_node_id"] = null
	candidate["enemy_hp_scale"] = 1.0
	candidate["enemy_atk_scale"] = 1.0
	candidate["reward_pending"] = false
	candidate["reward_options"] = []
	candidate["shop_options"] = []
	candidate["forge_uses_this_node"] = 0
	candidate["current_event_kind"] = ""
	_reward_option_authority.clear()
	_shop_option_authority.clear()
	_battle_launch_authority.clear()
	_battle_progress_session = null


func _is_recruitment_milestone(node: Dictionary) -> bool:
	return node["chapter"] == 1 and (node["column"] == 2 or node["type"] == "boss")


func _draw_initial_hero_choices(errors: Array[String]) -> Array:
	var candidates: Array = []
	for hero_id: Variant in _players:
		var exclusive_id: String = _players[hero_id].exclusive_skill_id
		if exclusive_id == "fate":
			continue
		candidates.append(hero_id)
	if candidates.size() < INITIAL_HERO_CHOICE_COUNT:
		errors.append("Run hero catalog cannot provide three choices")
		return []
	var shuffled: Array = _random.shuffle(candidates, errors)
	if not errors.is_empty():
		return []
	return shuffled.slice(0, INITIAL_HERO_CHOICE_COUNT)


func _atomic(command: Callable, errors: Array[String]) -> bool:
	errors.clear()
	if not _require_valid(errors) or not _validate_state(_state, errors):
		return false
	var reward_authority_before: Dictionary = _deep_copy(_reward_option_authority)
	var shop_authority_before: Dictionary = _deep_copy(_shop_option_authority)
	var battle_authority_before: Dictionary = _deep_copy(_battle_launch_authority)
	var battle_progress_before: Variant = _battle_progress_session
	var transition_errors: Array[String] = []
	var random_errors: Array[String] = []
	var result: Variant = _random.with_transaction(func() -> bool:
		return RunContractScript.transition(_state, func(candidate: Dictionary) -> bool:
			var changed: Variant = command.call(candidate, transition_errors)
			if typeof(changed) != TYPE_BOOL or not changed:
				return false
			return _validate_state(candidate, transition_errors)
		, transition_errors)
	, random_errors)
	for message: String in transition_errors:
		if message not in errors:
			errors.append(message)
	for message: String in random_errors:
		if message not in errors:
			errors.append(message)
	var committed: bool = typeof(result) == TYPE_BOOL and result
	if not committed:
		_reward_option_authority = reward_authority_before
		_shop_option_authority = shop_authority_before
		_battle_launch_authority = battle_authority_before
		_battle_progress_session = battle_progress_before
	return committed


func _formation_editable(candidate: Dictionary, first_slot: Variant, second_slot: Variant = null) -> bool:
	if not candidate["active"] or candidate["status"] != "map":
		return false
	if typeof(first_slot) != TYPE_INT or first_slot < 1 or first_slot > 6:
		return false
	if second_slot != null and (typeof(second_slot) != TYPE_INT or second_slot < 1 or second_slot > 6):
		return false
	return true


func _piece_slot_entry(candidate: Dictionary, slot: int) -> Dictionary:
	for entry: Dictionary in candidate["piece_slots"]:
		if entry["slot"] == slot:
			return entry
	return {}


func _validate_piece_formation(slots: Array, errors: Array[String]) -> bool:
	for entry: Dictionary in slots:
		var class_id: Variant = entry["piece_class_id"]
		if class_id != null and class_id not in RUN_PIECE_CLASS_IDS:
			errors.append("Run formation references unavailable piece class: %s" % str(class_id))
			return false
	# A legacy six-full save may retain three shields. This validator deliberately
	# permits that state so migration never deletes a unit; mutations enforce the
	# normal stock cap before introducing any additional class copy.
	return true


func _validate_state(state: Dictionary, errors: Array[String]) -> bool:
	var structural_errors: Array[String] = []
	if not RunContractScript.validate(state, structural_errors):
		errors.append_array(structural_errors)
		return false
	if not state["active"]:
		if state != RunContractScript.create():
			errors.append("inactive Run must equal the canonical idle state")
			return false
		return _validate_no_options(state, errors)
	if state["chapter"] < 1:
		errors.append("active Run chapter must be from 1 through 3")
		return false
	if not _validate_initial_choices(state, errors):
		return false
	for raw_hero_id: Variant in state["hero_deployment_slots"]:
		if not _players.has(int(raw_hero_id)):
			errors.append("Run roster references unknown hero %s" % raw_hero_id)
			return false
	if not _validate_piece_formation(state["piece_slots"], errors):
		return false
	for skill_id: Variant in state["free_skill_ids"]:
		if skill_id == "basicDamage" or not _skills.has(skill_id):
			errors.append("Run free-skill multiset references an unavailable player card: %s" % str(skill_id))
			return false
	for card_id: Variant in state["exclusive_card_ids"]:
		var card: Variant = _card_catalog.get(card_id)
		if (
			not card is Resource
			or card.card_category != "exclusive"
			or not _players.has(card.owner_hero_id)
		):
			errors.append("Run extra exclusive cards must reference a known hero ability")
			return false
		if _exclusive_card_details(card).is_empty():
			errors.append("Run extra exclusive cards cannot reference passive abilities")
			return false
	if state["status"] == "heroSelect":
		if (
			state["chapter"] != 1
			or state["currency"] != 30
			or not state["hero_deployment_slots"].is_empty()
			or not state["free_skill_ids"].is_empty()
			or not state["exclusive_card_ids"].is_empty()
			or not state["retained_card_keys"].is_empty()
			or not state["map_nodes"].is_empty()
			or state["current_node_id"] != null
		):
			errors.append("hero selection must not own roster, cards, map, or current node")
			return false
		return _validate_no_options(state, errors)
	if state["hero_deployment_slots"].is_empty():
		errors.append("active post-selection Run requires a deployed roster")
		return false
	if not _owned_includes_initial_choice(state):
		errors.append("Run roster must retain the selected initial hero")
		return false
	var identity_errors: Array[String] = []
	RunCardIdentityScript.enumerate_candidates(state, _catalogs, identity_errors)
	if not identity_errors.is_empty():
		errors.append(identity_errors[0])
		return false
	var owned_keys := {}
	for candidate: Dictionary in RunCardIdentityScript.enumerate_candidates(state, _catalogs):
		owned_keys[candidate["key"]] = true
	for key: String in state["retained_card_keys"]:
		if not owned_keys.has(key):
			errors.append("Run retained card key does not identify an owned copy: %s" % key)
			return false
	if not _validate_map(state, errors) or not _validate_status(state, errors):
		return false
	return true


func _deployed_exclusive_card_ids(state: Dictionary) -> Array:
	var cards: Array = []
	for card_id: Variant in state["exclusive_card_ids"]:
		var card: Variant = _card_catalog.get(card_id)
		if (
			card is Resource
			and state["hero_deployment_slots"].has(str(card.owner_hero_id))
		):
			cards.append(card_id)
	return cards


func _exclusive_card_details(card: Variant) -> Dictionary:
	if not card is Resource or card.card_category != "exclusive":
		return {}
	var ability: Variant = _catalogs["hero_abilities"]["exclusive"].get(card.source_skill_id)
	if ability != null:
		if ability.is_passive:
			return {}
		return {"name": ability.name, "description": ability.tip}
	var display: Variant = HeroCardCatalogScript.display(card.id)
	if (
		typeof(display) != TYPE_DICTIONARY
		or typeof(display.get("name")) != TYPE_STRING
		or str(display["name"]).is_empty()
		or typeof(display.get("description")) != TYPE_STRING
		or str(display["description"]).is_empty()
	):
		return {}
	return {"name": display["name"], "description": display["description"]}


func _validate_initial_choices(state: Dictionary, errors: Array[String]) -> bool:
	var choices: Array = state["initial_hero_choice_ids"]
	if choices.size() != INITIAL_HERO_CHOICE_COUNT:
		errors.append("active Run requires exactly three initial hero choices")
		return false
	for hero_id: Variant in choices:
		if not _players.has(hero_id) or _players[hero_id].exclusive_skill_id == "fate":
			errors.append("initial hero choices must be known non-fate heroes")
			return false
	return true


func _validate_map(state: Dictionary, errors: Array[String]) -> bool:
	if state["map_nodes"].size() != state["map_rows"] * state["map_columns"]:
		errors.append("post-selection Run map must contain exactly 30 nodes")
		return false
	var ids := {}
	var coordinates := {}
	var available_columns := {}
	for raw_node: Variant in state["map_nodes"]:
		if not _dictionary_has_exact_keys(raw_node, NODE_KEYS):
			errors.append("Run map node must keep the canonical M5 map shape")
			return false
		var node: Dictionary = raw_node
		var coordinate := "%d:%d" % [node.get("row", -1), node.get("column", -1)]
		if (
			typeof(node["id"]) != TYPE_STRING
			or node["chapter"] != state["chapter"]
			or typeof(node["row"]) != TYPE_INT
			or node["row"] < 0
			or node["row"] >= state["map_rows"]
			or typeof(node["column"]) != TYPE_INT
			or node["column"] < 0
			or node["column"] >= state["map_columns"]
			or node["type"] not in MapSystemScript.NODE_TYPES
			or typeof(node["available"]) != TYPE_BOOL
			or typeof(node["completed"]) != TYPE_BOOL
			or typeof(node["next_node_ids"]) != TYPE_ARRAY
			or ids.has(node["id"])
			or coordinates.has(coordinate)
			or (node["available"] and node["completed"])
		):
			errors.append("Run map contains an invalid node")
			return false
		ids[node["id"]] = node
		coordinates[coordinate] = true
		if node["id"] != "c%d-r%d-n%d" % [node["chapter"], node["row"], node["column"]]:
			errors.append("Run map node id must match its chapter, row, and column")
			return false
		if node["available"]:
			available_columns[node["column"]] = true
	if available_columns.size() > 1:
		errors.append("Run map frontier must occupy only one column")
		return false
	for node: Dictionary in state["map_nodes"]:
		var expected_successors: Array[String] = []
		if node["column"] < state["map_columns"] - 1:
			for next_row in [node["row"] - 1, node["row"], node["row"] + 1]:
				if next_row >= 0 and next_row < state["map_rows"]:
					expected_successors.append(
						"c%d-r%d-n%d" % [state["chapter"], next_row, node["column"] + 1]
					)
		if node["next_node_ids"] != expected_successors:
			errors.append("Run map successor edges must match adjacent rows in the next column")
			return false
		for next_id: Variant in node["next_node_ids"]:
			if typeof(next_id) != TYPE_STRING or not ids.has(next_id) or ids[next_id]["column"] != node["column"] + 1:
				errors.append("Run map contains an invalid successor edge")
				return false
	return true


func _validate_status(state: Dictionary, errors: Array[String]) -> bool:
	var status: String = state["status"]
	var current := _current_node(state)
	if status != "fighting" and (
		not _battle_launch_authority.is_empty() or _battle_progress_session != null
	):
		errors.append("non-fighting Run must not retain battle launch or progress authority")
		return false
	var available_count: int = state["map_nodes"].filter(func(node: Dictionary) -> bool:
		return node["available"]
	).size()
	if status == "map":
		if (
			state["current_node_id"] != null
			or available_count == 0
			or state["enemy_hp_scale"] != 1.0
			or state["enemy_atk_scale"] != 1.0
		):
			errors.append("map status requires a non-empty frontier and no current node")
			return false
		if state["forge_uses_this_node"] != 0:
			errors.append("map status must not retain forge uses")
			return false
		return _validate_no_options(state, errors)
	if status == "cleared":
		if (
			state["chapter"] != 3
			or state["current_node_id"] != null
			or available_count != 0
			or state["enemy_hp_scale"] != 1.0
			or state["enemy_atk_scale"] != 1.0
		):
			errors.append("cleared status requires the completed chapter-three boss")
			return false
		if state["forge_uses_this_node"] != 0 or not _validate_no_options(state, errors):
			return false
		return state["map_nodes"].any(func(node: Dictionary) -> bool:
			return node["type"] == "boss" and node["completed"]
		)
	if current.is_empty() or current["completed"] or available_count != 0:
		errors.append("selected Run status requires one incomplete current node and no frontier")
		return false
	if status == "fighting" or status == "failed":
		if current["type"] not in BATTLE_NODE_TYPES:
			errors.append("battle status requires a battle current node")
			return false
		if state["forge_uses_this_node"] != 0:
			errors.append("battle status must not retain forge uses")
			return false
		if not _validate_no_options(state, errors):
			return false
		if status == "failed":
			if not _battle_launch_authority.is_empty() or _battle_progress_session != null:
				errors.append("failed battle must not retain launch or progress authority")
				return false
			return true
		return _validate_battle_launch(state, current, errors)
	if status in NON_BATTLE_STATUS_BY_TYPE.values():
		if NON_BATTLE_STATUS_BY_TYPE.get(current["type"]) != status:
			errors.append("non-battle status must match the current node type")
			return false
		if state["enemy_hp_scale"] != 1.0 or state["enemy_atk_scale"] != 1.0:
			errors.append("non-battle status must keep neutral enemy scales")
			return false
		if status == "event":
			if state["forge_uses_this_node"] != 0:
				errors.append("event status must not retain forge uses")
				return false
			return _validate_no_options(state, errors)
		if state["reward_pending"] or not state["reward_options"].is_empty():
			errors.append("shop and forge statuses must not retain reward options")
			return false
		if not _reward_option_authority.is_empty():
			errors.append("shop and forge statuses must not retain reward authority")
			return false
		if status == "shop" and state["forge_uses_this_node"] != 0:
			errors.append("shop status must not retain forge uses")
			return false
		var allowed_types: Array = FORGE_OPTION_TYPES if status == "forge" else SHOP_OPTION_TYPES
		return _validate_option_list(
			state["shop_options"], allowed_types, _shop_option_authority,
			"shop options", state, errors,
		)
	if status == "reward":
		if (
			not state["reward_pending"]
			or not state["shop_options"].is_empty()
			or not _shop_option_authority.is_empty()
			or state["forge_uses_this_node"] != 0
			or not _validate_option_list(
				state["reward_options"], REWARD_OPTION_TYPES,
				_reward_option_authority, "reward options", state, errors,
			)
		):
			return false
		var hero_only: bool = state["reward_options"].all(func(option: Dictionary) -> bool:
			return option["type"] == "hero"
		)
		if hero_only:
			if not _validate_recruitment_options(state, errors):
				return false
			if state["enemy_hp_scale"] != 1.0 or state["enemy_atk_scale"] != 1.0:
				errors.append("recruitment status must keep neutral enemy scales")
				return false
			return _is_recruitment_milestone(current)
		if current["type"] not in BATTLE_NODE_TYPES:
			errors.append("battle reward requires a battle current node")
			return false
		var expected_scales := MapSystemScript.get_node_scales(current, errors)
		return (
			not expected_scales.is_empty()
			and state["enemy_hp_scale"] == expected_scales["hp"]
			and state["enemy_atk_scale"] == expected_scales["atk"]
		)
	errors.append("unsupported active Run status for M5-04: %s" % status)
	return false


func _validate_recruitment_options(state: Dictionary, errors: Array[String]) -> bool:
	var options: Array = state["reward_options"]
	if options.is_empty() or options.size() > RECRUITMENT_OPTION_COUNT:
		errors.append("recruitment must publish from one through three hero options")
		return false
	var seen := {}
	for raw_option: Variant in options:
		if not _dictionary_has_exact_keys(raw_option, OPTION_KEYS):
			errors.append("recruitment option must keep the canonical hero option shape")
			return false
		var option: Dictionary = raw_option
		var hero_id: Variant = option["payload_id"]
		if (
			option["type"] != "hero"
			or typeof(hero_id) != TYPE_INT
			or not _players.has(hero_id)
			or option["id"] != "reward:hero:%d" % hero_id
			or option["name"] != _players[hero_id].name
			or option["description"] != "招募后加入本局后台，可在整备区调整站位。"
			or option["price"] != 0
			or option["purchased"] != false
			or seen.has(hero_id)
			or state["hero_deployment_slots"].has(str(hero_id))
			or _players[hero_id].exclusive_skill_id == "fate"
		):
			errors.append("recruitment options must be unique unowned non-fate heroes")
			return false
		seen[hero_id] = true
	return true


func _validate_no_options(state: Dictionary, errors: Array[String]) -> bool:
	if (
		state["reward_pending"]
		or not state["reward_options"].is_empty()
		or not state["shop_options"].is_empty()
		or not _reward_option_authority.is_empty()
		or not _shop_option_authority.is_empty()
	):
		errors.append("%s status must not retain reward or shop options" % state["status"])
		return false
	return true


func _validate_battle_launch(
	state: Dictionary,
	node: Dictionary,
	errors: Array[String],
) -> bool:
	if _battle_launch_authority.keys() != ["node_id", "battle_seed", "stage_id", "encounter"]:
		errors.append("fighting Run requires one authoritative battle launch snapshot")
		return false
	var encounter: Variant = _battle_launch_authority["encounter"]
	if (
		_battle_launch_authority["node_id"] != node["id"]
		or _battle_launch_authority["stage_id"] != STAGE_ID_BY_CHAPTER[state["chapter"]]
		or typeof(_battle_launch_authority["battle_seed"]) != TYPE_INT
		or typeof(encounter) != TYPE_DICTIONARY
		or encounter.get("hp_scale") != state["enemy_hp_scale"]
		or encounter.get("atk_scale") != state["enemy_atk_scale"]
	):
		errors.append("fighting Run battle launch diverged from its current node")
		return false
	if _battle_progress_session != null and (
		_battle_progress_session.get_script() != RunBattleProgressScript
		or not _battle_progress_session.is_bound_to(state)
	):
		errors.append("fighting Run owns an invalid battle progress session")
		return false
	return true


func _validate_option_list(
	options: Array,
	expected_types: Array,
	authority: Dictionary,
	label: String,
	state: Dictionary,
	errors: Array[String],
) -> bool:
	var seen := {}
	for raw_option: Variant in options:
		if typeof(raw_option) != TYPE_DICTIONARY:
			errors.append("%s must contain only canonical option Dictionaries" % label)
			return false
		var option: Dictionary = raw_option
		if not _dictionary_has_exact_keys(option, OPTION_KEYS) or seen.has(option.get("id")):
			errors.append("%s must contain unique canonical option ids" % label)
			return false
		seen[option["id"]] = true
		if not _validate_option(option, expected_types, authority, false, state):
			errors.append("%s must match their authoritative snapshots one-to-one" % label)
			return false
	if authority.size() != seen.size():
		errors.append("%s must match their authoritative snapshots one-to-one" % label)
		return false
	for option_id: Variant in authority:
		if not seen.has(option_id):
			errors.append("%s must match their authoritative snapshots one-to-one" % label)
			return false
	return true


func _validate_option(
	option: Dictionary,
	expected_types: Array,
	authority: Dictionary,
	require_unpurchased: bool,
	state: Dictionary,
) -> bool:
	if (
		not _dictionary_has_exact_keys(option, OPTION_KEYS)
		or option.get("type") not in expected_types
		or typeof(option.get("id")) != TYPE_STRING
		or option["id"].is_empty()
		or typeof(option.get("name")) != TYPE_STRING
		or typeof(option.get("description")) != TYPE_STRING
		or typeof(option.get("price")) != TYPE_INT
		or option["price"] < 0
		or typeof(option.get("purchased")) != TYPE_BOOL
		or (require_unpurchased and option["purchased"])
		or not authority.has(option["id"])
		or option != authority[option["id"]]
	):
		return false
	match option["type"]:
		"heal":
			return (
				option["id"] == "reward:heal"
				and option["payload_id"] == null
				and option["price"] == 0
				and option["purchased"] == false
			)
		"hero":
			var hero_id: Variant = option["payload_id"]
			return (
				typeof(hero_id) == TYPE_INT
				and _players.has(hero_id)
				and not state["hero_deployment_slots"].has(str(hero_id))
				and _players[hero_id].exclusive_skill_id != "fate"
				and option["id"] == "reward:hero:%d" % hero_id
				and option["price"] == 0
				and option["purchased"] == false
			)
		"freeSkill", "shopFreeSkill":
			var skill_id: Variant = option["payload_id"]
			var prefix := "reward" if option["type"] == "freeSkill" else "shop"
			var expected_price := 0 if option["type"] == "freeSkill" else _skill_price(state["chapter"])
			return (
				typeof(skill_id) == TYPE_STRING
				and (
					skill_id not in UNOBTAINABLE_FREE_SKILL_IDS
					or (
						skill_id == INITIAL_PIECE_ACTION_SKILL_ID
						and option["type"] == "shopFreeSkill"
						and option["purchased"]
					)
				)
				and _skills.has(skill_id)
				and option["id"] == "%s:skill:%s" % [prefix, skill_id]
				and option["price"] == expected_price
				and (option["type"] == "shopFreeSkill" or option["purchased"] == false)
			)
		"exclusiveCard", "shopExclusiveCard":
			var card_id: Variant = option["payload_id"]
			var prefix := "reward" if option["type"] == "exclusiveCard" else "shop"
			var expected_price := 0 if option["type"] == "exclusiveCard" else _skill_price(state["chapter"])
			var card: Variant = _card_catalog.get(card_id)
			if (
				typeof(card_id) != TYPE_STRING
				or not card is Resource
				or card.card_category != "exclusive"
				or not state["hero_deployment_slots"].has(str(card.owner_hero_id))
			):
				return false
			var details := _exclusive_card_details(card)
			return (
				not details.is_empty()
				and option["id"] == "%s:exclusive:%s" % [prefix, card_id]
				and option["name"] == details["name"]
				and option["description"] == details["description"]
				and option["price"] == expected_price
				and (option["type"] == "shopExclusiveCard" or option["purchased"] == false)
			)
		"relic", "shopRelic", "forgeRelic":
			var relic_id: Variant = option["payload_id"]
			if typeof(relic_id) != TYPE_STRING or not _relics.has(relic_id):
				return false
			var relic: Variant = _relics[relic_id]
			var owned: bool = relic_id in state["relic_ids"]
			if option["type"] == "forgeRelic":
				return (
					option["id"] == "forge:relic:%s" % relic_id
					and option["price"] == _class_relic_price(state["chapter"])
					and relic.category == "classUpgrade"
					and owned == option["purchased"]
				)
			var prefix := "reward" if option["type"] == "relic" else "shop"
			var expected_price := 0 if option["type"] == "relic" else _relic_price(state["chapter"])
			return (
				relic.category != "classUpgrade"
				and relic.category != "shentongEvolve"
				and relic_id not in SHENTONG_EVOLUTION_RELIC_IDS
				and option["id"] == "%s:relic:%s" % [prefix, relic_id]
				and option["price"] == expected_price
				and owned == option["purchased"]
			)
	return false


func _owned_includes_initial_choice(state: Dictionary) -> bool:
	for raw_hero_id: Variant in state["hero_deployment_slots"]:
		if int(raw_hero_id) in state["initial_hero_choice_ids"]:
			return true
	return false


func _sync_roster_views(state: Dictionary) -> void:
	state["front_hero_ids"] = []
	state["back_hero_ids"] = []
	for hero_id: int in _sorted_deployment_ids(state["hero_deployment_slots"]):
		if state["hero_deployment_slots"][str(hero_id)] <= 3:
			state["front_hero_ids"].append(hero_id)
		else:
			state["back_hero_ids"].append(hero_id)


func _sorted_deployment_ids(slots: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for raw_hero_id: Variant in slots:
		ids.append(int(raw_hero_id))
	ids.sort_custom(func(left: int, right: int) -> bool:
		return slots[str(left)] < slots[str(right)]
	)
	return ids


func _current_node(state: Dictionary) -> Dictionary:
	return _node_by_id(state["map_nodes"], state["current_node_id"])


func _node_by_id(nodes: Array, node_id: Variant) -> Dictionary:
	if typeof(node_id) != TYPE_STRING:
		return {}
	for node: Dictionary in nodes:
		if node["id"] == node_id:
			return node
	return {}


func _option_by_id(options: Array, option_id: Variant) -> Dictionary:
	if typeof(option_id) != TYPE_STRING:
		return {}
	for raw_option: Variant in options:
		if typeof(raw_option) == TYPE_DICTIONARY and raw_option.get("id") == option_id:
			return raw_option
	return {}


func _battle_relic_ids() -> Array:
	var result: Array = []
	for relic_id: Variant in _state["relic_ids"]:
		if (
			_relics.has(relic_id)
			and relic_id not in SHENTONG_EVOLUTION_RELIC_IDS
			and _relics[relic_id].category != "shentongEvolve"
		):
			result.append(relic_id)
	return result


func _read_catalogs(content_catalog: Dictionary, errors: Array[String]) -> bool:
	if (
		typeof(content_catalog.get("characters")) != TYPE_DICTIONARY
		or typeof(content_catalog["characters"].get("players")) != TYPE_DICTIONARY
		or typeof(content_catalog.get("skills")) != TYPE_DICTIONARY
		or typeof(content_catalog.get("relics")) != TYPE_DICTIONARY
		or typeof(content_catalog.get("hero_abilities")) != TYPE_DICTIONARY
		or typeof(content_catalog.get("roguelike_content")) != TYPE_DICTIONARY
	):
		errors.append("Run lifecycle M1 catalog groups are missing")
		return false
	_players = content_catalog["characters"]["players"]
	_skills = content_catalog["skills"]
	_relics = content_catalog["relics"]
	_card_catalog = CardCatalogScript.build(_skills, content_catalog["hero_abilities"])
	if _card_catalog.is_empty():
		errors.append("Run lifecycle card catalog is unavailable")
		return false
	_roguelike_catalog = content_catalog["roguelike_content"]
	return true


func _require_valid(errors: Array[String]) -> bool:
	if _valid:
		return true
	errors.append(_dependency_error if not _dependency_error.is_empty() else "Run lifecycle is invalid")
	return false


func _replace(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for key: Variant in source:
		target[key] = source[key]


static func _has_checkpoint_shape(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != CHECKPOINT_KEYS.size():
		return false
	for key: String in CHECKPOINT_KEYS:
		if not value.has(key):
			return false
	return true


static func _dictionary_has_exact_keys(value: Variant, expected_keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != expected_keys.size():
		return false
	for key: Variant in expected_keys:
		if not value.has(key):
			return false
	return true


static func _normalized_integer(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value):
		return int(value)
	return null


static func _normalize_json_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value):
		return int(value)
	if typeof(value) == TYPE_ARRAY:
		var normalized_array: Array = []
		for item: Variant in value:
			normalized_array.append(_normalize_json_numbers(item))
		return normalized_array
	if typeof(value) == TYPE_DICTIONARY:
		var normalized_dictionary := {}
		for key: Variant in value:
			normalized_dictionary[key] = _normalize_json_numbers(value[key])
		return normalized_dictionary
	return value


static func _migrate_v1_checkpoint(checkpoint: Dictionary, errors: Array[String]) -> Dictionary:
	var migrated: Dictionary = checkpoint.duplicate(true)
	var state: Variant = migrated.get("state")
	if typeof(state) != TYPE_DICTIONARY or typeof(state.get("piece_slots")) != TYPE_ARRAY:
		errors.append("legacy Run checkpoint has no piece slot formation")
		return {}
	if state["piece_slots"].size() != 6:
		errors.append("legacy Run checkpoint has an invalid piece slot formation")
		return {}
	for index in state["piece_slots"].size():
		var entry: Variant = state["piece_slots"][index]
		if (
			typeof(entry) != TYPE_DICTIONARY
			or entry.size() != 2
			or not entry.has("slot")
			or not entry.has("hp_ratio")
		):
			errors.append("legacy Run checkpoint has an invalid piece slot entry")
			return {}
		entry["piece_class_id"] = LEGACY_RUN_ALLY_CLASS_BY_SLOT[index + 1]
	migrated["version"] = CHECKPOINT_VERSION
	return migrated


static func _migrate_exclusive_cards_checkpoint(
	checkpoint: Dictionary, errors: Array[String]
) -> Dictionary:
	var migrated: Dictionary = checkpoint.duplicate(true)
	var state: Variant = migrated.get("state")
	if typeof(state) != TYPE_DICTIONARY:
		errors.append("Run checkpoint state is invalid")
		return {}
	if not state.has("exclusive_card_ids"):
		state["exclusive_card_ids"] = []
	# Dictionaries retrieved from a duplicated Variant are value-copied here;
	# publish the normalized state back into the checkpoint explicitly.
	migrated["state"] = state
	migrated["version"] = CHECKPOINT_VERSION
	return migrated


static func _migrate_four_choice_checkpoint(
	checkpoint: Dictionary, content_catalog: Dictionary, errors: Array[String]
) -> Dictionary:
	var migrated: Dictionary = checkpoint.duplicate(true)
	var state: Variant = migrated.get("state")
	if typeof(state) != TYPE_DICTIONARY:
		errors.append("Run checkpoint state is invalid")
		return {}
	var characters: Variant = content_catalog.get("characters")
	var players: Variant = characters.get("players") if typeof(characters) == TYPE_DICTIONARY else null
	if typeof(players) != TYPE_DICTIONARY:
		errors.append("Run checkpoint content catalog lacks player definitions")
		return {}
	var choices: Variant = state.get("initial_hero_choice_ids")
	if typeof(choices) == TYPE_ARRAY and choices.size() == 4:
		if not _validate_legacy_four_initial_choices(choices, players, errors):
			return {}
		var required := {}
		var owned_initial: Array = []
		if state.get("status") != "heroSelect":
			var deployed: Variant = state.get("hero_deployment_slots")
			if typeof(deployed) != TYPE_DICTIONARY:
				errors.append("legacy four-choice checkpoint has an invalid deployed roster")
				return {}
			for hero_id: Variant in choices:
				if deployed.has(str(hero_id)):
					owned_initial.append(hero_id)
			if not owned_initial.is_empty():
				required[owned_initial[0]] = true
		var retained: Array = []
		for hero_id: Variant in choices:
			if required.has(hero_id):
				retained.append(hero_id)
		for hero_id: Variant in choices:
			if retained.size() == INITIAL_HERO_CHOICE_COUNT:
				break
			if hero_id not in retained:
				retained.append(hero_id)
		state["initial_hero_choice_ids"] = retained
	if typeof(state.get("reward_options")) == TYPE_ARRAY and state["reward_options"].size() == 4:
		if not _validate_legacy_four_recruitment_options(state, migrated.get("reward_option_authority"), players, errors):
			return {}
		var kept: Array = state["reward_options"].slice(0, 3)
		state["reward_options"] = kept
		var authority: Variant = migrated.get("reward_option_authority")
		var ids := kept.map(func(option: Dictionary) -> String: return option["id"])
		for key: Variant in authority.keys():
			if key not in ids:
				authority.erase(key)
	return migrated


static func _migrate_piece_action_option_snapshots(checkpoint: Dictionary) -> Dictionary:
	var migrated: Dictionary = checkpoint.duplicate(true)
	var state: Variant = migrated.get("state")
	if typeof(state) != TYPE_DICTIONARY:
		return migrated
	state["permanent_buffs"] = []
	var reward: Dictionary = _remove_stale_piece_action_options(
		state.get("reward_options"), migrated.get("reward_option_authority"), false,
	)
	var shop: Dictionary = _remove_stale_piece_action_options(
		state.get("shop_options"), migrated.get("shop_option_authority"), true,
	)
	if not reward.is_empty():
		state["reward_options"] = reward["options"]
		migrated["reward_option_authority"] = reward["authority"]
	if not shop.is_empty():
		state["shop_options"] = shop["options"]
		migrated["shop_option_authority"] = shop["authority"]
	migrated["state"] = state
	return migrated


static func _migrate_retained_cards_checkpoint(
	checkpoint: Dictionary, errors: Array[String]
) -> Dictionary:
	var migrated: Dictionary = checkpoint.duplicate(true)
	var state: Variant = migrated.get("state")
	if typeof(state) != TYPE_DICTIONARY:
		errors.append("Run checkpoint state is invalid")
		return {}
	# Legacy event checkpoints already received their currency on node entry.
	# Marking them as currency events preserves that result without rerolling or
	# paying the reward a second time after restore.
	state["retained_card_keys"] = []
	state["current_event_kind"] = "currency" if state.get("status") == "event" else ""
	migrated["state"] = state
	migrated["version"] = CHECKPOINT_VERSION
	return migrated


static func _remove_stale_piece_action_options(
	raw_options: Variant, raw_authority: Variant, preserve_purchased_shop_history: bool,
) -> Dictionary:
	if typeof(raw_options) != TYPE_ARRAY or typeof(raw_authority) != TYPE_DICTIONARY:
		return {}
	var options: Array = raw_options
	var authority: Dictionary = raw_authority
	var retained: Array = []
	var migrated_authority: Dictionary = authority.duplicate(true)
	for raw_option: Variant in options:
		if typeof(raw_option) != TYPE_DICTIONARY:
			retained.append(raw_option)
			continue
		var option: Dictionary = raw_option
		var option_id: Variant = option.get("id")
		var is_piece_action_offer: bool = (
			option.get("type") in ["freeSkill", "shopFreeSkill"]
			and option.get("payload_id") == INITIAL_PIECE_ACTION_SKILL_ID
			and typeof(option_id) == TYPE_STRING
			and authority.get(option_id) == option
		)
		if not is_piece_action_offer or (
			preserve_purchased_shop_history and option.get("purchased") == true
		):
			retained.append(option)
			continue
		migrated_authority.erase(option_id)
	return {"options": retained, "authority": migrated_authority}


static func _validate_legacy_four_initial_choices(
	choices: Array, players: Dictionary, errors: Array[String]
) -> bool:
	var seen := {}
	for hero_id: Variant in choices:
		if (
			typeof(hero_id) != TYPE_INT
			or seen.has(hero_id)
			or not players.has(hero_id)
			or players[hero_id].exclusive_skill_id == "fate"
		):
			errors.append("legacy four-choice checkpoint has invalid initial hero choices")
			return false
		seen[hero_id] = true
	return true


static func _validate_legacy_four_recruitment_options(
	state: Dictionary, authority: Variant, players: Dictionary, errors: Array[String]
) -> bool:
	if state.get("status") != "reward" or not state.get("reward_pending", false) or typeof(authority) != TYPE_DICTIONARY or authority.size() != 4:
		errors.append("legacy four-choice recruitment checkpoint has invalid authority")
		return false
	var seen := {}
	for raw_option: Variant in state["reward_options"]:
		if typeof(raw_option) != TYPE_DICTIONARY or not _dictionary_has_exact_keys(raw_option, OPTION_KEYS):
			errors.append("legacy four-choice recruitment checkpoint has invalid option shape")
			return false
		var option: Dictionary = raw_option
		var hero_id: Variant = option.get("payload_id")
		if (
			option.get("type") != "hero"
			or typeof(hero_id) != TYPE_INT
			or seen.has(hero_id)
			or not players.has(hero_id)
			or players[hero_id].exclusive_skill_id == "fate"
			or state.get("hero_deployment_slots", {}).has(str(hero_id))
			or option.get("id") != "reward:hero:%d" % hero_id
			or option.get("name") != players[hero_id].name
			or option.get("description") != "招募后加入本局后台，可在整备区调整站位。"
			or option.get("price") != 0
			or option.get("purchased") != false
		):
			errors.append("legacy four-choice recruitment checkpoint has invalid option data: %s" % str(option.get("id")))
			return false
		if not authority.has(option["id"]) or authority[option["id"]] != option:
			errors.append("legacy four-choice recruitment checkpoint must match its authority")
			return false
		seen[hero_id] = true
	return true


func _deep_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var array_copy: Array = []
		for item: Variant in value:
			array_copy.append(_deep_copy(item))
		return array_copy
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary_copy := {}
		for key: Variant in value:
			dictionary_copy[_deep_copy(key)] = _deep_copy(value[key])
		return dictionary_copy
	return value
