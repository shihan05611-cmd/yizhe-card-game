class_name CardIllustration
extends Control
## Small engraved pictograms; never consumes card drag or hover input.

const GLYPHS := {
	"pieceBlock": "shield", "pieceDamageUp": "power", "executeStrike": "blade",
	"pieceAction": "action", "markBurn": "flame", "burnStackBase": "flame",
	"burnDetonate": "flame", "pieceHealAll": "heal", "smallHeal": "heal",
	"bloodShift": "blood",
	"burn01": "flame", "burnEnchant": "flame", "counterAura": "shield",
	"fist": "fist", "shadow": "shadow", "ascend": "banner",
	"siege": "blade", "puppet": "puppet", "fate": "fate",
	"spSurge": "surge", "tacticalDraw": "draw", "puppetAttunement": "attunement",
}
var _glyph := "neutral"
var _category := "free"

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)

func bind_card(card_vm: Dictionary) -> void:
	var skill_id := str(card_vm.get("source_skill_id", card_vm.get("skill_id", "")))
	_glyph = str(GLYPHS.get(skill_id, "neutral"))
	_category = str(card_vm.get("category", "free"))
	queue_redraw()

func _stroke(points: Array, color: Color, width := 1.5, closed := false) -> void:
	var path := PackedVector2Array()
	for point: Vector2 in points:
		path.append(point)
	if closed and not path.is_empty():
		path.append(path[0])
	draw_polyline(path, color, width, true)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var unit := minf(size.x / 100.0, size.y / 66.0)
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * unit)
	var ink := Color("3c5c4b")
	if _glyph in ["flame", "blood"]:
		ink = Color("996147")
	elif _glyph == "blade":
		ink = Color("6b5544")
	draw_circle(Vector2.ZERO, 28.5, Color(0.40, 0.48, 0.33, 0.25), false, 0.7, true)
	if _category == "ultimate":
		draw_circle(Vector2.ZERO,30.5,Color(0.66,0.48,0.20,0.48),false,0.8,true)
	_stroke([Vector2(0,-32),Vector2(32,0),Vector2(0,32),Vector2(-32,0)], Color(0.40,0.48,0.33,0.14), 0.65, true)
	match _glyph:
		"surge":
			draw_arc(Vector2.ZERO, 22, -2.5, 1.8, 32, ink, 1.6, true)
			draw_arc(Vector2.ZERO, 14, 0.5, 4.9, 26, ink, 1.3, true)
			_stroke([Vector2(-11,14),Vector2(-5,23),Vector2(3,17)],ink,1.6)
			_stroke([Vector2(4,-20),Vector2(3,-12),Vector2(11,-12)],ink,1.4)
			_stroke([Vector2(0,-7),Vector2(5,0),Vector2(0,7),Vector2(-5,0)],ink,1.3,true)
		"draw":
			_stroke([Vector2(-21,-15),Vector2(-5,-22),Vector2(4,-3),Vector2(-12,4)],ink,1.0,true)
			_stroke([Vector2(-10,-19),Vector2(9,-19),Vector2(9,7),Vector2(-10,7)],ink,1.3,true)
			_stroke([Vector2(2,-15),Vector2(21,-9),Vector2(13,16),Vector2(-6,10)],ink,1.6,true)
			_stroke([Vector2(3,0),Vector2(8,-5),Vector2(13,3),Vector2(7,7)],ink,1.0,true)
			_stroke([Vector2(-19,15),Vector2(-12,23),Vector2(3,23)],ink,1.2)
			_stroke([Vector2(-2,19),Vector2(3,23),Vector2(-2,27)],ink,1.2)
		"attunement":
			draw_circle(Vector2(0,-16),5,ink,false,1.4,true)
			_stroke([Vector2(-15,-3),Vector2(0,-7),Vector2(15,-3)],ink,1.4)
			_stroke([Vector2(-15,-3),Vector2(-19,11)],ink,1.3)
			_stroke([Vector2(15,-3),Vector2(19,11)],ink,1.3)
			_stroke([Vector2(0,10),Vector2(-10,25)],ink,1.4)
			_stroke([Vector2(0,10),Vector2(10,25)],ink,1.4)
			_stroke([Vector2(0,-2),Vector2(6,5),Vector2(0,12),Vector2(-6,5)],Color("b08038"),1.8,true)
			for i in 4:
				var ray := Vector2.from_angle(-PI*0.85+i*0.7)
				draw_line(ray*20,ray*26,Color("b08038"),1.0,true)
		"shadow":
			_stroke([Vector2(15,-24),Vector2(-4,-17),Vector2(-16,-2),Vector2(-10,16),Vector2(9,25),Vector2(2,10),Vector2(1,-5)],ink,1.55,true)
			_stroke([Vector2(-9,-2),Vector2(-2,0),Vector2(-7,3)],ink,1.2)
			_stroke([Vector2(14,4),Vector2(22,17),Vector2(8,23)],ink,1.0)
		"fist":
			_stroke([Vector2(-15,12),Vector2(-19,-4),Vector2(-14,-13),Vector2(-7,-13),Vector2(-7,-19),Vector2(0,-21),Vector2(6,-19),Vector2(12,-20),Vector2(18,-14),Vector2(19,1),Vector2(10,13),Vector2(9,23),Vector2(-9,23),Vector2(-10,13)],ink,1.55,true)
			_stroke([Vector2(-14,-5),Vector2(-2,-5),Vector2(3,1),Vector2(-4,7)],ink,1.2)
			for x in [-5,3,11]:
				draw_line(Vector2(x,-16),Vector2(x,-8),ink,1.1,true)
		"banner":
			_stroke([Vector2(-12,25),Vector2(-12,-26),Vector2(15,-20),Vector2(10,-8),Vector2(-12,-13)],ink,1.5)
			_stroke([Vector2(-21,25),Vector2(-3,25)],ink,1.4)
			_stroke([Vector2(-6,-19),Vector2(7,-16)],ink,1.0)
		"puppet":
			draw_circle(Vector2(0,-9),6,ink,false,1.4,true)
			_stroke([Vector2(-19,-25),Vector2(19,-25)],ink,1.4)
			_stroke([Vector2(-14,-25),Vector2(-14,6),Vector2(0,1),Vector2(14,6),Vector2(14,-25)],ink,1.0)
			_stroke([Vector2(0,-3),Vector2(0,12),Vector2(-10,24)],ink,1.5)
			_stroke([Vector2(0,12),Vector2(10,24)],ink,1.5)
		"fate":
			draw_arc(Vector2.ZERO,21,-PI*0.4,PI*0.8,30,ink,1.3,true)
			draw_arc(Vector2.ZERO,14,PI*0.6,PI*1.9,24,ink,1.3,true)
			_stroke([Vector2(0,-9),Vector2(7,0),Vector2(0,9),Vector2(-7,0)],ink,1.3,true)
			draw_circle(Vector2(-19,11),2,ink)
		"shield":
			_stroke([Vector2(-18,-17),Vector2(0,-24),Vector2(18,-17),Vector2(16,9),Vector2(0,23),Vector2(-16,9)],ink,1.6,true)
			_stroke([Vector2(-12,-12),Vector2(0,-17),Vector2(12,-12),Vector2(10,6),Vector2(0,16),Vector2(-10,6)],ink,1.2,true)
			_stroke([Vector2(0,-17),Vector2(0,16)],ink,1.0)
			_stroke([Vector2(-12,-8),Vector2(12,-8)],ink,1.0)
			for side in [-1.0,1.0]:
				_stroke([Vector2(side*25,-15),Vector2(side*29,0),Vector2(side*23,14)],ink,0.85)
		"power":
			_stroke([Vector2(0,-20),Vector2(10,0),Vector2(0,19),Vector2(-10,0)],ink,1.7,true)
			_stroke([Vector2(0,-15),Vector2(0,14)],ink,1.0)
			_stroke([Vector2(-7,0),Vector2(7,0)],ink,1.0)
			for i in range(8):
				var ray := Vector2.from_angle(TAU * i / 8.0)
				draw_line(ray*21,ray*31,ink,1.0,true)
		"action":
			_stroke([Vector2(-1,-25),Vector2(15,-20),Vector2(0,-3),Vector2(9,3),Vector2(-14,26),Vector2(-9,5),Vector2(-15,-2)],ink,1.65,true)
			for i in range(3):
				var y := -15.0 + i * 9
				draw_line(Vector2(-30,y),Vector2(-19,y),ink,0.85,true)
				draw_line(Vector2(14,-y+8),Vector2(28,-y+8),ink,0.85,true)
		"blade":
			_stroke([Vector2(-7,9),Vector2(13,-25),Vector2(20,-25),Vector2(19,-17),Vector2(0,14)],ink,1.5,true)
			_stroke([Vector2(-14,5),Vector2(8,20)],ink,1.6)
			_stroke([Vector2(-8,13),Vector2(-17,23),Vector2(-10,28),Vector2(-2,18)],ink,1.4,true)
			for side in [-1.0,1.0]:
				draw_line(Vector2(side*22,-14),Vector2(side*29,-20),ink,0.9,true)
				draw_line(Vector2(side*22,15),Vector2(side*29,21),ink,0.9,true)
		"flame":
			_stroke([Vector2(0,-28),Vector2(3,-15),Vector2(14,-4),Vector2(19,7),Vector2(16,18),Vector2(8,25),Vector2(-5,26),Vector2(-15,21),Vector2(-20,11),Vector2(-17,1),Vector2(-11,-17),Vector2(-6,-9),Vector2(0,-28)],ink,1.55)
			_stroke([Vector2(1,0),Vector2(8,11),Vector2(8,18),Vector2(3,23),Vector2(-4,23),Vector2(-8,18),Vector2(-7,11),Vector2(1,0)],ink,1.25)
			_stroke([Vector2(12,-22),Vector2(16,-29)],ink,0.9)
		"heal":
			_stroke([Vector2(-5,-20),Vector2(5,-20),Vector2(5,-5),Vector2(20,-5),Vector2(20,5),Vector2(5,5),Vector2(5,20),Vector2(-5,20),Vector2(-5,5),Vector2(-20,5),Vector2(-20,-5),Vector2(-5,-5)],ink,1.5,true)
		"blood":
			_stroke([Vector2(0,-24),Vector2(15,1),Vector2(16,12),Vector2(9,21),Vector2(0,24),Vector2(-9,21),Vector2(-16,12),Vector2(-15,1)],ink,1.5,true)
			draw_arc(Vector2(0,9),9,0.2,1.6,14,ink,1.0,true)
		_:
			_stroke([Vector2(0,-20),Vector2(18,0),Vector2(0,20),Vector2(-18,0)],ink,1.5,true)
			draw_circle(Vector2.ZERO,7,ink,false,1.1,true)
	draw_set_transform(Vector2.ZERO)
