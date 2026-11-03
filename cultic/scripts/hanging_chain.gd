extends Node3D

# A small impulse from a passing player travels through the joints.
# Direct contact is handled separately by each link's rigid body.
func _on_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D or body != owner.get_node_or_null("Player"):
		return
	var motion := Vector3(body.velocity.x, 0.0, body.velocity.z).limit_length(4.5)
	$Link15.apply_central_impulse(motion * 0.4)
