class_name Eye
extends Node2D
## One of the spirit's eyes on the client's skin (the Observers task). Mostly open: now and then it shuts
## for a while, trembles as a warning and opens again. Ink can't go under it while it's open.
## State and timing only; the look lives under `Visual`, which reads it. The origin is the eye centre.

enum State { EMERGING, CLOSED, WARNING, OPENING, OPEN, CLOSING }

## Width and height of the open eye, in pixels. The task sets this and the timings before adding the eye.
var size: Vector2 = Vector2(120.0, 64.0)
## Seconds from the start to the first opening (the warning comes first), picked in this range.
var first_open_min: float = 1.5
var first_open_max: float = 3.0
var open_min: float = 4.0
var open_max: float = 7.0
var closed_min: float = 3.0
var closed_max: float = 5.0
## Seconds the lid trembles before it opens.
var warn_time: float = 0.7
## Seconds for the lids to open or shut.
var blink_time: float = 0.15
## Seconds it takes to surface on the skin at the start.
var emerge_time: float = 1.0
## Seconds after it starts opening during which a poke doesn't count.
var open_grace: float = 0.3

var state: State = State.EMERGING
## 0 shut, 1 wide open.
var openness: float = 0.0
## 0 not there yet, 1 fully on the skin.
var presence: float = 0.0
## How far into the warning, 0..1; 0 outside it.
var tremble: float = 0.0
## Where the pupil looks, -1..1 of its travel on each axis.
var gaze: Vector2 = Vector2.ZERO
## The skin under it is red: the white turns bloodshot, so the redness isn't hidden.
var alarmed: bool = false

var _timer: float = 0.0
var _since_open: float = 0.0
## Stays shut for good once the session is over.
var _shut_for_good: bool = false
var _gaze_target: Vector2 = Vector2.ZERO
var _idle_timer: float = 0.0

@onready var _visual: Node2D = $Visual


func _ready() -> void:
	_timer = randf_range(first_open_min, first_open_max)


func _process(delta: float) -> void:
	presence = minf(1.0, presence + delta / emerge_time)
	_since_open += delta
	_timer -= delta
	match state:
		State.EMERGING, State.CLOSED:
			if _timer <= 0.0 and not _shut_for_good:
				_enter(State.WARNING, warn_time)
		State.WARNING:
			tremble = 1.0 - maxf(0.0, _timer) / warn_time
			if _timer <= 0.0:
				tremble = 0.0
				_since_open = 0.0
				_enter(State.OPENING, blink_time)
		State.OPENING:
			openness = 1.0 - maxf(0.0, _timer) / blink_time
			if _timer <= 0.0:
				_enter(State.OPEN, randf_range(open_min, open_max))
		State.OPEN:
			openness = 1.0
			if _timer <= 0.0:
				_enter(State.CLOSING, blink_time)
		State.CLOSING:
			openness = maxf(0.0, _timer) / blink_time
			if _timer <= 0.0:
				_enter(State.CLOSED, randf_range(closed_min, closed_max))
	gaze = gaze.lerp(_gaze_target, 1.0 - exp(-8.0 * delta))
	_visual.queue_redraw()


## Whether ink is kept out from under it: from the first moment it opens until it's fully shut.
func is_open() -> bool:
	return state == State.OPENING or state == State.OPEN or state == State.CLOSING


## Open and past the grace time, so a poke counts.
func can_be_hit() -> bool:
	return is_open() and _since_open >= open_grace


## Whether `point` (in this eye's local pixels) is inside the eye.
func contains(point: Vector2) -> bool:
	return (point / (size * 0.5)).length_squared() <= 1.0


## The eye's rect in viewport pixels; the ellipse inside it takes no ink while open.
func block_rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


## Follows `point` (local pixels) while it's within `look_range`, otherwise glances around lazily.
func look_at_point(point: Vector2, look_range: float, delta: float) -> void:
	if point.length() <= look_range:
		var travel: Vector2 = point / (size * 0.5)
		_gaze_target = travel.limit_length(1.0)
		_idle_timer = 0.0
		return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(1.2, 2.8)
		_gaze_target = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6))


## Shuts and stays shut (the tattoo is done).
func shut() -> void:
	_shut_for_good = true
	tremble = 0.0
	if is_open():
		_enter(State.CLOSING, blink_time * openness)
	elif state == State.WARNING:
		_enter(State.CLOSED, 0.0)


func _enter(new_state: State, time: float) -> void:
	state = new_state
	_timer = time
