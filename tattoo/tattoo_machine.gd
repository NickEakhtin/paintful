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
	_spray.emitting = working
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
