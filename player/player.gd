class_name Player
extends CharacterBody3D
## First-person player: walking, mouse look, carrying one item.
## Other systems find it with get_tree().get_first_node_in_group("player").

signal controls_lock_changed(locked: bool)

const PITCH_LIMIT: float = 1.48 # ~85 degrees

@export var speed: float = 3.0
@export var acceleration: float = 20.0
## Radians per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0016875

var held_item: Item = null
var _locks: Dictionary[StringName, bool] = {}
## Head position at the last two physics ticks; the camera is drawn between them.
var _head_previous: Vector3
var _head_current: Vector3

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _hold_point: Node3D = $Head/Camera3D/HoldPoint


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
func _process(_delta: float) -> void:
	_update_camera()


func _update_camera() -> void:
	var origin: Vector3 = _head_previous.lerp(_head_current, Engine.get_physics_interpolation_fraction())
	_camera.global_transform = Transform3D(_head.global_basis, origin)


func _unhandled_input(event: InputEvent) -> void:
	# Temporary until the pause menu (step 9): Esc frees the mouse, a click captures it back.
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not is_locked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_locked():
		var motion: Vector2 = event.relative * mouse_sensitivity
		rotate_y(-motion.x)
		_head.rotation.x = clampf(_head.rotation.x - motion.y, -PITCH_LIMIT, PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir: Vector2 = Vector2.ZERO
	if not is_locked():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var target: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() * speed
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
	item.attach_to(_hold_point, true)


## Gives up the held item; the caller decides where it goes.
func take_item() -> Item:
	var item: Item = held_item
	held_item = null
	return item
