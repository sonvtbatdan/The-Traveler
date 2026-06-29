# Dev Mode — Editors & Debug Tools

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on F4 edit mode, F6 HUD edit, layout configs, creep/fleet/wave editors, arena debug spawn.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

> Creep / Fleet (dev button) / Wave (F7) editor specifics are documented in the 2026-06-29 changelog in [`enemy.md`](enemy.md).

## Edit Mode & Dev Tools

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

### `scripts/ui/edit_mode/editable_object.gd`

- `EditableObjectNode` (`class_name`) — every in-canvas placed sprite.
- `group_id: String` — one of `"screen" | "weaponry" | "defense" | "power_core" | "user"`.
- `_gameplay_mode: bool` — edit handles vs gameplay click routing.
- Displays resource price label (`_price_label`) in edit mode showing material cost (e.g. "100 Nonmetal").
- `group_id == "screen"` → invisible in gameplay (`visible = false`); scrolling background system handles rendering.

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

## Arena Dev Tools (`scripts/gameplay/arena_debug_spawn.gd`)
### `arena_debug_spawn.gd` — debug controls

Bottom-center HBox (CanvasLayer). Controls:
- `[−]` / `[+]` — adjust `GameManager.upg_fire_rate_mult` by `FR_STEP = 0.5`
- Label (updated every `_process`): `"Fire: X.X/s  |  N barrel(s)  |  ×X.XX"`
- `[+ Level]` — adds enough XP to trigger the next level-up

`GAT_INTERVAL = 0.09` mirrors `arena_weapons.gd GAT_FIRE_INTERVAL` — keep in sync if changed.

**Dev mode default state (2026-06-20):** `const DEV_MODE := false` — panel starts hidden. `arena_hud_buttons.gd` shows `dev:off` icon at game start (clicking toggles to `dev:on` and reveals firerate/level controls). Changed from `true` → `false` so players don't see debug controls by default.

### `arena_debug_spawn.gd` — Quick Spawn panel (2026-06-21)

Panel added to `_dev_ui_root` (bottom-left, 192×242px). Only visible when Dev:on.

**Layout:**
- Header: "Quick Spawn" label + "CLEAR ALL" button — each `SIZE_EXPAND_FILL`, row height 50px
- Grid: `GridContainer` 4 columns × 48×48px cells inside `ScrollContainer` (4 rows visible = 192px height; scroll reveals row 5)

**Enemy order** (`QUICK_SPAWN_ORDER` const): fly, bee, bug, swarm, diver, dragonfly, octopus, spider, centipede, shooter, sentinel, beamer, bomber, missile, dummy → then bosses: elephant, chromeleon, metalfly. Bosses get red background cells.

**Thumbnails:** loaded via `_load_thumb(icon)` — GIF path → `GifLoader.load_gif()` frame 0; PNG → `load()`. Source: `WaveDir.ENEMY_DEFS[type_id]["icon"]`.

**Spawn:** random position in viewport (`camera.global_position ± 500/270px`). Enemy added as sibling of `wave_director` (same parent as other arena enemies). Tagged with group `"quick_spawn_enemy"`.

**CLEAR ALL:** removes only enemies in group `"quick_spawn_enemy"`.

**Key preloads at top of file:**
```gdscript
const GifLoader   := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const WaveDir     := preload("res://scripts/gameplay/arena_wave_director.gd")
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
```

