# Arena weapon acquisition + 5-slot bar + lasgun fixes

**Date:** 2026-06-21
**Scope:** Arena mode (`scenes/arena.tscn`) only. Bespoke weapons in `arena_weapons.gd`.

## Goal

Replace the always-on default Gatling with an acquisition model: the ship starts unarmed,
the player picks one weapon from a start-of-run chest, and can acquire up to 5 distinct
weapons during a run. A HUD bar shows the 5 weapon slots with per-weapon cooldown pies.
Also fix two Lasgun beam bugs.

## Decisions (confirmed)

- **Chest pool:** the 4 "F12" weapons — `gatling`, `lasgun`, `arc`, `gauss`.
- **Acquisition:** unique only (no duplicates) for now; a level-up system comes later. Max 5 slots.
- **Start state:** totally unarmed — all weapon flags start `false`.
- **More weapons mid-run:** yes, via F12 palette + world pickups (same `acquire_weapon` path), capped at 5.
- **`arena_loadout.gd`:** left running but dormant (no inventory weapon equipped in a normal run → it self-stands-down). Boss-salvage inventory weapons remain a separate meta path, out of scope.
- **Lasgun fix:** swap `BeamScript` preload from `lasgun_ani_3.gd` to `lasgun_ani_1.gd`. Both use identical body/muzzle art; ani_1 already fixes both bugs and uses the requested impact spritesheet.

## Part 1 — Remove default auto-attack

`arena_weapons.gd`: change `_gat_active` initial value from `GAT_ENABLED` (true) to `false`.
All weapon-active flags now start `false`; combat begins only after the chest pick / a pickup.

## Part 2 — Start-of-run chest UI

New `scripts/ui/hud/arena_weapon_chest_ui.gd` (CanvasLayer, layer 109, `PROCESS_MODE_ALWAYS`).
- On run start (triggered from `arena.gd._ready`, deferred, after `reset_run`), pause and show a
  3-card pick-1 panel styled like the level-up cards.
- Cards = 3 distinct kinds randomly drawn from `arena_weapons.CHEST_POOL`.
- Card icon via `InventoryManager.get_icon(def_id)` using `arena_weapons.WEAPON_INFO`.
- Click a card → `arena_weapons.acquire_weapon(kind)`, unpause, close.
- SFX: `uialert.wav` on show, `uiclick.wav` on hover, `selectconfirm3.wav` on pick.

## Part 3 — Acquired-weapons model + 5-slot HUD

### 3a — model (in `arena_weapons.gd`)
- `const MAX_WEAPONS := 5`
- `const CHEST_POOL := ["gatling","lasgun","arc","gauss"]`
- `const WEAPON_INFO := { kind: {def_id, label} }` for all 6 kinds.
- `var _acquired: Array = []` (ordered kinds).
- `func acquire_weapon(kind) -> bool` — append if new and `< MAX_WEAPONS`, then route to the existing
  `activate_<kind>()`. Returns whether a new slot was filled.
- `func acquired_weapons() -> Array` — ordered copy for the HUD.
- `func weapon_cooldown_frac(kind) -> float` — 1.0 = ready (no mask), 0..1 = recovering:
  - `gatling`/`orbital`: always 1.0 (continuous / passive).
  - `gauss`: `_gauss_charge / (GAUSS_CHARGE_TIME / _rate_mult)`.
  - `arc`: `1 - _arc_cd / (ARC_COOLDOWN / _rate_mult)` (1.0 when `_arc_cd <= 0`).
  - `void`: `1 - _void_cd / (VOID_COOLDOWN / _rate_mult)` (1.0 when `_void_cd <= 0`).
  - `lasgun`: cycle phase — 1.0 during the `LASGUN_DURATION` firing window; during the
    `LASGUN_CYCLE - LASGUN_DURATION` recharge, ramps `0 → 1`.
- World pickups (`arena_weapon_pickup.gd._collect`) route through `acquire_weapon` (cap-respecting).

### 3b — HUD (`scripts/ui/hud/arena_weapon_slots.gd`)
- A `Control` added to the arena `"UI"` CanvasLayer, pinned top-left **below the HP/energy cluster**.
- 5 rounded-square slots drawn in `_draw()`:
  - Empty: dim outlined rounded square.
  - Filled: weapon icon (`InventoryManager.get_icon`).
  - **Cooldown pie:** a dark translucent wedge covering the `(1 - frac)` portion, sweeping
    **clockwise** from 12 o'clock, drawn as a triangle-fan polygon. Lifts as `frac → 1`.
- Polls `arena_weapons.acquired_weapons()` + `weapon_cooldown_frac()` each frame (`queue_redraw`).

## Part 4 — Lasgun fixes

`arena_weapons.gd:159`: `const BeamScript := preload(".../lasgun_ani_1.gd")`.
- Bug 1 (beam extends behind ship at close range): ani_1 uses the Isaac model (`x0 = conv.x - body_overlap`,
  no `beam_bwd` backward pull) + short-range alpha fade.
- Bug 2 (impact spins / unanchored): ani_1 draws the 12-frame impact flipbook anchored via
  `impact_anchor_x/y` at the true hit point, rotated to the beam angle only (no spin).
- Drop-in: identical `set_beam/fire/release` contract.

## Verification

`godot --headless --check-only` for parse; manual F5 for behavior (no test suite). Verify:
chest appears at run start; pick fills slot 1; gatling has no mask; gauss/arc/lasgun show the pie;
lasgun at point-blank doesn't extend behind the ship; impact cap sits on the target, no spin.
