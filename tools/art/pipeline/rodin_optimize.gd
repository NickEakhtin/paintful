# Heavy Rodin model (base_basic_pbr.glb, many parts sharing one texture set) -> light game prop, using only Godot:
# merges all parts into one mesh (one draw call), simplifies it with Godot's own LOD generator (meshoptimizer) down
# to about `triangles`, drops the unused vertices, bakes the real size into the vertices (Scale 1 in Godot), sets
# the pivot at the centre of the base, shrinks the textures and, if given, adds Rodin's separate emission map
# (texture_emissive_*.png) so the glowing parts glow (its grey and white specks dropped, only coloured glow kept). Writes a compact .glb (JPEG textures).
# Usage: Godot --headless --path . --script tools/pipeline/rodin_optimize.gd -- in.glb out.glb Name height triangles [emissive.png] [emission_energy] [texture_px] [matte]
#   matte    stone and the like: Rodin sometimes paints them metallic, which gives sparkly white highlights under a
#            close light; this drops the metal map and keeps only a weak sheen
extends SceneTree


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 5:
		push_error("usage: in.glb out.glb Name height triangles [emissive.png] [emission_energy] [texture_px]")
		quit(1)
		return
	var height := float(a[3])
	var target := int(a[4])
	var emissive_path := a[5] if a.size() > 5 else ""
	var energy := float(a[6]) if a.size() > 6 else 3.0
	var tex_px := int(a[7]) if a.size() > 7 else 1024
	var matte := a.size() > 8 and a[8] == "matte"

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(a[0], state) != OK:
		push_error("cannot read " + a[0])
		quit(1)
		return
	var source := doc.generate_scene(state)

	# 1) every part in model space, appended into one surface
	var verts := PackedVector3Array(); var normals := PackedVector3Array(); var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array(); var indices := PackedInt32Array()
	var material: BaseMaterial3D
	var source_tris := 0
	for m: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var n: Node = m
		while n != source:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var base := verts.size()
			for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				verts.append(xf * v)
			for v: Vector3 in arr[Mesh.ARRAY_NORMAL]:
				normals.append((xf.basis * v).normalized())
			var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			if t.is_empty():
				t.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 4)
			for i in range(0, t.size(), 4):
				var d := (xf.basis * Vector3(t[i], t[i + 1], t[i + 2])).normalized()
				tangents.append_array([d.x, d.y, d.z, t[i + 3]])
			uvs.append_array(arr[Mesh.ARRAY_TEX_UV])
			for i: int in arr[Mesh.ARRAY_INDEX]:
				indices.append(base + i)
			source_tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			if material == null:
				material = m.mesh.surface_get_material(s)

	# 2) simplify: Godot builds a chain of ever coarser index lists; take the first one at or under the target
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts; arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(60.0, 25.0, [])
	var best := indices
	for lod in importer.get_surface_lod_count(0):
		var lod_indices := importer.get_surface_lod_indices(0, lod)
		best = lod_indices
		if lod_indices.size() / 3 <= target:
			break

	# 3) keep only the vertices still used, real size, pivot at the centre of the base
	var bounds := AABB(verts[best[0]], Vector3.ZERO)
	for i in best:
		bounds = bounds.expand(verts[i])
	var k := height / bounds.size.y
	var origin := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var remap := {}
	var v2 := PackedVector3Array(); var n2 := PackedVector3Array(); var t2 := PackedFloat32Array()
	var uv2 := PackedVector2Array(); var i2 := PackedInt32Array()
	for i in best:
		if not remap.has(i):
			remap[i] = v2.size()
			v2.append((verts[i] - origin) * k); n2.append(normals[i]); uv2.append(uvs[i])
			t2.append_array([tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2], tangents[i * 4 + 3]])
		i2.append(remap[i])
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = v2; out_arrays[Mesh.ARRAY_NORMAL] = n2
	out_arrays[Mesh.ARRAY_TANGENT] = t2; out_arrays[Mesh.ARRAY_TEX_UV] = uv2; out_arrays[Mesh.ARRAY_INDEX] = i2

	# 4) one material: the shared textures, smaller; emission from the separate map
	for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_NORMAL]:
		var tex: Texture2D = material.get_texture(slot)
		if tex and tex.get_width() > tex_px:
			var img := tex.get_image()
			img.resize(tex_px, tex_px * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
			material.set_texture(slot, ImageTexture.create_from_image(img))
	if emissive_path != "":
		var em := Image.load_from_file(emissive_path)
		em.resize(tex_px, tex_px * em.get_height() / em.get_width(), Image.INTERPOLATE_LANCZOS)
		# Rodin's emission maps also light up grey/white specks on edges and chips; only coloured glow is wanted
		em.convert(Image.FORMAT_RGB8)
		for y in em.get_height():
			for x in em.get_width():
				var c := em.get_pixel(x, y)
				em.set_pixel(x, y, c * smoothstep(0.35, 0.6, c.s))
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_texture = ImageTexture.create_from_image(em)
		material.emission_energy_multiplier = energy
	if matte:
		material.metallic = 0.0
		material.metallic_texture = null
		material.metallic_specular = 0.2
	material.cull_mode = BaseMaterial3D.CULL_BACK

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	mesh.surface_set_material(0, material)
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
	print("%s: %s, %d -> %d triangles, %d vertices, %.2f x %.2f x %.2f m -> %s" % [a[2], error_string(err), source_tris, i2.size() / 3, v2.size(), size.x, size.y, size.z, a[1]])
	quit()
