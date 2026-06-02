# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4 GDScript — "The Traveler", a spaceship idle/clicker game. You captain a ship traveling through deep space — clicking the engine boosts fuel production, upgrades automate fuel harvesting and distress signal scanning, and credits accumulate from cosmic cargo events. Entry scene: `scenes/main.tscn`. Toggle edit mode with the `toggle_edit_mode` input action (mapped in `project.godot`).

On top of the idle economy there is now a **real-time combat / crafting layer**: asteroids drift down the StreamScreen, clicking or shooting them yields four raw **materials** (metal / nonmetal / organic / liquid via `MaterialManager`), and those materials buy tiered **weapons** (`WeaponManager`) and **defense** levels (`DefenseManager`). Weapons mounted on the canvas auto-fire at asteroids (`gun_system.gd`). This layer runs in parallel with the fuel/crew/credits idle loop and uses a separate currency — see **Combat, Asteroids & Materials** below.

## Theme Mapping (internal → display)

| Internal variable | Display label |
|-------------------|---------------|
| `views` | Fuel |
| `subs` | Crew |
| `cash` | Credits |
| `click_power` | Thrust |
| `vps` | FPS (Fuel Per Second) |
| `comment_auto_click_rate` | Defense scan rate |
| Upgrade tab `"weaponry"` | WEAPONRY panel |
| Upgrade tab `"defense"` | DEFENSE panel |
| Comment panel | Distress Signals / Space Radio |

## Commands

- **Run:** `godot --path .`
- **Parse check (no window):** `godot --headless --check-only --path . --quit` — exit 0 = parse clean
- **No test suite.** Verification is manual (F5 in editor). Say so explicitly rather than asserting success from a parse check alone.
- **Shell:** Windows / PowerShell. Use PowerShell syntax (`$null`, `$env:VAR`, backtick for line continuation). Bash tool is available for POSIX scripts.

---

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
| `GameManager` | `scripts/autoload/game_manager.gd` | Economy: fuel(views), crew(subs), credits(cash), click_power, vps, auto_click_rate, scan_rate(comment_auto_click_rate) |
| `WeaponManager` | `scripts/autoload/weapon_manager.gd` | Canvas-driven tiered weapon catalog, priced in materials. Built at runtime by `sync_from_canvas()` (not a const list). Saves to `user://save.cfg` section `[weapons]` |

**Load vs. registration order:** `main.gd._ready()` calls `GameManager.load_game()` **then** `UpgradeManager.load_game()` — the *opposite* of the "Risky Areas" note below. Verify which is correct before relying on it. `MaterialManager` / `WeaponManager` / `DefenseManager` load lazily from their own panels' `_ready()` (and `WeaponManager.load_game()` runs inside `sync_from_canvas()`).

### Main Scene (`scenes/main.tscn`)

Root `Control` with these direct children:

- `StreamScreen` — `Panel` at (270, 8), size 700×764: chứa scrolling background + overlay + border
- `EditMode` — `CanvasLayer` layer=10 (`scripts/ui/edit_mode/edit_mode.gd`): drag/resize, persisted to `res://default_layout.cfg`
- `UserPanel` — `CanvasLayer` layer=5 (`scripts/ui/user_panel/user_panel.gd`): PANEL_SCALE=0.5, contains TodoList, MusicPlayer, WeatherClock
- `ViewColumn` — `Panel` with `scripts/ui/upgrade/upgrade_list.gd`: WEAPONRY tab only
- `CommentColumn` — `Panel` with `scripts/ui/upgrade/upgrade_list.gd`: DEFENSE tab — **hidden at runtime** (`main.gd._apply_title_fonts()` sets `$CommentColumn.visible = false`)
- `StatPanel` — `Panel` 192×100 with `scripts/ui/hud/stat_panel.gd`: VBox gồm hàng buttons (MUTE/SETTING/QUIT) + slider BG + slider OV
- `EquipmentColumn` — ship module shop UI (header: "POWER CORE")

**Nodes created at runtime in `main.gd._ready()` (not in the .tscn):** defense panel (`defense_panel.gd`, left at 10,408) + `defense_visual.gd`; scrolling background + overlay; two `asteroid_layer.gd` instances (blurred under-layer + interactive `asteroid_main`); `gun_system.gd` (added to EditMode's `ObjectsContainer`, z_index 7); material HUD panel (`material_panel.gd`, top-right at 1240,8). `_notification(WM_CLOSE_REQUEST)` saves all six managers, then quits.

### CanvasLayer conventions

| Layer | Used for |
|-------|----------|
| 5 | UserPanel |
| 10 | EditMode overlay |
| 100 | Settings panel (always on top, even above screen group) |

---

## Scrolling Background System

### Files

| File | Role |
|------|------|
| `scripts/gameplay/scrolling_background.gd` | Tiles `assets/screen/background.png`, speed=40, z_index=0 |
| `scripts/gameplay/overlay.gd` | Tiles `assets/screen/overlay.png`, speed=80, z_index=1 |

Cả hai được tạo trong `main.gd._add_scrolling_background/overlay()` và thêm vào `StreamScreen` (group `"scrolling_bg"` / `"scrolling_overlay"`).

### Cơ chế tiling

- Chỉ 1 column dọc, `n_rows = ceili(screen_h / tile_h) + 1`
- `_tile_x` = x position của cột trong StreamScreen (mặc định căn giữa)
- `_offset` tăng mỗi frame → khi `>= tile_h` thì wrap về 0 (seamless scroll)

### Image scaling — QUAN TRỌNG

Không dùng `TextureRect.stretch_mode` để scale. Thay vào đó:
```gdscript
var img := _source_img.duplicate()
img.resize(int(_tile_w), int(_tile_h), Image.INTERPOLATE_BILINEAR)
_tex = ImageTexture.create_from_image(img)
```
`_source_img` là `Image` load từ file gốc (2048×2048). Resize CPU-side → texture đúng kích cỡ → `TextureRect.STRETCH_KEEP` chỉ hiển thị, không scale thêm.

### apply_layout_rect

```gdscript
bg.apply_layout_rect(rel_pos: Vector2, sz: Vector2)
```
`rel_pos` = vị trí tương đối trong StreamScreen (= viewport_pos − (270, 8)). `sz` = kích thước tile. Được gọi deferred từ `main.gd._apply_screen_layouts()` sau khi đọc `res://default_layout.cfg`.

### Sliders (StatPanel)

- **BG slider** — kết nối group `"scrolling_bg"`, gọi `set_tile_scale(v)` → `_rebuild()` → resize image mới
- **OV slider** — kết nối group `"scrolling_overlay"`, cùng cơ chế
- Cả hai được lưu vào `user://settings.cfg` key `display/bg_scale` và `display/ov_scale`
- `apply_layout_rect` ghi đè slider; `_rebuild()` từ slider reset `_tile_x` về centered

### Edit Mode — Screen Group

- Group `"screen"` là entry đầu tiên trong `GROUPS` (render sau cùng trong ObjectsContainer = background)
- Assets: `assets/screen/` — chỉ load `background.png` và `overlay.png` (bỏ qua Spaceship.png)
- Placement mặc định: `SCREEN_ORIGIN = (270, 8)`, `SCREEN_TILE_SZ = 700`
- **Invisible trong gameplay mode** — scrolling scripts xử lý visual, edit objects chỉ dùng để căn chỉnh
- Layout lưu vào `res://default_layout.cfg` (không phải `user://`)

---

## Combat, Asteroids & Materials

This is the big-picture loop the original idle docs don't cover. It spans `asteroid_layer.gd`, `gun_system.gd`, `weapon_manager.gd`, `material_manager.gd`, and the weapon/material/defense panels.

### Material economy (`MaterialManager`)

Four integer currencies — `metal`, `nonmetal`, `organic`, `liquid` — separate from the fuel/crew/credits idle economy. `add(type, n)` / `spend(type, n)` (clamped at 0). The `material_panel.gd` HUD subscribes to `materials_changed`. Materials are earned **only** from asteroids; they are spent **only** on weapons (`WeaponManager`).

### Asteroids (`scripts/gameplay/asteroid_layer.gd`)

- Two instances added to `StreamScreen`: a blurred, dimmed **under-layer** (`is_under=true`, z_index 0, custom 3×3 blur `ShaderMaterial`) and the interactive **main layer** (z_index 1, joins group `"asteroid_main"`).
- Asteroids spawn from `assets/asteroid/*.png`, drift down within a ±15° cone, rotate, and respawn on exit. Type is parsed from the **leading non-digit chars** of the filename (`dirt`, `ice`, `jewel`, `metal`, `rare`).
- **Collection** = click the asteroid OR a bullet hits it → `_collect_loot(type)` rolls a per-type random drop table into `MaterialManager.add(...)`. Hitbox min size `MIN_HITBOX = 36`.
- Query API used by the gun: `get_asteroid_centers()`, `get_asteroid_sizes()`, `collect_near(pos, radius)`. **Centers are in StreamScreen-local space** — the gun adds `SS_OFFSET = (270, 8)` to convert to ObjectsContainer/viewport space.

### Gun system (`scripts/gameplay/gun_system.gd`)

- A full-rect `Control` (added to `ObjectsContainer`, z_index 7) that fires every `FIRE_INTERVAL = 0.5s` from each **active `"gun"` weapon object** (`WeaponManager.get_active_objects("gun")`).
- Targets the nearest asteroid that is ≥100px above the gun muzzle; spawns a bullet (`atan2(dir.x, -dir.y)` rotation), an ejecting shell, an impact GIF on hit, and plays the gun-fire GIF (hides the static sprite during the animation). GIFs loaded via `GifLoader` (`Gun.gif`, `Gun-Impact50.gif`) from `assets/sprites/weapons/`.
- All projectiles/animations are pooled in plain arrays and ticked manually in `_process` (same manual-pool pattern as the asteroids and scrolling bg).

### Weapons (`scripts/autoload/weapon_manager.gd`) — canvas-driven catalog

The single most important non-obvious pattern: **weapons are discovered from edit-mode-placed sprites, not declared as a static list.**

- `WEAPON_CATALOG` (const) holds only metadata per id: `desc`, `base_cost` (per material), tier `mult` `[1.0, 2.5, 4.5]`, optional `center: true` (single mid-ship mount) and `requires: "wing"` (gate). `get_tier_cost(id, tier)` = `ceil(base_cost * mult[tier])`.
- `sync_from_canvas(placed)` is called from **`edit_mode.gd` after the layout loads** (`WeaponManager.sync_from_canvas(_placed["weaponry"])`). It scans the `"weaponry"` edit group:
  - finds the `spaceship` sprite to get the ship's horizontal center;
  - parses each filename via `_parse_filename()` for **tier** (`" Mk2"`/`" MkII"` → tier 1, `" Mk3"`/`" MkIII"` → tier 2) and a key;
  - assigns each sprite a **side**: `"C"` for `center` weapons, else `"L"`/`"R"` by whether its center is left/right of the ship;
  - fuzzy-groups keys sharing the first 7 chars (`_find_or_add_group`) plus `KEY_ALIASES` (e.g. `homing_missle`→`homing_missile`) to tolerate filename typos.
- `owned[id] = {L, R}` (or `{C}`); `-1` = not purchased. `_refresh_visibility()` shows **only the sprite for the currently-owned tier** per side (so buying Mk2 hides the Mk1 sprite, reveals the Mk2 one). `purchase()` checks `is_tier_available` (symmetric tiers per side), the `requires` gate, and material cost via `MaterialManager`.
- `weapon_panel.gd` (`assets/weaponry/`) renders the shop in fixed `WEAPON_ORDER`.

### Defense (`scripts/autoload/defense_manager.gd` + `defense_panel.gd`)

Simple linear track: `current_level` 0→8, each level purchasable only as `current_level+1`. `defense_panel.gd` lists 8 named items (`assets/defense/lv1..lv8.png`); `defense_visual.gd` renders the on-ship visual. (Distinct from the old "DEFENSE" upgrade tab, which is hidden.)

---

## GameManager

### Key fields

```gdscript
var cash: float                       # credits earned from cosmic cargo events
var click_power: float = 1.0          # fuel per engine click (thrust)
var vps: float = 0.0                  # fuel/sec from Fuel System upgrades
var auto_click_rate: float = 0.0      # autopilot engine boosts/sec (each × click_power)
var comment_auto_click_rate: float = 0.0  # scan automation rate (signals/sec)
var parasocial: float = 1.0           # crew morale multiplier (future)
var stat_template: String             # editable display template

# Read-only computed getters
var views: int        # fuel (int(_subs + _passive_views))
var subs: int         # crew (int(_subs))
var stable_views: int
var displayed_views: int
```

### Signals

`views_changed(int)`, `subs_changed(int)`, `cash_changed(float)`, `stable_views_changed(int)`, `stat_template_changed(String)`, `game_loaded`

`game_loaded` is emitted from `main.gd` after both `UpgradeManager.load_game()` and `GameManager.load_game()` complete — connect to it for late-initialising nodes that need loaded data.

### Formatting

```gdscript
format_views(n: int) -> String   # plain integer up to 999,999; then "1.28 Million" / "Billion" etc.
format_count(n: int) -> String   # plain below 1000; then "1 thousand" / "1 million" etc.
render_stat_template() -> String # replaces all {tokens} in stat_template
```

**FPS display rule:** always use `format_views()` for FPS — both in StatPanel template and in the screen overlay label in `editable_object.gd`.

### Stat template tokens

`{views}` (fuel), `{subs}` (crew), `{cash}` (credits), `{click_power}` (thrust), `{parasocial}` (morale), `{goal}`, `{run}`, `{time}`, `{vps}` (fps)

Default template: `"Fuel: {views}\nCrew: {subs}\nCredits: {cash}\nThrust: x{click_power}\nFPS: {vps}"`

---

## UpgradeManager

### UPGRADES const structure

```gdscript
const UPGRADES = {
    "id": {
        "name": "Display Name",
        "icon": "filename.png",           # in assets/upgrades/active/
        "cost": 100.0,                    # fuel cost (views)
        "tab": "fuel",                    # "fuel" or "scan"
        # one or more effect fields:
        "vps": 1.0,                       # adds to GameManager.vps (fuel/sec)
        "auto_click_rate": 1.0,           # adds to GameManager.auto_click_rate (autopilot boosts)
        "comment_click_rate": 1.0,        # adds to GameManager.comment_auto_click_rate (scan rate)
        "desc": "Flavor text",
    },
}
```

### Weaponry tab upgrades
`autopilot_booster` (autopilot, +1/s), `solar_panel` ($100, +2 fps), `mining_drone` ($1.5k, +35 fps), `asteroid_harvester` ($25k, +650 fps), `dark_matter_extractor` ($400k, +12k fps), `nebula_harvester` ($8M, +275k fps), `stellar_forge` ($200M, +8M fps), `quantum_synthesizer` ($5B, +230M fps), `galactic_fuel_web` ($150B, +8.5B fps)

### Defense tab upgrades
`comm_relay` ($500, +1/s), `signal_filter` ($8k, +20/s), `scanner_array` ($150k, +450/s), `sensor_grid` ($3M, +10k/s), `scan_station` ($75M, +300k/s), `deep_space_array` ($2.5B, +12M/s), `galactic_sensor_web` ($100B, +600M/s)

### Upgrade purchase currency
Upgrades bought with **fuel** (`GameManager.stable_views`).

### Upgrade purchase currency
Upgrades are bought with **fuel** (`GameManager.stable_views`). Credits (cash) accumulate passively from cargo events and are not spent on upgrades.

---

## UI Scripts

### `scripts/ui/hud/stat_panel.gd`

- Displays `GameManager.render_stat_template()` in TemplateLabel
- `_build_action_bar()`: VBox gồm 3 hàng — HBox (MUTE/SETTING/QUIT), BG slider, OV slider
- BG slider (0.1–10): scale tile background → group `"scrolling_bg"` → `set_tile_scale()`
- OV slider (0.1–10): scale tile overlay → group `"scrolling_overlay"` → `set_tile_scale()`
- Settings overlay: CanvasLayer(layer=100, PROCESS_MODE_ALWAYS) added to `get_tree().root`
  - ColorRect (0,0,0,0.6) with MOUSE_FILTER_STOP blocks all input to scene below
  - Panel 310×430 với: Resolution, Volume, Behavior, Reset sections
- `_open_settings()`: show overlay + `get_tree().paused = true`
- `_close_settings()`: hide overlay + `get_tree().paused = false`
- Escape key closes settings via `_input()`
- StatPanel has `process_mode = PROCESS_MODE_ALWAYS` so it updates while paused
- Saves to `user://settings.cfg` on every change (gồm cả `bg_scale`, `ov_scale`)

### `scripts/ui/upgrade/upgrade_list.gd`

- Tab bar (WEAPONRY / DEFENSE) built at top; ScrollContainer offset_top=50 to clear it
- `_current_tab: String` filters by `UPGRADES[id].get("tab", "weaponry")`
- `_switch_tab(tab)` rebuilds item list and updates button highlight colors

### `scripts/ui/edit_mode/editable_object.gd`

- `EditableObjectNode` (`class_name`) — every in-canvas placed sprite
- `group_id: String` — one of `"screen" | "weaponry" | "defense" | "power_core" | "user"`
- `_gameplay_mode: bool` — edit handles vs gameplay click routing
- FPS label uses `GameManager.format_views(total_vps)` (NOT format_count)
- `group_id == "weaponry" && basename == "view"` → `GameManager.on_view_clicked()` (engine boost click)
- `group_id == "screen"` → invisible trong gameplay (`visible = false`); scrolling scripts xử lý visual

---

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

EquipmentManager cost formula: `20 * pow(1.6, sorted_index)`

---

## Persistence Files (`user://`)

| File | Contents |
|------|----------|
| `user://game_save.cfg` | passive_views (fuel), subs (crew), cash (credits) |
| `user://upgrades_save.cfg` | owned counts per upgrade id |
| `user://settings.cfg` | resolution (w, h), music_vol, sfx_vol, bg_scale, ov_scale |
| `user://equipment.cfg` | owned ship module items |
| `user://user_panel.cfg` | UserPanel widget states |
| `user://session.cfg` | Chatbot conversation history |
| `user://audio_config.cfg` | AudioManager internal state |
| `user://materials.cfg` | material counts (metal, nonmetal, organic, liquid) |
| `user://save.cfg` | shared file: `[weapons]` owned tiers per id/side + `[defense]` level |
| `res://default_layout.cfg` | positions/sizes của tất cả edit mode objects (tất cả groups kể cả "screen") |

---

## Key Patterns & Conventions

### Static typing throughout
```gdscript
var x: int
func f() -> void:
for id: String in dict.keys():
```

### GDScript type inference gotcha
Dictionary access returns `Variant`. Annotate explicitly when comparing to a typed value:
```gdscript
# WRONG — GDScript can't infer bool from Variant:
var active := voices[i]["id"] == _selected_voice_id
# CORRECT:
var active: bool = voices[i]["id"] == _selected_voice_id
```

### Fractional accumulator (sub-integer tick rates)
```gdscript
_acc += rate * delta
if _acc >= 1.0:
    var n := int(_acc)
    _acc = fmod(_acc, 1.0)
    _process_n_times(n)
```

### Pause-safe UI nodes
Any node that must remain interactive while `get_tree().paused = true`:
```gdscript
process_mode = Node.PROCESS_MODE_ALWAYS
```
Apply to: the Panel, its CanvasLayer, and all interactive children (buttons, sliders).

### Settings overlay (guaranteed top layer)
```gdscript
# Build in _ready() deferred:
_overlay_layer = CanvasLayer.new()
_overlay_layer.layer = 100
_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
get_tree().root.add_child(_overlay_layer)
_overlay_layer.hide()

# Open:
_overlay_layer.show()
get_tree().paused = true

# Close:
_overlay_layer.hide()
get_tree().paused = false
```
CanvasLayer with high `layer` value beats any Control node's `z_index` — use layer=100 for overlays that must appear above the "screen" group.

### Tabs for indentation (matches all existing files)

---

## LOCKED MODULES — DO NOT MODIFY WITHOUT EXPLICIT USER PERMISSION

The following files are considered **stable and complete**. Claude must **not edit them** in any session unless the user explicitly says "bạn được phép sửa [tên file]" hoặc tương đương rõ ràng. Nếu có bug liên quan, hãy **báo cáo** thay vì tự ý sửa.

| File | Lý do khoá |
|------|-----------|
| `scripts/ui/user/music_player.gd` | Music player widget — đã ổn định sau nhiều lần debug |
| `scripts/ui/user/music_server.gd` | YouTube IPC client — logic kết nối mpv dễ vỡ |
| `scripts/autoload/audio_manager.gd` | Game music manager — đã có prev/next/shuffle/loop |
| `scripts/ui/user/user_panel.gd` | UserPanel layout — z-order và position đã được căn chỉnh |
| `tools/mpv-bridge.ps1` | PowerShell bridge — bidirectional async pipe, cực kỳ nhạy cảm |

Nếu một tác vụ yêu cầu đọc những file này để **hiểu context** thì được phép đọc. Chỉ không được **sửa** mà không có lệnh rõ ràng.

---

## Risky Areas

- Removing autoloads without updating `main.gd` references causes load failure
- Edit mode groups hiện tại: `["screen", "weaponry", "defense", "power_core", "user"]` — thêm group mới cần update `GROUPS`, `GROUP_FOLDERS`, `edit_mode.tscn` (button), `assets/<folder>/`; group "screen" có logic riêng qua `_auto_load_screen_group()`
- Scrolling background/overlay dùng `Image.resize()` CPU-side — KHÔNG dùng TextureRect stretch_mode. `EXPAND_IGNORE_SIZE` sẽ khiến texture render ở native size (2048px) rồi bị clip, trông như "crop"
- `res://default_layout.cfg` lưu layout edit mode (không phải `user://`) — đọc từ `main.gd._apply_screen_layouts()` deferred sau `_ready()`
- StreamScreen position = (270, 8) trong viewport; các tọa độ relative của scrolling bg = `viewport_pos − (270, 8)`
- `.uid` files sit next to every `.gd` and `.tscn` — Godot regenerates them on first editor open; scripts created headlessly may be missing UIDs
- `UpgradeManager.load_game()` must run before `GameManager.load_game()` (UpgradeManager resets GameManager rate fields to 0 then re-applies owned upgrades) — **but `main.gd._ready()` currently calls them in the opposite order (`GameManager` first). Verify intent before trusting either.**
- Internal GDScript variable names (views, subs, cash) are kept for API stability — they map to Fuel, Crew, Credits in all player-facing UI
- `WeaponManager.WEAPONS`/`owned` are empty until `edit_mode.gd` calls `sync_from_canvas()` after layout load — don't query weapons in `_ready()`; wait for the `catalog_updated` signal. Weapon ids come from **filenames** in `assets/weaponry/`, so renaming a sprite silently drops it from the catalog (mitigated by 7-char fuzzy match + `KEY_ALIASES`)
- `WeaponManager` and `DefenseManager` share `user://save.cfg`; `WeaponManager.save_game()` does `erase_section("weapons")` then rewrites — safe, but both managers must use distinct sections (`[weapons]` / `[defense]`)
- `project.godot` `[autoload]` has merge-conflicted twice on the autoload list; conflict markers there make Godot fail to open the project. Required set (no dups): AudioManager, MaterialManager, DefenseManager, EquipmentManager, UpgradeManager, GameManager, WeaponManager
