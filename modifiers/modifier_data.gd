class_name ModifierData
extends Resource
## A spirit task as it appears on the roulette. `scene` holds the TattooModifier that plays it out.

@export var id: StringName
## Short name on the roulette reel and in the HUD.
@export var display_name: String = ""
## What the spirit says when this task comes up.
@export_multiline var spirit_line: String = ""
@export var color: Color = Color.WHITE
## How many roulette reels may land on this task; 1 = it never repeats.
@export_range(1, 3) var max_count: int = 3
@export var scene: PackedScene
