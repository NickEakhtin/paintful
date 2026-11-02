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
