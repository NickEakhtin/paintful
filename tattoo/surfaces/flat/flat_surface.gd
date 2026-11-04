class_name FlatSurface
extends SkinSurface
## The square skin: the stencil fills this rect and every cell takes ink.

@onready var _stencil: Control = $Stencil


func stencil_layer() -> Control:
	return _stencil


func to_cell(screen_point: Vector2) -> Vector2:
	var rect: Rect2 = get_global_rect()
	return (screen_point - rect.position) / rect.size * Vector2(grid)


func project(cell: Vector2) -> Vector3:
	var rect: Rect2 = get_global_rect()
	var point: Vector2 = rect.position + cell / Vector2(grid) * rect.size
	return Vector3(point.x, point.y, 1.0)


func pixels_per_cell() -> float:
	return size.x / grid.x


func cells_within(_cell: Vector2, radius_px: float) -> Vector2:
	return Vector2(radius_px, radius_px) / (size / Vector2(grid))


func ink_reach(_cell: Vector2, radius_px: float) -> Vector2:
	return Vector2(radius_px, radius_px) / (size / Vector2(grid))


func supports_tasks() -> bool:
	return true
