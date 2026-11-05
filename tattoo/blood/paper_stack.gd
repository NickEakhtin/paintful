extends Node2D
## A stack of wet paper towels lying at the left of the screen (placeholder look): the artist's left hand takes one
## with Space. `rect` is set by the skin, in its own pixels.

var rect: Rect2 = Rect2(30.0, 400.0, 150.0, 90.0):
	set(value):
		rect = value
		queue_redraw()
## The hand is over it: it lights up a little.
var hovered: bool = false:
	set(value):
		if value != hovered:
			hovered = value
			queue_redraw()


func _draw() -> void:
	var sheet: Color = Color(0.86, 0.9, 0.95)
	var wet: Color = Color(0.62, 0.72, 0.82)
	# a few sheets, each a little off the one under it
	for i in 4:
		var offset: Vector2 = Vector2(sin(i * 1.7) * 4.0, -i * 5.0)
		var r: Rect2 = Rect2(rect.position + offset, rect.size)
		draw_rect(r.grow(2.0), Color(0.2, 0.22, 0.26, 0.6))
		draw_rect(r, sheet.lerp(wet, 0.25 + 0.1 * i))
	var top: Rect2 = Rect2(rect.position + Vector2(sin(3 * 1.7) * 4.0, -15.0), rect.size)
	# damp patches and a fold line on the top sheet
	draw_circle(top.position + top.size * Vector2(0.3, 0.45), top.size.y * 0.28, Color(wet, 0.55))
	draw_circle(top.position + top.size * Vector2(0.68, 0.6), top.size.y * 0.22, Color(wet, 0.45))
	draw_line(top.position + Vector2(top.size.x * 0.5, 4.0), top.position + Vector2(top.size.x * 0.5, top.size.y - 4.0),
			Color(0.55, 0.6, 0.68, 0.7), 2.0)
	if hovered:
		draw_rect(top.grow(5.0), Color(1.0, 0.9, 0.5, 0.8), false, 3.0)
	var font: Font = ThemeDB.fallback_font
	draw_string_outline(font, top.position + Vector2(0.0, top.size.y + 26.0), "Салфетки", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 16, 4, Color.BLACK)
	draw_string(font, top.position + Vector2(0.0, top.size.y + 26.0), "Салфетки", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(1, 1, 1, 0.85))
