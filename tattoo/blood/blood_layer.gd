class_name BloodLayer
extends Node2D
## Drops of blood on the client's skin, drawn in skin pixels (a child of the arm's `InkLayer`, so they wrap round
## the arm and slide with the skin). Look only: they don't touch the ink or the progress.
## Now and then a drop wells up on fresh ink (younger than `fresh_time`), swells while it's left alone, and after
## `run_after` seconds turns into a big drop that runs down the arm. The artist's left hand with a wet paper
## towel wipes them off (`wipe()`).

## Seconds between two drops (random in this range), at most `max_drops` at once.
@export var interval_min: float = 2.5
@export var interval_max: float = 5.5
@export var max_drops: int = 14
## Only ink this young can bleed, in seconds (the ink's own drying time).
@export var fresh_time: float = 6.0
## A drop's radius when it wells up and once it's full (after `grow_time` s), in skin pixels.
@export var start_radius: float = 2.5
@export var full_radius: float = 7.0
@export var grow_time: float = 8.0
## After this long it becomes a big drop (`run_radius`) and runs down at `run_speed` px/s, up to `run_max` px.
@export var run_after: float = 14.0
@export var run_radius: float = 9.5
@export var run_speed: float = 14.0
@export var run_max: float = 190.0
## How much of a drop one pixel of rubbing over it takes away (1 = all of it).
@export var wipe_per_pixel: float = 0.014
@export var color: Color = Color(0.3, 0.015, 0.04)
@export var rim_color: Color = Color(0.15, 0.0, 0.015)
@export var gloss_color: Color = Color(1.0, 0.86, 0.86, 0.9)

## Each drop: {at: Vector2, age: float, left: float (1 .. 0 as it's wiped), run: float (trail length), seed: float}.
var drops: Array[Dictionary] = []
## Off: no new drops (`Mechanics.blood`).
var spawning: bool = true

## Recently inked spots: [Vector2 position, float time], oldest first.
var _fresh: Array[Array] = []
var _clock: float = 0.0
var _next_drop: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_next_drop = _rng.randf_range(interval_min, interval_max)


## Ink just landed here (skin pixels).
func note_fresh(at: Vector2) -> void:
	if not _fresh.is_empty() and (_fresh[-1][0] as Vector2).distance_to(at) < 6.0:
		_fresh[-1] = [at, _clock]
		return
	_fresh.append([at, _clock])
	if _fresh.size() > 400:
		_fresh.pop_front()


func update(delta: float) -> void:
	_clock += delta
	while not _fresh.is_empty() and _clock - float(_fresh[0][1]) > fresh_time:
		_fresh.pop_front()
	_next_drop -= delta
	if _next_drop <= 0.0:
		_next_drop = _rng.randf_range(interval_min, interval_max)
		_spawn()
	for drop in drops:
		drop.age += delta
		if drop.age > run_after:
			drop.run = minf(drop.run + run_speed * delta * (0.6 + 0.4 * sin(drop.seed + drop.age * 0.7)), run_max)
	queue_redraw()


## Rubs at `at` (skin pixels) over a circle of `radius`, the hand having moved `moved` pixels: every drop (and its
## run) under it loses some. Returns how much blood came off (for the paper's stains).
func wipe(at: Vector2, radius: float, moved: float) -> float:
	var taken: float = 0.0
	for drop in drops.duplicate():
		var top: Vector2 = drop.at
		var bottom: Vector2 = top + Vector2(0.0, drop.run)
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(at, top, bottom)
		if near.distance_to(at) > radius + _radius(drop):
			continue
		var loss: float = minf(drop.left, moved * wipe_per_pixel)
		drop.left -= loss
		taken += loss * (1.0 + drop.run / 60.0)
		if drop.left <= 0.01:
			drops.erase(drop)
	if taken > 0.0:
		queue_redraw()
	return taken


## Nothing left (a restart).
func clear() -> void:
	drops.clear()
	_fresh.clear()
	queue_redraw()


func _spawn() -> void:
	if not spawning or _fresh.is_empty() or drops.size() >= max_drops:
		return
	for attempt in 6:
		var spot: Vector2 = _fresh[_rng.randi_range(0, _fresh.size() - 1)][0]
		spot += Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
		var crowded: bool = false
		for drop in drops:
			if (drop.at as Vector2).distance_to(spot) < 14.0:
				crowded = true
				break
		if not crowded:
			drops.append({at = spot, age = 0.0, left = 1.0, run = 0.0, seed = _rng.randf_range(0.0, TAU)})
			return


func _radius(drop: Dictionary) -> float:
	var grown: float = smoothstep(0.0, 1.0, drop.age / grow_time)
	var radius: float = lerpf(start_radius, full_radius, grown)
	if drop.age > run_after:
		radius = lerpf(full_radius, run_radius, smoothstep(run_after, run_after + 2.0, drop.age))
	return radius * lerpf(0.55, 1.0, drop.left)


func _draw() -> void:
	for drop in drops:
		var radius: float = _radius(drop)
		var alpha: float = clampf(drop.left * 1.3, 0.0, 1.0)
		var top: Vector2 = drop.at
		var run: float = drop.run
		var seed: float = drop.seed
		if run > 1.0:
			_draw_run(top, run, radius, seed, alpha)
		# the bead where it welled up (it hangs at the bottom of its run once it runs)
		var bead: Vector2 = top + Vector2(sin(seed) * 2.0, run)
		var bead_radius: float = radius * (1.1 if run > 1.0 else 1.0)
		_draw_bead(bead, bead_radius, alpha)
		if run > 1.0:
			_draw_bead(top, radius * 0.75, alpha * 0.9)


## A thin glossy streak from where it welled up down to the bead, wobbling a little and narrowing.
func _draw_run(top: Vector2, length: float, radius: float, seed: float, alpha: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = maxi(2, int(length / 6.0))
	for i in steps + 1:
		var t: float = float(i) / steps
		points.append(top + Vector2(sin(seed + t * 5.0) * 2.5 + sin(seed * 2.0 + t * 13.0) * 0.8, length * t))
	var width: float = radius * 0.9
	draw_polyline(points, Color(rim_color, alpha), width + 1.6, true)
	draw_polyline(points, Color(color, alpha), width, true)
	# a highlight running along its left side
	var shine: PackedVector2Array = PackedVector2Array()
	for p in points:
		shine.append(p + Vector2(-width * 0.22, 0.0))
	draw_polyline(shine, Color(gloss_color, alpha * 0.45), maxf(width * 0.18, 0.8), true)


## A round glossy bead: dark rim, deep red body, a bright highlight up and to the left and a faint one below.
func _draw_bead(at: Vector2, radius: float, alpha: float) -> void:
	draw_circle(at + Vector2(0.6, 0.8), radius + 0.9, Color(rim_color, alpha * 0.8))
	draw_circle(at, radius, Color(color, alpha))
	draw_circle(at + Vector2(radius * 0.12, radius * 0.18), radius * 0.72, Color(color.lightened(0.12), alpha))
	draw_circle(at + Vector2(-radius * 0.36, -radius * 0.38), maxf(radius * 0.26, 0.7), Color(gloss_color, alpha))
	draw_circle(at + Vector2(radius * 0.3, radius * 0.45), maxf(radius * 0.12, 0.5),
			Color(gloss_color, alpha * 0.35))
