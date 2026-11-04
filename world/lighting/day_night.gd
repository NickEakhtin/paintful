class_name DayNight
extends Node3D
## Switches the level between day and night. Night is the colleague's scene as he lit it (a stormy evening: moonlit
## sun, dark fog behind the windows, frequent lightning); its values are read on start. Day is a grey rainy day:
## brighter daylight and ambient, pale fog outside, rare lightning. At night the studio's lamps dim by
## `night_lamp_factor` and the candles in the ritual circle burn. The sun goes out while the player is underground.

@export var sun: DirectionalLight3D
@export var environment: WorldEnvironment
## Every Light3D under this is a studio lamp...
@export var studio: Node3D
## ...except those under these (street lamps, the neon sign, the sky's lightning).
@export var keep_lit: Array[Node3D] = []
## The sky sphere; its `lightning_interval` changes with the time of day.
@export var sky: Node
@export var night_lamp_factor: float = 0.7
@export_group("Day")
@export var day_sun_color: Color = Color(0.72, 0.76, 0.86)
@export var day_sun_energy: float = 2.2
@export var day_ambient_energy: float = 0.75
@export var day_background: Color = Color(0.52, 0.54, 0.58)
## Colour of the fog curtains behind the door and windows.
@export var day_fog_color: Color = Color(0.42, 0.44, 0.5)
@export var day_lightning_interval: Vector2 = Vector2(25.0, 60.0)

var is_night: bool = false

var _lamp_energy: Dictionary[Light3D, float] = {}
var _night_sun_color: Color
var _night_sun_energy: float
var _night_ambient_energy: float
var _night_background: Color
var _night_fog_color: Dictionary[Node, Color] = {}
var _night_lightning_interval: Vector2
var _underground: bool = false


func _ready() -> void:
	# read before the fire flicker's first frame moves anything
	for light: Light3D in studio.find_children("*", "Light3D", true, false):
		if not _kept(light):
			_lamp_energy[light] = light.light_energy
	_night_sun_color = sun.light_color
	_night_sun_energy = sun.light_energy
	_night_ambient_energy = environment.environment.ambient_light_energy
	_night_background = environment.environment.background_color
	for fog: Node in get_tree().get_nodes_in_group(&"lightning_fog"):
		_night_fog_color[fog] = fog.get(&"color")
	if sky != null:
		_night_lightning_interval = sky.get(&"lightning_interval")
	Events.underground_changed.connect(func(underground: bool) -> void:
		_underground = underground
		sun.visible = not underground)


func set_night(night: bool) -> void:
	is_night = night
	sun.visible = not _underground
	sun.light_color = _night_sun_color if night else day_sun_color
	sun.light_energy = _night_sun_energy if night else day_sun_energy
	environment.environment.ambient_light_energy = _night_ambient_energy if night else day_ambient_energy
	environment.environment.background_color = _night_background if night else day_background
	for fog: Node in _night_fog_color:
		fog.set(&"color", _night_fog_color[fog] if night else day_fog_color)
	if sky != null:
		sky.set(&"lightning_interval", _night_lightning_interval if night else day_lightning_interval)
	for light: Light3D in _lamp_energy:
		light.light_energy = _lamp_energy[light] * (night_lamp_factor if night else 1.0)
	for spot in get_tree().get_nodes_in_group(&"candle_spot"):
		(spot as CandleSpot).lit = night


func _kept(node: Node) -> bool:
	for root: Node3D in keep_lit:
		if root == node or root.is_ancestor_of(node):
			return true
	return false
