extends Control
## Session overlay: overall progress, part list, "part done" flash and the result screen.

const DONE_COLOR: Color = Color(0.55, 0.95, 0.55)

var _part_names: PackedStringArray = PackedStringArray()
var _part_labels: Array[Label] = []
var _flash_tween: Tween

@onready var _progress: ProgressBar = $Progress
@onready var _parts: VBoxContainer = $Parts
@onready var _flash: Label = $Flash
@onready var _hint: Label = $Hint
@onready var _done_panel: PanelContainer = $Done
@onready var _ink_warning: Label = $InkWarning


func setup(part_names: PackedStringArray) -> void:
	_part_names = part_names
	for part_name in part_names:
		var label: Label = Label.new()
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		_parts.add_child(label)
		_part_labels.append(label)
	_flash.modulate.a = 0.0
	_done_panel.visible = false


func show_progress(canvas: InkCanvas) -> void:
	_progress.value = canvas.total_progress() * 100.0
	for i in _part_labels.size():
		var label: Label = _part_labels[i]
		if canvas.is_part_done(i):
			label.text = "%s — готово" % _part_names[i]
			label.modulate = DONE_COLOR
		else:
			label.text = "%s — %d%%" % [_part_names[i], floori(canvas.part_progress(i) * 100.0)]


func flash_part(index: int) -> void:
	_flash.text = "%s — готово!" % _part_names[index]
	if _flash_tween != null:
		_flash_tween.kill()
	_flash.modulate.a = 1.0
	_flash.scale = Vector2.ONE * 1.3
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "scale", Vector2.ONE, 0.2)
	_flash_tween.tween_interval(0.8)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.4)


func set_ink_empty(empty: bool) -> void:
	_ink_warning.visible = empty


func show_done() -> void:
	_hint.visible = false
	_ink_warning.visible = false
	_done_panel.visible = true
	_done_panel.modulate.a = 0.0
	create_tween().tween_property(_done_panel, "modulate:a", 1.0, 0.4).set_delay(0.6)
