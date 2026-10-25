class_name TattooSession
extends CanvasLayer
## Tattoo mini-game screen. Add it to the tree and call start(stencil);
## `finished` fires once the player closes the result screen. The caller frees it.
## Running this scene on its own starts it with `stencil` and restarts after the result.

signal finished(result: TattooResult)

@export var stencil: StencilData

@export_group("Tuning")
## Needle size in grid cells; the grid is InkCanvas.SIZE cells wide.
@export var brush_radius: float = 6.0
## Ink per second under the needle centre; 1.0 fills a cell.
@export var ink_rate: float = 5.0
@export_range(0.5, 1.0) var completion_threshold: float = 0.97
## Cells around the stencil where ink doesn't count as a mistake.
@export var edge_tolerance: int = 2
## Highest mistake share of the stencil area for each grade.
@export var perfect_mistake_ratio: float = 0.01
@export var good_mistake_ratio: float = 0.05
@export var stencil_color: Color = Color(0.55, 0.3, 0.75, 0.5)

var canvas: InkCanvas

var _running: bool = false
var _elapsed: float = 0.0
var _was_inking: bool = false
var _last_cell: Vector2 = Vector2.ZERO
var _highlight_refresh: float = 0.0
var _result: TattooResult = null
var _result_shown_msec: int = 0

@onready var _canvas_rect: Control = $Canvas
@onready var _stencil_layer: Control = $Canvas/Stencil
@onready var _highlight: TextureRect = $Canvas/Highlight
@onready var _ink: TextureRect = $Canvas/Ink
@onready var _machine: TattooMachine = $Machine
@onready var _hud: Control = $HUD


func _ready() -> void:
	_highlight.modulate.a = 0.0
	_start_if_main_scene.call_deferred()


func _start_if_main_scene() -> void:
	if get_tree().current_scene == self and stencil != null and canvas == null:
		finished.connect(func(_done: TattooResult) -> void: get_tree().reload_current_scene())
		start(stencil)


func start(new_stencil: StencilData) -> void:
	stencil = new_stencil
	canvas = InkCanvas.new(stencil, completion_threshold, edge_tolerance)
	canvas.part_completed.connect(_hud.flash_part)

	var part_names: PackedStringArray = PackedStringArray()
	for part in stencil.parts:
		part_names.append(part.display_name)
		var rect: TextureRect = TextureRect.new()
		rect.texture = part.texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.modulate = stencil_color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stencil_layer.add_child(rect)
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ink.texture = canvas.texture
	_hud.setup(part_names)
	_hud.show_progress(canvas)

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_paint(delta)
	_update_highlight(delta)
	canvas.flush()
	_hud.show_progress(canvas)
	if canvas.is_complete():
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	# The short delay keeps a click from the last stroke from closing the result at once.
	if _result != null and event.is_action_pressed("use") \
			and Time.get_ticks_msec() - _result_shown_msec > 500:
		get_viewport().set_input_as_handled()
		var result: TattooResult = _result
		_result = null
		finished.emit(result)


func _paint(delta: float) -> void:
	var inking: bool = Input.is_action_pressed("use")
	_machine.working = inking
	var cell: Vector2 = _to_cell(_machine.needle_position())
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


func _update_highlight(delta: float) -> void:
	if not Input.is_action_pressed("highlight"):
		_highlight_refresh = 0.0
		_highlight.modulate.a = 0.0
		return
	_highlight_refresh -= delta
	if _highlight_refresh <= 0.0:
		_highlight.texture = ImageTexture.create_from_image(canvas.make_remaining_image())
		_highlight_refresh = 0.25
	_highlight.modulate.a = 0.35 + 0.25 * sin(_elapsed * 10.0)


func _finish() -> void:
	_running = false
	_machine.working = false
	_machine.visible = false
	_highlight.modulate.a = 0.0

	_result = TattooResult.new()
	_result.time = _elapsed
	_result.mistakes = canvas.mistakes
	_result.mistake_ratio = float(canvas.mistakes) / maxi(1, canvas.stencil_cell_count())
	if _result.mistake_ratio <= perfect_mistake_ratio:
		_result.grade = TattooResult.Grade.PERFECT
	elif _result.mistake_ratio <= good_mistake_ratio:
		_result.grade = TattooResult.Grade.GOOD
	else:
		_result.grade = TattooResult.Grade.BAD

	_hud.show_result(_result)
	_result_shown_msec = Time.get_ticks_msec()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
