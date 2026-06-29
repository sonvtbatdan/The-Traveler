# Weapon — Combat, Inventory & Arena Weapons

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on weapons, firing, inventory/affixes, ship visuals, arena weapon mechanics + their VFX.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

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

## Inventory — Equip Slot Tooltips & Gate Fix

### Slot tooltips

`inventory_ui.gd` set `es.tooltip_text = SLOT_LABELS.get(slot, slot)` ngay sau `es.setup(slot)` → Godot tự hiện tên slot khi hover chuột lên ô trống hoặc ô có item.

### Equip-gate on swap (item_widget.gd)

`_drop_data()` trong `item_widget.gd` (khi drop lên equipped item để swap) giờ kiểm tra `InventoryManager.meets_requirement(def_id)` trước khi gọi `equip()` — giống logic trong `equip_slot.gd`. Không đủ stat → `flash_message` + return (item không bị swap).

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


## Arena Weapons (`scripts/gameplay/arena_weapons.gd`)
### `arena_weapons.gd` — Gatling multi-barrel

`GAT_BARREL_SPACING = 18.0px`. `num_barrels = maxi(1, floori(shots_per_sec / 10.0))`. Barrels placed perpendicular to the forward direction:

| shots/sec | barrels |
|-----------|---------|
| 10–19.9 | 1 |
| 20–29.9 | 2 |
| 30–39.9 | 3 |
| 40+ | 4+ |

### `arena_weapons.gd` — Crit System (2026-06-20)

- `const BASE_CRIT_CHANCE := 0.10` — 10% base crit chance at game start, additive with `GameManager.get_crit_chance()` from upgrade cards. Without this, upgrading "crit damage" (multiplier) had no effect because default chance was 0%.
- `_crit_chance = BASE_CRIT_CHANCE + (GameManager.get_crit_chance() if GameManager.has_method("get_crit_chance") else 0.0)` — refreshed on every upgrade pickup.
- `_roll_damage(base: float) -> Dictionary` returns `{"dmg": float, "is_crit": bool}` (changed from plain `float`).
- `_spawn_crit_number(world_pos: Vector2, amount: float)` — spawns a floating Label in a CanvasLayer (layer 12) at screen-space coords via `get_viewport().get_canvas_transform() * world_pos`. Style: red fill `Color(1.0, 0.15, 0.10)`, white outline (size 7), font `Gameplay.ttf` at 22px, scale ×1.6. Tweens: rise 48px over 0.8s, fade out, then `queue_free()`.
- All three weapons (Gatling, Arc, Lasgun) call `_spawn_crit_number()` when `is_crit == true`.

### `arena_weapons.gd` — Arc lightning (textured, from the 2D-lightning tutorial)

The Arc (chain lightning) **visual** is textured `Line2D` bolts (the 2D-lightning-tutorial technique), NOT
immediate-mode polylines. `_fire_arc`'s damage/chain logic is unchanged; only the rendering. Per chain link,
`_spawn_arc_bolt(a, b, delay)` builds a small `bolts` list via `_make_bolt_line` (each `{ln, mat}`): a **main**
strand + a thin **secondary** companion (`ARC_SECONDARY_FRAC` 0.4, same jagged path nudged `±ARC_STRAND_GAP` perp
via `_offset_points`, + a texture `phase` offset so it crackles out of phase). `_arc_line_points` = a jagged path
(random perp kinks per point, `amp = dist*0.1`). Each bolt is a `Line2D` (width `ARC_BOLT_WIDTH`, `STRETCH`) with
`scripts/gameplay/fx/arc_lightning.gdshader` + a **procedural tileable thunder texture** (`_make_thunder_tex` — a
CONTINUOUS bright jagged centreline that always peaks at 1.0 along its length + a soft glow halo; **h=64 so the
bright band is well-resolved**).
**The CONTINUITY rule (hard-won):** the white core is `pow(t, ARC_CORE_SHARP)` — a SMOOTH continuous function of
the texture brightness, NOT `smoothstep(threshold, …)`. A threshold is on/off, and combined with a sub-pixel-thin
bright band it only lit where the jittering centreline landed on a texel row → the core broke into DASHES. A
`pow` core fades smoothly from the bright centreline → an unbroken line. So: body = `color * t*keep` (soft blue
`ARC_HDR_COL`), core = `core_color * pow(t,core_sharp) * keep` (HDR white-blue `ARC_CORE_COL`), additive, blooms.
`scroll_speed = 0` (static, generated once per shot). `_tick_arcs` animates each bolt's `vanishing_value`
(per-link `delay` → outward sweep) and frees the `Line2D`s at `ARC_LIFE`; `_fire_arc` calls `_clear_arcs()` on a
new burst so shots REPLACE the old arc (no stacking). Each strike point spawns `_spawn_arc_sparks`. `get_lights()`
reads each link's `tip` for dust illumination. Tunables: `ARC_BOLT_WIDTH`, `ARC_THUNDER_UNIT`,
`ARC_SECONDARY_FRAC`/`ARC_STRAND_GAP`, `ARC_CORE_SHARP` (core thinness), `ARC_HDR_COL`/`ARC_CORE_COL`/`ARC_LIGHT`.
RULE: never bake a thin bright feature sub-pixel into a low-res texture, and prefer a smooth `pow` over a
threshold for a continuous core. (History: was briefly widened to a 216px branched/forked beam — reverted to this
clean continuous single-bolt-per-link on request.)

### `arena_weapons.gd` — Z-Sword slash (layered, "VFX Anatomy: Slash")

The Z-Sword **visual** is a sweeping energy-slash CRESCENT, not the old radial line (`_draw_zsword` removed).
`scripts/gameplay/fx/z_slash.gd` (`class_name ZSlash`) is an additive Node2D child of `arena_weapons` (created
in `_ready`, typed `Node2D` and called dynamically — do NOT type by `ZSlash` or a fresh-class-name boot fails).
`_tick_zsword` drives it: each frame `set_sweep(center, reach, _zsword_start, blade_ang)`; on each enemy hit
`add_spark(pos)`; on sweep end `fade_out()`. Preview: `scenes/test_slash.tscn` (F6 → plays a sweep, replays on
Space; draws a glow env + white grid so the bloom and the distortion layer are visible). The whole thing is
**additive HDR** (`CanvasItemMaterial` ADD) so it blooms under the arena WorldEnvironment.

**Reworked to a blue-white CRESCENT BLADE** after a detailed crit (the prior green version read as a uniform
"neon tube"). Palette is **white core → cyan body → blue glow → faint violet** (no green). Layers (`_draw`,
back→front):
- **Width curve** `_w(p)= peak·pow(4p(1-p),0.55)` — the crescent is thin at both ends and thick in the MIDDLE,
  tapering to a SHARP point at the leading tip (not a constant-width tube). `BODY_PEAK 46` (big, per "scale").
- **Blue bloom aura** — a wide soft crescent (`BLOOM_PEAK`, `GLOW_COL`, low alpha), strongest toward the lead.
- **Cyan body** — translucent crescent (`BODY_COL`, `BODY_ALPHA 0.5`) — you see the background through it.
- **Ghost streaks** (`_draw_ghosts`) — `GHOST_COUNT` thin polylines at different radial offsets, parallel to the
  arc, broken into fragments (sine gaps), white-blue, lead-bright = speed lines (not curly rainbow noise).
- **Hard cutting edge** (`_draw_cutting_edge`) — a thin near-overexposed line riding the crescent's OUTER
  boundary (`radius + _w(p)`), `EDGE_COL`→`CORE_COL` toward the lead = the bright sharp blade edge.
- **Lead bloom** (`_draw_lead_bloom`) — concentric blue→violet→cyan→white circles at the leading edge (impact mass).
- **Origin wisp** (`_draw_origin_wisp`) — a faint thin tapered quad + small flash from the ship → keeps it
  attached WITHOUT the old rigid bright tube ("hide the emitter" crit).
- **Shards** (`_emit_shard`/`_draw_shards`) — drawn (not particle nodes) white-blue fragments stretched along
  their velocity, trailed off the leading edge during the sweep (direction cue) + a burst per hit (`add_spark`);
  they outlive the body fade. No `CPUParticles2D` here → no scale_amount footgun.
- **Distortion (layer 4)** — `z_slash_distort.gdshader` on a fullscreen `CanvasLayer` (`DISTORT_LAYER 79`),
  `_update_distort` feeds it the arc band (PIXEL space, aspect-correct) from the world centre/radius/`_lead`/span;
  low `aberration` (0.2) to avoid rainbow. Caveat (like the explosion shockwave): invisible on a flat background
  and the CanvasLayer ripples everything below it.
Tunables: `SPAN`/`BODY_PEAK`/`BLOOM_PEAK`/`GHOST_COUNT`/`EDGE_W`/`SHARD_*`, palette `CORE_/EDGE_/BODY_/GLOW_/
GHOST_/SHARD_/VIOLET_COL`. **Lessons:** `CPUParticles2D.scale_amount` is a texture-size MULTIPLIER (~0.8 on a
64px tex; 24 = a ~1500px blob); **don't redefine `PI`/`TAU` in a shader** (built-in → compile error); and for a
sword slash, build a varying-width CRESCENT (thin→thick→sharp) in blue-white, NOT a uniform tube — a constant
half-width additive band reads as a glowing noodle. The scythe HIT's expanding *veil* is still an unbuilt upgrade
in the `slash-technique` memory note.

### `arena_weapons.gd` — SFX

| Const | File | Trigger |
|-------|------|---------|
| `SFX_ENGINE_HUM` | `sfx/enginehum3.wav` | Always-on engine hum — loops via `finished` signal, stops when `ship_hp <= 0`, restarts on `_on_ship_hp_changed`. `PROCESS_MODE_PAUSABLE` → tự pause khi game paused. |
| `SFX_GAUSS_FIRE` | `sfx/hitimpact.wav` | Gauss cannon fires (once per shot) |
| `SFX_GAUSS_IMPACT` | `sfx/AstroMenace-SFX/weaponfire6.wav` | Gauss orb hits an enemy or ruin |
| `SFX_LASGUN_CHARGE` | `sfx/Scifi/blg_beam_01.wav` | Lasgun charge phase bắt đầu (one-shot, guarded by `_las_charge_started`) |
| `SFX_LASGUN_BEAM` | `sfx/AstroMenace-SFX/weaponfire14.wav` | Lasgun beam firing — restarts nếu WAV kết thúc trước khi beam tắt (guarded by `_las_beam_playing` flag) |

**`arena_elephant.gd` M5 SFX:** `SFX_M1 = preload("res://assets/audio/sfx/blob.wav")` (Shoot Blob move).

**Asset folder note:** `AstroMenace-SFX/` nằm ở `assets/audio/sfx/AstroMenace-SFX/` (không phải `sfx/Scifi/AstroMenace-SFX/`).

### `arena_weapons.gd` — Weapon tuning constants (as of 2026-06-25)

| Const | Value | Notes |
|-------|-------|-------|
| `BOOM_SPIN` | `12.566` rad/s | Aliwa self-spin = 120 RPM (4π) |
| `SNAKE_SPACING` | `25.2` px | = `BODY_SEG_PX` → zero gap between body segments |
| `YARI_TURN_RATE` | `120/60 × TAU` rad/s | 120 RPM — shared by both Yari Jaeger and Yari (moroboshi) |
| `MORO turn` | uses `YARI_TURN_RATE` | `_moro_facing` clamped by `angle_difference + clampf` instead of instant snap |

### `arena_weapons.gd` — Gauss orb visuals

- `GAUSS_ORB_DRAW = 38.0` px — kích thước hiển thị trên screen (TextureRect 38×38). Frame nguồn là ~421px nhưng được scale về 38px.
- `GAUSS_TRAIL_WIDTH = 0.75` — hệ số nhân bán kính trail circle (`base_w = GAUSS_RADIUS × GAUSS_TRAIL_WIDTH`). Giảm để trail nhỏ hơn, bớt "vòng sáng" quanh orb.
- **Trail và charge rings dùng gradient layers** — mỗi vị trí trail vẽ 4 circle lồng nhau (outer soft → inner bright) với `antialiased=true`. Charge rings tương tự 4 arc layers. Đây là cách mô phỏng soft/glow edge trong Godot 4 CanvasItem `_draw()` (không có built-in blur).

### `arena_weapons.gd` — Generic Plume Registry (2026-06-25)

Replaces 9 per-weapon load/update functions (~390 lines) with a single generic system (~90 lines).

**API:**
```gdscript
var _plume_registry: Array = []   # [{cfg_key, count, ds, provider, anchors}]

func _register_plume(cfg_key: String, count: int, ds: Vector2, provider: Callable) -> void
func _load_all_plumes() -> void   # call once in _ready() after all registrations
func _update_all_plumes() -> void # call once per frame in _process()
```

**How it works:**
- `_register_plume()` adds a weapon entry with a `provider` Callable that returns `Array[{pos, rot, visible}]`
- `_load_all_plumes()` reads `weapon_layout.cfg` [thrustpoints] and `weapon_plume_styles.cfg` [styles] in ONE pass for all registered weapons. Creates `count` anchor Node2Ds each with CPUParticles2D children at TP frac offsets.
- `_update_all_plumes()` calls each provider, moves anchors to returned world positions + rotations.

**Adding a new weapon plume:** add TPs in `weapon_layout.cfg` + styles in `weapon_plume_styles.cfg`, then one `_register_plume()` call in `_ready()`. No new functions needed.

**Kept separate (too complex for generic pattern):**
- Snake (`_load_snake_plume` / `_update_snake_plumes`) — multi-segment chain physics
- Para cloud (`_load_para_plume_data` / `_make_para_cloud_plume`) — dynamic lifecycle (created/freed per cloud)

**`local_coords = false` in `_make_orbital_plume()`:** All plumes use world-space particles. When a weapon rotates or changes direction, previously emitted particles continue on their old trajectory (inertia) while new particles emit in the new direction — physically correct curving trail. Setting this to `true` makes plumes rigidly rotate with the weapon (wrong).

### `arena_weapons.gd` — Spore (Parasite Cloud) Mechanics (2026-06-25)

**Gas cloud VFX on expire:** When a spore's `age >= PARA_LIFETIME`, instead of disappearing silently it spawns `PARA_GAS_PUFF_N = 7` DynamicFire puffs (1 centre + 6 on ring at `PARA_RADIUS × 0.55`) at its final position. These live for `PARA_GAS_LIFETIME = 4.0s` and render via `_para_gas_fx: DynamicFire` (green→purple, `intensity=0.15`). The circle drawn by `_draw_para_cloud()` has `alpha=0.0` — players see only the gas cloud, not the circle.

**Facing freeze fix:** Cloud dict has `"ang"` key (initialized to launch direction angle). Updated each tick only when `vel.length_squared() > 1.0` — freezes on last valid velocity direction instead of snapping to `angle=0.0` when decelerated. `_draw_para_cloud()` uses `c.get("ang", 0.0)` for sprite rotation.

### `arena_weapons.gd` — Auto-fire logic

**`_has_enemy_on_screen() -> bool`:**
- Trả `true` ngay nếu `GameManager.is_boss_alive()` (boss luôn kích hoạt auto-fire bất kể vị trí)
- Dùng `get_viewport().get_canvas_transform()` convert world pos → screen pos
- Rect kiểm tra = viewport rect được mở rộng 50% mỗi cạnh (`grow_individual(vp_size.x * 0.5, vp_size.y * 0.5, ...)`) — tổng diện tích gấp 4 lần screen

**Behavior khi không có enemy:**

| Weapon | Behavior |
|--------|----------|
| Gatling | Tích `_gat_acc` bình thường, không gọi `_fire_gatling()` → bắn ngay khi enemy xuất hiện |
| Gauss | Charge đến full (`_gauss_charge` vẫn tăng), giữ nguyên, fire ngay khi enemy xuất hiện |
| Arc | Skip `_fire_arc()` — `_arc_cd` vẫn tick |
| Lasgun | Dừng `_fire_lasgun(delta)` → `_las_t` không advance (cycle paused); tắt beam visuals + audio |

