class_name TattooMachine
extends Node2D
## Tattoo machine shown in place of the mouse cursor. The needle tip is at the node origin.
## It only reports the mouse (`pointer`); the session decides where the needle goes (`needle`).
## The look is the 3D model in a full-screen perspective `Model` SubViewport, drawn by `Sprite`:
## the camera looks down at the skin plane (z = 0) and the needle tip touches it under `needle`,
## so the machine is seen from a different angle in every part of the screen.

## Needle tip in the model's mesh coordinates (the leftmost point of IGLA_RL).
const NEEDLE_TIP: Vector3 = Vector3(-5.1824, 1.4684, 0.0325)

## Visual buzz while working, in pixels. Doesn't move where the ink goes.
@export var buzz: float = 1.5
@export var model_scale: float = 0.45
## Direction from the needle tip up the machine, held like a pen. The camera looks along -Z.
@export var hold_direction: Vector3 = Vector3(0.55, 0.65, 0.5)
## How far the top of the machine trails behind the motion, in radians per pixel/second.
@export var lean_per_speed: float = 0.0005
@export var max_lean: float = 0.35

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

var _velocity: Vector2 = Vector2.ZERO
var _last_needle: Vector2 = Vector2.ZERO

@onready var _spray: CPUParticles2D = $Spray
@onready var _hum: AudioStreamPlayer = $Hum
@onready var _view: SubViewport = $Model
@onready var _camera: Camera3D = $Model/Camera3D
@onready var _model: Node3D = $Model/TattooMachineModel


func _ready() -> void:
	pointer = get_viewport().get_mouse_position()
	needle = pointer
	_last_needle = needle


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position


func _process(delta: float) -> void:
	var shake: Vector2 = Vector2.ZERO
	if working:
		shake = Vector2(randf_range(-buzz, buzz), randf_range(-buzz, buzz))
	global_position = needle + shake
	if delta > 0.0:
		var velocity: Vector2 = (needle - _last_needle) / delta
		_velocity = _velocity.lerp(velocity, 1.0 - exp(-8.0 * delta))
	_last_needle = needle
	_place_model(needle + shake)

	var dry: bool = ink_level <= 0.0
	_spray.emitting = working and not dry
	_hum.pitch_scale = 0.8 if dry else 1.0 # a dry machine sounds hollow
	if working and not _hum.playing:
		_hum.play()
	elif not working and _hum.playing:
		_hum.stop()


## Puts the model so its needle tip touches the skin plane right under `screen_point`.
func _place_model(screen_point: Vector2) -> void:
	var screen_size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	if _view.size != screen_size:
		_view.size = screen_size
	var from: Vector3 = _camera.project_ray_origin(screen_point)
	var direction: Vector3 = _camera.project_ray_normal(screen_point)
	var touch: Vector3 = from + direction * (-from.z / direction.z)
	var hold: Basis = _hold_basis()
	_model.global_transform = Transform3D(hold, touch - hold * NEEDLE_TIP)


## The model's +X runs from the needle up the machine; its side (+Z) faces the camera.
func _hold_basis() -> Basis:
	# Screen y points down, the view's y up. The top trails behind the motion.
	var lean: Vector2 = (_velocity * lean_per_speed).limit_length(max_lean)
	var along: Vector3 = (hold_direction.normalized() - Vector3(lean.x, -lean.y, 0.0)).normalized()
	var side: Vector3 = (Vector3.BACK - along * along.z).normalized()
	var up: Vector3 = side.cross(along)
	return Basis(along, up, side).scaled(Vector3.ONE * model_scale)


func _draw() -> void:
	_draw_gauge()


## Vertical ink gauge up and to the left of the needle, clear of the machine body.
func _draw_gauge() -> void:
	var frame: Rect2 = Rect2(Vector2(-34, -150), Vector2(8, 56))
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
