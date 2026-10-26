extends Node3D
## The game level: studio upstairs, basement below. Runs the start of the day loop:
## "Day N" card → the spirit speaks by the altar → go up and open the studio.
## Clients (steps 6–7) take over once the studio is open.

const SESSION_SCENE: PackedScene = preload("res://tattoo/tattoo_session.tscn")
const TEST_STENCIL: StencilData = preload("res://data/stencils/sigil/sigil.tres")
const SPIRIT_FIRST_DAY: DialogueData = preload("res://data/dialogues/spirit_day1.tres")
const SPIRIT_MORNING: DialogueData = preload("res://data/dialogues/spirit_morning.tres")

@onready var _player: Player = $Player
@onready var _day_night: DayNight = $Lighting
@onready var _sign: OpenSign = $Studio/OpenSign


func _ready() -> void:
	Transition.keep_black()
	Events.studio_opened.connect(_on_studio_opened)
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
	Events.objective_changed.emit("Студия открыта. Жди клиента")


# Temporary until clients arrive (step 7): the chair runs a test session.
func _on_tattoo_chair_interacted(_by: Player) -> void:
	_player.lock_controls(&"tattoo")
	await Transition.fade_out()
	var session: TattooSession = SESSION_SCENE.instantiate()
	add_child(session)
	await Transition.fade_in()
	session.roll_and_start(TEST_STENCIL)

	await session.finished
	await Transition.fade_out()
	session.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await Transition.fade_in()
	_player.unlock_controls(&"tattoo")
