# tTracker

**tTracker** is a Windower addon for Final Fantasy XI that displays recent spell casts and TP moves used by your current target in a small, draggable text box. It helps track enemy actions in real time.

---

## Features

- Displays:
  - Spells cast by your target (color-coded by element)
  - TP moves being readied
- Fully draggable overlay box
- Customizable:
  - Display mode: always, combat-only, or only when actions occur
  - Number of visible lines (1–50)
  - Duration each line stays visible (1–120 seconds)
- Settings save automatically (position, mode, timeout, etc.)

---

## Display Modes

`tTracker` supports three display modes you can toggle with `/track mode`:

- **always** – The box is always shown (even when no target actions occur).
- **combat** – Only shown while you are in combat.
- **action** – Only shown when your current target uses an action (spell or TP move), then hides after.

---

## Commands

Use these in-game:

```
//track mode [always|combat|action]   -- When to show the box
//track lines <1–50>                  -- Max lines displayed (default: 5)
//track timeout <1–120>               -- Line duration in seconds (default: 20)
//track status                        -- View current settings
```

You can also use `//ttracker` in place of `//track`.

---

## Important Notes

- Spells are colored based on their **element** as defined by Windower’s `resources`.
- Some spells (specifically Blue Magic spells such as *Cocoon*) may appear with **unexpected colors**.
  - Example: *Cocoon* is an Earth spell, but may appear as element ID `15` (None) due to how Windower classifies it.
- This is a limitation of Windower’s internal spell database and not a bug in the addon.

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
- **Version:** 1.0
