class_name NeedleCartridge
extends Control
## A needle cartridge standing on the side table (placeholder look in `_draw`): a grip with ridges and a coloured
## tip. The session hit-tests this control's rect; LMB on it swaps the machine's needle for this one. While this
## needle is in the machine (`taken`), only its empty slot shows.

## The tip's colour; the machine's needle glows the same while this one is in it.
@export var color: Color = Color(0.55, 0.2, 0.75)
## The label under it.
@export var title: String = ""
## Thin needles get a slimmer body.
@export var slim: bool = false

## In the machine: the table shows an empty slot.
var taken: bool = false:
	set(value):
		taken = value
		queue_redraw()

var _flash: float = 0.0


## A short highlight when it's put back or picked up.
func flash() -> void:
	_flash = 1.0
	set_process(true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	queue_redraw()
	if _flash <= 0.0:
		set_process(false)


func _draw() -> void:
	var width: float = size.x * (0.42 if slim else 0.6)
	var x: float = (size.x - width) * 0.5
	var base: Rect2 = Rect2(x - 6.0, size.y - 34.0, width + 12.0, 10.0)
	# the slot in the stand
	draw_rect(base, Color(0.08, 0.06, 0.07, 0.9))
	if taken:
		draw_rect(Rect2(x, size.y * 0.2, width, size.y * 0.8 - 34.0), Color(1, 1, 1, 0.12), false, 2.0)
	else:
		var glow: Color = Color.WHITE.lerp(color, 0.5)
		# the tip at the top, the grip below it
		var tip_height: float = size.y * 0.22
		var tip_top: Vector2 = Vector2(size.x * 0.5, 0.0)
		draw_colored_polygon(PackedVector2Array([tip_top, Vector2(x + width * 0.3, tip_height),
				Vector2(x + width * 0.7, tip_height)]), color.lerp(glow, _flash))
		var body: Rect2 = Rect2(x, tip_height, width, size.y - 34.0 - tip_height)
		draw_rect(body, Color(0.16, 0.15, 0.18).lerp(glow, _flash * 0.4))
		draw_rect(Rect2(x, tip_height, width, 10.0), color.darkened(0.2))
		for i in 6:   # grip ridges
			var y: float = body.position.y + 22.0 + i * (body.size.y - 30.0) / 6.0
			draw_line(Vector2(x + 3.0, y), Vector2(x + width - 3.0, y), Color(0.3, 0.29, 0.33), 2.0)
	if not title.is_empty():
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 16
		var text_width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string_outline(font, Vector2((size.x - text_width) * 0.5, size.y - 6.0), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
		draw_string(font, Vector2((size.x - text_width) * 0.5, size.y - 6.0), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.5 if taken else 0.85))
