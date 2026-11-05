class_name Mechanics
extends Resource
## Switches for game mechanics, all in one file (`data/mechanics.tres`): untick one and it's gone
## everywhere, in the level and in a session run on its own. Nothing is deleted, so ticking it brings it back.

## Spirit roulette and tasks in the session; the level skips the spirit's roulette line too.
@export var spirit_tasks: bool = true
## Skin turns red when the needle is parked and the session starts over (`SkinHeat`).
@export var skin_heat: bool = true
## The machine runs dry and is refilled at the ink cap. Off: endless ink, no gauge, no hints.
@export var ink_supply: bool = true
## The needle is pulled toward unfilled stencil.
@export var magnet: bool = true
## The needle lags behind the hand on a spring. Off: it's exactly where the hand puts it (the top still swings).
@export var machine_inertia: bool = true
## Before a session the player brings the needed items to the workstation.
@export var table_prep: bool = true
## After a client the player tidies the workstation.
@export var table_cleanup: bool = true
## Skin dents and turns pink under the working needle; the picture trembles while the machine buzzes.
@export var skin_press: bool = true
## Long, steady strokes over the stencil raise the hum, widen the trail and make the needle glow.
@export var flow: bool = true
## The needle paints with a flat brush of dots across its motion. Off: the old round brush and smooth trail.
@export var flat_brush: bool = true
## Spirit, client and player dialogues. Off: `Dialogue.play()` returns at once, so the day goes on without them.
@export var dialogues: bool = true
## Two needles on the side table (Q): LMB on one swaps it into the machine. The thick one paints with the flat
## spray brush, the thin one with a small round brush for careful edges. Off: always the thick one, no needles.
@export var needle_swap: bool = true
## Inking past the stencil's edge with the needle shakes the skin and pushes the machine back toward the
## drawing (the thick needle hard, the thin one gently).
@export var edge_kick: bool = true
## Stretchable skin (the arm) takes ink well only where the left hand pulls it taut, poorly where it's slack.
@export var skin_tension: bool = true
## Now and then blood wells up on fresh ink, swells and runs; the left hand wipes it with a wet paper towel and
## throws the towel in the bin. Look only.
@export var blood: bool = true
