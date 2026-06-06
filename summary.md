# The Traveler — Code Summary

Godot 4 GDScript. A spaceship idle/clicker with a real-time combat layer on top. You captain a ship through deep space: an idle economy accrues **fuel/crew/credits** while asteroids drift down the play area and drop **materials**; entering **manual boost** lets you fly the ship (WASD + SPACE dash) and fight bosses.

This codebase carries scars from two pivots, which is why "legacy" exists:
1. **Theme pivot** — it began as a YouTube/streamer idle clicker (views/subs/cash, comments, autoclickers). Internal variable names and several hidden panels are from that era.
2. **Weapon pivot** — the player's guns used to be **sprites mounted on the ship in edit mode** (driven by `WeaponManager`, auto-firing). That was replaced by a **Diablo-2-style inventory** (`InventoryManager` + `weapon_system`). The old mount auto-fire is retired (still inert in `gun_system.gd`), and the **old weapon shop has now been deleted**. `WeaponManager` survives only to position the cosmetic ship-weapon sprites + save/load.

Entry scene: `scenes/main.tscn` → `scripts/main.gd`. Toggle the layout editor with **F4** (`toggle_edit_mode`); the boss editor with **F5** (`toggle_boss_edit_mode`).

Legend: ✅ Active · 🟡 Partial (some live, some dead) · ⚠️ Legacy / hidden · 🗑️ Orphaned (unreferenced)

---

## 1. What actually runs when you play

`main.gd._ready()` wires everything up. The authoritative list of what is instantiated at runtime:

- **Autoloads** (9, see §2) — always live.
- **Screen visuals** — `scrolling_background.gd` + `overlay.gd` (parallax starfield), added to `StreamScreen`.
- **Asteroid field** — `asteroid_layer.gd` (spawn/drift/collect → materials).
- **Player weapons** — `weapon_system.gd` (inventory-driven firing + FX).
- **Ship control** — `gun_system.gd` (ship float, WASD movement, SPACE dash, ship↔asteroid collision, boss-fight scaling). *Its old mount auto-fire is disabled.*
- **HUD** — `boost_button.gd`, `ship_hp_bar.gd` (HP + shield + energy bars), `boss_hp_bar.gd`, `material_panel.gd`, plus the `QuickPanel` running `stat_panel.gd` (stats + settings overlay).
- **Inventory** — `inventory_ui.gd` overlay.
- **Bosses** (deferred, added to `ObjectsContainer`) — `boss_fight.gd` (Elephant), `chromeleon_fight.gd` (Chromeleon), and `boss_edit_mode.gd` (F5 editor). `boss_panel.gd` has the spawn buttons.

### Active gameplay loops

**Idle economy** ✅ — `GameManager` holds fuel(`views`)/crew(`subs`)/credits(`cash`); `UpgradeManager` ticks passive fuel production from purchased upgrades; `EquipmentManager` applies Power-Core multipliers. Bought with fuel.

**Combat** ✅ — `asteroid_layer.gd` spawns asteroids; clicking or shooting them rolls a drop table into `MaterialManager` (metal/nonmetal/organic/liquid). `weapon_system.gd` reads the equipped weapons from `InventoryManager` each frame and fires the **primary on LEFT-click and the secondary on RIGHT-click, fully independently** (each slot has its own cooldown/charge/beam/zone state). Most weapons aim at the cursor; a few (Lasgun, Orbitals) don't. Damage routes through the `asteroid_main` group and the live boss. See §6 for the full inventory/affix system.

**Ship control** ✅ — only during **manual boost** (`GameManager.manual_boost`). `gun_system.gd._handle_ship_movement` reads WASD (200 px/s) and SPACE (dash: ~126 px lunge, 20 energy, 1 s cooldown). `GameManager` owns `ship_hp` (100), `ship_shield` (from an equipped Shield Generator), `ship_energy` (dash fuel, max 100, +5/s regen), and 0.3 s invincibility frames after a hit.

**Boss fights** ✅ — spawn from `boss_panel.gd`. Both controllers share `GameManager.boss_hp`/`boss_max_hp` and the `boss_killed` signal, and both join the `boss_fight` group; only one fights at a time. The Elephant is HP-driven (defeat at 0 HP → "DISASTER AVOIDED"); the Chromeleon has its own orb-based win (→ "CHROMELEON DEFEATED").

---

## 2. Autoloads (`scripts/autoload/`)

| Autoload | File | Status | Role |
|---|---|---|---|
| AudioManager | `audio_manager.gd` | ✅ | Music/SFX playback + volumes |
| MaterialManager | `material_manager.gd` | ✅ | 4 material currencies (metal/nonmetal/organic/liquid); earned from asteroids, spent on nothing wired yet (was: WeaponManager) |
| DefenseManager | `defense_manager.gd` | 🟡 | Linear defense level 0→8; purchasable + drives a ship visual, but it's a leftover progression with no combat effect wired |
| EquipmentManager | `equipment_manager.gd` | ✅ | Auto-scans `assets/upgrades/equipment/*.png`; Power-Core items multiply idle production |
| UpgradeManager | `upgrade_manager.gd` | ✅ | Fuel-production upgrade catalog + passive tick |
| GameManager | `game_manager.gd` | ✅ | Central state: economy, ship HP/shield/energy/i-frames, boss HP, boost, save/load |
| WeaponManager | `weapon_manager.gd` | 🟡 | Only **positions the cosmetic weapon sprites** on the ship (via `sync_from_canvas`) + save/load. Firing is retired and the old weapon shop/purchase path has been deleted |
| AffixManager | `affix_manager.gd` | ✅ | Diablo-2 affix catalog (43 affixes) + weapon-eligible pool (22) + the tier-band `roll_affix(id, tier)` roller. Data only — no gameplay wiring here (see §6) |
| InventoryManager | `inventory_manager.gd` | ✅ | The player's real weapons: item catalog (`ITEM_DEFS`), 10×6 backpack grid + 10 equip slots, per-instance affix rolls + hidden base-damage roll, weapon generation, sell, save/load (see §6) |

---

## 3. Legacy / disabled / orphaned

| Thing | Status | Where | Why |
|---|---|---|---|
| Mount auto-fire | ⚠️ retained but inert | `gun_system.gd` `MOUNT_AUTOFIRE=false` — `_fire_gun/_fire_turret/_fire_canon/_fire_railgun_bullet/_fire_lightning` early-return | Replaced by inventory weapons. Left in place on purpose (gun_system is fragile / partly LOCKED); the rest of gun_system (movement/dash/collision/sprite positioning) is still live |
| Canvas weapon shop | 🗑️ **deleted** | was `WeaponPanel` in `main.tscn` + `scripts/ui/weapon/weapon_panel.gd` + `WeaponManager.purchase()/get_tier_cost()` | Old material-priced weapon store; removed — inventory is the only weapon source |
| Old idle upgrade UI | ⚠️ hidden | `UpgradeArea` in `main.tscn` (`visible=false`) — rows FriendView/ReactHand/Ad/Algorithm/BotIntel/Content; `scripts/ui/upgrade/upgrade_list.gd`, `upgrade_item.gd` | Streamer-era upgrade panel; upgrades now surface elsewhere |
| Comment / "Distress Signals" panel | ⚠️ hidden | `CommentColumn` set `visible=false` in `main.gd._apply_title_fonts`; `scripts/ui/hud/comment_panel.gd` | Streamer-era chat feed |
| Defense tab / scan automation | ⚠️ vestigial | `DefenseManager`, `defense_panel.gd`, `defense_visual.gd`; `comment_auto_click_rate`/scan fields in GameManager | Progression + ship visual remain, but no scan/defense gameplay drives off them |
| Auto-clicker overlay | 🗑️ orphaned | `scripts/gameplay/auto_clicker_overlay.gd` | Not referenced anywhere; idle-clicker hand cursors |
| Views/Subs bar | 🗑️ orphaned | `scripts/ui/hud/view_sub_bar.gd` | Not referenced anywhere |
| Ionizing Field item | 🟡 | `inventory_manager.gd` `ITEM_DEFS.ionizing_field` | Aura weapon+shield, secondary-only. Granted by the debug "one of each" load grant and works; but it's NOT in `STARTER_ITEMS` (so absent in normal mode) and is excluded from affix rolling (its "shield" tag keeps it out of `_weapon_base_ids`). |
| Per-weapon energy stats | 🟡 partial | `energy` / `activation_energy` in `ITEM_DEFS` stats | Only consumed by weapons flagged `uses_energy:true` — currently the **Lasgun**, **Rift Maker**, and **Orbitals** (each drains `energy`/sec while firing + a 10 activation cost, and cuts out at empty). Other weapons' energy numbers are data-only (global `WEAPONS_USE_ENERGY=false`). |
| `weight` item stat | ⚠️ data-only | `weight` in `ITEM_DEFS` | Present on items but not consumed by gameplay |
| Theme/internal names | ℹ️ intentional | `views`/`subs`/`cash`/`comment_auto_click_rate` | Kept for API stability; map to Fuel/Crew/Credits (see §7) |

---

## 4. Full file map (`scripts/`)

### `scripts/gameplay/`
| File | Status | Role |
|---|---|---|
| `main.gd` | ✅ | Root `Control`; instantiates all runtime systems, save/load, F4/F5 toggles, death + victory screens |
| `asteroid_layer.gd` | ✅ | Asteroid spawn/drift/collect → materials; boss-aware (`boost_changed`/`boss_spawned`/`boss_killed`) |
| `weapon_system.gd` | ✅ | Inventory weapon firing + FX for BOTH slots independently (left=primary, right=secondary). Dispatches on `fire_mode`/`fire_type`; `get_weapon_stat()` applies the equipped item's affixes (§6). Damages asteroids + boss |
| `gun_system.gd` | 🟡 | Ship float/WASD movement/SPACE dash/scale/collision + cosmetic weapon-sprite positioning **(live)**; mount auto-fire **(retained but inert, `MOUNT_AUTOFIRE=false`)** |
| `scrolling_background.gd` | ✅ | Tiled parallax background |
| `overlay.gd` | ✅ | Tiled parallax overlay |
| `boss_fight.gd` | ✅ | Elephant boss — 5 moves (M1–M5), projectile pool, "DISASTER AVOIDED" on defeat |
| `chromeleon_fight.gd` | ✅ | Chromeleon boss — multi-part body + orbs, orb-based win, "CHROMELEON DEFEATED" |
| `auto_clicker_overlay.gd` | 🗑️ | Orphaned idle-clicker cursor overlay |

### `scripts/ui/hud/`
| File | Status | Role |
|---|---|---|
| `stat_panel.gd` | ✅ | Stat readout + settings overlay (resolution/volume/reset) + debug KILL BOSS/RESET HP |
| `material_panel.gd` | ✅ | Material counts HUD (top-right) |
| `boost_button.gd` | ✅ | AUTO-DRIVE / manual-boost toggle |
| `ship_hp_bar.gd` | ✅ | HP + yellow shield overlay + cyan dash-energy bar |
| `boss_hp_bar.gd` | ✅ | Boss HP bar (shown during fights) |
| `boss_panel.gd` | ✅ | Elephant / Chromeleon spawn buttons |
| `audio_monitor.gd` | ✅ | Audio-level monitor used by `stat_panel.gd` |
| `comment_panel.gd` | ⚠️ | "Distress Signals" feed — hidden at runtime |
| `upgrade_shelf.gd` | 🟡 | Visual shelf of purchased upgrade icons (tied to idle upgrades) |
| `view_sub_bar.gd` | 🗑️ | Orphaned views/subs label bar |

### `scripts/ui/inventory/`  (all ✅)
| File | Role |
|---|---|
| `inventory_ui.gd` | Backpack + equip-slots overlay (open with **I**); sell-confirm popup |
| `backpack_grid.gd` | `InvBackpackGrid` — grid cells + drag/drop |
| `item_widget.gd` | `InvItemWidget` — a draggable item; shows the rolled name + the D2 hover tooltip (`_make_custom_tooltip`) |
| `equip_slot.gd` | `InvEquipSlot` — one equip slot with tag rules |

### `scripts/ui/edit_mode/`  (F4 layout editor — ✅ tooling)
| File | Role |
|---|---|
| `edit_mode.gd` | Drag/resize placed sprites; saves `res://default_layout.cfg`; calls `WeaponManager.sync_from_canvas()` |
| `editable_object.gd` | `EditableObjectNode` — every placed sprite (ship, weapons, screen, etc.) |
| `object_list_panel.gd` | Object tree sidebar (z-order/rename/delete) |
| `transform_panel.gd` | X/Y/W/H spinners |
| `gif_loader.gd` | `GifLoader` — pure-GDScript GIF decoder (used by bosses + editors) |

### `scripts/ui/boss_edit/`  (F5 boss editor — ✅ tooling)
| File | Role |
|---|---|
| `boss_edit_mode.gd` | Place boss sprites + fire points; saves `res://boss_layout.cfg`; hides bosses in gameplay (active boss revealed by its controller) |
| `grid_overlay.gd` | Grid + fire-point markers |

### `scripts/ui/defense/`
| File | Status | Role |
|---|---|---|
| `defense_panel.gd` | 🟡 | 8-level defense shop |
| `defense_visual.gd` | 🟡 | On-ship defense visual |

### `scripts/ui/upgrade/`
| File | Status | Role |
|---|---|---|
| `upgrade_list.gd` | ⚠️ | WEAPONRY/DEFENSE tabbed upgrade list (hosted by hidden `UpgradeArea`) |
| `upgrade_item.gd` | ⚠️ | One upgrade row |

### `scripts/ui/equipment/`  (✅ — Power Core shop)
| File | Role |
|---|---|
| `equipment_list.gd` | Lists `EquipmentManager` items (`EquipmentColumn`) |
| `equipment_item.gd` | One equipment row |

### `scripts/ui/user/`  (✅ — UserPanel widgets; **LOCKED** modules, do not edit)
| File | Role |
|---|---|
| `user_panel.gd` | Draggable utility panel container |
| `music_player.gd` | YouTube/mpv music widget |
| `music_server.gd` | mpv IPC client |
| `todo_list.gd` | 4-task to-do |
| `weather_clock.gd` | Weather + clock + session timer |

### `tools/`
| File | Role |
|---|---|
| `mpv-bridge.ps1` | PowerShell async pipe bridge for the music player (**LOCKED**) |

---

## 5. Player weapons (the catalog)

Defined in `inventory_manager.gd` `ITEM_DEFS`; behaviour in `weapon_system.gd`, dispatched purely on a `fire_mode` string (when/how it triggers) + a `fire_type` string (what it spawns) — no per-name hardcoding. **Two slots fire independently: primary = left-click, secondary = right-click.** Base stats below are the catalog defaults; each *dropped copy* also rolls affixes + a hidden ±20% base-damage variance (see §6).

| Item | Slot | fire_mode / fire_type | Behaviour (catalog base) |
|---|---|---|---|
| Gatling Gun | primary | `repeat` / `projectile` | Hold to fire every 0.12 s, dmg 8 |
| Gauss Cannon | primary | `charge` / `projectile` | Hold to charge ≤1.5 s; release one big ball, dmg ∝ charge (≤110) |
| Homing Missile | primary | `repeat` / `homing` | Cinematic launch → arcs behind ship → seeks cursor → explodes, dmg 19 @ 0.53 s |
| Shotgun | primary | `repeat` / `cone` | 5 pellets, dmg 18 each, 34° spread, range 216, 0.7 s |
| Lasgun | primary | `beam` / `hitscan_beam` | Continuous beam **straight forward**, dmg 20/tick @ 0.15 s, range 760. **Uses energy** (10 + 20/s) |
| Arc | primary | `repeat` / `chain` | Lightning chaining up to 4 jumps within 200 px, dmg 30 @ 0.5 s |
| Plasma Drill | primary | `beam` / `tether` | Short tether (range 170) on the nearest target, dmg 70/tick @ 0.2 s |
| Rift Maker | primary | `channel` / `growing_zone` | **Hold** to grow a void at the cursor; dmg 39→390/tick over 2.5 s, radius→90. **Uses energy** (10 + 20/s). Procedural vortex shader |
| Parasite Gun | primary | `repeat` / `dot_stack` | Fires 5 parasites that stick to a target (tracks drifting asteroids) and deal 6 DPS each; 4 s reload |
| Swarm Host | primary | `channel` / `minion` | **Hold** to keep 4 bats out; they chase/auto-attack (5 dmg @ 0.4 s) and **body-block boss projectiles**, respawning 3 s after dying |
| Orbitals | primary | `orbital` / `orbital` | 3 balls orbit the ship (always-on, free), 38 dmg on contact; **hold** to overcharge to 3× spin (more hits). **Uses energy** (10 + 20/s) |
| Shield Generator | secondary | — | Passive 20-pt shield read by `GameManager` (regen after 3 s) |
| Ionizing Field | secondary | `aura` / `aura` | Always-on area damage in a 140 px radius each tick (secondary-only; see §3) |

To add/retune a weapon you usually only edit `ITEM_DEFS`. Energy is opt-in per weapon via `uses_energy` (Lasgun, Rift Maker, Orbitals today).

---

## 6. Inventory, items & affixes (Diablo-2 system)

### Item *type* vs item *instance*
`ITEM_DEFS` (in `inventory_manager.gd`) is the **catalog** — one shared template per weapon/gear type (name, grid size, `tags`, `fire_mode`/`fire_type`, base `stats`). What you actually own are **instances**, tracked per unique id (`uid`) in `_items`:

```
_items[uid] = { def, where, cell, affixes, base_mult }
```
- `def` — which catalog entry · `where` — `"backpack"` or an equip-slot name · `cell` — backpack grid origin.
- `affixes` — this copy's rolled magic mods · `base_mult` — this copy's hidden ±20% base-damage roll.

So **two copies of the same weapon are different items** (different rolls). The catalog is the template; the instance is the unique drop.

### Backpack & equip slots
- Backpack = **10×6 grid**; multi-cell items occupy several cells; drag to rearrange (`backpack_grid.gd`).
- **10 equip slots** (`EQUIP_SLOTS`): primary_weapon, secondary_weapon, thruster, command_bridge, hull, energy_core, radar, drone_1/2, wings. `SLOT_RULES` gates by `tags` (Primary takes any "weapon" but **not** "shield"; Secondary takes weapon or shield → so the shield/aura items are secondary-only).
- `weapon_system.gd` reads the equipped **primary (left-click)** + **secondary (right-click)** every frame and fires them **independently**.
- **Sell:** right-click an item → confirm popup → `sell_item` removes it and pays `GameManager.add_money` (flat **$1** via `get_sell_price`, a TODO hook).

### How items are granted
- **Debug (current):** `RESET_INVENTORY_ON_LOAD = true` → every load wipes the inventory and grants **one of every catalog item**; the **11 true weapons are rolled with affixes + a base roll** (like drops) at `WEAPON_ROLL_TIER` (currently **Low**). Mid-session changes are wiped on reload. (Shield Generator and Ionizing Field carry the "shield" tag, so they're granted plain — not affix-rolled.)
- **Normal (flag off):** `STARTER_ITEMS` granted once into a new save (`_backfill_starters` hands out newly-added starters once); everything persists.

### Affixes (`affix_manager.gd`)
- Catalog of **43 affixes** (from `Item_fixes_completed.xlsx`): each has `prefix`, `after_fix`, `unit`, `min`, `max`. `WEAPON_AFFIX_POOL` = the **22** allowed on weapons (the rest are ship/equipment stats).
- **`roll_affix(id, tier)`** rolls a value inside a **tier band** of Min→Max: **Low** Min→33%, **Mid** 33→66%, **High** 66→Max. Negative affixes (e.g. `energy_consumption_percentage`) roll toward the more-negative/better end at higher tiers.
- A rolled weapon gets **1 prefix + 1 after-fix** affix (two distinct pool ids) **plus** a hidden **±20% base-damage** multiplier (`BASE_DAMAGE_VARIANCE`), stored on the instance.
- **Name** (`item_display_name`): `"[Prefix] [Base] [After-fix]"`, e.g. *"Brutal Gatling Gun of Barrage"*.
- **Tooltip** (`item_widget._make_custom_tooltip`): dark D2 box → rolled name → base stats (real Damage *incl.* the hidden roll + Fire rate) → separator → blue affix lines. Colours/labels are tunable at the top of `item_widget.gd`.

### What affixes actually DO right now ⚠️
All firing code reads stats through **`weapon_system.get_weapon_stat(def, key, …)`**, which applies the equipped instance's `base_mult` + affixes at one spot. **Only some are wired to gameplay:**

| Wired ✅ (changes the weapon) | Rolled + shown, but NO effect yet ⚠️ |
|---|---|
| hidden ±20% base damage (`base_mult`) | crit_chance, crit_damage |
| `damage_flat`, `damage_percentage` → damage | projectile_speed, armor_penetration |
| `fire_rate` → lower cooldown/tick (faster) | poison, burn, slow, freeze |
| `energy_consumption_percentage` → cheaper energy | multishot, pierce, ricochet, splash_radius, knockback |
| | energy_leech, hp_leech, shield_leech, energy_regen_flat/percentage |

The unwired ones each need a mechanic that doesn't exist yet (crit rolls, status effects, projectile-behaviour changes, on-hit/regen hooks) — listed in the TODO above `get_weapon_stat`. They are **not faked**: they appear on the item and in the tooltip, but don't change combat.

### Test / tuning
- **ROLL WEAPON** button (stat panel) drops a fresh rolled weapon at `WEAPON_ROLL_TIER`.
- Tune in `inventory_manager.gd`: `WEAPON_ROLL_TIER` (1/2/3 = Low/Mid/High), `BASE_DAMAGE_VARIANCE`. Tooltip look: the `TT_*` consts in `item_widget.gd`.

### Not done yet
- **Phase 3** (per `minh_scope.md`): bosses drop 3 affixed weapons on defeat — **not implemented**.

---

## 7. Persistence

| File | Written by | Contents |
|---|---|---|
| `user://save.cfg` | GameManager / DefenseManager / WeaponManager / InventoryManager | `[player]` (HP/shield + money), `[defense]`, `[weapons]`, `[inventory]` (items + per-item `affixes` + `base_mult`) |
| `user://materials.cfg` | MaterialManager | material counts |
| `user://settings.cfg` | stat_panel | resolution, volumes, bg/ov scale |
| `user://equipment.cfg` | EquipmentManager | owned Power-Core items |
| `user://user_panel.cfg` / `music_player.cfg` / `session.cfg` | UserPanel widgets | widget state, music, weather/timer |
| `res://default_layout.cfg` | edit_mode (F4) | all placed-sprite positions/sizes/z (incl. ship + weapons) |
| `res://boss_layout.cfg` | boss_edit (F5) | per-boss sprite + fire-point layout |

---

## 8. Theme map (internal → display)

| Internal | Display |
|---|---|
| `views` | Fuel |
| `subs` | Crew |
| `cash` | Credits |
| `click_power` | Thrust |
| `vps` | FPS (Fuel/sec) |
| `comment_auto_click_rate` | (legacy scan rate) |
| `manual_boost` | Manual flight / AUTO-DRIVE off |

These internal names are kept for save-compatibility; all player-facing UI uses the display names.
