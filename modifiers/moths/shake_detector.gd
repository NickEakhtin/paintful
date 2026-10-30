class_name ShakeDetector
extends RefCounted
## Spots a shake in a stream of mouse positions: a quick, straight swing that sharply turns back.
## Ordinary strokes and curves along a stencil don't count, so a shake can't happen by accident.

## A swing shorter than this, in pixels, doesn't count.
var min_stroke: float = 40.0
## Nor one slower than this on average, in pixels per second.
var min_speed: float = 600.0
## Where the last counted swing went, so whatever is shaken off can fly that way.
var direction: Vector2 = Vector2.ZERO

var _last: Vector2 = Vector2.INF
## The current swing: its overall heading, length and duration.
var _stroke: Vector2 = Vector2.ZERO
var _stroke_length: float = 0.0
var _stroke_time: float = 0.0


## Feed the mouse position every frame; true on the frame a swing turns back sharply.
func feed(position: Vector2, delta: float) -> bool:
	var move: Vector2 = position - _last if _last.is_finite() else Vector2.ZERO
	_last = position
	_stroke_time += delta
	if move.length() < 0.5:
		return false
	# More than 120° away from where the swing was going: it turned back.
	if _stroke != Vector2.ZERO and move.normalized().dot(_stroke.normalized()) < -0.5:
		# A shake swings straight; a fast curve around a ring bends a long way before it turns back.
		var counted: bool = _stroke_length >= min_stroke and _stroke_length / _stroke_time >= min_speed \
				and _stroke.length() >= 0.7 * _stroke_length
		if counted:
			direction = move.normalized()
		_stroke = move
		_stroke_length = move.length()
		_stroke_time = delta
		return counted
	_stroke += move
	_stroke_length += move.length()
	return false
