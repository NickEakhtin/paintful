# Project
3D indie game, Godot 4.7, GDScript only.

- Godot project root: `tattoo/` (has `project.godot`). Git repo root is the folder above it.
- Development roadmap: `docs/ROADMAP.md`. Each big step gets its own detailed plan before work starts.

# Rules
- Godot 4 API only (await, CharacterBody3D, @export). Never Godot 3 syntax.
- Prefer editing .tscn/.gd files directly; keep scenes small and composable.
- Run the game to check for errors (from the Godot project root):
  /Applications/Godot.app/Contents/MacOS/Godot --path . 2>&1
  Quick headless check that exits by itself:
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120 2>&1
- Commit after each working step.

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
