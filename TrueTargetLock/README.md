# TrueTargetLock v1.1

TrueTargetLock is a Windower addon that automatically keeps your character facing your current target while you are engaged in combat.

It helps track the monster if it moves, keeping you properly oriented so your attacks continue to connect.

This prevents common melee issues where auto-retarget selects a new monster but your character is not facing it, resulting in **"not facing the target"** messages and lost attacks.

---

## What It Does

- Automatically turns you to face your current target
- Tracks the monster if it moves around you
- Works with FFXI’s native auto-retarget system
- Prevents "not facing the target" attack failures
- Only active while you are **engaged** and have a valid target

---

## Modes (v1.1)

TrueTargetLock supports two operating modes that can be changed with commands and are saved between sessions.

Your selected mode is stored in:

    addons/TrueTargetLock/data/settings.xml

and will persist across reloads and game restarts.

### 🔒 Normal Mode (Default)

    //truetargetlock normal

- Turns your character only when **Target Lock (*) is ON**
- Matches traditional FFXI behavior
- Allows free turning when target lock is off

### 🔁 Always Mode

    //truetargetlock always

- Always turns you toward your target while engaged
- Works even if **Target Lock is OFF**
- ⚠ You will not be able to turn away from your target while engaged

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

4. (Optional) Change modes:

       //truetargetlock normal
       //truetargetlock always

---

## Auto-Load on Login (Optional)

You can have the addon load automatically by editing your Windower scripts file and adding:

       lua l TrueTargetLock

This will load the addon every time you start the game.

Copyright (c) 2026 Broguypal / MIT License
