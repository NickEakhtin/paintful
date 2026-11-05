extends Node3D
## Test client by the basement pit: LMB on them opens a tattoo session at once (no fade, no roulette, no day
## loop), for working on the inking. Remove the node from `basement.tscn` when it's no longer needed.

const SESSION_SCENE: PackedScene = preload("res://tattoo/tattoo_session.tscn")

## Who sits for the test; their `stencil` is inked.
@export var client_data: ClientData

var _session: TattooSession = null

@onready var _client: Client = $Client


func _ready() -> void:
	_client.setup(client_data)
	_client.allow_talk(true, "Набить татуировку")
	_client.talk_requested.connect(func(_c: Client) -> void: _tattoo())


func _tattoo() -> void:
	if _session != null:
		return
	var player: Player = get_tree().get_first_node_in_group(&"player")
	if player != null:
		player.lock_controls(&"tattoo_test")
	_session = SESSION_SCENE.instantiate()
	get_tree().current_scene.add_child(_session)
	_session.start(client_data.stencil)
	await _session.finished
	_session.queue_free()
	_session = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if player != null:
		player.unlock_controls(&"tattoo_test")
