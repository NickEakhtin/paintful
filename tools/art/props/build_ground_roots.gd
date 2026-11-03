extends SceneTree
## Builds low-poly ground patches (scenes/props/ground/) and tree roots (scenes/props/roots/), each under 500 triangles.
## Patches: an irregular disc of rings, with mounds and hollows; the hollows are marked wet (vertex alpha) for
## scripts/wet_soil.gdshader. The rim sinks a little so a patch can lie on any floor. Walkable in the game.
## Roots: tapering six-sided tubes along arched, wobbly curves that come out of the ground and dive back in; bark is
## only a normal map stretched along the root.
## Usage: Godot --headless --path . -s tools/props/build_ground_roots.gd   (re-running overwrites; change SEED)

const SEED := 4242
const GROUND_MESH := "res://art/models/ground/"
const GROUND_SCENE := "res://cultic/scenes/props/ground/"
const ROOT_MESH := "res://art/models/roots/"
const ROOT_SCENE := "res://cultic/scenes/props/roots/"
const MAT_DIR := "res://art/materials/ground/"

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var soil: ShaderMaterial
var bark: StandardMaterial3D


func _init() -> void:
	rng.seed = SEED
	noise.seed = SEED
	noise.frequency = 0.45
	noise.fractal_octaves = 3
	for dir in [GROUND_MESH, GROUND_SCENE, ROOT_MESH, ROOT_SCENE, MAT_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_materials()
	for i in 4:
		var mesh := _patch(i)
		_save(mesh, GROUND_MESH, GROUND_SCENE, "ground_patch_%d" % (i + 1), true)
	_save(_roots_spread(), ROOT_MESH, ROOT_SCENE, "roots_spread", false)
	_save(_root_arch(), ROOT_MESH, ROOT_SCENE, "root_arch", false)
	_save(_root_fork(), ROOT_MESH, ROOT_SCENE, "root_fork", false)
	_save(_roots_tangle(), ROOT_MESH, ROOT_SCENE, "roots_tangle", false)
	quit()


# ---------------------------------------------------------------- materials

func _noise_tex(kind: int, freq: float, octaves: int, normal: bool, bump := 4.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = SEED + kind * 7 + octaves
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	t.as_normal_map = normal
	t.bump_strength = bump
	return t


func _materials() -> void:
	soil = ShaderMaterial.new()
	soil.shader = load("res://cultic/scripts/wet_soil.gdshader")
	soil.set_shader_parameter("pattern", _noise_tex(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 4, false))
	soil.set_shader_parameter("grain", _noise_tex(FastNoiseLite.TYPE_CELLULAR, 0.05, 3, true, 6.0))
	ResourceSaver.save(soil, MAT_DIR + "wet_soil.tres")
	soil = load(MAT_DIR + "wet_soil.tres")

	bark = StandardMaterial3D.new()
	bark.albedo_color = Color(0.085, 0.062, 0.045)
	bark.vertex_color_use_as_albedo = true
	bark.roughness = 0.55                         # damp
	bark.normal_enabled = true
	bark.normal_texture = _noise_tex(FastNoiseLite.TYPE_SIMPLEX, 0.03, 4, true, 8.0)
	bark.normal_scale = 1.3
	bark.uv1_scale = Vector3(3.0, 0.5, 1.0)      # across x along: ridges run along the root
	ResourceSaver.save(bark, MAT_DIR + "root_bark.tres")
	bark = load(MAT_DIR + "root_bark.tres")


# ---------------------------------------------------------------- ground patches

## Rings x segments around the centre: 24 + (rings - 1) * 48 triangles (9 rings = 408).
func _patch(variant: int) -> ArrayMesh:
	var rings := 9
	var segs := 24
	var radius: float = [2.2, 3.0, 2.6, 3.4][variant]
	var a := rng.randf() * TAU
	var b := rng.randf() * TAU
	var stretch := Vector2(rng.randf_range(0.8, 1.25), rng.randf_range(0.8, 1.25))
	# a couple of mounds and hollows, placed inside the patch
	var bumps := []
	for i in rng.randi_range(2, 3):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.0, 0.6) * radius
		bumps.append([Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(0.6, 1.2), rng.randf_range(0.18, 0.35)])
	for i in rng.randi_range(1, 3):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.1, 0.55) * radius
		bumps.append([Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(0.45, 0.9), -rng.randf_range(0.1, 0.16)])
	var off := Vector3(rng.randf() * 50.0, 0, rng.randf() * 50.0)

	var outline := func(t: float) -> float:
		return radius * (1.0 + 0.16 * sin(3.0 * t + a) + 0.08 * sin(5.0 * t + b) + 0.05 * sin(8.0 * t))
	var verts := []          # [ring][seg] -> Vector3, ring 0 = centre
	var heights := []
	for r in rings + 1:
		var row := []
		var hrow := []
		var count := 1 if r == 0 else segs
		for s in count:
			var t := float(s) / segs * TAU
			var f := float(r) / rings
			var rad: float = outline.call(t) * f
			var p := Vector2(cos(t) * rad * stretch.x, sin(t) * rad * stretch.y)
			# a raised bed: up to 0.14 m in the middle, sinking 3 cm below zero at the rim
			var h := lerpf(0.14, -0.03, smoothstep(0.55, 1.0, f))
			var inner := 1.0 - smoothstep(0.7, 1.0, f)
			h += noise.get_noise_2d(p.x + off.x, p.y + off.z) * 0.07 * inner
			for bump in bumps:
				var d: float = (p - bump[0]).length() / bump[1]
				h += bump[2] * exp(-d * d * 2.0) * inner
			h = maxf(h, 0.015 * inner - 0.03 * (1.0 - inner))   # hollows stay above the floor it lies on
			row.append(Vector3(p.x, h, p.y))
			hrow.append(h)
		verts.append(row)
		heights.append(hrow)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index := {}
	var add := func(r: int, s: int) -> int:
		var key := r * 1000 + s
		if index.has(key):
			return index[key]
		var p: Vector3 = verts[r][s]
		# wetness: how far below the local level (the raised bed + noise) the point is
		var f := float(r) / rings
		var bed := lerpf(0.14, -0.03, smoothstep(0.55, 1.0, f))
		var wet := clampf((bed - p.y) / 0.1, 0.0, 1.0) * (1.0 - smoothstep(0.75, 1.0, f))
		var tone := 0.9 + noise.get_noise_2d(p.x * 3.0 - 20.0, p.z * 3.0) * 0.12
		st.set_color(Color(tone, tone, tone, wet))
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)
		index[key] = index.size()
		return index[key]
	var tri := func(i0: int, i1: int, i2: int) -> void:
		st.add_index(i0)
		st.add_index(i1)                # wound so the top faces up (Godot: clockwise = front)
		st.add_index(i2)
	for s in segs:
		var s1 := (s + 1) % segs
		tri.call(add.call(0, 0), add.call(1, s), add.call(1, s1))
	for r in range(1, rings):
		for s in segs:
			var s1 := (s + 1) % segs
			var i00: int = add.call(r, s)
			var i01: int = add.call(r, s1)
			var i10: int = add.call(r + 1, s)
			var i11: int = add.call(r + 1, s1)
			tri.call(i00, i10, i11)
			tri.call(i00, i11, i01)
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, soil)
	return mesh


# ---------------------------------------------------------------- roots

## A tube along `points` with radius from r0 to r1, `sides` around. No end caps: both ends are underground.
func _tube(st: SurfaceTool, points: Array, r0: float, r1: float, sides: int) -> void:
	var n := points.size()
	var tangent: Vector3 = (points[1] - points[0]).normalized()
	var normal := tangent.cross(Vector3.UP).normalized()
	if normal.length() < 0.1:
		normal = Vector3.RIGHT
	var length := 0.0
	var rings := []
	var tone := rng.randf_range(0.85, 1.1)
	for i in n:
		var p: Vector3 = points[i]
		if i > 0:
			length += p.distance_to(points[i - 1])
		var t_next: Vector3 = (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		# parallel transport: keep the ring from twisting
		var axis := tangent.cross(t_next)
		if axis.length() > 0.0001:
			normal = normal.rotated(axis.normalized(), tangent.angle_to(t_next))
		tangent = t_next
		var binormal := tangent.cross(normal).normalized()
		var f := float(i) / (n - 1)
		var r := lerpf(r0, r1, f) * (1.0 + 0.12 * sin(f * 17.0 + r0 * 40.0))   # knobbly
		var ring := []
		for k in sides + 1:                                       # +1: the UV seam
			var ang := float(k) / sides * TAU
			var dir := normal * cos(ang) + binormal * sin(ang)
			# a bit flattened: roots spread sideways more than up
			var pos := p + normal * cos(ang) * r * 1.15 + binormal * sin(ang) * r * 0.85
			ring.append([pos, dir, Vector2(float(k) / sides, length)])
		rings.append(ring)
	var base := st_vertex_count
	for ring in rings:
		for v in ring:
			st.set_color(Color(tone, tone, tone))
			st.set_normal(v[1])
			st.set_uv(v[2])
			st.add_vertex(v[0])
	for i in n - 1:
		for k in sides:
			var a := base + i * (sides + 1) + k
			var b := a + 1
			var c := a + sides + 1
			var d := c + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	st_vertex_count += (sides + 1) * n
	_root_tris += sides * 2 * (n - 1)

var st_vertex_count := 0
var _root_tris := 0


## An arched path from `start` along `dir` (horizontal), `length` long, arching `height` above the line from the
## start down to 12 cm underground at the far end, wobbling sideways. Main roots start underground, side roots
## start on their parent and dive into the ground too. Returns the points.
func _root_path(start: Vector3, dir: Vector3, length: float, height: float, segs: int, wobble := 0.12) -> Array:
	dir = Vector3(dir.x, 0, dir.z).normalized()
	var side := dir.cross(Vector3.UP)
	var seed_x := rng.randf() * 100.0
	var pts := []
	for i in segs + 1:
		var f := float(i) / segs
		# rises fast near the trunk end, long low tail, dips under at the far end
		var base_y := lerpf(start.y, -0.12, smoothstep(0.0, 1.0, f))
		var y := base_y + height * sin(PI * pow(f, 0.7))
		var lateral := noise.get_noise_1d(seed_x + f * 4.0) * wobble * length * f
		var p := start + dir * length * f + side * lateral
		p.y = y
		pts.append(p)
	return pts


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_vertex_count = 0
	_root_tris = 0
	return st


func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, bark)
	return mesh


## Roots fanning out from one spot (where a trunk once stood): 4 roots x 96 = 384 triangles.
func _roots_spread() -> ArrayMesh:
	var st := _begin()
	var start_ang := rng.randf() * TAU
	for i in 4:
		var ang := start_ang + i * TAU / 4.0 + rng.randf_range(-0.35, 0.35)
		var dir := Vector3(cos(ang), 0, sin(ang))
		_tube(st, _root_path(dir * 0.12 + Vector3(0, -0.06, 0), dir, rng.randf_range(1.0, 1.6), rng.randf_range(0.18, 0.3), 8), rng.randf_range(0.1, 0.14), 0.03, 6)
	return _finish(st)


## One long thick root arching out of the ground, with a side shoot: 7 x 12 x 2 + 6 x 8 x 2 = 264 triangles.
func _root_arch() -> ArrayMesh:
	var st := _begin()
	var main := _root_path(Vector3(-1.2, -0.06, 0), Vector3.RIGHT, 2.6, 0.38, 12, 0.08)
	_tube(st, main, 0.15, 0.05, 7)
	var from: Vector3 = main[4]
	_tube(st, _root_path(from - Vector3(0, 0.04, 0), Vector3(0.4, 0, 1), 0.9, 0.08, 8), 0.07, 0.025, 6)
	return _finish(st)


## A root that splits in two: 6 x 8 x 2 x 3 = 288 triangles.
func _root_fork() -> ArrayMesh:
	var st := _begin()
	var trunk := _root_path(Vector3(-0.9, -0.06, 0), Vector3.RIGHT, 1.1, 0.3, 8, 0.05)
	_tube(st, trunk, 0.13, 0.08, 6)
	var split: Vector3 = trunk[6]
	for sgn in [-1.0, 1.0]:
		var dir := Vector3(1.0, 0, sgn * rng.randf_range(0.5, 0.9))
		var branch := _root_path(split - Vector3(0, 0.03, 0), dir, rng.randf_range(0.9, 1.3), 0.1, 8, 0.1)
		_tube(st, branch, 0.085, 0.025, 6)
	return _finish(st)


## Thin roots crossing each other: 5 x (5 x 8 x 2) = 400 triangles.
func _roots_tangle() -> ArrayMesh:
	var st := _begin()
	for i in 5:
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var start := Vector3(rng.randf_range(-0.4, 0.4), -0.06, rng.randf_range(-0.4, 0.4)) - dir * 0.6
		_tube(st, _root_path(start, dir, rng.randf_range(1.0, 1.6), rng.randf_range(0.08, 0.16), 8, 0.2), rng.randf_range(0.04, 0.06), 0.015, 5)
	return _finish(st)


# ---------------------------------------------------------------- output

func _save(mesh: ArrayMesh, mesh_dir: String, scene_dir: String, name: String, walkable: bool) -> void:
	ResourceSaver.save(mesh, mesh_dir + name + ".res", ResourceSaver.FLAG_COMPRESS)
	var root := Node3D.new()
	root.name = name.to_pascal_case()
	if walkable:
		root.set_script(load("res://cultic/scripts/mesh_collision.gd"))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = load(mesh_dir + name + ".res")
	root.add_child(mi)
	mi.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, scene_dir + name + ".tscn")
	var tris := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arr[Mesh.ARRAY_INDEX] else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var box := mesh.get_aabb()
	print("%-16s %4d triangles  %.2f x %.2f x %.2f m" % [name, tris, box.size.x, box.size.y, box.size.z])
	root.free()
