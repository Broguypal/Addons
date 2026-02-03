# dbTracker

**dbTracker** is a Windower addon for *FFXI* that helps players keep track of active debuffs on their party members. It provides a clean overlay with role-colored jobs for easy visibility during combat.

---

## ✨ Features

- **Debuff Tracking**  
  Monitors and displays active debuffs on each party member in real-time, including your own character.  

- **Role-Based Job Coloring**  
  Jobs are automatically colored by their role for quick identification:  
  - **Tank** – Blue  
  - **Healer** – Green  
  - **Pure DD** – Brown  
  - **Hybrid** – Orange  
  - **Magic DPS** – Dark Purple  
  - **Support** – Yellow  

- ** Debuffs Highlighting**  
  Debuffs flagged as **SEVERE** in `tracked_buffs.lua` are displayed in **red**, making them stand out as undispellable.

  
  Debuffs flagged as **NA** in `tracked_buffs.lua` are displayed in **yellow**, making them stand out as being dispellable with a whitemage -NA spell.
  

---

## ⚙️ Installation

1. Place the `dbTracker` folder into your Windower `addons` directory.  
2. Inside Windower, load the addon with:  
   ```
   //lua load dbTracker
   ```

---

## 📖 Usage

- The addon runs automatically once loaded.  
- The overlay displays party slots, names, active debuffs, and role-colored jobs.  
- Drag the header ("dbTracker") to reposition the window.  
- Your own job is detected and colored immediately on load.  

---

## 📝 Notes

- This addon parses incoming packets to maintain accurate debuff states.  
- Zone changes reset tracking to prevent stale data.  
- Only tracked debuffs defined in `tracked_buffs.lua` are shown.  

---

## 👤 Author

Created by **Broguypal**  
Version **1.5** 

Copyright (c) 2026 Broguypal
License: BSD 3-Clause 
