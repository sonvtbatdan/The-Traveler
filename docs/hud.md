# HUD — Player HUD architecture & gotchas

> Module của [`CLAUDE.md`](../CLAUDE.md). Đọc file này khi làm bất cứ thứ gì liên quan HUD in-game (thanh HP/Shield/Level, slot weapon/aux, nút Menu/Inv, coin/kill, layout HUD).
> Cơ chế **editor** (kéo/thả, groups, blend, save layout) nằm chi tiết ở [`docs/dev_mode.md`](dev_mode.md) — file này là bức tranh tổng + các lưu ý sống còn.

## Changelog — 2026-08-30 (e) — Quest board wired to a real quest system (Electric, 12 quests)

- **`scripts/autoload/quest_manager.gd`** (new autoload, after MetaManager): `QUESTS` = the 12 Electric
  quests from the [Electric Quest Board artifact](https://claude.ai/code/artifact/10dad07c-fd59-4204-b4d4-ff2085fb1308)
  (eq01..eq12, 3 tiers, `prereq` + tier-gate: T2 needs ≥2 T1 done, T3 needs ≥3 T2 done + eq09). Live
  tracking during a run (per-type / per-faction kills, survive time, first-hit time, 3 s burst-kill peak,
  temple breaks, boss / final-boss kills, rescue, no-revive) + a persistent per-map lifetime kill tally;
  `end_run()` evaluates every available quest's `obj` spec, multi-pass so a mid-eval tier unlock also
  completes. Rewards: **coins real** (`GameManager.add_money`), "+X% … on Electric" / luck / global-XP are
  RECORDED (`map_mod()` / `luck_bonus` / `global_xp_pct`, persisted) — wiring those numbers into live
  gameplay is a follow-up. Persisted: `user://save.cfg [quests]`.
- **Hooks:** `arena_enemy._die()` → `QuestManager.on_enemy_killed(_type, is_boss, is_final, drop_loot)`;
  `arena._ready` → `begin_run(map_id)`; `arena._show_run_over` → `end_run(map_id, victory)`;
  QuestManager connects `GameManager.player_hit` / `rebirth_used`.
- **`quest_binder.gd`:** cells 0–11 → eq01..eq12 (12–29 empty). Cell art from `QuestManager.state_of()`:
  locked = dim `btn quest` (disabled), available = `btn quest` / `…pressed` (selected) / `…track`
  (tracked), done = `btn quest done` (still clickable to view). **Hover** a cell → after 0.3 s a green
  name tooltip drops below it. **Click** → the TV panel's 4 authored sentinel texts ("Quest name",
  "Objective Description", "Reward Description", "Trivia") are hidden and refilled by **wrapped** runtime
  Labels using each one's authored font/size/colour, width wrapped to the `quest tv` right edge
  ("Objective" / "Reward" green headers left alone). **Track** button → `QuestManager.toggle_tracked` (max 3).
- **`mapname` sprite** moved (cfg) into the board's bottom-left cutout window + scan `scanline_freq`
  lowered to 22 so the orange lines read on the short strip.
- **quest tv VFX** (`_scanlines_over` now takes `with_sweep` / `with_border` / `opacity`): the TV screen
  keeps only the fine `selection_scan` lines at `modulate.a` 0.5 — no `selection_sweep` band, no border
  ring (`border_strength` 0). It renders at the `quest tv` node's z (currently 225) which is **below**
  `quest board` (234), so it shows through the board's window cutout. `mapname` keeps the full treatment.
- **Per-quest icons** (`assets/hud/quest/Electric/<quest name>.png`, filename == `QUESTS[qid].name`):
  `_add_cell_icon()` puts a `TextureRect` (`EXPAND_IGNORE_SIZE` + `STRETCH_KEEP_ASPECT_CENTERED`, GPU
  scale) as a child of each slot button. Fit box = `Vector2(53,55) · ICON_FIT(0.80) − ICON_SHRINK(4)`,
  centred. Child of the button so it inherits `modulate` — dimmed with the slot when the quest is locked.
- **Every quest cell (0–11) is clickable to VIEW its info** — locked/available/done all open in the TV
  panel; only locked can't be tracked/completed, only the 18 empty cells are `disabled`. (Was: locked
  cells `disabled` → "why can't I click 8 of the 12 quests".) A locked cell shows `btn quest pressed`
  while it's the one being viewed, still dimmed.

## Changelog — 2026-08-30 (d) — Quest board: map selector, auto-centre, fixed cell size

- **`quest_binder._center_board()`** (first thing in `build()`, + on `viewport.size_changed`): restores every
  authored node to its cfg pos then shifts them all so the union bbox is centred in the game window. Runtime
  nodes (grid/VFX/overlays) are placed AFTER, from the shifted positions, so they follow.
- **Grid cells are now a fixed `CELL_W×CELL_H` = 53×55** (was aspect-derived from `btn quest`), 3 px apart,
  the 6×5 block centred inside the `quest grid` rect.
- **Map selector:** `MetaManager` gained `quest_map_id` (default `"electric"`, **persisted** in
  `user://save.cfg`), `QUEST_MAP_ORDER` (= Launch-panel card order), `set_quest_map_id`, `quest_map_step`,
  `quest_map_name`. The binder resolves the authored **"Map Name"** text (`_HudText`, sentinel match) and
  sets it to `quest_map_name()`; **"btn back" / "btn forward"** overlay buttons swap to `…press` art on
  `button_down`, restore + `quest_map_step(∓1)` on release. Re-opening the board returns to the last map.
- **`mapname` sprite** gets its own **orange** CRT scan-line (`SCAN_ORANGE`), via the generalised
  `_scanlines_over(file, colour)` — `quest tv` keeps green. ⚠️ If `mapname` is authored in a low-Z group
  (behind `quest board`) its scan-line is hidden too — move it / reorder its group in the editor.

## Changelog — 2026-08-30 (b) — Quest board: grid + button states + TV VFX + per-board BG colour

Built on top of the "Quest" board added earlier the same day.

### `quest_binder.gd` — now the full interaction (self-contained, like DockBinder)
- **6×5 cell grid** generated at runtime over the authored `quest grid` sprite's rect:
  `cell_w = (grid_w − 5·3) / 6`, `cell_h = cell_w · (btn_native_h / btn_native_w)` (keeps `btn quest`'s
  147×152 aspect — 5 rows then land just inside the grid art's own height), **3 px gap between cells only**.
  30 `TextureButton`s, row-major, `z = 245` (above every authored layer). The ONE authored `btn quest`
  is just an art reference — hidden at runtime.
- **Cell states** (sprite per state in `assets/hud/quest/`): idle `btn quest` → selected `btn quest pressed`
  (radio, one at a time) → tracked `btn quest track` (**up to 3**, wins over "selected" visually) → done
  `btn quest done` (not clickable; **no trigger yet** — `_done` static array, wire when quest data exists).
- **Track button** (`btn track` ⇄ `btn untrack`): reflects whether the *selected* cell is tracked. Click to
  track/untrack it. Nothing selected → no-op. Already 3 tracked → toast **"Maximum 3 quest tracking allowed"**
  (Mandalore font, fades in/out, pinned near the top of `quest board`).
- **Close button** (`btn close` → `btn close press` on hover): emits `close_requested`; `hub_screen._open_quest`
  (re)connects it to `_close_quest` after every `reload()` (fresh binder instance each time).
- **TV scan-line VFX**: the Level Up board's exact shader pair (`selection_scan` + `selection_sweep`,
  green `Color(0.35,1.0,0.45,0.5)`) as two `ColorRect`s over the `quest tv` rect. **z-order (2026-08-30 fix):**
  runtime nodes no longer use a fixed z — the VFX takes the `quest tv` node's OWN `z_index` (added after
  every authored node, so tree order still floats it just over the tv art) and the cells take
  `quest grid`'s `z_index + 1`. So re-ordering the "Quest Tivi" group *below* "Quest Board" in the editor
  now correctly pushes the scan-line behind the board frame too.
- Selection/tracking are `static var`s (survive the host's per-open `clear()`+`build()`; reset on game
  restart — no quest-data model yet).

### Per-board background colour (editor feature — ALL boards)
`hud_edit_mode.gd`: a **BG:** `ColorPickerButton` + ✕ clear, right under the Transform W/H row. Saved per
board in `[meta] bg_color` (default fully transparent → existing boards unchanged). Applied by
`_apply_board_bg()` as a full-screen `ColorRect` **z −4096, a SIBLING of `_objects_container`** (added to its
parent CanvasLayer) so canvas zoom/pan never moves it — runs for runtime-only hosts too, so the colour
shows in-game, not just in the editor. See [`dev_mode.md`](dev_mode.md).

## Changelog — 2026-08-30 — New "Quest" board (Dock → Bridge room)

"Bảng này sẽ hiện ra khi bấm ô Bridge ở Dock Menu (hiện đang là coming soon)" + "Làm thêm dòng Quest trong
HUD Edit ... load các asset trong assets/hud/quest".

- **`board_defs.gd`**: new `"quest"` entry (`assets/hud/quest/`, `config/boards/quest.cfg`,
  `quest_binder.gd`) + appended to `ORDER` → shows up as a **"Quest"** row in the board editor's "Board:"
  dropdown automatically (dropdown is built from `ORDER`). Not a `hud_version`, so it's excluded from the
  Settings HUD picker like `levelup`/`dock`/`choose_weapon`.
- **`scripts/ui/boards/quest_binder.gd`** (`QuestBinder`): minimal for now — board is pure authored chrome
  (`quest board` / `quest grid` / `quest tv` / `quest btn` (+` pressed`)). Only exposes `has_layout()`
  (any non-empty group) so the host can fall back to a toast until it's authored. Dynamic quest rows TBD.
- **`hub_screen.gd`**: `_build_quest_host()` — a runtime-only `HudEditScript` surface + dim + BACK button
  on a hidden `CanvasLayer` (layer 15), same pattern as `_build_dock_host` / the chest UI's board host.
  `_on_room_clicked` routes `"Bridge"` → `_open_quest()` (was the generic "Coming soon" toast).
  `_open_quest()` calls `_quest_host.reload()` first (picks up a layout saved by the editor since the
  scene loaded) and still shows the "Bridge — Coming soon" toast if `has_layout()` is false.
- **Authoring workflow** (unchanged from every other board): arena → dev:on → Asset 41 (HUD Edit) →
  Board: "Quest" → drag the palette sprites → Save writes `config/boards/quest.cfg`. The HUD editor is
  only wired in the arena, not the hub.

## Changelog — 2026-08-25 — Off-screen pointer label gap: the "chest correct, rescue wrong" bug was actually shared by both, and had nothing to do with copy-paste

"Đọc offset và khoảng cách giữa object và text của chest (hiện tại đang đúng) và áp dụng cho rescue landmark
(hiện tại đang sai)."

Read both files first: `arena_chest_pointer.gd` and `arena_ruin_pointer.gd`'s label-gap math (`_anchor.x +
_content_half.x + LABEL_GAP_PX`) and every constant feeding it (`EDGE_MARGIN`, `HUD_GAP`, `LABEL_GAP_PX`,
font size) were **already byte-identical** — unified back on 2026-08-19 per both files' own changelogs. So
there was nothing to "copy from chest" at the code level. The actual bug was underneath both, in
`_measure_content()`.

**Root cause, confirmed by sampling `get_used_rect()` over 40 live consecutive frames**: a freshly created
transparent SubViewport's very **first** rendered frame can read back **fully opaque** (a one-frame GPU
clear/composite race — corner AND center pixels both `alpha=1.0`, RGB `(0,0,0)`). `get_used_rect()` then
reports the WHOLE 128×128 canvas as "used" instead of empty, which slips past the `used.size.x <= 0` guard
because a full box has positive size — it's just wrong. Every frame from the **second** successful read
onward was correct and stable (~40–58px of 128, matching this file's own documented "38–52% of frame width"
for GLB rescue models).

Both pointer files trusted whichever frame happened to be their first successful read, completely
unconditionally — so both were equally exposed to this exact race. Chest usually happened to land on a good
frame in real play (never confirmed why — likely just a small, consistent difference in exactly when its
viewport first renders vs. when this file's own `_process()` first checks), which is what made it *look*
like a chest-only-correct, rescue-only-wrong split, when the vulnerability was identical in both.

**Fix** (both files): discard the first successful `get_used_rect()` read, trust the second. Cheap (one
extra ~1-frame wait, imperceptible) and doesn't touch the flat-icon (temple) path in `arena_ruin_pointer.gd`,
which reads a real loaded PNG's alpha synchronously and was never exposed to this particular race.

Verified live — `content_half` before the fix was always exactly `icon_size * 0.5` (the full padded box, for
BOTH); after the fix:
```
chest: content_half=(19.0, 19.0)  of icon_size(84,84)   → ~23% half, tight fit
ruin:  content_half=(27.7, 17.3)  of icon_size(120,120) → ~23%/14% half, matches the documented 38-52% fill
```

## Changelog — 2026-08-25 — Arena pickup art un-automated (ammo ≠ gun); dedicated orbital models; 5 high-poly level-up overrides

Two corrections to the previous day's "every weapon with a .glb drops as 3D" pass, both from user feedback:

### 1. Arena pickup art is no longer auto-derived

"Có nhiều vũ khí (ví dụ laser, aliwa), glb trên arena là đạn, còn glb trong level-up và inventory là súng, nên
chúng ko cùng drop được. Tôi sẽ chỉ định thủ công vũ khí nào hiện trên arena là 3D."

Right — `InventoryManager.glb_for()` (sibling-of-the-icon guess) was never meant to answer "does this look
right as a dropped weapon pickup"; for several weapons the glb sitting next to the icon is that weapon's
**ammo/projectile model** (its in-flight shot), not the gun. Auto-wiring every resolvable glb to the pickup
crate would have shown the wrong asset for those.

`arena_weapons.gd` now has its own `ARENA_PICKUP_GLB` table (kind → path), curated by hand — nothing is added
automatically. `_pickup_glb()` reads only this table; anything not listed keeps the procedural crate diamond,
same as before any of this 3D work started. Currently populated with the 2 orbitals below only.

### 2. The orbitals use a SEPARATE, arena-specific model

"Dùng ND-OID-F.glb và ND-OIO-F.glb trong assets\\weaponry để hiện trên screen."

`ARENA_PICKUP_GLB`:
```
"defensive_orbitals": "res://assets/weaponry/ND-OID-F.glb"   # NOT assets/inventory/"defense orbital.glb"
"striker":            "res://assets/weaponry/ND-OIO-F.glb"   # NOT assets/inventory/"offense orbital.glb"
```
The level-up board / inventory still show `assets/inventory/"defense orbital.glb"` / `"offense orbital.glb"`
(via `InventoryManager.GLB_BY_ICON`, unchanged) — the two pairs are deliberately different files for
deliberately different contexts, exactly the ammo-vs-gun split above.

### 3. 5 weapons get a high-poly model, level-up board ONLY

"Có 5 vũ khí tôi muốn dùng file high poly (đặt ở assets\\inventory\\high poly) thay vào thumbnail và preview
trong bảng level up."

New `arena_levelup_ui.HIGHPOLY_GLB` (keyed by def_id, checked before the normal resolution in
`_weapon_icon_glb()` — covers every call site in that file, i.e. both the small choice-card thumbnails and
the big WeaponDisplay preview):
```
gatling_gun    -> assets/inventory/high poly/Gatling.glb
ionizing_field -> assets/inventory/high poly/Ionize field.glb
gauss          -> assets/inventory/high poly/gauss.glb
homing_missile -> assets/inventory/high poly/homing missile.glb
arc            -> assets/inventory/high poly/lightning.glb
```
Scoped to the level-up board only — the equip screen (`inventory_ui.gd`, doesn't use `Item3DIcon` at all) and
the arena pickup (curated separately, see above) are untouched and keep their regular model/PNG.

### Preloader

`arena_glb_preloader._collect_paths()` now pulls from all three sources (board's normal resolution, board's
high-poly override, arena's curated table) so nothing added above cold-loads on first use. All 18 distinct
models — 5 high-poly (80–102 MB source each) + 2 arena-specific orbitals (26–29 MB) + the 11 already
covered — warm in the background; booted run: `18 weapon model(s) warmed by t=10.8s`.

### Verified (booted arena)

```
[TMP-board]  def_id=gatling_gun -> HIGHPOLY res://assets/inventory/high poly/Gatling.glb
[TMP-pickup] kind=defensive_orbitals glb=res://assets/weaponry/ND-OID-F.glb is_3d=true
[TMP-pickup] kind=striker            glb=res://assets/weaponry/ND-OIO-F.glb is_3d=true
[TMP-pickup] kind=gauss              glb=(none) is_3d=false   ← auto-wiring removed, back to the crate
[TMP-pickup] kind=death_beam         glb=(none) is_3d=false
[TMP-pickup] kind=aliwa              glb=(none) is_3d=false
```

## Changelog — 2026-08-24 — Orbital Impact models wired in: level-up board AND the arena weapon drop

"Cập nhật thêm defense, offense orbital 3D vào bảng level up và cũng dùng glb này cho spawn trên arena khi
loot được."

`assets/inventory/defense orbital.glb` + `offense orbital.glb` (they had never been imported — no `.import`
existed — so an editor import pass ran first). Neither is reachable by the sibling-of-the-icon guess that
resolves every other weapon model: Defensive Orbitals' icon is `ND-OID-F.png`, and Striker (the Orbital
Impact **OFFENSE** weapon) has no `ITEM_DEFS` entry at all — it is identified purely by an icon override at
`assets/weaponry/ND-OIF-F.png`.

**One resolution point** now serves every consumer: `InventoryManager.glb_for(def_id, icon_path)`, with a
`GLB_BY_ICON` table for art whose model isn't named after its PNG. `arena_levelup_ui._weapon_icon_glb()`,
`arena_glb_preloader._glb_for()` and the new pickup path all delegate to it, so a weapon can't show a model
in one place and a flat PNG in another.

**Arena drop:** `arena_weapon_pickup.gd` renders the live model — SubViewport + 2 lights + ambient + a
Camera3D at `ISO_DEG`, the `arena_loot.gd` recipe — spinning at `MODEL_RPM`, in place of the procedural
crate diamond + emblem. The glow halo, bob and pop-on-collect are untouched, so it still reads as a pickup.
`arena_weapons.spawn_weapon_pickup()` resolves the path and passes it to `setup()` (the pickup can't preload
`arena_weapons` back — that preload already runs the other way).

**Scope note:** this is keyed off "does this weapon have a model", not off the two orbitals, so **every**
weapon with a `.glb` now drops as a 3D pickup — Gauss, Gatling, Viper and the rest, matching what the
level-up board has shown since 2026-08-19. Say so if you want it restricted to the orbitals only.

`item_3d_icon.gd` gained `warm_scene(path)` — the warm table's single entry point, returning the parked
`PackedScene` or loading-and-parking it. The pickup goes through it too, which is what stops a 54 MB model
cold-loading mid-fight because it happened to drop as loot.

**Verified** (booted arena, pickups force-spawned):
```
[TMP-pickup] kind=defensive_orbitals glb=.../defense orbital.glb is_3d=true
[TMP-pickup] kind=striker            glb=.../offense orbital.glb is_3d=true
[TMP-pickup] kind=gauss              glb=.../Gauss.glb           is_3d=true
```
and the preloader now warms **16** models (was 15 — `ND-OID-F.glb` is replaced by `defense orbital.glb`,
`offense orbital.glb` is new) finishing at t≈8.8s.

### ⚠️ These two models are very heavy

| | source | imported .scn | cold load | vertices |
|---|---|---|---|---|
| defense orbital | 82 MB | 54 MB | 426 ms | **1,038,894** |
| offense orbital | 115 MB | 66 MB | 438 ms | **1,688,818** |
| Gauss (for scale) | — | 1.1 MB | 308 ms | 29,111 |

The cold load is absorbed by the background preloader, but the **vertex count is not** — each live pickup
renders its mesh every frame (`UPDATE_ALWAYS`), so one dropped offense orbital pushes 1.7M verts/frame for a
40 px sprite, and holding both resident costs ~120 MB on top of VIPER's 55 MB. They are ~40× heavier than
any other weapon model here. Decimating them (or baking a low-poly LOD for icon/pickup use) is worth doing
before this ships.

## Changelog — 2026-08-24 — Level-up hitch WAS the 3D models; they are now warmed in the background

"Kiểm tra xem mỗi lần lên level thì bị giật lag (có phải do load model 3D ko?)" — yes, it is.

The board swaps a live-rendered `item_3d_icon.gd` in wherever a weapon has a sibling `.glb` (3 small choice
cards + 1 big `WeaponDisplay` preview, all built in the frame the board opens). Timed cold `load()` of every
`assets/inventory/*.glb`: **280–345 ms each** (`carnage` 9 ms and `Jeager` 22 ms are the only cheap ones), so
opening the board stalled the main thread for most of a second. And it recurred every level-up: Godot's
resource cache holds only **weak** references, so the `PackedScene` is released the moment the board's icons
free, and the next level-up pays the identical cost again. A cached re-load, by contrast, is ~0.02 ms.

Fix, two parts:
- **`scripts/gameplay/arena_glb_preloader.gd`** (new, added by `arena.gd` next to `LevelUpUIScript`) resolves
  every weapon/fusion glb the board can offer — exactly the way `arena_levelup_ui._weapon_icon_glb()` does, so
  the sets can't drift — and loads them via `ResourceLoader.load_threaded_request()`, **off the main thread,
  one at a time**, starting `START_DELAY` = 3 s into the run so it never competes with the arena's own load.
- **`item_3d_icon.gd`** gained a `static var _warm` table (`warm_store`/`is_warm`/`warm_clear`). A static
  strong reference is what actually keeps a scene resident; `setup()` reads it first and also parks its own
  first cold load, so even a board opened before the preloader got there is instant the second time.
  `_exit_tree()` clears the table on leaving the arena — no reason to hold ~75 MB of weapon models resident in
  the main menu, and the next run re-warms in the background.

Verified in a booted arena: `[glb-preload] 15 weapon model(s) warmed by t=10.0s` — comfortably before any
realistic first level-up. The 3 inventory glbs NOT in that set (`carnage`, `NC-DC-F`, `ND-OIF-F`) are ones the
board's own resolution doesn't reach either (e.g. Striker's icon override points at
`assets/weaponry/ND-OIF-F.png`, whose sibling `.glb` doesn't exist), so those slots keep showing their flat
PNG exactly as before.

## Changelog — 2026-07-28 — Level Up board: hover-away falls back to the selected perk's info

Bug: `arena_levelup_ui.gd._board_click()`'s `mouse_exited` handler only reset the hover-scale VFX — it
never touched `_hover_preview_idx`, so once you'd hovered a card, `UpgradeDesc`/stat deltas (driven by
`_board_render_updesc()`/`_board_render_stats()`, both gated on `_hover_preview_idx`) stayed frozen on
whatever was hovered LAST, even after the mouse left every card and even if you'd since clicked a
DIFFERENT card to actually select it (`_pending_pick_idx`). Fixed: `mouse_exited` now also reverts
`_hover_preview_idx` back to `_pending_pick_idx` (re-rendering updesc/stats) whenever something is already
selected (`_pending_pick_idx >= 0`) and the preview isn't already showing it — so leaving all cards shows
the SELECTED perk's info again, and hovering any card still previews that card's info as before. Only the
active **board**-authored path (`_board_click`, gated by `_use_board()`/`_board_authored()`) was touched —
the legacy non-board fallback (`_make_option_box`/`_render_options`) is a different, currently-inactive
code path and wasn't touched.

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
- `set_edit_focus(on)`: ẩn gameplay + HUD + buttons + player + enemies **+ bật `_edit_backdrop` (ColorRect đen kín, CanvasLayer 8)** khi mở 1 full‑screen editor (playerhud editor gọi qua `_arena_focus`) — xem [`dev_mode.md`](dev_mode.md) changelog 2026‑08‑30.

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

**Audit** (`assets/hud/weapon perks/`, 9 folder = 9 weapon có pool): Minigun 6/6, Death Beam 6/6, Arc Lightning 6/6, Gauss Pulser 6/6 (qua alias `aoe`), Z-Sword 6/6 (qua alias `cooldown`→`cd`), sonic 5/5 (qua alias `cooldown`→`cd`), red X 6/6 (thêm perk mới `armor_reduction`/"Melting Steel Beam" — **data + icon xong, CHƯA có gameplay effect** — cần hook giảm armor enemy theo `_burn_stacks`, chưa implement), Orbital Defender 7/7 (gồm `spin2`/"Flywheel"), Chemtrail 5/5 (gồm `intensity`/"Intensity Mastery") — **note cũ ghi 2 file này "còn thiếu" đã lỗi thời, file đã có sẵn từ trước**. Orbital cũng vừa thêm perk mới `widen`/"Widen" (+5% orbit distance, +7.5% damage) — **đã implement đầy đủ** trong `_orbital_radius()`/`_orbital_dmg_value()`.

**Bug đã sửa (2026-07-27):** `WEAPON_PERK_FOLDER` (`arena_levelup_ui.gd`) dùng key sai cho 2 weapon — `"gatling"` thay vì kind thật `"gatling_gun"`, `"snake"` thay vì kind thật `"viper"` — khiến `_weapon_perk_icon_tex()` luôn bail sớm ở `WEAPON_PERK_FOLDER.has(kind)` (false) cho MỌI perk của Gatling Gun + Viper, rơi về icon weapon cha dù file art đã có sẵn đầy đủ (`Gatling/`, `snake/` folder, 6/6 file mỗi bên). Đã đổi key đúng theo kind thật (folder name giữ nguyên, chỉ đổi key dict).

**Scale — GPU stretch, KHÔNG CPU resize:** `_contain_box(native, max_w, max_h)` tính kích thước CONTAIN-fit (giữ aspect, cả 2 chiều đều ≤ box, trục nào chặt hơn quyết định) thuần toán học; `_fit_texture_rect(tex, max_w, max_h)` dựng `TextureRect` với `expand_mode=EXPAND_IGNORE_SIZE` + `stretch_mode=STRETCH_KEEP_ASPECT_CENTERED` — **y hệt cách weapon icon vẫn làm**, để GPU tự co giãn lúc vẽ. Đã thử CPU `Image.resize()` (kể cả LANCZOS) trước — nét kém hẳn so với GPU stretch dù cùng tỉ lệ thu nhỏ lớn (so sánh trực tiếp với weapon icon, nguồn cũng to tương đương ~2000-2900px). **Đừng quay lại CPU resize** cho icon aux/perk trừ khi có bằng chứng ngược lại.

**Hover vs Click trên Upgrade1-3 (mirror Weapon1-3):** 2 biến tách biệt —
- `_hover_preview_idx` (set bởi CẢ hover lẫn click, qua `_hover_option`/`_select_option`) → chỉ lái `_board_render_updesc()` + `_board_render_stats()` (preview). Hover KHÔNG rebuild lại 3 card, chỉ refresh 2 panel này (nhẹ).
- `_pending_pick_idx` (set CHỈ bởi click, qua `_select_option`) → lái VFX đỏ/xanh (`ucol` trong `_board_render_options`), Confirm commit target, VÀ icon trên `WeaponDisplay` (`_board_render_selected` ưu tiên `_current[_pending_pick_idx]` nếu có, fallback `_choices[_selected_idx]`). Reset về `-1` mỗi khi chuyển sang weapon/aux khác ở cột trái (`_select_item`) — tránh WeaponDisplay hiện nhầm icon perk của lựa chọn trước.

**Route cache** (`_route_cache: Dictionary`, key = `ckey` "w:kind"/"a:id"): `_gen_pool_choices`/`_gen_aux_pool_choices` (có `shuffle()`) chỉ chạy 1 lần/slot/màn hình — click qua lại giữa 3 weapon/aux không reroll perk. Clear ở đầu `_show_cards()` mỗi màn hình mới.

**Ô Upgrade trống** (ít hơn 3 option, pool cạn/capstone ít lựa chọn): VFX đen (`SCAN_COLOR_BLACK`) trên cả `UpgradeIcon`+`UpgradeName`, đồng bộ với cách StatDisplay/MainDisplay hiện khi "không phải item chọn được".
