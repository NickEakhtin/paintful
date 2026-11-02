extends Node2D
## Placeholder look of an Eye: almond-shaped lids over a white with an amber iris, lashes on top.
## Shut, it's just the lid line with lashes and a faint crease. Swap this node for sprites later;
## it only reads the parent's state (`openness`, `presence`, `tremble`, `gaze`, `alarmed`, `flinch`).

const OUTLINE: Color = Color(0.2, 0.1, 0.09)
const WHITE: Color = Color(0.95, 0.92, 0.86)
const CORNER_PINK: Color = Color(0.88, 0.62, 0.6)
const IRIS: Color = Color(0.62, 0.36, 0.08)
const IRIS_RIM: Color = Color(0.3, 0.14, 0.03)
const PUPIL: Color = Color(0.03, 0.02, 0.02)
const VEIN: Color = Color(0.75, 0.08, 0.08)
## Points along each lid.
const STEPS: int = 24
const LASHES: int = 7

## Each eye trembles to its own beat.
var _seed: float = randf() * 100.0
## Per vein: x = where it starts along the width (-1..1, at a corner), y = how it bends.
var _veins: Array[Vector2] = []

@onready var _eye: Eye = get_parent()


func _ready() -> void:
	for i in 5:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_veins.append(Vector2(side * randf_range(0.8, 0.98), randf_range(-0.5, 0.5)))


func _draw() -> void:
	var half: Vector2 = _eye.size * 0.5
	var time: float = Time.get_ticks_msec() / 1000.0 + _seed
	# The warning: the lid quivers and opens a crack now and then.
	var shake: float = _eye.tremble * sin(time * 47.0) * 1.6
	var crack: float = _eye.tremble * 0.07 * maxf(0.0, sin(time * 23.0))
	# A poked eye winces: the lids narrow for a moment.
	var open: float = maxf(_eye.openness * (1.0 - 0.4 * _eye.flinch), crack)
	modulate.a = _eye.presence

	var upper: PackedVector2Array = PackedVector2Array()
	var lower: PackedVector2Array = PackedVector2Array()
	for i in STEPS + 1:
		var x: float = lerpf(-1.0, 1.0, float(i) / STEPS)
		var shape: float = pow(1.0 - x * x, 0.75)
		var shut: float = half.y * 0.22 * (1.0 - x * x) # the closed lid sags a little
		upper.append(Vector2(x * half.x, lerpf(shut, -half.y * shape, open) + shake))
		lower.append(Vector2(x * half.x, lerpf(shut, half.y * 0.85 * shape, open) + shake))

	if open > 0.01:
		var white: PackedVector2Array = upper.duplicate()
		var back: PackedVector2Array = lower.duplicate()
		back.reverse()
		white.append_array(back.slice(1, back.size() - 1))
		_draw_open(white, half)
		draw_polyline(lower, OUTLINE, 2.5, true)
		draw_polyline(upper, OUTLINE, 4.5, true)
	else:
		# The crease above a shut eye.
		var crease: PackedVector2Array = PackedVector2Array()
		for i in range(3, STEPS - 2):
			crease.append(upper[i] + Vector2(0.0, -half.y * 0.45 * (1.0 - absf(lerpf(-1.0, 1.0, float(i) / STEPS)))))
		draw_polyline(crease, Color(OUTLINE, 0.25), 2.0, true)
		draw_polyline(upper, OUTLINE, 4.0, true)
	_draw_lashes(upper, open, time)


func _draw_open(white: PackedVector2Array, half: Vector2) -> void:
	var colors: PackedColorArray = PackedColorArray()
	for point in white:
		colors.append(CORNER_PINK.lerp(WHITE, clampf(1.6 - absf(point.x) / half.x * 1.6, 0.0, 1.0)))
	draw_polygon(white, colors)

	# Veins from the corners; many and bright when the skin under it is red.
	var red: float = 1.0 if _eye.alarmed else _eye.flinch
	var vein_color: Color = Color(VEIN, lerpf(0.3, 0.9, red))
	for vein in _veins:
		var start: Vector2 = Vector2(vein.x * half.x, vein.y * half.y * 0.4)
		var end: Vector2 = Vector2(vein.x * half.x * 0.45, vein.y * half.y * 0.6)
		var mid: Vector2 = start.lerp(end, 0.5) + Vector2(0.0, vein.y * 6.0)
		_clipped_line(PackedVector2Array([start, mid, end]), white, vein_color, lerpf(1.0, 1.8, red))

	var iris_radius: float = half.y * 0.72
	var center: Vector2 = _eye.gaze * Vector2(half.x - iris_radius * 1.1, half.y * 0.3)
	_clipped_circle(center, iris_radius + 2.0, white, IRIS_RIM)
	_clipped_circle(center, iris_radius, white, IRIS)
	_clipped_circle(center, iris_radius * 0.45 * (1.0 - 0.45 * _eye.flinch), white, PUPIL)
	_clipped_circle(center + Vector2(-0.35, -0.4) * iris_radius, iris_radius * 0.16, white, Color(1, 1, 1, 0.9))
	if _eye.alarmed:
		draw_polyline(white + PackedVector2Array([white[0]]), Color(VEIN, 0.8), 3.0, true)


func _draw_lashes(upper: PackedVector2Array, open: float, time: float) -> void:
	for i in LASHES:
		var t: float = lerpf(0.2, 0.8, float(i) / (LASHES - 1))
		var index: int = roundi(t * STEPS)
		var root: Vector2 = upper[index]
		var x: float = lerpf(-1.0, 1.0, t)
		# Up and outward when open, hanging down when shut; they twitch during the warning.
		var twitch: float = _eye.tremble * sin(time * 31.0 + i * 1.7) * 0.35
		var angle: float = lerpf(PI * 0.5 + x * 0.6, -PI * 0.5 + x * 0.9, open) + twitch
		var length: float = lerpf(9.0, 13.0, 1.0 - absf(x))
		draw_line(root, root + Vector2.from_angle(angle) * length, OUTLINE, 2.0, true)


## A filled circle cut to `shape`, so the iris never pokes out past the lids.
func _clipped_circle(center: Vector2, radius: float, shape: PackedVector2Array, color: Color) -> void:
	var circle: PackedVector2Array = PackedVector2Array()
	for i in 24:
		circle.append(center + Vector2.from_angle(TAU * i / 24.0) * radius)
	for piece in Geometry2D.intersect_polygons(circle, shape):
		draw_colored_polygon(piece, color)


func _clipped_line(line: PackedVector2Array, shape: PackedVector2Array, color: Color, width: float) -> void:
	for piece in Geometry2D.intersect_polyline_with_polygon(line, shape):
		if piece.size() >= 2:
			draw_polyline(piece, color, width, true)
