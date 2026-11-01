class_name Roulette
extends CanvasLayer
## The spirit's slot machine: three reels, each lands on a different task.
## `await roulette.spin(pool)` returns the tasks that came up once the player clicks past the spirit's words.

signal _closed

## Seconds until the first reel stops.
@export var spin_time: float = 1.4
## Each next reel stops this much later.
@export var reel_delay: float = 0.6

var _can_close: bool = false

@onready var _reels: Array[Label] = [$Panel/Box/Reels/Reel1/Label, $Panel/Box/Reels/Reel2/Label, $Panel/Box/Reels/Reel3/Label]
@onready var _lines: Label = $Panel/Box/Lines
@onready var _continue: Label = $Panel/Box/Continue
@onready var _tick: AudioStreamPlayer = $Tick


func spin(pool: Array[ModifierData]) -> Array[ModifierData]:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_lines.text = ""
	_continue.visible = false
	var tasks: Array[ModifierData] = []
	for i in _reels.size():
		var allowed: Array[ModifierData] = _allowed(pool, tasks)
		if allowed.is_empty():
			break
		tasks.append(allowed.pick_random())
	# A reel with nothing left to land on stays hidden.
	for i in _reels.size():
		_reels[i].get_parent().visible = i < tasks.size()

	# Every reel flicks through symbols, slowing down before it stops; reels stop left to right.
	var elapsed: float = 0.0
	var next_flick: Array[float] = []
	next_flick.resize(tasks.size())
	var stopped: Array[bool] = []
	stopped.resize(tasks.size())
	while stopped.has(false):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		for i in tasks.size():
			if stopped[i]:
				continue
			var stop_at: float = spin_time + reel_delay * i
			if elapsed >= stop_at:
				stopped[i] = true
				_show(i, tasks[i])
				_play_tick(0.7)
			elif elapsed >= next_flick[i]:
				var slowdown: float = 1.0 - clampf((stop_at - elapsed) / spin_time, 0.0, 1.0)
				next_flick[i] = elapsed + lerpf(0.05, 0.25, slowdown * slowdown)
				_show(i, pool.pick_random())
				_play_tick(1.0 + 0.1 * i)

	_lines.text = _spirit_words(tasks)
	_continue.visible = true
	_can_close = true
	await _closed
	return tasks


func _unhandled_input(event: InputEvent) -> void:
	if _can_close and event.is_action_pressed("use"):
		get_viewport().set_input_as_handled()
		_can_close = false
		_closed.emit()


## The pool minus tasks that already landed or don't go with one that landed.
func _allowed(pool: Array[ModifierData], landed: Array[ModifierData]) -> Array[ModifierData]:
	var allowed: Array[ModifierData] = []
	for task in pool:
		if not landed.has(task) and not landed.any(_excluded.bind(task)):
			allowed.append(task)
	return allowed


func _excluded(landed: ModifierData, task: ModifierData) -> bool:
	return landed.excludes.has(task.id) or task.excludes.has(landed.id)


func _show(reel: int, task: ModifierData) -> void:
	var label: Label = _reels[reel]
	label.text = task.display_name
	label.modulate = task.color


func _play_tick(pitch: float) -> void:
	_tick.pitch_scale = pitch
	_tick.play()


func _spirit_words(tasks: Array[ModifierData]) -> String:
	if tasks.is_empty():
		return "Дух молчит. Сегодня можно работать спокойно."
	var lines: PackedStringArray = PackedStringArray()
	for task in tasks:
		if not task.spirit_line.is_empty():
			lines.append(task.spirit_line)
	return "\n".join(lines)
