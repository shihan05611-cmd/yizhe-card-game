class_name BattleResultOverlay
extends ColorRect

signal restart_requested

@onready var title_label: Label = %TitleLabel
@onready var detail_label: Label = %DetailLabel
@onready var icon_label: Label = %IconLabel
@onready var restart_button: Button = %RestartButton


func _ready() -> void:
	restart_button.pressed.connect(func() -> void: restart_requested.emit())


func bind_result(result: Variant) -> void:
	var won: bool = result == "win"
	title_label.text = "战斗胜利" if won else "战斗失败"
	detail_label.text = "敌方阵线已瓦解。" if won else "我方阵线已失守。"
	icon_label.text = "胜" if won else "败"
	visible = result in ["win", "lose"]
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
