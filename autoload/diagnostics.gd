extends CanvasLayer
## F8: a diagnostics panel over everything, to catch frame drops on the player's own machine. Every `refresh` s it
## shows, over that window: the frame time (average and worst), the engine's processing of a frame (`TIME_PROCESS`:
## scripts, animation, GUI and everything before drawing) and the physics in it,
## the CPU's draw submission and the GPU, the mouse motion events that came in per frame (average and most), the
## objects and draw calls drawn, the window and render size and the video memory. Off by default; costs nothing
## while hidden (the GPU timing is measured only while shown).

## How often the numbers update, in seconds.
@export var refresh: float = 0.5

var _label: Label = Label.new()
var _panel: ColorRect = ColorRect.new()
var _wait: float = 0.0
var _frames: int = 0
var _frame_sum: float = 0.0
var _frame_worst: float = 0.0
var _process_sum: float = 0.0
var _physics_sum: float = 0.0
var _gpu_sum: float = 0.0
var _draw_sum: float = 0.0
var _motion_this_frame: int = 0
var _motion_sum: int = 0
var _motion_most: int = 0
var _last_usec: int = 0


func _ready() -> void:
	layer = 127
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel.color = Color(0.0, 0.0, 0.0, 0.62)
	_panel.position = Vector2(4, 34)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label.position = Vector2(12, 38)
	_label.add_theme_font_size_override(&"font_size", 16)
	_label.add_theme_color_override(&"font_color", Color(0.85, 1.0, 0.75))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 3)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = "…"
	add_child(_label)
	set_process(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_motion_this_frame += 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		visible = not visible
		set_process(visible)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), visible)
		_reset()
		_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = (now - _last_usec) / 1000.0
	_last_usec = now
	var viewport: RID = get_viewport().get_viewport_rid()
	_frames += 1
	_frame_sum += frame_ms
	_frame_worst = maxf(_frame_worst, frame_ms)
	_process_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_physics_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	_draw_sum += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
	_motion_sum += _motion_this_frame
	_motion_most = maxi(_motion_most, _motion_this_frame)
	_motion_this_frame = 0
	_wait -= _delta
	if _wait > 0.0:
		return
	_wait = refresh
	var n: float = maxf(_frames, 1)
	var window: Vector2i = get_window().size
	var render: Vector2 = get_viewport().get_visible_rect().size
	var lines: PackedStringArray = PackedStringArray([
		"F8 — диагностика",
		"кадр: %.1f мс в среднем, худший %.1f мс (%d FPS)" % [_frame_sum / n, _frame_worst, roundi(Engine.get_frames_per_second())],
		"обработка кадра процессором: %.1f мс, из них физика %.1f мс" % [_process_sum / n, _physics_sum / n],
		"отрисовка: процессор %.1f мс, видеокарта %.1f мс" % [_draw_sum / n, _gpu_sum / n],
		"мышь: %.1f событий за кадр, максимум %d" % [_motion_sum / n, _motion_most],
		"объектов %d, вызовов отрисовки %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)],
		"окно %d×%d, рендер %d×%d, видеопамять %d МБ" % [window.x, window.y, roundi(render.x), roundi(render.y),
				roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)],
	])
	_label.text = "\n".join(lines)
	_panel.size = _label.get_minimum_size() + Vector2(16, 8)
	_reset()


func _reset() -> void:
	_frames = 0
	_frame_sum = 0.0
	_frame_worst = 0.0
	_process_sum = 0.0
	_physics_sum = 0.0
	_gpu_sum = 0.0
	_draw_sum = 0.0
	_motion_sum = 0
	_motion_most = 0
	_wait = minf(_wait, refresh)
