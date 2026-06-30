# Cockpit-Frame HUD Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the arena HUD into a procedural cockpit frame — weapons in a left vertical column (4), passives in a right vertical column (4), player vitals (nested shield+HP bar) bottom-center, a shorter XP bar at the bottom, and a boss vitals bar top-center that mirrors the player and shows only during a boss fight.

**Architecture:** One new shared procedural widget `arena_vitals_bar.gd` (poll-based, `player` or `boss` mode) drives both the bottom player bar and the top boss bar so they mirror. A new `arena_hud_frame.gd` draws the angled cockpit bezels procedurally. The existing weapon/aux slot widgets are relocated to vertical edge columns (add a `_slot_rect(i)` helper computed from viewport size), the XP bar is shortened, and `arena.gd::_build_ui()` is rewired. The legacy `hud_hp_display.gd` and `boss_hp_bar.gd` are left untouched (the legacy non-arena game still uses them); the arena simply stops instantiating `hud_hp_display`.

**Tech Stack:** Godot 4 GDScript; Control widgets on the arena "UI" CanvasLayer; `_draw()` procedural drawing; `GameManager` polled each frame for HP/shield/boss state.

## Global Constraints

- Static typing throughout; tabs for indentation.
- No test suite — gate each task on `godot --headless --path . --quit-after 8` (boot-compiles the arena, which instantiates the HUD with autoloads). `--check-only` is NOT sufficient — it misses identifier errors in unreached functions. Ignore unrelated `lasgun_ani_1.gd` texture lines. State that runtime/visual is unverified until manual F5.
- Draw bezels procedurally (no art); keep them in one widget so art can replace them later.
- Display-only: no HP/shield/XP mechanic changes. Slot caps already 4 (`MAX_WEAPONS`, `MAX_AUX`).
- Shell is PowerShell; the Bash tool runs the headless check.
- These files are NOT locked. Do not edit locked files.

## File Structure

- **Create:** `scripts/ui/hud/arena_vitals_bar.gd` — procedural nested shield+HP bar; `player`/`boss` mode; polls `GameManager`; boss instance auto-hides when no boss.
- **Create:** `scripts/ui/hud/arena_hud_frame.gd` — procedural angled cockpit bezels on the 4 edges (one Control, `_draw` polylines).
- **Modify:** `scripts/ui/hud/arena_weapon_slots.gd` — replace fixed top-left row with a left-edge vertical column via `_slot_rect(i)`.
- **Modify:** `scripts/ui/hud/arena_aux_slots.gd` — right-edge vertical column via `_slot_rect(i)`.
- **Modify:** `scripts/ui/hud/arena_stats_hud.gd` — shorter XP bar.
- **Modify:** `scripts/gameplay/arena.gd` (`_build_ui`, ~224-235) — add frame + player/boss vitals bars; drop `hud_hp_display`; keep weapon/aux/stats.

---

### Task 1: Player + boss vitals bar (`arena_vitals_bar.gd`)

**Files:**
- Create: `scripts/ui/hud/arena_vitals_bar.gd`
- Modify: `scripts/gameplay/arena.gd` (`_build_ui`)

**Interfaces:**
- Produces: a `Control` script with `var mode: String` (`"player"` | `"boss"`) set before `add_child`. Polls `GameManager` each frame; player mode reads `ship_hp`/`ship_max_hp`/`ship_shield`/`shield_capacity_total()`, boss mode reads `boss_hp`/`boss_max_hp` (+ `is_boss_active()`), shield 0.
- Consumes (arena): instantiated twice in `_build_ui`.

- [ ] **Step 1: Create `scripts/ui/hud/arena_vitals_bar.gd`**

```gdscript
extends Control
## Procedural player/boss vitals bar: an OUTER shield layer (blue, fills left→right) framing an INNER main
## HP box (fills left→right), with HP and shield readouts. One widget, two modes — `mode = "player"` pins it
## bottom-center and reads the ship's HP/shield; `mode = "boss"` pins it top-center, reads the boss HP (shield
## 0), and is visible only during a boss fight. Poll-based (reads GameManager each frame) for robustness.

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const BAR_W := 440.0          # bar width (px)
const BAR_H := 46.0           # bar height (px)
const SHIELD_PAD := 7.0       # HP inner box inset from the shield outer frame (the visible shield band)
const BOTTOM_MARGIN := 16.0   # player: gap from the bottom screen edge
const TOP_MARGIN := 12.0      # boss: gap from the top screen edge
const HP_COL    := Color(0.30, 0.85, 0.45, 0.95)
const HP_LOW    := Color(0.90, 0.30, 0.25, 0.95)
const SHIELD_COL := Color(0.35, 0.70, 1.0, 0.95)
const TRACK_COL := Color(0.05, 0.06, 0.09, 0.9)
const BORDER_COL := Color(0.4, 0.55, 0.85, 0.95)

var mode: String = "player"
var _font: FontFile = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) as FontFile

func _process(_delta: float) -> void:
	if mode == "boss":
		visible = GameManager.boss_max_hp > 0 and GameManager.boss_hp > 0
	queue_redraw()

func _origin() -> Vector2:
	var vp := get_viewport_rect().size
	var x := (vp.x - BAR_W) * 0.5
	var y := (vp.y - BAR_H - BOTTOM_MARGIN) if mode == "player" else TOP_MARGIN
	return Vector2(x, y)

func _vitals() -> Dictionary:
	if mode == "boss":
		var bmax := float(maxi(1, GameManager.boss_max_hp))
		return {"hp": float(GameManager.boss_hp), "hp_max": bmax, "sh": 0.0, "sh_max": 0.0}
	var hpmax := float(maxi(1, GameManager.ship_max_hp))
	var shmax: float = GameManager.shield_capacity_total() if GameManager.has_method("shield_capacity_total") else 0.0
	return {"hp": float(GameManager.ship_hp), "hp_max": hpmax, "sh": GameManager.ship_shield, "sh_max": shmax}

func _draw() -> void:
	if mode == "boss" and not visible:
		return
	var v := _vitals()
	var o := _origin()
	var outer := Rect2(o, Vector2(BAR_W, BAR_H))
	# Shield outer layer: dark track + blue L→R fill (shows as a band around the HP box).
	_rounded(outer, TRACK_COL, 8.0)
	var sh_max: float = v["sh_max"]
	if sh_max > 0.0:
		var sf := clampf(float(v["sh"]) / sh_max, 0.0, 1.0)
		_rounded(Rect2(o, Vector2(BAR_W * sf, BAR_H)), SHIELD_COL, 8.0)
	# HP inner main box: dark track + L→R fill.
	var inner := outer.grow(-SHIELD_PAD)
	_rounded(inner, TRACK_COL, 6.0)
	var hf := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
	var hp_col: Color = HP_COL if hf > 0.3 else HP_LOW
	_rounded(Rect2(inner.position, Vector2(inner.size.x * hf, inner.size.y)), hp_col, 6.0)
	# Border around the whole bar.
	_border(outer, BORDER_COL, 8.0)
	# Readouts: HP on the inner box, shield small at the top-right of the outer frame.
	if _font != null:
		var hp_txt := "%d / %d" % [int(round(v["hp"])), int(v["hp_max"])]
		draw_string(_font, Vector2(inner.position.x + 8.0, inner.position.y + inner.size.y * 0.72),
			hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		if sh_max > 0.0:
			var sh_txt := "SH %d / %d" % [int(round(v["sh"])), int(sh_max)]
			draw_string(_font, Vector2(o.x + BAR_W - 110.0, o.y + 13.0),
				sh_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SHIELD_COL)

func _rounded(rect: Rect2, col: Color, r: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r))
	draw_style_box(sb, rect)

func _border(rect: Rect2, col: Color, r: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = col
	sb.set_corner_radius_all(int(r))
	draw_style_box(sb, rect)
```

- [ ] **Step 2: Wire into `arena.gd::_build_ui()`** — drop `hud_hp_display`, add the two vitals bars. Replace the existing block:

Old (`scripts/gameplay/arena.gd`, in `_build_ui`):
```gdscript
	var hp := HudHpDisplayScript.new()
	hp.arena_mode = true   # re-pin the HP cluster to the top-left corner (legacy keeps its layout pos)
	ui.add_child(hp)
	ui.add_child(WeaponSlotsScript.new())   # 5 weapon slots + cooldown pies, just below the HP cluster
	ui.add_child(AuxSlotsScript.new())      # 5 aux-item slots in a second row below the weapon slots
	ui.add_child(ArenaStatsHudScript.new()) # XP bar (bottom) + kill/coin counters (top-right)
```
New:
```gdscript
	var player_vitals := VitalsBarScript.new()
	player_vitals.mode = "player"           # bottom-centre nested shield+HP bar (replaces hud_hp_display)
	ui.add_child(player_vitals)
	var boss_vitals := VitalsBarScript.new()
	boss_vitals.mode = "boss"               # top-centre, mirrors the player bar; auto-hides when no boss
	ui.add_child(boss_vitals)
	ui.add_child(WeaponSlotsScript.new())   # left vertical column of weapon slots
	ui.add_child(AuxSlotsScript.new())      # right vertical column of aux slots
	ui.add_child(ArenaStatsHudScript.new()) # shorter XP bar (bottom) + kill/coin counters (top-right)
```

- [ ] **Step 3: Add the preload** near the other HUD preloads at the top of `arena.gd` (after `HudHpDisplayScript`):

```gdscript
const VitalsBarScript    := preload("res://scripts/ui/hud/arena_vitals_bar.gd")  # player + boss vitals bars
```
(Leave `HudHpDisplayScript` preload in place even though the arena no longer instantiates it — harmless, and avoids touching unrelated lines.)

- [ ] **Step 4: Boot-compile check**

Run: `godot --headless --path . --quit-after 8 2>&1 | grep -iE "arena_vitals_bar|arena.gd|Compile Error|Parse Error|Identifier" | grep -vi lasgun_ani`
Expected: no output (clean).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/hud/arena_vitals_bar.gd scripts/gameplay/arena.gd
git commit -m "Cockpit HUD: player + boss vitals bar (nested shield+HP)"
```

---

### Task 2: Procedural cockpit frame (`arena_hud_frame.gd`)

**Files:**
- Create: `scripts/ui/hud/arena_hud_frame.gd`
- Modify: `scripts/gameplay/arena.gd` (`_build_ui` — add the frame first so it draws behind the widgets)

**Interfaces:**
- Produces: a `Control` that draws angled bezel polylines on all four edges from the viewport size.

- [ ] **Step 1: Create `scripts/ui/hud/arena_hud_frame.gd`**

```gdscript
extends Control
## Procedural cockpit-frame bezels: angled trapezoidal outlines hugging the four screen edges, leaving the
## centre open for gameplay. Pure decoration (drawn behind the HUD widgets). No art — swap to textures later
## by replacing _draw. Recomputes from the viewport size every frame so it tracks window resizes.

const LINE_COL := Color(0.32, 0.50, 0.78, 0.85)
const LINE_W := 2.0
const M := 6.0        # outer margin from the screen edge
const SIDE_INSET := 70.0   # how far the left/right bezels reach in from the edge at their widest
const SIDE_TOP := 0.22     # left/right bezel spans this fraction of the height (top..bottom)
const SIDE_BOT := 0.78
const TB_INSET := 70.0     # how far the top/bottom bezels reach in (vertically)
const TB_SIDE := 0.24      # top/bottom bezel spans this fraction of the width (left..right)
const CHAMFER := 48.0      # diagonal corner cut length

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	# Left bezel (vertical trapezoid open toward the centre).
	_poly([
		Vector2(M, vp.y * SIDE_TOP),
		Vector2(M + SIDE_INSET, vp.y * SIDE_TOP + CHAMFER),
		Vector2(M + SIDE_INSET, vp.y * SIDE_BOT - CHAMFER),
		Vector2(M, vp.y * SIDE_BOT),
	])
	# Right bezel (mirror).
	_poly([
		Vector2(vp.x - M, vp.y * SIDE_TOP),
		Vector2(vp.x - M - SIDE_INSET, vp.y * SIDE_TOP + CHAMFER),
		Vector2(vp.x - M - SIDE_INSET, vp.y * SIDE_BOT - CHAMFER),
		Vector2(vp.x - M, vp.y * SIDE_BOT),
	])
	# Top bezel (horizontal trapezoid).
	_poly([
		Vector2(vp.x * TB_SIDE, M),
		Vector2(vp.x * TB_SIDE + CHAMFER, M + TB_INSET),
		Vector2(vp.x * (1.0 - TB_SIDE) - CHAMFER, M + TB_INSET),
		Vector2(vp.x * (1.0 - TB_SIDE), M),
	])
	# Bottom bezel (mirror).
	_poly([
		Vector2(vp.x * TB_SIDE, vp.y - M),
		Vector2(vp.x * TB_SIDE + CHAMFER, vp.y - M - TB_INSET),
		Vector2(vp.x * (1.0 - TB_SIDE) - CHAMFER, vp.y - M - TB_INSET),
		Vector2(vp.x * (1.0 - TB_SIDE), vp.y - M),
	])

func _poly(pts: Array) -> void:
	var pv := PackedVector2Array(pts)
	draw_polyline(pv, LINE_COL, LINE_W, true)
```

- [ ] **Step 2: Add the frame in `arena.gd::_build_ui()`** — add it FIRST (so it's behind the widgets), right after `_ui_layer = ui`:

```gdscript
	ui.add_child(HudFrameScript.new())      # procedural cockpit bezels (drawn behind the HUD widgets)
```

- [ ] **Step 3: Add the preload** near the other HUD preloads in `arena.gd`:

```gdscript
const HudFrameScript     := preload("res://scripts/ui/hud/arena_hud_frame.gd")   # procedural cockpit bezels
```

- [ ] **Step 4: Boot-compile check** — Run the Task-1 grep command; expected clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/hud/arena_hud_frame.gd scripts/gameplay/arena.gd
git commit -m "Cockpit HUD: procedural edge bezels"
```

---

### Task 3: Weapon slots → left vertical column

**Files:**
- Modify: `scripts/ui/hud/arena_weapon_slots.gd`

**Interfaces:**
- Produces: `_slot_rect(i: int) -> Rect2` (a left-edge vertical column, vertically centered, computed from the viewport). `_draw` and `_update_hover_tip` use it.

- [ ] **Step 1: Replace the layout constants + add `_slot_rect`.** Change the `ORIGIN`/`SLOT`/`GAP` consts block:

Old:
```gdscript
const ORIGIN := Vector2(12.0, 82.0)   # top-left of the first slot — ~8px (~0.2cm) below the HP bar's bottom edge
const SLOT   := 30.8                   # slot side (px) — 30% smaller than the original 44
const GAP    := 5.6                    # gap between slots (px) — 30% smaller than the original 8
```
New:
```gdscript
const SLOT   := 46.0                   # slot side (px) — left-edge vertical column
const GAP    := 12.0                   # gap between slots (px)
const LEFT_MARGIN := 16.0              # x of the column from the left screen edge

## i-th slot rect: a vertical column pinned to the left edge, vertically centered on screen.
func _slot_rect(i: int) -> Rect2:
	var vp := get_viewport_rect().size
	var n := ArenaWeapons.MAX_WEAPONS
	var total_h := SLOT * float(n) + GAP * float(n - 1)
	var y0 := (vp.y - total_h) * 0.5
	return Rect2(Vector2(LEFT_MARGIN, y0 + float(i) * (SLOT + GAP)), Vector2(SLOT, SLOT))
```

- [ ] **Step 2: Update `_update_hover_tip()`** to use `_slot_rect`. Replace its loop body:

Old:
```gdscript
	var mpos := get_local_mouse_position()
	for i in acquired.size():
		var r := Rect2(ORIGIN + Vector2(float(i) * (SLOT + GAP), 0.0), Vector2(SLOT, SLOT))
		if r.has_point(mpos):
			_tip.text = _code_for(String(acquired[i]))
			_tip.reset_size()
			var sx := ORIGIN.x + float(i) * (SLOT + GAP) + SLOT * 0.5 - _tip.size.x * 0.5
			_tip.position = Vector2(sx, ORIGIN.y - _tip.size.y - 4.0)
			_tip.show()
			return
	_tip.hide()
```
New:
```gdscript
	var mpos := get_local_mouse_position()
	for i in acquired.size():
		var r := _slot_rect(i)
		if r.has_point(mpos):
			_tip.text = _code_for(String(acquired[i]))
			_tip.reset_size()
			# Tooltip to the RIGHT of the slot (column is on the left edge), vertically centered on it.
			_tip.position = Vector2(r.position.x + SLOT + 6.0, r.get_center().y - _tip.size.y * 0.5)
			_tip.show()
			return
	_tip.hide()
```

- [ ] **Step 3: Update `_draw()`** to use `_slot_rect`. Replace the per-slot geometry lines:

Old:
```gdscript
	for i in ArenaWeapons.MAX_WEAPONS:
		# Base slot box; centre stays put so the firing pulse scales in place.
		var center := ORIGIN + Vector2(float(i) * (SLOT + GAP) + SLOT * 0.5, SLOT * 0.5)
		var rect := Rect2(ORIGIN + Vector2(float(i) * (SLOT + GAP), 0.0), Vector2(SLOT, SLOT))
```
New:
```gdscript
	for i in ArenaWeapons.MAX_WEAPONS:
		# Base slot box; centre stays put so the firing pulse scales in place.
		var rect := _slot_rect(i)
		var center := rect.get_center()
```

- [ ] **Step 4: Boot-compile check** — Run the Task-1 grep (adjust to `arena_weapon_slots`); expected clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/hud/arena_weapon_slots.gd
git commit -m "Cockpit HUD: weapon slots as left vertical column"
```

---

### Task 4: Aux slots → right vertical column

**Files:**
- Modify: `scripts/ui/hud/arena_aux_slots.gd`

**Interfaces:**
- Produces: `_slot_rect(i: int) -> Rect2` (right-edge vertical column).

- [ ] **Step 1: Replace the layout constants + add `_slot_rect`.** Change:

Old:
```gdscript
const SLOT   := 30.8
const GAP    := 5.6
const ORIGIN := Vector2(12.0, 82.0 + SLOT + 10.0)
```
New:
```gdscript
const SLOT   := 46.0                   # slot side (px) — right-edge vertical column (matches weapon column)
const GAP    := 12.0
const RIGHT_MARGIN := 16.0             # x of the column from the right screen edge

## i-th slot rect: a vertical column pinned to the right edge, vertically centered on screen.
func _slot_rect(i: int) -> Rect2:
	var vp := get_viewport_rect().size
	var n := ArenaAux.MAX_AUX
	var total_h := SLOT * float(n) + GAP * float(n - 1)
	var y0 := (vp.y - total_h) * 0.5
	return Rect2(Vector2(vp.x - RIGHT_MARGIN - SLOT, y0 + float(i) * (SLOT + GAP)), Vector2(SLOT, SLOT))
```

- [ ] **Step 2: Update `_draw()`** to use `_slot_rect`. Replace:

Old:
```gdscript
	for i in ArenaAux.MAX_AUX:
		var rect := Rect2(ORIGIN + Vector2(float(i) * (SLOT + GAP), 0.0), Vector2(SLOT, SLOT))
```
New:
```gdscript
	for i in ArenaAux.MAX_AUX:
		var rect := _slot_rect(i)
```

- [ ] **Step 3: Boot-compile check** — Run the grep (`arena_aux_slots`); expected clean.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/hud/arena_aux_slots.gd
git commit -m "Cockpit HUD: aux slots as right vertical column"
```

---

### Task 5: Shorter XP bar

**Files:**
- Modify: `scripts/ui/hud/arena_stats_hud.gd`

- [ ] **Step 1: Shorten the XP bar.** Change the geometry constants:

Old:
```gdscript
const XP_W_FRAC       := 0.5     # bar width as a fraction of the viewport width
const XP_W_MIN        := 380.0
const XP_W_MAX        := 760.0
```
New:
```gdscript
const XP_W_FRAC       := 0.3     # bar width as a fraction of the viewport width (shorter — sits under the vitals bar)
const XP_W_MIN        := 280.0
const XP_W_MAX        := 460.0
```

- [ ] **Step 2: Boot-compile check** — Run the grep (`arena_stats_hud`); expected clean.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/hud/arena_stats_hud.gd
git commit -m "Cockpit HUD: shorter XP bar"
```

---

### Task 6: Manual verification (no automated tests)

**Files:** none.

- [ ] **Step 1: Launch** `godot --path .` (boots straight to the arena via `WEAPON_TEST_MODE`). Open F12, drag in 2–4 weapons; gain XP / spawn a boss to exercise all elements.
- [ ] **Step 2: Verify** — weapons in a left vertical column (4 slots, icons + cooldown pies + hover names to the right); passives in a right vertical column (4 slots + level pips); player vitals bottom-center with a blue shield outer band (fills L→R) framing the HP inner box (fills L→R) + correct HP/shield numbers; XP bar shorter + centered at the bottom; cockpit bezels on all four edges.
- [ ] **Step 3: Verify boss bar** — spawn a boss (F12 / dev spawn): a vitals bar appears top-center mirroring the player bar and tracks boss HP; it disappears when the boss dies.
- [ ] **Step 4: Report honestly** — note anchor/size/bezel-angle nudges needed (expected for a procedural HUD) and fix/re-commit.

---

## Self-Review

**Spec coverage:** weapons left 4 (Task 3) ✓; passives right 4 (Task 4) ✓; player vitals bottom-center nested shield(outer,blue,L→R)+HP(inner,L→R) (Task 1) ✓; shorter XP bar at bottom (Task 5) ✓; boss vitals top-center mirroring player, conditional (Task 1, `mode="boss"`, visibility from `boss_hp`/`boss_max_hp`) ✓; procedural bezels (Task 2) ✓; relocate+reskin, reuse slot behavior — Tasks 3/4 keep cooldown pies/hover/pips, only geometry changes ✓; legacy `hud_hp_display`/`boss_hp_bar` untouched, arena drops `hud_hp_display` (Task 1 Step 2) ✓; kill/coin counters unchanged (Task 5 leaves them) ✓.

**Placeholder scan:** no TBD/TODO; complete code in every code step. Bezel angles + bar dimensions are concrete constants (F5-tunable, flagged in Task 6).

**Type consistency:** `_slot_rect(i: int) -> Rect2` defined and used in both slot widgets (Tasks 3/4); `mode: String` ("player"/"boss") set before add_child and read in `_process`/`_origin`/`_vitals`/`_draw` (Task 1); arena preloads `VitalsBarScript`/`HudFrameScript` (Tasks 1/2) and instantiates them in `_build_ui`. Boss visibility uses `GameManager.boss_hp`/`boss_max_hp` (confirmed fields). Player shield max via `shield_capacity_total()` (confirmed, guarded by `has_method`).

**Open/F5-tunable:** exact bezel geometry (`SIDE_INSET`/`TB_INSET`/`CHAMFER`/spans), bar size (`BAR_W`/`BAR_H`/`SHIELD_PAD`), slot size/margins, XP width. Boss has no shield mechanic, so the boss bar's shield band reads empty (0/0, hidden) — mirrors the player bar's structure without inventing boss shields; add later if wanted.
