extends Control
## A carved geometric seal for the commanding hero, matching the native pieces.
## Portrait identity remains in the VM; this view never changes hero mechanics.
var hero_id: Variant = 1
var enemy := false
var title := "弈"
var charge := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func configure(vm: Dictionary) -> void:
	hero_id = vm.get("id",1)
	enemy = vm.get("side","ally") == "enemy"
	title = str(vm.get("name","弈")).trim_prefix("敌·").trim_prefix("敌")
	charge = clampf(float(vm.get("energy",0)) / maxf(1,float(vm.get("max_energy",100))),0,1)
	queue_redraw()

func _draw() -> void:
	var r := minf(size.x*0.36, size.y*0.41)
	if r < 5: return
	var center := size*0.5
	var face := Color("be7961") if enemy else Color("80a596")
	var side := Color("59392f") if enemy else Color("2c4943")
	var light := Color("e0ad87") if enemy else Color("b5c5a6")
	var gold := Color("c6ad72")
	draw_arc(center,r*1.23,0,TAU,64,Color(0.7,0.72,0.53,0.23),1,true)
	if charge > 0:
		draw_arc(center,r*1.23,-PI/2,-PI/2+TAU*charge,64,gold,2,true)
	var outline := PackedVector2Array()
	for v in [Vector2(-0.68,-0.88),Vector2(0.48,-1),Vector2(0.85,-0.62),Vector2(0.68,0.88),Vector2(-0.48,1),Vector2(-0.85,0.62)]:
		outline.append(center+v*r)
	var rear := PackedVector2Array()
	for v in outline: rear.append(v+Vector2(-r*0.10,-r*0.06))
	draw_colored_polygon(rear,side)
	draw_polygon(outline,PackedColorArray([light,light,face,side,side,face]))
	var inset := PackedVector2Array()
	for v in outline: inset.append(center+(v-center)*0.81)
	inset.append(inset[0])
	draw_polyline(inset,Color(0.12,0.23,0.19,0.65),1,true)
	# The inscribed name gives a stable identity even when the compact enemy
	# panel is too small for a figurative portrait.
	var font := ThemeDB.fallback_font
	var font_size := maxi(12,roundi(r*0.52))
	var glyph := title.substr(0,1)
	var metrics := font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	draw_string(font,center+Vector2(-metrics.x*0.5,metrics.y*0.24),glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("f0e4c3"))
	for i in 3:
		var x := center.x+(i-1)*r*0.17
		draw_line(Vector2(x,center.y+r*0.46),Vector2(x,center.y+r*0.57),gold,1.3,true)
