class_name BattleHud
extends Control

const RelicStripScene = preload("res://scenes/battle/relic_strip.tscn")
var relic_strip: Control

signal end_turn_requested
signal speed_requested(speed: float)
signal auto_battle_requested(enabled: bool)
signal combat_log_toggle_requested

@onready var round_label: Label = %RoundLabel
@onready var phase_label: Label = %PhaseLabel
@onready var sp_label: Label = %SpLabel
@onready var sp_bar: ProgressBar = %SpBar
@onready var sp_orb: Control = %SpOrb
@onready var sp_detail: Label = %SpDetail
@onready var relic_trigger_notice: Label = %RelicTriggerNotice
@onready var sp_drain_notice: Label = %SpDrainNotice
@onready var pile_count_draw: Label = %DrawCount
@onready var hand_count: Label = %HandCount
@onready var discard_count: Label = %DiscardCount
@onready var exhaust_count: Label = %ExhaustCount
@onready var auto_toggle: CheckButton = %AutoToggle
@onready var log_button: Button = %LogButton
@onready var log_unread_badge: Label = %LogUnreadBadge
@onready var end_turn_button: Button = %EndTurnButton
@onready var speed_buttons: Array[Button] = [%Speed1, %Speed2, %Speed3, %Speed4]

var _input_locked := false
var _queue_busy := false
var _binding := false
var _pending: Dictionary = {}
var _log_open := false
var _log_unread := 0
var _relic_notice_tween: Tween
var _sp_notice_tween: Tween


func _ready() -> void:
	relic_strip = RelicStripScene.instantiate()
	relic_strip.name = "Relics"
	add_child(relic_strip)
	relic_strip.anchor_right = 1.0
	relic_strip.offset_left = 32.0
	relic_strip.offset_right = -285.0
	relic_strip.offset_top = 59.0
	relic_strip.offset_bottom = 98.0
	end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	for index in speed_buttons.size():
		var speed := float(index + 1)
		speed_buttons[index].pressed.connect(func() -> void: speed_requested.emit(speed))
	auto_toggle.toggled.connect(func(enabled: bool) -> void:
		if not _binding:
			auto_battle_requested.emit(enabled)
	)
	log_button.pressed.connect(func() -> void:
		if not _binding:
			combat_log_toggle_requested.emit()
	)
	if not _pending.is_empty():
		_apply(_pending)
	_apply_log_state()
	_apply_lock()


func bind_view_model(vm: Dictionary) -> void:
	_pending = vm.duplicate(true)
	if is_node_ready():
		_apply(_pending)


func present_relic_trigger(relic_id: String, duration: float) -> void:
	var relic_name: String = relic_strip.present_trigger(relic_id, duration)
	if relic_name.is_empty(): return
	if _relic_notice_tween != null and _relic_notice_tween.is_valid(): _relic_notice_tween.kill()
	relic_trigger_notice.text = "%s · 已触发" % relic_name
	relic_trigger_notice.visible = true
	relic_trigger_notice.modulate.a = 1.0
	_relic_notice_tween = create_tween()
	_relic_notice_tween.tween_interval(maxf(0.25, duration))
	_relic_notice_tween.tween_property(relic_trigger_notice, "modulate:a", 0.0, maxf(0.25, duration * 0.6))
	_relic_notice_tween.tween_callback(func() -> void: relic_trigger_notice.visible = false)


func present_sp_change(new_sp: float, duration: float, drain_amount: float = 0.0) -> void:
	var sp_max := float(_pending.get("resources", {}).get("sp_max", sp_bar.max_value))
	_set_sp_display(new_sp, sp_max)
	if drain_amount <= 0.0: return
	if _sp_notice_tween != null and _sp_notice_tween.is_valid(): _sp_notice_tween.kill()
	sp_drain_notice.text = "吞噬 −%s SP" % str(snappedf(drain_amount, 0.1)).trim_suffix(".0")
	sp_drain_notice.visible = true
	sp_drain_notice.modulate.a = 1.0
	sp_orb.modulate = Color(1.35, 0.65, 1.6)
	_sp_notice_tween = create_tween()
	_sp_notice_tween.tween_interval(maxf(0.18, duration * 0.5))
	_sp_notice_tween.tween_property(sp_orb, "modulate", Color.WHITE, maxf(0.2, duration))
	_sp_notice_tween.parallel().tween_property(sp_drain_notice, "modulate:a", 0.0, maxf(0.3, duration))
	_sp_notice_tween.tween_callback(func() -> void: sp_drain_notice.visible = false)


func reset_trigger_feedback() -> void:
	for tween in [_relic_notice_tween, _sp_notice_tween]:
		if tween != null and tween.is_valid(): tween.kill()
	relic_trigger_notice.visible = false
	sp_drain_notice.visible = false
	sp_orb.modulate = Color.WHITE
	relic_strip.reset_triggers()


func _set_sp_display(sp: float, sp_max: float) -> void:
	sp_label.text = str(snappedf(sp, 0.1)).trim_suffix(".0")
	sp_detail.text = "技能点 · %s / %s" % [str(snappedf(sp, 0.1)).trim_suffix(".0"), str(snappedf(sp_max, 0.1)).trim_suffix(".0")]
	sp_orb.bind_resources(sp, sp_max)
	sp_bar.max_value = sp_max
	sp_bar.value = clampf(sp, 0.0, sp_max)


func set_input_locked(locked: bool) -> void:
	_input_locked = locked
	if is_node_ready():
		_apply_lock()


func set_queue_busy(busy: bool) -> void:
	_queue_busy = busy
	if is_node_ready():
		_apply_lock()


func set_speed_display(speed: float) -> void:
	if not is_node_ready():
		return
	for index in speed_buttons.size():
		speed_buttons[index].button_pressed = is_equal_approx(speed, float(index + 1))


func set_log_state(open: bool, unread: int) -> void:
	_log_open = open
	_log_unread = clampi(unread, 0, 100)
	if is_node_ready():
		_apply_log_state()


func is_input_locked() -> bool:
	return _input_locked


func _apply(vm: Dictionary) -> void:
	relic_strip.bind_relics(vm.get("relics", []))
	var battle: Dictionary = vm.get("battle", {})
	var resources: Dictionary = vm.get("resources", {})
	var piles: Dictionary = vm.get("piles", {})
	var presentation: Dictionary = vm.get("presentation", {})
	var sp := float(resources.get("sp", 0.0))
	var sp_max := maxf(0.0, float(resources.get("sp_max", 0.0)))
	round_label.text = "回合 %s" % str(battle.get("round", "—"))
	phase_label.text = "我方行动" if str(battle.get("phase", "")) == "player_input" else "战斗演算"
	if bool(battle.get("game_over", false)):
		phase_label.text = "战斗结束"
	_set_sp_display(sp, sp_max)
	pile_count_draw.text = str(int(piles.get("draw", 0)))
	hand_count.text = str(int(piles.get("hand", 0)))
	discard_count.text = str(int(piles.get("discard", 0)))
	exhaust_count.text = str(int(piles.get("exhaust", 0)))
	var speed := float(presentation.get("speed", 1.0))
	_binding = true
	auto_toggle.button_pressed = bool(presentation.get("auto_battle", false))
	_binding = false
	for index in speed_buttons.size():
		speed_buttons[index].button_pressed = is_equal_approx(speed, float(index + 1))


func _apply_log_state() -> void:
	_binding = true
	log_button.button_pressed = _log_open
	_binding = false
	log_unread_badge.visible = not _log_open and _log_unread > 0
	log_unread_badge.text = "99+" if _log_unread >= 100 else str(_log_unread)


func _apply_lock() -> void:
	end_turn_button.disabled = _input_locked or _queue_busy
	auto_toggle.disabled = _input_locked or _queue_busy
	for button: Button in speed_buttons:
		button.disabled = _input_locked
