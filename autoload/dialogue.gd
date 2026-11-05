extends CanvasLayer
## Plays comic-style dialogues: `await Dialogue.play(dialogue, client_head, client_name)`.
## Spirit lines go to a dark panel at the top, the player's to a caption at the bottom,
## the client's to a speech bubble over `client_head`. The player can't move meanwhile.
## LMB or E: the first press finishes the line, the next goes on.

signal _advance

const MECHANICS: Mechanics = preload("res://data/mechanics.tres")

## Letters per second.
@export var typing_speed: float = 45.0
## Extra pause after . ! ? … and commas, in seconds.
@export var punctuation_pause: float = 0.12

var is_playing: bool = false

var _typing: bool = false
var _skip_typing: bool = false
var _vignette_tween: Tween

@onready var _spirit_panel: DialogueView = $SpiritPanel
@onready var _caption: DialogueView = $PlayerCaption
@onready var _bubble: SpeechBubble = $SpeechBubble
@onready var _vignette: ColorRect = $Vignette
@onready var _tick: AudioStreamPlayer = $Tick
@onready var _whisper: AudioStreamPlayer = $Whisper


func _ready() -> void:
	_vignette.visible = false


func play(dialogue: DialogueData, client_head: Node3D = null, client_name: String = "") -> void:
	if not MECHANICS.dialogues:
		return   # switched off in data/mechanics.tres
	is_playing = true
	var player: Player = get_tree().get_first_node_in_group(&"player")
	if player != null:
		player.lock_controls(&"dialogue")
	_bubble.anchor = client_head

	for line in dialogue.lines:
		var view: DialogueView = _view_for(line.speaker)
		for other in [_spirit_panel, _caption, _bubble]:
			if other != view:
				other.close()
		_set_spirit_mood(line.speaker == DialogueLine.Speaker.SPIRIT)
		view.show_line(_decorate(line, client_name), _speaker_name(line.speaker, client_name))
		await _type(view.label, _tick_pitch(line.speaker))
		await _advance

	for view in [_spirit_panel, _caption, _bubble]:
		view.close()
	_set_spirit_mood(false)
	_bubble.anchor = null
	if player != null:
		player.unlock_controls(&"dialogue")
	is_playing = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_playing:
		return
	if event.is_action_pressed("use") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if _typing:
			_skip_typing = true
		else:
			_advance.emit()


func _type(label: RichTextLabel, pitch: float) -> void:
	_typing = true
	_skip_typing = false
	var plain: String = label.get_parsed_text()
	var total: int = plain.length()
	var shown: float = 0.0
	var pause: float = 0.0
	while label.visible_characters < total and not _skip_typing:
		await get_tree().process_frame
		var delta: float = get_process_delta_time()
		if pause > 0.0:
			pause -= delta
			continue
		var before: int = label.visible_characters
		shown += typing_speed * delta
		label.visible_characters = mini(total, floori(shown))
		if label.visible_characters > before:
			var last: String = plain[label.visible_characters - 1]
			if last in ".!?…,":
				pause = punctuation_pause * (0.5 if last == "," else 1.0)
			if label.visible_characters % 2 == 0 and last != " ":
				_tick.pitch_scale = pitch * randf_range(0.95, 1.05)
				_tick.play()
	label.visible_characters = -1
	_typing = false


func _view_for(speaker: DialogueLine.Speaker) -> DialogueView:
	match speaker:
		DialogueLine.Speaker.SPIRIT:
			return _spirit_panel
		DialogueLine.Speaker.PLAYER:
			return _caption
	return _bubble


func _decorate(line: DialogueLine, client_name: String) -> String:
	var text: String = line.text.replace("{client}", client_name)
	if line.speaker == DialogueLine.Speaker.SPIRIT:
		text = "[shake rate=10.0 level=4]%s[/shake]" % text
	return text


func _speaker_name(speaker: DialogueLine.Speaker, client_name: String) -> String:
	match speaker:
		DialogueLine.Speaker.SPIRIT:
			return "Дух"
		DialogueLine.Speaker.PLAYER:
			return "Я"
	return client_name


func _tick_pitch(speaker: DialogueLine.Speaker) -> float:
	match speaker:
		DialogueLine.Speaker.SPIRIT:
			return 0.5
		DialogueLine.Speaker.PLAYER:
			return 1.0
	return 1.3


## The spirit darkens the screen edges and whispers while it talks.
func _set_spirit_mood(on: bool) -> void:
	if on and not _whisper.playing:
		_whisper.play()
	elif not on and _whisper.playing:
		_whisper.stop()
	var material: ShaderMaterial = _vignette.material
	var current: float = material.get_shader_parameter("strength")
	var target: float = 1.0 if on else 0.0
	if is_equal_approx(current, target):
		return
	_vignette.visible = true
	if _vignette_tween != null:
		_vignette_tween.kill()
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(func(v: float) -> void: material.set_shader_parameter("strength", v), current, target, 0.4)
	if not on:
		_vignette_tween.tween_callback(_vignette.hide)
