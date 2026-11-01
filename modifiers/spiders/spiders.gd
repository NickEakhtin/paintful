extends TattooModifier
## "Remind him of his childhood": spiders run over the skin. Click one with the needle to squash it.
## A spider that runs off the skin escapes and the client flinches.

## Seconds between spiders (±30%).
@export var spawn_interval: float = 5.0
## Pixels per second.
@export var speed: float = 90.0
## How far from the needle tip a click still squashes, in pixels.
@export var hit_radius: float = 26.0
## Escapes allowed for the task to count as done.
@export var allowed_escapes: int = 1
## How sharply spiders wander off a straight line.
@export var wander: float = 2.5

var squashed_count: int = 0
var escaped_count: int = 0

var _spawn_timer: float = 2.5
var _flinch_time: float = 0.0
var _time: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()

@onready var _crunch: AudioStreamPlayer = $Crunch


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 0.8


func _process(delta: float) -> void:
	_time += delta
	_flinch_time = maxf(0.0, _flinch_time - delta)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn()
		_spawn_timer = spawn_interval * randf_range(0.7, 1.3)

	var bounds: Rect2 = session.skin.get_rect().grow(10.0)
	for spider in _live_spiders():
		var turn: float = _noise.get_noise_2d(spider.get_instance_id() % 997 * 7.0, _time) * wander * delta
		spider.velocity = spider.velocity.rotated(turn)
		spider.position += spider.velocity * delta
		if not bounds.has_point(spider.position):
			escaped_count += 1
			_flinch_time = 0.3
			spider.queue_free()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("use"):
		return
	# The magnet may pull the needle off a spider near the stencil, so the mouse counts too.
	var needle: Vector2 = to_local(session.needle_position())
	var pointer: Vector2 = to_local(session.pointer_position())
	for spider in _live_spiders():
		if minf(spider.position.distance_to(needle), spider.position.distance_to(pointer)) <= hit_radius:
			spider.squash()
			squashed_count += 1
			_crunch.pitch_scale = randf_range(0.85, 1.15)
			_crunch.play()
			return


## The client twitches when a spider gets away.
func skin_offset() -> Vector2:
	if _flinch_time <= 0.0:
		return Vector2.ZERO
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 8.0 * (_flinch_time / 0.3)


func status_text() -> String:
	return "%s: раздавлено %d, сбежало %d (можно %d)" % [title(), squashed_count, escaped_count, allowed_escapes]


func is_passed() -> bool:
	return escaped_count <= allowed_escapes


func stop() -> void:
	super()
	for spider in _live_spiders():
		spider.queue_free()


func _live_spiders() -> Array[Spider]:
	var spiders: Array[Spider] = []
	for child in get_children():
		if child is Spider and not child.squashed and not child.is_queued_for_deletion():
			spiders.append(child)
	return spiders


## Starts on the edge of the skin oval, heading roughly for the middle.
func _spawn() -> void:
	var bounds: Rect2 = session.skin.get_rect()
	var center: Vector2 = bounds.get_center()
	var angle: float = randf() * TAU
	var spider: Spider = Spider.new()
	spider.position = center + Vector2(cos(angle) * bounds.size.x, sin(angle) * bounds.size.y) * 0.47
	var heading: float = (center - spider.position).angle() + randf_range(-0.6, 0.6)
	spider.velocity = Vector2.from_angle(heading) * speed
	add_child(spider)
