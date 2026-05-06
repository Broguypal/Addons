# Wardrobe9

**Wardrobe9** is a Windower 4 addon for *FFXI* that
automatically analyzes your GearSwap Lua files, checks your wardrobes
for the required items, and intelligently swaps gear into place.

Its purpose is simple:

> Make sure the gear referenced in your Lua files is actually present in
> your wardrobes --- and fix it automatically when it isn't.

------------------------------------------------------------------------

## Important Usage Requirement

Wardrobe9 is designed to be used **through its User Interface inside your Mog House**.

-   The **full interface is only available while you are inside your Mog House.**
-   This is where scanning, planning, and execution occur.

**Note 1**: In windowed mode, button positions may appear slightly offset
from their click targets. This is a known Windower 4 limitation where
text rendering and mouse coordinates can diverge. Borderless Windowed 
or Fullscreen mode is recommended for the best experience.

**Note 2**: If your cursor appears behind the addon interface, this is typically 
caused by the Hardware Mouse setting being disabled in Windower 4. To resolve this, 
open  the Windower launcher, select Edit (pencil icon), navigate to the Game tab, and 
enable the Hardware Mouse option.

------------------------------------------------------------------------

## What Wardrobe9 Does

Wardrobe9 reads your selected GearSwap file and:

1.  Identifies every item referenced in the Lua.
2.  Checks whether you currently have that item.
3.  Determines whether it is already in a wardrobe.
4.  Automatically moves it into an appropriate wardrobe if needed.
5.  Offers two execution modes: **Swap** (replaces unused items of the
    same equipment type to make room) or **Fill** (uses free wardrobe
    slots first, only swapping as a last resort).
6.  Validates your wardrobes for missing or unused gear across your
    selected Lua files.

This removes the need to manually check bags, compare sets, or move
items one by one.

------------------------------------------------------------------------

## Core Features

### 🔎 Lua File Analysis

-   Scans your selected GearSwap job files.
-   Extracts all gear references from your sets.
-   Builds a complete list of required items.

You immediately see what your Lua expects you to have equipped.

------------------------------------------------------------------------

### 📦 Wardrobe Verification

-   Checks your wardrobes and inventory for each referenced item.
-   Clearly indicates:
    -   Items already in wardrobes.
    -   Items found but not currently stored in wardrobes.
    -   Items not found at all.

This provides a fast validation of your job file against your actual
gear.

------------------------------------------------------------------------

### 🔁 Automatic Swapping & Filling

If an item is found but not stored in a wardrobe, Wardrobe9 can move it
in using one of two modes:

-   **Swap mode** — Prioritises swapping out an unused item of the same
    equipment type (ring-for-ring, body-for-body, etc.) to make room.
    If no same-type item is available to evict, it falls back to any
    free wardrobe slot.
-   **Fill mode** — Prioritises filling empty wardrobe slots first.
    Only evicts an unused same-type item if no free space remains.

Both modes are available as buttons in the UI after planning.
Movements are always planned first, then executed in a controlled way.

No more manual inventory juggling.

------------------------------------------------------------------------

### 🧠 Smart Planning System

Wardrobe9 follows a safe workflow inside the UI:

1.  **Scan** -- Build a list of all items you own and identify .lua files in your Gearswap folder.
2.  **Plan** -- Compare your gear against the selected Luas and preview the proposed moves.
3.  **Swap** or **Fill** -- Execute the plan using your preferred mode.
4.  **VAL MISS** or **VAL UNUSED** -- Optionally validate your gear for missing or unused items.

------------------------------------------------------------------------

### ✅ Gear Validation

Wardrobe9 includes two validation tools that cross-reference your
selected GearSwap Lua files against your scan cache:

-   **VAL MISS** — Lists items referenced in your Luas that are not
    currently in your wardrobes. Results are split into two categories:
    items missing entirely (not found in any bag) and items found in
    non-wardrobe bags but not yet moved into a wardrobe.

-   **VAL UNUSED** — Lists items sitting in your wardrobes that are not
    referenced by any of your selected Lua files. Useful for identifying
    gear that can be safely moved out to free up wardrobe space.

Both tools respect augmented gear. Items are matched by name, so
augment-string differences between your Lua source and the game's
internal data will not cause false results. Protected slot groups
and locked items (configured in `w9_config.lua`) are excluded from
the unused report.

Select one or more Lua files, then press **VAL MISS** or **VAL UNUSED**
to run the check. Results appear in the log panel.

------------------------------------------------------------------------

## Configuration (w9_config.lua)

Wardrobe9 includes a configuration file (`w9_config.lua`) that allows
you to adjust how the addon behaves.

Common configurable options include:

-   Setting the default position of the User Interface.
-   Locking specific items from movement.
-   Preventing certain equipment categories (weapons/Head/etc.) from being moved.
-	Setting source bags to be ignored.
-	Defining custom gear variables (`ex. "WAR_AF_HEAD"`) to ensure gear isn't missed.


### Defaults

By default, **weapons** and **items in a players inventory** are *not* moved in automatic wardrobe
management.

This is intentional to prevent accidental movement of situational weapons and to leave your inventory untouched.
However, this behavior can be changed in the w9_config.lua file.

------------------------------------------------------------------------

## Additional Practical Benefits

While its main purpose is GearSwap wardrobe management, Wardrobe9 also
allows you to Qqickly generate a full structured list of all items in your
inventory via the scan cache.

------------------------------------------------------------------------

## Installation

Place the `wardrobe9` folder inside your Windower `addons` directory and
load it while inside your Mog House to access the full interface.

------------------------------------------------------------------------

## Why Use Wardrobe9?

Managing multiple jobs with full wardrobes is tedious and error-prone.

Wardrobe9 removes that friction by:

-   Connecting your Luas directly to your wardrobes.
-   Showing you exactly what's missing.
-   Identifying unused gear that can be cleared out.
-   Fixing storage automatically.

It turns wardrobe management from a manual chore into a simple, visual
workflow.

------------------------------------------------------------------------

## License

BSD 3-Clause License
Copyright (c) 2026 Broguypal