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

@export var stencil: StencilData
## Testing shortcut: F3 finishes the tattoo and closes the session at once. Turn off for release.
@export var debug_skip_enabled: bool = true

@export_group("Spirit tasks")
## What the roulette can land on.
@export var task_pool: Array[ModifierData] = []
## When set, running this scene on its own skips the roulette and uses these, e.g. to tune one task.
@export var fixed_tasks: Array[ModifierData] = []

@export_group("Tuning")
## Needle size in grid cells; the grid is InkCanvas.SIZE cells wide.
@export var brush_radius: float = 9.0
## Ink per second under the needle centre; 1.0 fills a cell.
@export var ink_rate: float = 4.0
@export_range(0.5, 1.0) var completion_threshold: float = 0.97
## How far (in cells) the needle feels the pull of unfilled stencil.
@export var magnet_radius: float = 14.0
## Share of the way to the target the needle moves when right next to it.
@export_range(0.0, 1.0) var magnet_strength: float = 0.85
## How fast the needle catches up with where it should be; higher is snappier.
@export var needle_follow: float = 25.0

@export_group("Ink supply")
## Ink the machine holds, in filled-cell units (the sigil is about 18 700 cells).
@export var ink_capacity: float = 3000.0
## Seconds to fill an empty machine while holding LMB over the ink cap.
@export var refill_time: float = 0.6
## Share of the tank below which the gauge warns.
@export_range(0.0, 1.0) var low_ink: float = 0.25
## The ink cap stands on a side table off screen to the right; the view swings this far to see it.
@export var table_offset: float = 900.0
## Seconds for the swing either way.
@export var turn_time: float = 0.22
## Moving the machine this close to the screen edge swings the view, in pixels.
@export var turn_edge: float = 40.0

var canvas: InkCanvas
## The skin panel; tasks may tint it.
@onready var skin: Panel = $View/Body/Skin

var _ink_left: float = 0.0
var _dipping: bool = false
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
var _result: SessionResult = null
var _at_table: bool = false
var _turning: bool = false
## After the swing back, LMB must be let go once before it inks again.
var _wait_for_release: bool = false

@onready var _view: Control = $View
@onready var _body: Control = $View/Body
@onready var _canvas_rect: Control = $View/Body/Canvas
@onready var _stencil_layer: Control = $View/Body/Canvas/Stencil
@onready var _modifier_layer: Node2D = $View/Body/Modifiers
@onready var _machine: TattooMachine = $Machine
@onready var _hud: Control = $HUD
@onready var _ding: AudioStreamPlayer = $Ding
@onready var _dip_sound: AudioStreamPlayer = $DipSound
@onready var _ink_cap: InkCap = $View/InkCap
@onready var _to_table_hint: Label = $View/ToTable
@onready var _to_client_hint: Label = $View/ToClient
@onready var _blur: ColorRect = $MotionBlur


func _ready() -> void:
	_machine.visible = false
	_start_if_main_scene.call_deferred()


func _start_if_main_scene() -> void:
	if get_tree().current_scene == self and stencil != null and canvas == null:
		finished.connect(func(_done: SessionResult) -> void: get_tree().reload_current_scene())
		if fixed_tasks.is_empty():
			roll_and_start(stencil)
		else:
			start(stencil, fixed_tasks)


## Lets the spirit spin the roulette over the bare skin, then starts with what came up.
func roll_and_start(new_stencil: StencilData) -> void:
	var roulette: Roulette = ROULETTE_SCENE.instantiate()
	add_child(roulette)
	var tasks: Array[ModifierData] = await roulette.spin(task_pool)
	roulette.queue_free()
	start(new_stencil, tasks)


## `tasks` may repeat a task: each repeat raises its intensity.
func start(new_stencil: StencilData, tasks: Array[ModifierData] = []) -> void:
	stencil = new_stencil
	canvas = InkCanvas.new(stencil, completion_threshold)
	canvas.part_completed.connect(_on_part_completed)

	var part_names: PackedStringArray = PackedStringArray()
	for part in stencil.parts:
		part_names.append(part.display_name)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = INK_SHADER
		material.set_shader_parameter("coverage", canvas.texture)
		_materials.append(material)
		var rect: TextureRect = TextureRect.new()
		rect.texture = part.texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.material = material
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stencil_layer.add_child(rect)
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.setup(part_names)
	_hud.show_progress(canvas)
	_add_modifiers(tasks)

	_machine.visible = true
	_machine.needle = _machine.pointer
	_steady_needle = _machine.pointer
	_show_turn_hints()
	_ink_left = ink_capacity
	_update_ink_display()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_running = true


func _process(delta: float) -> void:
	# Nothing happens while the screen fades in or out around the session.
	if not _running or Transition.is_busy:
		return
	_apply_skin_offset()
	_check_turn()
	_update_needle(delta)
	_paint(delta)
	_update_ink_display()
	canvas.flush()
	_hud.show_progress(canvas)
	_hud.show_tasks(_modifiers)
	if canvas.is_complete():
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if Transition.is_busy:
		return
	if _running and debug_skip_enabled and event is InputEventKey and event.pressed \
			and not event.echo and event.physical_keycode == KEY_F3:
		get_viewport().set_input_as_handled()
		skip()
	elif _running and event.is_action_pressed("highlight"):
		_ping_highlight()
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
	for part in canvas.part_count():
		for cell in canvas._part_cells[part]:
			@warning_ignore("integer_division")
			canvas.stamp(Vector2(cell % InkCanvas.SIZE + 0.5, cell / InkCanvas.SIZE + 0.5), 0.5, 1.0)
	canvas.flush()
	_finish()
	_waiting_for_close = false
	finished.emit(_result)


## Where the needle touches, in viewport pixels.
func needle_position() -> Vector2:
	return _machine.needle


## Where the mouse is, in viewport pixels.
func pointer_position() -> Vector2:
	return _machine.pointer


## How fast the needle really moves, in viewport pixels per second.
func needle_velocity() -> Vector2:
	return _machine.velocity


## Where the top end of the machine is, in viewport pixels.
func machine_top_position() -> Vector2:
	return _machine.top_position()


## Takes the ink off every part that isn't done yet; done parts stay. They flash in `color`.
func wipe_unfinished(color: Color) -> void:
	for part in canvas.part_count():
		if not canvas.is_part_done(part):
			canvas.clear_part(part)
			_flash(_materials[part], color)


func _add_modifiers(tasks: Array[ModifierData]) -> void:
	var counts: Dictionary[ModifierData, int] = {}
	for task in tasks:
		counts[task] = counts.get(task, 0) + 1
	for task in counts:
		var modifier: TattooModifier = task.scene.instantiate()
		modifier.session = self
		modifier.data = task
		modifier.intensity = counts[task]
		_modifiers.append(modifier)
		_modifier_layer.add_child(modifier)
	_hud.setup_tasks(_modifiers)


func _apply_skin_offset() -> void:
	var offset: Vector2 = Vector2.ZERO
	for modifier in _modifiers:
		offset += modifier.skin_offset()
	_body.position = offset


## Mouse position -> needle position: magnet pull and smoothing, then task offsets.
func _update_needle(delta: float) -> void:
	var desired: Vector2 = _machine.pointer
	var pointer_cell: Vector2 = _to_cell(_machine.pointer)
	var target: Vector2 = canvas.find_unfilled_near(pointer_cell, magnet_radius)
	if target.is_finite():
		var distance: float = pointer_cell.distance_to(target) / magnet_radius
		var pull: float = magnet_strength * (1.0 - distance * distance) # stays strong until near the radius
		desired = _machine.pointer.lerp(_to_screen(target), pull)
	_steady_needle = _steady_needle.lerp(desired, 1.0 - exp(-needle_follow * delta))
	var offset: Vector2 = Vector2.ZERO
	for modifier in _modifiers:
		offset += modifier.needle_offset()
	_machine.needle = _steady_needle + offset


func _paint(delta: float) -> void:
	if _turning:
		_machine.working = false
		_was_inking = false
		return
	var pressing: bool = Input.is_action_pressed("use")
	if _wait_for_release:
		_wait_for_release = pressing
		pressing = false
	var cell: Vector2 = _to_cell(_machine.needle)
	var over_cap: bool = _ink_cap.get_global_rect().has_point(_machine.needle)
	_set_dipping(pressing and over_cap)
	if _dipping:
		_ink_left = minf(ink_capacity, _ink_left + ink_capacity / refill_time * delta)
	var inking: bool = pressing and not over_cap and _modifiers.all(func(m: TattooModifier) -> bool: return m.can_ink())
	_machine.working = inking
	if inking and _ink_left > 0.0:
		var laid: float
		if _was_inking:
			laid = canvas.stroke(_last_cell, cell, brush_radius, ink_rate * delta)
		else:
			laid = canvas.stamp(cell, brush_radius, ink_rate * delta)
		_ink_left = maxf(0.0, _ink_left - laid)
	_last_cell = cell
	_was_inking = inking


func _set_dipping(dipping: bool) -> void:
	if dipping and not _dipping and _ink_left < ink_capacity:
		_dip_sound.play()
	_dipping = dipping
	_ink_cap.set_dipping(dipping)


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


## The machine at the right screen edge swings the view to the side table, at the left edge back.
func _check_turn() -> void:
	if _turning:
		return
	var pointer: Vector2 = _machine.pointer
	if not _at_table:
		if pointer.x >= get_viewport().get_visible_rect().size.x - turn_edge:
			_turn(true)
	elif pointer.x <= turn_edge:
		_turn(false)


## A quick swing with a horizontal smear, only when the player moves to a screen edge.
## The machine never moves by itself: it stays under the mouse the whole time.
func _turn(to_table: bool) -> void:
	if _turning:
		return
	_turning = true
	_set_dipping(false)
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
func _show_turn_hints() -> void:
	_to_table_hint.visible = not _at_table
	_to_client_hint.visible = _at_table


## Peaks halfway through the swing.
func _set_blur(progress: float) -> void:
	(_blur.material as ShaderMaterial).set_shader_parameter("strength", sin(progress * PI))


func _to_cell(screen_position: Vector2) -> Vector2:
	var rect: Rect2 = _canvas_rect.get_global_rect()
	return (screen_position - rect.position) / rect.size * InkCanvas.SIZE


func _to_screen(cell: Vector2) -> Vector2:
	var rect: Rect2 = _canvas_rect.get_global_rect()
	return rect.position + cell / InkCanvas.SIZE * rect.size


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
	_machine.visible = false
	_set_highlight(0.0)
	for material in _materials:
		_flash(material)

	_result = SessionResult.new()
	for modifier in _modifiers:
		modifier.stop()
		_result.tasks.append(modifier.data)
		_result.intensities.append(modifier.intensity)
		_result.passed.append(modifier.is_passed())
	_body.position = Vector2.ZERO
	_hud.show_done(_result)
	_done_msec = Time.get_ticks_msec()
	_waiting_for_close = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
