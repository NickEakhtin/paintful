extends Node3D
## The game level: studio upstairs, basement below. Runs the day loop so far:
## "Day N" card → the spirit speaks by the altar → go up and open the studio →
## clients come in one by one: talk at reception → they sit in the chair → session →
## they say goodbye and leave while the next one walks in.
## Roulette timing, workstation prep, cleanup and the third client's hypnosis come in step 7.

const SESSION_SCENE: PackedScene = preload("res://tattoo/tattoo_session.tscn")
const CLIENT_SCENE: PackedScene = preload("res://characters/client/client.tscn")
const SPIRIT_FIRST_DAY: DialogueData = preload("res://data/dialogues/spirit_day1.tres")
const SPIRIT_MORNING: DialogueData = preload("res://data/dialogues/spirit_morning.tres")
const CLIENTS: Array[ClientData] = [
	preload("res://data/clients/anton.tres"),
	preload("res://data/clients/marina.tres"),
	preload("res://data/clients/gleb.tres"),
]

var _next_client: int = 0
## In the chair, waiting for the session.
var _seated: Client = null
## Clients passing through the entrance right now; the door stays open while any are.
var _door_users: int = 0

@onready var _player: Player = $Player
@onready var _day_night: DayNight = $Lighting
@onready var _points: Node3D = $Points
@onready var _entrance: Door = $Studio/EntranceDoor
@onready var _seat_point: Marker3D = $Studio/TattooChair/SeatPoint
@onready var _chair: Interactable = $Studio/TattooChair/Interactable


func _ready() -> void:
	Transition.keep_black()
	Events.studio_opened.connect(_on_studio_opened)
	_set_chair_ready(false)
	_start_day()


func _unhandled_input(event: InputEvent) -> void:
	# Debug until the day flow (step 7) drives it: F2 flips day and night.
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		_day_night.set_night(not _day_night.is_night)


func _start_day() -> void:
	_day_night.set_night(false)
	_player.lock_controls(&"day_start")
	await Transition.show_title("День %d" % GameState.day)
	await Transition.fade_in()
	await Dialogue.play(SPIRIT_FIRST_DAY if GameState.day == 1 else SPIRIT_MORNING)
	_player.unlock_controls(&"day_start")
	Events.objective_changed.emit("Поднимись в студию и открой её")


func _on_studio_opened() -> void:
	Events.objective_changed.emit("Студия открыта. Сейчас придёт клиент")
	_send_next_client()


## The next client walks in from the street and waits at reception to be talked to.
func _send_next_client() -> void:
	if _next_client >= CLIENTS.size():
		return
	var client: Client = CLIENT_SCENE.instantiate()
	client.setup(CLIENTS[_next_client])
	_next_client += 1
	add_child(client)
	client.global_position = _point("Street")
	_use_entrance(true)
	await client.walk_to(_point("Entrance"))
	await client.walk_to(_point("ReceptionWait"))
	_use_entrance(false)
	client.face(_point("ReceptionWait") + Vector3.FORWARD) # towards the desk
	client.allow_talk(true)
	client.talk_requested.connect(_on_client_talk, CONNECT_ONE_SHOT)
	if _seated == null:
		Events.objective_changed.emit("Поговори с клиентом")


func _on_client_talk(client: Client) -> void:
	client.allow_talk(false)
	await Dialogue.play(client.data.greeting, client.head, client.data.display_name)
	Events.objective_changed.emit("Клиент садится в кресло")
	await client.walk_to(_point("ChairSeat"))
	client.sit(_seat_point)
	_seated = client
	_set_chair_ready(true)
	Events.objective_changed.emit("Начни сеанс")


func _on_tattoo_chair_interacted(_by: Player) -> void:
	if _seated == null:
		return
	var client: Client = _seated
	_set_chair_ready(false)
	_player.lock_controls(&"tattoo")
	await Transition.fade_out()
	var session: TattooSession = SESSION_SCENE.instantiate()
	add_child(session)
	await Transition.fade_in()
	session.roll_and_start(client.data.stencil)

	var result: SessionResult = await session.finished
	await Transition.fade_out()
	session.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await Transition.fade_in()
	_player.unlock_controls(&"tattoo")

	if result.is_perfect():
		client.set_eyes_glowing(true)
	await Dialogue.play(client.data.farewell, client.head, client.data.display_name)
	_seated = null
	client.stand_up(_point("ChairSeat"))
	if _next_client < CLIENTS.size():
		Events.objective_changed.emit("Следующий клиент уже идёт")
		_send_next_client()
	else:
		Events.objective_changed.emit("Клиентов на сегодня больше нет")
	_walk_out(client)


func _walk_out(client: Client) -> void:
	_use_entrance(true)
	await client.walk_to(_point("Entrance"))
	await client.walk_to(_point("Exit"))
	_use_entrance(false)
	client.queue_free()


func _use_entrance(using: bool) -> void:
	_door_users += 1 if using else -1
	if _door_users > 0 and not _entrance.is_open:
		_entrance.open()
	elif _door_users == 0 and _entrance.is_open:
		_entrance.close()


func _set_chair_ready(is_ready: bool) -> void:
	_chair.enabled = is_ready
	_chair.prompt = "Начать сеанс" if is_ready else ""


func _point(point_name: String) -> Vector3:
	return _points.get_node(point_name).global_position
