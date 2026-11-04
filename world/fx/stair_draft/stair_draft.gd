@tool
extends GPUParticles3D

const LIGHT_PARTICLE_SHADER: Shader = preload("res://world/fx/light_reactive_particles.gdshader")
## A draft up a staircase: glowing dust is born around this node (the foot of the stairs) and drawn up to `to`
## (the top), speeding up on the way as if sucked up, with a little wobble, then fades out.
## By the doorway the draft starts from (around this node, the foot of the stairs) calm dust just floats about (`calm_*`).
## Points only (PointMesh), no geometry. Put the node at the foot of the stairs and set `to`; shows in the editor too.

@export var to: Vector3 = Vector3(0.0, 3.8, 6.2):         # top of the stairs, from this node
	set(v):
		to = v
		_rebuild()
@export var width: float = 0.6:                          # half-width of the stream, metres
	set(v):
		width = v
		_rebuild()
@export var height: float = 1.2:                         # half-height of the stream where it starts, metres (its bottom stays at the node)
	set(v):
		height = v
		_rebuild()
@export var count: int = 220:                          # particles in the stream at once
	set(v):
		count = v
		_rebuild()
@export var speed: float = 1.0:                          # metres per second at the foot; twice that at the top
	set(v):
		speed = v
		_rebuild()
@export var color: Color = Color(0.12, 1.0, 0.22):       # same green as the basement dust
	set(v):
		color = v
		_rebuild()
@export var brightness: float = 1.2:                     # above 1 glows
	set(v):
		brightness = v
		_rebuild()
@export var point_size: float = 3.0:                     # pixels of the 3D view; under the retro filter 3 = one game pixel
	set(v):
		point_size = v
		_rebuild()
@export_group("Calm dust by the doorway")
@export var calm_count: int = 90:                      # 0 = none
	set(v):
		calm_count = v
		_rebuild()
@export var calm_area: Vector3 = Vector3(1.2, 1.1, 1.0):  # half-size of the box it floats in
	set(v):
		calm_area = v
		_rebuild()
@export var calm_offset: Vector3 = Vector3(0.0, 0.6, -1.0):  # centre of that box from this node (-Z = out into the room)
	set(v):
		calm_offset = v
		_rebuild()
@export var calm_speed: float = 0.15:                    # metres per second, a slow drift
	set(v):
		calm_speed = v
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var path: float = to.length()
	# starts at `speed`, doubles by the top: distance = 1.5 * speed * time
	var life: float = path / (1.5 * maxf(speed, 0.05))
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(width, height, 0.5)
	m.emission_shape_offset = Vector3(0.0, height - 0.5, 0.0)
	m.direction = to.normalized()
	m.spread = 6.0
	m.initial_velocity_min = speed * 0.8
	m.initial_velocity_max = speed * 1.2
	m.gravity = Vector3.ZERO
	m.linear_accel_min = speed / life * 0.8           # sucked harder the higher it gets
	m.linear_accel_max = speed / life * 1.2
	# no turbulence: in Godot it overrides a particle's own velocity every frame, so the stream stopped and just hovered
	m.color_ramp = _ramp()
	process_material = m

	draw_pass_1 = _points()

	amount = count
	lifetime = life
	preprocess = life                                  # already flowing when the scene starts
	randomness = 0.4
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lo: Vector3 = Vector3(minf(0.0, to.x), minf(0.0, to.y), minf(0.0, to.z)) - Vector3.ONE * (width + height * 2.0 + 1.0)
	var hi: Vector3 = Vector3(maxf(0.0, to.x), maxf(0.0, to.y), maxf(0.0, to.z)) + Vector3.ONE * (width + height * 2.0 + 1.0)
	visibility_aabb = AABB(lo, hi - lo)
	emitting = true
	_rebuild_calm()


## Calm dust floating by the doorway at the foot of the stairs: slow, every way, softly swirling.
func _rebuild_calm() -> void:
	for child in get_children():
		if child.has_meta("calm_dust"):
			child.queue_free()
	if calm_count <= 0:
		return
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = calm_area
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = calm_speed * 0.5
	m.initial_velocity_max = calm_speed * 1.5
	m.gravity = Vector3(0, 0.02, 0)                    # hangs in the air, never settles
	m.turbulence_enabled = true                        # here the swirl is the point: it only wanders
	m.turbulence_noise_strength = calm_speed
	m.turbulence_noise_scale = 1.5
	m.turbulence_noise_speed = Vector3(0.1, 0.15, 0.1)
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.15
	m.color_ramp = _ramp()
	var calm: GPUParticles3D = GPUParticles3D.new()
	calm.set_meta("calm_dust", true)
	calm.process_material = m
	calm.draw_pass_1 = _points()
	calm.amount = calm_count
	calm.lifetime = 6.0
	calm.preprocess = 6.0
	calm.randomness = 0.5
	calm.local_coords = false
	calm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	calm.visibility_aabb = AABB(-calm_area - Vector3.ONE, (calm_area + Vector3.ONE) * 2.0)
	calm.position = calm_offset
	add_child(calm)


func _points() -> PointMesh:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = LIGHT_PARTICLE_SHADER
	mat.set_shader_parameter("particle_size", point_size)
	var points: PointMesh = PointMesh.new()
	points.material = mat
	return points


## Fades in at the foot, glows up the stairs, fades out at the top (additive: black is invisible).
func _ramp() -> GradientTexture1D:
	var bright: Color = Color(color.r, color.g, color.b) * brightness
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color.BLACK)
	ramp.set_color(1, Color.BLACK)
	ramp.add_point(0.15, bright)
	ramp.add_point(0.8, bright * 0.8)
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = ramp
	return tex
