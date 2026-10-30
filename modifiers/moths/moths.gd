extends TattooModifier
## "Moths": tiny fairies fly in and hang on the machine. Each one makes it heavier: it follows
## the hand slower, swings more and sags. A quick shake of the mouse knocks them off.
## Can't be failed; it only gets in the way.

@export_group("Spawn")
## Seconds between fairies at intensity 1; repeats divide it.
@export var spawn_interval: float = 6.0
@export var first_spawn: float = 3.0
## No more than this many hang on the machine; the rest circle and wait.
@export var max_moths: int = 6
## Pixels per second.
@export var fly_speed: float = 300.0
## Size of a fairy; 1 is about 18 px tall.
@export var moth_scale: float = 1.8

@export_group("Weight")
## Mass each fairy adds; the machine's springs slow down by sqrt(1 + weight).
@export var weight_per_moth: float = 0.5
## How far each fairy pulls the needle down, in pixels.
@export var sag_per_moth: float = 3.5
## Each extra roulette hit multiplies weight and sag by this.
@export var intensity_factor: float = 1.25

@export_group("Shake")
## A swing of the mouse shorter than this, in pixels, isn't a shake.
@export var shake_min_stroke: float = 40.0
## Nor one slower than this on average, in pixels per second.
@export var shake_min_speed: float = 600.0
## Grip each fairy loses on every sharp turn of a shake (±30%); at 0 it falls off.
@export var shake_grip_loss: float = 0.45
## Grip regained per second.
@export var grip_recover: float = 0.4

var _spawn_timer: float = 0.0
var _sag: float = 0.0
var _time: float = 0.0
var _shake: ShakeDetector = ShakeDetector.new()

@onready var _swarm: Node2D = $Swarm
@onready var _perch_sound: AudioStreamPlayer = $Perch
@onready var _flutter_sound: AudioStreamPlayer = $Flutter


func _ready() -> void:
	_spawn_timer = first_spawn
	_shake.min_stroke = shake_min_stroke
	_shake.min_speed = shake_min_speed


func _process(delta: float) -> void:
	_time += delta
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and not session.is_turning() and _live_moths().size() < max_moths + 2:
		_spawn()
		_spawn_timer = spawn_interval / intensity * randf_range(0.7, 1.3)

	# The mouse, not the needle: a heavy needle lags and would smooth the shake out.
	var shook: bool = _shake.feed(session.pointer_position(), delta)
	for moth in _perched():
		moth.grip = minf(1.0, moth.grip + grip_recover * delta)
		if shook:
			moth.grip -= shake_grip_loss * randf_range(0.7, 1.3)
			if moth.grip <= 0.0:
				moth.shake_off(_shake.direction.rotated(randf_range(-0.6, 0.6)))
				_flutter_sound.pitch_scale = randf_range(0.9, 1.2)
				_flutter_sound.play()

	var needle: Vector2 = session.needle_position()
	var top: Vector2 = session.machine_top_position()
	var waiting: int = 0
	for moth in _live_moths():
		if not moth.has_perch and _perch_count() < max_moths:
			_give_perch(moth)
		if moth.state == Moth.State.PERCHED:
			moth.hang_at(_perch_point(moth, needle, top))
		elif moth.has_perch:
			if moth.fly_to(_perch_point(moth, needle, top), delta):
				moth.perch(_perch_point(moth, needle, top))
				_perch_sound.pitch_scale = randf_range(0.9, 1.3)
				_perch_sound.play()
		else:
			# No room: circle around the top of the machine.
			var angle: float = _time * 1.8 + waiting * TAU / 3.0
			moth.fly_to(top + Vector2(cos(angle) * 60.0, sin(angle) * 30.0 - 30.0), delta)
			waiting += 1

	var target_sag: float = _perched().size() * sag_per_moth * _factor()
	_sag = lerpf(_sag, target_sag, 1.0 - exp(-6.0 * delta))


func machine_weight() -> float:
	return _perched().size() * weight_per_moth * _factor()


func needle_offset() -> Vector2:
	return Vector2(0.0, _sag)


func status_text() -> String:
	var count: int = _perched().size()
	if count == 0:
		return "%s: машинка чистая" % title()
	return "%s: на машинке %d — потряси мышью!" % [title(), count]


func stop() -> void:
	super()
	for moth in _live_moths():
		moth.shake_off(Vector2.from_angle(randf() * TAU))


func _factor() -> float:
	return pow(intensity_factor, intensity - 1)


func _live_moths() -> Array[Moth]:
	var moths: Array[Moth] = []
	for child in _swarm.get_children():
		if child is Moth and child.state != Moth.State.LEAVING:
			moths.append(child)
	return moths


func _perched() -> Array[Moth]:
	return _live_moths().filter(func(m: Moth) -> bool: return m.state == Moth.State.PERCHED)


func _perch_count() -> int:
	return _live_moths().filter(func(m: Moth) -> bool: return m.has_perch).size()


## A random spot along the machine body, away from the needle end.
func _give_perch(moth: Moth) -> void:
	moth.has_perch = true
	moth.perch_t = randf_range(0.35, 0.95)
	moth.perch_side = randf_range(6.0, 12.0)


## Under the body: the side of the needle-to-top line that faces down the screen.
func _perch_point(moth: Moth, needle: Vector2, top: Vector2) -> Vector2:
	var normal: Vector2 = (top - needle).orthogonal().normalized()
	if normal.y < 0.0:
		normal = -normal
	return needle.lerp(top, moth.perch_t) + normal * moth.perch_side


## Comes in from just past a random edge of the screen.
func _spawn() -> void:
	var screen: Rect2 = get_viewport().get_visible_rect().grow(30.0)
	var start: Vector2
	match randi() % 4:
		0: start = Vector2(screen.position.x, randf_range(screen.position.y, screen.end.y))
		1: start = Vector2(screen.end.x, randf_range(screen.position.y, screen.end.y))
		2: start = Vector2(randf_range(screen.position.x, screen.end.x), screen.position.y)
		_: start = Vector2(randf_range(screen.position.x, screen.end.x), screen.end.y)
	var moth: Moth = Moth.new()
	moth.position = start
	moth.fly_speed = fly_speed
	moth.scale = Vector2.ONE * moth_scale
	_swarm.add_child(moth)
