extends SceneTree
## Synthesizes placeholder sounds until real ones arrive (roadmap step 10).
## Only writes files that don't exist yet; delete one to make it again.
## Run: Godot --headless --path . --script res://tools/generate_placeholder_sounds.gd

const RATE: int = 44100
const OUT_DIR: String = "res://placeholders/sounds/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_save("ding.wav", _ding())
	_save("machine_buzz.wav", _buzz())
	_save("dip.wav", _dip())
	_save("crunch.wav", _crunch())
	_save("tick.wav", _tick())
	_save("whisper.wav", _whisper())
	_save("chop.wav", _chop())
	_save("hiss.wav", _hiss())
	_save("ignite.wav", _ignite())
	_save("perch.wav", _perch())
	_save("flutter.wav", _flutter())
	quit()


## Soft bell: a few sine partials with a fast attack and a long decay.
func _ding() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	for i in int(RATE * 0.9):
		var t: float = float(i) / RATE
		var envelope: float = exp(-t * 5.0) * minf(1.0, t * 200.0)
		var tone: float = 0.6 * sin(TAU * 1320.0 * t) + 0.3 * sin(TAU * 1980.0 * t) + 0.15 * sin(TAU * 2640.0 * t)
		samples.append(envelope * tone * 0.5)
	return samples


## Wet "bloop" for dipping the needle: a sine gliding up with a quick decay.
func _dip() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var phase: float = 0.0
	for i in int(RATE * 0.18):
		var t: float = float(i) / RATE
		phase += TAU * lerpf(280.0, 720.0, t / 0.18) / RATE
		samples.append(sin(phase) * exp(-t * 18.0) * minf(1.0, t * 400.0) * 0.6)
	return samples


## Squashed spider: a short burst of rough noise with a low thump under it.
func _crunch() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var smoothed: float = 0.0
	for i in int(RATE * 0.14):
		var t: float = float(i) / RATE
		smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), 0.35) # crude low-pass
		var thump: float = sin(TAU * 90.0 * t) * exp(-t * 40.0)
		samples.append((smoothed * 0.8 + thump * 0.6) * exp(-t * 28.0))
	return samples


## Roulette reel click.
func _tick() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	for i in int(RATE * 0.03):
		var t: float = float(i) / RATE
		samples.append((sin(TAU * 2200.0 * t) * 0.5 + randf_range(-0.3, 0.3)) * exp(-t * 180.0))
	return samples


## Spirit's whisper: breathy noise swelling and fading twice. 2 s, loops.
func _whisper() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var smoothed: float = 0.0
	var count: int = RATE * 2
	for i in count:
		var t: float = float(i) / count
		smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), 0.18) # soft hiss
		var swell: float = 0.5 - 0.5 * cos(t * TAU * 2.0)
		samples.append(smoothed * swell * 0.5)
	return samples


## The ritual cut: a sharp wet hit and a heavy low thud.
func _chop() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var smoothed: float = 0.0
	for i in int(RATE * 0.6):
		var t: float = float(i) / RATE
		smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), 0.5)
		var hit: float = smoothed * exp(-t * 35.0)
		var thud: float = sin(TAU * lerpf(70.0, 40.0, minf(t * 3.0, 1.0)) * t) * exp(-t * 6.0)
		samples.append(clampf(hit * 0.9 + thud * 0.8, -1.0, 1.0))
	return samples


## A flame going out: a bright burst of hiss dying away.
func _hiss() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var previous: float = 0.0
	for i in int(RATE * 0.7):
		var t: float = float(i) / RATE
		var noise: float = randf_range(-1.0, 1.0)
		var bright: float = noise - previous # crude high-pass
		previous = noise
		samples.append(bright * exp(-t * 6.0) * minf(1.0, t * 300.0) * 0.35)
	return samples


## A flame catching: a soft low whoosh swelling up and fading.
func _ignite() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var smoothed: float = 0.0
	var count: int = int(RATE * 0.5)
	for i in count:
		var t: float = float(i) / count
		smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), lerpf(0.05, 0.3, t))
		samples.append(smoothed * sin(t * PI) * 0.9)
	return samples


## A fairy landing on the machine: a tiny soft tap with a glassy ring.
func _perch() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	for i in int(RATE * 0.12):
		var t: float = float(i) / RATE
		var tap: float = randf_range(-1.0, 1.0) * exp(-t * 120.0) * 0.3
		var ring: float = sin(TAU * 3100.0 * t) * exp(-t * 30.0) * 0.25
		samples.append((tap + ring) * minf(1.0, t * 800.0))
	return samples


## A fairy shaken off: a quick "frrr" of wings, soft noise chopped at about 28 Hz.
func _flutter() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var smoothed: float = 0.0
	var count: int = int(RATE * 0.4)
	for i in count:
		var t: float = float(i) / RATE
		smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), 0.25)
		var beat: float = 0.5 + 0.5 * sin(TAU * 28.0 * t)
		samples.append(smoothed * beat * beat * sin(PI * float(i) / count) * 0.7)
	return samples


## Machine hum, 0.5 s holding a whole number of periods so it loops without a click.
func _buzz() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var freq: float = 110.0
	for i in RATE / 2:
		var t: float = float(i) / RATE
		var phase: float = TAU * freq * t
		var tone: float = sin(phase) + 0.5 * sin(2.0 * phase) + 0.25 * sin(3.0 * phase) + 0.2 * signf(sin(phase))
		samples.append(tone * 0.18)
	return samples


func _save(file_name: String, samples: PackedFloat32Array) -> void:
	if FileAccess.file_exists(OUT_DIR + file_name):
		return
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.save_to_wav(OUT_DIR + file_name)
