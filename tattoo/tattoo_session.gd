class_name TattooSession
extends CanvasLayer
## Tattoo mini-game screen, modeled on PowerWash Simulator: no timer, no penalties,
## ink only lands inside the stencil and the needle is pulled toward what's left.
## Spirit tasks (TattooModifier) sit on top of the skin and push the needle or the skin around.
## Add it to the tree and call start(stencil, tasks); `finished` fires once the player closes
## the "done" panel. The caller frees it and restores the mouse mode.
## Running this scene on its own starts it with `stencil` and restarts when done.

signal finished(result: SessionResult)

const INK_SHADER: Shader = preload("res://tattoo/stencil_ink.gdshader")
const ROULETTE_SCENE: PackedScene = preload("res://ui/roulette/roulette.tscn")
const MECHANICS: Mechanics = preload("res://data/mechanics.tres")
## Skin scenes by `StencilData.surface`; anything else uses the flat panel already in the scene.
const SURFACE_SCENES: Dictionary = {
	&"arm": "res://tattoo/surfaces/arm/arm_surface.tscn",
}

@export var stencil: StencilData
## Testing shortcut: F3 finishes the tattoo and closes the session at once. Turn off for release.
@export var debug_skip_enabled: bool = true

@export_group("Spirit tasks")
## What the roulette can land on.
@export var task_pool: Array[ModifierData] = []
## When set, running this scene on its own skips the roulette and uses these, e.g. to tune one task.
@export var fixed_tasks: Array[ModifierData] = []

@export_group("Tuning")
## Needle radius on screen, in pixels: the flat brush's half length.
@export var brush_radius: float = 30.0
## Ink per second under the needle centre; 1.0 fills a cell.
@export var ink_rate: float = 4.0
@export_range(0.5, 1.0) var completion_threshold: float = 0.97
## How far (in cells) the needle feels the pull of unfilled stencil.
@export var magnet_radius: float = 14.0
## Share of the way to the target the needle moves when right next to it.
@export_range(0.0, 1.0) var magnet_strength: float = 0.85
## How fast the needle catches up with the mouse (per second); higher is snappier, lower calmer. It follows
## through two smoothing stages (each twice this fast): the same lag as one, but the needle eases into a move and
## out of it instead of starting at once. 2.2 is about 450 ms behind, a heavy machine (4.2 was 240 ms, 14 was
## 70 ms, 42 nearly the raw mouse).
@export var needle_follow: float = 2.2
## Share of the mouse's own motion the machine follows (the session captures the mouse): 0.5 = half as
## sensitive; 1 uses the plain cursor position.
@export var mouse_sensitivity: float = 0.5
## The machine's own weight on top of the tasks' (`TattooMachine.weight`): its top swings slower and wider, as a
## mass 1 + this times the bare machine's. 0.9: 90% heavier.
@export var machine_mass: float = 0.9
## Seconds fresh ink takes to dry from wet gloss to matte.
@export var ink_dry_time: float = 6.0

@export_group("Look")
## The game's retro filter (world/fx/retro_post) over the skin and the machine; the HUD stays sharp.
@export var retro_filter: bool = true
## As the game's RetroPost: a game pixel is a whole number of screen pixels, as big as fits this many rows in
## the window, at most `retro_max_pixel`.
@export var retro_min_rows: int = 360
@export var retro_max_pixel: int = 3

@export_group("Needles")
## The thin needle (`Mechanics.needle_swap`): a small round brush, no dots, for careful edges.
@export var thin_radius: float = 18.0
## How much the thin needle feels the stencil's edge, as a share of the thick one's push and shake.
@export_range(0.0, 1.0) var thin_edge_factor: float = 0.15

@export_group("Edge")
## Inking past the stencil's edge (`Mechanics.edge_kick`): the machine is pushed back toward the drawing by up to
## this many pixels, in proportion to how much of the brush is outside.
@export var edge_push: float = 180.0
## The view (skin and table, like a camera) shakes by up to this many pixels meanwhile; the machine stays under
## the mouse.
@export var edge_shake: float = 8.0
## A red frame around the screen shows how far past the edge the brush is; how fast it comes and goes.
@export var edge_frame_rate: float = 10.0
## How quickly the push builds up past the edge, and fades once the needle is back in (per second).
@export var edge_rate: float = 12.0
@export var edge_return: float = 5.0
## Seconds between two flinch sounds at the edge.
@export var edge_sound_gap: float = 0.7

@export_group("Brush")
## The flat brush's half thickness as a share of `brush_radius` (1: round). Off with `Mechanics.flat_brush`.
@export_range(0.05, 1.0) var brush_thickness: float = 0.25
## The brush turns across the needle's motion; off, it always keeps `brush_rest_angle` (like calligraphy).
@export var brush_follows_motion: bool = true
## Angle of the brush before it has moved, in degrees from the screen's x axis (negative: up to the right).
@export var brush_rest_angle: float = -10.0
## How fast the brush turns to the motion's direction; higher is quicker.
@export var brush_turn_rate: float = 12.0
## Slower than this (pixels per second) the brush keeps its angle.
@export var brush_min_speed: float = 30.0
## Dots the brush drops per second of inking.
@export var dots_per_second: float = 2600.0
## Solid middle of the brush (share of its radius): the ink closes up there first, the dots are densest.
@export_range(0.0, 0.95) var brush_core: float = 0.45
## Dots scatter out to this many brush radii, past the brush's rim, like a spray.
@export_range(1.0, 3.0) var dot_spread: float = 1.6
## Past the core the dots thin out as (1 - x)^this towards the spread's edge; higher is a tighter spray.
@export var dot_falloff: float = 2.0
## Dot radius over the core and at the spray's outer edge, in pixels.
@export var dot_size_center: float = 2.0
@export var dot_size_edge: float = 1.0
## Dot radius varies by this share either way.
@export_range(0.0, 0.9) var dot_size_jitter: float = 0.3
## Some dots are stretched along the brush, up to this much.
@export var dot_stretch_max: float = 2.0
## Share of full ink where the smooth film starts closing the gaps between the dots.
@export_range(0.0, 0.95) var film_from: float = 0.15
## Share of full ink where the film is solid: a single pass at an easy pace lays about 0.4 in the brush's middle,
## so the core of a stroke closes up at once while its sides stay a spray of dots.
@export_range(0.05, 1.0) var film_full: float = 0.35

@export_group("Feel")
## Half length of the dent under the working needle, in pixels (as the brush's); it has the brush's shape and
## turns with it.
@export var press_radius: float = 45.0
## How far the picture is pulled into the dent, in pixels (deep enough to read through the retro filter).
@export var press_depth: float = 12.0
## The dent is this many times wider across than the brush (keeping the brush's length and turn).
@export var press_widen: float = 2.0
## Light and shade on the dent's walls: the side facing the lamp lighter, the other darker, by this share.
@export var press_shade: float = 0.35
## Pink halo around the tip; alpha is its strength.
@export var press_tint: Color = Color(1.0, 0.45, 0.45, 0.28)
## Seconds for the dent to appear and to go once the needle stops.
@export var press_in_time: float = 0.08
@export var press_out_time: float = 0.25
## How far the skin picture trembles while the machine buzzes, in pixels.
@export var skin_buzz: float = 0.5

@export_group("Flow")
## Seconds of steady stroking over the stencil to reach full flow.
@export var flow_build_time: float = 5.0
## Seconds full flow takes to fade once the stroke breaks.
@export var flow_fade_time: float = 1.2
## A break shorter than this (a quick slip off the stencil) doesn't touch the flow.
@export var flow_grace: float = 0.25
## Slower than this (pixels per second) the needle counts as standing: flow holds, doesn't grow.
@export var flow_min_speed: float = 40.0
## Trail widens by this share of `brush_radius` at full flow.
@export var flow_brush_bonus: float = 0.25

@export_group("Ink supply")
## Ink the machine holds, in filled-cell units (the black square is 22 500 cells).
@export var ink_capacity: float = 3000.0
## Clicks on the ink cap that fill an empty machine; each one adds an equal share.
@export_range(1, 10) var refill_clicks: int = 3
## Share of the tank below which the gauge warns.
@export_range(0.0, 1.0) var low_ink: float = 0.25
## The ink cap stands on a side table off screen to the right; Q swings the view this far to see it.
@export var table_offset: float = 900.0
## Seconds for the swing either way.
@export var turn_time: float = 0.22

@export_group("Skin")
## Heat grid cell, in pixels.
@export var heat_cell: float = 8.0
## Radius of the heated circle under the needle, in pixels.
@export var heat_radius: float = 30.0
## Heat per second under the needle centre; 1.0 is the limit.
@export var heat_rate: float = 0.25
## Heat where the skin starts to turn pink.
@export_range(0.0, 1.0) var pink_from: float = 0.25
## Heat where the skin is red and the client hisses.
@export_range(0.0, 1.0) var warn_heat: float = 0.5
## Heat where the warning gets urgent.
@export_range(0.0, 1.0) var danger_heat: float = 0.8
## Heat where the skin gives out and the session starts over.
@export_range(0.0, 1.0) var fail_heat: float = 1.0
## How far the skin jumps when the client flinches at the redness, in pixels.
@export var flinch_distance: float = 6.0
## What the spirit snaps when the skin gives out: one at random, no repeats until all are used.
@export var overheat_lines: Array[DialogueData] = []
## Seconds a spot must be left alone before it starts to cool.
@export var cool_delay: float = 0.5
## Heat lost per second once a spot cools.
@export var cool_rate: float = 0.2

var canvas: InkCanvas
## The ink's look at the screen's resolution (InkPaint), fed from `canvas` every frame.
var _paint_view: InkPaint = null
## The skin panel; tasks may tint it.
@onready var skin: Panel = $View/Body/Skin

var _ink_left: float = 0.0
var _running: bool = false
var _waiting_for_close: bool = false
var _done_msec: int = 0
var _was_inking: bool = false
var _last_cell: Vector2 = Vector2.ZERO
var _materials: Array[ShaderMaterial] = []
var _completed_parts: int = 0
var _highlight_tween: Tween
var _modifiers: Array[TattooModifier] = []
## Needle after magnet and smoothing, before task offsets.
var _steady_needle: Vector2 = Vector2.ZERO
## The first smoothing stage between the mouse and `_steady_needle`.
var _needle_lead: Vector2 = Vector2.ZERO
## The thin needle is in the machine (`Mechanics.needle_swap`).
var _thin: bool = false
## Push on the needle back toward the drawing, and how far past the edge the brush is (0..1, weighted by needle).
var _edge_push: Vector2 = Vector2.ZERO
var _edge_amount: float = 0.0
var _edge_sound_at: float = -10.0
var _edge_frame_level: float = 0.0
## The stencil's centre in cells: where the edge pushes toward.
var _stencil_center: Vector2 = Vector2.ZERO
var _result: SessionResult = null
var _at_table: bool = false
var _turning: bool = false
## After the swing back, LMB must be let go once before it inks again.
var _wait_for_release: bool = false
var _heat: SkinHeat
var _was_heating: bool = false
## Last heated point, in skin-local pixels.
var _last_heat_point: Vector2 = Vector2.ZERO
## 0 calm, 1 red (`warn_heat`), 2 about to give out (`danger_heat`).
var _skin_stage: int = 0
## The client's flinch: pushes the skin and settles back.
var _flinch: Vector2 = Vector2.ZERO
## What the roulette gave, kept to start the tasks again after the skin gives out.
var _tasks: Array[ModifierData] = []
var _overheat_bag: Array[DialogueData] = []
var _last_overheat_line: DialogueData = null
## How hard the needle presses into the skin right now, 0..1 (the look only).
var _press: float = 0.0
var _flow: InkFlow
## The skin being inked: the flat panel or a surface scene picked by the stencil.
var _surface: SkinSurface
## The needle's brush; `_update_brush()` turns it across the motion.
var _brush: InkBrush = InkBrush.new()
## The brush's angle, doubled, in radians: a brush is the same either way along, so turning it by the doubled
## angle never flips it end over end.
var _brush_angle2: float = 0.0

@onready var _view: Control = $View
@onready var _body: Control = $View/Body
@onready var _canvas_rect: FlatSurface = $View/Body/Canvas
@onready var _redness: ColorRect = $View/Body/Redness
@onready var _press_rect: ColorRect = $View/Body/Press
@onready var _modifier_layer: Node2D = $View/Body/Modifiers
@onready var _machine: TattooMachine = $Machine
@onready var _hud: Control = $HUD
@onready var _ding: AudioStreamPlayer = $Ding
@onready var _dip_sound: AudioStreamPlayer = $DipSound
@onready var _wince: AudioStreamPlayer = $Wince
@onready var _needle_swap: AudioStreamPlayer = $NeedleSwap
@onready var _thick_cartridge: NeedleCartridge = $View/ThickNeedle
@onready var _thin_cartridge: NeedleCartridge = $View/ThinNeedle
@onready var _edge_frame: ColorRect = $EdgeFrame
@onready var _heartbeat: AudioStreamPlayer = $Heartbeat
@onready var _cry: AudioStreamPlayer = $Cry
@onready var _ink_cap: InkCap = $View/InkCap
@onready var _to_table_hint: Label = $View/ToTable
@onready var _to_client_hint: Label = $View/ToClient
@onready var _blur: ColorRect = $MotionBlur
@onready var _retro: ColorRect = $RetroFilter
@onready var _retro_copy: BackBufferCopy = $RetroCopy

## Whether the window's own 3D was already off before the session turned it off.
var _window_3d_was_off: bool = false


func _ready() -> void:
	_machine.visible = false
	get_viewport().size_changed.connect(_on_window_resized)
	# the session covers the whole screen: the level's 3D under it (SSAO, volumetric fog, glow) would cost about
	# 15 ms a frame on a 3K screen for nothing, so the window stops drawing 3D until the session is freed
	_window_3d_was_off = get_viewport().disable_3d
	get_viewport().disable_3d = true
	_fit_retro()
	_start_if_main_scene.call_deferred()


func _exit_tree() -> void:
	get_viewport().disable_3d = _window_3d_was_off


func _start_if_main_scene() -> void:
	if get_tree().current_scene == self and stencil != null and canvas == null:
		finished.connect(func(_done: SessionResult) -> void: get_tree().reload_current_scene())
		if fixed_tasks.is_empty() and MECHANICS.spirit_tasks:
			roll_and_start(stencil)
		else:
			start(stencil, fixed_tasks)


## How big the skin draws the stencil, in real pixels: the ink look is drawn that big.
func _ink_pixels() -> Vector2:
	return _surface.ink_pixels()


## The ink look of every stencil part reads the InkPaint buffers (again after they're resized).
func _bind_paint() -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("paint", _paint_view.coverage)
		material.set_shader_parameter("wet_map", _paint_view.wetness)
		material.set_shader_parameter("paint_texel", _paint_view.texel())


## Fullscreen on or off, or a resized window: the ink look follows the screen's pixels (the machine and the
## ink cap size themselves every frame).
func _on_window_resized() -> void:
	_resize_paint.call_deferred()   # after the layout has settled
	_fit_retro()


## The retro filter's game pixel for the height the session renders at, as the game's RetroPost does it.
func _fit_retro() -> void:
	_retro.visible = retro_filter
	_retro_copy.visible = retro_filter
	var window: Window = get_window()
	var height: int = window.size.y
	if window.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		height = int(get_viewport().get_visible_rect().size.y)
	var pixel: int = clampi(height / maxi(retro_min_rows, 1), 1, retro_max_pixel)
	(_retro.material as ShaderMaterial).set_shader_parameter("pixel_size", float(pixel))
	# the filter keeps one point per game pixel: the machine's 3D needn't be finer
	_machine.render_divisor = pixel if retro_filter else 1


func _resize_paint() -> void:
	if _paint_view != null:
		_paint_view.resize(_ink_pixels())


## Lets the spirit spin the roulette over the bare skin, then starts with what came up.
## With spirit tasks switched off it starts at once, without tasks.
func roll_and_start(new_stencil: StencilData) -> void:
	if not MECHANICS.spirit_tasks:
		start(new_stencil)
		return
	var roulette: Roulette = ROULETTE_SCENE.instantiate()
	add_child(roulette)
	var tasks: Array[ModifierData] = await roulette.spin(task_pool)
	roulette.queue_free()
	start(new_stencil, tasks)


## `tasks` are the spirit tasks for this session, each once.
func start(new_stencil: StencilData, tasks: Array[ModifierData] = []) -> void:
	stencil = new_stencil
	_setup_surface()
	canvas = InkCanvas.new(stencil, completion_threshold)
	_stencil_center = _find_stencil_center()
	_thin = false
	_thick_cartridge.visible = MECHANICS.needle_swap
	_thin_cartridge.visible = MECHANICS.needle_swap
	_edge_push = Vector2.ZERO
	_edge_amount = 0.0
	canvas.part_completed.connect(_on_part_completed)
	if _paint_view != null:
		_paint_view.queue_free()
	_paint_view = InkPaint.new()
	add_child(_paint_view)
	_paint_view.setup(_ink_pixels(), canvas.size, ink_dry_time)
	_paint_view.resized.connect(_bind_paint)
	_setup_brush()
	_flow = InkFlow.new(flow_build_time, flow_fade_time, flow_grace)

	var part_names: PackedStringArray = PackedStringArray()
	for part in stencil.parts:
		part_names.append(part.display_name)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = INK_SHADER
		material.set_shader_parameter("dry_time", ink_dry_time)
		if MECHANICS.flat_brush:
			material.set_shader_parameter("film_from", film_from)
			material.set_shader_parameter("film_full", film_full)
			material.set_shader_parameter("first_pass", 0.0)   # below the dots the film fades in from nothing
		_materials.append(material)
		var rect: TextureRect = TextureRect.new()
		rect.texture = part.texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # big stencils stay clean on small screens
		rect.material = material
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.stencil_layer().add_child(rect)
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bind_paint()
	_hud.setup(part_names, MECHANICS.ink_supply)
	if not _surface.hint().is_empty():
		_hud.add_hint(_surface.hint())
	_setup_skin_heat()
	_setup_skin_press()
	_hud.show_progress(canvas)
	_tasks = tasks
	if not MECHANICS.spirit_tasks or not _surface.supports_tasks():
		_tasks = []
	_add_modifiers(_tasks)
	_hud.setup_tasks(_modifiers)

	_machine.visible = true
	_machine.inertia = MECHANICS.machine_inertia
	_machine.show_gauge = MECHANICS.ink_supply
	_machine.needle = _machine.pointer
	_steady_needle = _machine.pointer
	_needle_lead = _machine.pointer
	_show_turn_hints()
	_ink_left = ink_capacity
	_update_ink_display()
	_machine.mouse_sensitivity = mouse_sensitivity
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if is_equal_approx(mouse_sensitivity, 1.0) else Input.MOUSE_MODE_CAPTURED
	_running = true


func _process(delta: float) -> void:
	_dry_ink(delta)
	# Nothing happens while the screen fades in or out around the session.
	if not _running or Transition.is_busy:
		return
	_apply_skin_offset()
	_surface.update_surface(delta, not _turning)
	_update_ink_blocks()
	_update_needle(delta)
	_update_brush(delta)
	_paint(delta)
	_heat.cool(delta, cool_delay, cool_rate)
	_heat.flush()
	_update_redness(delta)
	_update_skin_press(delta)
	if MECHANICS.skin_heat and _heat.peak() >= fail_heat:
		_overheat()
		return
	_update_ink_display()
	_flush_ink()
	_hud.show_progress(canvas)
	_hud.show_tasks(_modifiers)
	if canvas.is_complete():
		_finish()


## Fresh ink keeps drying whatever else happens, the "done" panel included.
func _dry_ink(delta: float) -> void:
	if canvas == null:
		return
	canvas.time += delta
	for material in _materials:
		material.set_shader_parameter("now", canvas.time)


func _unhandled_input(event: InputEvent) -> void:
	if Transition.is_busy:
		return
	if _running and debug_skip_enabled and event is InputEventKey and event.pressed \
			and not event.echo and event.physical_keycode == KEY_F3:
		get_viewport().set_input_as_handled()
		skip()
	elif _running and event.is_action_pressed("highlight"):
		_ping_highlight()
	elif _running and event.is_action_pressed("turn_to_ink"):
		_turn(not _at_table)
	# The delay keeps the end of the last stroke from closing the panel at once.
	elif _waiting_for_close and event.is_action_pressed("use") \
			and Time.get_ticks_msec() - _done_msec > 1000:
		get_viewport().set_input_as_handled()
		_waiting_for_close = false
		finished.emit(_result)


## Fills the whole stencil and ends the session right away, without the "done" panel.
## Spirit tasks are judged as they stand at that moment.
func skip() -> void:
	if not _running:
		return
	canvas.blocked.clear()
	for part in canvas.part_count():
		for cell in canvas._part_cells[part]:
			@warning_ignore("integer_division")
			canvas.stamp(Vector2(cell % canvas.size.x + 0.5, cell / canvas.size.x + 0.5), 0.5, 1.0)
	canvas.dabs.clear()   # every part is done now, and done parts show full anyway
	canvas.strokes.clear()
	_flush_ink()
	_finish()
	_waiting_for_close = false
	finished.emit(_result)


## Where the needle touches, in viewport pixels.
func needle_position() -> Vector2:
	return _machine.needle


## Whether the machine is inking right now: LMB down, every task lets it, not swinging. Dry counts too.
func is_working() -> bool:
	return _machine.working


## Where the mouse is, in viewport pixels.
func pointer_position() -> Vector2:
	return _machine.pointer


## How fast the needle really moves, in viewport pixels per second.
func needle_velocity() -> Vector2:
	return _machine.velocity


## Where the top end of the machine is, in viewport pixels.
func machine_top_position() -> Vector2:
	return _machine.top_position()


## Where the stencil is, in the coordinates of the task layer (tasks draw in the same space).
func stencil_rect() -> Rect2:
	return _canvas_rect.get_rect()


## Where the skin is red right now (the hottest spot), in viewport pixels; Vector2.INF while nothing is.
func red_spot() -> Vector2:
	if _heat == null or _heat.peak() < warn_heat:
		return Vector2.INF
	return skin.get_global_rect().position + _heat.peak_position()


## Whether the view is swinging to the side table or back right now.
func is_turning() -> bool:
	return _turning


## Takes the ink off every part that isn't done yet; done parts stay. They flash in `color`.
func wipe_unfinished(color: Color) -> void:
	for part in canvas.part_count():
		if not canvas.is_part_done(part):
			canvas.clear_part(part)
			_flash(_materials[part], color)


func _add_modifiers(tasks: Array[ModifierData]) -> void:
	for task in tasks:
		var modifier: TattooModifier = task.scene.instantiate()
		modifier.session = self
		modifier.data = task
		_modifiers.append(modifier)
	# Lower `draw_order` goes into the layer first, so it draws under the rest; ties keep the roulette order.
	var layered: Array[TattooModifier] = _modifiers.duplicate()
	layered.sort_custom(func(a: TattooModifier, b: TattooModifier) -> bool:
		return a.draw_order < b.draw_order \
				or (a.draw_order == b.draw_order and _modifiers.find(a) < _modifiers.find(b)))
	for modifier in layered:
		_modifier_layer.add_child(modifier)


## Hands the canvas where tasks keep ink off this frame, in cells.
func _update_ink_blocks() -> void:
	canvas.blocked.clear()
	for modifier in _modifiers:
		for rect in modifier.ink_blocks():
			var from: Vector2 = _to_cell(rect.position)
			canvas.blocked.append(Rect2(from, _to_cell(rect.end) - from))


func _apply_skin_offset() -> void:
	var offset: Vector2 = Vector2.ZERO
	for modifier in _modifiers:
		offset += modifier.skin_offset()
	_body.position = offset + _flinch


## Mouse position -> needle position: magnet pull and smoothing, then task offsets.
func _update_needle(delta: float) -> void:
	var desired: Vector2 = _machine.pointer
	var pointer_cell: Vector2 = _to_cell(_machine.pointer)
	var target: Vector2 = Vector2.INF
	# `magnet_radius` is in cells of the flat panel; other skins get the same reach on screen.
	var radius: float = magnet_radius * _canvas_rect.pixels_per_cell() / _surface.pixels_per_cell()
	if MECHANICS.magnet and pointer_cell.is_finite():
		target = canvas.find_unfilled_near(pointer_cell, radius, null if _surface == _canvas_rect else _surface)
	if target.is_finite():
		var distance: float = pointer_cell.distance_to(target) / radius
		var pull: float = magnet_strength * (1.0 - distance * distance) # stays strong until near the radius
		desired = _machine.pointer.lerp(_to_screen(target), pull)
	var follow: float = 1.0 - exp(-needle_follow * 2.0 * delta)
	_needle_lead = _needle_lead.lerp(desired, follow)
	_steady_needle = _steady_needle.lerp(_needle_lead, follow)
	var offset: Vector2 = Vector2.ZERO
	var weight: float = machine_mass
	for modifier in _modifiers:
		offset += modifier.needle_offset()
		weight += modifier.machine_weight()
	_machine.needle = _steady_needle + offset + _edge_push
	_machine.weight = weight


func _paint(delta: float) -> void:
	if _turning:
		_machine.working = false
		_was_inking = false
		_was_heating = false
		_update_flow(delta, false)
		return
	var pressing: bool = Input.is_action_pressed("use")
	var clicked: bool = Input.is_action_just_pressed("use")
	if _wait_for_release:
		_wait_for_release = pressing
		pressing = false
		clicked = false
	var cell: Vector2 = _surface.to_cell(_machine.needle)
	var on_skin: bool = cell.is_finite()
	var over_cap: bool = _ink_cap.get_global_rect().has_point(_machine.needle)
	if clicked and over_cap:
		_dip()
	var cartridge: NeedleCartridge = _cartridge_under(_machine.needle)
	if clicked and cartridge != null and not cartridge.taken:
		_swap_needle(cartridge == _thin_cartridge)
	var inking: bool = pressing and not over_cap and cartridge == null \
			and _modifiers.all(func(m: TattooModifier) -> bool: return m.can_ink())
	_machine.working = inking
	_update_flow(delta, inking and _ink_left > 0.0 and on_skin and canvas.is_stencil(cell))
	if inking and _ink_left > 0.0 and on_skin:
		_brush.radius_px = _needle_radius() * (1.0 + flow_brush_bonus * _flow.strength())
		var laid: float
		if _was_inking:
			laid = canvas.stroke_on(_surface, _last_cell, cell, _brush, ink_rate * delta)
		else:
			laid = canvas.stamp_on(_surface, cell, _brush, ink_rate * delta)
		if MECHANICS.ink_supply:
			_ink_left = maxf(0.0, _ink_left - laid)
	_update_edge(delta, inking and on_skin)
	_last_cell = cell
	# Off the skin the stroke breaks, so it never joins two far-apart points.
	_was_inking = inking and on_skin
	_heat_skin(inking, delta)


## The brush's shape and the dots' look, from the exports (`Mechanics.flat_brush` off: the old round brush).
func _setup_brush() -> void:
	var flat: bool = MECHANICS.flat_brush and not _thin
	_brush.thickness = brush_thickness if flat else 1.0
	_brush.radius_px = _needle_radius()
	_paint_view.dots_per_dose = dots_per_second / maxf(ink_rate, 0.001) if flat else 0.0
	_paint_view.core = brush_core if flat else 0.0
	_thick_cartridge.taken = not _thin
	_thin_cartridge.taken = _thin
	_machine.set_needle_color((_thin_cartridge if _thin else _thick_cartridge).color)
	_paint_view.dot_spread = dot_spread
	_paint_view.dot_falloff = dot_falloff
	_paint_view.dot_size_center = dot_size_center
	_paint_view.dot_size_edge = dot_size_edge
	_paint_view.dot_size_jitter = dot_size_jitter
	_paint_view.dot_stretch_max = dot_stretch_max
	_reset_brush()


func _reset_brush() -> void:
	_brush_angle2 = deg_to_rad(brush_rest_angle) * 2.0
	_set_brush_axis()


## Turns the brush across the needle's motion, smoothly; standing or slow, it keeps its angle.
func _update_brush(delta: float) -> void:
	if not brush_follows_motion or _turning:
		_set_brush_axis()
		return
	var velocity: Vector2 = _machine.velocity
	var speed: float = velocity.length()
	if speed > brush_min_speed:
		var wanted: float = velocity.orthogonal().angle() * 2.0
		# just above the threshold it turns gently, so a creeping needle doesn't wobble it
		var eagerness: float = clampf((speed - brush_min_speed) / brush_min_speed, 0.0, 1.0)
		_brush_angle2 = wrapf(_brush_angle2 + angle_difference(_brush_angle2, wanted)
				* (1.0 - exp(-brush_turn_rate * delta)) * eagerness, -PI, PI)
	_set_brush_axis()


func _set_brush_axis() -> void:
	_brush.axis = Vector2.from_angle(_brush_angle2 * 0.5)
	if not brush_follows_motion:
		_brush.axis = Vector2.from_angle(deg_to_rad(brush_rest_angle))
	_machine.brush_axis = _brush.axis
	_machine.brush_size = Vector2(_brush.radius_px, _brush.half_thickness())


## `stroking`: the needle inks over the stencil right now. Flow builds while it also moves.
func _update_flow(delta: float, stroking: bool) -> void:
	stroking = stroking and MECHANICS.flow
	var moving: bool = _machine.velocity.length() > flow_min_speed
	_flow.update(delta, stroking and moving, stroking and not moving)
	_machine.flow = _flow.strength()


func _setup_skin_heat() -> void:
	_heat = SkinHeat.new(skin.size, heat_cell)
	var material: ShaderMaterial = _redness.material
	material.set_shader_parameter("heat", _heat.texture)
	material.set_shader_parameter("pink_from", pink_from)
	material.set_shader_parameter("warn_heat", warn_heat)
	material.set_shader_parameter("danger_heat", danger_heat)
	material.set_shader_parameter("size", skin.size)
	material.set_shader_parameter("corner_radius", _skin_corner_radius())


func _setup_skin_press() -> void:
	var material: ShaderMaterial = _press_rect.material
	material.set_shader_parameter("radius", press_radius)
	material.set_shader_parameter("depth", press_depth)
	material.set_shader_parameter("shade", press_shade)
	material.set_shader_parameter("tint", press_tint)
	material.set_shader_parameter("size", skin.size)
	material.set_shader_parameter("corner_radius", _skin_corner_radius())
	if _surface != _canvas_rect:
		# Not the panel: the dent may show anywhere on the screen.
		_press_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		material.set_shader_parameter("size", _body.size)
		material.set_shader_parameter("corner_radius", 0.0)


## The needle dents the skin while it works, and the picture trembles with the buzz.
## Only the look: ink, heat and the needle itself don't move.
## Hidden at once during a swing: the smear can't see what it draws.
func _update_skin_press(delta: float) -> void:
	if _turning:
		_calm_press()
		return
	var working: bool = MECHANICS.skin_press and _machine.working and _surface.is_on_skin(_machine.needle)
	var time: float = press_in_time if working else press_out_time
	_press = move_toward(_press, 1.0 if working else 0.0, delta / maxf(time, 0.001))
	_press_rect.visible = _press > 0.0
	if not _press_rect.visible:
		return
	var shake: Vector2 = Vector2(randf_range(-skin_buzz, skin_buzz), randf_range(-skin_buzz, skin_buzz)) if working else Vector2.ZERO
	var material: ShaderMaterial = _press_rect.material
	material.set_shader_parameter("tip", _machine.needle - _press_rect.get_global_rect().position)
	material.set_shader_parameter("axis", _brush.axis)
	material.set_shader_parameter("thickness", minf(_brush.thickness * press_widen, 1.0))
	# a thin needle makes a smaller, shallower dent
	var needle_scale: float = _brush.radius_px / maxf(brush_radius, 0.001)
	material.set_shader_parameter("radius", press_radius * needle_scale)
	material.set_shader_parameter("depth", press_depth * needle_scale)
	material.set_shader_parameter("press", smoothstep(0.0, 1.0, _press))
	material.set_shader_parameter("shake", shake)


func _calm_press() -> void:
	_press = 0.0
	_press_rect.visible = false


## The working needle heats the skin under it, ink or no ink.
func _heat_skin(working: bool, delta: float) -> void:
	var point: Vector2 = _machine.needle - skin.get_global_rect().position
	var heating: bool = MECHANICS.skin_heat and _surface.supports_tasks() and working and _is_on_skin(point)
	if heating:
		_heat.heat(_last_heat_point if _was_heating else point, point, heat_radius, heat_rate * delta)
	_last_heat_point = point
	_was_heating = heating


## Whether a skin-local point lies on the rounded skin panel.
func _is_on_skin(point: Vector2) -> bool:
	var radius: float = _skin_corner_radius()
	var half: Vector2 = skin.size * 0.5
	var q: Vector2 = (point - half).abs() - (half - Vector2(radius, radius))
	return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) <= radius


## Warning stages: the red spot throbs with a heartbeat, the client hisses and flinches.
func _update_redness(delta: float) -> void:
	var peak: float = _heat.peak()
	var stage: int = 0
	if peak >= danger_heat:
		stage = 2
	elif peak >= warn_heat:
		stage = 1
	if stage > _skin_stage:
		_wince.pitch_scale = 1.0 if stage == 1 else 1.15
		_wince.play()
		_flinch = Vector2.from_angle(randf() * TAU) * flinch_distance * stage
	_skin_stage = stage
	_flinch = _flinch.lerp(Vector2.ZERO, 1.0 - exp(-20.0 * delta))
	_hud.set_skin_warning(stage)

	var pulse: float = 0.0
	if stage == 0:
		_heartbeat.stop()
	else:
		_heartbeat.pitch_scale = 1.0 if stage == 1 else 1.4
		_heartbeat.volume_db = -14.0 if stage == 1 else -5.0
		if not _heartbeat.playing:
			_heartbeat.play()
		# The spot throbs on the beat: "lub" at 0, "dub" at 0.18 s into the loop.
		var beat: float = _heartbeat.get_playback_position()
		pulse = exp(-beat * 9.0) + 0.7 * exp(-maxf(0.0, beat - 0.18) * 9.0) * float(beat >= 0.18)
	(_redness.material as ShaderMaterial).set_shader_parameter("pulse", minf(1.0, pulse))


## The skin gave out: the client cries out, the spirit snaps from the machine
## and the session starts over with the same stencil and tasks.
func _overheat() -> void:
	_running = false
	_machine.working = false
	_surface.release()
	_was_inking = false
	_calm_skin()
	_calm_press()
	_flow.clear()
	_machine.flow = 0.0
	for modifier in _modifiers:
		modifier.stop()
	_cry.play()
	Transition.flash(Color(0.75, 0.0, 0.05, 0.5), 0.6)
	_body.position += Vector2.from_angle(randf() * TAU) * flinch_distance * 3.0
	create_tween().tween_property(_body, "position", Vector2.ZERO, 0.3) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.6).timeout
	var line: DialogueData = _next_overheat_line()
	if line != null:
		await Dialogue.play(line)
	await Transition.fade_out()
	_restart()
	await Transition.fade_in()
	_running = true


## Everything back to the start: no ink, a full machine, cool skin, fresh tasks, the view on the client.
func _restart() -> void:
	canvas.clear()
	_flush_ink()
	for material in _materials:
		material.set_shader_parameter("done", 0.0)
		material.set_shader_parameter("flash", 0.0)
	_completed_parts = 0
	_ink_left = ink_capacity
	_heat.clear()
	_heat.flush()
	_was_heating = false
	_view.position.x = 0.0
	_at_table = false
	_show_turn_hints()
	_body.position = Vector2.ZERO
	for modifier in _modifiers:
		modifier.queue_free()
	_modifiers.clear()
	_add_modifiers(_tasks)
	_machine.needle = _machine.pointer
	_steady_needle = _machine.pointer
	_needle_lead = _machine.pointer
	_reset_brush()
	# The click that closed the spirit's line may still be held.
	_wait_for_release = true
	_update_ink_display()
	_hud.show_progress(canvas)


func _next_overheat_line() -> DialogueData:
	if overheat_lines.is_empty():
		return null
	if _overheat_bag.is_empty():
		_overheat_bag = overheat_lines.duplicate()
		_overheat_bag.shuffle()
		# A fresh bag never opens with the line just said.
		if _overheat_bag.size() > 1 and _overheat_bag.back() == _last_overheat_line:
			_overheat_bag.push_front(_overheat_bag.pop_back())
	_last_overheat_line = _overheat_bag.pop_back()
	return _last_overheat_line


## Silences the warning: no heartbeat, no throb, no HUD line.
func _calm_skin() -> void:
	_skin_stage = 0
	_flinch = Vector2.ZERO
	_heartbeat.stop()
	_hud.set_skin_warning(0)
	(_redness.material as ShaderMaterial).set_shader_parameter("pulse", 0.0)


## The needle in the machine's brush half length, without flow.
func _needle_radius() -> float:
	return thin_radius if _thin else brush_radius


## The needle cartridge on the side table under a screen point, or null.
func _cartridge_under(point: Vector2) -> NeedleCartridge:
	if not MECHANICS.needle_swap:
		return null
	for cartridge: NeedleCartridge in [_thick_cartridge, _thin_cartridge]:
		if cartridge.get_global_rect().has_point(point):
			return cartridge
	return null


## Puts the needle in the machine back in its slot and takes the other one.
func _swap_needle(thin: bool) -> void:
	_thin = thin
	_setup_brush()
	(_thin_cartridge if thin else _thick_cartridge).flash()
	(_thick_cartridge if thin else _thin_cartridge).flash()
	_needle_swap.play()


## How much of the working brush is past the stencil's edge (`Mechanics.edge_kick`): the skin shakes and the
## machine is pushed back toward the drawing. The thin needle feels it `thin_edge_factor` as much.
func _update_edge(delta: float, inking: bool) -> void:
	var target: Vector2 = Vector2.ZERO
	_edge_amount = 0.0
	if MECHANICS.edge_kick and inking:
		var outside: float = _brush_outside()
		if outside > 0.0:
			_edge_amount = outside * (thin_edge_factor if _thin else 1.0)
			var toward: Vector2 = _to_screen(_stencil_center) - _machine.needle
			target = toward.normalized() * edge_push * _edge_amount
			if _edge_amount > 0.3 and canvas.time - _edge_sound_at > edge_sound_gap:
				_edge_sound_at = canvas.time
				_wince.pitch_scale = randf_range(1.15, 1.35)
				_wince.play()
	var rate: float = edge_rate if target != Vector2.ZERO else edge_return
	_edge_push = _edge_push.lerp(target, 1.0 - exp(-rate * delta))
	# the view shakes like a camera (the machine stays under the mouse); the swing owns it while turning
	if not _turning:
		var shake: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * edge_shake * _edge_amount
		_view.position = Vector2(-table_offset if _at_table else 0.0, 0.0) + shake
	_edge_frame_level = lerpf(_edge_frame_level, minf(_edge_amount * 1.5, 1.0), 1.0 - exp(-edge_frame_rate * delta))
	_edge_frame.visible = _edge_frame_level > 0.01
	(_edge_frame.material as ShaderMaterial).set_shader_parameter("strength", _edge_frame_level)


## Share of five points along the brush (its middle, halfway and its ends) that miss the stencil.
func _brush_outside() -> float:
	var outside: int = 0
	for s: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var cell: Vector2 = _surface.to_cell(_machine.needle + _brush.axis * _brush.radius_px * s)
		if not cell.is_finite() or not canvas.is_stencil(cell):
			outside += 1
	return outside / 5.0


## Centre of the stencil's cells, in cells.
func _find_stencil_center() -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for part in canvas.part_count():
		for cell: int in canvas.part_cells(part):
			sum += Vector2(cell % canvas.size.x, cell / canvas.size.x) + Vector2(0.5, 0.5)
			count += 1
	return sum / count if count > 0 else Vector2(canvas.size) * 0.5


func _skin_corner_radius() -> float:
	var style: StyleBoxFlat = skin.get_theme_stylebox("panel") as StyleBoxFlat
	return minf(style.corner_radius_top_left, minf(skin.size.x, skin.size.y) * 0.5) if style != null else 0.0


## One click in the ink cap: the ink wobbles and the machine takes a share of a full tank.
func _dip() -> void:
	_ink_cap.dip()
	if _ink_left >= ink_capacity:
		return
	_dip_sound.play()
	_ink_left = minf(ink_capacity, _ink_left + ink_capacity / refill_clicks)


func _update_ink_display() -> void:
	var level: float = _ink_left / ink_capacity
	_machine.ink_level = level
	_machine.low_ink = level < low_ink
	_hud.set_ink_empty(level <= 0.0)
	# The cap pulses when the machine runs dry, so it's obvious where to go.
	var pulse: float = 0.0
	if level <= 0.0:
		pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
	_ink_cap.modulate = Color.WHITE.lerp(Color(1.0, 0.75, 0.3), pulse)
	_to_table_hint.modulate = Color(1, 1, 1, 0.7).lerp(Color(1.0, 0.75, 0.3), pulse)


## A quick swing with a horizontal smear to the side table or back, on Q.
## The machine never moves by itself: it stays under the mouse the whole time.
func _turn(to_table: bool) -> void:
	if _turning:
		return
	_turning = true
	_to_table_hint.visible = false
	_to_client_hint.visible = false
	_blur.visible = true
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(_view, "position:x", -table_offset if to_table else 0.0, turn_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_blur, 0.0, 1.0, turn_time)
	await tween.finished
	_blur.visible = false
	_at_table = to_table
	if not to_table:
		_wait_for_release = Input.is_action_pressed("use")
	_show_turn_hints()
	_turning = false


## Each view shows only the way to the other one.
## Without the ink supply there's no reason to turn, so no hints.
func _show_turn_hints() -> void:
	var table_needed: bool = MECHANICS.ink_supply or MECHANICS.needle_swap
	_to_table_hint.visible = table_needed and not _at_table
	_to_client_hint.visible = table_needed and _at_table


## Peaks halfway through the swing.
func _set_blur(progress: float) -> void:
	(_blur.material as ShaderMaterial).set_shader_parameter("strength", sin(progress * PI))


## Uploads the grid and hands this frame's stamps (or a wipe) to the screen-resolution look.
func _flush_ink() -> void:
	if canvas.cleared:
		canvas.cleared = false
		_paint_view.clear_ink()
	_paint_view.set_blocks(canvas.blocked)
	_paint_view.add_ink(canvas.dabs, canvas.strokes)
	canvas.dabs.clear()
	canvas.strokes.clear()
	canvas.flush()


func _to_cell(screen_position: Vector2) -> Vector2:
	return _surface.to_cell(screen_position)


func _to_screen(cell: Vector2) -> Vector2:
	var placed: Vector3 = _surface.project(cell)
	return Vector2(placed.x, placed.y)


## The stencil picks its skin. Another surface takes the place of the flat panel and its redness.
func _setup_surface() -> void:
	if _surface != null:
		return
	var path: String = SURFACE_SCENES.get(stencil.surface, "")
	if path.is_empty():
		_surface = _canvas_rect
	else:
		_surface = (load(path) as PackedScene).instantiate()
		_body.add_child(_surface)
		_body.move_child(_surface, 0)
		_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		skin.visible = false
		_canvas_rect.visible = false
		_redness.visible = false
	_surface.setup(stencil)


## PowerWash "ping": what still needs ink glows once and fades.
func _ping_highlight() -> void:
	if _highlight_tween != null:
		_highlight_tween.kill()
	_highlight_tween = create_tween()
	_highlight_tween.tween_method(_set_highlight, 0.0, 1.0, 0.15)
	_highlight_tween.tween_method(_set_highlight, 1.0, 0.0, 1.2)


func _set_highlight(value: float) -> void:
	for material in _materials:
		material.set_shader_parameter("highlight", value)
	if _surface != null and canvas != null:
		_surface.set_highlight(value, canvas)


func _on_part_completed(index: int) -> void:
	_materials[index].set_shader_parameter("done", 1.0)
	_flash(_materials[index])
	_hud.flash_part(index)
	# Each completed part rings a whole tone higher.
	_ding.pitch_scale = pow(2.0, _completed_parts * 2.0 / 12.0)
	_ding.play()
	_completed_parts += 1


func _flash(material: ShaderMaterial, color: Color = Color.WHITE) -> void:
	material.set_shader_parameter("flash_color", color)
	var tween: Tween = create_tween()
	tween.tween_method(func(v: float) -> void: material.set_shader_parameter("flash", v), 0.8, 0.0, 0.6)


func _finish() -> void:
	_running = false
	_machine.working = false
	_surface.release()
	_calm_skin()
	_calm_press()
	_flow.clear()
	_machine.flow = 0.0
	_machine.weight = 0.0
	_machine.visible = false
	_set_highlight(0.0)
	for material in _materials:
		_flash(material)

	_result = SessionResult.new()
	for modifier in _modifiers:
		modifier.stop()
		_result.tasks.append(modifier.data)
		_result.passed.append(modifier.is_passed())
	_body.position = Vector2.ZERO
	_hud.show_done(_result)
	_done_msec = Time.get_ticks_msec()
	_waiting_for_close = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
