extends Node3D

@export var auto_close_distance := 2.5

var door_tween: Tween
var handle_tween: Tween
var doors_open := false
var _opener: Node3D
var _close_beyond := 0.0
@onready var door_left: Node3D = $LeftDoorHinge
@onready var door_right: Node3D = $RightDoorHinge
@onready var handle_left: Node3D = $LeftDoorHinge/GoldHandle
@onready var handle_right: Node3D = $RightDoorHinge/GoldHandle
@onready var interior_light: OmniLight3D = $InteriorLight
@onready var lower_shelf_light: OmniLight3D = $LowerShelfLight
@onready var click_area: StaticBody3D = $CabinetClickArea

func _ready() -> void:
	click_area.set_meta("outline_front_sign", 1.0)
	click_area.collision_layer = 4

func _process(_delta: float) -> void:
	if not doors_open or auto_close_distance <= 0.0 or (door_tween and door_tween.is_running()):
		return
	var viewer := _opener if is_instance_valid(_opener) else get_tree().get_first_node_in_group("player") as Node3D
	if viewer == null:
		viewer = get_viewport().get_camera_3d()
	if viewer == null:
		return
	var offset := viewer.global_position - global_position
	if Vector2(offset.x, offset.z).length() > _close_beyond:
		_set_doors_open(false)

func can_interact() -> bool:
	return true

func interact(player: Node3D) -> void:
	if doors_open:
		_set_doors_open(false)
		return
	_opener = player
	var offset := player.global_position - global_position
	_close_beyond = maxf(auto_close_distance, Vector2(offset.x, offset.z).length() + 0.5)
	_set_doors_open(true)

func _set_doors_open(open: bool) -> void:
	doors_open = open
	# Let the player target objects on the shelves while the cabinet is open.
	click_area.collision_layer = 0 if open else 4
	if open:
		interior_light.visible = true
		lower_shelf_light.visible = true
	if door_tween and door_tween.is_running():
		door_tween.kill()
	door_tween = create_tween()
	door_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if open:
		door_tween.set_parallel(true)
		door_tween.tween_property(door_left, "rotation:y", -1.7, 0.25)
		door_tween.tween_property(door_right, "rotation:y", 1.7, 0.25)
		door_tween.chain().tween_property(door_left, "rotation:y", -1.5, 0.25)
		door_tween.parallel().tween_property(door_right, "rotation:y", 1.5, 0.25)
	else:
		door_tween.set_parallel(true)
		door_tween.tween_property(door_left, "rotation:y", 0.0, 0.5)
		door_tween.tween_property(door_right, "rotation:y", 0.0, 0.5)
		door_tween.finished.connect(_turn_off_lights_after_close)
	if handle_tween and handle_tween.is_running():
		handle_tween.kill()
	handle_tween = create_tween().set_parallel(true)
	handle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	handle_tween.tween_property(handle_left, "rotation:z", deg_to_rad(90.0), 0.25)
	handle_tween.tween_property(handle_right, "rotation:z", deg_to_rad(90.0), 0.25)
	handle_tween.chain().tween_property(handle_left, "rotation:z", 0.0, 0.25)
	handle_tween.parallel().tween_property(handle_right, "rotation:z", 0.0, 0.25)

func _turn_off_lights_after_close() -> void:
	if doors_open:
		return
	interior_light.visible = false
	lower_shelf_light.visible = false
