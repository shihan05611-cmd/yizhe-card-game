class_name PortraitHalo
extends Control
## Optional backing for the actual portrait texture, never replaces the art.

@export var enemy := false:
	set(value):
		enemy = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var radius := minf(size.x,size.y)*0.43
	if radius <= 0.0:
		return
	var center := size*0.5
	var tint := Color("ce9e6f") if enemy else Color("a9bb8e")
	for i in range(16):
		var t := float(i)/15.0
		draw_circle(center,radius*(1-t*0.80),Color(tint,0.0035))
	draw_circle(center,radius,Color(tint,0.14),false,0.8,true)
	var diamond := PackedVector2Array([center+Vector2(0,-radius*1.18),center+Vector2(radius*1.18,0),center+Vector2(0,radius*1.18),center+Vector2(-radius*1.18,0),center+Vector2(0,-radius*1.18)])
	draw_polyline(diamond,Color(tint,0.075),0.75,true)
	for i in range(48):
		var angle := TAU*i/48.0
		draw_arc(center,radius*1.105,angle,angle+0.055,3,Color(tint,0.07),0.7,true)
