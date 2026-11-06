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


## Two screen vectors at `cell` (the brush's half length and half thickness, `InkBrush`) in cells: the
## columns of the result, origin unused. On curved or stretched skin the brush's ellipse is skewed there.
## The ink look draws each dab through it.
func brush_basis(_cell: Vector2, along_px: Vector2, across_px: Vector2) -> Transform2D:
	var scale: float = 1.0 / pixels_per_cell()
	return Transform2D(along_px * scale, across_px * scale, Vector2.ZERO)


## How big the stencil's ink look should be drawn, in real screen pixels (window pixels, not layout ones).
func ink_pixels() -> Vector2:
	return size * get_viewport().get_final_transform().get_scale()


## Whether a screen point is on the skin.
func is_on_skin(screen_point: Vector2) -> bool:
	return to_cell(screen_point).is_finite()


## Whether spirit tasks, the magnet and skin redness can work on this skin (they assume the flat panel).
func supports_tasks() -> bool:
	return false


## Controls this skin adds to the HUD line, or "".
func hint() -> String:
	return ""


## The cell-centre projections this skin has cached, for brushes to read without a call per cell:
## [PackedVector3Array (relative to `offset`), PackedByteArray (1 = known), Vector3 offset], indexed y * grid.x + x;
## [] when there's no cache. Misses go through project().
func cached_projections() -> Array:
	return []


## Cell (x, y)'s centre through the cache, relative to `cached_projections()`'s offset; only called when that
## isn't empty.
func place_cell_at(x: int, y: int) -> Vector3:
	return project(Vector2(x + 0.5, y + 0.5))


## Whether this skin can be stretched (`tension_at()` means something); the flat panel can't.
func has_tension() -> bool:
	return false


## How taut the skin under a screen point is, 0 (slack) .. 1 (pulled tight).
func tension_at(_screen_point: Vector2) -> float:
	return 1.0


## Moves the view along the skin by `amount` px (down positive), if it can scroll.
func scroll_view(_amount: float) -> void:
	pass


## The skin learns where ink just landed (the canvas's new `dabs` and `strokes`, before the look takes them): fresh
## ink can bleed. Called by the session every frame.
func note_ink(_canvas: InkCanvas) -> void:
	pass


## The artist's left hand lying on the skin, as circles (x, y = centre, z = radius) in viewport pixels following its
## outline: no ink lands under them. Empty when there is no hand.
func hand_outline() -> PackedVector3Array:
	return PackedVector3Array()


## The "show what's left" ping, 0..1 (rises, then fades). A skin can light up what's left out of sight.
func set_highlight(_value: float, _canvas: InkCanvas) -> void:
	pass


## Per frame, from the session. `active`: the player may use the free hand on the skin now.
func update_surface(_delta: float, _active: bool) -> void:
	pass


## The ink look's wetness buffer (InkPaint.wetness, laid over the stencil's area like the ink): a skin can glisten
## where it's wet.
func set_wet_map(_wet: Texture2D) -> void:
	pass


## The camera is pulled back to look the skin over: no inking, no scrolling.
func is_overview() -> bool:
	return false


## Lets go of anything held at once (overheat, the end).
func release() -> void:
	pass
