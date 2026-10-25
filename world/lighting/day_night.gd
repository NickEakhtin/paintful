class_name DayNight
extends Node3D
## Switches the level between day and night: sun through the window, studio lamps,
## the street outside, and candles in the ritual circle (they burn only at night).

@export var sun: DirectionalLight3D
## Its children are the studio's Light3D lamps.
@export var studio_lamps: Node3D
## Unshaded street backdrop seen through the door and window.
@export var street: MeshInstance3D
@export var day_lamp_energy: float = 1.2
@export var night_lamp_energy: float = 0.35
@export var day_street_color: Color = Color(0.75, 0.85, 1.0)
@export var night_street_color: Color = Color(0.03, 0.04, 0.09)

var is_night: bool = false


func set_night(night: bool) -> void:
	is_night = night
	sun.visible = not night
	for lamp in studio_lamps.get_children():
		(lamp as Light3D).light_energy = night_lamp_energy if night else day_lamp_energy
	var street_material: StandardMaterial3D = street.get_active_material(0)
	street_material.albedo_color = night_street_color if night else day_street_color
	for spot in get_tree().get_nodes_in_group(&"candle_spot"):
		(spot as CandleSpot).lit = night
