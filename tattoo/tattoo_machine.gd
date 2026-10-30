class_name TattooMachine
extends Node2D
## Tattoo machine shown in place of the mouse cursor. The needle tip is at the node origin.
## It reports the mouse (`pointer`); the session says where the hand wants the needle (`needle`),
## and the machine follows on a spring, so it feels heavy: reading `needle` gives where it really is.
## The look is the 3D model in a full-screen perspective `Model` SubViewport, drawn by `Sprite`:
## the camera looks down at the skin plane (z = 0) and the needle tip touches it under `needle`.
## The artist is right-handed: the machine stands upright at the left edge of the screen and
## lies lower towards the right. Its top swings behind the motion.

## Needle tip in the model's mesh coordinates (the leftmost point of IGLA_RL).
const NEEDLE_TIP: Vector3 = Vector3(-5.1824, 1.4684, 0.0325)
## The far end of the machine body (its rightmost point), where a flame can burn.
const TOP: Vector3 = Vector3(2.5117, 1.0952, 0.0206)
## Longest step of the spring simulation. The needle spring is stiff: stepped once per frame below
## ~35 fps it overshoots more every frame and the machine jumps back and forth across the screen.
const MAX_STEP: float = 1.0 / 120.0

## Visual buzz while working, in pixels. Doesn't move where the ink goes.
@export var buzz: float = 1.5
@export var model_scale: float = 0.45

@export_group("Hold")
## Angle to the skin at the left edge of the screen, in degrees (90 = straight up).
@export_range(0.0, 90.0) var angle_at_left: float = 60.0
## Angle to the skin at the right edge of the screen, in degrees.
@export_range(0.0, 90.0) var angle_at_right: float = 30.0
## Which way the top of the machine points over the skin (x right, y up on screen).
@export var hold_heading: Vector2 = Vector2(0.65, 0.75)

@export_group("Weight")
## How quickly the needle catches up with the hand, in radians per second. Lower feels heavier.
@export var follow_frequency: float = 33.0
## 1 settles without overshoot; below 1 the needle overshoots a little before settling.
@export var follow_damping: float = 0.75
## A jump longer than this (in pixels) is a teleport: no spring.
@export var snap_distance: float = 300.0
## How far the top trails behind the motion, in radians per pixel/second.
@export var lean_per_speed: float = 0.0006
@export var max_lean: float = 0.45
## The top's own spring: lower frequency and damping make it swing more.
@export var swing_frequency: float = 9.0
@export var swing_damping: float = 0.4

var working: bool = false
## Extra mass on the machine (spirit tasks add it); 0 = just the machine. Both springs slow down with it.
var weight: float = 0.0
## Mouse position in viewport pixels.
var pointer: Vector2 = Vector2.ZERO
## Set: where the hand wants the needle. Get: where the needle actually is.
var needle: Vector2:
	set(value):
		_target = value
	get:
		return _position
## Ink left, 0..1, shown on the gauge beside the machine.
var ink_level: float = 1.0:
	set(value):
		if not is_equal_approx(value, ink_level):
			ink_level = value
			queue_redraw()
var low_ink: bool = false
## How fast the needle really moves, in pixels per second. Zero right after a teleport.
var velocity: Vector2:
	get:
		return _velocity

var _target: Vector2 = Vector2.ZERO
var _position: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
## How far the top leans from the hold direction (screen axes), and how fast it's swinging.
var _lean: Vector2 = Vector2.ZERO
var _lean_velocity: Vector2 = Vector2.ZERO

@onready var _spray: CPUParticles2D = $Spray
@onready var _hum: AudioStreamPlayer = $Hum
@onready var _view: SubViewport = $Model
@onready var _camera: Camera3D = $Model/Camera3D
@onready var _model: Node3D = $Model/TattooMachineModel


func _ready() -> void:
	pointer = get_viewport().get_mouse_position()
	_target = pointer
	_position = pointer


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position


func _process(delta: float) -> void:
	_simulate(delta)
	var shake: Vector2 = Vector2.ZERO
	if working:
		shake = Vector2(randf_range(-buzz, buzz), randf_range(-buzz, buzz))
	global_position = _position + shake
	_place_model(_position + shake)

	var dry: bool = ink_level <= 0.0
	_spray.emitting = working and not dry
	_hum.pitch_scale = 0.8 if dry else 1.0 # a dry machine sounds hollow
	if working and not _hum.playing:
		_hum.play()
	elif not working and _hum.playing:
		_hum.stop()


## Mass on a spring: the needle chases the hand, the top chases its lean.
## Long frames are split into short steps, so it feels the same and stays stable at any frame rate.
func _simulate(delta: float) -> void:
	if _position.distance_to(_target) > snap_distance:
		_position = _target
		_velocity = Vector2.ZERO
	var steps: int = maxi(1, ceili(delta / MAX_STEP))
	for i in steps:
		_step(delta / steps)


func _step(delta: float) -> void:
	# A mass on a spring: frequency falls with the square root of the mass.
	var heavy: float = 1.0 / sqrt(1.0 + weight)
	_velocity += _spring(_target - _position, _velocity, follow_frequency * heavy, follow_damping) * delta
	_position += _velocity * delta

	var lean_target: Vector2 = (-_velocity * lean_per_speed).limit_length(max_lean)
	_lean_velocity += _spring(lean_target - _lean, _lean_velocity, swing_frequency * heavy, swing_damping) * delta
	_lean += _lean_velocity * delta


func _spring(offset: Vector2, velocity: Vector2, frequency: float, damping: float) -> Vector2:
	return offset * frequency * frequency - velocity * 2.0 * damping * frequency


## Where the top end of the machine (`TOP`) is on screen, in viewport pixels.
func top_position() -> Vector2:
	return _camera.unproject_position(_model.global_transform * TOP)


## Puts the model so its needle tip touches the skin plane right under `screen_point`.
func _place_model(screen_point: Vector2) -> void:
	var screen_size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	if _view.size != screen_size:
		_view.size = screen_size
	var from: Vector3 = _camera.project_ray_origin(screen_point)
	var direction: Vector3 = _camera.project_ray_normal(screen_point)
	var touch: Vector3 = from + direction * (-from.z / direction.z)
	var hold: Basis = _hold_basis(screen_point.x / screen_size.x)
	_model.global_transform = Transform3D(hold, touch - hold * NEEDLE_TIP)


## The model's +X runs from the needle up the machine; its side (+Z) faces the camera as much
## as the tilt allows. `across` is 0 at the left edge of the screen and 1 at the right.
func _hold_basis(across: float) -> Basis:
	var angle: float = deg_to_rad(lerpf(angle_at_left, angle_at_right, clampf(across, 0.0, 1.0)))
	var heading: Vector3 = Vector3(hold_heading.x, hold_heading.y, 0.0).normalized()
	# Screen y points down, the view's y up.
	var along: Vector3 = (heading * cos(angle) + Vector3.BACK * sin(angle) + Vector3(_lean.x, -_lean.y, 0.0)).normalized()
	var side: Vector3 = Vector3.BACK * cos(angle) - heading * sin(angle) # well defined even when upright
	side = (side - along * side.dot(along)).normalized()
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
