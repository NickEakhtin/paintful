extends Node2D
## The wet paper towel under the artist's left palm (drawn behind the hand), stained redder as it wipes blood.

## How much blood it has taken, 0 .. 1.
var stained: float = 0.0:
	set(value):
		stained = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	show_behind_parent = true


func _draw() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	# a crumpled square under the palm
	for i in 10:
		var angle: float = TAU * i / 10.0 + 0.3
		var reach: float = 64.0 + 9.0 * sin(i * 2.3)
		points.append(Vector2(cos(angle), sin(angle)) * reach + Vector2(14.0, 30.0))
	draw_colored_polygon(points, Color(0.8, 0.86, 0.92))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.45, 0.5, 0.58), 2.0, true)
	if stained > 0.0:
		var blood: Color = Color(0.45, 0.03, 0.06, 0.25 + 0.6 * stained)
		draw_circle(Vector2(-22.0, 62.0), 10.0 + 18.0 * stained, blood)
		draw_circle(Vector2(40.0, 70.0), 6.0 + 12.0 * stained, blood)
		draw_circle(Vector2(-44.0, 30.0), 4.0 + 10.0 * stained, blood)
		draw_circle(Vector2(62.0, 20.0), 3.0 + 9.0 * stained, blood)
