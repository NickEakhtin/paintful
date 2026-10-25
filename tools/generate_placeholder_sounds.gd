extends SceneTree
## Synthesizes placeholder sounds until real ones arrive (roadmap step 10).
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
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.save_to_wav(OUT_DIR + file_name)
