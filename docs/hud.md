# HUD — Player HUD architecture & gotchas

> Module của [`CLAUDE.md`](../CLAUDE.md). Đọc file này khi làm bất cứ thứ gì liên quan HUD in-game (thanh HP/Shield/Level, slot weapon/aux, nút Menu/Inv, coin/kill, layout HUD).
> Cơ chế **editor** (kéo/thả, groups, blend, save layout) nằm chi tiết ở [`docs/dev_mode.md`](dev_mode.md) — file này là bức tranh tổng + các lưu ý sống còn.

## ⚠️ TL;DR — điều PHẢI biết trước khi đụng HUD

1. **Có HAI hệ HUD trong repo, chỉ 1 cái đang bật:**
   - ✅ **Playerhud (ĐANG DÙNG)** — HUD "authored" do người chơi/dev tự dựng, code ở `scripts/ui/boss_edit/hud_edit_mode.gd` (giờ là **generic board editor**), layout ở `res://config/boards/hud.cfg` (fallback `res://playerhud_layout.cfg` nếu chưa migrate), sprite ở `assets/hud/Playerhud/`. Wire qua `arena.gd._setup_hud_edit()`. Runtime HUD (weapon/aux slot, bar VFX, macro, sentinel) đã tách ra `scripts/ui/boards/hud_binder.gd`.
   - 🚫 **Cockpit HUD (ĐANG ẨN)** — bản cũ từ nhánh `Minh_test` (merge 2026‑07‑02): `arena_vitals_bar.gd`, `arena_hud_frame.gd`, `arena_weapon_slots.gd`, `arena_aux_slots.gd`, `arena_stats_hud.gd`, `hud_hp_display.gd`. Vẫn được `arena._build_ui()` thêm vào cây nhưng **`visible = false`** (giữ để group‑lookup còn resolve). **KHÔNG bật cùng lúc với playerhud** (sẽ chồng HUD).
2. **`hud_edit_mode.gd` vừa là EDITOR vừa là HUD THẬT:** khi đóng editor, các node đã đặt CHÍNH LÀ HUD sống, được `_update_bindings()` cập nhật mỗi frame từ game state. Đừng tưởng nó chỉ là "công cụ chỉnh".
3. **Toạ độ = design coords tuyệt đối**, KHÔNG còn scale toàn HUD theo màn hình (đã bỏ `_apply_hud_screen_fit`). Vị trí trên màn hình do **macro regions** canh theo cạnh.
4. Một số **cờ TẠM** đang bật để kiểm tra icon (xem [§8](#8-các-cờ-tạm-icon-check-mode)). Nhớ trả lại trước khi coi là "final".

---

## 1. Wiring — HUD được dựng ở đâu

`arena.gd`:
- `_build_ui()` (CanvasLayer "UI", layer 10): thêm **cockpit HUD** widgets nhưng `visible = false` (legacy, ẩn).
- `call_deferred("_setup_hud_edit")` → **`_setup_hud_edit()`**: tạo `CanvasLayer(layer=9)` + `ObjectsContainer` (Control full‑rect, mouse_filter IGNORE) → `HudEditScript.new()` → `hem.setup(oc)`. Đây là **playerhud sống**.
- `set_edit_focus(on)`: ẩn gameplay + HUD + buttons + player + enemies khi mở 1 full‑screen editor (playerhud editor gọi qua `_arena_focus`).

`arena_hud_buttons.gd` (CanvasLayer 11, cụm nút góc phải + dev góc trái):
- Nút **Asset 41** (`_hud_edit_btn`, chỉ hiện khi **dev:on**) → `_on_hud_edit()` → `get_first_node_in_group("hud_edit").toggle()` mở/đóng editor playerhud.
- `_settings` (settings/menu panel) được `add_to_group("settings_panel")` để nút **Menu** của playerhud mở được.

Z/layer: cockpit HUD layer 10 (ẩn) · playerhud ObjectsContainer layer 9 · buttons layer 11.

## 2. `hud_edit_mode.gd` — mô hình dữ liệu

Lưu `res://config/boards/hud.cfg`, section `[hud] groups`:
- `_groups: Array` — danh sách nhóm có thứ tự; **index 0 = trên cùng = Z cao nhất** (`_reassign_z` gán z giảm dần từ `Z_TOP=240`).
- Mỗi group = `{name, children, collapsed, locked}`. Mỗi child `{id, type}`:
  - **item**: `file` (basename trong `assets/hud/Playerhud/`), `pos`, `size`, `blend`, `grow` (bar band), `visible`, `opacity`.
  - **text**: `text`, `font`, `font_size`, `color`, `outline_color`, `outline_size`, `align`, `pos`.
- `_nodes: {id → node}`: item = `EditableObjectNode`; text = inner class `_HudText`.

**Editor UI** (chi tiết ở [dev_mode.md](dev_mode.md)): panel trái GROUPS (`+`, RMB Copy/Rename/Delete/Add Text, khoá, caret, kéo đổi Z, kéo item từ ITEMS); panel phải Save/Delete/Close · ITEMS palette · TRANSFORM (X/Y/W/H) · Zoom · Opacity · **Blend** · **Grow** (chỉ bar band) · **Text** style.

## 3. Runtime binding (playerhud = HUD sống)

`_process` → `_update_bindings()` khi `not _is_open and _bindings_ready`. `_build_runtime_bindings()` (gọi ở `setup()` + `_close()`) resolve node theo group/file/sentinel + tạo node runtime‑only; `_open()` xoá chúng (`_clear_runtime_extras` + `_clear_macros`) và khôi phục text design để sửa.

**Text theo sentinel** (giá trị chữ = khoá bind): `"200"`→ship_hp, `"300"`→ship_max_hp, `"50"`→ship_shield, `"100"`→shield_capacity_total(), `"KILL"`→run_kills, `"COIN"`→money, `"LV. 3"`→player_level. Giữ anchor theo `align` (trái/giữa/phải) để số đổi độ rộng không lệch.

## 4. Bar VFX — HP / Shield / Level

- Shader **`assets/shaders/bar_fill.gdshader`**: 1 `TextureRect` phủ đúng rect band, **mask bằng alpha của chính sprite band** (`texture(TEXTURE,UV).a`) → chỉ vẽ lên pixel band có màu, KHÔNG tràn khỏi silhouette. `progress` (0..1) grow theo `grow_dir` (0=L→R,1=R→L,2=B→T,3=T→B). Có shimmer + glow mép như level cũ.
- `_make_bar_fill(ch, fill_col, glow_col)` — màu: Level=xanh lá (xp%), HP=đỏ (hp/hp_max), Shield=xanh biển (shield/shield_cap). `_set_fill_progress()` set uniform mỗi frame.
- **Band = indicator, chỉ hiện trong HUD Edit** (`_is_band_node` + `_set_gameplay`): lúc chơi band ẩn, thanh fill masked mới là bar thật. Band resolve theo **filename** ở bất kỳ group nào: `levelband`/`HPband`/`shieldband` (`BAR_BAND_FILES`).
- **Grow direction**: dropdown "Grow" (panel phải, chỉ khi chọn band) → lưu `ch["grow"]`. Fill là runtime‑only nên editor không preview (áp dụng lúc chơi).

## 5. Macro regions — canh cạnh + animation

Thay cho scale toàn HUD. `_build_macros()` (cuối `_build_runtime_bindings`, gỡ ở `_clear_macros` khi mở editor):
- Gom member nodes theo `GROUP_MACRO` (group "Text" tách theo `KILLCOIN_TEXTS`) + runtime extras (theo `set_meta("macro_key")`), **reparent** vào 1 `Control` container/vùng.
- **4 vùng:** `Weapon`=Button1‑5+ActiveBar (**trái**, giữa dọc) · `Aux`=Button6‑10+PassiveBar (**phải**, giữa dọc) · `KillCoin`=text KILL/COIN+KillBar (**trên**, giữa ngang) · `LV`=INV/MENU/LevelBarBg/Level/LevelBar + text HP/Shield/LV (**dưới**, giữa ngang).
- **Anchor robust:** container scale về gốc (pivot 0); **`_update_macro_anchors()` chạy MỖI FRAME** set `position = screen_anchor − scale·anchor_local` → mép vùng **luôn dính cạnh ở mọi mức scale** (giữ flush suốt tween) + tự re‑fit khi resize. `MACRO_MARGIN=0` (sát hẳn).
- **Animation:**
  - Weapon/Aux nghỉ ở `SHRINK_SCALE`(70%). `_trigger_shrink`: về 100% → chờ `SHRINK_DELAY`(5s) → về 70%. Trigger: `GameManager.player_stats_changed` (upgrade) + đếm `acquired_weapons()`/`owned_aux()` tăng (item mới) trong `_update_weapons/_update_aux`.
  - KillCoin `_pulse_macro`: pop `PULSE_SCALE`(103%) trong 0.1s. Trigger: `kills_changed` / `money_changed`. Signals hook 1 lần ở `_ready`→`_hook_stat_signals`.
- Reparent giữ z (z_as_relative, container z=0); `_clear_macros` reparent members về objects_container (keep_global=false = giữ toạ độ design) để sửa.

## 6. Icon weapon trên slot btn

- Set **riêng** ở `res://assets/inventory/icon/<kind>.png` — **filename = weapon kind** (đã đổi tên khớp code name; 27 kind + `zeus.png` thừa cho evolve chưa implement). KHÔNG trùng icon inventory cũ (`assets/inventory/*.png` dùng cho mục đích khác).
- `_weapon_icon_tex(kind)` **ưu tiên** set này (`WEAPON_HUD_ICON_DIR`), fallback `WEAPON_INFO/FUSION_DEFS.icon` → `InventoryManager.get_icon(def_id)`.
- `_make_slot_icon(btn, macro_key)`: icon = `SLOT_ICON_FIT`(0.72) kích thước btn, căn giữa, `STRETCH_KEEP_ASPECT_CENTERED` (không méo), blend = `SLOT_ICON_BLEND`.
- Aux icon: `_aux_icon_tex` từ `def_for(id).icon`.
- Charge overlay: `btnred` (cooldown) / `btngreen` (firing); continuous weapon (`CONTINUOUS_WEAPONS`) tắt cả hai.

## 7. Nút Menu / Inv & blend

- `_setup_press_pair(normal, press, action, macro_key)`: Button trong suốt phủ lên; mặc định hiện `normal`, giữ chuột hiện `…press`, thả gọi action.
- **Menu** (`menubtn`/`menubtnpress`) → `_open_menu()` mở settings/menu panel (group `settings_panel`). **Inv** (`invbtn`/`invbtnpress`) → `_open_inventory()` (`inventory_ui.toggle()`; panel inventory làm sau). Cặp legacy `inventory`/`inventorypress` cùng cơ chế.
- **Blend**: item thường qua `EditableObjectNode.set_blend_mode` (0..5 Normal/Screen/HardLight/Overlay/Add/Multiply, shader `assets/shaders/hud_blend.gdshader`). Slot icon dùng `_apply_blend_to` riêng, **có thêm Lighten** (blend id 6 → hud_blend mode 3 = `max(dst,src)`).

## 8. Các cờ TẠM (icon‑check mode)

Đầu `hud_edit_mode.gd` — đang bật để kiểm tra icon, **nhớ trả lại khi final**:
| Cờ | Đang là | Ý nghĩa | Giá trị "bình thường" |
|----|---------|---------|-----------------------|
| `SHOW_CHARGE_FX` | `false` | ẩn overlay btnred/btngreen | `true` |
| `SHOW_SLOT_BTN` | `false` | ẩn khung `btn` (giữ vị trí làm anchor cho icon) | `true` |
| `SLOT_ICON_BLEND` | `0` (Normal) | blend icon slot | tuỳ chọn (`6`=Lighten, `1`=Screen…) |

## 9. Bản đồ file

| Vai trò | File |
|---------|------|
| Playerhud editor + HUD sống | `scripts/ui/boss_edit/hud_edit_mode.gd` |
| Layout đã lưu | `res://config/boards/hud.cfg` (fallback `res://playerhud_layout.cfg`) |
| Board system (multi-board) | `scripts/ui/boards/board_defs.gd` (registry), `board_binder.gd` (base), `hud_binder.gd`, `levelup_binder.gd` |
| Sprite HUD | `assets/hud/Playerhud/` (btn, btnred/green, HPband/shieldband/levelband, HPframe, activebar/passivebar, coin bar, menubtn(press), invbtn(press), inventory(press)) |
| Icon weapon slot | `assets/inventory/icon/<kind>.png` |
| Shader | `assets/shaders/bar_fill.gdshader` (bar), `assets/shaders/hud_blend.gdshader` (blend, có Lighten), `assets/shaders/level_fill.gdshader` (cũ, không còn dùng) |
| Wire vào arena | `scripts/gameplay/arena.gd` (`_setup_hud_edit`, `_build_ui`, `set_edit_focus`) · `scripts/ui/hud/arena_hud_buttons.gd` (nút Asset 41) |
| Cockpit HUD (ẩn) | `scripts/ui/hud/arena_vitals_bar.gd`, `arena_hud_frame.gd`, `arena_weapon_slots.gd`, `arena_aux_slots.gd`, `arena_stats_hud.gd`, `hud_hp_display.gd` |

## 10. Gotchas

- **Đừng bật cả 2 HUD.** Muốn quay lại Cockpit: trong `arena._build_ui` bỏ `visible=false` cho các widget cockpit + gỡ `call_deferred("_setup_hud_edit")` (hoặc ẩn playerhud). Muốn giữ playerhud (mặc định hiện tại): để nguyên.
- **Band là indicator** — nếu thấy band silhouette hiện lúc chơi là sai (`_set_gameplay` phải ẩn nó). Band phải là **hình đặc của thanh** (không phải khung rỗng ruột) vì fill mask theo alpha của band.
- **Grow direction không preview trong editor** (fill runtime‑only) — chỉnh xong Save rồi vào game xem.
- **Macro anchor tính theo viewport mỗi frame** — không hard‑code kích thước màn hình.
- **Layout ở `res://config/boards/*.cfg`** (không phải `user://`) — commit cùng project. HUD còn fallback `res://playerhud_layout.cfg` (đã xoá, chỉ giữ đường fallback trong `board_defs.gd`).
- Icon cache theo `kind` (`_weapon_icon_cache`): thay ảnh lúc chạy không refresh, restart mới thấy.
- Boss fight: playerhud **chưa có thanh máu boss** (cockpit có `VitalsBar mode="boss"` nhưng đang ẩn) — cần thì làm riêng.
- **`level_fill.gdshader`** vẫn còn trong repo nhưng bar VFX đã chuyển sang `bar_fill.gdshader` (masked) — đừng nhầm.

## 11. Multi-board system (2026-07-02) — 1 editor, nhiều bảng

`hud_edit_mode.gd` giờ là **board editor generic**: cùng 1 công cụ (groups/items/text, drag-drop, blend, transform, zoom, save/load) author được nhiều "board" khác nhau. Chọn board qua dropdown **"Board:"** (panel phải).

**Kiến trúc:**
- `scripts/ui/boards/board_defs.gd` — registry: `id → {name, layout, assets, binder}` + `ORDER` (thứ tự dropdown). Thêm board mới = thêm 1 entry + 1 binder script + 1 folder sprite, **không sửa editor**.
- Board nào có `"hud_version": true` (hiện tại: `hud`="HUD 1.0", `hud_1_1`="HUD 1.1") là một **bản HUD người chơi chọn được**, khác với board chức năng riêng như `levelup`. `BoardDefs.hud_version_ids()` liệt kê các board này (thứ tự theo `ORDER`, lọc theo cờ) — dùng cho dropdown "HUD" ở Settings, KHÔNG dùng cho dropdown "Board:" của editor (cái đó vẫn liệt kê hết `ORDER`, kể cả `levelup`).
- `board_binder.gd` (base, `extends Node`) — lifecycle `setup/build/update/clear` + hook `is_band_file()`. Binder là con của surface, đọc data qua `_ed` (`_ed._nodes/_groups/_objects_container/_load_tex/...`).
- `hud_binder.gd` — **toàn bộ runtime HUD cũ** (weapon/aux slot, bar VFX, macro region, sentinel text, Menu/Inv). Editor không còn biết gì về HUD. Board `hud` và `hud_1_1` dùng CHUNG file này — khác board chỉ khác *tên file sprite* trong layout; binder resolve theo `ROLE_FILES`/filename nên hỗ trợ song song cả 2 bộ tên (không cần if/else theo board_id).
- `levelup_binder.gd` — board Level Up: chrome tĩnh + role = **tên group** (`Title/Slot1/Slot2/Slot3/Selected/Options/Stats`), `role_rect(name)` = bbox group (screen coords).

### 11b. Chọn HUD version ở Settings (2026-07-05)

- `settings_panel.gd`: dưới dòng **Graphic**, thêm dòng **HUD** với `OptionButton` liệt kê `BoardDefs.hud_version_ids()`. Chọn xong áp dụng **live ngay** qua `_apply_hud_version(id)` → tìm node group `hud_edit` (chính là `hud_edit_mode.gd` instance sống trong arena) → gọi `hud.set_home_board(id)`. Persist ở `user://settings.cfg` `[hud] version`; Reset về `hud` (HUD 1.0); Cancel revert về snapshot lúc mở panel — giống pattern Volume/Graphic. Không áp dụng gì ở Main Menu (chưa có `hud_edit` node) — HUD version được đọc lại khi `arena.gd._setup_hud_edit()` build HUD (`SettingsScript.load_cfg()["hud_version"]` → `hem.setup(oc, hud_version)`).
- `hud_edit_mode.gd.set_home_board(id)`: đổi `_home_board` (board hiện ra khi editor đóng). Nếu editor đang mở board khác thì chỉ nhớ, để `_close()` tự load; nếu không, swap surface ngay (`_binder.clear()` → `_load_board_into_container(id)` → `_set_gameplay(true)` → `_binder.build()`) — pattern y hệt phần "restore home board" trong `_close()`.
- **Thêm HUD version mới** (vd HUD 1.2): thêm entry `"hud_1_2"` trong `BoardDefs.BOARDS` (`"hud_version": true`, layout `res://config/boards/hud_1_2.cfg`) + thêm vào `ORDER`; copy 1 file `.cfg` có sẵn làm điểm khởi đầu nếu muốn kế thừa layout cũ. Không cần sửa editor lẫn Settings — cả 2 dropdown đọc registry.

### 11c. HUD 1.1 Menu/Inv art (2026-07-05)

HUD 1.1 dùng art riêng cho nút Menu/Inv: `menu1`/`inv1` (+`…press`, `assets/hud/Playerhud/`) qua `_setup_hover_pair` (mới, cạnh `_setup_press_pair` mà HUD 1.0 dùng cho `menubtn`/`invbtn`) — hiện `…press` **khi hover** (mouse_entered/exited) thay vì khi giữ chuột, click vẫn trigger action như cũ. Cả 2 bộ filename đều nằm trong `ROLE_FILES`; board nào không có file tương ứng thì lệnh gọi tương ứng no-op (an toàn gọi cả 4 dòng `_setup_press_pair`/`_setup_hover_pair` mỗi lần `build()`).

**Shield VFX (2026-07-05):** `shieldband` và `shieldband1` có 2 hệ **node/shader hoàn toàn tách biệt** (không hệ nào đọc/gọi hệ kia), nhưng cả 2 cùng theo % khiên thật:
- `shieldband` (band thật, group `Level`, vẫn ẩn lúc chơi) → `_shield_fill` = `_make_bar_fill(roles["shieldband"], ...)`, dùng chung `bar_fill.gdshader` — CHÍNH LÀ code gốc của HUD 1.0, không đổi gì, board-agnostic (chạy y hệt trên `hud_1_1.cfg` vì file cfg vẫn còn role này).
- `shieldband1` (2 layer decorative, HUD 1.1 riêng, group `LevelBar`, giữ nguyên 2 blend Overlay/Add gốc) → `_shieldband1_vfx`, dựng qua `_find_shieldband1()` (quét riêng, LẤY rect occurrence đầu + z = z lớn nhất trong 2 layer + 1, KHÔNG đụng `roles`/`ROLE_FILES`) + `_make_shieldband1_vfx()`, shader riêng `assets/shaders/shieldband1_vfx.gdshader` (`render_mode blend_add` — chỉ cộng sáng, không che 2 blend layer bên dưới; **mask theo alpha của chính shieldband1** — giống crop trick của `bar_fill.gdshader` — nên sweep không tràn ra ngoài điểm trong suốt; sweep chéo + pulse chạy liên tục bên trong vùng còn "đầy").
  - **`progress`** (uniform, 0=cạn/trái, 1=đầy/phải — cùng convention `grow_dir=0` của `bar_fill.gdshader`): `_update_bindings()` gọi `_set_fill_progress(_shieldband1_vfx, ship_shield, shield_capacity_total())` — TÁI DÙNG luôn hàm generic có sẵn (chỉ cần `material` có uniform `progress`, không quan tâm shader nào). Trong shader: pixel có `UV.x > progress` bị cắt (`COLOR=vec4(0)`), cộng thêm 1 dải glow mềm ở đúng mép progress (giống leading-edge glow của `bar_fill.gdshader`).
  - Bug đã gặp + đã sửa: shader gốc dùng `if (...) { COLOR=...; return; }` bên trong `fragment()` — Godot KHÔNG chấp nhận `return` sớm kiểu này (lỗi compile, chỉ lộ ra lúc GPU thật sự compile — `--headless --check-only` KHÔNG bắt được lỗi `.gdshader`). Vì material lỗi, node fallback vẽ texture trơn Normal đè lên 2 layer blend gốc → nhìn như "mất blend". Đã đổi sang `if {...} else {...}` (giống `bar_fill.gdshader`) — hết lỗi.
  - Bản thử đầu tiên (dùng chung 1 shader + gate theo `_ed._board_id`, xen giữa code `shieldband`) đã bị revert vì rối — lần này 2 đường hoàn toàn song song, xoá 1 bên không ảnh hưởng bên kia.

**Surface = editor + host runtime:** `setup(oc, board_id, editable)`. `editable=true` = editor arena (home board = HUD, dropdown author mọi bảng, đóng lại về HUD, ở group `hud_edit`). `editable=false` = host runtime-only (không UI, không vào group) — dùng cho **Level Up host** (CanvasLayer 99 trong `arena_levelup_ui`). Board switch: `_switch_board(id)` save nếu dirty → nạp board mới; `_close()` khôi phục home board.

**Layout:** mỗi board 1 file `res://config/boards/<id>.cfg` (`hud.cfg`, `levelup.cfg`…). Save ghi `_layout_save` (primary), load ưu tiên primary → legacy fallback.

**Level Up (2026-07-02 — data-wired):** board Level Up **thay hẳn** UI level-up khi đã author (board rỗng → fallback UI full-screen cũ, chạy y nguyên). `arena_levelup_ui.gd` **giữ 100% logic sinh card/pick/apply/pool/capstone/fusion/all-in**; render song song lên host (layer 99) qua `LevelUpBinder`. Old `_root` (layer 100) bị ẩn từng box khi board active; blocker STOP tối trên host chặn input rò xuống game. `_board_reload` mỗi lần level-up (host đọc lại cfg do editor lưu).

**Role convention (binder index — sprite theo filename, text theo nội dung, scope theo tên group):**
| Group | Nội dung | Runtime |
|-------|----------|---------|
| `Weapon1/2/3` | sprite `WeaponFrame` (indicator) + text `Codename` | sprite weapon (`get_icon(def_id)`) = (frame−8px)×80%, center; text Codename = code name (label), center-X theo WeaponFrame; hover→sáng+5%+uiclick+grow; click→uialert+select (`_select_item`) |
| `Upgrade1/2/3` | text `Upgrade Name` (style template) + sprite `UpgradeName` (wrap box) + sprite `UpgradeIcon` (icon/swatch box) + text `Upgrade Icon` (sentinel, ẩn — chỉ để binder tìm group) | fill 1..3 option từ `_current` (thừa → VFX đen như StatDisplay, xem §12); **hover** (`_hover_option`) = phóng to + preview UpgradeDesc/Weapon Stat, KHÔNG đổi màu VFX; **click** (`_select_option`) = chọn thật: VFX đỏ + đẩy icon lên WeaponDisplay. Mặc định "Select Weapon" khi chưa chọn |
| `WeaponDisplay` | sprite `WeaponDisplay` (indicator) + text `Codename`/`Full Name`/`Item Lore` + sprite `LoreDisplay` (indicator, khung wrap lore) | sprite = top-level pick, HOẶC option Upgrade1-3 đang được **click** đè lên (xem §12); Codename=`label`, Full Name=`name` (cả 2 center-X theo WeaponDisplay, LUÔN theo top-level pick dù sprite bị đè); Lore=`ArenaWeapons.WEAPON_LORE[kind]` (English) wrap trong khung `LoreDisplay`, top-align. Chưa chọn→ẩn hết text |
| `StatDisplay` | sprite indicator + text `Weapon Stat` + text `Upgrade Desc` (style template, sentinel ẩn) + sprite `UpgradeDesc` (wrap box, hiện khi chơi) | thay `Weapon Stat` bằng bảng stats (`_fill_stat_rows`) scale 80%; `UpgradeDesc` = RichTextLabel 3 phần màu (stat trắng/rank đỏ/trivia vàng, cách nhau 1 dòng trống, font style−4, center cả 2 chiều) theo option đang **hover** (`_hover_preview_idx`), KHÔNG phải option đã click; sprite `StatDisplay` = indicator ẩn khi chơi |

> Sentinel text match **bỏ khoảng trắng + lowercase** ("Code Name"=="Codename"). Indicator sprites edit-only thật sự (`LevelUpBinder.INDICATORS`) chỉ có **`WeaponDisplay`/`StatDisplay`** — `WeaponFrame`/`CodeName`/`UpgradeName`/`UpgradeIcon`/`UpgradeDesc`/`LoreDisplay` là **FRAME_LAYERS** (chrome/khung thật, ở lại visible lúc chơi, runtime vẽ ĐÈ lên chứ không thay thế). **Click được nhờ ẩn hẳn `_root`** (Control full-rect layer 100 STOP nuốt click) khi board active — input xử lý ở host layer 99 + blocker.

`WeaponDisplay`/`StatDisplay` = edit-only thật (`LevelUpBinder.is_band_file`) — ẩn khi chơi, chỉ hiện trong HUD Edit. Sprite chrome/indicator ở `assets/hud/LevelUp/`. Runtime nodes (sprite/label/button) do `arena_levelup_ui` tạo trên `binder.container()`, dọn qua `_board_clear_all`.

## 12. Level Up — aux/perk icon + hover/click select (2026-07-03)

**Nguồn icon aux/perk** (`arena_levelup_ui.gd`):
| Loại | Folder | Filename | Hàm resolve |
|---|---|---|---|
| Aux top-level (17 item, `AUX_DEFS`) | `assets/hud/UpgradeIcon/` | `<aux_id>.png` (vd `hp.png`, `coin.png`) | `_aux_icon_tex(id)` |
| Aux pool perk (40 perk dưới 7 aux có pool, `AUX_POOL`) | `assets/hud/perks/` | `<perk_id>.png` (vd `regen_shield.png`) | `_perk_icon_tex(id)` |
| Weapon (new/capstone/fusion) | `assets/inventory/*.png` (KHÔNG phải `assets/inventory/icon/` — đó là set riêng cho HUD slot, xem §6) | qua `ITEM_DEFS[def_id].icon` | `InventoryManager.get_icon(def_id)` |
| Weapon pool perk (53 perk dưới 9 weapon có pool — `GATLING_POOL`/`ARC_POOL`/... trong `arena_weapons.gd`) | `assets/hud/weapon perks/<folder>/` (1 subfolder/weapon, tên folder = nhãn tự do của artist, KHÔNG khớp `WEAPON_INFO.label/name` — xem `WEAPON_PERK_FOLDER`) | `<perk_id>.png`, hoặc filename thay thế trong `WEAPON_PERK_ID_ALIAS` nếu id không khớp file (vd `aoe_mastery`→`aoe.png`, `cd`→`cooldown.png`, `ms`→`movespeed.png`, `armor_reduction`→`armor reduction.png`) | `_weapon_perk_icon_tex(kind, perk_id)` |

`_option_icon_tex(c)` = điểm vào DUY NHẤT resolve icon cho 1 card dict `c` bất kỳ (top-level pick / pool perk / capstone): `cat=="pool"` thử icon RIÊNG của weapon-perk trước (`_weapon_perk_icon_tex`), fallback xuống nhánh dưới nếu không có; rồi `def_id != ""` → weapon (`InventoryManager`, tức icon weapon cha cho pool-perk chưa có art + mọi new/capstone/fusion); else aux — nếu `cat=="aux_pool"` thử icon RIÊNG của perk trước (`_perk_icon_tex`), fallback icon **aux cha** (`_aux_icon_tex(_aux_id_for(c))`); còn lại (capstone, aux đơn) luôn dùng icon aux cha. **Weapon capstone (evolve level-6) vẫn CHƯA có icon riêng** — luôn hiện icon weapon cha (khác aux capstone, cũng fallback icon cha nhưng ít nhất đã có hệ đó).

**Audit** (`assets/hud/weapon perks/`, 9 folder = 9 weapon có pool): Minigun 7/7, Death Beam 6/6, Arc Lightning 6/6, Gauss Pulser 6/6 (qua alias `aoe`), Z-Sword 6/6 (qua alias `cooldown`→`cd`), sonic 5/5 (qua alias `cooldown`→`cd`), red X 6/6 (thêm perk mới `armor_reduction`/"Melting Steel Beam" — **data + icon xong, CHƯA có gameplay effect** — cần hook giảm armor enemy theo `_burn_stacks`, chưa implement) — **còn thiếu**: Orbital Defender 6/7 (thiếu `spin2`/"Flywheel"), Chemtrail 4/5 (thiếu `intensity`/"Intensity Mastery"). Orbital cũng vừa thêm perk mới `widen`/"Widen" (+5% orbit distance, +7.5% damage) — **đã implement đầy đủ** trong `_orbital_radius()`/`_orbital_dmg_value()`.

**Scale — GPU stretch, KHÔNG CPU resize:** `_contain_box(native, max_w, max_h)` tính kích thước CONTAIN-fit (giữ aspect, cả 2 chiều đều ≤ box, trục nào chặt hơn quyết định) thuần toán học; `_fit_texture_rect(tex, max_w, max_h)` dựng `TextureRect` với `expand_mode=EXPAND_IGNORE_SIZE` + `stretch_mode=STRETCH_KEEP_ASPECT_CENTERED` — **y hệt cách weapon icon vẫn làm**, để GPU tự co giãn lúc vẽ. Đã thử CPU `Image.resize()` (kể cả LANCZOS) trước — nét kém hẳn so với GPU stretch dù cùng tỉ lệ thu nhỏ lớn (so sánh trực tiếp với weapon icon, nguồn cũng to tương đương ~2000-2900px). **Đừng quay lại CPU resize** cho icon aux/perk trừ khi có bằng chứng ngược lại.

**Hover vs Click trên Upgrade1-3 (mirror Weapon1-3):** 2 biến tách biệt —
- `_hover_preview_idx` (set bởi CẢ hover lẫn click, qua `_hover_option`/`_select_option`) → chỉ lái `_board_render_updesc()` + `_board_render_stats()` (preview). Hover KHÔNG rebuild lại 3 card, chỉ refresh 2 panel này (nhẹ).
- `_pending_pick_idx` (set CHỈ bởi click, qua `_select_option`) → lái VFX đỏ/xanh (`ucol` trong `_board_render_options`), Confirm commit target, VÀ icon trên `WeaponDisplay` (`_board_render_selected` ưu tiên `_current[_pending_pick_idx]` nếu có, fallback `_choices[_selected_idx]`). Reset về `-1` mỗi khi chuyển sang weapon/aux khác ở cột trái (`_select_item`) — tránh WeaponDisplay hiện nhầm icon perk của lựa chọn trước.

**Route cache** (`_route_cache: Dictionary`, key = `ckey` "w:kind"/"a:id"): `_gen_pool_choices`/`_gen_aux_pool_choices` (có `shuffle()`) chỉ chạy 1 lần/slot/màn hình — click qua lại giữa 3 weapon/aux không reroll perk. Clear ở đầu `_show_cards()` mỗi màn hình mới.

**Ô Upgrade trống** (ít hơn 3 option, pool cạn/capstone ít lựa chọn): VFX đen (`SCAN_COLOR_BLACK`) trên cả `UpgradeIcon`+`UpgradeName`, đồng bộ với cách StatDisplay/MainDisplay hiện khi "không phải item chọn được".
