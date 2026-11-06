class_name GloveHand
extends Node2D
## The artist's left hand in a session: the player's white glove (its model, mirrored into a left hand, with the
## bones of `GloveRig`) seen from the back, fingers up, the palm's middle at this node's origin — the same frame the
## old flat placeholder drew in, so whatever holds it doesn't change. It's rendered in its own little 3D world
## (a SubViewport just big enough for the hand, drawn only while the hand is) and drawn here as a picture; children
## with `show_behind_parent` (the paper towel) go under it, others (the paper ball) over it.
## `fist` (0 open .. 1 a fist) is where the hand is heading; it closes at `clench_rate` and opens at `open_rate`.

const GLOVE: PackedScene = preload("res://art/models/player_glove/player_glove.glb")
## The glove's palm middle in its model (m): put at this node's origin.
const PALM: Vector3 = Vector3(-0.01, 0.2, 0.0)
## How much of the model the picture shows round the palm (m), and how many layout px a metre of glove is.
const FRAME: float = 0.56
const PX_PER_M: float = 420.0
## The picture is rendered this many times finer than it's drawn.
const SUPERSAMPLE: float = 3.0

## Where the hand is heading, 0 open .. 1 a fist.
@export_range(0.0, 1.0) var fist: float = 0.0
## How fast it closes and opens (per second, exponential).
@export var clench_rate: float = 21.0
@export var open_rate: float = 12.0
## The fingers lean away from us by this much (degrees), so the hand reads as lying on something, not flat.
@export var lean: float = 18.0
@export_group("Alive")
## The hand follows its own motion (measured from its position on screen, so it works wherever it's used): moving
## sideways the fingers turn that way up to `turn_max` degrees (the whole node turns, its towel and ball with it;
## off with `follow_motion` where the owner turns it itself) and the glove twists up to `twist_max` in 3D; moving up
## the fingers lean `lean_motion` further away. Full at `full_speed` px/s, eased at `turn_rate`. Standing still it
## sways `idle_sway` degrees and the open fingers flex a little (`idle_flex` of a fist).
@export var follow_motion: bool = true
@export var turn_max: float = 16.0
@export var twist_max: float = 14.0
@export var lean_motion: float = 10.0
@export var full_speed: float = 600.0
@export var turn_rate: float = 7.0
@export var idle_sway: float = 1.5
@export var idle_flex: float = 0.06

var rig: GloveRig
var _pivot: Node3D
var _time: float = 0.0
var _last_position: Vector2 = Vector2.INF
var _velocity: Vector2 = Vector2.ZERO
var _motion: Vector2 = Vector2.ZERO
var _viewport: SubViewport
var _glove: Node3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	var side: int = roundi(FRAME * PX_PER_M * SUPERSAMPLE)
	_viewport.size = Vector2i(side, side)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.55, 0.52)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	# the lamp up and to the right, as on the client's arm; a warm fill from the lower left
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.86)
	key.light_energy = 1.3
	_viewport.add_child(key)
	key.look_at_from_position(Vector3(0.6, 0.7, 0.9), Vector3.ZERO)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.78, 0.6)
	fill.light_energy = 0.3
	_viewport.add_child(fill)
	fill.look_at_from_position(Vector3(-0.9, -0.25, 0.5), Vector3.ZERO)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = FRAME
	camera.near = 0.05
	camera.far = 4.0
	camera.position = Vector3(0.0, 0.0, 2.0)
	_viewport.add_child(camera)
	# the player's glove is a right hand, palm toward +z: mirrored through its palm it's a left hand with its back
	# to the camera and the thumb on the right; the palm's middle at the origin
	var pivot: Node3D = Node3D.new()
	pivot.rotation_degrees.x = -lean
	_viewport.add_child(pivot)
	_pivot = pivot
	_glove = GLOVE.instantiate()
	_glove.scale = Vector3(1.0, 1.0, -1.0)
	_glove.position = -PALM
	pivot.add_child(_glove)
	for mesh: MeshInstance3D in _glove.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig = GloveRig.new()
	rig.name = "Rig"
	_glove.add_child(rig)


func _process(delta: float) -> void:
	if rig == null or not is_visible_in_tree():
		_last_position = Vector2.INF
		return
	_time += delta
	# its own speed on screen, smoothed; a jump (a reset, a swing) doesn't count
	var here: Vector2 = global_position
	if _last_position.is_finite() and delta > 0.0:
		var moved: Vector2 = (here - _last_position) / delta
		if moved.length() < full_speed * 6.0:
			_velocity = _velocity.lerp(moved, 1.0 - exp(-10.0 * delta))
	_last_position = here
	_motion = _motion.lerp((_velocity / full_speed).limit_length(1.0), 1.0 - exp(-turn_rate * delta))
	if follow_motion:
		rotation = deg_to_rad(_motion.x * turn_max + sin(_time * 1.1) * idle_sway)
	_pivot.rotation_degrees = Vector3(-(lean - _motion.y * lean_motion + sin(_time * 0.9) * 0.8), _motion.x * twist_max, 0.0)
	# open fingers flex a little at rest; a fist stays a fist
	var flex: float = idle_flex * (0.5 + 0.5 * sin(_time * 1.6)) * (1.0 - smoothstep(0.2, 0.5, fist))
	var wanted: float = fist + flex
	var rate: float = clench_rate if wanted > rig.fist else open_rate
	var eased: float = lerpf(rig.fist, wanted, 1.0 - exp(-rate * delta))
	rig.fist = wanted if absf(eased - wanted) < 0.002 else eased


## Snaps the hand to `fist` at once (a new session).
func snap() -> void:
	if rig != null:
		rig.fist = fist
	_velocity = Vector2.ZERO
	_motion = Vector2.ZERO
	_last_position = Vector2.INF


func _draw() -> void:
	var shown: float = FRAME * PX_PER_M
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ONE * -shown * 0.5, Vector2.ONE * shown), false)
