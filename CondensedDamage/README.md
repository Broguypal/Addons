# CondensedDamage
A minimal Windower addon for Final Fantasy XI that condenses auto-attack and Enspell damage from players, trusts, and NPCs into a single line per action round. Now includes customizable filters and toggle commands.

## What It Does
- Replaces multiple log lines of damage with a single summary line.
- Keeps monster attacks completely native (unchanged).
- Allows filtering damage from different sources (you, party, alliance, trusts, others).
- Supports in-game commands to toggle filters and check status.

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

## Filtering Options
You can choose which sources of damage are shown using in-game commands or by editing `settings.xml`:

- Show/hide **your own** damage
- Show/hide **party** member damage
- Show/hide **alliance** member damage
- Show/hide **trust/NPC** damage
- Show/hide **other players'** damage

## In-Game Commands
- `//cdd toggle self` – Show/hide your own damage
- `//cdd toggle party` – Show/hide party member damage
- `//cdd toggle alliance` – Show/hide alliance member damage
- `//cdd toggle trusts` – Show/hide trust/NPC damage
- `//cdd toggle others` – Show/hide other player damage
- `//cdd status` – Show current filter settings
- `//cdd help` – Show available commands

## Notes
- Condensed output shows once per action round.
- Filters are saved and persist across sessions.
- Condensed messages still appear in the chat log like normal and work with other addons that read chat.
