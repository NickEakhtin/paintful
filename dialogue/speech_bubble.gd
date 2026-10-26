class_name SpeechBubble
extends DialogueView
## Comic speech bubble over a speaker's head in the 3D world, with a tail pointing at it.
## When the head is off screen, the bubble sticks to the screen edge and the tail points that way.

## How far above the anchor the tail ends, in metres.
@export var head_offset: float = 0.25
## Keeps the bubble this far from the screen edges, in pixels.
@export var margin: float = 24.0
@export var gap: float = 44.0

## The speaker's head. Dialogue sets it for client lines.
var anchor: Node3D

var _tip: Vector2 = Vector2.ZERO

@onready var _panel: PanelContainer = $Panel


func _process(_delta: float) -> void:
	if not visible:
		return
	var screen: Rect2 = get_viewport_rect()
	var target: Vector2 = screen.size * Vector2(0.5, 0.35)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if anchor != null and is_instance_valid(anchor) and camera != null:
		var point: Vector3 = anchor.global_position + Vector3.UP * head_offset
		target = camera.unproject_position(point)
		if camera.is_position_behind(point):
			# Behind the camera: unproject mirrors the point, push it to the bottom edge.
			target = Vector2(screen.size.x - target.x, screen.size.y)
	var inner: Rect2 = screen.grow(-margin)
	_tip = target.clamp(inner.position, inner.end)
	var size: Vector2 = _panel.size
	var top_left: Vector2 = _tip - Vector2(size.x * 0.5, size.y + gap)
	_panel.position = top_left.clamp(inner.position, inner.end - size)
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(_panel.position, _panel.size)
	var base_x: float = clampf(_tip.x, rect.position.x + 30.0, rect.end.x - 30.0)
	var base_y: float = rect.end.y - 3.0
	if _tip.y < rect.position.y:
		base_y = rect.position.y + 3.0 # head above the bubble: tail goes up
	var tail: PackedVector2Array = PackedVector2Array([
		Vector2(base_x - 14.0, base_y), Vector2(base_x + 14.0, base_y), _tip])
	draw_colored_polygon(tail, Color.WHITE)
	draw_line(tail[0], tail[2], Color.BLACK, 3.0, true)
	draw_line(tail[1], tail[2], Color.BLACK, 3.0, true)
