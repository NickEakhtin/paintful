class_name InkPaint
extends Node
## The look of the ink at the screen's own resolution. InkCanvas counts ink on a coarse grid (progress, the 85%,
## the magnet, the tasks' blocks), which shows steps and blotches stretched over a big monitor. Two half-float
## buffers, as big as the stencil is drawn in real pixels, get the same stamps drawn at that resolution:
## - `coverage` R, the film: every stamp as a smooth dab of the brush's shape (the brush's flat ellipse, skewed
##   where the skin is curved or stretched), adding up like the ink in the logic. With a flat brush the dab is
##   full over its `core` and fades to nothing at the rim, so the middle of a stroke closes up solid first;
## - `coverage` G, the dots: a flat brush (`dots_per_dose` > 0) also drops round dots, as many as the dose: dense
##   and big over the core, thinning out and shrinking past it and scattering beyond the brush's rim up to
##   `dot_spread`, like a spray. The ink shader shows them black at once and lets the film close the gaps as the
##   dose builds up;
## - `coverage` B, the capped film: the thick needle's film within the stencil's edge margin (`set_edge()`), which
##   the ink shader never lets close up;
## - `wetness`: a dab sets it to 1 and it decays every frame, so fresh ink stays glossy for `dry_time`. `add_wet()`
##   wets a spot without ink (a wet paper towel wiped over the skin): the ink there looks fresh again and the skin
##   glistens, drying the same way. Those spots ignore the blocked ellipses (the hand wiping is one of them).
## New dabs skip the blocked ellipses, as the logic does, so ink never lands under an open eye.
## `resize()` (the window changed size mid-session) moves the ink into buffers of the new size; `resized` then
## says `coverage`, `wetness` and `texel()` changed.

signal resized

## Largest side of the buffers, in pixels (the aspect is kept).
const MAX_SIZE: int = 2048
## A stroke is drawn as dabs this far apart, in radii (the logic steps half a radius): no scallops at its edges.
const STROKE_SPACING: float = 0.15
## Most blocked ellipses passed to the brushes.
const MAX_BLOCKS: int = 80
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
// near the stencil's edge the film is laid only by distance / edge_margin, as the logic lays ink, and into B instead
// of R: the ink shader caps B, so the thick needle's film never fills the strip however many passes; the dots (G)
// stay, so it leaves a ragged spray there. edge_map: distance from the edge in cells.
uniform sampler2D edge_map : filter_linear;
uniform float edge_margin = 0.0;
uniform vec2 buffer_size = vec2(1.0);
void fragment() {
	for (int i = 0; i < block_count; i++) {
		vec2 offset = (FRAGCOORD.xy - blocks[i].xy) / blocks[i].zw;
		if (dot(offset, offset) <= 1.0) {
			discard;
		}
	}
	vec4 color = texture(TEXTURE, UV) * COLOR;
	// the thick needle lays nothing within the edge margin, film or dots: only the thin one reaches the edge
	if (edge_margin > 0.0 && texture(edge_map, FRAGCOORD.xy / buffer_size).r < edge_margin) {
		discard;
	}
	COLOR = color;
}
"""

var coverage: Texture2D
var wetness: Texture2D

## Dots per unit of a stamp's dose (InkCanvas amounts); 0: no dots, the film only (the round brush).
var dots_per_dose: float = 0.0
## Share of the brush (elliptic radius, 0..1) that is solid: the film dab is full and the dots densest inside it.
var core: float = 0.0:
	set(value):
		core = clampf(value, 0.0, 0.95)
		_shape_dab()
## Dots scatter out to this many brush radii (1: only inside the brush).
var dot_spread: float = 1.0
## Past the core the dots thin out as (1 - x)^this, x = 0 at the core's rim .. 1 at `dot_spread`.
var dot_falloff: float = 2.0
## Dot radius in screen pixels over the core and at the far edge of the scatter.
var dot_size_center: float = 2.4
var dot_size_edge: float = 1.1
## Dot radius varies by this share either way.
var dot_size_jitter: float = 0.3
## Dots are stretched along the brush up to this much (most stay round).
var dot_stretch_max: float = 2.0
## Smallest dot radius in buffer pixels, so a dot never falls between them.
const MIN_DOT_PIXELS: float = 0.75

var _cover: SubViewport
var _wet: SubViewport
var _cover_brush: Node2D = Node2D.new()
var _wet_brush: Node2D = Node2D.new()
## Draws `add_wet()` spots into the wetness buffer, blocks or not.
var _wipe_brush: Node2D = Node2D.new()
var _fader: Node2D = Node2D.new()
## Dabs to draw, each [centre: Vector2, basis: Transform2D, amount: float, dot: bool] in cells: a film dab, or
## a dot (its own small basis, a full dose).
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
var _dot: GradientTexture2D = GradientTexture2D.new()
## A wet spot: full in the middle, soft toward its rim, so a wiped stripe has no hard edge.
var _wipe: GradientTexture2D = GradientTexture2D.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _brush_materials: Array[ShaderMaterial] = []
var _drew_last_frame: bool = false
## The engine skips drawing while the window can't be seen (minimised, covered on macOS): dabs stay queued and
## drying time adds up until a frame is really drawn.
var _frame_drawn: bool = true
var _undrawn_time: float = 0.0


func _init() -> void:
	_shape_dab()
	_dab.fill = GradientTexture2D.FILL_RADIAL
	_dab.fill_from = Vector2(0.5, 0.5)
	_dab.fill_to = Vector2(1.0, 0.5)
	_dab.width = 256
	_dab.height = 256
	# a dot is solid with a soft rim; the ink shader makes its edge crisp
	var disc: Gradient = Gradient.new()
	disc.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	disc.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	_dot.gradient = disc
	_dot.fill = GradientTexture2D.FILL_RADIAL
	_dot.fill_from = Vector2(0.5, 0.5)
	_dot.fill_to = Vector2(1.0, 0.5)
	_dot.width = 64
	_dot.height = 64
	var soft: Gradient = Gradient.new()
	soft.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	soft.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	_wipe.gradient = soft
	_wipe.fill = GradientTexture2D.FILL_RADIAL
	_wipe.fill_from = Vector2(0.5, 0.5)
	_wipe.fill_to = Vector2(1.0, 0.5)
	_wipe.width = 128
	_wipe.height = 128
	_rng.randomize()
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
	_wipe_brush.draw.connect(_draw_wipes)
	_wet.add_child(_wipe_brush)
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
	# the logic raises a thin brush's dose by 1 / thickness (InkBrush.dose_scale()); the film's dabs do the same,
	# so the film builds up exactly as the logic counts
	for dab: Array in dabs:
		var basis: Transform2D = dab[1]
		var thick: float = dab[4] if dab.size() > 4 else 1.0
		_pending.append([dab[0], basis, float(dab[2]) / maxf(thick, 0.001), false])
		_add_dots(dab[0], dab[0], basis, dab[2], dab[3] if dab.size() > 4 else 0.0, thick)
	for stroke: Array in strokes:
		var from: Vector2 = stroke[0]
		var to: Vector2 = stroke[1]
		var basis: Transform2D = stroke[2]
		var thick: float = stroke[5] if stroke.size() > 5 else 1.0
		var spacing: float = maxf(minf(basis.x.length(), basis.y.length()) * STROKE_SPACING, 0.01)
		var steps: int = clampi(ceili(from.distance_to(to) / spacing), 1, 512)
		for i in steps:
			_pending.append([from.lerp(to, float(i + 1) / steps), basis,
					float(stroke[3]) / maxf(thick, 0.001) / steps, false])
		_add_dots(from, to, basis, stroke[3], stroke[4] if stroke.size() > 5 else 0.0, stroke[5] if stroke.size() > 5 else 1.0)


## Wets an ellipse (centre and half size, in cells) without laying ink: drawn this frame like a dab.
func add_wet(center: Vector2, radius: Vector2) -> void:
	_pending.append([center, Transform2D(Vector2(radius.x, 0.0), Vector2(0.0, radius.y), Vector2.ZERO), 0.0, false,
			true])


## The film dab's profile over the elliptic radius: without a core, the logic's (InkCanvas.stamp() lays
## amount * (1 - 0.5 * d^2 / r^2) inside the radius, nothing outside); with one, full over the core and easing down
## to nothing at the rim, so a stroke is solid in the middle and soft at its sides.
func _shape_dab() -> void:
	var falloff: Gradient = Gradient.new()
	if core <= 0.0:
		falloff.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 0.97, 1.0])   # a rim of a pixel or two, anti-aliased
		falloff.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.969), Color(1, 1, 1, 0.875),
				Color(1, 1, 1, 0.719), Color(1, 1, 1, 0.505), Color(1, 1, 1, 0.0)])
	else:
		var offsets: PackedFloat32Array = PackedFloat32Array([0.0])
		var colors: PackedColorArray = PackedColorArray([Color.WHITE])
		for i in 9:
			var x: float = i / 8.0
			offsets.append(lerpf(core, 1.0, x))
			colors.append(Color(1, 1, 1, 1.0 - smoothstep(0.0, 1.0, x)))
		falloff.offsets = offsets
		falloff.colors = colors
	_dab.gradient = falloff


## Drops `amount * dots_per_dose` dots (rounded at random) at random spots of a segment: dense over the brush's
## core, thinning out past it to `dot_spread` brush radii. `radius_px`: the brush's half length on screen (0: no
## dots), `thickness` as in `InkBrush`.
func _add_dots(from: Vector2, to: Vector2, basis: Transform2D, amount: float, radius_px: float,
		thickness: float) -> void:
	if dots_per_dose <= 0.0 or radius_px <= 0.0 or amount <= 0.0:
		return
	var wanted: float = amount * dots_per_dose
	var count: int = floori(wanted) + (1 if _rng.randf() < wanted - floorf(wanted) else 0)
	# the brush's unit across is its half thickness: a dot of radius r screen px is r / radius_px along it and
	# r / (thickness * radius_px) across it in brush units
	thickness = maxf(thickness, 0.001)
	var reach: float = maxf(dot_spread, core + 0.01)
	for i in count:
		# a spot in the brush's elliptic units (s along, t across), kept with the density at its radius
		var s: float = 0.0
		var t: float = 0.0
		var x: float = 0.0
		for attempt in 32:
			s = _rng.randf_range(-reach, reach)
			t = _rng.randf_range(-reach, reach)
			var r: float = sqrt(s * s + t * t)
			if r > reach:
				continue
			x = clampf((r - core) / (reach - core), 0.0, 1.0)
			if _rng.randf() <= pow(1.0 - x, dot_falloff):
				break
		var centre: Vector2 = from.lerp(to, _rng.randf()) + basis.x * s + basis.y * t
		var size: float = lerpf(dot_size_center, dot_size_edge, x) \
				* (1.0 + _rng.randf_range(-dot_size_jitter, dot_size_jitter))
		var stretch: float = 1.0 + pow(_rng.randf(), 3.0) * (dot_stretch_max - 1.0)
		var along: Vector2 = basis.x * (size * stretch / radius_px)
		var across: Vector2 = basis.y * (size / (radius_px * thickness))
		_pending.append([centre, Transform2D(along, across, Vector2.ZERO), 1.0, true])


## The stencil's edge distances (InkCanvas.edge_texture) and the margin (cells) within which new film is thinned,
## like InkCanvas.edge_margin; 0: off. Only the coverage buffer's film; the dots and the wetness don't change.
func set_edge(edge_map: Texture2D, margin: float) -> void:
	var material: ShaderMaterial = _cover_brush.material
	material.set_shader_parameter("edge_map", edge_map)
	material.set_shader_parameter("edge_margin", margin)
	material.set_shader_parameter("buffer_size", Vector2(_cover.size))


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
		_wipe_brush.queue_redraw()
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
	(_cover_brush.material as ShaderMaterial).set_shader_parameter("buffer_size", Vector2(_cover.size))
	_fader.reparent(_wet, false)
	_wet_brush.reparent(_wet, false)
	_wipe_brush.reparent(_wet, false)
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
		if dab.size() > 4:
			continue   # a wet spot without ink: _draw_wipes()
		var dot: bool = dab[3]
		if wet and dot:
			continue   # the film's dab already wets the whole brush
		var basis: Transform2D = dab[1]
		var along: Vector2 = basis.x * _cell_pixels
		var across: Vector2 = basis.y * _cell_pixels
		if dot:
			along = along.normalized() * maxf(along.length(), MIN_DOT_PIXELS)
			across = across.normalized() * maxf(across.length(), MIN_DOT_PIXELS)
		brush.draw_set_transform_matrix(Transform2D(along, across, (dab[0] as Vector2) * _cell_pixels))
		var rect: Rect2 = Rect2(-1.0, -1.0, 2.0, 2.0)
		if wet:
			brush.draw_texture_rect(_dab, rect, false, Color.WHITE)
		else:
			# an HDR buffer takes colours as sRGB and blends in linear: encode the dose so it lands as is
			var dose: float = dab[2]
			var channels: Color = Color(0.0, dose, 0.0) if dot else Color(dose, 0.0, 0.0)
			brush.draw_texture_rect(_dot if dot else _dab, rect, false, Color(channels.linear_to_srgb(), 1.0))
	brush.draw_set_transform_matrix(Transform2D.IDENTITY)


## The wet spots of this frame (add_wet()), each a soft disc that sets the wetness toward 1.
func _draw_wipes() -> void:
	for dab: Array in _frame:
		if dab.size() <= 4:
			continue
		var basis: Transform2D = dab[1]
		_wipe_brush.draw_set_transform_matrix(Transform2D(basis.x * _cell_pixels, basis.y * _cell_pixels,
				(dab[0] as Vector2) * _cell_pixels))
		_wipe_brush.draw_texture_rect(_wipe, Rect2(-1.0, -1.0, 2.0, 2.0), false, Color.WHITE)
	_wipe_brush.draw_set_transform_matrix(Transform2D.IDENTITY)


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
