extends MeshInstance3D
## One depth-tested outline around the Interactable the player aims at (the colleague's look).
## What it draws, by the Interactable's metas: `outline_contour` (a ready mesh, e.g. the crater's pentagram) →
## that mesh; `outline_mesh` (a MeshInstance3D) or a MeshInstance3D parent → a coloured silhouette of it;
## otherwise a thin frame on its collision shape (a flat box gets it on top, an upright one on the
## `outline_front_sign` side, a cylinder a circle). `outline_suppress` hides it. The colour comes from the first
## node up from the Interactable with `interaction_outline_color()`, white otherwise.

var target: Interactable = null
var _anchor: Node3D = null
var _offset: Transform3D = Transform3D.IDENTITY
var _silhouette: ShaderMaterial = ShaderMaterial.new()
var _hull: ShaderMaterial = ShaderMaterial.new()
var _rim: ShaderMaterial = ShaderMaterial.new()
var _contour: StandardMaterial3D = StandardMaterial3D.new()
var _current_color: Color = Color.WHITE
var _plane: QuadMesh = QuadMesh.new()


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_silhouette.shader = preload("res://player/outline/interaction_silhouette.gdshader")
	_silhouette.render_priority = -1
	_silhouette.next_pass = _hull
	_hull.shader = preload("res://player/outline/interaction_outline.gdshader")
	_rim.shader = preload("res://player/outline/interaction_rim.gdshader")
	_contour.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_contour.cull_mode = BaseMaterial3D.CULL_DISABLED
	_contour.disable_fog = true
	_contour.emission_enabled = true
	_contour.emission_energy_multiplier = 1.5
	_plane.size = Vector2.ONE
	hide()


## Outline `next` (null hides it).
func track(next: Interactable) -> void:
	if next == null or not is_instance_valid(next) or next.has_meta(&"outline_suppress"):
		target = null
		_anchor = null
		hide()
		return
	if next != target:
		target = next
		_setup()
	if not is_instance_valid(_anchor):
		hide()
		return
	var tint_source: Node = _color_source()
	var tint: Color = tint_source.call(&"interaction_outline_color") if tint_source != null else Color.WHITE
	if material_override == _silhouette and tint != _current_color:
		_current_color = tint
		_hull.set_shader_parameter("outline_color", tint)
	elif material_override == _contour:
		_contour.albedo_color = tint
		_contour.emission = tint if tint_source != null else Color.BLACK
		_contour.emission_enabled = tint_source != null
	global_transform = _anchor.global_transform * _offset
	show()


func _setup() -> void:
	_offset = Transform3D.IDENTITY
	_current_color = Color(0, 0, 0, 0)
	var visual: MeshInstance3D = target.get_meta(&"outline_mesh") as MeshInstance3D if target.has_meta(&"outline_mesh") else target.get_parent() as MeshInstance3D
	if target.has_meta(&"outline_contour"):
		_anchor = target
		mesh = target.get_meta(&"outline_contour")
		material_override = _contour
	elif visual != null:
		_anchor = visual
		mesh = visual.mesh
		material_override = _silhouette
	else:
		# an invisible zone: a horizontal opening or an upright frame
		var shape: CollisionShape3D = null
		for child: Node in target.get_children():
			if child is CollisionShape3D:
				shape = child
				break
		_anchor = shape
		if shape == null:
			return
		mesh = _plane
		material_override = _rim
		var cylinder: CylinderShape3D = shape.shape as CylinderShape3D
		_rim.set_shader_parameter("circular", cylinder != null)
		if cylinder != null:
			var diameter: float = cylinder.radius * 2.0
			_offset = Transform3D(Basis(Vector3.RIGHT, -PI / 2) * Basis.from_scale(Vector3(diameter, diameter, 1)), Vector3.UP * (cylinder.height / 2 + 0.015))
		elif shape.shape is BoxShape3D:
			var size: Vector3 = (shape.shape as BoxShape3D).size
			if size.y < size.z:
				_offset = Transform3D(Basis(Vector3.RIGHT, -PI / 2) * Basis.from_scale(Vector3(size.x, size.z, 1)), Vector3.UP * (size.y / 2 + 0.008))
			else:
				var front_sign: float = float(target.get_meta(&"outline_front_sign", -1.0))
				_offset = Transform3D(Basis.from_scale(Vector3(size.x, size.y, 1)), Vector3(0, 0, front_sign * size.z / 2))
		else:
			_anchor = null


func _color_source() -> Node:
	var n: Node = target
	while n != null:
		if n.has_method(&"interaction_outline_color"):
			return n
		n = n.get_parent()
	return null
