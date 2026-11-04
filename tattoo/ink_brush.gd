class_name InkBrush
extends RefCounted
## The needle's brush on screen: a flat ellipse, `radius_px` long each way along `axis`, `thickness` of that
## across it (1 = the old round brush). Pure logic; InkCanvas weighs cells with it, InkPaint draws its dots.
## The session turns `axis` across the needle's motion, so a flat brush paints the same width in any direction.

## Half length along `axis`, in screen pixels.
var radius_px: float = 14.3
## Half thickness across `axis` as a share of `radius_px`, 0..1.
var thickness: float = 1.0
## Unit vector along the brush, on screen.
var axis: Vector2 = Vector2.RIGHT


func _init(radius: float = 14.3, thick: float = 1.0, along: Vector2 = Vector2.RIGHT) -> void:
	radius_px = radius
	thickness = thick
	axis = along


## Unit vector across the brush, on screen.
func across() -> Vector2:
	return axis.orthogonal()


## Squared elliptic distance of a screen offset from the brush centre: 1 on the brush's rim.
func distance2(offset_px: Vector2) -> float:
	var along: float = offset_px.dot(axis) / radius_px
	var side: float = offset_px.dot(across()) / (radius_px * maxf(thickness, 0.001))
	return along * along + side * side


## Share of a stamp's ink that lands at a screen offset: full at the centre, half on the rim, none outside.
func weight(offset_px: Vector2) -> float:
	var e: float = distance2(offset_px)
	return 1.0 - 0.5 * e if e <= 1.0 else 0.0


## A thin brush sweeps each cell for `thickness` of the time a circle would: its dose is raised by as much,
## so one pass lays the same ink everywhere across the stroke.
func dose_scale() -> float:
	return 1.0 / maxf(thickness, 0.001)


## Half thickness, in screen pixels.
func half_thickness() -> float:
	return radius_px * thickness
