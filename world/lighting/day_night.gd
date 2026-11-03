class_name DayNight
extends Node3D
## Switches the level between day and night: sun through the window, studio lamps (dimmed by
## `night_lamp_factor` from the energies they were given), the street backdrop if there is one,
## and candles in the ritual circle (they burn only at night).

@export var sun: DirectionalLight3D
## Its children are the studio's Light3D lamps.
@export var studio_lamps: Node3D
## Unshaded street backdrop seen through the door and window (optional).
@export var street: MeshInstance3D
@export var night_lamp_factor: float = 0.6
@export var day_street_color: Color = Color(0.75, 0.85, 1.0)
@export var night_street_color: Color = Color(0.03, 0.04, 0.09)

var is_night: bool = false
var _lamp_energy: Dictionary[Light3D, float] = {}


func set_night(night: bool) -> void:
	is_night = night
	sun.visible = not night
	for lamp in studio_lamps.get_children():
		var light: Light3D = lamp as Light3D
		if light == null:
			continue
		if not _lamp_energy.has(light):
			_lamp_energy[light] = light.light_energy
		light.light_energy = _lamp_energy[light] * (night_lamp_factor if night else 1.0)
	if street != null:
		var street_material: StandardMaterial3D = street.get_active_material(0)
		street_material.albedo_color = night_street_color if night else day_street_color
	for spot in get_tree().get_nodes_in_group(&"candle_spot"):
		(spot as CandleSpot).lit = night
