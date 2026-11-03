class_name InkCanvas
extends RefCounted
## Ink coverage of a stencil on a grid of `size` cells (`StencilData.grid_size`). Pure logic: no nodes, no input.
## Ink only lands inside the stencil. `texture` holds coverage (red channel, 0..1),
## `inked_at_texture` when each cell last took ink (in `time` seconds, for the wet gloss);
## call flush() once per frame to upload changes.

signal part_completed(index: int)

## `inked_at` of cells that never took ink: long dry.
const NEVER: float = -10000.0

## Grid size in cells.
var size: Vector2i = Vector2i(256, 256)
var texture: ImageTexture
var inked_at_texture: ImageTexture
## Clock stamped on fresh ink; the session advances it.
var time: float = 0.0
## Ellipses where ink can't land and the magnet doesn't pull, each inscribed in a rect, in cells.
var blocked: Array[Rect2] = []

var _threshold: float
var _ink: PackedFloat32Array = PackedFloat32Array()
var _inked_at: PackedFloat32Array = PackedFloat32Array()
## Part index per cell, -1 outside the stencil.
var _part_of: PackedInt32Array = PackedInt32Array()
var _part_cells: Array[PackedInt32Array] = []
var _part_filled: PackedInt32Array = PackedInt32Array()
var _part_done: PackedByteArray = PackedByteArray()
var _pixels: PackedByteArray = PackedByteArray()
var _image: Image
var _dirty: bool = false
var _inked_at_dirty: bool = false


func _init(stencil: StencilData, completion_threshold: float = 0.97) -> void:
	_threshold = completion_threshold
	size = stencil.grid_size
	_build_parts(stencil)
	_ink.resize(size.x * size.y)
	_pixels.resize(size.x * size.y)
	_image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, _pixels)
	texture = ImageTexture.create_from_image(_image)
	_inked_at.resize(size.x * size.y)
	_inked_at.fill(NEVER)
	inked_at_texture = ImageTexture.create_from_image(_inked_at_image())


## Adds ink in a soft circle: full `amount` at the centre, half at the edge.
## `center` and `radius` are in cells. Cells outside the stencil are skipped.
## Every stencil cell under the needle turns wet again, already full ones too: fresh ink lies over old.
## Returns the ink actually laid down, in filled-cell units.
func stamp(center: Vector2, radius: float, amount: float) -> float:
	var x0: int = maxi(0, floori(center.x - radius))
	var x1: int = mini(size.x - 1, ceili(center.x + radius))
	var y0: int = maxi(0, floori(center.y - radius))
	var y1: int = mini(size.y - 1, ceili(center.y + radius))
	var r2: float = radius * radius
	var laid: float = 0.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * size.x + x
			if _part_of[cell] < 0:
				continue
			var point: Vector2 = Vector2(x + 0.5, y + 0.5)
			var d2: float = point.distance_squared_to(center)
			if d2 <= r2 and not _is_blocked(point):
				laid += _add_ink(cell, amount * (1.0 - 0.5 * d2 / r2))
				_mark_inked(cell)
	return laid


## Stamps along a segment. `amount` is split so ink per cell depends on how long
## the needle stays over it, not on how fast the mouse moves. Returns the ink laid down.
func stroke(from: Vector2, to: Vector2, radius: float, amount: float) -> float:
	var steps: int = maxi(1, ceili(from.distance_to(to) / (radius * 0.5)))
	var laid: float = 0.0
	for i in steps:
		laid += stamp(from.lerp(to, float(i + 1) / steps), radius, amount / steps)
	return laid


## Like stamp(), but the brush is a circle of `radius_px` on screen and the skin may be curved or stretched:
## every stencil cell near `center` (a cell) is placed on screen by `surface.project()`, which also says how
## much ink that skin takes (0 where it is hidden or turned away). Returns the ink laid down.
func stamp_on(surface: SkinSurface, center: Vector2, radius_px: float, amount: float) -> float:
	var middle: Vector3 = surface.project(center)
	var reach: Vector2 = surface.cells_within(center, radius_px)
	var x0: int = maxi(0, floori(center.x - reach.x))
	var x1: int = mini(size.x - 1, ceili(center.x + reach.x))
	var y0: int = maxi(0, floori(center.y - reach.y))
	var y1: int = mini(size.y - 1, ceili(center.y + reach.y))
	var tip: Vector2 = Vector2(middle.x, middle.y)
	var r2: float = radius_px * radius_px
	var laid: float = 0.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * size.x + x
			if _part_of[cell] < 0:
				continue
			var point: Vector2 = Vector2(x + 0.5, y + 0.5)
			var placed: Vector3 = surface.project(point)
			if placed.z <= 0.0:
				continue
			var d2: float = Vector2(placed.x, placed.y).distance_squared_to(tip)
			if d2 <= r2 and not _is_blocked(point):
				laid += _add_ink(cell, amount * placed.z * (1.0 - 0.5 * d2 / r2))
				_mark_inked(cell)
	return laid


## stroke() for stamp_on(): from one skin cell to another, so ink follows the skin when it slides
## under a still needle too.
func stroke_on(surface: SkinSurface, from: Vector2, to: Vector2, radius_px: float, amount: float) -> float:
	var radius_cells: float = maxf(0.5, radius_px / surface.pixels_per_cell())
	var steps: int = mini(64, maxi(1, ceili(from.distance_to(to) / (radius_cells * 0.5))))
	var laid: float = 0.0
	for i in steps:
		laid += stamp_on(surface, from.lerp(to, float(i + 1) / steps), radius_px, amount / steps)
	return laid


## Centre of the nearest stencil cell that still needs ink, or Vector2.INF if none within `radius`.
func find_unfilled_near(center: Vector2, radius: float) -> Vector2:
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
			if d2 < best_d2 and not _is_blocked(point):
				best_d2 = d2
				best = point
	return best


## Uploads changed cells to `texture`.
func flush() -> void:
	if _dirty:
		_image.set_data(size.x, size.y, false, Image.FORMAT_R8, _pixels)
		texture.update(_image)
		_dirty = false
	if _inked_at_dirty:
		inked_at_texture.update(_inked_at_image())
		_inked_at_dirty = false


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
	for cell in _part_cells[index]:
		_set_ink(cell, 0.0)
		_inked_at[cell] = NEVER
	_inked_at_dirty = true
	_part_filled[index] = 0
	_part_done[index] = 0


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


func _mark_inked(cell: int) -> void:
	_inked_at[cell] = time
	_inked_at_dirty = true


## Half floats filter on every GPU and are precise enough for a session-long clock.
func _inked_at_image() -> Image:
	var image: Image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, _inked_at.to_byte_array())
	image.convert(Image.FORMAT_RH)
	return image


func _check_part(part: int) -> void:
	if _part_done[part] == 1 or part_progress(part) < _threshold:
		return
	_part_done[part] = 1
	# Like PowerWash: the last specks are filled for the player.
	for cell in _part_cells[part]:
		if _ink[cell] < 1.0:
			_set_ink(cell, 1.0)
			_mark_inked(cell)
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
