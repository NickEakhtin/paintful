class_name HeadMount
extends Node3D
## A wooden plaque on the basement wall. Shows a sacrificed client's head once one hangs here.

var data: ClientData = null

@onready var _head: MeshInstance3D = $Head


func _ready() -> void:
	_head.visible = false


func is_free() -> bool:
	return data == null


func hang(client_data: ClientData) -> void:
	data = client_data
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = client_data.color
	_head.material_override = material
	_head.visible = true
