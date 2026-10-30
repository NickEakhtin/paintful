class_name Moth
extends Node2D
## A tiny pale-blue fairy. It flies to a point, hangs there by its hands with its legs dangling,
## and tumbles away when shaken off. The Moths task says where to fly; this only moves and draws it.
## The origin is where its hands hold on.

enum State { FLYING, PERCHED, LEAVING }

const COLOR: Color = Color(0.7, 0.85, 1.0)
const SKIN: Color = Color(0.88, 0.95, 1.0)
## Within this distance it lands.
const LAND_DISTANCE: float = 5.0
## Within this distance it keeps up with a moving target, so it can land on a machine in motion.
const CATCH_DISTANCE: float = 80.0

var state: State = State.FLYING
## Whether it has a place on the machine; without one it circles and waits.
var has_perch: bool = false
## Where it hangs on the machine: share of the way from the needle to the top, and px under the body.
var perch_t: float = 0.0
var perch_side: float = 0.0
## 1 = holds on tight, 0 = falls off.
var grip: float = 1.0
## Pixels per second.
var fly_speed: float = 260.0

var _velocity: Vector2 = Vector2.ZERO
var _last_target: Vector2 = Vector2.INF
var _last_position: Vector2 = Vector2.ZERO
var _wing_phase: float = randf() * TAU
var _time: float = randf() * 10.0
var _sway: float = 0.0
var _spin: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 1.5
	_last_position = position


## Flies toward `target` with a flutter; returns true once it is close enough to land.
## Near the target it moves along with it, so a moving machine can still be caught.
func fly_to(target: Vector2, delta: float) -> bool:
	if _last_target.is_finite():
		var catch: float = 1.0 - clampf(position.distance_to(target) / CATCH_DISTANCE, 0.0, 1.0)
		position += (target - _last_target) * catch
	_last_target = target
	var to_target: Vector2 = target - position
	var flutter: Vector2 = Vector2(_noise.get_noise_1d(_time * 3.0), _noise.get_noise_1d(_time * 3.0 + 100.0))
	# Slows down when close, so it doesn't overshoot and land with a jerk.
	var desired: Vector2 = to_target.normalized() * minf(fly_speed, to_target.length() * 6.0)
	desired += flutter * fly_speed * 0.6 * clampf(to_target.length() / 60.0, 0.0, 1.0)
	_velocity = _velocity.lerp(desired, 1.0 - exp(-6.0 * delta))
	position += _velocity * delta
	return to_target.length() <= LAND_DISTANCE


## Grabs on at `point`.
func perch(point: Vector2) -> void:
	state = State.PERCHED
	position = point
	_last_position = point
	_velocity = Vector2.ZERO


## Hangs at `point` and sways behind the motion.
func hang_at(point: Vector2) -> void:
	position = point


## Tumbles off toward `direction`, flutters up and fades away.
func shake_off(direction: Vector2) -> void:
	if state == State.LEAVING:
		return
	state = State.LEAVING
	has_perch = false
	_velocity = direction.normalized() * randf_range(250.0, 420.0) + Vector2(0.0, -120.0)
	_spin = randf_range(8.0, 14.0) * (1.0 if direction.x >= 0.0 else -1.0)
	var tween: Tween = create_tween()
	tween.tween_interval(0.3)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	_time += delta
	var moved: Vector2 = (position - _last_position) / maxf(delta, 0.0001)
	_last_position = position
	match state:
		State.FLYING:
			_wing_phase += delta * 30.0
			rotation = lerpf(rotation, clampf(_velocity.x * 0.002, -0.5, 0.5), 1.0 - exp(-8.0 * delta))
		State.PERCHED:
			# Losing its grip, it flaps harder and kicks its legs.
			_wing_phase += delta * lerpf(3.0, 40.0, 1.0 - grip)
			_sway = lerpf(_sway, clampf(-moved.x * 0.0012, -0.8, 0.8), 1.0 - exp(-5.0 * delta))
			rotation = _sway
		State.LEAVING:
			_wing_phase += delta * 36.0
			_velocity = _velocity.lerp(Vector2(0.0, -160.0), 1.0 - exp(-2.5 * delta))
			position += _velocity * delta
			rotation += _spin * delta
			_spin = lerpf(_spin, 0.0, 1.0 - exp(-3.0 * delta))
	queue_redraw()


func _draw() -> void:
	var trouble: float = 1.0 - grip if state == State.PERCHED else 0.0
	var jitter: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * trouble * 1.5
	draw_set_transform(jitter)

	draw_circle(Vector2(0.0, 8.0), 15.0, Color(COLOR, 0.08))
	draw_circle(Vector2(0.0, 8.0), 9.0, Color(COLOR, 0.14))

	# Wings: folded and opened by the flap, so they look like they turn in depth.
	var open: float
	if state == State.PERCHED and trouble < 0.3:
		open = 0.55 + 0.45 * sin(_wing_phase)
	else:
		open = 0.25 + 0.75 * absf(sin(_wing_phase))
	for side in [-1.0, 1.0]:
		_draw_wing(Vector2(side * 1.0, 6.0), side, Vector2(8.0, 4.5), -0.5, open)
		_draw_wing(Vector2(side * 1.0, 8.0), side, Vector2(5.5, 3.0), 0.5, open)

	var flying: bool = state != State.PERCHED
	# Arms reach up to the hands at the origin when hanging, forward when flying.
	var hand_l: Vector2 = Vector2(-1.2, 0.0) if not flying else Vector2(-3.5, 6.0)
	var hand_r: Vector2 = Vector2(1.2, 0.0) if not flying else Vector2(3.5, 5.0)
	draw_line(Vector2(-1.3, 5.6), hand_l, SKIN, 1.1)
	draw_line(Vector2(1.3, 5.6), hand_r, SKIN, 1.1)
	# Dress.
	draw_colored_polygon(PackedVector2Array([Vector2(0.0, 5.0), Vector2(2.8, 12.0), Vector2(-2.8, 12.0)]), COLOR)
	# Legs dangle and kick.
	var kick: float = 1.0 + trouble * 4.0
	for side in [-1.0, 1.0]:
		var swing: float = sin(_time * (3.0 + trouble * 14.0) + side) * 1.2 * kick
		draw_line(Vector2(side * 1.0, 11.5), Vector2(side * 1.3 + swing, 17.0), SKIN, 1.1)
	draw_circle(Vector2(0.0, 3.2), 2.6, SKIN)
	draw_circle(Vector2(0.0, 2.4), 2.7, Color(COLOR.darkened(0.25), 0.9), false, 1.0)


func _draw_wing(root: Vector2, side: float, size: Vector2, tilt: float, open: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in 12:
		var angle: float = i * TAU / 12.0
		var point: Vector2 = Vector2(cos(angle) * size.x, sin(angle) * size.y).rotated(tilt)
		point.x = (point.x + size.x) * open * side
		points.append(root + point)
	draw_colored_polygon(points, Color(COLOR, 0.35))
	points.append(points[0])
	draw_polyline(points, Color(COLOR.lightened(0.3), 0.75), 0.8, true)
