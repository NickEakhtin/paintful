# Project
3D indie game, Godot 4.7, GDScript only.

- The repo root is the Godot project root (`project.godot` is here).
- Development roadmap: `docs/ROADMAP.md`. Each big step gets its own detailed plan before work starts.
- `docs/` has a `.gdignore`, so Godot doesn't scan it.

# Rules
- Godot 4 API only (await, CharacterBody3D, @export). Never Godot 3 syntax.
- Prefer editing .tscn/.gd files directly; keep scenes small and composable.
- Run the game to check for errors (from the repo root):
  /Applications/Godot.app/Contents/MacOS/Godot --path . 2>&1
  Quick headless check that exits by itself:
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120 2>&1
- Commit after each working step.

# Code conventions
- Static typing everywhere: `var speed: float = 5.0`, `func f(x: int) -> void`.
- Files and folders in snake_case. Add `class_name` (PascalCase) only when the class is used as a type elsewhere.
- Feature folders: a scene and its script sit side by side (`main/`, `player/`, `items/`, `world/sandbox/`...).
- Systems talk through the `Events` signal bus, not through absolute node paths into other scenes.
- Autoloads (`autoload/`):
  - `Events` — global signal bus; add signals when a feature needs them (mark each `@warning_ignore("unused_signal")`). Now: `interaction_prompt_changed(text)`, `objective_changed(text)`.
  - `GameState` — playthrough progress (`day`, `client_index`).
  - `Transition` — black overlay: `await Transition.change_scene(path)`, `fade_out()`, `fade_in()`, `show_title(text)` (leaves the screen black; call `fade_in()` after).
  - `Dialogue` — comic-style dialogues, see below.
- Input actions: `move_forward/back/left/right` (WASD), `interact` (E), `use` (LMB), `highlight` (RMB), `pause` (Esc). Keys are physical, so they work on any keyboard layout.
- Physics layers: 1 `world`, 2 `player`, 3 `interactable` (bit value 4).
- Commit the `.uid` files Godot creates next to scripts.

# Building blocks
- `player/player.tscn` (`Player`, group `player`): walking, mouse look, one held item (`held_item`, `hold()`, `take_item()`).
  Block input with `lock_controls(&"reason")` / `unlock_controls(&"reason")`; it stays locked while any reason remains. HUD is inside the player scene.
- `Interactable` (`interaction/interactable.gd`, an Area3D on layer 3 with a CollisionShape3D child): use as is and connect `interacted(player)`, or extend and override `get_prompt()`, `can_interact()`, `interact()`.
  The player's ray (`player/interactor.gd`, 2 m) shows `"E — <prompt>"` when interaction is possible, the bare prompt when it isn't, nothing for an empty prompt.
- `items/item.tscn` (`Item`): set `item_id`, `display_name`, `mesh`, `color`. Put it under an `ItemSlot` in the editor to start there. No dropping on the floor.
- `items/item_slot.tscn` (`ItemSlot`): `accepts` filters by `item_id` (empty = any); signals `item_placed(item)`, `item_removed(item)`.
- Stairs: visual steps without collision plus an invisible ramp `StaticBody3D` — `CharacterBody3D` doesn't climb steps.
- Scenes: `main/main.tscn` is the start screen and leads to the level; `world/sandbox/sandbox.tscn` is a test ground (shelf with items, table with slots, stairs, day sign, tattoo chair).

## Level (`world/`)
- `world/level/level.tscn` is the game: `Studio` + `Basement` scenes (authored in level coordinates), `Lighting` (`DayNight`), `Points`, `Player`.
  `level.gd` runs the day loop so far: black "День N" card → spirit talks by the altar → objective "go up and open the studio" → `Events.studio_opened` → clients from `CLIENTS` come in one by one: wait at reception → E to talk (greeting) → sit in the chair → chair starts a session with their stencil → perfect result lights their eyes → farewell → they walk out while the next one walks in. Roulette timing, prep, cleanup, hypnosis and night are step 7+.
- Layout: studio floor y=0, x −4..4, z −3..3; entrance + OPEN sign on the front wall (z=3), street outside; back door (x=3, z=−3) → stairwell down to the basement (floor y=−3, z −12..−7). Walls are one `CSGCombiner3D` per scene (outer boxes minus inner boxes and holes).
- Props (`world/props/`): `Door` (hinged `AnimatableBody3D` with `sync_to_physics = false` so collision follows the hinge; `locked` blocks only the player, code can `open()`), `OpenSign` (emits `studio_opened`/`studio_closed`; closing only when `can_close`), `tattoo_chair.tscn`, `CandleSpot` (candle-only `ItemSlot`, group `candle_spot`, glows when `lit`).
- `DayNight.set_night()`: sun, studio lamps, street colour, candles (lit only at night, only where a candle stands). F2 toggles it for now.
- NPC markers in `Points`: `Street`, `Entrance`, `ReceptionWait`, `ChairSeat` (beside the chair; sitting snaps to the chair's `SeatPoint`), `Exit`, `BasementStairsTop`, `AltarSpot`.
- Navigation: `Navigation` (NavigationRegion3D) uses the pre-baked `world/level/level_navmesh.tres`. After changing level geometry re-run `Godot --headless --path . --script res://tools/bake_level_navigation.gd`. Doors are excluded from the bake, so code must open the entrance for clients (`level.gd` counts clients in the doorway).

## Clients (`characters/client/`)
- `ClientData` (`data/clients/*.tres`): name, placeholder colour/height, `stencil`, `greeting`, `farewell` dialogues. Demo: Антон (sigil), Марина (eye), Глеб (moon).
- `Client` (CharacterBody3D on layer 4 `npc`; player collides with npc, clients don't collide with the player): `await walk_to(point)` on the navmesh, `sit(seat)`, `stand_up(point)`, `face(point)`, `allow_talk(bool)` → `talk_requested`, `set_eyes_glowing()`, `hypnotize()`, `follow(target)` (for step 8). Look lives under `Visual` (capsule now, 2D sprite later); `head` (`Visual/Head`) is the dialogue bubble anchor.
- Never give two sibling nodes the same name in a `.tscn` — Godot silently drops one (this happened with the chair's `Seat`).
- `Transition.keep_black()` from a scene's `_ready` keeps `change_scene()` from fading in, so the scene can run its own intro.

## Dialogues (`dialogue/`, autoload `Dialogue`)
- `await Dialogue.play(dialogue, client_head, client_name)` — locks the player, plays every line, unlocks. LMB/E: first press finishes typing, next press advances.
- `DialogueData` = list of `DialogueLine` (`speaker` SPIRIT / PLAYER / CLIENT, `text` with BBCode and `{client}`), stored as `.tres` in `data/dialogues/`. New dialogue = new `.tres`.
- Views (`DialogueView`): spirit → dark shaking panel at the top + violet vignette + whisper; player → caption at the bottom ("Я"); client → `SpeechBubble` that tracks `client_head` (a Node3D above the head) and sticks to the screen edge when it's off screen.
- Day loop: the level plays `spirit_day1.tres` on day 1, `spirit_morning.tres` later, right after the "День N" card. `test_client.tres` is used by the sandbox's test client.
- All texts are Russian; the spirit has no name ("Дух").

## Tattoo session (`tattoo/`)
- Feel goal: as pleasant as cleaning in **PowerWash Simulator**. No timer, no grade, no ink penalties; difficulty comes from spirit tasks.
- A 2D screen over the game, not a 3D close-up. `TattooSession` (CanvasLayer 10): add it, then `roll_and_start(stencil)` (roulette first) or `start(stencil, tasks)`; `await session.finished` → `SessionResult` (`tasks`, `intensities`, `passed`, `is_perfect()`). The caller frees it and restores the mouse mode (see `world/sandbox/sandbox.gd`).
  Running `tattoo/tattoo_session.tscn` on its own rolls the roulette and restarts when done — use it for tuning (exports under "Tuning"; set `fixed_tasks` to skip the roulette).
- Skin and stencil sit in `Body` (a full-rect Control) that tasks can push; tasks live in `Body/Modifiers`, so they move with the skin and draw on it. `InkCap` and HUD stay put.
- `InkCanvas`: pure logic on a 256×256 coverage grid. Ink only lands on stencil cells and builds up over time under the needle; a part auto-completes at 97% (`part_completed`). `find_unfilled_near()` feeds the magnet.
- Drawing: each part is a TextureRect with `stencil_ink.gdshader` — crisp edges from the full-res part texture, soft fill from the coverage texture; uniforms `done`, `flash`, `highlight`.
- Needle: `TattooMachine` only reports the mouse (`pointer`) and draws itself at `needle`. `TattooSession._update_needle()` is the one place that turns pointer into needle (magnet pull toward unfilled stencil, then smoothing) — spirit tasks (step 3) add their offsets there.
- Ink supply: the machine holds `ink_capacity` (filled-cell units; `stamp()`/`stroke()` return ink laid down). When dry it still buzzes but lays nothing; the gauge beside the machine turns orange when low and red when empty, the ink cap (bottom left) pulses, the HUD says to dip. Holding LMB over the cap refills in `refill_time`.
- Feedback: per-part white flash + ding rising a whole tone per completed part, HUD flash label, machine hum and ink spray while inking, RMB "ping" lights up what's left and fades.
- Placeholder sounds in `placeholders/sounds/`, synthesized by `tools/generate_placeholder_sounds.gd` (the hum loops via its `.import` setting).

## Spirit tasks (`modifiers/`) and roulette (`ui/roulette/`)
- A task = `ModifierData` (`data/modifiers/*.tres`: name, spirit line, colour, scene) + a scene whose root extends `TattooModifier`.
  Override `needle_offset()`, `skin_offset()`, `status_text()`, `is_passed()`, `stop()` (call `super()`). `session`, `data`, `intensity` are set before `_ready`.
  Adding a task: new folder + `.tres`, then add it to `task_pool` in `tattoo/tattoo_session.tscn`. No session code changes.
- Repeats on the roulette become one task with higher `intensity` (shown as "×2").
- Fear: noise drift on the needle with panic waves; always passes. Spiders: click (needle or mouse within `hit_radius`) to squash; more than `allowed_escapes` escapes fails. Pain: tense (skin reddens) → jerk → hold → return of the whole `Body`; always passes.
- `Roulette`: three reels, each a task or "Пусто" (`empty_weight`); `await roulette.spin(pool)` returns the tasks after the player clicks.
- Stencils (`StencilData`) are lists of `StencilPart` (name + texture). One PNG per part, all the same size, opaque pixels = area to fill. Placeholder: `data/stencils/sigil/`, generated by `tools/generate_placeholder_stencil.gd`.

## Testing
- To test a flow headless, put a temporary scene in `_test/` (git-ignored) that drives it with `Input.action_press` / `Input.parse_input_event`, run it with `--headless --path . res://_test/<scene>.tscn`, then delete it.
  Pure-logic tests can be a `extends SceneTree` script run with `--headless --path . --script res://_test/<file>.gd`.
- A test that changes the current scene must run from a node added to the root, or it is freed with the old scene.
- Headless windows are tiny: mouse events are in window pixels, so map positions with `get_tree().root.get_final_transform() * viewport_pos`.
- `ImageTexture.get_image()` returns nothing useful headless; check the source `Image` instead.
- To see a screen, run a temporary scene windowed (no `--headless`) that saves `get_viewport().get_texture().get_image()` to a PNG in the scratchpad, then read the PNG.

# Game concept
First-person game. The player is a tattoo artist with esoteric leanings: believes in spirits, does occult tattoos.
At the start a dark spirit contacts them: it must be freed, and for that the artist has to carry out its tasks every day.

## Locations
- **Tattoo studio**: small; reception desk, entrance door with an OPEN/CLOSED sign, session chair, workstation with supplies.
- **Basement**: altar to the spirit, spots for candles and other ritual props.

## Art direction
- Characters and animations will be flat 2D sprites in a 3D world (billboards). The user will provide the art later.
- Until then use simple 3D placeholder figures (capsules, CSG/primitive meshes). Build character scenes so the visual can be swapped for a sprite without touching logic.
- Spirit and dialogue text are shown comic-style (speech bubbles / text panels), no voice acting.

## Core mechanic 1: tattooing
- Very casual, modeled directly on **PowerWash Simulator**: move the tattoo machine over the skin, hold to ink, fill the stencil; progress fills by area.
- At the start of every session the spirit spins a **roulette** that gives a combination of tasks (modifiers) that make the session harder. Examples:
  - *Instill fear*: the player's hands shake while tattooing.
  - *Childhood trauma* (client is afraid of spiders): spiders run across the skin, the player must hit them.
  - *Instill pain*: the client jerks their arm away, the player has to keep up.
- Start with just a couple of modifiers; the system must make adding new ones easy.
- A perfect session makes the client's eyes glow: the spirit says (in text) this client is ready for the ritual.

## Core mechanic 2: the ritual
- After three clients the day ends and night begins. In the basement the player sacrifices one of the clients to the spirit.
- Demo: the chosen client is always the 3rd one. The player leads them to the basement, prepares the ritual (candles and other small tasks), then kills them brutally. Then the next day starts.

## Day loop
1. Day starts → dialogue with the spirit.
2. Go out into the studio, press OPEN.
3. Client arrives → dialogue with the client → roulette gives the spirit's tasks.
4. Prepare the workstation: tiny fetch quest for a few items (needle, ink, ...).
5. Tell the client the station is ready → switch to tattoo mode → tattoo while following the roulette tasks.
6. Client leaves → clean up the workstation (one interaction).
7. Next client is already waiting at reception → repeat from step 3, three clients in total.
8. After the 3rd client the spirit hypnotizes them so they can't leave.
9. Player closes the studio, goes to the basement and prepares the ritual site.
10. Player returns to the client; player, client and spirit end up in the basement and perform the ritual.
11. Black screen with "Day N" → next day.
