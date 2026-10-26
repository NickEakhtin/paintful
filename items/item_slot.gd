class_name ItemSlot
extends Interactable
## A spot where an Item can be put down. An Item placed under it in the editor starts here.

signal item_placed(item: Item)
signal item_removed(item: Item)

## Item ids this slot takes; empty means any item.
@export var accepts: Array[StringName] = []

var item: Item = null

@onready var _marker: Node3D = $Marker


func _ready() -> void:
	for child in get_children():
		if child is Item:
			child.home = self
			_store(child)
			break


func get_prompt(player: Player) -> String:
	if item != null or player.held_item == null:
		return ""
	if not accepts_item(player.held_item):
		return "Сюда нельзя: %s" % player.held_item.display_name
	return "Положить: %s" % player.held_item.display_name


func can_interact(player: Player) -> bool:
	return enabled and item == null and player.held_item != null and accepts_item(player.held_item)


func interact(player: Player) -> void:
	var placed: Item = player.take_item()
	_store(placed)
	item_placed.emit(placed)
	super(player)


## Puts `new_item` here from code (e.g. tidying up), as if the player had placed it.
func place(new_item: Item) -> void:
	_store(new_item)
	item_placed.emit(new_item)


func accepts_item(candidate: Item) -> bool:
	return accepts.is_empty() or accepts.has(candidate.item_id)


## Called by the item when the player picks it up.
func release() -> void:
	var removed: Item = item
	item = null
	removed.slot = null
	collision_layer = LAYER
	_marker.visible = true
	item_removed.emit(removed)


func _store(new_item: Item) -> void:
	item = new_item
	new_item.slot = self
	new_item.attach_to(self, false)
	# The slot stops catching the ray so the item lying in it can be aimed at.
	collision_layer = 0
	_marker.visible = false
