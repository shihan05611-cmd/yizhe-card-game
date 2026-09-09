class_name RelicIcon
extends Control
## Small presentation-only objects. The real description belongs to the tooltip.
## Dormant shentong relics are deliberately not added to any candidate pool here.

const JADE := Color("a6bba2")
const COPPER := Color("c89a72")
const PAPER := Color("d6c8a0")
const GLYPHS := {
	"spLimitPlus":"vessel", "trueNameUnseal":"unseal", "ultPursuitMark":"pursuit",
	"arcConductor":"conductor", "emberStorm":"storm", "executionAxe":"axe",
	"thornCrown":"crown", "tradePermit":"permit", "discountCard":"discount",
	"witheredSeal":"wither", "crossbowPlus":"crossbow", "shieldPlus":"shield",
	"assassinPlus":"dagger", "bannerPlus":"banner", "rationChip":"ration",
	"zeroCostSpark":"spark", "scorchShard":"shard", "fieldBandage":"bandage",
	"graveChange":"grave", "lastEmber":"ember",
}
var _glyph := "unknown"

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)

func bind_relic(relic: Variant) -> void:
	var id := str(relic.get("id", "")) if relic is Dictionary else str(relic)
	_glyph = str(GLYPHS.get(id,"unknown"))
	queue_redraw()

func _line(coords: Array, ink := JADE, width := 1.45, closed := false) -> void:
	var points := PackedVector2Array()
	for i in range(0,coords.size(),2):
		points.append(Vector2(coords[i],coords[i+1]))
	if closed:
		points.append(points[0])
	draw_polyline(points,ink,width,true)

func _cross(at: Vector2, ink := JADE, radius := 3.0) -> void:
	draw_line(at-Vector2(radius,0),at+Vector2(radius,0),ink,1.5,true)
	draw_line(at-Vector2(0,radius),at+Vector2(0,radius),ink,1.5,true)

func _coin(at: Vector2, radius := 7.0) -> void:
	draw_circle(at,radius,Color(COPPER,0.12))
	draw_circle(at,radius,COPPER,false,1.3,true)
	draw_rect(Rect2(at-Vector2(2,2),Vector2(4,4)),PAPER,false,1.0)

func _draw() -> void:
	var unit := minf(size.x,size.y)/40.0
	if unit <= 0.0:
		return
	draw_set_transform((size-Vector2(40,40)*unit)*0.5,0,Vector2.ONE*unit)
	match _glyph:
		"vessel":
			_line([12,9,28,9,30,28,26,33,14,33,10,28],JADE,1.5,true)
			_line([10,6,30,6],PAPER)
			_cross(Vector2(20,20),PAPER,4)
		"unseal":
			_line([10,5,30,5,30,17,25,15,21,22,16,19,10,23],PAPER,1.4,true)
			_line([10,28,16,24,20,28,26,21,30,24,30,35,10,35],JADE,1.4,true)
			_line([17,10,23,10,20,15],COPPER)
		"pursuit":
			_line([7,10,17,20,7,30],JADE,2.1)
			_line([19,10,29,20,19,30],PAPER,2.1)
			_line([30,9,34,9,34,31,30,31],COPPER,1.0)
		"conductor":
			_line([22,5,12,21,20,21,17,35,29,17,21,17],PAPER,1.6,true)
			for y in [11,29]:
				_line([5,y,9,y],COPPER)
				_line([31,y,35,y],COPPER)
		"storm":
			_line([21,5,23,15,29,12,31,23,26,30,17,31,11,25,12,16,17,21],COPPER,1.6,true)
			draw_arc(Vector2(20,22),15,0.1,2.5,18,JADE,1.0,true)
			_line([5,9,12,7,17,8],PAPER,1.0)
		"axe":
			_line([12,35,26,6],PAPER,2.5)
			_line([21,10,12,7,7,14,17,21,23,20,32,22,35,12,28,8],COPPER,1.5,true)
		"crown":
			_line([8,15,14,20,20,9,26,20,32,15,29,31,11,31],COPPER,1.6,true)
			_line([12,27,28,27],PAPER,1.0)
			_line([7,12,5,8,10,9],JADE)
			_line([30,9,35,8,33,12],JADE)
		"permit":
			_line([11,6,29,6,29,29,25,34,11,34],PAPER,1.4,true)
			_line([15,12,25,12],JADE,1.0)
			_line([15,16,23,16],JADE,1.0)
			draw_circle(Vector2(20,25),5,COPPER,false,1.3,true)
			_line([17,25,19,27,23,23],PAPER,1.0)
		"discount":
			_line([8,13,17,5,32,20,20,33,6,19],JADE,1.4,true)
			draw_circle(Vector2(13,13),2,PAPER,false,1.0,true)
			_line([16,26,26,16],COPPER,1.6)
			draw_circle(Vector2(19,18),1.4,PAPER)
			draw_circle(Vector2(24,24),1.4,PAPER)
		"wither":
			_line([20,34,20,17,13,10,9,10,11,18,20,22],COPPER,1.4)
			_line([20,17,29,10,31,15,27,22,20,25],JADE,1.4)
			_line([10,29,31,7],PAPER,1.6)
		"crossbow":
			_line([20,7,20,34],PAPER,1.5)
			_line([7,24,10,14,20,10,30,14,33,24,7,24],JADE,1.5)
			_line([15,8,20,4,25,8],COPPER,1.3)
			_line([16,29,24,29],COPPER,1.3)
		"shield":
			_line([8,9,20,5,32,9,29,26,20,34,11,26],JADE,1.6,true)
			_cross(Vector2(20,18),PAPER,5)
		"dagger":
			_line([16,24,25,5,30,7,29,13,21,27],JADE,1.5,true)
			_line([12,22,25,29,21,29,16,35,11,32,16,26],COPPER,1.5)
			_line([7,9,10,14],PAPER,1.0)
			_line([10,6,14,9],PAPER,1.0)
		"banner":
			_line([11,35,11,5,31,9,27,19,11,15],JADE,1.5)
			_line([7,35,17,35],PAPER,1.4)
			_line([23,23,19,30,25,30,22,36],COPPER,1.3)
		"ration":
			_coin(Vector2(20,21),12)
			_line([13,5,27,5],JADE,1.4)
			_cross(Vector2(31,9),PAPER,3)
		"spark":
			draw_circle(Vector2(12,12),6,JADE,false,1.4,true)
			_line([27,10,23,21,16,25,23,27,26,36,29,27,36,24,29,21],PAPER,1.4,true)
		"shard":
			_line([8,31,15,9,22,17,26,8,31,30,19,35],COPPER,1.5,true)
			_line([14,28,19,21,23,29],PAPER,1.2)
		"bandage":
			_line([7,24,24,7,33,16,16,33],PAPER,1.8,true)
			_line([12,20,20,28],JADE,1.0)
			_line([20,12,28,20],JADE,1.0)
			_cross(Vector2(20,20),COPPER,3)
		"grave":
			_line([9,30,9,11,13,6,20,6,24,11,24,30,6,30],JADE,1.4)
			_line([13,13,20,13],PAPER,1.0)
			_coin(Vector2(27,28),8)
		"ember":
			_line([20,6,22,15,28,22,27,29,21,34,14,32,10,25,14,15,17,20],COPPER,1.5,true)
			_cross(Vector2(20,26),JADE,4)
		_:
			_line([13,7,27,7,29,29,25,34,15,34,11,29],JADE,1.4,true)
			draw_circle(Vector2(20,20),4,PAPER,false,1.2,true)
	draw_set_transform(Vector2.ZERO)
