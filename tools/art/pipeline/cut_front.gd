# Keeps only the front slice of a model: triangles lying entirely within `fraction` of the depth from the front (+Z) edge.
# For Rodin results that came out as a closed box (e.g. a fence segment turned into an enclosure).
# Usage: Godot --headless --path . --script tools/pipeline/cut_front.gd -- in.glb out.glb fraction (0..1)
#   then run rodin_to_godot.gd on out.glb for the pivot / real size.
extends SceneTree


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var fraction := float(a[2])
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(a[0], state) != OK:
		push_error("cannot read " + a[0])
		quit(1)
		return
	var source := doc.generate_scene(state)
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	var zmin := INF; var zmax := -INF
	for m: MeshInstance3D in meshes:
		zmin = min(zmin, m.get_aabb().position.z); zmax = max(zmax, m.get_aabb().end.z)

	for m: MeshInstance3D in meshes:
		var out := ArrayMesh.new()
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var kept := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var z: float = min(verts[idx[t]].z, verts[idx[t + 1]].z, verts[idx[t + 2]].z)
				if z > zmax - fraction * (zmax - zmin):
					kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
			arrays[Mesh.ARRAY_INDEX] = kept
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(s, m.mesh.surface_get_material(s))
		m.mesh = out

	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	out_doc.append_from_scene(source, out_state)
	print("cut_front: ", error_string(out_doc.write_to_filesystem(out_state, a[1])), " -> ", a[1])
	quit()
