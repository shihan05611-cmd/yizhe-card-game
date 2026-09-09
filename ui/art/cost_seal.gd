class_name CostSeal
extends Control
## Place beneath the cost Label. A 26 x 30 pointed jade tab, without text.

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var unit := minf(size.x / 26.0, size.y / 30.0)
	if unit <= 0.0:
		return
	draw_set_transform((size - Vector2(26,30)*unit)*0.5, 0.0, Vector2.ONE*unit)
	var silhouette := PackedVector2Array([Vector2(0.6,0.6),Vector2(25.4,0.6),Vector2(25.4,22.0),Vector2(13,29.3),Vector2(0.6,22.0)])
	draw_polygon(silhouette,PackedColorArray([Color("456153"),Color("345447"),Color("304d40"),Color("2c473b"),Color("3b5849")]))
	silhouette.append(silhouette[0])
	draw_polyline(silhouette,Color("a39967"),0.85,true)
	draw_line(Vector2(3,2.5),Vector2(23,2.5),Color(0.83,0.80,0.56,0.20),0.65,true)
	draw_set_transform(Vector2.ZERO)
