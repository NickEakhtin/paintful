extends CanvasLayer
## Full-screen black overlay for scene changes and title cards like "Day 2".
## Every method is awaitable: `await Transition.change_scene(path)`.

const DEFAULT_FADE: float = 0.5

## True while the overlay covers the screen even partially.
var is_busy: bool = false

var _changing_scene: bool = false
var _keep_black: bool = false

@onready var _overlay: ColorRect = $Overlay
@onready var _title: Label = $Title


func fade_out(duration: float = DEFAULT_FADE) -> void:
	is_busy = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	await _tween_alpha(_overlay, 1.0, duration)


func fade_in(duration: float = DEFAULT_FADE) -> void:
	await _tween_alpha(_overlay, 0.0, duration)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_busy = false


## Fades to black, swaps the current scene, fades back in
## unless the new scene called keep_black() from its _ready.
func change_scene(path: String, duration: float = DEFAULT_FADE) -> void:
	await fade_out(duration)
	_changing_scene = true
	var error: Error = get_tree().change_scene_to_file(path)
	if error == OK:
		await get_tree().scene_changed
	else:
		push_error("Can't change scene to %s: %s" % [path, error_string(error)])
	_changing_scene = false
	if _keep_black:
		_keep_black = false
		return
	await fade_in(duration)


## For a scene that opens with its own black-screen intro (e.g. the "Day N" card):
## call from _ready so change_scene() leaves the screen black. Does nothing otherwise.
func keep_black() -> void:
	_keep_black = _changing_scene


## Fades to black and shows the text for `hold` seconds.
## The screen stays black afterwards: call fade_in() when the next scene is ready.
func show_title(text: String, hold: float = 2.0, duration: float = DEFAULT_FADE) -> void:
	_title.text = text
	await fade_out(duration)
	await _tween_alpha(_title, 1.0, duration)
	await get_tree().create_timer(hold).timeout
	await _tween_alpha(_title, 0.0, duration)


func _tween_alpha(item: CanvasItem, alpha: float, duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(item, "modulate:a", alpha, duration)
	await tween.finished
