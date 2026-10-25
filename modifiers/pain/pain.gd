extends TattooModifier
## "Make him feel pain": every few seconds the client tenses up (skin reddens and trembles),
## jerks the arm away, holds it there and slowly brings it back. Follow the skin to keep inking.

enum Phase { CALM, TENSE, JERK, HOLD, RETURN }

@export var calm_time_min: float = 4.0
@export var calm_time_max: float = 7.0
## The warning before a jerk.
@export var tense_time: float = 0.7
@export var jerk_time: float = 0.15
@export var hold_time: float = 0.8
@export var return_time: float = 0.6
@export var jerk_distance_min: float = 80.0
@export var jerk_distance_max: float = 140.0
@export var tense_color: Color = Color(1.0, 0.6, 0.55)

var jerk_count: int = 0

var _phase: Phase = Phase.CALM
var _phase_time: float = 0.0
var _phase_length: float = 0.0
var _jerk: Vector2 = Vector2.ZERO
var _offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_enter(Phase.CALM)


func _process(delta: float) -> void:
	_phase_time += delta
	var t: float = clampf(_phase_time / _phase_length, 0.0, 1.0)
	var redness: float = 0.0
	match _phase:
		Phase.CALM:
			_offset = Vector2.ZERO
		Phase.TENSE:
			redness = t
			_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 3.0 * t
		Phase.JERK:
			redness = 1.0
			_offset = _jerk * ease(t, 0.3) # fast out, soft stop
		Phase.HOLD:
			redness = 1.0
			_offset = _jerk
		Phase.RETURN:
			redness = 1.0 - t
			_offset = _jerk * (1.0 - smoothstep(0.0, 1.0, t))
	session.skin.self_modulate = Color.WHITE.lerp(tense_color, redness)
	if t >= 1.0:
		_enter(_next(_phase))


func skin_offset() -> Vector2:
	return _offset


func status_text() -> String:
	var text: String = data.display_name
	if intensity > 1:
		text += " ×%d" % intensity
	return text + (": сейчас дёрнется!" if _phase == Phase.TENSE else ": клиент дёргает рукой")


func stop() -> void:
	super()
	_offset = Vector2.ZERO
	session.skin.self_modulate = Color.WHITE


func _next(phase: Phase) -> Phase:
	match phase:
		Phase.CALM:
			return Phase.TENSE
		Phase.TENSE:
			return Phase.JERK
		Phase.JERK:
			return Phase.HOLD
		Phase.HOLD:
			return Phase.RETURN
	return Phase.CALM


func _enter(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0
	match phase:
		Phase.CALM:
			# More pain, shorter breaks.
			_phase_length = randf_range(calm_time_min, calm_time_max) / (1.0 + 0.4 * (intensity - 1))
		Phase.TENSE:
			_phase_length = tense_time
		Phase.JERK:
			_phase_length = jerk_time
			var distance: float = randf_range(jerk_distance_min, jerk_distance_max) * (1.0 + 0.25 * (intensity - 1))
			_jerk = Vector2.from_angle(randf() * TAU) * distance
			jerk_count += 1
		Phase.HOLD:
			_phase_length = hold_time
		Phase.RETURN:
			_phase_length = return_time
