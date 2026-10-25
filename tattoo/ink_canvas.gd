class_name InkCanvas
extends RefCounted
## Ink coverage of a stencil on a square grid. Pure logic: no nodes, no input.
## Ink only lands inside the stencil. `texture` holds coverage (red channel, 0..1);
## call flush() once per frame to upload changes.

signal part_completed(index: int)

const SIZE: int = 256

var texture: ImageTexture

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
	_build_parts(stencil)
	_ink.resize(SIZE * SIZE)
	_pixels.resize(SIZE * SIZE)
	_image = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_R8, _pixels)
	texture = ImageTexture.create_from_image(_image)


## Adds ink in a soft circle: full `amount` at the centre, half at the edge.
## `center` and `radius` are in cells. Cells outside the stencil are skipped.
## Returns the ink actually laid down, in filled-cell units.
func stamp(center: Vector2, radius: float, amount: float) -> float:
	var x0: int = maxi(0, floori(center.x - radius))
	var x1: int = mini(SIZE - 1, ceili(center.x + radius))
	var y0: int = maxi(0, floori(center.y - radius))
	var y1: int = mini(SIZE - 1, ceili(center.y + radius))
	var r2: float = radius * radius
	var laid: float = 0.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * SIZE + x
			if _part_of[cell] < 0:
				continue
			var d2: float = Vector2(x + 0.5, y + 0.5).distance_squared_to(center)
			if d2 <= r2:
				laid += _add_ink(cell, amount * (1.0 - 0.5 * d2 / r2))
	return laid


## Stamps along a segment. `amount` is split so ink per cell depends on how long
## the needle stays over it, not on how fast the mouse moves. Returns the ink laid down.
func stroke(from: Vector2, to: Vector2, radius: float, amount: float) -> float:
	var steps: int = maxi(1, ceili(from.distance_to(to) / (radius * 0.5)))
	var laid: float = 0.0
	for i in steps:
		laid += stamp(from.lerp(to, float(i + 1) / steps), radius, amount / steps)
	return laid


## Centre of the nearest stencil cell that still needs ink, or Vector2.INF if none within `radius`.
func find_unfilled_near(center: Vector2, radius: float) -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_d2: float = radius * radius
	var r: int = ceili(radius)
	var cx: int = floori(center.x)
	var cy: int = floori(center.y)
	for y in range(maxi(0, cy - r), mini(SIZE, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(SIZE, cx + r + 1)):
			var cell: int = y * SIZE + x
			if _part_of[cell] < 0 or _ink[cell] >= 1.0:
				continue
			var point: Vector2 = Vector2(x + 0.5, y + 0.5)
			var d2: float = point.distance_squared_to(center)
			if d2 < best_d2:
				best_d2 = d2
				best = point
	return best


## Uploads changed cells to `texture`.
func flush() -> void:
	if _dirty:
		_image.set_data(SIZE, SIZE, false, Image.FORMAT_R8, _pixels)
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


func is_complete() -> bool:
	return not _part_done.has(0)


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
	_part_of.resize(SIZE * SIZE)
	_part_of.fill(-1)
	for index in stencil.parts.size():
		var image: Image = stencil.parts[index].texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
		for y in SIZE:
			for x in SIZE:
				if image.get_pixel(x, y).a > 0.5:
					_part_of[y * SIZE + x] = index # later parts win where parts overlap

	for index in stencil.parts.size():
		var cells: PackedInt32Array = PackedInt32Array()
		for cell in SIZE * SIZE:
			if _part_of[cell] == index:
				cells.append(cell)
		_part_cells.append(cells)
	_part_filled.resize(_part_cells.size())
	_part_done.resize(_part_cells.size())
