# Cockpit-Frame HUD Redesign — Design

**Date:** 2026-06-30
**Status:** Proposed — awaiting approval before implementation plan

## Goal

Rework the arena HUD into a **cockpit frame** that hugs the four screen edges and leaves the center open for gameplay, drawn **procedurally** (no art yet; art can be dropped in later):

- **Left edge** — 4 weapon slots in a vertical column inside an angled bezel.
- **Right edge** — 4 passive (aux) slots in a vertical column inside a mirrored bezel.
- **Bottom-center** — player vitals: a **nested bar** where the outer layer is the **shield** (blue, fills left→right) wrapping an inner main box that is **HP** (fills left→right), with readouts "Current HP / Max HP" and "Current shield / Max shield".
- **Bottom edge** — a **shorter** XP bar (not full-width; ~the width of the vitals bezel, centered) with an "exp" label at its left.
- **Top-center** — boss vitals: the **same** nested HP+shield bar, shown only while a boss is alive, hidden otherwise.

Slot caps are already set to 4 (`MAX_WEAPONS`, `MAX_AUX`).

## Current state (what we're moving)

The arena HUD is assembled in `arena.gd::_build_ui()` on `_ui_layer` (CanvasLayer layer 10):
- `hud_hp_display.gd` — HP/shield, **sprite-sheet + `default_layout.cfg` driven**, pinned top-left.
- `arena_weapon_slots.gd` — weapon slots, procedural `_draw`, horizontal-ish top-left (reads `ArenaWeapons.MAX_WEAPONS`).
- `arena_aux_slots.gd` — aux slots, procedural `_draw`, row below weapons (reads `ArenaAux.MAX_AUX`).
- `arena_stats_hud.gd` — XP bar (bottom) + kill/coin counters (top-right).
- `boss_hp_bar.gd` — existing boss HP bar (used by boss scripts).

## Approach: relocate + reskin, with one new shared widget

- **New `scripts/ui/hud/arena_vitals_bar.gd`** (`extends Control`) — a self-contained procedural nested shield+HP bar. The legacy `hud_hp_display.gd` is sprite/layout-driven and doesn't fit the left→right nested-fill design, so the player vitals bar is built fresh here instead of reskinning that widget. One widget, two instances:
  - **Player instance** (bottom-center): reads `GameManager` HP/shield (`ship_hp_changed`, `ship_shield_changed`, and max values); always visible in-run.
  - **Boss instance** (top-center): reads boss HP/shield (`boss_hp_changed` + boss max); visible only between `boss_spawned`/`boss_incoming` and `boss_killed`/`boss_defeated`/player-death. Mirrors the player bar's look.
  - Draw model: an outer rounded bar (shield) filled L→R in blue by `shield/max_shield`; an inset inner main bar (HP) filled L→R by `hp/max_hp` in the HP color; numeric readouts drawn over/beside. A `configure(source)` flag picks player vs boss data source; a `set_visible_when_boss()` gate for the boss instance.
- **`arena_weapon_slots.gd`** — relocate to a **left vertical column** (4 slots top→down) and wrap in a procedural angled bezel; keep all behavior (icons, cooldown pies, hover code-name). Change `ORIGIN`/layout from a top-left row to a left-edge vertical stack; the slot loop already runs `ArenaWeapons.MAX_WEAPONS` (=4).
- **`arena_aux_slots.gd`** — relocate to a **right vertical column** (4 slots) mirrored, in a bezel; keep behavior (icons, level pips). Loop already runs `ArenaAux.MAX_AUX` (=4).
- **`arena_stats_hud.gd`** — make the XP bar **shorter + centered** at the very bottom (under the vitals bezel) with the "exp" label at its left; leave the kill/coin counters where they are (top-right; not part of this mockup).
- **`boss_hp_bar.gd`** — replace its visual with the boss instance of `arena_vitals_bar` (top-center), OR reskin it to match. Decision in the plan: prefer routing the boss bar through `arena_vitals_bar` so player + boss share one look; keep `boss_hp_bar.gd`'s existing show/hide wiring if boss scripts depend on it (adapt rather than break callers).
- **New procedural cockpit bezels** — angled trapezoidal frame outlines on the 4 edges, drawn in code (Line2D/`_draw` polylines) on a dedicated frame Control behind the widgets. A single `arena_hud_frame.gd` draws all four bezels so the look is centralized and art can replace it later.

`arena.gd::_build_ui()` is rewired to add: the frame, the left weapon column, the right aux column, the bottom player vitals bar + shorter XP bar, and the top boss vitals bar (hidden by default). The legacy `hud_hp_display` is removed from the arena HUD (kept for the legacy non-arena game, which still uses it).

## Components / boundaries

| File | Responsibility |
|------|----------------|
| `arena_vitals_bar.gd` (new) | Procedural nested shield+HP L→R bar; player or boss data source; boss-conditional visibility |
| `arena_hud_frame.gd` (new) | Procedural angled cockpit bezels on the 4 edges |
| `arena_weapon_slots.gd` (edit) | Same slots, repositioned to left vertical column + bezel-aware layout |
| `arena_aux_slots.gd` (edit) | Same slots, repositioned to right vertical column |
| `arena_stats_hud.gd` (edit) | XP bar shorter + centered at bottom; "exp" label; counters unchanged |
| `boss_hp_bar.gd` (edit) | Route boss HP/shield through `arena_vitals_bar` look (or reskin), preserve show/hide callers |
| `arena.gd::_build_ui()` (edit) | Assemble the new frame + relocated widgets; drop `hud_hp_display` from the arena |

## Open questions (resolve in plan or with user)

1. Exact bezel geometry/angles and edge insets (procedural — tuned at F5; pick sensible defaults).
2. Boss bar: route through `arena_vitals_bar` vs reskin `boss_hp_bar` in place — pick whichever least disturbs the boss scripts that show/hide it.
3. Player vitals readout format (numbers inside the bar vs beside it) — default: numbers centered on each sub-bar.

## Out of scope (YAGNI)

- No HP/shield/XP mechanic changes — display only.
- No art assets (procedural now; art later).
- Kill/coin counters keep their current top-right position.
- The legacy non-arena game HUD (`hud_hp_display` in `main.tscn`) is untouched.

## Verification

- Boot-compile check: `godot --headless --path . --quit-after 8` (the reliable check — `--check-only` misses identifier errors in unreached functions).
- Manual F5 (no test suite — state explicitly): weapons on the left (4), passives on the right (4); player vitals bottom-center with shield outer (blue, L→R) + HP inner (L→R) + correct numbers; XP bar shorter/centered with "exp" label; boss bar appears top-center on boss spawn and disappears when the boss dies; nothing overlaps the play area badly. Anchor/inset nudges expected.
