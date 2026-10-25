class_name TattooMachine
extends Node2D
## Tattoo machine drawn in place of the mouse cursor. The needle tip is at the node origin.
## It only reports the mouse (`pointer`); the session decides where the needle goes (`needle`).

## Visual buzz while working, in pixels. Doesn't move where the ink goes.
@export var buzz: float = 1.5

var working: bool = false
## Mouse position in viewport pixels.
var pointer: Vector2 = Vector2.ZERO
## Where the needle actually is; set by the session every frame.
var needle: Vector2 = Vector2.ZERO
## Ink left, 0..1, shown on the gauge beside the machine.
var ink_level: float = 1.0:
	set(value):
		if not is_equal_approx(value, ink_level):
			ink_level = value
			queue_redraw()
var low_ink: bool = false

@onready var _spray: CPUParticles2D = $Spray
@onready var _hum: AudioStreamPlayer = $Hum


func _ready() -> void:
	pointer = get_viewport().get_mouse_position()
	needle = pointer


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position


func _process(_delta: float) -> void:
	var shake: Vector2 = Vector2.ZERO
	if working:
		shake = Vector2(randf_range(-buzz, buzz), randf_range(-buzz, buzz))
	global_position = needle + shake
	var dry: bool = ink_level <= 0.0
	_spray.emitting = working and not dry
	_hum.pitch_scale = 0.8 if dry else 1.0 # a dry machine sounds hollow
	if working and not _hum.playing:
		_hum.play()
	elif not working and _hum.playing:
		_hum.stop()


func _draw() -> void:
	# Placeholder art: needle, grip and coil body, leaning right like a pen.
	draw_line(Vector2.ZERO, Vector2(10, -28), Color(0.8, 0.8, 0.85), 2.0)
	draw_line(Vector2(10, -28), Vector2(26, -74), Color(0.22, 0.22, 0.27), 10.0)
	draw_circle(Vector2(36, -98), 17.0, Color(0.55, 0.12, 0.15))
	draw_circle(Vector2.ZERO, 2.0, Color(0.95, 0.25, 0.25))
	_draw_gauge()


## Vertical ink gauge to the right of the body.
func _draw_gauge() -> void:
	var frame: Rect2 = Rect2(Vector2(58, -126), Vector2(8, 56))
	draw_rect(frame.grow(2.0), Color(0, 0, 0, 0.7))
	var fill_height: float = frame.size.y * ink_level
	var color: Color = Color(0.35, 0.55, 1.0)
	if ink_level <= 0.0:
		color = Color(0.95, 0.2, 0.2)
	elif low_ink:
		color = Color(1.0, 0.65, 0.2)
	draw_rect(Rect2(frame.position + Vector2(0, frame.size.y - fill_height), Vector2(frame.size.x, fill_height)), color)
	if ink_level <= 0.0:
		draw_rect(frame, color, false, 2.0)
