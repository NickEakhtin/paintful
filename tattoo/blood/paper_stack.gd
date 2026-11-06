extends Node2D
## A stack of wet paper towels lying at the left of the screen: the artist's left hand takes one with Space. The
## sheets are drawn with `wet_paper.gdshader` (each its own blotches), a little crumpled and off the one under it;
## the hover frame and the label go over them. `rect` is set by the skin, in its own pixels.

const WET_PAPER: Shader = preload("res://tattoo/blood/wet_paper.gdshader")
const SHEETS: int = 4

var rect: Rect2 = Rect2(30.0, 400.0, 150.0, 90.0):
	set(value):
		rect = value
		queue_redraw()
		if _sheets != null:
			_sheets.queue_redraw()
			for sheet: Node2D in _sheets.get_children():
				sheet.queue_redraw()
## The hand is over it: it lights up a little.
var hovered: bool = false:
	set(value):
		if value != hovered:
			hovered = value
			queue_redraw()

var _sheets: Node2D


func _ready() -> void:
	_sheets = Node2D.new()
	_sheets.name = "Sheets"
	_sheets.show_behind_parent = true
	# a soft shadow under the stack, drawn before the sheets
	_sheets.draw.connect(func() -> void:
		_sheets.draw_rect(Rect2(rect.position + Vector2(6.0, 8.0), rect.size), Color(0.0, 0.0, 0.0, 0.35)))
	add_child(_sheets)
	for i in SHEETS:
		var sheet: Node2D = Node2D.new()
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = WET_PAPER
		shader_material.set_shader_parameter("seed", Vector2(i * 7.3 + 1.0, i * 3.1 + 5.0))
		shader_material.set_shader_parameter("wet", 0.7 + 0.08 * i)
		sheet.material = shader_material
		sheet.draw.connect(_draw_sheet.bind(sheet, i))
		_sheets.add_child(sheet)


## Sheet `i` (0 at the bottom): the rect shifted and its corners nudged, a soft shadow under it.
func _draw_sheet(sheet: Node2D, i: int) -> void:
	var r: Rect2 = _sheet_rect(i)
	var nudge: float = r.size.x * 0.015
	var corners: PackedVector2Array = PackedVector2Array([
		r.position + Vector2(sin(i * 2.1) * nudge, cos(i * 1.3) * nudge),
		Vector2(r.end.x, r.position.y) + Vector2(cos(i * 1.7) * nudge, sin(i * 2.9) * nudge),
		r.end + Vector2(sin(i * 3.3) * nudge, cos(i * 2.2) * nudge),
		Vector2(r.position.x, r.end.y) + Vector2(cos(i * 0.9) * nudge, sin(i * 1.1) * nudge),
	])
	var shade: float = 0.8 + 0.2 * float(i) / (SHEETS - 1)   # lower sheets in the upper ones' shadow
	sheet.draw_polygon(corners, PackedColorArray([Color(shade, shade, shade)]),
			PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))


func _sheet_rect(i: int) -> Rect2:
	var step: float = rect.size.y * 0.04
	return Rect2(rect.position + Vector2(sin(i * 1.7) * step, -i * step), rect.size)


func _draw() -> void:
	var top: Rect2 = _sheet_rect(SHEETS - 1)
	if hovered:
		draw_rect(top.grow(5.0), Color(1.0, 0.9, 0.5, 0.8), false, 3.0)
	var font: Font = ThemeDB.fallback_font
	var at: Vector2 = Vector2(rect.position.x, rect.end.y + 26.0)
	draw_string_outline(font, at, "Салфетки", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
	draw_string(font, at, "Салфетки", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
