class_name SkinSurface
extends Control
## The skin a tattoo goes on, as the session sees it: where each stencil cell is on screen and how much
## ink it takes there. Cells are `InkCanvas` cells; screen points are viewport pixels.
## `FlatSurface` is the square skin panel, `ArmSurface` the forearm with pulled skin.

## Grid size of the stencil being inked, in cells; set by setup().
var grid: Vector2i = Vector2i(256, 256)


## Called once by the session before the parts are added to stencil_layer().
func setup(stencil: StencilData) -> void:
	grid = stencil.grid_size


## Where the session puts one full-rect TextureRect per stencil part.
func stencil_layer() -> Control:
	return null


## The cell under a screen point, or Vector2.INF where there is no skin.
func to_cell(_screen_point: Vector2) -> Vector2:
	return Vector2.INF


## Screen point of a cell (x, y) and how much ink lands there, 0..1 (z); z is 0 where it's hidden.
func project(_cell: Vector2) -> Vector3:
	return Vector3.ZERO


## Typical size of a cell on screen, in pixels.
func pixels_per_cell() -> float:
	return 1.0


## How many cells around `cell` a circle of `radius_px` on screen can reach, per axis.
func cells_within(_cell: Vector2, radius_px: float) -> Vector2:
	return Vector2.ONE * (radius_px / pixels_per_cell())


## Whether a screen point is on the skin.
func is_on_skin(screen_point: Vector2) -> bool:
	return to_cell(screen_point).is_finite()


## Whether spirit tasks, the magnet and skin redness can work on this skin (they assume the flat panel).
func supports_tasks() -> bool:
	return false


## Controls this skin adds to the HUD line, or "".
func hint() -> String:
	return ""


## The "show what's left" ping, 0..1 (rises, then fades). A skin can light up what's left out of sight.
func set_highlight(_value: float, _canvas: InkCanvas) -> void:
	pass


## Per frame, from the session. `active`: the player may use the free hand on the skin now.
func update_surface(_delta: float, _active: bool) -> void:
	pass


## Lets go of anything held at once (overheat, the end).
func release() -> void:
	pass
