# Untextured low-poly prop (one colour, flat-shaded, e.g. a procedural mesh) -> smooth game prop: welds the
# duplicated corners, recomputes soft normals (no facets, no light seams between triangles), scales it to a real
# height, puts the pivot at the centre of its base and gives it a glossy material.
# Usage: Godot --headless --path . --script tools/pipeline/smooth_prop.gd -- in.glb out.glb Name height r,g,b roughness
extends SceneTree


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var height := float(a[3])
	var rgb := a[4].split(",")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(a[0], state) != OK:
		push_error("cannot read " + a[0])
		quit(1)
		return
	var source := doc.generate_scene(state)
	var points := PackedVector3Array()
	for m: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index = arrays[Mesh.ARRAY_INDEX]
			if index == null:
				for v in verts: points.append(m.transform * v)
			else:
				for i: int in index: points.append(m.transform * verts[i])
	var bounds := AABB(points[0], Vector3.ZERO)
	for p in points: bounds = bounds.expand(p)
	var k := height / bounds.size.y
	var origin := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for p in points:
		# snap so corners that should meet do meet exactly, then weld
		st.add_vertex(((p - origin) * k).snapped(Vector3.ONE * 0.0001))
	st.index()
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.resource_name = a[2]
	material.albedo_color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	material.roughness = float(a[5])
	material.metallic_specular = 0.7
	st.set_material(material)
	var mesh := st.commit()

	var root := Node3D.new()
	root.name = a[2]
	var part := MeshInstance3D.new()
	part.name = a[2].to_snake_case()
	part.mesh = mesh
	root.add_child(part)
	part.owner = root
	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	out_doc.append_from_scene(root, out_state)
	var err := out_doc.write_to_filesystem(out_state, a[1])
	var size := bounds.size * k
	print("%s: %s, %d triangles, %d vertices (was %d), %.2f x %.2f x %.2f m -> %s" % [a[2], error_string(err),
			points.size() / 3, (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), points.size(),
			size.x, size.y, size.z, a[1]])
	quit()
