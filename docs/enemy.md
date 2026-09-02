# Enemy — Bosses, Arena & Normal Enemies

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on enemy behavior, bosses, waves, arena enemies, ruins, enemy panel.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

## Changelog — 2026-09-02 (k) — Nautilus: charge in the pool again, homing approach-charge, Move 5 hit fix

- **Move 1 is back in the random pool** — a normal telegraphed lunge (locked lane) when the player is inside
  `NB_FAR_R`. The FORCED approach-charge (player past `NB_FAR_R`, or interrupting a running move) is the
  same move but flagged `_nb_charge_homing`: its lane **re-aims toward the player at `NB_M1_HOME_RATE`
  (1.6 rad/s)** — slow enough to juke, so the player gets a dodge window ("có delay nhẹ so với di chuyển
  của người chơi"). The lunge version stays lane-locked and ends on overshoot; the homing one doesn't.
- **Move 5 beam dealt no damage.** The sweep turns ~11°/frame — far faster than the beam is thick — so the
  per-frame "player on the beam now?" test tunnelled past them every pass, and the `fmod(_nb_t, 0.4)` tick
  gate almost never coincided with a pass. Replaced with a **swept test** (`_ang_swept()` — did the beam's
  bearing cross the player's this frame, in range?) + a per-contact cooldown (`_nb_beam_hit_cd`, 0.35 s).
- **Charge now barrels THROUGH the player**, not up to them ("chưa chạm tới player đã dừng"). The dash ends
  when it has PASSED its closest approach by `NB_M1_PASS` (180 px), not at `NB_M1_ARRIVE_R`. The homing
  approach-charge also stops re-aiming once within `0.7 × ARRIVE_R` and commits to a straight pass, so the
  constant re-aim can't curl it into an orbit around the player.

## Changelog — 2026-09-02 (j) — Nautilus: Move 1 approach-only (SUPERSEDED by (k)), interrupt-to-charge, missile size

- Any frame the player gets past `NB_FAR_R` while a move (state 11-14) is running, `_tick_atlantic_boss`
  **interrupts it** (`_nb_finish_move()` teardown → `_nb_enter_move(0)`) and charges. (Kept.)
- **Charge has no fixed length.** The dash runs until `dist ≤ NB_M1_ARRIVE_R` (320), or (lunge only) it has
  overshot its closest approach by a body width, or `NB_M1_DASH_MAX_T` (4 s) as a backstop — was a hard
  1200 px. `NB_M1_DASH_LEN` is now just the aim-band's drawn length. `_nb_dash_left` → `_nb_dash_min`.
- **Missile draw size from Weapon Edit.** `_nb_spawn_missile` reads `weapon_layout.cfg [creeps] missile.size.x`
  (the TRANSFORM panel's W) into the def's `draw_w`; missile.png keeps its own aspect for the height.

## Changelog — 2026-09-02 (i) — Nautilus: continuous moves, forced-charge-when-far, 120 px/s tween

- **No rest beat.** `NB_RECOVER_T` and the state-20 wait are gone — `_tick_atlantic_boss`'s pick state runs
  the same frame a move ends, so moves are back-to-back ("Ko có thời gian nghỉ giữa các move").
- **Far → Move 1.** New `NB_FAR_R` (800 px): past it the next move is FORCED to Move 1 (charge) regardless
  of the random pick, so the boss dashes in to close the gap. `NB_APPROACH_R` removed.
- **`NB_TWEEN_SPEED` (120 px/s).** Moves that don't drive their own movement — M2 missiles, M3 arcs, M5
  sweep — now drift toward the player at this speed (was: M2/M3 stationary, M5 at `speed × 1.15` ≈ 60).
  `NB_M5_CHASE` removed.

## Changelog — 2026-09-02 (h) — Nautilus tuning

- HP stays 5000; `knockback_mult` stays **0.3**.
- **Move 5 sweep: zero knockback.** The sweep sets `_knockback_mult = 0.0` directly; `_nb_finish_move`
  restores it to `_nb_base_kb_mult` (captured from the def in `configure()`, = 0.3) — not to 1.0.
- **Move 1**: charge `NB_M1_CHARGE_T` 1.5 → **1.0 s**, dash `NB_M1_DASH_SPD` 600 → **800 px/s**.
- **Move 4 fade.** Split into phase 0 (screen up: emit + −50% dmg + regen + retreat, `NB_M4_T` = 5 s) and
  phase 1 (emitters stopped, buffs off, `NB_M4_FADE` = 5 s while the cloud thins). Puff `lifetime` = the
  fade window so it dissipates slowly instead of snapping off.

## Changelog — 2026-09-02 (g) — Nautilus: TP spray direction, Move 5 chase/trail, exposure, smokescreen

- **TP jets sprayed INWARD.** `_load_tp_fracs` only read the flat `dir_angle` (→ default `PI/2` "down"),
  ignoring the `dir_rot` 3-axis spray the sliders write. Now carries `dir_rot` (composed with `dir_rot_base`)
  and the plume glue projects it through the LIVE mount basis + pivot yaw — `view_basis(mount) ·
  view_basis(dir_rot) · +Z`, the exact chain Creep Edit's preview plume renders. New `_glb_dir_canvas()`
  + `_glb_body_basis_yaw()` (shared with `_glb_point_offset`), `dir3` particle meta.
- **Move 5** now chases at `NB_M5_CHASE` (1.15× speed) instead of `VB_CHASE_SPEED` (0.35× ≈ 18 px/s — "chưa
  có chase"). The beam trail (`fx/nb_beam_trail.gd`) got ADD blend, alpha 0.30→0.85, `TRAIL_T` 0.45→0.75 s,
  fade `1−age²` — reads as a real light wake now.
- **`light_scale` def key** (→ `GlbSpinBody.setup`) multiplies the shared rig's lights + ambient. Nautilus's
  baked albedo is self-lit and blew out at 1.0 → set to **0.55**. VIPER/Jaeger/Skull default 1.0, untouched.
- **Smokescreen** (Move 4): new `smoke_trail` style **`follow`** = every layer `local_coords` so the cloud
  rides the emitter and stays centred on the boss as it retreats ("khói xì ra chưa bao được hết nautilus khi
  nó chạy lùi"). Emitters are now a ring across the whole body + one dead centre (7, was 5 around FP4),
  bigger puffs, retreat slowed 0.9→0.65×.

## Changelog — 2026-09-02 (f) — Creep Edit saves weren't reaching the runtime + Move 1 leftover yaw

Two separate reasons an edited "Charge Position" angle looked like it was ignored:

- **`reload_layout_cfgs()` didn't clear the new cache.** `_creep_layout()` now reads through `_layout_cfgs`
  (keyed by path, so a def's `plume_layout` can point at `weapon_layout.cfg`), but the reload only reset the
  old `_creep_cfg`/`_creep_cfg_tried` pair. So after a Creep Edit save the runtime kept serving the
  **pre-save file for the rest of the session** — every live creep/plume edit silently did nothing until a
  restart. Now clears `_layout_cfgs` too.
- **Move 1's phase order was wrong.** It unwound the pose *during* the dash, so on screen it read as "tilts,
  snaps back to default, then lunges" — the authored pose was gone for the whole visible part of the move.
  Rebuilt to the order the user specified: **0 TURN IN → 1 CHARGE → 2 DASH → 3 TURN OUT**, with the pose
  held flat (`set_mount_rot(pitched)`, `set_yaw(0)`) through both 1 and 2, and the return to default only
  after the dash has landed.
- **Move 1's yaw: settled, then tracked.** The body's orientation is MOUNT × PIVOT-YAW, and the two now
  carry different halves: the "Charge Position" layer supplies the **tilt** (mount), while the **heading**
  keeps turning onto the player through the pivot yaw instead of being pinned ("Hướng xoay theo trục Z vẫn
  cần được xoay về hướng player thay vì fix cứng" — the editor's Rot Z and the pivot yaw are both pure spins
  about the world vertical, so the yaw is the right place for it). Phase 0 will not hand over until the
  mount lerp **and** that heading have both settled (`NB_M1_YAW_RATE`) — a half-turned yaw multiplying onto
  the mount was the original "vẫn bị xéo". Phase 1 tracks the player, phase 2 holds the **locked lane** so
  the lunge points where it is actually going.
  Caveat: `_glb_front_angle` is calibrated against the REST pose, so a charge pose with a very different
  X/Y tilt can aim a constant offset out — trim it with that layer's own Rot Z.

## Changelog — 2026-09-02 (e) — the plume fix was going into DEAD CODE

`arena_enemy._update_plume_xform()` **is never called** — it only appears in its own definition and in two
comments. The live plume glue is an inline block inside `_process()` (search "Glue plume emitters to the
sprite"), which re-derives `p.position` from the `base_pos` meta (the flat `(frac − 0.5) · _draw_size`)
rotated by `_facing`. So (c)/(d)'s 3D projection was patched into a function that runs nowhere, and the TPs
stayed on the flat path — "TP vẫn bị nằm ở đầu Nautilus".

- The glb branch now lives in the **inline block**, and runs **unconditionally every frame** for a glb creep
  (the `vrot`-changed gate is a 2D-sprite optimisation; a move can re-pitch the MOUNT without `_facing`
  moving at all, which would freeze the points mid-move). Sprite creeps keep the gated path untouched.
- `_update_plume_xform()` is reverted to its original body and marked **UNUSED** in its doc comment, so the
  next person edits the live one.

## Changelog — 2026-09-02 (d) — the `z` rescale in (c) was wrong + "Charge Position" pose layer

- **Point placement, corrected.** (c) below got the 3D path right but rescaled the authored `z` by
  `px / 32`, throwing every point ~6× off the body. There is **no rescale**: Creep Edit's
  `_build_plume3d_preview` places a marker at `(frac − 0.5) · part_px` with
  `part_px = maxf(eo.size.x, eo.size.y)` **and fits the model to that same number**, while
  `_setup_glb_spin_body` fits the live body to `maxf(size.x, size.y)` off the identical cfg entry — so
  editor units == runtime units and `z` passes through raw. (The 32 came from the rig's `target_px`, which
  only the X/Y/Z **spinbox readout** uses — a separate editor display quirk, not the placement path.)
  Verified numerically: editor and runtime now compute the identical model-local vector.
- **New Creep Edit layer "Charge Position"** (Atlantic map). Nautilus's Move 1 pitch used to be a hardcoded
  Euler that REPLACED the calibrated mount, so it came out crooked ("khi charge cũng bị xoay xéo"). It is
  now authored: same `Nautilus.glb`, its own `rot`/`rot_base` in `creep_layout.cfg`, dialled with the normal
  Rotate X/Y/Z sliders. Runtime reads it via `_creep_mount_rot(NB_CHARGE_LAYER)`; **falls back to the rest
  pose** (no pitch) until it's been saved once.
  It is a **CHILD LAYER of the Nautilus group**, not a separate palette creep — `_group_nautilus_layers()`
  parents it, the same shape `_group_metalfly_layers()` uses for the Cocoon. So it carries the **full**
  layer surface: Rotate X/Y/Z, its own FP + TP (own `[firepoints]`/`[thrustpoints]` rows keyed by the layer
  name) and its own FRONT arrow. The name itself is declared through `_extra_names()`/`_asset_path_for()`
  (no file of its own, same hooks Metalfly's bodies use) + `WIRED_3D_CREEPS`. Selecting either row renders
  BOTH models in the group overlay, so the rest pose and the charge pose can be compared side by side.

## Changelog — 2026-09-02 (c) — glb FP/TP were projected FLAT (points off the model) + Nautilus tuning

- **The real bug** (user: "TP của nautilus đang nằm sai vị trí so với khi hiện trong creep edit"). In Creep
  Edit a fire/thrust point's marker is a **child of the rotated model**, placed at
  `Vector3((frac.x−0.5)·target_px, z, (frac.y−0.5)·target_px)`, so it inherits the mount rotation and its
  authored height. At runtime `_muzzle()` / `_update_plume_xform()` used a flat `(frac−0.5)·_draw_size` —
  **dropping the mount rotation, the pivot yaw and the whole `z` axis**, so every point sat somewhere the
  editor never showed it. New **`_glb_point_offset(frac, z)`** runs the same 3D path: model-local → live
  mount basis (`GlbSpinBody.get_mount_basis()`, NEW) → pivot yaw → project (world X = screen X, world
  Z = screen Y). `_load_fp_fracs`/`_load_tp_fracs` now carry `z`; `GLB_EDIT_TARGET_PX` (32.0, Creep Edit's
  `_arena_display_px` fallback) rescales the authored height to the body's real on-screen size.
  Fixes The Skull's FP muzzles too, not just Nautilus's TP plumes.
- Move 1: the pitched pose is now explicitly **held for the whole charge** and only unwinds once the dash
  starts ("khi charge, nautilus vẫn giữ góc xoay").
- Move 5: lights **every TP** for the spin (like Move 1); new **`fx/nb_beam_trail.gd`** draws the faint
  fading wake behind the sweeping beam; `NB_M5_BEAM_DMG` 8 → **10**. `_nb_muzzle_spun` deleted — `_muzzle()`
  now applies the live yaw itself.
- `ENEMY_DEFS["Nautilus"]` contact damage 40 → **20**.

## Changelog — 2026-09-02 (b) — Nautilus: the 5-move set

`_tick_atlantic_boss` grew from the chase-only shell into a full state machine: 0 approach → 10-14 (one
move) → 20 recover (3 s plain chase) → a **random** next move (never the same one twice running).

- **Thrust points as state.** New def key **`tp_on`** = the TP ids lit at rest (Nautilus: `[6, 9]`; absent
  → all, i.e. every other creep is unchanged). `_plume_ids` runs parallel to `_plumes`, so
  `_set_plume_on(id, bool)` / `_set_all_plumes_on()` / `_reset_plumes_default()` can light one point.
- **`_setup_plumes` now keys a glb creep by `_type`** (it used to bail out entirely — the 2026-09-01 fix
  for magma1's plumes leaking onto The Skull). Both glb bosses now show their OWN authored TP jets.
- **New def keys `plume_from` / `plume_layout`** — borrow another entry's thrust points from another cfg.
  The Nautilus missile reads `missile`'s authored TP out of `weapon_layout.cfg` (missile.png is a Weapon
  Edit asset, not a creep). `_load_tp_fracs(cname, layout_path)` + `_layout_cfg(path)` generalise the read.
- **Move 1 — charge & dash.** All TPs lit + thruster wind-up; `fx/nb_aim_band.gd` draws a red highlight lane
  that re-aims at the player every frame; body pitches to the absolute editor angle `NB_M1_PITCH` (1°/0°/89°).
  After 1.5 s the lane is **locked** and the boss dashes it at 600 px/s for 1200 px, unwinding the pitch.
- **Move 2 — missiles.** 20 out of FP1/FP2 over 5 s (odd shots delayed `NB_M2_FP_OFFSET` so the tubes read
  as separate). New behavior **`nb_missile`**: coasts its launch heading 0.5 s, then curves onto the player
  at `NB_M2_TURN`. A real `arena_enemy` (HP 8, `frag`) → every player weapon can shoot it down.
- **Move 3 — arc waves.** `fx/nb_arc_wave.gd`: a 60° annulus front out of FP3 at 300 px/s, 15 dmg to the
  ship once, and a one-time outward `_knockback` shove to every creep the front crosses. ×3, 1 s apart.
- **Move 4 — smokescreen.** Retreats while 5 `SmokeTrail` puffs pour from FP4, drawn OVER the body
  (`z_index 6`). New `smoke_trail` style keys **`no_fire`** (drop the ember/flame/glow layers) and
  **`c_shadow`/`c_body`/`c_lit`** (override the shader's 3-tone palette → white-blue). Halves damage taken
  via new `_nb_dmg_taken_mult` (applied in `take_damage`) and regens 10 hp/s for 5 s.
- **Move 5 — spin beam.** `vb_charge_vfx.begin()` now takes an optional `{rim, core, ember}` palette (red
  defaults preserved) → blue charge. Then a 500 px blue `LaserBeamScript` off FP5 while the body spins
  10 revolutions at 0.5 s each, chasing the player. `_nb_muzzle_spun()` orbits the FP offset with the yaw
  (plain `_muzzle()` is yaw-agnostic — fine for a still boss, wrong for a spinning one).

## Changelog — 2026-09-02 — Nautilus (Atlantic 3D boss) wired

`assets/map/atlantic/enemies/Nautilus.glb` (2nd glb boss after The Skull). Full mirror of The Skull's
generic path — no bespoke code, the `boss_glb` def key does the work:

- **`ENEMY_DEFS["Nautilus"]`** (`arena_wave_director.gd`): `behavior:"boss_stub"`, `boss_move:"atlantic"`,
  `boss_glb` = the model, `sprite_alpha:0`, placeholder icon, hp/speed/etc. **placeholder** (match The
  Skull). Id `"Nautilus"` (capital) matches the `.glb` basename → the Creep-Edit creep name → the
  `creep_layout.cfg` key.
- **`_tick_atlantic_boss()`** (`arena_enemy.gd`): SHELL — chase the player + `_glb_boss_face_player()` to
  turn the 3D body toward them. No moveset yet (user authors points, then specs moves — The Skull flow).
- **Generalised the 3D-boss facing**: `_vb_face_body` → `_glb_boss_face_player` (shared), `VB_FRONT_ANGLE`
  → per-instance `_glb_front_angle` (def `"front_angle"`, default `GLB_FRONT_ANGLE_DEFAULT` = PI/2).
  `creep_edit_mode.gd`: `BOSS_FRONT_ANGLE`/`BOSS_CREEP_NAME` → `GLB_BOSS_FRONT_ANGLES` dict
  (`{"boss": PI/2, "Nautilus": PI/2}`); `_front_marker_angle()` reads it. Both front angles are **starting
  guesses** — calibrate the FRONT arrow by eye, then the def key + the dict entry must stay equal.
- **`WIRED_3D_CREEPS` += `"Nautilus"`** → Rotate X/Y/Z + FP/TP/SP/LED XYZ surface + FRONT arrow in Creep
  Edit (select the **Atlantic** map). Folder scan finds `Nautilus.glb` automatically; the two
  `Nautilus_Baked_*.png` siblings are correctly excluded.
- **`QUICK_BOSS_IDS` += `"Nautilus"`** → live 3D cell in the Dev → Creep panel's **Boss** tab.
- **`atlantic.json`**: added `{"is_boss": true, "time": 1200, "type": "Nautilus"}` — Atlantic now has a
  finale (was "để sau"). All 3 maps' final boss now at t=1200.
- ⚠️ Not verified in-arena — headless render of the 22 MB glb times out (same wall as The Skull). Model
  loads + fits clean (probe); wiring is identical to The Skull's working path. Needs a real playtest.

## Changelog — 2026-09-01 (h) — run length cut 30:00 → 20:00

Whole game shortened to 20 minutes. The final boss of each map now spawns at **t=1200** (was ~t=1800 or
never), and everything from minute 20 onward is gone.

- **Level timelines** (`levels/arena/`, the 4 live V2 files — `elecforest.json`, `vocalnic.json`,
  `atlantic.json`, `spawnmode2.json`): every `timeline` entry with `time >= 1200` removed; `hp_targets`
  with `time >= 1200` removed (only vocalnic had any — now ends at the t=1170 milestone).
- **Final boss @ t=1200** (solo `is_boss` entry, the `_final_boss_entry` the director holds until the field
  clears): **vocalnic → `boss`** (The Skull, was already at 1200), **elecforest → `metalfly`** (NEW —
  Electric had no timeline boss before). **atlantic + spawnmode2 have NO finale yet** (user: "để sau") —
  their run just runs out of spawns near t=1170/540 and relies on the temple landmark boss for a boss beat.
- **F7 Wave Editor** (`arena_wave_editor.gd`): `GRID_ROWS` 360 → 240 (grid is now 5s…1200s).
- **Temple landmark bosses** (`electric/atlantic/volcanic_temple_layer.gd`): `SPAWN_WINDOW` 1800 → 1200 —
  the 2 temples/run now roll their spawn time in [0, 1200).
- **Quests** (`quest_manager.gd`): `eq11` "The Long Dark" and `eq12` "Apex Predator" survive thresholds
  1800 → 1200, objective text "30:00" → "20:00".

## Changelog — 2026-09-01 (g) — The Skull Move 3: untargetable instead of fire-suppress

- Move 3 no longer disables player fire at all. User: "người chơi vẫn bắn được, chỉ là không bắn trúng
  vào boss được, do boss đã hạ xuống terrain rồi, vẫn bắn vào các enemy khác bình thường."
- `GameManager.player_fire_suppressed` **removed entirely** (declaration, ship-death reset, `reset_run`,
  the `arena_weapons`/`arena_loadout` gates — all gone).
- New `arena_enemy.is_untargetable()` → `_vb_grounded`. `arena_weapons._enemies()` (the shared per-frame
  cache every point/hitscan/AoE weapon + the spatial grid + `_nearest_enemy` read) now filters it out
  alongside `is_charmed`, so bullets pass over the grounded boss and still hit the ash behind it. Auto-fire
  keeps running (`_has_enemy_on_screen` short-circuits on `is_boss_alive`). `_check_contact()` also early-
  returns while `_vb_grounded` (ship flies over the flattened body — no contact damage / crowd push).
- The `_process` deadline safety valve + `_exit_tree` + `_vb_finish_move`/`_die` now just force-un-ground
  (restores targetability + body scale) instead of clearing a fire flag; a stun stuck mid-Move-3 would
  otherwise leave the boss permanently untargetable = unkillable.
- Death Beam / Predator beam "a boss blocks the beam" checks (which iterate the raw `boss` group, not
  `_enemies()`) also skip an `is_untargetable()` boss, so the beam passes cleanly over the grounded body
  instead of stopping short at an invisible wall.

## Changelog — 2026-09-02 — fleet "giật giật" was the CARRIER staggering, not knockback

Reverses the 2026-09-01 (f) fix below — that removed per-unit knockback from fleet escorts, but the real
cause of "cả fleet bị knockback giật giật" was elsewhere:

- **Fleet CARRIERS now ignore hit-stagger** (`stagger_ok` in `arena_enemy._process` — `or not
  _fleet_dock.is_empty()`, same exemption bosses have). Every escort is rigidly re-pinned to the carrier's
  position each frame, so a carrier stagger-stutter under rapid fire read as the whole formation juddering.
  The carrier now keeps gliding.
- **Fleet ESCORTS (`dock_kind:"fleet"`) take a real per-unit `_knockback` again** (reverted): only the shot
  unit strays, `_fleet_update_dock_positions` eases just that one back. `take_damage`'s guard is back to
  `(_docked and _dock_kind != "fleet") or not _fleet_dock.is_empty()` → `_hit_shake`; `_process`'s
  knockback-apply back to `(not _docked or _dock_kind == "fleet")`.
- Mothership escorts + carriers still get `_hit_shake` only (a real push would drag the exact-snap formation).

## Changelog — 2026-09-01 (f) — fleet formations: no per-unit knockback  [SUPERSEDED by 2026-09-02 above]

- User: "các fleet ash khi 1 con bị bắn thì cả fleet bị knockback". A `dock_kind:"fleet"` escort used to
  take a real positional `_knockback` on hit (the mothership path already didn't). `_fleet_update_dock_positions`
  re-pins escorts only at `speed × 1.3`, but `KNOCKBACK_SPEED` is 460 px/s — so under Gatling/Nuke fire
  enough escorts get shoved past the re-pin at once that the whole formation visibly smears backward.
  Fix (`arena_enemy.take_damage`): **any docked escort (mothership OR fleet) and any carrier now takes
  `_hit_shake` (visual-only, draw-transform, decays fast) instead of `_knockback`** — a formation moves as
  one block. `_process`'s knockback-apply is now plain `not _docked`. Affects every fleet, not just ash.
  Killing the carrier still breaks the squad into free chasers (each re-enables its own knockback then).

## Changelog — 2026-09-01 (e) — The Skull: Move 3 fire-latch bug, beam len/dmg

- **`player_fire_suppressed` could stick ON** (user: "có lúc player bị disable không bắn ra đạn"). Move 3
  latches this global flag while the boss is grounded; it was only cleared by `_vb_finish_move()` / `_die()`.
  Gaps: (a) run ends via BOSS ELIMINATED or End Run (not ship death) while grounded → node frees, flag
  carries into the **next run** → player can't fire all run; (b) boss stunned mid-Move-3 → `_tick_volcanic_boss`
  frozen, phase never completes → fire-locked until the stun ends. Fixes: `GameManager.reset_run()` now
  clears it; `arena_enemy._exit_tree()` clears it if freed while grounded; and a `_process` **safety valve**
  force-releases once `_t` passes `_vb_ground_deadline` (set at grounding = full move duration + 3 s margin;
  `_t` advances even while stunned).
- **Move 2 beams**: length `VB_M2_BEAM_LEN` 500 → **800 px**; damage `VB_M2_BEAM_DMG` 6 → **10, now PER beam**
  touching the ship (both beams on target = 20/tick) on the 0.4 s tick, and `_report_hit_player()` is now
  called before the beam's `ship_take_damage` (RUN OVER "last hit by" was missing for beam kills).

## Changelog — 2026-09-01 (d) — The Skull FRONT arrow + a real chase-facing sign bug

- **FRONT arrow in Creep Edit** (user: "hướng chỉ front giống như của jeager, nhưng dành cho The Skull") —
  `creep_edit_mode.gd`'s `_front_marker_angle()` now special-cases `"boss"` (it isn't an `MF_GLB`-style
  layer group, just one plain `WIRED_3D_CREEPS` entry) and returns `BOSS_FRONT_ANGLE` (`PI*0.5`, canvas
  DOWN — a starting value, same convention as `MF_FRONT_ANGLE`, not yet confirmed against The Skull's own
  mesh authoring). Select "boss" as the active creep in Creep Edit to see it — same cyan "FRONT" arrow
  Jeager/Metalfly get. Compare it to the model's actual face; if they don't line up, that's the one number
  to change (and re-check the fix below against it).
- **"boss bị confuse" / won't chase-face the player — TWO bugs in `_vb_face_body()`:**
  1. **Wrong yaw sign.** `yaw = _facing + PI/2` assumed `GlbSpinBody`'s pivot yaw ADDS to the model's
     on-screen angle, like a 2D `Sprite2D.rotation`. It doesn't — a Y-axis `Node3D` rotation under this
     top-down camera SUBTRACTS from canvas angle (a nose at canvas N, pivot-yawed by θ, projects to N − θ;
     verified with the rotation matrix + camera projection). `metalfly_rig.gd`'s `set_heading()` — the only
     OTHER live 3D body with this need — already codifies it right: `Basis(UP, PI*0.5 − heading) * mount`.
  2. **`_facing` has two writers that disagree.** `_tick_volcanic_boss` sets `_facing = dir.angle()` (raw
     heading); the generic post-move block in `_process` then overwrites it every moving frame with
     `intended.angle() + PI/2` ("sprite north"). Routing the body yaw through `_facing` meant it chased a
     moving average of two conventions → "confused".
  Fix: `_vb_face_body()` now reads the player position **directly** (`_player_pos() − global_position`) and
  sets `want = VB_FRONT_ANGLE − heading` (`VB_FRONT_ANGLE` renamed from `VB_FACE_YAW_OFFSET`, `PI*0.5`, must
  equal Creep Edit's `BOSS_FRONT_ANGLE`). Matches metalfly_rig's proven formula exactly.

## Changelog — 2026-09-01 (c) — The Skull polish: stray plumes, Move 2 beam/particles, Move 3 blast, Move 4 TP flare

- **The "5 light points" the user saw around the boss = magma1's thrust-point plumes leaking on.**
  `_setup_plumes` / `_setup_vortexes` / `_setup_leds` still keyed off the *placeholder icon* basename
  (`magma1`) for a glb creep — so the boss inherited magma1's 5 authored thrust jets (and would have
  inherited magma1's LEDs/vortexes if it had any). Same bug class already fixed in `_setup_fire_points` /
  `_setup_smoke_points`. Fix: all three now `return` early when `_glb_body != null` — a 3D creep gets its
  ambient VFX from **SP** (smoke points) only; its FP/TP are logic anchors, not persistent sprite jets.
- **Move 3** — removed the `_spawn_explosion` "landing blast" when the boss descends (user: "loại bỏ vfx
  nổ khi boss hạ xuống"). The body still darkens + shrinks via `_vb_set_body_grounded`.
- **Move 2** — beam `beam_thickness` 14 → 46, colors pushed to a near-white core + fuller red glow
  (`body_glow_width` 1.35, `body_point_boost` 2.2); hit-radius 30 → 34 to match. The charge VFX embers
  now carry a soft round-dot texture (`VbChargeVfx._round_dot()`) so they render circular, not square.
- **Move 4** — `_vb_tp_flare()`: every authored TP glows red for ~0.2 s (additive round-dot Sprite2D,
  tween 0.05 s up / 0.15 s down), fired once as the boss locks the face-up pose and again on **each of
  the 5 rain waves** (user: "mỗi đợt rải thì các TP sẽ rực sáng lên 0.2 giây"). Replaces the old
  one-shot FP flare. TP fractions cached into `_vb_tp_fracs` in `_setup_glb_spin_body`.

## Changelog — 2026-09-01 (b) — Volcanic 3D boss (`boss.glb`), the game's first 3D-model enemy + "SP" smoke-point markers

`assets/map/volcanic/enemies/boss.glb` — every other creep is a PNG sprite. Display name **"The Skull"**
(`ENEMY_DEFS["boss"]["name"]`; shown as the Boss-tab cell tooltip in `arena_debug_spawn.gd` — `"boss"` is
in `QUICK_BOSS_IDS`, so it renders as a live 3D cell there and quick-spawn passes the `is_boss` cap
bypass). New pieces:

- **`ENEMY_DEFS["boss"]`** (`arena_wave_director.gd`): `name:"The Skull"`, `behavior:"boss_stub"`, `boss_move:"volcanic"`,
  `hp:5000`, `sprite_alpha:0.0`, `body_px:150`, `icon` = a placeholder (`magma1.png`, hidden), `boss_glb`
  = the model. In `vocalnic.json` as the `is_boss:true` row at **t=1200 (20:00)** → the timeline's final
  boss (field clears → "BOSS ELIMINATED").
- **Generic 3D body** — `arena_enemy._setup_glb_spin_body()` builds `GlbSpinBody` on `boss_glb` (mirrors the
  Metalfly cocoon; `_creep_mount_rot("boss")` reads the Creep-Edit angle). NOT a posed rig — a top-down
  spinner. On success `_draw_size` snaps to `body_px` so every frac-of-rect marker (FP/TP/SP) lands on the
  visible model. Falls back to the flat icon if the glb won't load. **`BOSS_SPIN_RPM = 0`** — The Skull
  holds the Creep-Edit orientation exactly (`GlbSpinBody.setup` now skips the random start-yaw/tumble for
  an axis whose rpm is 0, so a non-spinner == `view_basis(mount_rot)` == the editor's top-down preview).
- **`boss_move == "volcanic"`** — `_tick_volcanic_boss()`: states 0 approach → 10-13 (one move, each with
  its own `_vb_phase` telegraph→active machine) → 20 recover (3 s, plain chase) → next. `_vb_enter_move` /
  `_vb_finish_move` bracket every move; `_vb_finish_move` also runs from `_die()` (drops beams / charge
  VFX, clears `player_fire_suppressed`, restores the mount angle). The 4 moves (2026-09-01, user spec):
  (1) **magmafrag cone** — 30 `_vb_spawn_frag` from FP1 in a 60° cone at the player;
  (2) **charge + beams** — 1.5 s `fx/vb_charge_vfx.gd` (red rings collapsing inward + inward embers), then
  two `LaserBeamScript` from FP2/FP3, red, 800 px, each sweeping 45° outside→inside onto the player
  (segment hit-test damages like `_beamer_tick`);
  (3) **ground slam** — `GameManager.player_fire_suppressed = true` (weapons stand down, ship still moves —
  one check each in `arena_weapons`/`arena_loadout`), body darkens+shrinks, 20 `ash1-4` over 5 s, rise;
  (4) **pitch + rain** — `_glb_body.set_mount_rot()` pitches to Rot X −74°, flare FP1/2/3, **holds the
  face-up pitch through all 5 rain waves** (20 magmafrag each, across `_vb_screen_rect()` top edge), then
  pitches back. `_vb_face_body()` / `GlbSpinBody.set_yaw()` turn the body flat to face the player while
  chasing (all states except Move 4); `VB_FACE_YAW_OFFSET` is the canvas-angle→yaw tunable.
- **`"frag"` def flag** — a `thrown_bomb` that just POPs on the hull (no `_mgr.explode` AoE), `contact`
  damage only, random `magmafrag (N).png` icon, honours an `"aim"` def key (fixed launch dir vs auto-aim).
- **FP / SP on a glb boss are keyed by `_type`** ("boss"), not the placeholder icon basename — see
  `_setup_fire_points` / `_setup_smoke_points`. New: `GlbSpinBody.set_mount_rot()` / `body_sprite()`;
  `_spawn_sibling` now returns the Node; `GameManager.player_fire_suppressed`.
- **SP — smoke points** (Creep Edit's 3rd marker type, after FP/TP): a thrust point tagged `"sp":true`.
  Placed & rotated with the identical 3D machinery as TP (Rotate X/Y/Z sliders, XYZ panel), but it
  previews / runs as the ash-wake `smoke_trail` VFX (`docs/vfx.md` → Creep Smoke Trail) instead of a fire
  plume, and saves to its own `[smokepoints]` cfg section. Runtime: `arena_enemy._setup_smoke_points()`
  spawns one world-space `SmokeTrail` per SP at its body-relative fraction, sprayed along `dir_rot.z`
  (`smoke_trail.gd` gained a `dir` style key). `"boss"` added to `creep_edit_mode.WIRED_3D_CREEPS`.
- **FP / LED on a glb creep** get the SAME height (`z` / PgUp-PgDn) + on-model placement as TP —
  `_pt3_target()` / `_pt3_apply_delta()` generalise the `_tp_xyz_*` machinery, `_make_pt3_marker()`
  renders a billboarded dot on the model, and `grid_overlay.glb_creep` suppresses the now-wrong flat 2D
  gizmos. `_tp_xyz_set` bakes the result into `pos`, so the 2D runtime readers need no change. `dir_rot`
  (spray rotation) stays TP/SP-only. Verify: `tools/screenshot_volcanic_boss.gd`.
- **On-screen size + hit radius** (user: "set 800 nhưng trên arena vẫn nhỏ"). `_setup_glb_spin_body()` now
  takes `px` from the Creep-Edit rect (`creep_layout.cfg [creeps] <type>.size`, the value the user drags),
  falling back to `body_px` → 150. `GlbSpinBody` caps the SubViewport RENDER at `RENDER_CAP = 560` px and
  scales the Sprite2D up to the requested size (`_base_scale` / `base_scale()`), so an 800 px boss doesn't
  allocate a ~1200² `UPDATE_ALWAYS` viewport re-rendering the 27 MB model every frame. `_radius = px *
  hit_frac` (new def key `hit_frac`, 0.33) so bullets + contact (`16 + _radius`) track the visible body,
  not the tiny `size:72` hitbox number. Move-3 grounded tween multiplies `base_scale()`.
- **`knockback_mult: 0.3`** in the def — The Skull takes 30% of a normal creep's pushback impulse
  (`arena_enemy.gd` `_knockback_mult`, was elite-only; a plain boss defaults to 1.0 without this).

## Changelog — 2026-09-01 — Volcanic: F7 said 5000 HP / 30s, live field showed 11.4k. THREE stacked bugs.

User playtest: t=24, 120 creeps, live "Total HP" **11.4k** — but the F7 wave editor's first 30s milestone is
only **5000**. Three independent causes, each inflating the field in a way the milestone target couldn't see:

1. **`"lvl": true` on the whole magma / stone / ash roster.** Runtime `hp_max = base × ENEMY_HP_TUNE(×2) ×
   GameManager.player_level`. Electric's core roster (`fly`/`bee`/`bug`/`swarm`/`spider`/`dragonfly`/`diver`)
   is **flat** — no `lvl` — so Volcanic got exponentially tankier as you level, Electric didn't. The flag
   isn't shown in the Creep Info panel, so the user (who'd tuned magma→60 / stone→50 / ash→80 there) couldn't
   see the ×level on top. **Fix: `"lvl"` removed from magma1-7, stone1-7, ash1-4, ashleader** → flat.
   (`centipede` keeps `lvl` — the one Electric creep that has it, unchanged.)

2. **The `ENEMY_HP_TUNE` ×2 was never folded into the HP-milestone maths.** `hp_targets` / F7's "Total HP"
   column were in bare-`hp` terms; the live "Total HP" readout sums post-×2 `hp_max`. So "5000" always meant
   "10000 on the field". **Fix: `WaveHpGen.effective_hp(id, defs)`** now returns `hp × blob × ENEMY_HP_TUNE`
   — a creep's real live `hp_max`. Wired into the composer pool (`_build_gen_pools`), F7's `_gen_unit_pool` +
   `_row_total_hp`, and `fleet_hp`. F7's column now matches the in-run readout 1:1; a `hp_targets` value = the
   HP you actually see. (Death-spawns are NOT counted — a stone's magma/frags are summed as their own live
   creeps when they appear, so a stone/magma window just ramps a bit above target as you fight it.)

3. **Low-count catch-up was flooding the field, ignoring `hp_targets` entirely.** When `alive` stays under
   `LOW_COUNT_THRESHOLD` (20) for 2s — which at run start it always does — catch-up dumps `CATCHUP_BURST` (50)
   then pumps `CATCHUP_RATE` (15/s) up to `CATCHUP_TARGET` (100), picking creeps with **no HP budget at all**.
   So the first ~10s hit 100 creeps regardless of the milestone. **Fix: `_tick_low_count_watch` now no-ops
   when `hp_targets` is non-empty** — the milestone composer is the population authority for that map; its
   waves ramp the field to each target on their own. Maps without `hp_targets` (Electric) keep catch-up.

**Verified** (booted Volcanic): catch-up never fires, milestone 0 composes to ~5000 live-field HP (5 of 6
random draws within ±5%; the 6th whiffs low — pre-existing `_pick_index` ~2% failure mode, made worse by
`metalfly_spawn` sitting in the gen pool — flag for later).

**Cadence (`cách rải creep theo từng tick`): no bug.** Both maps trickle through the same `_spread_entry()`
(count ÷ 5s ticks). The per-tick flood was purely #1+#2+#3.

**User's next step:** re-tune per-creep HP (Creep Info) + `hp_targets` in `vocalnic.json`, then re-run F7
"Generate Base on HP". The density is now milestone-driven (no catch-up backstop), so if 5000/30s feels thin,
raise the targets — the number is now exactly the field HP you'll see.

## Changelog — 2026-08-31 — `ash1`–`ash4` + `ashleader` (Volcanic "burning wreck" creeps); `fleet_unique` flag

New Volcanic creeps, all carrying the `"smoke_trail": true` VFX flag (see `docs/vfx.md` → Creep Smoke
Trail): `ash1`–`ash4` ordinary chase creeps, `ashleader` the squad flagship — bigger/tankier, `strike_back`,
plus two new flags:

- **`"fleet_unique": true`** — a fleet deployment fields **at most one** of this def, ever (user rule: "fleet
  có thể không có ashleader, hoặc có thì tối đa là 1"). Enforced by `_roll_slot_id(pool, fu_used)` in BOTH
  directors' `_deploy_fleet` + mothership paths: a slot that rolls an already-placed `fleet_unique` id falls
  back to a non-unique pool option, else the slot is dropped. `V.Ash.Wedge.9` / `V.Ash.Col.7` author exactly
  one `["ashleader"]` slot (it's the biggest sprite → becomes the carrier); `V.Ash.Rec.8` / `V.Ash.Mix.12`
  author none. The guard is belt-and-suspenders over the authoring.
- **`"no_auto": true`** on `ashleader` — `WaveHpGen.is_auto_excluded` → kept out of every AUTOMATIC pool (F7
  Gen, runtime milestone gen, low-pop reinforcement, Elite/Champion promotion) so a lone leader never spawns
  itself; still available via fleets, an authored timeline row, the F7 Unit picker, and dev Quick Spawn.

Four `V.Ash.*` fleets in `fleet_layout.cfg` (`V.` prefix → auto-scoped to Volcanic in F7's Fleet picker;
ash icons live in `assets/map/volcanic/enemies/` → the Unit picker + Gen pool pick them up with no wiring).
HP is placeholder — user tunes per-creep then re-runs F7 "Gen". Added to `arena_debug_spawn.gd`
`QUICK_SPAWN_ORDER` (Dev → Creep, Volcanic filter). Verified live: each fleet deploys with the right leader
count (0/0/1/1) and every ash creep gets its smoke VFX child.

## Changelog — 2026-08-25 (47th pass) — dummy really is blocked now; boss_stub can never be fielded as a creep

### "Trước đây tôi đã set rule là ko spawn dummy rồi? Vì sao giờ vẫn còn thấy trên arena?"

Because the 43rd pass only blocked the AUTOMATIC selection pools and deliberately let an **authored** row
through ("an explicitly authored timeline row still spawns itself"). That was the wrong call here:
`elecforest.json` authors **290 dummies across 6 rows** (t=270, 420, 1380, 1440, 1530, 1680), so on Electric
they kept arriving exactly as before. My note claiming it was handled was true only of the pools.

Fixed at the fire path: `_tl_fire()` now refuses any type whose def carries `no_auto`. Blocking it there
rather than in `_spawn_def()` deliberately keeps `arena_debug_spawn`'s Quick Spawn working — that is the
intended way to put a test dummy on the field.

Also closed a second hole found while auditing: `_timeline_earliest_type_pool()` (the reinforcement pool used
before the timeline's first entry fires) filtered `elite` but **never** boss_stub/gate_waves/no_auto, on both
its direct-type and fleet-member branches. Both now use `is_auto_excluded()`, matching
`_timeline_type_pool()`.

### "Metalfly là boss, không được spawn ra như creep"

`metalfly` is already `behavior: "boss_stub"`, so every automatic pool excluded it. The gap was an authored
row: `_tl_fire` passes `is_boss` straight from the entry, so a row that names a boss_stub type **without**
`is_boss: true` spawned it as an ordinary capped creep with none of a boss's handling.

`_spawn_def()` now promotes any boss_stub def to `is_boss = true` regardless of how it was requested. That is
the single funnel every spawn passes through, so "fielded as a creep" is simply not reachable any more.

**Verified** with a temp timeline authoring `dummy` ×40 (t=5) and `metalfly` ×3 **without** `is_boss` (t=10),
on the Electric map:
```
t= 6 | dummy=0 | metalfly as BOSS=0 as CREEP=0
t=12 | dummy=0 | metalfly as BOSS=3 as CREEP=0
```
Every dummy refused; every metalfly promoted to a real boss, none as a creep.

> The 290 dummy rows are still sitting in `elecforest.json` — now inert. Say the word and I'll strip them so
> the timeline reads honestly in F7; I left the level data alone rather than editing authored content unasked.

## Changelog — 2026-08-25 (46th pass) — Elite/Champion now drop a collectible weapon (3D if it has a model)

"Khi bắn chết elite / champion, tôi cần icon weapon drop ra trên màn hình (nếu trong inventory có glb thì drop
object glb xoay tròn, ko có thì fallback png). Khi ăn thì có notification ở góc dưới bên phải: '[tên vũ khí]
has been acquired. Press I to view'."

New **`scripts/gameplay/arena_item_drop.gd`** — a collectible keyed by an `InventoryManager` **def_id** (not a
weapon KIND like `arena_weapon_pickup.gd`, which arms the bespoke 5-slot arena loadout). It goes into the
**backpack**, which is what makes "Press I to view" the right call to action.

Art follows the request exactly, with a third safety rung:
1. `InventoryManager.get_glb(def_id)` returns a model → live SubViewport render spinning at `MODEL_RPM`
   (`arena_loot.gd`'s recipe: SubViewport + 2 DirectionalLight3D + ambient + Camera3D at `ISO_DEG`, model
   centred on its own AABB). Served through `item_3d_icon.warm_scene()`, so a heavy model comes from the
   shared warm cache instead of cold-loading mid-fight.
2. otherwise → the item's flat PNG icon, drawn aspect-correct (width fixed, height from the texture ratio).
3. neither → a rarity-coloured diamond, so a drop can never be invisible.

Both forms get a rarity-tinted pulsing glow halo and a bob, and collect at `COLLECT_RANGE` (fixed range — it
does not magnetise like an XP orb). On pickup: `add_to_backpack()` + `MetaManager.mark_run_temp()` (in-run
loot, purged next run — same lifecycle as the existing field drops), then the notice. A full backpack says so
instead of silently swallowing the drop.

`ArenaToast.show()` gained a `corner` argument; `"bottom_right"` is the new placement, clear of the
top-centre chrome and the bottom-centre HP/Shield/Level bars. Every existing caller keeps the default `"top"`.

**Additive, not a replacement**: Elite still drops its 50 coin and Champion still grants its guaranteed-new
weapon/aux pick — the drop is on top of both. Say the word if it should replace them instead. Champion rolls
from a higher rarity cap (`very_rare`) than Elite (`rare`), via the same `MetaManager.roll_boss_weapon()` the
mid-run field drops already use.

**One real bug caught during verification**: `ArenaToast` parents its CanvasLayer *and its fade tween* to the
host it is given, and the drop `queue_free()`s itself 0.25s into its pop — hosting the toast on `self` killed
the notice a quarter-second in, far short of its 3s life. It is hosted on the parent (the Arena) instead.

**Verified in a live arena, screenshotted:** the drop rendering as a spinning 3D model in its glow halo above
the ship, and the pickup notice reading `GATLING GUN HAS BEEN ACQUIRED. PRESS I TO VIEW` in the bottom-right.
Both art paths confirmed in the log (`mortar` → PNG, `gauss`/`homing_missile`/`z_sword` → 3D).

> Noted while testing, not changed: the first Elite actually appears at `START_DELAY + INTERVAL` (90+30 =
> 120s), and the first Champion at 150+60 = 210s — the accumulator only starts counting *after* the start
> delay, so both tiers arrive one full interval later than the constant names suggest.

## Changelog — 2026-08-25 (45th pass) — centipede wasn't tanky, most of its body simply could not be hit

"Nghiên cứu kĩ centipede xem có cái gì đó làm cho creep này nhân HP lên khác biệt hẳn với các con khác, có
thể do số node của nó chăng? Nó rất khỏe, bắn mãi ko chết."

The instinct was right that the segments are responsible — but **not through HP**. There is no node-count HP
multiplier anywhere: `hp_max = def.hp × lvl_mult × beacon × ENEMY_HP_TUNE`, and `centi_segments` never enters
it. Measured live, a `centipede` has **30 HP** (15 base × ×2 tune) — one of the *weakest* creeps on the roster,
with armor 7 (≈27% reduction). Nothing about its durability was unusual.

**The real cause was the collision broad phase.** `arena_weapons._rebuild_grid()` indexed every enemy by
`global_position` alone — which for a centipede is its **HEAD**. Its body trails ~330px behind, far past
`GRID_CELL` (128), so the enemy only ever became a hit candidate for projectiles near its head. Probed in a
live arena:

```
BEFORE  segs=10  head_to_tail=345px  head_cell=(2,-8) tail_cell=(5,-7)
        grid finds it at TAIL: false   |  segments UNHITTABLE by the grid: 9 of 10
AFTER   segs=10  head_to_tail=345px
        grid finds it at TAIL: true    |  segments UNHITTABLE by the grid: 0 of 10
```

So **7–9 of its 10 segments had no hit test run against them at all** — bullets flew straight through the
visible body. You were shooting a creep that mostly wasn't there to hit, which is exactly "bắn mãi ko chết".

The narrow phase was never at fault: callers already resolve `_hit_pos()` → `nearest_hit_point()`, which picks
the nearest segment correctly. The enemy just never reached them. That also explains why it read as tanky
mainly against projectile weapons — the Lasgun/Predator beams iterate `_enemies()` directly with no grid, so
those always could hit the body.

**Fix**: a multi-point body now registers in **every cell it occupies**. Only centipedes pay the extra cost —
`hit_points()` allocates, so it is called only for that behavior (the same guard `_beam_swept_hit_enemy()`
uses), and cells are de-duplicated since consecutive segments usually share one. Confirmed after the fix that
a centipede's HP actually drops under fire (30 → 13 over the probe window) instead of sitting at full.

Applies to every centipede-behavior creep: `centipede`, `atlantic_centipede`, `hammerhead`, `killerwhale`,
`shark_elite`, `spermwhale2`.

## Changelog — 2026-08-25 (44th pass) — the ranged ceiling is now ABSOLUTE (boss/elite/champion excepted)

"Luật trần 10 con này là cao nhất override các rule khác (trừ boss, ví dụ đang có 10 con bắn rồi, boss vẫn có
thể spawn được, boss bao gồm cả elite và champion)."

Audited **every** path an enemy can reach the field, rather than assuming the one fixed last pass was the
only one:

| path | status |
|---|---|
| `_spawn_def()` — ambient loop, timeline units, catch-up, **debug Quick Spawn** | already gated ✓ |
| `_deploy_fleet()` via `_drain_fleet_queue()` | gated, but had an escape hatch → **fixed** |
| `_spawn_sibling()` — stone→magma death-spawns, alien morphs | ungated → **closed** |
| boss / elite / champion | exempt **by design** ✓ |

**The escape hatch.** Last pass admitted an over-sized formation whole "when the field is clear of shooters,
better than a permanently stuck queue". `fleet_layout.cfg` has two formations that carry more ranged units
than the whole ceiling — `AT.Squid.Grid.15` (15) and `AT.StingrayElite.Row.11` (11) — so that hatch really
did breach the rule. It is gone. Such a formation now waits for the ceiling's full worth of room and then
deploys **thinned**: `_deploy_fleet()` takes a `shoot_budget` and skips ranged escorts past it (melee members
untouched). Safe to thin because escorts are built from the `roster` array handed to `init_fleet_dock()` — a
shorter roster is simply a smaller formation; orphaning only happens when a LIVE escort loses its carrier.

**`_spawn_sibling()`** builds an arena_enemy directly, bypassing `_spawn_def()`. No def death-spawns a ranged
creep today (every stone→magma target is behavior `"chase"`), so this is a no-op right now — new public
`can_spawn_shooter()` closes it so a future def can't silently reopen the hole the way `"sentinel"` did.

**Verified** — stress timeline: the 15-ranged squid grid ×6, 150 `shooter`, 80 `sentinel`, the 11-ranged
stingray fleet ×4, with Elite/Champion timers shrunk so both fire into a saturated field:
```
t= 3 | normal_shooters=10/10 OK | elite/champ_exempt=0 | total=10 | fleetq=0
t= 9 | normal_shooters=10/10 OK | elite/champ_exempt=0 | total=10 | fleetq=6
t=15 | normal_shooters= 9/10 OK | elite/champ_exempt=2 | total=11 | fleetq=6
t=18 | normal_shooters= 8/10 OK | elite/champ_exempt=3 | total=11 | fleetq=6
```
Normal ranged creeps never exceed 10; Elite/Champion spawn **on top** of a full ceiling, exactly as
specified (both are `def["elite"] = true`, which is the same flag the `not is_boss and not elite` guard in
`_spawn_def()` already honoured). Queued formations wait rather than being dropped.

## Changelog — 2026-08-25 (43rd pass) — the ranged classifier had drifted from the code; `dummy` excluded from every auto-spawn path

### "9 animalhornet và 16 sentinel (các sentinel này cũng bắn đạn), vậy là vi phạm rule rồi"

Correct — and the ceiling itself was working; the **classifier** feeding it was wrong.
`WaveHpGen.SHOOT_BEHAVIORS` was a hand-written list of 4 behaviors that had silently drifted from
`arena_enemy.gd`. An audit of every `case` in `_tick_behavior()` for `spawn_bullet` / `throw_bomb` /
`_beamer_tick` / the missile volley found **six** firing behaviors, not four:

| behavior | fires? | was classified? |
|---|---|---|
| shooter, beamer, bomber, missile | yes | yes |
| **sentinel** | yes — a 5-bullet fan at the player every 2s | **NO** |
| **steer_kiter** | yes — fires while kiting (spawn_mode_2's test_kiter) | **NO** |

`sentinel` is the one that produced the report: that id sits inside the **Kingdom1/Kingdom2 fleets**, so
`fleet_shoot_count()` returned **0** for those formations and `_drain_fleet_queue()`'s ranged ceiling waved
every Kingdom deployment straight through. Verified after the fix — the same fleets now report correctly:

```
[TMP-shootids] 11: animalhornet, atlantic_squid, beamer, missile, pros5, sentinel,
                   shark_elite, shooter, stingray_elite, test_charger, test_kiter   (was 9)
[TMP-pool] kingdom1_shooters=1  kingdom2_shooters=1                                 (was 0, 0)
```

Worth stating precisely: `sentinel1`–`sentinel4`/`sentinelleader` are behavior `"patrol"` and genuinely do
**not** fire — they only carry `strike_back` (turn and chase once hit) plus contact damage. Only the plain
`sentinel` id is ranged. A Kingdom1 deployment is 1 ranged + 8 melee.

The list now carries a note to re-run that audit whenever a behavior gains or loses a projectile.

### "dummy ko bao giờ được tự động Gen và spawn trên arena, vì đây là creep test"

New `WaveHpGen.is_auto_excluded(def)` — data-driven (`"no_auto": true` on the def) rather than an
`id == "dummy"` check copy-pasted across call sites, so any future test/target creep just gets the flag.
`invincible` counts as an implicit opt-out on its own: a creep that cannot be killed can never be cleared,
so auto-spawning one would wedge the field and the alive-cap forever — `dummy` carries both flags.

Wired into all four AUTOMATIC selection paths (it also subsumes the `boss_stub`/`gate_waves` checks each of
them already had): F7's "Gen" candidate pool, the runtime HP-milestone generator's pool, the low-population
reinforcement pool, and Elite/Champion promotion. Verified: `dummy_in_gen_pool=false`.

Deliberately still works: an explicitly authored timeline row, Fleet Edit membership, and
`arena_debug_spawn`'s Quick Spawn — those are the manual test paths and are the whole point of the creep.

## Changelog — 2026-08-25 (42nd pass) — Elite/Champion verified live; glowing tier ring (gold/red)

### "Cơ chế spawn elite/champion còn hoạt động không? Có drop weapon/aux mỗi khi bắn được elite/champion không?"

Verified live, not just read — shrunk `ELITE_CREEP_START_DELAY`/`CHAMPION_CREEP_START_DELAY` for one boot,
one-shot-killed the first of each the instant it spawned, and watched the actual reward call fire:
```
[TMP-tier] spawned base=pirate1 champion=false elite=true hp=140
[TMP-die]  ELITE died, type=pirate1 mgr_found=true will_spawn_coin=true
[TMP-tier] spawned base=piratespearshield champion=true elite=true hp=300
[TMP-die]  CHAMPION died, type=piratespearshield ui_found=true will_grant=true
```
Both tiers still spawn on their own timers (Elite every 30s from t=90, Champion every 60s from t=150, each
promoting the current wave's own weakest not-yet-promoted type) and both still pay out on death exactly as
designed: **Elite → flat 50 coin**, **Champion → guaranteed-new weapon/aux pick** (`grant_champion_reward()`,
falling back to a unique fragment if every run-slot is already full). Neither the 2026-08-24 HP-milestone
generator nor the fleet ranged-ceiling touched this path — `_spawn_tiered_creep()` calls `_spawn_def()`
directly with `def["elite"]=true`, which is the SAME flag that exempts it from the new shooter/alive-cap gate
(see the 41st-pass entry).

*(Process note: the diagnostic pass that confirmed this also caught and fixed a self-inflicted regression —
a cleanup script had accidentally deleted the actual `_spawn_def(...)` call itself while stripping a
temp-print line that shared the same line as real code. Elite/Champion would not have spawned at all with
that bug in place; the boot trace above is from AFTER the fix, and a second boot re-confirmed it.)*

### "Với các enemy elite, vẽ vòng tròn vàng phát sáng bao quanh nó. Champion thì vòng đỏ"

`arena_enemy.gd`'s `_draw()` now draws a pulsing glow ring around any `_is_elite` creep — **gold** for plain
Elite, **red** for Champion (checked in that order, same precedence the death-reward split already uses,
since every Champion also carries `_is_elite=true` for the cap-bypass). Sized off `_radius` + a fixed margin,
so it automatically scales with the creep's own already-upscaled size (2× for Elite, 3× for Champion) with no
separate lookup. Drawn first, under the body/tentacles, so the sprite reads clearly on top while the ring
still frames it.

Verified visually — forced both to spawn next to the player and screenshotted the live arena:

*(gold ring around the Elite, red ring around the Champion, clearly readable against a 122-enemy field)*

## Changelog — 2026-08-24 (41st pass) — the ranged ceiling had a fleet-shaped hole; raised to 10

"Hornet cũng là enemy shoot projectile, vì sao ở giây thứ 55, có tới hơn 70 animalhornet trên arena?"

Real, and the classifier was never the problem — `animalhornet` is `behavior: "bomber"`, which
`WaveHpGen.is_shoot_def()` counts as ranged. The hole was the exemption the 40th pass shipped one entry
above: **`_deploy_fleet()` builds its units directly and never went through `_spawn_def()`**, where the
ceiling lives. `elecforest.json`'s t=60 row is `fleet:A.Hornet.Diamon.5` **×20** — 5 hornets per deployment,
100 in total — and every one of them arrived through that exempt path. Spread across the 30→60s gap by the
39th pass's own fix, the arithmetic lands exactly on the report:

```
t=35  3 deploys → 15 hornets      t=50  12 deploys → 60 hornets
t=40  6 deploys → 30 hornets      t=55  16 deploys → 80 hornets
t=45  9 deploys → 45 hornets      t=60  20 deploys → 100 hornets
```

A level's ranged pressure is largely delivered BY formations, so exempting them made the rule close to
meaningless in practice.

**Fix:** fleets deploy through their own gate now. `_tl_fire()` pushes each deployment onto `_fleet_queue`
instead of deploying inline, and `_drain_fleet_queue()` (run every frame, and immediately after any fire)
admits formations oldest-first for as long as the ceiling has room for the *next* one. A formation is
admitted or deferred **whole** — a rigid dock can't be thinned mid-deploy without orphaning its escorts —
and the queue stops at the first one that doesn't fit rather than skipping past it, so the authored order
survives. Fleets with no ranged members never wait. A single formation carrying more shooters than the whole
ceiling is admitted once the field is clear of shooters, so it can't wedge the queue forever.

`SHOOT_MAX_ALIVE` **5 → 10** on request. The generator reads the same const for its per-wave total, so
composed waves scale with it automatically.

**Verified** — the same fleet row replayed on the default map, booted:
```
[TMP-hornet] t=5  alive=10 hornets=10 SHOOTERS=10 fleet_queue=3
[TMP-hornet] t=10 alive=14 hornets=10 SHOOTERS=10 fleet_queue=6
```
Pinned at exactly 10 with the surplus formations queued, against ~80 before.

## Changelog — 2026-08-24 (40th pass) — waves are now COMPOSED at runtime from HP milestones, and a hard 5-shooter ceiling

"Dựa trên các mốc total HP. Mỗi lần start game, luôn tự gen lại mỗi mốc 30 giây rồi rải đều ra các tick 5 giây."

### What was already there, and what wasn't

Both rules the request assumed existed, did — but only as **authoring-time** rules inside F7's "Generate Base
on HP" button, and one of them was a different number counting a different thing:

| rule | before | now |
|---|---|---|
| wave total ≈ target HP | `GEN_HP_TOLERANCE = 0.10`, F7 Gen button only | same ±10%, enforced at runtime every wave |
| ranged-creep limit | `SHOOT_TYPE_CAP = 10` **placed per id, per generated row** | ≤5 **alive at once**, enforced on every spawn |

And the milestones themselves did not exist as data anywhere: `target_hp` lived only in F7's in-memory row
dict and was **never written to the JSON**, so it was lost on every reload.

### Timing — the deadline is the PREVIOUS milestone, not the milestone

Gap-spread releases a milestone's units across the gap *behind* it (t=90's wave fires at 65/70/75/80/85/90),
so its composition must exist before **t=65**. The request estimated "generate at t=55 for t=90" — right idea;
`_tick_hp_gen()` anchors on the previous milestone instead (t=90's wave is composed at t=60), which is the
same deadline with no magic number and keeps working if the milestone grid isn't 30s.

### The pieces

- **`scripts/gameplay/wave_hp_gen.gd`** (new) — the composer, extracted so F7 and the director can't drift.
  Pure statics; callers pass their own candidate pools. Holds `is_shoot_def()` (the one definition of "fires
  projectiles"), the fleet HP/shooter-count helpers, and `generate()`.
- **`arena_wave_editor.gd`** — `_generate_row_hp()`/`_is_shoot_type()`/`_fleet_total_hp()` now delegate to it.
  `hp_targets` is written into the wave JSON on Save and restored on Load *and* on any row rebuild (which
  reads the live director, not the file — that path would otherwise blank every target field). New
  **"Targets = Actual"** button seeds every row's target from the HP its slots already hold, so a
  hand-authored timeline becomes a milestone curve in one press.
- **`arena_wave_director_v2.gd`** — `set_timeline(entries, targets)`; `_tick_hp_gen()` composes each milestone
  one milestone ahead; `_gen_compose()` spreads it with the same `_spread_entry()` the authored timeline uses
  (factored out of `_spread_gaps()`); generated entries ride their own `_gen_fire_queue` so the authored
  queue's ordering and final-boss logic are untouched. An authored entry at a timestamp that *has* a target is
  dropped — the target defines that row now, and firing both would double the wave.

### The 5-shooter ceiling

`SHOOT_MAX_ALIVE = 5`, checked in `_spawn_def()` — the funnel every ordinary spawn passes through — exactly
the way `MISSILE_MAX_ALIVE` already worked: the spawn is **refused**, the item stays in `_spawn_queue`, and
the next drain pick tries something else. So the field keeps filling at full rate with melee creeps and the
held-back shooter arrives when one of the five dies. `_drain_spawn_queue()` now skips queued shooters without
burning its retry budget while the ceiling is closed, so a large backlog of them can't starve the melee
creeps sharing that queue. Exempt: bosses/elites, and Fleet Edit formations (`_deploy_fleet()` builds units
directly — thinning a rigid dock mid-deploy would orphan its escorts); the generator budgets a fleet's own
ranged units against the same number so composed waves don't lean on that exemption.

### Verified

- **Composer** (`tools/check_wave_hp_gen.gd`, 400 random targets against a realistic roster): 389/400 within
  ±10%, **0 ceiling violations** across four scenarios including a fleet-only pool and a ranged-only pool.
  The uniform-random pick was replaced with a bounded best-of-6 draw (`_pick_index`) after the first run
  showed ~8% of waves missing by up to 71% (285% on fleet-only) simply because the draw came up all-cheap or
  all-expensive; that is now 61% / 28% worst-case. The residual misses are targets physically unreachable
  from the drawn pool inside 10 slots at `PER_SLOT_MAX` each.
- **Runtime** (booted arena, milestones at 10s + an authored 240-shooter flood): milestones composed one
  ahead (t=20's wave built at t=10) landing +0.0% / +0.5% / −1.0% of target, spread evenly across the 5s
  ticks (88/89/89/89/91/91 units), and `shooters_alive` pinned at exactly **5** the whole run while total
  alive still climbed to the 120 cap.

### Note

Nothing changes until a wave file has `hp_targets` — `spawnmode2.json` has none yet, so it plays exactly as
before. Press **"Targets = Actual"** in F7 (or type a curve into the Total HP column) to switch it on. Its
current curve is worth reviewing first: it runs 8.1k → 25k → 39k, then 100 at t=150, 356k at t=180 and 0 at
t=360.

## Changelog — 2026-08-24 (39th pass) — gap-spread only ever spread the FIRST unit of each authored wave row

"Có cảm giác các wave creep đang bị drop theo từng tick 30 giây (như wave editor) chứ ko được rải đều theo
từng tick 5 giây (như cơ chế rải creep đã nói trước đây)."

Correct, and it was `_spread_gaps()` in `arena_wave_director_v2.gd`. The function walked `sorted` entry by
entry and did `prev_t = t` after **each** one. But one authored F7 row is several entries (one per Unit slot)
all stamped with the SAME `time` — so only a row's first unit ever measured a real gap. Units 2..N saw
`gap = 0`, fell straight through the `gap <= GRID_SPREAD_STEP` early-out, and dumped their whole count in one
instant burst at the row's timestamp.

`spawnmode2.json` is a 30s grid of 4–10 entries per row, so in practice ~99% of every wave arrived as a
single 30-second drop. Units released per 5s bucket, first 200s (recomputed from the actual timeline):

```
BEFORE  5s=33 10s=33 15s=33 20s=33 25s=34 30s=240 35s=33 … 60s=289 … 90s=305 … 120s=1256 … 180s=1409
AFTER   5s=66 10s=67 15s=67 20s=67 25s=69 30s=70  35s=74 … 60s=78  … 90s=94  … 120s=213  … 180s=1077
```

**Fix:** the loop now takes the whole GROUP of entries sharing a timestamp before advancing `prev_t`, so every
entry in a row spreads across the same gap — the one back to the previous *distinct* timestamp. Interleaving
several entries' sub-ticks leaves the queue out of order (row A's 5s…10s…, then row B's 5s…) and `_tl_tick()`
walks it strictly sequentially, so `_spread_gaps()` now re-sorts by time before returning; ties may land in
any order, which the callers already tolerate (see `set_timeline()`'s final-boss scan).

The 180s bucket stays large on purpose — those are `"stream"` entries, deliberately exempt from gap-spread
because they already carry their own ramp/duration.

Verified in a booted arena: the real `_tl_fire_queue` expanded from 443 to 2956 entries and every bucket
under 200s landed in the 66–213 range instead of spiking to 1256.

## Changelog — 2026-08-24 — Total HP on the live creep readout (top-right)

"Thêm dòng total HP vào bảng thông tin về creep… để tôi theo dõi xem người chơi có đang bị quá ngộp thở với
lượng creep lớn ko."

`perf_overlay.gd`'s enemy breakdown (the green type/count list under the FPS readout) gained a
`Total HP <current> / <max>` line between the header and the per-type rows, short-formatted (`12.3k`,
`2.40M`) so the right-aligned 350px column still fits. Summed in the pass that already walks the
`arena_enemy` group for the counts — two extra property reads per creep, at the same throttled 5 Hz — and
read via `.get()` so a group member without `hp`/`hp_max` is skipped rather than erroring. A head-count alone
can't tell 300 flies from 12 fleet carriers; this is the number that says whether the field is actually
oppressive.

## Changelog — 2026-08-15 (38th pass) — Shift-click range-select for TP/Vortex/LED; LED points now arrow-key movable

Two requests: (1) holding Shift and clicking 2 points should select everything IN BETWEEN too (standard
file-explorer/IDE range-select), not just toggle those 2 individually; (2) LED points should move with the
arrow keys like TP already does.

1. **Range-select**: `_select_tp_add()`/`_select_vortex_add()`/`_select_led_add()` (Shift-click handlers) used
   to toggle only the ONE clicked index in/out of the multi-selection. Now select the full contiguous range
   between a fixed anchor and the clicked index, inclusive — the anchor is set by every plain (non-Shift)
   click (`_select_tp()`/`_select_vortex()`/`_select_led()`) and stays put across a run of Shift-clicks, so
   repeated Shift-clicks keep re-extending/shrinking the SAME range instead of drifting from wherever the
   last Shift-click landed (new `_tp_range_anchor`/`_vortex_range_anchor`/`_led_range_anchor`). FP and Tentacle
   Points are unaffected — they only ever had a single-index selection, no multi-select to range over.
2. **LED arrow-key move**: `_input()`'s arrow-key handler gained a `_selected_led_indices` branch (mirroring
   the existing Vortex one exactly) — moves every selected LED's `pos` by the arrow direction (×10 with Shift
   held), same as FP/TP/TenP/Vortex already do.

Verified via `godot --headless --check-only` (clean).

## Changelog — 2026-08-15 (37th pass) — "Apply Wave" button: mistake-proof way to stagger Phase across a row of LEDs

User: set a batch of LEDs with Phase 5° apart, but they still all blinked in sync in Creep Edit. Re-checked the
whole Phase pipeline (`_on_led_changed()` write, `_get_led_style()` per-`led_id` dict, `_refresh_led_preview()`
read, `led_light.gd`'s `_blink_factor()` sine math) end to end — all correct in isolation. The real trap is the
WORKFLOW: setting Phase one LED at a time means re-selecting a row each time, and if more than one LED is
selected at once (multi-select, e.g. an accidental shift-click carried over), every field — Phase included —
applies the SAME value to ALL currently-selected LEDs simultaneously (by design, identical to how Vortex's own
multi-select-apply already works) — so "select a few, drag Phase" can only ever make them identical, never
staggered, reading as "still all in sync" exactly as reported. Also: 5° is a small step — spread across only a
few LEDs at a typical Blink Hz, the resulting time offset can be near-imperceptible even done correctly.

Rather than a fix for a bug that isn't really there, added a workflow that can't hit the trap: a new **Wave
step (°) + "Apply Wave"** control in the LED panel — one click assigns `phase_deg = index × step` to EVERY LED
of the active creep in placement order, completely independent of the current selection. Directly delivers "1
dải sóng tín hiệu chạy từ đầu về đuôi" without any per-LED manual selection at all.

Verified via `godot --headless --check-only` (clean — caught and fixed a real variable-name collision,
`ledw_lbl`, along the way; already used by the W/H row above).

## Changelog — 2026-08-15 (36th pass) — LEDs on auto-generated (duplicate) body segments still collapsed onto one of the 3 real parts

User: "tôi đặt nhiều segment body nhưng led chỉ tách thành 2 phần" — placed several LEDs along a body raised
to many Segments, but they only ever split into ~2 groups instead of one per segment.

Root cause: the 35th-pass fix only matched a LED against the **3 REAL named boxes** (Head/Body-template/Tail —
the only ones with an actual entry in `creep_layout.cfg`). Every AUTO-GENERATED duplicate segment (whenever
Segments > the template count) has no box of its own on disk, so any LED placed near one just collapsed onto
whichever of the 3 real boxes happened to be nearest — at most 3 possible groups, matching "only ~2" for a
typical Head+Body+Tail set where none matched Head.

Fix (`_setup_leds_centipede()`): now builds a full VIRTUAL center+size for **every** slot k=0..n-1 — not just
the 3 real ones — by walking the exact same `_centi_joint_spacing()` / `_centi_seg_size_for()` /
`_centi_seg_scale()` formulas the live chain itself uses (the identical cumulative-distance construction
`_update_centipede_chain()`'s own straight-line init already does, just scalar/OC-space here). Verified with
real "cent" numbers (8 segments, Spacing 0.65, Taper 3%) — the 8 slots come out properly spread and shrinking
(y from 422 to 723, size 84.9 down to 30.0), not collapsed. A LED now matches its nearest slot among ALL of
them, so it correctly lands on the specific duplicate segment it was actually placed near, and
`_update_led_xform_centipede()` (unchanged from the 35th pass) glues it to that exact slot's live position
every frame.

Verified via `godot --headless --check-only` (clean) plus the numeric slot-spread check above. Ask the user to
re-spawn "cent" with several LEDs spread across a high-Segments body and confirm each now rides its own
distinct segment instead of collapsing into 2-3 clumps.

## Changelog — 2026-08-15 (35th pass) — LEDs on a centipede (cent/hammerhead/…) now ride their own body segment; added Phase (wave stagger) + Rotate to the LED panel

Three-part request: (1) bug — LEDs placed on "cent" stayed lined up in one rigid straight column instead of
following the body's live bend as it moves; (2) a per-LED time offset so a row of LEDs reads as a wave/chase
signal running head→tail; (3) a Rotate control per LED.

**Bug root cause**: `_setup_leds()` anchors every LED against ONE rigid box — `_icon`'s own `creeps` entry,
which for a centipede-behavior creep is always the HEAD's box (`_icon` = the head icon). A LED actually placed
near Body or Tail in Creep Edit got its `frac` computed against the tiny HEAD box instead, producing one large,
FIXED local offset that only ever rotated rigidly with the head's own `_spin` — never independently following
the body chain's own live bend. Reads exactly as "stays lined up in a straight column" (which is literally what
a fixed offset from a single rotating point looks like), confirmed against the user's own actual saved LED data
(nearest-nesting check: LEDs stored under the "cent head" key at y≈469/492 sit far closer to "cent body"'s own
box center than head's or tail's — correctly re-matched to Body by the fix below).

**Fix** (`arena_enemy.gd`): centipede-behavior creeps now route through a new dedicated path instead of the
generic single-box one:
- `_setup_leds_centipede()` — matches each LED to whichever REAL template box (Head / each distinct Body icon /
  Tail — by nearest box-CENTER, not literal containment, so it doesn't matter which key they were stored under)
  it actually sits closest to, and remembers that as a chain slot `k` (Tail stored as `k=-1`, resolved live to
  `n-1` every frame since Segments could in principle change after spawn).
- `_update_led_xform_centipede()` — every frame, glues the LED to THAT segment's own LIVE `_centi_pts[k]`
  position and own angle. New shared helper `_centi_seg_ang(k)` (factored out of `_draw_centipede()`'s inline
  per-k angle formula, now used by BOTH — one source of truth, not a second copy that can drift like the
  neck-shift saga earlier this session) supplies the exact same angle the segment's own sprite draws at, so a
  LED on Body/Tail now turns and follows precisely as the chain bends.
- Regular (non-chain) enemies are untouched — `_setup_leds()`'s original single-box path still handles them.

**Phase** (0-360°, per-LED, new `phase_deg` style field) — shifts that LED's own blink sine cycle
(`led_light.gd`'s `_blink_factor()`: `sin(TAU·blink_hz·t − phase_deg)`). Set increasing Phase across a row of
LEDs (Led1=0°, Led2=+some step, …) to make them blink in sequence — a running "wave" signal strip head→tail,
per request. No automatic order-based default — it's a plain per-point control like every other LED property,
consistent with how W/H/Color/Intensity/Blink already work.

**Rotate** (0-360°, per-LED, new `rotate_deg` style field) — an extra rotation added ON TOP of whatever the
anchor already applies (segment angle for centipede, overall body `_facing` for regular enemies; a bare
user-only value in Creep Edit's own static preview, which has no body/segment to auto-orient to). Mainly
useful once W≠H (an elongated light) — a pure circle doesn't visibly change under rotation.

Both new fields added end-to-end: `_default_led_style()`, the LED panel UI (new Phase/Rotate spin row), 
`_refresh_led_editor()`/`_on_led_changed()`/`_copy_led_style()`/`_paste_led_style()`, `_refresh_led_preview()`
(editor), and both `_setup_leds()` paths + `_update_led_xform()` (arena).

Verified via `godot --headless --check-only` (clean). Ask the user to re-spawn "cent" (or any chain creep with
LEDs) and confirm the LEDs now bend/turn with their own body segment instead of staying in a rigid column, then
try staggering Phase across a few LEDs to check the wave effect, and Rotate on a non-square (W≠H) LED.

## Changelog — 2026-08-15 (34th pass) — New "Add Led" point type; FP/TP/Vortex/Led panels now dynamic (hidden until the creep has one)

Two-part request: (1) a new "Add Led" point type (W/H, color, intensity, 0-60Hz blink slider), same group as
Add FP/TP/Vortex; (2) the properties panel below LAYERS becomes dynamic — a section only shows once the active
creep actually has at least one point of that type.

**New LED point type** — mirrors the existing Vortex Points system exactly (a directionless point + a separate
per-point style dict), swapping vortex's radius/spin/arms/colors for LED's own fields:
- New `scripts/gameplay/fx/led_light.gd` (`LedLight`, no `class_name` — same reasoning as `EnergyVortex`/
  ZSlash) — additive-blend glow, a procedurally generated radial-falloff dot (same technique
  `_make_preview_plume()` already uses) stretched to W×H. `blink_hz` (0-60, "0 = không nhấp nháy, 60 = nháy
  60Hz") drives a smooth sine brightness pulse between a dim floor and full intensity — reads as a flicker,
  never a jarring hard on/off strobe, well-defined at every Hz including 60.
- `creep_edit_mode.gd`: `_add_led_btn` in the same `mode_row` as FP/TP/TenP/Vortex, full mutual-exclusion
  wiring (activating any one cancels the other four, matches the existing FP/TP/TenP/Vortex pattern
  exactly). New LED POINTS section (list + W/H spins + color picker + Intensity spin + Blink slider) with
  Copy/Paste, mirroring the Vortex Points section's own layout. Data model: `_led_points` (pos+id, saved to
  `creep_layout.cfg [ledpoints]`) + `_led_styles` (w/h/color/intensity/blink_hz, saved to `plume_styles.cfg`'s
  new `[led_styles]` section — same file Vortex/Plume styles already share). Live canvas preview via
  `_refresh_led_preview()` (spawns real `LedLight` nodes on the EO, exactly like `_refresh_vortex_preview()`).
  Wired into every cross-cutting system Vortex already had: ESC/right-click cancel, Delete key, ESC/ARENA-focus
  cleanup on close, ratio-preserving `_rescale_points_for_resize()` on sprite resize, ADD/select mutual-
  exclusion with FP/TP/TenP/Vortex.
- `arena_enemy.gd`: `_setup_leds()` / `_update_led_xform()`, byte-for-byte the same anchoring approach as
  `_setup_vortexes()` / `_update_vortex_xform()` (body-relative fraction, scaled to `_draw_size`, re-glued
  every frame to the live rotating/breathing sprite transform) — reads `creep_layout.cfg [ledpoints]` +
  `plume_styles.cfg [led_styles]`.

**Dynamic panels** — new `_refresh_dynamic_panels()`, called after every add/delete for FP/TP/Vortex/Led and on
every creep switch: FIRE POINTS / THRUST POINTS / VORTEX POINTS / LED POINTS section now `.visible`s only
when `_fire_points`/`_thrust_points`/`_vortex_points`/`_led_points` for the ACTIVE creep is non-empty — an
empty/unused section no longer takes up panel space. (TENTACLE POINTS stays permanently hidden regardless,
already hidden by design since the CHAIN rewrite — unaffected.) Each section's leading separator + header +
list are captured into `_fp_section_nodes`/`_tp_section_nodes`/`_vortex_section_nodes`/`_led_section_nodes` at
build time; the FP/TP angle rows are deliberately excluded — they already have their own dedicated show/hide
tied to whether a point is currently SELECTED, a separate concern from "does this creep have any at all".

Verified via `godot --headless --check-only` (clean) plus a runtime smoke test instantiating `LedLight`
directly (`setup()`, multiple `_process()` ticks, confirmed the blink factor varies smoothly and correctly
across a 10Hz cycle — not just a static value).

## Changelog — 2026-08-15 (33rd pass) — Bend Lock had no effect on the Head→Body1 joint

User's suspicion confirmed by inspection: `_update_centipede_chain()`'s bend clamp required `k >= 2` (a real
`k-2` point to derive "the previous joint's own direction" from) to have anything to compare against — so the
very first joint (k=1, Head→first Body point) was silently exempt, letting Body1 swing to any angle relative
to where the Head actually points, no matter what Bend Lock was set to. Every other joint (k>=2) — which
already includes Tail, an ordinary joint like any other — was already correctly clamped; nothing tail-specific
was ever skipped.

Fix: `k=1` now gets its own reference direction — the Head's actual facing (`_centi_dir`) — playing the same
role a real `k-2` point plays for every later joint, instead of being skipped outright. Editor-side unaffected
(Creep Edit's CHAIN preview is a static straight-line layout, no bend simulation to fix there — Bend Lock is
purely a live-movement arena behavior).

Verified via `godot --headless --check-only` (clean). Ask the user to set a tight Bend Lock and confirm Body1
no longer snaps independently of Head's turning.

## Changelog — 2026-08-15 (32nd pass) — LAYERS panel: synthetic "whole creep" group row that resizes every part together; child rows shortened to head/body1/body2/tail

Two-part request: (1) a top-level layer named after the creep, above all its parts, that resizes the WHOLE
creep when selected instead of one part; (2) shorten the part rows below it to just "head"/"body"/"body1"/
"body2"/"tail" instead of the full "<prefix> head" etc.

- **New `_group_selected: bool`** state — true when the synthetic group row is active instead of any one part.
  `_set_active_creep()` always clears it (picking a specific part always exits group mode).
- **`_refresh_layer_list()`**: for any multi-part creep, now emits `_make_group_layer_row(root_name)` first —
  the LAYERS panel's collapse caret moved here from the old un-indented Head "root row". Every real part
  (Head included) is now an indented child row. Standalone (no-parts) creeps are unaffected — still a single,
  full-name row.
- **`_group_display_name()`** — the group row's label is the shared prefix `_parse_chain_name()` already
  extracts from Head/Body/Tail filenames (e.g. "hammerhead"), trimmed. **`_short_layer_label()`** — same parse,
  returns just "head"/"tail"/"body" (or "body1"/"body2"/… for multi-texture sets) for child rows. Both fall
  back to the raw name for parts that don't fit the Head/Body\<N\>/Tail convention (e.g. squid's tentacles).
- **`_creep_group_bbox()`** / **`_apply_group_scale()`** / **`_apply_group_move()`** — ported from
  `hud_edit_mode.gd`'s own proven group-resize pattern (`_group_bbox()`/`_scale_group()`): bbox from every
  live member's position+size; scale multiplies every member's position (relative to the bbox's own top-left)
  and size by the same factor; move adds the same delta to every member. Also rescales each member's own fire/
  thrust/tentacle/vortex points via the existing `_rescale_points_for_resize()`, same as a normal single-part
  resize.
- **Transform panel + spin handlers** (`_refresh_transform_panel()`, `_on_w_spin_changed()`/`_on_h_spin_changed()`/
  `_apply_spin_to_selected()`/`_on_pos_spin_changed()`) each gained a `_group_selected` branch at the top: W/H/X/Y
  show and drive the group's bbox instead of one EO's transform; Z is hidden/disabled (no single meaningful
  value for a group).

Known minor limitation: each member's resize/move pushes its own undo entry, so Ctrl+Z after a group resize
reverts one part at a time rather than the whole group in one step — acceptable for now, flagging in case it's
worth a dedicated multi-part undo entry later.

Verified via `godot --headless --check-only` (clean). Applies to `weapon_edit_mode.gd` too (subclasses this
file, doesn't override any of the touched functions) — untouched: `boss_edit_mode.gd`, which has its own
completely separate, unrelated `_make_layer_row()`/`_refresh_layer_list()`.

## Changelog — 2026-08-15 (31st pass) — "Bend lock (deg)" SpinBox couldn't go below 10°

User request: couldn't set Bend Lock under 10. Was a hardcoded `min_value = 10.0` on the SpinBox
(`creep_edit_mode.gd`'s `_build_chain_controls()`), no functional reason for the floor — the bend-clamp math
(`arena_enemy.gd`'s `_update_centipede_chain()`, `clampf(diff, -_centi_max_bend, _centi_max_bend)`) is well-
defined all the way to 0° (a fully rigid, non-bending chain — every joint forced to extend in a dead-straight
line from the one before it, no crash/NaN risk). Lowered the SpinBox floor to 0.0.

Verified via `godot --headless --check-only` (clean).

## Changelog — 2026-08-15 (30th pass) — Removed the Head's separate "neck shift" hack entirely — one source of truth, no more drift-prone second formula

The 29th-pass fix (sync `_centi_spacing` to the real authored joint-1 distance) wasn't enough — user confirmed
arena still overlapped noticeably more than Creep Edit. Root cause: `_draw_centipede()`'s Head draw call has
ALWAYS applied a second, separate adjustment on top of the chain point — `shift = (_centi_head_len -
_centi_spacing) * 0.5 - CENTI_HEAD_OVERLAP` (a magic-number `20.0px` pull-in) — pulling the drawn Head sprite
even closer to Body than the joint-1 distance alone already places it. Creep Edit's own canvas has no
equivalent second adjustment anywhere — it just draws Head at its authored box, period. Two formulas
computing "the same thing" independently is exactly the kind of drift this whole investigation kept re-
finding in different forms (expand_mode clamp, z-order, the neck shift itself going stale in the 29th pass) —
per explicit user request ("sử dụng 1 nguồn dữ liệu cho cả 2... để creep giống y hệt nhau ở cả hai nơi"),
collapsed it to one source of truth instead of patching the second formula again.

Fix: deleted the shift entirely. Head now draws directly at `_centi_pts[0]`, exactly like every Body/Tail
segment — the ONLY thing determining the Head↔Body gap is `_centi_joint_spacing(1, n)` (which itself reads
Creep Edit's authored positions when available, or the Spacing-mult formula otherwise) — the exact same value
both the point-placement AND the draw call now use, with no second adjustment layered on top anywhere. Removed
the now-fully-dead `CENTI_HEAD_OVERLAP` const and `_centi_spacing`/`_centi_head_len` vars along with it (no
other callers).

Verified via `godot --headless --check-only` (clean). Ask the user to re-spawn "cent"/"hammerhead" and confirm
the Head↔Body gap now matches Creep Edit exactly (not just closer) — if it still doesn't, the discrepancy is
no longer in this code path at all (both places now read from the literal same numbers), so the next place to
look would be a rendering-level difference (rotation, pivot, or texture native-size handling) rather than
another spacing formula.

## Changelog — 2026-08-15 (29th pass) — Head↔Body gap on arena was noticeably closer than Creep Edit — the head's own cosmetic "neck shift" went stale after the 23rd-pass authored-gap override

User caught it via direct A/B comparison: Head-to-Body gap visibly smaller on a real arena spawn than what
Creep Edit shows for the same creep.

Root cause: `_load_centipede()` sets `_centi_spacing` — used ONLY by `_draw_centipede()`'s head-specific "shift
forward so its neck meets the first body segment, pull back `CENTI_HEAD_OVERLAP`" cosmetic offset — from the
OLD formula (`_centi_body_sizes[0].y * _centi_spacing_mult`). The 23rd pass changed what joint 1 (head↔first-
body) ACTUALLY uses for point placement to `_centi_joint_spacing(1, n)` (the authored gap from Creep Edit's
saved positions, when set), but never updated this second, separate copy the head-shift math reads — so the
two drifted apart: the BODY's chain point moved to the new authored distance, but the HEAD sprite's forward
shift stayed calibrated to the old formula value, over- or under-pulling the head toward the body depending on
how the authored gap compared to the formula guess. Flagged as a known gap in the 23rd-pass changelog entry at
the time ("cosmetic only... flagging in case a large authored gap ever looks slightly off") — this is that gap
actually manifesting.

Fix: `_centi_spacing` now reads `_centi_joint_spacing(1, _centi_segments)` directly (the exact same value
`_update_centipede_chain()` uses for that joint), falling back to the old formula only in the degenerate
`_centi_segments <= 1` case. Head's neck shift is now always calibrated against whatever gap is actually in
effect, authored or formula-derived.

Verified via `godot --headless --check-only` (clean — one unrelated pre-existing resource-not-found warning for
`hammerhead.png`, a main-menu preview-spawner asset gap untouched by this change).

## Changelog — 2026-08-15 (28th pass) — Tail independent position restored; CHAIN panel description label removed

Two requests testing on "hammerhead": (1) couldn't move Tail independently — adjusting Body2's position dragged
Tail along with it; (2) remove the CHAIN section's explainer paragraph to keep the panel shorter (also now
stale — it claimed only Segments/Spacing/Bend/Taper affect spawn, no longer true since the 23rd pass).

1. **Tail independence**: reverted the 18th-pass "Tail position always auto-follows the chain end" behavior in
   `creep_edit_mode.gd`'s `_rebuild_chain_preview()` — Tail is a real node again, treated exactly like Head and
   every Body-template (this rebuild never writes its position; only true DUPLICATES, which have none of their
   own, get repositioned here). The 18th-pass concern this originally fixed ("tail nằm ở vị trí khác lạ" after
   raising Segments) doesn't regress: `_auto_arrange_chain_templates()` already includes Tail in its one-time
   stacked-default layout (same as Head/Body), and more importantly the REAL spawn was changed in this same
   pass to read Tail's AUTHORED GAP from its saved position (extended `arena_enemy.gd`'s `_centi_joint_spacing()`
   — previously Head↔Body-template(s) only — to also cover the last-Body-template↔Tail boundary, using
   `_centi_icon_for()` so it still resolves correctly even when the actual preceding runtime slot is a
   duplicate/tapered repeat of that template). So whatever gap you set between Tail and its neighbor now
   actually shows up in-game regardless of Segments/Spacing, instead of a formula guess.
2. **CHAIN panel description removed** (`_build_chain_controls()`) — the `Label` explaining the pos/size
   caveat is gone per request; the (now more accurate) explanation lives only as a code comment.

Verified via `godot --headless --check-only` (clean) plus a manual trace against "hammerhead"'s actual saved
`creep_layout.cfg` data (head/body1/body2/tail real pos+size) confirming the authored gap resolves sensibly at
every template↔template boundary including the new Tail one, and correctly falls back to the formula once
Segments pushes a duplicate in front of Tail (no real position to read there, by design).

## Changelog — 2026-08-15 (27th pass) — FOUND THE REAL "tail size / body position resets on restart" bug: switching the Map dropdown never re-loads that map's saved layout

User's own precise before/after test nailed it: Tail W was 60 → resized to 30 → Save (toast confirmed) → full
restart → Creep Edit shows W=60 again. Body Y (relative to Head) was 85 → set to 60 → Save → restart → shows 85
again. **Only in Creep Edit — arena always spawned with the correct, just-saved values**, which was the key
clue: the disk file was never the problem (confirmed correct/updated both times via direct read).

Root cause: `_selected_map_id` (which `MAP_REGISTRY` entry the "Map:" dropdown is on) is a plain in-memory var
defaulting to `"default"` — never persisted, so every fresh session starts on the default map regardless of
what was selected last time. `_ensure_built()` (first Creep Edit open each session) calls `_scan_creeps()` (map-
filtered sprite list) then `_load_layout()` (reads `creep_layout.cfg` pos/size into `_placed`, but only for
whatever's in `_all_creep_names` AT THAT MOMENT — the default map's sprites; "cent"/Atlantic isn't there yet).
Switching the dropdown to Atlantic (`_on_map_selected()`) re-ran `_scan_creeps()` (now "cent body"/"cent tail"
appear in `_all_creep_names`) but **never called `_load_layout()` again** — so the first time an Atlantic creep
got selected, it fell through to `_load_or_create_creep()`'s hardcoded-default fallback (`size =
Vector2(60.0, 60.0*aspect)`, `pos = Vector2(480.0, 380.0)`) instead of what was actually saved on disk — exactly
the "W=60 / position back at Head's spot" values reported. `arena_enemy.gd` reads `creep_layout.cfg` directly
through its own independent static cache, untouched by any of this editor-only state, which is why it always
showed the correct, freshly-saved values while the editor kept showing stale defaults.

Fix: `_on_map_selected()` now also calls `_load_layout()` right after `_scan_creeps()`/`_build_creep_buttons()`
— safe to call repeatedly, it's a no-op for any name already present in `_placed`. Any creep newly revealed by
a map switch now gets its real saved pos/size/firepoints/etc. loaded immediately, matching what already happens
for the first (default) map at editor-open time.

Verified via `godot --headless --check-only` (clean). Ask the user to fully restart, open Creep Edit, switch
Map to Atlantic, and confirm "cent tail"/"cent body" now show their actual last-saved values immediately —
no need to have touched them this session first.

## Changelog — 2026-08-15 (26th pass) — Taper "far nodes stretched/skewed toward the tail" — the z_index fix was a red herring; real cause was a TextureRect minimum-size clamp

User correctly pushed back that it wasn't z_index — sent a screenshot (Segments=15, Spacing=0.65, Taper=4.8%)
showing the body chain visibly skewed/flattened toward the tail, confirmed it does NOT happen on a real arena
spawn with identical settings. Built an actual runtime probe (`EditableObjectScene.instantiate()` +
`template.duplicate()`, mirroring `_make_chain_dup_eo()`'s exact code path, printing real property values
instead of re-deriving math) and found it immediately: `dup.size.x` (the Control) correctly shrinks with taper
every step, but `texture_rect.size.x` (the CHILD node that actually renders the sprite) stayed pinned near
60px — the template's original, un-tapered width — no matter how small `.size` was assigned. Only the height
tracked correctly. That's a horizontally-stretched, off-center silhouette by construction: the Control's own
box (used for centering) shrinks correctly, but the visible texture inside it stays wide and anchored to the
box's top-left, increasingly overhanging to the right as the box narrows around it — reading exactly as
"skewed/flattened, drifting right" the further it tapered. Confirmed why arena never shows this: it draws with
`draw_texture_rect()` (immediate-mode), never touching a `TextureRect` node or its layout/minimum-size system
at all.

Mechanism: `editable_object.tscn`'s `TextureRect` has `expand_mode = EXPAND_FIT_WIDTH_PROPORTIONAL` (3), which
makes Godot compute a texture-derived minimum size that any `.size =` assignment gets silently clamped to —
verified by literally printing `texture_rect.expand_mode`/`.size` before and after the assignment.

First fix attempt changed `expand_mode` directly in the shared `.tscn` — **caused a real regression**: that
scene is instantiated by main menu, boss edit, and HUD edit too (not just creep/weapon edit), and main menu's
logo/buttons visibly shrank. Reverted the `.tscn` back to its original `expand_mode = 3`. Real fix scoped
instead to `creep_edit_mode.gd`'s `_place_creep_eo()` — the single choke point for every node either creep edit
or weapon edit (a subclass) ever creates — setting `eo.texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE`
there only. Chain DUPLICATES (`_make_chain_dup_eo()`) are created via `template_eo.duplicate()`, which correctly
carries this property over from the now-fixed template — no separate fix needed for them. Main menu
(`"mainmenu"`), boss edit (`"boss_*"`), and HUD edit (`"hud_item"`) build their `EditableObject` instances
through their own code, never through this function, so they're untouched — reverified with a runtime probe
showing an object built the same way main menu does still clamps exactly like before (unchanged behavior).

Verified via `godot --headless --check-only` (clean) plus the two runtime probes (numbers pasted in the reply).
Also un-did the previous (25th-pass) z_index hack back to the harmless `move_child()`-based reorder from the
24th pass, since it's no longer load-bearing for this bug and the z_index approach had a real side effect
(permanently changing what `_save_layout()` persists for Head/Body-template/Tail's z_index).

## Changelog — 2026-08-15 (25th pass) — Taper flatten/shift in Creep Edit survived the sibling-reorder fix; switched to explicit distinct z_index

User sent an actual screenshot (Segments=15, Spacing=0.65, Taper=4.8%) confirming the 24th-pass `move_child()`
reorder did not fix it — still flattened/shifted toward the tail. Isolated it further: **Taper=0% with the
same Segments/Spacing shows no distortion at all**; only reappears once Taper > 0%, i.e. once neighboring
segments actually differ in size. Re-ran the headless math-proof script a 3rd time with these exact live values
— `center_x` still locked at 510.000000 (±1e-5 float noise) through all 13 duplicates — box math is, for the
third time, proven correct. Confirms the underlying cause is still paint-order/occlusion, not position — the
24th-pass fix's *diagnosis* was right, but relying on `_objects_container.move_child()` (same-z-index sibling
tie-break) apparently isn't a reliable enough paint-priority signal in practice.

Fix: replaced the sibling-reorder with explicit, mutually **distinct** `z_index` values on every node in the
active chain (`_chain_z_order`) — `head = 130`, decreasing by 1 per slot down to the tail — which Godot sorts
by unconditionally, no tie-break involved. Only ever applied to the currently-active/visible chain's own nodes.
Side effect (acceptable, arguably an improvement): `z_index` for the 3 real nodes (head/body-template(s)/tail
— duplicates are never saved) now persists via `_save_layout()` as "head above body above tail" instead of the
old uniform 115 — a sensible default matching the arena's own draw order, not an arbitrary value.

Verified via `godot --headless --check-only` (clean). **Ask the user to fully restart Godot** (not just
reopen the Creep Edit panel) before retesting, since the previous fix attempt's code may not have been the one
actually running when the screenshot was taken — then re-drag Taper on "cent" with Segments=15/Spacing=0.65 and
confirm the far segments now render as clean, centered boxes with head on top, tail on bottom, no flatten/shift.

## Changelog — 2026-08-15 (24th pass) — Taper slider "far nodes get flattened + shifted right" in Creep Edit's own canvas: paint-order bug, not a math bug

User report was specific: reproduces on the **static Creep Edit canvas** while dragging Taper (not a moving
arena spawn), keeping `centi_spacing_mult` intentionally low (0.75 — segments meant to overlap).

Proved with an actual headless script run (same method as the 15th-pass entry) that the size-ratio and X-
centering formulas in `_rebuild_chain_preview()` are exactly correct at every taper step: aspect ratio constant
at 1.6730 through 10 compounding steps, `center_x` identical to 6 decimal places from the template all the way
to the last duplicate. So the box math was never the bug — confirmed by real numbers, not just re-reading code.

Real cause: `EditableObjectNode`s don't clip against each other — with `Spacing < 1.0` (deliberate overlap),
whichever node is LATER in `_objects_container`'s child list simply paints on top in the overlap region
(Godot's default same-z-index paint order). Duplicates get `add_child()`ed farthest-first (i=2, then 3, then
4…), so the smaller/farther duplicate always ends up painting OVER the larger one just ahead of it — backwards
from the real arena's own convention (`arena_enemy.gd`'s `_draw_centipede()`: draws tail→head, head last =
head always on top). That backwards paint order is what read as "far nodes chewed into a flattened, off-center
sliver" — only part of each far segment's box survived the overlap, and which part survives depends on paint
order, not the box's own (perfectly centered, correctly sized) position.

Fix (`creep_edit_mode.gd`'s `_rebuild_chain_preview()`): collect every real/dup node for the active chain in
head→tail order (`_chain_z_order`), then re-sibling them (`move_child`, walked tail→head so head lands last)
so paint order always matches the arena's head-on-top convention — regardless of how tight `Spacing` is set.
Deliberately does NOT touch any node's saved `z_index` (would otherwise leak an editor-internal paint-order
concern into `creep_layout.cfg` on the next Save) — purely a sibling-order change, live every rebuild.

Verified via `godot --headless --check-only` (clean) and the throwaway headless math-proof script (numbers in
the reply, not just claimed). Ask the user to re-drag Taper up on "cent" with Spacing still at 0.75 and confirm
the far segments now render as clean, centered, progressively-smaller boxes with head always on top — the
overlap itself will still be visible (that's the deliberate 0.75 Spacing choice), just no longer reading as
distorted/shifted.

## Changelog — 2026-08-15 (23rd pass) — Head/Body-template X/Y position now actually affects the real chain spacing (not just size)

Follow-up to the 21st-pass explanation: "cent" (and every chain-type creep)'s spawn NEVER read `pos` from
`creep_layout.cfg` — only `size` (16th pass). All joint spacing came from a single global formula (preceding
segment's own size × `centi_spacing_mult`), so dragging Body up to overlap Head in the Transform panel visibly
changed nothing at spawn/on restart — it was "reset" every time because nothing was ever wired to read it.

Wired it up for the one case where a saved `pos` is genuinely, freely user-authored — the boundary between two
**real templates** (Head↔first-Body-template, or Body-template(i)↔Body-template(i+1) for the 2-body-texture
sets like hammerhead) — since those are the only nodes `creep_edit_mode.gd`'s CHAIN rebuild never auto-
repositions (deliberately excluded: chain DUPLICATES, which have no position of their own — always formula-
placed — and the Tail boundary, whose own saved `pos` is itself chain-derived every rebuild in the editor, not
a free choice, so reading it back would just be circular).

- New `_authored_joint_dist()` (`arena_enemy.gd`) — same case-insensitive `creep_layout.cfg` lookup pattern as
  `_authored_seg_size()`, returns the authored CENTER-TO-CENTER distance between two named parts' saved
  pos+size, or a fallback if either was never placed.
- New `_centi_joint_spacing(k, n)` — single source of truth for both `_update_centipede_chain()` call sites
  (one-time straight-line init + the live per-frame follow loop): the existing size×Spacing-mult×taper formula
  as the default, overridden by `_authored_joint_dist()` only at a real template↔template boundary.
- Takes effect the moment Creep Edit's Save button runs (already calls `ArenaEnemyScript.reload_layout_cfgs()`
  → drops the static `creep_layout.cfg` cache) for any enemy spawned AFTER that Save, same as size already did
  — does not retroactively reposition an already-alive enemy (same documented limitation size resize has).
  Persists to disk via the existing `creep_layout.cfg` "pos" field — no new save-side changes needed, only the
  read side was missing.
- Known minor gap, not addressed here: the Head sprite's own small neck-overlap draw shift
  (`CENTI_HEAD_OVERLAP` in `_draw_centipede()`) is still calibrated off the OLD formula-based spacing, not the
  new authored one — cosmetic only, unrelated to what was reported, flagging in case a large authored gap ever
  looks slightly off right at the neck.

Verified via `godot --headless --check-only` (clean). Ask the user to drag "cent body" to overlap Head, Save,
then Quick Spawn a fresh "cent" (same session AND after a restart) to confirm the gap now matches what they set.

## Changelog — 2026-08-15 (22nd pass) — FOUND THE REAL BUG: `_load_tentacle()` misread CHAIN's "parent" field as squid tentacle segments on every centipede-type creep

The 21st pass's theory (stuck static editor ghost) was wrong — user confirmed the stray body/tail **moves**,
tracking the real creep but on its own trajectory, with no head of its own, reproduced with a single plain
Quick Spawn click (ruled out bulk-spawn / a second full instance, since only 1 head was ever visible).

Root cause: `_load_tentacle()` (built for `"squid"` — forward-kinematics wave/drag tentacle segments,
`squid-1`..`squid-8` parented to `Squid-body` in `creep_layout.cfg`) runs **unconditionally for every enemy**
in `_ready()`, and identifies "tentacle segments" purely by scanning `creep_layout.cfg` for entries whose
`"parent"` field matches the enemy's icon basename — with no `behavior` check at all. Creep Edit's CHAIN
auto-grouping (2026-08-13) uses that exact same `"parent"` field, for an unrelated reason (organizing
Head/Body/Tail under the Head in the Layers panel): `"cent body"` and `"cent tail"` both have
`"parent": "cent head"`. Every centipede-type creep therefore had its own Body/Tail template misread as
"my tentacle segments", building a second, bogus tentacle chain — headless (the template only ever includes
whatever's parented, never the head itself), animated by tentacle physics (wave+drag+taper, nothing like
`_update_centipede_chain()`'s follow-the-preceding-joint formula) — drawn every frame right alongside the real
one. Reads exactly as "an extra body and an extra tail, no head, trailing on their own path."

Fix: `_load_tentacle()` now returns immediately unless `behavior == "squid"` — the only real consumer
(`arena_wave_director.gd`'s `"squid"` def; the similarly-named `"atlantic_squid"` is `behavior: "chase"`, not
affected either way). No other creep type ever legitimately needs this system.

Verified via `godot --headless --check-only` (clean). Ask the user to Quick Spawn a fresh "cent" and confirm
only 1 body + 1 tail now, tracking correctly.

## Changelog — 2026-08-15 (21st pass) — "cent có 2 tail, 1 đúng vị trí 1 sai vị trí": Creep Edit could be left permanently "open" (EOs never hidden) if something else unpaused the tree

User confirmed, precisely, that the 2 stray "cent" pieces from the 19th-pass report were **1 body + 1 tail**
(not a Segments-related duplicate — ruled that theory out: they'd raised Segments for "cent", but Tail is
never duplicated by the CHAIN system, only Body is, so a stray tail can't come from that path), and that the
stray tail sits at a **fixed position** while the real one is correctly attached to the moving enemy.

Root cause, confirmed by tracing coordinates: Creep Edit's placed EOs (`"cent body"`/`"cent tail"`/…) live on
their **own dedicated CanvasLayer (layer 9, screen-space, added directly under `arena`)** — see
`arena.gd._setup_creep_edit()` — completely independent of the world/camera. `creep_layout.cfg`'s saved
`"cent tail"` position (`Vector2(493.5, 607.39)`) is a fixed SCREEN coordinate, not a world one. The 19th-pass
fix made `_close()` → `_update_gameplay_visibility()` a hard guarantee *whenever `_close()` actually runs* —
but `_close()` only ever runs from this editor's own Close button or its `toggle()` off-path. Nothing stopped
the tree's pause from being lifted by some OTHER path (e.g. dismissing an unrelated overlay that
unconditionally does `get_tree().paused = false`) while Creep Edit still believed itself open
(`_is_open == true`, EOs still `visible = true` + interactive from when it was the active/companion creep) —
gameplay would then resume around it, and the stuck EO reads exactly as "a second tail sitting at some random
unmoving spot" next to the real, live, chain-animated one.

Fix (`creep_edit_mode.gd`): added a `_process()` — the node already runs `PROCESS_MODE_ALWAYS` (works while
paused) — that checks every frame for the one state combination that should be impossible under normal
operation: `_is_open == true` while `get_tree().paused == false` (this editor is the only thing that's
supposed to set `paused = true` for as long as `_is_open` holds). The instant that combination is observed, it
self-heals by running the normal `_close()` path — same cleanup Close already does (hide/un-interact every
placed EO, clear chain dups, restore focus), just triggered defensively instead of only on an explicit click.
Applies to `weapon_edit_mode.gd` too (subclasses this file, no `_process()` override of its own).

Verified via `godot --headless --check-only` (clean). Couldn't reproduce the exact external-unpause trigger
without a live session — ask the user to confirm the stray tail no longer appears after this change, and if it
still does, get the precise repro steps (what they clicked/pressed right before returning to gameplay) so the
actual external unpause path can be identified and named here.

## Changelog — 2026-08-14 (20th pass) — Found the REAL reason Segments kept resetting on restart: no wave director ever runs on the Atlantic map

The 17th/18th-pass "unconditional write" fix was correct but incomplete — it fixed a real bug in the WRITE
path, but the user kept seeing `centi_segments` reset to 3 after a full game restart regardless. Checked the
actual file this time instead of just re-reasoning about the write side: `creep_chain_overrides.cfg` DID
correctly have `"centi_segments": 8` on disk. The bug was entirely on the READ side.

Root cause: `apply_overrides()` (creep_info_panel.gd, HP/Move/Shoot) and `apply_chain_overrides()`
(creep_edit_mode.gd, this feature) were ONLY ever called from a wave director's own `_ready()`
(`arena_wave_director.gd` / `_v2.gd`). But `arena.gd` has a **`if _map_id != "atlantic":` guard around BOTH
wave-director options** — a deliberate, unrelated 2026-08-08 debug change ("Ngăn chặn spawn trong map atlantic
để tôi test map") that skips ambient wave spawning entirely on Atlantic so terrain could be tested without
combat. Since NEITHER wave director is ever instantiated on that map, NOTHING ever calls
`apply_overrides()`/`apply_chain_overrides()` there — `WaveDir.ENEMY_DEFS` (a `static var`, so it resets to
its literal hardcoded values on every fresh process launch) stays at its raw un-overridden defaults for the
whole session. `arena_debug_spawn.gd` (Quick Spawn — what's actually used to test enemies on Atlantic, since
the ambient spawner is off) reads `WaveDir.ENEMY_DEFS` directly, so it silently spawned with `centi_segments:
3` all session. It LOOKED fixed within the same session because Creep Edit's own live-apply
(`_apply_chain_fields()`) mutates that same static dict directly, in memory, immediately — masking that the
override was never actually being loaded back in from disk on a real restart.

Fix: `arena_debug_spawn.gd` is instantiated unconditionally on every map (unlike either wave director) — added
both `CreepInfoPanelScript.apply_overrides(WaveDir.ENEMY_DEFS)` and
`CreepEditModeScript.apply_chain_overrides(WaveDir.ENEMY_DEFS)` calls to its own `_ready()`. Redundant (and
harmless — both are idempotent, absolute-value applies) wherever a wave director already does it; load-bearing
on Atlantic where none exists.

Verified via `godot --headless --check-only` (clean).

## Changelog — 2026-08-14 (19th pass) — Editor preview sprites hardened to ALWAYS hide on close, no list indirection to fall out of sync with

User confirmed the "1 miếng tail và 1 miếng body của cent bay lòng vòng" report was NOT a stale old enemy
instance — it was the EDITOR's own template EOs ("cent body"/"cent tail") stuck `visible = true`, floating at
their EDITOR CANVAS coordinate (a totally different coordinate space than where a real enemy actually spawns
in the arena, hence looking like a random/stray spot).

`_update_gameplay_visibility()` (the function `_close()` calls to guarantee nothing's left showing) only ever
walked `_all_creep_names` — so any placed EO that fell out of that list, for ANY reason (the already-fixed
map-switch case, or some other path not yet identified), was silently skipped and left visible forever. Fixed
by making it iterate every EO in `_placed` DIRECTLY instead of going through the name-list indirection —
closing Creep Edit is now a hard, unconditional guarantee that nothing it ever placed is still visible, with
no list-membership gap possible. (Deliberately did NOT extend `_update_all_creep_interactivity()` the same
way — that one's OPEN-time selective show/hide logic actively depends on chain-duplicate EOs NOT being in
`_all_creep_names`/`visible_set`, so blindly iterating `_placed` there would hide every CHAIN duplicate the
instant it's created.)

Verified via `godot --headless --check-only` (clean).

## Changelog — 2026-08-14 (18th pass) — Taper re-spec'd to 0-10% per-step compounding; fixed a real disk-erase bug; creep_layout.cfg gets an extra autosave point

1. **Taper redefined** (explicit request): slider is now **0-10%** (was 0-80%, step 0.1 not 1.0) and the
   formula is **per-step compounding**, not "spread linearly across the whole chain" — each body slot is
   exactly `(1 - taper%)` smaller than the ONE RIGHT BEFORE IT in its own texture's run (`steps` = slots since
   that texture's own template/first-use). Changed in both `creep_edit_mode.gd`'s `_rebuild_chain_preview()`
   (`steps = i - idx - 1`) and `arena_enemy.gd`'s `_centi_seg_scale()` (`steps = k - idx - 1`, same formula,
   `k`↔`i` are the same absolute slot index) — still pixel/shape-identical between editor and spawn.
2. **Real bug, found by inspecting the actual override file**: `centi_segments` was straight-up MISSING from
   `creep_chain_overrides.cfg` after the user set it to 8 and it read back as 3 on restart — confirms the
   17th-pass "moving target" bug (comparing a new value against `ENEMY_DEFS`, which `apply_chain_overrides()`
   itself had just mutated) really was silently erasing overrides, not just a theoretical risk. That fix
   (unconditional write, no more comparison) already covers this.
3. **"vẫn thấy có cái đuôi nằm ở vị trí khác lạ" lingering + "1 tail và 1 node body bay lòng vòng" on the
   arena** — the tail-position fix from the 17th pass covers the EDITOR preview; a SEPARATE, already-alive
   enemy instance from BEFORE the Segments change won't retroactively adopt the new segment count (documented,
   intentional — `_load_centipede()` only runs once per instance, at spawn). If an old (segments=3) instance
   was still alive when testing the new (segments=8) config, you'd see BOTH on the arena at once: the old one
   showing as just 1 body + 1 tail, the new one correct — reading as "a stray tail and body floating around"
   next to the correct one. Not a bug; let old enemies die (or restart the wave) before checking a config
   change. (The 17th pass' `_on_map_selected()` fix already covers the OTHER way a stray EDITOR sprite could
   get stuck visible, in case that's what was actually seen instead.)
4. **creep_layout.cfg (pos/size) extra autosave point**: previously only flushed when the editor closed
   cleanly — alt-F4, a crash, or forgetting to close the panel before quitting meant every resize/move since
   the last close was gone, with no visible warning. Now also flushes on every plain creep switch (`if _dirty
   and creep_name != _active_creep: _save_layout()` in `_set_active_creep()`), so there's no longer one single
   "did I close it right" moment the whole session hinges on.

Verified via `godot --headless --check-only` (clean).

## Changelog — 2026-08-14 (17th pass) — CHAIN fields now apply live (no Save button); fixed a real "Segments resets" bug + a stuck-visible ghost creep on map switch

Three separate reports:

1. **"chỉnh segment lên 8, bấm layer tail, segment tự động về 3"** — real bug, root cause: `_refresh_chain_controls()`
   re-reads the 4 CHAIN spinbox values from `ENEMY_DEFS` on EVERY active-creep change, including just clicking
   a different LAYERS row within the SAME already-open chain group — and under the old "Save Chain" model,
   `ENEMY_DEFS` still held whatever was last explicitly saved, not the in-progress edit, so switching rows
   silently snapped the UI (and, on the next rebuild, the preview) back to the last-saved value.
2. **Explicit request: "Bỏ nút save chains đi, mọi thay đổi có hiệu lực ngay tức thì"** — removed the "Save
   Chain" button entirely. `_on_chain_field_changed()` now calls `_apply_chain_fields()` (renamed from
   `_on_chain_save()`) on every keystroke/drag-tick — applies to `ENEMY_DEFS` (both v1's shared dict and v2's
   own copy if running) AND writes `creep_chain_overrides.cfg` to disk immediately, every time. "Reset" stays
   (still a distinct action: revert to hardcoded defaults). This directly fixes bug 1 above too, as a side
   effect — `ENEMY_DEFS` is never stale anymore, so re-reading it on every LAYERS click is now always safe.
3. **"Khi tôi mở creep edit, có 1 cái máy bay pirate1 xuất hiện... sau khi tắt creep edit, nó vẫn tồn tại trên
   arena"** — real bug in `_on_map_selected()` (the "Map:" dropdown). Switching maps rebuilds
   `_all_creep_names` down to ONLY the new map's sprites (`_scan_creeps()`), but never hid the previously-
   active creep first. The only 2 places anything ever gets hidden — `_update_all_creep_interactivity()` and
   `_update_gameplay_visibility()` — both walk `_all_creep_names`, so a creep that's no longer in that list
   (e.g. "pirate1", a Space/default-map sprite, after switching to Atlantic) is never visited again, EVER,
   including on close — a permanently stuck-`visible=true` ghost overlay for the rest of the session. Fixed by
   hiding every currently-placed EO unconditionally before the swap, then re-selecting the new map's first
   creep the same way the initial editor-open flow already does.

Also reaffirmed/verified the 16th pass' "edit matches spawn" work still holds for all 3 parts (head/body/tail)
after these changes — nothing in this pass touches `arena_enemy.gd`.

Verified via `godot --headless --check-only` (clean).

## Changelog — 2026-08-14 (16th pass) — Centipede arena spawn now reads its size from creep_layout.cfg — the same source Creep Edit's CHAIN preview uses

Per explicit request ("tôi muốn edit như thế nào thì spawn ra sẽ y hệt như thế"): until now, "centipede"-
behavior enemies computed their OWN geometry at spawn from scratch — width from `_radius * CENTI_WIDTH_MUL`
(the `size` stat), height from each texture's native pixel aspect at that width — completely ignoring
whatever the user actually resized Head/Body/Tail to in Creep Edit's canvas (`creep_layout.cfg`'s "size" was
gameplay-inert for this behavior type, mentioned as a known gap in the 14th-pass reply). That's WHY the editor
and the spawn could look different even with identical Segments/Spacing/Bend/Taper.

Fixed by making the arena spawn read the exact same per-part "size" Creep Edit saves, instead of deriving its
own:
- New `_authored_seg_size(icon_path, tex)` — looks up `creep_layout.cfg`'s `[creeps]` entry for that sprite's
  basename (identical lookup `ArenaEnemyScript.base_draw_width()` already uses for every OTHER enemy type,
  generalized to both W and H here). Falls back to the old radius-derived guess only if that sprite has never
  been placed/sized in Creep Edit at all (a brand-new def wired in by hand).
- `_load_centipede()` now populates `_centi_head_size`/`_centi_body_sizes[]`/`_centi_tail_size` from that
  lookup once per spawn, replacing the old shared `_centi_width` (kept only as a rough hit-radius fallback for
  `_check_contact()`).
- `_centi_seg_scale(k, n)` gained the same "first occurrence of a texture keeps its own authored size
  untouched" rule creep_edit_mode.gd's `_rebuild_chain_preview()` already used for its templates (`k <=
  _centi_body_texs.size()` → scale 1.0) — previously only the single-body-texture case (e.g. "cent") matched
  by coincidence; 2-texture reskins (hammerhead/killerwhale/shark_elite) now match too.
- `_update_centipede_chain()`'s per-joint follow distance now uses `_centi_seg_size_for(k-1, n).y ×
  spacing_mult` — the PRECEDING joint's own (tapered) size, matching the editor's own duplicate-spacing
  formula (`prev_eo.size.y × spacing_mult`) exactly, instead of the joint's own size.
- `_draw_centi_seg()` now takes an explicit `base_size: Vector2` param (the authored size for that slot) and
  draws `base_size × scale_mul` — same formula shape as before, just no longer forced to share one width
  across every segment.

Net effect: resize Head/Body/Tail (or the taper/spacing/segments) in Creep Edit → the next spawn of that enemy
looks the same, size- and spacing-wise. What still CAN'T match: absolute X/Y position while the enemy is
actually moving — the editor shows a static straight line, the arena's chain is live physics trailing behind
the head as it turns (that's inherent to a moving chain, not something a static preview can replicate frame-
by-frame) — but a fresh, stationary spawn's straight initial layout now uses the identical size/spacing math.

Verified via `godot --headless --check-only` (clean). Ask the user to resize/reposition a "cent" part in Creep
Edit, save, and spawn fresh to confirm the sizes now visually match.

## Changelog — 2026-08-14 (15th pass) — "cent" looked flattened toward the tail: proved it's not a ratio bug, fixed the real cause (zero-gap overlap)

Another round of "rõ ràng bị dẹp lép" with a screenshot. Rather than re-derive the math on paper again, actually
RAN it: a throwaway headless GDScript reproducing both the editor's `taper_ratio` formula and the runtime's
`_centi_seg_scale`/`_draw_centi_seg` formula against `cent body.png`'s real authored size (60×35.86, from
creep_layout.cfg). Printed width/height for every body slot at 70% taper — **every single one came back
1.6730**, bit-for-bit identical, in both formulas. So the per-segment box is not being distorted; that number
IS `cent body.png`'s own native aspect (532×318 px) — it's just a wide/flat sprite by design.

The actual cause: `centi_spacing_mult` defaulted to 1.0 for `atlantic_centipede`, and spacing is derived as
`segment's own height × spacing_mult` — so at 1.0, consecutive segments' CENTERS sit exactly one segment-height
apart, i.e. they touch edge-to-edge with ZERO gap. Segments closer to the head draw ON TOP of the ones behind
them (`_draw_centipede()` paints tail→head, head last). With zero gap, that top-drawn segment covers most of
the visible top of the one behind it — you only ever see the thin sliver below the segment in front, which
reads as "flattened", and the sliver is a bigger fraction of a SMALLER (more-tapered) segment, so it looks
progressively worse toward the tail even though every segment's own box is identically proportioned.

Fix: gave `atlantic_centipede` its own `"centi_spacing_mult": 1.3` in `ENEMY_DEFS` (was implicitly 1.0, the
shared fallback every other centipede-type def still uses) — a real ~30% gap between segments so each one's
actual silhouette is visible instead of hidden behind the one in front. User can still override via the CHAIN
section's "Spacing x" slider + Save Chain same as before; this just moves the *default* to something that
doesn't self-occlude.

Verified via `godot --headless --check-only` (clean) plus the actual headless GDScript run above (numbers
pasted in the reply, not just claimed).

## Changelog — 2026-08-14 (14th pass) — Stray chain-dup sweep on editor open (belt-and-suspenders for the 13th pass' ghost-node fix)

Re-verified the math after another "vẫn méo/lệch, giữ ratio + align center" report:
- Size: `dup_eo.size = template_eo.size * taper_ratio.call(i)` is a `Vector2 × float` — GDScript multiplies
  both components by the identical scalar, so the width:height ratio is mathematically unable to change.
- Position: `dup.x = prev.x + (prev.w - dup.w)/2` centers `dup`'s box exactly on `prev`'s own center
  (`center(dup) = dup.x + dup.w/2 = prev.x + prev.w/2 = center(prev)`, algebraically, for ANY prev/dup width)
  — and since every node centers on its immediate predecessor, the whole chain is transitively centered on the
  root template's own centerline no matter how many segments or how much taper. Independently re-checked the
  actual arena draw path too (`arena_enemy.gd`'s `_draw_centi_seg()`): `Rect2(Vector2(-dw*0.5,-dh*0.5), Vector2(dw,dh))`
  drawn at the joint's own position — also exactly centered, also `dw`/`dh` both scaled by the same `scale_mul`.
  Both the editor preview and the real spawn are already provably ratio-preserving and centered.

So the visible distortion isn't a math bug — it's almost certainly the 13th-pass "ghost duplicate" issue
(`queue_free()` racing a same-named `add_child()`) leaving orphaned stale-sized nodes behind BEFORE that fix
landed. Those orphans were created under the old code and were never cleaned up by anything — restarting just
the editor panel doesn't touch them, since they live under `_objects_container` (outside `_all_creep_names`,
outside `_placed`/`_chain_dup_names` tracking) and persist for the rest of that game session regardless of
code changes. Added `_sweep_stray_chain_dups()`, run once every time the editor is opened (`toggle()`): walks
`_objects_container`'s children, and any node whose name matches the `"<template> #<n>"` duplicate pattern but
isn't a currently-tracked value in `_placed` gets removed outright. This guarantees a clean slate on open
regardless of what a previous (possibly pre-13th-pass) session left behind — belt-and-suspenders on top of the
13th pass' actual fix, which already stops any NEW orphans from being created going forward.

Verified via `godot --headless --check-only` (clean). **Ask the user to fully restart the game** (not just
toggle the editor closed/open) before retesting — a hot-reloaded / still-running session from before this fix
could have accumulated exactly this kind of leftover.

## Changelog — 2026-08-14 (13th pass) — 3 bug fixes: taper "ghost duplicate" distortion, CHAIN edits lost on close, spawn not matching editor

Three reports after the 12th-pass rewrite:

1. **"spawn thì không giống như đã edit"** — CHAIN's Segments/Spacing/Bend/Taper fields only ever reached
   `ENEMY_DEFS` (and therefore an actual spawn) via the separate "Save Chain" button; the canvas preview
   already reflected the live slider values, but a spawn tested before clicking that button still used
   whatever was last saved. (Reminder for the user: Head/Body/Tail's own size/position in the editor canvas
   is a pure visual aid for "centipede"-behavior enemies — it's never read at spawn time at all; only the 4
   CHAIN fields + each sprite's own pixel aspect ratio affect the real in-game look.)
2. **"Taper khi kéo vẫn làm méo và lệch các node"** — root cause was a classic Godot race, not a math bug:
   `_clear_chain_dups()` used `queue_free()`, which only actually removes a node at end-of-frame, while
   `_rebuild_chain_preview()` immediately re-`add_child()`s a FRESH duplicate under the SAME name right after.
   A fast slider drag fires several `value_changed` ticks per rendered frame, so the new node kept colliding
   with the old (not-yet-freed) one — Godot silently auto-renamed the new one, and the orphaned old one (no
   longer tracked anywhere) stayed fully visible, overlapping the new one at its stale size, until its
   deferred free finally landed. That overlap is what read as "méo/lệch". Fixed by freeing synchronously
   (`remove_child()` + `free()`) instead of `queue_free()`. (The scaling math itself was already correct — a
   uniform `Vector2 × float` multiply can't change the width:height ratio — and duplicate positions were
   already exactly centered under their predecessor's center transitively back to the root template, so no
   separate "align center" fix was needed once the ghosting stopped.)
3. **"khi tắt game mở lại, toàn bộ edit bị mất"** — closing Creep Edit already auto-saves `creep_layout.cfg`
   when position/size edits are pending (`_dirty`), but the CHAIN fields live in a separate file
   (`creep_chain_overrides.cfg`) behind their own explicit "Save Chain" button, and closing never flushed
   THAT — so any Segments/Spacing/Bend/Taper edit made without remembering to click Save Chain first was
   silently gone on next open or game restart. Fixed with a new `_chain_dirty` flag: `_on_chain_field_changed()`
   sets it, `_on_chain_save()`/`_on_chain_reset()` clear it, and both `_request_close()` (closing the editor)
   and `_refresh_chain_controls()` (switching to a DIFFERENT chain group — the 4 fields are one shared widget
   set reused for every group, so leaving one dirty would otherwise be silently overwritten by the next
   group's own values) now auto-`_on_chain_save()` whenever it's set.

Verified via `godot --headless --check-only` (clean). Please re-test taper dragging + close/reopen and report back.

## Changelog — 2026-08-14 (12th pass) — Full CHAIN rewrite: 3 fully independent parts, linear taper, no more disappearing/snap-back nodes

User report: "càng làm càng hỏng" (kept getting worse) — after move+taper, segment nodes vanished; the 8-11th
pass "sticky template" design (`_chain_dup_offset`/`_chain_dup_taper_steps`/`_chain_templates_initialized`/
`_chain_preview_root`, the head-vs-template two-case split in `_follow_chain_on_move/resize`) was too fragile.
Threw all of that out and rebuilt from 4 explicit rules the user gave:

1. Enemy has 3 parts — Head, Body (+ segments), Tail.
2. The 3 parts adjust independently in size AND position (moving/resizing one never touches another).
3. Editing the body template's size affects every one of its segment duplicates.
4. Taper scales the LAST body segment by the taper %, distributed evenly back to the root (first) body
   segment, which never changes — i.e. **linear**, not the old per-step-compounding `pow()`.

New model (`creep_edit_mode.gd`'s `_rebuild_chain_preview()` and friends):
- HEAD, every BODY TEMPLATE (one per distinct body texture — plain chains have 1, hammerhead-style reskins
  have 2), and TAIL are real, independent nodes. The rebuild function **never** writes their `.position`/
  `.size` — the only exception is a true one-time-per-session `_auto_arrange_chain_templates()`, gated by
  `_chain_all_stacked()` (only fires if every part is still literally piled on the head's spot, i.e. never
  touched) — so a manual drag/resize can never be discarded, by anything, ever.
- DUPLICATES (extra segments beyond what real sprites cover) are the only thing ever created/moved/resized:
  fully derived, thrown away and rebuilt from scratch every call. Each hangs directly below whichever
  real/duplicate node precedes it in the chain, at that node's CURRENT position + size — so moving/resizing
  any earlier node drags every duplicate after it along live, with no stored offsets to go stale.
- Taper (0-80%, unchanged range) now scales only duplicates via `1.0 - taper% × (slot-1)/(body_count-1)` —
  linear from the root (slot 1, always 1.0) to the last body slot (slot body_count, exactly `1-taper%`).
  Head, every template's own authored size, and Tail are never scaled by taper.
- `_follow_chain_on_move()`/`_follow_chain_on_resize()` collapsed to one line each (`_rebuild_chain_preview()`
  unconditionally) — the old head-vs-template branching is gone since the rebuild itself is now always safe
  to call from anywhere.
- Runtime formula changed to match: `arena_enemy.gd`'s `_centi_seg_scale(k, n)` (now takes `n` too) uses the
  same linear formula instead of the old `pow(1-taper%, k)` compounding, so the editor's taper shape and the
  arena's actual taper shape are conceptually the same rule (editor node *sizes* were already established
  earlier this session as a pure visualization aid, not synced to runtime pixel-for-pixel — only the 4
  Segments/Spacing/Bend/Taper fields are; see the "no more pixel-matching" note in the 8th-pass entry).

Verified via `godot --headless --check-only` and `--headless --import` (both clean, no script errors) — not
visually tested in the running editor since this environment can't drive the UI; ask the user to re-check
move/resize/taper on a chain creep (e.g. `cent`/`hammerhead`) and report back if anything's still off.

## Changelog — 2026-08-13 (11th pass) — Bug fix: `duplicate(0)` silently dropped the script; templates made fully sticky

Two more regressions from the 10th pass, same session:

- **"Tăng segment không thấy tăng node" (Segments no longer creates any nodes)** — root cause:
  `template_eo.duplicate(0)` (flags=0) does NOT guarantee the clone keeps the template's own GDScript
  attached — `Node.DuplicateFlags.DUPLICATE_SCRIPTS` specifically controls that, and passing 0 excludes it.
  The clone likely came back as a bare `Control` (no `EditableObjectNode` script), so `as EditableObjectNode`
  silently returned `null` for every single duplicate, and the `continue` on a null result meant NOTHING got
  created — no error, just an empty result. **Fix**: use `template_eo.duplicate()` with Godot's own default
  flags (guarantees the script/class comes along) instead of guessing a flags value. Default flags also
  include `DUPLICATE_SIGNALS`, so the template's own `object_clicked`/`transform_ended`/`transform_motion`
  connections may already be cloned along with everything else — the explicit (re)connect calls are now
  wrapped in `is_connected()` guards so they're a safe no-op either way, instead of risking a double-fired
  handler if signals did come along automatically.
- **"Chỉnh vị trí node rồi tăng/giảm segment, vị trí bị giật ngược về vị trí cũ" (reposition a node, then
  change Segments, and it snaps back)** — the 9th pass only stopped templates from re-snapping on a pure
  LAYERS selection click; a genuine Segments/Spacing/Taper edit still unconditionally repositioned every
  template every time (by design, at that point). Per this follow-up report, that's ALSO unwanted — the user
  wants a manually-positioned template to stay put through *any* interaction short of explicitly moving the
  head. Redesigned: templates are now auto-arranged from the head formula **only the first time a given chain
  root is ever built** (new `_chain_templates_initialized: Dictionary`, `root_name -> bool`) — every
  subsequent Segments/Spacing/Taper edit or plain creep-switch only regenerates/repositions DUPLICATES, never
  touching template position again. The one deliberate exception: dragging the HEAD still forces a full
  re-arrange (`_rebuild_chain_preview(true)` from `_follow_chain_on_move()`'s head branch) — moving the
  anchor is still meant to cascade, per the earlier explicit request that motivated that function.
  Duplicates' positions are now computed relative to their OWN template's CURRENT position (a local
  cumulative offset, geometric partial sum of `template.size.y × spacing_mult × taper_ratio(step)`) rather
  than the head's shared cursor — so a duplicate tracks correctly whether its template was auto-arranged or
  manually dragged, consistent with the "duplicates follow their template" behavior added in an earlier pass.

## Changelog — 2026-08-13 (10th pass) — Bug fix, take 2: duplicates now cloned via `Node.duplicate()`, not hand-reconstructed

The 9th pass's aspect-ratio fix (deriving a duplicate's height from its own `_aspect_ratio` instead of a
flat `Vector2 × float`) didn't fully fix it — follow-up report: further-down duplicates got progressively
"ép dẹp ngang và méo sang bên phải" (squashed horizontally, skewed rightward) as Taper increased.

- **Root-caused**: duplicates were being built from scratch every rebuild — a fresh
  `EditableObject.instantiate()` + `init(tex, pos, sz)` — rather than actually being copies of the template.
  `editable_object.tscn`'s `TextureRect` child uses `expand_mode = EXPAND_FIT_WIDTH_PROPORTIONAL`, which
  derives its own rendered height from its CURRENT width + the texture's native aspect on Godot's own layout
  pass — any subtle difference between what a hand-called `init()` sets up vs. what the TEMPLATE's own
  (already-`_ready()`'d, already-through-at-least-one-resize) internal state actually is could diverge and
  compound as the duplicate got resized smaller each taper step.
- **Fix**: duplicates are now created via Godot's own `template_eo.duplicate(0)` — an exact, guaranteed
  pixel-identical clone of the template's ENTIRE state (`.size`, `_aspect_ratio`, the child `TextureRect`'s
  own internal layout state, …) at the moment of cloning. `duplicate(0)` (no flags) deliberately does NOT
  carry over the template's own signal connections/group membership — those are reconnected explicitly
  (`object_clicked`/`transform_ended`/`transform_motion`), matching how every other placed part in this file
  wires up (`_place_creep_eo()`'s own pattern). New `_make_chain_dup_eo()` replaces the old
  `_place_creep_eo()`-based construction; the custom `_chain_dup_size()` aspect-derivation helper from the
  9th pass is removed — no longer needed, since a duplicate now STARTS as an exact copy of a correctly-
  rendering template, so a plain uniform `eo.size = template.size × ratio` can't introduce any distortion the
  template didn't already have.

## Changelog — 2026-08-13 (9th pass) — Bug fix: LAYERS click re-snapped manual body position; duplicate taper size made aspect-safe

Two more user-reported bugs, same session:

- **Bug fix — clicking a different LAYERS row erased a manual template reposition**: "chỉnh xong [body], bấm
  sang tail thì body lại tự nhảy về vị trí lúc đầu". Root cause: `_refresh_chain_controls()` ran on EVERY
  `_active_creep` change — including a pure SELECTION click between rows already in the SAME open chain group
  (head → tail, tail → body, …) — and unconditionally called `_rebuild_chain_preview()`, which repositions
  every TEMPLATE from the head formula regardless of any manual drag the user had just done. New
  `_chain_preview_root` remembers which root the canvas currently reflects; `_refresh_chain_controls()` now
  only rebuilds when `_active_creep`'s root actually CHANGES (a genuine switch to a different chain group) —
  merely selecting a different member of the group you're already viewing no longer touches anyone's
  position. Segments/Spacing/Taper edits (`_on_chain_field_changed()`) and a head drag
  (`_follow_chain_on_move()`) still always rebuild — both call `_rebuild_chain_preview()` directly, unaffected
  by this gate. Also fixed a related leak: switching to a *non*-chain creep previously left the last chain
  group's duplicates sitting on the canvas forever (the early-return before this point never reached the
  cleanup call) — now explicitly clears them and resets `_chain_preview_root` too.
- **Duplicate taper sizing made aspect-ratio-safe**: report of duplicates looking "méo sang một bên" (skewed
  to one side, losing their original aspect) while dragging Taper. The `eo.size = template_eo.size * ratio`
  multiply itself is uniform (Vector2 × float scales both axes by the same factor) so couldn't distort a
  duplicate on its own, but it inherits whatever aspect the TEMPLATE's own authored size happens to have —
  if that's ever slightly off from the texture's true native ratio, the mismatch would carry through, and
  compound visually as duplicates shrink. New `_chain_dup_size(eo, template_eo, ratio)` derives HEIGHT from
  the duplicate's own `_aspect_ratio` (computed from its actual texture dimensions in `EditableObjectNode.
  init()`, same texture as the template) instead of blindly scaling the template's `.size.y` — guarantees a
  duplicate always renders at its texture's true aspect regardless of what the template's own W/H says.
  Applied at both call sites (the full rebuild's duplicate-creation loop and
  `_resize_chain_dups_from_templates()`).

## Changelog — 2026-08-13 (8th pass) — Bug fix: `.scale` broke LAYERS resize/selection; taper/size now real `.size`, not a transform trick

User report: "phần layer đang bị ko hoạt động khớp với chain" — clicking a LAYERS row could no longer resize
that part, and body-segment duplicates seemed to vanish when selecting head or tail specifically.

- **Root cause**: the 7th pass's runtime-size-matching applied `eo.scale`/`eo.pivot_offset` directly to the
  REAL template nodes (head + each texture role's first use) to visually shrink them toward the true in-game
  size. `EditableObjectNode`'s drag-resize handles and click hit-testing were never built with a `.scale`
  transform in mind — they compute against the node's plain `.size`/`.position`, so once a template had
  `.scale != 1` applied, its handles/hit-box stopped lining up with what was actually rendered on screen,
  reading as "can't resize" and, apparently, parts becoming unselectable/appearing to vanish.
- **Fix — `.scale` removed from the CHAIN feature entirely**, on both templates and duplicates:
  - **Templates** (head + each role's first real use) are now **never** resized/rescaled by this feature —
    only repositioned, exactly like before any of the taper/size work started. Full normal resize/drag/select
    behavior restored, unconditionally.
  - **Duplicates** now get a REAL `.size` (`eo.size = template.size * taper_ratio`, `eo._sync_rect_size()`)
    instead of a `.scale` trick — safe because duplicates are never saved (`_save_layout()` only ever
    iterates `_all_creep_names`, which duplicates are deliberately excluded from) and never individually
    resized by a user, so there's no "authored value vs. cosmetic override" conflict to protect against for
    them the way there was for templates.
  - Net effect, matching the explicit spec ("click vào body thì chỉnh node đầu tiên, các nốt khác trong
    segment sẽ scale theo node đó và taper"): clicking/resizing a template (the "first node" for its texture
    role) is a completely normal, unrestricted edit; every one of ITS duplicates re-derives its own size as
    `template.size × (1 − taper%)^steps` (`steps` = how many chain positions behind the template that
    specific copy sits), automatically, the moment the template's W/H changes (new `_follow_chain_on_resize()`
    hook on `_apply_spin_to_selected()`) or the CHAIN section's own fields change.
  - The 7th pass's "pixel-accurate to a real spawn" width/size matching (`ENEMY_DEFS["size"]`-derived
    `centi_width`) is **dropped** — it's what required scaling the head, which is exactly what broke
    resizing. Editor sizes are back to being purely author-controlled again, same as every other placed part.
- **`_follow_chain_on_resize()`** mirrors the existing `_follow_chain_on_move()`'s 2-case split: resizing the
  HEAD triggers a full `_rebuild_chain_preview()` (repositions + resizes the whole chain against the head's
  new size); resizing a body/tail TEMPLATE only resizes its own duplicates (`_resize_chain_dups_from_templates()`)
  — position for those isn't live-recomputed on every resize keystroke (stays at its last full-rebuild
  position until the next Segments/Spacing/Taper edit or creep switch) — a disclosed, purely cosmetic gap,
  not worth the extra complexity for how rarely it'd be visible mid-drag.

## Changelog — 2026-08-13 (7th pass) — CHAIN preview: real taper shrink, drag-follow, pixel-accurate runtime size

Three follow-up requests on the CHAIN feature, same session:

- **Taper actually shrinks bodies now** (was position-only before this pass — the gap between nodes grew but
  every node stayed the SAME size, contradicting the whole point of "taper"). Slider range changed **0–90 →
  0–80** (per spec: 0 = 0% shrink, 80 = 80% per-step shrink). Applied as a pure **visual** transform —
  `eo.scale` (centered via `eo.pivot_offset = eo.size * 0.5`, per this project's own Pivot Point Rule) —
  deliberately NOT via `eo.size` itself, since `.size` IS what `_save_layout()` persists into
  `creep_layout.cfg` (and feeds `tools/downscale_enemies.gd`'s bake); `.scale`/`.pivot_offset` aren't part of
  that saved schema, so this stays purely cosmetic no matter how many times Save Layout is clicked. New
  `_chain_scaled_names` + `_reset_chain_scale()` (called at the top of every rebuild) put every touched node
  back to `scale=1, pivot=0` first, so a part doesn't stay stuck visually shrunk after switching creeps or
  dialing Taper back to 0.
- **Duplicates now follow when you reposition a chain part** — previously the whole layout only recomputed on
  a Segments/Spacing/Taper edit or a creep switch; dragging/spinning a part's X/Y did nothing until the next
  unrelated CHAIN edit. New `_follow_chain_on_move()`, hooked into `_on_pos_spin_changed()` /
  `_on_transform_motion()` / `_on_transform_ended()`, no-ops outside an active CHAIN section. Two cases,
  handled differently on purpose:
  - **Head dragged** → full `_rebuild_chain_preview()` (the whole chain is anchored on the head, so this is
    the correct "everything follows" response).
  - **A body/tail TEMPLATE dragged/spun** → does **NOT** run a full rebuild (that would instantly recompute
    the template's own position from the head formula and erase the edit the user just made). Instead only
    its own duplicate copies move, by the SAME offset it captured at creation time (new `_chain_dup_offset`,
    consumed by new `_reposition_chain_dups_from_templates()`) — the template's manual position is respected,
    its clones just tag along.
- **Editor preview now matches a real spawn pixel-for-pixel** (previously it used each part's own
  `creep_layout.cfg`-authored W/H, which for the new Atlantic sets is a flat 60px-wide convention chosen for
  editor legibility — the REAL runtime chain (`_load_centipede()`/`_centi_width` in `arena_enemy.gd`) never
  reads that field at all for `"centipede"`-behavior parts; it derives width from `ENEMY_DEFS["size"]` (the
  hit-radius stat) × 1.05 × `CENTI_WIDTH_MUL`, often 25–45% smaller than the authored editor size).
  Confirmed with the user this should scale the WHOLE chain including the head (previously untouched) to
  match, accepting that parts now look visibly smaller in Creep Edit than before — an accurate reflection of
  their small in-game footprint, not a bug. Every part (head, templates, duplicates, tail) now gets an
  additional `centi_width / eo.size.x` normalization factor multiplied into its taper scale, and the
  spacing/cursor-advance math switched from `eo.size.y` to a locally-computed `runtime_along_len()` (mirrors
  `arena_enemy.gd`'s `_seg_along_len()` exactly: `centi_width × texture_h/texture_w`). One disclosed
  simplification: the real runtime's head neck-overlap adjustment (`CENTI_HEAD_OVERLAP`, ~20px pulled into
  the first body segment) isn't replicated — the editor starts body1 flush at the head's own along-length,
  a minor, purely cosmetic difference at the neck join only.
- The `_position_chain_members()` fallback (used only when a chain group's parts can't be classified into
  body/tail roles — a hand-added `CHAIN_PARTS` entry that doesn't follow Head/Body`<N>`/Tail naming) was NOT
  extended with runtime-size matching — out of scope, no real def hits that path today.

## Changelog — 2026-08-13 (6th pass) — CHAIN "Segments" now spawns REAL duplicate body nodes, not just repositioning

Follow-up to the 5th pass (per request: "khi tăng segment thì tăng node body lên, như lúc bạn làm với
preview ấy, nhưng làm trên node body thật" — raising Segments should actually add more body nodes, the way
the earlier ghost-preview version did, but using real nodes this time). The 5th pass's "just reposition
whatever real parts already exist" was a disclosed simplification that under-delivered for exactly this case
— e.g. `atlantic_centipede`/`spermwhale2`/the original centipede only ever have 1 real "body" `EditableObjectNode`
no matter how high Segments goes.

- **New**: when a chain's `mid_count` (`Segments − 2` if a tail exists, else `− 1`) exceeds the number of
  distinct real body textures, `_rebuild_chain_preview()` now instantiates real DUPLICATE
  `EditableObjectNode`s via the exact same `_place_creep_eo()` helper every normal placed part uses — same
  texture, same size, same interactivity — named `"<template> #2"`, `"<template> #3"`, … Each middle slot's
  texture assignment mirrors `arena_enemy.gd`'s own `_centi_tex_for()` exactly (body1, body2, …, clamping to
  the LAST body texture once the def runs out of distinct ones — same rule the real runtime chain uses), so
  a def like `hammerhead` (2 body textures) fills slots 1-2 from its own real body1/body2, then repeats body2
  for every slot beyond that.
- Duplicates are fully torn down and rebuilt from scratch on every call (segment-count change, spacing/taper
  edit, or creep switch) — always exactly matches the CURRENT `Segments` value, no incremental add/remove
  bookkeeping. New `_chain_dup_names` tracks the live set for cleanup; new `_clear_chain_dups()` destroys them
  (called at the top of every rebuild, and from `_close()` — they're deliberately excluded from
  `_all_creep_names`, so `_update_gameplay_visibility()`'s "hide every known creep for gameplay" pass doesn't
  know about them and would otherwise leave them visible outside the editor).
- **Deliberately excluded from `_all_creep_names`** (and therefore from `_save_layout()`, `_scan_creeps()`,
  and the ENEMIES palette) — they're pure derived output of `centi_segments`, not their own authored data;
  persisting them would just create stale orphaned entries the next time Segments changes. `creep_layout.cfg`
  gains no new keys from this feature at all.
- `_position_chain_members()` split out as the plain "reposition, no duplication" fallback — still used when
  a chain group's parts can't be classified into body/tail roles (e.g. a hand-added `CHAIN_PARTS` entry that
  doesn't follow the Head/Body`<N>`/Tail naming convention).

## Changelog — 2026-08-13 (5th pass) — CHAIN preview simplified: reposition the REAL nodes, no ghost copies at all

The 4th pass's ghost-copy preview (translucent duplicate `TextureRect`s drawn alongside the real parts) was
pushback-flagged as needlessly complicated — an intermediate offset-lane variant was tried and discarded same
session before landing here. Final approach, much simpler: **no extra preview nodes exist at all.**
`_rebuild_chain_preview()` just REPOSITIONS the REAL body/tail `EditableObjectNode`s (already resizable/
draggable/selectable — completely untouched otherwise, no hide/restore bookkeeping, no `Array[Control]`
tracking) to sit where they'd actually line up below the head, in head → body1 → body2 → … → tail order
(`_chain_group_order`, from the 2026-08-12 naming-convention auto-grouping). This is safe to do
unconditionally, not just "while a preview is active": `creep_layout.cfg`'s `"pos"` for a `"centipede"`-
behavior part has **zero gameplay effect** — the real runtime chain (`_update_centipede_chain()` in
`arena_enemy.gd`) computes every segment's position procedurally from the enemy's own transform each frame,
never reads `creep_layout.cfg` position for centipede-type enemies at all — so the auto-aligned position IS
just the part's real, permanent, normally-savable position now; there's no "preview vs. real" state to
reconcile. One disclosed approximation: this lines up whatever DISTINCT real parts actually exist, in
sequence — it does NOT synthesize `Segments`-many synthetic copies of a single reused body texture (e.g. the
original 10-segment centipede has only 1 real "body" EO to move, not 8) — good enough to sanity-check order/
spacing/taper direction at a glance, not a segments-accurate node count.

## Changelog — 2026-08-13 (4th pass) — Bug fix: CHAIN preview doubled body/tail; Creep Info gets per-map tabs

- **Bug fix — "2 tail, 1 mờ 1 rõ" in Creep Edit** (`creep_edit_mode.gd`): the 3rd pass's new ghost CHAIN
  preview (built to fix the PREVIOUS bug — Segments/Spacing/Bend/Taper having no visible effect) drew ghost
  copies of EVERY non-head segment, including body/tail slots that ALREADY have their own real, separately-
  placed `EditableObjectNode` sitting at its own fixed `creep_layout.cfg` position — so any chain creep at
  its default segment count showed both at once (the real one at full opacity, the ghost at 50%, stacked
  almost exactly on top of each other since both start near the same default placement). Fix: new
  `_set_chain_real_parts_visible(root_name, vis)` hides every REAL body/tail part belonging to the active
  chain root the moment `_rebuild_chain_preview()` is about to draw ghosts for it, restored the moment the
  preview clears (creep switch, CHAIN section hidden, or editor close — new `_chain_preview_root` remembers
  which root to restore, mirroring how `_preview_vortexes` already gets torn down in `_close()`). Only
  rendering is affected — the real parts are still fully there in `creep_layout.cfg` and still selectable via
  the LAYERS panel for their own transform/firepoint editing, just not drawn on canvas while their ghost
  stand-in is showing. (Root-caused via careful re-read of `arena_enemy.gd`'s actual runtime draw code —
  `_centi_tex_for()`/`_draw_centipede()` only ever draw exactly ONE tail per chain; the duplicate was 100%
  a Creep Edit canvas artifact, never present in real gameplay.)
- **Creep Info panel gets per-map tabs** (`creep_info_panel.gd`), on request — a row of tabs (**All / Space /
  Electric / Volcanic / Atlantic**) added directly below the Save/Close row, filtering the (previously single
  flat ~70-row) list down to one map's own roster. `_map_id_for(id, def)` infers ownership from the def's
  `"icon"` path prefix, reusing `creep_edit_mode.gd`'s own `MAP_REGISTRY` as the single source of truth (the
  SAME list the Creep Edit "Map:" dropdown already uses) — so this stays correct automatically as creeps get
  moved between per-map folders, no separate id→map table to maintain in sync. The 3 bosses are the one
  exception: their icons stay under `assets/bosses/<name>/` (deliberately excluded from the 2026-08-12 per-map
  asset reorg), so ownership can't be inferred from icon path for them — hardcoded `BOSS_MAP_OVERRIDE`
  (`metalfly`→Electric, `elephant`→Volcanic, `chromeleon`→Space) instead, from that reorg's own wave-timeline
  audit. Tab click = `_populate()` re-run with the filter applied; active tab highlighted via font color, same
  convention as the existing Save (green) / Close (red) buttons — no new StyleBox machinery for a strip this
  small. Scroll area's reserved height bumped (`psize.y - 150` → `-182`) to make room for the new row.
- Verified: `godot --headless --check-only`/`--import` clean. Runtime smoke-testing `_map_id_for()` against
  the real `ENEMY_DEFS` hit the same bare-`--script`-can't-see-autoloads wall as prior passes (any script
  touching `arena_wave_director.gd`/`arena_enemy.gd` fails to even compile outside a full project boot) —
  relied on the full-boot `--check-only --path .` pass plus manual verification of the icon-prefix logic
  (identical pattern to Creep Edit's already-verified-working `_folders()` map filter) instead.

## Changelog — 2026-08-13 (3rd pass) — Bug fix: "Save Chain" crashed (const ENEMY_DEFS is read-only since Godot 4.4); CHAIN section gets a live canvas preview

User-reported bug: Creep Edit's CHAIN "Save Chain" button threw `Invalid assignment on read-only value (on
base: 'Dictionary')`, and separately, raising "Segments" to 6 for `atlantic_centipede` ("cent") never showed
more than 1 body sprite anywhere.

- **Root cause of the crash**: `arena_wave_director.gd`'s `ENEMY_DEFS` was declared `const`. As of Godot 4.4,
  a `const` Dictionary/Array literal — and everything nested inside it — is automatically frozen read-only.
  `apply_chain_overrides()`'s `entry["centi_segments"] = ...` (mutating a per-id sub-dict pulled straight out
  of that const) hit the freeze and threw. **This silently also broke the pre-existing Creep Info dev panel's
  Save button** (`creep_info_panel.gd`'s `apply_overrides()`, same "mutate a nested dict pulled from ENEMY_DEFS
  in place" pattern) whenever v1 (`arena_wave_director.gd`, not v2) was the active director — v2
  (`arena_wave_director_v2.gd`) never hit this because its OWN `ENEMY_DEFS` is a plain instance `var` populated
  via `v1_defs.duplicate(true)`, and `duplicate()` doesn't carry over the read-only flag. **Fix**: `const
  ENEMY_DEFS` → `static var ENEMY_DEFS` (same file-scope "one shared dict, same `WaveDir.ENEMY_DEFS` access
  syntax" semantics, just no longer frozen) — a one-line declaration change, every read-site untouched.
- **Root cause of "Segments=6 still shows 1 body"**: not a data bug at all — the value WAS saving correctly
  (once the crash above is fixed) and DOES apply at the next real spawn (verified: default `atlantic_centipede`
  has `centi_segments: 3`, i.e. exactly 1 middle "body" slot, which is precisely what "still only 1 body"
  describes). The actual gap: Creep Edit's canvas only ever renders the handful of individually PLACED sprites
  (head/body/tail as separate `EditableObjectNode`s) — the real N-segment chain is assembled procedurally at
  RUNTIME inside the arena (`arena_enemy.gd`'s `_update_centipede_chain()`/`_draw_centipede()`), which Creep
  Edit's canvas has never simulated. Changing Segments/Spacing/Bend/Taper always had a real effect — just
  invisible in the editor itself, only checkable via an actual spawn (Quick Spawn).
- **Fix (on request): live CHAIN preview in the canvas** — new `_rebuild_chain_preview()`, called on every
  Segments/Spacing/Bend/Taper edit (`_on_chain_field_changed()`) and whenever the active creep changes
  (`_refresh_chain_controls()`). Draws a translucent (50% alpha) "ghost" stack of `TextureRect`s directly below
  the placed head sprite — reuses the CURRENT (possibly still-unsaved) spinbox/slider values and the exact
  same along-length/taper/spacing formulas as the real runtime chain (`_seg_along_len`/`_centi_seg_scale` in
  `arena_enemy.gd`, duplicated here as local lambdas since there's no live enemy instance to call them on), so
  it's an accurate preview, not a rough sketch. **Deliberately a static vertical stack, no bend simulation** —
  bend only matters mid-turn, which doesn't exist in a stationary editor preview; Bend Lock still has zero
  visible effect on this preview specifically (by design, not a gap — it only ever affects a live chain that's
  actually turning). Ghost nodes are cleaned up on creep switch, section hide, and editor close (`_close()`,
  same lifecycle as the existing vortex-preview nodes it's modeled on) — they live on `_objects_container`,
  which persists past close, so leaving them unmanaged would leak stale ghosts into the next open.
- Verified: `godot --headless --check-only`/`--import` clean. Direct-mutation runtime verification (bare
  `--script` smoke tests) is blocked by a pre-existing tooling limitation — `--script` mode never registers
  autoload singletons, so any script referencing `GameManager` (nearly all gameplay scripts) fails to compile
  under it regardless of correctness — relied on the full project boot (`--check-only --path .`, which DOES
  register autoloads) plus the well-documented, standard nature of the const→static-var fix instead.

## Changelog — 2026-08-13 (2nd pass) — Atlantic's first enemy roster wired in: 12 sea creatures, chain runtime generalized beyond centipede

User dropped 27 sprites into `assets/map/atlantic/enemies/` (7 simple + 5 multi-node "Head/Body1/Body2/Tail"
sets, per the naming convention the same day's earlier Creep Edit auto-grouping pass added). Wired end-to-end
(`ENEMY_DEFS`, `creep_layout.cfg`, Creep Edit's `CHAIN_PARTS`, Quick Spawn) — **not** into `atlantic.json`'s
wave timeline, per explicit request ("chỉ wire dữ liệu, để bạn tự dàn wave"; still empty, unchanged).

- **Chain runtime generalized off "electric centipede only"** (`arena_enemy.gd`) — `_load_centipede()` used
  to hardcode exactly 3 `res://assets/map/electric/enemies/...` paths; now reads `"centi_head_icon"` /
  `"centi_body_icons"` (**Array**, new) / `"centi_tail_icon"` from the def, defaulting to those same 3 paths
  (`CENTI_HEAD_ICON_DEFAULT`/etc.) so the original `"centipede"` entry needed zero changes. `_centi_body_tex`
  (single Texture2D) → `_centi_body_texs: Array[Texture2D]` + new `_centi_tex_for(k, n)` picks the right
  texture per middle-segment index (body1 for k=1, body2 for k=2, …, clamping to the last one if a def
  supplies fewer body textures than it has middle slots — the original centipede's 1-texture-for-8-slots
  case). Per-joint follow SPACING (`_update_centipede_chain()`) is now derived live from whichever texture
  that specific joint draws (`_seg_along_len(_centi_tex_for(k,n))`) instead of one precomputed scalar — needed
  because hammerhead/killerwhale/shark_elite's body1 and body2 are genuinely different-sized sprites, unlike
  the original centipede's one repeated body texture. `_centi_spacing` is now used ONLY for the head's own
  neck-shift formula (still needs a single reference value); everything else reads per-joint.
- **12 new `ENEMY_DEFS` entries** (`arena_wave_director.gd`), stats estimated by analogy to existing
  similar-role creeps (no design doc for these yet — flagged, retune via Creep Info panel):
  - Simple (`"behavior": "chase"`): `shark`, `killer_whale`, `whale`, `spermwhale`, `atlantic_squid`
    (deliberately a NEW id — the existing tentacle `"squid"` on Electric was left untouched, per explicit
    correction), `stingray`, `stingray_elite`.
  - Chain (`"behavior": "centipede"`, `"lvl": true` matching the original): `atlantic_centipede` (files:
    `cent head/body/tail.png`, 3 segments), `hammerhead` (`hammerhead head/body1/body2/tail.png` + its own
    dedicated `hammerhead.png` icon, 4 segments), `killerwhale` (`killerwhale head/body1/body2/tail.png`, no
    separate icon — reuses the head sprite like the original centipede does, 4 segments; distinct from the
    SIMPLE `killer_whale` id above — the artist supplied both a plain "killer whale.png" AND a segmented
    "killerwhale …" set as two different creatures), `shark_elite` (`shark elite head/body1/body2/tail.png`,
    no separate icon, 4 segments; distinct from the simple `shark` id — NOT wired into the game's Elite/
    Champion creep auto-promotion mechanic, just a literal stronger reskin), `spermwhale2` (`spermwhale2
    head/body/tail.png` + its own `spermwhale2.png` icon, 3 segments; distinct from the simple `spermwhale`
    id — same "two versions of one animal" pattern as killer whale).
- **`creep_layout.cfg`**: 27 new `[creeps]` entries (one per sprite file), `"parent"` set to each chain set's
  head for the body/tail parts (matching `CHAIN_PARTS` below), default `pos`/`z_index` matching every other
  entry's convention, `size` width fixed at 60 (project convention) with height computed from each PNG's own
  aspect ratio. **Gotcha hit while authoring this programmatically**: `ConfigFile` requires any key containing
  a space to be `"quoted"` (`"killer whale"={`, `"cent head"={`, …) — an unquoted multi-word key silently
  fails to parse as that key at all (first attempt wrote all 27 unquoted; a `ConfigFile` load+read-back smoke
  test caught every space-containing key coming back empty before this was saved for real).
- **`creep_edit_mode.gd`'s `CHAIN_PARTS`** extended with all 20 new chain part names → their `ENEMY_DEFS` id,
  so the CHAIN section (segments/spacing/bend/taper) recognizes and edits these 5 new sets too, same as
  centipede.
- **`arena_debug_spawn.gd`'s `QUICK_SPAWN_ORDER`**: all 12 new ids added — with no wave timeline yet, Quick
  Spawn is the only in-game way to summon them for now.
- Verified: `godot --headless --check-only` (clean) + `--import` (all 27 new textures — none had `.import`
  sidecars yet since the user added them outside the editor — reimported clean) + a standalone `ConfigFile`
  load/read-back smoke test confirming every one of the 27 `creep_layout.cfg` keys resolves with the correct
  `parent` chain and size.

## Changelog — 2026-08-13 — electric→electric asset folder rename; Creep Edit map dropdown, taper slider, auto-grouping

Follow-up to the 2026-08-12 entry below, same session's feature set extended per explicit request:

- **`assets/map/electric/` renamed to `assets/map/electric/`** — "to match the code": `meta_manager.gd`'s
  `MAP_DEFS`/`hub_screen.gd`'s `MAP_LIST` have always displayed the `"electric"` map_id as **"Electric"**
  (`elecforest.json`'s own name is the same theme), so the on-disk asset folder being literally named
  "electric" was the odd one out. Scope was explicitly limited to the **`assets/map/` asset tree only** — the
  `map_id` string `"electric"` itself (meta_manager/arena.gd/hub_screen/dock_binder/…) and the **script**
  folder `scripts/gameplay/electric/*.gd` are UNCHANGED, on request; only the asset directory moved. `git mv
  assets/map/electric assets/map/electric` (whole tree in one shot, ~209 tracked files: enemies/, landmark/,
  maptile/, SeaWaterMaterial/, watertile/) + repo-wide `res://assets/map/electric/` → `.../electric/` string
  replace across every `.gd`/`.cfg`/`.import` that referenced it (~20 files, ~90 occurrences — `creep_layout.
  cfg`, `arena_wave_director.gd`'s `ENEMY_DEFS`, `meta_manager.gd`'s `RESCUE_CHARACTER_DEFS`, every
  `electric_*.gd`/`atlantic_*.gd` script that reuses Electric's temple/trees/ground assets, `.import` sidecars'
  `source_file=`). Verified clean with a repo-wide `git grep -F "assets/map/electric"` sweep (zero hits) +
  `godot --headless --check-only`/`--import` (no errors).
- **Creep Edit "Map:" dropdown** (`creep_edit_mode.gd`) — new `MAP_REGISTRY` (id/display-name/folder, mirrors
  `meta_manager.gd`'s own map list) drives a dropdown above the ENEMIES grid: **Space / Electric / Volcanic /
  Atlantic**. Selecting one now shows **only that map's own enemy folder** — supersedes the 2026-08-12 fix's
  "merge every map's folder into one palette" behavior (`_folders()` now returns exactly ONE folder, picked
  from `MAP_REGISTRY` by `_selected_map_id`, not a merged array), per explicit correction: "mỗi map sẽ hiện
  đúng enemy set của map đó". `weapon_edit_mode.gd` (the other `_folders()`/`_folder()` override, for
  `assets/weaponry/`) gets a new `_show_map_selector() -> false` override so its palette has no dropdown at
  all — the per-map split is a creep-only concept.
- **CHAIN section: Taper slider** — new 4th control (an `HSlider`, not a SpinBox like the other 3 — explicitly
  requested as a literal drag slider, mirrors the existing Zoom slider's label+slider+"NN%" row layout), 0–90%.
  Progressively shrinks each body node relative to the one before it toward the tail (`arena_enemy.gd`'s new
  `_centi_seg_scale(k) := pow(1 - taper/100, k)` — k=0 is the head, always scale 1.0 by construction; body1
  is the first node that CAN shrink, matching the request's own example "body 1 gần head, body 2 sẽ nhỏ hơn
  body 1"). Applied to both the DRAW size (`_draw_centi_seg()`'s `dw`/`dh` × `scale_mul`) and the FOLLOW
  SPACING per joint (`_update_centipede_chain()`'s `sp` is now computed per-`k`, `_centi_spacing ×
  _centi_seg_scale(k)`, cumulative for the initial-fill branch too) — without the spacing scaling down in
  lockstep, a tapered tail would visually detach with growing gaps between its now-smaller segments.
  `taper_pct = 0` (the default, and every existing def's implicit value) reproduces the exact pre-taper
  behavior bit-for-bit (`pow(x, k)` with the guard `if _centi_taper_pct <= 0.0: return 1.0`). New def field
  `"centi_taper_pct"`, same sparse-override/live-apply plumbing as the other 3 CHAIN fields
  (`creep_chain_overrides.cfg` / `apply_chain_overrides()`).
- **Naming-convention auto-grouping** — sprite files named `<Prefix>Head` / `<Prefix>Body<N>` / `<Prefix>Tail`
  (case-insensitive suffix — e.g. `ViperHead.png`/`Viperbody1.png`/`VIPERBODY2.png`/`vipertail.png`) are now
  automatically grouped into ONE enemy, ordered head → body1 → body2 → … → tail, with **no manual parenting
  step** (there wasn't actually a UI for that before this — parenting could previously only ever come from a
  value already sitting in `creep_layout.cfg`'s `"parent"` field, hand-edited or never set; centipede's own 3
  parts, discovered while building this, had `"parent": ""` for all three — i.e. were NEVER actually grouped
  in the editor UI up to this point, despite `CHAIN_PARTS` already existing). New `_parse_chain_name()`
  (`RegEx` `(?i)^(.+?)(head|tail|body(\d*))$`) + `_auto_group_chain_names()` (called after every
  `_scan_creeps()` — initial open AND every "Map:" dropdown change) populate `_creep_parents` (skips any name
  that already has an explicit parent from a previous save — auto-detection only fills in gaps, never
  overrides saved data) and a new `_chain_group_order` dict used by `_refresh_layer_list()` to order the
  LAYERS panel's children correctly (previously plain alphabetical via `_all_creep_names.sort()`, which would
  NOT put "Body2" after "Body1" the way a human reads it once names hit double digits or mixed casing).
  `_build_creep_buttons()` also now skips any parented name — a detected (or pre-existing, e.g. squid's
  manually-parented squid-1..8 tentacles) group shows as **1 palette cell** (the root), not N — its
  head/body/tail parts are reached via the LAYERS panel once the root is active, matching "sắp xếp chung vào
  1 enemy" literally. **Scope note, disclosed**: this is an EDITOR-ONLY convenience (palette + LAYERS
  grouping/ordering) — it does not give a newly-detected group any actual in-game chain BEHAVIOR. Only
  `"centipede"` (`CHAIN_PARTS`) has that runtime wiring (the segmented-body draw/collision/movement code in
  `arena_enemy.gd`); a brand-new `<Prefix>Head/Body/Tail` set would organize correctly in Creep Edit but
  still needs its own `behavior` case wired up to actually crawl/chain in the arena.

## Changelog — 2026-08-12 — Per-map enemy/landmark asset split; Creep Edit CHAIN section (centipede segments/spacing/bend-lock)

- **Per-map enemy sprite reorg** — `assets/enemiesHD/` was one shared pool for every map; enemies exclusive to
  one map's own wave timeline now live under `assets/map/<map>/enemies/`, physically separated per map (per
  explicit request: "map mặc định dùng được hết enemies của các map khác, các map khác dùng set enemies độc
  lập" — the default/space map still reads whatever path a def's icon points at, so it transparently keeps
  using every other map's roster; electric/volcanic/atlantic each own only what THEIR OWN wave JSON actually
  spawns). Cross-referenced every enemy `"type"` in `levels/arena/elecforest.json` (electric), `vocalnic.json`
  (volcanic), `atlantic.json` (empty — no roster authored yet, folders created but empty) and expanded every
  `"fleet:X"` entry against `fleet_layout.cfg` to resolve real enemy ids before deciding ownership:
  - **Electric** (`assets/map/electric/enemies/`, 27 files): animalhornet, beamer, bee/bee_dive (animalbee.png),
    bug, centipede (head/body/tail), diver (kingfisher.png), dragonfly, fly (flie1/flie2 flap frames),
    missile, spider, squid (Squid-body + squid-1/2/3/5/7/8), swarm, and the whole Kingdom1/Kingdom2-fleet
    sentinel family (sentinel, sentinel 1/2/3/4, sentinelleader).
  - **Volcanic** (`assets/map/volcanic/enemies/`, 4 files): magma1, magma3, magma4, magma6 — note magma1 is
    ALSO pulled into one electric fleet slot (`A.Hornet.Row.10`) as a mixed-formation guest; kept volcanic-owned
    (its thematic home) rather than duplicated — electric's fleet just references the volcanic path directly,
    which works fine, it's only "independent ownership" that's map-scoped, not "no cross-map references ever".
  - **Bosses untouched, on request**: `assets/bosses/<name>/` (elephant/chromeleon/metalfly/nautilus/scorpion)
    was explicitly EXCLUDED from this move — too many per-boss hardcoded `.sheet.json`/shader paths for the
    risk to be worth it here; only regular creep sprites in enemiesHD moved.
  - Every reference updated in lockstep: `ENEMY_DEFS` icon paths (`arena_wave_director.gd`), `boss_scorpion.gd`'s
    own separate minion table (fly/bug/bee — a v1/legacy roster, unrelated to the map split but pointing at the
    same physical files), `creep_layout.cfg`'s per-part `"path"` fields (31 entries — this file is the
    authoritative source Creep Edit/`_load_icon()` sub-parts actually load from, independent of ENEMY_DEFS'
    own icon field), `arena_enemy.gd`'s hardcoded centipede texture `load()` calls (bypass `_resolve_sprite()`
    entirely, so these needed a direct edit), `arena_enemy_manager.gd`'s debug `spawn_bee()` fallback def, and
    `game_manager.gd`'s custom-cursor `CURSOR_OPTIONS` (sentinel/magma3/squid_body entries reused these sprites
    as cursor icons). Verified with a repo-wide `git grep -F` sweep for every moved filename's old path (clean)
    plus `godot --headless --check-only` and `--headless --import` (all 31 textures reimported clean, `.import`
    sidecars' `source_file=` fields updated to match).
  - **Landmark assets** also split into a new `assets/map/<map>/landmark/` subfolder (previously loose files
    directly in `assets/map/<map>/`): electric's `temple.*`/`mechanic.*`/`constructor.*` (+ unused `_0/_1/_2.jpg`
    thumbnail variants — confirmed unreferenced anywhere, moved along for tidiness only), volcanic's
    `temple.*`/`temple_mark_ref.png`/`engineer.*`/`psyker.*`, atlantic's `temple_mark_ref.png` (atlantic has no
    rescue-character ruin — reuses ELECTRIC's `temple.glb`/`.png` directly for its temple boss, per the
    2026-08-06 Atlantic map changelog — nothing to move for that half). 43 files updated across
    `meta_manager.gd` (`RESCUE_CHARACTER_DEFS`), each map's own `*_temple_layer.gd`/`*_landmark_mark.gd`, and 5
    one-off `tools/bake_*`/`tools/inspect_*`/`tools/normalize_*` scripts. `res://assets/ruin/Scholar.glb/.png`
    (the rescue-fallback character) was deliberately left alone — it's a shared/generic fallback, not owned by
    any one map.
  - **Creep Edit's asset palette regressed by this move, then fixed**: `creep_edit_mode.gd`'s `_scan_creeps()`
    only ever scanned the single `ENEMIES_FOLDER` const — any sprite moved out of it would silently vanish
    from the palette. New overridable `_folders() -> Array[String]` hook (default: `[_folder()]` +
    `MAP_ENEMY_FOLDERS`) — `_scan_creeps()`/`_creep_icon_tex()`/`_load_or_create_creep()` all now try every
    folder in priority order, deduped by name. `weapon_edit_mode.gd` (the other subclass of creep_edit_mode.gd,
    reusing the same editor for `assets/weaponry/`) overrides `_folders()` back down to `[_folder()]` — the
    per-map split is a creep-only concept, weapons still have one shared folder.
- **Creep Edit "CHAIN" section** (new, `creep_edit_mode.gd`) — requested control for multi-node/segmented
  enemies (centipede today; architecture is generic for any future chain-type enemy, not centipede-specific).
  Centipede's body was previously 3 hardcoded consts in `arena_enemy.gd`: `CENTI_SEGMENTS` (10, fixed node
  count), `CENTI_MAX_BEND` (PI×0.5 = 90°, the joint rotation lock the request called out specifically), and an
  implicit 1:1 sprite-derived spacing (no "offset between nodes" knob at all). All 3 are now per-def
  overridable fields read in `configure()` (`_centi_segments`, `_centi_max_bend`, `_centi_spacing_mult` —
  defaults unchanged: `CENTI_SEGMENTS_DEFAULT`/`CENTI_MAX_BEND_DEFAULT`/`1.0`), consumed by
  `_load_centipede()`/`_update_centipede_chain()` exactly where the old consts were.
  - **UI**: opening Creep Edit and selecting any of centipedehead/centipedebody/centipedetail (`CHAIN_PARTS`
    dict, mirrors `_load_centipede()`'s 3 hardcoded filenames) now shows a "CHAIN (multi-node)" section below
    TRANSFORM — **Segments** (3–40), **Spacing ×** (0.3–3.0, the "offset between nodes" — >1 opens a gap, <1
    overlaps tighter), **Bend lock (deg)** (10–180, the rotation-lock request — was fixed at 90°). Save Chain /
    Reset buttons, same shape as the existing HP/XP/Move/Shoot Creep Info workflow.
  - **Persistence**: sparse-override cfg `res://creep_chain_overrides.cfg`, new `id → {centi_segments,
    centi_bend_deg, centi_spacing_mult}` dict, applied to `ENEMY_DEFS` via static `apply_chain_overrides()`
    (mirrors `creep_info_panel.gd`'s `apply_overrides()` pattern exactly) called from both wave directors'
    `_ready()`. **Deliberately a SEPARATE file from `creep_info_overrides.cfg`**, not reusing Creep Info's
    existing one — Creep Info's own Save rebuilds its whole "overrides" dict from only ITS OWN visible
    rows/fields on every save, which would silently drop these 3 new keys the next time someone saves an
    unrelated HP/XP edit in that other panel if they shared a file.
  - Takes effect on the next spawn of that type (both the live running director's `ENEMY_DEFS` and the
    class-level default are updated immediately on Save; already-alive enemies keep whatever chain they were
    built with — `_load_centipede()` only runs once per instance, not re-read per frame).
  - **"vũ khí Viper" scope note**: the request cited "vũ khí viper" (the Viper player weapon) alongside
    centipede as an example of "nhiều node" — confirmed with the user this was illustrative only (centipede's
    chain logic literally is a Viper-port, per the existing `arena_enemy.gd` header comment), not a request to
    add editing for the Viper weapon itself. Viper (`arena_weapons.gd`) is untouched.

## Changelog — 2026-08-05 — Creep XP drop ×10 (real pacing buff, not the 2026-07-28 units-only rescale)

- On request: every creep's `"xp"` value in `ENEMY_DEFS` (`arena_wave_director.gd`, `boss_scorpion.gd`'s own
  minion table) **scaled ×10 again**, plus every runtime `xp`/`_xp` default-fallback constant that mirrors an
  `ENEMY_DEFS` entry (`arena_enemy.gd`'s FALLBACK "chase", `arena_enemy_manager.gd`'s debug `spawn_bee()`,
  `arena_elephant.gd`/`boss_scorpion.gd`'s own boss `xp`/`_xp` vars). `arena_wave_director_v2.gd`'s
  `_xp_per_hp` (test-roster + Elite/Champion Creep XP, proportional to HP) needed **no separate edit** — it's
  pinned live to v1's own "fly" entry, so it self-propagated. See [`core.md`](core.md)'s matching entry for
  `GameManager.BASE_XP`/`XP_PER_ASTEROID`/`XP_PER_BOSS` and, importantly, why this pass is NOT the same as the
  2026-07-28 one below: that pass was a pure units rescale (BASE_XP scaled ×10 in lockstep, so kills-per-level
  was unchanged); THIS pass only scaled BASE_XP ×5 (separate request), so the actual grind is now genuinely
  ~2× faster — a real pacing change, not cosmetic.
- **HP→XP auto-fill button** formula updated to match: `max(10, round(hp_spin.value / 10.0))` (was
  `max(1, round(hp_spin.value / 100.0))` from the 2026-07-28 pass below) — see `creep_info_panel.gd`.
- **Side effect caught and fixed**: `arena_xp_orb_manager.gd`'s tier-color thresholds (`TIER_GREEN_MAX` etc.)
  classify an orb's on-screen color/size from its raw xp `value` — since creep xp just went up another ×10,
  those thresholds would have under-classified every orb again (same failure mode the 2026-07-28 pass below
  hit and fixed once already). Rescaled the same way: `TIER_*_MAX` ×10, `TIER_*_MULT` ÷10 (keeps on-screen
  orb pixel size unchanged), `TIER_*_CAP` left alone.

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
  not `no_collide` landmarks. The electric temple (spawns 10,000-15,000px away, 2000 HP) could hit 120s from
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

## Wave Edit (F7) — `scripts/ui/hud/arena_wave_editor.gd`

Changes of 2026-08-24:

- **`test_chaser` is hidden from the roster** (`EDITOR_HIDDEN_TYPES`). It is spawn_mode_2's synthesised
  "fly + steer_chaser" entry (`arena_wave_director_v2.gd`'s `TEST_ROSTER`), so its MODEL is `fly` — which is
  already in the list, making the two read as the same creep twice. Hidden in the UI only: the continuous
  spawn loop still uses it, so deleting it from `TEST_ROSTER` would change how spawn_mode_2 actually plays.
  Its siblings `test_flanker`/`test_kiter`/`test_charger` are the same shape over dragonfly/shooter/
  animalhornet and are NOT hidden — only this one was asked for.
- **Gen and Gen All save by themselves.** Gen is destructive (it clears the row before refilling it), so
  there is no useful state between generating and saving. `_on_save()` now returns the filename it wrote so
  the Gen status line can report the outcome instead of being overwritten by the save's own message; Gen All
  saves ONCE after the whole batch, not per row.
- **A two-digit Total HP means thousands.** Anything under `HP_SHORTHAND_MAX` (100) is multiplied by 1000
  when Gen runs — 13 becomes 13,000 — and the expansion is written back into the field, because a field
  still reading "13" next to a row holding 13,000 HP of creeps would make the next Gen press look wrong.
  Nothing legitimate lives in that range: the cheapest creep on the roster outweighs a two-digit total on
  its own.

  > This needed the SpinBox's `step` dropped from 100 to 1 as well. `Range` snaps whatever is typed to its
  > step, so a typed "13" became 0 and the shorthand could never have fired — the field could not hold a
  > two-digit value at all.

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
| `"boss_stub"` | elephant, chromeleon, metalfly | High-HP, slow. Chromeleon still has no moveset; elephant has its own class (`boss_script`); **metalfly** has a 2-move set + live 3D body, layered on via `"boss_move"` — see below |

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

### Arena Metalfly boss — live 3D body + 2-move set (2026-08-24)

Metalfly is the first `boss_stub` creep to get a real moveset **without** becoming its own class. Two new
mechanisms make that possible, both keyed off one def field:

```gdscript
"metalfly": {"behavior": "boss_stub", "boss_move": "metalfly", "sprite_alpha": 0.0, ...}
```

- **`"boss_move"`** — a named moveset layered ON TOP of `behavior: "boss_stub"`, dispatched from the
  `"chase", "boss_stub"` branch of `_tick_behavior()` (`_tick_metalfly`). Layered rather than made its own
  `behavior` string so the boss keeps every exemption already keyed off `"boss_stub"`: no HP/speed tuning,
  the `"boss"` group, no `LIFETIME_MAX` despawn, no off-screen recycling in the v2 director.
- **`"sprite_alpha": 0.0`** — hides the flat `.sheet.png` without dropping it. The icon stays the FALLBACK
  body: if the glb fails to load, `_setup_metalfly()` puts `_sprite_alpha` back to 1.0 and the boss draws as
  the old sprite. (Same arrangement the electric temple boss uses.)

**Phase 1 — cocoon (2026-08-24).** The boss ARRIVES as `assets/map/electric/boss/Cocoon.glb` — a static
mesh with no bones — rendered by `scripts/gameplay/fx/glb_spin_body.gd` (a generic spinning-3D-body node; it
takes any glb path, nothing in it is Metalfly-specific). It rams the player at `MF_COCOON_SPEED` (120 px/s,
nearly double the winged form's) with its own `MF_COCOON_HP` (2000) pool.

It spins on **two** axes. The camera looks straight down the view Y, so a Y spin alone reads as a flat dial
turn — same silhouette all the way round, a rotating picture rather than a rotating object. `tumble_rpm`
adds a second rotation about the view X and is what actually rolls it end over end. The two rates are
deliberately unrelated (26 and 17 RPM): related ones compose into a single fixed axis and the tumble
disappears again. Each axis gets its own nested node rather than both accumulating onto one Euler, and
`VP_PAD` went up to 1.5 because a tumble swings the model's vertical extent into the plane `center_and_fit`
sized it by.

Running that pool out **hatches** the boss rather than killing it: `take_damage`'s `hp <= 0` branch calls
`_metalfly_hatch()` instead of `_die()`, so none of death's consequences fire — no kill tally, no XP, no
loot, no chain-reaction, no `boss_defeated`. The hatch blows a `MF_HATCH_BLAST_PX` explosion, frees the
cocoon, builds the winged rig (deferred until here, so a fight that never gets past the cocoon never pays
for a second SubViewport + skeleton), refills to Phase 2's pool and enters Move 1.

The def's `hp`/`speed` are **Phase 2's**. `configure()` captures them into `_mf_p2_hp`/`_mf_p2_speed` after
every multiplier has been applied (player level, Beacon, the director's `HP_MULT`) and drops the cocoon's
flat constants in, so the real boss still gets all of that scaling. On hatch, write **`_base_speed`**, not
`speed` — `_process()` recomputes `speed` from it through the slow/Beacon/Zone-of-Peace chain every frame.

**Phase 2 body** — `scripts/gameplay/fx/metalfly_rig.gd`, a child Node2D holding a SubViewport that renders
`assets/map/electric/boss/metalfly.glb` top-down (via `glb_topdown_rig.gd`'s shared framing). The glb has a
46-bone UniRig skeleton and **zero animation clips**, so every motion is posed from code each frame: wing
beat, forewing lag, antenna sway, leg/abdomen idle, mouth gape. See that file's header for the bone map,
the measured per-bone vertex displacements, and why a bone rotation must be composed onto the rest pose and
converted out of model space (a naive `set_bone_pose_rotation` moves a UniRig leg by 0.034 units, i.e.
nothing). Verified body offset from the node origin: 6 px.

**Move 1 — cruise.** Slow beat (2.2 Hz), chases the player, fires one projectile from EACH wing TIP every
second (`MF_SHOT_INTERVAL`). Muzzles are read off the live posed skeleton (`wing_muzzles()`), so they ride
the beat rather than sitting at a fixed offset. Runs for `MF_CRUISE_T` (6s).

**Move 2 — lunge.** Mouth gapes, beat goes to 9 Hz, and a 150 px lane is drawn from the boss. For the whole
`MF_WINDUP` (1.5s) the lane **tracks the player** (`aim()` every frame, 2026-08-24) — sidestepping once no
longer beats it, the lane comes with you. Then the mouth shuts, the wings STOP, the lane **locks**, and the
boss flies down it at `MF_LUNGE_SPEED`. Only the direction tracks; the lane's ORIGIN stays pinned where the
wind-up began, so it keeps marking the ground the boss will actually leave from.

Lane length is a fixed `MF_LUNGE_LEN` (1200 px) and the boss always flies the whole of it. It was the
current distance-to-player at first, which made the same move into two different fights: a point-blank
wind-up became a twitch, a long-range one a screen-crossing charge. A fixed length also guarantees the
lunge overshoots a player who stands still.

Lane VFX: 80% opacity overall (the player has to read the field THROUGH it), three widening glow layers
under the body so the light bleeds past the edges, and a blink that multiplies a slow breath by a fast
flicker — one rate alone reads as a mechanical pulse. On lock all of that stops and the lane brightens
(`LOCKED_BOOST`): going from flickering to solid is itself the tell that the dodge window shut.

**Move 3 — swarm release.** Fast beat for `MF_SWARM_WINDUP` inside a **gathering ring**
(`scripts/gameplay/fx/metalfly_swarm_ring.gd`), then `MF_SWARM_COUNT` (8) miniature Metalflies burst out of
that ring and chase.

The ring is raised at exactly `MF_SWARM_RING` — the radius the brood appears at — so it reads as the thing
they come out of rather than as decoration that happens to be nearby, and it is released the instant they
do. It throws off concentric pulses of light the whole time: `PULSE_COUNT` rings share one clock, spread
around it by index, so there is always one leaving the centre and one arriving at the rim (a continuous
flow, not a burst per period) and no ring is ever created, tracked or freed.

Its palette, global opacity and both blink rates are read straight off `metalfly_charge_path.gd` rather
than restated — the lane and the ring are the same boss saying "something is about to come out of me" and
should read as one visual language; retyped constants drift apart the first time either is tuned.

> Two drawing notes. It is built from **annuli** (`draw_arc` with a width), never stacked discs: overlapping
> translucent discs accumulate alpha toward the middle and turn a radial gradient into a dark blob. And
> unlike the lane it is a **CHILD of the boss** — the lane marks a strip of ground the boss is about to
> leave, so it must stay put; the ring marks the boss itself, and the separation pass shoves the boss around
> inside a busy field even while it holds station. Same model and same rig at `MF_SWARM_SCALE` (25%) of the body size, with
`MF_SWARM_HP_FRAC` (5%) of the boss's HP. Both are taken from the BOSS's own live numbers, not from the
`metalfly_spawn` def, so the brood scales with everything the boss scaled with.

> Two multipliers have to be divided back OUT when writing those overrides, and both were wrong first time:
> `ENEMY_HP_TUNE` (configure() re-applies the global x2 to every non-`boss_stub` enemy — the brood hatched
> at 10%, not 5%) and `SIZE_TO_RADIUS` (a def's `size` is not the hit radius — the bodies came out 26.2%
> instead of 25%). `SIZE_TO_RADIUS` was an inline `1.05` before this; it is a named const now precisely
> because anything deriving a def `size` back from a live `_radius` has to know about it.

**The two specials alternate** rather than being rolled, so neither can come up three times running and
neither can go missing for a whole fight.

**`body_rig` — a live 3D body on an ORDINARY enemy.** The def key Move 3's brood uses: build the Metalfly
rig at `body_px`, attach no moveset, and let the enemy's own `behavior` (chase) drive it exactly as it
would with a flat sprite. `_process()` points the model along `_facing` for every rig, boss or not — that
call used to live inside `_tick_metalfly`, where it ran before the facing was finalised and covered only
the boss, leaving the brood pointing wherever it spawned.

**The lane** (`scripts/gameplay/fx/metalfly_charge_path.gd`) is parented to `get_parent()` (Arena root,
world space), NOT to the boss — same reasoning as the beamer's beam. As a child it would translate with the
boss during the lunge, so the danger zone would slide along underneath it and always extend the same
distance ahead, i.e. stop being a telegraph exactly when it matters. Freed via `tree_exited`.

#### Authoring the mount angles — Creep Edit, Electric map

Both bodies are authored in **Creep Edit** (not Boss Edit — that panel is the SpaceScreen boss's 2D layer
editor and has no 3D/rotation machinery at all). On the Electric map the palette carries a **Metalfly**
group with two rows:

| Row | Body | cfg key | Asset |
|-----|------|---------|-------|
| `Metalfly` (root) | Phase 2, `metalfly_rig.gd` | `Metalfly` | `metalfly.glb` |
| `Metalfly Cocoon` | Phase 1, `glb_spin_body.gd` | `Metalfly Cocoon` | `Cocoon.glb` |

Declared via the base's own hooks (`_extra_names` / `_asset_path_for` / `_group_metalfly_layers` /
`_default_creep_rect` / `_front_marker_angle`) — the same set weapon_edit_mode.gd uses for Jeager's clip
layers, so the FRONT arrow comes for free.

> **Both bodies must also be listed in `WIRED_3D_CREEPS`** or the "3D VIEW / MOUNT ANGLE" section stays
> hidden and there are **no Rotate X/Y/Z sliders at all** — the models still preview perfectly, which is
> what makes the omission easy to miss (it shipped that way in the first pass here). That allowlist is
> deliberate: `_refresh_glb_view_ui()` gates the rotation UI on it so a glb with no real 3D runtime wiring
> can't offer controls that silently do nothing. Metalfly qualifies because `_creep_mount_rot()` genuinely
> feeds both bodies. Anything added to the palette later needs the same two-step: declare it, AND wire the
> runtime before allowlisting it. Adding them to the BASE cannot leak
into the other editors: `weapon_edit_mode.gd` overrides every one of those hooks, and hud/fleet edit extend
`CanvasLayer`, not this file. They are further gated to `MF_MAP` ("electric").

**The root IS the winged body.** Giving Phase 2 its own `Metalfly Wings` row put a second, identical model
on the canvas stacked exactly on the root's — indistinguishable from one body until you drag it. Two rows,
two bodies.

**The FRONT arrow points DOWN (+PI/2), not up like the weapons'.** `metalfly.glb` is authored head-at-+Z,
and glb_topdown_rig.gd maps +Z to screen-down, so at zero calibration the nose genuinely points down. An
arrow pointing up would invite a 180° "correction" that the runtime would apply on top of an orientation
that is already right — i.e. the boss flying backwards, which is the exact bug the arrow was added to
Jeager to fix. Arrow aligned with the nose at `rot` 0 keeps the dial a pure correction: **0 means "what
ships today"**, which is the state verified in the arena.

**Runtime.** `arena_enemy.gd::_creep_mount_rot(layer)` reads `rot_base ∘ rot` out of `creep_layout.cfg`
(through `_creep_layout()`, whose cache the editor drops on save — so an edit lands on the next spawn, no
restart) and hands it to whichever body is being built. `metalfly_rig.gd` composes it INSIDE the heading
yaw (`Basis(UP, PI/2 - heading) * mount`): the mount corrects how the model sits on its own axes, the yaw
is which way it is flying this frame. Composed the other way round, dialling a mount angle would swing the
travel direction instead. `glb_spin_body.gd` puts it on a dedicated node between the spin pivot and the
model — writing it onto the model would throw away the fit scale `center_and_fit` baked into that transform.

Verified end to end by `tools/check_metalfly_creep_edit.gd`: dial a rotation into the rig the sliders drive
→ `_save_layout()` → spawn a boss → read the basis its body actually renders with, and compare against
`view_basis(rot)`.

#### Gotcha fixed here: facing froze above ~130 fps

`_process()` only re-aims `_facing` when the enemy actually moved more than 0.5 px in the frame. At the
boss's cruise speed of 65 px/s that threshold is crossed at 60 fps (1.1 px/frame) and MISSED above ~130 fps
(0.4 px/frame) — so on a fast machine the boss chased the player while pointing wherever it happened to be
pointing when the fight started. `_mf_face_player()` now sets the facing directly in every non-lunge state
(including the cocoon's), which sidesteps the threshold entirely. Facing a target should not depend on the
frame rate. Measured after the fix: 0.0° error at every sampled frame of settled cruise.

#### Gotcha fixed here: hit-stagger froze the whole move cycle

Every hit re-arms `_stagger_t`, and `_process()` gated `_tick_behavior()` on `_stagger_t <= 0.0`. Under
sustained Gatling fire the re-arm outruns the decay, so the boss's move clock advanced **0.00s across 700
frames** — holding the fire button cancelled the entire fight and Move 2 was unreachable. `_boss_move != ""`
now bypasses hit-stagger (stun and docking still freeze it) and is also `_stagger_exempt` from the
off-screen LOD, so a scripted cycle keeps a stable cadence. Any future `"boss_move"` inherits both.

#### Dev tools

| Tool | What it verifies |
|------|------------------|
| `tools/screenshot_metalfly.gd` | The FIGHT — boots the arena, spawns the boss under live fire, asserts the state sequence `[0,1,2,3,0]` and screenshots each beat. Its header lists the three things it has to arrange (clear the field, kill knockback, pin the player) and why each is a property of the harness, not the boss. |
| `tools/screenshot_metalfly_rig.gd` | The ANIMATION — the rig alone, heading pinned, dumping one PNG per sampled frame of the slow beat / fast beat / gape, plus the centroid check. |

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


