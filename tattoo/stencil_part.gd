class_name StencilPart
extends Resource
## One area of a tattoo design that is filled and completed on its own.

@export var display_name: String = ""
## Opaque pixels are the area to fill. All parts of a stencil share one image size.
@export var texture: Texture2D
