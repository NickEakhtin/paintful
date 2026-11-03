extends Node3D

# A small impulse from a passing player travels through the joints.
# Direct contact is handled separately by each link's rigid body.
func _on_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D or not body.is_in_group("player"):
		return
	var walker: CharacterBody3D = body as CharacterBody3D
	var motion: Vector3 = Vector3(walker.velocity.x, 0.0, walker.velocity.z).limit_length(4.5)
	($Link15 as RigidBody3D).apply_central_impulse(motion * 0.4)
