class_name ArmSurface
extends SkinSurface
## The forearm, seen straight on and filling the screen top to bottom. The stencil is the unwrapped skin
## (`theta` -wrap..wrap around the arm, `stencil_height` px along it), so its sides hide behind the
## silhouettes. WASD (`hand_*`) move the artist's left hand over the screen; Space (`hand_wave`) grips the skin
## under it and the hand drags it along, any way, until Space is pressed again: the skin around the grip slides over the arm (up to
## `max_drag` px, fading out over `drag_radius`), the stencil and ink with it, so skin from behind a silhouette
## can be slid into view and inked. Let go (Space again) and it slides back.
## The math is `ArmShape` (and its copy in `arm_skin.gdshader`).


## The left hand holding a paper towel asks the session to throw it in the bin (Space).
signal paper_discard_requested

const MECHANICS: Mechanics = preload("res://data/mechanics.tres")
const PAPER_STACK: Script = preload("res://tattoo/blood/paper_stack.gd")
const PAPER_IN_HAND: Script = preload("res://tattoo/blood/paper_in_hand.gd")
const HAND_ALBEDO: String = "res://art/characters/client_hand/hand_albedo.png"
const HAND_NORMAL: String = "res://art/characters/client_hand/hand_normal.png"

@export_group("Shape")
@export var radius: float = 210.0
## How long the arm's mesh is built (it runs 1.8 times this, centred on the stencil: shoulder to past the hand). The
## outline itself is `ArmShape.PROFILE_V` / `PROFILE_S`.
@export var arm_length: float = 1800.0

@export_group("Stencil")
## How far around the arm the stencil reaches on each side of the front line, in degrees.
@export var wrap_angle: float = 120.0
## How much of the arm's length the stencil covers, in pixels, centred.
@export var stencil_height: float = 700.0

@export_group("Ink")
## Ink starts thinning where the skin turns this far from the camera, in degrees...
@export var ink_soft_angle: float = 50.0
## ...and stops landing here.
@export var ink_max_angle: float = 62.0

@export_group("Hand")
## How fast the left hand moves, pixels per second, and how quickly it gets there (per second).
@export var hand_speed: float = 650.0
@export var hand_acceleration: float = 12.0
## Farthest the gripped skin is dragged from where it was taken, in pixels.
@export var max_drag: float = 160.0
## Share of the hand's footprint (round its middle) that keeps ink off the skin under it.
@export_range(0.1, 1.0) var hand_block_scale: float = 0.55
## The view scrolls along the whole arm (the session asks for it with `scroll_view()` when the machine nears the top
## or bottom of the screen), eased at `scroll_rate`, from `scroll_min` (the shoulder) to `scroll_max` (the hand);
## 0 = the stencil in the middle.
@export var scroll_rate: float = 10.0
@export var scroll_min: float = -1300.0
@export var scroll_max: float = 700.0
## The client's hand picture: the row its top (the wrist) sits at, and where the wrist is in the picture (its width
## and middle, in the picture's pixels), so it lines up with the arm.
@export var hand_top: float = 460.0
@export var hand_wrist_width: float = 235.0
@export var hand_wrist_center: float = 322.0
## The hand's size against a wrist as wide as the arm's (1: as wide; below 1 smaller).
@export var hand_scale: float = 0.667
## Out of focus toward the wrist and over the hand (a screen blur): from nothing at the arm's row `defocus_from` to
## `defocus_radius` px at `defocus_full` and on, and darkening smoothly from `defocus_from` down to `defocus_dark_to`
## (`defocus_darken` there and below).
@export var defocus_from: float = 360.0
@export var defocus_full: float = 700.0
@export var defocus_radius: float = 13.0
@export_range(0.0, 1.0) var defocus_darken: float = 0.6
@export var defocus_dark_to: float = 950.0
## The wet paper towel wipes blood over this radius round the palm (skin pixels).
@export var wipe_radius: float = 42.0
## How far past the silhouette (on the background) the hand can still take the side of the skin, in pixels.
@export var side_grab_margin: float = 70.0
## How far around the grip the skin moves along, in pixels (a gaussian; keep it over 1.2 × max_drag, or the skin
## folds).
@export var drag_radius: float = 200.0
## A grip at least this far round the arm (degrees from the front line) takes the side: pulling outward then lifts
## it off the arm as a taut flap facing the camera (`ArmShape`'s pull, up to `max_pull`), up and down tilt it;
## closer to the front the skin slides.
@export var flap_grip_angle: float = 40.0
## How quickly let-go skin slides back (per second, exponential).
## Short folds across the arm (`ArmShape.folds`): skin tucked into one takes no ink until it's pulled smooth.
@export var fold_enabled: bool = true
## Each fold: (degrees round the arm of its middle, its middle row in px from the arm's centre (down positive),
## half its length round the arm in degrees, skin px tucked in). Two at most; they mustn't overlap round the arm.
@export var folds: Array[Vector4] = [Vector4(-30.0, -90.0, 22.0, 60.0), Vector4(32.0, 110.0, 20.0, 60.0)]
## A fat bump that sags over the stencil (`ArmShape.bump`): (degrees round the arm of its middle, its top row,
## half its width in degrees, its height in px); the skin below it it covers, in px. Stretching the skin near it
## flattens it (like the folds: any pull counts). Off with `bump_enabled`.
@export var bump_enabled: bool = true
@export var bump: Vector4 = Vector4(-5.0, 235.0, 24.0, 60.0)
## The bump reaches up over the skin above it (here: excess skin lying over the stencil's bottom) instead of sagging down.
@export var bump_up: bool = true
@export var bump_overhang: float = 45.0
## How uneven the bump is (0: an even dome), and how ragged the folds' creases are (px they wander; 0: straight).
@export var bump_uneven: float = 0.5
@export var fold_ragged: float = 9.0
## Width of a closed fold on the arm, in pixels.
@export var fold_closed: float = 8.0
## How far beyond a fold the skin is drawn in toward it, in pixels (the rest of the arm stays put).
@export var fold_spread: float = 70.0
## Share of `max_drag` (pulling away from the fold along the arm) that smooths it out fully; pulls any other way
## count this much.
@export var fold_open_at: float = 0.6
@export_range(0.0, 1.0) var fold_side_share: float = 0.3
## How quickly it follows (per second).
@export var fold_rate: float = 8.0
## The taut patch round a slide's grip reaches this many `drag_radius`es; a flap's taut band along the arm this
## many of its `bulge_spread`s.
@export var tension_spread: float = 0.55
## How far from a fold or the bump (past it) a slide still smooths it, in `drag_radius`es.
@export var fold_reach_spread: float = 0.8
@export var drag_return_rate: float = 8.0

@export_group("Pull")
## Where the fingers hold the skin, in degrees from the front line (behind the silhouette).
@export var grip_angle: float = 115.0
## How far past the silhouette a full pull drags the skin, in pixels.
@export var max_pull: float = 160.0
## How far toward the camera a full pull brings the grip, in radii (more = flatter flap).
@export var hold_depth: float = 0.25
## Share of the pull lost at the top and bottom of the screen.
@export_range(0.0, 1.0) var grip_bulge: float = 0.35
@export var bulge_spread: float = 300.0
## Steepest pull, in degrees from horizontal.
@export var max_pull_angle: float = 60.0
@export var pull_rate: float = 4.5
@export var return_rate: float = 10.0
## How fast W / S tilt the pull, degrees per second.
@export var tilt_speed: float = 80.0

## Grid of the arm mesh (around, along).
const MESH_STEPS: Vector2i = Vector2i(288, 400)

var shape: ArmShape = ArmShape.new()
var pull: SkinPull = SkinPull.new()

var _material: ShaderMaterial
var _wrap: float = 0.0
var _highlight: float = 0.0
## Which sides hide unfinished stencil, found when a ping starts: (left, right), 0 or 1.
var _hidden_left_right: Vector2 = Vector2.ZERO
## project() of every cell centre, filled as cells are asked for and dropped when the skin moves (a pull, the
## arm's place on screen): a stroke projects hundreds of cells a frame, mostly the same ones again.
var _projected: PackedVector3Array = PackedVector3Array()
var _projected_known: PackedByteArray = PackedByteArray()
## The pull the cache was filled for: side, amount, shear, grip row.
var _projected_pull: Vector4 = Vector4.INF
var _projected_from: Vector2 = Vector2.INF
var _projected_fold: PackedFloat32Array = PackedFloat32Array()
var _projected_bump: float = -1.0
## Each cell centre's ArmShape.skin_layer() (row before the slide, how much shows), and which are known: kept while
## the slide moves, dropped when a fold or the bump changes.
var _layers: PackedVector2Array = PackedVector2Array()
var _layers_known: PackedByteArray = PackedByteArray()
## ArmShape.ink_factor()'s smoothstep edges, for place_cell_at().
var _ink_low: float = 0.0
var _ink_high: float = 1.0
## The left hand: where it is (this control's pixels) and how fast it moves.
var _hand_position: Vector2 = Vector2.ZERO
var _hand_previous: Vector2 = Vector2.ZERO
## The left hand holds a wet paper towel (wipes blood, doesn't pull); `hand_locked` freezes it (the bin).
var holding_paper: bool = false
var hand_locked: bool = false
var _blood: BloodLayer
var _paper_stack: Node2D
var _paper: Node2D
var _defocus: ColorRect
var _defocus_copy: BackBufferCopy
## How far down the arm the view looks, in pixels (negative: up).
var _pan: float = 0.0
## Where the scroll is heading.
var _scroll_target: float = 0.0
## The arm's centre on screen as cached projections need it (`_refresh_center()`).
var _center_offset: Vector3 = Vector3.ZERO
var _hand_velocity: Vector2 = Vector2.ZERO
## Holding the skin: the gripped skin point (theta, v) and where on screen the hand took it.
var _gripping: bool = false
var _grip_skin: Vector2 = Vector2.ZERO
var _grip_screen: Vector2 = Vector2.ZERO
## The grip took the side: the hand lifts a flap instead of sliding the skin.
var _grip_flap: bool = false
## While the skin rests, the cache is filled ahead a little every frame (rows from the middle out), so a sweep
## into fresh skin doesn't project hundreds of new cells in one frame.
const WARM_BUDGET_USEC: int = 1500
var _warm_cursor: int = 0
var _warm_rows: PackedInt32Array = PackedInt32Array()

@onready var _background: ColorRect = $Background
@onready var _view_viewport: SubViewport = $View3D/Viewport
@onready var _camera: Camera3D = $View3D/Viewport/Camera
@onready var _arm: MeshInstance3D = $View3D/Viewport/Arm
@onready var _ink_layer: SubViewport = $InkLayer
@onready var _stencil: Control = $InkLayer/Stencil
@onready var _hand: Node2D = $Hand
@onready var _key_light: DirectionalLight3D = $View3D/Viewport/Key
@onready var _fill_light: DirectionalLight3D = $View3D/Viewport/Fill
@onready var _stretch_sound: AudioStreamPlayer = $StretchSound
@onready var _release_sound: AudioStreamPlayer = $ReleaseSound


func _ready() -> void:
	_apply_exports()
	item_rect_changed.connect(_forget_projections)
	# The lamp up and to the left, as for the wet ink's highlight; a warm fill from the lower right.
	_key_light.look_at_from_position(Vector3(-600.0, 700.0, 900.0), Vector3.ZERO)
	_fill_light.look_at_from_position(Vector3(900.0, -250.0, 500.0), Vector3.ZERO)
	_arm.mesh = _build_mesh()
	_material = _arm.material_override
	_material.set_shader_parameter("ink_layer", _ink_layer.get_texture())
	_material.set_shader_parameter("wrap_angle", _wrap)
	_material.set_shader_parameter("stencil_height", stencil_height)
	shape.apply_to(_material)
	_build_client_hand()
	_build_defocus()
	_hand.visible = false
	_reset_hand.call_deferred()
	# blood on the skin (look only) and the wet paper towels that wipe it
	_blood = BloodLayer.new()
	_blood.name = "Blood"
	_ink_layer.add_child(_blood)
	_paper_stack = PAPER_STACK.new()
	_paper_stack.name = "PaperStack"
	add_child(_paper_stack)
	move_child(_paper_stack, _hand.get_index())
	_paper_stack.visible = MECHANICS.blood
	_paper = PAPER_IN_HAND.new()
	_paper.name = "Paper"
	_paper.visible = false
	_hand.add_child(_paper)
	resized.connect(_place_paper_stack)
	_place_paper_stack.call_deferred()


func setup(stencil: StencilData) -> void:
	super(stencil)
	_projected.resize(grid.x * grid.y)
	_projected_known.resize(grid.x * grid.y)
	_layers.resize(grid.x * grid.y)
	_layers_known.resize(grid.x * grid.y)
	_layers_known.fill(0)
	_warm_rows.clear()
	var middle: int = grid.y / 2
	_warm_rows.append(middle)   # the middle row first, then outward
	for d in range(1, grid.y):
		for row in [middle - d, middle + d]:
			if row >= 0 and row < grid.y:
				_warm_rows.append(row)
	_forget_projections()
	if not stencil.parts.is_empty():
		_ink_layer.size = Vector2i(stencil.parts[0].texture.get_size())


func stencil_layer() -> Control:
	return _stencil


func to_cell(screen_point: Vector2) -> Vector2:
	var skin: Vector2 = shape.screen_to_skin(screen_point - _center())
	if not skin.is_finite():
		return Vector2.INF
	return _skin_to_cell(skin)


func project(cell: Vector2) -> Vector3:
	# a cell centre: from the cache while the skin stays put
	var x: int = int(cell.x)
	var y: int = int(cell.y)
	if cell.x - x == 0.5 and cell.y - y == 0.5 and x >= 0 and y >= 0 and x < grid.x and y < grid.y \
			and not _projected.is_empty():
		var index: int = y * grid.x + x
		if _projected_known[index] == 0:
			_projected[index] = _place_cell(cell)
			_projected_known[index] = 1
		return _projected[index] + _center_offset
	return _project_now(cell)


func _project_now(cell: Vector2) -> Vector3:
	var center: Vector2 = _center()
	return _place_cell(cell) + Vector3(center.x, center.y, 0.0)


## A cell centre placed on the arm, relative to the arm's centre (the cache keeps these, so panning the view
## doesn't drop it).
func _place_cell(cell: Vector2) -> Vector3:
	var skin: Vector2 = _cell_to_skin(cell)
	var x: int = int(cell.x)
	var y: int = int(cell.y)
	if cell.x - x == 0.5 and cell.y - y == 0.5 and x >= 0 and y >= 0 and x < grid.x and y < grid.y \
			and not _layers.is_empty():
		# the folds' and the bump's part, kept while only the slide moves (the costly part of a projection)
		var index: int = y * grid.x + x
		if _layers_known[index] == 0:
			_layers[index] = shape.skin_layer(skin.x, skin.y)
			_layers_known[index] = 1
		return shape.project_layer(skin.x, skin.y, _layers[index])
	return shape.project(skin.x, skin.y)



## Cell (x, y)'s centre placed on the arm, relative to the arm's centre, through the cache: everything inline for
## the plain arm (no flap), since a stroke over sliding skin projects a thousand cells a frame.
func place_cell_at(x: int, y: int) -> Vector3:
	var index: int = y * grid.x + x
	if _projected_known[index] == 1:
		return _projected[index]
	var theta: float = ((x + 0.5) / grid.x * 2.0 - 1.0) * _wrap
	var v: float = ((y + 0.5) / grid.y - 0.5) * stencil_height
	var layer: Vector2
	if _layers_known[index] == 1:
		layer = _layers[index]
	else:
		layer = shape.skin_layer(theta, v)
		_layers[index] = layer
		_layers_known[index] = 1
	var placed: Vector3
	if shape.side == 0:
		var at_theta: float = theta
		var at_row: float = layer.x
		if shape.drag != Vector2.ZERO:
			var dx: float = (theta - shape.drag_from.x) * shape.radius
			var dy: float = v - shape.drag_from.y
			var k: float = exp(-(dx * dx + dy * dy) / (shape.drag_radius * shape.drag_radius))
			at_theta += shape.drag.x / shape.radius * k
			at_row += shape.drag.y * k
		var r: float = shape.radius_at(at_row)
		placed = Vector3(sin(at_theta) * r, at_row, smoothstep(_ink_low, _ink_high, cos(at_theta)) * layer.y)
	else:
		placed = shape.project_layer(theta, v, layer)
	_projected[index] = placed
	_projected_known[index] = 1
	return placed


func cached_projections() -> Array:
	if _projected.is_empty():
		return []
	return [_projected, _projected_known, _center_offset]


func pixels_per_cell() -> float:
	return 2.0 * _wrap * radius / grid.x


## The preimage of a screen circle is a sheared ellipse on stretched skin: bound it with the local Jacobian.
func cells_within(cell: Vector2, radius_px: float) -> Vector2:
	# Walk out along each axis over cell centres until the screen distance passes the radius: exact where the skin
	# is bunched (a fold squeezes many rows into a few pixels, which the local Jacobian blew up to the cap).
	var limit: int = ceili(3.0 * radius_px / pixels_per_cell())
	var center: Vector2 = Vector2(floorf(cell.x) + 0.5, floorf(cell.y) + 0.5)
	var here: Vector3 = project(center)
	var reach: Vector2 = Vector2.ONE
	for axis in 2:
		for direction: float in [-1.0, 1.0]:
			var step: Vector2 = Vector2(direction, 0.0) if axis == 0 else Vector2(0.0, direction)
			var k: int = 1
			while k < limit:
				var there: Vector3 = project(center + step * k)
				# rows by how far down the screen they go, columns by how far across: a slide shears the other way,
				# which doesn't bring a row or column closer
				var gone: float = absf(there.x - here.x) if axis == 0 else absf(there.y - here.y)
				if gone > radius_px:
					break
				k += 1
			reach[axis] = maxf(reach[axis], minf(ceilf(k * 1.2) + 2.0, limit))
	return reach


## The brush's screen vectors on the skin, through the local inverse Jacobian (so it skews where the skin is
## stretched); each kept within a few brush lengths where the skin turns edge-on.
func brush_basis(cell: Vector2, along_px: Vector2, across_px: Vector2) -> Transform2D:
	var here: Vector3 = project(cell)
	var du: Vector3 = project(cell + Vector2(1.0, 0.0)) - here
	var dv: Vector3 = project(cell + Vector2(0.0, 1.0)) - here
	var det: float = du.x * dv.y - dv.x * du.y
	var limit: float = 3.0 * along_px.length() / pixels_per_cell()
	if absf(det) < 0.0001:
		return Transform2D(Vector2(limit, 0.0), Vector2(0.0, limit * across_px.length() / maxf(along_px.length(), 0.001)), Vector2.ZERO)
	# Rows of the inverse Jacobian: how much u and v change per screen pixel.
	var u_row: Vector2 = Vector2(dv.y, -dv.x) / det
	var v_row: Vector2 = Vector2(-du.y, du.x) / det
	var along: Vector2 = Vector2(u_row.dot(along_px), v_row.dot(along_px)).limit_length(limit)
	var across: Vector2 = Vector2(u_row.dot(across_px), v_row.dot(across_px)).limit_length(limit)
	return Transform2D(along, across, Vector2.ZERO)


## The ink is drawn into the skin's own layer, as big as the stencil image.
func ink_pixels() -> Vector2:
	return Vector2(_ink_layer.size)


func supports_tasks() -> bool:
	return false


func hint() -> String:
	if MECHANICS.blood:
		return "WASD — левая рука, пробел — тянуть кожу или взять салфетку (кровь вытирать ей); машинка у края экрана — вдоль руки"
	return "WASD — левая рука, пробел — держать и тянуть кожу; машинка у края экрана — вдоль руки"


func update_surface(delta: float, active: bool) -> void:
	_refresh_center()
	var can_use: bool = active and not Transition.is_busy and not hand_locked
	if _hand_position == Vector2.ZERO and size != Vector2.ZERO:
		_reset_hand()
	# the hand: WASD with a little inertia, kept on the screen
	var wanted: Vector2 = Input.get_vector("hand_left", "hand_right", "hand_up", "hand_down") if can_use else Vector2.ZERO
	_hand_velocity = _hand_velocity.lerp(wanted * hand_speed, 1.0 - exp(-hand_acceleration * delta))
	_hand_position = (_hand_position + _hand_velocity * delta).clamp(Vector2.ZERO, size)
	_update_pan(delta)
	_refresh_center()
	# Space grips the skin under the hand and the hand drags it (no farther than max_drag); Space again lets go
	var toggled: bool = can_use and Input.is_action_just_pressed("hand_wave")
	var before: Vector2 = _hand_previous
	_hand_previous = _hand_position
	_paper_stack.hovered = not holding_paper and not _gripping and _paper_stack.visible \
			and _paper_stack.rect.grow(20.0).has_point(_hand_position)
	if holding_paper:
		# with a paper towel the hand wipes blood instead of pulling: Space sends the paper to the bin
		_wipe(_hand_position.distance_to(before))
		if toggled:
			paper_discard_requested.emit()
		toggled = false
	elif toggled and _paper_stack.hovered:
		holding_paper = true
		_paper.stained = 0.0
		_paper.visible = true
		_stretch_sound.play()
		toggled = false
	if toggled and not _gripping:
		var skin: Vector2 = shape.screen_to_skin(_arm_point(_hand_position))
		if not skin.is_finite():
			skin = _side_grab(_arm_point(_hand_position))
		if skin.is_finite():
			_gripping = true
			_grip_skin = skin
			_grip_screen = _hand_position
			_grip_flap = absf(skin.x) >= deg_to_rad(flap_grip_angle)
			shape.drag_from = skin
			shape.drag = Vector2.ZERO
			if _grip_flap:
				pull.release()
				shape.grip_v = skin.y   # the flap bulges most at the hand's row
				_forget_projections()
			_stretch_sound.play()
	elif toggled and _gripping:
		_gripping = false
		if shape.drag.length() > max_drag * 0.3 or pull.amount > 0.3:
			_release_sound.play()
	if _gripping:
		_hand_position = _grip_screen + (_hand_position - _grip_screen).limit_length(max_drag)
		if _grip_flap:
			_lift_flap()
			_slide_side_grip()
		else:
			# the gripped skin goes where the hand is: its bare-arm place under the hand, minus where it came from
			var target: Vector2 = shape.rest_skin(_arm_point(_hand_position))
			shape.drag = Vector2((target.x - _grip_skin.x) * radius,
					target.y - shape.skin_row(_grip_skin.x, _grip_skin.y)).limit_length(max_drag)
	else:
		shape.drag = shape.drag * exp(-drag_return_rate * delta)
		if shape.drag.length() < 0.2:
			shape.drag = Vector2.ZERO
		pull.update(delta, false, false, false, false)   # a let-go flap slides back
	_update_fold(delta)
	_blood.spawning = MECHANICS.blood
	_blood.update(delta)
	_sync_pull()
	_place_hand()
	if shape.drag == Vector2.ZERO and pull.amount <= 0.0:
		_warm_projections()


## Just outside the silhouette (within `side_grab_margin` of it, on the background) the hand still takes the skin:
## the side at the silhouette of that row. INF farther out.
func _side_grab(point: Vector2) -> Vector2:
	var past: float = absf(point.x) - shape.radius_at(point.y)
	if past < 0.0 or past > side_grab_margin:
		return Vector2.INF
	return shape.rest_skin(point)


## A side grip moved inward or up and down (rather than out) slides the skin too, like a grip in front: the inward
## part of the hand's way and the up-down part the flap doesn't use for its tilt.
func _slide_side_grip() -> void:
	var offset: Vector2 = _hand_position - _grip_screen
	var side: float = -1.0 if _grip_skin.x < 0.0 else 1.0
	var inward: float = minf(offset.x * side, 0.0) * side
	var way: Vector2 = Vector2(inward, offset.y * (1.0 - pull.amount))
	var base: Vector2 = shape.rest_skin(_arm_point(_grip_screen))
	var target: Vector2 = shape.rest_skin(_arm_point(_grip_screen + way))
	shape.drag = Vector2((target.x - base.x) * radius, target.y - base.y).limit_length(max_drag)


## A side grip: how far the hand went outward lifts the flap (`max_pull` = a full one), how far up or down tilts it
## (the grip follows the hand: the shear is the hand's height over the grip).
func _lift_flap() -> void:
	var offset: Vector2 = _hand_position - _grip_screen
	var side: int = -1 if _grip_skin.x < 0.0 else 1
	var outward: float = maxf(0.0, offset.x * side)
	pull.side = side
	pull.holding = true
	pull.amount = clampf(outward / maxf(max_pull, 1.0), 0.0, 1.0)
	pull.angle = clampf(atan2(-offset.y, maxf(outward, 1.0)), -pull.max_angle, pull.max_angle)


## Projects cells ahead into the cache for at most WARM_BUDGET_USEC.
func _warm_projections() -> void:
	var total: int = grid.x * grid.y
	if _projected.is_empty() or _warm_cursor >= total:
		return
	var until: int = Time.get_ticks_usec() + WARM_BUDGET_USEC
	while _warm_cursor < total:
		var row: int = _warm_rows[_warm_cursor / grid.x]
		var column: int = _warm_cursor % grid.x
		_warm_cursor += 1
		var index: int = row * grid.x + column
		if _projected_known[index] == 0:
			_projected[index] = _place_cell(Vector2(column + 0.5, row + 0.5))
			_projected_known[index] = 1
		if _warm_cursor % 64 == 0 and Time.get_ticks_usec() > until:
			return


## A ping also lights up the silhouette on each side that still hides unfinished stencil, so it's
## clear which way to pull.
func set_highlight(value: float, canvas: InkCanvas) -> void:
	if value > 0.0 and _highlight <= 0.0:
		_hidden_left_right = _find_hidden(canvas)
	_highlight = value
	_material.set_shader_parameter("hint_left", _hidden_left_right.x * value)
	_material.set_shader_parameter("hint_right", _hidden_left_right.y * value)


func _find_hidden(canvas: InkCanvas) -> Vector2:
	var found: Vector2 = Vector2.ZERO
	var out_of_reach: float = shape.ink_soft_angle
	for part in canvas.part_count():
		if canvas.is_part_done(part):
			continue
		for cell in canvas.part_cells(part):
			if canvas.cell_ink(cell) >= 1.0:
				continue
			var theta: float = _cell_to_skin(Vector2(cell % grid.x + 0.5, 0.0)).x
			if theta < -out_of_reach:
				found.x = 1.0
			elif theta > out_of_reach:
				found.y = 1.0
	return found


func release() -> void:
	_pan = 0.0
	_scroll_target = 0.0
	hand_locked = false
	finish_paper()
	_blood.clear()
	pull.release()
	_gripping = false
	shape.drag = Vector2.ZERO
	_reset_hand()
	_sync_pull()


## The view eases toward where the scroll is heading. The left hand and a held grip ride along with the arm, so
## the view moving never pulls the skin by itself.
func _update_pan(delta: float) -> void:
	var before: float = _pan
	_pan = lerpf(_pan, _scroll_target, 1.0 - exp(-scroll_rate * delta))
	if absf(_pan - _scroll_target) < 0.3:
		_pan = _scroll_target
	var moved: float = _pan - before
	if moved != 0.0 and _gripping:
		_grip_screen.y -= moved
		_hand_position.y -= moved


## Scrolls the view along the arm by `amount` px (down positive), within `scroll_min`..`scroll_max`.
func scroll_view(amount: float) -> void:
	_scroll_target = clampf(_scroll_target + amount, scroll_min, scroll_max)


## The hand rests low on the left of the arm, out of the stencil's way.
func _reset_hand() -> void:
	_hand_position = size * 0.5 + Vector2(-radius * 0.8, size.y * 0.3)
	_hand_velocity = Vector2.ZERO
	_place_hand()


func _process(_delta: float) -> void:
	_update_defocus()
	var view_size: Vector2 = size
	if view_size.y > 0.0:
		_camera.size = view_size.y
	_camera.position.y = -_pan   # the view's y is up: looking lower down the arm
	(_background.material as ShaderMaterial).set_shader_parameter("size", view_size)


func _sync_pull() -> void:
	shape.side = pull.side
	shape.amount = pull.amount
	shape.shear = pull.shear(max_pull)
	var pulled: Vector4 = Vector4(shape.amount + shape.side * 10.0, shape.shear, shape.drag.x, shape.drag.y)
	if pulled != _projected_pull or (shape.drag != Vector2.ZERO and _projected_from != shape.drag_from) \
			or shape.fold_amounts != _projected_fold or shape.bump_amount != _projected_bump:
		if shape.fold_amounts != _projected_fold or shape.bump_amount != _projected_bump:
			_layers_known.fill(0)   # the folds or the bump changed: their part goes too
		_projected_fold = shape.fold_amounts.duplicate()
		_projected_bump = shape.bump_amount
		_projected_pull = pulled
		_projected_from = shape.drag_from
		_forget_projections()
	shape.apply_to(_material)


func note_ink(canvas: InkCanvas) -> void:
	if not MECHANICS.blood:
		return
	var scale: Vector2 = Vector2(_ink_layer.size) / Vector2(grid)
	for dab in canvas.dabs:
		_blood.note_fresh((dab[0] as Vector2) * scale)
	for stroke in canvas.strokes:
		_blood.note_fresh((stroke[1] as Vector2) * scale)


## The paper towel went into the bin: the hand is empty again.
func finish_paper() -> void:
	holding_paper = false
	_paper.visible = false
	_paper.stained = 0.0


## How bloody the paper in the hand is, 0 .. 1.
func paper_stain() -> float:
	return _paper.stained if holding_paper else 0.0


## The skin under the palm loses the blood the hand rubs over (`moved` px this frame).
func _wipe(moved: float) -> void:
	if moved <= 0.0:
		return
	var skin: Vector2 = shape.screen_to_skin(_arm_point(_hand_position))
	if not skin.is_finite():
		return
	var layer: Vector2 = Vector2(_ink_layer.size)
	var at: Vector2 = Vector2((skin.x / _wrap + 1.0) * 0.5 * layer.x, (skin.y / stencil_height + 0.5) * layer.y)
	var taken: float = _blood.wipe(at, wipe_radius, moved)
	_paper.stained += taken * 0.12


func _place_paper_stack() -> void:
	_paper_stack.rect = Rect2(28.0, size.y * 0.62, 150.0, 90.0)


func has_tension() -> bool:
	return true


## Skin round a slide's grip is taut by how far it was dragged (over a gaussian a little wider than the slide);
## a lifted flap tightens its side by the flap's amount, most at the hand's row. Holding
## without moving tightens nothing.
func tension_at(screen_point: Vector2) -> float:
	var skin: Vector2 = shape.screen_to_skin(screen_point - _center())
	if not skin.is_finite():
		return 0.0
	var tension: float = 0.0
	if shape.drag != Vector2.ZERO:
		var reach: float = shape.drag_radius * tension_spread
		var d: Vector2 = Vector2((skin.x - shape.drag_from.x) * shape.radius, skin.y - shape.drag_from.y)
		tension = clampf(shape.drag.length() / maxf(max_drag, 1.0), 0.0, 1.0) \
				* exp(-d.length_squared() / (reach * reach))
	if shape.side != 0 and shape.amount > 0.0:
		var local: float = skin.x * shape.side   # angle toward the pulled side
		var row: float = (skin.y - shape.grip_v) / (shape.bulge_spread * tension_spread)
		var flap: float = shape.amount * smoothstep(0.0, deg_to_rad(flap_grip_angle), local) * exp(-0.5 * row * row)
		tension = maxf(tension, flap)
	return clampf(tension, 0.0, 1.0)


## The fold smooths out while the skin near it is pulled away from it along the arm (a pull any other way counts
## `fold_side_share` as much), fully at `fold_open_at` of `max_drag`; let go and it bunches up again.
func _update_fold(delta: float) -> void:
	for i in shape.folds.size():
		var fold: Vector4 = shape.folds[i]
		var opening: float = 0.0
		if fold_enabled and shape.drag != Vector2.ZERO:
			var away: float = shape.drag.y * (-1.0 if shape.drag_from.y < fold.y else 1.0)
			var along: float = maxf(away, 0.0) + (shape.drag.length() - absf(shape.drag.y)) * fold_side_share \
					+ maxf(-away, 0.0) * fold_side_share
			# how far the grip is from the crease: past its band along the arm, past its ends round it
			var gap: Vector2 = Vector2(maxf(absf(shape.drag_from.x - fold.x) - fold.z, 0.0) * radius,
					maxf(absf(shape.drag_from.y - fold.y) - fold.w * 0.5, 0.0))
			var reach: float = shape.drag_radius * fold_reach_spread
			opening = clampf(along / maxf(max_drag * fold_open_at, 1.0), 0.0, 1.0) * exp(-gap.length_squared() / (reach * reach))
		var target: float = (1.0 - opening) if fold_enabled else 0.0
		var settled: float = lerpf(shape.fold_amounts[i], target, 1.0 - exp(-fold_rate * delta))
		shape.fold_amounts[i] = target if absf(settled - target) < 0.002 else settled
	# the bump flattens while the skin round it is pulled taut, whichever way
	if shape.bump.z > 0.0:
		var flat: float = 0.0
		if shape.drag != Vector2.ZERO:
			var b: Vector4 = shape.bump
			# the bump and the skin it covers: below it when it sags, above it when it reaches up
			var span: float = b.w + shape.bump_overhang
			var middle: float = b.y + (b.w - shape.bump_overhang) * 0.5 if shape.bump_up else b.y + span * 0.5
			var gap: Vector2 = Vector2(maxf(absf(shape.drag_from.x - b.x) - b.z, 0.0) * radius,
					maxf(absf(shape.drag_from.y - middle) - span * 0.5, 0.0))
			var reach: float = shape.drag_radius * fold_reach_spread
			flat = clampf(shape.drag.length() / maxf(max_drag * fold_open_at, 1.0), 0.0, 1.0) * exp(-gap.length_squared() / (reach * reach))
		var full: float = 1.0 - flat
		var eased: float = lerpf(shape.bump_amount, full, 1.0 - exp(-fold_rate * delta))
		shape.bump_amount = full if absf(eased - full) < 0.002 else eased


## The hand's footprint (fingers, palm and the wrist's top) in the hand node's own pixels.
const HAND_SHAPE: Rect2 = Rect2(-44.0, -106.0, 120.0, 166.0)


func hand_rect() -> Rect2:
	if not _hand.visible:
		return Rect2()
	var shape_rect: Rect2 = HAND_SHAPE
	var middle: Vector2 = shape_rect.get_center()
	shape_rect = Rect2(middle - shape_rect.size * 0.5 * hand_block_scale, shape_rect.size * hand_block_scale)
	return _hand.get_global_transform() * shape_rect


## The placeholder hand: palm at `_hand_position`, fingers up; a little smaller and solid while gripping.
func _place_hand() -> void:
	_hand.visible = true
	_hand.position = _hand_position
	_hand.rotation = 0.0
	_hand.scale = Vector2.ONE * (0.85 if _gripping else 1.0)
	_hand.modulate.a = 1.0 if _gripping else 0.75


func _forget_projections() -> void:
	_projected_known.fill(0)
	_warm_cursor = 0


## The arm's centre on screen: the middle of this control, moved up by the view's pan.
func _center() -> Vector2:
	return get_global_rect().get_center() - Vector2(0.0, _pan)


## Refreshes `_center_offset`, the arm's centre that cached projections add (a field, not a call: a stroke reads
## thousands of them). The session calls update_surface() first thing every frame, after moving the skin.
func _refresh_center() -> void:
	var center: Vector2 = _center()
	_center_offset = Vector3(center.x, center.y, 0.0)


## A point in this control's pixels -> the same point relative to the arm's centre (with the pan).
func _arm_point(local: Vector2) -> Vector2:
	return local - size * 0.5 + Vector2(0.0, _pan)


func _skin_to_cell(skin: Vector2) -> Vector2:
	return Vector2((skin.x / _wrap + 1.0) * 0.5 * grid.x, (skin.y / stencil_height + 0.5) * grid.y)


func _cell_to_skin(cell: Vector2) -> Vector2:
	return Vector2((cell.x / grid.x * 2.0 - 1.0) * _wrap, (cell.y / grid.y - 0.5) * stencil_height)


func _apply_exports() -> void:
	_forget_projections()
	_layers_known.fill(0)
	_wrap = deg_to_rad(wrap_angle)
	shape.radius = radius
	shape.length = arm_length
	shape.grip_angle = deg_to_rad(grip_angle)
	shape.max_pull = max_pull
	shape.hold_depth = hold_depth
	shape.grip_bulge = grip_bulge
	shape.bulge_spread = bulge_spread
	shape.drag_radius = drag_radius
	shape.folds.clear()
	for fold: Vector4 in folds.slice(0, 2):
		shape.folds.append(Vector4(deg_to_rad(fold.x), fold.y, deg_to_rad(fold.z), fold.w))
	shape.fold_amounts.resize(shape.folds.size())
	shape.fold_amounts.fill(1.0 if fold_enabled else 0.0)
	shape.fold_closed_width = fold_closed
	shape.bump = Vector4(deg_to_rad(bump.x), bump.y, deg_to_rad(bump.z), bump.w) if bump_enabled else Vector4.ZERO
	shape.bump_overhang = bump_overhang
	shape.bump_uneven = bump_uneven
	shape.bump_up = bump_up
	shape.fold_ragged = fold_ragged
	shape.bump_amount = 1.0 if bump_enabled else 0.0
	shape.fold_spread = fold_spread
	shape.ink_soft_angle = deg_to_rad(ink_soft_angle)
	_ink_low = cos(deg_to_rad(ink_max_angle))
	_ink_high = cos(deg_to_rad(ink_soft_angle))
	shape.ink_max_angle = deg_to_rad(ink_max_angle)
	pull.max_angle = deg_to_rad(max_pull_angle)
	pull.pull_rate = pull_rate
	pull.return_rate = return_rate
	pull.tilt_speed = deg_to_rad(tilt_speed)


## The defocus over the wrist and the hand: a screen blur drawn right after the arm's 3D view (under the artist's
## hand and everything else), its rows set every frame from the scroll (`_update_defocus()`).
func _build_defocus() -> void:
	var copy: BackBufferCopy = BackBufferCopy.new()
	_defocus_copy = copy
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	move_child(copy, $View3D.get_index() + 1)
	_defocus = ColorRect.new()
	_defocus.name = "Defocus"
	_defocus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://tattoo/surfaces/arm/defocus.gdshader")
	_defocus.material = material
	add_child(_defocus)
	move_child(_defocus, copy.get_index() + 1)
	_defocus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The defocus starts at `defocus_from` along the arm and is full at `defocus_full`, `defocus_radius` px at full.
func _update_defocus() -> void:
	if _defocus == null:
		return
	var scale: float = get_viewport().get_final_transform().get_scale().y
	var centre: float = _center().y
	var material: ShaderMaterial = _defocus.material
	material.set_shader_parameter("from_y", (centre + defocus_from) * scale)
	material.set_shader_parameter("full_y", (centre + defocus_full) * scale)
	material.set_shader_parameter("max_radius", defocus_radius * scale)
	material.set_shader_parameter("darken", defocus_darken)
	material.set_shader_parameter("dark_y", (centre + defocus_dark_to) * scale)
	_defocus.visible = centre + defocus_from < size.y + get_global_rect().position.y
	_defocus_copy.visible = _defocus.visible   # no screen copy (and its mipmaps) while nothing is blurred


## The client's hand below the wrist: a flat out-of-focus picture (`client_hand.gdshader`) on a quad just behind the
## arm, scaled so its wrist is as wide as the arm's and its top under the arm's fade, where it dissolves in.
func _build_client_hand() -> void:
	var albedo: Texture2D = load(HAND_ALBEDO)
	if albedo == null:
		return
	var picture: Vector2 = Vector2(albedo.get_size())
	var scale: float = 2.0 * shape.radius_at(hand_top + 140.0) / hand_wrist_width * hand_scale
	var size: Vector2 = picture * scale
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	quad.subdivide_depth = 32   # rows for the shader's lean
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://tattoo/surfaces/arm/client_hand.gdshader")
	material.set_shader_parameter("albedo_tex", albedo)
	material.set_shader_parameter("normal_tex", load(HAND_NORMAL))
	material.set_shader_parameter("skin_detail", _material.get_shader_parameter("skin_detail"))
	material.set_shader_parameter("skin_normal", _material.get_shader_parameter("skin_normal"))
	material.set_shader_parameter("quad_size", size)
	var hand: MeshInstance3D = MeshInstance3D.new()
	hand.name = "ClientHand"
	hand.mesh = quad
	hand.material_override = material
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# world y is up and the arm's rows run down; the wrist (the picture's top) lines up with the arm's middle
	hand.position = Vector3((picture.x * 0.5 - hand_wrist_center) * scale, -(hand_top + size.y * 0.5), 0.0)
	_view_viewport.add_child(hand)


## A flat grid; UV = skin coordinates (theta -PI..PI, v along `arm_length` × the shader's MESH_REACH).
## The shader places the vertices.
func _build_mesh() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for j in MESH_STEPS.y + 1:
		for i in MESH_STEPS.x + 1:
			var uv: Vector2 = Vector2(float(i) / MESH_STEPS.x, float(j) / MESH_STEPS.y)
			uvs.append(uv)
			vertices.append(Vector3(uv.x, uv.y, 0.0))
	var row: int = MESH_STEPS.x + 1
	for j in MESH_STEPS.y:
		for i in MESH_STEPS.x:
			var a: int = j * row + i
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var reach: float = radius * 3.0 + max_pull
	mesh.custom_aabb = AABB(Vector3(-reach, -arm_length * 2.0, -reach), Vector3(reach * 2.0, arm_length * 4.0, reach * 2.0))
	return mesh
