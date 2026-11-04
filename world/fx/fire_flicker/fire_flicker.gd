@tool
extends Node
## Fire flicker for the warm lamps: every orange OmniLight3D / SpotLight3D in the scene gently breathes brighter and
## dimmer like a flame, each on its own rhythm. Lights of other colours are left alone.
## Also plays in the editor (`preview_in_editor`): the lights' own energies are put back before every save, and an
## energy you change in the inspector becomes that light's new base, so the saved values never drift.

@export var strength: float = 0.2               # how far the energy swings, as a share of the light's own energy
@export var speed: float = 1.0
@export var preview_in_editor: bool = true:
	set(value):
		preview_in_editor = value
		if not value:
			_restore()

var _lights: Array = []                   # [light, base energy, noise offset, last energy we set]
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0
var _paused: bool = false


func _ready() -> void:
	_noise.frequency = 1.0
	var scene_root: Node = owner if owner else get_parent()
	for light: Light3D in scene_root.find_children("*", "Light3D", true, false):
		var c: Color = light.light_color
		if light is DirectionalLight3D or c.s < 0.4 or c.h < 0.02 or c.h > 0.14:   # orange hues only
			continue
		_lights.append([light, light.light_energy, randf() * 1000.0, light.light_energy])


func _process(delta: float) -> void:
	if _paused or (Engine.is_editor_hint() and not preview_in_editor):
		return
	_time += delta * speed
	for entry in _lights:
		var light: Light3D = entry[0]
		if not is_instance_valid(light):
			continue
		if not is_equal_approx(light.light_energy, entry[3]):   # changed by hand: that is the new base
			entry[1] = light.light_energy
		# slow sway of the flame plus a faint fast crackle
		var n: float = _noise.get_noise_1d(_time * 1.3 + entry[2]) * 0.75 + _noise.get_noise_1d(_time * 7.0 + entry[2] * 2.0) * 0.25
		light.light_energy = entry[1] * (1.0 + strength * 2.0 * n)
		entry[3] = light.light_energy


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_paused = true
		_restore()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_paused = false
	elif what == NOTIFICATION_EXIT_TREE:
		_restore()


func _restore() -> void:
	for entry in _lights:
		if is_instance_valid(entry[0]):
			entry[0].light_energy = entry[1]
			entry[3] = entry[1]
