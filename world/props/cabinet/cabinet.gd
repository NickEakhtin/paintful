extends Node3D
## Furniture with hinged doors and sliding drawers (glass cabinet, station cart): swings door_left / door_right on
## their hinges (node origins) and slides the drawers listed in `drawer_names` along +Z.
## The player opens them through Interactables built on start over the doors (one for both) and over each drawer
## (it moves with the drawer); code can call toggle_doors() / toggle_drawer("drawer_left"); `demo` cycles them for
## the showcase scene.
## Open doors and drawers close by themselves once the player walks farther than `auto_close_distance` from them
## (horizontal distance; the player is the first node in the "player" group, otherwise the active camera); opened
## from farther away, they close only once the player walks off from there.

@export var door_open_angle: float = 110.0
@export var drawer_travel: float = 0.3
@export var duration: float = 0.6
@export var demo: bool = false
@export var drawer_names: PackedStringArray = ["drawer_left", "drawer_right"]
## Metres; 0 turns auto-closing off. Not applied while `demo` is on.
@export var auto_close_distance: float = 1.0

var doors_open: bool = false
var _drawer_open: Dictionary = {}
var _drawer_rest: Dictionary = {}
var _close_beyond: float = 0.0
var _doors_interactable: Interactable
var _drawer_interactables: Dictionary = {}
@onready var _door_left: Node3D = find_child("door_left", true, false) as Node3D
@onready var _door_right: Node3D = find_child("door_right", true, false) as Node3D


func _ready() -> void:
	for drawer_name in drawer_names:
		var drawer: Node3D = find_child(drawer_name, true, false) as Node3D
		if drawer:
			_drawer_rest[drawer_name] = drawer.position.z
			var drawer_interactable: Interactable = _make_interactable(drawer, [drawer], "Выдвинуть ящик")
			drawer_interactable.interacted.connect(func(player: Player) -> void:
				_note_opener(player)
				toggle_drawer(drawer_name))
			_drawer_interactables[drawer_name] = drawer_interactable
	var doors: Array[Node3D] = []
	for door: Node3D in [_door_left, _door_right]:
		if door:
			doors.append(door)
	if not doors.is_empty():
		_doors_interactable = _make_interactable(self, doors, "Открыть")
		_doors_interactable.interacted.connect(func(player: Player) -> void:
			_note_opener(player)
			toggle_doors())
	if demo:
		_demo_loop()


func _process(_delta: float) -> void:
	if demo or auto_close_distance <= 0.0 or not is_anything_open():
		return
	var viewer: Node3D = _find_viewer()
	if viewer and _horizontal_distance_to(viewer.global_position) > maxf(auto_close_distance, _close_beyond):
		close_all()


func is_anything_open() -> bool:
	return doors_open or _drawer_open.values().has(true)


func close_all() -> void:
	if doors_open:
		set_doors_open(false)
	for drawer_name in _drawer_open.keys():
		if _drawer_open[drawer_name]:
			toggle_drawer(drawer_name)


func _find_viewer() -> Node3D:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player:
		return player
	return get_viewport().get_camera_3d()


func _horizontal_distance_to(point: Vector3) -> float:
	# nearest of the moving parts (door hinges, drawers) and the middle of the front between the hinges
	var anchors: Array[Vector3] = []
	for part in [_door_left, _door_right]:
		if part:
			anchors.append(part.global_position)
	if anchors.size() == 2:
		anchors.append((anchors[0] + anchors[1]) * 0.5)
	for drawer_name in _drawer_rest.keys():
		var drawer: Node3D = find_child(drawer_name, true, false) as Node3D
		if drawer:
			anchors.append(drawer.global_position)
	if anchors.is_empty():
		anchors.append(global_position)
	var best: float = INF
	for anchor in anchors:
		best = minf(best, Vector2(point.x - anchor.x, point.z - anchor.z).length())
	return best


## An Interactable under `parent` whose box covers the meshes of `parts` (in this node's space when they turn).
func _make_interactable(parent: Node3D, parts: Array[Node3D], text: String) -> Interactable:
	var bounds: AABB = AABB()
	var first: bool = true
	var to_parent: Transform3D = parent.global_transform.affine_inverse()
	for part: Node3D in parts:
		var meshes: Array[Node] = part.find_children("*", "MeshInstance3D", true, false)
		if part is MeshInstance3D:
			meshes.append(part)
		for mesh: MeshInstance3D in meshes:
			var box: AABB = (to_parent * mesh.global_transform) * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	var interactable: Interactable = Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt = text
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = bounds.size + Vector3.ONE * 0.02
	shape.shape = box_shape
	shape.position = bounds.get_center()
	interactable.add_child(shape)
	parent.add_child(interactable)
	return interactable


func _note_opener(player: Player) -> void:
	if not is_anything_open():
		_close_beyond = _horizontal_distance_to(player.global_position) + 0.5


func toggle_doors() -> void:
	set_doors_open(not doors_open)


func set_doors_open(open: bool) -> void:
	doors_open = open
	if _doors_interactable:
		_doors_interactable.prompt = "Закрыть" if open else "Открыть"
	var angle: float = deg_to_rad(door_open_angle) if open else 0.0
	var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# hinges are the node origins: the left door swings out with a negative turn, the right one with a positive one
	if _door_left:
		tween.tween_property(_door_left, "rotation:y", -angle, duration)
	if _door_right:
		tween.tween_property(_door_right, "rotation:y", angle, duration)


func toggle_drawer(drawer_name: String = "") -> void:
	if drawer_name.is_empty() and not drawer_names.is_empty():
		drawer_name = drawer_names[0]
	var drawer: Node3D = find_child(drawer_name, true, false) as Node3D
	if drawer == null or not _drawer_rest.has(drawer_name):
		return
	var open: bool = not _drawer_open.get(drawer_name, false)
	_drawer_open[drawer_name] = open
	if _drawer_interactables.has(drawer_name):
		(_drawer_interactables[drawer_name] as Interactable).prompt = "Задвинуть ящик" if open else "Выдвинуть ящик"
	var target: float = _drawer_rest[drawer_name] + (drawer_travel if open else 0.0)
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).tween_property(drawer, "position:z", target, duration)


func _demo_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(2.0).timeout
		toggle_doors()
		toggle_drawer()
