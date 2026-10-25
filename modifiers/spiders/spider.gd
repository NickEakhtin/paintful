class_name Spider
extends Node2D
## A spider running over the skin. Draws itself; the Spiders task steers and squashes it.

var velocity: Vector2 = Vector2.ZERO
var squashed: bool = false

var _leg_phase: float = 0.0


func squash() -> void:
	squashed = true
	rotation = randf() * TAU
	var tween: Tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	tween.tween_callback(queue_free)
	queue_redraw()


func _process(delta: float) -> void:
	if squashed:
		return
	_leg_phase += delta * 20.0
	rotation = velocity.angle()
	queue_redraw()


func _draw() -> void:
	if squashed:
		# Splat: a dark blot with a few drops around it.
		var splat: Color = Color(0.22, 0.26, 0.08, 0.85)
		draw_circle(Vector2.ZERO, 11.0, splat)
		for i in 6:
			draw_circle(Vector2.from_angle(i * TAU / 6.0 + 0.4) * 15.0, 3.0, splat)
		return
	var body: Color = Color(0.07, 0.05, 0.05)
	# Four legs a side, swinging in alternating pairs. The spider faces +X.
	for side in [-1.0, 1.0]:
		for i in 4:
			var root: Vector2 = Vector2(3.0 - i * 3.0, 0.0)
			var swing: float = sin(_leg_phase + i * 1.4 + (PI if side > 0.0 else 0.0)) * 4.0
			var knee: Vector2 = root + Vector2(5.0 - i * 2.0 + swing, side * 9.0)
			var foot: Vector2 = knee + Vector2(6.0 - i * 4.0 + swing * 0.5, side * 8.0)
			draw_polyline(PackedVector2Array([root, knee, foot]), body, 2.0)
	draw_circle(Vector2(-7.0, 0.0), 8.0, body)
	draw_circle(Vector2(5.0, 0.0), 5.0, body)
	draw_circle(Vector2(8.0, -2.0), 1.2, Color(0.8, 0.1, 0.1))
	draw_circle(Vector2(8.0, 2.0), 1.2, Color(0.8, 0.1, 0.1))
