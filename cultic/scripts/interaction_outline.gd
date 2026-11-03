extends MeshInstance3D
## One depth-tested outline, shared by all interactables.
var collider: Node3D
var anchor: Node3D
var offset := Transform3D.IDENTITY
var silhouette := ShaderMaterial.new()
var hull := ShaderMaterial.new()
var rim := ShaderMaterial.new()
var contour := StandardMaterial3D.new()
var current_color := Color.WHITE
var plane := QuadMesh.new()

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	silhouette.shader = preload("res://cultic/scripts/interaction_silhouette.gdshader")
	silhouette.render_priority = -1
	silhouette.next_pass = hull
	hull.shader = preload("res://cultic/scripts/interaction_outline.gdshader")
	rim.shader = preload("res://cultic/scripts/interaction_rim.gdshader")
	contour.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	contour.cull_mode = BaseMaterial3D.CULL_DISABLED
	contour.disable_fog = true
	contour.emission_enabled = true
	contour.emission_energy_multiplier = 1.5
	plane.size = Vector2.ONE
	hide()

func track(hit: Dictionary) -> void:
	var next_target := hit.get("target") as Node
	if is_instance_valid(next_target) and next_target.has_method("suppress_interaction_outline") and next_target.suppress_interaction_outline():
		collider = hit.collider
		anchor = null
		hide()
		return
	if hit.is_empty():
		collider = null
		anchor = null
		hide()
		return
	var outline_collider := hit.collider as Node3D
	var outline_shape := int(hit.get("shape", 0))
	if is_instance_valid(next_target) and next_target.has_method("interaction_outline_collider"):
		var preferred := next_target.call("interaction_outline_collider", get_parent() as Node3D) as Node3D
		if is_instance_valid(preferred):
			outline_collider = preferred
			outline_shape = 0
	if collider != outline_collider:
		collider = outline_collider
		offset = Transform3D.IDENTITY
		var visual := collider.get_meta("outline_mesh", null) as MeshInstance3D if collider.has_meta("outline_mesh") else collider.get_parent() as MeshInstance3D
		if collider.has_meta("outline_contour"):
			anchor = collider
			mesh = collider.get_meta("outline_contour")
			material_override = contour
		elif visual:
			anchor = visual
			mesh = visual.mesh
			material_override = silhouette
		else:
			# Invisible click targets have a horizontal opening or a vertical door frame.
			var shape := collider.shape_owner_get_owner(collider.shape_find_owner(outline_shape)) as CollisionShape3D
			anchor = shape
			mesh = plane
			material_override = rim
			var cylinder := shape.shape as CylinderShape3D
			rim.set_shader_parameter("circular", cylinder != null)
			if cylinder:
				var diameter := cylinder.radius * 2.0
				offset = Transform3D(Basis(Vector3.RIGHT, -PI/2) * Basis.from_scale(Vector3(diameter, diameter, 1)), Vector3.UP * (cylinder.height/2 + 0.015))
			else:
				var size := (shape.shape as BoxShape3D).size
				if size.y < size.z:
					offset = Transform3D(Basis(Vector3.RIGHT, -PI/2) * Basis.from_scale(Vector3(size.x, size.z, 1)), Vector3.UP * (size.y/2 + 0.008))
				else:
					var front_sign := float(collider.get_meta("outline_front_sign", -1.0))
					offset = Transform3D(Basis.from_scale(Vector3(size.x, size.y, 1)), Vector3(0, 0, front_sign * size.z/2))
	if material_override == silhouette or material_override == contour:
		var tint: Color = hit.target.interaction_outline_color() if hit.target.has_method("interaction_outline_color") else Color.WHITE
		if material_override == silhouette and tint != current_color:
			current_color = tint
			hull.set_shader_parameter("outline_color", tint)
		elif material_override == contour:
			contour.albedo_color = tint
			contour.emission = tint if hit.target.has_method("interaction_outline_color") else Color.BLACK
			contour.emission_enabled = hit.target.has_method("interaction_outline_color")
	global_transform = anchor.global_transform * offset
	show()
