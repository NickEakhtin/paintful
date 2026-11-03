extends Node3D
## Small wall cabinet with two doors, lit inside. Opens through its Interactable; while open the Interactable is off,
## so the player can reach what lies on the shelves, and the doors close once the player walks away.

@export var auto_close_distance: float = 2.5

var door_tween: Tween
var handle_tween: Tween
var doors_open: bool = false
var _opener: Node3D
var _close_beyond: float = 0.0
@onready var door_left: Node3D = $LeftDoorHinge
@onready var door_right: Node3D = $RightDoorHinge
@onready var handle_left: Node3D = $LeftDoorHinge/GoldHandle
@onready var handle_right: Node3D = $RightDoorHinge/GoldHandle
@onready var interior_light: OmniLight3D = $InteriorLight
@onready var lower_shelf_light: OmniLight3D = $LowerShelfLight
@onready var click_area: Interactable = $Interactable
@onready var _click_shape: CollisionShape3D = $Interactable/CollisionShape3D

func _ready() -> void:
	click_area.set_meta("outline_front_sign", 1.0)
	click_area.interacted.connect(_on_interacted)

func _process(_delta: float) -> void:
	if not doors_open or auto_close_distance <= 0.0 or (door_tween and door_tween.is_running()):
		return
	var viewer: Node3D = _opener if is_instance_valid(_opener) else get_tree().get_first_node_in_group("player") as Node3D
	if viewer == null:
		viewer = get_viewport().get_camera_3d()
	if viewer == null:
		return
	var offset: Vector3 = viewer.global_position - global_position
	if Vector2(offset.x, offset.z).length() > _close_beyond:
		_set_doors_open(false)

func _on_interacted(player: Player) -> void:
	if doors_open:
		_set_doors_open(false)
		return
	_opener = player
	var offset: Vector3 = player.global_position - global_position
	_close_beyond = maxf(auto_close_distance, Vector2(offset.x, offset.z).length() + 0.5)
	_set_doors_open(true)

func _set_doors_open(open: bool) -> void:
	doors_open = open
	# Let the player target objects on the shelves while the cabinet is open; it closes once they walk off.
	_click_shape.set_deferred("disabled", open)
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
