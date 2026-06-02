I'm working on a Godot 4 idle/clicker game (GDScript). I'm not a programmer, so please explain what you're doing in plain language, work in small testable phases, and pause after each phase so I can run the game and confirm before you continue. Don't refactor or rename anything outside the scope below.
Goal: Add a Diablo-2-style drag-and-drop inventory and equipment system, built alongside the existing weapon system (which I want hidden, not deleted).
First, read the project to understand it. Pay special attention to: weapon_manager.gd, weapon_panel.gd, material_manager.gd, asteroid_layer.gd, gun_system.gd, game_manager.gd, equipment_manager.gd, and main.gd. Tell me your understanding before writing code.
Phase 1 — Hide the old weapon system (don't delete).
Stop the weapon panel from showing in the game, but leave weapon_manager.gd and weapon_panel.gd files intact so I can restore them later. Don't remove their autoload registration if doing so would cause errors elsewhere — just make sure no weapon panel appears on screen. Pause and let me confirm the game still runs.
Phase 2 — Inventory data layer (new autoload InventoryManager).
Create a new manager that holds:

A list of all possible item definitions (id, display name, icon path, grid size in cells like 1x1 / 1x2 / 2x2, equip slot type, rarity, and a stats dictionary).
The player's backpack (a grid like Diablo 2 — a fixed number of columns and rows).
10 equip slots: primary_weapon, secondary_weapon (shield generator), thruster, command_bridge, hull, energy_core, radar, drone_1, drone_2, wings.
Functions to add an item to the backpack, move an item, equip/unequip, and check whether an item fits a given slot.
Save/load to the existing save file the same way the other managers do.
For now, make up about 8–12 placeholder items spread across the slot types, each with a small stats dictionary (e.g. fire_rate_pct, damage_pct, fuel_gain_pct, credit_gain_pct). Use simple colored placeholder icons if real art isn't available. Pause so I can confirm it compiles.

Phase 3 — Inventory UI (drag and drop).
Build a Diablo-2-style panel: a grid backpack on one side and the 10 equip slots laid out like the picture I'll describe. I want to drag items from the backpack onto a slot to equip, drag back to unequip, and rearrange items in the backpack. Items should only drop into slots that match their type, and snap back if the drop is invalid. Match the dark blue/steel UI style the rest of the game already uses. Add a way to open/close this panel (a hotkey and/or a button). Pause so I can test the dragging feels right.
Phase 4 — Item drops from asteroids.
In the asteroid loot logic, keep the current material drops exactly as they are, and add a small extra chance (start around 2–5%) that destroying an asteroid also drops one inventory item into the backpack. Rarer items should be much less likely. If the backpack is full, don't drop. Show some small visual or feedback when an item drops. Pause so I can test.
Phase 5 — Make a couple of equipped stats actually do something (keep it simple).
Wire up just two or three of the stats so I can see equipment matter — for example, equipping a primary weapon raises the gun's fire rate, and a stat that boosts fuel or credit gain. Leave the other stats defined-but-unused for now, and add a clear comment listing which stats are not yet wired up so I know what's left for later.
Throughout: keep changes additive and reversible, follow the existing code's style and save-file conventions, and after all phases give me a short plain-language summary of every file you added or changed and how I can undo the whole thing if I want to.