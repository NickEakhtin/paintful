extends Node3D
## First-person glove: locked to camera position, with rotational inertia and a short touch jab.

const PAINT_MODEL_SCENE := preload("res://cultic/scenes/props/yellow_paint_model.tscn")

@export var camera_offset := Vector3(0.25, -0.34, -0.44)
@export_range(10.0, 80.0, 1.0) var rotation_follow_speed := 26.0
@export_range(0.03, 0.3, 0.01) var tap_distance := 0.12
@export_range(0.03, 0.15, 0.01) var tap_out_seconds := 0.06
@export_range(0.05, 0.25, 0.01) var tap_return_seconds := 0.11
@export_range(0.0, 35.0, 1.0) var inward_aim_degrees := 14.0
@export_range(45.0, 90.0, 1.0) var paint_finger_angle_degrees := 45.0
@export_range(4.0, 24.0, 1.0) var paint_pose_speed := 12.0
@export_range(8.0, 40.0, 1.0) var physics_follow_speed := 24.0
@export var held_obstacle_offset := Vector3(0.12, -0.12, 0.0)
@export_range(4.0, 24.0, 1.0) var held_obstacle_retract_speed := 14.0

var camera: Camera3D
var player: Node
var glove: Node3D
var held_paint: Node3D
var base_glove_orientation := Quaternion.IDENTITY
var paint_glove_orientation := Quaternion.IDENTITY
var current_glove_orientation := Quaternion.IDENTITY
var target_glove_orientation := Quaternion.IDENTITY
var glove_scale := Vector3.ONE
var rest_camera_offset := Vector3.ZERO
var tap_tween: Tween
var _hand_collision_shape := CapsuleShape3D.new()
var _held_hand_collision_shape := CapsuleShape3D.new()
var _hand_collision_query := PhysicsShapeQueryParameters3D.new()
var _physics_hand: AnimatableBody3D
var _physics_hand_initialized := false
var _restore_hand_collision_frame := -1
var _raw_desired_hand_position := Vector3.ZERO
var _desired_hand_position := Vector3.ZERO
var _holding_yellow_paint := false
var _hand_sweep_blocked := false
var _held_obstacle_retract_weight := 0.0

func _ready() -> void:
	camera = get_parent() as Camera3D
	if not is_instance_valid(camera):
		push_warning("PlayerHandFollow must be a direct child of Camera3D.")
		return

	top_level = true
	player = camera.get_parent().get_parent()
	_hand_collision_shape.radius = 0.11
	_hand_collision_shape.height = 0.43
	# The held tube extends farther across the palm than the glove's normal sweep volume.
	_held_hand_collision_shape.radius = 0.15
	_held_hand_collision_shape.height = 0.50
	_hand_collision_query.shape = _hand_collision_shape
	# The visual sweep checks scenery; the physics body handles articulated objects such as chains.
	_hand_collision_query.collision_mask = 0xFFFFFFEF
	_hand_collision_query.collide_with_areas = false
	_hand_collision_query.margin = 0.01
	rest_camera_offset = camera_offset
	global_transform = Transform3D(camera.global_basis, _target_position())
	_setup_glove_and_paint()
	_apply_soft_reflection()
	_setup_physics_hand()
	_raw_desired_hand_position = global_position
	_desired_hand_position = global_position

func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		return
	var step_state := _get_footstep_motion()
	var step_weight := clampf(step_state.y, 0.0, 1.3)
	var hand_sway := Vector3(
		0.012 * cos(step_state.x) * step_weight,
		-0.014 * step_state.z * step_weight,
		0.0
	)
	# Keep translation locked to the camera while adding a small step-synchronised sway.
	var desired_position := camera.global_position + camera.global_basis * (camera_offset + hand_sway)
	var step_rotation := Vector3(
		deg_to_rad(-0.8 * step_state.z * step_weight),
		0.0,
		deg_to_rad(1.1 * sin(step_state.x) * step_weight)
	)
	var target_basis := camera.global_basis * Basis.from_euler(step_rotation)
	var safe_delta := minf(delta, 0.05)
	var rotation_blend := 1.0 - exp(-rotation_follow_speed * safe_delta)
	global_basis = global_basis.slerp(target_basis, rotation_blend).orthonormalized()
	if is_instance_valid(glove):
		var pose_blend := 1.0 - exp(-paint_pose_speed * safe_delta)
		current_glove_orientation = current_glove_orientation.slerp(target_glove_orientation, pose_blend)
		_apply_glove_orientation()
	_raw_desired_hand_position = desired_position
	global_position = _physics_hand.global_position if is_instance_valid(_physics_hand) and _physics_hand.is_inside_tree() and _physics_hand_initialized else desired_position

func _collision_safe_hand_position(desired_position: Vector3) -> Vector3:
	_hand_sweep_blocked = false
	if not is_instance_valid(glove):
		return desired_position
	var hand_basis := glove.global_basis.orthonormalized()
	var finger_axis := hand_basis.y.normalized()
	var start_root := camera.global_position + camera.global_basis.z * 0.55
	var motion := desired_position - start_root
	_hand_collision_query.shape = _held_hand_collision_shape if _holding_yellow_paint else _hand_collision_shape
	_hand_collision_query.transform = Transform3D(hand_basis, start_root + finger_axis * 0.18)
	_hand_collision_query.motion = motion
	_hand_collision_query.exclude = []
	if player is CollisionObject3D:
		var player_body := player as CollisionObject3D
		_hand_collision_query.exclude = [player_body.get_rid()]

	var travel := camera.get_world_3d().direct_space_state.cast_motion(_hand_collision_query)
	if travel.size() < 2 or travel[0] >= 1.0:
		return desired_position

	_hand_sweep_blocked = true
	var safe_fraction: float = travel[0]
	if motion.length() > 0.001:
		safe_fraction = maxf(safe_fraction - 0.015 / motion.length(), 0.0)
	var resolved := start_root + motion * safe_fraction
	var camera_offset_position := camera.global_basis.inverse() * (resolved - camera.global_position)
	if camera_offset_position.z > -0.12:
		camera_offset_position = camera.global_basis.inverse() * (desired_position - camera.global_position)
		camera_offset_position.z = -0.12
		resolved = camera.global_position + camera.global_basis * camera_offset_position
	return resolved


func _setup_physics_hand() -> void:
	if not is_instance_valid(glove) or not player is Node3D:
		return

	_physics_hand = AnimatableBody3D.new()
	_physics_hand.name = "PlayerHandPhysics"
	# Layer 5 matches the articulated chain links.
	_physics_hand.collision_layer = 16
	# The articulated chain links use layer 5; scenery is handled by the visual sweep.
	_physics_hand.collision_mask = 16
	_physics_hand.sync_to_physics = true
	var hand_shape := CollisionShape3D.new()
	hand_shape.name = "GloveCollision"
	hand_shape.position = Vector3(0.0, 0.18, 0.0)
	hand_shape.shape = _hand_collision_shape
	_physics_hand.add_child(hand_shape)
	# Keep this body under Player so teleports carry it with the camera.
	# PlayerHand._ready() runs while Player is still setting up children.
	(player as Node3D).add_child.call_deferred(_physics_hand)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_physics_hand) or not _physics_hand.is_inside_tree() or not is_instance_valid(glove):
		return
	var safe_rest_position := _collision_safe_hand_position(_raw_desired_hand_position)
	var retract_target := 1.0 if _holding_yellow_paint and _hand_sweep_blocked else 0.0
	var retract_blend := 1.0 - exp(-held_obstacle_retract_speed * minf(delta, 0.05))
	_held_obstacle_retract_weight = lerpf(_held_obstacle_retract_weight, retract_target, retract_blend)
	if _holding_yellow_paint and _held_obstacle_retract_weight > 0.001:
		var retracted_position := _raw_desired_hand_position + camera.global_basis * (held_obstacle_offset * _held_obstacle_retract_weight)
		_desired_hand_position = _collision_safe_hand_position(retracted_position)
	else:
		_desired_hand_position = safe_rest_position
	if not _physics_hand_initialized:
		_physics_hand.global_transform = Transform3D(glove.global_basis.orthonormalized(), _desired_hand_position)
		_physics_hand_initialized = true
		global_position = _physics_hand.global_position
		return

	if _restore_hand_collision_frame >= 0 and Engine.get_physics_frames() >= _restore_hand_collision_frame:
		_physics_hand.collision_layer = 16
		_restore_hand_collision_frame = -1
	var blend := 1.0 - exp(-physics_follow_speed * minf(delta, 0.05))
	var target_basis := glove.global_basis.orthonormalized()
	var body_basis := _physics_hand.global_basis.slerp(target_basis, blend).orthonormalized()
	var body_position := _physics_hand.global_position.lerp(_desired_hand_position, blend)
	_physics_hand.global_transform = Transform3D(body_basis, body_position)
	global_position = body_position


func snap_to_camera() -> void:
	if not is_instance_valid(camera):
		return
	global_basis = camera.global_basis.orthonormalized()
	if is_instance_valid(glove):
		_apply_glove_orientation()
	var target_position := _target_position()
	_raw_desired_hand_position = target_position
	_desired_hand_position = target_position
	global_position = target_position
	if is_instance_valid(_physics_hand) and _physics_hand.is_inside_tree() and is_instance_valid(glove):
		_physics_hand.collision_layer = 0
		_physics_hand.global_transform = Transform3D(glove.global_basis.orthonormalized(), target_position)
		_physics_hand_initialized = true
		_restore_hand_collision_frame = Engine.get_physics_frames() + 2


func _target_position() -> Vector3:
	return camera.global_position + camera.global_basis * camera_offset

func _get_footstep_motion() -> Vector3:
	if is_instance_valid(player) and player.has_method("get_hand_bob_state"):
		return player.call("get_hand_bob_state")
	return Vector3.ZERO

func tap() -> void:
	if not is_instance_valid(camera):
		return
	if tap_tween and tap_tween.is_running():
		tap_tween.kill()
	camera_offset = rest_camera_offset
	tap_tween = create_tween()
	tap_tween.tween_property(self, "camera_offset", rest_camera_offset + Vector3(0.0, 0.0, -tap_distance), tap_out_seconds)
	tap_tween.tween_property(self, "camera_offset", rest_camera_offset, tap_return_seconds)

func _setup_glove_and_paint() -> void:
	glove = get_node_or_null("GloveModel") as Node3D
	if not is_instance_valid(glove):
		return
	glove_scale = glove.scale
	# Flip around the finger axis, aim the fingers forward, then cant them toward the screen centre.
	base_glove_orientation = Quaternion(Vector3.UP, deg_to_rad(inward_aim_degrees))
	base_glove_orientation *= Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))
	base_glove_orientation *= Quaternion(Vector3.UP, PI)
	# During a hold, face the palm toward the camera and aim the fingers toward screen centre.
	# Keep the fingers aimed toward screen centre, with a lower 45-degree angle above horizontal.
	var finger_angle := deg_to_rad(paint_finger_angle_degrees)
	var held_finger_direction := Vector3(-cos(finger_angle), sin(finger_angle), 0.0).normalized()
	var held_palm_normal := Vector3.BACK
	var held_hand_width := held_finger_direction.cross(held_palm_normal).normalized()
	paint_glove_orientation = Quaternion(Basis(held_hand_width, held_finger_direction, held_palm_normal))
	current_glove_orientation = base_glove_orientation
	target_glove_orientation = base_glove_orientation
	_apply_glove_orientation()

	held_paint = PAINT_MODEL_SCENE.instantiate() as Node3D
	held_paint.name = "HeldYellowPaint"
	# Lay the tube across the palm, label facing the player, with its lower edge resting on the glove.
	held_paint.position = Vector3(0.09, 0.29, 0.10)
	held_paint.rotation.z = deg_to_rad(90.0)
	held_paint.scale = Vector3.ONE * 0.45
	held_paint.visible = false
	glove.add_child(held_paint)

func _apply_glove_orientation() -> void:
	glove.basis = Basis(current_glove_orientation) * Basis.from_scale(glove_scale)

func set_holding_yellow_paint(holding: bool) -> void:
	_holding_yellow_paint = holding
	target_glove_orientation = paint_glove_orientation if holding else base_glove_orientation
	if is_instance_valid(held_paint):
		held_paint.visible = holding

func _apply_soft_reflection() -> void:
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var finish := source.duplicate() as StandardMaterial3D
				finish.metallic = 0.08
				finish.roughness = 0.42
				mesh.set_surface_override_material(surface, finish)
