Description:
TargetTracker is a Windower addon that tracks and displays your current target’s spell casting and TP moves in real-time. It presents this information in two customizable, on-screen text boxes for quick awareness during combat.

Each text box is click-and-draggable and their last position is saved in settings. the following settings are easily changed in the lua:
- local max_entries = 3 - Specifies the total number of entries on each box you would like displayed
- local expire_seconds = 30 - Specifies how long you would like each box to keep the prior battle message displayed before it's automatically cleared.

In-Game commands: (//tart or //targettracker)
//tart box always → Boxes always visible (default).
//tart box combat → Boxes only show when you're engaged in combat.
//tart box action → Boxes only show when new actions (cast/TP) are tracked.


NOTE: This version uses incoming text events and is not compatible with chatfilter addons such as Battlemod. If Battlemod is enabled, CastTracker will fail to detect actions based on how Battlemod modifies spell and tp actions.
For this to work with the native FFXI client, Battle messages must be allowed to be displayed. Additionally, you must not have the following chat filters on:
a) Magic Actions
b) TP Moves / Special abilities
