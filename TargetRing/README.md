# TargetRing

Draws a ring on the ground under your current target and subtarget in
Final Fantasy XI.

The ring sits flat on the ground, scales with the size of the mob, and tracks
the model exactly while it moves. Enemies get a red ring, players and other
friendly targets get a blue one.

<img width="627" height="368" alt="image" src="https://github.com/user-attachments/assets/86ebd4aa-8d15-4ac4-a914-5e18e2af7d43" />


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
        └── src/
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

## Notes

TargetRing is a binary addon, not a Windower plugin. The DLL in `libs` is loaded
by the addon itself and draws through the game's own renderer, so Windower
updates do not affect it.

The `src` folder holds the source and build files. It's only there so the code
can be read. You do not need it to use TargetRing.

## Credits

Nalfey for the motion smoothing, the model size fallback, the conflict handling and 
for the groundwork on earlier versions.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
