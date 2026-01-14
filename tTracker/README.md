# tTracker

**tTracker** is a Windower addon that displays recent spell casts and TP moves used by your current target in a small, draggable text box. It helps track enemy actions in real time.

---

## Features

- Displays:
  - Spells cast by your target (color-coded by element)
  - Monster abilities being readied by your target (with optional manual element coloring)
  - Weapon skills being used by your player/trust target (color-coded by element)
  - Spells and TP moves interrupted
  - Spells and TP moves completed
- Fully draggable overlay box
- Customizable:
  - Display mode: always, combat-only, or only when actions occur
  - Number of visible lines (1–50)
  - Duration each line stays visible (1–120 seconds)
- Settings save automatically (position, mode, timeout, etc.)

---

## Display Modes

`tTracker` supports three display modes you can toggle with `//track mode`:

- **always** – The box is always shown (even when no target actions occur).
- **combat** – Only shown while you are in combat.
- **action** – Only shown when your current target uses an action (spell or TP move), then hides after.

---

## Commands

Use these in-game:

```
//track mode [always|combat|action]       -- When to show the box
//track lines <1–50>                      -- Max lines displayed (default: 5)
//track timeout <1–120>                   -- Line duration in seconds (default: 20)
//track status                            -- View current settings
//track add "Ability Name" <element>      -- Assign a monster TP move to an element
//track remove "Ability Name"             -- Remove a tracked monster TP move
```

You can also use `//ttracker` in place of `//track`.

---

## Custom Monster Ability Elements

`tTracker` allows you to manually color monster TP moves by assigning them an element using:

```
//track add "Ability Name" <element>
//track remove "Ability Name"
```

Valid elements are: `fire`, `water`, `wind`, `ice`, `earth`, `thunder`, `light`, `dark`

Once added, the ability will show in the corresponding element color (same as spells).

Note:
- You **cannot assign the same ability to more than one element**.
- Abilities are saved to `Monster_Ability_Elements.lua` and persist between sessions.

---

## Installation

1. Place the folder in your `Windower4/addons/` directory.
2. Load it in-game with:

```
//lua load ttracker
```

---

## Author

- **Name:** Broguypal
- **Version:** 2.0
