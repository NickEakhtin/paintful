extends SceneTree
## Builds the ruined dark grey stone walls (scenes/props/ruins/*.tscn) out of single blocks, like a dry-stone kit:
## a wall with a breach, two low broken walls, a stepped stub and four rubble heaps.
## Clean blocks in a course are drawn only where they can be seen: front and back faces with a recessed rim (the
## mortar joint) plus the ends, tops and bottoms that no neighbour covers, about 20 triangles a block. Damaged blocks
## are chipped (noise) and bitten (carved corners) on a grid of `cells` per side, coarser on walls than on rubble.
## Every piece stays within about 1 000 - 5 000 triangles.
## The stone look is all in the normal maps of two materials (art/materials/stone/): fine grain for clean blocks,
## porous for damaged ones. Each block gets a slightly different tint (vertex colour).
## Usage: Godot --headless --path . -s tools/props/build_ruins.gd      (re-running overwrites the files; change SEED
## for other variations)

const SEED := 1701
const MESH_DIR := "res://art/models/ruins/"
const SCENE_DIR := "res://world/props/ruins/"
const MAT_DIR := "res://art/materials/stone/"
const GAP := 0.008                     # gap around loose / damaged stones, metres
const JOINT := 0.014                   # width of the bevelled rim that draws the mortar joint on a clean block
const RECESS := 0.012                  # how deep the rim goes back

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var mat_clean: StandardMaterial3D
var mat_damaged: StandardMaterial3D
var _clean: SurfaceTool
var _damaged: SurfaceTool
var _tris := 0
var _cells := 7                        # grid cells per side of a damaged block


func _init() -> void:
	rng.seed = SEED
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.frequency = 1.0
	for dir in [MESH_DIR, SCENE_DIR, MAT_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_make_materials()
	_build("wall_breach", _wall_breach, 3)
	_build("wall_low_long", _wall_low_long, 3)
	_build("wall_low_short", _wall_low_short, 4)
	_build("stub_stepped", _stub_stepped, 4)
	for i in 4:
		_build("rubble_%d" % (i + 1), _rubble.bind(i), 7)
	quit()


# ---------------------------------------------------------------- materials

func _make_materials() -> void:
	mat_clean = _stone_material(Color(0.09, 0.09, 0.095), FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 6, 5.0, 0.9, 1.4)
	mat_damaged = _stone_material(Color(0.075, 0.075, 0.08), FastNoiseLite.TYPE_CELLULAR, 0.06, 3, 7.0, 1.1, 2.4)
	ResourceSaver.save(mat_clean, MAT_DIR + "limestone.tres")
	ResourceSaver.save(mat_damaged, MAT_DIR + "limestone_damaged.tres")
	mat_clean = load(MAT_DIR + "limestone.tres")
	mat_damaged = load(MAT_DIR + "limestone_damaged.tres")


## Dark grey stone with the relief only in a procedural normal map, mapped triplanar (no UVs needed).
func _stone_material(albedo: Color, kind: int, freq: float, octaves: int, bump: float, strength: float, scale: float) -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.seed = SEED + kind
	if kind == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB   # pits between cells: porous stone
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = bump
	tex.noise = n
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.vertex_color_use_as_albedo = true            # per-block tint
	m.roughness = 0.93
	m.normal_enabled = true
	m.normal_texture = tex
	m.normal_scale = strength
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * scale
	return m


# ---------------------------------------------------------------- blocks

## A block centred at `c`, `size` in metres, tilted by `rot` (radians). damage 0 = clean chamfered box,
## up to 1 = heavily chipped with bitten corners.
func block(c: Vector3, size: Vector3, damage := 0.0, rot := Vector3.ZERO, tint := 1.0) -> void:
	var basis := Basis.from_euler(rot)
	var h := size * 0.5
	var st := _damaged if damage > 0.0 else _clean
	var color := Color(1.0, 1.0, 1.0) * tint if damage == 0.0 else Color(0.96, 0.96, 0.97) * tint
	color.a = 1.0
	if damage == 0.0:
		var ch := minf(0.016, h[h.min_axis_index()] * 0.3)
		_box(st, c, basis, h, [-1.0, -1.0 + 2.0 * ch, 1.0 - 2.0 * ch, 1.0], ch, 0.0, [], color)
	else:
		var steps := []
		for i in _cells + 1:
			steps.append(-1.0 + 2.0 * i / float(_cells))
		var bites := []
		for i in rng.randi_range(2, 4):
			# carve from a corner or an edge: a sphere centred a little outside it
			var corner := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).sign()
			if rng.randf() < 0.4:
				corner[rng.randi_range(0, 2)] = 0.0
			var centre := corner * h * rng.randf_range(1.0, 1.25)
			bites.append([centre, h[h.min_axis_index()] * rng.randf_range(0.6, 1.3) * damage + 0.02])
		_box(st, c, basis, h, steps, minf(0.04, h[h.min_axis_index()] * 0.4), damage, bites, color)


## A clean block in a course, axis-aligned: front and back faces with a recessed, darker rim (the joint) and only the
## side faces listed in `open` (0..3 = -X, +X, -Y, +Y), which nothing covers.
func _slab(c: Vector3, h: Vector3, open: Array, tint: float) -> void:
	var col := Color(1.0, 1.0, 1.0) * tint
	col.a = 1.0
	var rim := col * 0.62
	rim.a = 1.0
	for side in [-1.0, 1.0]:
		var zo: float = c.z + side * (h.z - RECESS)
		var zi: float = c.z + side * h.z
		var out := [Vector3(c.x - h.x, c.y - h.y, zo), Vector3(c.x + h.x, c.y - h.y, zo), Vector3(c.x + h.x, c.y + h.y, zo), Vector3(c.x - h.x, c.y + h.y, zo)]
		var inn := [Vector3(c.x - h.x + JOINT, c.y - h.y + JOINT, zi), Vector3(c.x + h.x - JOINT, c.y - h.y + JOINT, zi), Vector3(c.x + h.x - JOINT, c.y + h.y - JOINT, zi), Vector3(c.x - h.x + JOINT, c.y + h.y - JOINT, zi)]
		var n: Vector3 = Vector3(0, 0, side)
		_quad(_clean, inn[0], inn[1], inn[2], inn[3], [col, col, col, col], n)
		for i in 4:
			var j := (i + 1) % 4
			var mid: Vector3 = (out[i] + out[j]) * 0.5 - c
			mid.z = 0.0
			_quad(_clean, out[i], out[j], inn[j], inn[i], [rim, rim, col, col], (mid.normalized() + n).normalized())
	var zf := h.z - RECESS
	for f in open:
		var axis: int = 0 if f < 2 else 1
		var sgn := -1.0 if f % 2 == 0 else 1.0
		var e := h
		e[axis] = h[axis] * sgn
		var other := 1 - axis
		var a := c
		a[axis] += e[axis]
		var p0 := a; var p1 := a; var p2 := a; var p3 := a
		p0[other] -= h[other]; p0.z = c.z - zf
		p1[other] += h[other]; p1.z = c.z - zf
		p2[other] += h[other]; p2.z = c.z + zf
		p3[other] -= h[other]; p3.z = c.z + zf
		var n := Vector3.ZERO
		n[axis] = sgn
		_quad(_clean, p0, p1, p2, p3, [rim, rim, rim, rim], n)


## One quad as two triangles, wound so that `outward` is the front side (Godot: clockwise = front).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colors: Array, outward: Vector3) -> void:
	var pts := [a, b, c, d]
	var order := [0, 1, 2, 0, 2, 3]
	if (b - a).cross(c - a).dot(outward) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k in order:
		st.set_color(colors[k])
		st.add_vertex(pts[k])
	_tris += 2


## Puts out a list of course blocks [centre, size, damage]: damaged ones as loose chipped stones, clean ones as
## slabs whose faces hidden behind clean neighbours (touching and covering at least 95 %) are left out.
func _emit(blocks: Array) -> void:
	var clean := blocks.filter(func(b): return b[2] <= 0.0)
	for b in blocks:
		if b[2] > 0.0:
			_course_block(b[0], b[1], b[2])
	for b in clean:
		var c: Vector3 = b[0]
		var h: Vector3 = b[1] * 0.5
		var open := []
		for f in 4:
			var axis: int = 0 if f < 2 else 1
			var sgn := -1.0 if f % 2 == 0 else 1.0
			var plane := c[axis] + sgn * h[axis]
			var other := 1 - axis
			var lo := c[other] - h[other]
			var hi := c[other] + h[other]
			var covered := 0.0
			for o in clean:
				if o == b:
					continue
				var oc: Vector3 = o[0]
				var oh: Vector3 = o[1] * 0.5
				if absf(oc[axis] - sgn * oh[axis] - plane) > 0.02:
					continue
				var along := minf(hi, oc[other] + oh[other]) - maxf(lo, oc[other] - oh[other])
				var deep := minf(c.z + h.z, oc.z + oh.z) - maxf(c.z - h.z, oc.z - oh.z)
				if along > 0.0 and deep > 0.0:
					covered += along * deep
			if covered < 0.95 * (hi - lo) * h.z * 2.0:
				open.append(f)
		_slab(c, h, open, rng.randf_range(0.88, 1.05))


## A box surface as six grids (cell lines at `steps`, in -1..1), rounded by radius r, then chipped and carved.
func _box(st: SurfaceTool, c: Vector3, basis: Basis, h: Vector3, steps: Array, r: float, damage: float, bites: Array, color: Color) -> void:
	var seed_off := Vector3(rng.randf() * 100.0, rng.randf() * 100.0, rng.randf() * 100.0)
	for axis in 3:
		for side in [-1.0, 1.0]:
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var grid := []
			for j in steps.size():
				var row := []
				for i in steps.size():
					var p := Vector3.ZERO
					p[axis] = side
					p[u] = steps[i]
					p[v] = steps[j]
					row.append(_shape(p * h, h, r, damage, bites, seed_off))
				grid.append(row)
			for j in steps.size() - 1:
				for i in steps.size() - 1:
					var a: Vector3 = grid[j][i]
					var b: Vector3 = grid[j][i + 1]
					var d: Vector3 = grid[j + 1][i]
					var e: Vector3 = grid[j + 1][i + 1]
					var quad := [a, b, e, d]
					# winding: outward normal along +axis*side
					var ccw: bool = side < 0.0          # Godot: clockwise = front face
					var tri := [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]] if ccw else [quad[0], quad[2], quad[1], quad[0], quad[3], quad[2]]
					for k in 6:
						st.set_color(color)
						st.add_vertex(c + basis * tri[k])
					_tris += 2


func _shape(p: Vector3, h: Vector3, r: float, damage: float, bites: Array, seed_off: Vector3) -> Vector3:
	# round the box: pull the point onto a box of half-size h-r, then out by r
	var inner := (h - Vector3.ONE * r).max(Vector3.ZERO)
	var q := p.clamp(-inner, inner)
	var out := p - q
	if out.length() > 0.00001:
		p = q + out.normalized() * r
	if damage > 0.0:
		var n := out.normalized() if out.length() > 0.00001 else p.normalized()
		# chipped surface: dents only (never bulges), scaled by the block size
		var amp := minf(h.x, minf(h.y, h.z)) * 0.6 * damage
		var big := noise.get_noise_3dv((p + seed_off) * 3.5) * 0.5 + 0.5              # broken-off chunks
		var small := absf(noise.get_noise_3dv((p - seed_off) * 14.0))                   # crumbly rim
		p -= n * amp * (big * big * big * 1.6 + small * 0.35)
		for bite in bites:
			var centre: Vector3 = bite[0]
			var radius: float = bite[1]
			var d := p - centre
			if d.length() < radius:
				p = centre + d.normalized() * radius       # pushed out of the bite = into the block
	return p


# ---------------------------------------------------------------- layouts

## Courses of blocks in running bond along X (centred), Z = thickness, from y0 up to `height`.
## keep(rect_centre, size) decides per block: < 0 skip, 0 clean, > 0 damage amount.
func courses(width: float, height: float, thick: float, keep: Callable, y0 := 0.0, ragged_ends := 0.15) -> Array:
	var placed := []
	var y := y0
	var row := 0
	while y < height - 0.05:
		var hgt: float = [0.16, 0.2, 0.24, 0.28, 0.32][rng.randi_range(0, 4)]
		if y + hgt > height:
			hgt = height - y
		if hgt < 0.08:
			break
		var x := -width * 0.5 + rng.randf_range(0.0, ragged_ends)
		var end := width * 0.5 - rng.randf_range(0.0, ragged_ends)
		if row % 2 == 1:
			x -= rng.randf_range(0.05, 0.2)
		while x < end - 0.12:
			var length := rng.randf_range(0.32, 0.85) * (1.0 + (hgt - 0.16) * 2.0)
			length = minf(length, end - x)
			var centre := Vector3(x + length * 0.5, y + hgt * 0.5, 0.0)
			var size := Vector3(length, hgt, thick)
			var dmg: float = keep.call(centre, size)
			if dmg >= 0.0:
				placed.append([centre, size, dmg])
			x += length
		y += hgt
		row += 1
	return _stable(placed, y0)


## Drops blocks that would hang in the air: a block stays if it sits on the ground, on a kept block, or is
## wedged between kept neighbours on both sides (like the stones over the breach). Repeated until nothing changes.
func _stable(blocks: Array, ground: float) -> Array:
	var kept := blocks.duplicate()
	var changed := true
	while changed:
		changed = false
		for b in kept.duplicate():
			var c: Vector3 = b[0]
			var s: Vector3 = b[1]
			var bottom := c.y - s.y * 0.5
			if bottom < ground + 0.02:
				continue
			var below := false
			var left := false
			var right := false
			for o in kept:
				if o == b:
					continue
				var oc: Vector3 = o[0]
				var os: Vector3 = o[1]
				var overlap := minf(c.x + s.x * 0.5, oc.x + os.x * 0.5) - maxf(c.x - s.x * 0.5, oc.x - os.x * 0.5)
				if absf(oc.y + os.y * 0.5 - bottom) < 0.03 and overlap > 0.06:
					below = true
					break
				if absf(oc.y - c.y) < 0.02:
					if absf(oc.x + os.x * 0.5 - (c.x - s.x * 0.5)) < 0.03:
						left = true
					if absf(oc.x - os.x * 0.5 - (c.x + s.x * 0.5)) < 0.03:
						right = true
			if not below and not (left and right):
				kept.erase(b)
				changed = true
	return kept


func _course_block(centre: Vector3, size: Vector3, dmg: float) -> void:
	var rot := Vector3(rng.randf_range(-0.01, 0.01), rng.randf_range(-0.015, 0.015), rng.randf_range(-0.01, 0.01))
	if dmg > 0.0:
		rot *= 4.0                                         # loose, shifted stones
		size = (size - Vector3.ONE * GAP) * rng.randf_range(0.94, 1.0)
	block(centre, size, dmg, rot, rng.randf_range(0.88, 1.05))


func _wall_breach() -> void:
	var cx := 0.15
	var cy := 1.55
	var radius := 0.95
	var a := rng.randf() * TAU
	var b := rng.randf() * TAU
	var hole_r := func(angle: float) -> float:
		return radius * (1.0 + 0.16 * sin(3.0 * angle + a) + 0.1 * sin(5.0 * angle + b) + 0.06 * sin(9.0 * angle))
	var keep := func(centre: Vector3, size: Vector3) -> float:
		var d := Vector2(centre.x - cx, (centre.y - cy) * 1.15)
		var edge: float = hole_r.call(d.angle())
		var dist := d.length()
		if dist < edge - 0.05:
			return -1.0                                    # inside the breach: gone
		if dist < edge + 0.45:
			return clampf(1.0 - (dist - edge) / 0.45, 0.25, 1.0)   # around it: crumbled
		return 0.0
	var blocks := courses(6.0, 3.0, 0.38, keep, 0.0, 0.05)
	# a cap course of bigger slabs
	var top := 0.0
	for blk in blocks:
		top = maxf(top, blk[0].y + blk[1].y * 0.5)
	var x := -3.0
	while x < 2.95:
		var length := minf(rng.randf_range(0.5, 0.75), 3.0 - x)
		blocks.append([Vector3(x + length * 0.5, top + 0.11, 0.0), Vector3(length, 0.22, 0.42), 0.0])
		x += length
	_emit(blocks)
	# a few fallen stones at the foot of the breach
	for i in 5:
		var s := Vector3(rng.randf_range(0.25, 0.45), rng.randf_range(0.14, 0.24), rng.randf_range(0.25, 0.4))
		block(Vector3(cx + rng.randf_range(-0.7, 0.7), s.y * 0.5, rng.randf_range(0.35, 0.8) * (1 if rng.randf() < 0.5 else -1)), s, rng.randf_range(0.5, 1.0), Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.1, 0.1)), rng.randf_range(0.85, 1.0))


## A broken wall whose top follows profile(x) (height in metres); blocks near the top are crumbled.
func _broken_wall(width: float, thick: float, profile: Callable) -> void:
	var keep := func(centre: Vector3, size: Vector3) -> float:
		var top: float = profile.call(centre.x) + rng.randf_range(-0.08, 0.08)
		if centre.y > top:
			return -1.0
		if centre.y + size.y * 0.5 > top - 0.35:
			return rng.randf_range(0.5, 1.0)
		return 0.0 if rng.randf() > 0.08 else rng.randf_range(0.3, 0.6)
	_emit(courses(width, 1.6, thick, keep, 0.0, 0.2))


func _wall_low_long() -> void:
	_broken_wall(4.4, 0.4, func(x: float) -> float:
		var t := (x + 2.2) / 4.4
		return lerpf(1.35, 0.45, smoothstep(0.1, 0.55, t)) + 0.12 * sin(x * 3.1) + 0.06 * sin(x * 7.3))
	# loose crumbled stones lying on the low end
	for i in 4:
		var s := Vector3(rng.randf_range(0.3, 0.42), rng.randf_range(0.16, 0.24), 0.32)
		block(Vector3(rng.randf_range(-0.2, 1.8), 0.55 + s.y * 0.5, rng.randf_range(-0.05, 0.05)), s, rng.randf_range(0.6, 1.0), Vector3(0, rng.randf_range(-0.3, 0.3), rng.randf_range(-0.08, 0.08)), rng.randf_range(0.85, 1.0))


func _wall_low_short() -> void:
	_broken_wall(2.3, 0.4, func(x: float) -> float:
		return 0.62 + 0.1 * sin(x * 2.3 + 1.0) + (0.18 if x > 0.55 else 0.0))


## A stepped stub: a few courses that get narrower and shift sideways, mostly crumbled.
func _stub_stepped() -> void:
	var blocks := []
	var y := 0.0
	var shift := 0.0
	var w := 0.7
	for row in 6:
		var hgt := rng.randf_range(0.18, 0.28)
		var n := 1 if w < 0.5 else 2
		var x := -w * 0.5 + shift
		for i in n:
			var length := w / n
			var dmg := 0.0 if row < 2 and rng.randf() < 0.5 else rng.randf_range(0.4, 0.9)
			blocks.append([Vector3(x + length * 0.5, y + hgt * 0.5, 0.0), Vector3(length, hgt, 0.46), dmg])
			x += length
		y += hgt
		shift += rng.randf_range(-0.08, 0.12)
		w = maxf(0.38, w - rng.randf_range(0.0, 0.1))
	_emit(blocks)


## Small heaps of fallen, chipped blocks.
func _rubble(variant: int) -> void:
	var count: int = [3, 4, 5, 2][variant]
	var y := 0.0
	for i in count:
		var s := Vector3(rng.randf_range(0.28, 0.55), rng.randf_range(0.16, 0.3), rng.randf_range(0.26, 0.45))
		var lie: bool = i < 2 or rng.randf() < 0.5                         # on the ground or stacked
		var p := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.2, 0.2))
		if lie:
			p.y = s.y * 0.5
		else:
			p.y = y + s.y * 0.5
		y = maxf(y, p.y + s.y * 0.5)
		block(p, s, rng.randf_range(0.5, 1.0), Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.8, 0.8), rng.randf_range(-0.12, 0.12)), rng.randf_range(0.85, 1.02))


# ---------------------------------------------------------------- output

func _build(name: String, layout: Callable, cells: int) -> void:
	_cells = cells
	_clean = SurfaceTool.new()
	_clean.begin(Mesh.PRIMITIVE_TRIANGLES)
	_damaged = SurfaceTool.new()
	_damaged.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tris = 0
	layout.call()
	var mesh := ArrayMesh.new()
	for pair in [[_clean, mat_clean], [_damaged, mat_damaged]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()                             # no shared vertices: flat, faceted stone
		var arrays := st.commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	ResourceSaver.save(mesh, MESH_DIR + name + ".res", ResourceSaver.FLAG_COMPRESS)

	var root := Node3D.new()
	root.name = name.to_pascal_case()
	root.set_script(load("res://world/props/mesh_collision.gd"))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = load(MESH_DIR + name + ".res")
	root.add_child(mi)
	mi.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, SCENE_DIR + name + ".tscn")
	var box := mesh.get_aabb()
	print("%-16s %6d triangles  %.2f x %.2f x %.2f m" % [name, _tris, box.size.x, box.size.y, box.size.z])
	root.free()
