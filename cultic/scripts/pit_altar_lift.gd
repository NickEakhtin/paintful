extends StaticBody3D

const VIOLET := Color(0.68, 0.22, 1.0)
const PIT_PARTICLE_SHADER := preload("res://world/props/volcano/pit_violet_particles.gdshader")

@export var altar: Node3D
@export_range(0.5, 30.0, 0.1) var rise_seconds := 7.0
@export_range(0.5, 30.0, 0.1) var lower_seconds := 10.0
@export_range(0.0, 0.2, 0.005) var settle_overshoot := 0.045
@export_range(0.1, 1.0, 0.05) var settle_seconds := 0.45
@export_range(0.0, 0.15, 0.005) var return_overshoot := 0.035
@export_range(0.1, 1.0, 0.05) var return_settle_seconds := 0.6

var activated := false
var resting_position: Vector3
var movement: Tween
var skull_ritual: Node
var pit_particles: GPUParticles3D

func _ready() -> void:
	if is_instance_valid(altar):
		resting_position = altar.global_position
	set_meta("outline_contour", _build_pentagram_mesh())
	skull_ritual = get_tree().current_scene.get_node_or_null("StreetProps/Skull/SkullRitual")
	if is_instance_valid(skull_ritual) and skull_ritual.has_signal("violet_stage_changed"):
		skull_ritual.connect("violet_stage_changed", Callable(self, "_on_violet_stage_changed"))
	_make_pit_particles()
	if _skull_is_violet():
		_on_violet_stage_changed(true)

func can_interact() -> bool:
	return _skull_is_violet() and not activated and is_instance_valid(altar)

func interaction_outline_color() -> Color:
	return VIOLET

func interact(_player: Node3D) -> void:
	if not can_interact():
		return
	# The top of the click disk sits at the lip of the lower crater.
	var disk: CollisionShape3D = $Opening
	var cylinder := disk.shape as CylinderShape3D
	var rim_y := disk.to_global(Vector3.UP * cylinder.height * 0.5).y
	var mesh: MeshInstance3D = altar.get_node("Model/altar")
	var altar_top := (mesh.global_transform * mesh.get_aabb()).end.y
	activated = true
	if movement and movement.is_running():
		movement.kill()
	var target_y := altar.global_position.y + rim_y - altar_top
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

func _skull_is_violet() -> bool:
	return is_instance_valid(skull_ritual) and skull_ritual.has_method("is_violet_active") and bool(skull_ritual.call("is_violet_active"))

func _on_violet_stage_changed(active: bool) -> void:
	if not is_instance_valid(pit_particles):
		return
	if active:
		pit_particles.visible = true
		pit_particles.restart()
		pit_particles.emitting = true
	else:
		pit_particles.emitting = false
		pit_particles.visible = false

func _make_pit_particles() -> void:
	var process := ParticleProcessMaterial.new()
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
	var material := ShaderMaterial.new()
	material.shader = PIT_PARTICLE_SHADER
	material.set_shader_parameter("particle_size", 3.0)
	var points := PointMesh.new()
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
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.68, 0.22, 1.0, 0.0))
	gradient.set_color(1, Color(0.38, 0.08, 0.72, 0.0))
	gradient.add_point(0.12, Color(0.72, 0.3, 1.0, 0.82))
	gradient.add_point(0.72, Color(0.58, 0.16, 0.95, 0.5))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

func _build_pentagram_mesh() -> ArrayMesh:
	var radius := 1.45
	var ring_y := 1.12
	var stroke := 0.035
	var dot_radius := 0.065
	var outer: Array[Vector2] = []
	for i in 5:
		var angle := -PI * 0.5 + TAU * float(i) / 5.0
		outer.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var order := [0, 2, 4, 1, 3, 0]
	for i in range(5):
		var a: Vector2 = outer[order[i]]
		var b: Vector2 = outer[order[i + 1]]
		var direction := (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x) * stroke * 0.5
		var base := vertices.size()
		vertices.append(Vector3(a.x + normal.x, ring_y, a.y + normal.y))
		vertices.append(Vector3(a.x - normal.x, ring_y, a.y - normal.y))
		vertices.append(Vector3(b.x - normal.x, ring_y, b.y - normal.y))
		vertices.append(Vector3(b.x + normal.x, ring_y, b.y + normal.y))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	for point in outer:
		var center_index := vertices.size()
		vertices.append(Vector3(point.x, ring_y + 0.004, point.y))
		for i in 12:
			var angle := TAU * float(i) / 12.0
			vertices.append(Vector3(point.x + cos(angle) * dot_radius, ring_y + 0.004, point.y + sin(angle) * dot_radius))
		for i in 12:
			var a := center_index + 1 + i
			var b := center_index + 1 + ((i + 1) % 12)
			indices.append_array(PackedInt32Array([center_index, a, b]))

	# A thin circular rim frames the star just inside the pit's physical edge.
	var circle_radius := 1.58
	var circle_stroke := 0.025
	var circle_segments := 96
	var circle_y := ring_y + 0.006
	for i in circle_segments:
		var angle_a := TAU * float(i) / float(circle_segments)
		var angle_b := TAU * float(i + 1) / float(circle_segments)
		var a := Vector2(cos(angle_a) * circle_radius, sin(angle_a) * circle_radius)
		var b := Vector2(cos(angle_b) * circle_radius, sin(angle_b) * circle_radius)
		var direction := (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x) * circle_stroke * 0.5
		var base := vertices.size()
		vertices.append(Vector3(a.x + normal.x, circle_y, a.y + normal.y))
		vertices.append(Vector3(a.x - normal.x, circle_y, a.y - normal.y))
		vertices.append(Vector3(b.x - normal.x, circle_y, b.y - normal.y))
		vertices.append(Vector3(b.x + normal.x, circle_y, b.y + normal.y))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
