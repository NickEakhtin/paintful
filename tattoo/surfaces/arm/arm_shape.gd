class_name ArmShape
extends RefCounted
## The forearm as math: skin coordinates <-> the picture on screen. Pure logic, no nodes.
##
## Skin point = (theta, v): theta is the angle around the arm from its front line (negative to the left),
## v runs along the arm in pixels (0 = the arm's centre, positive down). The screen point is in pixels
## from the arm's centre too, seen straight on by an orthographic camera (x right, y down, z toward the camera).
##
## Pulling: the left hand grips the skin at `grip_angle` behind one silhouette and drags that grip point Q out
## past the arm and a little toward the camera. Seen from above, the skin follows the arm to the tangent point T
## and then runs straight to Q; the arc from T to the grip is stretched evenly over that segment. At rest
## T = Q and the arm is a plain cylinder. The stretch eases in along the flap (none right at T, more toward
## the fingers) and the vertical drag grows with the square of the way out, so the flap joins the arm
## without a crease in the light. The shape stays convex, so a skin point is visible exactly where it
## faces the camera. `arm_skin.gdshader` repeats these formulas: keep the two in sync.
##
## Sliding (the left hand gripping anywhere): the skin around a held point `drag_from` (theta, v) slides over the
## arm by `drag` (along the arc at `radius`, and along the arm, in pixels), fading out with distance
## (gaussian over `drag_radius`). Skin coordinates stay on the skin, so the stencil and the ink go with it; a point
## is shown where it slid to, so skin from behind a silhouette can be slid into view (and take ink) or front skin
## pushed away. Kept invertible: `drag` stays under about 1.1 × `drag_radius`.

## Radius at the arm's centre, in pixels.
var radius: float = 210.0:
	set(value):
		radius = value
		_profile_texture = null
## The arm's outline, shoulder to fingertips, and its centre line: measured off the user's side-view photo of an arm
## (ArmProfile, made by `tools/make_client_arm.gd`): the photo turned so the forearm stands upright under the stencil,
## the upper arm leaning toward the shoulder as the elbow bends, the hand below the wrist. A point (theta, v) sits at
## x = center_at(v) + sin(theta) × radius_at(v): round cross-sections stacked along the rows, their middles following
## the centre line, so seen from the front the arm has the photo's outline on both sides. The shader reads the same
## table as a texture (`apply_to()`: R the half width, G the centre, in radii), so the outline lives only in the data.
const PROFILE: ArmProfile = preload("res://art/characters/client_arm/arm_profile.tres")
var _radii: PackedFloat32Array = PROFILE.radii
var _centers: PackedFloat32Array = PROFILE.centers
var _profile_top: float = PROFILE.top
var _profile_step: float = PROFILE.step
var _profile_texture: ImageTexture
## Length the mesh is built for, in pixels (the shader's mesh runs MESH_REACH times it, centred on the stencil):
## from above the shoulder cap to below the hand.
var length: float = 2300.0
## Where the fingers hold the skin, measured from the front line (radians, behind the silhouette).
var grip_angle: float = deg_to_rad(115.0)
## How far past the silhouette a full pull drags the grip, in pixels.
var max_pull: float = 220.0
## How far toward the camera a full pull brings the grip, in radii.
var hold_depth: float = 0.25
## Share of the pull lost at rows far from the hand (the flap bulges where the hand holds it).
var grip_bulge: float = 0.35
## How quickly the pull falls off away from the hand's row, in pixels.
var bulge_spread: float = 300.0
## Row the hand holds, in pixels from the centre.
var grip_v: float = 0.0
## Ink stops landing between these angles of the surface away from the camera.
var ink_soft_angle: float = deg_to_rad(50.0)
var ink_max_angle: float = deg_to_rad(62.0)

## Pulled side: -1 left, 1 right, 0 none.
var side: int = 0
## How far the pull is, 0..1 of `max_pull`.
var amount: float = 0.0
## Vertical drag of the grip at a full-width row, in pixels (negative = up).
var shear: float = 0.0
## The held skin point (theta, v), how far it slid (arc pixels, pixels along the arm) and how far the slide reaches.
var drag_from: Vector2 = Vector2.ZERO
var drag: Vector2 = Vector2.ZERO
var drag_radius: float = 160.0
## Short folds across the arm, each (theta of its middle, its middle row, half its length round the arm in
## radians, skin px tucked in): that band of skin is bunched into `fold_closed_width` px on the arm and turned
## inward, so it takes no ink; the crease fades out toward its ends. `fold_amounts[i]` 1 = closed, 0 = smoothed
## out. Folds must not overlap round the arm (at any theta at most one counts). Applied before the slide
## (skin -> fold -> slide -> arm). `arm_skin.gdshader` repeats it (two folds at most).
var folds: Array[Vector4] = []
var fold_amounts: PackedFloat32Array = PackedFloat32Array()
var fold_closed_width: float = 8.0
## How far beyond a fold the skin is drawn in toward it, in pixels.
var fold_spread: float = 70.0
## A fat bump: (theta of its middle, its top row, half its width round the arm in radians, its height H in px). The
## bump's skin (rows top..top+H) bulges out and sags down over the `bump_overhang` px of skin below it, which hides
## under it and takes no ink. `bump_amount` 1 = full, 0 = flattened (the skin pulled taut). Applied after the folds,
## before the slide (skin -> folds -> bump -> slide -> arm). `arm_skin.gdshader` repeats it. z = 0: no bump.
var bump: Vector4 = Vector4.ZERO
var bump_overhang: float = 45.0
var bump_amount: float = 0.0
## How uneven the bump is (0: an even dome).
var bump_uneven: float = 0.5
## The bump reaches up over the skin above it instead of sagging down (`bump.y` stays its top row).
var bump_up: bool = false
## How ragged the folds' creases are, in pixels the crease wanders up and down (0: straight).
var fold_ragged: float = 9.0
## The crease climbs this many rows per radian round the arm (a fold across the stencil's diagonal), and breaks:
## its middle runs in straight pieces `FOLD_KINK_STEP` radians long, each corner `fold_kinks` × FOLD_KINKS[i] px off
## the line. `arm_skin.gdshader` repeats them.
var fold_tilt: float = 0.0
var fold_kinks: float = 0.0
const FOLD_KINK_STEP: float = 0.23
const FOLD_KINKS: PackedFloat32Array = [0.0, 0.85, -0.6, 0.45, -1.0, 0.7, 0.1, -0.75, 0.95, -0.35, 0.6, -0.9, 0.3, 0.0]


## Arm radius at row `v` (0 above the shoulder and below the fingertips).
func radius_at(v: float) -> float:
	var at: float = clampf((v - _profile_top) / _profile_step, 0.0, _radii.size() - 1.001)
	var i: int = int(at)
	return radius * lerpf(_radii[i], _radii[i + 1], at - i)


## The arm's centre line at row `v`: px across from the stencil's middle (right positive).
func center_at(v: float) -> float:
	var at: float = clampf((v - _profile_top) / _profile_step, 0.0, _centers.size() - 1.001)
	var i: int = int(at)
	return radius * lerpf(_centers[i], _centers[i + 1], at - i)


## The whole arm's box (shoulder's top to fingertips, its widest reach either side) as seen turned by `turn` (arm px
## into a turned frame, e.g. the view's), in that frame's px.
func outline_bounds(turn: Transform2D = Transform2D.IDENTITY) -> Rect2:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for i in _radii.size():
		var row: float = _profile_top + _profile_step * i
		for side: float in [-1.0, 1.0]:
			var p: Vector2 = turn.basis_xform(Vector2((_centers[i] + side * _radii[i]) * radius, row))
			low = low.min(p)
			high = high.max(p)
	return Rect2(low, high - low)


## Arm rows of the elbow and the wrist (ArmProfile).
func elbow_row() -> float:
	return PROFILE.elbow


func wrist_row() -> float:
	return PROFILE.wrist


## How much of the pull reaches row `v`, 0..1.
func bulge_at(v: float) -> float:
	var d: float = (v - grip_v) / bulge_spread
	return 1.0 - grip_bulge * (1.0 - exp(-0.5 * d * d))


## Screen point (x, y, z) of skin point (theta, v), in pixels from the arm's centre.
func skin_to_screen(theta: float, v: float) -> Vector3:
	var at: Vector2 = slide(theta, v)
	return _place(at.x, at.y)[0]


## How squarely the skin at (theta, v) faces the camera: 1 straight on, 0 edge-on, negative = hidden.
func facing(theta: float, v: float) -> float:
	var at: Vector2 = slide(theta, v)
	return _place(at.x, at.y)[1]


## Where skin point (theta, v) sits on the arm after the slide, as (theta, v).
func slide(theta: float, v: float) -> Vector2:
	var row: float = skin_row(theta, v)
	if drag == Vector2.ZERO:
		return Vector2(theta, row)
	var k: float = _slide_weight(theta, v)
	return Vector2(theta + drag.x / radius * k, row + drag.y * k)


## Skin point (theta, v) -> its row on the arm before the slide: folds, then the bump.
func skin_row(theta: float, v: float) -> float:
	return bump_place(theta, fold_place(theta, v))


## skin_row()'s inverse along the row.
func skin_unrow(theta: float, row: float) -> float:
	return fold_unplace(theta, bump_unplace(theta, row))


## A row (after the folds) -> its row with the bump sagging: the bump's rows stretched down over the skin below,
## that skin squeezed under it; nothing moves outside the two.
func bump_place(theta: float, row: float) -> float:
	if bump_up:
		return -_bump_place_down(theta, -row)
	return _bump_place_down(theta, row)


## bump_place() for a bump sagging down (an upward one works on mirrored rows).
func _bump_place_down(theta: float, row: float) -> float:
	var slip: float = _bump_slip(theta)
	if slip <= 0.0:
		return row
	var local: Vector2 = _bump_local(theta)   # (top, height) here
	var top: float = local.x
	var lip: float = top + local.y
	var bottom: float = lip + bump_overhang
	if row <= top or row >= bottom:
		return row
	if row <= lip:
		return top + (row - top) * (local.y + slip) / local.y
	return lip + slip + (row - lip) * (bump_overhang - slip) / bump_overhang


## bump_place()'s inverse.
func bump_unplace(theta: float, row: float) -> float:
	if bump_up:
		return -_bump_unplace_down(theta, -row)
	return _bump_unplace_down(theta, row)


func _bump_unplace_down(theta: float, row: float) -> float:
	var slip: float = _bump_slip(theta)
	if slip <= 0.0:
		return row
	var local: Vector2 = _bump_local(theta)
	var top: float = local.x
	var lip: float = top + local.y
	var bottom: float = lip + bump_overhang
	if row <= top or row >= bottom:
		return row
	if row <= lip + slip:
		return top + (row - top) * local.y / (local.y + slip)
	return lip + (row - lip - slip) * bump_overhang / (bump_overhang - slip)


## How deep a row (after the folds) is hidden under the bump, 0..1.
func bump_hidden(theta: float, row: float) -> float:
	if bump.z <= 0.0 or bump_amount <= 0.0:
		return 0.0
	var reach: float = _bump_reach(theta)
	if reach <= 0.0:
		return 0.0
	var local: Vector2 = _bump_local(theta)
	var lip: float = local.x + local.y
	var t: float = ((-row if bump_up else row) - lip) / bump_overhang
	return bump_amount * reach * smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.8, 1.0, t))


## 1 across the bump's middle, easing to 0 at its sides round the arm.
func _bump_reach(theta: float) -> float:
	if bump.z <= 0.0:
		return 0.0
	var x: float = clampf(absf(theta - bump.x) / bump.z, 0.0, 1.0)
	var r: float = 1.0 - x * x
	return r * r   # round, easing to nothing at the sides (no hard edge)


## How far the bump sags over the skin below at `theta`, in pixels: uneven, more in some places than others.
func _bump_slip(theta: float) -> float:
	if bump.z <= 0.0 or bump_amount <= 0.0 or absf(theta - bump.x) >= bump.z:
		return 0.0
	return minf(bump_overhang * 0.92 * clampf(bump_amount, 0.0, 1.0) * _bump_reach(theta) * _bump_lumps(theta),
			bump_overhang * 0.95)


## The bump's lumpiness at `theta`: around 1, swelling and shrinking along it (`bump_uneven`).
func _bump_lumps(theta: float) -> float:
	var a: float = theta - bump.x
	return 1.0 + bump_uneven * (0.55 * sin(a * 8.0 + 0.6) + 0.3 * sin(a * 19.0 + 2.1))


## The bump's far edge row and height at `theta` (rows mirrored for an upward bump, so the far edge is its top when
## it sags down, its bottom when it reaches up): a wavy edge, taller where it's lumpier.
func _bump_local(theta: float) -> Vector2:
	var a: float = theta - bump.x
	var edge: float = -(bump.y + bump.w) if bump_up else bump.y
	return Vector2(edge + bump_uneven * 14.0 * sin(a * 11.0 + 1.3), bump.w * (0.75 + 0.25 * _bump_lumps(theta)))


## Skin point (theta, v) -> its row on the arm with the fold there bunched up: the band is squeezed and the skin
## next to it pulled in half the slack from either side, easing off over `fold_spread` px (stretched a little), so
## the rest of the arm stays put.
func fold_place(theta: float, v: float) -> float:
	var index: int = _fold_at(theta)
	if index < 0:
		return v
	return v + _fold_shift(_fold_local(index, theta), _fold_slack(index, theta), v)


## fold_place()'s inverse along the row (theta doesn't move): the map only moves a row by up to half the slack and
## keeps the order of rows, so halving the bracket finds it (24 rounds: under a thousandth of a pixel).
func fold_unplace(theta: float, row: float) -> float:
	var index: int = _fold_at(theta)
	if index < 0:
		return row
	var fold: Vector4 = _fold_local(index, theta)
	var slack: float = _fold_slack(index, theta)
	if slack <= 0.0:
		return row
	var low: float = row - slack
	var high: float = row + slack
	for i in 24:
		var middle: float = (low + high) * 0.5
		if middle + _fold_shift(fold, slack, middle) < row:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## How far skin row `v` moves along the arm for a fold with `slack` px taken up: +slack/2 at the band's top down to
## -slack/2 at its bottom, easing to nothing `fold_spread` px beyond it.
func _fold_shift(fold: Vector4, slack: float, v: float) -> float:
	var start: float = fold.y - fold.w * 0.5
	var end: float = start + fold.w
	if v < start:
		return slack * 0.5 * (1.0 - smoothstep(0.0, fold_spread, start - v))
	if v > end:
		return -slack * 0.5 * (1.0 - smoothstep(0.0, fold_spread, v - end))
	return slack * 0.5 - slack * (v - start) / fold.w


## How deep skin point (theta, v) is tucked into a fold, 0..1 (soft at the band's edges and the crease's ends).
func fold_hidden(theta: float, v: float) -> float:
	var index: int = _fold_at(theta)
	if index < 0:
		return 0.0
	var fold: Vector4 = _fold_local(index, theta)
	var t: float = (v - (fold.y - fold.w * 0.5)) / fold.w
	return fold_amounts[index] * _fold_reach(fold, theta) * smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.8, 1.0, t))


## The fold round the arm at `theta`, or -1.
func _fold_at(theta: float) -> int:
	for i in folds.size():
		if absf(theta - folds[i].x) < folds[i].z and i < fold_amounts.size() and fold_amounts[i] > 0.0:
			return i
	return -1


## 1 along the crease, easing to 0 at its ends.
func _fold_reach(fold: Vector4, theta: float) -> float:
	return 1.0 - smoothstep(0.5, 1.0, absf(theta - fold.x) / fold.z)


## Fold `index` as it is at `theta`: a scar, not a straight line — its middle row wanders up and down and its band
## widens and narrows along it (`fold_ragged`).
func _fold_local(index: int, theta: float) -> Vector4:
	var fold: Vector4 = folds[index]
	var a: float = theta - fold.x
	var seed: float = index * 2.3 + 0.7
	var middle: float = fold.y + fold_tilt * a + _fold_kink(a + fold.z) \
			+ fold_ragged * (0.6 * sin(a * 9.0 + seed) + 0.3 * sin(a * 23.0 + 2.0 * seed) + 0.15 * sin(a * 53.0 + 3.0 * seed))
	return Vector4(fold.x, middle, fold.z, fold.w * (1.0 + 0.3 * sin(a * 13.0 + 1.7 * seed)))


## The crease's breaks `along` radians from its start: straight between corners (FOLD_KINKS), px.
func _fold_kink(along: float) -> float:
	var at: float = clampf(along / FOLD_KINK_STEP, 0.0, FOLD_KINKS.size() - 1.001)
	var i: int = int(at)
	return fold_kinks * lerpf(FOLD_KINKS[i], FOLD_KINKS[i + 1], at - i)


## Fold `index`'s middle row at `theta` (its tilt, breaks and wander), clamped to its ends round the arm.
func fold_middle(index: int, theta: float) -> float:
	var fold: Vector4 = folds[index]
	return _fold_local(index, clampf(theta, fold.x - fold.z, fold.x + fold.z)).y


func _fold_slack(index: int, theta: float) -> float:
	var fold: Vector4 = _fold_local(index, theta)
	return maxf(0.0, fold.w - fold_closed_width) * clampf(fold_amounts[index], 0.0, 1.0) * _fold_reach(fold, theta)


## The skin point that slid to (theta, v): slide()'s inverse, by a few rounds.
func unslide(theta: float, v: float) -> Vector2:
	if drag == Vector2.ZERO:
		return Vector2(theta, skin_unrow(theta, v))
	var skin: Vector2 = Vector2(theta, skin_unrow(theta, v))
	for i in 24:   # each round cuts the error by about 0.86 × drag / drag_radius: 24 get under a tenth of a pixel
		var k: float = _slide_weight(skin.x, skin.y)
		var skin_theta: float = theta - drag.x / radius * k
		skin = Vector2(skin_theta, skin_unrow(skin_theta, v - drag.y * k))
	return skin


## The bare arm's skin point (theta, v) under a screen point, ignoring pulls and slides; past the silhouette
## clamped just inside it.
func rest_skin(point: Vector2) -> Vector2:
	var r: float = maxf(radius_at(point.y), 0.001)
	return Vector2(asin(clampf((point.x - center_at(point.y)) / r, -0.995, 0.995)), point.y)


func _slide_weight(theta: float, v: float) -> float:
	var d: Vector2 = Vector2((theta - drag_from.x) * radius, v - drag_from.y)
	return exp(-d.length_squared() / (drag_radius * drag_radius))


## Screen point plus how much ink lands there (0..1), as (x, y, ink).
func project(theta: float, v: float) -> Vector3:
	return project_layer(theta, v, skin_layer(theta, v))


## The part of a projection that only the folds and the bump change: (the skin point's row on the arm before the
## slide, how much of it shows: 0 tucked in a fold or under the bump .. 1). A slide doesn't change it, so a surface
## can keep it while the hand drags the skin.
func skin_layer(theta: float, v: float) -> Vector2:
	var folded: float = fold_place(theta, v)
	return Vector2(bump_place(theta, folded), (1.0 - fold_hidden(theta, v)) * (1.0 - bump_hidden(theta, folded)))


## project() from a skin_layer() already worked out.
func project_layer(theta: float, v: float, layer: Vector2) -> Vector3:
	var at_theta: float = theta
	var at_row: float = layer.x
	if drag != Vector2.ZERO:
		var k: float = _slide_weight(theta, v)
		at_theta += drag.x / radius * k
		at_row += drag.y * k
	if side == 0:   # no flap: the plain cylinder, inline (the common case, thousands of times a stroke)
		var r: float = radius_at(at_row)
		var face: float = cos(at_theta)
		return Vector3(center_at(at_row) + sin(at_theta) * r, at_row, ink_factor(face) * layer.y)
	var placed: Array = _place(at_theta, at_row)
	var point: Vector3 = placed[0]
	return Vector3(point.x, point.y, ink_factor(placed[1]) * layer.y)


## 1 where the skin faces the camera squarely enough to take ink, fading to 0 toward the silhouette.
func ink_factor(face: float) -> float:
	return smoothstep(cos(ink_max_angle), cos(ink_soft_angle), face)


## Skin point (theta, v) under a screen point, or Vector2.INF where there is no skin.
## The flap is sheared, so the row is found by a few rounds; the ends of the flap are clamped while
## searching and only the final row decides whether there is skin.
func screen_to_skin(point: Vector2) -> Vector2:
	var v: float = point.y
	var solved: Vector3 = Vector3.ZERO
	for i in 8:
		solved = _solve_row(point.x, v)
		if solved.z < 0.0 and side == 0:
			return Vector2.INF
		var next_v: float = point.y - _row_shear(v) * solved.y * solved.y
		var done: bool = absf(next_v - v) < 0.01
		v = next_v
		if done:
			break
	solved = _solve_row(point.x, v)
	if solved.z < 0.0:
		return Vector2.INF
	return unslide(solved.x, v)


## The grip point Q of row `v` in the pulled side's frame (x outward, y = z toward the camera).
func grip_point(v: float) -> Vector2:
	var r: float = radius_at(v)
	var rest: Vector2 = Vector2(sin(grip_angle), cos(grip_angle)) * r
	var full: Vector2 = Vector2(r + max_pull, hold_depth * r)
	return rest.lerp(full, amount * bulge_at(v))


## Where the grip is on screen (x, y), for the hand. Mirrored to the pulled side.
func grip_screen() -> Vector2:
	var q: Vector2 = grip_point(grip_v)
	return Vector2(q.x * _side_sign() + center_at(grip_v), grip_v + _row_shear(grip_v))


## Angle of the tangent point T in row `v` (pulled side's frame); >= grip_angle when nothing is pulled.
func tangent_angle(v: float) -> float:
	if side == 0 or amount <= 0.0:
		return grip_angle
	var r: float = radius_at(v)
	var q: Vector2 = grip_point(v)
	var distance: float = q.length()
	if distance <= r:
		return grip_angle
	return minf(grip_angle, atan2(q.x, q.y) - acos(r / distance))


## Copies the shape into an `arm_skin.gdshader` material.
func apply_to(material: ShaderMaterial) -> void:
	material.set_shader_parameter("radius", radius)
	if _profile_texture == null:
		var pairs: PackedFloat32Array = PackedFloat32Array()
		for i in _radii.size():
			pairs.append(_radii[i])
			pairs.append(_centers[i])
		var image: Image = Image.create_from_data(_radii.size(), 1, false, Image.FORMAT_RGF, pairs.to_byte_array())
		_profile_texture = ImageTexture.create_from_image(image)
		material.set_shader_parameter("profile_tex", _profile_texture)
	material.set_shader_parameter("profile_top", _profile_top)
	material.set_shader_parameter("profile_step", _profile_step)
	material.set_shader_parameter("profile_count", _radii.size())
	material.set_shader_parameter("photo_shading", PROFILE.shading)
	material.set_shader_parameter("hand_from", PROFILE.wrist)
	material.set_shader_parameter("fade_top_from", _profile_top)
	material.set_shader_parameter("arm_length", length)
	material.set_shader_parameter("grip_angle", grip_angle)
	material.set_shader_parameter("max_pull", max_pull)
	material.set_shader_parameter("hold_depth", hold_depth)
	material.set_shader_parameter("grip_bulge", grip_bulge)
	material.set_shader_parameter("bulge_spread", bulge_spread)
	material.set_shader_parameter("grip_v", grip_v)
	material.set_shader_parameter("pull_side", float(side))
	material.set_shader_parameter("pull_amount", amount)
	material.set_shader_parameter("pull_shear", shear)
	material.set_shader_parameter("drag_from", drag_from)
	material.set_shader_parameter("drag", drag)
	material.set_shader_parameter("drag_radius", drag_radius)
	for i in 2:
		var fold: Vector4 = folds[i] if i < folds.size() else Vector4(0.0, 0.0, 0.0001, 1.0)
		var amount: float = fold_amounts[i] if i < fold_amounts.size() and i < folds.size() else 0.0
		material.set_shader_parameter("fold_%d" % i, fold)
		material.set_shader_parameter("fold_amount_%d" % i, amount)
	material.set_shader_parameter("fold_closed_width", fold_closed_width)
	material.set_shader_parameter("fold_spread", fold_spread)
	material.set_shader_parameter("bump", bump)
	material.set_shader_parameter("bump_overhang", bump_overhang)
	material.set_shader_parameter("bump_amount", bump_amount)
	material.set_shader_parameter("bump_uneven", bump_uneven)
	material.set_shader_parameter("bump_up", bump_up)
	material.set_shader_parameter("fold_ragged", fold_ragged)
	material.set_shader_parameter("fold_tilt", fold_tilt)
	material.set_shader_parameter("fold_kinks", fold_kinks)


func _side_sign() -> float:
	return -1.0 if side < 0 else 1.0


func _row_shear(v: float) -> float:
	return shear * bulge_at(v) if side != 0 else 0.0


## [Vector3 screen point, float facing].
func _place(theta: float, v: float) -> Array:
	var r: float = radius_at(v)
	var s: float = _side_sign()
	var local: float = theta * s # angle in the pulled side's frame
	var t_angle: float = tangent_angle(v)
	if side == 0 or local <= t_angle or local > grip_angle:
		return [Vector3(center_at(v) + sin(theta) * r, v, cos(theta) * r), cos(theta)]
	var tangent: Vector2 = Vector2(sin(t_angle), cos(t_angle)) * r
	var t: float = _ease_out(t_angle, v, (local - t_angle) / (grip_angle - t_angle))
	var on_flap: Vector2 = tangent.lerp(grip_point(v), t)
	return [Vector3(on_flap.x * s + center_at(v), v + _row_shear(v) * t * t, on_flap.y), cos(t_angle)]


## Skin taken off the arm at T starts unstretched: the first bit of arc covers as much screen as it did
## on the arm, the rest stretches more. Share of the arc `share` -> share of the flap's length.
func _ease_out(t_angle: float, v: float, share: float) -> float:
	var k: float = _start_density(t_angle, v)
	return k * share + (1.0 - k) * share * share


func _ease_back(t_angle: float, v: float, t: float) -> float:
	var k: float = _start_density(t_angle, v)
	if absf(1.0 - k) < 0.0001:
		return t
	return (-k + sqrt(maxf(0.0, k * k + 4.0 * (1.0 - k) * t))) / (2.0 * (1.0 - k))


## Arc length over flap length, kept where the easing stays monotonic.
func _start_density(t_angle: float, v: float) -> float:
	var r: float = radius_at(v)
	var flap: float = (grip_point(v) - Vector2(sin(t_angle), cos(t_angle)) * r).length()
	return clampf(r * (grip_angle - t_angle) / maxf(flap, 0.0001), 0.2, 2.0)


## In row `v`: (theta, share of the way along the flap, 1 or -1 when there is no skin) under screen x.
## Past the flap's end the result is clamped to its end, flagged as no skin.
func _solve_row(screen_x: float, v: float) -> Vector3:
	var x: float = screen_x - center_at(v)   # across from the row's own middle
	var r: float = radius_at(v)
	var s: float = _side_sign()
	var t_angle: float = tangent_angle(v)
	var flap_visible: bool = side != 0 and t_angle < grip_angle and t_angle < PI * 0.5
	var local_x: float = x * s
	if flap_visible:
		var tangent_x: float = sin(t_angle) * r
		if local_x > tangent_x:
			var grip_x: float = grip_point(v).x
			var t: float = (local_x - tangent_x) / maxf(grip_x - tangent_x, 0.0001)
			var ok: float = 1.0 if t <= 1.0 else -1.0
			t = minf(t, 1.0)
			var share: float = _ease_back(t_angle, v, t)
			return Vector3((t_angle + share * (grip_angle - t_angle)) * s, t, ok)
	if absf(x) > r:
		return Vector3(signf(x) * PI * 0.5, 0.0, -1.0)
	return Vector3(asin(x / r), 0.0, 1.0)
