class_name DayFlow
extends Node
## The day loop from CLAUDE.md, written top to bottom as one script:
## "Day N" → the spirit by the altar → open the studio → for each client: talk → the spirit's
## roulette → prepare the table → call them to the chair → tattoo → (1st, 2nd) the spirit's
## verdict, goodbye, tidy up while the next one walks in / (3rd) the spirit claims them →
## close the studio → night. The basement ritual continues in step 8.

const CLIENT_SCENE: PackedScene = preload("res://characters/client/client.tscn")
const SESSION_SCENE: PackedScene = preload("res://tattoo/tattoo_session.tscn")
const ROULETTE_SCENE: PackedScene = preload("res://ui/roulette/roulette.tscn")
const SPIRIT_FIRST_DAY: DialogueData = preload("res://data/dialogues/spirit_day1.tres")
const SPIRIT_MORNING: DialogueData = preload("res://data/dialogues/spirit_morning.tres")
const SPIRIT_ROULETTE: DialogueData = preload("res://data/dialogues/spirit_roulette.tres")
const SPIRIT_PLEASED: DialogueData = preload("res://data/dialogues/spirit_pleased.tres")
const SPIRIT_DISPLEASED: DialogueData = preload("res://data/dialogues/spirit_displeased.tres")
const SPIRIT_CHOSEN: DialogueData = preload("res://data/dialogues/spirit_chosen.tres")
const PLAYER_READY: DialogueData = preload("res://data/dialogues/player_ready.tres")

## What a session may need on the table, and how the objective names it ("принеси …").
const PREP_ITEMS: Dictionary[StringName, String] = {&"needle": "иглу", &"ink": "краску", &"gloves": "перчатки"}
## How many of PREP_ITEMS each session needs.
const PREP_COUNT: int = 2

@export var clients: Array[ClientData] = []
@export var task_pool: Array[ModifierData] = []
@export var player: Player
@export var day_night: DayNight
@export var points: Node3D
@export var entrance: Door
@export var open_sign: OpenSign
@export var workstation: Workstation
@export var seat_point: Marker3D

## Clients passing through the entrance right now; the door stays open while any are.
var _door_users: int = 0
var _arrived: Dictionary[Client, bool] = {}
var _session: TattooSession = null


func _ready() -> void:
	Transition.keep_black()
	_run_day()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_F2: # debug: flip day and night
			day_night.set_night(not day_night.is_night)
		KEY_F3: # debug: finish the current tattoo at once
			if is_instance_valid(_session) and _session.canvas != null:
				var canvas: InkCanvas = _session.canvas
				for part in canvas.part_count():
					for cell in canvas._part_cells[part]:
						@warning_ignore("integer_division")
						canvas.stamp(Vector2(cell % InkCanvas.SIZE + 0.5, cell / InkCanvas.SIZE + 0.5), 0.5, 1.0)


func _run_day() -> void:
	await _morning()
	Events.objective_changed.emit("Поднимись в студию и открой её")
	await Events.studio_opened
	Events.objective_changed.emit("Студия открыта. Сейчас придёт клиент")

	var next: Client = _bring_in(clients[0])
	for i in clients.size():
		GameState.client_index = i
		var client: Client = next
		var is_last: bool = i == clients.size() - 1
		await _greet(client)
		var tasks: Array[ModifierData] = await _spirit_roulette()
		await _prepare_table(client)
		await _call_to_chair(client)
		var result: SessionResult = await _tattoo(client, tasks)
		if is_last:
			await _spirit_claims(client)
		else:
			await Dialogue.play(SPIRIT_PLEASED if result.is_perfect() else SPIRIT_DISPLEASED)
			await Dialogue.play(client.data.farewell, client.head, client.data.display_name)
			client.stand_up(_point("ChairSeat"))
			next = _bring_in(clients[i + 1])
			_walk_out(client)
			await _tidy_up()

	open_sign.can_close = true
	Events.objective_changed.emit("Закрой студию")
	await Events.studio_closed
	await _nightfall()


func _morning() -> void:
	day_night.set_night(false)
	player.lock_controls(&"day_start")
	await Transition.show_title("День %d" % GameState.day)
	await Transition.fade_in()
	await Dialogue.play(SPIRIT_FIRST_DAY if GameState.day == 1 else SPIRIT_MORNING)
	player.unlock_controls(&"day_start")


## Spawns a client on the street and walks them in to reception. Doesn't wait.
func _bring_in(data: ClientData) -> Client:
	var client: Client = CLIENT_SCENE.instantiate()
	client.setup(data)
	add_child(client)
	client.global_position = _point("Street")
	_walk_in(client)
	return client


func _walk_in(client: Client) -> void:
	_use_entrance(true)
	await client.walk_to(_point("Entrance"))
	await client.walk_to(_point("ReceptionWait"))
	_use_entrance(false)
	client.face(_point("ReceptionWait") + Vector3.FORWARD) # towards the desk
	_arrived[client] = true


## Waits for the client at reception (and a tidy table), then plays their greeting.
func _greet(client: Client) -> void:
	while not _arrived.get(client, false):
		await get_tree().process_frame
	Events.objective_changed.emit("Поговори с клиентом")
	client.allow_talk(true)
	await client.talk_requested
	client.allow_talk(false)
	await Dialogue.play(client.data.greeting, client.head, client.data.display_name)


func _spirit_roulette() -> Array[ModifierData]:
	await Dialogue.play(SPIRIT_ROULETTE)
	player.lock_controls(&"roulette")
	var roulette: Roulette = ROULETTE_SCENE.instantiate()
	add_child(roulette)
	var tasks: Array[ModifierData] = await roulette.spin(task_pool)
	roulette.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.unlock_controls(&"roulette")
	return tasks


## The client waits on the bench while the player brings the needed items to the table.
func _prepare_table(client: Client) -> void:
	var needed: Array[StringName] = Array(PREP_ITEMS.keys(), TYPE_STRING_NAME, &"", null)
	needed.shuffle()
	workstation.set_required(needed.slice(0, PREP_COUNT))
	client.allow_talk(true, "Место ещё не готово", false)
	client.walk_to(_point("BenchWait"))
	while not workstation.has_required():
		var names: PackedStringArray = PackedStringArray()
		for id in workstation.missing():
			names.append(PREP_ITEMS[id])
		Events.objective_changed.emit("Подготовь место: принеси на стол %s" % ", ".join(names))
		await workstation.contents_changed


func _call_to_chair(client: Client) -> void:
	Events.objective_changed.emit("Место готово. Позови клиента")
	client.allow_talk(true, "Позвать в кресло")
	await client.talk_requested
	client.allow_talk(false)
	await Dialogue.play(PLAYER_READY, client.head, client.data.display_name)
	Events.objective_changed.emit("")
	await client.walk_to(_point("ChairSeat"))
	client.sit(seat_point)


func _tattoo(client: Client, tasks: Array[ModifierData]) -> SessionResult:
	player.lock_controls(&"tattoo")
	await Transition.fade_out()
	_session = SESSION_SCENE.instantiate()
	add_child(_session)
	_session.start(client.data.stencil, tasks)
	await Transition.fade_in()
	var result: SessionResult = await _session.finished
	await Transition.fade_out()
	_session.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await Transition.fade_in()
	player.unlock_controls(&"tattoo")
	return result


func _walk_out(client: Client) -> void:
	_use_entrance(true)
	await client.walk_to(_point("Entrance"))
	await client.walk_to(_point("Exit"))
	_use_entrance(false)
	_arrived.erase(client)
	client.queue_free()


func _tidy_up() -> void:
	if workstation.is_empty():
		return
	Events.objective_changed.emit("Убери рабочее место")
	workstation.cleanup_needed = true
	await workstation.cleaned_up


## The last client of the day is the one: eyes light up and they stay, held by the spirit.
func _spirit_claims(client: Client) -> void:
	client.stand_up(_point("ChairSeat"))
	client.face(player.global_position)
	client.hypnotize()
	await Dialogue.play(SPIRIT_CHOSEN, client.head, client.data.display_name)


func _nightfall() -> void:
	player.lock_controls(&"nightfall")
	await Transition.fade_out(1.0)
	day_night.set_night(true)
	await Transition.fade_in(1.0)
	player.unlock_controls(&"nightfall")
	Events.objective_changed.emit("Спустись в подвал и подготовь ритуал")


func _use_entrance(using: bool) -> void:
	_door_users += 1 if using else -1
	if _door_users > 0 and not entrance.is_open:
		entrance.open()
	elif _door_users == 0 and entrance.is_open:
		entrance.close()


func _point(point_name: String) -> Vector3:
	return points.get_node(point_name).global_position
