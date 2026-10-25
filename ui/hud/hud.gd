extends CanvasLayer
## Crosshair, interaction hint and current objective.

@onready var _crosshair: Control = $Crosshair
@onready var _prompt: Label = $Prompt
@onready var _objective: Label = $Objective


func _ready() -> void:
	_prompt.text = ""
	_objective.text = ""
	Events.interaction_prompt_changed.connect(_on_prompt_changed)
	Events.objective_changed.connect(_on_objective_changed)


func set_controls_locked(locked: bool) -> void:
	_crosshair.visible = not locked
	_prompt.visible = not locked


func _on_prompt_changed(text: String) -> void:
	_prompt.text = text


func _on_objective_changed(text: String) -> void:
	_objective.text = text
