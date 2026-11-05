extends Node2D
## The bin beside the side table (placeholder look) with the floor as solid ground, so a thrown paper ball lands
## somewhere. Lives in the session's `View`, in its pixels; `build(origin)` puts the bin's bottom
## middle at `origin`. Each ball that lands in it shows as a crumple inside (`add_ball()`).

const WIDTH: float = 130.0
const HEIGHT: float = 170.0

var balls: int = 0:
	set(value):
		balls = value
		queue_redraw()

var _body: StaticBody2D


## Builds the bin's walls (an open top) and the floor, in this node's parent's pixels.
func build(bin_bottom: Vector2) -> void:
	position = bin_bottom
	if _body != null:
		_body.queue_free()
	_body = StaticBody2D.new()
	add_child(_body)
	var half: float = WIDTH * 0.5
	_add_segment(Vector2(-half, -HEIGHT), Vector2(-half * 0.82, 0.0))   # left wall, a little slanted
	_add_segment(Vector2(half, -HEIGHT), Vector2(half * 0.82, 0.0))
	_add_segment(Vector2(-half, 0.0), Vector2(half, 0.0))
	# the floor across the whole view (the ball flies in front of the table, so the table doesn't catch it)
	_add_segment(Vector2(-3000.0, 0.0), Vector2(3000.0, 0.0))
	queue_redraw()


## Where a ball should fly to: the middle of the opening, a little inside.
func target() -> Vector2:
	return global_position + Vector2(0.0, -HEIGHT + 20.0)


## Whether a point (global) is inside the bin.
func holds(point: Vector2) -> bool:
	var local: Vector2 = point - global_position
	return absf(local.x) < WIDTH * 0.5 and local.y > -HEIGHT and local.y <= 2.0


func _add_segment(a: Vector2, b: Vector2) -> void:
	var shape: CollisionShape2D = CollisionShape2D.new()
	var segment: SegmentShape2D = SegmentShape2D.new()
	segment.a = a
	segment.b = b
	shape.shape = segment
	_body.add_child(shape)


func _draw() -> void:
	var half: float = WIDTH * 0.5
	var body: PackedVector2Array = PackedVector2Array([Vector2(-half, -HEIGHT), Vector2(half, -HEIGHT),
			Vector2(half * 0.82, 0.0), Vector2(-half * 0.82, 0.0)])
	draw_colored_polygon(body, Color(0.2, 0.21, 0.24))
	for i in mini(balls, 6):   # what's thrown in shows over the rim
		var at: Vector2 = Vector2(-36.0 + (i % 3) * 34.0 + sin(i * 2.1) * 6.0, -HEIGHT + 18.0 - (i / 3) * 14.0)
		draw_circle(at, 15.0, Color(0.82, 0.84, 0.88))
		draw_circle(at + Vector2(4.0, 3.0), 7.0, Color(0.45, 0.04, 0.07, 0.8))
	draw_polyline(body + PackedVector2Array([body[0]]), Color(0.08, 0.08, 0.1), 4.0, true)
	draw_line(Vector2(-half - 6.0, -HEIGHT), Vector2(half + 6.0, -HEIGHT), Color(0.32, 0.33, 0.37), 8.0)
	for i in 4:   # ribs
		var x: float = lerpf(-half * 0.6, half * 0.6, i / 3.0)
		draw_line(Vector2(x, -HEIGHT + 20.0), Vector2(x * 0.85, -10.0), Color(0.15, 0.15, 0.18), 3.0)
