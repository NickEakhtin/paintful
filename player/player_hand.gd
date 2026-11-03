class_name PlayerHand
extends Node3D
## The colleague's first-person glove: locked to the camera's position with rotational inertia, a small sway in step
## with the head bob and a short jab (tap()). While the player holds an item the glove turns its palm to the camera
## and the item lies across it at `hold_point`. A sweep keeps the glove out of walls; an AnimatableBody on the
## "prop_physics" layer pushes the hanging chains. Must be a direct child of the player's Camera3D.

@export var camera_offset: Vector3 = Vector3(0.25, -0.34, -0.44)
@export_range(10.0, 80.0, 1.0) var rotation_follow_speed: float = 26.0
@export_range(0.03, 0.3, 0.01) var tap_distance: float = 0.12
@export_range(0.03, 0.15, 0.01) var tap_out_seconds: float = 0.06
@export_range(0.05, 0.25, 0.01) var tap_return_seconds: float = 0.11
@export_range(0.0, 35.0, 1.0) var inward_aim_degrees: float = 14.0
@export_range(45.0, 90.0, 1.0) var hold_finger_angle_degrees: float = 45.0
@export_range(4.0, 24.0, 1.0) var hold_pose_speed: float = 12.0
@export_range(8.0, 40.0, 1.0) var physics_follow_speed: float = 24.0
@export var held_obstacle_offset: Vector3 = Vector3(0.12, -0.12, 0.0)
@export_range(4.0, 24.0, 1.0) var held_obstacle_retract_speed: float = 14.0

const PROP_PHYSICS_LAYER: int = 32      # layer 6: the hanging chains
const SCENERY_MASK: int = 1             # what the glove's sweep stays out of

## Where a held item lies, across the palm.
var hold_point: Node3D = Node3D.new()

var _camera: Camera3D
var _player: Node3D
var _glove: Node3D
var _base_orientation: Quaternion = Quaternion.IDENTITY
var _hold_orientation: Quaternion = Quaternion.IDENTITY
var _current_orientation: Quaternion = Quaternion.IDENTITY
var _target_orientation: Quaternion = Quaternion.IDENTITY
var _glove_scale: Vector3 = Vector3.ONE
var _rest_camera_offset: Vector3 = Vector3.ZERO
var _tap_tween: Tween
var _hand_shape: CapsuleShape3D = CapsuleShape3D.new()
var _held_hand_shape: CapsuleShape3D = CapsuleShape3D.new()
var _sweep: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _physics_hand: AnimatableBody3D
var _physics_hand_initialized: bool = false
var _restore_collision_frame: int = -1
var _raw_desired_position: Vector3 = Vector3.ZERO
var _desired_position: Vector3 = Vector3.ZERO
var _holding: bool = false
var _sweep_blocked: bool = false
var _retract_weight: float = 0.0


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera == null:
		push_warning("PlayerHand must be a direct child of Camera3D.")
		return
	top_level = true
	_player = _camera.get_parent().get_parent() as Node3D
	_hand_shape.radius = 0.11
	_hand_shape.height = 0.43
	# a held item reaches farther across the palm than the bare glove
	_held_hand_shape.radius = 0.15
	_held_hand_shape.height = 0.50
	_sweep.shape = _hand_shape
	_sweep.collision_mask = SCENERY_MASK
	_sweep.collide_with_areas = false
	_sweep.margin = 0.01
	_rest_camera_offset = camera_offset
	global_transform = Transform3D(_camera.global_basis, _target_position())
	_setup_glove()
	_apply_soft_reflection()
	_setup_physics_hand()
	_raw_desired_position = global_position
	_desired_position = global_position


func _process(delta: float) -> void:
	if _camera == null:
		return
	var step: Vector3 = _player.call(&"get_hand_bob_state") if _player.has_method(&"get_hand_bob_state") else Vector3.ZERO
	var step_weight: float = clampf(step.y, 0.0, 1.3)
	var hand_sway: Vector3 = Vector3(0.012 * cos(step.x) * step_weight, -0.014 * step.z * step_weight, 0.0)
	# translation stays locked to the camera, plus a small sway in step with the walk
	var desired: Vector3 = _camera.global_position + _camera.global_basis * (camera_offset + hand_sway)
	var step_rotation: Vector3 = Vector3(deg_to_rad(-0.8 * step.z * step_weight), 0.0, deg_to_rad(1.1 * sin(step.x) * step_weight))
	var target_basis: Basis = _camera.global_basis * Basis.from_euler(step_rotation)
	var safe_delta: float = minf(delta, 0.05)
	global_basis = global_basis.slerp(target_basis, 1.0 - exp(-rotation_follow_speed * safe_delta)).orthonormalized()
	if _glove != null:
		_current_orientation = _current_orientation.slerp(_target_orientation, 1.0 - exp(-hold_pose_speed * safe_delta))
		_apply_orientation()
	_raw_desired_position = desired
	var physics_ready: bool = _physics_hand != null and _physics_hand.is_inside_tree() and _physics_hand_initialized
	global_position = _physics_hand.global_position if physics_ready else desired


func _physics_process(delta: float) -> void:
	if _physics_hand == null or not _physics_hand.is_inside_tree() or _glove == null:
		return
	var safe_rest: Vector3 = _collision_safe_position(_raw_desired_position)
	var retract_target: float = 1.0 if _holding and _sweep_blocked else 0.0
	_retract_weight = lerpf(_retract_weight, retract_target, 1.0 - exp(-held_obstacle_retract_speed * minf(delta, 0.05)))
	if _holding and _retract_weight > 0.001:
		_desired_position = _collision_safe_position(_raw_desired_position + _camera.global_basis * (held_obstacle_offset * _retract_weight))
	else:
		_desired_position = safe_rest
	if not _physics_hand_initialized:
		_physics_hand.global_transform = Transform3D(_glove.global_basis.orthonormalized(), _desired_position)
		_physics_hand_initialized = true
		global_position = _physics_hand.global_position
		return
	if _restore_collision_frame >= 0 and Engine.get_physics_frames() >= _restore_collision_frame:
		_physics_hand.collision_layer = PROP_PHYSICS_LAYER
		_restore_collision_frame = -1
	var blend: float = 1.0 - exp(-physics_follow_speed * minf(delta, 0.05))
	var body_basis: Basis = _physics_hand.global_basis.slerp(_glove.global_basis.orthonormalized(), blend).orthonormalized()
	var body_position: Vector3 = _physics_hand.global_position.lerp(_desired_position, blend)
	_physics_hand.global_transform = Transform3D(body_basis, body_position)
	global_position = body_position


func tap() -> void:
	if _camera == null:
		return
	if _tap_tween and _tap_tween.is_running():
		_tap_tween.kill()
	camera_offset = _rest_camera_offset
	_tap_tween = create_tween()
	_tap_tween.tween_property(self, "camera_offset", _rest_camera_offset + Vector3(0.0, 0.0, -tap_distance), tap_out_seconds)
	_tap_tween.tween_property(self, "camera_offset", _rest_camera_offset, tap_return_seconds)


## Palm up to hold an item, or back to the pointing pose.
func set_holding(holding: bool) -> void:
	_holding = holding
	_target_orientation = _hold_orientation if holding else _base_orientation


func snap_to_camera() -> void:
	if _camera == null:
		return
	global_basis = _camera.global_basis.orthonormalized()
	if _glove != null:
		_apply_orientation()
	var target_position: Vector3 = _target_position()
	_raw_desired_position = target_position
	_desired_position = target_position
	global_position = target_position
	if _physics_hand != null and _physics_hand.is_inside_tree() and _glove != null:
		_physics_hand.collision_layer = 0
		_physics_hand.global_transform = Transform3D(_glove.global_basis.orthonormalized(), target_position)
		_physics_hand_initialized = true
		_restore_collision_frame = Engine.get_physics_frames() + 2


func _collision_safe_position(desired: Vector3) -> Vector3:
	_sweep_blocked = false
	if _glove == null:
		return desired
	var hand_basis: Basis = _glove.global_basis.orthonormalized()
	var start_root: Vector3 = _camera.global_position + _camera.global_basis.z * 0.55
	var motion: Vector3 = desired - start_root
	_sweep.shape = _held_hand_shape if _holding else _hand_shape
	_sweep.transform = Transform3D(hand_basis, start_root + hand_basis.y.normalized() * 0.18)
	_sweep.motion = motion
	_sweep.exclude = [(_player as CollisionObject3D).get_rid()] if _player is CollisionObject3D else []
	var travel: PackedFloat32Array = _camera.get_world_3d().direct_space_state.cast_motion(_sweep)
	if travel.size() < 2 or travel[0] >= 1.0:
		return desired
	_sweep_blocked = true
	var safe_fraction: float = travel[0]
	if motion.length() > 0.001:
		safe_fraction = maxf(safe_fraction - 0.015 / motion.length(), 0.0)
	var resolved: Vector3 = start_root + motion * safe_fraction
	var local: Vector3 = _camera.global_basis.inverse() * (resolved - _camera.global_position)
	if local.z > -0.12:
		local = _camera.global_basis.inverse() * (desired - _camera.global_position)
		local.z = -0.12
		resolved = _camera.global_position + _camera.global_basis * local
	return resolved


func _setup_physics_hand() -> void:
	if _glove == null or _player == null:
		return
	_physics_hand = AnimatableBody3D.new()
	_physics_hand.name = "PlayerHandPhysics"
	_physics_hand.collision_layer = PROP_PHYSICS_LAYER
	_physics_hand.collision_mask = PROP_PHYSICS_LAYER
	_physics_hand.sync_to_physics = true
	var hand_shape: CollisionShape3D = CollisionShape3D.new()
	hand_shape.name = "GloveCollision"
	hand_shape.position = Vector3(0.0, 0.18, 0.0)
	hand_shape.shape = _hand_shape
	_physics_hand.add_child(hand_shape)
	# under the player, so teleports carry it along; the player is still adding its children now
	_player.add_child.call_deferred(_physics_hand)


func _setup_glove() -> void:
	_glove = get_node_or_null("GloveModel") as Node3D
	if _glove == null:
		return
	_glove_scale = _glove.scale
	# flip around the finger axis, aim the fingers forward, then cant them toward the screen centre
	_base_orientation = Quaternion(Vector3.UP, deg_to_rad(inward_aim_degrees))
	_base_orientation *= Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))
	_base_orientation *= Quaternion(Vector3.UP, PI)
	# holding: palm to the camera, fingers toward the screen centre, 45 degrees above horizontal
	var finger_angle: float = deg_to_rad(hold_finger_angle_degrees)
	var finger_direction: Vector3 = Vector3(-cos(finger_angle), sin(finger_angle), 0.0).normalized()
	var palm_normal: Vector3 = Vector3.BACK
	var hand_width: Vector3 = finger_direction.cross(palm_normal).normalized()
	_hold_orientation = Quaternion(Basis(hand_width, finger_direction, palm_normal))
	_current_orientation = _base_orientation
	_target_orientation = _base_orientation
	_apply_orientation()
	# an item lies across the palm, its lower edge on the glove
	hold_point.name = "HoldPoint"
	hold_point.position = Vector3(0.09, 0.29, 0.10)
	hold_point.rotation.z = deg_to_rad(90.0)
	_glove.add_child(hold_point)


func _apply_orientation() -> void:
	_glove.basis = Basis(_current_orientation) * Basis.from_scale(_glove_scale)


func _apply_soft_reflection() -> void:
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source: Material = mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var finish: StandardMaterial3D = source.duplicate() as StandardMaterial3D
				finish.metallic = 0.08
				finish.roughness = 0.42
				mesh.set_surface_override_material(surface, finish)


func _target_position() -> Vector3:
	return _camera.global_position + _camera.global_basis * camera_offset
