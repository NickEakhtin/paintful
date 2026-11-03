extends StaticBody3D

const OUTLINE_YELLOW := Color(1.0, 0.76, 0.08, 1.0)

func _ready() -> void:
	set_meta("outline_mesh", $Visual/TubeBody)

func can_interact() -> bool:
	return true

func interaction_outline_color() -> Color:
	return OUTLINE_YELLOW

func interact(player: Node3D) -> void:
	if player.has_method("collect_yellow_paint") and bool(player.call("collect_yellow_paint")):
		queue_free()
