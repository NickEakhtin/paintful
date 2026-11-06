extends Node2D
## The wet paper towel under the artist's left palm (drawn behind the hand), a soft sheet: a grid of points moved
## by verlet steps in the screen's pixels, its middle held by the fist, the rest dragging behind as the hand moves,
## swinging and settling back (each point is pulled toward its place in the flat sheet, the paper's stiffness);
## it creases where it's squeezed. Drawn with `wet_paper.gdshader`, staining redder as it wipes blood.

const WET_PAPER: Shader = preload("res://tattoo/blood/wet_paper.gdshader")
## Points across and down the sheet.
const COLUMNS: int = 9
const ROWS: int = 9
## The sheet in the hand's own pixels (the hand is scaled up; the sheet goes with it).
const SHEET: Rect2 = Rect2(-46.0, -30.0, 118.0, 112.0)
## Points this close to the palm's middle (hand pixels) are held by the fist.
const HELD_AT: Vector2 = Vector2(8.0, 4.0)
const HELD_RADIUS: float = 24.0
## Physics: steps per second, velocity kept per step, the pull back toward the flat sheet, constraint rounds.
const STEP: float = 1.0 / 120.0
const DAMPING: float = 0.95
const STIFFNESS: float = 0.006
const ROUNDS: int = 4

## How much blood it has taken, 0 .. 1.
var stained: float = 0.0:
	set(value):
		stained = clampf(value, 0.0, 1.0)
		if material != null:
			(material as ShaderMaterial).set_shader_parameter("stained", stained)

var _points: PackedVector2Array = PackedVector2Array()
var _previous: PackedVector2Array = PackedVector2Array()
var _rest: PackedVector2Array = PackedVector2Array()
var _held: PackedByteArray = PackedByteArray()
var _links: Array[Vector3i] = []   # point a, point b, rest length in hand pixels (as an int ×100)
var _uvs: PackedVector2Array = PackedVector2Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _time: float = 0.0
var _placed: bool = false


func _ready() -> void:
	show_behind_parent = true
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = WET_PAPER
	shader_material.set_shader_parameter("seed", Vector2(randf() * 40.0, randf() * 40.0))
	material = shader_material
	for y in ROWS:
		for x in COLUMNS:
			var uv: Vector2 = Vector2(float(x) / (COLUMNS - 1), float(y) / (ROWS - 1))
			var rest: Vector2 = SHEET.position + SHEET.size * uv
			# crumpled a little: each point off its place in the flat sheet, the corners drawn in
			rest += Vector2(sin(x * 2.7 + y * 1.3), cos(x * 1.9 - y * 2.4)) * 5.0
			rest = rest.lerp(HELD_AT, 0.12 * absf(uv.x - 0.5) * absf(uv.y - 0.5) * 4.0)
			_rest.append(rest)
			_uvs.append(uv)
			_held.append(1 if rest.distance_to(HELD_AT) < HELD_RADIUS else 0)
	for y in ROWS:
		for x in COLUMNS:
			var i: int = y * COLUMNS + x
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(2, 0), Vector2i(0, 2)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or nx >= COLUMNS or ny >= ROWS:
					continue
				var j: int = ny * COLUMNS + nx
				_links.append(Vector3i(i, j, roundi(_rest[i].distance_to(_rest[j]) * 100.0)))
			if x < COLUMNS - 1 and y < ROWS - 1:
				_indices.append_array([i, i + 1, i + COLUMNS, i + 1, i + COLUMNS + 1, i + COLUMNS])
	_points.resize(_rest.size())
	_previous.resize(_rest.size())
	visibility_changed.connect(func() -> void: _placed = false)


## Lays the sheet flat under the palm at once (a new towel).
func settle() -> void:
	_placed = false


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var to_screen: Transform2D = get_global_transform()
	if not _placed:
		for i in _rest.size():
			_points[i] = to_screen * _rest[i]
			_previous[i] = _points[i]
		_placed = true
	_time = minf(_time + delta, 0.1)
	var scale_px: float = to_screen.get_scale().x
	while _time >= STEP:
		_time -= STEP
		_step(to_screen, scale_px)
	queue_redraw()


func _step(to_screen: Transform2D, scale_px: float) -> void:
	for i in _points.size():
		var target: Vector2 = to_screen * _rest[i]
		if _held[i] == 1:
			_previous[i] = target
			_points[i] = target
			continue
		var p: Vector2 = _points[i]
		var moved: Vector2 = (p - _previous[i]) * DAMPING
		_previous[i] = p
		_points[i] = p + moved + (target - p) * STIFFNESS
	for round_i in ROUNDS:
		for link: Vector3i in _links:
			var a: Vector2 = _points[link.x]
			var b: Vector2 = _points[link.y]
			var between: Vector2 = b - a
			var length: float = between.length()
			var rest: float = link.z / 100.0 * scale_px
			if length < 0.0001:
				continue
			# paper doesn't stretch, but it folds easily: a link pushes back only half as hard when squeezed
			var error: float = (length - rest) / length * (0.5 if length > rest else 0.25)
			var shift: Vector2 = between * error
			var held_a: bool = _held[link.x] == 1
			var held_b: bool = _held[link.y] == 1
			if held_a and held_b:
				continue
			if held_a:
				_points[link.y] = b - shift * 2.0
			elif held_b:
				_points[link.x] = a + shift * 2.0
			else:
				_points[link.x] = a + shift
				_points[link.y] = b - shift


func _draw() -> void:
	if not _placed:
		return
	var from_screen: Transform2D = get_global_transform().affine_inverse()
	var local: PackedVector2Array = PackedVector2Array()
	local.resize(_points.size())
	var colours: PackedColorArray = PackedColorArray()
	colours.resize(_points.size())
	for i in _points.size():
		local[i] = from_screen * _points[i]
	# creases: where the sheet is squeezed (its neighbours closer than in the flat sheet) it shades darker
	for y in ROWS:
		for x in COLUMNS:
			var i: int = y * COLUMNS + x
			var squeeze: float = 0.0
			var count: int = 0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or nx >= COLUMNS or ny < 0 or ny >= ROWS:
					continue
				var j: int = ny * COLUMNS + nx
				var rest: float = _rest[i].distance_to(_rest[j])
				squeeze += clampf(1.0 - local[i].distance_to(local[j]) / rest, 0.0, 1.0)
				count += 1
			var shade: float = 1.0 - 0.9 * squeeze / maxf(count, 1)
			colours[i] = Color(shade, shade, shade, 1.0)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, local, colours, _uvs)
