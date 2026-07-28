# Core — Architecture, State & Scenes

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on autoloads, main scene, GameManager, persistence, main menu, settings, music player.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

## Changelog — 2026-07-28 (3rd pass) — replaced the Master limiter with smooth overlap ducking (limiter crackled)

- **`audio_manager.gd`**: the `AudioEffectLimiter` added in the "Master bus limiter" pass below caused
  audible crackling once many short SFX (hits/fire/explosions) piled up — a hard, sample-accurate limiter
  doesn't track game audio's fast transients cleanly. Removed entirely; replaced with a manual, smooth
  ducking system: an `AudioEffectAmplify` on the Master bus, whose `volume_db` is adjusted every frame
  (`_tick_duck()`, new `_process()`) from the bus's own real-time peak reading
  (`AudioServer.get_bus_peak_volume_left/right_db`) — the more sound currently overlapping (squid + spider +
  jetfighter fire all at once, etc.), the higher that peak reads, the more this ducks; a single/quiet moment
  stays under `DUCK_PEAK_THRESHOLD_DB` (-14dB) and is left completely untouched. Fast attack (30dB/s — catches
  a sudden pile-up immediately) + slow release (6dB/s — recovers gradually, no audible pumping) is the actual
  fix for the crackle, not just a different curve shape. Deliberately an effect's own gain, NOT
  `AudioServer.set_bus_volume_db(master, ...)` — that property is what `settings_panel.gd`'s volume slider
  already controls; ducking it directly would fight the slider every frame. This stays fully orthogonal: the
  slider sets the base level, ducking only ever pulls the mix down temporarily on top of it.

## Changelog — 2026-07-28 (2nd pass) — every XP source scaled ×10 (whole-number XP, no more decimals)

- **`game_manager.gd`**: `BASE_XP` 100.0→1000.0, `XP_PER_ASTEROID` 0.05→0.5 (+ `xp_for_asteroid()`'s size term
  divisor 20.0→2.0 to scale that half of the formula too), `XP_PER_BOSS` 25.0→250.0. `LEVEL_XP_MULT` (the
  early-level discount dict) is untouched — it's a ratio applied ON TOP of `BASE_XP`, not an absolute
  amount, so it already scales through automatically. Every enemy's `"xp"` field across `ENEMY_DEFS`
  (`arena_wave_director.gd`, `boss_scorpion.gd`'s own minion table, plus the small `FALLBACK`/`BEE_DEF`
  inline defs in `arena_enemy.gd`/`arena_enemy_manager.gd`) scaled ×10 too, rounded half-up to the nearest
  whole number for the few that were already quarter-increments (0.25/0.35/0.45/0.75 → e.g. ghost 0.25×10=
  2.5→**3**, not 2.5) — this was the actual point: "0.05 xp/hit" style decimals are gone project-wide, all
  XP values are now whole numbers. Net effect on pacing: **unchanged** — since both the per-kill XP amounts
  AND the level-up cost curve scaled by the same ×10 factor, the number of kills needed per level is
  identical to before, only the displayed numbers got 10× bigger (like switching from dollars to cents).
  `arena_wave_director_v2.gd`'s `_xp_per_hp` (test-roster XP-proportional-to-HP ratio) needed no separate
  edit — it's computed live from `fly`'s own def at `_ready()`, so it auto-picked up the new ratio (10/20 =
  0.5, was 1/20 = 0.05).
- **Does this "lighten" the math?** No — asked directly, answered honestly: GDScript's `float` arithmetic
  costs exactly the same whether the value is `0.2` or `2.0`; whole vs. fractional doesn't change CPU cost.
  The real (minor) benefit is precision, not speed: values like `0.1`/`0.2`/`0.4` aren't exactly
  representable in IEEE-754 binary floats (classic decimal-fraction rounding error), while whole numbers
  are exact — `add_xp()`'s fractional accumulator (`_xp_frac_acc`) already existed specifically to stop that
  imprecision from ever silently losing XP, so this mostly just makes the numbers easier to read/author
  (matches the request that prompted this: Creep Info's XP Drop column, and the "0.1 step" question).
- **Follow-up (same day)**: `arena_xp_orb_manager.gd`'s tier thresholds (`TIER_GREEN/YELLOW/RED_MAX` — pick
  an orb's on-screen color/size from its xp `value`) were still calibrated for the PRE-×10 scale, so every
  orb was landing in a way-too-high tier (a fly's now-10xp kill exceeded the old YELLOW_MAX of 5.0, showing
  RED). Rescaled ×10 to match (2.5/5.0/25.0 → 25.0/50.0/250.0); the `TIER_*_MULT` constants that convert
  value→pixel-size rescaled ÷10 in the opposite direction to keep the actual on-screen orb SIZE unchanged
  (size = value × mult, value is 10× bigger so mult must be 10× smaller) — the `TIER_*_CAP` pixel-size caps
  are untouched, same as before. This is the exact same "rescale thresholds with value, mult inversely,
  caps alone" pattern the file's own comment already documented from an EARLIER ÷20/×20 xp rescale — this
  one just compounds ×10/÷10 on top of it. Net result: orb appearance is visually identical to before the
  xp rescale, same as the level-curve pacing being unchanged.

## Changelog — 2026-07-28 — Master bus limiter + GameManager run stats

- **Sound got very loud with many simultaneous SFX** (weapon fire, hits, explosions all stacking).
  Root cause: the project has **no custom audio bus layout** (no `default_bus_layout.tres`, no `[audio]`
  section in `project.godot`) — every `AudioStreamPlayer.bus = "SFX"`/`"Music"` across the codebase
  resolves to a bus name that was never actually registered, so in practice **everything plays on
  Master** (the only bus that exists) and just sums freely. Fixed in `audio_manager.gd._ready()`
  (`AudioManager` is the first autoload, so this is in place before anything else can play):
  `_setup_master_limiter()` adds an `AudioEffectLimiter` to the Master bus (`ceiling_db = -1.0`,
  `threshold_db = -6.0`) — transparent for normal single/few-sound moments, clamps the combined peak once
  many sounds overlap instead of letting them add up freely. Did **not** attempt to fix the underlying
  "SFX"/"Music" bus routing itself (a bigger, riskier, out-of-scope restructure) — just capped the actual
  symptom at the one bus that reliably exists.
- **`GameManager` gained 4 new run-scoped fields** (all reset in `reset_run()`), added for the arena's
  RUN OVER stats screen (see [`weapon.md`](weapon.md) / [`enemy.md`](enemy.md) for the producer side):
  `run_time: float` (actual play seconds this run, ticks in `_process()` so it's naturally frozen while
  the tree is paused — the DPS divisor for the stats screen), `last_hit_name`/`last_hit_icon: String`
  (whoever most recently damaged the player), and `record_last_hit(name, icon_path)` to set the latter
  two.

## Architecture

### Autoloads (registration order in project.godot)

Registered in this exact order (matters: `MaterialManager` must exist before `WeaponManager`, which spends materials; see commit history):

| Name | File | Role |
|------|------|------|
| `AudioManager` | `scripts/autoload/audio_manager.gd` | Music/SFX, volume control |
| `MaterialManager` | `scripts/autoload/material_manager.gd` | 4 raw-material currencies: `metal`, `nonmetal`, `organic`, `liquid`. `add()`/`spend()`, emits `materials_changed` / `material_added`. Saves to `user://materials.cfg` |
| `DefenseManager` | `scripts/autoload/defense_manager.gd` | Single `current_level` (0–8) progression, `try_purchase(level)` (must be `current_level+1`). Saves to `user://save.cfg` section `[defense]` |
| `EquipmentManager` | `scripts/autoload/equipment_manager.gd` | Auto-scans `assets/upgrades/equipment/*.png`, cost = 20 × 1.6^index |
| `UpgradeManager` | `scripts/autoload/upgrade_manager.gd` | UPGRADES catalog, owned counts, factory accumulator, save/load |
| `GameManager` | `scripts/autoload/game_manager.gd` | Core game state (Ship HP, Shield, Boost, Boss fight) |
| `WeaponManager` | `scripts/autoload/weapon_manager.gd` | Canvas-driven tiered weapon catalog, priced in materials. Built at runtime by `sync_from_canvas()` (not a const list). Saves to `user://save.cfg` section `[weapons]`. **Legacy** — the live weapon path is now `InventoryManager` + `weapon_system.gd` |
| `AffixManager` | `scripts/autoload/affix_manager.gd` | Affix catalog (`AFFIX_DEFS`, ~40 affixes) + tier-band roller `roll_affix(id, tier)`. Separate `WEAPON_AFFIX_POOL` / `HULL_AFFIX_POOL`. No persistence; loaded at startup. See **Inventory, Items & Affixes** |
| `InventoryManager` | `scripts/autoload/inventory_manager.gd` | Diablo-2 grid inventory + 10 equip slots + `ITEM_DEFS` item catalog. `weapon_system.gd` reads equipped items from it each frame. Saves to `user://save.cfg` section `[inventory]` |

**Load vs. registration order:** `main.gd._ready()` calls `UpgradeManager.load_game()` then `GameManager.load_game()`. `MaterialManager` / `WeaponManager` / `DefenseManager` load lazily from their own panels' `_ready()` (and `WeaponManager.load_game()` runs inside `sync_from_canvas()`).

### Main Scene (`scenes/main.tscn`)

Root `Control` with these direct children:

- `SpaceScreen` — `Panel` at (270, 8), size 700×764: chứa scrolling background + overlay + border
- `EditMode` — `CanvasLayer` layer=10 (`scripts/ui/edit_mode/edit_mode.gd`): drag/resize, persisted to `res://default_layout.cfg`
- `UserPanel` — `CanvasLayer` layer=5 (`scripts/ui/user_panel/user_panel.gd`): PANEL_SCALE=0.5, contains TodoList, MusicPlayer, WeatherClock
- `ViewColumn` — `Panel` with `scripts/ui/upgrade/upgrade_list.gd`: WEAPONRY tab only
- `CommentColumn` — `Panel` with `scripts/ui/upgrade/upgrade_list.gd`: DEFENSE tab — **hidden at runtime**
- `StatPanel` — `Panel` 192×100 with `scripts/ui/hud/stat_panel.gd`: VBox gồm hàng buttons (MUTE/SETTING/QUIT) + slider BG + slider OV
- `EquipmentColumn` — ship module shop UI (header: "POWER CORE")

**Nodes created at runtime in `main.gd._ready()` (not in the .tscn):** defense panel (`defense_panel.gd`, left at 10,408) + `defense_visual.gd`; scrolling background + overlay; two `asteroid_layer.gd` instances (blurred under-layer + interactive `asteroid_main`); `gun_system.gd` (added to EditMode's `ObjectsContainer`, z_index 7); material HUD panel (`material_panel.gd`, top-right at 1240,8). `_notification(WM_CLOSE_REQUEST)` saves all six managers, then quits.

### CanvasLayer conventions

| Layer | Used for |
|-------|----------|
| 5 | UserPanel |
| 10 | EditMode overlay |
| 11 | `auto_clicker_overlay.gd` (autoclicker hand cursors) |
| 48 | `coord_grid.gd` (coordinate grid — child of enemy_panel) |
| 50 | HP bars / AUTO-DRIVE / AUTO-FIRE buttons |
| 51 | HUD display elements |
| 60 | `inventory_ui.gd` (inventory/equipment screen) |
| 95 | `arena_enemy_manager.gd` hit flash (screen-blend red overlay) |
| 100 | Settings panel + `hud_edit_overlay.gd` (HUD edit F6) — always on top |

`auto_clicker_overlay.gd` (`scripts/gameplay/auto_clicker_overlay.gd`) draws one hand cursor per owned autoclicker upgrade, placed flush against the ship sprite's silhouette via alpha-edge detection (`_alpha_edge`); rebuilds on `UpgradeManager.upgrade_purchased` / `upgrades_reset`. Self-contained, no signals out.

## Main Menu (`scenes/main_menu.tscn`)

The game's **entry scene** (`run/main_scene`) and the return target when the player presses **Quit inside the Arena** (`arena_hud_buttons._on_quit` → `change_scene_to_file("res://scenes/main_menu.tscn")`). Built entirely in code by `scripts/ui/mainmenu/main_menu.gd`.

**Flow:** launch → Main Menu. **Resume** → `arena.tscn`; Arena **Quit** button → Main Menu; Arena run-over still → `hub.tscn` (Dock).

### Layers ARE EditableObjectNodes (edit in place with F4)

The menu visuals (background, space, Logo) and the four buttons (resume/setting/codex/quit) are `EditableObjectNode`s placed by `main_menu_edit_mode.gd` into a shared ObjectsContainer (CanvasLayer 9). They are the **live menu** in gameplay AND **editable with F4** — the editor only drops a dim overlay over them; the objects stay in place so you resize/move them live. Layout persists to `res://mainmenu_layout.cfg`, plume styles to `res://mainmenu_plume_styles.cfg`. Assets scanned from `assets/hud/mainmenu/`.

**`main_menu_edit_mode.gd`** (adapted from `creep_edit_mode.gd`): OBJECTS table (scanned layers), TRANSFORM **X/Y** (position) + **W/H** (aspect-locked to source ratio) + **Z**, scroll-wheel zoom (no slider), grid, undo, **Thrust Points + per-TP plume editor** (plumes also render live on the menu). Per-layer default geometry in `DEFAULT_GEOM` (kept in sync with `main_menu.gd`). Z order: background 0, space 1, bullets 2, enemies/missiles 3, Logo 5, buttons 10.

### Buttons — manual hit-test (NOT Control picking)

Button hover/click is driven by `main_menu._input()` via direct rect hit-test (`_edit.live_button_at(pos)` / `_edit.set_button_hover(base, on)`). The full-rect IGNORE container + Node2D enemy backdrop made normal Control input unreliable, so in gameplay **all layer EOs are `MOUSE_FILTER_IGNORE`** and main_menu owns input. Hover → brighten + grow 3% + `uiclick.wav`. Clicks: Resume → `start.mp3` + arena; **Setting → opens the Settings panel** (below); Codex → `uialert.wav` + toast; Quit → `gameover.wav` (awaited) → save all managers → `quit()`. UI sounds use `AudioManager.play_sfx` (autoload — survives the Resume scene change). Toast Label is `MOUSE_FILTER_IGNORE`. Menu input + F4 are gated off while the Settings panel is open.

### Enemy backdrop (`menu_enemy_spawner.gd`)

Decorative flying enemies reusing the REAL arena AI (`arena_enemy.gd` + `arena_enemy_manager.gd`) so attackers fire normally. Added into the same ObjectsContainer (z 2–3, under the UI), `PROCESS_MODE_PAUSABLE` so they freeze under the F4 editor.
- **No bosses** (`behavior == "boss_stub"`) and no test `dummy`. **≤ 2 of each type, ≤ 10 total.** Enter from the top, descend toward an off-screen dummy `"player"` target, culled at the bottom.
- **Spider rationed:** ≤ 1 on screen, 5 s life, then 5 s cooldown.
- Drawn at **50 %** (node `scale`); brightness/contrast grade via per-CanvasItem shader (`_grade_mat` mix / `_grade_add_mat` additive for missiles) — menu-only.
- **Never corrupts the save:** `GameManager.activate_shield(2.0)` re-armed each frame zeroes all damage (arena `reset_run()` clears it on entry); `xp = 0` so no orbs.
- **Distant-echo audio:** a runtime bus `"MenuEnemySFX"` (low-pass 1500 Hz + reverb + **−17 dB**); enemies routed there via `arena_enemy.sfx_bus`.

### `arena_enemy.gd` attack SFX (applies to arena AND menu)

`var sfx_bus := "SFX"` + `_play_sfx()` (one-shot). Spider (`jump_diag`) leap → `dash.wav`; octopus (`jump`) leap → `chargeby.wav`; beamer beam start → `laserbeam.wav` (once, no loop); shooter/sentinel fire → `zap1.wav`. `_play_boom` also routes through `sfx_bus`.

## Settings panel (`scripts/ui/settings/settings_panel.gd`)

Shared modal opened from the **Setting** button in BOTH the Arena (`arena_hud_buttons._on_setting`) and the Main Menu (`main_menu._on_menu_button("setting")`). CanvasLayer 100, `PROCESS_MODE_ALWAYS`; `open()` pauses the tree (snapshots the prior pause state and restores it on close).

- **Volume** slider (0–100%) → the **`"Master"` audio bus** (`AudioServer.set_bus_volume_db` / `set_bus_mute`) = the WHOLE game's audio (music + all SFX) in every scene incl. the Main Menu. Live preview.
- **Graphic** Windowed / Fullscreen → `DisplayServer.window_set_mode`, applied live; active button highlighted.
- **Save** → persist to `user://settings.cfg` (`[audio] sfx_volume`, `[display] fullscreen`) + close. **Reset** → defaults (Volume 100%, Windowed) live (only persisted if you then Save). **Cancel** → revert to the on-open snapshot + close (no save). Buttons are image `TextureButton`s from `assets/hud/mainmenu/{save,reset,cancel}.png`.
- **Startup:** `SettingsPanel.apply_saved()` (static) reads the cfg and applies SFX volume + window mode — called from `main_menu._ready` and `arena_hud_buttons._ready` (AudioManager is locked, so it can't load settings itself).

## GameManager

### Key fields

```gdscript
var ship_hp: int
var ship_max_hp: int
var shield: float
var shield_max: float
var boss_intro_active: bool   # true during boss fly-in + wander; blocks boss _process attacks
```

### Signals

`ship_hp_changed(int)`, `shield_changed(float)`, `boss_state_changed(bool)`

`player_hit` — emitted in `ship_take_damage()` **after** armor + shield checks, only when actual HP damage goes through (d > 0). Use this to trigger visual/audio hit feedback. Connected by `arena_enemy_manager.gd` → `_play_hit()` (SFX + screen flash).

**Boss fight signal sequence:**
```
boss_incoming  → warning overlay shows, bg/overlay swapped, normal music fades out
boss_spawned   → boss HP set, boss music starts
boss_killed    → boss music fades, normal music restarts
boss_defeated  → XP awarded (real end, not phase transition)
```

---

## HUD — stat_panel
### `scripts/ui/hud/stat_panel.gd`

- Contains control buttons (MUTE, SETTING, QUIT) and cheat buttons (RESET HP, KILL BOSS).
- Settings overlay: CanvasLayer(layer=100, PROCESS_MODE_ALWAYS) added to `get_tree().root`
  - ColorRect (0,0,0,0.6) with MOUSE_FILTER_STOP blocks all input to scene below
  - Panel 330×660 with sections: Resolution, Volume, Weapon SFX, Materials (editable SpinBoxes), and Resets (RESET PURCHASES, RESET GAME).
- `_open_settings()`: show overlay + sync SpinBoxes with current materials from `MaterialManager`.
- `_close_settings()`: hide overlay.
- Escape key closes settings via `_input()`.

## Persistence Files (`user://`)

| File | Contents |
|------|----------|
| `user://save.cfg` | **shared central save** — written by GameManager (ship HP/shield), UpgradeManager (owned counts), EquipmentManager (modules), WeaponManager `[weapons]`, DefenseManager `[defense]`, InventoryManager `[inventory]` |
| `user://materials.cfg` | material counts (metal, nonmetal, organic, liquid) — MaterialManager |
| `user://settings.cfg` | resolution (w, h), music_vol, sfx_vol, bg_scale, ov_scale — stat_panel |
| `user://music_player.cfg` | MusicPlayer widget state |
| `user://todo.cfg` | TodoList widget state |
| `user://user_panel.cfg` | UserPanel widget states |
| `user://session.cfg` | Chatbot / weather-clock conversation history |
| `user://hud_layout.cfg` | HUD widget positions/sizes — boost_button, auto_fire, enemy_panel, stat_panel, inventory_btn — written by F6 HUD Edit Mode |
| `res://default_layout.cfg` | positions/sizes của tất cả edit mode objects (tất cả groups kể cả "screen") |

> Verified by grep over `scripts/`. The previously-listed `game_save.cfg`, `upgrades_save.cfg`, `equipment.cfg`, `audio_config.cfg` **do not exist** — GameManager/UpgradeManager/EquipmentManager all write to the shared `user://save.cfg`.


## Assets

| Folder | Contents |
|--------|----------|
| `assets/screen/` | `background.png` (2048×2048) + `overlay.png` (2048×2048) — nguồn cho scrolling system |
| `assets/upgrades/active/` | 48×48 PNG icons, one per upgrade id |
| `assets/upgrades/equipment/` | Ship module icons, auto-scanned by EquipmentManager (sorted order = cost order) |
| `assets/fonts/Gameplay.ttf` | Pixel/retro font for main UI |
| `assets/audio/music/` | OGG Vorbis music files streamed by AudioManager |
| `assets/asteroid/` | Asteroid PNGs; leading non-digit chars of filename = material type (`dirt`/`ice`/`jewel`/`metal`/`rare`) |
| `assets/sprites/weapons/` | Bullet/shell PNGs + `Gun.gif` / `Gun-Impact50.gif` animations for `gun_system.gd` |
| `assets/weaponry/` | Weapon mount sprites (edit group `"weaponry"`); filename + `" Mk2"`/`" Mk3"` suffix drives `WeaponManager` tiers |
| `assets/defense/` | `lv1.png`..`lv8.png` defense level icons |
| `assets/stat/` | Material icons (`metal.png`, `non-metal.png`, `organic.png`, `Liquid.png`) for HUD/shop |
| `assets/bosses/*/` | Boss sprites — see **PNG Sprite Sheet Animation** section below |


## Music Player (`scripts/ui/user/music_player.gd`)

### Default Playlist

```gdscript
const DEFAULT_PLAYLIST_URL := "https://www.youtube.com/watch?v=42Yw2Llnwzw&list=PLJ23c2czIAHmoVNRGL1vCmGD1mnAIZJkh"
```

- First launch (no save file): auto-loads and plays `DEFAULT_PLAYLIST_URL`.
- After user pastes + plays any URL: `_save_session()` overwrites `user://music_player.cfg` with that URL. Next launch resumes that URL instead.
- Fallback only applies when `last_url` is missing from the cfg.

### Auto-Shuffle on Startup

`_auto_play_saved(url)` sets `_auto_shuffle_next = true` when the URL is a playlist. In `_on_playlist_loaded()`:
1. `_shuffle_btn` visually toggled on
2. `{"cmd": "shuffle_on"}` sent to server (mpv shuffles internal queue)
3. `skip_to(randi() % ids.size())` starts from a random track

Only applies to auto-loaded playlists at startup — manual URL submissions are not auto-shuffled.

### Playlist Hover Highlight (`_MarqueeLabel`)

`set_hovered(true/false)` changes `font_color`:
- Hovered → `Color.WHITE`
- Unhovered → `_base_color` (set via `set_style()`)

Button's `hover` stylebox already provides a blue background highlight. Combined effect: blue bg + white text.


