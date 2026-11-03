extends Node3D
## Moves the player between the floor above and the green basement through a black screen, and shows only the level
## the player is on: everything inside `basement_box` is the basement, the rest is upstairs. While the player is in
## one level, every mesh, light, fog volume and particle system of the other one is hidden (they cost frame time even
## where they cannot be seen, e.g. the sun's shadows).
## Going down: LMB on the open hatch (sliding_hatch.gd calls go_down()). Going up: LMB on the basement exit, an
## invisible click target (layer 3) in the green doorway, which is part of this node.

@export var basement_box := AABB(Vector3(24.0, -6.0, -32.0), Vector3(22.0, 19.0, 28.5))   # world space
@export var down_position := Vector3(34.5, 0.1, -11.3)    # where the player lands in the basement
@export var down_yaw_degrees := 0.0                        # 0 = looking along -Z (into the green room)
@export var up_position := Vector3(6.35, 0.1, 6.9)         # where the player lands upstairs, next to the hatch
@export var up_yaw_degrees := 0.0
@export var exit_position := Vector3(34.55, 1.2, -9.6)     # the click target in the basement doorway
@export var exit_size := Vector3(1.6, 2.4, 0.4)
@export var fade_time := 3.0                               # the whole black-out, seconds: fade out, black, fade in
## Never hidden: they follow the camera or are the player.
@export var keep: PackedStringArray = ["Player", "RetroPost", "Weather", "SkySphere"]

@export_range(0.25, 1.0, 0.025) var basement_render_scale := 0.375
var upstairs_render_scale := 1.0

var in_basement := false              # the level shown now (the sky checks it: no lightning down there)
var _basement: Array[Node3D] = []
var _upstairs: Array[Node3D] = []
var _hidden: Array[Node3D] = []         # what this node hid, so only that is shown again
var _black: ColorRect
var _busy := false


func _ready() -> void:
	add_to_group("level_switch")
	var target := StaticBody3D.new()
	target.set_meta("outline_contour", preload("res://art/models/ground/basement_exit_reveal.res"))
	target.collision_layer = 4             # LMB sees it, the player walks through it
	target.collision_mask = 0
	target.top_level = true
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = exit_size
	target.add_child(shape)
	add_child(target)
	target.global_position = exit_position

	var layer := CanvasLayer.new()
	layer.layer = 100
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.modulate.a = 0.0
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_black)
	add_child(layer)

	# a few frames later: lamps, fireflies, dust and the like build their parts on start
	for i in 3:
		await get_tree().process_frame
	upstairs_render_scale = get_viewport().scaling_3d_scale
	_sort()
	var player := _player()
	if player:
		_show(basement_box.has_point(player.global_position))


## LMB on the basement exit.
func can_interact() -> bool:
	return in_basement and not _busy

func suppress_interaction_outline() -> bool:
	return true

func interact(player: Node3D) -> void:
	go_up(player)


func go_down(player: Node3D) -> void:
	_travel(player, true)


func go_up(player: Node3D) -> void:
	_travel(player, false)


func _travel(player: Node3D, down: bool) -> void:
	if _busy or player == null:
		return
	_busy = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var edge := fade_time * 0.2
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", 1.0, edge)
	await tween.finished
	var yaw := deg_to_rad(down_yaw_degrees if down else up_yaw_degrees)
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), down_position if down else up_position)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	var head := player.get_node_or_null("Head") as Node3D
	if head:
		head.rotation.x = 0.0                # looking straight ahead, not at the floor or the ceiling
	var hand := player.get_node_or_null("Head/Camera3D/PlayerHand")
	if is_instance_valid(hand) and hand.has_method("snap_to_camera"):
		hand.call("snap_to_camera")
	for hatch in get_tree().get_nodes_in_group("hatch"):
		hatch.close_now()                  # the way down is shut behind you, and closed when you come back up
	_show(down)
	await get_tree().create_timer(fade_time - edge * 2.0).timeout
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	tween = create_tween()
	tween.tween_property(_black, "modulate:a", 0.0, edge)
	await tween.finished
	_busy = false


## Splits every visible thing of the scene into basement and upstairs by where its middle is.
func _sort() -> void:
	var scene := owner if owner else get_parent()
	for node in scene.find_children("*", "VisualInstance3D", true, false):
		if _kept(node, scene):
			continue
		var v := node as VisualInstance3D
		var centre := v.global_position
		if not (v is Light3D):
			centre = (v.global_transform * v.get_aabb()).get_center()
		if v is DirectionalLight3D or not basement_box.has_point(centre):
			_upstairs.append(v)
		else:
			_basement.append(v)


func _kept(node: Node, scene: Node) -> bool:
	if node == self or is_ancestor_of(node):
		return true
	var n := node
	while n and n != scene:
		if String(n.name) in keep:
			return true
		n = n.get_parent()
	return false


## Shows the level the player is on and hides the other one.
func _show(basement: bool) -> void:
	get_viewport().scaling_3d_scale = minf(upstairs_render_scale, basement_render_scale) if basement else upstairs_render_scale
	in_basement = basement
	for node in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()
	for node in (_upstairs if basement else _basement):
		if is_instance_valid(node) and node.visible:
			node.visible = false
			_hidden.append(node)


func _player() -> Node3D:
	var scene := owner if owner else get_parent()
	return scene.get_node_or_null("Player") as Node3D
