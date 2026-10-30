class_name LeftHand
extends Node2D
## The artist's left hand in a tattoo session, for spirit tasks that need it (the right one holds the machine).
## WASD (`hand_*`) drive it over the screen with some inertia, Space (`hand_wave`) waves it.
## It knows nothing about tasks: a task adds it, sets `bounds`, calls `slide_in()` and listens to `waved`.
## Top-level, so it lives in screen pixels and stays put when the view swings to the ink cap.
## The origin is the palm centre; the look lives under `Visual`.

signal waved

## Pixels per second at full tilt.
@export var speed: float = 900.0
## How fast it gets up to speed and stops again; higher is snappier.
@export var acceleration: float = 14.0
## Seconds for one wave back and forth.
@export var wave_time: float = 0.3
## Degrees the hand leans per 1000 px/s of sideways speed.
@export var lean: float = 10.0

## Where the palm may go, in viewport pixels; empty = anywhere.
var bounds: Rect2 = Rect2()
var velocity: Vector2 = Vector2.ZERO
## Whether WASD and Space drive it; off while it slides in or out.
var active: bool = false

var _wave_angle: float = 0.0
var _wave: Tween

@onready var _visual: Node2D = $Visual
@onready var _swish: AudioStreamPlayer = $Swish


func _process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	if active and not Transition.is_busy:
		direction = Input.get_vector("hand_left", "hand_right", "hand_up", "hand_down")
	velocity = velocity.lerp(direction * speed, 1.0 - exp(-acceleration * delta))
	if active:
		position += velocity * delta
		if bounds.has_area():
			var clamped: Vector2 = position.clamp(bounds.position, bounds.end)
			# Stop dead against the edge instead of pushing into it.
			if clamped.x != position.x:
				velocity.x = 0.0
			if clamped.y != position.y:
				velocity.y = 0.0
			position = clamped
	_visual.rotation = deg_to_rad(velocity.x / 1000.0 * lean + _wave_angle)


func _unhandled_input(event: InputEvent) -> void:
	if active and not Transition.is_busy and event.is_action_pressed("hand_wave"):
		get_viewport().set_input_as_handled()
		wave()


## Where the palm is, in viewport pixels.
func palm() -> Vector2:
	return global_position


## A quick wave; `waved` fires at once, so a hit feels instant. A new wave may cut the old one short.
func wave() -> void:
	waved.emit()
	_swish.pitch_scale = randf_range(0.9, 1.15)
	_swish.play()
	if _wave != null:
		_wave.kill()
	_wave = create_tween()
	_wave.tween_property(self, "_wave_angle", -25.0, wave_time * 0.25).set_trans(Tween.TRANS_SINE)
	_wave.tween_property(self, "_wave_angle", 20.0, wave_time * 0.4).set_trans(Tween.TRANS_SINE)
	_wave.tween_property(self, "_wave_angle", 0.0, wave_time * 0.35).set_trans(Tween.TRANS_SINE)


## Comes in from `from` to `to` (viewport pixels), then takes WASD.
func slide_in(from: Vector2, to: Vector2, time: float = 0.3) -> void:
	active = false
	velocity = Vector2.ZERO
	position = from
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", to, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	active = true


## Drops WASD, slides off the bottom-left of the screen and frees itself.
func leave(time: float = 0.3) -> void:
	active = false
	var off: Vector2 = Vector2(-200.0, get_viewport_rect().size.y + 200.0)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", off, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
