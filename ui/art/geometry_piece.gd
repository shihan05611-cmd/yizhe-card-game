class_name GeometryPiece
extends Control
## Native port of tools/art/studies/piece-geometry-v4.js, the approved HTML's
## right-hand design. No textures or generated bitmap assets are used.

const JADE := {"ink": Color("142825"), "face": Color("80a596"), "light": Color("b5c5a6"), "side": Color("41685f"), "dark": Color("2c4943"), "gold": Color("c6ad72"), "grain": Color("e4dec0")}
const CLAY := {"ink": Color("30251f"), "face": Color("be7961"), "light": Color("e0ad87"), "side": Color("884f40"), "dark": Color("59392f"), "gold": Color("d1b176"), "grain": Color("efcfaa")}

var kind := "shield"
var enemy := false
var pose := 0.0:
	set(value):
		pose = clampf(value, 0.0, 1.0)
		queue_redraw()
var shot_progress := -1.0:
	set(value):
		shot_progress = value
		queue_redraw()
var _local := Transform2D.IDENTITY
var _stack: Array[Transform2D] = []
var _scale := 1.0
var _origin := Vector2.ZERO
var _alpha := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func configure(class_id: String, is_enemy: bool) -> void:
	kind = {"guard": "shield", "archer": "crossbow", "default": "shield"}.get(class_id, class_id)
	if kind not in ["shield", "crossbow", "assassin", "banner", "puppet", "devourer", "echo"]:
		kind = "shield"
	enemy = is_enemy
	visible = true
	queue_redraw()

func _draw() -> void:
	_scale = minf(size.y / 188.0, size.x / 108.0)
	if kind == "devourer":
		_scale = minf(size.y / 306.0, size.x / 130.0)
	elif kind == "echo":
		_scale = minf(size.y / 450.0, size.x / 132.0)
	_origin = Vector2(size.x * 0.5, size.y - 2.0)
	_local = Transform2D.IDENTITY
	_stack.clear()
	_alpha = 1.0
	var palette: Dictionary = CLAY if enemy else JADE
	var eased := pose * pose * (3.0 - 2.0 * pose)
	match kind:
		"shield": _shield(palette, eased)
		"crossbow": _crossbow(palette, eased)
		"assassin": _assassin(palette, eased)
		"banner": _banner(palette, eased)
		"puppet": _puppet(palette, eased)
		"devourer": _devourer(palette, eased)
		"echo": _echo(palette, eased)
	if kind == "crossbow" and shot_progress >= 0.0 and shot_progress < 1.0:
		_alpha = minf(1.0, (1.0 - shot_progress) / 0.18)
		var tip := 49.0 + 155.0 * shot_progress
		_stroke([[tip-20,-115],[tip-11,-115]], palette.gold, 1.4)
		_polygon([[tip,-115],[tip-5,-118],[tip-14,-115],[tip-5,-112]], palette.light, palette.ink, 1.0)

func _devourer(p: Dictionary, t: float) -> void:
	# Two-cell stone beast: a hollow jade maw, heavy claws and a horned crown.
	# Its silhouette stretches through both occupied cells, not a scaled pawn.
	var stone := {"ink": p.ink, "face": Color("8f7765"), "light": Color("c4ad86"), "side": Color("635143"), "dark": Color("3d3431"), "gold": p.gold, "grain": p.grain}
	_foot(stone)
	_slab([[-48,-10],[-51,-29],[-35,-48],[-15,-41],[-16,-14]], stone, true, 4)
	_slab([[13,-14],[14,-44],[38,-53],[55,-27],[49,-9]], stone, false, 5)
	for x in [-43, -30, 28, 42]:
		_polygon([[x-5,-16],[x,-6],[x+5,-19]], p.light, p.ink, 1)
	_push()
	_translate(5*t, -5*t)
	_slab([[-43,-48],[-55,-102],[-50,-195],[-32,-247],[31,-254],[54,-209],[53,-113],[37,-46]], stone, false, 6)
	# Armour flanges and chained forearms flank the open chest.
	_slab([[-39,-219],[-59,-211],[-62,-158],[-48,-140],[-39,-167]], stone, true, 4)
	_slab([[38,-224],[59,-211],[62,-157],[48,-133],[40,-173]], stone, false, 4)
	_polygon([[-56,-163],[-61,-130],[-49,-110],[-45,-143]], p.dark, p.gold, 1)
	_polygon([[51,-159],[61,-128],[48,-107],[43,-140]], p.dark, p.gold, 1)
	# Deep hexagonal mouth with two rows of teeth and a swallowed SP crystal.
	_polygon([[-31,-204],[0,-229],[34,-205],[37,-127],[0,-84],[-36,-130]], p.ink, p.gold, 3)
	_polygon([[-22,-191],[1,-209],[24,-190],[25,-136],[1,-111],[-25,-139]], Color("102b2a"), stone.side, 2)
	for i in 5:
		var x := -24.0 + i * 12.0
		_polygon([[x-4,-197],[x+4,-198],[x+1,-179-3*t]], stone.light, p.ink, 1)
		_polygon([[x-4,-127],[x+4,-126],[x,-145+3*t]], stone.light, p.ink, 1)
	_polygon([[-12,-158],[0,-177],[14,-157],[0,-140]], Color("83c6b0"), p.gold, 1.5)
	_stroke([[-16,-156],[-24,-149],[-28,-155]], Color("83c6b0"), 1.2)
	_stroke([[17,-158],[24,-169],[29,-162]], Color("83c6b0"), 1.2)
	# Horns are swept upward; small ember eyes frame a sealed brow plate.
	_slab([[-30,-248],[-48,-268],[-47,-293],[-29,-270],[-18,-260]], stone, true, 3)
	_slab([[17,-261],[32,-276],[44,-299],[48,-267],[32,-247]], stone, false, 3)
	_slab([[-27,-251],[-16,-276],[14,-277],[30,-255],[13,-228],[-13,-229]], stone, false, 4)
	_polygon([[-22,-252],[-6,-247],[-10,-241],[-21,-245]], Color("f0b66b"), p.ink, 1)
	_polygon([[7,-247],[23,-255],[21,-247],[11,-240]], Color("f0b66b"), p.ink, 1)
	_stroke([[-27,-66],[-7,-56],[15,-67],[29,-58]], p.gold, 1.2)
	_pop()


func _echo(p: Dictionary, t: float) -> void:
	# Three-cell resonator: three suspended masks around an exposed ringing core.
	var stone := {"ink": Color("29272e"), "face": Color("9389a0"), "light": Color("c7bad0"), "side": Color("625a74"), "dark": Color("3a354b"), "gold": p.gold, "grain": Color("ded3df")}
	_foot(stone)
	_slab([[-35,-14],[-45,-37],[-23,-62],[24,-63],[45,-37],[34,-14]], stone, true, 5)
	_slab([[-14,-54],[-20,-91],[-12,-114],[13,-112],[21,-91],[14,-54]], stone, false, 4)
	var glow := Color("b8cbce")
	for i in 3:
		var y := -153.0 - i * 104.0
		var radius := 43.0 + t * 6.0
		var ring: Array = []
		for j in 33:
			var angle := TAU * float(j) / 32.0
			ring.append([cos(angle)*radius, y+sin(angle)*25.0])
		_stroke(ring, Color(glow, 0.28+0.12*t), 1.2)
	# A long brass spine makes the three segments one continuous entity.
	_stroke([[0,-64],[0,-401]], stone.ink, 8)
	_stroke([[0,-69],[0,-403]], p.gold, 2)
	for i in 3:
		var y := -150.0 - i * 104.0
		_push()
		_translate((1.0 if i % 2 == 0 else -1.0) * 4.0*t, y)
		_slab([[-31,-35],[-10,-54],[16,-50],[35,-25],[28,28],[0,44],[-29,23]], stone, i == 1, 4)
		_polygon([[-23,-22],[-6,-17],[-10,-7],[-22,-11]], glow, stone.ink, 1)
		_polygon([[5,-17],[23,-26],[22,-12],[10,-7]], glow, stone.ink, 1)
		_polygon([[-10,9],[0,3],[11,9],[9,25],[0,30],[-9,25]], stone.ink, p.gold, 1.5)
		_stroke([[-26,-31],[-37,-46],[-49,-40],[-54,-16]], p.gold, 1.4)
		_stroke([[28,-31],[39,-44],[49,-37],[54,-8]], p.gold, 1.4)
		_polygon([[-52,-11],[-57,3],[-47,16],[-43,0]], stone.side, stone.ink, 1.5)
		_polygon([[52,-4],[60,11],[48,24],[44,7]], stone.light, stone.ink, 1.5)
		_pop()
	_slab([[-20,-405],[0,-441],[22,-407],[0,-392]], stone, false, 4)
	_polygon([[-7,-413],[0,-430],[8,-411],[0,-404]], glow, p.gold, 1)
	_stroke([[-31,-88],[-44,-68],[-34,-46]], p.gold, 1.3)
	_stroke([[30,-91],[43,-69],[33,-47]], p.gold, 1.3)


func _point(value: Array) -> Vector2:
	var v := _local * Vector2(float(value[0]), float(value[1]))
	return _origin + Vector2(-v.x if enemy else v.x, v.y) * _scale

func _points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for v: Array in values:
		result.append(_point(v))
	return result

func _polygon(points: Array, fill: Color, outline: Color = Color.TRANSPARENT, width: float = 2.0) -> void:
	var vertices := _points(points)
	var color := fill
	color.a *= _alpha
	draw_colored_polygon(vertices, color)
	if outline.a > 0.0:
		vertices.append(vertices[0])
		outline.a *= _alpha
		draw_polyline(vertices, outline, maxf(0.5, width * _scale), true)

func _stroke(points: Array, color: Color, width: float = 1.4) -> void:
	color.a *= _alpha
	draw_polyline(_points(points), color, maxf(0.5, width * _scale), true)

func _slab(points: Array, p: Dictionary, muted: bool = false, depth: float = 6.0) -> void:
	var back: Array = []
	for v: Array in points:
		back.append([v[0] - depth, v[1] - depth * 0.62])
	_polygon(back, p.dark, p.ink, 2.6)
	for i in points.size():
		var n := (i + 1) % points.size()
		_polygon([back[i], back[n], points[n], points[i]], p.light if points[n][0] > points[i][0] else p.side, p.ink, 1.1)
	var colors := PackedColorArray()
	for v: Array in points:
		var f := clampf(Vector2(float(v[0])+35.0, float(v[1])+170.0).dot(Vector2(70,160)) / 30500.0, 0.0, 1.0)
		var top: Color = p.side if muted else p.light
		var middle: Color = p.side if muted else p.face
		var bottom: Color = p.dark if muted else p.side
		colors.append(top.lerp(middle, f / 0.3) if f < 0.3 else middle.lerp(bottom, (f-0.3)/0.7))
	draw_polygon(_points(points), colors)
	var outline := points.duplicate()
	outline.append(points[0])
	_stroke(outline, p.ink, 2.4)
	# Same fixed mineral grain and LCG as the HTML; no gameplay RNG is consumed.
	var boundary := PackedVector2Array()
	for v: Array in points:
		boundary.append(Vector2(v[0], v[1]))
	var seed_value: int = 3907
	var grain_color: Color = p.grain
	grain_color.a = 0.10
	for i in 180:
		seed_value = (seed_value * 1664525 + 1013904223) & 0xffffffff
		var px := -58.0 + float(seed_value % 1170) / 10.0
		seed_value = (seed_value * 1664525 + 1013904223) & 0xffffffff
		var py := -182.0 + float(seed_value % 1800) / 10.0
		if Geometry2D.is_point_in_polygon(Vector2(px,py), boundary):
			draw_circle(_point([px,py]), maxf(0.20, 0.4 * _scale), grain_color)

func _push() -> void:
	_stack.append(_local)

func _pop() -> void:
	_local = _stack.pop_back()

func _translate(x: float, y: float) -> void:
	_local = _local * Transform2D(0.0, Vector2(x,y))

func _rotate(angle: float) -> void:
	_local = _local * Transform2D(angle, Vector2.ZERO)

func _transform(a: float, b: float, c: float, d: float, x: float, y: float) -> void:
	_local = _local * Transform2D(Vector2(a,b), Vector2(c,d), Vector2(x,y))

func _foot(p: Dictionary) -> void:
	_slab([[-33,-15],[-16,-32],[20,-28],[36,-12],[29,-2],[-29,-2]], p, true, 3)
	_stroke([[-26,-12],[25,-12]], p.face, 1.3)

func _puppet_joint(point: Array, radius: float, p: Dictionary) -> void:
	draw_circle(_point(point), radius * _scale, p.ink)
	draw_circle(_point(point), (radius - 1.7) * _scale, p.gold)
	draw_circle(_point(point), maxf(1.0, radius - 4.0) * _scale, p.dark)
	_stroke([[point[0]-1.5,point[1]-2],[point[0]+1.5,point[1]+2]], p.light, 1.1)

func _puppet(p: Dictionary, t: float) -> void:
	# Suspended wooden automaton: exposed hinges, separated limbs, open bronze
	# rib cage and a suspended core. Shared projection keeps enemy mirroring,
	# action tween and the host's dead-state modulation identical to other pieces.
	var wood := {"ink": p.ink, "face": Color("997e52"), "light": Color("c7ac76"), "side": Color("715c3e"), "dark": Color("493e2e"), "gold": p.gold, "grain": p.grain}
	var string_color: Color = p.gold
	string_color.a = 0.64
	# Slim controller crossbar above the head, with four taut marionette threads.
	_stroke([[-38,-176],[37,-170]], p.ink, 5)
	_stroke([[-38,-177],[37,-171]], p.gold, 2.4)
	_stroke([[-8,-183],[8,-165]], p.dark, 4.2)
	_stroke([[-8,-184],[8,-166]], p.gold, 1.4)
	_stroke([[-32,-176],[-34+3*t,-94-5*t]], string_color, 1)
	_stroke([[30,-172],[34+7*t,-107-7*t]], string_color, 1)
	_stroke([[-14,-174],[-15+2*t,-120]], string_color, 0.8)
	_stroke([[15,-172],[19+2*t,-120]], string_color, 0.8)
	# Split wooden feet and shins leave an unmistakable gap below the pelvis.
	_slab([[-18,-56],[-7,-56],[-9,-31],[-19,-12],[-30,-10],[-29,-18],[-20,-34]], wood, true, 3)
	_slab([[10,-56],[20,-53],[24,-28],[36,-13],[32,-7],[17,-10],[12,-28]], wood, false, 3)
	_polygon([[-29,-15],[-14,-17],[-12,-8],[-32,-6],[-35,-10]], p.dark, p.ink, 1.8)
	_polygon([[19,-13],[34,-15],[41,-9],[38,-4],[19,-5]], p.side, p.ink, 1.8)
	_puppet_joint([-15,-33], 5.4, p)
	_puppet_joint([18,-30], 5.4, p)
	_stroke([[-23,-22],[-20,-27]], wood.light, 1.2)
	_stroke([[26,-22],[23,-27]], wood.light, 1.2)
	_push()
	_translate(3*t, -2*t)
	# Pendulous arms are wood links with visible round bronze hinge pins.
	_slab([[-23,-117],[-32,-112],[-39,-92],[-31,-86],[-23,-106]], wood, true, 2.4)
	_slab([[-35,-88],[-27,-87],[-25,-64],[-33,-61],[-38,-73]], wood, false, 2.4)
	_puppet_joint([-33,-91], 6.2, p)
	_polygon([[-33,-65],[-24,-66],[-20,-58],[-24,-51],[-29,-55],[-34,-53],[-38,-59]], p.dark, p.ink, 2)
	_stroke([[-29,-62],[-27,-57]], p.gold, 1.5)
	_push()
	_translate(7*t, -7*t)
	_slab([[23,-119],[32,-116],[38,-103],[31,-96],[23,-108]], wood, false, 2.4)
	_slab([[33,-99],[41,-99],[45,-80],[39,-72],[32,-77]], wood, false, 2.4)
	_puppet_joint([34,-102], 6.2, p)
	_polygon([[35,-76],[43,-78],[49,-69],[45,-62],[39,-66],[35,-63],[31,-70]], p.side, p.ink, 2)
	_stroke([[39,-72],[42,-67]], p.gold, 1.5)
	_pop()
	# Angular pelvis and narrow exposed spine avoid a robe/armour silhouette.
	_slab([[-6,-86],[6,-86],[8,-65],[-6,-65]], wood, true, 2)
	_slab([[-19,-70],[0,-74],[21,-67],[17,-54],[3,-59],[-12,-54],[-22,-61]], p, false, 3)
	_puppet_joint([-12,-57], 5, p)
	_puppet_joint([15,-56], 5, p)
	# Open chest: dark cavity bounded by wooden uprights and bronze ribs.
	_polygon([[-19,-121],[15,-125],[26,-114],[21,-87],[2,-77],[-19,-89],[-25,-110]], p.ink, p.ink, 2)
	_slab([[-22,-118],[-15,-121],[-11,-92],[-4,-83],[-17,-88],[-24,-107]], wood, false, 2.2)
	_slab([[15,-123],[24,-116],[21,-94],[8,-83],[11,-96]], wood, true, 2.2)
	_polygon([[-17,-121],[4,-129],[22,-119],[16,-113],[-1,-119],[-14,-114]], p.side, p.ink, 1.5)
	_stroke([[-13,-112],[-2,-109],[15,-115]], p.gold, 2.4)
	_stroke([[-11,-94],[0,-88],[14,-97]], p.gold, 2.4)
	# Large luminous diamond stays legible when the entire piece is 40 px wide.
	_polygon([[0,-113],[10,-103],[1,-92],[-9,-101]], p.gold, p.ink, 2)
	_polygon([[0,-109],[6,-103],[0,-96],[-5,-102]], p.light)
	_stroke([[0,-117],[0,-113]], p.gold, 1.4)
	_puppet_joint([-24,-116], 5.5, p)
	_puppet_joint([25,-117], 5.5, p)
	# Small carved mask, single horizontal inset eye and exposed neck peg.
	_slab([[-4,-139],[4,-139],[5,-126],[-4,-125]], wood, true, 2)
	_slab([[-13,-159],[6,-162],[16,-151],[12,-134],[-1,-130],[-14,-140]], wood, false, 3)
	_polygon([[4,-159],[13,-151],[10,-137],[2,-133],[2,-145]], wood.side)
	_polygon([[-11,-151],[12,-153],[11,-147],[-10,-145]], p.ink)
	_stroke([[-7,-148],[5,-150]], p.light, 2.2)
	_stroke([[-7,-138],[3,-139]], p.dark, 1.5)
	_stroke([[-10,-157],[-6,-152]], wood.grain, 1.1)
	# One faction-coloured cloth tab accentuates the mechanical asymmetry.
	_polygon([[10,-122],[17,-120],[26,-131],[23,-121],[30,-116],[16,-114]], p.face, p.ink, 1.1)
	_pop()

func _shield(p: Dictionary, t: float) -> void:
	_foot(p)
	_push()
	_transform(1, 0, -0.095 * t, 1 - 0.025 * t, 0, 0)
	_slab([[-34,-127],[-17,-158],[4,-149],[11,-45],[-17,-13],[-33,-27]], p, true)
	_slab([[0,-159],[32,-148],[40,-105],[28,-51],[4,-16],[-12,-48],[-13,-117]], p)
	_polygon([[0,-156],[9,-146],[16,-97],[4,-22],[-8,-49],[-9,-115]], p.side)
	_stroke([[3,-151],[29,-143],[36,-105],[25,-56]], p.light, 1.8)
	_polygon([[6,-121],[31,-115],[32,-107],[7,-113]], p.gold)
	_stroke([[14,-80],[11,-65]], p.ink, 1.25)
	_pop()

func _crossbow(p: Dictionary, t: float) -> void:
	_slab([[-25,-3],[-30,-16],[-20,-61],[-6,-83],[13,-73],[7,-29],[24,-9],[20,-3]], p, true, 4)
	_polygon([[-6,-79],[9,-72],[2,-30],[-20,-10],[-23,-16],[-14,-57]], p.side)
	_stroke([[-19,-8],[17,-8]], p.face, 1.3)
	_push()
	_slab([[-37,-143],[-14,-158],[20,-145],[48,-125],[40,-119],[-13,-132],[-35,-125]], p, false, 4)
	_polygon([[-33,-141],[-14,-154],[20,-142],[44,-125],[-7,-142]], p.light)
	_polygon([[-7,-142],[44,-125],[39,-122],[-13,-134],[-32,-128]], p.side)
	_stroke([[-20,-132],[-8,-135]], p.gold, 2.1)
	_pop()
	_push()
	_slab([[-33,-94],[-12,-106],[38,-108],[46,-101],[1,-74],[-28,-76]], p, false, 4)
	_polygon([[-28,-94],[-11,-102],[37,-105],[41,-101],[-5,-88]], p.light)
	_polygon([[-5,-88],[41,-101],[0,-77],[-25,-79]], p.side)
	_stroke([[-20,-99],[-8,-104]], p.gold, 2.1)
	_pop()

func _assassin(p: Dictionary, t: float) -> void:
	_push()
	_transform(1, 0, -0.055 * t, 1, 0, 0)
	_slab([[-8,-3],[-16,-17],[-21,-55],[-12,-90],[-2,-99],[-6,-57],[3,-19],[0,-3]], p, true, 2)
	_polygon([[-12,-86],[-4,-96],[-10,-56],[-2,-18],[0,-5],[-5,-12],[-16,-55]], p.face)
	_stroke([[-5,-10],[-2,-4]], p.light, 1.2)
	_pop()
	_push()
	_translate(-2 + 6 * t, -129 + 3 * t)
	_rotate(0.095 * t)
	_translate(2, 129)
	_slab([[-28,-116],[-19,-149],[11,-167],[22,-157],[-4,-130],[-12,-105]], p, false, 2.2)
	_polygon([[-19,-147],[11,-165],[16,-158],[-8,-136],[-25,-119]], p.light)
	_polygon([[-8,-136],[16,-158],[20,-157],[-4,-130],[-12,-108]], p.side)
	_stroke([[-18,-139],[-10,-145]], p.gold, 2.2)
	_pop()
	_push()
	_translate(17 + 12 * t, -102 + 5 * t)
	_rotate(0.11 * t)
	_translate(-17, 102)
	_slab([[32,-143],[39,-125],[18,-78],[3,-63],[9,-101]], p, false, 2)
	_polygon([[32,-140],[35,-124],[14,-80],[5,-66],[15,-100]], p.light)
	_polygon([[35,-124],[37,-125],[17,-79],[5,-66],[14,-80]], p.side)
	_pop()

func _banner(p: Dictionary, t: float) -> void:
	_foot(p)
	_push()
	_transform(1, 0, -0.028 * t, 1, 0, 0)
	_slab([[-20,-16],[-22,-171],[-15,-179],[-7,-174],[0,-17]], p, true, 4)
	_stroke([[-14,-170],[-8,-28]], p.gold, 2)
	var lift := 5 * t
	_slab([[-8,-165],[43,-159-lift],[51,-117-lift],[26,-125-lift],[-5,-111]], p, false, 5)
	_polygon([[-5,-160],[11,-148],[14,-121],[-3,-114]], p.side)
	_polygon([[11,-148],[43,-155-lift],[46,-132-lift],[24,-138]], p.face)
	_stroke([[-3,-160],[39,-155-lift]], p.light, 1.8)
	_stroke([[15,-147],[36,-141-lift]], p.gold, 3.5)
	_pop()
