class_name InkCanvas
extends RefCounted
## Ink coverage of a stencil on a grid of `size` cells (`StencilData.grid_size`). Pure logic: no nodes, no input.
## Ink only lands inside the stencil. `texture` holds coverage (red channel, 0..1);
## call flush() once per frame to upload changes. What the player sees is drawn by InkPaint from `dabs` and `strokes`.

signal part_completed(index: int)

## Grid size in cells.
var size: Vector2i = Vector2i(256, 256)
var texture: ImageTexture
## The session's clock (seconds); the ink shader's ripple moves with it.
var time: float = 0.0
## Ellipses where ink can't land and the magnet doesn't pull, each inscribed in a rect, in cells.
var blocked: Array[Rect2] = []
## Every stamp since the look last took them, as [centre: Vector2, basis: Transform2D, amount: float] in cells,
## plus [radius_px, thickness] of the `InkBrush` for stamps made on a surface
## (`basis`: the brush in cells, x = along it times its half length, y = across it times its half thickness; on
## curved or stretched skin it is skewed). InkPaint redraws them at the screen's resolution. A stroke is kept as
## one segment in `strokes` instead. The look clears both.
var dabs: Array[Array] = []
## Strokes since the look last took them: [from: Vector2, to: Vector2, basis: Transform2D, amount: float], in cells
## (+ [radius_px, thickness] as for `dabs`).
var strokes: Array[Array] = []
var _in_stroke: bool = false
## Set when ink was taken off; the look wipes itself and clears this.
var cleared: bool = false

var _threshold: float
var _ink: PackedFloat32Array = PackedFloat32Array()
## Part index per cell, -1 outside the stencil.
var _part_of: PackedInt32Array = PackedInt32Array()
var _part_cells: Array[PackedInt32Array] = []
var _part_filled: PackedInt32Array = PackedInt32Array()
var _part_done: PackedByteArray = PackedByteArray()
var _pixels: PackedByteArray = PackedByteArray()
var _image: Image
var _dirty: bool = false


func _init(stencil: StencilData, completion_threshold: float = 0.97) -> void:
	_threshold = completion_threshold
	size = stencil.grid_size
	_build_parts(stencil)
	_ink.resize(size.x * size.y)
	_pixels.resize(size.x * size.y)
	_image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, _pixels)
	texture = ImageTexture.create_from_image(_image)


## Adds ink in a soft circle: full `amount` at the centre, half at the edge.
## `center` and `radius` are in cells. Cells outside the stencil are skipped.
## Returns the ink actually laid down, in filled-cell units.
func stamp(center: Vector2, radius: float, amount: float) -> float:
	var x0: int = maxi(0, floori(center.x - radius))
	var x1: int = mini(size.x - 1, ceili(center.x + radius))
	var y0: int = maxi(0, floori(center.y - radius))
	var y1: int = mini(size.y - 1, ceili(center.y + radius))
	var r2: float = radius * radius
	var laid: float = 0.0
	if not _in_stroke:
		dabs.append([center, Transform2D(Vector2(radius, 0.0), Vector2(0.0, radius), Vector2.ZERO), amount])
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * size.x + x
			if _part_of[cell] < 0:
				continue
			var point: Vector2 = Vector2(x + 0.5, y + 0.5)
			var d2: float = point.distance_squared_to(center)
			if d2 <= r2 and not _is_blocked(point):
				laid += _add_ink(cell, amount * (1.0 - 0.5 * d2 / r2))
	return laid


## Stamps along a segment. `amount` is split so ink per cell depends on how long
## the needle stays over it, not on how fast the mouse moves. Returns the ink laid down.
func stroke(from: Vector2, to: Vector2, radius: float, amount: float) -> float:
	var steps: int = maxi(1, ceili(from.distance_to(to) / (radius * 0.5)))
	var laid: float = 0.0
	strokes.append([from, to, Transform2D(Vector2(radius, 0.0), Vector2(0.0, radius), Vector2.ZERO), amount])
	_in_stroke = true
	for i in steps:
		laid += stamp(from.lerp(to, float(i + 1) / steps), radius, amount / steps)
	_in_stroke = false
	return laid


## Like stamp(), but with the needle's `brush` (a flat ellipse on screen) on skin that may be curved or stretched:
## every stencil cell near `center` (a cell) is placed on screen by `surface.project()`, which also says how
## much ink that skin takes (0 where it is hidden or turned away). Returns the ink laid down.
func stamp_on(surface: SkinSurface, center: Vector2, brush: InkBrush, amount: float) -> float:
	var middle: Vector3 = surface.project(center)
	var reach: Vector2 = surface.cells_within(center, brush.radius_px)   # the ellipse lies inside this circle
	var x0: int = maxi(0, floori(center.x - reach.x))
	var x1: int = mini(size.x - 1, ceili(center.x + reach.x))
	var y0: int = maxi(0, floori(center.y - reach.y))
	var y1: int = mini(size.y - 1, ceili(center.y + reach.y))
	var tip: Vector2 = Vector2(middle.x, middle.y)
	var dose: float = amount * brush.dose_scale()
	var laid: float = 0.0
	if not _in_stroke and middle.z > 0.0:
		dabs.append([center, _brush_basis(surface, center, brush), amount * middle.z, brush.radius_px, brush.thickness])
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * size.x + x
			if _part_of[cell] < 0:
				continue
			var point: Vector2 = Vector2(x + 0.5, y + 0.5)
			var placed: Vector3 = surface.project(point)
			if placed.z <= 0.0:
				continue
			var share: float = brush.weight(Vector2(placed.x, placed.y) - tip)
			if share > 0.0 and not _is_blocked(point):
				laid += _add_ink(cell, dose * placed.z * share)
	return laid


## stroke() for stamp_on(): from one skin cell to another, so ink follows the skin when it slides
## under a still needle too. Lays what stamps every half of the brush's thickness would (a thin brush leaves no
## gaps), but projects every cell it touches once: each cell sums only the stamps that can reach it, instead of
## every stamp walking its whole box (a fast stroke was dozens of stamps, thousands of projections a frame).
func stroke_on(surface: SkinSurface, from: Vector2, to: Vector2, brush: InkBrush, amount: float) -> float:
	var step_cells: float = maxf(0.5, brush.half_thickness() / surface.pixels_per_cell()) * 0.5
	var steps: int = mini(128, maxi(1, ceili(from.distance_to(to) / step_cells)))
	var facing: float = surface.project(to).z
	if facing > 0.0:
		strokes.append([from, to, _brush_basis(surface, to, brush), amount * facing, brush.radius_px, brush.thickness])
	# the stamps' centres on screen: the first one and the step between them (straight on screen; on curved skin a
	# short stroke bends by a hair)
	var first_tip: Vector3 = surface.project(from.lerp(to, 1.0 / steps))
	var last_tip: Vector3 = surface.project(to)
	var tip0: Vector2 = Vector2(first_tip.x, first_tip.y)
	var step_px: Vector2 = (Vector2(last_tip.x, last_tip.y) - tip0) / maxf(steps - 1, 1)
	# in the brush's ellipse units (InkBrush.weight(): full at the centre, half on the rim)
	var unit_along: Vector2 = brush.axis / brush.radius_px
	var unit_across: Vector2 = brush.across() / maxf(brush.half_thickness(), 0.001)
	var step_a: float = step_px.dot(unit_along)
	var step_b: float = step_px.dot(unit_across)
	var quad: float = step_a * step_a + step_b * step_b   # e(i) = quad i^2 - 2 lin i + const
	# every cell any stamp can reach: within the brush's reach (in cells) of the segment between the ends
	var reach: Vector2 = surface.cells_within(from, brush.radius_px).max(surface.cells_within(to, brush.radius_px))
	var reach_cells: float = maxf(reach.x, reach.y) + 1.0
	var low: Vector2 = from.min(to) - reach
	var high: Vector2 = from.max(to) + reach
	var x0: int = maxi(0, floori(low.x))
	var x1: int = mini(size.x - 1, ceili(high.x))
	var y0: int = maxi(0, floori(low.y))
	var y1: int = mini(size.y - 1, ceili(high.y))
	var dose: float = amount / steps * brush.dose_scale()
	var laid: float = 0.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * size.x + x
			if _part_of[cell] < 0:
				continue
			var point: Vector2 = Vector2(x + 0.5, y + 0.5)
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, from, to)) > reach_cells:
				continue   # out of every stamp's reach: no projection needed
			var placed: Vector3 = surface.project(point)
			if placed.z <= 0.0:
				continue
			# stamp i's offset in ellipse units is (pa - i step_a, pb - i step_b); its weight 1 - e(i) / 2 where
			# e(i) <= 1. The stamps inside are a run of i, and the sum of a quadratic over a run has a closed form.
			var offset: Vector2 = Vector2(placed.x, placed.y) - tip0
			var pa: float = offset.dot(unit_along)
			var pb: float = offset.dot(unit_across)
			var lin: float = pa * step_a + pb * step_b
			var const_e: float = pa * pa + pb * pb
			var share: float = 0.0
			if quad < 1e-9:
				if const_e <= 1.0:
					share = steps * (1.0 - 0.5 * const_e)
			else:
				var room: float = lin * lin - quad * (const_e - 1.0)
				if room >= 0.0:
					var root: float = sqrt(room)
					var i0: int = maxi(0, ceili((lin - root) / quad))
					var i1: int = mini(steps - 1, floori((lin + root) / quad))
					if i1 >= i0:
						var n: float = i1 - i0 + 1
						var sum_i: float = (float(i0) + i1) * n * 0.5
						var sum_i2: float = _sum_squares(i1) - _sum_squares(i0 - 1)
						share = n - 0.5 * (quad * sum_i2 - 2.0 * lin * sum_i + const_e * n)
			if share > 0.0 and not _is_blocked(point):
				laid += _add_ink(cell, dose * placed.z * share)
	return laid


## 0^2 + 1^2 + ... + n^2.
static func _sum_squares(n: int) -> float:
	return 0.0 if n < 0 else float(n) * (n + 1) * (2 * n + 1) / 6.0


## Centre of the nearest stencil cell that still needs ink, or Vector2.INF if none within `radius`.
## With a `surface`, only cells that take ink there now count (not hidden or turned away).
func find_unfilled_near(center: Vector2, radius: float, surface: SkinSurface = null) -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_d2: float = radius * radius
	var r: int = ceili(radius)
	var cx: int = floori(center.x)
	var cy: int = floori(center.y)
	for y in range(maxi(0, cy - r), mini(size.y, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(size.x, cx + r + 1)):
			var cell: int = y * size.x + x
			if _part_of[cell] < 0 or _ink[cell] >= 1.0:
				continue
			var point: Vector2 = Vector2(x + 0.5, y + 0.5)
			var d2: float = point.distance_squared_to(center)
			if d2 < best_d2 and not _is_blocked(point) and (surface == null or surface.project(point).z >= 0.5):
				best_d2 = d2
				best = point
	return best


## Uploads changed cells to `texture`.
func flush() -> void:
	if _dirty:
		_image.set_data(size.x, size.y, false, Image.FORMAT_R8, _pixels)
		texture.update(_image)
		_dirty = false


func part_count() -> int:
	return _part_cells.size()


func part_progress(index: int) -> float:
	return float(_part_filled[index]) / maxi(1, _part_cells[index].size())


func is_part_done(index: int) -> bool:
	return _part_done[index] == 1


func total_progress() -> float:
	var filled: int = 0
	var total: int = 0
	for i in part_count():
		filled += _part_filled[i]
		total += _part_cells[i].size()
	return float(filled) / maxi(1, total)


## Grid indices (y * size.x + x) of a part's cells.
func part_cells(index: int) -> PackedInt32Array:
	return _part_cells[index]


## Ink in one cell (grid index), 0..1.
func cell_ink(cell: int) -> float:
	return _ink[cell]


func is_complete() -> bool:
	return not _part_done.has(0)


## Whether `cell` (in cells, fractions allowed) is part of the stencil.
func is_stencil(cell: Vector2) -> bool:
	var x: int = floori(cell.x)
	var y: int = floori(cell.y)
	return x >= 0 and y >= 0 and x < size.x and y < size.y and _part_of[y * size.x + x] >= 0


## Takes all ink off every part.
func clear() -> void:
	for part in part_count():
		clear_part(part)


## Takes all ink off a part, done or not.
func clear_part(index: int) -> void:
	cleared = true
	for cell in _part_cells[index]:
		_set_ink(cell, 0.0)
	_part_filled[index] = 0
	_part_done[index] = 0


## The brush at `cell` in cells, for the look.
func _brush_basis(surface: SkinSurface, cell: Vector2, brush: InkBrush) -> Transform2D:
	return surface.brush_basis(cell, brush.axis * brush.radius_px, brush.across() * brush.half_thickness())


func _is_blocked(point: Vector2) -> bool:
	for rect in blocked:
		var offset: Vector2 = (point - rect.get_center()) / (rect.size * 0.5)
		if offset.length_squared() <= 1.0:
			return true
	return false


func _add_ink(cell: int, amount: float) -> float:
	var before: float = _ink[cell]
	if before >= 1.0:
		return 0.0
	var after: float = minf(1.0, before + amount)
	_set_ink(cell, after)
	if after >= 1.0:
		var part: int = _part_of[cell]
		_part_filled[part] += 1
		_check_part(part)
	return after - before


func _set_ink(cell: int, value: float) -> void:
	_ink[cell] = value
	_pixels[cell] = roundi(value * 255.0)
	_dirty = true


func _check_part(part: int) -> void:
	if _part_done[part] == 1 or part_progress(part) < _threshold:
		return
	_part_done[part] = 1
	# Like PowerWash: the last specks are filled for the player.
	for cell in _part_cells[part]:
		if _ink[cell] < 1.0:
			_set_ink(cell, 1.0)
	_part_filled[part] = _part_cells[part].size()
	part_completed.emit(part)


func _build_parts(stencil: StencilData) -> void:
	_part_of.resize(size.x * size.y)
	_part_of.fill(-1)
	for index in stencil.parts.size():
		var image: Image = stencil.parts[index].texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
		for y in size.y:
			for x in size.x:
				if image.get_pixel(x, y).a > 0.5:
					_part_of[y * size.x + x] = index # later parts win where parts overlap

	for index in stencil.parts.size():
		var cells: PackedInt32Array = PackedInt32Array()
		for cell in size.x * size.y:
			if _part_of[cell] == index:
				cells.append(cell)
		_part_cells.append(cells)
	_part_filled.resize(_part_cells.size())
	_part_done.resize(_part_cells.size())
