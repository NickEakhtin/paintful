class_name ModifierData
extends Resource
## A spirit task as it appears on the roulette. `scene` holds the TattooModifier that plays it out.

@export var id: StringName
## Short name on the roulette reel and in the HUD.
@export var display_name: String = ""
## What the spirit says when this task comes up.
@export_multiline var spirit_line: String = ""
@export var color: Color = Color.WHITE
## `id`s of tasks that never come up in the same session as this one (either side may list the other).
@export var excludes: Array[StringName] = []
@export var scene: PackedScene
