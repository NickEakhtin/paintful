class_name Item
extends Interactable
## Something the player can carry: needle, ink, gloves...
## Put it under an ItemSlot in the editor so it starts in that slot.

@export var item_id: StringName
@export var display_name: String = "Предмет"
## Placeholder look; the collision box is sized to fit the mesh.
@export var mesh: Mesh
@export var color: Color = Color.WHITE

## Slot the item lies in, null while carried.
var slot: ItemSlot = null

@onready var _mesh_instance: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape


func _ready() -> void:
	if mesh != null:
		_mesh_instance.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	_mesh_instance.material_override = material

	# Origin sits at the bottom of the mesh so the item rests on the slot surface.
	var bounds: AABB = _mesh_instance.get_aabb()
	_mesh_instance.position = Vector3(0.0, -bounds.position.y, 0.0)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = bounds.size + Vector3.ONE * 0.06 # a bit bigger so small items are easy to aim at
	_shape.shape = box
	_shape.position = _mesh_instance.position + bounds.get_center()


func get_prompt(player: Player) -> String:
	if player.held_item != null:
		return "Руки заняты"
	return "Взять: %s" % display_name


func can_interact(player: Player) -> bool:
	return enabled and player.held_item == null


func interact(player: Player) -> void:
	if slot != null:
		slot.release()
	player.hold(self)
	super(player)


## Moves the item under `parent`. A held item can't be aimed at, so it doesn't block the ray.
func attach_to(parent: Node3D, held: bool) -> void:
	if get_parent() != parent:
		reparent(parent, false)
	transform = Transform3D.IDENTITY
	collision_layer = 0 if held else LAYER
