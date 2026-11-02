class_name InkFlow
extends RefCounted
## "Flow": a feel-only combo for long, steady strokes. Pure logic: no nodes, no input.
## It builds while the needle keeps working over the stencil, holds while the needle stands still,
## and after a short grace fades away once the stroke breaks. No penalty, nothing is counted.

## 0..1, grows linearly with time spent in flow.
var level: float = 0.0

var _build_time: float
var _fade_time: float
var _grace: float
var _broken_for: float = 0.0


func _init(build_time: float, fade_time: float, grace: float) -> void:
	_build_time = build_time
	_fade_time = fade_time
	_grace = grace


## `building`: the stroke goes on and the needle moves; `holding`: it goes on but the needle stands still.
## Neither: the stroke is broken, and after the grace the flow fades.
func update(delta: float, building: bool, holding: bool) -> void:
	if building or holding:
		_broken_for = 0.0
		if building:
			level = minf(1.0, level + delta / maxf(_build_time, 0.001))
		return
	_broken_for += delta
	if _broken_for > _grace:
		level = maxf(0.0, level - delta / maxf(_fade_time, 0.001))


## Eased level for the effects: soft at both ends.
func strength() -> float:
	return smoothstep(0.0, 1.0, level)


func clear() -> void:
	level = 0.0
	_broken_for = 0.0
