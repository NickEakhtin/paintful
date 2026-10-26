extends Node
## Progress of the current playthrough. Survives level reloads between days.

var day: int = 1
var client_index: int = 0
## Clients sacrificed so far, oldest first; their heads hang on the basement wall.
var trophies: Array[ClientData] = []


func start_new_day() -> void:
	day += 1
	client_index = 0
