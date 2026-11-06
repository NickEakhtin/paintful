class_name ArmProfile
extends Resource
## The client's arm measured off a side-view photo (`tools/make_client_arm.gd` writes it): shoulder to fingertips,
## turned so the forearm stands upright. One sample per row of the (turned) photo, `step` arm px apart, from row
## `top` down (arm rows: px from the stencil's middle, down positive, as ArmShape counts them). Widths and the centre
## line are in ArmShape radii, so the whole outline scales with `ArmShape.radius`; the first and last samples are 0
## wide (the shoulder's top, the fingertips).

## Arm row of the first sample, and the arm px between samples.
@export var top: float = 0.0
@export var step: float = 1.0
## The arm's half width at each sample, in radii.
@export var radii: PackedFloat32Array = PackedFloat32Array()
## The arm's centre line at each sample, across (right positive), in radii; 0 at the stencil's middle.
@export var centers: PackedFloat32Array = PackedFloat32Array()
## Arm rows of the elbow (the narrowest point between the upper arm and the forearm) and the wrist (the narrowest
## point above the hand).
@export var elbow: float = -500.0
@export var wrist: float = 700.0
## The photo's own shading over the arm, for the shader: R = the shading's detail / 2 (the muscles, the elbow, the
## knuckles: the photo's luminance over its average across the arm, so 0.5 = no change), G = skin (0 between the
## fingers). Columns run across the arm, sin(theta) from -1 to 1; rows are the samples.
@export var shading: Texture2D


## Arm row of the last sample.
func bottom() -> float:
	return top + step * (radii.size() - 1)
