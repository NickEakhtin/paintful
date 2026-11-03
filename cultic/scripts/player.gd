extends CharacterBody3D
## First-person walker for looking around a room scene: WASD (any keyboard layout), mouse to look, Shift to run and
## Space to jump (when `can_run` / `can_jump` are on), Esc frees the mouse, a click grabs it again.
## The models come without collision, so on start it gives the scene some: exact shapes for the room shell
## (walls with door and window openings stay walkable), a box around each piece of furniture, nothing for small props
## and curtains.

@export var walk_speed := 2.2
@export var run_speed := 4.5
@export var jump_velocity := 3.5
@export var can_run := false                                         # Shift runs
@export var can_jump := false                                        # Space jumps
@export var mouse_sensitivity := 0.0022
@export var shell_groups: PackedStringArray = ["Shell"]              # exact collision
@export var furniture_groups: PackedStringArray = ["Furniture", "Decor", "NewModels", "RepoModels"]   # boxes
@export var min_prop_size := 0.35                                    # smaller meshes get no collision
@export var skip_names: PackedStringArray = ["curtain", "rug", "light", "sky", "simplewoodencabinet"]
@export var floor_cover_height := 0.2                               # flat things lying on the floor lower than this get no collision
@export var wall_mounted_above := 0.6                               # things hanging higher than this off the floor get no collision
@export var reach := 2.5                                            # how far LMB reaches
@export_flags_3d_physics var use_mask := 5                          # what LMB can hit: the world and click targets (layer 3), not the invisible walls (layer 2)
@export_group("Head bob")
@export var bob_height := 0.05                                      # how far the head drops on each footfall at walking speed, metres
@export var bob_sway := 0.03                                        # side to side per stride at walking speed, metres
@export var stride_length := 2.0                                    # metres per full stride (two steps): longer = slower, heavier steps
@export var footfall_sharpness := 3.0                               # 1 = smooth bounce; higher = a quick heavy drop on each step, slow rise
@export var bob_roll_degrees := 0.9                                 # camera leans towards the foot that carries the weight
@export var bob_nod_degrees := 0.6                                  # camera dips forward a little on each footfall
@export var run_sway := 0.35                                       # side sway and lean when running, relative to walking (1 = the same)
@export var bob_smoothing := 4.0                                    # how quickly the bob fades in when you start and out when you stop

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _hand: Node3D = $Head/Camera3D/PlayerHand
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _outline := preload("res://player/outline/interaction_outline.gd").new()
var _head_rest: Vector3
var _bob_phase := 0.0
var _bob_amount := 0.0                # current bob strength, eased towards the walking speed
var _has_yellow_paint := false


func _ready() -> void:
	add_to_group("player")
	add_child(_outline)
	_head_rest = _head.position
	_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var scene_root := owner if owner else get_parent()
	for group in shell_groups:
		_add_collision(scene_root.get_node_or_null(NodePath(group)), false)
	for group in furniture_groups:
		_add_collision(scene_root.get_node_or_null(NodePath(group)), true)
	var floor := StaticBody3D.new()                                  # safety net under the whole level
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	floor.position.y = -0.05
	scene_root.add_child.call_deferred(floor)


func _add_collision(group: Node, boxes: bool) -> void:
	if group == null:
		return
	for mesh: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _skipped(mesh, group):
			continue
		var size := (mesh.global_basis * mesh.get_aabb().size).abs()
		if boxes and maxf(size.x, maxf(size.y, size.z)) < min_prop_size:
			continue
		var top := (mesh.global_transform * mesh.get_aabb()).end.y
		if boxes and size.y < floor_cover_height and top < floor_cover_height + 0.1:
			continue                                                    # rugs, tile platforms: walked over, not bumped into
		if boxes and top - size.y > wall_mounted_above:
			continue                                                    # shelves, frames, skulls on the walls: the wall already stops you
		if not boxes:
			mesh.create_trimesh_collision()
			continue
		var body := StaticBody3D.new()                                # a box is instant; hulls of these models took seconds
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.get_aabb().size
		shape.shape = box
		shape.position = mesh.get_aabb().get_center()
		body.add_child(shape)
		mesh.add_child(body)


func _skipped(mesh: Node, group: Node) -> bool:
	var n := mesh
	while n != group:
		var lower := String(n.name).to_lower()
		for word in skip_names:
			if lower.contains(word):
				return true
		n = n.get_parent()
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_head.rotate_x(-event.relative.y * mouse_sensitivity)
		_head.rotation.x = clampf(_head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.button_index == MOUSE_BUTTON_LEFT:
			_use()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## LMB: whatever you look at within reach that has interact() (doors, the basement hatch) gets used.
func _use() -> void:
	var hit := _interaction_hit()
	if not hit.is_empty():
		if _hand.has_method("tap"):
			_hand.call("tap")
		hit.target.interact(self)


func collect_yellow_paint() -> bool:
	if _has_yellow_paint:
		return false
	_has_yellow_paint = true
	if _hand.has_method("set_holding_yellow_paint"):
		_hand.call("set_holding_yellow_paint", true)
	return true

func _interaction_hit() -> Dictionary:
	var from := _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - _camera.global_basis.z * reach, use_mask)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var node: Node = hit.collider if hit else null
	while node and not node.has_method("interact"):
		node = node.get_parent()
	if node and (not node.has_method("can_interact") or node.can_interact()):
		hit["target"] = node
		return hit
	return {}


func _physics_process(delta: float) -> void:
	_outline.track(null)   # the outline now follows our Interactables only
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif can_jump and Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var speed := run_speed if can_run and Input.is_physical_key_pressed(KEY_SHIFT) else walk_speed
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()


## Head bob: on every footfall the head drops quickly (the weight lands on the leg) and rises slowly, swaying towards
## the standing leg with a slight lean and nod; scaled by speed, eased back to rest on the spot or in the air.
func get_hand_bob_state() -> Vector3:
	var step := pow(fmod(_bob_phase, PI) / PI, 1.4)
	var footfall := pow(1.0 - sin(step * PI), footfall_sharpness)
	return Vector3(_bob_phase, _bob_amount, footfall)


func _process(delta: float) -> void:
	if not is_physics_processing():
		_outline.track(null)
	var speed := Vector2(velocity.x, velocity.z).length()
	var walking := is_on_floor() and speed > 0.1
	_bob_amount = move_toward(_bob_amount, minf(speed / walk_speed, 1.6) if walking else 0.0, delta * bob_smoothing)
	if walking:
		_bob_phase = fmod(_bob_phase + speed * delta / stride_length * TAU, TAU)
	# progress through the current step, 0 = a foot lands; bent so the head falls fast into the landing and climbs slowly
	var step := pow(fmod(_bob_phase, PI) / PI, 1.4)
	var footfall := pow(1.0 - sin(step * PI), footfall_sharpness)            # 1 right when a foot lands, 0 mid-step
	var side := cos(_bob_phase)                                             # which leg carries the weight
	# side to side: as much as walking at most, and less the closer to full running speed
	var running := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var sway := minf(_bob_amount, 1.0) * lerpf(1.0, run_sway, running)
	_head.position = _head_rest + Vector3(side * bob_sway * sway, -footfall * bob_height * _bob_amount, 0.0)
	_camera.rotation.z = deg_to_rad(bob_roll_degrees) * side * sway
	_camera.rotation.x = -deg_to_rad(bob_nod_degrees) * footfall * _bob_amount
