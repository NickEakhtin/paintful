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
  - `GameState` — playthrough progress that survives level reloads (`day`, `client_index`, `trophies`).
  - `Transition` — black overlay: `await Transition.change_scene(path)`, `fade_out()`, `fade_in()`, `show_title(text)` (leaves the screen black; call `fade_in()` after), `flash(color)` (instant colour that fades, non-blocking).
  - `Dialogue` — comic-style dialogues, see below.
- Input actions: `move_forward/back/left/right` (WASD), `interact` (E), `use` (LMB), `highlight` (RMB), `turn_to_ink` (Q, tattoo session), `pause` (Esc). Keys are physical, so they work on any keyboard layout.
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
- `world/level/level.tscn` is the game: `Studio` + `Basement` scenes (authored in level coordinates), `Lighting` (`DayNight`), `Points`, `Player`, `DayFlow`.
- `DayFlow` (`world/level/day_flow.gd`) is the day loop as one top-to-bottom script with `await`s — keep it that way, it should read like the loop above:
  "День N" → spirit by the altar → open the studio → per client: arrive → E to talk (greeting) → spirit line + roulette (in the studio) → client waits on the bench, objective lists 2 random items to bring to the `Workstation` → E on client "Позвать в кресло" → they sit, the session starts with the rolled tasks → clients 1–2: spirit verdict (pleased if `is_perfect()`), farewell, they leave while the next walks in, the player must tidy the table → client 3: the spirit claims them (eyes glow, hypnotized, stays) → sign can close → night →
  ritual prep (5 candles into the circle's `CandleSpot`s, knife into `AltarSlot`) → E on the chosen one "Повести за собой" → they `follow()` the player down → E on the altar "Начать ритуал" → they kneel at `RitualCenter`, spirit speaks → E on them "Отрезать голову" (one action: red `Transition.flash`, chop sound, `behead()`, head hangs on the next free `HeadMount`) → spirit speaks → `GameState.start_new_day()` → `Transition.change_scene` reloads the level → "День N+1".
  Day 1 uses the exported `clients` (Антон, Марина, Глеб); from day 2 the day makes up random clients (names in `RANDOM_NAMES`, random colour/height, one of `random_stencils`, `random_greeting`/`random_farewell`).
  The level reloads every day, so anything that must survive goes into `GameState` (`day`, `trophies` → heads re-hung on the wall at load).
  Exports: `clients`, `task_pool`, the random-client pool and the scene nodes it drives. Debug key: F2 day/night.
- Layout: studio floor y=0, x −4..4, z −3..3; entrance + OPEN sign on the front wall (z=3), street outside; back door (x=3, z=−3) → stairwell down to the basement (floor y=−3, z −12..−7). Walls are one `CSGCombiner3D` per scene (outer boxes minus inner boxes and holes).
- Props (`world/props/`): `Door` (hinged `AnimatableBody3D` with `sync_to_physics = false` so collision follows the hinge; `locked` blocks only the player, code can `open()`), `OpenSign` (emits `studio_opened`/`studio_closed`; closing only when `can_close`), `tattoo_chair.tscn` (just geometry + `SeatPoint`), `Workstation` (table slots; `set_required(ids)`, `missing()`, `has_required()`, `cleanup_needed` → "Убрать рабочее место" puts items back to their `Item.home` slots, `cleaned_up`), `CandleSpot` (candle-only `ItemSlot`, group `candle_spot`, glows when `lit`), `HeadMount` (plaque on the basement `HeadWall`; `hang(client_data)`), basement `AltarInteract` (enabled by `DayFlow` only when the ritual can start).
- `DayNight.set_night()`: sun, studio lamps, street colour, candles (lit only at night, only where a candle stands).
- NPC markers in `Points`: `Street`, `Entrance`, `ReceptionWait`, `BenchWait`, `ChairSeat` (beside the chair; sitting snaps to the chair's `SeatPoint`), `Exit`, `BasementStairsTop`, `AltarSpot`.
- Navigation: `Navigation` (NavigationRegion3D) uses the pre-baked `world/level/level_navmesh.tres`. After changing level geometry re-run `Godot --headless --path . --script res://tools/bake_level_navigation.gd`. Doors are excluded from the bake, so code must open the entrance for clients (`DayFlow` counts clients in the doorway).

## Clients (`characters/client/`)
- `ClientData` (`data/clients/*.tres`): name, placeholder colour/height, `stencil`, `greeting`, `farewell` dialogues. Demo: Антон (sigil), Марина (eye), Глеб (moon).
- `Client` (CharacterBody3D on layer 4 `npc`; player collides with npc, clients don't collide with the player): `await walk_to(point)` on the navmesh, `sit(seat)`, `stand_up(point)`, `face(point)`, `allow_talk(allowed, prompt, enabled)` → `talk_requested`, `set_eyes_glowing()`, `hypnotize()`, `follow(target)`, `kneel()`, `behead()`. Look lives under `Visual` (capsule now, 2D sprite later); `head` (`Visual/Head`) is the dialogue bubble anchor.
- Never give two sibling nodes the same name in a `.tscn` — Godot silently drops one (this happened with the chair's `Seat`).
- `Transition.keep_black()` from a scene's `_ready` keeps `change_scene()` from fading in, so the scene can run its own intro.

## Dialogues (`dialogue/`, autoload `Dialogue`)
- `await Dialogue.play(dialogue, client_head, client_name)` — locks the player, plays every line, unlocks. LMB/E: first press finishes typing, next press advances.
- `DialogueData` = list of `DialogueLine` (`speaker` SPIRIT / PLAYER / CLIENT, `text` with BBCode and `{client}`), stored as `.tres` in `data/dialogues/`. New dialogue = new `.tres`.
- Views (`DialogueView`): spirit → dark shaking panel at the top + violet vignette + whisper; player → caption at the bottom ("Я"); client → `SpeechBubble` that tracks `client_head` (a Node3D above the head) and sticks to the screen edge when it's off screen.
- Day loop: the level plays `spirit_day1.tres` on day 1, `spirit_morning.tres` later, right after the "День N" card. `test_client.tres` is used by the sandbox's test client.
- All texts are Russian; the spirit has no name ("Дух").

## Tattoo session (`tattoo/`)
- Feel goal: as pleasant as cleaning in **PowerWash Simulator**. No timer, no grade, no ink penalties; difficulty comes from spirit tasks (the only ink loss is the Flame task wiping unfinished parts).
- A 2D screen over the game, not a 3D close-up. `TattooSession` (CanvasLayer 10): add it, then `roll_and_start(stencil)` (roulette first) or `start(stencil, tasks)`; `await session.finished` → `SessionResult` (`tasks`, `intensities`, `passed`, `is_perfect()`). The caller frees it and restores the mouse mode (see `world/sandbox/sandbox.gd`).
  Testing shortcut: F3 in a session fills the stencil and ends it at once (`skip()`; off with `debug_skip_enabled`); the HUD hint mentions it.
  Running `tattoo/tattoo_session.tscn` on its own rolls the roulette and restarts when done — use it for tuning (exports under "Tuning"; set `fixed_tasks` to skip the roulette).
- Skin and stencil sit in `View/Body` (a full-rect Control) that tasks can push; tasks live in `Body/Modifiers`, so they move with the skin and draw on it. `View/SideTable` + `View/InkCap` sit `table_offset` px to the right; HUD stays put.
- `InkCanvas`: pure logic on a 256×256 coverage grid. Ink only lands on stencil cells and builds up over time under the needle; a part auto-completes at 97% (`part_completed`). `find_unfilled_near()` feeds the magnet.
- Drawing: each part is a TextureRect with `stencil_ink.gdshader` — crisp edges from the full-res part texture, soft fill from the coverage texture; uniforms `done`, `flash`, `highlight`.
- Machine look: the user's 3D model (`art/models/tattoo_machine/`, Nomad Sculpt OBJ, long clip cord stripped on import) rendered in a full-screen perspective SubViewport inside `tattoo/tattoo_machine.tscn` (camera looking down at the skin plane z = 0); every frame the model is placed so its needle tip (`NEEDLE_TIP`) touches the plane under `needle`, so it's seen from different angles across the screen. Right-handed hold: `angle_at_left` (60°) at the left edge down to `angle_at_right` (30°) at the right; never steeper, or the body hides the tip. In the session the needle surface uses a no-depth-test, spirit-purple glowing material so the tip always shows over the body. Weight: setting `machine.needle` sets where the hand wants it, reading it gives where the needle really is — it follows on a spring (`follow_frequency`, `follow_damping`; jumps over `snap_distance` teleport), and the top swings behind the motion on its own spring (`swing_*`, `lean_per_speed`). `tattoo_machine.tscn` in `art/` holds the per-part materials and is also a prop on the studio workstation.
- Needle: `TattooMachine` only reports the mouse (`pointer`) and draws itself at `needle`. `TattooSession._update_needle()` is the one place that turns pointer into needle (magnet pull toward unfilled stencil, then smoothing) — spirit tasks (step 3) add their offsets there.
- Ink supply: the machine holds `ink_capacity` (filled-cell units; `stamp()`/`stroke()` return ink laid down). When dry it still buzzes but lays nothing; the gauge beside the machine turns orange when low and red when empty, the ink cap pulses, the HUD says to turn to it. Each LMB click on the cap adds 1/`refill_clicks` of a full tank (3 clicks from empty) and makes the ink wobble (`InkCap.dip()`).
- The ink cap stands on a side table off screen to the right. Q (`turn_to_ink`) swings the whole `View` (skin + table) left by `table_offset` in `turn_time` with a horizontal smear (`motion_blur.gdshader`); Q again swings back. No screen-edge swings (the user disliked turning with the mouse). Never move or warp the machine/mouse on a swing — the user feels any jump as losing control; it always stays under the mouse. The cap is `tattoo/ink_cap.tscn` (`InkCap`): a small 3D cup with ink inside rendered through a SubViewport. LMB must be released once after the swing back before it inks again.
- Feedback: per-part white flash + ding rising a whole tone per completed part, HUD flash label, machine hum and ink spray while inking, RMB "ping" lights up what's left and fades.
- Placeholder sounds in `placeholders/sounds/`, synthesized by `tools/generate_placeholder_sounds.gd` (writes only missing files; the hum and whisper loop via their `.import` setting).
- The session ignores input and stops painting while `Transition.is_busy`, so nothing (F3 included) fires before the caller awaits `finished`.

## Spirit tasks (`modifiers/`) and roulette (`ui/roulette/`)
- A task = `ModifierData` (`data/modifiers/*.tres`: name, spirit line, colour, scene) + a scene whose root extends `TattooModifier`.
  Override `needle_offset()`, `skin_offset()`, `can_ink()`, `status_text()`, `is_passed()`, `stop()` (call `super()`). `session`, `data`, `intensity` are set before `_ready`.
  Session API for tasks: `needle_position()`, `pointer_position()`, `needle_velocity()` (the spring needle, zero after a teleport), `machine_top_position()` (screen point of `TattooMachine.TOP`), `wipe_unfinished(color)`, `skin`.
  Adding a task: new folder + `.tres`, then add it to `task_pool` in `tattoo/tattoo_session.tscn`. No session code changes.
- Repeats on the roulette become one task with higher `intensity` (shown as "×2"). `ModifierData.max_count` caps how many reels may land on a task (Spiders: 1, never repeats).
- Pool now: Spiders and Flame (Fear and Pain were removed).
- Spiders: one every `spawn_interval` (5 s, ±30%; first after 2.5 s); click (needle or mouse within `hit_radius`) to squash; more than `allowed_escapes` escapes fails.
- Flame: a flame burns on the machine top (`Fire` node, `top_level`, `z_index` over the machine, `flame.gdshader`). Needle speed over `safe_speed` drains it, at `blowout_speed` it goes out at once (both ×`intensity_factor` per repeat). Out: hiss + smoke, `wipe_unfinished()` (done parts stay), `can_ink()` false until the needle stays under `still_speed` for `relight_time`. More than `allowed_outs` outs fails. The look follows the current speed (`_gust`, from `react_from` × `safe_speed`): the flame shrinks, tears, flickers faster and reddens before any flame is lost, so the player sees "too fast" early. A 500 px move takes about half the flame in 0.35 s and blows it out in 0.25 s.
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
  - *Childhood trauma* (client is afraid of spiders): spiders run across the skin, the player must hit them.
  - *Flame*: a flame burns on the machine; moving too fast or too sharply blows it out and the unfinished ink is gone.
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
