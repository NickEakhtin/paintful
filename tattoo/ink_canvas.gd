class_name InkCanvas
extends RefCounted
## Ink coverage of a stencil on a square grid. Pure logic: no nodes, no input.
## The grid doubles as the ink texture; call flush() once per frame to upload changes.

signal part_completed(index: int)

const SIZE: int = 256

## Cells inked outside the stencil (and its edge tolerance) by at least half.
var mistakes: int = 0
var texture: ImageTexture

var _threshold: float
var _ink: PackedFloat32Array = PackedFloat32Array()
## Part index per cell, -1 outside the stencil.
var _part_of: PackedInt32Array = PackedInt32Array()
## 1 where ink is not a mistake: the stencil plus a band around it.
var _allowed: PackedByteArray = PackedByteArray()
var _part_cells: Array[PackedInt32Array] = []
var _part_filled: PackedInt32Array = PackedInt32Array()
var _part_done: PackedByteArray = PackedByteArray()
var _pixels: PackedByteArray = PackedByteArray()
var _image: Image
var _dirty: bool = false


func _init(stencil: StencilData, completion_threshold: float = 0.97,
		edge_tolerance: int = 2, ink_color: Color = Color(0.08, 0.06, 0.12)) -> void:
	_threshold = completion_threshold
	_build_parts(stencil)
	_build_allowed(edge_tolerance)

	_ink.resize(SIZE * SIZE)
	_pixels.resize(SIZE * SIZE * 4)
	for i in SIZE * SIZE:
		_pixels[i * 4] = ink_color.r8
		_pixels[i * 4 + 1] = ink_color.g8
		_pixels[i * 4 + 2] = ink_color.b8
	_image = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, _pixels)
	texture = ImageTexture.create_from_image(_image)


## Adds ink in a soft circle: full `amount` at the centre, half at the edge.
## `center` and `radius` are in cells.
func stamp(center: Vector2, radius: float, amount: float) -> void:
	var x0: int = maxi(0, floori(center.x - radius))
	var x1: int = mini(SIZE - 1, ceili(center.x + radius))
	var y0: int = maxi(0, floori(center.y - radius))
	var y1: int = mini(SIZE - 1, ceili(center.y + radius))
	var r2: float = radius * radius
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d2: float = Vector2(x + 0.5, y + 0.5).distance_squared_to(center)
			if d2 <= r2:
				_add_ink(y * SIZE + x, amount * (1.0 - 0.5 * d2 / r2))


## Stamps along a segment. `amount` is split so ink per cell depends on how long
## the needle stays over it, not on how fast the mouse moves.
func stroke(from: Vector2, to: Vector2, radius: float, amount: float) -> void:
	var steps: int = maxi(1, ceili(from.distance_to(to) / (radius * 0.5)))
	for i in steps:
		stamp(from.lerp(to, float(i + 1) / steps), radius, amount / steps)


## Uploads changed cells to `texture`.
func flush() -> void:
	if _dirty:
		_image.set_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, _pixels)
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


func stencil_cell_count() -> int:
	var total: int = 0
	for cells in _part_cells:
		total += cells.size()
	return total


func is_complete() -> bool:
	return not _part_done.has(0)


## White where the stencil still needs ink, for the "show what's left" highlight.
func make_remaining_image() -> Image:
	var data: PackedByteArray = PackedByteArray()
	data.resize(SIZE * SIZE * 4)
	for i in SIZE * SIZE:
		if _part_of[i] >= 0 and _ink[i] < 1.0:
			data[i * 4] = 255
			data[i * 4 + 1] = 255
			data[i * 4 + 2] = 255
			data[i * 4 + 3] = 255
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)


func _add_ink(cell: int, amount: float) -> void:
	var before: float = _ink[cell]
	if before >= 1.0:
		return
	var after: float = minf(1.0, before + amount)
	_set_ink(cell, after)
	var part: int = _part_of[cell]
	if part >= 0:
		if after >= 1.0:
			_part_filled[part] += 1
			_check_part(part)
	elif _allowed[cell] == 0 and before < 0.5 and after >= 0.5:
		mistakes += 1


func _set_ink(cell: int, value: float) -> void:
	_ink[cell] = value
	_pixels[cell * 4 + 3] = roundi(value * 255.0)
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


func _build_allowed(tolerance: int) -> void:
	_allowed.resize(SIZE * SIZE)
	for cy in SIZE:
		for cx in SIZE:
			if _part_of[cy * SIZE + cx] < 0:
				continue
			for y in range(maxi(0, cy - tolerance), mini(SIZE, cy + tolerance + 1)):
				for x in range(maxi(0, cx - tolerance), mini(SIZE, cx + tolerance + 1)):
					_allowed[y * SIZE + x] = 1
