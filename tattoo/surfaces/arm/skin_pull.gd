class_name SkinPull
extends RefCounted
## The left hand pulling the forearm skin, as numbers. Pure logic: the caller feeds it the keys.
## Holding left or right pulls that side toward a full pull, quickly at first and tighter near the end;
## up/down while pulling tilt the pull (the angle stays when they're let go). Up or down alone does nothing:
## the stencil is hidden only at the sides. Letting go of the side key lets the skin slide back.
## Switching sides lets go first and grips the other side once the skin is back.

## Steepest pull, from horizontal.
var max_angle: float = deg_to_rad(60.0)
## How quickly a held pull closes in on a full one (per second, exponential).
var pull_rate: float = 4.5
## How quickly the skin slides back once let go (per second, exponential).
var return_rate: float = 10.0
## How fast up/down tilt the pull, radians per second.
var tilt_speed: float = deg_to_rad(80.0)

## -1 left, 1 right, 0 nothing held.
var side: int = 0
## 0..1 of a full pull.
var amount: float = 0.0
## Tilt of the pull, positive = up.
var angle: float = 0.0


func update(delta: float, left: bool, right: bool, up: bool, down: bool) -> void:
	var want: int = 0
	if left != right:
		want = -1 if left else 1
	if want != 0 and (side == want or amount <= 0.0):
		if side != want:
			side = want
			angle = 0.0
		amount += (1.0 - amount) * (1.0 - exp(-pull_rate * delta))
		var tilt: float = (1.0 if up else 0.0) - (1.0 if down else 0.0)
		angle = clampf(angle + tilt * tilt_speed * delta, -max_angle, max_angle)
		return
	amount = move_toward(amount * exp(-return_rate * delta), 0.0, delta * 0.5)
	if amount <= 0.0:
		release()


## Vertical drag of the grip for a pull of `max_pull` pixels, in pixels (negative = up).
func shear(max_pull: float) -> float:
	return -tan(angle) * amount * max_pull


func release() -> void:
	side = 0
	amount = 0.0
	angle = 0.0
