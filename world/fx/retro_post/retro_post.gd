extends CanvasLayer
## The colleague's grimy low-fi filter (retro_post.gdshader) over the 3D world only: it sits under every UI layer
## (HUD, dialogues, the tattoo session, the black fades), so text and the session stay sharp.
## A game pixel is a whole number of screen pixels, as retro 3D games do it (a fractional one makes uneven
## pixels): as big as fits `min_rows` game pixels in the window height, at most `max_pixel_size`. So 1080p gets
## 540 rows (2 px), a MacBook's 1120 560, 1440p and 4K 480 and 720 (3 px), 720p its own 720 (1 px): bigger
## monitors show finer pixels, never a blurry stretch.
## The 3D world is rendered at exactly one pixel per game pixel and without MSAA: the filter samples one point per
## game pixel anyway, so it looks the same and costs far less (a 4K screen renders 1280x720).

## Fewest game pixels from the top of the window to the bottom.
@export var min_rows: int = 480
## Largest game pixel, in screen pixels.
@export var max_pixel_size: int = 3

@onready var _material: ShaderMaterial = ($Screen as ColorRect).material as ShaderMaterial


func _ready() -> void:
	var viewport: Viewport = get_viewport()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.size_changed.connect(_fit)
	_fit()


## Screen pixels per game pixel for the height the game renders at: the window's own pixels, or the base size
## when `Display.low_resolution` stretches a smaller picture to the window.
func pixel_size() -> int:
	return clampi(_render_height() / min_rows, 1, max_pixel_size)


func _render_height() -> int:
	var window: Window = get_window()
	if window.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		return int(get_viewport().get_visible_rect().size.y)
	return window.size.y


func _fit() -> void:
	var pixel: int = pixel_size()
	_material.set_shader_parameter("pixel_size", float(pixel))
	get_viewport().scaling_3d_scale = 1.0 / pixel
