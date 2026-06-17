# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Memory

Khi bắt đầu làm việc với project này, **đọc file memory** tại:
`C:\Users\sonvt\.claude\projects\C--Users-sonvt\memory\MEMORY.md`

File đó chứa index các memory notes liên quan đến project — coordinate system, locked files, session conventions, v.v.

## Project

Godot 4 GDScript — "The Traveler", a spaceship idle/clicker game. You captain a ship traveling through deep space. Entry scene: `scenes/main.tscn`. Toggle edit mode with the `toggle_edit_mode` input action (mapped in `project.godot`).

The game features a **real-time combat / crafting and idle harvesting layer**: asteroids drift down the SpaceScreen, clicking or shooting them yields four raw **materials** (metal / nonmetal / organic / liquid via `MaterialManager`). Upgrades (`UpgradeManager`) passively generate these materials. The **current** combat path is the Diablo-2 **inventory + affix** system (`InventoryManager`) with equipped weapons driven by `weapon_system.gd`; the older canvas-mounted `WeaponManager` / `gun_system.gd` auto-fire path is now legacy (kept for ship movement + asteroid-vs-ship collision).

### Reference docs (repo root, not code)

`README.md` (setup), `design.md` (idle-economy design + tuning), `summary.md` (fuller architecture map — active vs legacy code), `inventory_redesign.md` + `minh_scope.md` (inventory/hull/affix task specs), `GRAPHICS_SPEC.md` (planned visual-polish tiers). `weapon_current.csv` + the `weapon_current.*.translation` files are **documentation only, not loaded by code** — hand-maintained from `ITEM_DEFS` in `inventory_manager.gd`.

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
| 100 | Settings panel + `hud_edit_overlay.gd` (HUD edit F6) — always on top |

`auto_clicker_overlay.gd` (`scripts/gameplay/auto_clicker_overlay.gd`) draws one hand cursor per owned autoclicker upgrade, placed flush against the ship sprite's silhouette via alpha-edge detection (`_alpha_edge`); rebuilds on `UpgradeManager.upgrade_purchased` / `upgrades_reset`. Self-contained, no signals out.

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

### Pivot Point Rule — QUAN TRỌNG

**Mọi loại scale (zoom, shrink, transform) luôn lấy pivot point là center of image.**

```gdscript
# Setup before scaling:
eo.pivot_offset = eo.size / 2.0

# Then scale from center:
eo.scale = Vector2(0.5, 0.5)  # Scales từ center, không từ top-left
eo.rotation = TAU / 4          # Rotates từ center
```

**Áp dụng cho:**
- Boss sprites (cocoon, metalfly, chromeleon, elephant)
- Weapon sprites
- Spaceship (manual boost / boss fight scale-down)
- Projectiles (bullets, lasers, shards)
- UI overlays (health bars, warnings)

**Lý do:** Nếu không set `pivot_offset`, GDScript mặc định scale/rotate từ top-left → vị trí bị shift, không center. Dẫn đến movement bị sai, animation bị lệch.

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

### `weapon_system.gd` vs `gun_system.gd` — QUAN TRỌNG

The active firing engine is **`weapon_system.gd`** (`scripts/gameplay/weapon_system.gd`), not `gun_system.gd`. They run in parallel:

| | `weapon_system.gd` (live) | `gun_system.gd` (legacy) |
|--|---------------------------|--------------------------|
| Role | Equipped-weapon engine + all combat FX | Ship float/movement + asteroid-vs-ship collision |
| Source of weapons | `InventoryManager` equipped slots, read each frame | (mount auto-fire **retired**) |
| Where added | `main.gd` → child of `SpaceScreen`, group `"weapon_system"` | `main.gd` → `ObjectsContainer`, z_index just above spaceship |
| Looked up by | bosses via `get_tree().get_first_node_in_group("weapon_system")` | not group-queried |

`weapon_system.gd` handles fire modes **repeat / charge / beam / channel / aura**; projectiles/missiles/homing/cone-spread/chain/parasites-with-DoT, orbitals, bat swarm, Laser gun (hitscan, mouse-aimed) + Plasma-Drill (tether) beams, Rift-Maker vortex, environment light overlay, and floating crit damage numbers. Primary weapon = left-click, secondary = right-click. It applies each item's hidden `base_mult` (±20%) and affixes when computing stats. **`gun_system.refresh_layout()` and the F4 save/load cycle remain locked** (see LOCKED MODULES).

**Laser gun** (`fire_type: "hitscan_beam"`, item id `"lasgun"`, display name `"Laser gun"`): beam hướng từ muzzle về phía chuột (`get_local_mouse_position() - muzzle`). Fallback `Vector2.UP` chỉ khi chuột trùng muzzle. Affix `splash_radius` → suffix "of Detonation" (chưa implement splash). **`splash_radius` và các affix `multishot/pierce/ricochet/knockback` chưa được wire vào fire logic** (xem comment `weapon_system.gd:2436`).

### Gun system (`scripts/gameplay/gun_system.gd`) — legacy mount auto-fire

> Historical: the description below documents the retired `WeaponManager`-driven mount auto-fire. `gun_system.gd` still runs for ship movement + asteroid collision, but no longer fires.

- A full-rect `Control` (added to `ObjectsContainer`, z_index 7) that fires every `FIRE_INTERVAL = 0.5s` from each **active `"gun"` weapon object** (`WeaponManager.get_active_objects("gun")`).
- Targets the nearest asteroid that is ≥100px above the gun muzzle; spawns a bullet (`atan2(dir.x, -dir.y)` rotation), an ejecting shell, an impact GIF on hit, and plays the gun-fire GIF (hides the static sprite during the animation). GIFs loaded via `GifLoader` (`Gun.gif`, `Gun-Impact50.gif`) from `assets/sprites/weapons/`.
- All projectiles/animations are pooled in plain arrays and ticked manually in `_process` (same manual-pool pattern as the asteroids and scrolling bg).

### Coordinate Systems — QUAN TRỌNG

**Rule: Khi chỉ định tọa độ (position, spawn, etc.), luôn dùng SpaceScreen-local coordinates (screen coordinates).**

- **SpaceScreen** là `Panel` ở vị trí (270, 8) trong viewport, kích thước 700×764
- **Screen coordinates** = tọa độ relative to SpaceScreen origin (0, 0 = top-left corner của SpaceScreen)
- **ObjectsContainer coordinates** = absolute coordinates trong viewport/ObjectsContainer

**Conversion formula:**
```gdscript
var screen_pos := Vector2(150, 350)  # User-specified, screen coordinates
var oc_pos := screen_pos + Vector2(270, 8)  # = (420, 358) in ObjectsContainer
```

**Áp dụng:**
- `boss_layout.cfg` — luôn ghi ObjectsContainer coordinates (`oc_pos = screen_pos + SS_OFFSET`)
- Boss spawn positions — specified as screen coordinates, convert trong code/config
- UI annotations — give user screen coordinates for clarity

**Examples:**
| Use case | Screen coords | ObjectsContainer coords |
|----------|---------------|-----------------------|
| Cocoon spawn | (350, 150) | (620, 158) |
| Metalfly spawn | (350, 150) | (620, 158) |
| Firepoint | (596, 455) | (866, 463) |

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

## Inventory, Items & Affixes (current item layer)

A Diablo-2-style grid inventory with equip slots and rolled affixes. This is the **live** weapon/gear path; `weapon_system.gd` reads equipped items from here. Two autoloads + four UI files.

### `InventoryManager` (`scripts/autoload/inventory_manager.gd`) — data layer

- **`ITEM_DEFS`** (const): master catalog (weapons + hulls + shield). Each def: `name`, `icon`, `size` (grid cells), `tags`, `rarity`, optional `fire_mode`/`fire_type`, `stats` dict.
- **Item instances** (`_items[uid]`): `{def, where, cell, affixes, base_mult, hull_mult}`. `uid` is an int counter (`_next_uid`); `where` = `"backpack"` or a slot name; `cell` = grid origin. `STARTER_ITEMS` are granted once per save (tracked in `_granted`); `RESET_INVENTORY_ON_LOAD` flag re-grants on load.
- **Backpack**: grid (cols × rows from `BACKPACK_COLS/ROWS`), 46px cells. **10 equip slots**: `primary_weapon`, `secondary_weapon`, `thruster`, `command_bridge`, `hull`, `energy_core`, `radar`, `drone_1`, `drone_2`, `wings`. Slot gating via `SLOT_RULES` (per-slot `any` tags required + `exclude` tags blocked) → `fits_slot(def_id, slot)`.
- Key methods: `add_to_backpack`, `move_item(uid, cell)`, `equip(uid, slot)`, `unequip(slot)`, `can_place(size, cell, ignore_uid)`, `generate_weapon(tier, base_def_id)` / `generate_hull(...)`, `roll_asteroid_drop()` (weighted by def `rarity`). Stat accessors apply rolls: `item_base_mult`, `item_affixes`, `item_display_name`, `item_display_color`, `hull_bonus_hp`, `hull_damage_reduction`.
- **Signals:** `inventory_changed`, `item_added(uid)`, `item_equipped(slot, uid)`, `item_unequipped(slot, uid)`. **Save:** `user://save.cfg` section `[inventory]`.

### `AffixManager` (`scripts/autoload/affix_manager.gd`) — affix roller

- **`AFFIX_DEFS`**: ~40 affixes, each with prefix/suffix names, `unit`, `min`/`max`. Pools: `WEAPON_AFFIX_POOL` (~19) vs `HULL_AFFIX_POOL` (~22). No persistence.
- **`roll_affix(id, tier)`**: rolls inside a tier band of `[min, max]` — tier 1 Low (0–33%), tier 2 Mid (33–66%), tier 3 High (66–100%). Negative affixes use the same math (higher tier = more negative = better).

### Rolling model

- Per weapon/hull instance: **30% prefix + 30% suffix** chance independently → **0, 1, or 2** affixes (distinct ids). Plus a **hidden ±20% `base_mult`** (weapons: on damage) / per-stat `hull_mult` (hulls: HP & damage-reduction each roll their own ±20%).
- **Display color = affix count, not def rarity**: white (0 affixes) vs blue (1–2). `rarity` only drives loot-drop weights. Display name = `[Prefix] Base [Suffix]`.

### UI (`scripts/ui/inventory/`)

- `inventory_ui.gd` — toggle panel (key **I** / ESC), rebuilds children on `inventory_changed`; cross-shaped equip-slot grid (each slot sized to its largest item footprint) + backpack grid; right-click item → `sell_requested` → confirm → `sell_item`.
- `backpack_grid.gd` — drag/drop re-arrange; delegates to `can_place` / `move_item`; green/red hover overlay.
- `equip_slot.gd` — drop target; `_can_drop_data` → `fits_slot`, `_drop_data` → `equip`.
- `item_widget.gd` — one placed item; drag source (`_get_drag_data` carries `{uid, def_id, grab, slot}`) + D2 hover tooltip (name colored by affix count → base stats → affix lines). **LOCKED** (tooltip is critical).

---

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

**Boss fight signal sequence:**
```
boss_incoming  → warning overlay shows, bg/overlay swapped, normal music fades out
boss_spawned   → boss HP set, boss music starts
boss_killed    → boss music fades, normal music restarts
boss_defeated  → XP awarded (real end, not phase transition)
```

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

### `scripts/ui/hud/hud_edit_overlay.gd` (F6 HUD Edit Mode)

Toggle với **F6**. Cho phép drag/resize các HUD widget theo thời gian thực, lưu vào `user://hud_layout.cfg`.

**Widget registration protocol** — mỗi widget cần:
```gdscript
add_to_group("hud_editable")
set_meta("hud_key", "unique_key_name")
func get_hud_rect() -> Rect2: ...   # trả về position + size hiện tại
func apply_hud_rect(rect: Rect2) -> void: ...  # áp dụng rect mới lên node
static func _load_hud_rect(key: String) -> Rect2: ...  # đọc từ user://hud_layout.cfg
```

**Widgets hiện đang editable:**
| Widget | File | hud_key | Default pos |
|--------|------|---------|-------------|
| AUTO-DRIVE | `boost_button.gd` | `"boost_button"` | (vp.x-60, 550) |
| AUTO-FIRE | `auto_fire_button.gd` | `"auto_fire"` | (vp.x-60, 652) |
| ENEMIES panel | `enemy_panel.gd` | `"enemy_panel"` | (980, 500) |
| QuickPanel (stat) | `stat_panel.gd` | `"stat_panel"` | (1240, 228) deferred |
| INVENTORY button | `inventory_ui.gd` | `"inventory_btn"` | (1240, 310) |

**Props panel (X/Y/W/H):** Click frame để chọn (viền vàng) → nhập số vào ô X/Y/W/H → nhấn Enter để áp dụng ngay. Kéo cũng cập nhật các ô này real-time.

**`stat_panel.gd` deferred load:** `_anchor_bottom_right()` chạy deferred → phải gọi `_load_hud_layout()` deferred SAU ĐÓ (thứ tự `call_deferred` trong cùng `_ready()` là đảm bảo). Nếu đảo thứ tự, config bị override bởi `_anchor_bottom_right()`.

**Save:** nút Save trong toolbar → `apply_hud_rect()` tất cả widgets → ghi `user://hud_layout.cfg`. Mỗi widget load config riêng trong `_ready()` / `_reposition()` của nó.

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
| `assets/bosses/*/` | Boss sprites — see **PNG Sprite Sheet Animation** section below |

EquipmentManager cost formula: `20 * pow(1.6, sorted_index)`

---

## PNG Sprite Sheet Animation (Project-Wide Standard)

**Rule: All animated GIFs (>1 frame) must be converted to PNG sprite sheets + JSON metadata.**

### Why
- GIF multi-frame animations can cause visual artifacts (frame stacking) in edit mode
- PNG sprite sheets are static, reliable, and support arbitrary frame timing via JSON
- Centralized frame/delay metadata enables consistent animation playback across edit + gameplay modes

### Conversion Process

1. **Create PNG sprite sheet:**
   ```bash
   python3 << 'EOF'
   from PIL import Image
   
   gif = Image.open("animation.gif")
   n_frames = gif.n_frames
   frame_w, frame_h = gif.size
   
   # All frames in single row
   sheet = Image.new('RGBA', (frame_w * n_frames, frame_h), (0, 0, 0, 0))
   
   for i in range(n_frames):
       gif.seek(i)
       frame = gif.convert('RGBA')
       sheet.paste(frame, (i * frame_w, 0))
   
   sheet.save("animation.png", 'PNG')
   EOF
   ```

2. **Create JSON metadata** (`animation.json`):
   ```json
   {
     "version": 1,
     "frame_width": 200,
     "frame_height": 115,
     "frame_count": 11,
     "frames": [
       {"index": 0, "x": 0, "y": 0, "width": 200, "height": 115, "delay": 0.1},
       {"index": 1, "x": 200, "y": 0, "width": 200, "height": 115, "delay": 0.1},
       ...
     ]
   }
   ```
   - `frame_width` × `frame_height`: individual frame dimensions
   - `frame_count`: total frame count
   - `delay`: seconds per frame (e.g., `0.1s` = 10 fps)
   - `x`, `y`, `width`, `height`: bounding box of each frame in the sprite sheet

3. **Update `boss_layout.cfg`** (or similar asset config):
   ```ini
   path: "res://assets/bosses/metalfly/Transform.png"
   ```
   (Point to PNG, not GIF. JSON metadata must be in same folder.)

### Code Integration (Automatic)

**`scripts/ui/edit_mode/png_sprite_loader.gd`** — Handles PNG sprite sheet loading:
- Reads PNG + JSON metadata
- Cuts frames from sprite sheet
- Returns `Texture2D` with `get_meta("gif_frames")` and `get_meta("gif_delays")` (GifLoader-compatible format)

**`scripts/ui/boss_edit/boss_edit_mode.gd._load_full_tex()`** — Auto-detects PNG + JSON:
```gdscript
if ext == "png":
    var json_path := path.get_basename() + ".json"
    if FileAccess.open(json_path, FileAccess.READ) != null:
        return PngSpriteLoader.load_png_sprite(path)
```

**All EditableObjectNodes** automatically animate PNG sprite sheets in edit mode (same as GIF frames).

### Gameplay Usage

In boss fight scripts (`metalfly_fight.gd`, `chromeleon_fight.gd`, etc.):
- `_load_assets()` uses `GifLoader` which now handles both GIF and PNG sprite metadata
- Projectile animations and boss sprites render frame-by-frame
- **No script changes required** — loader handles both formats transparently

### Asset File Checklist

For each animated asset:
- ✓ PNG sprite sheet in `assets/bosses/[name]/animation.png`
- ✓ JSON metadata in `assets/bosses/[name]/animation.json`
- ✓ `boss_layout.cfg` points to `.png`, not `.gif`
- ✓ Verify frame count matches JSON `frame_count`
- ✓ Verify frame dimensions match PNG sprite sheet layout

### Examples

| Asset | Frames | Frame Size | Delay | Total Duration |
|-------|--------|------------|-------|-----------------|
| `Transform.png` | 11 | 200×115 | 0.1s | 1.1s |
| `arrow.png` | 5 | 200×364 | 0.15s | 0.75s |
| `fly.png` | 8 | 200×136 | 0.12s | 0.96s |

---

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

### Structure: coordinator + standalone per-boss controllers

`boss_fight.gd` is a **coordinator**, not a base class. It is the only member of group `"boss_fight"`, the sole listener of `GameManager.boss_killed` / `boss_hp_changed`, and routes those signals **only to the active boss**. It owns three **standalone** boss controllers (each a self-contained `Control`):

| Controller | Boss | Notes |
|------------|------|-------|
| `scripts/gameplay/boss_elephant.gd` | Elephant | The 5-move spike/vortex engine detailed below; 75% projectile damage mult; rotation-invariant hitbox |
| `scripts/gameplay/boss_chromeleon.gd` | Chromeleon | 2-phase crystal; Phase-2 orb lasers via `lasgun_beam.gd`; emits `anim_finished` |
| `scripts/gameplay/boss_metalfly.gd` | Metalfly | 2-phase cocoon→fly, separate HP pools (P1 idle, P2 attacks) |

Per-boss API contract: `setup(oc)`, `spawn_boss()`, `kill_boss()`, `get_boss_hit_rect() -> Rect2`, `notify_boss_killed()` (+ optional `notify_hp_changed`, `flash_boss_hit`, `consume_projectile_near`). Shared `scripts/gameplay/boss_death_fx.gd` drives the death cutscene — `play(body_nodes, arena_rect, shake_node, is_final)` → emits `finished`; a one-time-use utility, not per-boss. `lasgun_beam.gd` is a standalone beam-FX helper (a copy of `weapon_system`'s Lasgun beam) used by Chromeleon's orbs.

### Elephant move engine — Architecture

The move/projectile docs below describe the **elephant** boss (the original generic engine). Other bosses have their own move sets in their controllers.

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

### Boss Intro & Warning Flow

**Timeline (triggered by `boss_fight.gd → spawn_boss()`):**

```
t=0s   m.setup_arena()         ← bg/overlay swap per boss (called before boss_incoming)
t=0s   boss_incoming.emit()    ← warning.png flashes 5s, bossalert.wav plays, normal music fades
t=0s   normal music fades out  ← boss_music.gd connects to boss_incoming
t=5s   m.spawn_boss()          ← HP set, boss_spawned emitted, boss music starts
t=5s   _start_intro()          ← boss_intro_active=true, boss EO flies in from above (1s)
t=6s   _start_wander()         ← boss drifts around WANDER_CENTER=(620,158) OC for 5s
t=11s  _end_wander()           ← boss_intro_active=false, m.start_fight() → attacks begin
```

**`boss_warning.gd`** (`scripts/gameplay/boss_warning.gd`): listens to `boss_incoming`, flashes `warning.png` as CanvasLayer(layer=20) over screen with 5s duration / 0.75s interval / 0.2s fade. Positioned at SS_POS shifted 300px up.

**Per-boss contract additions (beyond basic API):**
- `setup_arena()` — swap scrolling bg + overlay to boss-specific assets. Called at `boss_incoming` time (before spawn delay).
- `spawn_boss()` — must make boss EO **visible** (so it's seen during fly-in + wander). Must NOT call `start_fight()`.
- `start_fight()` — called by coordinator after wander. Must call `_begin_random_move()` only (no visual setup; boss is already visible).

**`boss_intro_active` flag:** set `true` in `_start_intro()`, cleared in `_end_wander()`. Each boss `_process()` returns early when true — blocks all attack logic. Tween position updates still run (wander works).

**Ship movement during intro** (`gun_system.gd`): when `boss_intro_active` first becomes true, ship lerps from its **current position** to the designated center-bottom position over 1s. `_intro_from = _spaceship_origin` (not teleported from below screen).

**Wander constants** (`boss_fight.gd`):
```gdscript
const WANDER_CENTER   := Vector2(620.0, 158.0)  # OC coords = screen (350,150) + SS_OFFSET
const WANDER_RADIUS   := 50.0
const WANDER_STEP_T   := 1.2   # seconds per step
const WANDER_DURATION := 5.0
const WARNING_DELAY   := 5.0   # seconds of warning before boss spawns
```

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
| `scripts/ui/inventory/item_widget.gd` | Diablo-2 style inventory + tooltip system — tooltip functionality là critical |
| `scripts/autoload/inventory_manager.gd` | Item data layer + `get_icon()` loader — chỉ sửa ITEM_DEFS, không động hàm load/get_icon |

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

All GIFs are **automatically converted to PNG sprite sheets** on first load. No manual step required.

**Automatic (runtime, `gif_loader.gd`):**
- `GifLoader.load_gif()` tries Path 1 first (fast sheet). If missing, falls back to GDScript LZW decode **and immediately writes** `.sheet.png` + `.sheet.json` next to the `.gif` via `_auto_convert()`.
- Next session the same GIF loads via Path 1 (fast native PNG).
- Works in editor/dev builds. No-ops in exported PCKs (res:// is read-only there — pre-generate sheets before export).

**Batch pre-generate (before export or for all GIFs at once):**
```bash
godot --headless --script tools/convert_gifs.gd
# Generates: <name>.sheet.png + <name>.sheet.json next to each .gif
# Open Godot editor once after to re-import the new .sheet.png files
```

**Loading (scripts/ui/edit_mode/gif_loader.gd):**
- **Path 1 (fast):** if `.sheet.png` + `.sheet.json` exist → slice into AtlasTextures from PNG
- **Path 2 (slow + auto-convert):** if sheets missing → GDScript LZW decode + write sheet files → next load uses Path 1

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
- **Six managers share `user://save.cfg`** (GameManager, UpgradeManager, EquipmentManager, WeaponManager `[weapons]`, DefenseManager `[defense]`, InventoryManager `[inventory]`); each rewrites only its own section (e.g. `erase_section("weapons")` then rewrite) — safe as long as sections stay distinct
- `project.godot` `[autoload]` has merge-conflicted twice on the autoload list; conflict markers there make Godot fail to open the project. Required set (no dups, in order): AudioManager, MaterialManager, DefenseManager, EquipmentManager, UpgradeManager, GameManager, WeaponManager, AffixManager, InventoryManager

## Layout Config Files Workflow

### Files Overview

| File | Purpose | When updated |
|------|---------|--------------|
| `res://default_layout.cfg` | Current/working layout state | Auto-saved when user clicks "Save" in F4 |
| `res://preset_layout.cfg` | Reset baseline (F5 loads from here) | Manually copied from default when layout is final |

### Workflow: Adjust Layout → Set as Preset

1. **Open edit mode (F4):** Loads from `default_layout.cfg`
2. **Adjust positions/sizes:** Drag spaceship, weapons, etc.
3. **Click Save:** Writes to `default_layout.cfg` (auto filters thrust objects)
4. **Ready to set as baseline?** Copy `default_layout.cfg` → `preset_layout.cfg`
5. **Press Reset (F5):** Loads from `preset_layout.cfg` (now has new positions)

**Key:** `preset_layout.cfg` is source-of-truth for Reset. Without snapshot, F5 loads stale positions.

### Autoload Disabled

- `_auto_load_group()` in `edit_mode.gd` completely disabled (line 514: early return)
- Objects come ONLY from config files or manual drag/drop
- Folder scanning eliminated to prevent phantom objects

---

## Ship Visual System (`gun_system.gd`)

### Hull Skin Swap

Khi equip/unequip hull, `InventoryManager.inventory_changed` → `_apply_hull_skin()` → swap texture của spaceship EO.

- **`HULL_SKIN_MAP`** — dict-of-dicts: `def_id → {"idle": path, "lean": path, "dash": path}`. Thiếu key `lean`/`dash` → fallback về `SHIP_DEFAULT_LEAN` / `SHIP_DEFAULT_DASH`.
- **Default skins:** `SHIP_DEFAULT_SKIN = "res://assets/screen/Spaceship.png"`, `SHIP_DEFAULT_LEAN = "res://assets/screen/lean.png"`, `SHIP_DEFAULT_DASH = "res://assets/screen/dash.png"`.
- `_hull_skin_path(state: String)` — helper tra cứu path cho state `"idle"/"lean"/"dash"` của hull đang equip.
- **Khi thêm lean/dash cho hull mới:** thêm key `"lean"`/`"dash"` vào entry tương ứng trong `HULL_SKIN_MAP`.

### Ship Asset Folder Structure

```
assets/screen/ship/
  <hull_name>/          ← tên folder = tên ship (vd: adamantium, titanium…)
    <hull_name>.png     ← idle skin
    lean.png            ← lean skin (nếu có, nếu không → dùng default)
    dash.png            ← dash skin (nếu có, nếu không → dùng default)
```

Mapping `def_id` → folder (lưu ý `adamantine_hull` → folder `adamantium`):

| def_id | folder |
|--------|--------|
| `titanium_hull` | `titanium/` |
| `adamantine_hull` | `adamantium/` |
| `aerographene_hull` | `aerographene/` |
| `glass_hull` | `glass/` |
| `neutronium_hull` | `neutronium/` |
| `nanobot_hull` | `nano/` |
| `voidmetal_hull` | `voidmetal/` |
| `pzt_hull` | `pzt/` |
| `memory_foam_hull` | `thorned/` |
| `cursed_hull` | `cursed/` |

### Ship Pose System

Pose được set mỗi frame trong `_handle_ship_movement()`. Texture chỉ load khi pose thực sự thay đổi.

```gdscript
const POSE_IDLE       := 0
const POSE_LEAN_LEFT  := 1   # di chuyển sang trái → lean.png
const POSE_LEAN_RIGHT := 2   # di chuyển sang phải → lean.png + flip_h
const POSE_DASH_LEFT  := 3   # dash sang trái → dash.png
const POSE_DASH_RIGHT := 4   # dash sang phải → dash.png + flip_h
```

- `_set_ship_pose(pose)` — áp texture + `flip_h`, skip nếu pose không đổi.
- Khi `inventory_changed`: `_apply_hull_skin()` reset `_ship_pose = -1` → force reload pose hiện tại với skin mới.
- Intro / `input_locked` → force `POSE_IDLE`.

---

## Overlay — Right Strip Mirror (`scripts/gameplay/overlay.gd`)

### `attach_right_strip(x_pos: float)`

Tạo bản mirror (flip_h) của strip hiện tại tại vị trí x_pos. Phải gọi **sau** `swap_texture()`.

- `_rects_r` — tiles của right strip, cùng `_tile_h` và cùng `_offset` với left strip → scroll đồng bộ.
- `restore_texture()` tự clear right strip.
- `_apply_positions()` cập nhật cả right strip.

### Elephant boss map geometry

```
Left strip:  tile_x = -150, width = 300 → visible x=[0, 150]   (150px overflow left)
Right strip: tile_x =  550, width = 300 → visible x=[550, 700] (150px overflow right)
screen_w = 700
```

### `attach_blob(..., flip_h: bool = false)`

Optional `flip_h` param cho right-side blobs. Blob mirror formula:
```gdscript
bx_r = OC_BOUNDS.size.x - bx - bw   # = 700 - bx - bw
```

---

## Arena System (`scenes/arena.tscn`)

Arena is a **separate, self-contained scene** from `main.tscn` — a Vampire-Survivors-style top-down bullet-heaven mode. It does **not** use `enemy_manager.gd`, `gun_system.gd`, or the individual `enemy_*.gd` scripts. All arena combat logic lives in its own dedicated scripts.

### Key arena scripts

| Script | Role |
|--------|------|
| `scripts/gameplay/arena_enemy.gd` | Data-driven enemy behavior engine (all enemy types in one script) |
| `scripts/gameplay/arena_wave_director.gd` | Authored timeline spawner — fires enemies at scripted timestamps |
| `scripts/gameplay/arena_weapons.gd` | Player weapon system (Gatling etc.) specific to arena |
| `scripts/gameplay/arena_debug_spawn.gd` | Debug UI: fire rate +/− buttons, barrel count display, + Level button |
| `scripts/ui/hud/arena_levelup_ui.gd` | Level-up card UI (pause + pick 1-of-3 upgrade) |

**IMPORTANT:** Fixes to `enemy_dragonfly.gd`, `enemy_swarm.gd`, etc. do **NOT** affect the arena game. To fix arena enemy behavior, edit `arena_enemy.gd`.

### `arena_enemy.gd` — behavior system

Each enemy has a `behavior` string from `ENEMY_DEFS` in `arena_wave_director.gd`. Key behaviors:

| Behavior | Enemy | Notes |
|----------|-------|-------|
| `"orbit"` | dragonfly | **Known bug:** orbit center snaps to player each frame — player cannot escape. Not yet fixed. |
| `"spiral"` | diver | Fixed (2026-06): uses `SPIRAL_CENTER_SPEED = 80px/s` drift + aim-once straight dive when `_orbit_r <= 8` |
| `"swarm_dive"` | bee, swarm | Chase + dive |
| `"chase"` | bug | Direct pursuit |
| `"scatter"` | fly | Random wander |
| `"jump"` | octopus | Pause → aim-once → leap |
| `"jump_diag"` | spider | 45° diagonal jumps only |
| `"shooter"` | jet fighter | Ranged projectiles |
| `"boss_stub"` | elephant, chromeleon, metalfly | High-HP, slow, no real moveset yet |

**Spiral fix — two phases:**
```gdscript
# Phase 0: orbit center drifts toward player at SPIRAL_CENTER_SPEED px/s
_scatter_target = _scatter_target.move_toward(pp, SPIRAL_CENTER_SPEED * delta)
# Phase 1 (when _orbit_r <= 8): aim-once straight dive
_aim = dir  # captured once; player can now dodge
```

**Sprite sheet animation:** `_load_icon()` auto-detects `.sheet.png`, calls `_load_sheet_frames()` which reads the adjacent `.sheet.json` (cols, fw, fh, delays), slices `AtlasTexture` per frame into `_frames`/`_delays`.

### `arena_wave_director.gd` — ENEMY_DEFS & boss icons

All enemy types defined in `ENEMY_DEFS`. Boss stubs now use real sprite sheet icons:
```gdscript
"elephant":  {..., "icon": "res://assets/bosses/elephant/elephant.sheet.png"},
"chromeleon":{..., "icon": "res://assets/bosses/chromeleon/chromeleon.sheet.png"},
"metalfly":  {..., "icon": "res://assets/bosses/metalfly/metalfly.sheet.png"},
```

### `arena_weapons.gd` — Gatling multi-barrel

`GAT_BARREL_SPACING = 18.0px`. `num_barrels = maxi(1, floori(shots_per_sec / 10.0))`. Barrels placed perpendicular to the forward direction:

| shots/sec | barrels |
|-----------|---------|
| 10–19.9 | 1 |
| 20–29.9 | 2 |
| 30–39.9 | 3 |
| 40+ | 4+ |

### `arena_debug_spawn.gd` — debug controls

Bottom-center HBox (CanvasLayer). Controls:
- `[−]` / `[+]` — adjust `GameManager.upg_fire_rate_mult` by `FR_STEP = 0.5`
- Label (updated every `_process`): `"Fire: X.X/s  |  N barrel(s)  |  ×X.XX"`
- `[+ Level]` — adds enough XP to trigger the next level-up

`GAT_INTERVAL = 0.09` mirrors `arena_weapons.gd GAT_FIRE_INTERVAL` — keep in sync if changed.

### `arena_levelup_ui.gd` — level-up card UI

**Layout:** `CenterContainer` → `Control 720×390` panel → `TextureRect TEX_FRAME` (full panel bg, `assets/hud/lvupframe.png`).

**Card bg by upgrade category** (`assets/hud/lvgreen/red/blue.png`):
- Green: `hp`, `hp_regen`, `pickup`
- Red: `fire_rate`, `damage`
- Blue: `defense`, `move_speed`, `momentum`

**Card icons:** `res://assets/hud/<id>.png` — id must match the upgrade `id` string exactly.

**Card size:** 160×208. `_cards_box` is a plain `Control` (NOT `HBoxContainer`) — outer cards shift ±20px horizontally via `_CSHIFT`. **Using `HBoxContainer` here causes a runtime type-assign error.**

**Title label:** font = `Good Old DOS.ttf`, color `#9bfdb0`, size 22. Anchors top=0.035/bottom=0.155 + offset_top=30/offset_bottom=30/offset_left=−10/offset_right=−10.

### `enemy_dragonfly.gd` — non-arena fix

Fixed with Option B (`DF_ORBIT_CENTER_SPEED = 80px/s` drift, aim-once dive). This file is used only by `enemy_manager.gd` (non-arena waves). The arena dragonfly ("orbit" behavior in `arena_enemy.gd`) still has the snap bug.

---

## Enemy Panel (`scripts/ui/hud/enemy_panel.gd`)

6-tab panel (Animal / Human / Alien / Asteroid / Boss / Other). **GRID_COLS = 7** (7 thumbnails per row, wraps tự động).

**TAB_ENEMIES** — format `[display_label, spawn_key, icon_path, spawn_group]`:

| Tab | Enemies |
|-----|---------|
| Animal | Diver, Bombing wanderer, Swarm, Bee, Bug, Centipede, Dragonfly, Flies, Octopus, Spider |
| Human | Shooter, Beamer, Missile launcher, Royal, Royal Fighter, Royal Scout, Royal Tanker, Pirate Leader, Pirate Ork, Pirate Spear, Pirate SpearShield |
| Alien | Sentinels, Cruiser, Crystal, Egg, Fighter, Plate, Scout, Tree |
| Boss | Elephant, Chromeleon, Metalfly, Nautilus |
| Other | Dummy (`dummy.png`), Bomb |

Spawn keys **đã implement** trong `enemy_manager`: `spawn_bee/bug/centipede/dragonfly/flies/octopus/spider` (Animal group — xem Animal Enemy Group section).

Spawn keys **chưa implement**: `spawn_royal/royal_fighter/royal_scout/royal_tanker`, `spawn_pirate_leader/ork/spear/spear_shield`, `spawn_alien_cruiser/crystal/egg/fighter/plate/scout/tree`.

Image assets tại `assets/enemies/`: prefix `animal*`, `alien*`, `royal*`, `pirate*`, `dummy.png`.

---

## Normal Enemy System

### `enemy_base.gd` — base class

- **Size**: `_diameter_for_hp(hp_max) * size_mult` → square, sau đó nếu có texture thì height được kéo khớp ratio: `size.y = size.x * tex_h / tex_w`.
- **`size_mult: float = 1.0`** — set trong `_configure()` để scale size riêng per-enemy (vd: `bomb` = 0.5).
- **`icon_path: String = ""`** — set trong `_configure()`. Nếu != "" → load texture, override height theo ratio.
- **`_draw()`**: nếu có texture → `draw_texture_rect` + white flash overlay khi hit. Nếu không → placeholder shape (circle/triangle/diamond/square) + flash.
- HP bar vẫn hiển thị ở cả 2 trường hợp.
- **`_hp_mult: float = -1.0`** — per-enemy HP multiplier override. `-1` = dùng global `ENEMY_HP_MULT = 1.5`. Set `_hp_mult = 1.0` trong `_configure()` để bypass global mult (dùng cho Animal enemies với HP đã = effective HP từ PDF).

### Enemy assets (`assets/enemies/`)

| Enemy | File | shape_kind | size_mult |
|-------|------|-----------|-----------|
| Kingfisher | `kingfisher.png` | triangle | 1.0 |
| Jet Fighter | `jetfighter.png` | triangle | 1.0 |
| Sentinel | `sentinel.png` | diamond | 1.0 |
| Bombing Wanderer | `bombing.png` | square | 1.0 |
| Bomb | `bomb.png` | circle | **0.5** |
| Swarm | `swarm.png` | triangle | 1.0 |

### Animal Enemy Group — Architecture

7 enemies + 3 flock orchestrators, tất cả trong `scripts/gameplay/`.

**Solo enemies** (có `spawn(mgr)` tự chọn vị trí vào):

| Script | HP | XP | Contact DMG | Behaviour |
|--------|----|----|-------------|-----------|
| `enemy_centipede.gd` | 240 | 24 | 20 | Rotate 120°/s, tiến thẳng về player 100px/s, vào từ cạnh ngẫu nhiên |
| `enemy_dragonfly.gd` | 90 | 10 | 10 | ENTRY → SPIRAL (orbit thu hẹp 180→32px) → DIVE 160px/s |
| `enemy_octopus.gd` | 240 | 24 | 20 | WAIT 1s → JUMP aim-once smoothstep 600px/s range 200px |
| `enemy_spider.gd` | 60 | 8 | 8 | Như Octopus nhưng chỉ nhảy theo 4 góc 45° |

**Flock pairs** (orchestrator + member):

| Orchestrator | Member | Count | Behaviour |
|---|---|---|---|
| `enemy_bee_flock.gd` | `enemy_bee.gd` (HP 20) | 12 (4×3) | Form → Hold 0.4s → DIVE_ROW top-to-bottom, stagger 0.2s/member |
| `enemy_bug_flock.gd` | `enemy_bug.gd` (HP 15) | 16 (4×4) | Form → Hold → EXPAND sideways → DIVE |
| `enemy_flies_flock.gd` | `enemy_fly.gd` (HP 10) | 20 (ring 8+12) | Self-driven scatter, random target 1s interval |

**Flock spawn pattern** (cả 3 orchestrators dùng chung):
- Tính `_spawn_origin` = điểm ngẫu nhiên trên vòng tròn `radius = half_screen_diagonal + 100px` quanh `ship_center()`
- Queue toàn bộ members, release lần lượt với interval 0.08–0.12s (không overlap)
- State machine: `SPAWNING → FORMING → HOLD → DIVE_ROW → DONE`

**GDScript type inference gotcha trong enemy scripts**: `_mgr` typed là `Node` nên `_mgr.ship_center()` trả về `Variant`. Dùng `var x: Vector2 = _mgr.ship_center()` (explicit annotation), KHÔNG dùng `:=` (sẽ lỗi parse).

**Wave timeline**: `choreo_animal_wave.gd` — 4 phases × 30s = 2 phút:
- 0–30s: Flies + Bug (cap 80, rate 1.0s)
- 30–60s: Flies/Bug/Bee/Swarm/Spider + Diver event t=45s (cap 150, rate 0.8s)
- 60–90s: Bee/Swarm/Dragonfly/Spider/Octopus + BombingWanderer event t=75s (cap 250, rate 0.5s)
- 90–120s: full mix + Centipede (cap 400, rate 0.3s)

Registered trong `choreography_registry.gd` key `"Animal_wave"`. Level file: `levels/Level_Animal.json`.

---

## Inventory — Equip Slot Tooltips & Gate Fix

### Slot tooltips

`inventory_ui.gd` set `es.tooltip_text = SLOT_LABELS.get(slot, slot)` ngay sau `es.setup(slot)` → Godot tự hiện tên slot khi hover chuột lên ô trống hoặc ô có item.

### Equip-gate on swap (item_widget.gd)

`_drop_data()` trong `item_widget.gd` (khi drop lên equipped item để swap) giờ kiểm tra `InventoryManager.meets_requirement(def_id)` trước khi gọi `equip()` — giống logic trong `equip_slot.gd`. Không đủ stat → `flash_message` + return (item không bị swap).

---

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

---

## Thrust Objects Policy

**CRITICAL: Thrust objects (auto.gif, manual.gif, thrust.png) behavior locked by design.**

- **Current state (post-2026-06-05):** Thrust GIFs now properly managed in config with controlled visibility
- **Thrust objects are dynamic UI animations** managed by `gun_system.gd` at runtime
- If thrust objects added to power_core in config:
  1. `gun_system._on_spaceship_changed()` finds them and creates animations
  2. Uses `_resize_frame()` to scale GIF frames to object's size
  3. Respects GIF placement in config (not fixed corner position)
- **Auto-load disabled:** Thrust folder no longer auto-places files on F4 group switch
- **Save filter active:** If thrust somehow in weaponry, `_save_layout()` filters them out before save
- **Fix if phantom thrust appears:** Delete entries with path `res://assets/sprites/thrust/*` from config, or verify autoload is disabled (`edit_mode.gd:514`)
