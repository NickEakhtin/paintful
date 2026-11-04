class_name InkPaint
extends Node
## The look of the ink at the screen's own resolution. InkCanvas counts ink on a coarse grid (progress, the 97%,
## the magnet, the tasks' blocks), which shows steps and blotches stretched over a big monitor. Two half-float
## buffers, as big as the stencil is drawn in real pixels, get the same stamps drawn as smooth dabs of the same
## shape (full at the centre, half at the edge, a crisp rim; an ellipse where the skin is curved or stretched):
## - `coverage`: the dabs add up, like the ink in the logic;
## - `wetness`: a dab sets it to 1 and it decays every frame, so fresh ink stays glossy for `dry_time`.
## New dabs skip the blocked ellipses, as the logic does, so ink never lands under an open eye.
## `resize()` (the window changed size mid-session) moves the ink into buffers of the new size; `resized` then
## says `coverage`, `wetness` and `texel()` changed.

signal resized

## Largest side of the buffers, in pixels (the aspect is kept).
const MAX_SIZE: int = 2048
## A stroke is drawn as dabs this far apart, in radii (the logic steps half a radius): no scallops at its edges.
const STROKE_SPACING: float = 0.15
## Most blocked ellipses passed to the brushes.
const MAX_BLOCKS: int = 8
## Wetness decays as exp(-DECAY * age / dry_time); the ink shader turns it back into an age.
const DECAY: float = 3.0
## Copies a buffer as is into one of another size; its values are already linear, so they go out re-encoded.
const COPY_SHADER: String = """
shader_type canvas_item;
render_mode blend_disabled;
vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
void fragment() {
	vec4 value = texture(TEXTURE, UV);
	COLOR = vec4(to_srgb(value.rgb), value.a);
}
"""
const BRUSH_SHADER: String = """
shader_type canvas_item;
render_mode %s;
// ellipses where new ink doesn't land: centre and half size, in buffer pixels
uniform vec4 blocks[%d];
uniform int block_count = 0;
void fragment() {
	for (int i = 0; i < block_count; i++) {
		vec2 offset = (FRAGCOORD.xy - blocks[i].xy) / blocks[i].zw;
		if (dot(offset, offset) <= 1.0) {
			discard;
		}
	}
	COLOR = texture(TEXTURE, UV) * COLOR;
}
"""

var coverage: Texture2D
var wetness: Texture2D

var _cover: SubViewport
var _wet: SubViewport
var _cover_brush: Node2D = Node2D.new()
var _wet_brush: Node2D = Node2D.new()
var _fader: Node2D = Node2D.new()
## Dabs to draw, each [centre: Vector2, reach: Vector2, amount: float] in cells.
var _pending: Array[Array] = []
var _frame: Array[Array] = []
var _cell_pixels: Vector2 = Vector2.ONE
var _cells: Vector2i = Vector2i(256, 256)
## While the ink moves to new buffers: the old ones (frozen) and the frame that copies them.
var _old_views: Array[SubViewport] = []
var _move_frame: int = -1
var _wanted_size: Vector2i = Vector2i.ZERO
var _dry_time: float = 6.0
var _dab: GradientTexture2D = GradientTexture2D.new()
var _brush_materials: Array[ShaderMaterial] = []
var _drew_last_frame: bool = false
## The engine skips drawing while the window can't be seen (minimised, covered on macOS): dabs stay queued and
## drying time adds up until a frame is really drawn.
var _frame_drawn: bool = true
var _undrawn_time: float = 0.0


func _init() -> void:
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
	_cover = _buffer("Coverage")
	_wet = _buffer("Wetness")
	coverage = _cover.get_texture()
	wetness = _wet.get_texture()
	_cover_brush.material = _brush_material("blend_add")
	_cover_brush.draw.connect(_draw_dabs.bind(_cover_brush, false))
	_cover.add_child(_cover_brush)
	# the fader multiplies the whole wetness buffer every frame, then fresh dabs set it back to 1
	var fade: ShaderMaterial = ShaderMaterial.new()
	fade.shader = Shader.new()
	fade.shader.code = "shader_type canvas_item;\nrender_mode blend_mul;\n"
	_fader.material = fade
	_fader.draw.connect(func() -> void: _fader.draw_rect(Rect2(Vector2.ZERO, Vector2(_wet.size)), Color.WHITE))
	_wet.add_child(_fader)
	_wet_brush.material = _brush_material("blend_mix")
	_wet_brush.draw.connect(_draw_dabs.bind(_wet_brush, true))
	_wet.add_child(_wet_brush)
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_frame_drawn)


func _enter_tree() -> void:
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_drawn):
		RenderingServer.frame_post_draw.connect(_on_frame_drawn)


## `pixels`: the stencil's size as drawn, in real pixels; `cells`: the logic grid's size.
func setup(pixels: Vector2, cells: Vector2i, dry_time: float) -> void:
	var buffer: Vector2i = _buffer_size(pixels)
	_cover.size = buffer
	_wet.size = buffer
	_cells = cells
	_cell_pixels = Vector2(buffer) / Vector2(cells)
	_dry_time = maxf(dry_time, 0.01)
	_fader.queue_redraw()
	clear_ink()


## The stencil's side on screen changed (the window was resized or went fullscreen): the ink moves into buffers of
## the new size, so it stays as sharp as the screen. Takes effect once a frame has copied the old ones.
func resize(pixels: Vector2) -> void:
	_wanted_size = _buffer_size(pixels)
	if _move_frame >= 0 or _wanted_size == _cover.size:
		return   # a move in progress picks the latest size up when it ends
	# the last batch may not have reached the old buffers: draw it into the new ones
	if not _frame_drawn:
		_frame.append_array(_pending)
		_pending = _frame
	_frame = []
	_old_views = [_cover, _wet]
	for old: SubViewport in _old_views:
		old.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var buffer: Vector2i = _wanted_size
	_cover = _buffer("Coverage")
	_wet = _buffer("Wetness")
	for i in 2:
		var view: SubViewport = [_cover, _wet][i]
		view.size = buffer
		var copy: TextureRect = TextureRect.new()
		copy.name = "Copy"
		copy.texture = _old_views[i].get_texture()
		copy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		copy.size = Vector2(buffer)
		copy.material = ShaderMaterial.new()
		(copy.material as ShaderMaterial).shader = Shader.new()
		(copy.material as ShaderMaterial).shader.code = COPY_SHADER
		view.add_child(copy)
	_cell_pixels = Vector2(buffer) / Vector2(_cells)
	coverage = _cover.get_texture()
	wetness = _wet.get_texture()
	_move_frame = Engine.get_frames_drawn()
	resized.emit()


## One buffer pixel in UV, per axis.
func texel() -> Vector2:
	return Vector2.ONE / Vector2(_cover.size)


## Queues stamps and strokes (in cells, as InkCanvas keeps them) to be drawn this frame.
func add_ink(dabs: Array[Array], strokes: Array[Array]) -> void:
	_pending.append_array(dabs)
	for stroke: Array in strokes:
		var from: Vector2 = stroke[0]
		var to: Vector2 = stroke[1]
		var reach: Vector2 = stroke[2]
		var spacing: float = maxf(minf(reach.x, reach.y) * STROKE_SPACING, 0.01)
		var steps: int = clampi(ceili(from.distance_to(to) / spacing), 1, 512)
		for i in steps:
			_pending.append([from.lerp(to, float(i + 1) / steps), reach, float(stroke[3]) / steps])


## Ellipses (inscribed in rects, in cells) where new dabs don't land, like InkCanvas.blocked.
func set_blocks(blocked: Array[Rect2]) -> void:
	var blocks: Array[Vector4] = []
	for rect: Rect2 in blocked.slice(0, MAX_BLOCKS):
		var centre: Vector2 = rect.get_center() * _cell_pixels
		var half: Vector2 = (rect.size * 0.5 * _cell_pixels).max(Vector2.ONE * 0.01)
		blocks.append(Vector4(centre.x, centre.y, half.x, half.y))
	var padded: Array[Vector4] = blocks.duplicate()
	padded.resize(MAX_BLOCKS)
	for material: ShaderMaterial in _brush_materials:
		material.set_shader_parameter("blocks", padded)
		material.set_shader_parameter("block_count", blocks.size())


func clear_ink() -> void:
	if _move_frame >= 0:
		_finish_move()
	_pending.clear()
	_frame.clear()
	_cover.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_wet.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE


func _process(delta: float) -> void:
	_undrawn_time += delta
	if _move_frame >= 0:
		if Engine.get_frames_drawn() <= _move_frame:
			return   # dabs wait until the copy is drawn
		_finish_move()
		if _wanted_size != _cover.size:
			resize(Vector2(_wanted_size))
			return
	var keep: float = exp(-DECAY * _undrawn_time / _dry_time)
	_fader.modulate = Color(keep, keep, keep).linear_to_srgb()
	if _frame_drawn:
		_frame = _pending
	else:
		_frame.append_array(_pending)   # the last batch never reached the buffers: draw it with this one
	_pending = []
	_frame_drawn = false
	# a dab is drawn in exactly one frame: the buffers keep it, so the brushes redraw empty afterwards
	if not _frame.is_empty() or _drew_last_frame:
		_cover_brush.queue_redraw()
		_wet_brush.queue_redraw()
	_drew_last_frame = not _frame.is_empty()


func _on_frame_drawn() -> void:
	_frame_drawn = true
	_undrawn_time = 0.0


## The copy has been drawn: the brushes and the fader go to the new buffers, the old ones are dropped.
func _finish_move() -> void:
	_move_frame = -1
	for view: SubViewport in [_cover, _wet]:
		var copy: Node = view.get_node("Copy")
		view.remove_child(copy)
		copy.queue_free()
	_cover_brush.reparent(_cover, false)
	_fader.reparent(_wet, false)
	_wet_brush.reparent(_wet, false)
	_fader.queue_redraw()
	for old: SubViewport in _old_views:
		old.queue_free()
	_old_views.clear()


## The buffer for a stencil drawn `pixels` big: as big, the longer side at most MAX_SIZE.
func _buffer_size(pixels: Vector2) -> Vector2i:
	var fit: float = minf(1.0, MAX_SIZE / maxf(maxf(pixels.x, pixels.y), 1.0))
	return Vector2i((pixels * fit).round()).max(Vector2i(16, 16))


func _draw_dabs(brush: Node2D, wet: bool) -> void:
	for dab: Array in _frame:
		var centre: Vector2 = (dab[0] as Vector2) * _cell_pixels
		var reach: Vector2 = (dab[1] as Vector2) * _cell_pixels
		var rect: Rect2 = Rect2(centre - reach, reach * 2.0)
		if wet:
			brush.draw_texture_rect(_dab, rect, false, Color.WHITE)
		else:
			# an HDR buffer takes colours as sRGB and blends in linear: encode the dose so it lands as is
			var dose: float = dab[2]
			brush.draw_texture_rect(_dab, rect, false, Color(Color(dose, dose, dose).linear_to_srgb(), 1.0))


func _buffer(buffer_name: String) -> SubViewport:
	var view: SubViewport = SubViewport.new()
	view.name = buffer_name
	view.transparent_bg = true
	view.use_hdr_2d = true                 # half floats: tiny per-frame doses add up instead of rounding away
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(view)
	return view


func _brush_material(blend: String) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = BRUSH_SHADER % [blend, MAX_BLOCKS]
	_brush_materials.append(material)
	return material
