# Enemy — Bosses, Arena & Normal Enemies

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on enemy behavior, bosses, waves, arena enemies, ruins, enemy panel.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

## Changelog — 2026-08-02 (5th pass) — Fleet Edit's UNIT/RANDOM grids widened from 2×5 (10) to 2×10 (20)

- `fleet_edit_mode.gd`: `SLOT_COUNT` 10→20, `UNIT_COLS` 5→10 — both the UNIT and RANDOM tables share this
  same column count, so both grew together. New `LEFT_PANEL_W` const (`PANEL_W + 310`) widens the left panel
  to fit the now-10-wide `GridContainer`s (10×`CELL(50)` + 9×4px h_separation + 12px VBox margin = 548px
  minimum); the hover-preview panel's x-position was updated to sit just right of the new width instead of
  the old hardcoded `PANEL_W + 50`. No data-model or save-format change needed — `res://fleet_layout.cfg`
  stores each fleet's `slots` as a plain variable-length Array (no fixed-10 assumption anywhere), and every
  runtime consumer (`arena_wave_director.gd`/`_v2.gd`'s `_deploy_fleet()`, `arena_debug_spawn.gd`'s Fleet
  tab, `arena_wave_editor.gd`'s `_fleet_total_hp()`) already iterates it generically — existing 10-slot
  fleets in `fleet_layout.cfg` load unaffected, with slots 10-19 simply starting empty until edited.

## Changelog — 2026-08-02 (4th pass) — Dragonfly "vortex_dive" behavior; fly sprite no_downscale

- **Dragonfly**: `behavior` changed from `"orbit"` to a new `"vortex_dive"` (`arena_enemy.gd`) — swirls
  inward on a GUARANTEED-shrinking radius (`VORTEX_SHRINK := 60.0`, double the old `"orbit"`'s `28`, same
  `ORBIT_SPAWN_REF_R`-scaled rate pattern that fixed the "70 dragonfly stuck orbiting" bug) steered as
  velocity toward a point on the shrinking ring (organic vortex feel, not a rigid position-snap like the old
  `"orbit"`). Once the radius reaches `VORTEX_DIVE_TRIGGER` (40px) it commits a straight overshoot dash
  (`VORTEX_DIVE_SPEED_MULT` × speed) for `VORTEX_OVERSHOOT_TIME` (0.4s), then curls back into the vortex,
  re-homing on the player's CURRENT position — unlike the old `"orbit"` behavior's dash, which never
  returned (kept re-aiming and dashing forever once committed). First implementation reused
  `"steer_chaser"`'s pure dir+tangent pursuit-curve math verbatim ("bay dạng vortex giống flie1") — measured
  via a real-render test to settle into a stable ~200-400px wide orbit that never reliably shrank (a known
  property of constant-bearing pursuit against a near-stationary target at a high tangent ratio), so it was
  replaced with the deterministic-shrink approach above; re-verified afterward to decay monotonically
  (298px → 167px over the test window, no oscillation).
- **Fly**: added `"no_downscale": true` to `ENEMY_DEFS`'s `fly` entry — the pre-baked
  `assets/Enemies Downscale/flie1.png`/`flie2.png` copies (`tools/downscale_enemies.gd`'s
  `Image.resize(..., INTERPOLATE_LANCZOS)`, no alpha premultiply) measurably brightened/introduced a
  whitish edge fringe vs. the clean HD source (edge-pixel mean RGB brighter, near-white pixel share ~3×
  higher) — this skips that bake and loads the full `assets/enemiesHD/` PNG directly, same flag Elite/
  Champion Creep already use. Trade-off flagged: unlike Elite/Champion (rare), fly is high-volume (200-count
  ring bursts) — the HD texture is shared/cached across instances (not duplicated per-fly), so VRAM cost is
  bounded (~7.6MB total for flie1+flie2 combined, not ×200), but worth watching if it becomes a bottleneck.

## Changelog — 2026-08-02 (3rd pass) — Two-tier Elite/Champion Creep, wave quiet-window, temple LIFETIME_MAX fix

- **Bug fix**: `arena_enemy.gd`'s `LIFETIME_MAX` (120s) safety net — silently `queue_free()`s any enemy alive
  too long, bypassing `_die()` entirely (no loot, no XP, no death FX) — only excluded `behavior=="boss_stub"`,
  not `no_collide` landmarks. The rubicon temple (spawns 10,000-15,000px away, 2000 HP) could hit 120s from
  travel+fight time alone and vanish mid-fight with no `orb_of_light` drop. Fixed: also exempt `_no_collide`
  (`arena_enemy.gd:1856-1861`) — covers the temple and dead-ship wrecks (`arena_ruin_layer.gd`), the only
  other `no_collide` landmark type; `no_collide` "bomb"/"thrown_bomb" projectiles are unaffected in practice
  since they self-clean via their own behavior logic well under 120s.
- **Elite Creep split into two independent tiers** (`arena_wave_director_v2.gd`), replacing the single-tier
  version from the 1st/2nd-pass entries below:
  - **Elite**: 200% size, 35× HP, every 30s starting at 1:30 (`ELITE_CREEP_*` consts).
  - **Champion**: 300% size, 75× HP, every 60s starting at 2:30 (`CHAMPION_CREEP_*` consts) — note this
    reuses the "Champion" name for a DIFFERENT mechanic than the one removed in the 2nd-pass entry (that one
    was a random-archetype, fully-knockback-immune, gold-ringed spawn on an Agony-scaled timer with no
    concept of "wave's weakest type"; this one is architecturally identical to Elite, just a bigger/rarer/
    later tier of the same "weakest wave type" mechanism).
  - Both tiers share the same picker (`_weakest_wave_type(used)`, now parameterized) and spawn path
    (`_spawn_tiered_creep`), but track their OWN "already promoted" type set independently
    (`_elite_creep_used` / `_champion_creep_used`) — Elite and Champion each escalate through the wave's
    roster on their own schedule, not a shared progression. Both still 50% knockback resistance, "elite"
    flag (cap-bypass + reward-on-death), "no_downscale" (HD sprite).
- **Wave quiet-window**: new `WAVE_INTERVAL` (120s) / `WAVE_QUIET_TAIL` (10s) — the last 10 seconds of every
  2-minute block spawn nothing at all: gates `_tick_spawn_loop` (ambient/cluster/wall AND the low-population
  catch-up burst) and both `_tick_elite_creep`/`_tick_champion_creep` (a tick landing in the window is
  skipped outright, not delayed — the accumulator still resets). Deliberately does NOT gate `_drain_spawn_queue`
  (shared with the F7 timeline's own queued ring/scatter/wall/stream entries — gating it would stall
  hand-authored timeline spawns, not just the ambient loop) or the timeline's own `_tl_tick` firing at all —
  authored JSON spawn times are intentionally left untouched by this generic periodic rule.

## Changelog — 2026-08-02 (2nd pass) — Removed the "Champion" spawner (redundant with Elite Creep)

- `arena_wave_director_v2.gd`'s "Champion" mechanic (`_tick_champion`/`_spawn_champion`, `CHAMPION_*`
  consts, `_champion_acc`) — a random test-roster archetype scaled ×50 HP/×2 size/×1.5 speed on its own
  Agony-scaled ~30-150s timer, fully knockback-immune, drawing a gold ring (`arena_enemy.gd`'s
  `_is_champion`) — removed entirely: it spawned "creeps with a gold ring and very high HP", the same role
  Elite Creep (see the 2026-08-02 1st-pass entry above) now already covers more generally (any wave type,
  not just the 4-archetype test roster; fixed 30s cadence; partial knockback resistance instead of full).
  `_is_champion` field + its 2-line gold-ring `_draw()` block also removed (dead once nothing ever sets
  `"champion": true`). The shared `"elite"` flag / `_is_elite` / `grant_reward`-on-death / alive-cap-bypass
  infrastructure Champion used is untouched — Elite Creep depends on that same plumbing.

## Changelog — 2026-08-02 — Automatic Elite Creep spawner replaces the 3 scripted milestone elites; bug_crawl removed

- **Removed** v1's `ENEMY_DEFS` entries `elite_fly`/`elite_bug`/`elite_bee` (the fixed 5/10/15-minute
  insect-only milestone mini-bosses, `arena_wave_director.gd`) and their `DEFAULT_TIMELINE`/
  `Level_1_Minh.json` scripted appearances. Also removed `bug_crawl` (identical to `bug` except speed 120
  vs 80, no distinct behavior — flagged as likely-redundant in a prior Creep Info icon-duplication audit);
  `Level_1_Minh.json`'s `bug_crawl` rows now spawn `bug`. Orphaned `creep_info_overrides.cfg` entries for
  all 4 removed types were deleted too (harmless either way — `CreepInfoPanelScript.apply_overrides` skips
  any id no longer in `ENEMY_DEFS`).
- **Replacement**: `arena_wave_director_v2.gd`'s new `_tick_elite_creep`/`_spawn_elite_creep`
  (`ELITE_CREEP_INTERVAL` = 30s) — every 30 seconds, finds the CURRENT wave's own weakest (lowest-HP, "lvl"
  scaled by player level for fair comparison) non-elite/non-boss creep type (`_weakest_wave_type`, scanning
  the loaded F7 timeline's distinct `"type"` values, or the `TEST_TYPES` roster if no timeline is loaded)
  and promotes it to an elite: 300% size (`ELITE_CREEP_SIZE_MULT`, applied to BOTH `def["size"]` for the
  hitbox and `def["draw_w"]` — via new `arena_enemy.gd` static helper `base_draw_width()` — for the actual
  sprite, since `creep_layout.cfg`'s fixed authored width would otherwise silently no-op a plain `size`
  bump), 75× HP (`ELITE_CREEP_HP_MULT`). Unlike Champion/the old milestone elites (which are fully
  knockback-immune), this one is only 50% resistant (`ELITE_CREEP_KNOCKBACK_MULT`) — new `arena_enemy.gd`
  field `_knockback_mult` (`d.get("knockback_mult", 0.0 if elite else 1.0)`) lets a def override the
  elite-implies-full-immunity default instead of the old hardcoded `not _is_elite` gate. Flagged `"elite"`
  (same `MAX_ALIVE_V2` cap-bypass + reward-on-death as Champion) but not `"champion"` (no gold ring). This
  mechanic now covers ANY creep type in the current wave, not just fly/bug/bee, and fires much more
  frequently (30s flat vs 5/10/15 min) — a meaningfully different, more general difficulty knob than what it
  replaced, not just a rename.

### Update (same day) — 2-minute grace period, no-repeat progression, HD sprite, 100×→75× HP

- **`ELITE_CREEP_START_DELAY` = 120s** — `_tick_elite_creep` now no-ops entirely until `_run_t` passes this,
  so the field stays elite-free for the opening 2 minutes (accumulator starts counting at t=120, so the
  first Elite Creep lands at ~2:30, not exactly 2:00).
- **No immediate repeats**: new `_elite_creep_used: Dictionary` (type id → true, marked in
  `_spawn_elite_creep` right after `_weakest_wave_type` picks one) is now excluded from `_weakest_wave_type`'s
  candidate pool — each successive Elite Creep escalates to the wave's NEXT-weakest still-fresh type instead
  of re-promoting the same one every 30s. Once every eligible type has had a turn, the used-set clears and
  the cycle restarts from the weakest again (rather than the mechanic going silent once the roster is
  exhausted) — worth flagging in case a hard stop after one full pass was actually intended instead.
- **HD sprite, no blur**: `def["no_downscale"] = true` on every Elite Creep def → `arena_enemy.gd`'s
  `_load_icon()` (via new `_no_downscale` field + `_resolve_sprite(path, skip_downscale)` param) now skips
  the pre-baked-downscale substitution (`assets/Enemies Downscale/`, sized for the type's NORMAL on-screen
  footprint) and loads the full `assets/enemiesHD/` source instead — needed because a 300%-size elite would
  otherwise visibly blur, stretching a texture that was already downsized for the small regular version.
- **`ELITE_CREEP_HP_MULT`: 100× → 75×.**

## Changelog — 2026-07-28 (26th pass) — Root-caused "dragonfly/diver stuck, never approaching": tighten rate

- **Different bug from the 25th pass's despawn/teleport fix** — dragonfly ("orbit") and diver ("spiral")
  weren't actually LOST off-screen (their orbit is centered exactly on the player's current position, so
  `_tick_despawn_teleport()`'s distance check never flags them — technically "in range" the whole time).
  They were legitimately stuck ORBITING at a huge radius for way too long: both behaviors start orbiting at
  their spawn distance and shrink the radius toward the player at a FIXED px/s rate (`ORBIT_SHRINK` = 28,
  `SPIRAL_SHRINK` = 75) before finally diving — a fixed rate means time-to-dive is proportional to spawn
  distance. That was tuned fine for v1's ~600-840px spawn ring (arena_wave_director.gd's `SPAWN_RADIUS`),
  but spawn_mode_2's annulus spawns much farther out (~1000-1900px — `R_PADDING`/`R_WIDTH` in
  `arena_wave_director_v2.gd`), stretching dragonfly's tighten-then-dive out to 35-65+ seconds (diver:
  13-25s) — with 200-count "ring" bursts spawning dozens at once, all stuck orbiting in lockstep at a huge,
  off-screen-ish radius for the better part of a minute reads exactly like "70 dragonfly stuck, never seen
  approaching."
- **Fix**: new `_orbit_r0` (the orbit radius captured AT SPAWN, in `_init_behavior()`) scales the tighten
  rate: `rate = BASE_RATE × (_orbit_r0 / ORBIT_SPAWN_REF_R)`, where `ORBIT_SPAWN_REF_R` (720, v1's average
  spawn distance) is the distance the original rates were tuned/felt right at. This keeps time-to-dive
  approximately CONSTANT (≈ 25s dragonfly, ≈ 9.5s diver) regardless of where the enemy actually spawned —
  v1's own feel at its own ~720px average spawn distance is unchanged by construction (rate ≈ base rate
  there), while spawn_mode_2's much farther annulus now tightens proportionally faster to match.

## Changelog — 2026-07-28 (25th pass) — Root-caused "120 alive, 0 on screen": generalized despawn/teleport

- **Root cause**: `_tick_despawn_teleport()` only ever recycled `steer_*`-behavior enemies (the 4 spawn_mode_2
  test archetypes) — this was a known, repeatedly-flagged gap all session. Any OTHER enemy (the bulk of the
  roster: `chase`/`patrol`/`teleport`/`bomber`/etc.) that ends up off-screen — most commonly a `chase`-type
  enemy slower than the player that can never catch up if the player keeps moving — just stays lost off-
  screen FOREVER, invisibly counted in the alive total, while the spawn loop keeps admitting more (well
  under the 500 population cap, so nothing stops it). `LIFETIME_MAX` (120s safety-net despawn, 15th pass)
  bounds the worst case but doesn't prevent a sizeable off-screen population existing at any given moment if
  the spawn rate is healthy — explains "count says 120, screen shows 0".
- **Fix**: `_tick_despawn_teleport()` generalized from "steer_* only" to every enemy except: `"boss_stub"`
  (bosses fight wherever combat brings them), `"mothership"` (already always approaching on its own since
  the 24th pass disabled its flee cycle — teleporting it would also visually snap its whole docked
  formation), `"patrol"` (intentionally a one-way flyby that self-culls via `PATROL_CULL` — recycling it
  would fight that design, causing it to immediately re-exceed R_despawn along the same captured heading
  instead of ever reaching the player), and any `_docked` escort (pinned to its carrier's relative slot
  every frame — teleporting it independently would fight that pin). Every other lost enemy now gets pulled
  back into the visible ring (same "keep its own relative angle, just closer" logic steer_* already used)
  on the existing `DESPAWN_INTERVAL` tick, instead of sitting off-screen until `LIFETIME_MAX` eventually
  clears it.

## Changelog — 2026-07-28 (24th pass) — Jetfighter/sentinel/mothership no longer flee — always close the distance

- **"shooter" (jetfighter)**: the standoff band (approach past 340+40px, hold, retreat below 340-40px) is
  gone — `standoff_v` is now unconditionally `dir * speed`, i.e. it always advances like a normal chase
  creep. Flocking (22nd pass) is untouched, still additively blended on top. `JF_STANDOFF_RANGE` const
  removed (no longer referenced).
- **"sentinel"**: `_standoff(dist, dir, 420.0)` (approach/hold/retreat around a 420px band) replaced with plain
  `velocity = dir * speed; _move_step()` — always closes in, fires its fan while approaching instead of
  holding range. Note this is the literal `"behavior": "sentinel"` ENEMY_DEFS entry (marked "obsolete —
  replaced by the Sentinel Fleet" in its own comment) — the ACTIVE Sentinel Fleet units (`sentinel1-4`/
  `sentinelleader`, `fleet1-4`/`fleetleader`) use `"patrol"` behavior instead, which was already a straight
  one-way flyby with no player-tracking or retreat to begin with, so nothing needed changing there.
- **"mothership" (prosmotherblank/Prosmothership carrier)**: `MS_CYCLE_ENABLED` flipped `true` → `false`.
  This existing flag (already built for exactly this) makes `MS_READY`'s per-frame advance
  (`velocity = dir * MS_APPROACH_SPEED`) never time out into the `MS_TURN`→`MS_FLEE`→`MS_WAIT`→`MS_RESPAWN`
  cycle — the carrier just keeps closing the distance forever with its docked escorts intact, never turning
  tail. The full flee/release/respawn state machine code is untouched (just disabled), so this is a
  one-line revert if the cycle is ever wanted back.

## Changelog — 2026-07-28 (23rd pass) — Investigated "repeating SFX": off-screen creeps no longer play SFX

- **No literal audio-loop bug found**: checked every SFX `.wav.import` this file uses (`SFX_ZAP`, `SFX_BEAM`,
  `SFX_SPIDER_JUMP`, `SFX_OCTOPUS_JUMP`) — all have `edit/loop_mode=0` (loop disabled at the resource level),
  and `_play_sfx()` never called `.stop()` on anything because there was nothing looping to stop.
- **Actual cause**: an off-screen creep keeps running its behavior tick (the movement/off-screen LOD only
  STAGGERS the rate — see `_run_full_tick` in `_process()` — it never stops attack timers entirely), so a
  shooter/sentinel/beamer/bomber/missile sitting off-screen keeps re-triggering `_play_sfx()` on its normal
  fire cycle, with no visible source to explain the recurring sound — that's what read as "SFX lặp lại".
  Every attack-SFX call site in this file routes through the one `_play_sfx()` function (checked — spider/
  octopus jump sounds too), so a single fix covers all of them: gated on the same camera-visible-rect test
  `_process()` already computes for the movement LOD (`_mgr.visible_world_rect().grow(LOD_MARGIN)`) — an
  off-screen creep now plays nothing, however many times its behavior calls this.
- **Not gated**: `_play_boom()` (death sound) — already pooled/throttled manager-side
  (`BOOM_POOL`/`BOOM_MIN_GAP` in `arena_enemy_manager.gd`), and "something just died" reads as useful
  feedback even from just off-screen, unlike a repeating attack sound with no visible source. Ask if this
  should be gated too.

## Changelog — 2026-07-28 (22nd pass) — Jetfighters now flock together instead of orbiting the player solo

- **New shared flock centroid** (`arena_enemy_manager.gd`): `_tick_jf_flock()`, throttled to every
  `JF_FLOCK_RECALC_EVERY` (0.4s), scans `get_tree().get_nodes_in_group("arena_enemy")` once and averages
  the position of every live `_type == "shooter"` (jetfighter) enemy into `_jf_flock_center` — computed ONCE
  per tick and read by every jetfighter, not O(alive) per jetfighter per frame. Exposed via
  `jf_flock_center()`/`jf_flock_valid()` (false if no jetfighter is alive yet).
- **"shooter" case in `arena_enemy.gd`** no longer calls plain `_standoff()` — it now blends TWO steering
  pulls: the existing player-standoff (hold `JF_STANDOFF_RANGE` = 340px from the player) additively combined
  with a cohesion pull toward `jf_flock_center()` (weighted `JF_FLOCK_WEIGHT` = 0.7, stops once within
  `JF_FLOCK_HOLD_R` = 70px of the centroid — i.e. "already in the pack"), then clamped to `speed`. Actual
  clumping (not stacking) still comes from the EXISTING spatial-hash separation pass, untouched — this only
  adds the "pull together when far apart" half; separation was deliberately not reimplemented (matches the
  project's spawn_mode_2 convention of reusing separation rather than rebuilding it per-behavior).
- **Scoped to `"shooter"` (v1's type_id) only** — spawn_mode_2's `"steer_kiter"` (`test_kiter`, ALSO the
  jetfighter sprite) is untouched; only "jet fighter" was named, ask if that one should flock too.

## Changelog — 2026-07-28 (21st pass) — Jetfighter 1 bullet/sec (was 4); magmafrag HP 35%→10% of parent

- **"shooter" behavior (jetfighter.png, v1's `"shooter"` — the literal "Jet Fighter" unit) fire rate**: was
  a 4-shot burst (one per configured firepoint — jetfighter has 4 in `creep_layout.cfg`, 0.2s apart) every
  1.0s = **4 bullets/sec**. `sh_total` hardcoded to `1` (was `maxi(1, _fp_fracs.size())`) → now fires exactly
  **1 bullet/sec**, always from firepoint 0. **Not touched**: spawn_mode_2's `"steer_kiter"` (also the
  jetfighter sprite, `test_kiter`) still fires 1 bullet every `KITE_FIRE_INTERVAL` = 1.2s — close but not
  exactly 1/sec; left alone since only "jet fighter" (the v1 unit) was named, ask if this one should match too.
- **magmafrag HP** (`_burst_small_magma()`, spawned when a large `magma_split` creep dies): child "hp" field
  changed `hp_max * 0.35` → `hp_max * 0.1` (10% of the parent's fully-computed HP, per explicit request).

## Changelog — 2026-07-28 (20th pass) — Fixed: fleet "count" FPS bug, Shoot dropdown's misleading "None"

- **Root-caused a heavy FPS drop with multiple Prosmothership carriers on screen**: `spawnmode2.json` and
  `my_timeline.json`'s `"fleet:"` entries all had `"count": 5` baked in — leftover from `_slot_default()`'s
  generic default, silently written by `_collect()` since fleets never had a count UI/meaning until the
  17th-pass fleet-count feature. Once `_tl_fire()` started actually honoring fleet count (17th pass), every
  one of those rows started deploying its WHOLE formation 5× instead of once — 8 Prosmothership rows × 5 =
  40 carriers × ~6 docked escorts each, ~280 extra nodes, all running their own flee/release/respawn cycle.
  Fixed by resetting every `"fleet:"` entry's count back to 1 in both files (46 + 41 entries respectively).
  `1strun.json` has 6 fleet entries with the same stale `count: 5`, left AS-IS — it's v1's locked/tuned
  file and v1's `_deploy_fleet()` explicitly ignores count anyway, so it's inert there (only matters if
  ever cross-loaded into spawn_mode_2's F7, which isn't the normal workflow).
- **Creep Info's Shoot dropdown showing "None" for units that DO fire** (e.g. "shooter"/jetfighter,
  "sentinel") **was misleading, not a stat bug**: "None" was both the no-override default AND an explicit
  "force no ranged attack" choice, indistinguishable — units with no override always displayed "None" even
  though their classic `behavior` fires just fine (Move/Shoot only reflects the NEW composed-mode override,
  it can't see into the ~30 bespoke classic behaviors — disclosed in the panel's own hint text). Fixed:
  Shoot now has its own separate "(default)" first option (mirroring Move), so "keep original firing
  behavior" and "explicitly disable firing" are visually distinct. This required a real logic fix alongside
  the UI one — `arena_enemy.gd`'s `_composed` gate was `move_logic != "" or shoot_logic != "none"`,
  which couldn't distinguish "no shoot override" from "explicitly overridden to none" (both resolve to the
  same string); changed to `d.has("move") or d.has("shoot")` so an explicit `shoot: "none"` override now
  correctly activates composed mode (forcing no ranged attack) instead of silently no-op'ing back to the
  classic behavior.

## Changelog — 2026-07-28 (19th pass) — Creep Info: sortable Unit/HP columns; every ENEMY_DEFS "xp" ×10

- **Every `"xp"` value in `ENEMY_DEFS`** (`arena_wave_director.gd`, `boss_scorpion.gd`'s own minion table)
  **scaled ×10 and rounded to a whole number** (part of a project-wide XP rescale — see
  [`core.md`](core.md)'s matching entry for the full rationale, `GameManager.BASE_XP`/`XP_PER_ASTEROID`/
  `XP_PER_BOSS`, and the honest answer to "does this lighten the math" — short version: no, it's a precision/
  readability change, not a perf one). Pacing is unchanged since the level-up cost curve scaled by the same
  factor.
- **Creep Info's Unit and HP column headers are now sort buttons** (`creep_info_panel.gd`): click "Unit
  ▲/▼" to toggle Z→A (▲) / A→Z (▼); click "HP ▲/▼" to toggle high→low (▼) / low→high (▲) — note Name's arrow
  meaning is intentionally the REVERSE of HP's, per explicit spec. `_apply_sort()` reorders the already-built
  row Controls in place (`move_child`) rather than rebuilding via `_populate()`, so unsaved in-progress edits
  in the SpinBoxes/dropdowns survive a re-sort. Also: dropped the `Gameplay.ttf` font override (default
  theme font throughout, matching the same-session Wave Editor/perf-overlay convention), and added an
  **XP Drop** column (editable SpinBox, same override/save plumbing as HP) between HP and Move.
- **HP→XP auto-fill button** — a small "→" between the HP and XP Drop columns per row; click sets that
  row's XP Drop SpinBox to `max(1, round(hp_spin.value / 100.0))` — floored at 1 so any HP under 50 (which
  would round to 0) still grants at least 1 XP rather than nothing. Reads the LIVE (possibly unsaved-edited)
  HP value, not the original def, so editing HP then clicking "→" chains correctly. Purely a per-row
  authoring shortcut — doesn't touch anything until you also hit Save.

## Changelog — 2026-07-28 (18th pass) — Creep Info: default font + XP Drop column; fly's static icon → flie1.png

- **`creep_info_panel.gd`**: dropped the `Gameplay.ttf` font override entirely (every label/button/spinbox
  now uses the default theme font, matching the same-session convention already applied to the Wave Editor
  and perf overlay). New **XP Drop** column (SpinBox, 0.0–1000.0 step 0.1 — several existing xp values are
  already fractional, e.g. 0.2/0.4/0.6) between HP and Move, same save/override plumbing as HP:
  `_on_save()` writes an `"xp"` key when changed from the def's base value, and the static
  `apply_overrides()` (called by both wave directors' `_ready()`) now also applies a saved `"xp"` override.
- **`fly`'s static "icon" field switched `animalflies.png` → `flie1.png`** (new sprite) in both
  `arena_wave_director.gd` (`"fly"` + `"elite_fly"`) and `boss_scorpion.gd`'s own minion table. This is
  safe/inert for the MAIN roster's `fly`/`elite_fly` in-arena rendering specifically: `flap_icons: ["flie1",
  "flie2"]` already made `_load_icon()` ignore the "icon" field's own filename entirely (only its directory
  matters for resolving the flap frames — see arena_enemy.gd `_load_icon()`), so the arena was already
  rendering flie1/flie2 either way — the "icon" field only mattered for everything ELSE that reads it
  directly: Wave Editor / Creep Info icon previews, "last hit by" (RUN OVER stats), Quick Spawn thumbnails,
  and — since it lacks `flap_icons` — boss_scorpion's own minion DOES render this statically in-arena during
  Scorpion fights, now updated to match. `creep_layout.cfg` needed no changes (a `"flie1"` costume entry —
  creeps/firepoints/thrustpoints/vortexpoints, all matching `"animalflies"`'s empty thrust/vortex data —
  already existed from when the wing-flap feature was added). `plume_styles.cfg` did NOT have a `"flie1"`
  key though (`_setup_plumes()`'s `cname` is also `_icon`-basename-derived) — duplicated `"animalflies"`'s
  existing tuned style dict under a new `"flie1"` key (both kept; `"animalflies"` now unused but harmless)
  so the plume look doesn't silently reset to default. Also updated for consistency: `arena_enemies.md`,
  `info/enemies_catalog.md`, `enemies_catalog.md` (doc references only).

## Changelog — 2026-07-28 (17th pass) — Fleet "n" wired to actually deploy; new Creep Info panel + composed Move/Shoot system

- **Fleet deployment ported into spawn_mode_2** (`arena_wave_director_v2.gd`): `_tl_fire()`'s `"fleet:"`
  early-return is gone — new `_deploy_fleet()`/`_deploy_mothership_v2()`/`_fleet_centroid()`/`_load_fleets()`
  port `arena_wave_director.gd`'s `_deploy_fleet()`/`_deploy_mothership()` (v1's own HP_MULT/SPEED_MULT are
  both 1.0, so skipped — v2 already tunes uniformly via `configure()`). Unlike v1, **"n" (count) is now
  honored** — `_tl_fire()` loops `_deploy_fleet()` `count` times (v1 explicitly ignores count: "fleet = its
  own formation (count/pattern ignored)"). Generic (non-mothership) slots roll one enemy from their pool and
  join the shared `_spawn_queue` (respects `MAX_ALIVE_V2` + the fair random drain, 14th-pass entry) instead
  of v1's instant unconditional `_spawn()`. A "mothership"-behavior slot (e.g. Prosmothership's
  `prosmotherblank`) still deploys immediately/uncapped, same as v1 — self-contained via arena_enemy.gd's
  `init_mothership()` regardless of which director spawned it. The Wave Editor's `_fleet_total_hp()`/
  `_row_total_hp()` comments updated to match (no longer describe fleets as a display-only gap).
- **Fleet slots gained a "n" (count) field** in the Wave Editor (`arena_wave_editor.gd`), mirroring Unit
  slots — a SpinBox in the fleet slot cell, defaulting to 1 on drag-drop assign, multiplying into
  `_row_total_hp()`'s fleet contribution. Now functional end-to-end (was authored/HP-planning-only in the
  16th pass, before the runtime side above existed).
- **New "Creep Info" dev panel** (`scripts/ui/hud/creep_info_panel.gd`, group `"creep_info"`) — a new HUD
  button between Boss Edit and Creep Edit (`arena_hud_buttons.gd`; Creep Edit and everything below it
  shifted down by one small-button height to make room). Lists every id in `arena_wave_director.gd`'s
  `ENEMY_DEFS` (~60+, the full v1 roster) with: icon, name (tooltip shows its original `behavior` string),
  an editable HP SpinBox, and independent **Move** / **Shoot** dropdowns. Saves to
  `res://creep_info_overrides.cfg` (sparse — only rows actually changed from their base value get an entry);
  each wave director applies saved overrides to its own `ENEMY_DEFS` once via the new static
  `CreepInfoPanelScript.apply_overrides(defs)`, called from both `arena_wave_director.gd._ready()` and
  `arena_wave_director_v2.gd._ready()` independently (not relying on instantiation order, since only one of
  v1/v2 is ever actually instantiated) — **takes effect from the next arena load**, not the current run.
- **New composed Move/Shoot system** (`arena_enemy.gd`) — orthogonal to the classic single `behavior` string
  match (which still tightly couples movement + attack per the ~30 existing bespoke behaviors: centipede's
  chain, mothership's docking cycle, magma's split-on-death, swarm's boomerang loop, etc. — these were
  **deliberately NOT decomposed**, since doing so would mean losing what makes each of them that specific
  enemy for little practical gain). `MOVE_LOGICS` = `["chase","standoff","orbit","spiral","patrol",
  "teleport","roam","stationary"]`, `SHOOT_LOGICS` = `["none","burst","fan","beam"]` — a curated, generic
  subset covering the common reusable patterns, reusing existing math where it already existed as a
  standalone helper (`_standoff()`, `_beamer_tick()`, the teleport-blink/idle-float math, the burst/fan fire
  math from "shooter"/"sentinel"). `configure()` reads optional `"move"`/`"shoot"` fields from the def; if
  either is non-default, `_composed = true` and BOTH `_init_behavior()`/`_tick_behavior()` short-circuit
  straight to `_init_composed()`/`_tick_move_logic()`+`_tick_shoot_logic()`, bypassing the classic `match
  behavior:` entirely — untouched units (no override, the overwhelming majority) have `_composed` stay
  false, zero behavior change. New dedicated `_cm_*`/`_cs_*` state vars (NOT the classic `_phase`/`_timer`/
  `_orbit_r`/`_scatter_target`) since composed mode runs a move-logic AND a shoot-logic concurrently — the
  classic system only ever ran one at a time, so reusing its shared vars risked collision (except "beam",
  which safely reuses `_beamer_tick()`'s own `_phase`/`_timer` since no move-logic here touches those).
  **Known, disclosed limitation**: the classic and composed systems cannot be mixed — overriding only ONE of
  Move/Shoot does NOT preserve the original bespoke pattern for the other side; it falls back to
  "stationary" movement / no shooting. Stated in the panel's own header hint text.

## Changelog — 2026-07-28 (16th pass) — Wave Editor: "Total HP" column

- **`arena_wave_editor.gd`** — new "Total HP" column between Type and the delete button (header row + each
  row's `hp_lbl` Label, 130px). `_row_total_hp(row)` sums `base_hp × count × blob` across the row's filled
  slots (`_director.ENEMY_DEFS`), including "fleet:" slots via `_fleet_total_hp()` (see below). `blob` (e.g.
  "swarm", blob:50) is multiplied in too, since each queued position for a blob-type def actually spawns
  `blob` creeps around it at runtime (`_tl_queue_or_spawn()`) — `count` alone would understate the true
  total for those types. Uses the RAW def `hp`, not the
  runtime-applied `ENEMY_HP_TUNE` (×2, arena_enemy.gd) or any "lvl"/Beacon/Champion multiplier — those
  depend on player level/aux state unknowable at authoring time, so this is a baseline/relative indicator,
  not the exact in-run total. `_fmt_hp()` shows the exact integer with thousands separators (e.g.
  "1,234,500") — no K/M abbreviation (an initial K/M version was replaced same-session per explicit
  request). Refreshed on every slot/count edit (`_update_row_hp()`, called alongside every existing
  `_update_type_btn()` call site, plus the count SpinBox's `value_changed` and the Type popup's OK button).
- **Per-slot HP readout in the Type popup's slot grid** (`_make_slot_cell()`): each filled, non-fleet slot
  cell now also shows its own "HP <exact>" (`hp_per_unit × count`, same `_fmt_hp()`), sized down to font 9
  and the Pattern dropdown shrunk 92→78px to make room without overflowing the cell's fixed 252×104 size.
  Updates live as you retype the count SpinBox (updates the label directly, no full-grid rebuild) and
  whenever a slot is freshly assigned via drag-drop (`_populate_slots_grid()` already rebuilds the cell from
  scratch, so the new unit's HP shows immediately). Fleet slot cells get the same "HP <exact>" readout next
  to the Boss checkbox, static (a fleet's composition isn't editable here — see below).
- **`_fleet_total_hp(fleet_name)`**: sum of `hp × blob` over EVERY unit listed in EVERY slot of the fleet
  (`res://fleet_layout.cfg` via the existing `_load_fleets()`) — per explicit correction, a fleet's HP is
  the straight total of all its units, including every option in a multi-choice slot (e.g. Kingdom1's
  `["sentinel2","sentinel1"]` slot counts both). Note `arena_wave_director.gd`'s `_deploy_fleet()` actually
  rolls only ONE random enemy per slot at real deploy time, so this is an authored/planning total ("what's
  in the fleet"), not a probability-weighted runtime estimate — an initial average-per-slot version was
  replaced same-session per explicit correction. **Caveat unchanged from the 5th-pass entry**: v2's timeline
  engine (`_tl_fire()`) still silently skips `"fleet:"` entries entirely — a fleet slot doesn't actually
  spawn anything in a live spawn_mode_2 run yet, so this HP doesn't show up in-game either way right now.
- **Fleet slots gained a "n" (count) field**, mirroring Unit slots: a new SpinBox in the fleet slot cell
  (`_make_slot_cell()`'s `is_fleet` branch) sets `slot["count"]` (defaults to 1 on drag-drop assign, in
  `_assign_slot()` — NOT the unit-count default of 5), and `_row_total_hp()`'s fleet branch multiplies
  `_fleet_total_hp(name) × count`. `_collect()` already wrote `"count"` for every slot type regardless
  (unchanged), so this was already round-tripping through save/load — it just had no UI and was never
  actually 1 (whatever `_slot_default()` left it at). **Known gap, same shape as the caveat above**: neither
  runtime currently deploys a fleet more than once per JSON entry — `arena_wave_director.gd`'s dispatch
  explicitly ignores it ("fleet = its own formation (count/pattern ignored)") and v2's `_tl_fire()` skips
  fleets outright — so this "n" is authored/HP-planning only until fleet deployment itself gets wired to
  actually loop `count` times in whichever engine ends up spawning it.
- **Type popup: "Total HP" next to the "Spawn slots (2 × 5)" header** — that header is now the left half of
  a new `right_hdr` HBoxContainer (was a lone Label), with a right-aligned "Total HP <exact>" Label as the
  other half. Kept live for free: the Label is stashed on `row["popup_hp_lbl"]`, and `_update_row_hp(row)`
  (already called from every count/drag-drop/OK-button edit path) refreshes it alongside the table's own
  Total HP column whenever it's open and valid — no separate wiring needed.
- **Unit icon grid widened to fill its panel** (`_build_unit_tab()`): the picker container was already
  600px wide, but the icon ScrollContainer/GridContainer was hard-set to 290px (5 columns) — leaving ~300px
  of dead space before the VSeparator dividing it from the slots panel. Widened to 580px / 10 columns.

## Changelog — 2026-07-28 (15th pass) — Jet Fighter bullet MultiMesh + range cap, 120s stale-enemy despawn

- **Jet Fighter bullets → MultiMesh** (`arena_enemy_manager.gd`): the "shooter" behavior (arena_enemy.gd) and
  spawn_mode_2's "steer_kiter" both fire from the jetfighter.png sprite — their bullets now tag
  `spawn_bullet(..., kind="jetfighter")` and render through a dedicated `_jf_mm` MultiMeshInstance2D
  (`_setup_jf_multimesh()` in `_ready()`, `_sync_jf_multimesh()` called right after `_tick_bullets()` each
  frame) using the user-supplied `assets/weaponry/jetfighterbullet.png` (112×280, scaled to `JF_BULLET_LEN`
  = 22px height, aspect-preserved width — never stretched). Same technique as `arena_weapons.gd`'s Gatling
  tracer (`_setup_gat_multimesh`/`_sync_gat_multimesh`, 18th-pass-equivalent from earlier this session), a
  separate instance since these bullets live in a different array/script. `_draw()`'s generic circle+tail
  immediate-mode loop now skips `kind == "jetfighter"` bullets (every other enemy bullet — sentinel's fan,
  etc. — is untouched, still the plain circle draw). `JF_SPRITE_ROT_OFFSET`'s sign (nose-up assumption) is
  untested — flip if the art faces the wrong way in-game.
- **Jet Fighter bullet range cap**: `JF_BULLET_MAX_DIST := 2000.0`, read in `_tick_bullets()` only for
  `kind == "jetfighter"` bullets (everything else keeps the existing generic `BULLET_MAX_DIST` = 2200).
- **120s stale-enemy safety net** (`arena_enemy.gd`): `LIFETIME_MAX := 120.0` — any non-boss enemy
  (`behavior != "boss_stub"`) still alive that long (`_t`, the existing since-spawn age accumulator) is
  silently removed via new `_despawn_stale()` (releases mothership-docked escorts / detaches a squid first,
  then `queue_free()`) — deliberately NOT `_die()`: no kill-count, no XP/loot/reward roll, no death FX/SFX,
  since this is a cleanup, not a kill. Prevents any enemy that for whatever reason never reaches/engages the
  player (e.g. wanders off and — for non-`steer_*` behaviors — never gets recycled, see the spawn_mode_2
  despawn/teleport note in the 7th-pass entry) from occupying a population-cap slot forever.

## Changelog — 2026-07-28 (14th pass) — "missile" hard cap + fair, non-discarding spawn queue

- **Root-caused "why do ~20 missile launchers show up when no JSON row says 20"** (spawn_mode_2,
  `spawnmode2.json`): three separate timeline rows (5 + 10 + 10 = 25 total across the whole run) plus the
  "missile" behavior never being covered by `_tick_despawn_teleport()` (only `steer_*` behaviors get
  recycled — see the 7th-pass entry) meant every missile launcher ever spawned just accumulates forever
  (near-zero contact damage, stands off at range, nothing kills it off) instead of any single burst being
  the cause.
- **`MISSILE_MAX_ALIVE := 4`** (`arena_wave_director_v2.gd`): hard cap enforced unconditionally in
  `_spawn_def()` — the one funnel every spawn source goes through (timeline ring/scatter, catch-up,
  cluster/wall) — via a new `_type_alive_count(type_id)` helper. Deliberately ignores the usual boss/elite
  cap-bypass since "missile" is never boss/elite. `_reinforce_type()` also excludes "missile" from the
  catch-up candidate pool once at cap, so the low-population rescue stops offering it too.
- **Follow-up bug found while investigating**: `MAX_ALIVE_V2` (500) gets oversubscribed by this JSON almost
  immediately — cumulative requested spawns already exceed 500 by t=60s. Once the field is pinned at that
  cap (which it stays near for the rest of a normal run, since nothing recycles non-`steer_*` types), the
  OLD `_drain_spawn_queue()` popped strictly FIFO and **silently discarded** any spawn that failed the cap
  check — permanently losing it. Worse, `"stream"` entries (used heavily in this JSON with `"duration":
  0.0`, which clamps to a 0.01s minimum — see `_tl_fire()`) bypassed the shared queue entirely and called
  `_spawn()` directly, dumping their *entire* count in essentially one frame; whichever wave happened to be
  mid-stream when a kill freed room would grab it near-exclusively, reading as "only fleet2 spawns" even
  though the JSON never authored anything close to that as a single burst.
- **Fix**: `_drain_spawn_queue()` now (a) pre-checks the population cap once per frame and skips entirely if
  full — nothing is popped, so nothing is lost — and (b) when there IS room, draws a **random** index from
  `_spawn_queue` each attempt (not `pop_front()`) so no single wave/source can monopolize freed room; a
  failed per-type-cap pick (e.g. "missile" already at 4) is left queued and a different pick is tried
  instead, bounded to `min(queue.size(), 50)` tries/frame so an all-blocked queue can't stall a frame.
  `_tl_tick_streams()`'s two non-boss spawn sites now push into the same shared `_spawn_queue` instead of
  calling `_spawn()` directly — the credit/duration/ramp system still controls *when* a stream's units
  enter the pool, but actual instantiation now goes through the same fair, retry-until-room drain as every
  other source. Net effect: a heavily oversubscribed wave file no longer silently loses whatever didn't fit
  the instant it fired — every authored unit eventually spawns as kills free room, and composition when
  room frees up is randomized across whatever's currently pending instead of favoring whichever source
  fired most recently.

## Changelog — 2026-07-28 (13th pass) — "last hit by" tracking (regular enemies only) + F7 default-loads the active file

- **`arena_wave_editor.gd`** now opens (F7 / Wave Edit button) already showing the file that's actually
  driving the current run: `_sync_active_file()` (called from `_toggle()`) reads `LAST_WAVE_CFG`
  (`res://spawn_mode_2_wave.cfg`, the same file `_remember_last_wave()` writes on Load — see the 9th-pass
  entry) and sets the Name field + pre-selects it in the Load dropdown. Purely cosmetic — `_rebuild_rows()`
  already pulled the correct ROWS from `_director.get_timeline()` regardless (`arena_wave_director_v2.gd`
  auto-loads the remembered file at its own `_ready()`); this just stops the Name field from showing a
  blank "my_timeline" placeholder next to rows that are actually the active file's.
- **"Last hit by" tracking** (RUN OVER screen — see [`weapon.md`](weapon.md) for the full stats feature):
  `arena_enemy.gd._report_hit_player()` (new helper) calls `GameManager.record_last_hit(_type.
  capitalize(), _original_icon)` right before every `GameManager.ship_take_damage()` this file triggers
  — both `_check_contact()` branches (centipede bite + normal contact) and the `_MissileVolley` inner
  class's line-hit (via its stored `_launcher` ref). `arena_enemy_manager.gd` covers the other two player-
  damage paths it owns: `_tick_bullets()` (enemy ranged bullets — resolves the bullet dict's `"owner"`
  instance id back to the enemy node via `instance_from_id()`) and `explode()` (already had a `source`
  param, just wasn't using it for this). **Scoped, agreed gap**: boss-specific attack code
  (`arena_elephant.gd`, `boss_chromeleon.gd`, `boss_metalfly.gd`, `boss_nautilus.gd`, `flame_ring_reveal.
  gd` — ~30 more `GameManager.ship_take_damage()` call sites) is NOT instrumented; a death immediately
  after a boss-only attack (no regular-enemy damage in between) will show whichever regular enemy hit
  last, not the boss. Full boss coverage would mean adding an optional `source` param to `GameManager.
  ship_take_damage()` itself and threading it through all ~30 sites — deliberately deferred as a much
  bigger, riskier change than what was asked.

## Changelog — 2026-07-28 (12th pass) — F7 Type popup gets an OK button

`arena_wave_editor.gd._open_type_dropdown()`'s Unit/Fleet + slot-grid popup already saved edits live —
drag-drop and the per-slot count/pattern/boss controls write straight into `row["slots"]` as you touch
them, no separate commit step. Added an explicit **OK** button anyway (top-left of the popup, leftmost in
the tabs row, green like Load) for a clear "I'm done" action: refreshes the bottom JSON readout then
closes, same net effect as clicking outside but explicit rather than implicit.

## Changelog — 2026-07-28 (11th pass) — animalhornet reverted to bomber, HP bumps, F7 UI tweaks

- **`test_charger` reverted to animalhornet's own "bomber" behavior** (roam near the player, drop bombs)
  instead of the `steer_charger` dash — `TEST_ROSTER`'s entry now has no `"behavior"` override at all, so
  `_ready()` just keeps whatever behavior the base type (`animalhornet`) already carries in v1's
  `ENEMY_DEFS`. `steer_charger` itself is untouched in `arena_enemy.gd` (unused now, not deleted).
- **HP bumps** via a new `"hp_mult"` field on `TEST_ROSTER` entries, applied in `_ready()` before XP is
  derived (so the HP-proportional-XP rule still holds): `test_charger` (animalhornet) **+30%**,
  `test_kiter` ("jetfighter" sprite, base type `shooter`) **+50%**.
- **F7 Wave Editor UI**: Close/Load/Apply & Restart buttons now have distinct font colors (red/green/
  yellow) so the risky vs. safe actions read at a glance. The whole panel's font switched from
  `Gameplay.ttf` to Godot's default theme font — `_font` is left `null` in `_ready()` so every scattered
  `if _font: ...add_theme_font_override(...)` call site across the file no-ops (no per-call-site edits
  needed). The per-slot unit-count SpinBox's 200 cap is removed (raised to 100,000, i.e. effectively
  unlimited) — the Quick-test builder's separate count field is untouched (not "per slot").

## Changelog — 2026-07-28 (10th pass) — instant catch-up burst to 100, elites immune to knockback + 2× size

- **Catch-up rescue, two-stage now**: the moment it triggers (rising edge only, `_catchup_burst()`),
  `CATCHUP_BURST` (50) spawns are queued immediately (still budget-drained on actual instantiation by the
  existing `_drain_spawn_queue()` — "immediate" means not waiting on the rate accumulator to ramp up over
  several seconds, not literally 50 `add_child()` calls in one frame). The ordinary catch-up rate climb in
  `_tick_spawn_loop()` then continues from there up to the new `CATCHUP_TARGET` (**100**, was 50) before
  handing back control. `START_BOOST_TRIGGER` (50) is a **new, separate** const for the opening-surge
  decay trigger — it used to piggyback on `CATCHUP_TARGET` (both happened to be 50), now decoupled so
  raising `CATCHUP_TARGET` to 100 doesn't also double how long the opening 3× spawn-rate surge lasts.
- **Elites immune to knockback** (`arena_enemy.gd take_damage()`): the pushback impulse (Nuke/Gatling's
  `knock` param) is now gated `and not _is_elite` — a big "mini-boss" enemy no longer go skating across
  the screen on every hit. Applies to ANY `_is_elite` enemy (v1's milestone elite_fly/bug/bee too, not
  just spawn_mode_2 Champions — it's one shared code path, not data, so there's no sensible way to scope
  it to just Champions without a separate flag; seemed like a strict improvement for v1 elites either
  way).
- **Champion size 3× → 2×** (`CHAMPION_SIZE_MULT` in `arena_wave_director_v2.gd`): exactly double a
  normal creep's size now, down from triple. `CHAMPION_HP_MULT` (50×, still matching v1's elite_fly/bug/
  bee) and `CHAMPION_SPEED_MULT` (1.5×) unchanged. v1's own elite_fly/bug/bee entries are untouched (they
  carry hand-authored absolute sizes in `ENEMY_DEFS`, not a multiplier — out of scope, not part of this
  request).

## Changelog — 2026-07-28 (9th pass) — remembered wave file + temp Gatling-only start

- **F7 Load now persists across runs**: `arena_wave_editor.gd._on_load()` writes the loaded filename to
  `res://spawn_mode_2_wave.cfg` (`_remember_last_wave()`, section `"wave"`, key `"last_file"` — same
  `res://`-config convention as `default_layout.cfg`/`fleet_layout.cfg`/`creep_layout.cfg`, not `user://`,
  since this is dev-tooling state meant to live alongside the project). `arena_wave_director_v2.gd._ready()`
  now calls `_load_remembered_timeline()`, which reads that file and `set_timeline()`s it automatically —
  so a timeline JSON Loaded once via F7 stays active on every subsequent run without reopening F7. Only
  `_on_load()` writes the marker (not `_on_save()`/Apply) — scoped to exactly "load a file" per the
  request. Harmless with spawn_mode_1 active: v1 has no reader for this file, so the write is a no-op for
  it either way.
- **Temp: start-of-run weapon chest hidden, Gatling Gun only** (`arena.gd`, `const SKIP_START_CHEST :=
  true`): `_open_start_chest()` now short-circuits to a single `acquire_weapon("gatling_gun")` call and
  returns — no pick-1-of-3 chest UI, no Hub Loadout seeding. Flip the const back to `false` to restore
  the normal chest + Loadout flow.

## Changelog — 2026-07-28 (8th pass) — catch-up reinforcement matches the loaded timeline's own roster

Follow-up to the 7th-pass fix: the low-population catch-up path (still deliberately active even with a
timeline loaded, per explicit request) was reinforcing with the fixed 4-type test roster regardless of
what the loaded timeline actually spawns — so a rescue burst could still summon a "stray" type. Fixed:

- `_tl_fire()` now records every "safe" type into `_tl_seen_types` (a set) the moment the timeline
  actually fires it — "safe" excludes `is_boss` entries, `"elite":true` types, and `"blob"` types (a
  rescue shouldn't summon 50 units at once). Reset (cleared) on every `set_timeline()`.
- New `_reinforce_type()`, used by `_queue_ambient()`/`_queue_cluster()`/`_queue_wall()` (the functions
  the catch-up path calls into) instead of `_rand_test_type()`: with a timeline loaded, picks randomly
  from `_tl_seen_types` — i.e. only a type the timeline has **already** spawned so far, never one from a
  later/harder wave that hasn't fired yet ("không vượt cấp"). Falls back to the single weakest roster
  type (`TEST_TYPES[0]`, flies) if the timeline hasn't fired anything yet. No timeline loaded → unchanged
  behavior (the default 4-type roster, gated by `TYPE_UNLOCK_TIME`, same as before).
- Champion (`_spawn_champion()`) still calls `_rand_test_type()` directly, untouched — reinforcement-type
  matching only applies to the catch-up path, per explicit request ("champion giữ nguyên").

## Changelog — 2026-07-28 (7th pass) — a loaded F7 timeline suppresses the continuous test-roster loop

Reported bug: after Loading a JSON via F7 in spawn_mode_2, "stray" enemies (flies/dragonfly/shooter/
animalhornet, or their Champion variants) still appeared even though they weren't in the file. Root
cause: v2 runs 3 independent spawn sources, and only the new timeline engine actually reads the loaded
JSON — the continuous ambient/cluster/wall loop (`_tick_spawn_loop`) and the Champion spawner
(`_tick_champion`) keep running from the fixed 4-type test roster regardless, by original design (the
timeline was meant to be an ADDITIVE second channel).

Fix, scoped to exactly what was asked (only the continuous loop stands down, not Champion or the
population-floor rescue): `_tick_spawn_loop()` now returns immediately, before spending any rate budget,
whenever `timeline` is non-empty (a JSON was Loaded/Applied) **and** the low-population catch-up isn't
currently active. So:
- **Timeline loaded, population healthy** → ordinary spawns come ONLY from the timeline — matches
  "exactly what's in the JSON, no strays."
- **Timeline loaded, population crashes below `LOW_COUNT_THRESHOLD` for `LOW_COUNT_GRACE`s** → the
  catch-up path still runs (from the test roster) to keep the field from truly emptying out, same as
  with no timeline loaded — kept unchanged per explicit request ("cứu viện giữ nguyên").
- **Champion** (`_tick_champion`) is a separate call in `_process()`, entirely untouched — still fires on
  its own clock regardless of whether a timeline is loaded ("champion giữ nguyên").
- `_spawn_acc` (the rate accumulator) does NOT accumulate while the loop is standing aside — clearing the
  timeline back to blank later resumes at a normal rate, not a built-up burst.
- No change to `arena_wave_director.gd` (v1) or the timeline engine itself (`_tl_tick`/`_tl_fire`) —
  purely a gate on the pre-existing continuous-loop function.

## Changelog — 2026-07-28 (6th pass) — gap-spread: sparse timeline rows auto-fill blank grid ticks

Editing simplification for spawn_mode_2's F7 timeline (v2-only, no v1 equivalent — v1's timeline is
locked/hand-authored and unaffected). Before this, a filled row after a run of blank 5s-grid rows fired
its whole count in one instant burst at its own time. Now `arena_wave_director_v2.gd.set_timeline()` runs
`_spread_gaps()`: a filled row's count is divided evenly across every ~`GRID_SPREAD_STEP` (5s) tick
spanning the gap since the PREVIOUS filled row, so a row @10s followed by blanks and a row @60s (50s gap,
10 ticks) spreads that row's count across 15,20,…,60 instead of dumping it all at 60. Tick spacing is the
gap divided by the tick count (not a fixed 5s), so the LAST tick always lands exactly on the row's own
authored time even if that time isn't itself grid-aligned; remainder units go to the final ticks so the
total spawned always matches the authored count exactly.

- **Exempt** (fire as authored, no spreading): the first row in a timeline (nothing precedes it), any row
  with **"Boss" checked**, and any row using the **"stream" pattern** (already has its own ramp/duration
  spread — stacking gap-spread on top would double up).
- **The editor still shows/saves your original sparse rows** — `timeline` (what `get_timeline()`/Save/
  Load see, so F7 round-trips exactly what you authored) is untouched by spreading; a separate
  `_tl_fire_queue` (the expanded version) is what `_tl_tick()` actually fires from. Re-opening F7 after
  Apply shows the same rows you typed, not a wall of tiny expanded ones.

## Changelog — 2026-07-28 (5th pass) — F7 Wave Edit now works in spawn_mode_2

The Wave Edit button/F7 did nothing while `USE_SPAWN_MODE_2` was on — `arena.gd` only instantiated
`WaveEditorScript` in the `else` (spawn_mode_1) branch, so `get_tree().get_first_node_in_group
("wave_editor")` found nothing and `arena_hud_buttons.gd._on_wave_edit()`'s `has_method("toggle")` guard
silently no-opped. Fixed by giving `arena_wave_director_v2.gd` a **second, optional spawn channel**: a
full timeline engine that runs *alongside* the continuous annulus loop (which is untouched and keeps
running), ported from `arena_wave_director.gd`'s pattern/stream logic (GDScript has no mixins and v1 is
locked, so it's a straight port, not a shared base):

- **API the editor needs, all added**: `get_timeline()` / `set_timeline(entries)` / `elapsed()` / the
  `PATTERNS` const (`ENEMY_DEFS`/`enemy_types()` already existed). `arena.gd` now adds `WaveEditorScript`
  in the `elif USE_SPAWN_MODE_2:` branch too.
- **All 8 v1 patterns** (`ring/arc/scatter/pincer/wall/wedge/portal` + `stream` with ramp/formation/burst)
  ported as `_tl_pattern_positions()`/`_tl_tick_streams()`, radius swapped from v1's fixed `SPAWN_RADIUS`
  to v2's own `_r_min()`/`_r_max()` annulus — timeline spawns still honor "never appear on-screen" the
  same way the continuous loop does.
- **`elapsed()` is timeline-relative, not the run clock**: `set_timeline()` stamps `_tl_start_t = _run_t`;
  `elapsed()` returns `_run_t - _tl_start_t`. `_run_t` itself is never reset by the timeline (it also
  drives Agony Rank / type-unlock times / Champion timing) — but a timeline authored as "row at 5s, 10s…"
  should always replay from ITS OWN start whenever you hit Apply, not from wherever the run clock
  happens to be.
- **Alive-cap**: `_spawn`/`_spawn_def` gained an `is_boss` param and now do the actual cap check
  themselves (boss or `"elite":true` bypasses; everything else — continuous loop, timeline, Champion —
  funnels through one `_effective_cap()` gate). Matches v1: "Boss bỏ qua cap, quái thường tính cap."
- **Not ported** (deliberately out of scope for this pass): Fleet deployment (`"fleet:<name>"` entries
  are silently skipped — Fleet Edit's `fleet_layout.cfg` path isn't wired to v2), the Scorpion's
  `gate_waves` freeze-the-whole-director mechanic, and the background texture prewarm (a pure perf
  nicety in v1). A saved v1 timeline JSON loads and mostly plays in v2 as long as it doesn't use fleets.

## Changelog — 2026-07-28 (4th pass) — ruin pointer icon, periodic giant wrecks, restored small-ruin system

- **`perf_overlay.gd`**: the `Time mm:ss` run-clock (`_play_t`) now accumulates every frame regardless of
  whether the FPS switch is on — moved the `if not get_tree().paused: _play_t += delta` line above the
  `if not visible: return` early-out. It was already only being drawn while visible; now it's also only
  *counted* while visible was previously wrong — the clock silently reset-relative behavior (started
  counting only from whenever the switch was later turned on) instead of counting from arena start.
- **`arena_ruin_layer.gd`** (the giant, far-away wrecks — active in every spawn mode):
  - `DIST_MAX` 20,000 → **15,000px** (`DIST_MIN` unchanged at 10,000) — the run-start pair spawns closer.
  - **Periodic respawn**: gained a `_process()` — one additional wreck now spawns every
    `PERIODIC_INTERVAL` (180s / 3 min) at a fresh `[DIST_MIN, DIST_MAX]` distance from the player's
    **then-current** position (not the original run-start point), so later wrecks stay reachable as the
    player roams. Refactored the run-start pair's spawn body into `_spawn_one_wreck(origin, angle)`,
    shared by both the initial `_spawn_wrecks()` (2 wrecks) and the periodic tick (1 wreck).
- **`arena_ruin_pointer.gd`**: replaced the spinning chrome-arrow `_draw()` with the wreck's own already-
  loaded ship texture (`target.get("_tex")`, read once via `_load_icon()`), drawn at a fixed `ICON_WIDTH`
  (50px, height from the source aspect ratio — never stretched). The distance label now hides once the
  wreck itself falls inside `arena_enemy_manager.visible_world_rect()` (the player can already see it
  directly) — `_on_screen` gates `_lbl.visible`; the icon itself still shows at the clamped screen edge
  regardless (kept as a directional aid, per the literal ask — only the number was to be suppressed).
- **Small-ruin system restored, spawn_mode_2 only**: two new files, `arena_small_ruin.gd` +
  `arena_small_ruin_layer.gd`, are near-verbatim restorations of the **original** ruin design from before
  it was reworked into today's giant-wreck system (git history commit `ade3fd1`, superseded by `27f33cc`)
  — ship (200 HP, 70px) drifts 20–50px/s → dies into a box (50 HP, 40px) → box drops one of
  `["coin","diamond","heart","magnetic","divinity"]` (`arena_loot.gd`). Spawns one every 5–15s in a
  650–800px ring around the player (`arena_small_ruin_layer.gd`, mirrors the old `arena_ruin_layer.gd`).
  **`"shield"` was dropped from the restored loot pool** — it was in the original pool, but `arena_loot.
  gd`'s `_collect()` no longer has a `"shield"` case (that path was retired along with
  `arena_shield_visual.gd`, now an orphaned file) — including it would silently do nothing on pickup.
  Both new scripts join the shared group `"arena_ruin"` (same as the giant wrecks), so existing
  `arena_weapons.gd`/`explode()` combat code hits them for free — no changes needed there. Wired in
  `arena.gd` **only** inside the `elif USE_SPAWN_MODE_2:` branch (`ArenaSmallRuinLayerScript`) — spawn
  mode 1 / the test spawner are untouched, still only the giant wrecks. The giant-wreck system itself
  (`arena_ruin.gd`/`arena_ruin_layer.gd`) is unmodified aside from the DIST_MAX/periodic changes above and
  still runs unconditionally in every mode.

## Changelog — 2026-07-28 (spawn_mode_2: annulus director + steering movement, isolated test system)

New **parallel** spawn director — `scripts/gameplay/arena_wave_director_v2.gd` — implementing a classic
survivor-like continuous spawn loop, alongside (not replacing) the authored-timeline
`arena_wave_director.gd` / `Level_1_Minh.json` run. Toggle: `arena.gd` `const USE_SPAWN_MODE_2` (currently
`true` for active testing; same pattern as the existing `USE_TEST_SPAWNER` — flip to `false` to restore
the authored timeline + F7 editor). **Does not touch the authored timeline, its `ENEMY_DEFS` entries, or
any existing enemy's behavior** — everything new is additive.

- **Annulus spawn geometry**: `R_min` = half the camera-visible screen diagonal (`arena_enemy_manager.
  screen_size()`) + `R_PADDING` (150px); `R_max = R_min + R_WIDTH` (300px). Enemies always spawn in this
  ring around the player, never in view.
- **Batched spawn loop**: every `SPAWN_INTERVAL` (0.1s), the accumulator grows at `TARGET_RATE` (2/s — a
  fractional accumulator like the rest of the codebase, but the credit spent per firing is the batch's
  actual unit count, not a flat 1.0, so a 50-unit cluster doesn't spend the rate 50× too slow) up to
  `MAX_ALIVE_V2` (120) live `"arena_enemy"` nodes. Tuned to read as v1's *gentle intro* density, not its
  post-20-min endgame cap (500–1200) — this director doesn't ramp over time. Spawns are queued and
  drained at `SPAWN_BUDGET` (4) per frame — same queue+budget shape as v1's `_spawn_queue`/`SPAWN_BUDGET`.
- **3 spawn patterns**, weighted (`PATTERN_WEIGHTS`): **Ambient** (uniform random angle+radius on the
  annulus), **Cluster/Swarm** (one anchor point on the annulus, 10–50 enemies scattered within
  `CLUSTER_DELTA_R`), **Wall** (a `WALL_N`-unit line abreast perpendicular to one approach angle, advancing
  as one front — reuses v1's `"wall"` pattern math).
- **Despawn/teleport**: throttled sweep (`DESPAWN_INTERVAL` 0.5s) recycles any `steer_*`-behavior enemy
  beyond `R_max × R_DESPAWN_MULT` (1.5) by teleporting it back into `[R_min, R_max]` along **its own
  existing angle from the player** — same relative side, just pulled closer — rather than a fresh random
  or player-heading-biased angle (which would read as a different enemy appearing from nowhere).
- **4 new movement behaviors** in `arena_enemy.gd` `_tick_behavior()`/`_init_behavior()` — used **only**
  by 4 new test roster entries (`test_chaser/test_flanker/test_kiter/test_charger`). Their stats/sprite
  are NOT invented — each is v1's own `ENEMY_DEFS` entry for a low-tier enemy (`fly`/`dragonfly`/
  `shooter`/`animalhornet` respectively), duplicated with only `"behavior"` overridden to the new
  steer_* logic (`TEST_ROSTER` in `arena_wave_director_v2.gd`, resolved in `_ready()`) — a fresh-loadout
  player can actually clear them, unlike the initial version of this system which reused `"bug"` (a
  level-2, 200 HP insect) for the constantly-spawning chaser and overwhelmed the player. The existing
  ~30 `"chase"`-behavior enemies in v1 are untouched:
  - `"steer_chaser"` — pure Seek (`velocity = dir_to_player * speed`). No flank bias, no self-computed
    separation — separation is still entirely `arena_enemy_manager._tick_separation()`'s spatial-hash
    push-apart pass (deliberately NOT reimplemented per-enemy; that pass is already tuned for 500+
    enemies).
  - `"steer_flanker"` — seeks a point ahead of the player: `player_pos + player_velocity *
    FLANK_PREDICT_T` (0.5s). Reads velocity from the v2 director via group `"wave_director"`
    (`has_method("player_velocity")` guarded).
  - `"steer_kiter"` — 3-zone standoff: approach past `KITE_R_ATTACK` (340px), hold + fire a bullet every
    `KITE_FIRE_INTERVAL` (1.2s) between `KITE_R_FLEE` (160px) and `KITE_R_ATTACK`, flee below
    `KITE_R_FLEE`. Fires from `global_position` (test enemies have no authored firepoints, unlike
    `"shooter"`).
  - `"steer_charger"` — phase machine on the generic `_phase`/`_timer` vars: slow approach
    (`CHARGE_APPROACH_SPEED`) until `CHARGE_LOCK_RANGE` (260px) → lock `_aim` + pulse the existing hit-flash
    (`_flash`/`_flash_color`, red) for `CHARGE_TELEGRAPH_T` (0.6s) → dash at `CHARGE_DASH_SPEED` (620px/s)
    in a straight line for `CHARGE_DASH_T` (0.5s) → back to approach.
- Contact damage, HP/speed/XP global tuning (`ENEMY_HP_TUNE`/`ENEMY_SPEED_TUNE`), and the manager's
  separation/off-screen-LOD all apply to the 4 new types automatically — `_check_contact()` and
  `configure()` are behavior-agnostic, no changes needed there.
- v2 still joins group `"wave_director"` and exposes a merged `ENEMY_DEFS` (v1's table + the 4 new
  entries) so `_spawn_sibling`, the F12 debug-spawn panel, and the weapon palette keep working unchanged
  when v2 is active. It does **not** implement `get_timeline()`/`set_timeline()` — the F7 wave editor is
  simply not instantiated in this mode (same as `USE_TEST_SPAWNER`).

### Update (same day) — roster taken from v1, Agony Rank, Champions

The first pass reused `"bug"` (a level-2, 200 HP insect) for `test_chaser` and spawned it at 8/s — the
horde outscaled a fresh loadout immediately. Fixed + extended:

- **Test roster now IS v1's roster**: `TEST_ROSTER` in `arena_wave_director_v2.gd` maps each steer_*
  behavior onto one of v1's own low-tier `ENEMY_DEFS` entries (`test_chaser`→`fly`, `test_flanker`→
  `dragonfly`, `test_kiter`→`shooter`, `test_charger`→`animalhornet`), duplicating the whole def and
  overriding only `"behavior"` — same HP/speed/size/xp/icon v1 already tuned, resolved once in `_ready()`.
- **Spawn-loop accounting bug fixed**: the fractional accumulator used to spend a flat `1.0` credit per
  batch fired regardless of batch size, so a 50-unit cluster spawned ~20× faster than `TARGET_RATE`
  implied. Now spends the batch's actual unit count. `TARGET_RATE` 8→2/s, `MAX_ALIVE_V2` 500→120 (matches
  v1's early-game density, not its post-ramp endgame cap).
- **Despawn/teleport preserves relative direction**: an out-of-range `steer_*` enemy is pulled back into
  `[R_min, R_max]` along **its own existing angle from the player**, not a fresh random or
  player-heading-biased angle — same side, just closer.
- **Agony Rank** (`_agony_rank` in `arena_wave_director_v2.gd`): the harder-the-longer-you-survive knob.
  +1 every `AGONY_TIME_INTERVAL` (5 min) survived; +1 whenever `FASTKILL_COUNT` (20) enemies die within a
  rolling `FASTKILL_WINDOW` (1s) — edge-triggered off `GameManager.run_kills` so a sustained massacre
  doesn't rank up every frame, only once per crossing. −1 whenever `GameManager.rebirth_used` fires (a
  Phoenix Core revive charge spent) — floored at 0. Feeds `_tick_spawn_loop`'s rate as
  `TARGET_RATE + AGONY_RATE_PER_RANK (0.3) × rank`, flat, uncapped. **Not covered**: the separate Project
  Phoenix / Player-2 revive (`arena_weapons.gd player2_phoenix_try`) doesn't emit `rebirth_used`, so it
  doesn't dock Agony Rank.
- **Champions**: a gold-ringed, tougher spawn on its own clock, outside the ambient/cluster/wall loop and
  exempt from `MAX_ALIVE_V2` (same exemption v1 gives bosses/elites). Interval = `CHAMPION_BASE_TIME`
  (150s) − `CHAMPION_TIME_PER_RANK` (9s) × Agony Rank, floored at `CHAMPION_TIME_FLOOR` (30s). Each one is
  a random test-roster archetype scaled by v1's own milestone-elite multipliers (`CHAMPION_HP/SIZE/
  SPEED_MULT` = 50×/3×/1.5×, same numbers as `elite_fly/bug/bee`) and flagged both `"elite"` (cap-bypass +
  `grant_reward` on death, reusing `_is_elite` — arena_enemy.gd) and the new `"champion"` (`_is_champion`
  → a gold `draw_arc` ring at `_radius × 1.25`, arena_enemy.gd `_draw()` — champions had no visual marker
  before this; `_is_elite` alone draws nothing).
- `perf_overlay.gd` (FPS overlay, top-right) now also shows an `Agony N` readout next to `Spawn Mode 2:
  ON`, via the same `has_method` duck-typed lookup (`wd.agony_rank()`).

### Update (same day, 2nd pass) — wave order, HP-proportional XP, vortex flies, population floor

- **Wave order now references v1's own intro timeline**: `TYPE_UNLOCK_TIME` in `arena_wave_director_v2.gd`
  gates `_rand_test_type()` (used by ambient/cluster/wall AND Champion picks) to types already "unlocked"
  at `_run_t` — `test_chaser` (flies) unlocks at t=0 so the run always opens on flies alone (previously a
  uniform random pick across all 4 could open on a dragonfly), `test_flanker` (dragonfly) at 46s and
  `test_kiter` (shooter) at 55s match v1's own intro timestamps for those enemies, `test_charger`
  (animalhornet, never in v1's early game at all) at 90s as the last of the four introduced.
- **XP proportional to HP**: `_xp_per_hp` is resolved once in `_ready()` from v1's own `"fly"` entry —
  1.0 xp / 20.0 hp = 0.05 xp per HP (fly's base stats; the automatic ×2 HP/XP tune in
  `arena_enemy.configure()` scales both sides equally so the ratio survives it unchanged). Every
  test-roster def's `"xp"` is recomputed as `hp × _xp_per_hp` in `_ready()` (previously each def just
  carried over its base type's independently-tuned v1 xp value, e.g. animalhornet's 1.5/50 = 0.03 ratio,
  inconsistent with the rest of the roster) — and re-applied in `_spawn_champion()` AFTER the HP scale, so
  a Champion's XP scales right along with its inflated HP instead of staying at the base value.
- **Flies move in a vortex**: `"steer_chaser"` (arena_enemy.gd) no longer does a pure straight Seek —
  it blends the seek direction with a tangential (perpendicular) component that's strongest far from the
  player and fades to 0 near it (`VORTEX_TANGENT_RATIO`/`VORTEX_FADE_NEAR`/`VORTEX_FADE_FAR`), so flies
  swirl in from a distance and straighten into a direct dive for the final approach — a per-enemy
  `_vortex_sign` (set once in `_init_behavior()`) picks CW vs. CCW so the swarm doesn't all spin the same
  way. `steer_flanker`/`steer_kiter`/`steer_charger` are untouched (still pure seek/standoff/dash).
- **Population floor**: the field is never allowed to sit below `LOW_COUNT_THRESHOLD` (20) for long.
  `_tick_low_count_watch()` runs a `LOW_COUNT_GRACE` (2s) sustained-below-threshold timer; once it trips,
  `_tick_spawn_loop()` swaps its cap/rate from `MAX_ALIVE_V2`/Agony-scaled-`TARGET_RATE` to
  `CATCHUP_TARGET` (50) / `CATCHUP_RATE` (15/s) until the count reaches 50 (still queue+budget-drained,
  so it fills in gradually, not an instant dump), then hands back control to the normal cap/rate.

### Update (same day, 3rd pass) — opening-surge rate multiplier

The population floor above is a reactive safety net (only kicks in once the count has already been stuck
under 20 for 2s) — the opening minute still read as sparse at a flat `TARGET_RATE` 2/s. Added a proactive
multiplier instead: `_start_boost_mult()` returns `START_BOOST_MULT` (3×, triple) from t=0; once the field
first passes `CATCHUP_TARGET` (50) alive, `_tick_start_boost()` starts a linear decay back to 1× over
`START_BOOST_DECAY_T` (60s) — passing through 2× (double) at the halfway point, per spec, before settling
on the plain `TARGET_RATE + AGONY_RATE_PER_RANK × rank` formula. Multiplies only the **normal** rate in
`_tick_spawn_loop()`, not `CATCHUP_RATE` (that path already has its own fixed, higher rate and is a
separate/orthogonal trigger — both can technically be active at once right at t=0, which is harmless: the
larger of the two effectively wins until enough enemies exist to clear the catch-up condition).

## Changelog — 2026-07-06 (Level_1_Minh: ramped-stream wave system + 2 new behaviors)

New 20-minute authored run `levels/arena/Level_1_Minh.json` (now the live run — `DEFAULT_LEVEL_FILE` repointed
from `1strun.json`). Built on a deliberately limited roster: **fly · bug · swarm · bee · Elephant**.

- **Two new `arena_enemy.gd` behaviors** (in the `_tick_behavior` `match`, reuse `_phase`/`_timer`/`_aim`):
  - `swarm_loop` — **boomerang** swarm (movement modeled on the Aliwa/boomerang weapon): CHARGE the player →
    fly out to `SWARM_LOOP_RANGE` (1320px ≈ 4× the boomerang `BOOM_SIZE` 330) → HOLD out past the range for
    `SWARM_LOOP_WAIT` (≥5s, drifting slowly outward) → BANK back with a capped graceful turn (`SWARM_LOOP_TURN`
    1.6 rad/s) → charge again. **Never distance-culls** (unlike `swarm` "zoom" which `queue_free()`s) — only
    dies on HP=0, so it grants XP/explosion.
  - `bee_dive` — dive-bomber: approach at `speed` to `BEE_STANDOFF` (400px) → hover `BEE_PAUSE` (1s) → dive at
    `BEE_DIVE_SPEED` (320) steering toward the player with a capped `BEE_TURN` (1.2 rad/s → "tracks a bit, not
    perfectly") → overshoot past `RETURN_DIST` → re-approach. Loops until killed.
- **Three `ENEMY_DEFS` variants** (`arena_wave_director.gd`): `bug_crawl` (chase, hp 200, **speed 120**),
  `swarm_loop` (blob 50), `bee_dive` (hp 1000, speed 150).
- **Wave-director stream extensions** (all optional, back-compatible — omitting them reproduces old behavior):
  - `"ramp"` on a `stream` entry = end/start rate ratio (e.g. `5.0` → final rate 5× the start). `_tick_streams`
    now uses a fractional-rate accumulator; start rate is solved so the linear ramp integrates to `count`.
  - `"formation": "ring"` + `"burst"` (default 8) on a `stream` → emits ring bursts instead of single trickle
    spawns.
  - `"angle"` (degrees) on any entry → fixed spawn heading instead of random (used for the opposite-direction
    swarm pairs at 16/18 min). Threaded through `_fire` → `_pattern_positions` / `_one_position`.
  - **Per-level `"max_alive"`** (top-level JSON field) → runtime `_max_alive` overrides the `MAX_ALIVE` const
    (Level_1_Minh uses 1200 so the 1000-fly / 1000-bug floods can crowd the field; over-cap spawns still drop).

> ⚠️ The **F7 Wave editor does not know** `ramp`/`formation`/`burst`/`angle`/`max_alive` and may strip them on
> save — `Level_1_Minh.json` is **hand-authored**; don't round-trip it through F7.

**Balance/tuning pass (same session):**
- **XP pacing** (`game_manager.gd`): `LEVEL_XP_MULT = {1:0.30, 2:0.40, 3:0.50, 4:0.70, 5:0.80, 6:0.90}` applied in
  `xp_to_next()` — early levels are cheaper; level 7+ unchanged.
- **Global enemy sizes** (`ENEMY_DEFS`, model + hitbox both scale with `size`): `fly` 9 → 7.2 (×0.8),
  `bug`/`bug_crawl` 11 → 15.4 (×1.4).
- **Level_1_Minh bug spawn rate ×3** at every time point (all `bug_crawl` stream counts tripled).
- **Aliwa (boomerang) + Gatling** (`arena_weapons.gd`): boomerang model +30% (`BOOM_DRAW` 19.5→25.35,
  `BOOM_BLADE` 45→58.5) with matching hitbox (`BOOM_HIT_RADIUS` 48→62.4) and 300%-faster self-spin
  (`BOOM_SPIN` 12.566→50.265); Gatling hit radius `GAT_HIT_RADIUS` 16→24 (+50%).

## Changelog — 2026-06-29 (Arena enemy roster + Fleet/Wave editors)

Large session reworking the Arena enemy layer and its dev editors:

- **enemiesHD migration:** `assets/enemies/` was deleted; all enemy art now lives in `assets/enemiesHD/`. Enemies with no HD sprite (old octopus, bomber, bug-eye) were dropped. `creep_layout.cfg` sprite paths were repointed to `enemiesHD` (fixes squid/dummy load errors). The Creep Edit roster now scans `enemiesHD`.

- **Expanded `ENEMY_DEFS` roster** (`arena_wave_director.gd`): existing stats updated per the design table + ~60 new enemies across "races" — alien (teleport), bismuth, magma, stone, ghost, pirate / piratespear(+shield), pros (+prosmotherblank), fleet (+leader), Sentinel Fleet (sentinel1-4 + leader), animalhornet, dummy, squid. All added to `QUICK_SPAWN_ORDER`.
  - **Level scaling:** a def flag marks HP/XP as per-player-level bases (multiplied by `GameManager.player_level` at spawn).
  - **Two new behaviors** (`arena_enemy.gd`): `teleport` (blink toward the player + idle jigger + space-warp distortion VFX) and `patrol` (straight flyby).

- **Per-def special mechanics** (`arena_enemy.gd`, all flag-driven): ghost transparency + evasion; pirate flee-when-low; stone → spawn its matching magma on death; alien5 → morph to alien4; magma → eject magma-fragment projectiles; bismuth anti-magnetic (reflects Gatling bullets back at the player + takes reduced damage from laser / lightning / vacuum); pros5 → fire orange Gauss orbs; fleet & Sentinel-Fleet "Strike Back" (patrol→chase the first time hit); new armor damage-reduction formula. `take_damage` gained an optional weapon-`kind` param (threaded from `arena_weapons.gd`). Fleet "backup summon" is deferred to the Fleet grouping.

- **Centipede rework:** the single spinning sprite became a 3-part head/body/tail chain that follows like the Viper snake but chases the player.

- **Plumes glued to the sprite** (`arena_enemy.gd`): plume emitters are re-anchored each frame to the live sprite transform (position + scale) so they track any enemy scaling. The Plume Style panel (`creep_edit_mode.gd`) gained Copy / Paste buttons.

- **Fleet Edit** (new — `scripts/ui/boss_edit/fleet_edit_mode.gd`, group `fleet_edit`, dev:on button below Hotkey): authors named FLEETS. Fleet / Unit / Random tables + Enemies palette + Transform + Save. A fleet has up to 10 unit slots (single enemy or a random pool shown as "R"), each with a per-slot screen position + size. Saves to `res://fleet_layout.cfg`. (Editor only; spawn wiring lives in the wave director.)

- **Wave Edit (F7)** (`arena_wave_editor.gd`): a dev:on `Wave_edit` button (below Fleet) toggles it. Column headers realigned (the Type control is now a fixed-width clip button instead of an OptionButton that stretched on long names). Clicking Type opens a 2-tab dropdown — **Unit** (5-column enemy icon grid) and **Fleet** (fleet list with a 500px hover formation preview). Picking a fleet stores the wave type as `fleet:<name>`; `arena_wave_director._deploy_fleet` then spawns the fleet's units at their placed positions (screen→world via the camera) when that wave fires.

- **HUD focus while editing** (`arena.gd set_edit_focus`): opening Creep Edit or Fleet Edit hides the entire gameplay HUD (HP/XP, weapon/aux slots, both button clusters, debug panels), the player ship and all live enemies — leaving only the editor panels + the objects being edited; restored on close. Weapon Edit is excluded (it needs the ship visible). Fleet Edit polish: in-slot-sized drag preview centred on the cursor, arrow-key nudge of the selected slots, Shift multi-select in the Unit table, Enemies panel nudged left.

> Verification was parse-check + headless arena boot (clean). UI interactions (drag-drop, context menus, hover previews) still need manual F5 confirmation. Per-slot fleet SIZE is not yet applied to spawned enemies (uses `ENEMY_DEFS` size).

## Boss Fight System (`scripts/gameplay/boss_fight.gd`)

### Structure: coordinator + standalone per-boss controllers

`boss_fight.gd` is a **coordinator**, not a base class. It is the only member of group `"boss_fight"`, the sole listener of `GameManager.boss_killed` / `boss_hp_changed`, and routes those signals **only to the active boss**. It owns three **standalone** boss controllers (each a self-contained `Control`):

| Controller | Boss | Notes |
|------------|------|-------|
| `scripts/gameplay/boss_elephant.gd` | Elephant | The 5-move spike/vortex engine detailed below; 75% projectile damage mult; rotation-invariant hitbox |
| `scripts/gameplay/boss_chromeleon.gd` | Chromeleon | 2-phase crystal; Phase-2 orb lasers via `lasgun_beam.gd`; emits `anim_finished` |
| `scripts/gameplay/boss_metalfly.gd` | Metalfly | 2-phase cocoon→fly, separate HP pools (P1 idle, P2 attacks) |

Per-boss API contract: `setup(oc)`, `spawn_boss()`, `kill_boss()`, `get_boss_hit_rect() -> Rect2`, `notify_boss_killed()` (+ optional `notify_hp_changed`, `flash_boss_hit`, `consume_projectile_near`). Shared `scripts/gameplay/boss_death_fx.gd` drives the death cutscene — `play(body_nodes, arena_rect, shake_node, is_final)` → emits `finished`; a one-time-use utility, not per-boss. `lasgun_beam.gd` is a standalone beam-FX helper (a copy of `weapon_system`'s Lasgun beam) used by Chromeleon's orbs.

### Elephant move engine — Architecture

The move/projectile docs below describe the **elephant** boss (the original generic engine). Other bosses have their own move sets in their controllers.

- **Root node:** `Control` (layer z=200, PROCESS_MODE_PAUSABLE)
- **Clip container:** `_clip_node` (Control, clipped to SpaceScreen bounds) — all projectiles rendered inside
- **Boss EO:** `_boss_eo` (EditableObjectNode from objects_container) — animated sprite with rotation pivot at center
- **Ship EO:** `_ship_eo` — for targeting, collision bounds
- **Fire points:** `_fp1_node`, `_fp2_node`, `_fp3_node` (Node2D children of boss) — auto-follow boss rotation + translation

### Phases and Cycle

```
enum Phase { IDLE, M1_ENTRY, M1_TRAVEL, M2, M3_ROT, M3_MOVE, M3_WARN, M3_FIRE,
             M4_ROT, M4_TRAVEL, M5_ROT, M5_MOVE, DONE }
```

**Move sequence:** Random pick after each move completes → `_begin_random_move()` picks one of 5 moves uniformly.

- **M1 (Spike Rain):** Spin + horizontal sweep + spiral spike bursts mỗi 0.2s. Duration ~8s.
- **M2 (Vortex Wander):** Random movement + vortex bursts từ fp1, fp2 mỗi 1.5s. Duration ~8s.
- **M3 (Laser):** Rotate 90° → align X → laser telegraph + fire. Total ~3.5s. Laser = one-shot 30 HP.
- **M4 (Shot Drop):** Tween entry (trái/phải) → rotate 90° → sweep ngang 120 px/s + drops từ fp3 mỗi 1s. End khi chạm screen edge. Drops = 20 HP.
- **M5 (Shoot Blob):** Rotate 90° → random wander y<450 trong 5s + blobs từ boss center mỗi 1s, homing. Blobs = 20 HP.

**Entry tween:** M1/M2/M3/M4 tween vị trí trong 1.0–1.5s, set `_phase = Phase.M1_ENTRY` để block boss tick (nhưng projectiles vẫn tick — critical fix).

### Move-Specific Details

**M1:** Spikes → balls (ball1–4.gif) random pick, resize 10%, no blink, 30 px/s, damage 10.
**M2:** Vortex từ fp1+fp2, GIF animated, rotate, 90 px/s, 15 HP.
**M3:** Laser từ fp3 (rotated), telegraph flash 0.08s cycle, damage 30 (one-shot).
**M4:** Drops từ fp3 (rotated), drop.gif animated + pre-resized 20% at load, 120 px/s down, 20 HP.
**M5:** Blobs từ boss center, blob.gif animated, 80 px/s homing (straight line, no pause), 20 HP.

### Projectile System

**Dict format (in `_projectiles` array):**
```gdscript
{
  "tr":        TextureRect,    # scene node in _clip_node local space
  "vel":       Vector2,        # px/sec in clip space
  "rot_spd":   float,          # rotation speed (0 = no spin)
  "rot":       float,          # accumulated rotation
  "dmg":       int,            # damage on hit
  "type":      String,         # "spike", "ball", "vortex", "drop", "blob"
  "frames":    Array[Texture2D],
  "delays":    Array[float],   # per-frame GIF delays
  "frame":     int,            # current frame
  "acc":       float,          # frame accumulator
  "blink_acc": float,          # for spike blink effect (sin wave, orange-red pulse)
}
```

**Collision:** Pixel-perfect — tight rect broad-check → per-pixel alpha sampling (2px step).

**Critical:** `_tick_projectiles(delta)` is called **before** `M1_ENTRY` early-return in `_process()`. If called after, projectiles freeze during boss tween. See `_process()` line ~284.

### Asset Loading

Animations loaded in `_load_assets()` via GifLoader:
- firevortex.gif (M2)
- laser.gif (M3)
- ball1–4.gif (M1, random pick each spawn)
- drop.gif (M4, pre-resized 20% at load → cached in `_drop_frames`, `_drop_size`)
- blob.gif (M5)

GifLoader extracts frames and delays metadata. Non-GIF textures fallback to single-frame array.

### Key Functions and State

| Function | Purpose |
|----------|---------|
| `spawn_boss()` | Initialize boss, set HP, emit signals, auto-activate manual boost |
| `start_fight()` | Set boss visible, call `_begin_random_move()` |
| `_begin_random_move()` | Reset rotation, random pick move 0–4 |
| `_begin_m1/2/3/4()` | Tween setup + phase to M1_ENTRY or real phase |
| `_begin_m5()` | No tween, phase straight to M5_ROT |
| `_tick_m1/2/3/4/5_*()` | Move-specific tick logic |
| `_spawn_spike/drop/blob()` | Create projectile dict, append to `_projectiles` |
| `_tick_projectiles(delta)` | Move, animate, collide, cull all in-flight projectiles |
| `kill_boss()` | Set HP=0, hide sprite, cleanup projectiles, emit signal |

### Boss Intro & Warning Flow

**Timeline (triggered by `boss_fight.gd → spawn_boss()`):**

```
t=0s   m.setup_arena()         ← bg/overlay swap per boss (called before boss_incoming)
t=0s   boss_incoming.emit()    ← warning.png flashes 5s, bossalert.wav plays, normal music fades
t=0s   normal music fades out  ← boss_music.gd connects to boss_incoming
t=5s   m.spawn_boss()          ← HP set, boss_spawned emitted, boss music starts
t=5s   _start_intro()          ← boss_intro_active=true, boss EO flies in from above (1s)
t=6s   _start_wander()         ← boss drifts around WANDER_CENTER=(620,158) OC for 5s
t=11s  _end_wander()           ← boss_intro_active=false, m.start_fight() → attacks begin
```

**`boss_warning.gd`** (`scripts/gameplay/boss_warning.gd`): listens to `boss_incoming`, flashes `warning.png` as CanvasLayer(layer=20) over screen with 5s duration / 0.75s interval / 0.2s fade. Positioned at SS_POS shifted 300px up.

**Per-boss contract additions (beyond basic API):**
- `setup_arena()` — swap scrolling bg + overlay to boss-specific assets. Called at `boss_incoming` time (before spawn delay).
- `spawn_boss()` — must make boss EO **visible** (so it's seen during fly-in + wander). Must NOT call `start_fight()`.
- `start_fight()` — called by coordinator after wander. Must call `_begin_random_move()` only (no visual setup; boss is already visible).

**`boss_intro_active` flag:** set `true` in `_start_intro()`, cleared in `_end_wander()`. Each boss `_process()` returns early when true — blocks all attack logic. Tween position updates still run (wander works).

**Ship movement during intro** (`gun_system.gd`): when `boss_intro_active` first becomes true, ship lerps from its **current position** to the designated center-bottom position over 1s. `_intro_from = _spaceship_origin` (not teleported from below screen).

**Wander constants** (`boss_fight.gd`):
```gdscript
const WANDER_CENTER   := Vector2(620.0, 158.0)  # OC coords = screen (350,150) + SS_OFFSET
const WANDER_RADIUS   := 50.0
const WANDER_STEP_T   := 1.2   # seconds per step
const WANDER_DURATION := 5.0
const WARNING_DELAY   := 5.0   # seconds of warning before boss spawns
```

### Gotchas

1. **M1_ENTRY early-return:** `_process()` checks `_phase == Phase.M1_ENTRY` and returns early (line ~283). **This must come AFTER `_tick_projectiles(delta)`** or projectiles freeze during tween.

2. **Fire point caching:** Fire points are Node2D children of boss → Godot auto-rotates + translates them. Fallback to `boss_center + offset` if child invalid.

3. **Drop/blob resize:** Drop frames are pre-resized at load (0.2×) into `_drop_frames` + `_drop_size` cache. Blob uses native size. Ball frames are resized at spawn (0.1×) because there are 4 variants.

4. **Blob homing:** Blob fires once at ship center direction, flies straight (no state machine pause/redirect). Simple linear projectile, like vortex.

5. **Collision damage:** Ships collide via `GameManager.ship_take_damage(dmg)`. One hit per projectile (removed after collision). Boss collision via `get_boss_hit_rect()` for external hitbox checks.

6. **Screen edge detection (M4):** Boss position clamped to OC_BOUNDS. M4 manually checks `position.x >= end.x - size.x` to trigger end.


## Arena System (`scenes/arena.tscn`)

> **RULE — Default target for enemy changes:** Khi thực hiện bất kỳ thay đổi nào liên quan đến enemy (behavior, shooting, FP, plume, stats...), mặc định ghi vào **`arena_enemy.gd`**. Chỉ ghi vào file lẻ (`enemy_bee.gd`, `enemy_sentinel.gd`, ...) khi user yêu cầu cụ thể non-arena behavior.

Arena is a **separate, self-contained scene** from `main.tscn` — a Vampire-Survivors-style top-down bullet-heaven mode. It does **not** use `enemy_manager.gd`, `gun_system.gd`, or the individual `enemy_*.gd` scripts. All arena combat logic lives in its own dedicated scripts.

### Key arena scripts

| Script | Role |
|--------|------|
| `scripts/gameplay/arena_enemy.gd` | Data-driven enemy behavior engine (all enemy types in one script) |
| `scripts/gameplay/arena_wave_director.gd` | Authored timeline spawner — fires enemies at scripted timestamps |
| `scripts/gameplay/arena_weapons.gd` | Player weapon system (Gatling etc.) specific to arena |
| `scripts/gameplay/arena_debug_spawn.gd` | Debug UI: fire rate +/− buttons, barrel count display, + Level button |
| `scripts/ui/hud/arena_levelup_ui.gd` | Level-up card UI (pause + pick 1-of-3 upgrade) |

**IMPORTANT:** Fixes to `enemy_dragonfly.gd`, `enemy_swarm.gd`, etc. do **NOT** affect the arena game. To fix arena enemy behavior, edit `arena_enemy.gd`.

### `arena_enemy.gd` — behavior system

Each enemy has a `behavior` string from `ENEMY_DEFS` in `arena_wave_director.gd`. Key behaviors:

| Behavior | Enemy | Notes |
|----------|-------|-------|
| `"orbit"` | dragonfly | **Known bug:** orbit center snaps to player each frame — player cannot escape. Not yet fixed. |
| `"spiral"` | diver | Fixed (2026-06): uses `SPIRAL_CENTER_SPEED = 80px/s` drift + aim-once straight dive when `_orbit_r <= 8` |
| `"swarm_dive"` | bee, swarm | Chase + dive |
| `"chase"` | bug | Direct pursuit |
| `"scatter"` | fly | Random wander |
| `"jump"` | octopus | Pause → aim-once → leap |
| `"jump_diag"` | spider | 45° diagonal jumps only |
| `"shooter"` | jet fighter | Ranged projectiles |
| `"boss_stub"` | elephant, chromeleon, metalfly | High-HP, slow, no real moveset yet |

**Spiral fix — two phases:**
```gdscript
# Phase 0: orbit center drifts toward player at SPIRAL_CENTER_SPEED px/s
_scatter_target = _scatter_target.move_toward(pp, SPIRAL_CENTER_SPEED * delta)
# Phase 1 (when _orbit_r <= 8): aim-once straight dive
_aim = dir  # captured once; player can now dodge
```

**Sprite sheet animation:** `_load_icon()` auto-detects `.sheet.png`, calls `_load_sheet_frames()` which reads the adjacent `.sheet.json` (cols, fw, fh, delays), slices `AtlasTexture` per frame into `_frames`/`_delays`.

### `arena_enemy.gd` — Dynamic Plume VFX (2026-06-20)

New vars after `_plumes` array:
```gdscript
var _plume_base: Array = []        # [{vel_min, vel_max, sc_min, sc_max, life}] per plume
var _plume_base_cols: Array = []   # [PackedColorArray] per plume
var _plume_red_cols: Array = []    # pre-built red gradient (dragonfly proximity)
var _plume_in_red: bool = false
```

Cached at the END of `_setup_plumes()` (after the for loop building `_plumes`). Helper functions:

| Function | Effect |
|----------|--------|
| `_apply_plume_vel_mult(m)` | Scale `initial_velocity_min/max` on all plumes |
| `_apply_plume_full_mult(m)` | Scale vel + `scale_amount_min/max` + `lifetime` on all plumes |
| `_apply_plume_color(want_red)` | Swap `color_ramp.colors` to red tone; guarded by `_plume_in_red` flag (only updates when state flips) |
| `_update_plumes()` | `match behavior` dispatcher — called in `_process()` just before the plume rotation sync block |

**Behavior → plume rule:**

| Behavior | Condition | Effect |
|----------|-----------|--------|
| `"swarm_dive"` | `_phase == 1` (diving) | vel × 2 |
| `"orbit"` | distance to player < 350px | color → red tone |
| `"jump"` | `_phase == 1` (airborne) | vel × 3, scale × 3, life × 3 |
| `"jump_diag"` | `_phase == 1` (airborne) | vel × 3, scale × 3, life × 3 |

**IMPORTANT — legacy enemy files (`enemy_bee.gd`, `enemy_dragonfly.gd`, `enemy_octopus.gd`, `enemy_spider.gd`):** These extend `enemy_base.gd` and are loaded by `enemy_manager.gd` which no active scene uses. All arena enemies are `arena_enemy.gd` (CharacterBody2D). The legacy files got plume helpers added too (for non-arena waves) but they do NOT affect the arena.

### `arena_wave_director.gd` — ENEMY_DEFS & boss icons

All enemy types defined in `ENEMY_DEFS`. Boss stubs now use real sprite sheet icons:
```gdscript
"elephant":  {..., "icon": "res://assets/bosses/elephant/elephant.sheet.png"},
"chromeleon":{..., "icon": "res://assets/bosses/chromeleon/chromeleon.sheet.png"},
"metalfly":  {..., "icon": "res://assets/bosses/metalfly/metalfly.sheet.png"},
```

### `arena_elephant.gd` — Arena Elephant Boss

**Separate from `boss_elephant.gd`** — the arena-mode elephant boss living in world space. All its move logic is self-contained in `scripts/gameplay/arena_elephant.gd`.

**Move set (5 moves, random rotation after each via `_begin_random_move()`):**

| ID | Name | Notes |
|----|------|-------|
| M1 | Spike Rain | Spin + sweep + spiral spike bursts every 0.2s |
| M2 | Ring of Fire | `FlameRingReveal` children — jet then ring draw |
| M3 | Laser | Telegraph + fire from fp2; tracks player then locks aim |
| M4 | Shot Drop | Entry tween → horizontal sweep + drops from fp3 |
| M5 | Shoot Blob | Homing blobs from boss center every 1s |

**M2 — Ring of Fire contact rules:** Damage only triggers where **visual fire exists**. The ring uses `FlameRingReveal._draw_progress` (0→1) and an angle-based arc check — player angle must fall within the drawn arc; full-circle contact is intentionally blocked.

**M3 aim-lock:** `const M3_AIM_LOCK_T := 0.5` — elephant tracks player during the 2s charge phase, locks aim only 0.5s before firing. Players have 0.5s to dodge after the aim freezes.

**Projectile persistence:** `_begin_random_move()` does NOT clear `_projectiles`. Bullets from previous moves remain alive until they expire normally — this is intentional.

**`_tick_projectiles(delta)` MUST be called before any phase early-return** in `_process()` so projectiles keep moving during entry tweens.

### `arena_enemy_manager.gd` — Hit Feedback System

`arena_enemy_manager.gd` owns the player-hit SFX + screen flash:
- **`_hit_player`** (`AudioStreamPlayer`, bus `"SFX"`) — plays `hit.wav` on every real HP hit
- **`_hit_flash_rect`** (`ColorRect` on `CanvasLayer` layer=95) — screen-blend shader: `COLOR.rgb = mix(screen.rgb, blended, 0.35)` using `render_mode blend_disabled` + `hint_screen_texture`
- **Flash duration:** `HIT_FLASH_DUR = 0.12s`; intensity ramps 35% → 0 over the duration
- Sized each `_process()` frame to match viewport size
- Connected via `GameManager.player_hit.connect(_play_hit)` — NOT called directly

### `arena_enemy.gd` — `_MissileVolley` inner class (2026-06-21)

Missile launcher behavior fires a fan-boomerang volley: darts fly outward (behind launcher), decelerate + hover (telegraph), then return homing to player.

**Class vars:**
```gdscript
var _launcher: Node = null   # the arena_enemy that spawned this volley
```
Set via `launch(muzzles, away, launcher)`. The launcher is **excluded** from dart–enemy collision checks (`en == _launcher` guard) to prevent self-hit.

**Self-hit bug (fixed 2026-06-21):** Launcher is in group `"arena_enemy"`. During the return phase, darts fly back toward the player and can pass through the launcher (which maintains standoff at ~460px). Without the guard, darts hitting launcher would be removed early, resulting in 2–3 darts visible instead of 4. Fix: pass `self` into `launch()`, skip it in the collision loop.

**Dart–enemy damage:** darts also deal `ML_LINE_DMG = 8` to other arena enemies on hit. Uses `en.get("_radius")` for hit radius; falls back to 16px. Calls `en.call("take_damage", float(ML_LINE_DMG), 0.0)`.

**Off-screen culling removed:** original had hardcoded `Vector2(1440, 780)` screen check (from shmup parent). This caused darts to be removed the instant they entered the return phase (having flown outside those bounds). Culling is lifetime-only now (`ML_LIFETIME = 6.0s`).

**Key constants:** `ML_FAN_ANGLE = 80°`, `ML_OUT_SPEED = 750px/s`, `ML_DRAG = 0.06` (exponential, ~6% remains after 1s), `ML_HOVER_END = 0.6s`, `ML_STAGGER = 0.12s/dart`, `ML_RETURN_START = 320px/s`, `ML_RETURN_MAX = 900px/s`, `ML_RETURN_ACCEL = 200px/s²`, `ML_ACCEL_RAMP = 1.5`.

**Spider jump randomization (2026-06-21):** `_jump_interval` var (range 0.5–1.5s, randomized via `randf_range`) re-randomized after each jump. Only affects `jump_diag` (spider); octopus still uses fixed 1.0s interval.

### `enemy_dragonfly.gd` — non-arena fix

Fixed with Option B (`DF_ORBIT_CENTER_SPEED = 80px/s` drift, aim-once dive). This file is used only by `enemy_manager.gd` (non-arena waves). The arena dragonfly ("orbit" behavior in `arena_enemy.gd`) still has the snap bug.

### Arena Ruin System

Breakable passive props that drift across the arena — not enemies (use group `"arena_ruin"`, not `"arena_enemy"`), so they do NOT count toward `MAX_ALIVE = 120` in `arena_wave_director.gd`.

| Script | Role |
|--------|------|
| `scripts/gameplay/arena_ruin.gd` | Ship (200 HP, 70px) → Box (50 HP, 40px) on death. Drifts 20–50 px/s, rotates 15 RPM. HP bar drawn un-rotated above sprite. Explosion + random gunboom on death. |
| `scripts/gameplay/arena_ruin_layer.gd` | Periodic spawner — one ship every 5–15s at 650–800px ring around player. |
| `scripts/gameplay/arena_loot.gd` | Loot dropped by a destroyed box: `coin`/`diamond` (+50 money), `heart` (+25 HP), `magnetic` (pull all XP orbs), `shield` (10s immunity + visual overlay). Plays `start.mp3` on collect. |
| `scripts/gameplay/arena_shield_visual.gd` | Breathe ±5% + blink in final 3s, auto-free after 10s. Uses `assets/defense/shield.png`. |
| `scripts/gameplay/arena_explosion.gd` | One-shot 7-frame explosion animation (`Gun-Impact50.sheet.png`). Spawned at death position, scaled to match visual size of the destroyed object. |

**Bullet hit detection for ruins:**
- `arena_weapons.gd` checks both `"arena_enemy"` and `"arena_ruin"` groups in `_tick_bullets()` and `_tick_orbs()`
- Ruin hit radius exposed as `hit_radius: float` property (ship ≈ 31.5px, box ≈ 18px) — NOT the shared `GAT_HIT_RADIUS = 16px`
- Explosions from `arena_enemy_manager.explode()` also damage ruins

**Shield immunity:** `GameManager._shield_immune: bool` + `_shield_timer: float`. Early return in `ship_take_damage()` before iframe check. Reset in `reset_run()`. `activate_shield(duration)` + `heal(amount)` are new methods added to `GameManager`.

**XP orb magnetic item behavior:**
- `arena_loot.gd` magnetic branch calls `orb.force_magnetize()` (NOT `collect()`)
- `force_magnetize()` sets `_force_magnet = true` + resets `_vel = Vector2.ZERO`
- Orb accelerates from 0 → 1200 px/s over 2s (600 px/s² linear ramp) via `_force_magnet` flag in `_process()`
- Normal magnetization (player walks near) still uses `MAGNET_SPEED = 120` starting speed + `MAGNET_ACCEL = 900`

**SFX:**
| Sound | Trigger |
|-------|---------|
| `assets/audio/sfx/bolt.wav` | Gatling bullet hits enemy or ruin (single shared AudioStreamPlayer, restarts per hit) |
| `assets/audio/sfx/gunboom1–5.wav` | Random boom when any enemy or ruin dies (fire-and-forget AudioStreamPlayer) |
| `assets/audio/sfx/start.mp3` | Collecting any loot item from a box |
| `assets/audio/sfx/equip.wav` | Player ship collects an XP orb |

**XP orb sizing:** `ORB_SIZE_PER_XP = 1.0` — orb radius (px) = XP value × 1.0. An 8 XP drop has 8px core radius. Scales are applied multiplicatively for glow/pulse rings. Set in `arena_xp_orb.gd`.

**HP bar on ruins:** same `draw_rect` pattern as `arena_enemy.gd` — drawn after `draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)` to stay horizontal despite the ruin rotating. Only shown when `hp < hp_max`.

## Enemy Panel (`scripts/ui/hud/enemy_panel.gd`)

6-tab panel (Animal / Human / Alien / Asteroid / Boss / Other). **GRID_COLS = 7** (7 thumbnails per row, wraps tự động).

**TAB_ENEMIES** — format `[display_label, spawn_key, icon_path, spawn_group]`:

| Tab | Enemies |
|-----|---------|
| Animal | Diver, Bombing wanderer, Swarm, Bee, Bug, Centipede, Dragonfly, Flies, Octopus, Spider |
| Human | Shooter, Beamer, Missile launcher, Royal, Royal Fighter, Royal Scout, Royal Tanker, Pirate Leader, Pirate Ork, Pirate Spear, Pirate SpearShield |
| Alien | Sentinels, Cruiser, Crystal, Egg, Fighter, Plate, Scout, Tree |
| Boss | Elephant, Chromeleon, Metalfly, Nautilus |
| Other | Dummy (`dummy.png`), Bomb |

Spawn keys **đã implement** trong `enemy_manager`: `spawn_bee/bug/centipede/dragonfly/flies/octopus/spider` (Animal group — xem Animal Enemy Group section).

Spawn keys **chưa implement**: `spawn_royal/royal_fighter/royal_scout/royal_tanker`, `spawn_pirate_leader/ork/spear/spear_shield`, `spawn_alien_cruiser/crystal/egg/fighter/plate/scout/tree`.

Image assets tại `assets/enemies/`: prefix `animal*`, `alien*`, `royal*`, `pirate*`, `dummy.png`.


## Normal Enemy System

### `enemy_base.gd` — base class

- **Size**: `_diameter_for_hp(hp_max) * size_mult` → square, sau đó nếu có texture thì height được kéo khớp ratio: `size.y = size.x * tex_h / tex_w`.
- **`size_mult: float = 1.0`** — set trong `_configure()` để scale size riêng per-enemy (vd: `bomb` = 0.5).
- **`icon_path: String = ""`** — set trong `_configure()`. Nếu != "" → load texture, override height theo ratio.
- **`_draw()`**: nếu có texture → `draw_texture_rect` + white flash overlay khi hit. Nếu không → placeholder shape (circle/triangle/diamond/square) + flash.
- HP bar vẫn hiển thị ở cả 2 trường hợp.
- **`_hp_mult: float = -1.0`** — per-enemy HP multiplier override. `-1` = dùng global `ENEMY_HP_MULT = 1.5`. Set `_hp_mult = 1.0` trong `_configure()` để bypass global mult (dùng cho Animal enemies với HP đã = effective HP từ PDF).

### Enemy assets (`assets/enemies/`)

| Enemy | File | shape_kind | size_mult |
|-------|------|-----------|-----------|
| Kingfisher | `kingfisher.png` | triangle | 1.0 |
| Jet Fighter | `jetfighter.png` | triangle | 1.0 |
| Sentinel | `sentinel.png` | diamond | 1.0 |
| Bombing Wanderer | `bombing.png` | square | 1.0 |
| Bomb | `bomb.png` | circle | **0.5** |
| Swarm | `swarm.png` | triangle | 1.0 |

### Animal Enemy Group — Architecture

7 enemies + 3 flock orchestrators, tất cả trong `scripts/gameplay/`.

**Solo enemies** (có `spawn(mgr)` tự chọn vị trí vào):

| Script | HP | XP | Contact DMG | Behaviour |
|--------|----|----|-------------|-----------|
| `enemy_centipede.gd` | 240 | 24 | 20 | Rotate 120°/s, tiến thẳng về player 100px/s, vào từ cạnh ngẫu nhiên |
| `enemy_dragonfly.gd` | 90 | 10 | 10 | ENTRY → SPIRAL (orbit thu hẹp 180→32px) → DIVE 160px/s |
| `enemy_octopus.gd` | 240 | 24 | 20 | WAIT 1s → JUMP aim-once smoothstep 600px/s range 200px |
| `enemy_spider.gd` | 60 | 8 | 8 | Như Octopus nhưng chỉ nhảy theo 4 góc 45° |

**Flock pairs** (orchestrator + member):

| Orchestrator | Member | Count | Behaviour |
|---|---|---|---|
| `enemy_bee_flock.gd` | `enemy_bee.gd` (HP 20) | 12 (4×3) | Form → Hold 0.4s → DIVE_ROW top-to-bottom, stagger 0.2s/member |
| `enemy_bug_flock.gd` | `enemy_bug.gd` (HP 15) | 16 (4×4) | Form → Hold → EXPAND sideways → DIVE |
| `enemy_flies_flock.gd` | `enemy_fly.gd` (HP 10) | 20 (ring 8+12) | Self-driven scatter, random target 1s interval |

**Flock spawn pattern** (cả 3 orchestrators dùng chung):
- Tính `_spawn_origin` = điểm ngẫu nhiên trên vòng tròn `radius = half_screen_diagonal + 100px` quanh `ship_center()`
- Queue toàn bộ members, release lần lượt với interval 0.08–0.12s (không overlap)
- State machine: `SPAWNING → FORMING → HOLD → DIVE_ROW → DONE`

**GDScript type inference gotcha trong enemy scripts**: `_mgr` typed là `Node` nên `_mgr.ship_center()` trả về `Variant`. Dùng `var x: Vector2 = _mgr.ship_center()` (explicit annotation), KHÔNG dùng `:=` (sẽ lỗi parse).

**Wave timeline**: `choreo_animal_wave.gd` — 4 phases × 30s = 2 phút:
- 0–30s: Flies + Bug (cap 80, rate 1.0s)
- 30–60s: Flies/Bug/Bee/Swarm/Spider + Diver event t=45s (cap 150, rate 0.8s)
- 60–90s: Bee/Swarm/Dragonfly/Spider/Octopus + BombingWanderer event t=75s (cap 250, rate 0.5s)
- 90–120s: full mix + Centipede (cap 400, rate 0.3s)

Registered trong `choreography_registry.gd` key `"Animal_wave"`. Level file: `levels/Level_Animal.json`.


