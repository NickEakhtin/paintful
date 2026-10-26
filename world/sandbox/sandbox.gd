extends Node3D
## Test ground for trying out features.

const SESSION_SCENE: PackedScene = preload("res://tattoo/tattoo_session.tscn")
const TEST_STENCIL: StencilData = preload("res://data/stencils/sigil/sigil.tres")
const TEST_CLIENT_DIALOGUE: DialogueData = preload("res://data/dialogues/test_client.tres")

@onready var _player: Player = $Player


func _ready() -> void:
	Events.objective_changed.emit("Положи иглу на стол")


func _on_needle_placed(_item: Item) -> void:
	Events.objective_changed.emit("Игла на месте")


func _on_day_sign_interacted(_by: Player) -> void:
	_player.lock_controls(&"title")
	GameState.start_new_day()
	await Transition.show_title("День %d" % GameState.day)
	await Transition.fade_in()
	_player.unlock_controls(&"title")


func _on_tattoo_chair_interacted(_by: Player) -> void:
	_player.lock_controls(&"tattoo")
	await Transition.fade_out()
	var session: TattooSession = SESSION_SCENE.instantiate()
	add_child(session)
	await Transition.fade_in()
	session.roll_and_start(TEST_STENCIL)

	var result: SessionResult = await session.finished
	await Transition.fade_out()
	session.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await Transition.fade_in()
	_player.unlock_controls(&"tattoo")
	Events.objective_changed.emit("Сеанс завершён — дух доволен" if result.is_perfect() else "Сеанс завершён — дух недоволен")


func _on_test_client_interacted(_by: Player) -> void:
	await Dialogue.play(TEST_CLIENT_DIALOGUE, $TestClient/Head, "Антон")
