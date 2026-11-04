extends SceneTree
## Bakes the level's navigation mesh from the static collision of the studio and basement, placed where
## world/level/level.tscn puts them, and saves it into world/level/level_navmesh.tres (which also holds the
## bake settings). The studio builds its collision on start (world/studio/studio_collision.gd).
## Doors are left out (AnimatableBody3D), so doorways stay walkable whether open or shut.
## Re-run after changing level geometry:
##   Godot --headless --path . --script res://tools/bake_level_navigation.gd

const NAVMESH_PATH: String = "res://world/level/level_navmesh.tres"
const LEVEL: String = "res://world/level/level.tscn"
const PARTS: Array[StringName] = [&"Studio", &"Basement"]
const GROUP: StringName = &"navigation_source"


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var state: SceneState = (load(LEVEL) as PackedScene).get_state()
	for i: int in state.get_node_count():
		if not state.get_node_name(i) in PARTS or state.get_node_instance(i) == null:
			continue
		var part: Node3D = state.get_node_instance(i).instantiate()
		for p: int in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"transform":
				part.transform = state.get_node_property_value(i, p)
		holder.add_child(part)
	for node in holder.find_children("*", "CSGShape3D", true, false):
		var shape: CSGShape3D = node
		if shape.use_collision and shape.is_root_shape():
			shape.add_to_group(GROUP)
	for node in holder.find_children("*", "StaticBody3D", true, false):
		if not node is AnimatableBody3D:
			node.add_to_group(GROUP)
	# CSG builds its shapes deferred.
	await process_frame
	await physics_frame

	var navmesh: NavigationMesh = load(NAVMESH_PATH)
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	navmesh.geometry_source_group_name = GROUP
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.navigation_mesh = navmesh
	holder.add_child(region)
	region.bake_navigation_mesh(false)
	var error: Error = ResourceSaver.save(navmesh, NAVMESH_PATH)
	print("Baked %d polygons into %s: %s" % [navmesh.get_polygon_count(), NAVMESH_PATH, error_string(error)])
	quit()
