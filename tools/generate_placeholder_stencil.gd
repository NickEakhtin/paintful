extends SceneTree
## Draws the placeholder stencils (sigil, eye, moon, square): one PNG per part in data/stencils/<name>/.
## The shapes are laid out on a 512-unit square and drawn at OUT_SIZE pixels (2048: sharp on a 4K screen; real
## stencils follow the same rule, 2048 px per part, 4096 for big ones). Writes over existing files.
## Run: Godot --headless --path . --script res://tools/generate_placeholder_stencil.gd

const SIZE: int = 512
const OUT_SIZE: int = 2048
const OUT_DIR: String = "res://data/stencils/"
const CENTER: Vector2 = Vector2(SIZE / 2.0, SIZE / 2.0)


func _init() -> void:
	_save("sigil", "outer_ring", func(p: Vector2) -> bool: return _ring(p, CENTER, 220.0, 245.0))
	_save("sigil", "inner_ring", func(p: Vector2) -> bool: return _ring(p, CENTER, 150.0, 168.0))
	_save("sigil", "star", _star)
	_save("sigil", "dots", func(p: Vector2) -> bool: return _near_any(p, _circle_points(5, 194.0, PI / 2.0), 14.0))

	_save("eye", "outline", _eye_outline)
	_save("eye", "iris", func(p: Vector2) -> bool: return _ring(p, CENTER, 68.0, 92.0))
	_save("eye", "pupil", func(p: Vector2) -> bool: return p.distance_to(CENTER) <= 40.0)
	_save("eye", "lashes", _eye_lashes)

	_save("moon", "crescent", _crescent)
	_save("moon", "stars", func(p: Vector2) -> bool: return _near_any(p, [Vector2(300, 180), Vector2(340, 270), Vector2(290, 340)], 17.0))
	_save("moon", "dot_ring", func(p: Vector2) -> bool: return _near_any(p, _circle_points(12, 232.0, 0.0), 10.0))

	_save("square", "square", func(p: Vector2) -> bool: return absf(p.x - CENTER.x) <= 150.0 and absf(p.y - CENTER.y) <= 150.0)
	quit()


func _save(stencil: String, part_name: String, inside: Callable) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR + stencil)
	var image: Image = Image.create_empty(OUT_SIZE, OUT_SIZE, false, Image.FORMAT_RGBA8)
	var unit: float = float(SIZE) / OUT_SIZE
	for y in OUT_SIZE:
		for x in OUT_SIZE:
			if inside.call(Vector2(x + 0.5, y + 0.5) * unit):
				image.set_pixel(x, y, Color.WHITE)
	image.save_png("%s%s/%s.png" % [OUT_DIR, stencil, part_name])


func _ring(p: Vector2, center: Vector2, inner: float, outer: float) -> bool:
	var d: float = p.distance_to(center)
	return d >= inner and d <= outer


func _near_any(p: Vector2, points: Array, radius: float) -> bool:
	for point in points:
		if p.distance_to(point) <= radius:
			return true
	return false


## Pentagram: every second of five points on a circle joined by thick lines.
func _star(p: Vector2) -> bool:
	var points: Array[Vector2] = _circle_points(5, 140.0, -PI / 2.0)
	for i in 5:
		if _near_segment(p, points[i], points[(i + 2) % 5], 8.0):
			return true
	return false


## Almond eye shape: the overlap of two big circles; the outline is a band along its edge.
func _in_almond(p: Vector2, shrink: float) -> bool:
	var r: float = 300.0 - shrink
	return p.distance_to(CENTER + Vector2(0, 180)) <= r and p.distance_to(CENTER - Vector2(0, 180)) <= r


func _eye_outline(p: Vector2) -> bool:
	return _in_almond(p, 0.0) and not _in_almond(p, 22.0)


## Seven lashes fanning out above the upper lid.
func _eye_lashes(p: Vector2) -> bool:
	var lid_center: Vector2 = CENTER + Vector2(0, 180)
	for i in 7:
		var angle: float = -PI / 2.0 + (i - 3) * 0.17
		var start: Vector2 = lid_center + Vector2.from_angle(angle) * 312.0
		var end: Vector2 = lid_center + Vector2.from_angle(angle) * 362.0
		if _near_segment(p, start, end, 7.0):
			return true
	return false


func _crescent(p: Vector2) -> bool:
	return p.distance_to(CENTER) <= 185.0 and p.distance_to(CENTER + Vector2(70, -40)) > 165.0


func _near_segment(p: Vector2, a: Vector2, b: Vector2, width: float) -> bool:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= width


func _circle_points(count: int, radius: float, start_angle: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i in count:
		var angle: float = start_angle + TAU * i / count
		points.append(CENTER + Vector2(cos(angle), sin(angle)) * radius)
	return points
