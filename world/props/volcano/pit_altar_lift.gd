class_name PitAltarLift
extends Node3D
## Lives in the volcano crater (world/props/volcano/): raise() lifts the altar from the bottom of the pit until its top
## meets the lip of the crater (the top of the `Interactable`'s opening disk), with a small overshoot; lower() sends
## it back down. While the skull's violet stage is on, violet sparks rise around the rim. The Interactable over the
## opening is what the player uses to start the ritual; the day flow enables it.

const PIT_PARTICLE_SHADER: Shader = preload("res://world/props/volcano/pit_violet_particles.gdshader")

@export var altar: Node3D
@export var skull: SkullRitual
@export_range(0.5, 30.0, 0.1) var rise_seconds: float = 7.0
@export_range(0.5, 30.0, 0.1) var lower_seconds: float = 10.0
@export_range(0.0, 0.2, 0.005) var settle_overshoot: float = 0.045
@export_range(0.1, 1.0, 0.05) var settle_seconds: float = 0.45
@export_range(0.0, 0.15, 0.005) var return_overshoot: float = 0.035
@export_range(0.1, 1.0, 0.05) var return_settle_seconds: float = 0.6

var activated: bool = false
var resting_position: Vector3
var movement: Tween
var pit_particles: GPUParticles3D

@onready var _opening: CollisionShape3D = $Interactable/Opening


func _ready() -> void:
	if is_instance_valid(altar):
		resting_position = altar.global_position
	($Interactable as Interactable).set_meta("outline_contour", _build_pentagram_mesh())
	if skull != null:
		skull.violet_stage_changed.connect(_on_violet_stage_changed)
	_make_pit_particles()


func raise() -> void:
	if not is_instance_valid(altar) or activated:
		return
	# the top of the opening disk sits at the lip of the lower crater
	var cylinder: CylinderShape3D = _opening.shape as CylinderShape3D
	var rim_y: float = _opening.to_global(Vector3.UP * cylinder.height * 0.5).y
	var mesh: MeshInstance3D = altar.get_node("Model/altar")
	var altar_top: float = (mesh.global_transform * mesh.get_aabb()).end.y
	activated = true
	if movement and movement.is_running():
		movement.kill()
	var target_y: float = altar.global_position.y + rim_y - altar_top
	movement = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	movement.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	movement.tween_property(altar, "global_position:y", target_y + settle_overshoot, maxf(0.1, rise_seconds - settle_seconds))
	movement.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	movement.tween_property(altar, "global_position:y", target_y, settle_seconds)


func lower() -> void:
	if not is_instance_valid(altar):
		return
	if movement and movement.is_running():
		movement.kill()
	activated = false
	movement = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	movement.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	movement.tween_property(altar, "global_position:y", resting_position.y - return_overshoot, maxf(0.1, lower_seconds - return_settle_seconds))
	movement.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	movement.tween_property(altar, "global_position:y", resting_position.y, return_settle_seconds)


func _on_violet_stage_changed(active: bool) -> void:
	if not is_instance_valid(pit_particles):
		return
	pit_particles.visible = active
	if active:
		pit_particles.restart()
	pit_particles.emitting = active


func _make_pit_particles() -> void:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 1.46
	process.emission_ring_inner_radius = 1.38
	process.emission_ring_height = 0.035
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.28
	process.gravity = Vector3(0, 0.045, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.18
	process.turbulence_noise_scale = 1.4
	process.turbulence_noise_speed = Vector3(0.1, 0.18, 0.1)
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.12
	process.color_ramp = _violet_particle_ramp()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = PIT_PARTICLE_SHADER
	material.set_shader_parameter("particle_size", 3.0)
	var points: PointMesh = PointMesh.new()
	points.material = material
	pit_particles = GPUParticles3D.new()
	pit_particles.name = "VioletPitParticles"
	pit_particles.amount = 100
	pit_particles.lifetime = 3.4
	pit_particles.preprocess = 2.0
	pit_particles.randomness = 0.7
	pit_particles.local_coords = true
	pit_particles.emitting = false
	pit_particles.visible = false
	pit_particles.position = Vector3(0, 1.12, 0)
	pit_particles.visibility_aabb = AABB(Vector3(-1.9, -0.35, -1.9), Vector3(3.8, 1.35, 3.8))
	pit_particles.process_material = process
	pit_particles.draw_pass_1 = points
	pit_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pit_particles)

func _violet_particle_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(0.68, 0.22, 1.0, 0.0))
	gradient.set_color(1, Color(0.38, 0.08, 0.72, 0.0))
	gradient.add_point(0.12, Color(0.72, 0.3, 1.0, 0.82))
	gradient.add_point(0.72, Color(0.58, 0.16, 0.95, 0.5))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	return texture

func _build_pentagram_mesh() -> ArrayMesh:
	var radius: float = 1.45
	var ring_y: float = 1.12
	var stroke: float = 0.035
	var dot_radius: float = 0.065
	var outer: Array[Vector2] = []
	for i in 5:
		var angle: float = -PI * 0.5 + TAU * float(i) / 5.0
		outer.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var order: Array[int] = [0, 2, 4, 1, 3, 0]
	for i in range(5):
		var a: Vector2 = outer[order[i]]
		var b: Vector2 = outer[order[i + 1]]
		var direction: Vector2 = (b - a).normalized()
		var normal: Vector2 = Vector2(-direction.y, direction.x) * stroke * 0.5
		var base: int = vertices.size()
		vertices.append(Vector3(a.x + normal.x, ring_y, a.y + normal.y))
		vertices.append(Vector3(a.x - normal.x, ring_y, a.y - normal.y))
		vertices.append(Vector3(b.x - normal.x, ring_y, b.y - normal.y))
		vertices.append(Vector3(b.x + normal.x, ring_y, b.y + normal.y))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	for point: Vector2 in outer:
		var center_index: int = vertices.size()
		vertices.append(Vector3(point.x, ring_y + 0.004, point.y))
		for i in 12:
			var angle: float = TAU * float(i) / 12.0
			vertices.append(Vector3(point.x + cos(angle) * dot_radius, ring_y + 0.004, point.y + sin(angle) * dot_radius))
		for i in 12:
			var a: int = center_index + 1 + i
			var b: int = center_index + 1 + ((i + 1) % 12)
			indices.append_array(PackedInt32Array([center_index, a, b]))

	# A thin circular rim frames the star just inside the pit's physical edge.
	var circle_radius: float = 1.58
	var circle_stroke: float = 0.025
	var circle_segments: int = 96
	var circle_y: float = ring_y + 0.006
	for i in circle_segments:
		var angle_a: float = TAU * float(i) / float(circle_segments)
		var angle_b: float = TAU * float(i + 1) / float(circle_segments)
		var a: Vector2 = Vector2(cos(angle_a) * circle_radius, sin(angle_a) * circle_radius)
		var b: Vector2 = Vector2(cos(angle_b) * circle_radius, sin(angle_b) * circle_radius)
		var direction: Vector2 = (b - a).normalized()
		var normal: Vector2 = Vector2(-direction.y, direction.x) * circle_stroke * 0.5
		var base: int = vertices.size()
		vertices.append(Vector3(a.x + normal.x, circle_y, a.y + normal.y))
		vertices.append(Vector3(a.x - normal.x, circle_y, a.y - normal.y))
		vertices.append(Vector3(b.x - normal.x, circle_y, b.y - normal.y))
		vertices.append(Vector3(b.x + normal.x, circle_y, b.y + normal.y))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
