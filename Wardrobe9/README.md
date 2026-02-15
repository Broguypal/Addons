# Wardrobe9

**Wardrobe9** is a Windower 4 addon for *FFXI* that
automatically analyzes your GearSwap Lua files, checks your wardrobes
for the required items, and intelligently swaps gear into place.

Its purpose is simple:

> Make sure the gear referenced in your Lua files is actually present in
> your wardrobes --- and fix it automatically when it isn't.

------------------------------------------------------------------------

## Important Usage Requirement

Wardrobe9 is designed to be used **through its User Interface inside
your Mog House**.

-   The **full interface is only available while you are inside your Mog
    House.**
-   This is where scanning, planning, and execution are intended to
    occur.
-   Using the addon outside of your Mog House will not provide the
    complete interface experience.

This ensures safe wardrobe access and proper operation of the planning
system.

------------------------------------------------------------------------

## What Wardrobe9 Does

Wardrobe9 reads your selected GearSwap file and:

1.  Identifies every item referenced in the Lua.
2.  Checks whether you currently have that item.
3.  Determines whether it is already in a wardrobe.
4.  Automatically swaps it into an appropriate wardrobe if needed.
5.  Replaces unused items of the same equipment type to make room.

This removes the need to manually check bags, compare sets, or move
items one by one.

------------------------------------------------------------------------

## Core Features

### 🔎 Lua File Analysis

-   Scans your GearSwap job file.
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

### 🔁 Automatic Swapping

If an item is found but not stored in a wardrobe:

-   Wardrobe9 will move it into a wardrobe automatically.
-   If the wardrobe is full, it will swap out an unused item of the same
    gear type.
-   Movements are planned first, then executed in a controlled way.

No more manual inventory juggling.

------------------------------------------------------------------------

### 🧠 Smart Planning System

Wardrobe9 follows a safe workflow inside the UI:

1.  **Scan** -- Build a list of all items you own and identify .lua files in your Gearswap folder.
2.  **Plan** -- Compare your gear against the selected Lua.
3.  **Execute** -- Perform only the necessary swaps.

This ensures changes are deliberate and predictable.

------------------------------------------------------------------------

## Configuration (w9_config.lua)

Wardrobe9 includes a configuration file (`w9_config.lua`) that allows
you to adjust how the addon behaves.

Common configurable options include:

-   Which wardrobes are eligible for automatic swapping.
-   Whether inventory or specific bags are included in scans.
-   Swap behavior rules.
-   UI behavior and display settings.
-   Whether certain equipment categories are ignored.

### Weapons

By default, **weapons are not included** in automatic wardrobe
management.

This is intentional to prevent accidental movement of frequently swapped
or situational weapons.
However, this behavior can be changed in the configuration file if you
prefer weapons to be included in the scan and swap process.

------------------------------------------------------------------------

## Typical Use Cases

-   Setting up a new job file.
-   Returning to an old job after months away.
-   Cleaning up wardrobes after gear changes.
-   Verifying that your Lua is fully supported by your current
    inventory.

Wardrobe9 ensures your wardrobes reflect what your job file actually
uses.

------------------------------------------------------------------------

## Additional Practical Benefits

While its main purpose is GearSwap wardrobe management, Wardrobe9 also
allows you to:

-   Quickly generate a full structured list of all items in your
    inventory via the scan cache.
-   Easily validate any GearSwap file to confirm you actually own the
    referenced gear.

These are natural side benefits of the scan and planning system.

------------------------------------------------------------------------

## Installation

Place the `wardrobe9` folder inside your Windower `addons` directory and
load it while inside your Mog House to access the full interface.

------------------------------------------------------------------------

## Why Use Wardrobe9?

Managing multiple jobs with full wardrobes is tedious and error-prone.

Wardrobe9 removes that friction by:

-   Connecting your Lua directly to your wardrobes.
-   Showing you exactly what's missing.
-   Fixing storage automatically.

It turns wardrobe management from a manual chore into a simple, visual
workflow.

------------------------------------------------------------------------

## License

BSD 3-Clause License
Copyright (c) 2026 Broguypal
