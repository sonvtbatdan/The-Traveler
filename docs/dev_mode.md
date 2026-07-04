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

### `scripts/ui/boss_edit/hud_edit_mode.gd` (HUD Edit — Devon panel "Asset 41" button)

> Khác hẳn F6 `hud_edit_overlay.gd` ở trên (cái đó drag widget HUD có sẵn). Đây là editor **standalone** (extends CanvasLayer, KHÔNG subclass creep) để dựng Player-HUD từ **GROUPS**.

> **2026-07-02 — generic board editor:** file này giờ author nhiều "board" (HUD, Level Up…) qua dropdown "Board:". Runtime từng board tách ra `scripts/ui/boards/<x>_binder.gd`; registry ở `board_defs.gd`. Xem [`hud.md` §11](hud.md).

**Mô hình dữ liệu** (lưu `res://config/boards/<board>.cfg`, section `[hud] groups`):
- `_groups: Array` — danh sách nhóm có thứ tự; **index 0 = trên cùng panel = Z cao nhất**.
- Mỗi group = `{name, children: Array}`. Mỗi child có `id` duy nhất (`_next_id`), `type` = `"item"` hoặc `"text"`.
  - item: `file` (basename trong Playerhud), `pos`, `size`, `blend`.
  - text: `text`, `font` (basename trong assets/fonts), `font_size`, `color`, `outline_color`, `outline_size`, `align`, `pos`.
- `_nodes: {id → node}` — node sống trên canvas: **item = `EditableObjectNode`** (drag/resize + blend), **text = inner class `_HudText`** (Label kéo được, không resize — size theo font).
- `_reassign_z()`: duyệt group trên→dưới, child trên→dưới, gán `z_index` giảm dần từ `Z_TOP=240`.

**Panel trái GROUPS** (ScrollContainer — cuộn khi dài): nút `+` tạo group. Mỗi `_GroupRow` có: grip `≡` (kéo đổi thứ tự = Z), nút **khóa** `□`/`■` (`_toggle_group_locked` — group khóa: không select/move/resize, child non-interactive trên canvas + không drag/RMB; chỉ caret + nút khóa còn hoạt động), nút **caret** `▾`/`▸` (`_toggle_group_collapsed` — xổ/thu child rows). LMB lên group = `_select_group`. RMB group → Copy/Rename/Delete/Add Text (chặn khi khóa). RMB child (`_ChildRow`) → Copy/Delete. Drag-drop (`_get_drag_data`/`_can_drop_data`/`_drop_data`): kéo group đổi Z, kéo child trong/giữa group (`relocate_child` — **đặt tên này thay vì `move_child` vì trùng `Node.move_child`**), kéo `_PaletteCell` từ ITEMS vào group/child (`drop_item_file`, instance mới).

**Chọn group → move/resize cả nhóm qua ô X/Y/W/H** (panel phải): `_group_bbox(gi)` tính bounding-box từ node sống; X/Y = `_move_group_to` (dời delta toàn bộ children), W/H = `_scale_group_by_w/h` → `_scale_group` (scale ĐỀU pos+size mỗi child, text scale `font_size`, quanh góc trên-trái box; khóa tỉ lệ). Selection group ⟷ child loại trừ nhau (`_sel_group` vs `_sel_id`).

**Child row:** nút **mắt** `●`/`○` (`_toggle_child_visible` → `visible` per-child, ẩn cả trong gameplay) + grip `≡` kéo đổi Z nội bộ. **Opacity slider** (Transform, panel phải) → `opacity` per-child; với item set `texture_rect.modulate.a` (KHÔNG set EO root — `set_gameplay_mode` reset root `modulate.a=1` ở edit mode), với text set node `modulate.a`. Group được chọn: opacity slider bulk-apply cho mọi child.

**RUNTIME HUD BINDING (playerhud wired vào game):** `hud_edit_mode.gd` vừa là editor (khi mở) vừa là **HUD thật** (khi đóng) — `_process` gọi `_update_bindings()` khi `not _is_open`. `_build_runtime_bindings()` (gọi ở `setup()` + `_close()`) resolve node theo group/file/sentinel-text + tạo node runtime-only (icon weapon/aux, thanh level fill); `_open()` xóa chúng (`_clear_runtime_extras`) + khôi phục text thiết kế (`_restore_design_text`) để sửa. Binding:
> - **Text** (theo giá trị sentinel): "200"→`ship_hp`, "300"→`ship_max_hp`, "50"→`ship_shield`, "100"→`shield_capacity_total()`, "KILL"→`run_kills`, "COIN"→`money`, "LV. 3"→`"LV. %d"%player_level`. Giữ anchor theo `align` (trái/giữa/phải) để số đổi độ rộng không lệch.
> - **HP/Shield/Level bars (VFX, 2026-07-01)**: mỗi thanh = `TextureRect` fill dùng chung `assets/shaders/bar_fill.gdshader`, **mask bằng chính alpha của sprite band** (`texture(TEXTURE,UV).a` — chỉ vẽ lên pixel band có màu, alpha=0 → không vẽ; fill không tràn khỏi silhouette band). Fill đặt trùng rect band (`_make_bar_fill(ch, fill_col, glow_col)`, z = z band). Band resolve theo **filename** ở bất kỳ group nào (`ROLE_FILES`/`BAR_BAND_FILES`): `levelband`=xanh lá (progress=xp%), `HPband`=đỏ (hp/hp_max), `shieldband`=xanh biển (shield/shield_cap). `_set_fill_progress()` set uniform `progress` mỗi frame.
>   - **Band = indicator, chỉ hiện trong HUD Edit** (edit-only): `_set_gameplay(on=true)` ẩn band (`_is_band_node`), fill masked mới là thanh hiển thị lúc chơi. Fill theo eye-toggle của band (`_child_visible`).
>   - **Grow direction**: dropdown "Grow" (panel phải, chỉ hiện khi chọn band) → lưu `ch["grow"]` (0=L→R,1=R→L,2=B→T,3=T→B) → uniform `grow_dir`. Fill là runtime-only nên editor không preview trực tiếp (áp dụng lúc chơi). (Decile-sprite HP/Shield CŨ + `level_fill.gdshader` inset đã bỏ.)
> - **Menu / Inv buttons (2026-07-01)**: group "MENU" (`menubtn`+`menubtnpress`) và "INV" (`invbtn`+`invbtnpress`) → `_setup_press_pair(normal, press, action)`: một `Button` trong suốt phủ lên, mặc định hiện `normal`; `button_down` hiện `…press`, `button_up` về `normal`; `pressed` gọi action. Menu → `_open_menu()` mở settings/menu panel (`get_first_node_in_group("settings_panel")`.`open()` — `arena_hud_buttons` add `_settings` vào group đó). Inv → `_open_inventory()` (`inventory_ui.toggle()`; panel inventory thật làm sau). Cùng cơ chế xử lý cặp legacy `inventory`/`inventorypress` nếu layout còn dùng.
> - **Weapon slot 1-5**: `arena_weapons.acquired_weapons()`; slot trống ẩn cả btn; có weapon → icon (`_icon` qua WEAPON_INFO/`InventoryManager.get_icon`, blend hard-light, z giữa btn và red/green); weapon liên tục (`CONTINUOUS_WEAPONS`) tắt red/green; weapon charge → green khi `weapon_is_firing`, red khi `weapon_cooldown_frac<1` & không firing.
> - **Aux slot 6-10**: `arena_aux.owned_aux()`; passive → chỉ icon; btnyellow luôn ẩn; slot trống ẩn btn.
> - **Level**: `ColorRect` + `assets/shaders/level_fill.gdshader` (sóng xanh + glow) uniform `progress = player_xp/xp_to_next`; chỉ hiển thị, không tự lên cấp.
> - **Equip (legacy)**: cặp `inventory`/`inventorypress` giờ dùng chung `_setup_press_pair` như Menu/Inv ở trên (giữ để tương thích layout cũ; layout hiện tại dùng INV group).
> - **Blend**: btnred=overlay(3), btngreen=screen(1), HP+Shield sprites=screen(1); icon weapon/aux runtime=normal (`_make_slot_icon` _apply_blend_to 0).
> - **Screen-fit**: `_apply_hud_screen_fit()` (gọi sau binding ở setup/_close) scale `objects_container` đều theo `viewport_height / background_height`, ghim top-left panel background vào (0,0) → HUD cao bằng màn hình, sát mép trái. Editor mở thì `_reset_zoom()` về scale gốc (sửa ở toạ độ thiết kế).
> HUD cũ (hud_hp_display/arena_weapon_slots/arena_aux_slots/arena_stats_hud) bị `visible=false` trong `arena._build_ui` (thay thế hoàn toàn).

**Macro regions (2026-07-01) — 4 vùng canh cạnh + animation:** thay cho `_apply_hud_screen_fit` (đã bỏ scale toàn cục). `_build_macros` (gọi cuối `_build_runtime_bindings`, gỡ ở `_clear_macros` khi mở editor) gom member nodes theo `GROUP_MACRO` (group "Text" tách theo `KILLCOIN_TEXTS`) + runtime extras (theo `set_meta("macro_key")`), **reparent** vào 1 `Control` container/vùng rồi anchor container ra cạnh màn hình (pivot = điểm anchor → scale giữ dính cạnh):
> - **Weapon** = Button1-5 + ActiveBar → cạnh trái, giữa dọc. **Aux** = Button6-10 + PassiveBar → cạnh phải, giữa dọc. **KillCoin** = text KILL/COIN + KillBar → cạnh trên, giữa ngang. **LV** = INV/MENU/LevelBarBg/Level/LevelBar + text HP/Shield/LV → cạnh dưới, giữa ngang.
> - **Weapon/Aux** resting = `SHRINK_SCALE` (70%). `_trigger_shrink`: về 100% → chờ `SHRINK_DELAY`(5s) → ease về 70%. Trigger: `GameManager.player_stats_changed` (upgrade) + đếm `acquired_weapons()`/`owned_aux()` tăng (item mới) trong `_update_weapons/_update_aux`.
> - **KillCoin** `_pulse_macro`: pop `PULSE_SCALE`(103%) trong 0.1s rồi về 100%. Trigger: `GameManager.kills_changed` / `money_changed`. Signals hook 1 lần ở `_ready`→`_hook_stat_signals`.
> - Reparent giữ z (z_as_relative, container z_index=0); `_clear_macros` reparent members về objects_container (keep_global=false = giữ toạ độ design) để sửa trong editor.
> - **Anchor (2026-07-01, robust):** container scale về gốc (pivot 0), `_update_macro_anchors()` chạy MỖI FRAME set `position = screen_anchor − scale·anchor_local` → mép region dính cạnh ở MỌI mức scale (giữ flush suốt tween shrink/pulse) và tự re-fit khi đổi kích thước cửa sổ. `MACRO_MARGIN=0` (sát hẳn).

> ⚠️ **GOTCHA drag-reorder:** chọn group/child (`_select`/`_select_group`) chỉ được gọi `_update_row_selection()` (đổi highlight tại chỗ), **TUYỆT ĐỐI KHÔNG** `_rebuild_groups_panel()` — rebuild khi nhấn sẽ free row ngay lúc bấm → Godot không kịp khởi tạo `_get_drag_data` → hỏng kéo-thả đổi Z. Chỉ rebuild khi đổi cấu trúc (add/delete/reorder/collapse/lock/rename/visible).

**Panel phải:** Save/Delete/Close · **ITEMS** (palette `_PaletteCell` từ `assets/hud/Playerhud`, drag source) · TRANSFORM (X/Y/W/H, W/H chỉ cho item) · **BLEND** dropdown (item) · **TEXT** section (hiện khi chọn text): Text / Font (dropdown assets/fonts) / Size / Align / Color / Outline color+width.

**BLEND** → `EditableObjectNode.set_blend_mode(id)` (0..5 = Normal/Screen/HardLight/Overlay/Add/Multiply). Normal/Add/Multiply = `CanvasItemMaterial`; **Screen/HardLight/Overlay** = `ShaderMaterial` `res://assets/shaders/hud_blend.gdshader` (`hint_screen_texture`, `mode=id-1`).

**Live HUD:** node đặt nằm trên ObjectsContainer (CanvasLayer layer=9) — khi đóng editor `_set_gameplay(true)` giữ visible + non-interactive → là HUD thật trong gameplay. Mở editor: pause + `_arena_focus(true)` (gọi `arena.set_edit_focus` ẩn HUD/nút/player/enemy — nếu KHÔNG ẩn thì Control gameplay ở layer 10/11 nuốt mất cú kéo trên canvas layer 9) + `_objects_container.process_mode = ALWAYS` (nhận input khi tree paused) + `_set_gameplay(false)` cho kéo. **Zoom** canvas: slider (panel phải) + lăn chuột (`_apply_zoom` scale ObjectsContainer; reset khi open/close) — y như creep edit.

Wiring: `arena.gd._setup_hud_edit()` (CanvasLayer layer=9 + ObjectsContainer) → group `"hud_edit"`; nút `arena_hud_buttons.gd` (`Asset 41.png`, dưới Wave Edit, dev:on) → `_on_hud_edit()` → `toggle()`.

> Các hook `_uses_points()/_build_extra_controls()/_refresh_extra_controls()` + key `"blend"` từng thêm vào `creep_edit_mode.gd` (bản subclass cũ) vẫn còn — vô hại, default giữ nguyên hành vi creep/weapon edit; có thể tái dùng sau.

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

