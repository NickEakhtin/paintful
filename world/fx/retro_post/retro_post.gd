extends CanvasLayer
## The colleague's grimy low-fi filter (retro_post.gdshader) over the 3D world only: it sits under every UI layer
## (HUD, dialogues, the tattoo session, the black fades), so text and the session stay sharp.
## A game pixel is a share of the window height (`game_rows` of them), so the look is the same on any monitor.
## The filter turns the picture into chunky pixels anyway, so the 3D world is rendered at a fraction of the
## window's resolution and without MSAA: it looks the same through the filter and costs far less.

@export var render_scale: float = 0.5
## Game pixels from the top of the window to the bottom (his 1280 px window with 4 px pixels).
@export var game_rows: float = 320.0

@onready var _material: ShaderMaterial = ($Screen as ColorRect).material as ShaderMaterial


func _ready() -> void:
	var viewport: Viewport = get_viewport()
	viewport.scaling_3d_scale = render_scale
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	_material.set_shader_parameter("pixel_size", maxf(1.0, get_window().size.y / game_rows))
