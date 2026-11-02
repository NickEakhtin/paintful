extends TattooModifier
## "Observers": the spirit opens eyes on the client's skin to watch the work. Each one sits on the stencil
## and is mostly open; now and then it shuts for a while, trembles and opens again. Ink only goes under
## a shut eye, and the magnet doesn't pull into an open one. Poking an open eye with the working needle
## makes it wince and the client flinch; more than `allowed_hits` pokes fail the task.

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

@export_group("Hits")
## Seconds the working needle must stay in an open eye to count, so a quick click on a spider doesn't.
@export var poke_time: float = 0.1
## Seconds after an eye starts opening during which a needle already there doesn't count.
@export var open_grace: float = 0.3
## Seconds before a needle that stays in the same eye counts again.
@export var hit_cooldown: float = 1.0
## Pokes allowed for the task to count as done.
@export var allowed_hits: int = 2
## How far the skin jumps when the client flinches, in pixels.
@export var flinch_distance: float = 8.0

var eyes: Array[Eye] = []
var hits: int = 0

## Per eye: seconds the working needle has been inside it while it can be hit.
var _held: Dictionary[Eye, float] = {}
## Per eye: seconds until a needle that stayed inside counts again.
var _cooldown: Dictionary[Eye, float] = {}
var _flinch_time: float = 0.0

@onready var _eye_layer: Node2D = $Eyes
@onready var _open_sound: AudioStreamPlayer = $Open
@onready var _close_sound: AudioStreamPlayer = $Close
@onready var _twitch_sound: AudioStreamPlayer = $Twitch
@onready var _poke_sound: AudioStreamPlayer = $Poke


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
		eye.open_grace = open_grace
		eye.state_changed.connect(_on_eye_state_changed)
		_eye_layer.add_child(eye)
		eyes.append(eye)
		_held[eye] = 0.0
		_cooldown[eye] = 0.0


func _process(delta: float) -> void:
	var needle: Vector2 = session.needle_position()
	var red_spot: Vector2 = session.red_spot()
	for eye in eyes:
		eye.look_at_point(eye.to_local(needle), look_range, delta)
		eye.alarmed = eye.is_open() and red_spot.is_finite() \
				and eye.block_rect().grow(session.heat_radius).has_point(red_spot)
	_flinch_time = maxf(0.0, _flinch_time - delta)
	_check_pokes(needle, delta)


func ink_blocks() -> Array[Rect2]:
	var blocks: Array[Rect2] = []
	for eye in eyes:
		if eye.is_open():
			blocks.append(eye.block_rect())
	return blocks


## The client twitches when an eye gets poked.
func skin_offset() -> Vector2:
	if _flinch_time <= 0.0:
		return Vector2.ZERO
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * flinch_distance * (_flinch_time / 0.3)


func is_passed() -> bool:
	return hits <= allowed_hits


func stop() -> void:
	super()
	for eye in eyes:
		eye.shut()


## One poke per stab: the needle must stay in for `poke_time`, then counts again every `hit_cooldown`
## while it stays; leaving the eye (or the eye shutting) resets both.
func _check_pokes(needle: Vector2, delta: float) -> void:
	var working: bool = session.is_working()
	for eye in eyes:
		if not (working and eye.can_be_hit() and eye.contains(eye.to_local(needle))):
			_held[eye] = 0.0
			_cooldown[eye] = 0.0
			continue
		_held[eye] += delta
		_cooldown[eye] -= delta
		if _held[eye] >= poke_time and _cooldown[eye] <= 0.0:
			_cooldown[eye] = hit_cooldown
			_poke(eye)


func _poke(eye: Eye) -> void:
	hits += 1
	eye.poke()
	_flinch_time = 0.3
	_poke_sound.pitch_scale = randf_range(0.85, 1.15)
	_poke_sound.play()


func _on_eye_state_changed(state: Eye.State) -> void:
	var sound: AudioStreamPlayer = null
	match state:
		Eye.State.WARNING:
			sound = _twitch_sound
		Eye.State.OPENING:
			sound = _open_sound
		Eye.State.CLOSING:
			sound = _close_sound
	if sound != null:
		sound.pitch_scale = randf_range(0.9, 1.15)
		sound.play()


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
