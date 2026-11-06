extends Node2D
## The crumpled bloody paper towel in the left hand's half-closed fingers before the throw, over the curled
## fingers so it shows: a lumpy blob drawn with `wet_paper.gdshader` (soaked, bloody), creases shaded in.

const WET_PAPER: Shader = preload("res://tattoo/blood/wet_paper.gdshader")
const CENTER: Vector2 = Vector2(10.0, -62.0)
const RADIUS: float = 27.0


func _ready() -> void:
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = WET_PAPER
	shader_material.set_shader_parameter("stained", 0.75)
	shader_material.set_shader_parameter("wet", 1.0)
	shader_material.set_shader_parameter("emboss_cells", 5.0)
	material = shader_material


func _draw() -> void:
	# a lumpy outline, the middle a little lighter than the folds round it
	var count: int = 14
	var points: PackedVector2Array = PackedVector2Array([CENTER])
	var colours: PackedColorArray = PackedColorArray([Color(1.0, 1.0, 1.0)])
	var uvs: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.5)])
	for i in count + 1:
		var angle: float = TAU * (i % count) / count
		var reach: float = RADIUS * (1.0 + 0.16 * sin(i * 3.1) + 0.08 * sin(i * 5.7))
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		points.append(CENTER + direction * reach)
		var shade: float = 0.62 + 0.18 * sin(i * 2.3)
		colours.append(Color(shade, shade, shade))
		uvs.append(Vector2(0.5, 0.5) + direction * 0.5 * (reach / RADIUS) * 0.9)
	var indices: PackedInt32Array = PackedInt32Array()
	for i in count:
		indices.append_array([0, i + 1, i + 2])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colours, uvs)
	# crease lines over it
	var crease: Color = Color(0.25, 0.08, 0.1, 0.55)
	draw_line(CENTER + Vector2(-14.0, -8.0), CENTER + Vector2(6.0, 6.0), crease, 1.5)
	draw_line(CENTER + Vector2(2.0, -18.0), CENTER + Vector2(14.0, -4.0), crease, 1.5)
	draw_line(CENTER + Vector2(-6.0, 10.0), CENTER + Vector2(10.0, 16.0), crease, 1.5)
