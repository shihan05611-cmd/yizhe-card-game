class_name BattleScreen
extends Control

const DamageFloatScene = preload("res://scenes/effects/damage_float.tscn")
const HealFloatScene = preload("res://scenes/effects/heal_float.tscn")
const CombatMarkerScene = preload("res://scenes/effects/combat_marker.tscn")
const PendingCardQueueScript = preload("res://ui/cards/pending_card_queue.gd")
const DevourPulseScene = preload("res://scenes/effects/devour_pulse.tscn")
const LOG_DRAWER_DURATION := 0.18
const LOG_DRAWER_WIDTH := 300.0

signal end_turn_requested
signal speed_requested(speed: float)
signal auto_battle_requested(enabled: bool)
signal restart_requested
signal play_card_requested(command: Dictionary)

@onready var battle_hud: Node = %BattleHud
@onready var ally_board: Node = %AllyBoard
@onready var enemy_board: Node = %EnemyBoard
@onready var ally_heroes: Node = %AllyHeroes
@onready var enemy_heroes: Node = %EnemyHeroes
@onready var combat_log: Node = %CombatLog
@onready var log_slot: MarginContainer = %LogSlot
@onready var hand_view: Node = %HandView
@onready var fx_player: Node = %SkillFxPlayer
@onready var feedback_layer: Control = %FeedbackLayer
@onready var result_overlay: Node = %ResultOverlay
@onready var fatal_overlay: Node = %FatalOverlay
@onready var ally_side_buffs: Label = %AllySideBuffs
@onready var enemy_side_buffs: Label = %EnemySideBuffs
@onready var target_overlay: Control = %CardTargetOverlay

var _pending: Dictionary = {}
var _input_locked := false
var _terminal_locked := false
var _queue_busy := false
var _fx_end_tweens: Array[Tween] = []
var _combat_log_open := false
var _unread_log_count := 0
var _last_log_count := 0
var _log_tween: Tween
var _presented_piece_actions: Dictionary = {}
var _pending_card_queue: Control
var _side_buffs := {"ally": [], "enemy": []}
var _aim_card_id := ""
var _aim_origin := Vector2.ZERO
var _aim_pointer := Vector2.ZERO
var _aim_armed := false


func _ready() -> void:
	battle_hud.end_turn_requested.connect(func() -> void: end_turn_requested.emit())
	battle_hud.speed_requested.connect(func(speed: float) -> void: speed_requested.emit(speed))
	battle_hud.auto_battle_requested.connect(
		func(enabled: bool) -> void: auto_battle_requested.emit(enabled)
	)
	battle_hud.combat_log_toggle_requested.connect(toggle_combat_log)
	result_overlay.restart_requested.connect(func() -> void: restart_requested.emit())
	fatal_overlay.restart_requested.connect(func() -> void: restart_requested.emit())
	hand_view.target_drag_updated.connect(_show_card_target_preview)
	hand_view.target_drag_ended.connect(_clear_card_target_preview)
	hand_view.play_card_requested.connect(func(command: Dictionary) -> void:
		var targeted_command := _resolve_card_target(command)
		if targeted_command.is_empty():
			show_pending_card_notice("请将卡牌拖到一个有效目标上")
			return
		play_card_requested.emit(targeted_command)
	)
	_pending_card_queue = PendingCardQueueScript.new()
	_pending_card_queue.cancel_requested.connect(func(instance_id: String) -> void:
		pending_card_cancel_requested.emit(instance_id)
	)
	add_child(_pending_card_queue)
	resized.connect(_layout_pending_card_queue)
	call_deferred("_layout_pending_card_queue")
	if not _pending.is_empty():
		_apply(_pending)
	else:
		set_combat_log_open(false, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_combat_log"):
		if event is InputEventKey and event.echo:
			return
		toggle_combat_log()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _aim_card_id.is_empty():
		return
	var card: Variant = hand_view.card_for_instance(_aim_card_id)
	if card == null or not card.is_dragging() or _terminal_locked:
		_clear_card_target_preview()
		return
	_show_card_target_preview(card.view_model(), _aim_origin, _aim_pointer, _aim_armed)


func _clear_card_target_preview() -> void:
	_aim_card_id = ""
	target_overlay.clear_aim()


func bind_view_model(vm: Dictionary) -> void:
	_pending = vm.duplicate(true)
	if is_node_ready():
		_apply(_pending)


func is_input_locked() -> bool:
	return _input_locked


func is_combat_log_open() -> bool:
	return _combat_log_open


func unread_log_count() -> int:
	return _unread_log_count


func log_transition_duration() -> float:
	return LOG_DRAWER_DURATION


func toggle_combat_log() -> void:
	set_combat_log_open(not _combat_log_open)


func set_combat_log_open(open: bool, animate := true) -> void:
	if _log_tween != null and _log_tween.is_valid():
		_log_tween.kill()
	_combat_log_open = open
	if open:
		_unread_log_count = 0
	if not is_node_ready():
		return
	battle_hud.set_log_state(_combat_log_open, _unread_log_count)
	if not animate or not is_inside_tree():
		combat_log.position.x = 0.0
		log_slot.visible = _combat_log_open
		return
	log_slot.visible = true
	if _combat_log_open:
		combat_log.call_deferred("scroll_to_bottom")
	_log_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _combat_log_open:
		combat_log.position.x = LOG_DRAWER_WIDTH
		_log_tween.tween_property(combat_log, "position:x", 0.0, LOG_DRAWER_DURATION)
	else:
		_log_tween.tween_property(
			combat_log, "position:x", LOG_DRAWER_WIDTH, LOG_DRAWER_DURATION
		)
		_log_tween.tween_callback(_finish_log_close)


func _finish_log_close() -> void:
	if _combat_log_open:
		return
	log_slot.visible = false
	combat_log.position.x = 0.0


func set_queue_busy(busy: bool) -> void:
	_queue_busy = busy
	_apply_interaction_lock()


signal pending_card_cancel_requested(instance_id: String)


func set_pending_cards(entries: Array) -> void:
	if not is_instance_valid(_pending_card_queue):
		return
	_pending_card_queue.set_entries(entries)
	var occupied := not entries.is_empty()
	battle_hud.end_turn_button.visible = not occupied
	for path: String in ["Actions/DiscardCountRow", "Actions/ExhaustCountRow"]:
		var row: CanvasItem = battle_hud.get_node_or_null(path)
		if row != null:
			row.visible = not occupied
	_layout_pending_card_queue()


func set_pending_card_instances(instance_ids: Array) -> void:
	hand_view.set_queued_instance_ids(instance_ids)


func cancel_pending_return_flights() -> void:
	if is_instance_valid(_pending_card_queue):
		_pending_card_queue.cancel_return_flights()


func refresh_visible_hand_availability(authoritative_hand: Array) -> void:
	hand_view.refresh_visible_availability(authoritative_hand)


## Clears the previous turn's visual hand immediately after its authoritative
## discard has committed. The coordinator binds the next-turn ViewModel after
## the round presentation batch, which creates the new hand in its canonical
## order.
func clear_hand_for_turn_settlement(retained_instance_ids: Array = []) -> void:
	hand_view.clear_for_turn_settlement(retained_instance_ids)


func take_card_release_pose(instance_id: String) -> Dictionary:
	var pose: Dictionary = hand_view.take_release_pose(instance_id)
	if not pose.is_empty(): return pose
	var card: Variant = hand_view.card_for_instance(instance_id)
	if card == null: return {}
	return {"position": card.global_position, "rotation": card.rotation, "scale": card.scale}


func present_card_settlement(instance_id: String, card_vm: Dictionary, pose: Dictionary, duration: float) -> void:
	_pending_card_queue.animate_arrival(instance_id, card_vm, pose, duration)


func show_pending_card_notice(message: String) -> void:
	if is_instance_valid(_pending_card_queue):
		_pending_card_queue.show_notice(message)


func pending_card_count() -> int:
	return _pending_card_queue.get("_entries").size() if is_instance_valid(_pending_card_queue) else 0


func _layout_pending_card_queue() -> void:
	if not is_instance_valid(_pending_card_queue) or not is_instance_valid(battle_hud):
		return
	var button: Control = battle_hud.end_turn_button
	var button_rect: Rect2 = button.get_global_rect()
	var hand_rect: Rect2 = hand_view.get_global_rect()
	# Queue cards use the right-side action strip inside the hand band.  The
	# original end-turn control only provides its stable x alignment; anchoring
	# a tall card to that button would overlap the enemy formation.
	var action_rect := Rect2(
		Vector2(button_rect.position.x, hand_rect.position.y + 12.0) - get_global_rect().position,
		Vector2(122.0, maxf(1.0, hand_rect.size.y - 20.0)),
	)
	_pending_card_queue.set_queue_anchor(action_rect)


func set_presentation_speed(speed: float) -> void:
	set_speed_display(speed)
	set_effect_speed(speed)


func set_speed_display(speed: float) -> void:
	battle_hud.set_speed_display(speed)


func set_effect_speed(speed: float) -> void:
	for board: Node in [ally_board, enemy_board]:
		for slot: Node in board.slot_nodes():
			slot.set_presentation_speed(speed)


func set_duration_clock(clock: Callable) -> void:
	fx_player.set_duration_clock(clock)


func set_anchor_resolver(resolver: Callable) -> void:
	fx_player.set_anchor_resolver(resolver)


func present_event(event: Dictionary, duration: float) -> void:
	var target: Dictionary = event.get("visual_target", {})
	var kind := str(event.get("kind", ""))
	var event_id := str(event.get("event_id", ""))
	var payload: Dictionary = event.get("payload", {})
	var target_slot: Variant = _slot_for_target(target)
	_pulse_source(event, duration)
	_maybe_start_source_fx(event)
	if event_id == "relicTriggered":
		battle_hud.present_relic_trigger(str(payload.get("relic_id", "")), duration)
	elif event_id == "resourceChanged" and payload.get("resource") == "sp":
		battle_hud.present_sp_change(float(payload.get("new_sp", 0)), duration)
	elif event_id == "enemySpecialTriggered" and payload.get("special_id") == "devourer":
		_present_devour_trigger(payload, duration)
	elif kind == "damage" and event_id == "damage_applied":
		if target_slot != null:
			target_slot.present_hp_change(
				float(payload.get("old_hp", target_slot.hp_bar.value)),
				float(payload.get("new_hp", target_slot.hp_bar.value)),
				float(payload.get("target", {}).get("max_hp", target_slot.hp_bar.max_value)),
				duration,
			)
			target_slot.present_pulse(duration, Color(1.25, 0.62, 0.58, 1.0))
		_spawn_damage_float(event, duration)
		var tags: Array[String] = []
		if bool(payload.get("crit", false)): tags.append("暴击")
		if bool(payload.get("blocked", false)): tags.append("格挡")
		if not tags.is_empty(): _spawn_marker("·".join(tags), event, duration)
	elif kind == "heal":
		if target_slot != null:
			target_slot.present_hp_change(
				float(payload.get("old_hp", target_slot.hp_bar.value)),
				float(payload.get("new_hp", target_slot.hp_bar.value)),
				float(target_slot.hp_bar.max_value),
				duration,
			)
			target_slot.present_pulse(duration, Color(0.55, 1.2, 0.68, 1.0))
		_spawn_float(HealFloatScene, event, duration)
	elif kind == "buff" and target_slot != null:
		target_slot.present_buff_event(event)
		if str(payload.get("buff_id", "")) == "burn":
			target_slot.present_pulse(duration, Color(1.10, 0.69, 0.38, 1.0))
	elif kind == "buff" and str(target.get("kind", "")) == "side":
		_apply_side_buff_event(str(target.get("side", "")), payload)
	elif kind == "card":
		hand_view.present_card_event(event, duration)
		if str(payload.get("destination", "")) == "hand":
			var returning_card: Variant = hand_view.prepare_queued_return(
				str(payload.get("card_instance_id", ""))
			)
			if returning_card != null:
				_pending_card_queue.animate_return(
					str(payload.get("card_instance_id", "")), returning_card, duration
				)
		_present_card_fx(event, duration)
	elif kind == "fatal":
		fatal_overlay.bind_fatal(payload)
		_terminal_locked = true
		_apply_interaction_lock()


func finish_event(_event: Dictionary) -> void:
	pass


func _present_devour_trigger(payload: Dictionary, duration: float) -> void:
	var actor: Dictionary = payload.get("actor", {})
	var actor_slot: Variant = _slot_for_target({"kind": "unit", "side": "enemy", "unit_id": actor.get("id"), "slot": actor.get("slot")})
	var resource_position: Vector2 = battle_hud.sp_orb.get_global_rect().get_center()
	var amount := float(payload.get("amount", 0))
	if payload.get("kind") == "sp_drain":
		battle_hud.present_sp_change(float(payload.get("new_sp", 0)), duration, amount)
	elif payload.get("kind") == "energy_drain":
		battle_hud.present_sp_change(float(payload.get("new_sp", 0)), duration)
		var hero: Dictionary = payload.get("target", {})
		var hero_item: Variant = ally_heroes.item_for_hero(hero.get("hero_id"))
		if hero_item != null:
			hero_item.present_energy_value(float(hero.get("new_energy", 0)))
			resource_position = hero_item.get_global_rect().get_center()
		var drain_text := "吞噬 −%d 能量" % roundi(amount) if amount > 0 else "吞噬 · 能量已空"
		_spawn_marker(drain_text, {"visual_target": {"kind": "hero", "side": "ally", "hero_id": hero.get("hero_id")}}, duration)
	if actor_slot == null: return
	actor_slot.present_pulse(duration, Color(1.05, 0.65, 1.5))
	var pulse: Control = DevourPulseScene.instantiate()
	feedback_layer.add_child(pulse)
	pulse.play(resource_position, actor_slot.chess_art.get_global_rect().get_center(), maxf(0.12, duration))
	_spawn_marker("吞噬", {"visual_target": {"kind": "unit", "side": "enemy", "unit_id": actor.get("id"), "slot": actor.get("slot")}}, duration)


func clear_transient_feedback() -> void:
	for child: Node in feedback_layer.get_children():
		feedback_layer.remove_child(child)
		child.queue_free()


func reset_presentation() -> void:
	for tween: Tween in _fx_end_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_fx_end_tweens.clear()
	fx_player.clear_visual_effect()
	clear_transient_feedback()
	_presented_piece_actions.clear()
	battle_hud.reset_trigger_feedback()
	for board: Node in [ally_board, enemy_board]:
		for slot: Node in board.slot_nodes():
			slot.reset_visuals()
	_queue_busy = false
	_terminal_locked = false
	_apply_interaction_lock()


func feedback_instances() -> Array[Node]:
	var nodes: Array[Node] = []
	for child: Node in feedback_layer.get_children():
		nodes.append(child)
	return nodes


func resolve_visual_anchor(target: Dictionary) -> Dictionary:
	var control: Control = _control_for_target(target)
	if control == null:
		return {"position": size * 0.5}
	return {"position": control.get_global_rect().get_center() - get_global_rect().position}


func _apply(vm: Dictionary) -> void:
	battle_hud.bind_view_model(vm)
	ally_board.bind_team(vm.get("teams", {}).get("ally", {"slots": []}))
	enemy_board.bind_team(vm.get("teams", {}).get("enemy", {"slots": []}))
	_side_buffs["ally"] = vm.get("teams", {}).get("ally", {}).get("side_buffs", []).duplicate(true)
	_side_buffs["enemy"] = vm.get("teams", {}).get("enemy", {}).get("side_buffs", []).duplicate(true)
	_refresh_side_buffs()
	ally_heroes.bind_heroes(vm.get("heroes", {}).get("ally", []))
	enemy_heroes.bind_heroes(vm.get("heroes", {}).get("enemy", []))
	_sync_hero_panel_heights()
	var logs: Array = vm.get("logs", [])
	if not _combat_log_open:
		if logs.size() < _last_log_count:
			_unread_log_count = mini(100, logs.size())
		elif logs.size() > _last_log_count:
			_unread_log_count = mini(100, _unread_log_count + logs.size() - _last_log_count)
	_last_log_count = logs.size()
	combat_log.bind_logs(logs)
	battle_hud.set_log_state(_combat_log_open, _unread_log_count)
	hand_view.apply_view_model(vm)
	var battle: Dictionary = vm.get("battle", {})
	var fatal: Variant = vm.get("fatal")
	result_overlay.bind_result(battle.get("result"))
	fatal_overlay.bind_fatal(fatal)
	_terminal_locked = bool(battle.get("game_over", false)) or typeof(fatal) == TYPE_DICTIONARY
	_apply_interaction_lock()


func _sync_hero_panel_heights() -> void:
	# Portrait columns stretch with the arena; hero count must not push the hand down.
	ally_heroes.custom_minimum_size.y = 0
	enemy_heroes.custom_minimum_size.y = 0


func _apply_interaction_lock() -> void:
	if not is_node_ready():
		return
	_input_locked = _terminal_locked or _queue_busy
	battle_hud.set_input_locked(_terminal_locked)
	battle_hud.set_queue_busy(_queue_busy)
	var battle: Dictionary = _pending.get("battle", {})
	var session: Dictionary = _pending.get("session", {})
	hand_view.set_interaction_state(
		false,
		_terminal_locked,
		str(battle.get("phase", "")),
		bool(session.get("halted", false)),
	)


func _slot_for_target(target: Dictionary) -> Variant:
	var side := str(target.get("side", ""))
	if side == "ally":
		return ally_board.slot_for_target(target)
	if side == "enemy":
		return enemy_board.slot_for_target(target)
	return null


func _resolve_card_target(command: Dictionary) -> Dictionary:
	var result := command.duplicate(true)
	var release_position: Variant = result.get("release_position")
	result.erase("release_position")
	var card_vm := _hand_card_vm(str(result.get("instance_id", "")))
	if card_vm.is_empty():
		return {}
	var targeting: Dictionary = card_vm.get("targeting", {})
	var mode := str(targeting.get("mode", "automatic"))
	if mode == "automatic":
		return result
	var target: Variant = null
	if release_position is Vector2:
		target = _unit_target_at(release_position, targeting)
	if target != null:
		result["target"] = target
		return result
	return result if mode == "optional" else {}


func _show_card_target_preview(card_vm: Dictionary, origin: Vector2, pointer: Vector2, armed: bool) -> void:
	if _terminal_locked:
		target_overlay.clear_aim()
		return
	_aim_card_id = str(card_vm.get("instance_id", ""))
	_aim_origin = origin
	_aim_pointer = pointer
	_aim_armed = armed
	var targeting: Dictionary = card_vm.get("targeting", {})
	var side := str(targeting.get("side", ""))
	var rects: Array[Rect2] = []
	var picked := Rect2()
	var target_name := ""
	for unit: Dictionary in _pending.get("teams", {}).get(side, {}).get("slots", []):
		if not _unit_matches_target_filter(unit, str(targeting.get("filter", ""))):
			continue
		var slot: Variant = _slot_for_target({"kind": "unit", "side": side, "unit_id": unit.get("id"), "slot": unit.get("slot")})
		if slot == null:
			continue
		var rect: Rect2 = slot.get_global_rect()
		rects.append(rect)
		if armed and rect.has_point(pointer):
			picked = rect
			target_name = "%s · %d号位" % [slot.class_label.text, int(unit.get("slot", 0))]
	var hostile := side == "enemy"
	var message := "拖到敌方弈子 · 松手空放将退回" if hostile else "拖到我方弈子 · 松手空放将退回"
	if str(targeting.get("mode", "")) == "optional":
		message = "拖到弈子指定 · 空白处松手自动选择"
	if not armed:
		message = "向上拖出手牌区，再指定目标"
	elif picked.has_area():
		var action := "斩杀" if hostile else ("预备行动" if card_vm.get("source_skill_id") == "pieceAction" else "施放")
		message = "松手%s：%s" % [action, target_name]
	target_overlay.show_aim(origin, picked.get_center() if picked.has_area() else pointer, rects, picked, message, hostile)


func _hand_card_vm(instance_id: String) -> Dictionary:
	for card: Dictionary in _pending.get("hand", []):
		if str(card.get("instance_id", "")) == instance_id:
			return card
	return {}


func _unit_target_at(pointer_global: Vector2, targeting: Dictionary) -> Variant:
	var side := str(targeting.get("side", ""))
	var board: Node = ally_board if side == "ally" else enemy_board
	var slots: Array = _pending.get("teams", {}).get(side, {}).get("slots", [])
	for unit: Dictionary in slots:
		if not _unit_matches_target_filter(unit, str(targeting.get("filter", ""))):
			continue
		var slot_node: Variant = board.slot_for_target({
			"kind": "unit", "side": side,
			"unit_id": unit.get("id"), "slot": unit.get("slot"),
		})
		if slot_node != null and slot_node.get_global_rect().has_point(pointer_global):
			return {"side": side, "unit_id": unit["id"], "slot": int(unit["slot"])}
	return null


static func _unit_matches_target_filter(unit: Dictionary, filter_id: String) -> bool:
	if not bool(unit.get("occupied", true)) or not bool(unit.get("alive", false)):
		return false
	if filter_id == "living_non_puppet":
		return not bool(unit.get("is_puppet", false))
	if filter_id == "living_puppet_without_enchant_slot":
		return bool(unit.get("is_puppet", false)) and int(unit.get("enchantment_capacity", 0)) <= 0
	if filter_id == "lockable":
		for buff: Dictionary in unit.get("buffs", []):
			if str(buff.get("id", "")) == "stealth":
				return false
	return true


func _control_for_target(target: Dictionary) -> Control:
	var kind := str(target.get("kind", ""))
	if kind == "unit":
		return _slot_for_target(target) as Control
	if kind == "hero":
		var panel: Node = ally_heroes if target.get("side") == "ally" else enemy_heroes
		return panel.item_for_hero(target.get("hero_id")) as Control
	if kind == "side":
		return (ally_board if target.get("side") == "ally" else enemy_board) as Control
	return self


func _pulse_source(event: Dictionary, duration: float) -> void:
	# Damage emits damage_applied, unit_damaged, and sometimes unit_blocked for
	# one hit. Only the first envelope is an attack cue; the rest are feedback.
	if str(event.get("kind", "")) != "damage" or str(event.get("event_id", "")) != "damage_applied":
		return
	var source: Dictionary = event.get("source", {})
	if source.get("action_phase") != "piece_action":
		return
	var action_id := str(source.get("presentation_action_id", ""))
	if not action_id.is_empty():
		if _presented_piece_actions.has(action_id):
			return
		_presented_piece_actions[action_id] = true
	var source_slot: Variant = _slot_for_target({
		"kind": "unit", "side": source.get("side"), "unit_id": source.get("actor_id"),
	})
	if source_slot != null:
		source_slot.present_action(duration)


func _spawn_float(scene: PackedScene, event: Dictionary, duration: float) -> void:
	var node := scene.instantiate()
	feedback_layer.add_child(node)
	node.configure(event, resolve_visual_anchor(event.get("visual_target", {})))
	node.play(duration)


func _spawn_damage_float(event: Dictionary, duration: float) -> void:
	var display := event.duplicate(true)
	var payload: Dictionary = display.get("payload", {})
	# The HP delta is authoritative presentation feedback and remains zero for a
	# full block even if the damage request carried a pre-mitigation amount.
	# amount is final dealt damage; legacy envelopes fall back to the HP delta.
	if not payload.has("amount"):
		payload["amount"] = maxf(0.0, float(payload.get("old_hp", 0.0)) - float(payload.get("new_hp", 0.0)))
	display["payload"] = payload
	_spawn_float(DamageFloatScene, display, duration)


func _spawn_marker(text: String, event: Dictionary, duration: float) -> void:
	var node := CombatMarkerScene.instantiate()
	feedback_layer.add_child(node)
	node.configure_marker(text, event, resolve_visual_anchor(event.get("visual_target", {})))
	node.play(duration)


func _apply_side_buff_event(side: String, payload: Dictionary) -> void:
	if not _side_buffs.has(side): return
	var id := str(payload.get("buff_id", ""))
	var values: Array = _side_buffs[side]
	for index in range(values.size() - 1, -1, -1):
		if str(values[index].get("id", "")) == id: values.remove_at(index)
	var state: Variant = payload.get("state")
	if typeof(state) == TYPE_DICTIONARY:
		var next: Dictionary = state.duplicate(true)
		next["id"] = id
		values.append(next)
	_side_buffs[side] = values
	_refresh_side_buffs()


func _refresh_side_buffs() -> void:
	ally_side_buffs.text = _side_buff_text(_side_buffs["ally"])
	enemy_side_buffs.text = _side_buff_text(_side_buffs["enemy"])
	ally_side_buffs.tooltip_text = ally_side_buffs.text
	enemy_side_buffs.tooltip_text = enemy_side_buffs.text


static func _side_buff_text(values: Array) -> String:
	var text: Array[String] = []
	for buff: Dictionary in values:
		var item := BattlePieceSlot._buff_display_name(buff) + "×" + str(buff.get("stacks", 0))
		if int(buff.get("turns", 0)) > 0: item += "·%d回合" % int(buff["turns"])
		text.append(item)
	return "  ".join(text)


func _maybe_start_source_fx(event: Dictionary) -> void:
	var source: Dictionary = event.get("source", {})
	if source.get("action_phase") != "skill_action":
		return
	var fx_namespace := "ult" if source.get("type") == "ultimate" else "skill"
	var skill_key := str(source.get("id", ""))
	if skill_key.is_empty():
		return
	var active: Dictionary = fx_player.get_active_effect()
	if active.get("namespace") == fx_namespace and active.get("skill_key") == skill_key:
		return
	var payload: Dictionary = event.get("payload", {}).duplicate(true)
	payload["visual_target"] = event.get("visual_target", {}).duplicate(true)
	payload["skill_name"] = source.get("name", skill_key)
	fx_player.start_skill_fx(fx_namespace, skill_key, payload)


func _present_card_fx(event: Dictionary, duration: float) -> void:
	var payload: Dictionary = event.get("payload", {})
	var source_effect: Dictionary = payload.get("source_effect", {})
	var skill_key := str(source_effect.get("source_id", ""))
	if skill_key.is_empty():
		return
	var fx_namespace := "ult" if payload.get("card_category") == "ultimate" else "skill"
	var active: Dictionary = fx_player.get_active_effect()
	if active.get("namespace") == fx_namespace and active.get("skill_key") == skill_key:
		fx_player.end_skill_fx(fx_namespace, skill_key, payload)
		return
	var fx_payload := payload.duplicate(true)
	fx_payload["visual_target"] = event.get("visual_target", {}).duplicate(true)
	fx_player.start_skill_fx(fx_namespace, skill_key, fx_payload)
	if fx_namespace == "ult" and skill_key == "shadow" and is_inside_tree():
		var tween := create_tween()
		_fx_end_tweens.append(tween)
		tween.tween_interval(maxf(0.05, duration * 0.55))
		tween.tween_callback(func() -> void:
			fx_player.end_skill_fx(fx_namespace, skill_key, fx_payload)
		)
