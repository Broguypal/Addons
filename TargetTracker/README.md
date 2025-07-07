# TargetTracker

TargetTracker is a Windower addon for Final Fantasy XI that shows what your current target is casting or readying. It displays this information in two small boxes on your screen—one for spells, one for TP moves.

---

## Features

- Shows spells and TP moves in real-time.
- Boxes are draggable and remember their position.
- You can choose when the boxes appear (always, in combat, or only on action).
- Easy to configure inside the .lua file.

---

## Settings

You can change these in the Lua file:

- `max_entries = 3` — How many lines show in each box.
- `expire_seconds = 30` — How long each line stays visible.

The box positions and display mode are saved in `settings.xml`.

---

## Commands

Use either `//tart` or `//targettracker` in-game:

- `//tart box always` – Boxes always visible (default)
- `//tart box combat` – Boxes only show while you're fighting
- `//tart box action` – Boxes only show when something is cast or readied

---

## Important Notes

- This addon reads the visible game chat. If you're using Battlemod or anything that changes how spells/TP moves appear, TargetTracker may not work.
- Make sure you have **"Battle Messages"** turned ON in your chat filters.
- Don’t block special actions like monster magic or TP moves.

---

Made by **Broguypal**
