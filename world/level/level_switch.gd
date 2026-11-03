class_name LevelSwitch
extends Node
## Takes the player between the studio and the basement through a black screen: down through the open hatch
## (it asks with `descend_requested`), up through the basement exit. Only the floor the player is on is shown;
## the other one is hidden, since it costs frame time even where it can't be seen.
## Anything in `companions` (a client following the player) travels along and lands behind them.

signal travelled(underground: bool)

@export var player: Player
@export var hatch: Node3D
@export var studio: Node3D
@export var basement: Node3D
## Where the player lands; looking along the marker's -Z.
@export var basement_landing: Marker3D
@export var studio_landing: Marker3D
## The way back up, in the basement.
@export var basement_exit: Interactable
## Seconds the screen stays black between fading out and in.
@export var black_time: float = 0.6

var underground: bool = false
var companions: Array[Node3D] = []

var _busy: bool = false


func _ready() -> void:
	hatch.descend_requested.connect(func(_p: Player) -> void: _travel(true))
	basement_exit.interacted.connect(func(_p: Player) -> void: _travel(false))
	basement_exit.prompt = "Подняться в студию"
	# the day starts by the altar: show the floor whose landing the player is nearer to
	var to_basement: float = player.global_position.distance_to(basement_landing.global_position)
	_show(to_basement < player.global_position.distance_to(studio_landing.global_position))


func _travel(down: bool) -> void:
	if _busy or down == underground:
		return
	_busy = true
	player.lock_controls(&"level_switch")
	await Transition.fade_out()
	var landing: Marker3D = basement_landing if down else studio_landing
	player.global_transform = landing.global_transform
	player.velocity = Vector3.ZERO
	for i in companions.size():
		var companion: Node3D = companions[i]
		if is_instance_valid(companion):
			companion.global_position = landing.global_transform * Vector3(0.4 * (i % 2 * 2 - 1), 0.0, 1.2 + 0.6 * (i / 2))
	if hatch.has_method(&"close_now"):
		hatch.call(&"close_now")   # the way down is shut behind you, and closed when you come back up
	_show(down)
	await get_tree().create_timer(black_time).timeout
	await Transition.fade_in()
	player.unlock_controls(&"level_switch")
	_busy = false
	travelled.emit(down)


func _show(down: bool) -> void:
	underground = down
	studio.visible = not down
	basement.visible = down
	basement_exit.enabled = down
	Events.underground_changed.emit(down)
