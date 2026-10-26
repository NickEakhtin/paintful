class_name DialogueView
extends Control
## One way of showing lines (spirit panel, client bubble, player caption).
## Dialogue fills `label` and reveals it letter by letter.

const FADE_TIME: float = 0.15

@export var label: RichTextLabel
## Optional speaker name above the text.
@export var name_label: Label

var _fade: Tween


func _ready() -> void:
	visible = false


func show_line(text: String, speaker_name: String = "") -> void:
	label.text = text
	label.visible_characters = 0
	if name_label != null:
		name_label.text = speaker_name
		name_label.visible = speaker_name != ""
	if not visible:
		modulate.a = 0.0
	visible = true
	_start_fade().tween_property(self, "modulate:a", 1.0, FADE_TIME)


## Fades out; showing a line again cancels the fade.
func close() -> void:
	if not visible:
		return
	var tween: Tween = _start_fade()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(hide)


func _start_fade() -> Tween:
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	return _fade
