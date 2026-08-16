# TargetRing

Draws a ring on the ground under your current target and subtarget in
Final Fantasy XI.

The ring sits flat on the ground and scales with the size of the mob.

<img width="249" height="301" alt="Screenshot 2026-08-15 201035" src="https://github.com/user-attachments/assets/bc9b7134-0037-4ba0-b8d7-61dbe371fd8d" />

<img width="447" height="311" alt="Screenshot 2026-08-15 201126" src="https://github.com/user-attachments/assets/b076b4eb-1dbc-4de1-8ddb-0aaca096222e" />

## Installation

Download the latest release and drop the `TargetRing` folder into your
Windower `addons` folder:

```
Windower/
└── addons/
    └── TargetRing/
        ├── TargetRing.lua
        ├── plugins/
        │   └── TargetRing.dll
        └── src/
```

Then type this in game:

```
//lua load TargetRing
```

That's it. The addon copies `plugins\TargetRing.dll` into `Windower/plugins/` for you the
first time it runs, then starts the plugin. You do not need to move the DLL
yourself.

To load it every time you log in, add the `lua load TargetRing` line to
`Windower/scripts/init.txt`.

## Updating

Replace the `addons/TargetRing` folder with the new one and log in. The addon
notices the version changed, unloads the old plugin, copies the new DLL over,
and reloads it. Nothing else to do.

## Commands

```
//tring status    show whether the plugin is running and which version is installed
//tring install   force a copy of the bundled DLL into the plugins folder
```

## Troubleshooting

**Rings don't appear.** Type `//tring status`. It will tell you whether the
plugin is running and whether the DLL made it into the plugins folder.

**"Could not install the plugin."** The addon could not write to
`Windower/plugins/`. This usually means Windower is installed somewhere that
needs administrator rights, such as `Program Files`. Copy
`addons\TargetRing\plugins\TargetRing.dll` to `plugins\TargetRing.dll` by hand,
then type `//lua reload TargetRing`.

**Antivirus flagged something.** The addon writes a DLL to disk, which some
scanners treat as suspicious on principle. The file it writes is a byte-for-byte
copy of the DLL that shipped in the addon folder. Copying it by hand instead
works exactly the same.

## Requirements

Windower 4.

## Notes

The `src` folder holds the plugin's source code and build files. It's only there
so the code can be read. You do not need it to use TargetRing.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
