@tool
extends Node3D
## The hollow volcano crater (tools/props/build_volcano.gd): a pit in the floor and a shaft in the ceiling above it.
## Cuts the round hole through the ground patches of the floor and ceiling around it (the `hole` parameter of
## scripts/wet_soil.gdshader, set on the ground material), following this node when it is moved. In the game the crater gets
## exact collision and an invisible wall along the rim, so the player cannot fall into the pit.

@export var hole_radius := 1.45:                 # the floor and ceiling vanish inside this, metres from the axis (at scale 1; grows with the node)
	set(v):
		hole_radius = v
		_update_hole()
@export var ceiling_height := 5.75:              # where the ceiling part sits, above this node
	set(v):
		ceiling_height = v
		if is_node_ready():
			$Ceiling.position.y = ceiling_height
@export var rim_wall_radius := 1.75              # the invisible wall, metres from the axis
## The ground materials the hole is cut through (the patches of the floor and ceiling use the first one).
@export var cut_materials: Array[ShaderMaterial] = [preload("res://art/materials/ground/wet_soil.tres")]


func _ready() -> void:
	set_notify_transform(true)
	$Ceiling.position.y = ceiling_height
	_update_hole()
	if Engine.is_editor_hint():
		return
	for mesh: MeshInstance3D in [$Floor, $Ceiling]:
		mesh.create_trimesh_collision()
	var wall := StaticBody3D.new()
	wall.collision_layer = 2  # Blocks the walker, lets the use ray reach the opening.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = rim_wall_radius             # the wall is a child, so it scales with the node already
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.0
	wall.add_child(shape)
	add_child(wall)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_hole()


func _update_hole() -> void:
	if not is_inside_tree():
		return
	for material in cut_materials:
		if material:
			var grow := maxf(global_basis.get_scale().x, global_basis.get_scale().z)
			material.set_shader_parameter("hole", Vector3(global_position.x, global_position.z, hole_radius * grow))
