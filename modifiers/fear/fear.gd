extends TattooModifier
## "Instill fear": the artist's hands shake, rising into panic attacks and easing off again.

## Drift in pixels when calm.
@export var calm_amplitude: float = 8.0
## Extra drift in pixels at the peak of a panic attack.
@export var panic_amplitude: float = 22.0
## Seconds from one panic attack to the next.
@export var panic_period: float = 7.0
## How fast the hand wanders; higher is jitterier.
@export var drift_speed: float = 1.6
## Each extra roulette hit multiplies the shake by this much more.
@export var intensity_step: float = 0.6

var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = drift_speed
	_time = randf() * panic_period


func _process(delta: float) -> void:
	_time += delta


func needle_offset() -> Vector2:
	var amplitude: float = (calm_amplitude + panic_amplitude * _panic()) * (1.0 + intensity_step * (intensity - 1))
	# Noise rarely leaves ±0.6, so stretch it to roughly ±1.
	var drift: Vector2 = Vector2(_noise.get_noise_2d(_time, 0.0), _noise.get_noise_2d(0.0, _time + 100.0)) * 1.6
	var tremor: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.08
	return (drift + tremor) * amplitude


func status_text() -> String:
	return title() + (": паника!" if _panic() > 0.6 else ": руки дрожат")


## 0 when calm, 1 at the peak of a panic attack.
func _panic() -> float:
	var wave: float = 0.5 - 0.5 * cos(_time / panic_period * TAU)
	return wave * wave * wave
