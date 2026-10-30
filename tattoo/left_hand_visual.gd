extends Node2D
## Placeholder look of the left hand, seen from above: palm at the origin, fingers up,
## the forearm in a dark sleeve running off toward the bottom-left of the screen.
## Swap this node for a sprite later; LeftHand only rotates it.

const SKIN: Color = Color(0.76, 0.56, 0.44)
const OUTLINE: Color = Color(0.22, 0.13, 0.1)
const SLEEVE: Color = Color(0.11, 0.09, 0.12)
## Outline thickness in pixels.
const EDGE: float = 3.0
## Where the forearm runs, from the wrist.
const ARM_DIRECTION: Vector2 = Vector2(-0.4, 1.0)

## [base, tip, radius] per finger, little finger first. The back of the hand faces us, so the thumb is on the right.
const FINGERS: Array[Array] = [
	[Vector2(-25.0, -22.0), Vector2(-31.0, -72.0), 8.5],
	[Vector2(-9.0, -29.0), Vector2(-11.0, -90.0), 9.5],
	[Vector2(8.0, -30.0), Vector2(8.0, -97.0), 10.0],
	[Vector2(25.0, -24.0), Vector2(29.0, -86.0), 9.5],
]
const THUMB: Array = [Vector2(32.0, 8.0), Vector2(64.0, -24.0), 11.0]


func _draw() -> void:
	var wrist: Vector2 = Vector2(-4.0, 38.0)
	var elbow: Vector2 = wrist + ARM_DIRECTION.normalized() * 600.0
	var cuff: Vector2 = wrist + ARM_DIRECTION.normalized() * 70.0
	# Outlines first, then fills, so every part reads as one shape.
	for pass_outline in [true, false]:
		var grow: float = EDGE if pass_outline else 0.0
		var skin: Color = OUTLINE if pass_outline else SKIN
		_capsule(wrist, cuff, 30.0 + grow, skin)
		_capsule(cuff, elbow, 38.0 + grow, OUTLINE if pass_outline else SLEEVE)
		for finger in FINGERS:
			_capsule(finger[0], finger[1], finger[2] + grow, skin)
		_capsule(THUMB[0], THUMB[1], THUMB[2] + grow, skin)
		_ellipse(Vector2(0.0, 2.0), Vector2(40.0, 44.0) + Vector2.ONE * grow, skin)
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
