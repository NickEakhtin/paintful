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

@export_group("Flow")
## Hum pitch added at full flow (0.12 is about two semitones).
@export var flow_pitch: float = 0.12
## Hum volume added at full flow, in dB.
@export var flow_volume_db: float = 3.0
## Soft glow around the needle tip in flow: the spirit in the machine likes a steady hand.
@export var glow_color: Color = Color(0.62, 0.3, 0.95, 0.45)
@export var glow_radius_min: float = 40.0
@export var glow_radius_max: float = 80.0
## Seconds per breath of the glow at full flow.
@export var glow_breath: float = 1.5

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
## The model's needle surface, which glows in the needle's colour.
const NEEDLE_SURFACE: int = 4
## Mouse position in viewport pixels. With the mouse captured (the session does it) it moves by the mouse's
## own motion times `mouse_sensitivity` instead, kept on screen.
var pointer: Vector2 = Vector2.ZERO
## Share of the mouse's motion the pointer follows while the mouse is captured: 0.5 = half as sensitive.
var mouse_sensitivity: float = 1.0
## Screen pixels per rendered pixel of the model: the session's retro filter samples one point per game pixel,
## so the 3D renders at the game pixel's size, without MSAA (2: a quarter of the pixels, 3: a ninth). 1: real pixels.
var render_divisor: int = 1:
	set(value):
		render_divisor = maxi(value, 1)
		if is_node_ready():
			_view.msaa_3d = Viewport.MSAA_DISABLED if render_divisor > 1 else Viewport.MSAA_4X
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
## Whether the ink gauge is drawn.
var show_gauge: bool = true:
	set(value):
		show_gauge = value
		queue_redraw()
## Off: the needle is exactly at `needle` with no spring lag; the top still swings.
var inertia: bool = true
## Flow strength, 0..1 (the session's `InkFlow`): higher hum, glow at the tip.
var flow: float = 0.0
## The session's brush on screen: the spray comes off along it (`brush_size`: half length, half thickness).
var brush_axis: Vector2 = Vector2.RIGHT
var brush_size: Vector2 = Vector2.ZERO
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
var _hum_volume_db: float = 0.0
var _spray_speed: float = 0.0

@onready var _spray: CPUParticles2D = $Spray
@onready var _hum: AudioStreamPlayer = $Hum
@onready var _glow: Sprite2D = $Glow
@onready var _view: SubViewport = $Model
@onready var _sprite: Sprite2D = $Sprite
@onready var _camera: Camera3D = $Model/Camera3D
@onready var _model: Node3D = $Model/TattooMachineModel


func _ready() -> void:
	pointer = get_viewport().get_mouse_position()
	_target = pointer
	_position = pointer
	_hum_volume_db = _hum.volume_db
	_spray_speed = _spray.initial_velocity_max


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: InputEventMouseMotion = event
			pointer = (pointer + motion.relative * mouse_sensitivity).clamp(Vector2.ZERO,
					get_viewport().get_visible_rect().size)
		else:
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
	_spray.initial_velocity_max = _spray_speed * (1.0 + 0.6 * flow)
	if brush_size != Vector2.ZERO:
		_spray.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_spray.emission_rect_extents = brush_size
		_spray.rotation = brush_axis.angle()
	_hum.pitch_scale = 0.8 if dry else 1.0 + flow_pitch * flow # a dry machine sounds hollow
	_hum.volume_db = _hum_volume_db + flow_volume_db * flow
	_update_glow()
	if working and not _hum.playing:
		_hum.play()
	elif not working and _hum.playing:
		_hum.stop()


func _update_glow() -> void:
	_glow.visible = flow > 0.0
	if not _glow.visible:
		return
	var breath: float = 1.0 + 0.1 * flow * sin(Time.get_ticks_msec() / 1000.0 * TAU / glow_breath)
	var radius: float = lerpf(glow_radius_min, glow_radius_max, flow) * breath
	_glow.scale = Vector2.ONE * radius / (_glow.texture.get_width() * 0.5)
	_glow.modulate = Color(glow_color, glow_color.a * flow)


## Mass on a spring: the needle chases the hand, the top chases its lean.
## Long frames are split into short steps, so it feels the same and stays stable at any frame rate.
func _simulate(delta: float) -> void:
	if _position.distance_to(_target) > snap_distance:
		_position = _target
		_velocity = Vector2.ZERO
	var steps: int = maxi(1, ceili(delta / MAX_STEP))
	if not inertia:
		_velocity = (_target - _position) / maxf(delta, 0.0001)
		_position = _target
	for i in steps:
		_step(delta / steps)


func _step(delta: float) -> void:
	# A mass on a spring: frequency falls with the square root of the mass.
	var heavy: float = 1.0 / sqrt(1.0 + weight)
	if inertia:
		_velocity += _spring(_target - _position, _velocity, follow_frequency * heavy, follow_damping) * delta
		_position += _velocity * delta

	var lean_target: Vector2 = (-_velocity * lean_per_speed).limit_length(max_lean)
	_lean_velocity += _spring(lean_target - _lean, _lean_velocity, swing_frequency * heavy, swing_damping) * delta
	_lean += _lean_velocity * delta


func _spring(offset: Vector2, velocity: Vector2, frequency: float, damping: float) -> Vector2:
	return offset * frequency * frequency - velocity * 2.0 * damping * frequency


## Where the top end of the machine (`TOP`) is on screen, in viewport pixels.
func top_position() -> Vector2:
	return _camera.unproject_position(_model.global_transform * TOP) / _pixel_scale()


## Window pixels per viewport pixel (2 on a 1440p screen, 3 on 4K): the model is rendered at the window's own
## resolution, so it stays sharp on any monitor, and its sprite is drawn back at viewport size.
## The needle's glow colour (the needle cartridge in the machine).
func set_needle_color(value: Color) -> void:
	var mesh: MeshInstance3D = _model as MeshInstance3D
	if mesh == null:
		return
	var material: StandardMaterial3D = mesh.get_surface_override_material(NEEDLE_SURFACE)
	if material == null:
		return
	if not material.resource_local_to_scene and not material.has_meta(&"own_copy"):
		material = material.duplicate()
		material.set_meta(&"own_copy", true)
		mesh.set_surface_override_material(NEEDLE_SURFACE, material)
	material.albedo_color = value
	material.emission = value


func _pixel_scale() -> float:
	return maxf(1.0, get_viewport().get_final_transform().get_scale().x) / render_divisor


## Puts the model so its needle tip touches the skin plane right under `screen_point`.
func _place_model(screen_point: Vector2) -> void:
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var pixel_scale: float = _pixel_scale()
	var render_size: Vector2i = Vector2i((screen_size * pixel_scale).round())
	if _view.size != render_size:
		_view.size = render_size
		_sprite.scale = Vector2.ONE / pixel_scale
	var from: Vector3 = _camera.project_ray_origin(screen_point * pixel_scale)
	var direction: Vector3 = _camera.project_ray_normal(screen_point * pixel_scale)
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
	if show_gauge:
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
