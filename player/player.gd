class_name Player
extends CharacterBody3D
## First-person player: walking with the colleague's head bob, mouse look, carrying one item in the glove
## (`Head/Camera3D/PlayerHand`). Running (Shift) and jumping (Space) exist but are off, as in his game.
## Other systems find it with get_tree().get_first_node_in_group("player").

signal controls_lock_changed(locked: bool)

const PITCH_LIMIT: float = 1.48 # ~85 degrees

@export var speed: float = 2.2
@export var run_speed: float = 4.5
@export var can_run: bool = false
@export var jump_velocity: float = 3.5
@export var can_jump: bool = false
@export var acceleration: float = 20.0
## Radians per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0022
@export_group("Head bob")
## How far the head drops on each footfall at walking speed, metres.
@export var bob_height: float = 0.05
## Side to side per stride at walking speed, metres.
@export var bob_sway: float = 0.03
## Metres per full stride (two steps): longer = slower, heavier steps.
@export var stride_length: float = 2.0
## 1 = smooth bounce; higher = a quick heavy drop on each step, slow rise.
@export var footfall_sharpness: float = 3.0
## The camera leans towards the foot that carries the weight.
@export var bob_roll_degrees: float = 0.9
## The camera dips forward a little on each footfall.
@export var bob_nod_degrees: float = 0.6
## Side sway and lean when running, relative to walking (1 = the same).
@export var run_sway: float = 0.35
## How quickly the bob fades in when you start and out when you stop.
@export var bob_smoothing: float = 4.0
@export_group("")

var held_item: Item = null
var _locks: Dictionary[StringName, bool] = {}
## Head position at the last two physics ticks; the camera is drawn between them.
var _head_previous: Vector3
var _head_current: Vector3
var _bob_phase: float = 0.0
var _bob_amount: float = 0.0     # current bob strength, eased towards the walking speed
var _bob_offset: Vector3 = Vector3.ZERO
var _bob_rotation: Vector3 = Vector3.ZERO

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _hold_point: Node3D = $Head/Camera3D/HoldPoint
@onready var _hand: PlayerHand = $Head/Camera3D/PlayerHand


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Before anything that reads the camera this frame (speech bubbles).
	process_priority = -10
	_head_current = _head.global_position
	_head_previous = _head_current
	_update_camera()


## Walking moves the body at the physics rate; drawn as is, the camera judders whenever the
## frame rate isn't a multiple of it. So the camera (top_level) slides between the last two
## head positions, while turning (mouse look) applies at once.
func _process(delta: float) -> void:
	_update_bob(delta)
	_update_camera()


func _update_camera() -> void:
	var origin: Vector3 = _head_previous.lerp(_head_current, Engine.get_physics_interpolation_fraction())
	var look: Basis = _head.global_basis
	_camera.global_transform = Transform3D(look * Basis.from_euler(_bob_rotation), origin + look * _bob_offset)


## Head bob: on every footfall the head drops quickly (the weight lands on the leg) and rises slowly, swaying
## towards the standing leg with a slight lean and nod; scaled by speed, eased back to rest on the spot or in the air.
func _update_bob(delta: float) -> void:
	var walk_speed: float = Vector2(velocity.x, velocity.z).length()
	var walking: bool = is_on_floor() and walk_speed > 0.1
	_bob_amount = move_toward(_bob_amount, minf(walk_speed / speed, 1.6) if walking else 0.0, delta * bob_smoothing)
	if walking:
		_bob_phase = fmod(_bob_phase + walk_speed * delta / stride_length * TAU, TAU)
	var footfall: float = _footfall()                            # 1 right when a foot lands, 0 mid-step
	var side: float = cos(_bob_phase)                             # which leg carries the weight
	var running: float = clampf((walk_speed - speed) / maxf(run_speed - speed, 0.01), 0.0, 1.0)
	var sway: float = minf(_bob_amount, 1.0) * lerpf(1.0, run_sway, running)
	_bob_offset = Vector3(side * bob_sway * sway, -footfall * bob_height * _bob_amount, 0.0)
	_bob_rotation = Vector3(-deg_to_rad(bob_nod_degrees) * footfall * _bob_amount, 0.0, deg_to_rad(bob_roll_degrees) * side * sway)


## Progress through the current step, bent so the head falls fast into the landing and climbs slowly.
func _footfall() -> float:
	var step: float = pow(fmod(_bob_phase, PI) / PI, 1.4)
	return pow(1.0 - sin(step * PI), footfall_sharpness)


## For the glove: (phase, strength, footfall) of the head bob.
func get_hand_bob_state() -> Vector3:
	return Vector3(_bob_phase, _bob_amount, _footfall())


## The glove's short jab on using something.
func tap() -> void:
	_hand.tap()


## A click on a free mouse only captures it back, before the interaction ray sees the click.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and DisplayServer.get_name() != "headless" \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not is_locked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Temporary until the pause menu (step 9): Esc frees the mouse, a click captures it back.
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_locked():
		var motion: Vector2 = event.relative * mouse_sensitivity
		rotate_y(-motion.x)
		_head.rotation.x = clampf(_head.rotation.x - motion.y, -PITCH_LIMIT, PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif can_jump and not is_locked() and Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity

	var input_dir: Vector2 = Vector2.ZERO
	if not is_locked():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var pace: float = run_speed if can_run and Input.is_physical_key_pressed(KEY_SHIFT) else speed
	var target: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() * pace
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	move_and_slide()
	_head_previous = _head_current
	_head_current = _head.global_position


## Blocks movement, look and interaction until every reason is unlocked.
func lock_controls(reason: StringName) -> void:
	var was_locked: bool = is_locked()
	_locks[reason] = true
	if not was_locked:
		controls_lock_changed.emit(true)


func unlock_controls(reason: StringName) -> void:
	var was_locked: bool = is_locked()
	_locks.erase(reason)
	if was_locked and not is_locked():
		controls_lock_changed.emit(false)


func is_locked() -> bool:
	return not _locks.is_empty()


func hold(item: Item) -> void:
	held_item = item
	item.attach_to(_hand.hold_point if _hand != null else _hold_point, true)
	if _hand != null:
		_hand.set_holding(true)


## Gives up the held item; the caller decides where it goes.
func take_item() -> Item:
	var item: Item = held_item
	held_item = null
	if _hand != null:
		_hand.set_holding(false)
	return item


## Puts the glove back in front of the camera at once (after a teleport).
func snap_hand() -> void:
	_head_previous = _head.global_position
	_head_current = _head_previous
	_update_camera()
	if _hand != null:
		_hand.snap_to_camera()
