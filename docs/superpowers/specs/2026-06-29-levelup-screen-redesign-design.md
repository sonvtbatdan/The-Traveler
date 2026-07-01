# Level-Up Screen Redesign — Design

**Date:** 2026-06-29
**File touched (primary):** `scripts/ui/hud/arena_levelup_ui.gd`
**Status:** Approved design → ready for implementation plan

## Goal

Replace the current centered 800×433 level-up panel with a **full-screen (100% occupancy)** layout that flattens today's two-tier flow (pick item → pick pool upgrade) onto one screen and adds a persistent global-stats panel:

- **Left column** — the 3 offered level-up choices, stacked vertically, each showing the item's sprite (centered) + name.
- **Center column** — top: the **selected item** shown large (reused weapon sprite); bottom: the 3 **options** for that item (or a single Confirm panel / a Fusion composition, depending on the item type).
- **Right column** — a curated, read-only list of **global stats** (not item-tied).

This is a **presentation/layout rework only**. All underlying selection, pool, capstone, fusion, and apply logic in `arena_levelup_ui.gd` (and the `arena_weapons` / `arena_aux` calls it makes) is **reused unchanged**. We are changing how choices are laid out and adding the stats panel — not how items/upgrades work.

## Layout (proportions)

Full-screen `Control` (PRESET_FULL_RECT) on the existing `CanvasLayer` (layer 100, `PROCESS_MODE_ALWAYS`). A dimmed/opaque backdrop fills the screen. All measurements are percentages of the screen so it scales to any resolution.

Horizontal (symmetric): `margin 2% | left 21% | gap 2% | center 50% | gap 2% | right 21% | margin 2%`.

Vertical: `margin 3%` top and bottom (below the title strip).

- **Title strip** — a slim bar across the very top spanning the full width. Text: `LEVEL UP — choose an item`, switching to the selected weapon's name once an item is selected (and to `… — EVOLVE` on a capstone, matching today's title behavior). Reuses the existing `_title` label styling (Good Old DOS font, `#E5792A`).
- **Left column (21% wide, full inner height)** — 3 equal item slots stacked with even gaps (each ≈27.3% tall, 3% gaps). Each slot: the item's **sprite centered** in the box + the item name. Weapons/fusions use `InventoryManager.get_icon(def_id)` (same source as the center + today's cards); aux items fall back to a centered colour swatch (today's behavior). When fewer than 3 choices exist, only that many slots render (the pool can dry up — today's fallback).
- **Center column (50% wide)**:
  - **Selected-item panel** — top 52% of the inner height. Shows the selected item's sprite large + its name. Empty placeholder before any selection (or auto-select slot 1 on open — see Open behavior).
  - **Options row** — bottom 38%, starting ~59% down. Three equal-width boxes (≈15.5% screen width each within the center column) with even gaps. Content depends on item type (below).
- **Right column (21% wide, full inner height)** — header `Stats` + a curated, ordered, read-only stat list (`Label: value` rows). Refreshed each time the screen opens.

A reference mockup of these proportions was reviewed and approved in the brainstorming session.

## Item-type behavior (center + options)

When a left item is selected, the center panel shows it large and the options row fills per type. All cases map to logic that **already exists** in `arena_levelup_ui.gd` — we are re-routing where it renders, not adding new mechanics.

1. **Pooled upgrade** (owned weapon/aux that has a pool — e.g. Gatling, Lasgun, Arc, Gauss, Orbital, Red X, Chemtrail, Z-Sword, Sonic; aux pools likewise): the 3 option boxes show 3 not-maxed pool upgrades (today's `_gen_pool_choices` / `_gen_aux_pool_choices`). Each box: bold big upgrade name + small italic detail (the `per` / `desc` text, which already carries keyword effects like burn/bleed/electrocute). Picking one calls today's `pool_grant` + `spend_weapon_point` (or aux equivalents).
2. **New weapon / poolless weapon / simple-level item**: the option row collapses to a single large **Confirm** panel spanning the row, showing the description + a confirm action. Picking it runs today's `acquire_weapon` / `level_up_weapon` / `acquire_aux` / `level_up_aux`.
3. **Maxed pooled weapon (capstone/evolve)**: when the selected pooled weapon is at max level, the 3 option boxes become its 3 **EVOLVE** capstone choices (today's `weapon_capstones` / `aux_capstones`), visually flagged. All-In's "choose a weapon to destroy" sub-step opens as a small sub-overlay/secondary view (today's `_show_destroy_choice`), with a back affordance.
4. **Fusion available**: every ready fusion recipe places its **two source weapons in left slots 1 & 2**, each box ringed with a shiny yellow circle/line + a pulsing rainbow. Clicking either source box enters the fusion composition: **source A sprite large on top** (selected-item panel), **source B sprite in the options area**, and a **FUSION** button between them. Confirming runs today's fusion path: hide the screen, play the fusion cutscene (`arena_fusion_cutscene`), then `fuse(fid)`.

## Stats panel (right column)

Curated, ordered, **read-only** list of global / non-item stats, rebuilt each time the screen opens by reading current values from `GameManager` (getters/`upg_*` fields) and the masteries. Proposed order (final list tunable):

- HP (max), HP regen
- Fire rate, Damage
- AOE, Armor pen % , Armor pen flat
- Crit chance, Crit damage
- Move speed, Pickup radius
- Key masteries (e.g. kinetic / fire / light damage masteries, harden, regen, speed)

Each row: `Label: value` with sensible formatting (× for multipliers, % where appropriate, ints for flat). Stats not yet present in code are omitted (no stubs) rather than shown as zero — list is curated to what exists, kept legible. No interaction.

## Open / queue / input behavior (unchanged semantics)

- Opens on `GameManager.leveled_up` (and `grant_reward()` for reward chests), pausing the tree (today's `_begin`/`_show_cards`).
- On open: render the left choices; **auto-select slot 1** so the center + options are populated immediately (no empty center). User can click any other left item to switch.
- Picking an option / Confirm / Fusion applies it and then advances: show the next queued level-up (`_pending`) or `_finish()` (hide + unpause).
- **Keyboard:** `1/2/3` pick the bottom **options** (matching today). Left items are mouse-clickable (optionally `Q/W/E` or arrow keys later — out of scope unless requested).
- Empty pool (everything owned + maxed) → silently skip the level-up, as today.

## Components / structure

Keep everything in `arena_levelup_ui.gd` (the file already owns all this logic) but reorganize `_build_ui()` and the render path into clearly-bounded helpers so the file stays readable:

- `_build_ui()` — build the full-screen scaffold: backdrop, title strip, left column container (3 slot anchors), center column (selected panel + options row anchors), right stats panel container. Pure layout; no per-level content.
- `_render_left(choices)` — fill the 3 left slots (sprite centered + name; fusion ring/pulse; aux swatch fallback).
- `_select_item(idx)` — set the selected item, update the center panel (big sprite + name) and the title, and call `_render_options_for(choice)`.
- `_render_options_for(choice)` — dispatch by type → pooled (3 options) / confirm (1 panel) / capstone (3 evolve) / fusion (A-top / FUSION / B-bottom). Reuses the existing choice-generation + apply functions.
- `_refresh_stats()` — rebuild the right panel rows from `GameManager`.
- Existing `_generate_choices`, `_gen_pool_choices`, `_gen_aux_pool_choices`, `_show_capstone`, `_show_destroy_choice`, `_pick_*`, `_apply`, `_advance`, `_finish`, fusion handling, SFX — **reused**; only their rendering targets change.

The old centered-panel builders (`lvupframe` panel, `_position_cards`, the per-card `_make_card` layout) are replaced by the new full-screen builders. Card visuals that still apply (sprite icon, name, effect/detail text, hover) are adapted into the new slot/option widgets.

## Out of scope (YAGNI)

- No change to weapon/aux/pool/capstone/fusion **mechanics** or balance.
- No new stats added to `GameManager` (panel shows only existing ones).
- No new keyboard nav for the left list beyond mouse (can add later if wanted).
- No art for the frame/background beyond reusing existing textures/colors; exact theming polish can follow once the layout is in.

## Verification

- Parse check: `godot --headless --check-only --path . --quit` (exit 0).
- Manual (no test suite — state explicitly): in `WEAPON_TEST_MODE`, trigger level-ups (kill enemies / reward chest) and confirm: full-screen layout, sprites centered in left slots + center, options/confirm/capstone/fusion all render and apply correctly, stats panel populated, multi-level-up queue works, pause/unpause correct, keyboard 1/2/3 picks options.
