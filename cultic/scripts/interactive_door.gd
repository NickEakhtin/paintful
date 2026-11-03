extends Node3D
## A door the player opens and closes with LMB (player.gd calls interact()). Put it on a door instance in its
## closed position, pivot on the hinge (models/door.glb has it there). It swings away from the player.
## An open door closes by itself once the player walks farther than `auto_close_distance` from its hinge.

@export var open_angle := 95.0      # degrees
@export var duration := 0.7
@export var auto_close_distance := 2.5    # metres (horizontal) from the hinge; 0 = stays open

var _closed_yaw := 0.0
var _open := false
var _tween: Tween
var _opener: Node3D
var _close_beyond := 0.0      # opened from farther than auto_close_distance? then close only beyond that
var _front_frame_target: StaticBody3D
var _back_frame_target: StaticBody3D


func _ready() -> void:
	_closed_yaw = rotation.y
	_add_frame_interaction_targets()


func _add_frame_interaction_targets() -> void:
	# Put a raycast target just above the door leaf on each side. The shared outline
	# renders an inset frame within the door's outer edges.
	for side in [-1.0, 1.0]:
		var target := StaticBody3D.new()
		target.name = "DoorFrameInteraction_%s" % ("Front" if side > 0.0 else "Back")
		target.collision_layer = 4
		target.collision_mask = 0
		target.top_level = true
		target.set_meta("outline_front_sign", side)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.72, 1.8, 0.06)
		shape.shape = box
		shape.position = Vector3(-0.4, 1.0, side * 0.105)
		target.add_child(shape)
		add_child(target)
		target.global_transform = global_transform
		if side > 0.0:
			_front_frame_target = target
		else:
			_back_frame_target = target


func interaction_outline_collider(player: Node3D) -> StaticBody3D:
	var player_in_front := global_basis.z.dot(player.global_position - global_position) > 0.0
	return _front_frame_target if player_in_front else _back_frame_target


func can_interact() -> bool:
	return not (_tween and _tween.is_running())

func interact(player: Node3D) -> void:
	if _tween and _tween.is_running():
		return
	var target := _closed_yaw
	if not _open:
		# the leaf runs from the hinge along local -X, so a positive turn swings it to the front (+Z) side
		var player_in_front := global_basis.z.dot(player.global_position - global_position) > 0.0
		target = _closed_yaw + deg_to_rad(open_angle) * (-1.0 if player_in_front else 1.0)
	_open = not _open
	_opener = player
	var from := player.global_position - global_position
	_close_beyond = maxf(auto_close_distance, Vector2(from.x, from.z).length() + 0.5)
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "rotation:y", target, duration)


func _physics_process(_delta: float) -> void:
	if not _open or auto_close_distance <= 0.0 or (_tween and _tween.is_running()):
		return
	var player := _opener if is_instance_valid(_opener) else get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var offset := player.global_position - global_position
	if Vector2(offset.x, offset.z).length() > _close_beyond:
		interact(player)          # the door is open, so this swings it shut
