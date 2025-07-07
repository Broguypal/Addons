# CondensedDamage
A minimal Windower addon for Final Fantasy XI that condenses auto-attack and Enspell damage from players, trusts, and NPCs into a single line per action round. 

## What It Does
- Replaces multiple log lines of damage with a single summary line.
- Keeps monster attacks completely native (unchanged).
- Does not affect WS, magic, or TP moves.

## Example
Instead of:
```
Player hits Goblin for 112.
Player hits Goblin for 130.
Additional effect: 15 points of damage.
```
You’ll see:
```
Player dealt 242 to Goblin (2 hits)
Player's Enspell hits Goblin for 15 (1 hit)
```

## Chat Modes Used
- **151**: For normal auto-attacks (used by NPC text too).
- **122**: For Enspell damage (part of Battle Messages).

## Important Filters
To see condensed output:
- Enable **NPC Dialogue** to view mode 151 messages.
- Enable **Battle Messages** to view mode 122 (Enspell) lines.

## Notes
- Condensed output shows once per action round.
- Will not show unless the required filters are enabled.

## Additional Info
CondensedDamage adds custom messages to the chat log using windower.chat.input(), which makes them show up just like normal system messages.
Because of this, other addons that read the visible chat log (like ones that use incoming text) can still see these messages.
Unlike Battlemod, CondensedDamage doesn't replace or hide messages in a way that would block other addons from seeing them.
