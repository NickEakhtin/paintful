extends TattooModifier
## "Observers": the spirit opens eyes on the client's skin to watch the work. Each one sits on the stencil
## and is mostly open; now and then it shuts for a while, trembles and opens again. Ink only goes under
## a shut eye, and the magnet doesn't pull into an open one.

const EYE_SCENE: PackedScene = preload("res://modifiers/observers/eye.tscn")
## Places to try when looking for spots on the stencil.
const CANDIDATES: int = 400

@export_group("Eyes")
@export var eye_count: int = 3
## Width and height of an open eye, in pixels.
@export var eye_size: Vector2 = Vector2(120.0, 64.0)
## Eyes keep at least this far apart, centre to centre, in pixels.
@export var min_spacing: float = 150.0
## The pupils follow the needle within this distance and glance around beyond it, in pixels.
@export var look_range: float = 450.0

@export_group("Timing")
## Seconds from the start to the first opening, picked in this range per eye.
@export var first_open_min: float = 1.5
@export var first_open_max: float = 3.0
## Seconds an eye stays open, picked in this range each time.
@export var open_min: float = 4.0
@export var open_max: float = 7.0
## Seconds an eye stays shut, picked in this range each time.
@export var closed_min: float = 3.0
@export var closed_max: float = 5.0
## Seconds the lid trembles before it opens.
@export var warn_time: float = 0.7
## Seconds for the lids to open or shut.
@export var blink_time: float = 0.15

var eyes: Array[Eye] = []

@onready var _eye_layer: Node2D = $Eyes


func _ready() -> void:
	for spot in _pick_spots():
		var eye: Eye = EYE_SCENE.instantiate()
		eye.position = spot
		eye.size = eye_size
		eye.first_open_min = first_open_min
		eye.first_open_max = first_open_max
		eye.open_min = open_min
		eye.open_max = open_max
		eye.closed_min = closed_min
		eye.closed_max = closed_max
		eye.warn_time = warn_time
		eye.blink_time = blink_time
		_eye_layer.add_child(eye)
		eyes.append(eye)


func _process(delta: float) -> void:
	var needle: Vector2 = session.needle_position()
	var red_spot: Vector2 = session.red_spot()
	for eye in eyes:
		eye.look_at_point(eye.to_local(needle), look_range, delta)
		eye.alarmed = eye.is_open() and red_spot.is_finite() \
				and eye.block_rect().grow(session.heat_radius).has_point(red_spot)


func ink_blocks() -> Array[Rect2]:
	var blocks: Array[Rect2] = []
	for eye in eyes:
		if eye.is_open():
			blocks.append(eye.block_rect())
	return blocks


func stop() -> void:
	super()
	for eye in eyes:
		eye.shut()


## Spots on the stencil, inside the skin, `min_spacing` apart where the stencil allows it.
func _pick_spots() -> Array[Vector2]:
	var stencil: Rect2 = session.stencil_rect()
	var skin: Rect2 = session.skin.get_rect().grow(-10.0)
	var candidates: Array[Vector2] = []
	for i in CANDIDATES:
		var point: Vector2 = stencil.position + stencil.size * Vector2(randf(), randf())
		var cell: Vector2 = (point - stencil.position) / stencil.size * InkCanvas.SIZE
		if session.canvas.is_stencil(cell) and skin.encloses(Rect2(point - eye_size * 0.5, eye_size)):
			candidates.append(point)
	var spots: Array[Vector2] = []
	while spots.size() < eye_count and not candidates.is_empty():
		var spaced: Array[Vector2] = []
		for point in candidates:
			if _gap(point, spots) >= min_spacing:
				spaced.append(point)
		var spot: Vector2
		if not spaced.is_empty():
			spot = spaced.pick_random()
		else:
			# Too crowded: the spot farthest from the others will do.
			spot = candidates[0]
			for point in candidates:
				if _gap(point, spots) > _gap(spot, spots):
					spot = point
		spots.append(spot)
		candidates.erase(spot)
	return spots


## Distance from `point` to the nearest of `spots`; INF with none.
func _gap(point: Vector2, spots: Array[Vector2]) -> float:
	var gap: float = INF
	for spot in spots:
		gap = minf(gap, point.distance_to(spot))
	return gap
