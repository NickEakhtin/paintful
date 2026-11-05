class_name CandleSpot
extends ItemSlot
## A place for a candle in the ritual circle. A lit spot with a candle glows and flickers.

var lit: bool = false:
	set(value):
		lit = value
		_update_flame()

var _time: float = 0.0

@onready var _flame: OmniLight3D = $Flame


func _ready() -> void:
	super()
	add_to_group(&"candle_spot")
	item_placed.connect(func(_item: Item) -> void: _update_flame())
	item_removed.connect(func(_item: Item) -> void: _update_flame())
	_time = randf() * 10.0
	_update_flame()


func _process(delta: float) -> void:
	if not _flame.visible:
		return
	_time += delta
	_flame.light_energy = 0.9 + 0.15 * sin(_time * 11.0) + 0.1 * sin(_time * 23.0 + 1.3)


func _update_flame() -> void:
	if is_node_ready():
		_flame.visible = lit and item != null
