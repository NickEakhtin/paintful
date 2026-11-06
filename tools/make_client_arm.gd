extends SceneTree
## Builds the client's arm from the side-view photo the user brought (`docs/art/arm_side_reference.jpg`: a man's
## right arm hanging at his side, seen from the side, the forearm leaning forward, the hand curled): its outline
## shoulder to fingertips, row by row, and its shading, so the arm in a session has the photo's proportions.
## - The skin is cut from the photo by colour (reddish; the grey background and the black clothes aren't), the arm
##   is the piece round ARM_SEED. Under the shoulder the chest shows through the tank top's armhole and joins the arm,
##   so there the arm's front edge follows the crease between them, traced by hand (FRONT_EDGE).
## - The picture is turned so the forearm stands upright (its centre line fitted over FOREARM_ROWS): the stencil sits
##   on it square and the view scrolls straight along it; the upper arm leans as the elbow bends.
## - Each row of the turned arm gives its left and right edge (sub-pixel, smoothed a little): the half width and the
##   centre line. The elbow and the wrist are the narrowest rows near ELBOW_GUESS and WRIST_GUESS; the stencil's
##   middle goes STENCIL_AT of the way from the elbow to the wrist, and the forearm's half width there becomes
##   ArmShape's radius.
## - The shading: across each row (sin(theta) from -1 to 1) the photo's luminance over its average at that place
##   across the arm (the average over the arm's rows), which keeps the muscles, the elbow and the knuckles and leaves
##   the round light to the game's own lamp; plus a mask of the skin (0 between the fingers).
## Writes art/characters/client_arm/arm_profile.tres (ArmProfile) and arm_shading.png.
## Run: Godot --headless --path . --script res://tools/make_client_arm.gd   (then Godot --headless --path . --import)
## With the environment variable ARM_DEBUG set to a folder it also saves the turned arm with its edges there.

const SOURCE: String = "res://docs/art/arm_side_reference.jpg"
const OUT_DIR: String = "res://art/characters/client_arm/"
const ARM_SEED: Vector2i = Vector2i(260, 300)
## The arm's front edge under the shoulder (photo px), where the chest joins it: x at these rows, straight between.
const FRONT_EDGE: PackedVector2Array = [Vector2(349, 140), Vector2(350, 150), Vector2(348, 160), Vector2(344, 170),
		Vector2(339, 182), Vector2(332, 200), Vector2(326, 215), Vector2(322, 230), Vector2(320, 244)]
## Photo rows over which the forearm's centre line is fitted.
const FOREARM_ROWS: Vector2i = Vector2i(410, 580)
## Rough photo points of the elbow and the wrist (the narrowest rows are searched round them).
const ELBOW_GUESS: Vector2 = Vector2(260, 365)
const WRIST_GUESS: Vector2 = Vector2(346, 598)
const ELBOW_SEARCH: int = 35
const WRIST_SEARCH: int = 20
## The stencil's middle, as a share of the way from the elbow to the wrist.
const STENCIL_AT: float = 0.4
## The edges are smoothed over rows with a gaussian of this many rows (the photo's pixel steps go).
const EDGE_SMOOTH: float = 4.0
## ArmShape's radius (px): the forearm's half width at the stencil's middle.
const RADIUS: float = 210.0
## Above the strap's corner (FRONT_EDGE's first point) the photo shows the tank top, not the shoulder: there a round
## dome carries the deltoid on, as wide as the arm at that row and this share of its half width tall, leaning with
## the upper arm.
const DOME_HEIGHT: float = 0.85
## The shading is smoothed with a gaussian of this many texels along the arm and across it (the photo's grain and
## the row-by-row steps go; the muscles are tens of rows big).
const SHADING_SMOOTH: Vector2 = Vector2(1.5, 2.5)
## Near the strap (rows above the strap's corner + STRAP_ROWS) the photo's shading counts only STRAP_CLEAR px or more
## inside the skin (the strap's shadow lies along its edge).
const STRAP_ROWS: int = 25
const STRAP_CLEAR: float = 5.0
## Rows over which the shading fades to neutral past the photo's skin.
const DETAIL_FADE: float = 40.0
## Columns of the shading texture across the arm.
const COLUMNS: int = 128
## The shading's detail is kept within these bounds.
const DETAIL_RANGE: Vector2 = Vector2(0.4, 1.8)

var _w: int
var _h: int


func _init() -> void:
	var photo: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if photo == null or photo.is_empty():
		push_error("can't read " + SOURCE)
		quit(1)
		return
	photo.convert(Image.FORMAT_RGBA8)
	_w = photo.get_width()
	_h = photo.get_height()
	var luminance: PackedFloat32Array = PackedFloat32Array()
	luminance.resize(_w * _h)
	var skin: PackedByteArray = PackedByteArray()
	skin.resize(_w * _h)
	for y in _h:
		for x in _w:
			var c: Color = photo.get_pixel(x, y)
			luminance[y * _w + x] = c.get_luminance()
			skin[y * _w + x] = 1 if (c.r - c.b > 0.09 and c.r > 0.1 and c.r - c.g > 0.02) else 0
	# the chest through the armhole: nothing right of the arm's front edge in those rows
	for y in range(int(FRONT_EDGE[0].y), int(FRONT_EDGE[FRONT_EDGE.size() - 1].y) + 1):
		var limit: float = _front_edge_at(y)
		for x in range(ceili(limit) + 1, _w):
			skin[y * _w + x] = 0
	var arm: PackedByteArray = _piece(skin, ARM_SEED.y * _w + ARM_SEED.x)
	arm = _fill_holes(arm)
	# turn the forearm upright: its centre line c = a + k * y over FOREARM_ROWS
	var sum_y: float = 0.0
	var sum_c: float = 0.0
	var sum_yy: float = 0.0
	var sum_yc: float = 0.0
	var n: float = 0.0
	for y in range(FOREARM_ROWS.x, FOREARM_ROWS.y + 1):
		var edges: Vector2 = _row_edges(arm, y)
		if edges.x < 0.0:
			continue
		var c: float = (edges.x + edges.y) * 0.5
		sum_y += y
		sum_c += c
		sum_yy += y * y
		sum_yc += y * c
		n += 1.0
	var k: float = (n * sum_yc - sum_y * sum_c) / (n * sum_yy - sum_y * sum_y)
	var a: float = (sum_c - k * sum_y) / n
	var angle: float = atan(k)   # turning the picture by this brings the forearm's direction (k, 1) to (0, 1)
	var mid_y: float = (FOREARM_ROWS.x + FOREARM_ROWS.y) * 0.5
	var pivot: Vector2 = Vector2(a + k * mid_y, mid_y)
	var turn: Transform2D = Transform2D(angle, Vector2.ZERO)
	# the turned picture's frame: just big enough for the arm
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for i in _w * _h:
		if arm[i] == 1:
			var p: Vector2 = turn * (Vector2(i % _w, i / _w) - pivot)
			low = low.min(p)
			high = high.max(p)
	var margin: float = 4.0
	var origin: Vector2 = low - Vector2.ONE * margin
	var size: Vector2i = Vector2i((high - low + Vector2.ONE * margin * 2.0).ceil())
	var back: Transform2D = turn.affine_inverse()
	var coverage: PackedFloat32Array = PackedFloat32Array()
	var lit: PackedFloat32Array = PackedFloat32Array()   # luminance × coverage, so edges don't take the background in
	coverage.resize(size.x * size.y)
	lit.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			var source: Vector2 = back * (Vector2(x, y) + origin) + pivot
			var cover: float = _bilinear_mask(arm, source)
			coverage[y * size.x + x] = cover
			lit[y * size.x + x] = _bilinear_lit(arm, luminance, source)
	# the edges of every row of the turned arm
	var lefts: PackedFloat32Array = PackedFloat32Array()
	var rights: PackedFloat32Array = PackedFloat32Array()
	lefts.resize(size.y)
	rights.resize(size.y)
	var first: int = -1
	var last: int = -1
	for y in size.y:
		var edges: Vector2 = _cover_edges(coverage, size, y)
		lefts[y] = edges.x
		rights[y] = edges.y
		if edges.x >= 0.0:
			if first < 0:
				first = y
			last = y
	lefts = _smooth(lefts, first, last)
	rights = _smooth(rights, first, last)
	var half: PackedFloat32Array = PackedFloat32Array()
	var middle: PackedFloat32Array = PackedFloat32Array()
	half.resize(size.y)
	middle.resize(size.y)
	for y in range(first, last + 1):
		half[y] = maxf((rights[y] - lefts[y]) * 0.5, 0.0)
		middle[y] = (rights[y] + lefts[y]) * 0.5
	var elbow_row: int = _narrowest(half, roundi((turn * (ELBOW_GUESS - pivot) - origin).y), ELBOW_SEARCH)
	var wrist_row: int = _narrowest(half, roundi((turn * (WRIST_GUESS - pivot) - origin).y), WRIST_SEARCH)
	var stencil_row: float = lerpf(elbow_row, wrist_row, STENCIL_AT)
	var row_i: int = int(stencil_row)
	var stencil_half: float = lerpf(half[row_i], half[row_i + 1], stencil_row - row_i)
	var stencil_middle: float = lerpf(middle[row_i], middle[row_i + 1], stencil_row - row_i)
	var scale: float = RADIUS / stencil_half   # arm px per photo px
	# the shoulder's top: a dome from the strap's corner up, leaning as the upper arm does
	var cap_row: int = roundi((turn * (FRONT_EDGE[0] - pivot) - origin).y)
	var lean: float = _fit_slope(middle, cap_row + 20, elbow_row - 20)
	var cap_half: float = half[cap_row]
	var cap_middle: float = middle[cap_row]
	var dome: int = ceili(cap_half * DOME_HEIGHT)
	# the samples: a zero-wide one just above the dome's top and one below the fingertips
	var rows: PackedInt32Array = PackedInt32Array()
	var sample_half: PackedFloat32Array = PackedFloat32Array()
	var sample_middle: PackedFloat32Array = PackedFloat32Array()
	for y in range(cap_row - dome - 1, last + 2):
		var h: float = 0.0
		var m: float = cap_middle + lean * (y - cap_row)
		if y > last:
			m = middle[last]
		elif y >= cap_row:
			h = half[y]
			m = middle[y]
		else:
			var d: float = float(cap_row - y) / (cap_half * DOME_HEIGHT)
			h = cap_half * sqrt(maxf(1.0 - d * d, 0.0))
		rows.append(y)
		sample_half.append(h)
		sample_middle.append(m)
	# smoothed once more over the dome's base, so the photo's edges and the dome meet without a crease in the light
	sample_half = _smooth(sample_half, 1, rows.size() - 2)
	sample_middle = _smooth(sample_middle, 1, rows.size() - 2)
	var radii: PackedFloat32Array = PackedFloat32Array()
	var centers: PackedFloat32Array = PackedFloat32Array()
	for j in rows.size():
		radii.append(sample_half[j] / stencil_half)
		centers.append((sample_middle[j] - stencil_middle) / stencil_half)
	var top: float = (rows[0] - stencil_row) * scale
	# the shading: the turned photo across each row, over its average across the arm (neutral where there's no photo
	# of the skin: the dome over the strap, the ends)
	var samples: int = rows.size()
	var light: PackedFloat32Array = PackedFloat32Array()
	var skin_at: PackedFloat32Array = PackedFloat32Array()
	light.resize(samples * COLUMNS)
	skin_at.resize(samples * COLUMNS)
	var column_sum: PackedFloat32Array = PackedFloat32Array()
	var column_count: PackedFloat32Array = PackedFloat32Array()
	column_sum.resize(COLUMNS)
	column_count.resize(COLUMNS)
	for j in samples:
		var y: int = rows[j]
		for i in COLUMNS:
			var u: float = -1.0 + 2.0 * (i + 0.5) / COLUMNS
			light[j * COLUMNS + i] = -1.0
			skin_at[j * COLUMNS + i] = 1.0
			if y < 0 or y >= size.y or sample_half[j] <= 0.0:
				continue
			var at: Vector2 = Vector2(sample_middle[j] + u * sample_half[j], y)
			var cover: float = _sample(coverage, size, at)
			if y >= cap_row:
				skin_at[j * COLUMNS + i] = cover
			if cover < 0.5:
				continue
			# by the strap the photo's skin carries the strap's shadow: only well inside the skin counts there
			if y < cap_row + STRAP_ROWS and minf(_sample(coverage, size, at - Vector2(STRAP_CLEAR, 0.0)),
					_sample(coverage, size, at + Vector2(STRAP_CLEAR, 0.0))) < 0.95:
				continue
			var value: float = _sample(lit, size, at) / cover
			light[j * COLUMNS + i] = value
			# the average across the arm comes from the arm's rows only (not the shoulder's top or the hand)
			if y > cap_row and y < wrist_row:
				column_sum[i] += value
				column_count[i] += 1.0
	var detail: PackedFloat32Array = PackedFloat32Array()
	detail.resize(samples * COLUMNS)
	for j in samples:
		for i in COLUMNS:
			var value: float = light[j * COLUMNS + i]
			var average: float = column_sum[i] / maxf(column_count[i], 1.0)
			detail[j * COLUMNS + i] = 1.0 if value < 0.0 else clampf(value / maxf(average, 0.01), DETAIL_RANGE.x, DETAIL_RANGE.y)
	# where the photo has no skin (the dome over the strap, the ends) each column carries its nearest shading on and
	# fades it to neutral over DETAIL_FADE rows, so no seam shows
	for i in COLUMNS:
		var known: int = -1
		for j in samples:
			if light[j * COLUMNS + i] >= 0.0:
				known = j
				break
		if known < 0:
			continue
		for j in range(known - 1, -1, -1):
			detail[j * COLUMNS + i] = lerpf(detail[known * COLUMNS + i], 1.0, clampf(float(known - j) / DETAIL_FADE, 0.0, 1.0))
		for j in range(known + 1, samples):
			if light[j * COLUMNS + i] >= 0.0:
				known = j
			else:
				detail[j * COLUMNS + i] = lerpf(detail[known * COLUMNS + i], 1.0, clampf(float(j - known) / DETAIL_FADE, 0.0, 1.0))
	detail = _gauss(detail, COLUMNS, samples)
	var shading: Image = Image.create(COLUMNS, samples, false, Image.FORMAT_RGBA8)
	for j in samples:
		for i in COLUMNS:
			shading.set_pixel(i, j, Color(detail[j * COLUMNS + i] * 0.5, skin_at[j * COLUMNS + i], 0.0, 1.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	shading.save_png(ProjectSettings.globalize_path(OUT_DIR + "arm_shading.png"))
	_write_import(OUT_DIR + "arm_shading.png")
	_write_profile(top, scale, radii, centers, (elbow_row - stencil_row) * scale, (wrist_row - stencil_row) * scale)
	print("arm: forearm leaned %.1f°, %d rows, %.2f arm px per photo px, top %.0f, elbow %.0f, wrist %.0f, bottom %.0f" % [
			rad_to_deg(angle), samples, scale, top, (elbow_row - stencil_row) * scale, (wrist_row - stencil_row) * scale,
			top + scale * (samples - 1)])
	var debug: String = OS.get_environment("ARM_DEBUG")
	if not debug.is_empty():
		var view: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		for y in size.y:
			for x in size.x:
				var cover: float = coverage[y * size.x + x]
				var value: float = lit[y * size.x + x] / maxf(cover, 0.001) if cover > 0.02 else 0.15
				view.set_pixel(x, y, Color(value, value * 0.85, value * 0.75))
		for j in rows.size():
			var y: int = rows[j]
			if y < 0 or y >= size.y or sample_half[j] <= 0.0:
				continue
			for x: float in [sample_middle[j] - sample_half[j], sample_middle[j] + sample_half[j]]:
				view.set_pixel(clampi(roundi(x), 0, size.x - 1), y, Color(0, 1, 0))
			view.set_pixel(clampi(roundi(sample_middle[j]), 0, size.x - 1), y, Color(0, 0.6, 1))
		for x in size.x:
			view.set_pixel(x, elbow_row, Color(1, 0, 1))
			view.set_pixel(x, wrist_row, Color(1, 0, 1))
			view.set_pixel(x, int(stencil_row), Color(1, 1, 0))
		view.save_png(debug.path_join("arm_turned.png"))
		shading.save_png(debug.path_join("arm_shading.png"))
	quit()


func _front_edge_at(y: float) -> float:
	for i in FRONT_EDGE.size() - 1:
		var a: Vector2 = FRONT_EDGE[i]
		var b: Vector2 = FRONT_EDGE[i + 1]
		if y <= b.y:
			return lerpf(a.x, b.x, clampf((y - a.y) / (b.y - a.y), 0.0, 1.0))
	return FRONT_EDGE[FRONT_EDGE.size() - 1].x


## The 4-connected piece of `mask` holding pixel `start`.
func _piece(mask: PackedByteArray, start: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(_w * _h)
	var stack: PackedInt32Array = PackedInt32Array([start])
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if out[i] == 1 or mask[i] == 0:
			continue
		out[i] = 1
		var x: int = i % _w
		var y: int = i / _w
		if x > 0:
			stack.append(i - 1)
		if x < _w - 1:
			stack.append(i + 1)
		if y > 0:
			stack.append(i - _w)
		if y < _h - 1:
			stack.append(i + _w)
	return out


## Pixels the background can't reach from the border become arm (specks inside it); the gaps between the fingers
## open to the background, so they stay.
func _fill_holes(arm: PackedByteArray) -> PackedByteArray:
	var outside: PackedByteArray = PackedByteArray()
	outside.resize(_w * _h)
	var stack: PackedInt32Array = PackedInt32Array()
	for x in _w:
		stack.append(x)
		stack.append((_h - 1) * _w + x)
	for y in _h:
		stack.append(y * _w)
		stack.append(y * _w + _w - 1)
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if outside[i] == 1 or arm[i] == 1:
			continue
		outside[i] = 1
		var x: int = i % _w
		var y: int = i / _w
		if x > 0:
			stack.append(i - 1)
		if x < _w - 1:
			stack.append(i + 1)
		if y > 0:
			stack.append(i - _w)
		if y < _h - 1:
			stack.append(i + _w)
	var out: PackedByteArray = PackedByteArray()
	out.resize(_w * _h)
	for i in _w * _h:
		out[i] = 0 if outside[i] == 1 else 1
	return out


## Outermost arm pixels of photo row y, (-1, -1) if none.
func _row_edges(arm: PackedByteArray, y: int) -> Vector2:
	var left: int = -1
	var right: int = -1
	for x in _w:
		if arm[y * _w + x] == 1:
			if left < 0:
				left = x
			right = x
	return Vector2(left, right)


func _bilinear_mask(arm: PackedByteArray, p: Vector2) -> float:
	var x0: int = floori(p.x)
	var y0: int = floori(p.y)
	var fx: float = p.x - x0
	var fy: float = p.y - y0
	return lerpf(lerpf(_mask_at(arm, x0, y0), _mask_at(arm, x0 + 1, y0), fx),
			lerpf(_mask_at(arm, x0, y0 + 1), _mask_at(arm, x0 + 1, y0 + 1), fx), fy)


func _mask_at(arm: PackedByteArray, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return 0.0
	return float(arm[y * _w + x])


func _bilinear_lit(arm: PackedByteArray, luminance: PackedFloat32Array, p: Vector2) -> float:
	var x0: int = floori(p.x)
	var y0: int = floori(p.y)
	var fx: float = p.x - x0
	var fy: float = p.y - y0
	return lerpf(lerpf(_lit_at(arm, luminance, x0, y0), _lit_at(arm, luminance, x0 + 1, y0), fx),
			lerpf(_lit_at(arm, luminance, x0, y0 + 1), _lit_at(arm, luminance, x0 + 1, y0 + 1), fx), fy)


func _lit_at(arm: PackedByteArray, luminance: PackedFloat32Array, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return 0.0
	return luminance[y * _w + x] * arm[y * _w + x]


## Where the coverage of row y crosses 0.5 from the left and from the right (sub-pixel), (-1, -1) if it never does.
func _cover_edges(coverage: PackedFloat32Array, size: Vector2i, y: int) -> Vector2:
	var left: float = -1.0
	var right: float = -1.0
	for x in range(1, size.x):
		var a: float = coverage[y * size.x + x - 1]
		var b: float = coverage[y * size.x + x]
		if a < 0.5 and b >= 0.5:
			left = x - 1 + (0.5 - a) / (b - a)
			break
	if left < 0.0:
		return Vector2(-1.0, -1.0)
	for x in range(size.x - 1, 0, -1):
		var a: float = coverage[y * size.x + x]
		var b: float = coverage[y * size.x + x - 1]
		if a < 0.5 and b >= 0.5:
			right = x - (0.5 - a) / (b - a)
			break
	return Vector2(left, right)


## A gaussian over rows first..last (each row from the rows round it that exist).
func _smooth(values: PackedFloat32Array, first: int, last: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = values.duplicate()
	var reach: int = ceili(EDGE_SMOOTH * 3.0)
	for y in range(first, last + 1):
		var total: float = 0.0
		var weight: float = 0.0
		for d in range(-reach, reach + 1):
			var at: int = y + d
			if at < first or at > last:
				continue
			var g: float = exp(-0.5 * d * d / (EDGE_SMOOTH * EDGE_SMOOTH))
			total += values[at] * g
			weight += g
		out[y] = total / weight
	return out


func _narrowest(half: PackedFloat32Array, around: int, reach: int) -> int:
	var best: int = around
	for y in range(around - reach, around + reach + 1):
		if y >= 0 and y < half.size() and half[y] > 0.0 and half[y] < half[best]:
			best = y
	return best


func _sample(values: PackedFloat32Array, size: Vector2i, p: Vector2) -> float:
	var x0: int = clampi(floori(p.x), 0, size.x - 2)
	var y0: int = clampi(floori(p.y), 0, size.y - 1)
	var fx: float = clampf(p.x - x0, 0.0, 1.0)
	return lerpf(values[y0 * size.x + x0], values[y0 * size.x + x0 + 1], fx)


## A separable gaussian (SHADING_SMOOTH texels across and along), edges clamped.
func _gauss(values: PackedFloat32Array, width: int, height: int) -> PackedFloat32Array:
	var across: PackedFloat32Array = values.duplicate()
	var reach: int = ceili(SHADING_SMOOTH.x * 3.0)
	for y in height:
		for x in width:
			var total: float = 0.0
			var weight: float = 0.0
			for d in range(-reach, reach + 1):
				var g: float = exp(-0.5 * d * d / (SHADING_SMOOTH.x * SHADING_SMOOTH.x))
				total += values[y * width + clampi(x + d, 0, width - 1)] * g
				weight += g
			across[y * width + x] = total / weight
	var out: PackedFloat32Array = across.duplicate()
	reach = ceili(SHADING_SMOOTH.y * 3.0)
	for y in height:
		for x in width:
			var total: float = 0.0
			var weight: float = 0.0
			for d in range(-reach, reach + 1):
				var g: float = exp(-0.5 * d * d / (SHADING_SMOOTH.y * SHADING_SMOOTH.y))
				total += across[clampi(y + d, 0, height - 1) * width + x] * g
				weight += g
			out[y * width + x] = total / weight
	return out


## The slope of values over rows from..to (least squares), 0 if too few.
func _fit_slope(values: PackedFloat32Array, from: int, to: int) -> float:
	var n: float = 0.0
	var sy: float = 0.0
	var sv: float = 0.0
	var syy: float = 0.0
	var syv: float = 0.0
	for y in range(from, to + 1):
		n += 1.0
		sy += y
		sv += values[y]
		syy += y * y
		syv += y * values[y]
	if n < 2.0:
		return 0.0
	return (n * syv - sy * sv) / (n * syy - sy * sy)


func _write_import(path: String) -> void:
	var file: FileAccess = FileAccess.open(path + ".import", FileAccess.WRITE)
	file.store_string("""[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
""" % path)
	file.close()


func _write_profile(top: float, step: float, radii: PackedFloat32Array, centers: PackedFloat32Array, elbow: float,
		wrist: float) -> void:
	var file: FileAccess = FileAccess.open(OUT_DIR + "arm_profile.tres", FileAccess.WRITE)
	file.store_string("""[gd_resource type="Resource" script_class="ArmProfile" load_steps=3 format=3]

[ext_resource type="Script" path="res://tattoo/surfaces/arm/arm_profile.gd" id="1_script"]
[ext_resource type="Texture2D" path="%sarm_shading.png" id="2_shading"]

[resource]
script = ExtResource("1_script")
top = %.3f
step = %.5f
radii = PackedFloat32Array(%s)
centers = PackedFloat32Array(%s)
elbow = %.3f
wrist = %.3f
shading = ExtResource("2_shading")
""" % [OUT_DIR, top, step, _floats(radii), _floats(centers), elbow, wrist])
	file.close()


func _floats(values: PackedFloat32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value in values:
		parts.append("%.5f" % value)
	return ", ".join(parts)
