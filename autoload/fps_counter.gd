extends CanvasLayer
## FPS in the top left corner, over everything (the game, a tattoo session, dialogues). F9 hides and shows it.

## How often the number updates, in seconds.
@export var refresh: float = 0.25

var _label: Label = Label.new()
var _wait: float = 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label.position = Vector2(8, 6)
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_color", Color(0.75, 1.0, 0.6))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = refresh
	_label.text = "%d FPS" % roundi(Engine.get_frames_per_second())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		visible = not visible
