class_name BattleCardSession
extends RefCounted

const CardCatalogScript = preload("res://data/catalogs/card_catalog.gd")
const Result = preload("res://core/card_runtime_result.gd")
const BattleRuntimeScript = preload("res://systems/combat/battle_runtime.gd")
const RoundResolverScript = preload("res://systems/combat/round_resolver.gd")
const DeckAssemblerScript = preload("res://systems/cards/battle_deck_assembler.gd")
const HandRuntimeScript = preload("res://systems/cards/hand_runtime.gd")

const CONFIG_KEYS := [
	"battle_runtime", "battle_seed", "deployed_hero_ids", "free_skill_ids",
]
const COMPONENT_IDS := ["battle_runtime", "hand_runtime", "card_catalog"]

var _battle_runtime: Variant
var _hand_runtime: Variant
var _card_catalog: Dictionary = {}
var _deployed_hero_ids: Array[int] = []
var _free_skill_ids: Array[String] = []
var _deck_card_ids: Array[String] = []
var _opening_draw: Dictionary = {}
var _trace: Array[Dictionary] = []
var _halted := false
var _settled := false
var _valid := false


func _init(config: Variant = {}, errors: Array[String] = []) -> void:
	errors.clear()
	var expected_keys: Array = CONFIG_KEYS.duplicate()
	if typeof(config) == TYPE_DICTIONARY and config.has("exclusive_card_ids"):
		expected_keys.append("exclusive_card_ids")
	if not _exact_keys(config, expected_keys, "battle card session config", errors):
		return
	var runtime: Variant = config["battle_runtime"]
	if (
		typeof(runtime) != TYPE_OBJECT
		or runtime == null
		or runtime.get_script() != BattleRuntimeScript
		or not runtime.is_valid()
	):
		errors.append("battle card session requires exact valid BattleRuntime")
		return
	if runtime.component("card_bridge") != null:
		errors.append("battle card session requires an uninstalled player card runtime")
		return
	if typeof(config["deployed_hero_ids"]) != TYPE_ARRAY:
		errors.append("battle card session deployed_hero_ids must be an Array")
		return
	if typeof(config["free_skill_ids"]) != TYPE_ARRAY:
		errors.append("battle card session free_skill_ids must be an Array")
		return

	var state: Variant = runtime.component("state")
	if state["game_over"] or state["phase"] != "player_input":
		errors.append("battle card session must start in a live player_input phase")
		return
	var input_roster: Array = config["deployed_hero_ids"].duplicate()
	var state_roster: Array = []
	for hero: Dictionary in state["player_heroes"]:
		if hero["deployed"]:
			state_roster.append(hero["id"])
	var sorted_input := input_roster.duplicate()
	var sorted_state := state_roster.duplicate()
	sorted_input.sort()
	sorted_state.sort()
	if sorted_input != sorted_state:
		errors.append("battle card session roster must exactly match deployed BattleState heroes")
		return

	var catalogs: Dictionary = runtime.component("catalogs")
	var catalog_errors: Array[String] = []
	var card_catalog := CardCatalogScript.build_from(
		catalogs["skills"], catalogs["hero_abilities"], catalog_errors
	)
	if not catalog_errors.is_empty() or card_catalog.is_empty():
		errors.append(
			"battle card session card catalog failed: %s"
			% (catalog_errors[0] if not catalog_errors.is_empty() else "empty catalog")
		)
		return
	var assembled: Dictionary = DeckAssemblerScript.assemble({
		"card_catalog": card_catalog,
		"player_catalog": catalogs["characters"]["players"],
		"exclusive_catalog": catalogs["hero_abilities"]["exclusive"],
		"deployed_hero_ids": config["deployed_hero_ids"],
		"free_skill_ids": config["free_skill_ids"],
		"exclusive_card_ids": config.get("exclusive_card_ids", []),
	})
	if not assembled["ok"]:
		errors.append(assembled["error"])
		return
	var deck: Dictionary = assembled["value"]
	var hand_runtime := HandRuntimeScript.new(config["battle_seed"])
	var initialized: Variant = hand_runtime.initialize_deck(deck["definitions"], true)
	if not initialized.ok:
		errors.append("battle card session deck initialization failed: %s" % initialized.message)
		return
	# Draw outcomes such as HAND_FULL or DECK_EMPTY describe the fixed attempts;
	# they do not invalidate an otherwise canonical battle session.
	var opening_draw: Variant = hand_runtime.draw_for_turn(deck["active_hero_count"])
	var install_errors: Array[String] = []
	if not runtime.install_player_card_runtime({
		"hand_runtime": hand_runtime,
		"card_catalog": card_catalog,
	}, install_errors):
		errors.append(
			"battle card session install failed: %s"
			% (install_errors[0] if not install_errors.is_empty() else "unknown error")
		)
		return

	_battle_runtime = runtime
	_hand_runtime = hand_runtime
	_card_catalog = card_catalog
	for hero_id: Variant in deck["deployed_hero_ids"]:
		_deployed_hero_ids.append(int(hero_id))
	for skill_id: Variant in deck["free_skill_ids"]:
		_free_skill_ids.append(str(skill_id))
	for card_id: Variant in deck["card_ids"]:
		_deck_card_ids.append(str(card_id))
	_opening_draw = opening_draw.to_dict()
	_trace.append({
		"event": "battle_card_session_started",
		"round": state["round"],
		"deployed_hero_ids": _deployed_hero_ids.duplicate(),
		"free_skill_ids": _free_skill_ids.duplicate(),
		"deck_card_ids": _deck_card_ids.duplicate(),
		"draw": _opening_draw.duplicate(true),
	})
	_valid = true


func is_valid() -> bool:
	return _valid


func is_halted() -> bool:
	return _halted or (_hand_runtime != null and _hand_runtime.is_queue_halted())


func is_settled() -> bool:
	return _settled


func component(id: Variant, errors: Array[String] = []) -> Variant:
	errors.clear()
	if not _valid:
		errors.append("battle card session is invalid")
		return null
	if typeof(id) != TYPE_STRING or id not in COMPONENT_IDS:
		errors.append("unknown battle card session component: %s" % str(id))
		return null
	match id:
		"battle_runtime": return _battle_runtime
		"hand_runtime": return _hand_runtime
		"card_catalog": return _card_catalog
	return null


func play_card(request: Variant) -> RefCounted:
	if not _valid:
		return _failure(Result.INVALID_ARGUMENT, "battle card session is invalid")
	if _settled:
		return _failure(Result.INVALID_ARGUMENT, "battle card session is settled")
	if is_halted():
		_halted = true
		return _failure(Result.QUEUE_HALTED, "battle card session is halted", {
			"fatal": true, "committed_prefix": true,
		})
	var state: Dictionary = _battle_runtime.component("state")
	if state["phase"] != "player_input" or state["game_over"]:
		return _failure(Result.VALIDATOR_REJECTED, "player cards require a live player_input phase")
	var result: Variant = _battle_runtime.play_player_card(request)
	var request_snapshot: Variant = null
	if typeof(request) == TYPE_OBJECT and request != null and request.has_method("to_dict"):
		request_snapshot = request.to_dict()
	_trace.append({
		"event": "player_card_finished",
		"round": state["round"],
		"request": request_snapshot,
		"result": result.to_dict(),
	})
	if not result.ok and bool(result.details.get("fatal", false)):
		_halted = true
	return result


func inspect_card(request: Variant) -> RefCounted:
	if not _valid:
		return _failure(Result.INVALID_ARGUMENT, "battle card session is invalid")
	return _battle_runtime.inspect_player_card(request)


func end_player_turn() -> RefCounted:
	if not _valid:
		return _failure(Result.INVALID_ARGUMENT, "battle card session is invalid")
	if _settled:
		return _failure(Result.INVALID_ARGUMENT, "battle card session is settled")
	if is_halted():
		_halted = true
		return _failure(Result.QUEUE_HALTED, "battle card session is halted", {
			"fatal": true, "committed_prefix": true,
		})
	var state: Dictionary = _battle_runtime.component("state")
	if state["game_over"] or state["phase"] != "player_input":
		return _failure(Result.VALIDATOR_REJECTED, "end turn requires a live player_input phase")

	var discarded: Variant = _hand_runtime.end_player_turn()
	if not discarded.ok:
		return discarded
	_trace.append({
		"event": "player_hand_discarded",
		"round": state["round"],
		"result": discarded.to_dict(),
	})
	var round_result: Dictionary = _battle_runtime.resolve_round()
	if not round_result["ok"]:
		_halted = true
		var failure_details := {
			"fatal": true,
			"committed_prefix": true,
			"discard": discarded.to_dict(),
			"round_error": round_result["error"],
		}
		_trace.append({
			"event": "round_failed",
			"round": state["round"],
			"result": failure_details.duplicate(true),
		})
		return _failure(
			Result.COMMITTED_FAILURE,
			"battle round failed after player hand commit: %s" % round_result["error"],
			failure_details,
		)

	var resolved: Dictionary = round_result["value"].duplicate(true)
	var terminal: bool = state["game_over"] or resolved["status"] in ["settled", "already_settled"]
	var before_next_draw: Dictionary = _hand_runtime.snapshot()
	var next_draw: Variant = null
	if terminal:
		_settled = true
	else:
		if state["phase"] != "player_input":
			_halted = true
			return _failure(Result.COMMITTED_FAILURE, "round completed outside player_input phase", {
				"fatal": true, "committed_prefix": true,
				"discard": discarded.to_dict(), "round": resolved,
			})
		next_draw = _hand_runtime.draw_for_turn(_deployed_hero_ids.size())
	resolved["m3_obligations"] = _fulfilled_responsibilities(terminal)
	var next_draw_snapshot: Variant = null if next_draw == null else next_draw.to_dict()
	var details := {
		"status": "settled" if terminal else "player_input",
		"discard": discarded.to_dict(),
		"round": resolved,
		"before_next_draw": before_next_draw,
		"next_draw": next_draw_snapshot,
		"m3_obligations": resolved["m3_obligations"].duplicate(true),
	}
	_trace.append({
		"event": "battle_round_finished",
		"round_before": resolved["round_before"],
		"round_after": resolved["round_after"],
		"terminal": terminal,
		"discard": discarded.to_dict(),
		"round": resolved.duplicate(true),
		"before_next_draw": before_next_draw.duplicate(true),
		"next_draw": null if next_draw_snapshot == null else next_draw_snapshot.duplicate(true),
	})
	return Result.new(true, Result.OK, "", details)


func snapshot() -> Dictionary:
	if not _valid:
		return {}
	var state: Dictionary = _battle_runtime.component("state")
	return {
		"active": not is_halted() and not _settled,
		"halted": is_halted(),
		"settled": _settled,
		"round": state["round"],
		"phase": state["phase"],
		"game_over": state["game_over"],
		"battle_result": state["battle_result"],
		"deployed_hero_ids": _deployed_hero_ids.duplicate(),
		"free_skill_ids": _free_skill_ids.duplicate(),
		"deck_card_ids": _deck_card_ids.duplicate(),
		"opening_draw": _opening_draw.duplicate(true),
		"hand": _hand_runtime.snapshot(),
		"trace": _trace.duplicate(true),
	}


static func _fulfilled_responsibilities(terminal: bool) -> Array[Dictionary]:
	var fulfilled: Array[Dictionary] = []
	for obligation: Dictionary in RoundResolverScript.M3_SESSION_RESPONSIBILITIES:
		var entry := obligation.duplicate(true)
		entry["status"] = (
			"skipped_terminal"
			if terminal and entry["id"] == "draw_next_player_turn_after_finalize"
			else "fulfilled"
		)
		fulfilled.append(entry)
	return fulfilled


static func _failure(code: String, message: String, details: Dictionary = {}) -> RefCounted:
	return Result.new(false, code, message, details)


static func _exact_keys(value: Variant, keys: Array, path: String, errors: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		errors.append("%s must have a canonical closed shape" % path)
		return false
	for key: String in keys:
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
			return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			errors.append("%s contains an unknown field" % path)
			return false
	return true
