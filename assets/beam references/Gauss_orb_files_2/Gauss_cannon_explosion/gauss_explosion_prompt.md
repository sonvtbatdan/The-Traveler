# TASK: Convert the Gauss Cannon to an explode-on-impact AoE (sprite explosion + damage-over-time)

Repo: `sonvtbatdan/The-Traveler`, branch `RNG_items_test`.
Change the Gauss weapon: the projectile orb travels as now, but ON HITTING A TARGET it **explodes** — playing a 12-frame plasma-explosion animation for **2 seconds** and dealing area damage to everything inside it.

## EXACT DESIGN (locked with the user)
- **Trigger:** the moment the Gauss orb collides with a target, it is consumed and spawns an explosion at the impact point. Explosion is independent of the orb after that.
- **Duration:** 2.0 s total.
- **Animation (12 frames, already processed):** the explosion plays through frames but NOT at uniform speed — the look should dwell on the peak:
  - **Intro (frames 1→5):** fast. ~0.30 s total across these 5 frames (quick ramp-up).
  - **Peak loop (frames 6,7,8):** the MAJORITY of the duration. Loop 6→7→8→6→7→8… for ~1.40 s.
  - **Outro (frames 9→12):** fast. ~0.30 s (quick dissipate).
  - (Tunable split; the point is the middle is mostly the 6-7-8 loop.)
- **Damage field:** active for the FULL 2 s, starting the instant the explosion spawns. Ticks every **0.1 s**, **5 base damage per tick** (so ~20 ticks, ~100 base dmg over the lifetime). Damages ALL valid targets (enemies) inside the radius each tick. Scale the 5/tick by the weapon's damage stat via the normal `get_weapon_stat`/affix path (don't hardcode if the system applies damage affixes).
- **Damage radius:** FIXED for the whole explosion at the frame-6-8 size — measured ~2.4× the pre-explosion orb radius (the art's peak radius). One constant radius, NOT per-frame scaling. (The intro/outro frames visually grow/shrink, but the hitbox stays at the peak radius the whole time — simplest and matches "damage to all inside that sprite" for the main 6-8 phase.)

## ART (already aligned + ready to import) — 3 VARIANTS for variety
THREE explosion variants, each 12 frames, ALL aligned to the SAME spec so they're interchangeable: **394×404 each, burst core centered at (173,183)**, additive. Import to:
- `res://assets/fx/gauss_explosion/v1/00..11.png`
- `res://assets/fx/gauss_explosion/v2/00..11.png`
- `res://assets/fx/gauss_explosion/v3/00..11.png`

On each explosion spawn, **pick one variant at random** (so repeated shots don't look identical). All three share the same frame size, anchor, timing schedule, and peak radius — only the visual pattern differs, so the variant choice is purely cosmetic and doesn't affect damage/timing. The damage radius constant corresponds to the peak visual radius (~156 px at native art scale — adjust to in-game sprite scale).

## TUNABLES (group at top)
```
const GAUSS_EXPL_DURATION    := 2.0
const GAUSS_EXPL_INTRO_TIME  := 0.30   # time for frames 1->5
const GAUSS_EXPL_OUTRO_TIME  := 0.30   # time for frames 9->12
# peak loop time = DURATION - INTRO - OUTRO (~1.40s looping frames 6,7,8)
const GAUSS_EXPL_PEAK_FRAMES := [5,6,7]   # 0-indexed frames 6,7,8
const GAUSS_EXPL_INTRO_FRAMES:= [0,1,2,3,4]
const GAUSS_EXPL_OUTRO_FRAMES:= [8,9,10,11]
const GAUSS_EXPL_PEAK_FPS    := 12.0   # loop speed of the 6-7-8 peak
const GAUSS_TICK_INTERVAL    := 0.1
const GAUSS_TICK_DAMAGE      := 5.0    # base; scaled by weapon damage stat
const GAUSS_EXPL_RADIUS      := <peak radius in world units, ~2.4x orb>
const GAUSS_EXPL_SCALE       := 1.0    # sprite scale to match radius in-game
```

---

## STAGE 0 — READ AND REPORT (HARD GATE — NO EDITS)
1. Locate the Gauss weapon. Report the file + fire-type handling (likely a `gauss`/charge fire_type in `weapon_system.gd` or an arena weapon node). Quote: how the orb is spawned, how it travels, and how it currently detects hitting a target / currently deals damage.
2. Report how OTHER AoE/tick damage is done in the codebase (e.g. acid_cloud, aura, rift zone) — there's likely an existing "damage all enemies in radius each interval" pattern to reuse. Quote it. Report how enemies are enumerated and damaged (the damage call signature, crit handling) and how `get_weapon_stat`/affixes apply so the 5/tick scales correctly.
3. Report the orb's current radius/size so `GAUSS_EXPL_RADIUS` (~2.4× it) and sprite scale can be set in real units.
4. Report how transient timed visuals are spawned/cleaned (the `_tick_fx`/transient pattern used elsewhere) so the explosion can be a self-expiring node/entry.
5. Propose the structure: on orb-hit → spawn explosion (sprite animator + DoT field + 2s lifetime) → per-frame advance the animation by the intro/peak-loop/outro schedule → every 0.1s damage enemies in `GAUSS_EXPL_RADIUS` → despawn at 2s.

**STOP. Report the Gauss code + existing AoE-tick pattern + radius. No code yet.**

---

## STAGE 1 — Spawn explosion on impact + play the animation
- Import all 3 variants' 12 frames to `res://assets/fx/gauss_explosion/v1|v2|v3/` (additive).
- On orb→target collision: consume the orb, spawn a `GaussExplosion` (self-expiring, 2s) at the hit point, **choosing one of the 3 variants at random** for its frame set.
- Animation scheduler (NOT uniform): play intro frames over `GAUSS_EXPL_INTRO_TIME`, then loop `GAUSS_EXPL_PEAK_FRAMES` at `GAUSS_EXPL_PEAK_FPS` until `DURATION - OUTRO_TIME`, then play outro frames over `GAUSS_EXPL_OUTRO_TIME`. Reuse the existing transient/`_tick_fx` lifetime pattern.
- Draw additive at `GAUSS_EXPL_SCALE`, core-centered (173,183 anchor) on the impact point.
- NO damage yet — just the visual.

**STOP. Confirm the explosion plays on hit, lingers on the 6-7-8 peak for the bulk of 2s, and looks right at the intended size.**

---

## STAGE 2 — Damage field (DoT)
- For the explosion's full 2s, every `GAUSS_TICK_INTERVAL` (0.1s), damage all enemies within `GAUSS_EXPL_RADIUS` of the explosion center for `GAUSS_TICK_DAMAGE` scaled by the weapon's damage stat (via the existing AoE-tick pattern + `get_weapon_stat`/affixes + crit handling from Stage 0).
- Fixed radius the whole time (do not scale per-frame). Each enemy can be hit once per tick.
- Make sure it uses the same enemy enumeration + damage call as other AoE weapons so floating numbers, crits, and on-hit effects work consistently.

**STOP. Test: fire into a cluster — everything inside takes ~5/tick every 0.1s for 2s (~100 base). Verify damage numbers + radius feel right.**

---

## STAGE 3 — Polish + balance hooks
- Optional: debug-draw the `GAUSS_EXPL_RADIUS` circle (toggle) to confirm hitbox matches the visible 6-8 plasma.
- Tune `GAUSS_EXPL_RADIUS` so it matches the peak plasma edge, `PEAK_FPS` for crackle speed, intro/outro times for pacing.
- Confirm interaction with the orb's existing travel/charge behavior is unchanged up to impact; only the impact result changed.
- Verify multiple simultaneous explosions are independent (no shared tick/animation state).

**STOP. Final review.**

---

## RULES
- Only change the Gauss weapon's IMPACT behavior (orb→explosion AoE) + add the explosion entity. Keep the orb's travel as-is. Don't touch other weapons.
- Reuse the existing AoE-tick damage pattern + `get_weapon_stat`/affix/crit path — don't invent a parallel damage system; the 5/tick must scale with the weapon's damage like everything else.
- Animation is non-uniform: fast intro, long 6-7-8 peak loop, fast outro. Damage radius is FIXED at the peak size for the full 2s.
- Import frames to `res://assets/fx/gauss_explosion/v1|v2|v3/`, additive, core-anchored at (173,183). Pick a random variant per explosion (cosmetic only — same timing/radius/damage for all).
- Tunables as constants/`@export` grouped at top.
- Explosions are independent, self-expiring at 2s; reuse the transient/`_tick_fx` lifetime pattern.
- One stage at a time; STOP for my test + approval after each.
