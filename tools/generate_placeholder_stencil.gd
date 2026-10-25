extends SceneTree
## Draws the placeholder "sigil" stencil: one PNG per part.
## Run: Godot --headless --path . --script res://tools/generate_placeholder_stencil.gd

const SIZE: int = 512
const OUT_DIR: String = "res://data/stencils/sigil/"
const CENTER: Vector2 = Vector2(SIZE / 2.0, SIZE / 2.0)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_save("outer_ring", func(p: Vector2) -> bool: return _ring(p, 220.0, 245.0))
	_save("inner_ring", func(p: Vector2) -> bool: return _ring(p, 150.0, 168.0))
	_save("star", _star)
	_save("dots", _dots)
	quit()


func _save(part_name: String, inside: Callable) -> void:
	var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			if inside.call(Vector2(x + 0.5, y + 0.5)):
				image.set_pixel(x, y, Color.WHITE)
	image.save_png(OUT_DIR + part_name + ".png")


func _ring(p: Vector2, inner: float, outer: float) -> bool:
	var d: float = p.distance_to(CENTER)
	return d >= inner and d <= outer


## Pentagram: every second of five points on a circle joined by thick lines.
func _star(p: Vector2) -> bool:
	var points: Array[Vector2] = _circle_points(5, 140.0, -PI / 2.0)
	for i in 5:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 2) % 5]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
		if p.distance_to(closest) <= 8.0:
			return true
	return false


func _dots(p: Vector2) -> bool:
	for point in _circle_points(5, 194.0, PI / 2.0):
		if p.distance_to(point) <= 14.0:
			return true
	return false


func _circle_points(count: int, radius: float, start_angle: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i in count:
		var angle: float = start_angle + TAU * i / count
		points.append(CENTER + Vector2(cos(angle), sin(angle)) * radius)
	return points
