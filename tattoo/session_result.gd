class_name SessionResult
extends RefCounted
## Outcome of a tattoo session: which spirit tasks were in play and which were done.

var tasks: Array[ModifierData] = []
## Same order as `tasks`.
var passed: Array[bool] = []


## Every task done (also true with no tasks). Step 7 lights up the client's eyes on this.
func is_perfect() -> bool:
	return not passed.has(false)
