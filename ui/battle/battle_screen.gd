class_name BattleScreen
extends Control

const DamageFloatScene = preload("res://scenes/effects/damage_float.tscn")
const HealFloatScene = preload("res://scenes/effects/heal_float.tscn")
const CombatMarkerScene = preload("res://scenes/effects/combat_marker.tscn")
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

var _pending: Dictionary = {}
var _input_locked := false
var _terminal_locked := false
var _queue_busy := false
var _fx_end_tweens: Array[Tween] = []
var _combat_log_open := false
var _unread_log_count := 0
var _last_log_count := 0
var _log_tween: Tween


func _ready() -> void:
	battle_hud.end_turn_requested.connect(func() -> void: end_turn_requested.emit())
	battle_hud.speed_requested.connect(func(speed: float) -> void: speed_requested.emit(speed))
	battle_hud.auto_battle_requested.connect(
		func(enabled: bool) -> void: auto_battle_requested.emit(enabled)
	)
	battle_hud.combat_log_toggle_requested.connect(toggle_combat_log)
	result_overlay.restart_requested.connect(func() -> void: restart_requested.emit())
	fatal_overlay.restart_requested.connect(func() -> void: restart_requested.emit())
	hand_view.play_card_requested.connect(func(command: Dictionary) -> void:
		play_card_requested.emit(command)
	)
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


func set_presentation_speed(speed: float) -> void:
	battle_hud.set_speed_display(speed)


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
	if kind == "damage" and event_id == "damage_applied":
		if target_slot != null:
			target_slot.present_hp_change(
				float(payload.get("old_hp", target_slot.hp_bar.value)),
				float(payload.get("new_hp", target_slot.hp_bar.value)),
				float(payload.get("target", {}).get("max_hp", target_slot.hp_bar.max_value)),
				duration,
			)
			target_slot.present_pulse(duration, Color(1.25, 0.62, 0.58, 1.0))
		_spawn_float(DamageFloatScene, event, duration)
		if bool(payload.get("crit", false)):
			_spawn_marker("暴击", event, duration)
	elif kind == "damage" and event_id == "unit_blocked":
		_spawn_marker("格挡", event, duration)
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
		target_slot.present_pulse(duration, Color(0.72, 0.68, 1.3, 1.0))
	elif kind == "card":
		hand_view.present_card_event(event, duration)
		_present_card_fx(event, duration)
	elif kind == "fatal":
		fatal_overlay.bind_fatal(payload)
		_terminal_locked = true
		_apply_interaction_lock()


func finish_event(_event: Dictionary) -> void:
	pass


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
		_queue_busy,
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
	var source: Dictionary = event.get("source", {})
	if source.get("action_phase") != "piece_action":
		return
	var source_slot: Variant = _slot_for_target({
		"kind": "unit", "side": source.get("side"), "unit_id": source.get("actor_id"),
	})
	if source_slot != null:
		source_slot.present_action(duration)
		source_slot.present_pulse(duration, Color(1.2, 1.05, 0.55, 1.0))


func _spawn_float(scene: PackedScene, event: Dictionary, duration: float) -> void:
	var node := scene.instantiate()
	feedback_layer.add_child(node)
	node.configure(event, resolve_visual_anchor(event.get("visual_target", {})))
	node.play(duration)


func _spawn_marker(text: String, event: Dictionary, duration: float) -> void:
	var node := CombatMarkerScene.instantiate()
	feedback_layer.add_child(node)
	node.configure_marker(text, event, resolve_visual_anchor(event.get("visual_target", {})))
	node.play(duration)


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
