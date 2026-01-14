# TrueTargetLock 

TrueTargetLock is a Windower addon for Final Fantasy XI that automatically keeps your character facing your current target while you are engaged in combat and target lock is enabled.

It also helps track the monster if it moves, keeping you properly oriented so your attacks continue to connect.

This prevents common melee issues where auto-retarget selects a new monster but your character is not facing it, resulting in "not facing the target" messages and lost attacks.

## What It Does

- Automatically turns you to face your current target
- Tracks the monster if it moves around you
- Works with FFXI’s native auto-retarget system
- Prevents "not facing the target" attack failures
- Only active while:
  - You are engaged, and
  - Target lock is ON (numpad *)

## What It Does NOT Do

- Does not auto-target monsters
- Does not move your character
- Does nothing if target lock is OFF

## How to Use

1. Copy the TrueTargetLock folder into your Windower addons directory.
2. Load the addon:
   //lua load TrueTargetLock
3. Engage a monster.

If you turn off target lock, the addon becomes inactive.

## Auto-Load on Login (Optional)

You can have the addon load automatically by editing your Windower init.txt file under Windower>scripts and adding:

		lua l TrueTargetLock

This will load the addon every time you start the game.
