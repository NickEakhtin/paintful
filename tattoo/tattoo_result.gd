class_name TattooResult
extends RefCounted
## Outcome of one tattoo session.

enum Grade { PERFECT, GOOD, BAD }

var grade: Grade = Grade.BAD
## Seconds from start to the last part done.
var time: float = 0.0
var mistakes: int = 0
## Mistake cells relative to the stencil area.
var mistake_ratio: float = 0.0


func grade_name() -> String:
	match grade:
		Grade.PERFECT:
			return "Идеально"
		Grade.GOOD:
			return "Хорошо"
	return "Плохо"
