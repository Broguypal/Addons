# RoastMeDaddy

RoastMeDaddy is a **wonderful Windower addon** for Final Fantasy XI that brings humor and fun into your NPC interactions.  
Whenever you talk to an NPC, there’s a chance the addon will inject a random **flirty** or **roasting** one-liner into your chat log.  

---

## ✨ Features
- Automatically injects **flirty**, **roast**, or **random** lines during NPC dialogue.  
- Customizable **mode**, **trigger chance**, **cooldown**, and **delay**.  
- Persistent settings saved between sessions.  
- Two command aliases: `//rmd` or `//roastmedaddy`.  
- Easy to add your own custom lines.

---

## ⚙️ Installation
1. Place `RoastMeDaddy.lua`, `insults.lua`, and `flirty.lua` into your Windower addons folder:  
   ```
   Windower4/addons/RoastMeDaddy/
   ```

2. Load the addon in-game with:  
   ```
   //lua load roastmedaddy
   ```

---

## 🔧 Commands
Use either `//rmd` or `//roastmedaddy` followed by a command:

- `//rmd mode [flirty|roast|random]` — Switches between flirty mode, roast mode, or random.  
- `//rmd chance <0.0–1.0>` — Sets the probability of triggering on NPC dialogue.  
- `//rmd cooldown <seconds>` — Sets cooldown between triggers.  
- `//rmd delay <seconds>` — Sets the delay before injection after NPC dialogue appears.  
- `//rmd test` — Immediately injects a random line for testing.

---

## 📝 Customization
You can add your own lines by editing **insults.lua** or **flirty.lua**.  
Each file is just a Lua table of strings, so simply add more lines to the list.

Example (inside `insults.lua`):
```lua
return {
    "You're slower than a chocobo with a limp.",
    "Did a goblin teach you how to fight?",
    -- Add your own here!
}
```

---

## ✅ Credits
- Author: **Broguypal**  
- Version: **1.0**  
