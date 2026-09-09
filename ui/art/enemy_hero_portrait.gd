extends Control
## Small-format, transparent enemy busts. All geometry uses a 100 × 100 artboard.
## No frame/background: the host owns its card surface and interaction.

const INK := Color("101c1c")
const DARK := Color("203333")
const STEEL := Color("455654")
const EDGE := Color("78827a")
const GOLD := Color("aa8c59")
const LIGHT := Color("d2bc87")
const RED := Color("874637")
const SKIN := Color("ac9275")
const SHADE := Color("695e50")
var _kind: String = "commander"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func bind_hero(hero_vm: Dictionary) -> void:
	var by_id := {101: "commander", 102: "guardian", 103: "puppet", 201: "burn", 202: "enchant", 203: "fate", 301: "fist", 302: "siege", 303: "fate"}
	var by_skill := {"ascend": "commander", "counterAura": "guardian", "puppet": "puppet", "burn01": "burn", "burnEnchant": "enchant", "fate": "fate", "fist": "fist", "siege": "siege"}
	_kind = str(by_id.get(int(hero_vm.get("id", -1)), by_skill.get(str(hero_vm.get("ex_skill", "")), "commander")))
	queue_redraw()

func archetype() -> String:
	return _kind

func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 100.0
	if scale_factor <= 0.0:
		return
	draw_set_transform((size - Vector2.ONE * 100.0 * scale_factor) * 0.5, 0.0, Vector2.ONE * scale_factor)
	match _kind:
		"guardian": _guardian()
		"puppet": _puppet()
		"burn": _burn()
		"enchant": _enchant()
		"fate": _fate()
		"fist": _fist()
		"siege": _siege()
		_: _commander()
	draw_set_transform(Vector2.ZERO)

func _p(coords: Array, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(0, coords.size(), 2):
		points.append(Vector2(float(coords[i]), float(coords[i + 1])))
	draw_colored_polygon(points, color)

func _l(coords: Array, color: Color, width: float = 1.2) -> void:
	var points := PackedVector2Array()
	for i in range(0, coords.size(), 2):
		points.append(Vector2(float(coords[i]), float(coords[i + 1])))
	draw_polyline(points, color, width, true)

func _c(x: float, y: float, radius: float, color: Color) -> void:
	draw_circle(Vector2(x, y), radius, color)

func _face() -> void:
	_p([34,29, 62,27, 68,42, 63,60, 52,70, 41,64, 34,50], SKIN)
	_p([52,30, 64,30, 68,43, 62,59, 52,69, 50,57, 55,47], SHADE)
	_p([35,40, 33,47, 36,52, 39,49], SKIN)
	_l([38,42, 46,41], INK, 2.4)
	_l([55,41, 63,39], INK, 2.4)
	_l([40,44, 45,44], LIGHT, 1.0)
	_l([56,44, 60,43], LIGHT, 1.0)
	_l([50,43, 48,52, 53,53], SHADE)
	_l([46,59, 56,58], INK, 1.5)

func _robe(color: Color = DARK) -> void:
	_p([36,63, 62,61, 78,71, 91,91, 84,97, 13,97, 8,88, 22,73], INK)
	_p([36,66, 46,71, 40,95, 14,94, 24,77], color)
	_p([60,65, 72,74, 85,95, 43,95, 48,72], color.lightened(0.08))
	_p([35,64, 49,73, 62,63, 65,70, 49,86, 31,72], GOLD)
	_p([35,67, 49,77, 61,66, 62,70, 49,82, 34,72], INK)

func _commander() -> void:
	# A rigid official's crown and a loose red horsehair tassel.
	_p([58,18, 64,7, 74,5, 70,17, 83,29, 80,48, 72,38, 73,25], RED)
	_l([69,10, 66,19, 77,31, 78,42], GOLD, 1.2)
	_robe()
	_p([12,81, 28,69, 37,72, 34,87, 13,92], STEEL)
	_p([66,71, 76,71, 91,84, 86,94, 66,86], STEEL)
	_l([13,81, 29,74, 33,75], GOLD, 2)
	_l([68,75, 77,76, 88,85], GOLD, 2)
	for y in [82, 87, 92]:
		_l([18,y, 31,y-4], EDGE)
		_l([70,y-3, 82,y+1], EDGE)
	_face()
	_p([37,24, 39,12, 57,9, 64,16, 65,32, 33,35, 28,29], INK)
	_p([40,15, 55,12, 57,26, 39,28], DARK)
	_p([32,29, 65,25, 69,31, 33,36], GOLD)
	_l([37,31, 63,29], LIGHT, 1)
	_p([34,34, 39,35, 38,52, 34,49], INK)
	_p([62,33, 67,32, 67,49, 63,54], INK)
	_p([44,62, 53,63, 60,59, 57,69, 51,74, 45,69], INK)
	_l([50,64, 51,69], SHADE)

func _guardian() -> void:
	_robe(STEEL)
	_p([8,73, 29,65, 40,76, 34,97, 5,94], DARK)
	_p([66,74, 76,65, 96,76, 96,95, 66,97], DARK)
	_p([8,73, 27,69, 34,78, 9,84], EDGE)
	_p([72,74, 78,68, 93,77, 92,84], STEEL)
	_l([10,85, 31,82, 28,92, 10,94], GOLD, 1.5)
	_l([72,82, 92,85, 91,94], GOLD, 1.5)
	_p([27,35, 31,19, 45,12, 61,15, 72,30, 72,62, 62,72, 38,72, 27,60], INK)
	_p([31,34, 35,22, 47,16, 48,38], STEEL)
	_p([50,16, 60,19, 67,31, 68,39, 51,38], DARK)
	_p([46,15, 51,14, 55,41, 49,46, 45,38], GOLD)
	_p([29,39, 46,41, 49,48, 45,63, 37,65, 29,56], STEEL)
	_p([54,42, 70,39, 69,58, 59,65, 53,60], STEEL)
	_l([33,44, 44,46], LIGHT, 2)
	_l([56,46, 66,44], LIGHT, 2)
	_p([44,50, 54,50, 61,64, 53,72, 44,68, 39,61], DARK)
	_l([48,53, 47,62, 52,66], EDGE, 1.5)
	_l([30,35, 43,37], EDGE)
	for x in [37, 61]:
		_c(x, 57, 1.4, GOLD)
	_p([39,76, 49,82, 62,75, 60,93, 42,96], STEEL)
	_l([42,81, 51,87, 58,80], GOLD, 2)

func _puppet() -> void:
	_robe()
	_p([9,90, 12,75, 25,65, 36,72, 32,96], GOLD)
	_p([15,81, 24,72, 30,75, 26,94, 16,93], DARK)
	_c(24, 82, 6, INK)
	_c(24, 82, 3, EDGE)
	_p([69,61, 80,58, 86,66, 82,84, 93,94, 65,96], STEEL)
	_l([74,67, 78,74, 73,87], GOLD, 3)
	_c(77, 76, 4, INK)
	_c(77, 76, 2, GOLD)
	_p([29,34, 33,19, 47,13, 62,18, 72,29, 67,52, 58,69, 42,67, 31,55], INK)
	_p([34,28, 48,20, 62,23, 67,38, 59,62, 48,66, 36,53], GOLD)
	_p([48,24, 60,27, 62,37, 54,48, 57,58, 49,64, 45,49], SHADE)
	_p([34,28, 48,20, 47,40, 38,46, 32,39], DARK)
	_c(40, 39, 10, INK)
	_c(40, 39, 7.4, GOLD)
	_c(40, 39, 4.8, DARK)
	_c(38.6, 37.4, 2.3, LIGHT)
	_l([54,38, 62,36], INK, 3)
	_l([55,38, 60,37], LIGHT)
	_l([49,43, 47,51, 52,53], INK, 1.5)
	_l([43,57, 53,59], INK, 2)
	_l([36,48, 40,57, 39,62], LIGHT)
	_p([57,18, 64,14, 71,24, 70,38, 65,34], STEEL)
	_l([64,24, 68,29, 67,40], EDGE)
	_p([53,71, 60,65, 67,76, 60,89, 46,94], RED)

func _burn() -> void:
	_p([26,71, 23,38, 32,27, 30,10, 43,21, 53,6, 59,21, 73,18, 68,33, 78,50, 71,77], INK)
	_p([29,39, 37,31, 36,19, 46,29, 54,14, 57,31, 68,26, 64,41, 73,51, 65,64, 35,63], RED)
	_robe(RED.darkened(0.4))
	_face()
	_p([34,32, 41,23, 50,28, 63,27, 68,39, 56,32, 41,36, 36,44], INK)
	_l([37,37, 43,47, 41,52, 49,58], RED, 3)
	_l([38,38, 45,48, 43,51], LIGHT, 1)
	_p([27,70, 36,67, 42,91, 24,93], RED)
	_l([29,72, 33,81, 29,87], GOLD, 2)
	_l([64,71, 69,81, 76,91], GOLD, 2)

func _enchant() -> void:
	_p([24,64, 29,28, 40,12, 58,13, 72,34, 76,71], INK)
	_robe(RED.darkened(0.3))
	_face()
	_p([26,49, 29,28, 40,12, 55,13, 65,23, 70,44, 59,29, 40,28, 33,52], DARK)
	_l([29,43, 33,28, 42,17, 55,18, 63,28], GOLD, 1.5)
	_p([55,28, 65,31, 63,59, 54,56], GOLD)
	_l([58,33, 62,35, 57,40, 61,43, 57,49, 61,53], INK, 1.5)
	_p([33,65, 40,70, 32,92, 24,87], GOLD)
	_p([65,65, 72,69, 82,87, 74,92], GOLD)
	_l([33,72, 35,76, 29,81, 31,85], RED, 2)
	_l([68,72, 74,76, 72,81, 77,86], RED, 2)
	_l([43,57, 50,58], RED, 1.5)

func _fate() -> void:
	_p([20,76, 23,34, 35,12, 53,8, 70,25, 78,72], INK)
	_robe()
	_p([26,58, 28,32, 38,18, 53,13, 66,28, 70,55, 62,43, 57,27, 42,27, 33,43], DARK)
	_l([28,41, 34,27, 45,18, 53,17, 63,28], GOLD)
	_p([35,34, 48,26, 62,33, 65,49, 59,62, 49,70, 38,61, 32,46], GOLD)
	_p([49,28, 60,34, 62,47, 56,62, 49,67], SHADE)
	_l([36,40, 43,44, 46,43], INK, 2.4)
	_l([53,43, 57,43, 62,39], INK, 2.4)
	_l([48,36, 46,51, 51,54, 48,60], LIGHT, 1.5)
	_l([38,50, 41,56, 45,58], INK)
	_l([59,50, 56,56, 52,58], INK)
	_p([45,30, 49,27, 53,31, 49,35], LIGHT)
	for i in range(5):
		_c(32 + i * 8, 75 + abs(2 - i) * -2, 2.6, GOLD)
	_p([44,78, 52,79, 57,95, 40,95], RED)
	_l([48,82, 45,87, 51,89, 48,94], GOLD, 1.5)

func _fist() -> void:
	_robe(RED.darkened(0.3))
	_p([27,74, 40,63, 48,69, 59,63, 72,75, 68,92, 32,95], SKIN)
	_p([49,72, 58,66, 67,74, 63,93, 51,92], SHADE)
	_face()
	_p([33,36, 32,23, 43,16, 57,17, 64,27, 64,36, 56,27, 42,28], INK)
	_p([32,31, 63,29, 65,35, 33,38], RED)
	_p([33,34, 24,36, 17,54, 26,49, 30,39], RED)
	_l([35,34, 59,32], GOLD)
	_p([14,90, 20,69, 27,63, 35,66, 39,76, 35,93], SHADE)
	_p([20,78, 35,80, 34,94, 16,94], EDGE)
	for y in [81, 86, 91]:
		_l([20,y, 34,y+2], DARK, 1.5)
	_l([24,72, 29,72, 32,75], SKIN, 2)
	_p([64,80, 74,72, 85,94, 58,96], DARK)
	_l([42,79, 47,83, 54,78], SHADE, 1.5)

func _siege() -> void:
	# Broken swept crest, cheek scar and one oversized lamellar shoulder.
	_p([63,69, 76,58, 91,67, 96,89, 83,97, 64,94], INK)
	_robe(RED.darkened(0.35))
	_p([64,74, 78,63, 90,71, 95,90, 68,96], STEEL)
	_l([68,74, 79,68, 88,74], GOLD, 2)
	for y in [79, 85, 91]:
		_l([71,y, 88,y-3], EDGE, 1.8)
	_p([10,86, 23,72, 34,72, 37,92, 17,97], DARK)
	_l([15,85, 29,78, 31,90], GOLD, 1.5)
	_face()
	_p([31,39, 31,24, 41,17, 57,18, 66,29, 67,45, 61,36, 42,30], STEEL)
	_p([35,23, 26,10, 40,14, 48,25, 57,18, 61,6, 68,10, 64,27, 52,33], INK)
	_l([31,15, 41,20, 48,28, 60,23, 64,13], GOLD, 2)
	_p([31,37, 38,35, 39,55, 34,61, 29,51], DARK)
	_p([62,36, 69,35, 69,57, 61,62, 63,48], DARK)
	_l([40,47, 47,55, 45,61], RED, 2)
	_p([44,61, 51,64, 60,59, 56,68, 49,70], INK)
	_p([38,70, 48,76, 59,67, 62,74, 50,87], RED)
