class_name ChatBubble
extends Control
## A comic speech bubble with the chatty client's question, sitting on a corner of the stencil.
## The origin is the bubble centre; the panel centres itself around it whatever the text's size.
## Pops in, types its text, sways a little, and pops away on `pop()`.

## Which quarter of the stencil it covers: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
var corner: int = 0
## The tail points up (toward the client's face) instead of down.
var tail_up: bool = false
## Letters per second.
var type_speed: float = 40.0
var popped: bool = false

var _typed: float = 0.0
var _time: float = randf() * TAU

@onready var _panel: PanelContainer = $Panel
@onready var _text: RichTextLabel = $Panel/Text


func _ready() -> void:
	_panel.resized.connect(_center)
	_center()


func _process(delta: float) -> void:
	_time += delta
	_typed += type_speed * delta
	_text.visible_characters = int(_typed)
	# The label first measures itself at zero width (a letter per line) and the panel never shrinks on its own.
	_panel.reset_size()
	if not popped:
		rotation = deg_to_rad(1.2 * sin(_time * 1.7))


func _draw() -> void:
	# The tail sits behind the panel, so only its outer part shows.
	var half: Vector2 = _panel.size * 0.5
	var side: float = -1.0 if tail_up else 1.0
	var base_x: float = -half.x * 0.35 if corner % 2 == 0 else half.x * 0.35
	var base_y: float = side * (half.y - 6.0)
	var tip: Vector2 = Vector2(base_x * 1.5, side * (half.y + 30.0))
	var tail: PackedVector2Array = PackedVector2Array([
		Vector2(base_x - 16.0, base_y), Vector2(base_x + 16.0, base_y), tip])
	draw_colored_polygon(tail, Color.WHITE)
	draw_line(tail[0], tip, Color.BLACK, 3.0, true)
	draw_line(tail[1], tip, Color.BLACK, 3.0, true)


## The bubble's panel on screen, in canvas pixels (the same space as the left hand).
func hit_rect() -> Rect2:
	return _panel.get_global_rect()


## Shows up with a little bounce and starts typing `text`.
func pop_in(text: String) -> void:
	_text.text = "[center]%s[/center]" % text
	_text.visible_characters = 0
	_typed = 0.0
	scale = Vector2.ONE * 0.3
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 1.05, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.08)


## Puffs up, fades and frees itself. Safe to call twice.
func pop() -> void:
	if popped:
		return
	popped = true
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ONE * 1.2, 0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(queue_free)


func _center() -> void:
	_panel.position = -_panel.size * 0.5
	queue_redraw()
