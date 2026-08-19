# TargetRing

Draws a ring on the ground under your current target and subtarget in
Final Fantasy XI.

The ring sits flat on the ground, scales with the size of the mob, and tracks
the model exactly while it moves. Enemies get a red ring, players and other
friendly targets get a blue one.

<img width="627" height="368" alt="IqvTxbW" src="https://github.com/user-attachments/assets/8083bc17-7ea9-4c79-8feb-3fab11262799" />

## Installation

Download the latest release and drop the `TargetRing` folder into your Windower
`addons` folder:

```
Windower/
└── addons/
    └── TargetRing/
        ├── TargetRing.lua
        ├── libs/
        │   └── _TargetRing.dll
        ├── src/
        └── SceneHook/
```

Then type this in game:

```
//lua load TargetRing
```

That's it. Nothing goes in the `plugins` folder and there is nothing to
configure.

To load it every time you log in, add that line to `Windower/scripts/init.txt`.

## Commands

```
//tring          show status
//tring off      stop drawing
//tring on       start drawing again
```

## Requirements

Windower 4.

## Running alongside GEO-HUD

TargetRing and GEO-HUD can run together, in any load order, and either one can be
unloaded or reloaded at any time. Neither addon hooks the other: both draw
through a shared scene hook that owns the single `draw_scene` patch for the whole
process. If both are loaded, both draw, and their rings stack.

This needs GEO-HUD 2.0.0 or newer. Older versions patch `draw_scene` themselves
and will conflict.

See [SceneHook/SceneHook.md](SceneHook/SceneHook.md) for how it works, or if you are writing an addon
that needs to draw in the 3D scene yourself.

## Notes

TargetRing is a binary addon, not a Windower plugin. The DLL in `libs` is loaded
by the addon itself and draws through the game's own renderer, so Windower
updates do not affect it.

The `src` folder holds the source and build files. It's only there so the code
can be read. You do not need it to use TargetRing.

The `SceneHook` folder is self-contained and reusable. Any addon that wants to
draw in the 3D scene can copy it as-is; see `SceneHook/SceneHook.md`.

## Changes in 3.0.0

Rewritten hook handling: TargetRing no longer chains into or scans for other ring
addons. Load order, unload order and reloading no longer matter. About 250 lines
of cross-addon code were removed.

## Credits

Nalfey for the motion smoothing, the model size fallback, the conflict handling and 
for the groundwork on earlier versions.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
