class_name BattleResultOverlay
extends ColorRect

signal restart_requested

@onready var title_label: Label = %TitleLabel
@onready var detail_label: Label = %DetailLabel
@onready var icon_label: Label = %IconLabel
@onready var restart_button: Button = %RestartButton

var run_mode := false

func set_run_mode(enabled: bool) -> void:
	run_mode = enabled
	if is_node_ready():
		restart_button.text = "继续旅程" if enabled else "再战一局"


func _ready() -> void:
	restart_button.pressed.connect(func() -> void: restart_requested.emit())


func bind_result(result: Variant) -> void:
	var won: bool = result == "win"
	title_label.text = "战斗胜利" if won else "战斗失败"
	detail_label.text = "敌方阵线已瓦解。" if won else "我方阵线已失守。"
	if run_mode:
		detail_label.text = "收取战利品，继续前行。" if won else "此局止步于此。每一次落子，都是下一局的伏笔。"
		restart_button.text = "领取战利品" if won else "查看本局结果"
	icon_label.text = "胜" if won else "败"
	visible = result in ["win", "lose"]
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
