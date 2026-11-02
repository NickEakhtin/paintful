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
	_save("mumble.wav", _mumble())
	_save("swish.wav", _swish())
	_save("pop.wav", _pop())
	_save("uh_huh.wav", _uh_huh())
	_save("wince.wav", _wince())
	_save("cry.wav", _cry())
	_save("heartbeat.wav", _heartbeat())
	_save("eye_open.wav", _eye_blink(0.12, 900.0, 1.0))
	_save("eye_close.wav", _eye_blink(0.1, 600.0, 0.6))
	_save("eye_twitch.wav", _eye_twitch())
	_save("eye_poke.wav", _eye_poke())
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


## Chatty client's "bla-bla": five quick voiced syllables, each at its own pitch and brightness.
func _mumble() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var syllable: int = int(RATE * 0.1)
	var phase: float = 0.0
	for s in 5:
		var pitch: float = randf_range(170.0, 260.0)
		var bright: float = randf_range(0.3, 0.8)
		for i in syllable:
			var t: float = float(i) / syllable
			phase += TAU * pitch * (1.0 - 0.15 * t) / RATE # each syllable sags in pitch
			var voice: float = sin(phase) + bright * 0.6 * sin(2.0 * phase) + bright * 0.4 * sin(3.0 * phase)
			var envelope: float = minf(1.0, t * 12.0) * pow(1.0 - t, 1.5)
			samples.append(voice * envelope * 0.3)
		for i in int(RATE * 0.015): # a short gap between syllables
			samples.append(0.0)
	return samples


## A hand waving through the air: soft noise growing brighter, swelling and dying away.
func _swish() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var smoothed: float = 0.0
	var count: int = int(RATE * 0.22)
	for i in count:
		var t: float = float(i) / count
		smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), lerpf(0.06, 0.45, t))
		samples.append(smoothed * pow(sin(t * PI), 1.5) * 0.8)
	return samples


## A speech bubble popping: a tiny click on a quick downward blip.
func _pop() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var phase: float = 0.0
	for i in int(RATE * 0.09):
		var t: float = float(i) / RATE
		phase += TAU * lerpf(520.0, 160.0, minf(t / 0.06, 1.0)) / RATE
		var click: float = randf_range(-1.0, 1.0) * exp(-t * 400.0) * 0.3
		samples.append((sin(phase) * exp(-t * 35.0) * 0.6 + click) * minf(1.0, t * 1500.0))
	return samples


## The artist's closed-mouth "mm-hm": a low hum that falls, a breath, then one that rises.
func _uh_huh() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var phase: float = 0.0
	for part in [[0.14, 165.0, 140.0], [0.2, 130.0, 180.0]]:
		var count: int = int(RATE * part[0])
		for i in count:
			var t: float = float(i) / count
			phase += TAU * lerpf(part[1], part[2], t) / RATE
			var hum: float = sin(phase) + 0.3 * sin(2.0 * phase) + 0.1 * sin(3.0 * phase)
			samples.append(hum * minf(1.0, t * 10.0) * minf(1.0, (1.0 - t) * 6.0) * 0.35)
		for i in int(RATE * 0.05):
			samples.append(0.0)
	return samples


## The client hissing through the teeth, "ss-s": bright noise swelling and fading.
func _wince() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var previous: float = 0.0
	var smoothed: float = 0.0
	var count: int = int(RATE * 0.55)
	for i in count:
		var t: float = float(i) / count
		var noise: float = randf_range(-1.0, 1.0)
		smoothed = lerpf(smoothed, noise - previous, 0.6) # high-pass, then soften the very top
		previous = noise
		samples.append(smoothed * pow(sin(t * PI), 0.7) * (1.0 - 0.4 * t) * 0.4)
	return samples


## The client's short "ow!": a voiced tone with an open "a" formant, pitch falling, a quick close.
func _cry() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var phase: float = 0.0
	var count: int = int(RATE * 0.32)
	for i in count:
		var t: float = float(i) / count
		var pitch: float = lerpf(430.0, 300.0, t)
		phase += TAU * pitch / RATE
		var voice: float = 0.0
		for k in range(1, 9): # harmonics near 800 Hz ring out: the "a"
			var formant: float = exp(-pow((k * pitch - 800.0) / 450.0, 2.0))
			voice += sin(k * phase) * (0.25 + formant) / k
		var envelope: float = minf(1.0, t * 40.0) * pow(1.0 - t, 1.2)
		samples.append(voice * envelope * 0.45)
	return samples


## A heartbeat, "lub-dub": two low thumps in 0.8 s; loops.
func _heartbeat() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	for i in int(RATE * 0.8):
		var t: float = float(i) / RATE
		var value: float = 0.0
		for beat in [[0.0, 1.0], [0.18, 0.7]]:
			var local: float = t - beat[0]
			if local >= 0.0:
				value += sin(TAU * 52.0 * local) * exp(-local * 22.0) * minf(1.0, local * 300.0) * beat[1]
		samples.append(value * 0.8)
	return samples


## Wet lids parting or meeting: a smacky noise tick with a short sine blip gliding to `pitch`.
func _eye_blink(length: float, pitch: float, loudness: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var smoothed: float = 0.0
	var phase: float = 0.0
	for i in int(RATE * length):
		var t: float = float(i) / RATE
		smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), 0.5)
		phase += TAU * lerpf(pitch * 0.4, pitch, t / length) / RATE
		var smack: float = smoothed * exp(-t * 90.0)
		var blip: float = sin(phase) * exp(-t * 35.0) * 0.5
		samples.append((smack + blip) * minf(1.0, t * 800.0) * loudness * 0.6)
	return samples


## A trembling lid before it opens: a few faint wet ticks, quieter than a blink. 0.4 s.
func _eye_twitch() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(RATE * 0.4))
	samples.fill(0.0)
	for tick in 5:
		var start: int = int(RATE * (0.03 + tick * 0.07 + randf_range(-0.01, 0.01)))
		var smoothed: float = 0.0
		for i in int(RATE * 0.025):
			if start + i >= samples.size():
				break
			var t: float = float(i) / RATE
			smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), 0.45)
			samples[start + i] += smoothed * exp(-t * 160.0) * 0.25
	return samples


## Needle in the eye: a squelch, wet low-passed noise over a thump sliding down.
func _eye_poke() -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var smoothed: float = 0.0
	var phase: float = 0.0
	for i in int(RATE * 0.22):
		var t: float = float(i) / RATE
		smoothed = lerpf(smoothed, randf_range(-1.0, 1.0), 0.18)
		phase += TAU * lerpf(220.0, 70.0, t / 0.22) / RATE
		var wobble: float = 0.6 + 0.4 * sin(TAU * 38.0 * t)
		samples.append((smoothed * 1.6 * wobble + sin(phase) * 0.7) * exp(-t * 14.0) * minf(1.0, t * 600.0) * 0.6)
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
