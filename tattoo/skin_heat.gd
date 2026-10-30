class_name SkinHeat
extends RefCounted
## How irritated the skin is under the needle, on a coarse grid over the skin panel.
## Pure logic: no nodes, no input. Heat (0..1) grows with time under the working needle
## and cools once a cell is left alone. `texture` holds heat (red channel);
## call flush() once per frame to upload changes. Positions are in skin-local pixels.

var texture: ImageTexture

var _cell_size: float
var _width: int
var _height: int
var _heat: PackedFloat32Array = PackedFloat32Array()
## Seconds since each cell was last heated.
var _idle: PackedFloat32Array = PackedFloat32Array()
## Cells with any heat; only these cool down.
var _hot: Dictionary[int, bool] = {}
var _pixels: PackedByteArray = PackedByteArray()
var _image: Image
var _dirty: bool = false


func _init(size: Vector2, cell_size: float) -> void:
	_cell_size = cell_size
	_width = maxi(1, ceili(size.x / cell_size))
	_height = maxi(1, ceili(size.y / cell_size))
	_heat.resize(_width * _height)
	_idle.resize(_width * _height)
	_pixels.resize(_width * _height)
	_image = Image.create_from_data(_width, _height, false, Image.FORMAT_R8, _pixels)
	texture = ImageTexture.create_from_image(_image)


## Heats a soft circle along a segment: full `amount` at the centre, half at the edge.
## `amount` is split along the way, so heat depends on how long the needle stays, not on its speed.
func heat(from: Vector2, to: Vector2, radius: float, amount: float) -> void:
	var steps: int = maxi(1, ceili(from.distance_to(to) / (radius * 0.5)))
	for i in steps:
		_stamp(from.lerp(to, float(i + 1) / steps), radius, amount / steps)


## Cells left alone for `delay` seconds lose `rate` heat per second.
func cool(delta: float, delay: float, rate: float) -> void:
	for cell: int in _hot.keys():
		_idle[cell] += delta
		if _idle[cell] <= delay:
			continue
		var value: float = _heat[cell] - rate * delta
		if value <= 0.0:
			value = 0.0
			_hot.erase(cell)
		_set_heat(cell, value)


## Heat of the hottest cell.
func peak() -> float:
	return _heat[_peak_cell()] if not _hot.is_empty() else 0.0


## Centre of the hottest cell.
func peak_position() -> Vector2:
	if _hot.is_empty():
		return Vector2.INF
	var cell: int = _peak_cell()
	@warning_ignore("integer_division")
	return Vector2(cell % _width + 0.5, cell / _width + 0.5) * _cell_size


func heat_at(position: Vector2) -> float:
	var x: int = floori(position.x / _cell_size)
	var y: int = floori(position.y / _cell_size)
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return 0.0
	return _heat[y * _width + x]


## Cools everything at once.
func clear() -> void:
	for cell: int in _hot:
		_set_heat(cell, 0.0)
	_hot.clear()


## Uploads changed cells to `texture`.
func flush() -> void:
	if _dirty:
		_image.set_data(_width, _height, false, Image.FORMAT_R8, _pixels)
		texture.update(_image)
		_dirty = false


func _stamp(center: Vector2, radius: float, amount: float) -> void:
	var x0: int = maxi(0, floori((center.x - radius) / _cell_size))
	var x1: int = mini(_width - 1, floori((center.x + radius) / _cell_size))
	var y0: int = maxi(0, floori((center.y - radius) / _cell_size))
	var y1: int = mini(_height - 1, floori((center.y + radius) / _cell_size))
	var r2: float = radius * radius
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d2: float = (Vector2(x + 0.5, y + 0.5) * _cell_size).distance_squared_to(center)
			if d2 > r2:
				continue
			var cell: int = y * _width + x
			_set_heat(cell, minf(1.0, _heat[cell] + amount * (1.0 - 0.5 * d2 / r2)))
			_idle[cell] = 0.0
			_hot[cell] = true


func _peak_cell() -> int:
	var best: int = -1
	for cell: int in _hot:
		if best < 0 or _heat[cell] > _heat[best]:
			best = cell
	return best


func _set_heat(cell: int, value: float) -> void:
	_heat[cell] = value
	_pixels[cell] = roundi(value * 255.0)
	_dirty = true
