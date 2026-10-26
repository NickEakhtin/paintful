class_name ClientData
extends Resource
## Who a client is: looks, the tattoo they want and what they say.

@export var display_name: String = ""
## Placeholder figure colour and height until the 2D art arrives.
@export var color: Color = Color(0.5, 0.5, 0.6)
@export var height: float = 1.75
@export var stencil: StencilData
@export var greeting: DialogueData
@export var farewell: DialogueData
