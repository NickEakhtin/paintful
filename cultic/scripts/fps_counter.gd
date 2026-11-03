extends Label

const SAMPLE_USEC := 250_000
var frames := 0
var sample_start := 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if sample_start == 0:
		sample_start = now
		return
	frames += 1
	var elapsed := now - sample_start
	if elapsed >= SAMPLE_USEC:
		text = "FPS %d" % roundi(frames * 1_000_000.0 / elapsed)
		frames = 0
		sample_start = now
