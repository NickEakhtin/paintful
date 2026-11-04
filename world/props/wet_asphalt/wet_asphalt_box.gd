extends Node3D
## A block of wet asphalt (wet_asphalt_box.tscn): drop it anywhere, move and scale it freely,
## the texture stays the same size. In the game it gets a collision box and rain rings in the puddles.

@export var animate_rain: bool = true

@onready var _ground: MeshInstance3D = $Ground


func _ready() -> void:
	# made here, in the game only, like the basement hatch: keeps physics bodies out of the editor
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = _ground.get_aabb().size
	shape.shape = box
	shape.position = _ground.get_aabb().get_center()
	body.add_child(shape)
	_ground.add_child(body)


func _process(_delta: float) -> void:
	if animate_rain:
		var material: ShaderMaterial = _ground.get_active_material(0) as ShaderMaterial
		if material:
			material.set_shader_parameter("rain_time", Time.get_ticks_msec() / 1000.0)
