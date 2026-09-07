class_name BattleFatalOverlay
extends ColorRect

signal restart_requested

@onready var message_label: Label = %MessageLabel
@onready var code_label: Label = %CodeLabel
@onready var restart_button: Button = %RestartButton


func _ready() -> void:
	restart_button.pressed.connect(func() -> void: restart_requested.emit())


func bind_fatal(fatal: Variant) -> void:
	visible = typeof(fatal) == TYPE_DICTIONARY
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	if not visible:
		return
	code_label.text = str(fatal.get("code", "fatal"))
	message_label.text = str(fatal.get("message", "战斗发生不可恢复错误。"))
