class_name StencilData
extends Resource
## A tattoo design split into parts.

@export var display_name: String = ""
@export var parts: Array[StencilPart] = []
## Which skin it goes on: `&"flat"` (the square skin panel) or `&"arm"` (the forearm; the parts are the
## unwrapped skin, see `ArmSurface`).
@export var surface: StringName = &"flat"
## Ink coverage grid, in cells. Keep the aspect of the part images.
@export var grid_size: Vector2i = Vector2i(256, 256)
