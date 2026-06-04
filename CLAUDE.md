# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4 GDScript — "The Traveler", a spaceship idle/clicker game. You captain a ship traveling through deep space. Entry scene: `scenes/main.tscn`. Toggle edit mode with the `toggle_edit_mode` input action (mapped in `project.godot`).

The game features a **real-time combat / crafting and idle harvesting layer**: asteroids drift down the SpaceScreen, clicking or shooting them yields four raw **materials** (metal / nonmetal / organic / liquid via `MaterialManager`). Upgrades (`UpgradeManager`) passively generate these materials, and equipment/weapons cost these materials. Weapons mounted on the canvas auto-fire at asteroids (`gun_system.gd`).

## Theme Mapping (internal → display)

| Internal variable | Display label |
|-------------------|---------------|
| `metal`           | Metal         |
| `nonmetal`        | Nonmetal      |
| `organic`         | Organic       |
| `liquid`          | Liquid        |
| Upgrade tab `"weaponry"` | WEAPONRY panel |
| Upgrade tab `"defense"` | DEFENSE panel |

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
| `GameManager` | `scripts/autoload/game_manager.gd` | Core game state (Ship HP, Shield, Boost, Boss fight) |
| `WeaponManager` | `scripts/autoload/weapon_manager.gd` | Canvas-driven tiered weapon catalog, priced in materials. Built at runtime by `sync_from_canvas()` (not a const list). Saves to `user://save.cfg` section `[weapons]` |

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
| 100 | Settings panel (always on top, even above screen group) |

---

## Scrolling Background System

### Files

| File | Role |
|------|------|
| `scripts/gameplay/scrolling_background.gd` | Tiles `assets/screen/background.png`, speed=40, z_index=0 |
| `scripts/gameplay/overlay.gd` | Tiles `assets/screen/overlay.png`, speed=80, z_index=1 |

Cả hai được tạo trong `main.gd._add_scrolling_background/overlay()` và thêm vào `SpaceScreen` (group `"scrolling_bg"` / `"scrolling_overlay"`).

### Cơ chế tiling

- Chỉ 1 column dọc, `n_rows = ceili(screen_h / tile_h) + 1`
- `_tile_x` = x position của cột trong SpaceScreen (mặc định căn giữa)
- `_offset` tăng mỗi frame → khi `>= tile_h` thì wrap về 0 (seamless scroll)

### Image scaling — QUAN TRỌNG

Không dùng `TextureRect.stretch_mode` để scale background/overlay tile. Thay vào đó:
```gdscript
var img := _source_img.duplicate()
img.resize(int(_tile_w), int(_tile_h), Image.INTERPOLATE_BILINEAR)
_tex = ImageTexture.create_from_image(img)
```
`_source_img` là `Image` load từ file gốc (2048×2048). Resize CPU-side → texture đúng kích cỡ → `TextureRect.STRETCH_KEEP` chỉ hiển thị, không scale thêm.

**`EXPAND_IGNORE_SIZE` — NGUY HIỂM**: luôn render texture ở native size rồi clip, bất kể `size` set bao nhiêu. KHÔNG dùng khi muốn hiển thị nhỏ hơn native.

**CPU resize chỉ hoạt động với `ImageTexture`** — texture load từ file PNG qua `load()` trả về `CompressedTexture2D`, KHÔNG phải `ImageTexture`. Đoạn code `tex as ImageTexture` sẽ trả về `null` → resize fail → trả về original full-size. GIF frames từ `GifLoader` mới là `ImageTexture` và resize được.

**Scale sprite nhỏ (weapon, ship)** — dùng `eo.scale = Vector2(s, s)` + `eo.pivot_offset = eo.size * 0.5` trực tiếp trên `EditableObjectNode`. Force-apply mỗi frame trong `_process` để tránh bị override. **KHÔNG cần tạo TextureRect riêng** chỉ để scale — đó là over-engineering gây lỗi.

**Nguyên tắc**: trước khi thêm system phức tạp (static rect, wrapper node...), thử `eo.scale` đơn giản trước. Nếu nó bị reset, force-apply trong `_process` là đủ.

### apply_layout_rect

```gdscript
bg.apply_layout_rect(rel_pos: Vector2, sz: Vector2)
```
`rel_pos` = vị trí tương đối trong SpaceScreen (= viewport_pos − (270, 8)). `sz` = kích thước tile. Được gọi deferred từ `main.gd._apply_screen_layouts()` sau khi đọc `res://default_layout.cfg`.

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

- Two instances added to `SpaceScreen`: a blurred, dimmed **under-layer** (`is_under=true`, z_index 0, custom 3×3 blur `ShaderMaterial`) and the interactive **main layer** (z_index 1, joins group `"asteroid_main"`).
- Asteroids spawn from `assets/asteroid/*.png`, drift down within a ±15° cone, rotate, and respawn on exit. Type is parsed from the **leading non-digit chars** of the filename (`dirt`, `ice`, `jewel`, `metal`, `rare`).
- **Collection** = click the asteroid OR a bullet hits it → `_collect_loot(type)` rolls a per-type random drop table into `MaterialManager.add(...)`. Hitbox min size `MIN_HITBOX = 36`.
- Query API used by the gun: `get_asteroid_centers()`, `get_asteroid_sizes()`, `collect_near(pos, radius)`. **Centers are in SpaceScreen-local space** — the gun adds `SS_OFFSET = (270, 8)` to convert to ObjectsContainer/viewport space.

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
var ship_hp: int
var ship_max_hp: int
var shield: float
var shield_max: float
var is_boss_active: bool
```

### Signals

`ship_hp_changed(int)`, `shield_changed(float)`, `boss_state_changed(bool)`

---

## UpgradeManager

### UPGRADES const structure

```gdscript
const UPGRADES = {
    "id": {
        "name": "Display Name",
        "icon": "filename.png",           # in assets/upgrades/active/
        "cost_type": "metal",             # e.g., "metal", "nonmetal", "organic", "liquid"
        "cost": 100.0,                    # base material cost
        "produces_type": "liquid",        # e.g., "liquid" or "metal" etc.
        "mps": 1.0,                       # materials produced per second
        "desc": "Flavor text",
    },
}
```

### Upgrades Catalog
`solar_panel` (Solar Panel), `mining_drone` (Mining Drone), `asteroid_harvester` (Asteroid Harvester), `dark_matter_extractor` (Dark Matter Extractor), `nebula_harvester` (Nebula Harvester), `stellar_forge` (Stellar Forge), `quantum_synthesizer` (Quantum Synthesizer), `galactic_fuel_web` (Galactic Fuel Web)

### Upgrade purchase currency
Upgrades are bought with materials matching `cost_type` from `MaterialManager`.

---

## UI Scripts

### `scripts/ui/hud/stat_panel.gd`

- Contains control buttons (MUTE, SETTING, QUIT) and cheat buttons (RESET HP, KILL BOSS).
- Settings overlay: CanvasLayer(layer=100, PROCESS_MODE_ALWAYS) added to `get_tree().root`
  - ColorRect (0,0,0,0.6) with MOUSE_FILTER_STOP blocks all input to scene below
  - Panel 330×660 with sections: Resolution, Volume, Weapon SFX, Materials (editable SpinBoxes), and Resets (RESET PURCHASES, RESET GAME).
- `_open_settings()`: show overlay + sync SpinBoxes with current materials from `MaterialManager`.
- `_close_settings()`: hide overlay.
- Escape key closes settings via `_input()`.

### `scripts/ui/upgrade/upgrade_list.gd`

- Tab bar (WEAPONRY / DEFENSE) built at top; ScrollContainer offset_top=50 to clear it
- `_current_tab: String` filters by `UPGRADES[id].get("tab", "weaponry")`
- `_switch_tab(tab)` rebuilds item list and updates button highlight colors

### `scripts/ui/edit_mode/editable_object.gd`

- `EditableObjectNode` (`class_name`) — every in-canvas placed sprite.
- `group_id: String` — one of `"screen" | "weaponry" | "defense" | "power_core" | "user"`.
- `_gameplay_mode: bool` — edit handles vs gameplay click routing.
- Displays resource price label (`_price_label`) in edit mode showing material cost (e.g. "100 Nonmetal").
- `group_id == "screen"` → invisible in gameplay (`visible = false`); scrolling background system handles rendering.

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
| `user://game_save.cfg` | ship HP/shield save state |
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

## Boss Fight System (`scripts/gameplay/boss_fight.gd`)

### Architecture

- **Root node:** `Control` (layer z=200, PROCESS_MODE_PAUSABLE)
- **Clip container:** `_clip_node` (Control, clipped to SpaceScreen bounds) — all projectiles rendered inside
- **Boss EO:** `_boss_eo` (EditableObjectNode from objects_container) — animated sprite with rotation pivot at center
- **Ship EO:** `_ship_eo` — for targeting, collision bounds
- **Fire points:** `_fp1_node`, `_fp2_node`, `_fp3_node` (Node2D children of boss) — auto-follow boss rotation + translation

### Phases and Cycle

```
enum Phase { IDLE, M1_ENTRY, M1_TRAVEL, M2, M3_ROT, M3_MOVE, M3_WARN, M3_FIRE,
             M4_ROT, M4_TRAVEL, M5_ROT, M5_MOVE, DONE }
```

**Move sequence:** Random pick after each move completes → `_begin_random_move()` picks one of 5 moves uniformly.

- **M1 (Spike Rain):** Spin + horizontal sweep + spiral spike bursts mỗi 0.2s. Duration ~8s.
- **M2 (Vortex Wander):** Random movement + vortex bursts từ fp1, fp2 mỗi 1.5s. Duration ~8s.
- **M3 (Laser):** Rotate 90° → align X → laser telegraph + fire. Total ~3.5s. Laser = one-shot 30 HP.
- **M4 (Shot Drop):** Tween entry (trái/phải) → rotate 90° → sweep ngang 120 px/s + drops từ fp3 mỗi 1s. End khi chạm screen edge. Drops = 20 HP.
- **M5 (Shoot Blob):** Rotate 90° → random wander y<450 trong 5s + blobs từ boss center mỗi 1s, homing. Blobs = 20 HP.

**Entry tween:** M1/M2/M3/M4 tween vị trí trong 1.0–1.5s, set `_phase = Phase.M1_ENTRY` để block boss tick (nhưng projectiles vẫn tick — critical fix).

### Move-Specific Details

**M1:** Spikes → balls (ball1–4.gif) random pick, resize 10%, no blink, 30 px/s, damage 10.
**M2:** Vortex từ fp1+fp2, GIF animated, rotate, 90 px/s, 15 HP.
**M3:** Laser từ fp3 (rotated), telegraph flash 0.08s cycle, damage 30 (one-shot).
**M4:** Drops từ fp3 (rotated), drop.gif animated + pre-resized 20% at load, 120 px/s down, 20 HP.
**M5:** Blobs từ boss center, blob.gif animated, 80 px/s homing (straight line, no pause), 20 HP.

### Projectile System

**Dict format (in `_projectiles` array):**
```gdscript
{
  "tr":        TextureRect,    # scene node in _clip_node local space
  "vel":       Vector2,        # px/sec in clip space
  "rot_spd":   float,          # rotation speed (0 = no spin)
  "rot":       float,          # accumulated rotation
  "dmg":       int,            # damage on hit
  "type":      String,         # "spike", "ball", "vortex", "drop", "blob"
  "frames":    Array[Texture2D],
  "delays":    Array[float],   # per-frame GIF delays
  "frame":     int,            # current frame
  "acc":       float,          # frame accumulator
  "blink_acc": float,          # for spike blink effect (sin wave, orange-red pulse)
}
```

**Collision:** Pixel-perfect — tight rect broad-check → per-pixel alpha sampling (2px step).

**Critical:** `_tick_projectiles(delta)` is called **before** `M1_ENTRY` early-return in `_process()`. If called after, projectiles freeze during boss tween. See `_process()` line ~284.

### Asset Loading

Animations loaded in `_load_assets()` via GifLoader:
- firevortex.gif (M2)
- laser.gif (M3)
- ball1–4.gif (M1, random pick each spawn)
- drop.gif (M4, pre-resized 20% at load → cached in `_drop_frames`, `_drop_size`)
- blob.gif (M5)

GifLoader extracts frames and delays metadata. Non-GIF textures fallback to single-frame array.

### Key Functions and State

| Function | Purpose |
|----------|---------|
| `spawn_boss()` | Initialize boss, set HP, emit signals, auto-activate manual boost |
| `start_fight()` | Set boss visible, call `_begin_random_move()` |
| `_begin_random_move()` | Reset rotation, random pick move 0–4 |
| `_begin_m1/2/3/4()` | Tween setup + phase to M1_ENTRY or real phase |
| `_begin_m5()` | No tween, phase straight to M5_ROT |
| `_tick_m1/2/3/4/5_*()` | Move-specific tick logic |
| `_spawn_spike/drop/blob()` | Create projectile dict, append to `_projectiles` |
| `_tick_projectiles(delta)` | Move, animate, collide, cull all in-flight projectiles |
| `kill_boss()` | Set HP=0, hide sprite, cleanup projectiles, emit signal |

### Gotchas

1. **M1_ENTRY early-return:** `_process()` checks `_phase == Phase.M1_ENTRY` and returns early (line ~283). **This must come AFTER `_tick_projectiles(delta)`** or projectiles freeze during tween.

2. **Fire point caching:** Fire points are Node2D children of boss → Godot auto-rotates + translates them. Fallback to `boss_center + offset` if child invalid.

3. **Drop/blob resize:** Drop frames are pre-resized at load (0.2×) into `_drop_frames` + `_drop_size` cache. Blob uses native size. Ball frames are resized at spawn (0.1×) because there are 4 variants.

4. **Blob homing:** Blob fires once at ship center direction, flies straight (no state machine pause/redirect). Simple linear projectile, like vortex.

5. **Collision damage:** Ships collide via `GameManager.ship_take_damage(dmg)`. One hit per projectile (removed after collision). Boss collision via `get_boss_hit_rect()` for external hitbox checks.

6. **Screen edge detection (M4):** Boss position clamped to OC_BOUNDS. M4 manually checks `position.x >= end.x - size.x` to trigger end.

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

### Save/layout persistence — LOCKED FUNCTIONS (không sửa logic bên dưới)

Các hàm sau đây đã được debug và ổn định. **Không thay đổi** trừ khi user rõ ràng yêu cầu:

| Hàm | File | Lý do khoá |
|-----|------|-----------|
| `_save_layout()` | `edit_mode.gd` | Đọc `obj.position` khi game paused (gun_system dừng) → ghi đúng vào `res://default_layout.cfg`; check `cfg.save() == OK` trước khi reset `_dirty` |
| `_load_layout()` | `edit_mode.gd` | Load cfg → tạo objects → set position/size/z_index đúng thứ tự; cuối gọi `WeaponManager.sync_from_canvas()` |
| `_close()` | `edit_mode.gd` | Trước khi unpause: iterate `objects_container.get_children()` gọi `refresh_layout()` để gun_system sync origin mới; sau đó `get_tree().paused = false` |
| `refresh_layout()` | `gun_system.gd` | Public wrapper gọi `_refresh_static_frames()` — cập nhật `_spaceship_origin` và `_weapon_eo_rels` từ positions hiện tại sau khi user edit |

**Nguyên tắc save/load**: gun_system có `process_mode = PROCESS_MODE_PAUSABLE` → dừng khi tree paused → positions trong F4 mode là stable → save đọc đúng positions. Sau close F4: `refresh_layout()` sync gun_system về positions mới trước khi unpause. Không phá vỡ cycle này.

Nếu một tác vụ yêu cầu đọc những file này để **hiểu context** thì được phép đọc. Chỉ không được **sửa** mà không có lệnh rõ ràng.

---

## Sprite Sheet & GIF Loading

### GIF → PNG Sprite Sheet Conversion

All GIFs must be **pre-converted to PNG sprite sheets** for fast loading and correct frame rendering:

**Command:**
```bash
godot --headless --script tools/convert_gifs.gd
# Generates: <name>.sheet.png + <name>.sheet.json next to .gif
```

**Process (tools/convert_gifs.gd):**
1. Find all .gif under res://assets/
2. Decode using GDScript LZW (`GifLoader._decode_frames()`)
3. Create horizontal sprite sheet: `Image.create(frame_width × frame_count, frame_height)`
4. Blit each frame: `sheet.blit_rect(frame_img, src_rect, Vector2i(i × frame_width, 0))`
5. Save `.sheet.png` + `.sheet.json` metadata (cols, w, h, delays[])
6. **Open Godot editor once** to re-import `.sheet.png` (native GPU upload)

**Loading (scripts/ui/edit_mode/gif_loader.gd):**
- **Path 1 (fast):** if `.sheet.png` + `.sheet.json` exist → slice into AtlasTextures from PNG
- **Path 2 (slow fallback):** if sheets missing → GDScript LZW decode at runtime (per load)

### Frame Stacking / Disposal Mode Issue

GIF disposal modes control frame accumulation:
- **Mode 0/1 (default):** keep canvas (pixels stack)
- **Mode 2:** clear to background
- **Mode 3:** restore previous

**Problem:** Missing PNG sheets force GDScript path → potential accumulation if disposal=0 not handled.

**Solution:** Always run `convert_gifs.gd` after adding new GIFs:
```bash
# After adding chromeball.gif, chromeleon.gif, etc:
godot --headless --script tools/convert_gifs.gd
# Then open Godot editor once to import PNGs
```

**Debug:** Check if `.sheet.png` missing:
```bash
# If .sheet.json exists but .sheet.png missing → regenerate
ls assets/bosses/*/*.sheet.png | wc -l   # should match .json count
```

---

## Projectile & Asteroid Rescaling

### CPU-Side Rescaling Pattern

All projectiles (bullets, asteroids) must be **CPU-resized** for quality and consistency:

```gdscript
# Pattern A: Pre-cached (for fixed-size bullets)
func _resize_tex(tex: Texture2D, target_sz: Vector2) -> Texture2D:
    if tex == null or target_sz == Vector2.ZERO:
        return tex
    var img := tex.get_image()
    if img == null:
        return tex
    var copy := img.duplicate() as Image
    copy.resize(int(target_sz.x), int(target_sz.y), Image.INTERPOLATE_BILINEAR)
    return ImageTexture.create_from_image(copy)
```

### Application by Use Case

| Case | File | Pattern | Notes |
|------|------|---------|-------|
| **Chromeleon bullets** | `chromeleon_fight.gd` | Pre-cached | Size from F5 → load time → `_reload_bullet_sizes()` → `_resize_all_bullets()` |
| **Elephant bullets** | `boss_fight.gd` | Pre-cached | Tier-specific hardcoded sizes → resized at load → cached in frames array |
| **Asteroids** | `asteroid_layer.gd` | Runtime resize | Random size per spawn → `img.resize()` at spawn time → `ImageTexture.create_from_image()` |

### TextureRect Configuration

Once texture is **CPU-resized to target size**, use:
```gdscript
tr.stretch_mode = TextureRect.STRETCH_KEEP          # texture already sized; no GPU scaling
tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE     # (asteroid only: used with STRETCH_KEEP_CENTERED)
tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
```

**Never use `STRETCH_SCALE`** after CPU resize — defeats the purpose. `STRETCH_SCALE` scales compressed textures poorly.

### When Adding New Projectile

1. **Fixed size** (known at load time): pre-cache pattern (like chromebullet)
   - Load texture → store in array
   - On size config change: `_resize_all()` → cache resized versions
   - Spawn: pick from cache

2. **Random/dynamic size**: runtime resize (like asteroid)
   - Spawn: generate random size → duplicate source → `img.resize()` → `ImageTexture.create_from_image()`
   - One-shot, discarded after use (no cache overhead)

---

## Risky Areas

- Removing autoloads without updating `main.gd` references causes load failure
- Edit mode groups hiện tại: `["screen", "weaponry", "defense", "power_core", "user"]` — thêm group mới cần update `GROUPS`, `GROUP_FOLDERS`, `edit_mode.tscn` (button), `assets/<folder>/`; group "screen" có logic riêng qua `_auto_load_screen_group()`
- Scrolling background/overlay dùng `Image.resize()` CPU-side — KHÔNG dùng TextureRect stretch_mode. `EXPAND_IGNORE_SIZE` sẽ khiến texture render ở native size (2048px) rồi bị clip, trông như "crop"
- `res://default_layout.cfg` lưu layout edit mode (không phải `user://`) — đọc từ `main.gd._apply_screen_layouts()` deferred sau `_ready()`
- SpaceScreen position = (270, 8) trong viewport; các tọa độ relative của scrolling bg = `viewport_pos − (270, 8)`
- `.uid` files sit next to every `.gd` and `.tscn` — Godot regenerates them on first editor open; scripts created headlessly may be missing UIDs
- `UpgradeManager.load_game()` must run before `GameManager.load_game()` (UpgradeManager resets GameManager rate fields to 0 then re-applies owned upgrades) — **but `main.gd._ready()` currently calls them in the opposite order (`GameManager` first). Verify intent before trusting either.**
- `WeaponManager.WEAPONS`/`owned` are empty until `edit_mode.gd` calls `sync_from_canvas()` after layout load — don't query weapons in `_ready()`; wait for the `catalog_updated` signal. Weapon ids come from **filenames** in `assets/weaponry/`, so renaming a sprite silently drops it from the catalog (mitigated by 7-char fuzzy match + `KEY_ALIASES`)
- `WeaponManager` and `DefenseManager` share `user://save.cfg`; `WeaponManager.save_game()` does `erase_section("weapons")` then rewrites — safe, but both managers must use distinct sections (`[weapons]` / `[defense]`)
- `project.godot` `[autoload]` has merge-conflicted twice on the autoload list; conflict markers there make Godot fail to open the project. Required set (no dups): AudioManager, MaterialManager, DefenseManager, EquipmentManager, UpgradeManager, GameManager, WeaponManager
