class_name HeadMount
extends Node3D
## A wooden plaque on the basement wall. Shows a sacrificed client's head once one hangs here: the head cut out of
## the client drawing, tinted like the client was.

var data: ClientData = null

@onready var _head: MeshInstance3D = $Head


func _ready() -> void:
	_head.visible = false


func is_free() -> bool:
	return data == null


func hang(client_data: ClientData) -> void:
	data = client_data
	var material: StandardMaterial3D = ((_head.mesh as QuadMesh).material as StandardMaterial3D).duplicate()
	material.albedo_color = Color.WHITE.lerp(client_data.color, 0.3)
	_head.material_override = material
	_head.visible = true
