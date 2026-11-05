extends RigidBody2D
## A crumpled bloody paper towel thrown at the bin (placeholder look).

const RADIUS: float = 14.0


func _ready() -> void:
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.35
	physics_material_override.friction = 0.8
	angular_damp = 1.5
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	can_sleep = true


func _draw() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in 9:
		var angle: float = TAU * i / 9.0
		points.append(Vector2(cos(angle), sin(angle)) * (RADIUS + 2.5 * sin(i * 3.1)))
	draw_colored_polygon(points, Color(0.84, 0.86, 0.9))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.4, 0.42, 0.5), 2.0, true)
	draw_line(Vector2(-6.0, -4.0), Vector2(5.0, 3.0), Color(0.55, 0.58, 0.66), 1.5)
	draw_circle(Vector2(3.0, 4.0), 6.0, Color(0.45, 0.04, 0.07, 0.85))
	draw_circle(Vector2(-5.0, -2.0), 3.5, Color(0.45, 0.04, 0.07, 0.7))
