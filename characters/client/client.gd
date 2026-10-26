class_name Client
extends CharacterBody3D
## A client walking around the studio on the level's navigation mesh.
## The look lives in `Visual` (a placeholder capsule for now) so it can become a 2D sprite
## without touching this logic. Physics layer 4 "npc": the player bumps into clients,
## clients walk through the player.

## Fires when the player presses `interact` on a client that allows talking.
signal talk_requested(client: Client)

enum State { IDLE, WALKING, SEATED, HYPNOTIZED, FOLLOWING, KNEELING, DEAD }

@export var walk_speed: float = 1.4
@export var turn_speed: float = 8.0
## While following, stops this close to the target.
@export var follow_distance: float = 1.4

var data: ClientData
var state: State = State.IDLE

var _follow_target: Node3D
var _walk_done: bool = false

@onready var head: Marker3D = $Visual/Head
@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _head_mesh: MeshInstance3D = $Visual/HeadMesh
@onready var _eyes: Node3D = $Visual/HeadMesh/Eyes
@onready var _shape: CollisionShape3D = $Shape
@onready var _agent: NavigationAgent3D = $Agent
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(func(_player: Player) -> void: talk_requested.emit(self))
	allow_talk(false)
	set_eyes_glowing(false)
	if data != null:
		_apply_look()


## Call before adding to the tree, or any time after.
func setup(client_data: ClientData) -> void:
	data = client_data
	if is_node_ready():
		_apply_look()


## Walks to `point` along the navigation mesh. Awaitable: `await client.walk_to(p)`.
func walk_to(point: Vector3) -> void:
	# The navigation map needs one sync after the level bakes it.
	while NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) == 0:
		await get_tree().physics_frame
	state = State.WALKING
	_walk_done = false
	_agent.target_position = point
	while not _walk_done:
		await get_tree().physics_frame


## Sits on `seat`; the client faces the seat marker's -Z.
func sit(seat: Node3D) -> void:
	state = State.SEATED
	velocity = Vector3.ZERO
	_shape.disabled = true
	global_transform = seat.global_transform
	_visual.scale = Vector3(1.0, 0.5, 1.0) # placeholder "sitting": squashed onto the seat


func stand_up(floor_point: Vector3) -> void:
	_visual.scale = Vector3.ONE
	global_position = floor_point
	_shape.disabled = false
	state = State.IDLE


func face(point: Vector3) -> void:
	var to: Vector3 = point - global_position
	rotation.y = atan2(-to.x, -to.z)


## Shows `prompt` when the player looks at the client; a disabled prompt is a hint without "E".
## Not allowed: out of the ray's way entirely.
func allow_talk(allowed: bool, prompt: String = "Поговорить", enabled: bool = true) -> void:
	_interactable.collision_layer = Interactable.LAYER if allowed else 0
	_interactable.prompt = prompt
	_interactable.enabled = enabled


func set_eyes_glowing(glowing: bool) -> void:
	_eyes.visible = glowing


## Stands still with glowing eyes; the spirit holds them.
func hypnotize() -> void:
	state = State.HYPNOTIZED
	velocity = Vector3.ZERO
	set_eyes_glowing(true)


func follow(target: Node3D) -> void:
	_follow_target = target
	state = State.FOLLOWING


## Placeholder kneeling: squashed in place.
func kneel() -> void:
	state = State.KNEELING
	velocity = Vector3.ZERO
	_visual.scale = Vector3(1.0, 0.6, 1.0)


## The ritual: the head is gone (it goes to the wall), the body lies on the floor.
func behead() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	allow_talk(false)
	_shape.disabled = true
	_head_mesh.visible = false
	_visual.scale = Vector3.ONE
	_visual.rotation.x = -PI / 2.0 # fall backwards
	_visual.position.y = 0.26 # body radius, so it lies on the floor


func _physics_process(delta: float) -> void:
	if state in [State.SEATED, State.KNEELING, State.DEAD]:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	var horizontal: Vector3 = Vector3.ZERO
	match state:
		State.WALKING:
			if _agent.is_navigation_finished():
				state = State.IDLE
				_walk_done = true
			else:
				horizontal = _step_toward(_agent.get_next_path_position())
		State.FOLLOWING:
			if is_instance_valid(_follow_target):
				_agent.target_position = _follow_target.global_position
				if global_position.distance_to(_follow_target.global_position) > follow_distance:
					horizontal = _step_toward(_agent.get_next_path_position())
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if horizontal.length() > 0.01:
		var yaw: float = atan2(-horizontal.x, -horizontal.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))
	move_and_slide()


func _step_toward(point: Vector3) -> Vector3:
	var to: Vector3 = point - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return Vector3.ZERO
	return to.normalized() * walk_speed


func _apply_look() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = data.color
	_body_mesh.material_override = material
	_head_mesh.material_override = material
	# Placeholder proportions: the head sits on top of a body scaled to the height.
	var body_height: float = data.height - 0.4
	var capsule: CapsuleMesh = _body_mesh.mesh.duplicate() # the scene's mesh is shared by all clients
	capsule.height = body_height
	_body_mesh.mesh = capsule
	_body_mesh.position.y = body_height * 0.5
	_head_mesh.position.y = body_height + 0.18
	head.position.y = data.height
