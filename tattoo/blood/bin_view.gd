class_name BinView
extends Control
## What's to the left of the client: a wire-mesh waste basket on the floor in its own little 3D world (the mesh lets
## you see what's inside). The artist's left hand holds the crumpled bloody paper towel; WASD move it over the
## screen and LMB throws: the ball leaves the hand toward the point under it, and the higher the hand, the farther
## it flies. `throw_finished(in_bin)` fires once the ball lies still, or as soon as it hits the floor outside. Balls stay where they land (inside or not)
## until the session ends.

signal throw_finished(in_bin: bool)

## The left hand's speed and how quickly it gets there, as on the skin.
@export var hand_speed: float = 650.0
@export var hand_acceleration: float = 12.0
## The mouse moves the hand too (the session captures it): screen px per px of mouse motion.
@export var mouse_sensitivity: float = 0.8
## The throw: the ball lands on the floor point under the hand after `flight` s, off by up to `aim_error` m, plus
## the hand's own motion when it lets go (`swing_error` m per px/s): a still hand aimed over the basket goes in.
@export var flight: float = 0.75
@export var aim_error: float = 0.025
@export var swing_error: float = 0.0004
## A ball that lands in the basket makes it wobble: a spin round its axis and a tilt (degrees), over `wobble_time` s.
@export var wobble_spin: float = 18.0
@export var wobble_tilt: float = 6.0
@export var wobble_time: float = 0.9
## The basket: radius at the top and bottom, height (m).
@export var bin_top_radius: float = 0.2
@export var bin_bottom_radius: float = 0.16
@export var bin_height: float = 0.36

const BALL_RADIUS: float = 0.045
const HAND_SCRIPT: Script = preload("res://tattoo/left_hand_visual.gd")
const WIRE_SHADER: String = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 wire : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform vec2 cells = vec2(28.0, 9.0);
uniform float thickness = 0.12;
void fragment() {
	vec2 g = fract(UV * cells);
	vec2 d = min(g, 1.0 - g);
	if (min(d.x, d.y) > thickness * 0.5) {
		discard;   // the holes of the mesh
	}
	ALBEDO = wire.rgb;
	METALLIC = 0.7;
	ROUGHNESS = 0.4;
}
"""

## Ready for a throw (the hand holds a ball).
var armed: bool = false

var _viewport: SubViewport
var _camera: Camera3D
var _world_root: Node3D
var _hand: Node2D
var _hand_position: Vector2 = Vector2.ZERO
var _hand_velocity: Vector2 = Vector2.ZERO
## Mouse motion since the last frame, and the hand's measured speed (px/s).
var _mouse_move: Vector2 = Vector2.ZERO
var _hand_motion: Vector2 = Vector2.ZERO
var _ball: RigidBody3D
var _wait: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bin_visual: Node3D
## Time into the basket's wobble, -1 while still.
var _wobble: float = -1.0
## The ball in flight has gone into the basket.
var _ball_hit: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	_world_root = Node3D.new()
	_viewport.add_child(_world_root)
	_build_world()
	_hand = Node2D.new()
	_hand.set_script(HAND_SCRIPT)
	_hand.name = "Hand"
	add_child(_hand)
	var held: Node2D = Node2D.new()
	held.set_script(load("res://tattoo/blood/held_ball.gd"))
	_hand.add_child(held)
	_hand.visible = false
	set_process(false)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED   # off screen: no 3D to draw


## The view is about to swing here: start drawing the basket.
func wake() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## The view swung here: the hand comes up holding the ball.
func arm_throw() -> void:
	armed = true
	_hand_position = Vector2(size.x * 0.3, size.y * 0.72)
	_hand_velocity = Vector2.ZERO
	_hand_motion = Vector2.ZERO
	_mouse_move = Vector2.ZERO
	_hand.visible = true
	_hand.position = _hand_position
	wake()
	set_process(true)
	queue_redraw()


## Leaving: stop drawing the 3D.
func rest() -> void:
	armed = false
	_hand.visible = false
	set_process(false)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Every ball thrown is cleared away (a new session).
func clear_balls() -> void:
	for node in get_tree().get_nodes_in_group(&"paper_ball"):
		if is_ancestor_of(node):
			node.queue_free()


func _input(event: InputEvent) -> void:
	if armed and event is InputEventMouseMotion and not Transition.is_busy:
		_mouse_move += (event as InputEventMouseMotion).relative


func _process(delta: float) -> void:
	_wobble_basket(delta)
	if armed:
		var wanted: Vector2 = Input.get_vector("hand_left", "hand_right", "hand_up", "hand_down") \
				if not Transition.is_busy else Vector2.ZERO
		_hand_velocity = _hand_velocity.lerp(wanted * hand_speed, 1.0 - exp(-hand_acceleration * delta))
		var before: Vector2 = _hand_position
		_hand_position = (_hand_position + _hand_velocity * delta + _mouse_move * mouse_sensitivity).clamp(Vector2.ZERO, size)
		_mouse_move = Vector2.ZERO
		# how fast the hand really moves (keys and mouse), smoothed: a throw on the move goes astray
		_hand_motion = _hand_motion.lerp((_hand_position - before) / maxf(delta, 0.0001), 1.0 - exp(-12.0 * delta))
		_hand.position = _hand_position
		if Input.is_action_just_pressed("use") and not Transition.is_busy:
			_throw()
	elif _ball != null:
		_wait += delta
		var settled: bool = _wait > 0.7 and (_ball.sleeping or _ball.linear_velocity.length() < 0.05)
		# on the floor outside the basket: a miss, no need to wait for it to stop rolling
		var at: Vector3 = _ball.global_position
		var missed: bool = at.y < BALL_RADIUS * 1.6 and Vector2(at.x, at.z).length() > bin_top_radius + BALL_RADIUS
		if not _ball_hit and _is_inside(at) and at.y < bin_height * 0.75:
			_ball_hit = true
			_wobble = 0.0   # it went in: the basket wobbles right away
		if settled or missed or _wait > 4.0 or at.y < -1.0:
			var inside: bool = _is_inside(_ball.global_position)
			if inside:
				# it stays in the basket and wobbles with it
				_ball.freeze = true
				_ball.reparent(_bin_visual)
			_ball = null
			throw_finished.emit(inside)


## A hit: the basket gives a little kicked spin round its axis and a rocking tilt, dying out over
## `wobble_time` (not physics, just a nod).
func _wobble_basket(delta: float) -> void:
	if _wobble < 0.0 or _bin_visual == null:
		return
	_wobble += delta
	var fade: float = exp(-_wobble * 4.5 / wobble_time)
	var spin: float = deg_to_rad(wobble_spin) * fade * sin(_wobble * 11.0)
	var tilt: float = deg_to_rad(wobble_tilt) * fade * sin(_wobble * 17.0 + 0.6)
	_bin_visual.transform = Transform3D(Basis(Vector3.UP, spin) * Basis(Vector3(1.0, 0.0, 0.4).normalized(), tilt),
			Vector3.ZERO)
	if _wobble > wobble_time:
		_wobble = -1.0
		_bin_visual.transform = Transform3D.IDENTITY


func _draw() -> void:
	if not armed:
		return
	var font: Font = ThemeDB.fallback_font
	var text: String = "Мышь или WASD — прицелиться рукой над корзиной, ЛКМ — бросить"
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var at: Vector2 = Vector2((size.x - width) * 0.5, size.y - 70.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.9))


func _throw() -> void:
	armed = false
	_hand.visible = false
	queue_redraw()
	_ball = _make_ball()
	_world_root.add_child(_ball)
	# from just in front of the camera under the hand, in a lob onto the floor point under the hand
	var at: Vector2 = _hand_position / size * Vector2(_viewport.size)
	var from: Vector3 = _camera.project_ray_origin(at)
	var aim: Vector3 = _camera.project_ray_normal(at)
	var start: Vector3 = from + aim * 0.45
	var target: Vector3 = from + aim * (-from.y / minf(aim.y, -0.05))
	var miss: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * aim_error * sqrt(_rng.randf()) \
			+ _hand_motion * swing_error
	target += Vector3(miss.x, 0.0, miss.y)
	var gravity: Vector3 = Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_ball_hit = false
	_ball.global_position = start
	_ball.linear_velocity = (target - start) / flight - gravity * 0.5 * flight
	_ball.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
	_wait = 0.0


func _is_inside(point: Vector3) -> bool:
	var flat: Vector2 = Vector2(point.x, point.z)
	return flat.length() < bin_top_radius and point.y < bin_height and point.y > -0.05


func _make_ball() -> RigidBody3D:
	var ball: RigidBody3D = RigidBody3D.new()
	ball.add_to_group(&"paper_ball")
	ball.mass = 0.02
	ball.physics_material_override = PhysicsMaterial.new()
	ball.physics_material_override.bounce = 0.08
	ball.physics_material_override.friction = 0.9
	ball.angular_damp = 2.0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = BALL_RADIUS
	shape.shape = sphere
	ball.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = _crumpled_mesh()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	mesh.material_override = material
	ball.add_child(mesh)
	return ball


## A lumpy paper ball: a low sphere with its points pushed in and out, white with dark-red patches.
func _crumpled_mesh() -> ArrayMesh:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays: Array = sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = PackedColorArray()
	var stains: Array[Vector3] = [Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()]
	for i in vertices.size():
		var v: Vector3 = vertices[i]
		var direction: Vector3 = v.normalized() if v.length() > 0.0 else Vector3.UP
		# the same jitter for the same point, so the seams stay closed
		var bump: float = 0.75 + 0.5 * fposmod(sin(direction.dot(Vector3(12.9, 78.2, 37.7))) * 43758.5, 1.0)
		vertices[i] = direction * BALL_RADIUS * bump
		var red: float = 0.0
		for stain in stains:
			red = maxf(red, smoothstep(0.55, 0.85, direction.dot(stain)))
		colors.append(Color(0.88, 0.89, 0.92).lerp(Color(0.42, 0.03, 0.06), red))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var surface: SurfaceTool = SurfaceTool.new()
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface.create_from(mesh, 0)
	surface.generate_normals()
	return surface.commit()


func _build_world() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.05, 0.045, 0.05)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.5, 0.5)
	environment.environment.ambient_light_energy = 0.5
	_world_root.add_child(environment)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_world_root.add_child(_camera)
	_camera.look_at_from_position(Vector3(0.0, 0.95, 1.25), Vector3(0.0, 0.12, 0.0))
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.position = Vector3(-0.5, 1.4, 0.8)
	lamp.light_energy = 1.6
	lamp.omni_range = 4.0
	lamp.shadow_enabled = true
	_world_root.add_child(lamp)
	# the floor: a wide dark plank board
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	floor_mesh.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.22, 0.16, 0.12)
	floor_material.roughness = 0.85
	floor_mesh.material_override = floor_material
	floor_body.add_child(floor_mesh)
	_world_root.add_child(floor_body)
	_build_bin()


## The basket: a mesh side (a cylinder with holes cut by the wire shader, both faces drawn), a solid rim and base,
## and walls of thin boxes round it for the ball to hit.
func _build_bin() -> void:
	var bin: StaticBody3D = StaticBody3D.new()
	_world_root.add_child(bin)
	_bin_visual = Node3D.new()
	_bin_visual.name = "Visual"
	bin.add_child(_bin_visual)
	var side: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = bin_top_radius
	cylinder.bottom_radius = bin_bottom_radius
	cylinder.height = bin_height
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	cylinder.radial_segments = 48
	side.mesh = cylinder
	var wire: ShaderMaterial = ShaderMaterial.new()
	wire.shader = Shader.new()
	wire.shader.code = WIRE_SHADER
	side.material_override = wire
	side.position.y = bin_height * 0.5
	_bin_visual.add_child(side)
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.32, 0.32, 0.35)
	dark.metallic = 0.7
	dark.roughness = 0.35
	var rim: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = bin_top_radius - 0.008
	torus.outer_radius = bin_top_radius + 0.008
	rim.mesh = torus
	rim.material_override = dark
	rim.position.y = bin_height
	_bin_visual.add_child(rim)
	var base: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = bin_bottom_radius
	disc.bottom_radius = bin_bottom_radius
	disc.height = 0.01
	base.mesh = disc
	base.material_override = dark
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.position.y = 0.005
	_bin_visual.add_child(base)
	# collision: a base and 20 slanted wall slats
	var base_shape: CollisionShape3D = CollisionShape3D.new()
	var base_box: CylinderShape3D = CylinderShape3D.new()
	base_box.radius = bin_bottom_radius
	base_box.height = 0.02
	base_shape.shape = base_box
	base_shape.position.y = 0.01
	bin.add_child(base_shape)
	var slats: int = 20
	var middle_radius: float = (bin_top_radius + bin_bottom_radius) * 0.5
	var lean: float = atan2(bin_top_radius - bin_bottom_radius, bin_height)
	for i in slats:
		var angle: float = TAU * i / slats
		var slat: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(TAU * middle_radius / slats * 1.15, bin_height, 0.012)
		slat.shape = box
		var outward: Vector3 = Vector3(sin(angle), 0.0, cos(angle))
		slat.transform = Transform3D(Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -lean),
				outward * middle_radius + Vector3.UP * bin_height * 0.5)
		bin.add_child(slat)
