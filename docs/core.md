# Core — Architecture, State & Scenes

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on autoloads, main scene, GameManager, persistence, main menu, settings, music player.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

## Changelog — 2026-08-18 — rubicon→electric code rename finished; new "mechanic" map added

- **Code rename completed**: the Electric map's display name changed from "Rubicon" to "Electric" back on
  2026-08-13, but that pass only renamed the asset folder (`assets/map/electric/`) — every script, class
  name, node group, `map_id` string, and cfg filename still said `rubicon`/`Rubicon`. On explicit request
  ("đừng để sót lại rubicon nào"), finished it: `scripts/gameplay/rubicon/` → `scripts/gameplay/electric/`
  (all 16 files renamed, `class_name Rubicon*` → `Electric*`), `rubicon_arena.gd` → `electric_arena.gd`,
  `scripts/ui/hud/rubicon_terrain_edit.gd`/`rubicon_light_edit.gd` → `electric_terrain_edit.gd`/
  `electric_light_edit.gd`, `tools/bake_rubicon_trees.gd`/`screenshot_rubicon.gd` → `bake_electric_trees.gd`/
  `screenshot_electric.gd`, `scenes/rubicon.tscn` → `electric.tscn`, `rubicon_terrain.cfg` →
  `electric_terrain.cfg`, `spawn_mode_2_wave_rubicon.cfg` → `spawn_mode_2_wave_electric.cfg`. Every
  `MetaManager.MAP_DEFS`/`RESCUE_MAP_QUEUE`/`arena.gd` `_map_id` comparison, every `add_to_group("rubicon_*")`
  node group, and every cross-file comment updated to match. Also fixed 3 Python bake tools
  (`generate_canopy_bump.py`/`generate_canopy_normal.py`/`generate_map_thumbnails.py`) that still hardcoded
  the now-nonexistent `assets/map/rubicon/...` path (stale since the folder-only rename, never caught before).
  Verified zero case-insensitive "rubicon" hits remain anywhere outside `.git/` history.
- **New playable map: Mechanic** (`assets/map/mechanic/`) — same background structure as Electric (real
  canopy-photo ground tiled + tinted by baked noise zones, a procedural river band, 3-layer parallax clouds,
  procedural spark motes, a generic `.glb` scatter/landmark engine currently empty pending future assets), new
  `scripts/gameplay/mechanic/` pipeline. One deliberate difference: Electric picks between 3 canopy photos per
  tile-set (`green`/`grey`); Mechanic uses all 7 of its supplied canopy photos together in one set
  (`electric_ground.gdshader`'s existing mottle-noise region-split technique extended from a 3-way to a 7-way
  blend — `mechanic_ground.gdshader`). No landmark-ring system yet (no landmark `.glb` exists for this map) and
  the tree-scatter pool is empty (no `.glb` models exist under `assets/map/mechanic/` yet) — both wired and
  ready, will activate automatically once such assets are dropped in, same bootstrap state Volcanic's trees
  were once in. Wired into `MetaManager.MAP_DEFS`/`hub_screen.gd`'s `LAUNCH_CARDS` (flips the existing
  "Mechanic — coming soon" placeholder into a real launch card) and `arena.gd`/`arena_hud_buttons.gd`'s
  per-map Terrain Edit / Light Edit dev panels. Explicitly NOT done this pass: a dedicated enemy wave timeline
  (`levels/arena/mechanic.json` + `arena_wave_editor.gd`'s `MAP_FIXED_FILES`/`MAP_ENEMY_FOLDERS`) — the
  `pros1-8`/`prosmotherblank` roster is already fully defined in `ENEMY_DEFS` but not yet scoped to this map,
  so it currently spawns the same generic `TEST_ROSTER` placeholder creeps any other un-timelined map does.

## Changelog — 2026-08-06 (7th pass) — Hover-bar slide animation contained within its own room's icon bounds

- Bug report: the popup's rise-up/slide-down animation visibly bled into the room BELOW it, worst on Launch/
  Bridge/Beacon. Root cause: `_show_bar()`'s slide-up start position was hard-coded "BAR_H (36px) below the
  docked target", which overshoots the hovered room's own bottom edge by `BAR_H − lift` px — 21px for the 9
  regular rooms, 31px for Launch/Pilot — regardless of how much room actually exists below that icon on the
  board. `_hide_bar()`'s slide-down had the identical overshoot in the opposite direction.
- Fixed by clamping both animations' start/end Y to the hovered room's OWN icon bounds
  (`over.position.y` .. `over.position.y + over.size.y`) — the bar's top edge never rises above the icon's
  top, its bottom edge never dips below the icon's bottom, for the full rise/fall, not just the resting
  position (which was already inside bounds and never the problem). `_hide_bar()` reuses `_bar_natural_pos`/
  new `_bar_icon_bottom` (both refreshed by the `_show_bar()` call that necessarily preceded it) since it
  doesn't receive `over`/`lift` directly.
- Composes cleanly with the 6th-pass move-offset fix: the clamp applies to the NATURAL (un-moved) position
  first, in container-local space, exactly as before; `_bar_offset` is still added on top afterward — a
  player who's deliberately moved the bar via hold-to-edit can still push it wherever they want, this only
  fixes the DEFAULT unedited animation's unwanted overshoot.

## Changelog — 2026-08-06 (6th pass) — Hover-bar MOVE now persists room-independently (closes the 5th-pass caveat)

- On request ("tính lại offset cho khớp với sửa đổi của tôi"): fixed the caveat disclosed at the end of the
  5th-pass entry — moving the shared `_hover_bar` now actually sticks across different rooms/hover cycles,
  not just during the drag itself.
- New generic `HudEditRuntime.edit_confirmed(id, control)` signal, emitted right after a save (Enter). Useful
  beyond this one case for any future registered element whose "natural" position/size is recomputed
  elsewhere rather than fixed.
- `dock_binder.gd` listens for it (scoped to `id == "dock.hover_bar"`) and derives a room-INDEPENDENT delta:
  `_bar_offset = <final absolute position> − <that same moment's "natural" un-moved position>` — the natural
  position is kept fresh every `_show_bar()` call (`_bar_natural_pos`; hover is frozen during editing per the
  5th pass, so it's still accurate the instant the signal fires). Persisted to the SAME
  `user://hud_layout_overrides.cfg` file HudEditRuntime itself uses, under its own `[dock_binder]` section so
  it doesn't collide with HudEditRuntime's `[hud_edit]` one.
- `_show_bar()` now applies that delta on top of whatever room's freshly-computed docked position, converted
  into the same coordinate space `_hover_bar.position` lives in once it's `top_level` (global/canvas space,
  vs. the container-local space `over.position` is naturally expressed in) — so "drag the popup down 40px
  while looking at Merchant" now means "every room's popup sits 40px lower than its own natural spot",
  exactly the room-independent behavior the original move feature needed. Before any move (`top_level` still
  false, offset still zero), this is a complete no-op — behaves exactly as it always did.
- Scope check: only `_hover_bar` needed this — `_hover_bar_label`'s position is set once at construction and
  never touched again by `_show_bar()`, so a saved label move already stuck correctly with no special-casing.

## Changelog — 2026-08-06 (5th pass) — HudEditRuntime: freeze ALL hover side-effects while any edit is active

- On request ("khi hiện bounding box thì đã pause function rồi... trong khi edit thì hover lên các room khác
  ko có tác dụng"): new `HudEditRuntime.is_active()` (true while ANY element anywhere is being edited — wider
  than the existing per-control `is_editing()`). `dock_binder.gd`'s `_wire_hover`/`_wire_launch` hover-enter/
  hover-exit/click handlers now check this instead of the narrower per-control check, so hovering a
  DIFFERENT room while editing has zero effect (no scale change, no `_show_bar()`/`_hide_bar()`, no click) —
  not just skipping the one element being edited. This is what makes moving/resizing the shared
  `_hover_bar`/`_hover_bar_label` stable DURING a drag: previously, so much as hovering another room mid-edit
  would still call `_show_bar()` and stomp the bar being repositioned.
- **Residual caveat, still open, stated plainly rather than implied fixed**: this only freezes _show_bar()
  DURING an edit session. It does not make `_show_bar()` itself aware of a saved position override once
  editing ends — the very next real hover (on any room, even after pressing Enter) still recomputes and
  tweens the bar to its normal per-room docked position from scratch, so a MOVED (not resized) bar position
  will look reset again as soon as you hover anything post-edit, even though the override IS still saved to
  disk correctly. A real fix would need `_show_bar()` to apply the saved override as a delta on top of its
  per-room computed position (since the bar's "natural" position differs per room, a saved ABSOLUTE position
  doesn't have one consistent meaning across rooms) — scoped out for now; resizing the bar has no such issue.

## Changelog — 2026-08-06 (4th pass) — HudEditRuntime: correct hit-target selection, hover-bar/label wired, arrow-key nudge

- **Bug fix: holding a room icon edited the wrong thing** ("giữ chuột vào overlay popup thì lại hiện bounding
  box của ảnh preview"). Root cause: the hold-detection loop picked whichever registered Control matched LAST
  in Dictionary iteration order when several overlapped the same screen point — arbitrary, not "whatever's
  visually on top/most specific". Fixed to pick the SMALLEST-area match instead (standard nested-hit-test
  behavior), and registered the two elements that were missing and causing the overlap in the first place:
  `dock_binder.gd`'s `_hover_bar` (the popup background) and `_hover_bar_label` (its text) — now, per
  request, "giữ vào overlay pop up thì sửa pop-up, giữ vào text thì sửa text, giữ vào ảnh preview thì sửa
  ảnh" all resolve to 3 different elements correctly. Caveat disclosed, not hidden: RESIZING `_hover_bar`
  persists fine (nothing else touches its `.scale`), but MOVING it doesn't yet stick across separate hover
  cycles — `_show_bar()` unconditionally re-tweens `.position`/resets `.size` on every hover, which isn't
  aware of a saved top_level override the way the room-icon hover-zoom was made aware of a saved base scale.
- **Arrow-key nudge** ("Gán các phím mũi tên để di chuyển ảnh theo các hướng"): while editing, holding
  Left/Right/Up/Down now moves the element continuously (`NUDGE_SPEED` 120px/s, polled every frame rather
  than relying on OS key-repeat timing) — an alternative to mouse-drag for the same move feature added last
  pass. Reuses the same `top_level` escape-hatch (`_ensure_top_level()`, now shared by both the mouse-drag
  and nudge code paths) and the same Ctrl+Z/Esc/Enter handling. Arrow-key events are consumed while editing
  (`set_input_as_handled()`) so they don't also leak through to gameplay underneath (e.g. ship movement).

## Changelog — 2026-08-06 (3rd pass) — HudEditRuntime: move support, click-through-after-edit fixes, Dock room icons wired

- **Move (bug report: "chưa drag được item đi")**: dragging an editable Control's BODY (not a handle) now
  moves it, alongside the existing corner/edge resize. Same "escape the parent Container's layout" problem as
  resize (see the 2nd-pass entry's `.scale` rationale below), solved the same way but for position: the first
  time an element is ever moved, it flips `top_level = true` (computing an equivalent global position first so
  there's no visual jump) — this makes `position` relative to the nearest CanvasLayer instead of the parent
  Container's layout, which can then no longer fight a manual position change. Ctrl+Z/Esc/Enter all now cover
  position + `top_level` alongside scale + pivot; `register()` re-applies a saved move (not just a saved
  resize) to every freshly rebuilt replacement Control.
- **Bug fix: releasing after a hold-to-edit still fired the element's click** (reported on the new MAIN MENU
  button — holding it 3s, resizing, then releasing immediately jumped to the Main Menu). Root cause: a Button
  arms itself on the ORIGINAL mouse-down that started the 3s hold; blocking new input via the overlay doesn't
  retroactively un-arm it, so Godot still fired `pressed` on release regardless of what was drawn on top. Fix:
  `_enter_edit()` now explicitly `disabled = true`s the target if it's a `BaseButton`, restored in
  `_exit_edit()` — covers every registered Button/CheckButton/etc. at once, not just the one reported.
- **Dock board room icons wired** (bug report: holding "mechanic"/"launch"/etc. showed no bounding box at
  all — they were never registered, on purpose, per the 2nd-pass entry's disclosed gap). Now fixed properly
  instead of left open: `dock_binder.gd`'s `_wire_hover` (the 9 scale-based-hover rooms) and `_wire_launch`
  (the visibility-swap-based Launch room) both call `HudEditRuntime.register()`. The scale-conflict flagged
  previously (`_wire_hover`'s existing 1.0↔1.05 hover-zoom ALSO drives `.scale`) is resolved by new public
  `HudEditRuntime.get_base_scale(id)` / `is_editing(control)` helpers: the hover-zoom now multiplies
  `HOVER_SCALE` on top of the persisted base scale instead of overwriting `.scale` outright, and skips
  touching the node entirely while it's the thing actively being edited. The SAME "click fires after edit"
  bug as the Main Menu button applied here too, in a different shape: the thing edited (`node`, the visible
  icon) isn't a Button at all, so the BaseButton-disable fix above doesn't reach it — the ACTUAL click-catcher
  is a separate invisible overlay `btn`. Fixed by guarding `btn.pressed`'s `room_clicked.emit(...)` (and
  `_wire_launch`'s hover-art-swap handlers) behind `not HudEditRuntime.is_editing(node)`.

## Changelog — 2026-08-06 (2nd pass) — New player-facing HUD resize system (HudEditRuntime), piloted on the Dock

- **New autoload `HudEditRuntime`** (`scripts/autoload/hud_edit_runtime.gd`), on request: press-and-hold ANY
  opted-in Control for 3s without moving the mouse (>6px cancels the hold, so it doesn't false-trigger during
  a click/drag/scroll) → a cyan bounding-box overlay with 8 yellow drag handles appears (4 corners =
  proportional rescale, opposite corner stays anchored; 4 edge midpoints = single-axis stretch, opposite edge
  stays anchored). While editing: Ctrl+Z reverts the last finished drag, Esc cancels the whole session
  (reverts to how it looked before this hold), Enter confirms and **persists permanently** to
  `user://settings.cfg`-adjacent `user://hud_layout_overrides.cfg`, re-applied automatically next launch.
- **Deliberately separate from the existing dev-only edit-mode family** (`hud_edit_mode.gd`/
  `boss_edit_mode.gd`/`creep_edit_mode.gd`/`fleet_edit_mode.gd`, toggled by the `toggle_edit_mode` key) — this
  is a new, parallel, always-on PLAYER system; none of that code was touched.
- **Implementation choice: resize via `Control.scale`, not size/position.** Nearly every candidate element
  lives inside a VBoxContainer/HBoxContainer/GridContainer, which recomputes (and would silently overwrite)
  a child's `size`/`position` every layout pass — `scale` is a pure rendering transform layered on TOP of
  that computed layout, so it survives regardless of what kind of container the element happens to sit in.
  Disclosed trade-off: a scaled-up element can visually overlap its neighbors, since the container still only
  reserves space for the element's *unscaled* size.
- **Granularity, per explicit request: the finest — every individual Label/TextureRect/Button is its own
  editable unit**, not grouped into panels.
- **Scope so far — the Dock screen only** (`hub_screen.gd`): Back button, coin icon + coin total label, every
  sub-tab button (Loadout/Weapon/Hull/Thruster/Shield/Aux/Craft/Fragments/Passives), and — since
  `_make_grid_cell()`/`_build_merchant_preview()` are shared, this covers BOTH the Loadout tab's cells AND
  every Merchant tab's cells "for free" — each grid cell's icon/name/price label, plus the Merchant preview
  panel's icon/name/price-icon/price/description/stats/Buy-button. IDs are stable across UI rebuilds (e.g.
  `"dock.grid_cell.<def_id>.icon"`, `"dock.merchant.preview.name"`) — `register()` re-applies a saved override
  to the freshly-built replacement Control every time `_refresh()` tears down and rebuilds `_content`
  (unavoidable given how often Merchant/Loadout rebuild their grids). One deliberate side effect: since the
  grid-cell ID is keyed by `def_id` alone (not by which tab it's showing in), resizing e.g. "gatling_gun"'s
  icon in the Loadout tab also resizes it in the Merchant Weapon tab, since it's treated as the same logical
  element — not flagged as a problem, just worth knowing.
- **Also not yet wired**: the Hub's Loadout-specific chrome beyond what `_make_grid_cell` already covers, and
  every other scene's HUD (arena, main menu, settings, level-up, inventory) — per the user's own stated plan
  to request those one at a time after validating this pilot.
- Per spec, this system only ever registers UI Controls explicitly opted in via `register()` calls added to
  UI-building scripts — nothing in `arena_enemy.gd`/wave directors/volcanic terrain/etc. calls it, so "doesn't
  work on terrain/map/creep during gameplay" holds automatically, not by any special-case exclusion logic.

## Changelog — 2026-08-06 — Real coin art, diamond→multi-coin drop, Merchant preview panel, Custom Mouse cursor

- **Real coin icon** (user supplied `assets/screen/coin.png`, replacing the old text-glyph/placeholder
  stand-ins): `arena_stats_hud.gd`'s top-right coin counter — was a plain yellow `ColorRect` placeholder
  (its own comment said "swap for a coin icon later") — is now a `TextureRect` at the same `TR_ICON` (26px)
  box, aspect-preserved. `hub_screen.gd`'s Merchant header coin total swapped its `"⬤ %d"` text-glyph for a
  real `TextureRect` + plain number. Left AS-IS (out of the explicitly named scope — "merchant" + "arena"
  only): the Engineer→Passives buy-button price ("%d ⬤") and the dock-interest notification text, both still
  using the "⬤" glyph.
- **Diamond loot → multi-coin drop**: only one "diamond" drop mechanism exists in the whole codebase
  (`arena_small_ruin.gd`'s `LOOT_POOL`, small-ruin-box loot, uniform-random among coin/diamond/heart/
  magnetic/divinity — diamond was never a bigger reward, just a reskin of the same 50-value coin). Per
  confirmed spec: rolling "diamond" now scatters `DIAMOND_COIN_COUNT` (5) individual "coin" pickups worth
  `DIAMOND_COIN_VALUE` (10) each — 5×10 = the old diamond's 50, same total value, just visually several coins
  instead of one gem. `assets/screen/diamond.png` is now unreferenced by any code path (left in place,
  not deleted — an asset file, not code).
- **Merchant rebuilt again**: on request, replaced the click-to-buy-directly grid + hover tooltip (from the
  prior pass) with a **selection + detail-preview** model. Grid cells now just SELECT an item
  (`_merchant_selected_id`, persists across `_refresh()` within a tab, cleared on tab switch) instead of
  buying; the persistent price label on each cell is now a STATE WORD instead of a coin number — "Owned" /
  "Blue Print Required" / "Not Enough Coin" / "Buy" (`_merchant_state_text`/`_merchant_state_color`). A new
  fixed-width panel to the right of the grid (`_build_merchant_preview`) shows the selected item's large
  icon, name, price (icon + number — the only place a Merchant price still shows), description, every scalar
  `stats` key/value, and its own Buy button that dims (`modulate.a = 0.55`) and shows the same state word
  when not actually purchasable. The old per-cell hover tooltip (`Control.tooltip_text`) is gone entirely —
  superseded by the always-visible preview panel.
- **Custom Mouse cursor** (new Settings feature, entirely in-memory — no source PNG is ever read-modified-
  written back to disk): `GameManager.CURSOR_OPTIONS` lists Default + 13 enemy/inventory/aux/weaponry icons
  spanning 4 different asset folders. Picking one in the Settings panel's new 4×4 grid popup
  (`settings_panel.gd`'s `_open_cursor_picker`/`_build_cursor_popup` — 14 populated 20px cells + 2 blank
  hidden filler cells, since 14 doesn't evenly fill a 4×4=16 grid) calls `GameManager.apply_cursor(id)`:
  renders the source icon into a throwaway `SubViewport` rotated 30° counter-clockwise (GPU does the
  rotation — deliberately sidesteps `CompressedTexture2D` not being CPU-pixel-readable, the same constraint
  [[traveler_texture_scaling]] hit before), waits 2 frames for it to actually draw, captures + autocrops the
  transparent margins + rescales to 10px wide (aspect preserved — dialed down from the original 30px ask,
  which read as too big) via `Image.resize(..., INTERPOLATE_LANCZOS)`, then calls
  `Input.set_custom_mouse_cursor()` with the result. The pick is saved to `user://settings.cfg`'s
  `[game] cursor_id` (same file/section family as `dev_mode`/`fps`/`auto_aim`) and restored once at boot via
  `GameManager._apply_saved_cursor()` (called from its own `_ready()`, since `Input.set_custom_mouse_cursor`
  is a global OS-level call that persists across scene changes on its own — no per-scene re-apply needed,
  unlike `auto_aim`'s per-arena-instance re-arm). **Caveat**: this couldn't be visually verified from here —
  parse-checks confirm the code is syntactically sound, but headless Godot doesn't reliably rasterize a
  SubViewport the same way a normal windowed run does, so the actual rotated/rescaled cursor appearance
  should be spot-checked in a real run.

## Changelog — 2026-08-05 (3rd pass) — Kill-coins, dock interest passive, Merchant rename + 5-tab rebuild, reset-profile equipment bug fixed

- **XP require halved**: `GameManager.BASE_XP` 1875.0 (×0.5, this pass — was 3750.0 from the same day's earlier
  ×5 pass; see the 2nd-pass entry below). Pure magnitude change, curve shape (`GROWTH`/`LEVEL_XP_MULT`)
  untouched.
- **Kill-coins**: `GameManager.add_kill()` now mints 1 coin (`add_money(1)`, live, same as a normal pickup)
  every `KILLS_PER_BONUS_COIN` (100) cumulative kills this run.
- **Dock interest** (new mechanic): `MetaManager.apply_dock_interest()` — on returning to the dock (both of
  `arena.gd`'s "RETURN TO DOCK" handlers call it right before `change_scene_to_file(hub.tscn)`), pays
  `money × (5% + 2%×interest_boost passive rank)` straight into `GameManager.money`, but ONLY if
  `GameManager.run_time >= 600.0` (10 real minutes of unpaused play) — sub-10-minute runs earn nothing, closing
  off a farm-by-instant-requitting exploit. New passive `PASSIVE_DEFS["interest_boost"]` ("Cunning Engineer",
  max 5, +2%/level, so 5–15% total) shows up automatically in the Engineer → Passives tab (fully data-driven,
  no separate UI code needed). The payout is relayed to the Hub via a new transient
  `GameManager.pending_interest_notice: int`, read + cleared once in `hub_screen.gd._ready()`, which shows a
  new dismissible top-right notification card (`_show_interest_notification()` — separate from the existing
  centered `_toast`/`_show_toast`, since this one needs a manual "✕" AND a 5s auto-dismiss-with-slide-down,
  neither of which the old toast supports) reading "The Engineer built and sold spare weapons, bringing you
  N ⬤ in interest."
- **Reset-Profile bug fixed**: "equipment still shows Arc/Death Beam/Gauss after reset" traced to
  `MetaManager.unlocked_weapon_kinds()` blanket-including all of `ArenaWeapons.CHEST_POOL` (the 4
  start-of-run-chest weapons) as always-pickable in the Hub's Loadout tab, REGARDLESS of actual ownership —
  true for every profile, not just post-reset ones, so a truly fresh save had the exact same "extra weapons"
  appearance. Fixed to require real ownership (`blueprints`/`crafted_uniques`) for every kind, CHEST_POOL
  included. Per explicit clarification, `MetaManager.buy_weapon()` now exempts CHEST_POOL ids from its
  blueprint-ownership check (still coin-gated) and auto-`unlock_blueprint()`s on first purchase, so
  gatling_gun/death_beam/arc/gauss stay trivially available from the Merchant without ever needing a boss-drop
  blueprint — they just aren't pre-equipped for free anymore. The in-run start-of-run chest
  (`arena_weapon_chest_ui.gd`) reads `CHEST_POOL` directly and is untouched by any of this.
- **"Mechanic" room renamed to "Merchant"** (display-only, on request): `dock_binder.gd`'s hover-bar/click
  label is derived from the room's asset `file` name via `.capitalize()` — added a `ROOM_NAME_OVERRIDE`
  dict (`{"mechanic": "Merchant"}`) rather than renaming the actual asset (`assets/hud/dock/mechanic.png`) or
  `config/boards/dock.cfg`'s group name (which turned out to be UNUSED for the label — only the child item's
  `file` field feeds it), matching the existing "keep internal id, override display only" precedent
  (`MetaManager.MAP_DEFS`'s electric/default → Electric/Space rename). `hub_screen.gd`'s `ROOM_PANELS` key
  updated to match (`room_clicked` now emits "Merchant"). NOT touched: `hub_screen.gd`'s `LAUNCH_CARDS` also
  has an unrelated `{"name": "Mechanic"}` entry — that's a "coming soon" MAP-name placeholder (alongside
  "Atlantic"/"Arctic"), coincidentally the same word, nothing to do with the shop room.
- **Merchant rebuilt from one flat "Shop" tab into 5** (Weapon/Hull/Thruster/Shield/Aux, on request — Aux
  added on top of the requested 4 after finding 15 "aux" items in `ITEM_DEFS` with no shop presence
  anywhere): new `MetaManager.shop_ids_by_tag(tag)` returns every non-unique `ITEM_DEFS` id carrying that tag
  (craft-only uniques are excluded from all 5 — they stay Craft-tab-only). Every item is now listed
  regardless of ownership (previously the Weapon tab only showed blueprint-owned ones); `_make_grid_cell()`
  gained `btn_color`/`bg_override`/`show_persistent_label` params to support 3 read-at-a-glance states:
  gray bg + gray price (needs a blueprint — Weapon tab only, CHEST_POOL exempted), red price (owns no
  blueprint issue, just short on coin), normal (buyable). Clicking a gray/red cell now always fires (cell
  clicks used to be disconnected entirely when `btn_disabled` was true) and shows
  "I need blue print to make this" / "I need more coin to make this" via the existing `_show_toast()` — safe
  for the untouched Loadout tab too, since `MetaManager.toggle_loadout()` already no-ops harmlessly on an
  invalid pick.
- **Hover tooltips** added to every Merchant cell (`Control.tooltip_text`, Godot's native hover popup — no
  custom widget needed): item name, `desc`, then every scalar `stats` key formatted "Key: value" (damage,
  bonus_hp, armor, shield_points, cooldown_sec, whatever that item actually has).
- **Icon audit** (requested: delete non-functional stubs, report functional-but-iconless ones): found exactly
  14 `ITEM_DEFS` entries with `"icon": ""` — 10 unique/craft-only weapons (Singularity Lance, Hailstorm,
  Wraithfire, Hivemind, Prism Array, Graviton Well, Thunderhead, Annihilator, Omega Swarm, Event Horizon) and
  4 thrusters (Strong/Reverse/Smart/Bulwark). Verified EVERY one against `arena_weapons.gd`/`arena.gd` — all
  14 are fully implemented (own `activate_*()`, damage rolls, upgrade ranks for the 10 weapons;
  `thruster_type`-branched movement code in `arena.gd._physics_process` for the 4 thrusters). **None deleted
  — none are stubs.** Notable side-effect found: `MetaManager.unique_ids()` (feeds the Craft tab) filters on
  `unique==true AND icon != ""`, so all 10 of those weapons are currently invisible in Craft too — adding
  their icons will also be what makes them craftable/obtainable at all, not just prettier.

## Changelog — 2026-08-05 — XP pacing rebalance: drop ×10, level requirement ×5 (net ~2× faster leveling)

- On request, two DIFFERENT multipliers this time (not a matched units rescale like 2026-07-28's 2nd pass
  below): `GameManager.BASE_XP` 750.0→**3750.0** (×5 — the level-requirement curve; `GROWTH`/`LEVEL_XP_MULT`
  ratios untouched, so the curve's SHAPE is unchanged, only its overall height), while every creep XP-drop
  source (see [`enemy.md`](enemy.md)'s matching entry) went ×10. Net effect: kills-needed-per-level drops
  ~2× (10÷5) — a genuine grind-speed buff, unlike the 2026-07-28 pass which kept pacing identical.
- `XP_PER_ASTEROID` 0.5→**5.0**, `XP_PER_BOSS` 250.0→**2500.0**, `XP_ASTEROID_SIZE_DIV` 12.0→**1.2** (÷10, so
  `xp_for_asteroid()`'s size-based bonus term scales ×10 too, matching the flat term) — included per explicit
  scope decision (asteroids/boss-lump aren't HP-based like creep XP, so this was asked about rather than
  assumed).
- `creep_info_panel.gd`'s HP→XP auto-fill button formula updated `round(HP/100)` → `round(HP/10)` (min 1→10)
  to match the new creep-XP scale.
- Caught and fixed a side effect: `arena_xp_orb_manager.gd`'s `TIER_*_MAX`/`TIER_*_MULT` (orb color/size
  breakpoints, keyed to the raw xp `value`) needed the same `×10 threshold / ÷10 mult` rescale the 2026-07-28
  pass below already required once — otherwise every orb would visually over-tier again.

## Changelog — 2026-08-02 — Settings panel: new "Auto-Aim" toggle, persisted like Dev Mode/FPS

- Exposes `arena_hud_buttons.gd`'s existing `_auto_fire` flag (ship auto-faces the nearest enemy instead of
  the mouse — `arena.gd._aim()`; previously only reachable via the dev-cluster AUTO button) as a regular
  Settings-panel `CheckButton`, following the exact same pattern as the Dev Mode/FPS switches
  (`settings_panel.gd`): `_cur_auto_aim`/`_snap_auto_aim` state, live-apply via group "arena_hud_buttons" +
  new public `arena_hud_buttons.gd.set_auto_aim(v)` (keeps the dev AUTO button's own label/color in sync),
  persisted to `user://settings.cfg`'s `[game] auto_aim` key on Save, re-armed at the start of every arena
  load (`arena_hud_buttons.gd._ready()`, mirroring the existing `dev_mode` re-arm).

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


