class_name Workstation
extends Node3D
## The table by the tattoo chair. Before a session the required items must lie on it;
## after the session one interaction puts everything back where it came from.

## Items were put on or taken off the table.
signal contents_changed
signal cleaned_up

## Item ids needed for the next session.
var required: Array[StringName] = []
## While true the whole table offers "tidy up" instead of its slots.
var cleanup_needed: bool = false:
	set(value):
		cleanup_needed = value
		if is_node_ready():
			_cleanup.collision_layer = Interactable.LAYER if value else 0

var _slots: Array[ItemSlot] = []

@onready var _cleanup: Interactable = $Cleanup


func _ready() -> void:
	for child in get_children():
		if child is ItemSlot:
			_slots.append(child)
			child.item_placed.connect(func(_item: Item) -> void: contents_changed.emit())
			child.item_removed.connect(func(_item: Item) -> void: contents_changed.emit())
	_cleanup.interacted.connect(func(_player: Player) -> void: clean_up())
	cleanup_needed = false


func set_required(item_ids: Array[StringName]) -> void:
	required = item_ids
	contents_changed.emit()


## Required ids not on the table yet, in the order they were asked for.
func missing() -> Array[StringName]:
	var on_table: Array[StringName] = []
	for slot in _slots:
		if slot.item != null:
			on_table.append(slot.item.item_id)
	var result: Array[StringName] = []
	for id in required:
		if not on_table.has(id):
			result.append(id)
	return result


func has_required() -> bool:
	return missing().is_empty()


func is_empty() -> bool:
	for slot in _slots:
		if slot.item != null:
			return false
	return true


## Returns every item to the slot it started in (left on the table if that slot is taken).
func clean_up() -> void:
	for slot in _slots:
		var item: Item = slot.item
		if item == null or item.home == null or item.home.item != null:
			continue
		slot.release()
		item.home.place(item)
	required.clear()
	cleanup_needed = false
	cleaned_up.emit()
