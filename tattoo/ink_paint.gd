class_name InkPaint
extends SubViewport
## The look of the ink at the screen's own resolution. InkCanvas counts ink on a 256-cell grid (progress, the 97%,
## the magnet, the tasks' blocks), which looks soft and blocky stretched over a big monitor; this buffer, as big as
## the stencil is on screen in real pixels, gets the same stamps drawn as smooth dabs of the same shape (full at
## the centre, half at the edge, a crisp rim) and adds them up. The ink shader takes the ink's shape from here and
## uses the grid only as a mask, so ink never shows where the logic laid none (open eyes, wiped parts).

## Largest side of the buffer, in pixels.
const MAX_SIZE: int = 2048
## A stroke is drawn as dabs this far apart, in radii (the logic steps half a radius): no scallops at its edges.
const STROKE_SPACING: float = 0.15

var _pending: Array[Vector4] = []
var _cell_pixels: float = 1.0
var _brush: Node2D = Node2D.new()
var _dab: GradientTexture2D = GradientTexture2D.new()
var _drew_last_frame: bool = false


func _init() -> void:
	transparent_bg = true
	use_hdr_2d = true                 # half floats: tiny per-frame doses add up instead of rounding away
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	# InkCanvas.stamp() lays amount * (1 - 0.5 * d^2 / r^2) inside the radius, nothing outside
	var falloff: Gradient = Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 0.97, 1.0])   # a rim of a pixel or two, anti-aliased
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.969), Color(1, 1, 1, 0.875),
			Color(1, 1, 1, 0.719), Color(1, 1, 1, 0.505), Color(1, 1, 1, 0.0)])
	_dab.gradient = falloff
	_dab.fill = GradientTexture2D.FILL_RADIAL
	_dab.fill_from = Vector2(0.5, 0.5)
	_dab.fill_to = Vector2(1.0, 0.5)
	_dab.width = 256
	_dab.height = 256
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_brush.material = additive
	_brush.draw.connect(_draw_dabs)
	add_child(_brush)


## `pixels`: the stencil's side on screen in real pixels; `cells`: the logic grid's side.
func setup(pixels: float, cells: int) -> void:
	var side: int = clampi(roundi(pixels), 64, MAX_SIZE)
	size = Vector2i(side, side)
	_cell_pixels = float(side) / cells
	clear_ink()


## Queues stamps and strokes (in cells, as InkCanvas keeps them) to be drawn this frame.
func add_ink(dabs: Array[Vector4], strokes: Array[Array]) -> void:
	_pending.append_array(dabs)
	for stroke: Array in strokes:
		var from: Vector2 = stroke[0]
		var to: Vector2 = stroke[1]
		var radius: float = stroke[2]
		var steps: int = maxi(1, ceili(from.distance_to(to) / (radius * STROKE_SPACING)))
		for i in steps:
			var at: Vector2 = from.lerp(to, float(i + 1) / steps)
			_pending.append(Vector4(at.x, at.y, radius, float(stroke[3]) / steps))


func clear_ink() -> void:
	_pending.clear()
	render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE


func _process(_delta: float) -> void:
	# a dab is drawn in exactly one frame: the buffer keeps it, so the brush redraws empty afterwards
	if not _pending.is_empty() or _drew_last_frame:
		_brush.queue_redraw()


func _draw_dabs() -> void:
	_drew_last_frame = not _pending.is_empty()
	for dab: Vector4 in _pending:
		var radius: float = dab.z * _cell_pixels
		var rect: Rect2 = Rect2(Vector2(dab.x, dab.y) * _cell_pixels - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		# an HDR buffer takes colours as sRGB and blends in linear: encode the dose so it lands as is
		var dose: Color = Color(dab.w, dab.w, dab.w).linear_to_srgb()
		_brush.draw_texture_rect(_dab, rect, false, Color(dose, 1.0))
	_pending.clear()
