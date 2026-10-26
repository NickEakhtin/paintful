class_name DialogueLine
extends Resource
## One line of a dialogue. `text` may use BBCode and the {client} placeholder.

enum Speaker { SPIRIT, PLAYER, CLIENT }

@export var speaker: Speaker = Speaker.SPIRIT
@export_multiline var text: String = ""
