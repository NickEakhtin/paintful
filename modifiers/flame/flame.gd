extends TattooModifier
## "Light a fire over him": the spirit's flame burns on top of the machine. Fast or jerky moves
## blow it out, and the ink of every unfinished part goes with it (done parts stay).
## The machine won't ink until the flame is back: hold it still and the coal flares up again.

@export_group("Wind")
## Needle speed the flame bears forever, in pixels per second.
@export var safe_speed: float = 700.0
## At this speed the flame goes out at once.
@export var blowout_speed: float = 2200.0
## Flame lost per second just under `blowout_speed`; less the closer to `safe_speed`. 1 is all of it.
@export var burn_rate: float = 4.0
## Flame regained per second below `safe_speed`.
@export var recover_rate: float = 0.6
## Each extra roulette hit multiplies both speeds by this.
@export var intensity_factor: float = 0.75

@export_group("Relight")
## Needle speed below which the machine counts as held still.
@export var still_speed: float = 120.0
## Seconds of holding still to light the flame again.
@export var relight_time: float = 1.2
## Flame-outs allowed for the task to count as done.
@export var allowed_outs: int = 1
## The wiped parts flash in this colour.
@export var wipe_color: Color = Color(1.0, 0.45, 0.1)

@export_group("Look")
## How far the flame leans against the motion, in radians per pixel/second.
@export var lean_per_speed: float = 0.0006
@export var max_lean: float = 0.9
## Share of `safe_speed` at which the flame starts to cower, before it loses anything.
@export_range(0.0, 1.0) var react_from: float = 0.3
## Share of its size the flame gives up in the strongest gust.
@export_range(0.0, 1.0) var gust_shrink: float = 0.7

var out_count: int = 0

var _lit: bool = true
## 1 = full flame, 0 = blown out.
var _health: float = 1.0
## Holding still while it's out fills this up to 1.
var _relight: float = 0.0
var _size: float = 0.0
var _lean: float = 0.0
## How hard the flame is blown right now: 0 calm, 1 at `blowout_speed`. Drives the look only.
var _gust: float = 0.0
var _phase: float = 0.0

@onready var _fire: Node2D = $Fire
@onready var _material: ShaderMaterial = $Fire/Body.material
@onready var _sparks: CPUParticles2D = $Fire/Sparks
@onready var _smoke: CPUParticles2D = $Fire/Smoke
@onready var _hiss: AudioStreamPlayer = $Hiss
@onready var _ignite: AudioStreamPlayer = $Ignite


func _ready() -> void:
	_ignite.play()


func _process(delta: float) -> void:
	var velocity: Vector2 = session.needle_velocity()
	var speed: float = velocity.length()
	if _lit:
		_blow(speed, delta)
	else:
		_try_relight(speed, delta)
	_update_gust(speed, delta)
	_update_look(velocity, delta)


func can_ink() -> bool:
	return _lit


func status_text() -> String:
	var state: String = "горит"
	if not _lit:
		state = "погасло! Замри, чтобы разжечь"
	elif _health < 0.6 or _gust > 0.4:
		state = "дрожит, медленнее!"
	return "%s: %s (гасло %d, можно %d)" % [title(), state, out_count, allowed_outs]


func is_passed() -> bool:
	return out_count <= allowed_outs


func stop() -> void:
	super()
	_fire.visible = false


func _blow(speed: float, delta: float) -> void:
	var safe: float = _safe_speed()
	var blowout: float = _blowout_speed()
	if speed >= blowout:
		_health = 0.0
	elif speed > safe:
		_health -= burn_rate * (speed - safe) / (blowout - safe) * delta
	else:
		_health = minf(1.0, _health + recover_rate * delta)
	if _health <= 0.0:
		_go_out()


func _safe_speed() -> float:
	return safe_speed * pow(intensity_factor, intensity - 1)


func _blowout_speed() -> float:
	return blowout_speed * pow(intensity_factor, intensity - 1)


## Rises at once with the speed, so the player sees "too fast" before any flame is lost,
## and settles a little slower.
func _update_gust(speed: float, delta: float) -> void:
	var from: float = _safe_speed() * react_from
	# The curve rises early, so even a brisk move shows.
	var target: float = pow(clampf((speed - from) / (_blowout_speed() - from), 0.0, 1.0), 0.7)
	var rate: float = 20.0 if target > _gust else 5.0
	_gust = lerpf(_gust, target, 1.0 - exp(-rate * delta))


func _go_out() -> void:
	_lit = false
	_health = 0.0
	_relight = 0.0
	out_count += 1
	_hiss.play()
	_smoke.restart()
	session.wipe_unfinished(wipe_color)


## A twitch doesn't throw away all the waiting, but it takes it back quickly.
func _try_relight(speed: float, delta: float) -> void:
	if speed <= still_speed:
		_relight += delta / relight_time
	else:
		_relight = maxf(0.0, _relight - 3.0 * delta / relight_time)
	if _relight >= 1.0:
		_lit = true
		_health = 1.0
		_ignite.play()


func _update_look(velocity: Vector2, delta: float) -> void:
	_fire.global_position = session.machine_top_position()
	var target_size: float = (0.25 + 0.75 * _health) * (1.0 - gust_shrink * _gust) if _lit else 0.0
	_size = lerpf(_size, target_size, 1.0 - exp(-14.0 * delta))
	_phase += delta * lerpf(5.0, 16.0, _gust)
	# The flame trails behind the motion: it leans away from it and flattens into a headwind.
	_lean = lerpf(_lean, clampf(-velocity.x * lean_per_speed, -max_lean, max_lean), 1.0 - exp(-12.0 * delta))
	_fire.rotation = _lean
	_fire.scale.y = clampf(1.0 + velocity.y * lean_per_speed * 0.5, 0.6, 1.3)
	_material.set_shader_parameter("size", _size)
	_material.set_shader_parameter("heat", minf(_health, 1.0 - 0.8 * _gust))
	_material.set_shader_parameter("gust", _gust)
	_material.set_shader_parameter("phase", _phase)
	_material.set_shader_parameter("coal", 0.0 if _lit else 0.25 + 0.75 * _relight)
	_sparks.emitting = _lit and (_health < 0.6 or _gust > 0.4)
