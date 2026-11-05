extends Node2D
## The crumpled bloody paper towel in the left hand's fingers before the throw (placeholder look, over the
## fingertips, so it shows).


func _draw() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in 11:
		var angle: float = TAU * i / 11.0
		points.append(Vector2(cos(angle), sin(angle)) * (26.0 + 5.0 * sin(i * 3.1)) + Vector2(10.0, -104.0))
	draw_colored_polygon(points, Color(0.86, 0.88, 0.92))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.42, 0.45, 0.52), 2.0, true)
	draw_line(Vector2(-4.0, -112.0), Vector2(16.0, -98.0), Color(0.55, 0.58, 0.66), 2.0)
	draw_line(Vector2(12.0, -122.0), Vector2(24.0, -108.0), Color(0.55, 0.58, 0.66), 2.0)
	draw_circle(Vector2(18.0, -96.0), 9.0, Color(0.45, 0.04, 0.07, 0.85))
	draw_circle(Vector2(-2.0, -114.0), 6.0, Color(0.45, 0.04, 0.07, 0.75))
