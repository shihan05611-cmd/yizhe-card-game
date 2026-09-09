class_name BurnAura
extends Control
## Presentation only. Fit to the piece art rectangle, above its HP/name row.
## No timers, tweens, materials or particles survive this Control's lifetime.

var _stacks := 0
var _phase := 0.0
var _presentation_speed := 1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_INHERIT
	set_process(false)

func _ready() -> void:
	resized.connect(queue_redraw)
	visibility_changed.connect(_sync_processing)
	_sync_processing()

func set_burn_stacks(stacks: int) -> void:
	_stacks = clampi(stacks, 0, 8)
	if _stacks == 0:
		_phase = 0.0
	_sync_processing()
	queue_redraw()

func set_presentation_speed(speed: float) -> void:
	_presentation_speed = clampf(speed, 0.0, 4.0) if is_finite(speed) else 1.0
	_sync_processing()

func reset_visuals() -> void:
	_stacks = 0
	_phase = 0.0
	set_process(false)
	queue_redraw()

func _sync_processing() -> void:
	set_process(_stacks > 0 and _presentation_speed > 0.0 and is_visible_in_tree())

func _exit_tree() -> void:
	reset_visuals()

func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * _presentation_speed, TAU * 10.0)
	queue_redraw()

func _draw() -> void:
	if _stacks <= 0 or size.x <= 0 or size.y <= 0:
		return
	var unit := minf(size.x / 150.0, size.y / 96.0)
	draw_set_transform(Vector2(size.x * 0.5, size.y * 0.87), 0.0, Vector2.ONE * unit)
	var intensity := float(_stacks) / 8.0
	# A shallow copper contact ring leaves the piece silhouette readable.
	var ring := PackedVector2Array()
	for i in range(33):
		var angle := PI * i / 32.0
		ring.append(Vector2(cos(angle)*31,sin(angle)*5))
	draw_polyline(ring,Color(0.72,0.37,0.16,0.22+intensity*0.1),1.2,true)
	var flame_count := 3 + mini(_stacks, 5)
	for i in range(flame_count):
		var seed := float(i) * 2.399
		var sway := sin(_phase*2.2+seed)
		var x := -32.0 + 64.0 * float(i) / maxf(flame_count-1,1)
		var height := 13.0 + intensity*11.0 + 4.0*sin(_phase*1.6+seed)
		var base := Vector2(x,-3.0-absf(x)*0.08)
		var flame := PackedVector2Array([base+Vector2(-3,0),base+Vector2(-5,-height*0.35),base+Vector2(sway*3,-height),base+Vector2(2,-height*0.60),base+Vector2(4,-height*0.35),base+Vector2(3,0)])
		draw_colored_polygon(flame,Color(0.72,0.31,0.12,0.20+intensity*0.12))
		draw_polyline(PackedVector2Array([base+Vector2(-2,-2),base+Vector2(-3,-height*0.35),base+Vector2(sway*3,-height)]),Color(0.86,0.52,0.25,0.58),1.0,true)
	for i in range(2+mini(_stacks,4)):
		var progress := fmod(_phase*0.30 + i*0.173,1.0)
		var x := sin(i*4.3)*32 + sin(_phase+i)*3
		var point := Vector2(x,-8-progress*(27+intensity*14))
		var alpha := sin(progress*PI)*0.60
		draw_line(point,point+Vector2(0.7,-2.0),Color(0.91,0.62,0.32,alpha),1.0,true)
	draw_set_transform(Vector2.ZERO)
