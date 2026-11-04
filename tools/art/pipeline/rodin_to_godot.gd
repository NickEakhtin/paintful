# Rodin model (base_basic_pbr.glb) -> game prop, using only Godot (no python / node needed): turns it to face +Z,
# bakes the real size into the vertices (Scale 1 in Godot), sets the pivot, shrinks the textures and writes a
# compact .glb (JPEG textures).
# Usage: Godot --headless --path . --script tools/pipeline/rodin_to_godot.gd -- in.glb out.glb Name height pivot [turn_deg] [texture_px]
#   height   real height in metres
#   pivot    floor        centre of the base
#            wall         bottom centre of the back (hangs on a wall, faces +Z)
#            hinge_left / hinge_right   bottom of that vertical edge (seen from the front), middle of the thickness
#   turn_deg rotation about Y applied first, to make the front face +Z (default 0)
extends SceneTree


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 5:
		push_error("usage: in.glb out.glb Name height pivot [turn_deg] [texture_px]")
		quit(1)
		return
	var height := float(a[3])
	var pivot := a[4]
	var turn := deg_to_rad(float(a[5])) if a.size() > 5 else 0.0
	var tex_px := int(a[6]) if a.size() > 6 else 1024

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(a[0], state) != OK:
		push_error("cannot read " + a[0])
		quit(1)
		return
	var source := doc.generate_scene(state)

	# every surface in model space, turned to face +Z
	var surfaces := []   # [arrays, material]
	var bounds := AABB(); var first := true
	for m: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO)
		var chain := Transform3D()
		var n: Node = m
		while n != source:
			chain = (n as Node3D).transform * chain
			n = n.get_parent()
		xf = xf * chain
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] = xf * verts[i]
				bounds = AABB(verts[i], Vector3.ZERO) if first else bounds.expand(verts[i])
				first = false
			arrays[Mesh.ARRAY_VERTEX] = verts
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in normals.size():
					normals[i] = (xf.basis * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			if arrays[Mesh.ARRAY_TANGENT] != null:
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				for i in range(0, tangents.size(), 4):
					var t := (xf.basis * Vector3(tangents[i], tangents[i + 1], tangents[i + 2])).normalized()
					tangents[i] = t.x; tangents[i + 1] = t.y; tangents[i + 2] = t.z
				arrays[Mesh.ARRAY_TANGENT] = tangents
			surfaces.append([arrays, m.mesh.surface_get_material(s)])

	var k := height / bounds.size.y
	var origin := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	match pivot:
		"wall": origin.z = bounds.position.z
		"hinge_left": origin.x = bounds.position.x
		"hinge_right": origin.x = bounds.end.x

	var mesh := ArrayMesh.new()
	var shrunk := {}
	for entry in surfaces:
		var arrays: Array = entry[0]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = (verts[i] - origin) * k
		arrays[Mesh.ARRAY_VERTEX] = verts
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat = entry[1]
		if mat is BaseMaterial3D:
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_NORMAL]:
				var tex: Texture2D = mat.get_texture(slot)
				if tex and tex.get_width() > tex_px:
					if not shrunk.has(tex):
						var img := tex.get_image()
						img.resize(tex_px, tex_px * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
						shrunk[tex] = ImageTexture.create_from_image(img)
					mat.set_texture(slot, shrunk[tex])
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

	var root := Node3D.new()
	root.name = a[2]
	var part := MeshInstance3D.new()
	part.name = a[2].to_snake_case()
	part.mesh = mesh
	root.add_child(part)
	part.owner = root

	var out_doc := GLTFDocument.new()
	out_doc.image_format = "JPEG"
	out_doc.lossy_quality = 0.85
	var out_state := GLTFState.new()
	out_doc.append_from_scene(root, out_state)
	var err := out_doc.write_to_filesystem(out_state, a[1])
	var size := bounds.size * k
	print("%s: %s, %d triangles, %.2f x %.2f x %.2f m, pivot %s -> %s" % [a[2], error_string(err), _triangles(mesh), size.x, size.y, size.z, pivot, a[1]])
	quit()


func _triangles(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n
