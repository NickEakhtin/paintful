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
- Input actions: `move_forward/back/left/right` (WASD), `interact` (E), `use` (LMB), `pause` (Esc). Keys are physical, so they work on any keyboard layout.
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
- Scenes: `main/main.tscn` is the start screen; `world/sandbox/sandbox.tscn` is a test ground (shelf with items, table with slots, stairs, day sign).
- To test a flow headless, put a temporary scene in `_test/` (git-ignored) that drives it with `Input.action_press` / `Input.parse_input_event`, run it with `--headless --path . res://_test/<scene>.tscn`, then delete it.
  A test that changes the current scene must run from a node added to the root, or it is freed with the old scene.

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
