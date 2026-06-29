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

## 📂 Module Map — đọc đúng file cho từng việc

CLAUDE.md này (router) luôn được đọc mỗi session. Chi tiết từng hệ thống nằm trong `docs/`. **Khi làm một mảng, mở đúng module bên dưới** thay vì đọc cả project (tiết kiệm token):

| Bạn đang làm... | Đọc file |
|-----------------|----------|
| Weapon / firing / inventory / affixes / ship visual / arena weapons (+VFX của vũ khí: arc, z-sword) | [`docs/weapon.md`](docs/weapon.md) |
| Enemy / boss / wave / arena enemy / ruin / enemy panel | [`docs/enemy.md`](docs/enemy.md) |
| VFX chung: scrolling bg, sprite-sheet/GIF, dynamic fire, explosion, plume, thrust, rescale | [`docs/vfx.md`](docs/vfx.md) |
| Upgrade / defense track / equipment / level-up cards | [`docs/upgrade.md`](docs/upgrade.md) |
| Edit mode (F4) / HUD edit (F6) / creep·fleet·wave editor / debug spawn | [`docs/dev_mode.md`](docs/dev_mode.md) |
| Autoloads / main scene / GameManager / persistence / main menu / settings / music player | [`docs/core.md`](docs/core.md) |

> Bản đầy đủ trước khi tách: `CLAUDE.md.full.bak` (giữ để tra cứu, có thể xoá khi ổn định).

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
- **Git commit — LUÔN commit full project:** Trước mỗi commit, chạy `git status` và `git ls-files --others --exclude-standard` để kiểm tra untracked files. Nếu có file mới (assets, scripts, imports...) phải `git add` tất cả trước khi commit — không được để sót file nào. Dùng `git add assets/ scripts/ scenes/` (theo folder) hoặc `git add -A` nếu cần, sau đó review lại `git status` trước khi `git commit`.


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


## Rendering & Image Rules

### Aspect Ratio — QUY TẮC BẮT BUỘC

**KHÔNG BAO GIỜ stretch ảnh.** Mọi ảnh phải giữ đúng ratio gốc (width/height từ texture).

**Pattern chuẩn — scale theo width:**
```gdscript
var tex_w := float(tex.get_width())
var tex_h := float(tex.get_height())
var display_w := 60.0                          # width mong muốn
var display_h := display_w * tex_h / tex_w    # height tính từ ratio
var sz := Vector2(display_w, display_h)
```

**Pattern chuẩn — scale theo height:**
```gdscript
var display_h := 80.0
var display_w := display_h * tex_w / tex_h
var sz := Vector2(display_w, display_h)
```

Áp dụng cho: TextureButton (custom_minimum_size), TextureRect (size), EditableObjectNode (init size), SpinBox W↔H (aspect-lock), bất kỳ node nào hiển thị ảnh.

**TextureButton:** dùng `ignore_texture_size = true` + `stretch_mode = STRETCH_SCALE` → Godot scale ảnh vào vùng `custom_minimum_size`. Luôn tính `custom_minimum_size` từ ratio để không bị méo.

---

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


