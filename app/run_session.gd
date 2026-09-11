class_name RunSession
extends RefCounted

## Composition root for the player-facing roguelike Run.  Views receive only
## snapshots; every mutation enters through execute(), then the lifecycle owns
## validation, option authority, and transactional RNG rollback.

const ContentCatalogScript = preload("res://data/catalogs/content_catalog.gd")
const RunContractScript = preload("res://systems/roguelike/run_contract.gd")
const RunLifecycleScript = preload("res://systems/roguelike/run_lifecycle.gd")
const DeterministicRngScript = preload("res://core/rng.gd")
const TransactionalRandomScript = preload("res://systems/roguelike/run_random_transaction.gd")

const SAVE_VERSION := 1
const ECONOMY_OR_DEPLOY_COMMANDS := [
	"select_reward", "recruit_hero", "buy_shop_option", "buy_forge_option",
	"claim_reward", "buy_option", "use_forge_heal", "heal", "sell_free_skill",
	"complete_current_node", "leave_node", "set_hero_deployment_slot", "deploy",
	"swap_piece_slots", "set_piece_class",
]

var catalogs: Dictionary = {}
var state: Dictionary = {}
var raw_rng: Variant = null
var transaction_rng: Variant = null
var lifecycle: Variant = null
var save_store: Variant = null
var save_warning: Dictionary = {}


func _init(content_catalog: Dictionary = {}, save_path: String = "user://run-save.json") -> void:
	if content_catalog.is_empty():
		var catalog_errors: Array[String] = []
		catalogs = ContentCatalogScript.build(catalog_errors)
	else:
		catalogs = content_catalog
	state = RunContractScript.create()
	_create_save_store(save_path)


func new_run(seed: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if catalogs.is_empty():
		errors.append("RunSession content catalog is unavailable")
		return false
	var random_errors: Array[String] = []
	raw_rng = DeterministicRngScript.new(seed)
	transaction_rng = TransactionalRandomScript.new(raw_rng, random_errors)
	if not random_errors.is_empty() or not transaction_rng.is_valid():
		errors.append(random_errors[0] if not random_errors.is_empty() else "Run random setup failed")
		_clear_runtime()
		return false
	state = RunContractScript.create()
	var lifecycle_errors: Array[String] = []
	lifecycle = RunLifecycleScript.new(state, catalogs, transaction_rng, lifecycle_errors)
	if not lifecycle_errors.is_empty() or not lifecycle.is_valid():
		errors.append(lifecycle_errors[0] if not lifecycle_errors.is_empty() else "Run lifecycle setup failed")
		_clear_runtime()
		return false
	if not lifecycle.start_run(errors):
		_clear_runtime()
		return false
	_refresh_state()
	_save_after_mutation()
	return true


func continue_run(errors: Array[String] = []) -> bool:
	errors.clear()
	if save_store == null:
		errors.append("Run save store is unavailable")
		return false
	var envelope: Variant = save_store.load(errors)
	if envelope == null:
		return false
	return restore_checkpoint(envelope, errors)


func restore_checkpoint(envelope: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if (
		typeof(envelope) != TYPE_DICTIONARY
		or envelope.size() != 3
		or not envelope.has("version")
		or not envelope.has("random")
		or not envelope.has("lifecycle")
	):
		errors.append("Run save envelope has an invalid shape")
		return false
	if envelope["version"] != SAVE_VERSION or typeof(envelope["random"]) != TYPE_DICTIONARY:
		errors.append("Run save envelope has an unsupported version")
		return false
	var random_checkpoint: Dictionary = envelope["random"]
	if not random_checkpoint.has("source_state"):
		errors.append("Run save is missing its random source state")
		return false
	var restore_errors: Array[String] = []
	var restored_raw: Variant = DeterministicRngScript.from_state(random_checkpoint["source_state"], restore_errors)
	if not restore_errors.is_empty() or restored_raw == null:
		errors.append(restore_errors[0] if not restore_errors.is_empty() else "Run random source restore failed")
		return false
	var restored_random: Variant = TransactionalRandomScript.restore_checkpoint(
		random_checkpoint, restored_raw, restore_errors,
	)
	if not restore_errors.is_empty() or restored_random == null:
		errors.append(restore_errors[0] if not restore_errors.is_empty() else "Run random restore failed")
		return false
	var restored_lifecycle: Variant = RunLifecycleScript.restore_checkpoint(
		envelope["lifecycle"], catalogs, restored_random, restore_errors,
	)
	if not restore_errors.is_empty() or restored_lifecycle == null:
		errors.append(restore_errors[0] if not restore_errors.is_empty() else "Run lifecycle restore failed")
		return false
	raw_rng = restored_raw
	transaction_rng = restored_random
	lifecycle = restored_lifecycle
	_refresh_state()
	return true


func snapshot(errors: Array[String] = []) -> Dictionary:
	errors.clear()
	if lifecycle == null:
		return RunContractScript.snapshot(state, errors)
	return lifecycle.snapshot(errors)


func view_model(errors: Array[String] = []) -> Dictionary:
	var run := snapshot(errors)
	if not errors.is_empty():
		return {}
	var costs := {}
	var event := {}
	if lifecycle != null:
		if str(run.get("status", "")) == "event":
			var event_errors: Array[String] = []
			event = lifecycle.get_current_event(event_errors)
		for raw_option: Variant in run.get("shop_options", []):
			if typeof(raw_option) != TYPE_DICTIONARY:
				continue
			var option_id := str(raw_option.get("id", ""))
			var cost_errors: Array[String] = []
			var cost: Variant = lifecycle.get_option_cost(option_id, cost_errors)
			if cost_errors.is_empty() and cost != null:
				costs[option_id] = cost
		var heal_errors: Array[String] = []
		var heal_cost: Variant = lifecycle.get_forge_heal_cost(heal_errors)
		if heal_errors.is_empty() and heal_cost != null:
			costs["forge:heal"] = heal_cost
	return {
		"run": run,
		"status": str(run.get("status", "idle")),
		"active": bool(run.get("active", false)),
		"fighting": str(run.get("status", "")) == "fighting",
		"can_continue": save_store != null and save_store.has_method("has_save") and save_store.has_save(),
		"catalog": catalog_snapshot(),
		"costs": costs,
		"event": event,
		"save_warning": save_warning.duplicate(true),
	}


func catalog_snapshot() -> Dictionary:
	var heroes: Array[Dictionary] = []
	var skills := {}
	var relics := {}
	var abilities := {}
	var piece_classes := {}
	var exclusive_abilities: Dictionary = catalogs.get("hero_abilities", {}).get("exclusive", {})
	for ability_id: Variant in exclusive_abilities:
		var ability: Variant = exclusive_abilities[ability_id]
		abilities[ability_id] = _ability_view(ability)
	for hero_id: Variant in catalogs.get("characters", {}).get("players", {}):
		var hero: Variant = catalogs["characters"]["players"][hero_id]
		var exclusive: Variant = exclusive_abilities.get(hero.exclusive_skill_id)
		heroes.append({
			"id": hero.id,
			"name": hero.name,
			"exclusive_skill_id": hero.exclusive_skill_id,
			"exclusive_name": "" if exclusive == null else exclusive.name,
			"exclusive_description": "" if exclusive == null else exclusive.tip,
			"is_passive": false if exclusive == null else exclusive.is_passive,
			"base_sp_cost": 0 if exclusive == null else exclusive.base_sp_cost,
			"portrait_path": hero.source_portrait_path,
			"max_energy": hero.max_energy,
		})
	heroes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left["id"] < right["id"])
	for skill_id: Variant in catalogs.get("skills", {}):
		var skill: Variant = catalogs["skills"][skill_id]
		skills[skill_id] = {
			"id": skill.id, "name": skill.name, "description": skill.tip,
			"base_sp_cost": skill.base_sp_cost,
		}
	for relic_id: Variant in catalogs.get("relics", {}):
		var relic: Variant = catalogs["relics"][relic_id]
		relics[relic_id] = {
			"id": relic.id, "name": relic.name,
			"description": relic.description, "category": relic.category,
		}
	for class_id: Variant in catalogs.get("piece_classes", {}):
		var piece_class: Variant = catalogs["piece_classes"][class_id]
		if class_id in ["shield", "assassin", "crossbow", "banner"]:
			piece_classes[class_id] = {
				"id": piece_class.id, "name": piece_class.name, "description": piece_class.tip,
			}
	return {
		"heroes": heroes, "skills": skills, "relics": relics, "abilities": abilities,
		"piece_classes": piece_classes,
	}


static func _ability_view(ability: Variant) -> Dictionary:
	return {
		"id": ability.id,
		"owner_hero_id": ability.owner_hero_id,
		"ability_type": ability.ability_type,
		"name": ability.name,
		"description": ability.tip,
		"is_passive": ability.is_passive,
		"base_sp_cost": ability.base_sp_cost,
		"source_energy_requirement": ability.source_energy_requirement,
	}


func execute(command: Dictionary, errors: Array[String] = []) -> bool:
	errors.clear()
	if lifecycle == null:
		errors.append("RunSession has no active lifecycle")
		return false
	# The battle adapter settles directly through the same lifecycle. Refresh
	# its published status before app-level guards, rather than retaining the
	# pre-battle 'fighting' snapshot and rejecting the earned reward.
	_refresh_state()
	if typeof(command) != TYPE_DICTIONARY or typeof(command.get("type")) != TYPE_STRING:
		errors.append("Run command requires a string type")
		return false
	var type: String = command["type"]
	var status := str(state.get("status", "idle"))
	if status == "fighting" and type in ECONOMY_OR_DEPLOY_COMMANDS:
		errors.append("Run command %s is unavailable while a battle is active" % type)
		return false
	# A Run battle cannot be checkpointed while its one-shot progress object is
	# open. Persist the still-map state first, so a failed launch or process exit
	# always resumes at a safe frontier instead of a half-open battle.
	if type == "choose_node" and not _save_before_node_launch(errors):
		return false
	var ok := false
	match type:
		"choose_starting_hero":
			ok = lifecycle.choose_starting_hero(command.get("hero_id"), errors)
		"choose_node":
			ok = lifecycle.choose_node(command.get("node_id"), errors)
		"select_reward", "claim_reward":
			ok = lifecycle.select_reward(command.get("option_id"), errors)
		"skip_normal_reward_group":
			ok = lifecycle.skip_normal_reward_group(command.get("group"), errors)
		"recruit_hero":
			ok = lifecycle.recruit_hero(command.get("hero_id"), errors)
		"buy_shop_option":
			ok = lifecycle.buy_shop_option(command.get("option_id"), errors)
		"buy_forge_option":
			ok = lifecycle.buy_forge_option(command.get("option_id"), errors)
		"buy_option":
			if status == "shop":
				ok = lifecycle.buy_shop_option(command.get("option_id"), errors)
			elif status == "forge":
				ok = lifecycle.buy_forge_option(command.get("option_id"), errors)
		"use_forge_heal", "heal":
			ok = lifecycle.use_forge_heal(errors)
		"sell_free_skill":
			ok = lifecycle.sell_free_skill(command.get("skill_id"), errors)
		"select_retained_card":
			ok = lifecycle.select_retained_card(command.get("key"), errors)
		"skip_retained_card_event":
			ok = lifecycle.skip_retained_card_event(errors)
		"complete_current_node", "leave_node":
			ok = lifecycle.complete_current_node(errors)
		"set_hero_deployment_slot", "deploy":
			ok = lifecycle.set_hero_deployment_slot(command.get("hero_id"), command.get("slot"), errors)
		"swap_piece_slots":
			ok = lifecycle.swap_piece_slots(command.get("first_slot"), command.get("second_slot"), errors)
		"set_piece_class":
			ok = lifecycle.set_piece_class(command.get("slot"), command.get("piece_class_id"), errors)
		"quit_run", "end_run":
			ok = lifecycle.quit_run(errors)
		_:
			errors.append("Unknown Run command: %s" % type)
			return false
	if not ok:
		if errors.is_empty():
			errors.append("Run command was rejected: %s" % type)
		return false
	_refresh_state()
	_save_after_mutation()
	return true


func battle_lifecycle(errors: Array[String] = []) -> Variant:
	errors.clear()
	if lifecycle == null or str(state.get("status", "")) != "fighting":
		errors.append("Run is not waiting to launch a battle")
		return null
	return lifecycle


func save_checkpoint(errors: Array[String] = []) -> bool:
	errors.clear()
	if save_store == null:
		errors.append("Run save store is unavailable")
		return false
	if lifecycle == null or raw_rng == null or transaction_rng == null:
		errors.append("RunSession has no active checkpointable Run")
		return false
	var checkpoint := _checkpoint(errors)
	if checkpoint.is_empty():
		return false
	var saved: bool = save_store.save(checkpoint, errors)
	if saved:
		save_warning.clear()
	else:
		_record_save_warning(errors)
	return saved


func _checkpoint(errors: Array[String]) -> Dictionary:
	errors.clear()
	var random_checkpoint: Dictionary = transaction_rng.export_checkpoint(errors)
	if not errors.is_empty() or random_checkpoint.is_empty():
		return {}
	var lifecycle_checkpoint: Dictionary = lifecycle.export_checkpoint(errors)
	if not errors.is_empty() or lifecycle_checkpoint.is_empty():
		return {}
	return {"version": SAVE_VERSION, "random": random_checkpoint, "lifecycle": lifecycle_checkpoint}


func _save_before_node_launch(errors: Array[String]) -> bool:
	errors.clear()
	if not save_checkpoint(errors):
		return false
	return true


func _save_after_mutation() -> void:
	if save_store == null:
		return
	# A fighting Run owns an open one-shot battle progress object, which is
	# intentionally not serializable.  The map snapshot immediately before the
	# launch remains the resume point until the coordinator settles the battle.
	if str(state.get("status", "")) == "fighting":
		return
	var save_errors: Array[String] = []
	save_checkpoint(save_errors)


func _record_save_warning(errors: Array[String]) -> void:
	save_warning = {
		"code": "save_failed",
		"message": errors[0] if not errors.is_empty() else "Run save failed",
	}


func _refresh_state() -> void:
	if lifecycle == null:
		return
	var state_errors: Array[String] = []
	var published: Dictionary = lifecycle.snapshot(state_errors)
	if state_errors.is_empty():
		state = published


func _create_save_store(save_path: String) -> void:
	# M6 persistence is deliberately optional for composition-root construction
	# during import. The concrete store is required before continuing or saving.
	var store_path := "res://app/run_save_store.gd"
	if not ResourceLoader.exists(store_path):
		return
	var store_script: Variant = load(store_path)
	if store_script != null:
		save_store = store_script.new(save_path)


func _clear_runtime() -> void:
	state = RunContractScript.create()
	raw_rng = null
	transaction_rng = null
	lifecycle = null
	save_warning.clear()
