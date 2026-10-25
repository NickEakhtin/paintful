extends Node
## Progress of the current playthrough.

var day: int = 1
var client_index: int = 0


func start_new_day() -> void:
	day += 1
	client_index = 0
