class_name TattooModifier
extends Node2D
## A spirit task that makes a tattoo session harder. The session adds it on top of the skin,
## so it moves with the skin and can draw there (spiders). Extend it and override what you need.

## The session this task runs in. Set before the node enters the tree.
var session: TattooSession
var data: ModifierData


## Extra needle movement in viewport pixels, added after the magnet.
func needle_offset() -> Vector2:
	return Vector2.ZERO


## How far the skin and stencil are pushed, in viewport pixels.
func skin_offset() -> Vector2:
	return Vector2.ZERO


## Extra mass this task hangs on the machine; it follows the hand slower and swings more.
func machine_weight() -> float:
	return 0.0


## Whether the needle may lay ink right now; the machine stays silent while any task says no.
func can_ink() -> bool:
	return true


## One line for the session HUD; empty hides it.
func status_text() -> String:
	return title()


## Task name as the roulette shows it.
func title() -> String:
	return data.display_name


## Whether the spirit is satisfied. Asked once the tattoo is done.
func is_passed() -> bool:
	return true


## Called once when the tattoo is done. Override to clean up, and call super().
func stop() -> void:
	set_process(false)
	set_process_input(false)
