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


func _ready() -> void:
	relic_strip = RelicStripScene.instantiate()
	relic_strip.name = "Relics"
	add_child(relic_strip)
	relic_strip.anchor_right = 1.0
	relic_strip.offset_left = 32.0
	relic_strip.offset_right = -32.0
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
	sp_label.text = str(snappedf(sp, 0.1)).trim_suffix(".0")
	sp_detail.text = "技能点 · %s / %s" % [
		str(snappedf(sp, 0.1)).trim_suffix(".0"), str(snappedf(sp_max, 0.1)).trim_suffix(".0"),
	]
	sp_orb.bind_resources(sp, sp_max)
	sp_bar.max_value = sp_max
	sp_bar.value = clampf(sp, 0.0, sp_max)
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
