# TrueTargetLock v1.2

TrueTargetLock is a Windower addon that automatically keeps your character facing your current target.

It helps track the monster if it moves, keeping you properly oriented so your attacks continue to connect.

This prevents common melee issues where auto-retarget selects a new monster but your character is not facing it, resulting in **"not facing the target"** messages and lost attacks.

---

## What It Does

- Automatically turns you to face your current target
- Tracks the monster if it moves around you
- Works with FFXI’s native auto-retarget system
- Prevents "not facing the target" attack failures
- Configurable to work in or out of combat, with or without native target lock

---

## Settings (v1.2)

TrueTargetLock has two toggles that are saved between sessions in:

    addons/TrueTargetLock/data/settings.xml

### ⚔ Combat (Default: ON)

    //truetargetlock combat on
    //truetargetlock combat off

- **ON**: Only active while you are **engaged**
- **OFF**: Active in or out of combat

### 🔒 Locked (Default: ON)

    //truetargetlock locked on
    //truetargetlock locked off

- **ON**: Only active while **Target Lock (*)** is on
- **OFF**: Active even when Target Lock is off

Leaving off `on`/`off` toggles the current value. Use `//truetargetlock status` to see your current settings.

### Combinations

| Locked | Combat | Behavior |
|--------|--------|----------|
| ON  | ON  | Faces your target while engaged and locked on *(default, formerly Normal mode)* |
| ON  | OFF | Faces anything or anyone you are locked onto, in or out of combat |
| OFF | ON  | Always faces your target while engaged *(formerly Always mode)* ⚠ You cannot turn away while engaged |
| OFF | OFF | Always faces whatever you currently have targeted ⚠ You cannot turn away from any target |

If you have no target, the addon does nothing.

Upgrading from v1.1: an existing `always` mode setting is automatically converted to `locked off`.

---

## What It Does NOT Do

- Does not auto-target monsters
- Does not move your character
- Does not engage or disengage combat

---

## How to Use

1. Copy the **TrueTargetLock** folder into your Windower `addons` directory.

2. Load the addon:

       //lua load TrueTargetLock

3. Engage a monster.
   The addon will automatically keep you facing your current target.

4. (Optional) Adjust settings:

       //truetargetlock combat on|off
       //truetargetlock locked on|off
       //truetargetlock status

---

## Auto-Load on Login (Optional)

You can have the addon load automatically by editing your Windower scripts file and adding:

       lua l TrueTargetLock

This will load the addon every time you start the game.