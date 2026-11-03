extends Node
## The game window. Starts fullscreen (borderless, at the desktop's own resolution); F11, Alt+Enter and, on macOS,
## Cmd+Ctrl+F switch between fullscreen and a window. The choice is kept in `user://settings.cfg`.
## `--windowed` / `--fullscreen` after `--` on the command line win over the saved choice (tests take screenshots
## in a window): `Godot --path . res://_test/x.tscn -- --windowed`. Godot keeps its own `--windowed` to itself.

const SETTINGS_PATH: String = "user://settings.cfg"
## The layout's base size: the window never gets smaller than this (unless the screen is).
const MIN_SIZE: Vector2i = Vector2i(1280, 720)
## A window takes this share of the screen, 16:9.
const WINDOWED_SHARE: float = 0.75

var fullscreen: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	var window: Window = get_window()
	window.min_size = MIN_SIZE.min(DisplayServer.screen_get_usable_rect(window.current_screen).size)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--windowed") or args.has("--fullscreen"):
		fullscreen = args.has("--fullscreen")
		if fullscreen:
			window.mode = Window.MODE_FULLSCREEN
		return
	var settings: ConfigFile = ConfigFile.new()
	settings.load(SETTINGS_PATH)
	set_fullscreen(settings.get_value("display", "fullscreen", true), false)


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var toggle: bool = key.physical_keycode == KEY_F11 \
		or (key.alt_pressed and (key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER)) \
		or (key.ctrl_pressed and key.meta_pressed and key.physical_keycode == KEY_F)
	if toggle:
		get_viewport().set_input_as_handled()   # the start screen's "any key" doesn't start the game
		set_fullscreen(not fullscreen)


func set_fullscreen(on: bool, save: bool = true) -> void:
	fullscreen = on
	var window: Window = get_window()
	if on:
		window.mode = Window.MODE_FULLSCREEN
	else:
		var was_fullscreen: bool = window.mode != Window.MODE_WINDOWED
		window.mode = Window.MODE_WINDOWED
		if was_fullscreen:
			# leaving fullscreen restores the window's old frame on some systems: size it once that settles
			await get_tree().process_frame
			await get_tree().process_frame
			if not fullscreen:
				_size_window(window)
		else:
			_size_window(window)
	if save:
		var settings: ConfigFile = ConfigFile.new()
		settings.load(SETTINGS_PATH)
		settings.set_value("display", "fullscreen", on)
		settings.save(SETTINGS_PATH)


## A 16:9 window, `WINDOWED_SHARE` of the screen, centred on it.
func _size_window(window: Window) -> void:
	var screen: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	var height: int = int(minf(screen.size.y, screen.size.x * 9.0 / 16.0) * WINDOWED_SHARE)
	var size: Vector2i = Vector2i(height * 16 / 9, height).max(window.min_size)
	window.size = size
	window.position = screen.position + (screen.size - size) / 2
