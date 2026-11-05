class_name GloveRig
extends Node
## Bones for the player's white glove (the colleague's model has none). Put it under the glove's model: on ready it
## builds a Skeleton3D (a root in the palm, three bones down each finger and the thumb, at joints measured off the
## mesh), skins the glove's mesh to it (every vertex near a finger follows that finger's bones, blended over its
## joints; the rest stays with the palm) and poses it from `fist` (0 open .. 1 a clenched fist).
## Positions are in the model's own space: fingers along +y, the palm facing +z, the thumb on the +x side.

## How closed the hand is, 0 (open) .. 1 (a fist).
@export_range(0.0, 1.0) var fist: float = 0.0:
	set(value):
		fist = clampf(value, 0.0, 1.0)
		_pose()

## Each finger: joints from the knuckle out, then the tip (model space).
const FINGERS: Dictionary = {
	"index": [Vector3(0.048, 0.268, -0.025), Vector3(0.054, 0.332, -0.035), Vector3(0.055, 0.375, -0.03), Vector3(0.057, 0.425, -0.025)],
	"middle": [Vector3(-0.0055, 0.275, -0.041), Vector3(-0.006, 0.345, -0.038), Vector3(-0.01, 0.395, -0.025), Vector3(-0.015, 0.445, -0.012)],
	"ring": [Vector3(-0.0575, 0.27, -0.046), Vector3(-0.062, 0.335, -0.024), Vector3(-0.068, 0.372, -0.01), Vector3(-0.073, 0.415, 0.0)],
	"little": [Vector3(-0.089, 0.262, -0.036), Vector3(-0.092, 0.31, -0.025), Vector3(-0.097, 0.34, -0.01), Vector3(-0.1, 0.375, 0.0)],
	"thumb": [Vector3(0.025, 0.08, 0.01), Vector3(0.065, 0.19, 0.025), Vector3(0.093, 0.255, 0.04), Vector3(0.12, 0.31, 0.05)],
}
## The fist's bend at each joint, knuckle out (degrees, toward the palm).
const FINGER_BEND: Array[float] = [82.0, 98.0, 62.0]
## Where the thumb's joints go in a fist (its middle joint, its last joint, its tip; model space): it rises along the
## index finger's side, its last joint lies in front of the index finger's middle bone and the tip reaches the middle
## finger's, pressed to the curled fingers (as a sculpted fist reference the user brought). Each bone turns to aim
## at its point (the bones keep their length).
const THUMB_FIST: Array[Vector3] = [Vector3(0.071, 0.183, 0.046), Vector3(0.05, 0.245, 0.07), Vector3(0.0, 0.265, 0.068)]
## A vertex this close to a finger's bones (m) follows them; fading out over the last part.
const CAPTURE: float = 0.06
## The thumb is thicker and its outer side far from its bones.
const THUMB_CAPTURE: float = 0.07
## Joints blend over this much either side (m).
const BLEND: float = 0.011
## The thumb's root eases in over this much either side of its joint (m).
const THUMB_ROOT_BLEND: float = 0.04

var _skeleton: Skeleton3D
## Bone index of each finger's three bones.
var _bones: Dictionary = {}


func _ready() -> void:
	var model: Node3D = get_parent() as Node3D
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var mesh_instance: MeshInstance3D = meshes[0]
	_skeleton = Skeleton3D.new()
	_skeleton.name = "GloveSkeleton"
	mesh_instance.get_parent().add_child(_skeleton)
	_skeleton.transform = mesh_instance.transform
	var root: int = _skeleton.add_bone("palm")
	for finger: String in FINGERS:
		var joints: Array = FINGERS[finger]
		var chain: Array[int] = []
		var parent: int = root
		var parent_at: Vector3 = Vector3.ZERO
		for i in 3:
			var bone: int = _skeleton.add_bone("%s_%d" % [finger, i])
			_skeleton.set_bone_parent(bone, parent)
			_skeleton.set_bone_rest(bone, Transform3D(Basis(), (joints[i] as Vector3) - parent_at))
			parent = bone
			parent_at = joints[i]
			chain.append(bone)
		_bones[finger] = chain
	_skeleton.reset_bone_poses()
	_skin(mesh_instance)
	_pose()


## Rebuilds the glove's mesh with bone weights and binds it to the skeleton.
func _skin(mesh_instance: MeshInstance3D) -> void:
	var source: Mesh = mesh_instance.mesh
	var skinned: ArrayMesh = ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = PackedInt32Array()
		var weights: PackedFloat32Array = PackedFloat32Array()
		bones.resize(vertices.size() * 4)
		weights.resize(vertices.size() * 4)
		for v in vertices.size():
			var found: Array = _weights_at(vertices[v])
			for k in 4:
				bones[v * 4 + k] = found[k * 2]
				weights[v * 4 + k] = found[k * 2 + 1]
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		skinned.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		skinned.surface_set_material(surface, source.surface_get_material(surface))
	var skin: Skin = Skin.new()
	for bone in _skeleton.get_bone_count():
		skin.add_bind(bone, _skeleton.get_bone_global_rest(bone).affine_inverse())
	mesh_instance.mesh = skinned
	mesh_instance.skin = skin
	mesh_instance.skeleton = mesh_instance.get_path_to(_skeleton)


## [bone, weight] × 4 for a vertex: the nearest finger's bones blended along it, the palm for the rest.
func _weights_at(p: Vector3) -> Array:
	var best: String = ""
	var best_distance: float = INF
	var best_along: float = 0.0
	for finger: String in FINGERS:
		var joints: Array = FINGERS[finger]
		# the chain from a little behind the knuckle to the tip, and how far along it the vertex lies
		var start: Vector3 = (joints[0] as Vector3) - ((joints[1] as Vector3) - (joints[0] as Vector3)).normalized() * 0.03
		var points: Array = [start, joints[0], joints[1], joints[2], joints[3]]
		var travelled: float = -0.03
		for i in 4:
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var segment: Vector3 = b - a
			var t: float = clampf((p - a).dot(segment) / maxf(segment.length_squared(), 1e-9), 0.0, 1.0)
			var distance: float = p.distance_to(a + segment * t)
			if distance < best_distance:
				best_distance = distance
				best = finger
				best_along = travelled + segment.length() * t
			travelled += segment.length()
	var palm: int = 0
	var capture: float = THUMB_CAPTURE if best == "thumb" else CAPTURE
	if best_distance > capture or best == "":
		return [palm, 1.0, 0, 0.0, 0, 0.0, 0, 0.0]
	var joints2: Array = FINGERS[best]
	var l1: float = ((joints2[1] as Vector3) - (joints2[0] as Vector3)).length()
	var l2: float = l1 + ((joints2[2] as Vector3) - (joints2[1] as Vector3)).length()
	var on: float = 1.0 - smoothstep(capture * 0.8, capture, best_distance)
	# the thumb's root sits in the palm's flesh: it eases in over a much longer stretch, or the mound tears
	var root_blend: float = THUMB_ROOT_BLEND if best == "thumb" else BLEND
	var into: float = smoothstep(-root_blend, root_blend, best_along)
	var past1: float = smoothstep(l1 - BLEND, l1 + BLEND, best_along)
	var past2: float = smoothstep(l2 - BLEND, l2 + BLEND, best_along)
	var chain: Array = _bones[best]
	var w0: float = into * (1.0 - past1) * on
	var w1: float = past1 * (1.0 - past2) * on
	var w2: float = past2 * on
	var wp: float = 1.0 - w0 - w1 - w2
	return [chain[0], w0, chain[1], w1, chain[2], w2, palm, maxf(wp, 0.0)]


func _pose() -> void:
	if _skeleton == null:
		return
	for finger: String in _bones:
		if finger == "thumb":
			continue
		var chain: Array = _bones[finger]
		for i in 3:
			_skeleton.set_bone_pose_rotation(chain[i], Quaternion(Vector3.RIGHT, deg_to_rad(FINGER_BEND[i]) * fist))
	# the thumb: each bone's turn in model space aims it at its point in a full fist, eased by `fist`; a bone's own
	# rotation is that turn less its parent's
	var joints: Array = FINGERS["thumb"]
	var thumb: Array = _bones["thumb"]
	var at: Vector3 = joints[0]
	var parent_turn: Quaternion = Quaternion.IDENTITY
	for i in 3:
		var rest: Vector3 = (joints[i + 1] as Vector3) - (joints[i] as Vector3)
		var aim: Quaternion = Quaternion(rest.normalized(), (THUMB_FIST[i] - at).normalized())
		at += aim * rest
		var turn: Quaternion = Quaternion.IDENTITY.slerp(aim, fist)
		_skeleton.set_bone_pose_rotation(thumb[i], parent_turn.inverse() * turn)
		parent_turn = turn
