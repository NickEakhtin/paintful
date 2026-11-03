extends CanvasLayer
## The retro filter turns the picture into chunky pixels anyway, so the 3D world is rendered at a fraction of the
## window's resolution and without MSAA: it looks the same through the filter and costs far less.

@export var render_scale := 0.5


func _ready() -> void:
	var viewport := get_viewport()
	viewport.scaling_3d_scale = render_scale
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
