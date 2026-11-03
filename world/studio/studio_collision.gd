extends Node
## The colleague's models come without collision, so the studio gets it on start (his rules from his player):
## exact shapes for the shell and the ground outside (walls with door and window holes stay walkable), a box around
## each piece of furniture turned with it, nothing for small props, flat things on the floor, things hung on the
## walls and the names in `skip_names`. Everything lands on the "world" layer, so the navmesh bake sees it too
## (tools/bake_level_navigation.gd adds the level first and waits for this).

## Exact (trimesh) collision for every mesh under these.
@export var exact: Array[Node3D] = []
## A box per mesh under these.
@export var boxes: Array[Node3D] = []
@export var min_prop_size: float = 0.35                     # smaller meshes get no collision
@export var skip_names: PackedStringArray = ["curtain", "rug", "light", "sky", "simplewoodencabinet", "candle", "book", "coin", "inkbottle", "mug"]
@export var floor_cover_height: float = 0.2                 # flat things on the floor lower than this get none
@export var wall_mounted_above: float = 0.6                 # things hanging higher than this off the floor get none


func _ready() -> void:
	for group: Node3D in exact:
		_add(group, false)
	for group: Node3D in boxes:
		_add(group, true)


func _add(group: Node3D, as_boxes: bool) -> void:
	for mesh: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _skipped(mesh, group):
			continue
		if not as_boxes:
			mesh.create_trimesh_collision()
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		var size: Vector3 = bounds.size
		if maxf(size.x, maxf(size.y, size.z)) < min_prop_size:
			continue
		if size.y < floor_cover_height and bounds.end.y < floor_cover_height + 0.1:
			continue                                              # rugs, tile platforms: walked over, not bumped into
		if bounds.position.y > wall_mounted_above:
			continue                                              # shelves, frames, skulls on the walls: the wall stops you
		var body: StaticBody3D = StaticBody3D.new()               # a box is instant; hulls of these models took seconds
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = mesh.get_aabb().size
		shape.shape = box
		shape.position = mesh.get_aabb().get_center()
		body.add_child(shape)
		mesh.add_child(body)


func _skipped(mesh: Node, group: Node) -> bool:
	var n: Node = mesh
	while n != group:
		var lower: String = String(n.name).to_lower()
		for word in skip_names:
			if lower.contains(word):
				return true
		n = n.get_parent()
	return false
