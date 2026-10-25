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

var canvas: InkCanvas

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
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_update_needle(delta)
	_paint(delta)
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
	var inking: bool = Input.is_action_pressed("use")
	_machine.working = inking
	var cell: Vector2 = _to_cell(_machine.needle)
	if inking:
		if _was_inking:
			canvas.stroke(_last_cell, cell, brush_radius, ink_rate * delta)
		else:
			canvas.stamp(cell, brush_radius, ink_rate * delta)
	_last_cell = cell
	_was_inking = inking


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
