extends Node
## Global signal bus. Systems emit and listen here instead of referencing each other.
## Signals are added as features need them.

## Hint for what the player is aiming at; empty hides it.
@warning_ignore("unused_signal")
signal interaction_prompt_changed(text: String)

## Current goal shown in the HUD; empty hides it.
@warning_ignore("unused_signal")
signal objective_changed(text: String)

## The OPEN sign was turned: the working day starts.
@warning_ignore("unused_signal")
signal studio_opened

## The sign was turned back to CLOSED: no more clients today.
@warning_ignore("unused_signal")
signal studio_closed

## The player went down to the basement (true) or came back up (false).
@warning_ignore("unused_signal")
signal underground_changed(underground: bool)
