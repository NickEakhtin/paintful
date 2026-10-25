class_name Interactable
extends Area3D
## Something the player can aim at and press `interact` on. Needs a CollisionShape3D child.
## Use as is and connect `interacted`, or extend it and override the methods below.

signal interacted(player: Player)

## Physics layer 3, "interactable".
const LAYER: int = 4

@export var prompt: String = "Взаимодействовать"
@export var enabled: bool = true


func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0


## Text for the HUD hint; empty hides it.
func get_prompt(_player: Player) -> String:
	return prompt


func can_interact(_player: Player) -> bool:
	return enabled


func interact(player: Player) -> void:
	interacted.emit(player)
