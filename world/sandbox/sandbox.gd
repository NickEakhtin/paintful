extends Node3D
## Test ground for trying out features.

const SESSION_SCENE: PackedScene = preload("res://tattoo/tattoo_session.tscn")
const TEST_STENCIL: StencilData = preload("res://data/stencils/sigil/sigil.tres")

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
	session.start(TEST_STENCIL)
	await Transition.fade_in()

	var result: SessionResult = await session.finished
	await Transition.fade_out()
	session.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await Transition.fade_in()
	_player.unlock_controls(&"tattoo")
	Events.objective_changed.emit("Сеанс завершён — дух доволен" if result.is_perfect() else "Сеанс завершён — дух недоволен")
