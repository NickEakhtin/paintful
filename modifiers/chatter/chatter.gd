extends TattooModifier
## "Chatterbox": the spirit loosens the client's tongue. Every so often a speech bubble with a silly
## question pops up over a corner of the stencil and hides the tattoo under it. The artist's left hand
## (WASD) waves it away with Space and mumbles "Угу". Can't be failed; it only gets in the way.

const BUBBLE_SCENE: PackedScene = preload("res://modifiers/chatter/chat_bubble.tscn")
const HAND_SCENE: PackedScene = preload("res://tattoo/left_hand.tscn")
const REPLY_SCENE: PackedScene = preload("res://modifiers/chatter/reply.tscn")

@export_group("Timing")
## Seconds before the first bubble, so the player can settle in.
@export var first_delay: float = 7.0
## Seconds between bubbles, picked at random in this range.
@export var interval_min: float = 8.5
@export var interval_max: float = 16.5

@export_group("Bubbles")
## How far a bubble may sit off the centre of its quarter of the stencil, in pixels.
@export var jitter: float = 20.0
## Letters per second.
@export var type_speed: float = 40.0
## A wave still hits when the palm is this far outside a bubble, in pixels.
@export var hit_margin: float = 30.0

@export_group("Hand")
@export var hand_speed: float = 900.0
@export var hand_acceleration: float = 14.0
## Keeps the palm this far inside the screen edges.
@export var hand_margin: float = 40.0
## Where the hand waits at the start, from the bottom-left screen corner.
@export var hand_rest: Vector2 = Vector2(180.0, -150.0)

@export_group("Text")
## What the client asks, one bubble each; none repeats until all were used.
@export_multiline var phrases: PackedStringArray = []
## What the artist mumbles back when waving a bubble away, picked at random.
@export var replies: PackedStringArray = PackedStringArray(["Угу."])

var hand: LeftHand
var dismissed_count: int = 0

var _spawn_timer: float = 0.0
var _bag: PackedStringArray = PackedStringArray()

@onready var _bubble_layer: Node2D = $Bubbles
@onready var _mumble: AudioStreamPlayer = $Mumble
@onready var _pop_sound: AudioStreamPlayer = $Pop
@onready var _uh_huh: AudioStreamPlayer = $UhHuh


func _ready() -> void:
	_spawn_timer = first_delay
	var screen: Vector2 = get_viewport_rect().size
	hand = HAND_SCENE.instantiate()
	hand.speed = hand_speed
	hand.acceleration = hand_acceleration
	add_child(hand)
	hand.bounds = Rect2(Vector2.ZERO, screen).grow(-hand_margin)
	hand.waved.connect(_on_waved)
	hand.slide_in(Vector2(-200.0, screen.y + 200.0), Vector2(0.0, screen.y) + hand_rest)


func _process(delta: float) -> void:
	var red_spot: Vector2 = session.red_spot()
	for bubble in live_bubbles():
		bubble.targeted = _under_palm(bubble)
		bubble.alarmed = red_spot.is_finite() and bubble.hit_rect().grow(session.heat_radius).has_point(red_spot)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	# All four corners taken: wait until one frees up.
	var free: Array[int] = _free_corners()
	if free.is_empty():
		return
	_spawn(free.pick_random())
	_spawn_timer = randf_range(interval_min, interval_max)


func status_text() -> String:
	var count: int = live_bubbles().size()
	var state: String = "болтает (%d)" % count if count > 0 else "молчит"
	return "%s: %s · WASD — рука, пробел — отмахнуться" % [title(), state]


func stop() -> void:
	super()
	for bubble in live_bubbles():
		bubble.pop()
	if hand != null:
		hand.leave()
		hand = null


func live_bubbles() -> Array[ChatBubble]:
	var bubbles: Array[ChatBubble] = []
	for child in _bubble_layer.get_children():
		if child is ChatBubble and not child.popped:
			bubbles.append(child)
	return bubbles


## Pops every bubble under the palm; a wave at nothing does nothing.
func _on_waved() -> void:
	var palm: Vector2 = hand.palm()
	var hit: bool = false
	for bubble in live_bubbles():
		if _under_palm(bubble):
			bubble.pop()
			dismissed_count += 1
			hit = true
	if not hit:
		return
	_pop_sound.pitch_scale = randf_range(0.9, 1.15)
	_pop_sound.play()
	_uh_huh.pitch_scale = randf_range(0.92, 1.08)
	_uh_huh.play()
	_reply(palm)


## Whether a wave right now would pop `bubble`.
func _under_palm(bubble: ChatBubble) -> bool:
	return hand != null and bubble.hit_rect().grow(hit_margin).has_point(hand.palm())


## The artist's "Угу" by the fingertips: it floats up a little and fades.
func _reply(palm: Vector2) -> void:
	var reply: Label = REPLY_SCENE.instantiate()
	reply.text = replies[randi() % replies.size()] if not replies.is_empty() else "Угу."
	add_child(reply)
	var screen: Rect2 = get_viewport_rect()
	reply.position = (palm + Vector2(40.0, -150.0)).clamp(screen.position, screen.end - reply.size)
	var tween: Tween = reply.create_tween()
	tween.tween_interval(0.35)
	tween.set_parallel()
	tween.tween_property(reply, "position:y", reply.position.y - 30.0, 0.5)
	tween.tween_property(reply, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(reply.queue_free)


func _free_corners() -> Array[int]:
	var free: Array[int] = [0, 1, 2, 3]
	for bubble in live_bubbles():
		free.erase(bubble.corner)
	return free


## Centre of the stencil quarter (0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right), give or take `jitter`.
func _spawn(corner: int) -> void:
	var rect: Rect2 = session.stencil_rect()
	@warning_ignore("integer_division")
	var quarter: Vector2 = Vector2(0.25 + 0.5 * (corner % 2), 0.25 + 0.5 * (corner / 2))
	var bubble: ChatBubble = BUBBLE_SCENE.instantiate()
	bubble.corner = corner
	bubble.tail_up = corner < 2
	bubble.type_speed = type_speed
	bubble.position = rect.position + rect.size * quarter + Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))
	_bubble_layer.add_child(bubble)
	bubble.pop_in(_next_phrase())
	_mumble.pitch_scale = randf_range(0.85, 1.2)
	_mumble.play()


## Draws from a shuffled bag, refilled once empty, so phrases don't repeat too soon.
func _next_phrase() -> String:
	if phrases.is_empty():
		return "…"
	if _bag.is_empty():
		var shuffled: Array = Array(phrases)
		shuffled.shuffle()
		_bag = PackedStringArray(shuffled)
	var phrase: String = _bag[_bag.size() - 1]
	_bag.remove_at(_bag.size() - 1)
	return phrase
