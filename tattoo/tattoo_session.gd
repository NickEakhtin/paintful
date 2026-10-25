class_name TattooSession
extends CanvasLayer
## Tattoo mini-game screen, modeled on PowerWash Simulator: no timer, no penalties,
## ink only lands inside the stencil and the needle is pulled toward what's left.
## Add it to the tree and call start(stencil); `finished` fires once the player closes
## the "done" panel. The caller frees it and restores the mouse mode.
## Running this scene on its own starts it with `stencil` and restarts when done.

signal finished

const INK_SHADER: Shader = preload("res://tattoo/stencil_ink.gdshader")

@export var stencil: StencilData

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

var canvas: InkCanvas

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

@onready var _canvas_rect: Control = $Canvas
@onready var _stencil_layer: Control = $Canvas/Stencil
@onready var _machine: TattooMachine = $Machine
@onready var _hud: Control = $HUD
@onready var _ding: AudioStreamPlayer = $Ding
@onready var _dip_sound: AudioStreamPlayer = $DipSound
@onready var _ink_cap: Control = $InkCap


func _ready() -> void:
	_start_if_main_scene.call_deferred()


func _start_if_main_scene() -> void:
	if get_tree().current_scene == self and stencil != null and canvas == null:
		finished.connect(get_tree().reload_current_scene)
		start(stencil)


func start(new_stencil: StencilData) -> void:
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

	_machine.needle = _machine.pointer
	_ink_left = ink_capacity
	_update_ink_display()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_update_needle(delta)
	_paint(delta)
	_update_ink_display()
	canvas.flush()
	_hud.show_progress(canvas)
	if canvas.is_complete():
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _running and event.is_action_pressed("highlight"):
		_ping_highlight()
	# The delay keeps the end of the last stroke from closing the panel at once.
	elif _waiting_for_close and event.is_action_pressed("use") \
			and Time.get_ticks_msec() - _done_msec > 1000:
		get_viewport().set_input_as_handled()
		_waiting_for_close = false
		finished.emit()


## Mouse position -> needle position. Spirit tasks (step 3) will add their offsets here.
func _update_needle(delta: float) -> void:
	var desired: Vector2 = _machine.pointer
	var pointer_cell: Vector2 = _to_cell(_machine.pointer)
	var target: Vector2 = canvas.find_unfilled_near(pointer_cell, magnet_radius)
	if target.is_finite():
		var distance: float = pointer_cell.distance_to(target) / magnet_radius
		var pull: float = magnet_strength * (1.0 - distance * distance) # stays strong until near the radius
		desired = _machine.pointer.lerp(_to_screen(target), pull)
	_machine.needle = _machine.needle.lerp(desired, 1.0 - exp(-needle_follow * delta))


func _paint(delta: float) -> void:
	var pressing: bool = Input.is_action_pressed("use")
	var cell: Vector2 = _to_cell(_machine.needle)
	var over_cap: bool = _ink_cap.get_global_rect().has_point(_machine.needle)
	_set_dipping(pressing and over_cap)
	if _dipping:
		_ink_left = minf(ink_capacity, _ink_left + ink_capacity / refill_time * delta)
	var inking: bool = pressing and not over_cap
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


func _flash(material: ShaderMaterial) -> void:
	var tween: Tween = create_tween()
	tween.tween_method(func(v: float) -> void: material.set_shader_parameter("flash", v), 0.8, 0.0, 0.6)


func _finish() -> void:
	_running = false
	_machine.working = false
	_machine.visible = false
	_set_highlight(0.0)
	for material in _materials:
		_flash(material)
	_hud.show_done()
	_done_msec = Time.get_ticks_msec()
	_waiting_for_close = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
