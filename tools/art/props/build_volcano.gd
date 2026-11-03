extends SceneTree
## Builds the hollow "volcano" crater of wet soil (scenes/props/volcano.tscn): a mound with a ring-shaped rim and a
## funnel going 3.5 m down through the floor, and the same shape upside down in the ceiling, a shaft going up.
## A surface of revolution (a profile turned around the axis) with noise on the radius and the height, so it is not
## a clean cone; the inner funnel is wetter (vertex alpha, scripts/wet_soil.gdshader). Low poly like the ground
## patches. The floor and ceiling around it get their hole from scripts/volcano.gd.
## Usage: Godot --headless --path . -s tools/props/build_volcano.gd   (re-running overwrites; change SEED)

const SEED := 913
const MESH_DIR := "res://art/models/ground/"
const SCENE := "res://cultic/scenes/props/volcano.tscn"
const MATERIAL := "res://art/materials/ground/wet_soil_volcano.tres"
const SEGMENTS := 28

## The profile from the outside in: [radius, height, wetness]. The skirt starts under the floor so the mound grows
## out of it, the rim stands about 1.1 m up, the funnel ends in a closed bottom 3.6 m down.
const PROFILE := [
	[3.4, -0.35, 0.0], [2.9, -0.02, 0.0], [2.45, 0.32, 0.05], [2.1, 0.66, 0.1], [1.82, 0.96, 0.15],
	[1.66, 1.1, 0.2], [1.52, 1.06, 0.3], [1.42, 0.78, 0.45], [1.33, 0.34, 0.6], [1.2, -0.35, 0.7],
	[1.04, -1.2, 0.8], [0.9, -2.15, 0.9], [0.8, -3.0, 1.0], [0.74, -3.6, 1.0],
]

var noise := FastNoiseLite.new()


func _init() -> void:
	noise.seed = SEED
	noise.frequency = 0.9
	noise.fractal_octaves = 2
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	var material := (load("res://art/materials/ground/wet_soil.tres") as ShaderMaterial).duplicate()
	material.set_shader_parameter("ignore_hole", true)      # the volcano itself is not cut by its own hole
	ResourceSaver.save(material, MATERIAL)
	material = load(MATERIAL)
	var floor_mesh := _crater(false, material)
	var ceiling_mesh := _crater(true, material)
	ResourceSaver.save(floor_mesh, MESH_DIR + "volcano_floor.res")
	ResourceSaver.save(ceiling_mesh, MESH_DIR + "volcano_ceiling.res")
	print("volcano: %d + %d triangles" % [_tris(floor_mesh), _tris(ceiling_mesh)])
	quit()


## upside_down: the ceiling version, mirrored in height (the rim hangs down, the shaft goes up).
func _crater(upside_down: bool, material: Material) -> ArrayMesh:
	var flip := -1.0 if upside_down else 1.0
	var rows := []            # rows[ring] = [Vector3 per segment + 1 (UV seam)]
	var along := 0.0          # distance along the profile, metres: the V of the UVs
	var last := Vector2.ZERO
	for ring in PROFILE.size():
		var p: Array = PROFILE[ring]
		if ring > 0:
			along += Vector2(p[0], p[1]).distance_to(last)
		last = Vector2(p[0], p[1])
		var row := []
		for s in SEGMENTS + 1:
			var a := TAU * float(s % SEGMENTS) / SEGMENTS
			var n := noise.get_noise_2d(cos(a) * 2.0 + ring * 0.37, sin(a) * 2.0)
			var r: float = p[0] * (1.0 + 0.1 * n)
			var h: float = p[1] + 0.12 * noise.get_noise_2d(cos(a) * 3.0 - ring, sin(a) * 3.0 + ring)
			var wet: float = clampf(p[2] + 0.15 * n, 0.0, 1.0)
			row.append([Vector3(cos(a) * r, h * flip, sin(a) * r), Vector2(a * 2.0, along), wet])
		rows.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in rows.size() - 1:
		for s in SEGMENTS:
			var q := [rows[ring][s], rows[ring][s + 1], rows[ring + 1][s + 1], rows[ring + 1][s]]
			_tri(st, q[0], q[1], q[2], upside_down)
			_tri(st, q[0], q[2], q[3], upside_down)
	# closed bottom (top for the ceiling) of the funnel
	var end: Array = rows[rows.size() - 1]
	var centre := Vector3(0, PROFILE[PROFILE.size() - 1][1] * flip, 0)
	var mid := [centre, Vector2(0, along + 0.7), 1.0]
	for s in SEGMENTS:
		_tri(st, end[s], end[s + 1], mid, upside_down)
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	return mesh


## Wound so the face looks up and out on the slope, in towards the axis in the funnel (both open sides).
func _tri(st: SurfaceTool, a: Array, b: Array, c: Array, upside_down: bool) -> void:
	for v in ([a, c, b] if upside_down else [a, b, c]):
		st.set_color(Color(1, 1, 1, v[2]))
		st.set_uv(v[1])
		st.add_vertex(v[0])


func _tris(mesh: ArrayMesh) -> int:
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] else (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
