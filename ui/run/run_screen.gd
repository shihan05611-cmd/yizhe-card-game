extends Control

const SessionScript = preload("res://app/run_session.gd")
const BattleScene = preload("res://scenes/main.tscn")
const GeometryScript = preload("res://ui/art/geometry_piece.gd")
const MapScript = preload("res://ui/run/run_map.gd")
const FormationSlotScript = preload("res://ui/run/formation_slot.gd")
const FormationPieceTokenScript = preload("res://ui/run/formation_piece_token.gd")
const RelicItemScene: PackedScene = preload("res://scenes/battle/relic_item.tscn")
const HeroCardCatalogScript = preload("res://data/catalogs/hero_card_catalog.gd")
const CREAM := Color("e8e3cd")
const MUTED := Color("a9b7a0")
const GOLD := Color("c6ad72")
const CHAPTERS := ["", "铁壁关", "烬原", "问心局"]
const HERO_ROLES := {1:"灼烧与烈焰",2:"命运与变化",3:"反击与号令",4:"守护与格挡",5:"附魔与成长",6:"拳势与连击",7:"破势与集火",8:"傀儡与殉道",9:"潜行与点杀"}
const HERO_PORTRAITS := {
	1: "res://assets/portraits/chiyan_lihui_transparent_v2.png", 3: "res://assets/portraits/yuanshuai_lihui.png",
	4: "res://assets/portraits/qishi_lihui_transparent.png", 5: "res://assets/portraits/yanshushi_lihui_transparent_v2.png",
	6: "res://assets/portraits/ningbufan_lihui_transparent_v2.png", 7: "res://assets/portraits/chenge_lihui_transparent.png",
	8: "res://assets/portraits/qianji_lihui.png", 9: "res://assets/portraits/yingshou_lihui_transparent_v2.png",
}

@export var save_path := "user://run-save.json"
var session: Variant
var battle: Variant = null
var _surface: Control
var _page: VBoxContainer
var _message: Label
var _home := true
var _vm := {}
var _pause: Control
var _feedback := ""
var _confirm: ConfirmationDialog
var _confirmation_action: Callable
var _resume_auto := false
var _formation_expanded := false
var _formation_layer: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _theme()
	session = SessionScript.new({}, save_path)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "重新落子"
	_confirm.ok_button_text = "确认"
	_confirm.cancel_button_text = "取消"
	_confirm.confirmed.connect(func() -> void:
		if _confirmation_action.is_valid(): _confirmation_action.call()
	)
	add_child(_confirm)
	_render()

func _theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", CREAM)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := _box(Color("2e4638"), Color("53634d"), 7, 14)
		if state_name == "hover": box.bg_color = Color("415a46")
		if state_name == "pressed": box.bg_color = Color("526449")
		if state_name == "disabled": box.bg_color = Color("25382e")
		if state_name == "focus":
			box.bg_color = Color.TRANSPARENT
			box.border_color = GOLD
			box.set_border_width_all(2)
		result.set_stylebox(state_name, "Button", box)
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("7c8976"))
	result.set_stylebox("panel", "PanelContainer", _box(Color("263b30"), Color("53614a"), 10, 20))
	result.set_stylebox("normal", "LineEdit", _box(Color("203128"), Color("647258"), 6, 12))
	result.set_color("font_color", "LineEdit", CREAM)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	return result

func _box(color: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.border_color = border
	b.set_corner_radius_all(radius)
	b.set_border_width_all(1)
	b.content_margin_left = margin
	b.content_margin_right = margin
	b.content_margin_top = margin
	b.content_margin_bottom = margin
	return b

func _label(parent: Node, value: String, font_size: int = 16, color: Color = CREAM, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 44
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	if primary:
		button.add_theme_stylebox_override("normal", _box(Color("c8bd93"), Color("e2d4a6"), 7, 14))
		button.add_theme_color_override("font_color", Color("20382d"))
	parent.add_child(button)
	return button

func _vbox(parent: Node, gap: int = 14) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func _hbox(parent: Node, gap: int = 16) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func _spacer(parent: Node, vertical: bool = true) -> Control:
	var spacer := Control.new()
	if vertical: spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else: spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)
	return spacer

func _panel(parent: Node, expand: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	if expand: panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	return _vbox(panel)

func _render() -> void:
	if is_instance_valid(_surface):
		remove_child(_surface)
		_surface.queue_free()
	_surface = ColorRect.new()
	_surface.color = Color("182b22")
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_surface)
	move_child(_confirm, get_child_count()-1)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_"+edge, 26 if edge in ["left","right"] else 18)
	_surface.add_child(margin)
	_page = _vbox(margin, 16)
	_vm = session.view_model()
	if not _vm.get("save_warning", {}).is_empty():
		_feedback = "自动保存未成功，请保留窗口并重试：" + str(_vm.save_warning.get("message",""))
	var top := _hbox(_page)
	_label(top, "弈 者", 26, CREAM)
	_label(top, "几何棋阵 · 卡牌远行", 13, MUTED)
	_spacer(top, false)
	if not _home:
		var state: Dictionary = _vm.get("run", {})
		_label(top, "第 %d 章  /  %s" % [int(state.get("chapter",1)), CHAPTERS[int(state.get("chapter",1))]], 14, GOLD)
		_button(top, "返回标题", func() -> void: _home = true; _render())
	if not _vm.get("save_warning", {}).is_empty():
		_button(top,"重试保存",func() -> void:
			var errors: Array[String] = []
			if session.save_checkpoint(errors): _feedback = "检查点已保存。"
			_render()
		)
	_page.add_child(HSeparator.new())
	if _home:
		_render_home()
	else:
		_render_run()
	_message = _label(_page, _feedback, 13, Color("edba8c"), true)
	var foot := _hbox(_page)
	_label(foot, "弈子代你赴战，落牌决定局势。", 12, MUTED)
	_spacer(foot, false)
	_label(foot, "节点间自动保存  ·  战斗中 Esc 暂停", 12, MUTED)

func _render_home() -> void:
	var row := _hbox(_page, 40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var intro := _vbox(row, 20)
	intro.custom_minimum_size.x = 365
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spacer(intro)
	_label(intro, "一局未尽，山河又新。", 14, GOLD)
	_label(intro, "以牌为令\n以石为兵", 52, CREAM)
	_label(intro, "选择弈者，穿过三章棋路。\n在每次交锋中积累能量，以大招扭转局势；\n在旅途中招募同伴，让遗物与成长改变下一局。", 16, MUTED, true)
	var actions := _hbox(intro)
	_button(actions, "开始新的旅程", _request_new_run, true)
	var can_resume: bool = bool(_vm.get("can_continue", false)) or bool(_vm.get("active", false))
	var resume := _button(actions, "继续旅程", continue_run)
	resume.disabled = not can_resume
	_button(intro, "玩法提示", func() -> void:
		_feedback = "拖动卡牌至棋盘出牌；SP 足够即可连续出牌。结束回合后棋子自动交锋。能量满时获得大招卡；每回合弃掉余牌，再抽 2+上阵弈者数。"
		_render()
	)
	_spacer(intro)
	var gallery := _panel(row, true)
	_label(gallery, "四象成阵", 14, GOLD)
	_spacer(gallery)
	var figures := _hbox(gallery, 8)
	figures.custom_minimum_size.y = 230
	for i in 4:
		var col := _vbox(figures, 16)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var art := GeometryScript.new()
		art.kind = ["shield","crossbow","assassin","banner"][i]
		art.custom_minimum_size = Vector2(76,195)
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(art)
		var caption := _label(col, ["甲 卒","机 弩","刺 客","旗 兵"][i], 14, CREAM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spacer(gallery)
	_label(gallery, "守阵  /  远击  /  点杀  /  号令", 13, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(gallery, "三章棋路 · 六格阵线 · 每一局重新生长", 12, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _request_new_run() -> void:
	if bool(_vm.get("can_continue", false)) or bool(_vm.get("active", false)):
		_ask("新旅程将替换当前存档，确定重新开始？", func() -> void: start_new_run())
	else: start_new_run()

func start_new_run(seed_value: Variant = null) -> bool:
	var errors: Array[String] = []
	var seed_input: Variant = seed_value if seed_value != null else "%s-%s" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var success: bool = session.new_run(seed_input, errors)
	if success:
		_home = false
		_feedback = ""
	else: _feedback = "无法开始旅程：" + "; ".join(errors)
	_render()
	return success

func continue_run() -> void:
	var errors: Array[String] = []
	if not bool(session.snapshot().get("active", false)):
		if not session.continue_run(errors):
			_feedback = "存档暂时无法读取，原文件已保留。" + "; ".join(errors)
			_render()
			return
	_home = false
	_feedback = ""
	_render()

func _render_run() -> void:
	var state: Dictionary = _vm.get("run", {})
	var row := _hbox(_page, 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sidebar := _panel(row)
	sidebar.get_parent().custom_minimum_size.x = 270
	_sidebar(sidebar, state)
	var body := _vbox(row, 15)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status := str(state.get("status", "idle"))
	match status:
		"heroSelect": _hero_choices(body, state)
		"map": _map_page(body, state)
		"reward", "recruit": _reward_page(body, state)
		"shop", "forge": _shop_page(body, state)
		"event":
			_label(body, "奇遇 · 路旁拾遗", 28)
			_label(body, "苔痕间有旧行旅留下的钱囊。\n你收拢散落的铜钱，将它们带上下一段路。", 18, MUTED, true)
			_label(body, "已获得 %d 铜钱" % (10+int(state.chapter)*2), 22, GOLD)
			_button(body, "继续前行", func() -> void: command({"type":"leave_node"}), true)
		"cleared", "failed":
			_label(body, "三关已过，落子无悔。" if status == "cleared" else "此局止步，棋心未改。", 32)
			_label(body, "旅途终章" if status == "cleared" else "败于第 %d 章 · %s" % [int(state.chapter), CHAPTERS[int(state.chapter)]], 18, GOLD)
			_label(body, "%d 位同行弈者 · %d 件遗物 · %d 张自由技 · %d 张额外专属" % [state.hero_deployment_slots.size(),state.relic_ids.size(),state.free_skill_ids.size(),state.get("exclusive_card_ids", []).size()], 17, MUTED, true)
			_button(body, "再启一程", _request_new_run, true)
		_:
			_label(body, "旅程尚未开始", 28)
			_button(body, "选择弈者", _request_new_run, true)

func _sidebar(parent: Node, state: Dictionary) -> void:
	_label(parent, "行囊与棋阵", 18, GOLD)
	_label(parent, "%d  铜钱" % int(state.get("currency",0)), 27)
	var survivors := 0
	for slot: Dictionary in state.get("piece_slots", []):
		if slot.get("piece_class_id") != null and float(slot.get("hp_ratio",1.0)) > 0.0: survivors += 1
	_label(parent, "存活棋子  %d / 4" % survivors, 14, MUTED)
	var health := _hbox(parent,5)
	for slot: Dictionary in state.get("piece_slots", []):
		if slot.get("piece_class_id") == null:
			continue
		var meter := ProgressBar.new()
		meter.custom_minimum_size = Vector2(25,7)
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter.show_percentage = false
		meter.value = float(slot.get("hp_ratio",1.0))*100.0
		meter.tooltip_text = "槽位 %d：%d%% 生命" % [int(slot.slot),roundi(meter.value)]
		meter.add_theme_stylebox_override("background",_box(Color("172b21"),Color.TRANSPARENT,2,0))
		meter.add_theme_stylebox_override("fill",_box(Color("8fad8d"),Color.TRANSPARENT,2,0))
		health.add_child(meter)
	if state.get("status") == "map":
		_button(parent, "调整阵容", func() -> void: _show_formation_dialog(state))
	var owned: Dictionary = state.get("hero_deployment_slots", {})
	for id: String in owned:
		var hero := _hero(int(id))
		var line := _hbox(parent, 8)
		_label(line, str(hero.get("name","弈者")), 16)
		_spacer(line, false)
		if state.get("status") == "map":
			var positions := OptionButton.new()
			positions.custom_minimum_size.y = 44
			line.add_child(positions)
			for slot in range(1,7):
				positions.add_item("槽 %d" % slot, slot)
				positions.set_item_disabled(slot-1, slot in owned.values() and slot != int(owned[id]))
			positions.select(int(owned[id])-1)
			positions.item_selected.connect(func(index: int) -> void: command({"type":"set_hero_deployment_slot","hero_id":int(id),"slot":index+1}))
		else:
			_label(line, "槽 %d" % int(owned[id]), 14, MUTED)
	_label(parent, "%d 件遗物 · %d 张自由技 · %d 张额外专属" % [state.get("relic_ids",[]).size(),state.get("free_skill_ids",[]).size(),state.get("exclusive_card_ids", []).size()], 13, MUTED)
	if not state.get("relic_ids", []).is_empty():
		var relics := HBoxContainer.new()
		relics.add_theme_constant_override("separation", 5)
		parent.add_child(relics)
		for relic_id: String in state.relic_ids:
			_add_relic_icon(relics, relic_id)
	var inventory := _button(parent, "查看牌库与遗物", _show_inventory)
	inventory.disabled = owned.is_empty()
	_spacer(parent)
	_label(parent, "前排 1—3 / 后排 4—6\n地图上可调整弈者与棋子阵位。", 12, MUTED, true)


func _formation_board(parent: Node, state: Dictionary) -> void:
	var editable: bool = state.get("status") == "map"
	var classes: Dictionary = _vm.get("catalog", {}).get("piece_classes", {})
	var columns := _hbox(parent, 26)
	var arrangement := _vbox(columns, 8)
	_label(arrangement, "后排                 前排 →", 13, MUTED)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	arrangement.add_child(grid)
	var entry_by_slot := {}
	for entry: Dictionary in state.get("piece_slots", []):
		entry_by_slot[int(entry["slot"])] = entry
	# This is the same left-team formation geometry used by the battle board:
	# each row is [back, front], so the front column sits toward the centre.
	for visual_slot: int in [4, 1, 5, 2, 6, 3]:
		var entry: Dictionary = entry_by_slot[visual_slot]
		var tile: Variant = FormationSlotScript.new()
		tile.custom_minimum_size = Vector2(104, 108)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
		var class_view: Dictionary = classes.get(entry.get("piece_class_id"), {})
		tile.configure(entry, class_view, "后排" if visual_slot > 3 else "前排")
		if editable:
			tile.slot_dropped.connect(func(target_slot: int, payload: Dictionary) -> void:
				if payload.get("kind") == "run_formation_slot":
					_apply_formation_command({"type": "swap_piece_slots", "first_slot": int(payload["slot"]), "second_slot": target_slot})
				elif payload.get("kind") == "run_piece_class":
					_apply_formation_command({"type": "set_piece_class", "slot": target_slot, "piece_class_id": payload["piece_class_id"]})
			)
		grid.add_child(tile)
	if not editable:
		return
	var inventory := _vbox(columns, 14)
	inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(inventory, "备用兵种", 17, GOLD)
	_label(inventory, "每种最多两名。拖到已部署弟子上，替换其兵种。", 14, MUTED, true)
	var stock := _vbox(inventory, 10)
	for class_id: String in ["shield", "assassin", "crossbow", "banner"]:
		var used := 0
		for entry: Dictionary in state.get("piece_slots", []):
			if entry.get("piece_class_id") == class_id:
				used += 1
		var token: Variant = FormationPieceTokenScript.new()
		token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		token.custom_minimum_size.y = 42
		token.configure(class_id, classes.get(class_id, {}), max(0, 2 - used))
		stock.add_child(token)
	_label(inventory, "拖动左侧弟子可以互换位置，也可以移到空位。", 14, MUTED, true)


func _show_formation_dialog(state: Dictionary) -> void:
	_close_formation_dialog()
	_formation_layer = Control.new()
	_formation_layer.name = "FormationEditor"
	add_child(_formation_layer)
	_formation_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_formation_layer.z_index = 20
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.035, 0.78)
	_formation_layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	_formation_layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -272
	panel.offset_bottom = 272
	panel.add_theme_stylebox_override("panel", _box(Color("21382b"), Color("53634d"), 8, 24))
	var body := _vbox(panel, 16)
	var heading := _hbox(body)
	_label(heading, "调整阵容", 24)
	_spacer(heading, false)
	_button(heading, "完成", _close_formation_dialog)
	_formation_board(body, state)
	_label(body, "调整即时保存 · 不增加弟子人数 · 换兵种保留生命比例", 12, MUTED)

func _close_formation_dialog() -> void:
	if is_instance_valid(_formation_layer):
		remove_child(_formation_layer)
		_formation_layer.queue_free()
	_formation_layer = null

func _apply_formation_command(payload: Dictionary) -> void:
	command(payload)
	call_deferred("_show_formation_dialog", session.snapshot())

func _hero(id: int) -> Dictionary:
	for hero: Dictionary in _vm.get("catalog",{}).get("heroes",[]):
		if int(hero.id) == id: return hero
	return {"id":id,"name":"弈者","exclusive_skill_id":""}

func _hero_choices(parent: Node, state: Dictionary) -> void:
	_label(parent, "选择同行的第一位弈者", 28)
	_label(parent, "专属技构成牌库的起点，旅途中还会遇到新的同伴。", 14, MUTED, true)
	_hero_choice_grid(parent, state.initial_hero_choice_ids, func(id: int) -> void:
		command({"type":"choose_starting_hero","hero_id":id})
	)


func _hero_choice_grid(parent: Node, hero_ids: Array, choose: Callable) -> void:
	var choices := GridContainer.new()
	choices.columns = 3
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("h_separation", 14)
	choices.add_theme_constant_override("v_separation", 14)
	parent.add_child(choices)
	for raw_id: Variant in hero_ids:
		var id := int(raw_id)
		var hero := _hero(id)
		var panel := _panel(choices, true)
		panel.add_theme_constant_override("separation", 8)
		panel.get_parent().custom_minimum_size = Vector2(0, 370)
		panel.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
		_add_hero_portrait(panel, hero)
		var name := _label(panel, str(hero.name), 22)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var role := _label(panel, HERO_ROLES.get(id, "变化与机锋"), 14, GOLD)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var passive := bool(hero.get("is_passive", false))
		_label(panel, "%s：%s" % ["被动专属" if passive else "专属技卡", hero.get("exclusive_name", "")], 14, CREAM, true)
		var description := _label(panel, str(hero.get("exclusive_description", "")), 13, MUTED, true)
		description.max_lines_visible = 2
		description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_spacer(panel)
		var detail := _button(panel, "技能详解", func() -> void: _show_text(str(hero.name), str(hero.get("exclusive_description", ""))))
		detail.custom_minimum_size.y = 32
		_button(panel, "选择弈者", func() -> void: choose.call(id), true)


func _add_hero_portrait(parent: Node, hero: Dictionary) -> void:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, 160)
	frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(frame)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var path := str(HERO_PORTRAITS.get(int(hero.get("id", 0)), ""))
	if not path.is_empty() and ResourceLoader.exists(path, "Texture2D"):
		portrait.texture = load(path) as Texture2D
	else:
		portrait.tooltip_text = str(hero.get("name", "弈者"))
	frame.add_child(portrait)


func _add_relic_icon(parent: Node, relic_id: String) -> void:
	var relic: Dictionary = _vm.get("catalog", {}).get("relics", {}).get(relic_id, {})
	var item: Control = RelicItemScene.instantiate()
	item.tooltip_text = "%s\n%s" % [relic.get("name", relic_id), relic.get("description", "")]
	parent.add_child(item)
	item.get_node("Icon").bind_relic({"id": relic_id})


func _add_relic_info(parent: Node, relic_id: String) -> void:
	var relic: Dictionary = _vm.get("catalog", {}).get("relics", {}).get(relic_id, {})
	var row := _hbox(parent, 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_relic_icon(row, relic_id)
	var text := _vbox(row, 3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(text, str(relic.get("name", relic_id)), 17, GOLD)
	_label(text, str(relic.get("description", "")), 13, MUTED, true)

func _map_page(parent: Node, state: Dictionary) -> void:
	_label(parent, "%s · 择路而行" % CHAPTERS[int(state.chapter)], 28)
	_label(parent, "亮起的节点可以前往。每次只走一步，十步之后迎战关主。", 14, MUTED, true)
	var route := MapScript.new()
	route.size_flags_vertical = Control.SIZE_EXPAND_FILL
	route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(route)
	route.bind_nodes(state.map_nodes)
	route.node_selected.connect(func(id: String) -> void: command({"type":"choose_node","node_id":id}))
	_label(parent, "弈 交锋    锋 强敌    商 商旅    锻 锻坊    遇 奇遇    关 关主", 13, GOLD)
	_label(parent, "提示：锻坊首次恢复免费，可让阵亡棋子重新归阵。", 13, MUTED)

func _reward_page(parent: Node, state: Dictionary) -> void:
	var options: Array = state.get("reward_options",[])
	var recruiting: bool = not options.is_empty() and options[0].type == "hero"
	_label(parent, "新的同行者" if recruiting else "战利品 · 选择一项", 28)
	_label(parent, "上阵新弈者会增加每回合抽牌，并带来新的专属技。" if recruiting else "奖励只能领取一次。选定后继续旅程。", 14, MUTED, true)
	if recruiting:
		_hero_choice_grid(parent, options.map(func(option: Dictionary) -> int: return int(option["payload_id"])), func(id: int) -> void:
			command({"type": "recruit_hero", "hero_id": id})
		)
	else:
		_options(parent, options, "select_reward")

func _options(parent: Node, options: Array, action: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := _vbox(scroll, 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option: Dictionary in options:
		var box := _panel(list, true)
		var heading := _hbox(box)
		var relic_option := str(option.get("type", "")) in ["relic", "shopRelic", "forgeRelic"]
		var exclusive_option := str(option.get("type", "")) in ["exclusiveCard", "shopExclusiveCard"]
		if relic_option:
			_add_relic_icon(heading, str(option.get("payload_id", "")))
		_label(heading, str(option.get("name","选项")), 20)
		_spacer(heading,false)
		var purchased := bool(option.get("purchased",false))
		var cost: Variant = _vm.get("costs",{}).get(option.id,0)
		var buying := action in ["buy_shop_option","buy_forge_option"]
		var caption := "已购" if purchased else ("%d 铜钱" % int(cost) if buying else "选择")
		var payload := {"type":action,"option_id":option.id}
		if action == "recruit_hero": payload = {"type":action,"hero_id":int(option.payload_id)}
		var button := _button(heading,caption,func() -> void: command(payload),not buying)
		button.disabled = purchased or (buying and int(cost) > int(_vm.run.currency))
		if action == "recruit_hero":
			var hero := _hero(int(option.payload_id))
			_label(box,"%s · %s" % [HERO_ROLES.get(int(option.payload_id),"变化与机锋"),hero.get("exclusive_name","")],15,GOLD,true)
			_label(box,str(hero.get("exclusive_description",option.get("description",""))),14,MUTED,true)
		elif exclusive_option:
			var card_id := str(option.get("payload_id", ""))
			var exclusive_view := _exclusive_card_view(card_id)
			var hero := _hero(int(exclusive_view.get("owner_hero_id", 0)))
			_label(box, "%s · 专属副本 · %d SP" % [
				str(hero.get("name", "上阵弈者")), int(exclusive_view.get("base_sp_cost", 0)),
			], 15, GOLD, true)
			_label(box, str(option.get("description", "")), 14, MUTED, true)
		elif relic_option:
			var relic_description := _label(box, str(option.get("description", "")), 14, MUTED, true)
			relic_description.max_lines_visible = 2
			relic_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else:
			_label(box,str(option.get("description","")),14,MUTED,true)

func _shop_page(parent: Node, state: Dictionary) -> void:
	var forge: bool = state.status == "forge"
	var top := _hbox(parent)
	_label(top,"锻坊 · 修整棋阵" if forge else "商旅 · 添置行囊",28)
	_spacer(top,false)
	_button(top,"离开",func() -> void: command({"type":"leave_node"}))
	if forge:
		var can_heal: bool = _vm.get("costs",{}).has("forge:heal")
		var cost: int = int(_vm.get("costs",{}).get("forge:heal",0))
		var heal := _button(parent,"全阵已满血" if not can_heal else "全阵恢复 · %s" % ("本次免费" if cost == 0 else "%d 铜钱" % cost),func() -> void: command({"type":"use_forge_heal"}),true)
		heal.disabled = not can_heal or cost > int(state.currency)
	_options(parent,state.shop_options,"buy_forge_option" if forge else "buy_shop_option")
	if not forge and "tradePermit" in state.relic_ids:
		_button(parent,"出售自由技",_show_inventory)

func command(payload: Dictionary) -> bool:
	var errors: Array[String] = []
	var ok: bool = session.execute(payload,errors)
	if not ok:
		_feedback = "操作未完成：" + "; ".join(errors)
		_render()
		return false
	_feedback = ""
	if session.snapshot().get("status") == "fighting":
		_start_battle()
	else:
		_render()
	return true

func _start_battle() -> void:
	_surface.visible = false
	battle = BattleScene.instantiate()
	battle.auto_start = false
	add_child(battle)
	battle.run_battle_finished.connect(func(_snapshot: Dictionary) -> void:
		var errors: Array[String] = []
		if not session.save_checkpoint(errors): _feedback = "本局已结算，但存档写入失败：" + "; ".join(errors)
	)
	battle.run_continue_requested.connect(_leave_battle)
	if not battle.start_run_battle(session.battle_lifecycle()):
		_feedback = "战斗启动失败。返回标题后可读取入战前存档。"
		_leave_battle()
		var recovery_errors: Array[String] = []
		session.continue_run(recovery_errors)
		_home = true
		_render()
		return
	battle.command_rejected.connect(func(code: String, message: String) -> void:
		if code.begins_with("run_"):
			_show_text("结算暂未完成",message+"\n可通过暂停菜单返回入战前检查点。")
	)
	var hud: Node = battle.battle_screen.battle_hud
	if hud.has_node("RightGroup"):
		var controls: Control = hud.get_node("RightGroup")
		controls.offset_left -= 76
		_button(controls, "暂停", _toggle_pause)

func _leave_battle() -> void:
	if is_instance_valid(_pause):
		_pause.queue_free()
		_pause = null
	if is_instance_valid(battle):
		remove_child(battle)
		battle.queue_free()
	battle = null
	_home = false
	_render()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_formation_layer):
		_close_formation_dialog()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and is_instance_valid(battle):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if is_instance_valid(_pause):
		_pause.queue_free()
		_pause = null
		if is_instance_valid(battle):
			battle.process_mode = Node.PROCESS_MODE_INHERIT
			if _resume_auto: battle.set_auto_battle(true)
		_resume_auto = false
		return
	if not is_instance_valid(battle): return
	_resume_auto = bool(battle.controller.view_model().get("presentation",{}).get("auto_battle",false))
	battle.set_auto_battle(false)
	battle.process_mode = Node.PROCESS_MODE_DISABLED
	_pause = ColorRect.new()
	_pause.color = Color(0.04,0.09,0.06,0.94)
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_pause)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)
	var panel := _panel(center)
	panel.get_parent().custom_minimum_size.x = 460
	_label(panel,"暂歇片刻",30)
	_label(panel,"战斗中退出会回到入战前检查点。",16,MUTED)
	_button(panel,"继续战斗",_toggle_pause,true)
	_button(panel,"返回标题",func() -> void:
		var errors: Array[String] = []
		_leave_battle()
		# Restore the last durable checkpoint, never keep a half-fought world.
		if not session.continue_run(errors): _feedback = "无法恢复检查点：" + "; ".join(errors)
		_home = true
		_render()
	)

func _show_inventory() -> void:
	var dialog := Window.new()
	dialog.title = "牌库与遗物"
	dialog.size = Vector2i(680,500)
	dialog.transient = true
	dialog.exclusive = true
	add_child(dialog)
	dialog.close_requested.connect(dialog.queue_free)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var body := _vbox(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var state: Dictionary = _vm.run
	var catalog: Dictionary = _vm.catalog
	_label(body,"弈者专属",22,GOLD)
	for hero_id: String in state.hero_deployment_slots:
		var hero := _hero(int(hero_id))
		_label(body,"%s · %s%s" % [hero.name,hero.get("exclusive_name",""),"（被动，不入牌库）" if hero.get("is_passive",false) else ""],17)
		_label(body,str(hero.get("exclusive_description","")),14,MUTED,true)
	_label(body,"自由技 · 同名牌每份独立",22,GOLD)
	var counts := {}
	for id: String in state.free_skill_ids: counts[id] = int(counts.get(id,0))+1
	for id: String in counts:
		var skill: Dictionary = catalog.skills.get(id,{})
		var line := _hbox(body)
		_label(line,"%s × %d" % [skill.get("name",id),counts[id]],17)
		if state.status == "shop" and "tradePermit" in state.relic_ids:
			_button(line,"出售一张",func() -> void: dialog.queue_free(); command({"type":"sell_free_skill","skill_id":id}))
		_label(body,str(skill.get("description","")),14,MUTED,true)
	_label(body,"额外专属牌 · 同名副本独立",22,GOLD)
	var exclusive_counts := {}
	for card_id: String in state.get("exclusive_card_ids", []):
		exclusive_counts[card_id] = int(exclusive_counts.get(card_id, 0)) + 1
	if exclusive_counts.is_empty():
		_label(body,"战后与商旅的卡牌候选中，可再次取得上阵弈者的主动专属牌。",14,MUTED,true)
	for card_id: String in exclusive_counts:
		var ability := _exclusive_card_view(card_id)
		var hero := _hero(int(ability.get("owner_hero_id", 0)))
		_label(body, "%s · %s × %d · %d SP" % [
			str(hero.get("name", "弈者")), str(ability.get("name", card_id)),
			int(exclusive_counts[card_id]), int(ability.get("base_sp_cost", 0)),
		], 17)
		_label(body, str(ability.get("description", "")), 14, MUTED, true)
	_label(body,"遗物",22,GOLD)
	if state.relic_ids.is_empty(): _label(body,"旅途中获得的遗物会出现在这里。",14,MUTED,true)
	for id: String in state.relic_ids:
		_add_relic_info(body, id)
	dialog.popup_centered()


func _exclusive_card_view(card_id: String) -> Dictionary:
	var ability_id := card_id.trim_prefix("exclusive:")
	var view: Dictionary = _vm.get("catalog", {}).get("abilities", {}).get(ability_id, {}).duplicate()
	if not view.is_empty():
		return view
	var definition: Variant = HeroCardCatalogScript.definitions().get(card_id)
	var display: Variant = HeroCardCatalogScript.display(card_id)
	if definition is Resource and typeof(display) == TYPE_DICTIONARY:
		return {
			"owner_hero_id": definition.owner_hero_id,
			"base_sp_cost": definition.base_sp_cost,
			"name": display.get("name", ability_id),
			"description": display.get("description", ""),
		}
	return {}

func _ask(message: String, action: Callable) -> void:
	_confirmation_action = action
	_confirm.dialog_text = message
	_confirm.popup_centered(Vector2i(480,180))

func _show_text(heading: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = heading
	dialog.dialog_text = message
	dialog.ok_button_text = "明白了"
	dialog.dialog_autowrap = true
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(540,250))
