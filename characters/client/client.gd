class_name Client
extends CharacterBody3D
## A client walking around the studio on the level's navigation mesh.
## The look lives in `Visual`: the colleague's gentleman sprite (a Y-billboard quad with a normal map), sized to the
## client's height and lightly tinted with their colour, until each client gets their own art. Poses are
## placeholders made from the one drawing (squashed to sit or kneel, the body without its head lying flat).
## Physics layer 4 "npc": the player bumps into clients, clients walk through the player.

## Fires when the player presses `interact` on a client that allows talking.
signal talk_requested(client: Client)

enum State { IDLE, WALKING, SEATED, HYPNOTIZED, FOLLOWING, KNEELING, DEAD }

@export var walk_speed: float = 1.4
@export var turn_speed: float = 8.0
## While following, stops this close to the target.
@export var follow_distance: float = 1.4
## How much of the client's colour tints the sprite.
@export var tint_strength: float = 0.3

## Width / height of the drawing; how far down from its top the eyes are and the neck ends.
const SPRITE_ASPECT: float = 494.0 / 1060.0
const EYES_FROM_TOP: float = 0.09
const NECK_FROM_TOP: float = 0.18
const HIPS_FROM_BOTTOM: float = 0.47

var data: ClientData
var state: State = State.IDLE

var _follow_target: Node3D
var _walk_done: bool = false

@onready var head: Marker3D = $Visual/Head
@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _eyes: Node3D = $Visual/Eyes
@onready var _shape: CollisionShape3D = $Shape
@onready var _agent: NavigationAgent3D = $Agent
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(func(_player: Player) -> void: talk_requested.emit(self))
	_interactable.set_meta(&"outline_suppress", true)   # an outline would trace the sprite's square, not the figure
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
	# placeholder "sitting": the hips of the drawing on the seat, the legs hidden in the chair
	_visual.position.y = -_height() * HIPS_FROM_BOTTOM


func stand_up(floor_point: Vector3) -> void:
	_visual.scale = Vector3.ONE
	_visual.position.y = 0.0
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
	_visual.scale = Vector3(1.0, 0.7, 1.0)


## The ritual: the head is gone (it goes to the wall), the body lies on its back on the floor.
func behead() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	allow_talk(false)
	_shape.disabled = true
	set_eyes_glowing(false)
	if _body_mesh.material_override == null:
		_body_mesh.material_override = ((_body_mesh.mesh as QuadMesh).material as StandardMaterial3D).duplicate()
		_body_mesh.mesh = _body_mesh.mesh.duplicate()
	var material: StandardMaterial3D = _body_mesh.material_override as StandardMaterial3D
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.uv1_offset = Vector3(0.0, NECK_FROM_TOP, 0.0)   # the drawing below the neck
	material.uv1_scale = Vector3(1.0, 1.0 - NECK_FROM_TOP, 1.0)
	var quad: QuadMesh = _body_mesh.mesh as QuadMesh
	quad.size.y *= 1.0 - NECK_FROM_TOP
	quad.center_offset.y = quad.size.y * 0.5
	_visual.scale = Vector3.ONE
	_visual.rotation = Vector3(-PI / 2.0, PI, 0.0) # fall backwards, away from what they faced, face up
	_visual.position.y = 0.12   # over the bumps of the basement soil


## The glowing eyes are 3D dots on a flat drawing: keep them turned to the camera, in front of the face.
func _process(_delta: float) -> void:
	if not _eyes.visible:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var to: Vector3 = camera.global_position - _eyes.global_position
		_eyes.global_rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)


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


func _height() -> float:
	return data.height if data != null else 1.75


func _apply_look() -> void:
	var quad: QuadMesh = _body_mesh.mesh.duplicate() # the scene's mesh and material are shared by all clients
	var material: StandardMaterial3D = quad.material.duplicate()
	quad.material = null
	material.albedo_color = Color.WHITE.lerp(data.color, tint_strength)
	_body_mesh.material_override = material
	quad.size = Vector2(data.height * SPRITE_ASPECT, data.height)
	quad.center_offset = Vector3(0.0, data.height * 0.5, 0.0)
	_body_mesh.mesh = quad
	_eyes.position.y = data.height * (1.0 - EYES_FROM_TOP)
	head.position.y = data.height
