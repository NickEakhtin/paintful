extends Node2D
## Placeholder look of the left hand: just the hand, floating in the air, seen from the back,
## palm at the origin, fingers up. Swap this node for a sprite later; LeftHand only rotates it.

const SKIN: Color = Color(0.76, 0.56, 0.44)
const OUTLINE: Color = Color(0.22, 0.13, 0.1)
## Outline thickness in pixels.
const EDGE: float = 3.0

## [base, tip, radius] per finger, little finger first. The back of the hand faces us, so the thumb is on the right.
const FINGERS: Array[Array] = [
	[Vector2(-25.0, -22.0), Vector2(-31.0, -72.0), 8.5],
	[Vector2(-9.0, -29.0), Vector2(-11.0, -90.0), 9.5],
	[Vector2(8.0, -30.0), Vector2(8.0, -97.0), 10.0],
	[Vector2(25.0, -24.0), Vector2(29.0, -86.0), 9.5],
]
const THUMB: Array = [Vector2(32.0, 8.0), Vector2(64.0, -24.0), 11.0]
## A short rounded wrist under the palm, so the hand doesn't end in a flat cut.
const WRIST: Array = [Vector2(0.0, 20.0), Vector2(-3.0, 52.0), 27.0]


func _draw() -> void:
	# Outlines first, then fills, so every part reads as one shape.
	for pass_outline in [true, false]:
		var grow: float = EDGE if pass_outline else 0.0
		var color: Color = OUTLINE if pass_outline else SKIN
		_capsule(WRIST[0], WRIST[1], WRIST[2] + grow, color)
		for finger in FINGERS:
			_capsule(finger[0], finger[1], finger[2] + grow, color)
		_capsule(THUMB[0], THUMB[1], THUMB[2] + grow, color)
		_ellipse(Vector2(0.0, 2.0), Vector2(40.0, 44.0) + Vector2.ONE * grow, color)
	# Gaps between the fingers, so they don't melt into one paddle.
	for i in FINGERS.size() - 1:
		var a: Array = FINGERS[i]
		var b: Array = FINGERS[i + 1]
		var from: Vector2 = (a[0] + b[0]) * 0.5 + Vector2(0.0, -12.0)
		var to: Vector2 = (a[1] + b[1]) * 0.5 + Vector2(0.0, 14.0)
		draw_line(from, from.lerp(to, 0.35), OUTLINE, 2.0, true)


func _capsule(from: Vector2, to: Vector2, radius: float, color: Color) -> void:
	draw_line(from, to, color, radius * 2.0, true)
	draw_circle(from, radius, color)
	draw_circle(to, radius, color)


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, radii / radii.x)
	draw_circle(Vector2.ZERO, radii.x, color)
	draw_set_transform(Vector2.ZERO)
