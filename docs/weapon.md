# Weapon — Combat, Inventory & Arena Weapons

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on weapons, firing, inventory/affixes, ship visuals, arena weapon mechanics + their VFX.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

## Changelog — 2026-08-24 (53rd pass) — the approach clip is chosen by distance, not rolled

"Giờ ko random move nữa, mà khoảng cách <300 pixel đến enemy thì dùng run, lớn hơn 300px thì dùng fly."

`JAEGER3D_CHASE_CLIPS` and both roll sites are gone. The chase branch reads the distance to the target and
picks `Fly` beyond `YARI_FLY_DIST` (300px) or `Run` inside it, re-evaluated every frame so the clip changes
as Jeager closes rather than being locked in at the start of the approach.

**With a `YARI_FLY_HYST` = 30px band where the current clip is KEPT.** A target parked exactly on 300px is
inside one frame and outside the next, which would flip Run/Fly every frame — the identical failure the 48th
pass measured on `YARI_AGGRO`'s own edge, where it produced hundreds of state changes and an animation that
never finished. The band is not speculative caution; it is the same bug avoided twice.

Verified over 40 samples during live approaches: **0 violations** of the rule, the furthest Run was at 163px
and the nearest Fly at 302px, and the clip switched cleanly once per approach as the gap closed
(505 → 319 on Fly, Run from there in).

## Changelog — 2026-08-24 (52nd pass) — approach rolls Run/Fly, and the plume emission toggle that had never worked

### Dive → Fly

`JAEGER3D_CHASE_CLIPS = ["Run", "Fly"]` (corrected from the 51st pass on request). Verified in play:
approaches rolled `Run → Fly → Run`, each actually driving `current_animation`.

### Plume check on Fly / Run / Slash — and what it turned up

Asked for a check, so it was measured per clip in normal play rather than by forcing clips (an early attempt
did force them, and `_draw_yari` overwrote the choice the same frame — the numbers were meaningless).

| clip | master anchor | active layer | particles |
|---|---|---|---|
| Fly | visible | — | emitting, visible |
| Run | visible | — | emitting, visible |
| Slash | visible | — | emitting, visible |
| Walk | hidden | `Walk` | the Walk layer's own set shows instead |

So the plume works on all three. Walk is the one clip with TPs of its own, so it correctly shows those and
suppresses the master — by design, not a fault.

**But the numbers exposed a dead code path.** During Walk the hidden master anchor read `emitting=2,
visible_in_tree=0`: hidden, yet every particle still simulating. `_set_plume_anchor3d_visible()` walked
DIRECT children looking for `CPUParticles3D` — and no anchor has had one as a direct child since the
2026-08-21 pivot refactor, where every particle moved one level down under its TP's pivot. **The emission
half of that function had been dead for every 3D plume in the game ever since**; only `visible` (which
propagates) was doing anything.

Two fixes, because one alone was not enough:
* the walk recurses now, so hiding an anchor really does stop its particles;
* and `_add_tp_plume_pivot()` seeds `p.emitting = parent.visible` at build time. Without this the first hide
  was still a no-op — anchors are built hidden and `make_plume()` builds particles emitting, so
  `_set_plume_anchor3d_visible()`'s early-return (asked for the visibility it already has) skipped the sync
  and a never-yet-shown anchor simulated forever.

After: Walk reads `emitting=0, visible_in_tree=0`; Run and Slash read `emitting=2, visible_in_tree=2`.

## Changelog — 2026-08-24 (51st pass) — live sweep-delay slider, and Dive joins the approach

### Sweep-delay slider (bottom-left, dev only)

"làm 1 slider chỉnh mức độ delay, chạy từ 0-2 giây... tôi sẽ spawn jeager và tự kéo để điều chỉnh cho khớp
animation." Lining the arc up with the frames where Slash actually swings is a by-eye call, so it wants a
live control rather than a constant and a restart.

`YARI_SWEEP_DELAY` keeps its 0.4 default but is now backed by `_yari_sweep_delay`, reachable through
`set_yari_sweep_delay()` / `get_yari_sweep_delay()`. The slider (`arena_debug_spawn.gd`) sits on
`_dev_ui_root`, so it appears and disappears with dev mode like every other panel there, and it seeds its
handle from whatever the weapon currently holds rather than assuming the default.

Deliberately NOT persisted — it is a tuning aid. Once a value reads right, it belongs in `YARI_SWEEP_DELAY`.

Verified live: range 0–2, dragging to 1.35 put `get_yari_sweep_delay()` at 1.35 and relabelled the readout
in the same frame.

### Dive in the approach

"jeager khi chase enemies chỉ dùng run, chưa random ra dive. mỗi lần sau khi tấn công, sẽ random hoặc dive
tới mục tiêu tiếp theo, hoặc run."

`JAEGER3D_CHASE_CLIPS = ["Run", "Dive"]`, rolled ONCE per approach — on the `attack_hold → chase` handoff (the
"next target" case the request names) and on `idle → chase`, so the first run-up is not always Run either.
Not re-rolled per frame: the chase branch only rolls when the state is not already `chase`. Both clips loop,
so either carries a whole approach.

Verified: the roll is even (2000 draws → 969 Run / 1031 Dive) and both clips exist on the merged model and
play when selected. In-game, `Dive` was observed driving three consecutive approaches — which is what
prompted checking the distribution rather than trusting a three-sample run.

## Changelog — 2026-08-24 (50th pass) — sweep delay to 0.4s; the level-up board renders Jeager's model, and the skinned-AABB bug that kept it blank

"delay thêm 0.2 giây nữa. Dùng stand.glb làm thumbnail và preview cho bảng level up."

* `YARI_SWEEP_DELAY` 0.2 → **0.4**. Verified over three consecutive attacks: the arc first appears at
  `sweep_t` 0.406 every time.
* `ITEM_DEFS` entries can now name a `"glb"` outright, and `yari_jaeger` points at the merged
  `assets/weaponry/Jeager/Jeager.glb`. `get_glb()` used to only guess a model sitting next to the PNG under
  the same basename, which cannot reach a model that lives in the weaponry folder and is shared with the
  arena. Both the small card icon and the big WeaponDisplay preview go through `_make_weapon_icon()`, so one
  entry covers both. `Item3DIcon` never touches an AnimationPlayer, so the card shows the model's REST pose
  — which is exactly `stand`.

### It still rendered blank — the same skinned-mesh bug, in a third copy

With the path resolved the Yari Jeager card was an empty green screen while every other weapon drew fine.
`item_3d_icon.gd` keeps its own copy of the framing math (this repo's stated convention), and its
`_model_aabb()` was doing `_relative_transform(root, mi) * mi.get_aabb()` — the identical bind-space-box
mistake the 34th pass fixed in `glb_topdown_rig.gd`. For Jeager that is off by ~100x, so the camera framed a
box a hundredth of the model and the card rendered nothing.

Pointed at `glb_topdown_rig.instance_aabb()` instead of copying the fix a third time: it is ~50 lines with a
per-mesh cache, not the one-liner the rest of that file's duplicated framing is. Confirmed on the real board
— the card now shows the mech standing.

**Audit of every other copy (2026-08-24, "rà luôn").** There are **19** hand-copies of `mi.get_aabb()` across
17 files, not three. Rather than read all of them, the question was narrowed to the one that decides the bug:
*which assets are actually skinned?* Scanning all 72 `.glb` in the project turned up exactly two families:

| model | bind-space box | true skinned box | ratio |
|---|---|---|---|
| `Boss_Scorpion_1.glb` | (2, 2, 2) | (2, 2, 2) | **1.00x** — unaffected |
| `Jeager.glb` (and its 9 siblings) | (2, 2, 1) | (160, 170, 69) | **100x** — the broken one |

The scorpion is rigged without an armature-scale mismatch, so `mi.get_aabb()` is exactly right for it and
every scorpion/boss/test site is fine as written. Everything else that loads a model — the map asset scans,
the ship, the ruin pointer, the loot drops — loads unskinned art.

Cross-checked from the other direction too: of the four files that name a Jeager glb, the only one containing
a raw `mi.get_aabb()` is `glb_topdown_rig.gd` itself, where those calls are `instance_aabb()`'s own
rigid-mesh fallbacks. Every Jeager consumer now goes through that helper or through the fixed
`item_3d_icon.gd`.

**Correction to the note this replaces:** `arena_chest.gd` does hold a copy, but it hardcodes
`assets/ruin/Chest.glb` and can never be handed a skinned model — it was never at risk. `arena_loot.gd` is
the same, restricted to `assets/screen/<type>.glb`.

**So: nothing else is broken today.** The latent risk is real but conditional — the next skinned import that
carries an armature scale (the usual Mixamo/rigify shape, which is how Jeager arrived) will silently break
whichever site loads it. `glb_topdown_rig.instance_aabb()` is a drop-in for `mi.get_aabb()` — identical for
rigid meshes, since it early-returns on `skin == null` — so consolidating the 19 sites onto it is cheap
insurance whenever that is wanted. Not done here: 17 untouched files changed for a hypothetical is a worse
trade than the one-line change it would be at the time.

## Changelog — 2026-08-23 (49th pass) — Slash only, and the sweep light delayed 0.2s to land on the swing

"bỏ luôn cả animation kick và low kick đi, để lại slash thôi. delay luồng sáng quét lại 0.2 giây để khớp
với animation."

* `JAEGER3D_ATTACK_CLIPS` is `["Slash"]`. Kept as an array rather than collapsed to a bare constant — the
  roll reads the same either way, and putting a clip back is one word instead of restoring a mechanism.
* New `YARI_SWEEP_DELAY` = 0.2s. The arc used to start on the same frame as the attack, i.e. during Slash's
  wind-up. The damage window is unchanged in LENGTH — still `YARI_SWEEP_TIME`, just moved 0.2s later — so
  the move is re-timed without re-tuning its damage. Nothing is drawn and nothing is hit during the wind-up.
* `attack_hold` accounts for the delay too (`alen - (DELAY + SWEEP_TIME)`), or the pose would have been cut
  short by exactly the amount the arc was pushed back.

Verified over four consecutive attacks: every one plays `Slash`, the arc first becomes visible at
`sweep_t` **0.200 / 0.207 / 0.205 / 0.200**, and the attack state now runs to 0.60 (0.2 + 0.4) before
handing off to `attack_hold`. Loop reads `idle → chase → attack(Slash) → hold → chase → …`.

## Changelog — 2026-08-23 (48th pass) — Fly Punch lunge removed; Jeager is approach + three attacks

"bỏ animation lấy đà đánh đi, nó quá phức tạp và dễ tạo lỗi... Khi tiến về enemies, sử dụng fly hoặc run.
Khi đánh, dùng kick, low kick, slash, có vẽ ánh sáng quét ngang."

### Removed

The whole lunge apparatus: the `lunge_setup` and `lunge` states, `_measure_jaeger_lunge()` (root-motion
measurement off the clip), `_jaeger_lunge_px()`, `_yari_punch_impact()`, `_first_mesh_instance()`, the
`YARI_LUNGE_*` / `YARI_PUNCH_*` constants, `JAEGER3D_PUNCH_CLIP`, and five state variables. Three interacting
moving parts — a measured standoff, a run-up, a landing impact — that between them produced the 47th pass's
"runs in circles" bug. The clip is still in the merged glb; nothing plays it.

State machine is now: **idle** (Walk, wander within 300px of the player) → **chase** (Run at 200px/s) →
**attack** (Kick / Low Kick / Slash, rolled evenly, with the sweep arc) → **attack_hold** (pose plays out,
capped at 1.2s) → chase. Chase uses `Run`; `JAEGER3D_RUN_CLIP` is one constant if `Fly` is wanted instead.

### Found while verifying: idle/chase flickered every single frame

Logging every transition showed an unbroken alternating run — `chase, idle, chase, idle, …` on consecutive
frames — whenever an enemy sat near the edge of `YARI_AGGRO`: in range one frame, out the next, so the state
and therefore the CLIP flipped Walk/Run continuously and no animation ever finished. That is its own share of
"just runs around".

Fixed with hysteresis, the same shape VIPER's `SNAKE_TARGET_STICKY` already uses: a target is acquired inside
`YARI_AGGRO` (520) and released only past `YARI_DROP_RANGE` (676). **State transitions over 3000 frames went
from hundreds to nine**, reading cleanly as
`idle → chase → attack(Slash) → hold → chase → attack(Low Kick) → hold → chase → attack(Kick)`.

### Note on a self-inflicted scare

The scripted removal of the lunge block took the neighbouring `attack_hold` handler with it — caught by
grepping for the state name afterwards and restored before anything ran. Worth recording only because the cut
was anchored on a comment boundary, which is exactly the kind of anchor that silently swallows the block next
door.

## Changelog — 2026-08-23 (47th pass) — Jeager ran in circles instead of attacking; attacks were a 0.4s flash

Both reported from real play, both reproduced by logging state/clip every frame over ~3000 frames rather
than by watching.

### 1. "There is a creep right there but it just runs around"

The Fly Punch launch standoff is the clip's own travel, **636 px** — and `YARI_AGGRO` is **520**. So backing
off to the standoff walked Jeager out of its own aggro radius, `_nearest_enemy()` returned null on the way,
the state dropped to `idle` and it went back to wandering. Measured: **344 frames in `lunge_setup` without a
single lunge ever firing**, repeated every time the roll came up (1 in 4 attacks).

A lunge holds the target it locked, at any distance, instead of re-acquiring by proximity every frame. After:
`lunge_setup` → **`lunge|Fly Punch` for 491 frames**, i.e. the full 3.03 s clip, and the punch lands.

### 2. "The bright sweep never shows"

It always rendered — captured mid-swing: the orange crescent, the sparks and the damage numbers are all
there. The problem was how RARELY it ran, and for how long the pose lasted.

`YARI_SWEEP_TIME` is 0.4 s and ends both the damage arc AND the animation, while Kick runs 1.47 s, Low Kick
2.37 s and Slash 3.20 s. Measured at **67 frames per attack**: a flash of the move, then a snap back to Run.
That is also the "model falls back to stand" — at 105 px a pose glimpsed for a fifth of its length does not
read as an attack at all.

New `attack_hold` state: the damage window is UNCHANGED (`_yari_sweeping`, the arc and the hit test still end
at `YARI_SWEEP_TIME` exactly as before) but the pose plays on, holding position so a kick does not slide
across the screen. Capped at `YARI_ATTACK_HOLD_MAX` = 1.2 s — uncapped, Slash froze the weapon for 823
measured frames, which reads as a hang rather than an attack.

After: all three attacks fire and are readable, `lunge` fires, and time is split across idle / chase /
attack / hold instead of pooling in a run-away that never resolved.

## Changelog — 2026-08-23 (46th pass) — Jeager's master plumes bound to a bone, and the master-rotation bug that had them on the wrong body part

The user authored two exhaust plumes on the `stand` master layer and asked for them to be bone-bound and to
appear correctly on every animation.

### The blocker: the master layer's own rotation never reached the runtime

Every OTHER layer's mount angle reaches its plume for free — the runtime puts that layer's angle on the
CARRIER, so the model and its plumes turn together. The master's does not: the carrier carries the PLAYING
clip's angle, never the master's. `stand` is authored at **Rot Z 180**, so its plumes landed 180° away from
where the editor drew them — authored on the leg thrusters, rendered up by the arms.

Caught by measurement, not by eye: asking "which bone is each plume nearest?" returned `LeftForeArm` /
`RightForeArm` at distances of 20–27, while the editor screenshot plainly showed both flames coming out of
the leg pods. Two answers that disagree meant the two sides disagreed. With the master's rotation baked into
the offset (and composed into each TP's own spray direction), the same question returns **`Spine02` for both,
at 12.4 and 10.4** — nearest by a clear margin instead of floating between four candidates.

### Bone binding

Both TPs bound to **`Spine02`**. It is the nearest bone to each after the fix, it is the same bone for both
(so the pair stays rigid, which is what a booster pack is), and it sits at their height — `Hips` is the
runner-up at 13–15 if the pack should follow the pelvis instead.

Verified across five clips — Walk, Run, Kick, Fly Punch, Slash — the plumes hold **identical** offsets from
the spine bone: `(-1, 0, 12)` and `(10, 0, -5)` in every one. They no longer sit at a fixed spot in the
model's box while the body moves out from under them.

(One measurement artifact worth recording: reading a BoneAttachment3D's transform in the SAME frame as an
`AnimationPlayer.seek()` gives a stale value — on Fly Punch, whose root motion moves the hips 1000+ units,
that read as a 200-unit error. A frame's gap and it is exact. Nothing was wrong with the code.)

### Also fixed while in there

`_jaeger_clip_pose()` is keyed by LAYER name but was looked up by CLIP name, and those differ for exactly one
of them — `"Fly punch"` the layer, `"Fly Punch"` the clip. So that layer's mount angle was silently dropped
and it fell back to the weapon's. Same one-letter trap `JAEGER3D_LAYER_CLIP` exists to guard.

## Changelog — 2026-08-23 (45th pass) — `stand` had no rotate sliders; and a clicked TP did not land where you clicked

### The reported bug

`stand` was never added to `WIRED_3D_CREEPS`, so selecting it showed no Rotate X/Y/Z and no TP XYZ panel — an oversight when the master layer was introduced in the 43rd pass. Added; verified 8/8 of the 3D VIEW controls now render for it, with rig key `Jeager.glb#stand`.

Its own mount angle is an authoring convenience (turn the reference model to a workable angle). The runtime still takes the object's orientation from the PLAYING clip's layer, falling back to `Yari-Jeager` — see `_jaeger_clip_pose()`.

### Found while checking it: two writers of `tp["pos"]` disagreed

`tp["pos"]` is stored in the part's own LOCAL frame and drawn back through the mount rotation. The TP POS X/Y/Z spinboxes always respected that (`_tp_xyz_set()` inverse-rotates and splits a point into `pos` + `z`). **Clicking to place a TP did not** — it stored the raw canvas position. So on any rotated model a new TP appeared somewhere other than where it was clicked, which is exactly what the user was about to hit on a rotated `stand`.

Measured on a 150 px part, before:

| mount angle | click (+40, 0) rendered at | click (0, +40) rendered at |
|---|---|---|
| 0 | (40, 0) ✓ | (0, 40) ✓ |
| Rot X −90 | (40, 0) ✓ | **(0, 0)** — the vertical part of the click vanished |
| Rot Z 90 | **(0, −40)** — rotated | **(40, 0)** — rotated |

At Rot X −90 the canvas-down axis IS "height" under a top-down camera, so that component belongs in `z`, not in `pos` — which is why it disappeared rather than merely shifting. The click now routes through `_tp_xyz_set()`, the exact inverse of the render path and the same function the spinboxes use, so the two writers finally agree. After: every click lands where it was clicked at all three angles.

Existing TPs are untouched — only newly placed ones take the corrected path.

### "Add TP but nothing spawns" — it does; it is inside the model

Reported straight after. Traced end to end and the TP is fine at every step: the point is created, the
overlay builds its pivot, and the CPUParticles3D under it is `emitting=true`, `visible=true`, amount 30,
lifetime 0.6, quad 27px, velocity 60-80. Nothing is broken.

What is happening is **occlusion**. A TP sits at `z = 0` by default, which under the editor's top-down camera
is the model's MID-DEPTH — and Jeager is a solid 174k-vertex mesh, not the flat sprite this editor was built
around. Click on the body and the plume spawns inside the geometry, with only a sliver escaping at the
silhouette edge. Captured both cases side by side: a TP 10px below the part centre is almost entirely
swallowed; the same TP 62px down, clear of the body, is unmistakable.

Levers, in order of usefulness: place the TP at the silhouette edge where a real thruster would be, or raise
it with PgUp (`z` lifts it toward the camera, out of the mesh). Deliberately NOT "fixed" by making the
preview ignore depth — that would show a plume in the editor that the game then buries, which is the exact
class of editor/arena disagreement the 36th and 43rd passes existed to remove.

## Changelog — 2026-08-23 (44th pass) — three regressions from the merge/eye work

All three reported by the user after testing the 43rd pass. Two were mine.

### 1. Opening Weapon Edit showed every weapon at once

**My regression, from the 41st pass.** `eo.visible` has exactly one owner — `_update_all_creep_interactivity()`, which shows only the ACTIVE group. The eye toggle added a second writer (`_apply_layer_visibility()`) that ran right after it and set every placed creep visible unless its eye was closed, overwriting that rule. With nothing selected the canvas should be empty; instead it drew all nine Jeager clip layers plus VIPER, missile, bomb and the rest stacked on each other.

The eye now only ever SUBTRACTS, inside the one owner: `visible_set.has(name) and not _layer_hidden[name]`. `_apply_layer_visibility()` just delegates there. Verified: nothing selected → 1 visible EO (the editor auto-selects the first palette entry, unchanged behaviour); Yari-Jeager selected → exactly its 10 group members.

### 2. The `stand` layer rendered Dive

**My regression, from the 43rd pass.** `_play_preview_animation()` falls back to "the first clip whose name has no `|`" when no clip is asked for. That was safe while every glb held one animation — but the merged Jeager file holds eight, and they sort alphabetically, so the master layer (which is meant to sit in its REST pose) played **Dive**.

Guessing is now only allowed when the file has one obvious animation: exactly one plainly-named clip, or a single clip full stop. With several to choose from and no explicit request, it plays nothing.

### 3. The weapon's own layer displayed a walk frame

Not a regression — `Yari-Jeager.glb` has always been a byte-identical copy of `Walk.glb`, so the group row showed a mid-stride pose. On request it resolves to the merged file with no clip, i.e. the `stand` reference pose. That also drops the last 19 MB duplicate.

This needed `_rig_key()` extended: `stand` and `Yari-Jeager` both want the merged asset with NO clip, so a key of "path + no clip" would have collapsed them into one rig sharing one rotation — the same trap the 43rd pass fixed for the clip layers. When a creep's asset is shared and no clip disambiguates it, the key falls back to the creep's own name.

Verified visually: `stand` and `Yari-Jeager` now render the same symmetric standing pose, and their rig keys are `Jeager.glb#stand` and `Jeager.glb#Yari-Jeager`.

## Changelog — 2026-08-23 (43rd pass) — Jeager's layers share the merged glb, `stand` is the plume master, TPs can bind to a bone

The three items left open by the 42nd pass.

### 1. Every layer previews the ONE merged glb

`_glb_preview_cache` was keyed by asset path, so nine layers pointing at one file would have collapsed into a single rig — one rotation, one pose, one camera for all of them. The key is `_rig_key(creep_name, path)` now: the bare path when a creep has the asset to itself, `path#clip` when it does not. Three new hooks carry it: `_asset_path_for()` (override the "<folder>/<name>.<ext>" scan), `_preview_clip()` (which animation this layer's preview plays), and `_rig_key()` itself; `weapon_edit_mode.gd` fills all three in for Jeager and every other editor keeps the old behaviour by default.

Threaded through `_load_full_tex` / `_load_tex_raw` / `_load_glb_topdown_tex`, and through all seven cache lookups (`_tp_target_px`, `_tp_mount_basis`, `_rig_for_creep`, the group overlay, `_save_layout`, `_load_layout`, `_glb_refresh_tp_gizmos`). `_active_glb_path` holds the key rather than the path. The group overlay also passes each part's own clip now, or all nine would render whichever animation sorts first in the merged file.

Verified live: nine layers, all on `Jeager.glb`, keys `Jeager.glb`, `Jeager.glb#Fly`, `Jeager.glb#Walk`, `…#Fly Punch`, each rendering its own pose.

### 2. `stand` is the master layer

Added as a palette layer alongside the eight clips, previewing the merged file with **no** clip (rest pose — the pose you want to be aiming a thruster at), and given its own reserved spot on the canvas rather than a grid cell, since it is the one you dwell on. `_load_jaeger_plume_3d()` reads its TPs first and falls back to the weapon's own `Yari-Jeager` entry, so plumes authored before this keep burning until they are moved across. It also joins `front_angle_for()` — same carrier, same FRONT direction.

### 3. Thrust points can bind to a bone

`tp["bone"]` (absent = exactly the old behaviour). A **Bone:** dropdown appears under the TP's X/Y/Z row whenever the selected creep's model has a skeleton, listing its real bones — read off the live preview rig, so it is the same skeleton the runtime will bind to. Changing it saves and calls `reload_3d_weapon_layout()`, the same live-apply path the rotation sliders use.

At runtime the pivot is **not** parented to the `BoneAttachment3D`. Doing that would make it inherit the skeleton's own scale — the glTF armature carries a 0.01 and `center_and_fit` multiplies another ~57 on top — so particle size would be at the mercy of the rig. It stays a child of the plume anchor and is re-placed each frame from `att.global_transform * offset`, where `offset` is captured once at build time while the skeleton is still at rest: exactly the transform that puts the plume where it was authored.

Verified end to end with a TP bound to `RightHand` through the Kick clip: the bone travels x −18→−61, z 50→86 and the plume tracks it the whole way, swinging around as the hand rotates (the offset is rigid in the bone's frame, so that is correct, not drift). The seeded test data was removed again — both cfgs are back to what the user left.

### Correction — stray `hidden` flags in weapon_layout.cfg

My own eye-toggle test in the 41st pass ran through `_save_layout()`, which wrote `"hidden": true` onto eight Jeager layers and left it there. Found while debugging why those layers stopped rendering. Cleared. The lesson is recorded next to the ConfigFile duplicate-key gotcha in the 40th pass: **test tooling that drives the editor can write to the user's layout file** — back it up and diff it afterwards, do not assume a read-only run.

### Still open, deliberately

The eight source clip glbs are now referenced by nothing — not the runtime (one merged file since the 42nd pass), not the editor (all layers resolve to it as of this pass). Deleting them plus `Yari-Jeager.glb` and the eight duplicate texture PNGs is what actually banks the ~240 MB, and that is the user's call to make, not mine.

## Changelog — 2026-08-23 (42nd pass) — Jeager's eight animation glbs merged into one; Fly Punch was never actually animating

### What the numbers actually were

Measured before deciding anything, because the user's question was whether merging would be lighter "cả về dung lượng và thực thi":

| | |
|---|---|
| each clip glb | **19.4 MB**, mesh **174,381 verts**, 1 surface, 24 bones |
| `stand.glb` | mesh + skeleton **identical** to the clip glbs (same vert count, same bone names) |
| `Yari-Jeager.glb` | **md5-identical to `Walk.glb`** — a straight copy |
| the 8 texture PNGs | **all md5-identical** — eight copies of one 7.9 MB image |
| folder total | **233 MB** (+ 19.4 MB for the duplicate outside it) |

So: **disk, yes, hugely** — the same mesh and texture were duplicated nine times to carry one animation each. **Runtime, essentially no** — `_merge_jaeger_clip` already merged them at startup and freed every duplicate mesh, so only ever one mesh was live. The win there is startup: it stopped loading ~155 MB of glb only to throw it away.

(The real frame-time cost is untouched by any of this: 174k vertices for a character drawn at 105 px. Flagged to the user, not acted on.)

### Correction — Fly Punch has never animated

Found while writing the merge, and it invalidates part of the 40th pass's claim. Godot binds an animation track **by node path**. Seven of the eight glbs name their armature node `Armature`; **`Fly punch.glb` names it `target_character`**. Its tracks therefore resolved to nothing on the shared skeleton — the clip "played" for its full 3.03 s without moving a single bone. That is what the `AnimationMixer … couldn't resolve track: 'target_character/Skeleton3D:Hips'` warnings at every boot were.

The 40th pass said the lunge's own root motion carried the visual into the target. The state machine, the measured 636 px standoff and the logical jump were all real and correct — but the character was not visibly moving during it, so the jump read as a teleport. The merge fixes it by re-addressing every track **by bone name** against the target skeleton.

Verified on the merged file: `Fly Punch` moves Hips z **10.7 → 755 → 1061** across the clip, and a boot now logs **zero** "couldn't resolve track" warnings (there were several before).

### The merge

`tools/merge_jaeger_glb.gd` (new) — loads the user's clean `stand.glb`, lifts the longest animation out of each clip glb (the "longest" rule matters: `Fly punch.glb` ships a 0.07 s stub alongside the real 3.03 s lunge), retargets every track onto the base skeleton by bone name, and writes one `assets/weaponry/Jeager/Jeager.glb` via `GLTFDocument`. **21.2 MB, all 8 clips, 174,381 verts, 24 bones, 0 tracks dropped.**

`arena_weapons.gd` now loads that single file: `JAEGER3D_BASE_GLB` points at it, `JAEGER3D_CLIPS` and `_merge_jaeger_clip()` are gone, and the attack clips are set `LOOP_NONE` directly. Verified in a live run — all 8 clips present, `_jaeger_lunge_px()` still 635.9, and the Hips bone actually travels under the punch.

### Still outstanding (agreed scope, not yet done)

* **The editor still previews the eight source glbs**, so they cannot be deleted yet and the disk saving is not realised. Making the layers share `Jeager.glb` needs `_glb_preview_cache` re-keyed from bare path to `path#clip` (~8 lookup sites) so each layer keeps its own preview rig, mount angle and clip.
* **`stand` as the master plume layer** — not yet a palette entry.
* **Bone-attached TPs** (`BoneAttachment3D`), so a plume stays on the jetpack through every animation instead of holding a fixed offset from the model centre.

## Changelog — 2026-08-23 (41st pass) — Weapon Edit: per-layer eye toggles, and a FRONT arrow on every 3D part

### Eye toggle per layer

"hiện tại đang có nhiều layer cũng hiển thị, khó set plume." Every layer row carries an eye on the right. Closing it stops that part being DRAWN — its flat EO, its model in the 3D group overlay, and its FRONT arrow — while its position, TPs, styles and rotation are all untouched. Persisted per creep as `"hidden"` in the layout cfg, since which parts you want out of the way while authoring is worth surviving a restart (verified round-trip: saved, re-booted, came back).

One thing worth recording because it was wrong first time: the toggle has to go through `_update_grid_overlay()`, not just the plume rebuild. Refreshing only the 3D overlay left the hidden layers' FRONT arrows still drawn on the canvas, floating over nothing.

### FRONT marker

"Có điểm đánh dấu mặt trước (để tôi quay model cho đúng khi di chuyển, tránh di chuyển ngược)." A cyan arrow out of each 3D part's centre along the direction that part will TRAVEL in play — rotate the model to face down the arrow and it flies forwards.

The angle is not a constant, and assuming it was would have been the bug. Every 3D weapon reaches the screen through `_snake3d_world_xform(pos, ang, …)`, whose basis rotates the model by `ang` in the canvas plane — but each draw path passes `ang = facing + OFFSET`, and the offset differs. A canvas direction `d` therefore renders along `d + facing + offset`, so the one that ends up along `facing` is `d = -offset`:

| offset the draw path adds | weapons | FRONT points |
|---|---|---|
| `+PI/2` | VIPER head & tail, Yari-Jeager (and its clip layers), shooter | **up** |
| `0` (raw bearing) | VIPER body, Swarmball, Swarmbot, BC-SL-Spore | **right** |

`ND-Aliwa-Bmr` deliberately gets no arrow: it is handed a SPIN, not a heading, so no canvas direction is "its front" and drawing one would invent a rule the renderer does not have. The table lives in `arena_weapons.gd::front_angle_for()` — the file that owns the draw calls it is read off — and the editor reaches it through a `_front_marker_angle()` hook, so the enemy editor (no arena to ask) simply gets NAN and no markers.

### Verified

Live: 9 markers on the Jeager group with every clip layer showing, 2 after closing seven eyes — models and arrows both gone, the two remaining parts untouched. The screenshot also does the job it was asked for: the Yari-Jeager root and most clip layers visibly point away from their FRONT arrow, which is the "bay ngược" being pointed at directly.

## Changelog — 2026-08-23 (40th pass) — Jeager: per-layer plumes, a Walk/Run behaviour loop, and the Fly Punch lunge

### 1. Each animation layer carries its own plumes

Every clip layer is already its own creep in Weapon Edit, so its TPs and plume styles were storing separately with no new format — the runtime just never read them back. `_load_jaeger_clip_plumes()` builds one anchor per layer under the carrier and `_sync_jaeger_clip_plumes()` shows exactly the one whose clip is playing, falling back to the weapon's own set when that layer has none. So a plume authored on the Kick layer only burns during a Kick.

A TP is a fraction of **its own layer's** rect but has to land on the model at the size the ARENA draws the weapon, which is why the two arguments to `_tp_local_pos()` differ here; same conversion as every other weapon (see `_tp_scale`).

One ordering trap worth recording: `_update_jaeger_plume_3d()` runs later in the same frame and unconditionally switched the weapon's own anchor back on, so the layer's set and the weapon's set were both burning. It reads `_jaeger3d_active_plume_layer` now.

### 2. Behaviour

| state | clip | speed | notes |
|---|---|---|---|
| idle (no enemy in range) | **Walk** | 100 px/s | wanders to random points around the player, never past **300 px** |
| chase | **Run** | 200 px/s | straight at the target |
| attack | Kick / Low Kick / Slash | — | rolled per swing, unchanged damage arc |
| lunge_setup | Run | 200 px/s | backs off (or closes) to the punch's launch standoff |
| lunge | **Fly Punch** | — | holds position; the clip's own root motion flies the visual in |

### 3. Fly Punch

Two real bugs found on the way in.

* **The clip was never merged.** `_merge_jaeger_clip()` took the FIRST animation in the source glb, and `Fly punch.glb` ships two — `Armature|clip0|baselayer` (0.07 s, a stub) and `rigify_clip` (3.03 s, the actual lunge). It now takes the longest, which is a no-op for every other clip since they hold exactly one. Attack clips are also forced `LOOP_NONE`, or a looping clip would restart the lunge halfway through.
* **The launch distance is measured, not guessed.** The clip carries the character forward under its own root motion — Hips track, last key minus first, horizontal component: **1056 skeleton units**. Converting that to pixels is the fiddly half (glTF puts a 0.01 scale on the Armature, and `center_and_fit` scales again), so rather than hardcode the 0.01 the ratio is measured: the same skinned mesh bounded in both spaces (`instance_aabb()` is skeleton-space, `model_aabb()` is model-local), diagonals divided. Comes out **636 px** at the weapon's current 105 px size, and follows the weapon if it is resized.

Nothing moves `_yari_pos` during the lunge — the animation does the travelling. At the end the logical position jumps forward by exactly the clip's own travel, which is seamless *because* the clip then switches and the hips snap back to in-place: the two cancel. Damage lands as an impact circle at that point, at `YARI_PUNCH_MULT` × the normal hit, which is what pays for a long, fully telegraphed move.

If the standoff isn't reached within `YARI_LUNGE_SETUP_MAX` (4 s — backing off from attack range to ~640 px at 200 px/s is ~2.8 s), the lunge is **abandoned** rather than fired short. Firing from the wrong distance would fly the visual past the target and snap it back; an earlier draft committed to whatever distance it had reached and did exactly that.

### Verification

Live runs with state-transition logging: idle→Walk with max 277 px from the player, chase→Run at twice idle speed, attacks rolling, and a full `chase → lunge_setup → lunge → chase` cycle where the logical position jumped **635 px against a measured lunge of 635 px**, with no movement logged during the lunge itself. Per-layer plumes verified by seeding a TP on the Run layer: off while idling (Walk), on while chasing (Run), weapon's own set correctly suppressed. **That test TP was removed again** — both cfgs are back to what the user left them as.

### Gotcha for future cfg edits

`weapon_layout.cfg` can hold the SAME key twice in one section (the editor appends new creeps at the top while the old empty entry stays below), and ConfigFile takes the LAST one. A hand-seeded thrust point at the top of `[thrustpoints]` was silently shadowed by an empty `Run=Array[Dictionary]([])` further down. Edit the existing key; do not prepend.

## Changelog — 2026-08-23 (39th pass) — W/H resizes a live weapon without a restart; Jeager to 70%

"jeager tôi muốn nhỏ lại, còn khoảng 70% so với hiện tại. có cách nào để chỉnh in-game ko? hay phải chỉnh bằng code?"

In-game — W/H in Weapon Edit's TRANSFORM panel has been the arena size since the 37th pass. It just needed a restart to show, which was the wart this pass removes.

* `center_and_fit()` is **idempotent** now. Its centering was `position -= center`, which ACCUMULATED and walked a model off its own origin a little further on every call — so re-fitting an existing model was unsafe. `model_aabb()` deliberately excludes the model's own transform, so `center` is the same every time; assigning it absolutely is identical on the first call (position starts at zero for every caller) and a no-op afterwards.
* `_refit_3d_sizes()`, called from `reload_3d_weapon_layout()` (i.e. on every Save), re-fits every live 3D weapon. Two shapes: a real model node (Jeager, VIPER's heads/tails) is re-fitted in place; a MultiMesh weapon has no node — its fit lives in the `base` transform every per-instance write is multiplied by — so the glb is reloaded, fitted, and its base lifted out again. The Mesh resource is unchanged, so nothing else rebuilds. Plumes follow for free: `reload_3d_weapon_layout()` already rebuilds them from `display_px_for()`.
* Guarded by `_fitted_px`: a rotation-slider drag calls `_save_layout(true)` many times a second, and re-instantiating six glbs per tick for a size that has not moved would be a real cost for nothing.

### Jeager at 70%

150 → **105 px**, applied the same way the 37th pass's migration did — proportionally, not just the rect: TP X/Y re-derived so their FRACTION of the rect is unchanged, TP `z` and the style's `vel_min`/`vel_max` scaled by 0.7 (they are absolute lengths). Without that the exhaust would have kept its old absolute offset and length on a model 30% smaller, i.e. drifted off the thrusters — exactly the class of bug the 36th pass fixed for the shooter.

Verified live in one run: rendered at the saved 105, re-fitted to 150 and back to 105 through the same path a Save takes, with the plumes staying on the thrusters at every size.

## Changelog — 2026-08-23 (38th pass) — Jeager's animation glbs are editable layers, each with its own mount angle

"Khi tôi chọn jeager trong edit. Hiện các glb dưới dạng các layer cho tôi. Để tôi xoay nó cho đúng chiều / Hiện tại jeager đang bị bay ngược."

### Why it flew backwards

Jeager is ONE model — Walk.glb — with the other seven glbs' clips merged onto its skeleton (`_merge_jaeger_clip`), oriented by a SINGLE mount angle read from the `"Yari-Jeager"` cfg entry. The clips were authored facing different ways, so one angle cannot be right for all of them. Measured it rather than eyeballed: sampled `_yari_facing` against the actual per-frame travel vector and they agree (206.1° vs 205.6°) — the steering was never wrong. Rendering the rig with the travel direction drawn over it shows the exhaust plumes on the *same* side as the direction of travel: the thrusters fire forwards.

### Each clip is its own layer now

* `weapon_edit_mode.gd` scans `assets/weaponry/Jeager/` and accepts exactly the eight clip names, then parents them to `"Yari-Jeager"` in `_creep_parents` (`_auto_group_chain_names()` override, `super()` first so the VIPER chain is untouched). A plain LAYERS group — `_chain_id_for()` doesn't claim them, so no Segments/Spacing panel and no auto-arrangement.
* All eight joined `WIRED_3D_CREEPS`, so each gets its own Rotate X/Y/Z.
* **The previews animate.** New `_play_preview_animation()` runs on both the per-part thumbnail rig and the group overlay. Judging "is this clip facing the right way" from a bind pose is guesswork — a flight clip's whole point is the pose it holds mid-air. `PROCESS_MODE_ALWAYS`, because the editor holds the tree paused; and it prefers a plainly named clip over the glTF importer's `"Armature|…|baselayer"`, which is usually a concatenation of everything.
* New overridable `_default_creep_rect()` (was a hardcoded `(480,380)` + 60px in `_load_or_create_creep`): the eight clips would otherwise stack on one spot and the group overlay would draw them on top of each other, which makes it impossible to see which one a slider is moving. They land as two rows of four at 150px, clear of the control panels either side and of the weapon's own rect. First placement only — `_load_layout()` restores whatever you drag them to.

### Runtime

`JAEGER3D_CLIP_LAYERS` + `_jaeger3d_clip_cal`: each clip's mount angle and Z are read from its own cfg entry at setup (and on every Save, via `reload_3d_weapon_layout()`), and `_draw_yari()` picks the clip FIRST, then builds the carrier transform from that clip's calibration. A clip with no saved entry falls back to the weapon's own, so an untouched project renders exactly as before. `set_live_mount_cal()` accepts a clip name too, so dragging a slider updates the running game without a re-equip.

### Verified end to end

Seeded `"Fly"` with Rot Z 180°, booted, and re-rendered with the travel vector drawn on: the plumes flip to the far side of it — thrusters pointing backwards, flying forwards. **That test entry was removed again**; `weapon_layout.cfg` is untouched, since the request was for the control, not for me to pick the angle. Rot Z ≈ 180° on the `Fly` layer is what the measurement says it wants.

## Changelog — 2026-08-23 (37th pass) — shooter turrets follow the ship; the Weapon Edit W/H is the arena size now; Jaeger picks a random attack animation

### 1. Shooter turrets hold the ship's heading

They each used to ease toward their own nearest enemy at `SHOOTER_TURN_RATE`. They are hull-mounted pods, so they take `_player.rotation` directly — rigid, not eased: the ship's own aim is already smoothed and easing here would only make the pods lag the hull they are bolted to. `SHOOTER_TURN_RATE` is gone with the tracking it existed for. Aiming is untouched: `_shooter_fire_bolt()` picks and leads its own target and never read `rot`.

### 2. "Set Width 200 in edit but it's still tiny outside" — W/H is the arena size now

It was not a bug so much as a contract nobody could see: the Weapon Edit rect was documented as a pure editor **zoom**, and the arena size was a hardcoded const with no UI at all. Setting W did exactly what it appeared to do — nothing.

`display_px_for()` now takes the saved rect when there is one, with the consts as the fallback for a weapon that has never been placed. Every render and TP path routes through it (`center_and_fit` for VIPER x3 / Jaeger / Aliwa / the generic rigs, and all six TP loaders), so one number drives the model, the TP conversion and the editor alike. Gated on a weapon this file actually renders in 3D — a 2D weapon's rect is only a thumbnail size (missile's is 60x255) and must not escape into the editor's W/H sync.

**Left alone, this would silently have resized six weapons**, whose rects were the editor's 60px default rather than their real arena size. So it ships with a one-time cfg migration that writes each one's PREVIOUS arena size into its rect and rescales everything measured against that rect — TP positions (fraction held constant), TP `z`, and style `vel_min`/`vel_max` — so the rendered result is unchanged:

| weapon | rect | → | k applied to z / vel |
|---|---|---|---|
| ND-Aliwa-Bmr | 60 | 25.35 | 0.4225 |
| Swarmball | 60 | 20 | 0.3333 |
| Swarmbot | 60 | 24 | 0.4000 |
| shooter | 60 | 30 | 0.5000 |
| BC-SL-Spore | 62 | 18 | 0.2903 |
| VIPER body | 33 | 25.2 | 0.7636 |

VIPER head/tail already sat at 44 == their const. **Yari-Jeager was deliberately skipped** — its 150px rect is the authored intent, and it is now 150px in the arena (verified: ~15px before, filling its frame after). `[meta] size_space = "arena"` marks the migrated file.

Two things worth knowing: a size change needed the weapon re-equipped (or the run restarted) to show up, because `center_and_fit()` bakes the fit into the model/MultiMesh once at setup — **fixed in the 39th pass, it is live now**. And `snake_chain_geometry()` still takes VIPER's chain SPACING from the consts, so editing a VIPER part's W resizes the part without moving the chain's step.

Pleasant side effect: with rect == display size, `_tp_scale()` comes out 1.0 for every weapon, so the 36th pass's editor↔arena conversion is now an identity rather than something to get wrong.

### 3. Jaeger attacks with a random animation

`JAEGER3D_ATTACK_CLIPS = ["Kick", "Low Kick", "Slash"]`, rolled once when the sweep STARTS (`_yari_attack_clip`, set in `_tick_yari`) rather than per frame — rolling in `_draw_yari` would re-pick 60 times a second and never let a clip play. Falls back to `JAEGER3D_SWEEP_CLIP` if a clip failed to merge. Verified against the live `AnimationPlayer`: all three merged (`["Armature|walking_man|baselayer", "Dive", "Fly", "Fly Punch", "Kick", "Low Kick", "Run", "Slash", "Walk"]`) and three consecutive swings picked Slash / Slash / Kick with `current_animation` following each pick.

### Verification

Live runs, not parse checks. `display_px_for` re-read for all six migrated weapons plus Jaeger (only Jaeger moved: 32 → 150). Shooter turret captured from its own rig before and after: identical size and plume attachment, new heading, `rot == player.rotation - PI/2` confirmed numerically. Jaeger captured from its rig at the new size. `--headless --check-only` clean.

## Changelog — 2026-08-23 (36th pass) — boomerang trail, the TP-scale bug behind the shooter's floating plume, spawn-panel names, player ship in Weapon Edit

### 1. Boomerang: a real trail, and the spin back to its documented rate

* `BOOM_SPIN` `50.265` → `12.566`. 480 RPM → the 120 RPM its own comment and the tunables table had claimed all along (flagged in the 35th pass; confirmed as the intent).
* New per-style `trail` flag, read in `glb_topdown_rig.make_plume()`. `local_coords` has been TRUE for every plume since 2026-08-21, which continuously re-transforms *every live particle* by the emitter's current transform — correct for a flame pinned to a nozzle, but it means the plume can never fall behind the object, so a trail was impossible by construction. `trail` turns it off: particles freeze into world space at birth and the blade outruns its own wake. Opt-in per style, because the cost is the thing the 2026-08-21 note cares about — with it off, a live rotate-slider drag re-aims only newly born particles. For a wake that is correct behaviour, not a defect.
* `ND-Aliwa-Bmr`'s style: `lifetime` → **1.2 s**, `trail` → true.
* `make_plume`'s `amount` is a POOL SIZE, and CPUParticles emits `amount / lifetime` per second — so a long-lived style was quietly thinning into a dotted line (the 1.2 s trail would have been 10 particles/sec). It now scales with lifetime past the 0.6 s baseline to hold the emission RATE constant. Styles at or under 0.6 s are unchanged; longer ones get denser, which is what they were always asking for.

### 2. The shooter's plume floated a model-width off its nozzles — and the user's guess was right

"có phải do model size nhỏ quá?" — yes. Measured it rather than reasoned about it: rendered the same 120-px world window from the editor overlay and from the arena rig. Editor drew the drone at 60 px with the plume sitting on its engines; the arena drew it at 30 px with the plume a full model-width away.

The offset itself had not changed at all — **15 px in the editor, 15 px in the arena**. That is the bug. A TP's X/Y are stored as a FRACTION of the EO rect and multiplied by `display_px_for()` on the way out, so they shrink with the model. Its **`z`** (the PgUp/PgDn lift) was read RAW, and so were the style's `vel_min`/`vel_max`. 15 px is a quarter of a 60 px model and half of a 30 px one — and because the shooter is mounted at Rot X −90°, that lift is tipped into the screen plane where it reads as a plain gap.

Fixed at the conversion, not per weapon: `_tp_scale()` / `_tp_local_pos()` / `_tp_arena_style()` in `arena_weapons.gd`, and all **six** TP loader call sites (VIPER head/body/tail, Jaeger, Aliwa, the generic GLB3D rig) now go through them. Weapons whose EO rect already equals their display size (VIPER's parts, k = 1.0) are untouched by construction; Jaeger, Aliwa, Spore, Swarmbot and the shooter all move to where the editor has been showing them.

### 3. Weapon spawn panel

Yari Jeager was never missing — it is the last cell of the Drop tab. The cells were **icon-only**, and several icons don't look like what the arena draws (Jeager's is a ship with a blue blade; the arena draws a humanoid mech), so the grid could only be read by recognising art. Every cell carries its name now (48 → 62 px cells, one `WEAPON_CELL` const — the panel width and `_rebuild_weapon_grid()` had drifted apart, the grid was hardcoding 48).

Found while auditing it: **Defensive Orbitals' `def_id` was `"orbitals"`, which is not an ITEM_DEFS key** — `get_icon()` fell through to `_make_placeholder()` and that cell had been rendering as a blank grey square. Corrected to `defensive_orbitals`.

### 4. Player ship as a Weapon Edit entry, with a throttle-driven exhaust

The ship lives in `assets/defense/`, not `assets/weaponry/`, so the palette scans that folder too — and `_accept_file()` is folder-aware now (`(fname, folder)`) so the defence-track icons (`lv1..lv8`, `shield`) sitting next to it stay out. Palette: 22 entries, ship in, nothing else leaked.

`arena.gd::_load_ship_plumes()` builds the TPs as real 3D plumes under `_ship_pivot`, so they bank and light with the hull. **Sc-min = idle burn, Sc-max = full speed**, interpolated by an eased throttle (actual velocity against the current speed cap, so a shove or a smart-thruster dodge lights it too, not just a held key). Both ends of `scale_amount_*` are set to the same value on purpose — for a weapon that pair is a per-particle random range; here it is the two ends of the throttle curve.

Two things worth knowing while authoring it:

* the hull's orientation comes from AIM (`_update_ship_3d`), not from the cfg, so the Rotate X/Y/Z sliders turn the ship's **plume rig** (every TP together), not the hull. Still a real control, just not the same one a weapon gets.
* the editor previews TPs through a top-down ORTHOGRAPHIC camera while the ship viewport is PERSPECTIVE and tilted `SHIP_ISO_DEG`. A plume attaches to the right point of the hull and banks with it, but is not pixel-identical to the preview. Parenting under `_ship_pivot` buys correct compositing/lighting/banking, which for an exhaust matters more.

Verified with two temporary rear TPs (Sc 1.0 → 5.0, deliberately extreme): idle = two small quiet flames, moving = a full bloom, throttle 0.96. **Those test TPs were removed again** — `weapon_layout.cfg` / `weapon_plume_styles.cfg` are back to exactly what they were, so the ship's own plume is yours to author.

### Verification

Screenshots from the real game throughout, not parse checks: the boomerang trail curving behind the blade along its rose path; the shooter plume in the editor / arena-before / arena-after, same world window; the spawn panel with every name legible; the ship's exhaust idle vs moving. `--headless --check-only` clean.

## Changelog — 2026-08-23 (35th pass) — BC-SL-Spore joins the 3D panel; Aliwa's blade tumbles in 3D

### Spore: had the rig, was still missing everything the panel needs

`BC-SL-Spore` already had a live MultiMesh (`_setup_spore_3d`/`_update_spore_3d`, 2026-08-21) — it was held off `WIRED_3D_CREEPS` because that rig predated the generic one and lacked four of the five things the Rotate X/Y/Z panel actually depends on: no `z` lift, no `display_px_for()` entry (**so the editor converted its TP fractions against the generic 32 px fallback while the game drew at `PARA_DRAW` = 18 — a silent ~78% misplacement of every TP**), no 3D TP plumes, and neither `set_live_mount_cal()` nor `reload_3d_weapon_layout()` knew it existed.

Folded it into `GLB3D_WEAPONS` instead of re-implementing those four beside a near-duplicate rig — the old rig was already this exact shape (one MultiMesh, slot = the cloud's current index in `_para_clouds`, re-derived each frame so dynamic create/destroy needs no bookkeeping). Deleted: `SPORE3D_*` consts, nine `_spore3d_*` vars (one of which, `_spore3d_plume_pool`, was dead), and both functions. Region 900 and cap 8 carried over unchanged.

Untouched, as before: the gas-cloud/AoE VFX on expiry, the per-cloud 2D trail plume (`c["plume"]`), and the invisible hit-radius circle/arc in `_draw_para_cloud`.

### Aliwa: the blade only ever spun flat

`BOOM_SPIN` is a spin about the play-plane normal — the whole story while the blade was a 2D sprite, and it still read as a flat cut-out spinning on the spot now that it is a real model. Added the part only a 3D object can do: the blade also rolls about **the direction it is flying**, so it turns edge-on and back once per revolution and you see its thickness and both faces.

* `BOOM_ROLL_RPM` 45 — deliberately far slower than `BOOM_SPIN`. The fast spin is the "blade is whirling" read; this is the "and it is a solid object" read, and near the spin rate the two just fight.
* `BOOM_ROLL_PHASE` 1.05 rad per blade index, so a Split Blade / Chaos flock does not tumble in lockstep like one rigid object (a neat fraction of TAU would re-sync them every few revolutions).
* The tumble axis is the bearing actually walked this frame (`b["travel"]`, from the step between positions) rather than a differentiated rose curve — stays correct through the Death Roll snap-back and any future change to the flight path.
* Composed via the existing `_snake3d_roll_xform()`, which already does "spin about the world vertical, then roll about a bearing in the play plane" for VIPER's body. One definition, two weapons. The plume anchor uses the same `_boom3d_xform()` as blade 0's own instance — it is attached to the blade, so it has to tumble with it.

**Note for tuning:** `BOOM_SPIN` was `50.265` rad/s = **480 RPM**, while its own comment and the tunables table in this doc both said "120 RPM (4π)" — the value was `16π`, 4× the documented figure, and the comment had gone stale. The value was left alone in this pass (changing it changes feel, which was not the request) and the flag raised; **the 36th pass took it back to 12.566 / 120 RPM on request.**

### Verification

8 consecutive frames of blade 0, cropped straight out of the Aliwa SubViewport, show the blade both rotating in plane and foreshortening to edge-on and back — the tumble is real, not just the old flat spin. Spore verified twice: the 3D VIEW / MOUNT ANGLE section now renders for it in Weapon Edit, and a live run confirms `_glb3d` holds `BC-SL-Spore` and the pellet draws from the rig once a cloud spawns. All seven 3D weapons render whole in the editor with no square crop. `--headless --check-only` clean.

## Changelog — 2026-08-23 (34th pass) — 3D weapons were being clipped by their own frame; Swarmball/Swarmbot/shooter promoted to real 3D

Three separate reports, one of which turned out to be two different bugs wearing the same symptom ("vũ khí bị clip trong 1 frame vuông nhỏ").

### 1. Yari-Jeager rendered ~100× too big — in the arena as well as the editor

`glb_topdown_rig.gd::model_aabb()` measured every mesh with `MeshInstance3D.get_aabb()`. For a **skinned** mesh that number describes the *bind-space* box, not what the renderer draws: the vertices are placed by `bone_global_rest * bind_pose * v`. Yari-Jeager.glb is the only skinned weapon in the folder — glTF import gave it an `Armature` scaled `0.01` with bone rests around `100×` to match — so the measured box came out at 1.7 units while the drawn character is ~190. `center_and_fit()` then scaled *up* by that factor: **model scale 5734 where it should have been 57.3**, i.e. a small central crop of the character filling the entire frame.

Fixed with a real skinned-bounds pass (`instance_aabb()`): skin each vertex by its own bones at the **rest** pose and take the box of the result. Per-vertex rather than a union of per-bone boxes, which on a 24-bone humanoid would over-cover badly and shrink the model instead; rest pose rather than the live animation frame, or the fit would breathe and the weapon would pulse on screen. Cached per `Mesh` — it walks every vertex and several callers re-fit the same mesh.

Measured before/after, by rendering each model into a 512-px frame at `center_and_fit(model, 100)` and reading the alpha bbox:

| model | before | after | expected |
|---|---|---|---|
| Yari-Jeager | 512×512 (clipped) | 92×40 | footprint diag 100 ✔ |
| VIPER head top | 48×87 | 48×87 | unchanged ✔ |
| ND-Aliwa-Bmr | 99×16 | 99×16 | unchanged ✔ |

### 2. ND-Aliwa-Bmr: the editor thumbnail was fitted at rotation zero

Two compounding faults, both editor-side:

* `_fit_preview_cam()` measured the silhouette via `silhouette_extent(model, …)`, which knows nothing about `rot_pivot` — so the frame was fitted to the model **unrotated**. Aliwa sits at −79/95/105°, presenting a much wider silhouette, and its ends were sliced off square. (This is the same "khung crop" reported on 2026-08-22; the bounding-sphere fix then was replaced by the tight per-view fit in the 25th pass, which reintroduced it.) `silhouette_extent()` now takes an optional `pre` transform and gets the pivot's; `_glb_apply_rotation()` re-fits so the frame keeps up while a slider is dragged. Tight **and** uncroppable.
* That thumbnail should not have been the thing on screen at all. `_set_active_creep()` called `_refresh_glb_view_ui()` — the only writer of `_active_glb_path` — *after* `_update_grid_overlay()`, and `_build_plume3d_preview()` bails on an empty path. So the **first** 3D weapon selected in a session got no 3D overlay and fell back to its flat thumbnail; every later switch worked only because the previous weapon's path was still in the variable. `_refresh_glb_view_ui()` hoisted above the overlay rebuild — nothing in between reads that variable.

### 3. Swarmball / Swarmbot / shooter now have the 3D VIEW / MOUNT ANGLE panel

They ship as `.glb` but were drawn as flat `draw_texture_rect` sprites, which is exactly why `WIRED_3D_CREEPS` withheld the panel: the sliders would have written a mount angle nothing read. Added the missing runtime half — `GLB3D_WEAPONS` in `arena_weapons.gd`, one generic MultiMesh-in-a-SubViewport rig (`_build_glb3d_rig` / `_update_glb3d` / `_build_glb3d_plumes`) shared by all three. It is Aliwa's rig generalised over a name: same shape of problem (N identical instances, each a position + a facing), so no fourth copy. VIPER/Jaeger/Aliwa keep their bespoke rigs — each has machinery (chain geometry, an AnimationPlayer, per-blade taper) the generic one has no concept of.

Wired end to end: `display_px_for()` reports their size to the editor, the 2D `_register_plume` registration is skipped when the rig is up (same branch Jaeger/Aliwa already use), `set_live_mount_cal()` and `reload_3d_weapon_layout()` cover them, and TPs placed in Weapon Edit build real 3D plumes.

`weapon_layout.cfg` got a starting mount angle of **Rot X −90°** for the three. Their glbs are authored standing up in Y, so at 0° a top-down camera sees them edge-on — the shooter rendered as a 2-px sliver. −90° is the family default (Aliwa −79°, Spore −41°, VIPER Tail base −87°). Written to the cfg rather than defaulted in code deliberately: the editor and the game must read one source, or they disagree.

**`missile` was asked for in the same breath but is not included** — `assets/weaponry` has `missile.png` only, no `missile.glb`. There is nothing to render in 3D, so it stays on the flat sprite + flat TP path.

### 4. Weapon Edit palette

The palette heading said **ENEMIES** — the panel is the creep editor's by origin, but pointed at `assets/weaponry` here. New `_palette_title()` hook; the weapon editor returns "WEAPON". And `"VIPER head side"` joined `_SKIP`: an alternate side-on art variant nothing renders (the live weapon draws `VIPER head top.glb`), so it was only a decoy next to the real head. Skipping it in the scan also stops `_load_layout()` placing its stale cfg entry, since that walks the scanned name list. Palette verified at 21 entries with it gone.

### Verification

Not a parse check alone. `tools/screenshot_weapon_edit_3d.gd` and `tools/screenshot_arena_3d_weapons.gd` (both new) boot the real arena, open Weapon Edit / grant the weapons, and screenshot: all six 3D weapons render whole in the editor with no square crop, and in play Yari-Jeager draws at ~30 px instead of covering the screen while the swarm and both turrets draw as 3D models.

## Changelog — 2026-08-23 (33rd pass) — VIPER's level-up perk cards showed a spinning 3D head instead of their own perk art

One wrong string. `arena_levelup_ui.gd`'s `WEAPON_PERK_FOLDER` mapped `"viper": "viper"`, but the art folder on disk is **`assets/hud/weapon perks/snake/`** — the weapon was renamed to VIPER, the folder was not.

The knock-on: a pool-perk card only skips the 3D icon swap when `_weapon_perk_icon_tex()` finds its own art (`is_own_perk_icon`). With the wrong folder that lookup missed for every VIPER perk, so `is_own_perk_icon` came out false and `_make_weapon_icon()` ran — which resolves the *parent weapon's* glb and renders a live, rotating VIPER head on all six cards.

This was latent long before the 3D icons: the miss used to fall back to the parent weapon's flat PNG, which looked plausible enough to go unnoticed. Making weapon icons live 3D renders is what turned a quiet wrong-icon into an obvious one. `weapon_info_panel.gd` has always had `"viper": "snake"` — the two maps had simply drifted.

**Checked the whole map rather than just VIPER**, since a silent fallback hides this class of bug by design. Two more entries pointed at folders that do not exist:

| kind | was | is |
|---|---|---|
| `viper` | `viper` (missing) | `snake` |
| `ultrasonicator` | `ultrasonicator` (missing) | `sonic` |
| `aliwa` | `aliwa` (missing) | `boomerang` |

After the fix: all 17 entries resolve to a real folder; the two maps agree on all 17 shared kinds; and VIPER's six perk keys (`damage`, `hemophilia`, `length`, `serrated_fang`, `serrated_scale`, `speed`) each resolve to an existing PNG in `snake/`.

`godot --headless --check-only` clean (full boot). Verified against the filesystem, not by reading the code.

## Changelog — 2026-08-23 (32nd pass) — freeze fix: the new VIPER target lock held a Node reference across frames

`_snake_pick_target()` (31st pass) stored the chosen enemy as an object reference in `_snake_targets`, and read it back the next frame with

```gdscript
var cur: Node = _snake_targets[chain_idx] if chain_idx < _snake_targets.size() else null
```

The moment that enemy died — the normal case, several times a second — that line threw **"Trying to assign invalid previously freed instance"** and hung the frame. Reported at arena_weapons.gd 9233 with 9266 / 9181 / 9162 / 3161 above it in the stack: `_process` → `_tick_snake` → `_run_snake` → `_snake_move` → `_snake_pick_target`.

**`is_instance_valid()` cannot fix this.** The throw happens on the assignment itself, before any guard in the body could run. The target is now held as an **instance ID** (`Array[int]`, 0 = none) and resolved fresh each frame:

```gdscript
if cur_id != 0 and is_instance_id_valid(cur_id):
    cur = instance_from_id(cur_id) as Node
elif cur_id != 0:
    _snake_targets[chain_idx] = 0   # it died; drop the lock
```

An int can never be a freed instance, so the failure is gone by construction rather than by guarding. Verified with a headless probe that frees the target mid-run: the lock is held while alive, dropped cleanly on the frame it dies, re-picked after, five frames with no throw.

**Same defect found in three other places** while checking for it. A typed loop variable binds each element *before* the body runs, so `for pivot: Node3D in pivots: if is_instance_valid(pivot):` throws on a freed entry exactly the same way — the guard never gets the chance. Switched to untyped loop vars with a cast at the point of use:
- `set_live_tp_direction()` — the live plume pivots the weapon editor drives on every slider tick;
- `_setup_snake_3d()`'s body-plume-anchor teardown;
- `_reset_weapons()`'s plume-registry anchor sweep.

These hold nodes this file owns, so a stale entry is much less likely than a dead enemy — but the cost of being safe is one keyword. A comment in `reload_3d_weapon_layout()` that explicitly claimed stale refs "wouldn't have caused a crash" was wrong on the same grounds and has been corrected.

`godot --headless --check-only` clean (full boot).

## Changelog — 2026-08-23 (31st pass) — VIPER retargeted as a guard: it defends the ship instead of hunting whatever is nearest its own head

VIPER used to steer at `_nearest_enemy(head, INF, [])` — whatever was closest to **its own head**, at unlimited range. That made it a hunter: it would happily follow a lone straggler out to the end of its 1000px leash while something closed on the ship behind it. `_snake_pick_target()` replaces that with a score minimised over every candidate:

```
score = distance(enemy, PLAYER) + SNAKE_REACH_WEIGHT * distance(enemy, head)   [+ ruin penalty]
```

The **leading term is distance to the player** — how dangerous the thing is — so VIPER commits to whatever is closing on the ship. The head-distance term (weight 0.35) only settles near-ties, in favour of the target it can reach soonest, so it doesn't cross the whole screen past an equally threatening one.

The case this is for, measured: head out at 700px, a straggler 80px from the head but 780px from the ship, a threat 120px from the ship. Straggler scores 808.0, threat scores 323.0 → it turns back and defends. The old logic picked the straggler.

Reach still wins the close calls: against a target 300px from the ship and 500px from the head, one at 320px from the ship but only 80px from the head is preferred (348.0 vs 475.0); push the rival out to 600px from the ship and the more threatening one wins again (475.0 vs 670.0).

**Guard radius.** Anything beyond `SNAKE_GUARD_RADIUS` (900px) of the ship is ignored outright — the chain is leashed to 1000px of the player anyway, so chasing further just abandons the ship for something it cannot reach. With nothing in radius the head returns to its idle orbit around the ship, which is the right resting behaviour for a guard and is the same fallback as before.

**Ruins are a strict last resort.** A ruin is destructible scenery, not something closing on the ship, so killing it does not protect anyone. `SNAKE_RUIN_PENALTY = 2000` is chosen to exceed the largest score anything in radius can reach (`900 + 0.35 × 1900 = 1565`), which makes it a tier rather than a lean — verified: a ruin 10px from the ship (2076.5) still loses to an enemy 890px away (1131.5). A first attempt at 600 was only a nudge and left a ruin 200px out beating an enemy at 700px.

**Hysteresis.** `SNAKE_TARGET_STICKY = 0.75` — a rival must score below 75% of the current target's score to steal the lock. Without it two similarly-scored enemies swap the lock every frame and the head jitters between them instead of committing. Target is tracked per chain (`_snake_targets`, index 0 = main, 1 = the More Snakes evolve).

Unchanged: the Predator fusion passes an explicit `aim_angle` (the densest beam line), so it never reaches the target picker and keeps its own aiming. Bite/damage resolution is untouched — this only changes what the head steers at.

`godot --headless --check-only` clean (full boot); every figure above from a headless probe over the scoring function. **Feel needs playtesting**: `SNAKE_REACH_WEIGHT` is the dial between "defends stubbornly" (lower) and "opportunistic" (higher), and `SNAKE_GUARD_RADIUS` sets how far it will leave the ship at all.

## Changelog — 2026-08-23 (30th pass) — VIPER head banks into its turns; body roll lag set to 0.2 s per node

**Body stagger.** `SNAKE3D_ROLL_LAG` 0.07 → **0.2 s**, per request: body 1 starts at 0 s, body 2 at 0.2 s, body 3 at 0.4 s, and so on. At 12 rpm that is 14.4° of phase between neighbours — body 5 trails body 1 by 57.6°, so the roll now reads as a visible wave running down the snake instead of a near-uniform turn.

**Head bank.** The head no longer just points along its heading: when VIPER turns it leans, rolling about the **same axis the body segments roll about** — the chain's long axis. At the full turn rate it leans by the CHAIN panel's own Bend value read as an angle (30° today), scaling linearly to 0 when travelling straight, so that one slider now sets both how sharply VIPER can turn and how hard it leans doing it.

| turn rate | lean |
|---|---|
| 0% of Bend | 0.0° |
| 25% | 7.5° |
| 50% | 15.0° |
| 100% | 30.0° (−30.0° the other way) |

The lean eases toward its target rather than snapping — 47% of the way in 0.10 s, 96% in 0.50 s (`SNAKE3D_BANK_SMOOTH = 6.0/s`), so a twitchy heading can't make the head jitter.

**The part that needed care.** The head is *mounted* at `dir + PI/2`, not `dir` (a convention `_snake3d_update_chain` has always had). Rolling it about its own post-yaw RIGHT — the obvious thing, and what the body helper did — would have spun it about an axis **90° off the snake** at every heading. Measured: the naive axis gives `|dot| = 0.00` against the head→tail line at all five bearings tested. So `_snake3d_body_xform()` was generalised into `_snake3d_roll_xform(pos, ang, axis_ang, cal, z, roll)`, taking the model yaw and the long-axis bearing separately — identical for a body segment, different for the head. Verified `|dot| = 1.00000` against the head→tail line at bearings 0° / 37° / 90° / 143° / −120°, worst deviation 0.000000.

`dir` is the headward bearing at the head, matching the body's own `(pts[k−1] − pts[k+1])` convention, so a positive lean means the same visual direction on every part. The roll is still pre-multiplied in world space, so the authored mount calibration cannot tilt the axis.

Bank state is per chain (`_snake3d_prev_dir` / `_snake3d_bank`, index 0 = main, 1 = the More Snakes evolve) and the previous heading starts at `INF` meaning "none yet", so the first frame after a spawn cannot read a bogus turn rate off a stale heading.

`godot --headless --check-only` clean (full boot); figures above from a headless probe against the real saved calibration and the live Bend setting. **On-screen appearance still needs your eyes** — if the lean sits the wrong way round it is a single sign on the `roll` argument, and `SNAKE3D_BANK_SMOOTH` is the one number for how quickly it leans.

## Changelog — 2026-08-23 (29th pass) — VIPER body segments roll about the chain's long axis, 12 rpm, staggered

Per request: on the arena, every BODY segment spins about the head→tail line at one shared rate, each starting slightly after the one ahead of it. Head and tail do not roll.

| | |
|---|---|
| `SNAKE3D_ROLL_RPM` | **12.0** — one full turn every 5.00 s (1.25664 rad/s) |
| `SNAKE3D_ROLL_LAG` | **0.07 s** per segment = 5.0° of phase; a wave crosses a 6-segment body in 0.42 s |
| axis | the chain's own long axis at that segment, not the model axis and not the world vertical |

**Where the roll composes, and why it has to go exactly there.** `_snake3d_world_xform()` builds `Basis(UP, −ang) · view_basis(cal)`, and `Basis(UP, −ang) · RIGHT` *is* the chain's direction at that segment: `Basis(UP, θ) · X = (cos θ, 0, −sin θ)`, so at θ = −ang it comes out as canvas `(cos ang, sin ang)` — the 2D bearing itself. A rotation by φ about a world axis `M·RIGHT` is `M · R_RIGHT(φ) · M⁻¹`, which applied to `M · view_basis(cal)` collapses to `M · R_RIGHT(φ) · view_basis(cal)`. So slotting the roll **between the chain yaw and the mount calibration** is a true spin about the long axis — for any chain bearing, and without disturbing the mount angle authored in the editor.

Verified rather than assumed. Measured axis vs the head→tail direction at bearings 0° / 37° / 90° / 143° / −120°: `|dot| = 1.00000` at every one, rotation-angle error 0.0000°, worst deviation 0.000000. Repeated with three mount calibrations including VIPER body's real authored `(82.0, −176.2, −92.7)`: `|dot| = 1.00000` in all cases — the roll is independent of `cal`, which is what lets you keep tuning the mount angle without touching this.

New `_snake3d_body_xform()` (the plain `_snake3d_world_xform()` plus the roll) is used by both the MultiMesh segments and the body plume anchors, so a rolling segment carries its plumes around with it instead of leaving them behind. Both chains get it — the main one and the More Snakes second chain — since both go through `_snake3d_update_chain()`.

The clock is accumulated from `delta` after the pause guard, not read off a wall clock, so a paused arena shows a still snake rather than one that jumped ahead while you were in a menu. Editor-preview only shows the static pose; the roll is a gameplay visual.

`godot --headless --check-only` clean (full boot). The numbers above come from a headless probe driving the real `glb_topdown_rig.gd` against the real saved calibration; **on-screen appearance still needs your eyes.** If the wave reads too fast or too subtle, `SNAKE3D_ROLL_LAG` is the one number to turn — larger drags the wave out down the body, 0.0 makes every segment roll in lockstep.

## Changelog — 2026-08-23 (28th pass) — moving one layer moved the whole weapon; TP nudge keys were working in the model's local frame

**1. Selecting the body and nudging moved head and tail too.** My own over-correction. The 25th pass made every chain slot's position DERIVED on each rebuild, so a per-part nudge could not survive; the 27th pass then redirected the nudge to the group anchor so it would at least do something — which moved the whole weapon. Both are wrong: selecting one layer and pressing an arrow must move that layer.

Reverted to authored positions, with the arena formula as the thing that **seeds** the layout rather than one that overwrites it every frame:
- `_auto_arrange_chain_templates()` lays the real head / body / tail out on the game's own uniform centre-to-centre step (scaled by the authored zoom), and puts the tail at the end of the *whole* chain rather than after the last template.
- It re-runs whenever Segments / Spacing / Taper changes (`_on_chain_field_changed` clears the once-per-root latch), because those change what the game's layout *is*.
- Between those, positions are yours — arrows, drag and the X/Y spinboxes all stick.
- Generated duplicates stay derived; they have no identity of their own.

This still fixes the original "đầu bị nằm giữa body": that came from two different, both-wrong step formulas, not from the positions being authored. Only for chains with an arena authority — an enemy chain's hand-placed layout is never reset.

**2. Arrow keys and PgUp/PgDn were swapped for some parts.** A TP pivot is a **child** of its part node, so the part's mount rotation is applied to whatever offset is stored — but the keys were adding straight to the stored, model-local fields. Measured on the saved data:

| part | arrow Down → | PgUp → |
|---|---|---|
| VIPER Tail | altitude **1.00**, canvas 0.05 | canvas **1.00**, altitude 0.05 |
| VIPER body | altitude −0.99 | canvas +0.99 (sideways) |
| ND-Aliwa-Bmr | canvas 0.74 / altitude 0.67 | canvas 0.67 / altitude 0.74 |

VIPER Tail's mount rotation is ~90° about X, which exchanges its local canvas-Y with its local altitude outright — so the arrow keys changed height and PgUp/PgDn slid the plume across the play plane, exactly as reported.

`_tp_xyz_get()` / `_tp_xyz_set()` now work in **editor world space** (X right on the canvas, Y up on the canvas, Z the true altitude) and rotate through the part's mount basis on the way in and out; both key handlers go through them. Stored data is unchanged — only the frame the controls speak in. A creep with no 3D rig gets an identity basis, so every 2D creep behaves exactly as before.

Verified per part against the real saved rotations: arrow Up → canvas (0, −1.00), altitude 0.00; arrow Right → canvas (1.00, 0), altitude 0.00; PgUp → altitude 1.00, no play-plane movement. Clean for head, body, Tail, Aliwa and Jaeger. The X/Y/Z spinboxes now read in that same frame, so they and the keys agree.

`godot --headless --check-only` clean (full boot).

## Changelog — 2026-08-23 (27th pass) — arrow keys looked dead: the transform paths never told the 3D overlay anything had moved

Two causes, both fallout from the overlay becoming the only picture of a 3D part.

**The view was never told.** Mouse dragging has always ended in `_follow_chain_on_move()` (`_on_transform_motion`); the arrow-key branch never did, and never needed to — the part's own flat thumbnail moved with its rect and showed the edit by itself. That thumbnail is hidden now (23rd pass) and the overlay draws the part, so the rect moved under an unchanged image and the keys looked dead. The part really was moving; nothing redrew.

**The nudge landed on a derived node.** For an arena-authored chain every slot's position is computed from the head anchor on each rebuild (25th pass), so a nudge to a body or the tail was undone by the next one. Arrow keys now apply to the **anchor**, moving the whole assembly — the only thing "move this part" can mean when the game does not read per-part positions.

Fixed at the choke point rather than per call site: `_follow_chain_on_move()` / `_follow_chain_on_resize()` used to no-op entirely outside an active CHAIN section, and now refresh the overlay on that path. Every transform edit already funnels through those two — verified: `_on_transform_motion`, `_on_transform_ended`, `_apply_spin_to_selected`, `_apply_group_move`, `_apply_group_scale` and the arrow keys all reach them. That also closes the same latent gap for the non-chain 3D weapons (Yari-Jeager, Aliwa, Spore), where dragging or typing X/Y would have looked equally dead. `_rebuild_chain_preview()` already ends with that refresh, so the chain path does not do it twice.

Also added `_group_root_of()` for the "parent or self" idiom this file repeats in several places.

Verified with `godot --headless --check-only` (clean, full boot) and a source check that all six transform paths reach the choke point and both choke-point functions refresh the overlay when there is no chain.

## Changelog — 2026-08-23 (26th pass) — regression sweep over Weapon Edit: W/H edits were being overwritten, the assembly had drifted off-canvas, and the overlay rendered at 1 texel per pixel

Three things the 23rd–25th passes broke or left broken, plus the audit that found them.

**W/H edits silently reverted** ("chỉnh lên 33, bấm save, tắt rồi mở lại vẫn là 25"). `_sync_arena_part_size()` — added in the 23rd pass — forced every 3D part's rect to the size the game draws it at, on **every** open, before anything else ran. The save had worked; the next open overwrote it. **Removed entirely.**

Nothing is lost by removing it. A part's rect is a **zoom** on the game's geometry, not a competing definition of it: the overlay draws the model to fill the rect, and a thrust point is placed at `(frac − 0.5) × rect`, which is exactly the arena's `(frac − 0.5) × display_px` scaled by that same zoom — so a TP sits on the identical spot of the identical model either way. The zoom only affects how parts relate to **each other**, so the chain step is now multiplied by the body's zoom (`_chain_zoom()`): leave the parts at their in-game sizes, or scale them by a common factor, and the row is arena-exact. Replayed against the live data — body rect 33 vs game 25.2 → zoom 1.310, step 18.90 × 1.310 = 24.75 px, slots at 200.0 / 224.8 / 249.5 / 274.2 / 299.0 / 323.8 / 348.5 / 373.2.

**The whole weapon had drifted off-canvas** ("vị trí đặt object khi mở edit weapon thì bị lệch tít lên xa"). VIPER's head had reached y = −163 on a 1440×780 canvas — entirely above the top edge — and since every other slot is laid out relative to the head, the weapon was invisible and unreachable. Contributors: the group-rotation orbit (removed for arena chains in the 25th pass), group resize scaling positions about the anchor, and `_sync_arena_part_size` moving parts as it resized them. Head anchor reset into view, and a new `_recover_offcanvas_group()` runs on open: if a group's bounding box does **not intersect the canvas at all** it is translated rigidly back to the centre (points included) and says so in a toast. Deliberately conservative — a half-offscreen layout is left alone, and no internal geometry changes.

**"Các hình rất mờ" was resolution, not lighting.** The overlay rendered the whole screen at `cam.size = screen.y` into a screen-sized SubViewport — 1 world unit = 1 texture pixel, so a 44 px VIPER head got exactly 44×44 texels. The per-part thumbnail it replaced was a 512 px render squeezed into that same 44 px rect: more than 10× the sampling, and still sharp when the canvas is zoomed. The headlamp added in the 24th pass was a genuine omission but not this.

Fixed by framing only what must be visible and spending the pixels there. A square frame of radius (half the group's bbox **diagonal** + a 220 px plume allowance) cannot clip at any view angle — orbiting is a rotation about the pivot, so a point at radius r stays at radius r. For VIPER that is a 662 px frame rendered into 2048², i.e. **3.10× supersampling**: the head now gets ~136×136 texels instead of 44×44, downsampled with mipmapped linear filtering. Capped at `PLUME3D_MAX_TEX` so a large group degrades toward 1× rather than allocating an enormous target. Game-view pixel-exactness is unchanged: the pivot still projects to the frame centre and the layer is still offset by half the frame.

**Also found in the sweep:** the overlay framed and pivoted on `_creep_group_bbox()`, which walks `_creep_group_members()` and therefore **excludes the generated chain duplicates**. VIPER gets away with it because its tail is a real member sitting at the far end, but a chain with no tail would have had its duplicates clipped. The overlay now uses `_group_render_bbox()`, over exactly what it draws.

**Known and intended, not a regression:** dragging or typing X/Y for a body or the tail of an arena-authored chain snaps back on the next rebuild. Those positions are derived from the game's spacing (25th pass) because the game does not read them. The **head** is the anchor — drag it, or use the group row's X/Y, to move the assembly.

Verified with `godot --headless --check-only` (clean, full boot) plus a static replay of the full chain-layout pipeline over the real `weapon_layout.cfg` / `creep_chain_overrides.cfg` (slot table and frame/resolution figures above), and a 10-point regression checklist over the source — all pass. On-screen behaviour still needs your eyes: headless Godot cannot instantiate this editor.

## Changelog — 2026-08-23 (25th pass) — the real reason the editor stayed wrong: for a chain weapon, part positions were AUTHORED data, and the game never reads them

The 23rd pass corrected the layout *formula*. That was not enough, and this is why.

**The editor only ran the formula once.** `_rebuild_chain_preview()` recomputed the generated DUPLICATES on every rebuild, but the real head / body-template / tail hit `cur_eo = template_eo  # untouched — fully user-owned position`. Their coordinates came from `weapon_layout.cfg`, seeded once per session by `_auto_arrange_chain_templates()` and then moved by anything at all — a drag, a group-rotation orbit, or a layout saved by an earlier build's broken step rule. Whatever ended up in the file is what got drawn, however correct the formula had become.

**The game does not read those coordinates.** `arena_weapons.gd` reads a part's saved `pos`/`size` for exactly one purpose: converting a thrust point into a fraction of its own rect (`_load_snake_plume_3d`). Segment placement comes wholly from `pts[]` and `SNAKE_SPACING` (`_run_snake` seeds `pts[k] = base − spacing·k`; `_snake3d_update_chain` puts head at `pts[0]`, bodies at `pts[1..n−2]`, tail at `pts[n−1]`). So a hand-authored position for a chain part is not data the game respects — and the editor was presenting it as though it were.

Measured from the actual file, at the live settings (segments 8, spacing× 0.75 → 18.90 px step):

| | arena | editor (authored) |
|---|---|---|
| head → body1 | 18.90 px | **121.10 px** |
| head → tail | 132.30 px | **146.71 px**, and on the *opposite* side from the body |

**Fix: for a chain with an arena authority, positions are derived, not authored.** Every slot — templates included — is now computed on every rebuild as `head_centre + axis · step · i`, with the tail at `body_count + 1`. The head's own position stays user-owned and acts as the anchor, so dragging the head still moves the whole assembly; dragging a body or the tail snaps back on the next rebuild, which is the honest signal that the game does not read that position. Chains with **no** authority — every enemy — keep the old behaviour exactly, because their arena layout genuinely is hand-placed per map.

Verified against the same settings: editor slot offsets 0 / 18.90 / 37.80 / 56.70 / 75.60 / 94.50 / 113.40 / 132.30 with sizes 44 / 25.2×6 / 44 — the arena's own sequence, same order, head first, tail last.

**Two related editor inventions removed for such a chain:**
- The row no longer swings with the mount rotation. In game the chain's path comes from where the weapon has travelled; the calibration `cal` enters `_snake3d_world_xform` only as a BASIS and never touches an origin. The Rotate sliders still turn each part in place — which is all `cal` does — but the row itself stays on a fixed axis.
- `_apply_group_rigid_delta()` returns early: there is no rigid block to orbit when the layout is a formula. The caller still writes each member's `rot`, so slider behaviour is unchanged apart from parts no longer drifting off the chain.

`_auto_arrange_chain_templates()` also returns early for these chains — a one-time seed for a layout nobody owns is just a second, differently-computed arrangement living for the few statements until the derive loop overwrites it.

Verified with `godot --headless --check-only` (clean, full boot) plus a static replay of both layouts over the real `weapon_layout.cfg` / `creep_chain_overrides.cfg` (numbers above). **Still not verified on screen** — headless Godot cannot instantiate this editor. Please reopen Weapon Edit on VIPER: one evenly-spaced row, head at the front, tail at the end, 8 slots.

## Changelog — 2026-08-23 (24th pass) — chain duplicates vanished and the parts rendered dim: `duplicate()` never copied `source_path`, and the overlay had no headlamp

Two regressions from the 23rd pass, both from the overlay becoming the sole renderer and inheriting things the thumbnails had been quietly covering for it.

**1. "Chỉ còn 1 head, 1 body (mất hết segment) và 1 tail."** `Node.duplicate()` copies child nodes and EXPORTED properties. A plain (non-`@export`) GDScript member has no `PROPERTY_USAGE_STORAGE`, so it is **not** carried over — verified directly:

```
template  : source_path='res://assets/weaponry/VIPER body.glb'  group='weaponry'  display_name='VIPER body'
duplicate : source_path=''                                      group=''          display_name=''
```

So every chain duplicate this editor has ever made was anonymous. It never showed, because nothing asked a duplicate what it *was* — its `TextureRect` child carries `texture`, which *is* exported, so the picture came along for free. The moment the 3D overlay started rendering duplicates it did ask, hit `"".get_extension() != "glb"`, and skipped all of them — while `_sync_flat_thumbnails()` had already hidden their thumbnails as "covered by the overlay". Result: the three templates alone on screen.

Fixed at the source in `_make_chain_dup_eo()` (copy `source_path` / `group_id` / `display_name`), not in the one caller that noticed. The overlay additionally resolves a duplicate's asset through its TEMPLATE (`_chain_data_name`), so a future regression there can't blank the chain again.

**2. "Cả 3 đều rất mờ."** `glb_topdown_rig.make_camera()` bundles a camera-aligned `DirectionalLight3D` at energy 1.6, and `_load_glb_topdown_tex()` adds its own copy, precisely because `build_lighting()`'s two fixed directional lights graze most models. The full-screen overlay builds its camera by hand and never got one — invisible while it was only drawing plumes over crisp thumbnails, glaring once it became the only renderer. Added. (Brightness could not be measured headlessly: the dummy renderer returns no viewport texture, as `docs/core.md` already notes.)

Also fixed while in there: `_fit_preview_cam()` re-aims a thumbnail rig's camera on every view change but never its stored headlamp, so orbiting progressively darkened the thumbnails. Only reachable now for a glb part the overlay isn't covering, but it is the same bug.

Verified with `godot --headless --check-only` (clean, full boot) plus a headless probe on the real `editable_object.tscn` for the duplicate-identity behaviour and its fix (output above). Please reopen Weapon Edit on VIPER: all 8 segments present, parts lit like the old thumbnails were.

## Changelog — 2026-08-23 (23rd pass) — editor and arena now render a 3D weapon from ONE source; VIPER's head no longer lands inside the body run

"Có sự sai lệch giữa weapon hiển thị trên arena và trong weapon edit… tôi muốn lấy nguồn dữ liệu hiển thị từ cùng 1 nguồn." The editor was carrying its own copies of every display number, and they had all drifted.

**What diverged, measured against `weapon_layout.cfg`'s real VIPER data:**

| Quantity | Arena | Editor (before) |
|---|---|---|
| head→body centre distance @ Spacing 1.0 | 25.20 px | **63.00 px** (head rect edge → body rect edge) |
| body→body centre distance @ Spacing 1.0 | 25.20 px | **46.00 px** (mean of the two rect heights) |
| part display size (head / body / tail) | 44 / 25.2 / 44 | 80 / 46 / 60 — and not even a common scale factor |
| VIPER Tail `tp_1` position on the model | (14.16, 71.16) | **(19.31, 97.03)** — 26.38 px away |

The two step rules also disagreed with **each other**: the one-time template arrangement stepped by rect edges and always straight DOWN, while the generated duplicates stepped centre-to-centre along the group's *rotated* chain axis. Once the group was rotated the templates and the duplicates ran in different directions — which is what buried the head inside the body run while the arena drew the chain correctly.

**The single source.** `arena_weapons.gd` owns these numbers because it is what actually draws the weapon in play. Three new statics expose them — `snake_chain_geometry(spacing_mult)`, `chain_seg_scale(taper_pct, k)`, `display_px_for(weapon_name)` — and `_snake_seg_scale()` now calls the second one, so there is one taper curve rather than two identical-looking ones. `creep_edit_mode.gd` reaches them through three hooks (`_chain_geometry`, `_chain_seg_scale`, `_arena_display_px`) that `weapon_edit_mode.gd` implements; the base class holds no weapon numbers at all any more, and every chain ENEMY gets `{}` / `0.0` so their hand-authored per-map layout is untouched.

Removed from `creep_edit_mode.gd`: the hardcoded 44 / 25.2 / 32 / 25.35 `target_px` table (kept in sync with arena_weapons.gd by comment only — and it had already drifted once, Aliwa) and both hand-rolled step formulas. All three chain placement sites — templates, duplicates, tail — now read `_chain_step_px()`, and both read the chain axis from `_chain_axis()`.

**One renderer instead of two.** A flat EO thumbnail is its own preview camera's bounding-sphere fit plus `GLB_FRAME_MARGIN` padding, stretched to whatever the EO rect happens to be — an apparent size built entirely from editor constants. The 3D overlay draws at 1 world unit = 1 canvas px and now fits each model to the arena's `display_px`. So the thumbnails are hidden for every part the overlay covers, at **every** view angle, rather than being swapped in at Game view; what the editor shows is the arena's geometry. (The 22nd pass hid the overlay's models at Game view instead — correct for the duplicate symptom, wrong about which of the two was telling the truth.)

**Canvas is 1:1 with the game.** `_sync_arena_part_size()` snaps each 3D part's rect to its `display_px` on open. This matters beyond looks: a TP is *saved* as a fraction of the rect and *consumed* — here and in `arena_weapons.gd` alike — as `(frac − 0.5) × display_px`, so while the two differ, clicking a point on the model stores a fraction that maps somewhere else. Existing FP/TP fractions are preserved exactly (canvas positions re-derived from the fraction they had), so nothing moves *on the model*: the arena keeps rendering them where it always did and the editor now agrees with it.

**Plumes missing in the editor** ("plume trên arena có, nhưng trong edit lại không hiện"). The overlay built plumes only for `_active_creep`. VIPER's TPs live on the Tail, so selecting the head — or the group row, the normal way to have VIPER open — rendered no plume at all, while the arena builds an anchor for head, body and tail alike. It now walks every part in the group, each with its own display size, style and TP list, and TP pivots are placed by the arena's own `(frac − 0.5) × display_px` rather than a raw canvas offset.

**Chain duplicates are drawn too.** The overlay walked `_group_member_names()`, which deliberately excludes the generated duplicates (they hold no data of their own), so a 6-segment VIPER drew as 3 parts. New `_group_render_names()` adds them; `_chain_data_name()` resolves a duplicate to its template for TP/style lookup — exactly what the arena does, drawing every body segment from the one "VIPER body" entry — and each duplicate's model is shrunk by the taper factor it was created with (`chain_scale` meta), matching the arena's per-instance `_snake_seg_scale`.

**Refresh ownership.** `_rebuild_chain_preview()` decides the duplicate set, so it now ends by refreshing the overlay; `_refresh_plume3d_preview()` in turn always re-syncs the thumbnails. Three of the five chain-rebuild call sites never did either. Accepted cost: the group-rotation path builds the overlay twice per slider tick — bounded, and in line with what that path already does per tick.

Verified with `godot --headless --check-only` (clean, full boot) plus a static parity check over the real `weapon_layout.cfg` and `arena_weapons.gd`: the four divergence figures in the table above are measured, all three placement sites resolve to `_chain_step_px`, and the editor source no longer contains a display-size or spacing literal. **A headless probe cannot instantiate the editor** (its `--script` mode has no autoloads, so `arena_weapons.gd` won't even compile there) — so the on-screen result is unverified. Please reopen Weapon Edit on VIPER and confirm: head at the front of a single evenly-spaced row, parts at their in-game sizes, plumes visible whichever part is selected, and the arena unchanged.

## Changelog — 2026-08-22 (22nd pass) — 3D overlay drew a second washed-out copy of every part, and survived closing the editor

Both symptoms came from the one node: the full-screen 3D overlay `_refresh_plume3d_preview()` builds (a `SubViewport` holding every group member's model + the active part's TP plumes, composited by a `TextureRect` at `z_index 200`).

**1. Duplicate faint parts** ("3 part của viper hiện trên màn hình, model 3D nhưng mờ, trùng lặp với các part thật"). At Game view the flat EO thumbnails are *themselves* top-down renders of these same models and stay visible (`_sync_flat_thumbnails`), so the overlay was painting a second, differently-lit copy of all three VIPER parts on top of the real ones. The models are only needed once the view is ORBITED — which is exactly when the thumbnails hide. Fixed by making the overlay's models the exact complement of that test: `model.visible = not _at_game_view()`. The `part` NODE is kept in both cases, because it carries the transform the TP plume pivots hang off — the plumes must keep rendering at Game view.

`_sync_flat_thumbnails()` is now also called when the editor OPENS. The view angle survives a close/reopen but nothing re-ran that on open, so closing while orbited and reopening left the two representations out of step until the cube was next touched. Which representation is on screen is now a function of the view angle alone, at every moment.

**2. Overlay survived closing the editor** ("sau khi tôi tắt edit đi vẫn còn lại trên màn hình, cùng với đó là 1 cái plume"). `_set_ui_visible(false)` freed the 2D preview plumes but had no idea the 3D overlay existed. Its two halves live on nodes that deliberately outlive the panel — the `TextureRect` on `_objects_container` (same reason the vortex/LED previews need their own explicit cleanup in `_close()`) and the `SubViewport` on the edit-mode node — so nothing else ever reclaimed them, and the assembled 3D scene kept painting over the running game until the editor happened to be reopened. Teardown split out into `_clear_plume3d_preview()` and called from both the rebuild path and `_set_ui_visible(false)`.

`_refresh_plume3d_preview()` also early-returns when `not _is_open`. Several refresh paths (`_update_grid_overlay` → `_refresh_plume_preview`, style edits, chain rebuilds) still fire while the panel is closing — `_close()` calls `_select_tp(-1)` before `_set_ui_visible(false)` — and any one of them would have rebuilt the overlay straight back onto the game.

Verified with `godot --headless --check-only` (clean, full boot). **Node-lifecycle behaviour is not headless-testable** — please reopen Weapon Edit on VIPER and confirm: only one copy of each part at Game view, the plumes still visible there, all three parts appearing when you orbit the cube, and nothing left on screen after Close.

## Changelog — 2026-08-22 (21st pass) — authoring space switched to Z-UP: X·Y is the play plane, Z is vertical; TP rotation restored to the 2D plume's absolute-heading feel

**The convention.** Two spaces now meet, and every rotation crosses the boundary through one helper instead of being passed around raw:

| | X | Y | Z | Euler order |
|---|---|---|---|---|
| **EDITOR space** — sliders, readouts, `weapon_layout.cfg` | canvas right | canvas **up** | **vertical** | ZXY |
| **VIEW space** — Godot's own, every `Node3D` | canvas right | vertical | canvas down | YXZ |

They differ by exactly -90° about the shared X axis (`glb_topdown_rig.gd::axis_fix()`). Crossing is a conjugation — `view_basis()` / `editor_rot()` — never a permutation of the three Euler numbers; those are only equal for single-axis rotations. New helpers: `axis_fix`, `view_basis`, `view_rotation`, `editor_rot`, `rot_basis`, `rot_euler`, plus `EDITOR_EULER_ORDER`.

**Why ZXY and not Godot's default YXZ.** ZXY applies Z outermost, so `Rot Z` is a spin about the *world* vertical no matter how the part is already tilted. Measured: at tilt (35°,0,0) and (0,25°,0) a Rot Z sweep still walks the same canvas compass — down → down-right → right → up → left — just foreshortened by the tilt. Under YXZ, Z is innermost/local and would have swung a tilted part around a tilted axis instead.

**`height` → `z`.** Objects now store `z` alongside a TP's own `z` (TPs already used this convention — that half needed no change). All 18 parts verified at `z = 0.0`, i.e. one plane. `_read_creep_z()` / `_rig_z()` still accept the old `height` key.

**Plume rotation back to the 2D feel** ("thiết lập lại cơ chế xoay như của plume 2D"). The Rotate handles are now **mode-sensitive**:

- **TP focused → ABSOLUTE.** The handle position *is* the angle and stays where you put it, exactly like the old flat `dir_angle` field. Rot Z is the spray heading. Verified equal to the 2D fallback's own sweep: Rot Z 0° → canvas (0,1) *down*, 45° → (0.71,0.71), 90° → (1,0) *right*, 270° → (-1,0) — the same set of directions `dir_angle` 90/45/0/180 produced.
- **Object focused → RELATIVE jog** (handles spring back), unchanged from the 20th pass. An object genuinely needs poses tilted past 90°, where absolute Euler fields gimbal-lock; a plume's normal pose is flat, so absolute handles are safe there.

Absolute handles did **not** bring gimbal lock back. Measured slider axes at 7 poses including the two that used to collapse: `|X·Y| = |X·Z| = |Y·Z| = 0.00` at (0,0,0), (45,0,0), (89,0,0), (91,0,0), (76,-177,179), (-42,0,15), (30,40,50).

**One-time cfg migration.** `weapon_layout.cfg` gained `[meta] axis_space = "z_up"`; every stored `rot`/`rot_base`/`dir_rot` was converted with the exact inverse of `view_basis`, so **the rendered orientation is unchanged** — worst drift across all parts 7.1e-7. Anything loaded without that marker is converted on the fly (`_migrate_axis` in the editor, `_editor_axis` in `arena_weapons.gd`), so restoring an old backup of the cfg is safe rather than silently destructive. Example conversion: Aliwa `rot (-42,15,0) → (-42,0,15)` — the yaw simply moves onto Rot Z, which is the whole point.

**⚠ Behaviour change worth checking in-game.** `_snake3d_world_xform()` used to build the mount angle by hand as `Basis(UP, -cal.y) * Basis.from_euler(cal.x, 0, cal.z)` — note the **negated** `cal.y`, while the editor preview fed the very same value straight into `Node3D.rotation`. The two disagreed for any part whose yaw wasn't near 0 or ±180°. Measured gap between what the editor showed and what the game rendered: **VIPER body 185.5°, VIPER Tail 185.3°, ND-Aliwa-Bmr 30.0°** (head 1.2°, Jaeger and Spore 0°). The game now goes through `view_basis(cal)` and matches the editor exactly. If one of those three looked *right* in-game before, it will look different now — re-dial it in the editor, which is finally telling the truth.

**Other latent mismatches closed along the way** (all no-ops on today's data, since every `dir_rot_base` is currently zero):

- The full-screen plume preview built each TP pivot from the **raw** `dir_rot`, dropping any banked "Set 0° here" baseline — while `_apply_rotation_delta` wrote the **composed** value into the same pivot. A TP with a baseline jumped the moment a slider moved.
- `set_live_tp_direction()` was handed the raw half too; it now receives the composed angle.
- `_rebuild_chain_preview()` laid a force-arranged chain out along `rot` alone, ignoring `rot_base`.

**UI.** The section carries a "X·Y = play plane, Z = vertical (up)" hint; each Rot label/slider has a tooltip naming its axis and the current mode. Handle parking is centralised in `_sync_glb_rot_handles()`, called on focus change and on drag release — and from `_apply_tp_focus_transform_lock()` when focus actually crosses between TP and object, which covers the paths that clear a TP selection without going through `_refresh_glb_view_ui()` (deleting a TP, selecting a vortex/LED point).

Verified with `godot --headless --check-only` (clean) plus headless probes driving the real `glb_topdown_rig.gd`: slider-axis independence at 7 poses, the Rot Z ↔ `dir_angle` equivalence sweep at 3 tilts, per-part migration drift, legacy-cfg round-trip, TP base composition (preview vs live), and the Z = 0 audit. Probes deleted afterwards. **Not verified in-game** — please restart (Alt+F4 → F5) and check the three parts flagged above.

## Changelog — 2026-08-22 (20th pass) — rotate sliders rebuilt as axis-relative jog controls (gimbal lock removed)

- **User's diagnosis was right** ("Rot Y và Rot Z cùng xoay 1 trục?"). Confirmed by measuring each slider's
  actual rotation AXIS at various poses: at `rot.x = 0` they were perpendicular (|dot| 0.000), at 45° already
  converging (0.707), at 80° nearly identical (0.985), and at **89°/91° exactly the same axis (|dot| 1.000)**.
  The user's own saved VIPER body sat at `rot.x = 91°` — dead centre of the lock — so two of the three
  controls genuinely did the same thing.
- **Cause**: the sliders wrote an absolute Euler triple, and Euler's middle axis (X, with Godot's default
  YXZ order) collapses the other two onto one axis as it approaches ±90°. Inherent to editing orientation as
  three independent Euler numbers, not an implementation slip.
- **Fix**: each drag now applies a rotation about that slider's OWN WORLD AXIS, composed onto the current
  orientation as a Basis (`new = base⁻¹ · delta · base · old`, which keeps any banked `*_base` intact).
  Euler is only ever used to STORE the result, never to edit it, so no pose can lock the controls together.
  Verified after the change at the same poses — `|dot| = 0.000` at 0°, 45°, 89° AND 91°.
- **UX consequences, deliberate**:
  - The handles are jog controls: they spring back to centre on release (`drag_ended`, not inside
    `value_changed` — resetting mid-drag would fight the mouse, since the slider re-derives its value from
    the pointer).
  - The "NN°" readouts beside them now show the FOCUSED TARGET's absolute angle instead of echoing the
    handle, so the absolute readout the old design had is not lost.
  - "Reset Rotation" can no longer work by zeroing the handles (that delta would be zero) — it now computes
    the rotation that undoes the focused target's absolute angle and routes it through the same delta path,
    which also un-orbits a whole group rigidly instead of leaving its parts spun in place.
- **Simplification that fell out**: `_apply_group_rigid_rotation()` took an absolute value and tracked what
  was already baked into member positions (`_group_rot_applied`) to derive a delta. It now takes the delta
  directly (`_apply_group_rigid_delta`) and that bookkeeping dict is gone — there is no baseline left to get
  out of step.

## Changelog — 2026-08-22 (19th pass) — view cube now orbits the whole assembly as one 3D scene, display-only

- Request: "muốn có cách xoay qua xoay lại để căn chỉnh các part và plume cho chính xác, chứ ko phải xoay
  rồi lưu." The 18th pass declined a scene orbit because moving EO positions would mutate the saved layout —
  that objection only applied to moving the 2D rects. Orbiting a **render** has no such problem.
- **The parts and their plumes are now assembled into ONE real 3D scene** inside the existing full-screen
  overlay, at their canvas positions (1 world unit = 1 canvas px), and the view cube orbits that scene's
  camera. Each part is a real model node carrying its own `rot`/`rot_base`/`height`, with the active part's
  TP plume pivots as its children — so what you orbit around is the true spatial relationship between the
  parts and where each plume actually leaves them. Separate per-part thumbnails could never show this: each
  is pinned to its own flat rect and can only spin in place, which is exactly what the 18th pass reported.
- **Nothing is written.** The orbit reads EO positions and never assigns them; no cfg write is involved.
  Verified explicitly: snapshot every EO position, orbit to `yaw 0.7 / pitch 0.55`, compare —
  **0 positions changed**.
- **Orbit pivot = the edited group's own centre**, with the overlay rect offset by the same amount. That is
  what keeps Game view pixel-exact: at pitch 90 the pivot projects to the frame centre, the offset puts that
  centre back on the pivot's own canvas point, and everything else follows 1:1. Verified after the rewrite:
  TPs clicked at (600,300), (350,520), (880,240) drew at **0.35 / 0.35 / 0.29 px** error.
  - Note for future measuring: the overlay now renders the MODELS too, so `Image.get_used_rect()` over the
    whole viewport no longer isolates the plume — an early check read 141 px of "error" that was purely the
    models widening the bbox. The models have to be hidden to measure a TP's own position.
- **Flat thumbnails vs 3D scene** (`_sync_flat_thumbnails`): at Game view the canvas and the 3D scene
  coincide, so the flat EO thumbnails stay visible and 2D editing is exactly as before. At any other angle
  they would disagree with the orbited scene, so their TEXTURES are hidden — the EO nodes themselves stay
  alive, so selection, outlines, dragging and every other 2D interaction keep working untouched.
- **Default view is now Game view** (straight down) rather than the 3/4 angle, so the editor opens in the
  familiar flat 2D mode and shows each part as it actually looks in play. Right-clicking the cube still parks
  at the 3/4 authoring angle; the "Game view" button returns.

## Changelog — 2026-08-22 (18th pass) — preview frames fitted tightly per view (model was ~4% of its texture); Spacing floor lowered

- **"Object khá nhỏ so với khung trắng"** — measured before fixing: the model filled only **4.2 / 5.0 / 3.8 %**
  of its own 256² texture (opaque bbox ~47×58). Two stacked causes, both mine:
  1. The 15th pass framed to the model's bounding SPHERE — rotation-invariant, so nothing could ever crop,
     but a sphere also covers the full 3D diagonal, most of which is not in the silhouette for a flat-ish
     part.
  2. The 15th pass also inflated that frame by `abs(height)` so a PgUp/PgDn lift could not push the model out
     of shot. With a lift of ~30 units on a ~26-unit radius, that alone more than tripled the frame.
- **Fix**: new `_fit_preview_cam()` positions the camera at the current view angle and fits `cam.size` to the
  model's silhouette **as seen from there**, re-running on every view-cube move. Tight and uncropped at any
  angle, and the texture stays square so `eo._aspect_ratio` never shifts underfoot. `height` is deliberately
  no longer applied to the per-part thumbnail — a part's preview is a fixed-size sprite in a 2D layout, and
  letting the lift shift it inside its own frame is exactly what forced the inflation. Height still does
  everything it should elsewhere: depth ordering in the live weapon (`_snake3d_world_xform`) and a true 3D
  offset in the full-screen plume overlay. Measured after: fill **25.7 / 50.5 / 43.8 %** at the default 3/4
  view, **51.3 / 86.1 / 89.0 %** at Game view, **46.1 / 35.6 / 38.4 %** while orbited — `cropped = false` in
  all nine.
- **"Spacing min 0.3 nhưng segment vẫn xa nhau"** — same root cause: with centre-to-centre stepping, 1.0 is
  already exactly touching and 0.3 is a 70% overlap, but every EO rect was sized to that hugely padded
  thumbnail, so the visible models sat far apart inside touching rects. Fixing the framing fixes the look;
  the Spacing floor was also lowered 0.3 → 0.05 for extra headroom.
- **"Cube xoay từng object quanh tâm của nó, không xoay cả scene"** — NOT fixed, and deliberately so: each
  part renders in its own SubViewport pinned to its own fixed EO rect on the canvas, so a camera orbit can
  only change how that part is drawn inside its rect — making parts orbit each other would mean moving their
  canvas positions, which IS the saved layout (and would also have to be un-transformed for every drag,
  arrow-nudge, hit-test and grid read). Rotating the whole assembly is already available as a data operation:
  select the VIPER group row and drag Rotate X/Y/Z — the 14th pass made that a true rigid rotation about the
  block centre. The cube stays a view control.

## Changelog — 2026-08-22 (17th pass) — VIEW CUBE drag direction fixed; "Game view" button added

- **Drag was inverted** ("kéo sang phải thì cube lại xoay sang trái"). `_view_yaw`/`_view_pitch` describe
  where the CAMERA orbits to, but the hand is grabbing the CUBE — feeding the raw drag straight into the
  camera angle spins it backwards. Both axes now take the NEGATIVE of the drag, so the cube follows the
  hand. Verified by measuring where the cube's front face (+Z) ends up: drag right → `x = +0.671` (moved
  right), drag left → `x = -0.033` (moved left).
- **New "Game view" button** under the cube (96×22 at (1088, 144), directly below the 96×96 cube at
  (1088, 44)): snaps to the EXACT angle the weapon is drawn at in play — straight top-down, which is what
  every live rig uses (`glb_topdown_rig.gd::make_camera`). Distinct from right-clicking the cube, which
  resets to the 3/4 authoring view; this one is what you check your work against.
- **Reaching exactly 90° needed a second up-vector**: straight down makes the usual `Vector3.UP` parallel to
  the look direction, which `look_at_from_position()` cannot resolve — the reason free dragging is clamped to
  ±88°. New `_view_up()` switches to `(0,0,-1)` at exactly ±90°, the SAME up the live gameplay rigs use, so
  the button lands on precisely the in-game angle rather than merely near it. Verified: `yaw 0 / pitch 90.0`
  puts the preview camera at `(0, 1, 0)` — straight above, matching the game rig — with `cropped = false`.

## Changelog — 2026-08-22 (16th pass) — VIEW CUBE navigation gizmo (3ds Max / Blender style)

- Request: "làm thêm 1 cục xoay viewport, hình cube, tương tự như trong 3Ds Max hay Blender... Đặt nó ở góc
  trên bên phải, nằm bên trái bảng weapon edit."
- **`_build_view_cube()`**: a real 3D `BoxMesh` in its own small SubViewport (96px), composited as a
  `TextureRect` at the top-right, immediately left of the control panel (measured: cube right edge 1184,
  panel left edge 1196). The camera in that little viewport is FIXED and the cube turns instead, which is
  what makes it read as a compass for the current view rather than just another spinning object.
  - **Drag** = orbit yaw + pitch. **Right-click** = reset to the default 3/4 view (`GLB_DEFAULT_PITCH_DEG`).
  - Pitch is clamped to ±88°, not ±90°: at exactly 90° the camera's up-vector becomes parallel to its own
    look direction and `look_at_from_position()` cannot build a basis from it.
- **What it orbits**: `_apply_view_angle()` re-points every built `.glb` PREVIEW camera. Framing needs no
  rework — those previews are fitted to the model's bounding SPHERE (3rd pass), which is view-invariant, so
  orbiting cannot crop anything. `_load_glb_topdown_tex()` also builds new rigs at the current angle, so a
  preview created after an orbit matches the ones already on screen.
- **What it deliberately does NOT orbit**: the plume overlay's camera. That one is top-down ON PURPOSE —
  its world coordinates ARE canvas coordinates (1 unit = 1 px, 15th pass), which is what makes a TP render
  exactly where it was clicked. Tilting it would break TP placement and the whole 2D editing plane with it.
- **Verified**: cube sits at (1088, 44) 96×96 with the panel at (1196, 44); a drag moved the view from
  `yaw 0 / pitch 35` to `yaw 61.9 / pitch 55.6` and the preview camera direction followed
  `(0, 0.57, 0.82)` → `(0.50, 0.83, 0.27)`; the object preview reported `cropped = false` after orbiting;
  and a TP clicked at (600, 300) still drew at (600, 300) — **0.00 px** — confirming the canvas mapping is
  untouched.

## Changelog — 2026-08-22 (15th pass) — plume preview moved to ONE full-screen viewport; object frame re-fits to height

- Request: "bỏ hoàn toàn các khung đang crop mất object đi, để viewport to bằng màn hình."
- **Plume overlay is now a single screen-sized SubViewport** instead of a small frame sized from the style's
  particle reach and centred on the object. Anything that outgrew that box was clipped at its edge — a big
  `Sc` (which only started mattering once `billboard_keep_scale` was fixed in the 11th pass), a long/fast
  plume, or a TP placed well off the model. A full-screen viewport has no edge anywhere the canvas can show,
  so the cropping is gone by construction rather than by guessing a bigger box.
- **The rewrite also deleted the whole world→pixel conversion**, which is where the 6th pass's placement bug
  lived: the camera is now 1 world unit = 1 canvas pixel (`make_camera(vp, screen.y * 0.5)`), a `world_root`
  offset by half the screen makes world `(x, z)` read directly as canvas `(x, y)`, and a TP simply sits at
  its own canvas coordinates. No `target_px`/`eo.size` ratio left to get wrong. The object's `rot_pivot` sits
  at the part's canvas centre with TPs hanging off it at their canvas offsets, so a mount rotation orbits
  them exactly as the real weapon does.
- **Object preview frame re-fits to `height`**: the bounding-sphere framing from the 3rd pass is
  rotation-invariant, but a PgUp/PgDn lift (13th pass) shifts the model within the frame — the preview camera
  is pitched, so a Y offset shows as a vertical shift — and could push it out. `_glb_apply_rotation()` now
  re-fits `cam.size` to `(radius + abs(height)) * 2 * GLB_FRAME_MARGIN` on every apply, so no height can crop
  it either. `radius` is cached in the rig at build time for this.
- **Verified**: viewport is the full `1440x780` screen with the layer at `(0,0)` covering all of it; a
  deliberately oversized plume (vel 300-400, lifetime 1.5, Sc 8-10) renders with `touches_edge = false`; the
  object preview at `height = 40` re-fit `cam.size` 26.1 → 140.1 and also reports `touches_edge = false`.
  Placement re-checked after the coordinate rewrite with rotation zeroed — clicks at (430,340), (700,200),
  (250,560), (900,650) all drew at **0.00 px error**.

## Changelog — 2026-08-22 (14th pass) — group rotation is now a true rigid-body spin about ONE pivot (the block's centre)

- Request: "khi tôi chọn layer VIPER (layer tổng) thì xoay toàn bộ dựa trên 1 pivot duy nhất lấy trung tâm
  khối object làm pivot point. Thay vì xoay quanh nhiều tâm như hiện tại."
- **What was wrong**: the 12th pass's group branch set every part's `rot` to the same value, which aligned
  their ORIENTATIONS but left their positions untouched — so each part pivoted in place about its own centre.
  A rigid rotation also has to ORBIT every part around the shared pivot.
- **`_apply_group_rigid_rotation()`**: orbits every group member about the centre of the assembled block
  (`_creep_group_bbox`, duplicates included). Works on the **delta** from whatever rotation is already baked
  into the positions (`_group_rot_applied`), not the absolute value, so a manual nudge or resize between two
  drags is absorbed into the new offsets instead of being undone; seeded from the root's own saved `rot` the
  first time a group is touched so the first drag after loading doesn't jump. Uses this editor's own
  coordinate mapping — canvas X = world X, canvas Y = world Z, a part's `height` = world Y — so it is a
  genuine 3-axis rotation and a part lifted with PgUp/PgDn swings correctly instead of being treated as flat.
- **Chain layout follows the rotation**: body duplicates hold no position of their own — they are re-derived
  by `_rebuild_chain_preview()`, which always stepped straight DOWN. Left alone, rotating the group swung the
  head/body/tail templates round while the duplicates re-stacked vertically, tearing the chain apart. The
  step direction is now the chain's own `(0,0,1)` axis rotated by the group's mount angle, projected to the
  canvas; the tail's end-snap uses the same vector. Guarded by `_chain_force_arrange()`, so ENEMY chains keep
  the original straight-down, top-to-top formula byte for byte (their layout is hand-authored). The group
  branch also calls `_rebuild_chain_preview()` so duplicates re-lay immediately.
- **"Set 0° here" on a group** resets `_group_rot_applied` to zero as well — positions are already where the
  banked pose put them, so without that the next drag would re-orbit by the whole banked amount.
- **Verified**: with 5 segments at rot 0 the chain runs vertically (y 340→532); group yaw 90° puts it
  horizontal (x 412→595, all y = 372); yaw 180° puts it vertical again facing the other way (y 399→217). The
  pivot stayed at (439, 372) and every part's distance from it was preserved exactly across 90°→180°
  (27.0 / 35.3 / 95.3 / 155.3), which is what proves it is one rigid rotation about one fixed point.

## Changelog — 2026-08-22 (13th pass) — PgUp/PgDn moved to real 3D height; all test-plume / debug scaffolding removed

- **PgUp/PgDn now edit the part's real world-Y height, not `z_index`** (correction to the 12th pass). Stored
  per part as `height` in `weapon_layout.cfg`'s creeps entry, applied in the editor to the same `rot_pivot`
  the model and its TPs hang off (so the whole part rises/sinks together), and read by arena_weapons.gd via
  the new `_read_creep_height()` into per-part vars that feed a new `height` parameter on
  `_snake3d_world_xform()`. Whole-group selection lifts every member at once, matching how the rotation
  sliders behave in group mode. `set_live_mount_cal()` re-reads the height too, so a lift shows up in-game
  without re-equipping.
  - **Worth knowing**: under this file's top-down ORTHOGRAPHIC rigs a pure Y offset does not move a part on
    screen — it changes DEPTH, i.e. which part draws in front of which (head above body, etc.). It is
    directly visible in the editor's 35°-pitch preview, which is where you author it.
- **Removed all the throwaway diagnostics**: the TEST PLUME (`_setup_test_plume_3d`/`_update_test_plume_3d`,
  its vars/consts and on-screen label), the Numpad live-edit target (`set_live_edit_target`/
  `clear_live_edit_target`/`_edit_target_key` + `_sync_live_edit_target()` and its 4 call sites in
  creep_edit_mode.gd), and every debug print/counter (`_live_write_debug`, `_live_write_call_count`,
  `_sync_debug`, `_print_debug_dedup`, `[LiveTP]`/`[LiveTPKeys]`/`[SyncTarget]`). `set_live_tp_direction()`
  stays — it is what the Rotate X/Y/Z sliders drive.
- **Two self-inflicted bugs caught during that removal, both by the verification run rather than the parse
  check** — worth recording because a clean parse proved nothing in either case:
  1. Deleting the two call lines left `if not _companion:` with an EMPTY body twice (a parse error that
     cascaded into "could not preload arena_weapons.gd" from every autoload that imports it).
  2. The var-block deletion walked back to the previous blank line and took `_live_tp_particles` with it —
     the dict the live plume rotation actually needs. Restored with its documentation.
- **Also fixed**: `var names: Array[String] = ... if cond else [x]` throws at runtime, because the `else`
  branch builds an UNTYPED Array — the same trap `_rebuild_chain_preview()` hit in the 8th pass. Rewritten
  as an explicit if/else. Only surfaced because the probe exercised the non-group path.
- **Verified**: single-layer 5× PgUp → `height 5.0`, pivot Y 5.0, head/tail untouched at 0; 2× PgDn → 3.0;
  cfg stores 3.0 and the game reads back 3.0; group-mode +1 → head 1.0 / body 4.0 / tail 1.0.

## Changelog — 2026-08-22 (12th pass) — group-row rotation turns the whole VIPER; PgUp/PgDn raises/lowers a selected object layer

- **"Khi click layer VIPER: kéo thanh xoay sẽ xoay toàn bộ object"**: the Rotate X/Y/Z sliders acted on
  `_active_glb_path` — ONE rig — so with the synthetic whole-creep LAYERS row selected (`_group_selected`,
  already an existing concept) they still only turned whichever single part was active. `_on_glb_rotation_
  changed()` now branches on `_group_selected` and writes the slider triple to EVERY member of the group
  (new `_group_member_names()` / `_rig_for_creep()` helpers), pushing each one to the live weapon via
  `set_live_mount_cal()` as it goes. "Set 0° here" got the same group branch, so banking a pose zeroes the
  whole assembly at once. Selecting a single part still edits only that part, unchanged.
  - **Worth knowing**: a group drag OVERWRITES each part's own mount angle with the shared value — that is
    what "rotate the whole thing as one" means here, but it does flatten any per-part fine-tuning. Bank the
    pose with "Set 0° here" first if you want to keep per-part offsets and tune from a common zero.
- **"Khi click mỗi layer đơn, phím pgup và pgdn có thể nâng hạ object"**: PgUp/PgDn previously only moved a
  selected TP's Z (height). With a plain OBJECT layer selected and no TP focused, they now raise/lower it in
  the LAYER stack — `z_index`, the same value the Transform panel's Z field edits — with undo push, panel +
  layer-list refresh and a silent save, matching the arrow-key nudge path. TP selection still takes priority
  (checked first), since for a TP the Z axis means height above the ground plane instead.
- **Verified** on the real editor: single-layer drag moved only the head (`y 3.14 → 0.52`) leaving body/tail
  untouched; group-row drag set all three to the same `(-0.87, 1.57, 0.00)`; "Set 0° here" on the group put
  all three at `(0,0,0)` with `visuals_unchanged=true`; `z_index` went `115 → 118` on 3× PgUp and back to
  `117` on 1× PgDn.

## Changelog — 2026-08-22 (11th pass) — Plume Sc did nothing (billboard dropped the scale); tail movable again; new "Set 0° here"

- **`Sc` had no effect at all — real bug, affects the LIVE game plumes too.** `make_plume()` sets
  `billboard_mode = BILLBOARD_ENABLED` but never `billboard_keep_scale`, and Godot **discards a mesh's scale
  when billboarding** unless that flag is on. Every particle therefore rendered at the QuadMesh's base size
  and `scale_amount_min/max` (the panel's Sc fields) were inert. Measured before: sc 1 / 4 / 10 all produced
  an identical 12×12 px blob — and still 12×12 with `scale_amount_curve` removed, proving the scale never
  reached the renderer rather than being overridden downstream. After `mat.billboard_keep_scale = true`:
  sc 1 / 2 / 5 / 10 → bbox 10 / 22 / 54 / 106 px. Fixes Sc for VIPER/Jaeger/Aliwa in-game, not just the editor.
- **Tail movable independently again** ("Tail không dịch chuyển được độc lập với body như head"): the 9th
  pass snapped the tail to the chain end on EVERY rebuild, and `_refresh_transform_panel()` triggers one on
  every selection change — so a manual nudge was overwritten before it could be seen. Now it only re-snaps
  when the Segments count actually changed (`_chain_last_segs` per root), which still prevents the original
  "raising Segments strands the tail mid-chain" problem while leaving it as freely movable as the head and
  the body template. Verified: 3 arrow moves stuck (453→456), survived a selection change, then re-snapped
  correctly on Segments 5→7 (456→501).
- **New "Set 0° here" button** (3D VIEW / MOUNT ANGLE, next to Reset Rotation) — "Reset vị trí hiện tại thành
  0,0,0 rotation... sau này sẽ fine tune dựa trên tọa độ này". Banks the currently-dialled orientation into a
  `*_base` companion and zeroes the editable half, so the object/plume does not visibly move but the three
  sliders read 0/0/0 again and every later tweak is a small readable delta. Context-sensitive exactly like
  the sliders: a selected TP banks `dir_rot` → `dir_rot_base`, otherwise the object banks `rot` → `rot_base`.
  Composition is a Basis product (`glb_topdown_rig.gd::compose_rot()`), never euler addition. Plumbed through
  the preview, `_save_layout`/`_load_layout`, and `arena_weapons.gd::_read_creep_rot()` so the live weapon
  renders at the same mount angle. Verified: pivot unchanged before/after (0.5, 0.9, 0.3), sliders 0/0/0, cfg
  stores `rot=(0,0,0) rot_base=(0.5,0.9,0.3)`, the game reads back the composed (0.5, 0.9, 0.3), and a
  subsequent +0.2 yaw composes on top instead of replacing it.
- **Process note for future passes**: one of the Python patch batches hit an `AssertionError` partway and,
  because it only writes the file after all replacements succeed, silently applied NOTHING — leaving 4 edits
  missing while the parse check still passed. Caught it because the verification probe reported
  `visual unchanged = false`. Apply multi-site edits one at a time (or verify each) rather than trusting a
  batch that can fail atomically and look clean.

## Changelog — 2026-08-22 (10th pass) — CHAIN panel discarded saved Segments/Spacing on any selection change

- **Symptom**: "tăng segment, bấm save, sau đó di chuyển các layer bằng phím mũi tên, thì segment bị reset,
  spacing reset về 1.0."
- **Root cause**: `_refresh_chain_controls()` populated the 4 fields from `_chain_defaults()` ALONE. That
  silently worked for the chain ENEMIES only by side-effect — `apply_chain_overrides()` mutates
  `WaveDirScript.ENEMY_DEFS` **in place**, so for them "the defaults" already contain whatever was saved. A
  chain whose defaults are real constants — VIPER's, read from arena_weapons.gd — has no such backdoor, so
  every refresh threw the saved values away and repainted the hardcoded ones. And `_refresh_transform_panel()`
  calls `_refresh_chain_controls()` on **every selection change and every layer nudge**, so merely clicking
  another layer was enough to trigger it (reproduced: panel went `segs=8 spacing=1.50` → `segs=5
  spacing=1.00` on selecting a sibling layer, while `creep_chain_overrides.cfg` still correctly held 8/1.5).
  Worse than cosmetic: the next field edit then wrote those wrong values back to disk, destroying the real
  ones permanently, and `_rebuild_chain_preview()` shrank the visible chain to match.
- **Fix**: `_refresh_chain_controls()` now overlays the saved `creep_chain_overrides.cfg` row on top of
  `_chain_defaults()` explicitly, instead of depending on someone else having mutated the defaults dict.
  Correct for both kinds of chain and no longer order-dependent. `.duplicate()` first is required — the enemy
  path returns the live `ENEMY_DEFS` entry BY REFERENCE, and merging into it would corrupt the very dict this
  function is only supposed to read.
- **Verified** end to end on the real editor + a real `arena_weapons` instance: set Segments 8 / Spacing 1.5 /
  Taper 2%, then Save, then select a sibling layer, then two arrow-key moves, then select the tail — panel
  stayed `segs=8 spacing=1.50 taper=2.0` and the row stayed at 8 nodes throughout, with the weapon runtime
  reading `segs=8 spacing=37.80 taper=2.0`.

## Changelog — 2026-08-22 (9th pass) — VIPER's head/body/tail grouped into ONE chain weapon: centred, in a row, bodies spawned from Segments

- Request: "gom cả đầu, thân, đuôi của viper lại trong chung 1 weapon... align center và xếp chúng thành 1
  hàng. Nếu tôi tăng số segment thì tạo thêm body." Every piece of that already existed in
  `creep_edit_mode.gd` for the chain ENEMIES — parenting under the head (`_auto_group_chain_names`),
  centre-align + vertical row (`_position_chain_members` / `_auto_arrange_chain_templates`), and duplicate
  bodies spawned from the Segments field (`_rebuild_chain_preview`). Four separate reasons VIPER was left
  out, each fixed at its own root rather than by special-casing the layout code:
  1. **Name parsing**: the grouping keys off a `^(.+?)(head|tail|body(\d*))$` regex. "VIPER head top" ends in
     "top", so it never parsed as a head. `weapon_edit_mode.gd` now overrides `_parse_chain_name()` for the
     3 VIPER sprites. All three had to be answered, not just the head — the regex gives "VIPER body"/"VIPER
     Tail" the prefix `"VIPER "` (trailing space) while the head would get `"VIPER"`, and a prefix mismatch
     splits them back into two groups.
  2. **Auto-arrange never triggered**: it is gated on `_chain_all_stacked()` (only rearrange a group still
     piled on one spot, so a hand-placed enemy layout is never clobbered). VIPER's parts sit at authored
     positions, so the head stayed off to the side — centreX 440 vs 510. New `_chain_force_arrange(root)`
     hook: base returns false (enemies unchanged), `weapon_edit_mode.gd` returns true for VIPER, which is
     always one assembled creature with no authored arrangement worth preserving.
  3. **Stale saved parent silently dropped the tail**: `weapon_layout.cfg` had `parent = "VIPER body"` on
     "VIPER Tail" from before it was a chain. `_auto_group_chain_names()` won't clobber an existing parent,
     and `_load_layout()` (which runs AFTER it) re-applied the stale value every load — so
     `_set_active_creep()`, which only loads children whose parent IS the root, skipped the tail entirely and
     the row rendered with no tail at all. Both sites now let a force-arranged root own its own parenting.
  4. **Tail didn't follow the chain end**: deliberate for enemies (a 2026-08-15 revert — "chỉnh vị trí body2
     thì tail cũng bị kéo theo"), but it strands VIPER's tail mid-chain as soon as Segments goes up. Now
     repositioned to the end for force-arranged chains only, using the same centre-on-previous formula the
     body duplicates use.
- **Bug fixed on the way** (pre-existing, newly reachable): `_rebuild_chain_preview()` assigned
  `Dictionary.get()`'s UNTYPED Array straight into an `Array[String]`, which throws at runtime. Every enemy
  chain's names match the regex so they always had an entry and never hit it; VIPER's don't. Now `assign()`.
- **Verified** by driving the real editor: `parent(VIPER body) = parent(VIPER Tail) = "VIPER head top"`;
  Segments=4 → head, body, body#2, Tail; Segments=7 → head, body, body#2..#5, Tail — every node at
  `centreX = 440.0`, evenly spaced down one column, tail always last.

## Changelog — 2026-08-22 (8th pass) — VIPER now uses the chain enemies' own Segments/Spacing/Bend/Taper panel

- **研究 first**: the CHAIN (multi-node) panel that centipede-style enemies use (`cent`, `centipede`,
  `hammerhead`, `killerwhale`, `shark_elite`, `spermwhale2`) turned out to be **already fully generic** — 4
  fields (Segments 3-40, Spacing× 0.3-3.0, Bend lock 0-180°, Taper 0-10% per-step), saved to
  `creep_chain_overrides.cfg` under `[overrides] data = {id: {centi_segments, centi_spacing_mult,
  centi_bend_deg, centi_taper_pct}}`, applied live on every keystroke. Only its DATA SOURCE
  (`WaveDirScript.ENEMY_DEFS`) and its live-apply (the wave director) were hardwired to enemies.
- **Extracted 3 hooks** in `creep_edit_mode.gd` rather than duplicating the panel: `_chain_defaults(id)`,
  `_apply_chain_runtime(id)`, `_clear_chain_runtime(id)`. The UI, the cfg format and the whole save/reset
  flow are untouched and shared.
- **`weapon_edit_mode.gd`** overrides those three plus `_chain_id_for()`, mapping the 3 VIPER part sprites
  ("VIPER head top" / "VIPER body" / "VIPER Tail") to the chain id `"viper"`. Defaults come from
  arena_weapons.gd's own consts, so an untouched install shows exactly the stock values.
- **`arena_weapons.gd`** reads that row into `_snake_cfg_segments/_spacing/_turn/_taper` via the new public
  `reload_chain_overrides()` (called at `_ready()` and by the editor on every edit/Reset, through the
  `"arena_weapons"` group). Each defaults to the matching const, so behaviour is identical until overridden:
  - `_snake_len()` — base segment count (Elongate / Primordial God / Nanobots bonuses still stack on top)
  - `_snake_move()` — follow distance; also both chains' initial spawn spacing and the head plume offset
  - `_run_snake()` — `turn_rate` default changed from the `SNAKE_TURN` const to the panel's Bend lock
    (explicit callers like Predator's `PREDATOR_TURN` still win — the param is now `-1.0` = "use config")
  - `_snake_seg_scale()` — new, per-segment compounding shrink applied to the 3D body MultiMesh, matching
    the enemy taper's own per-step model. Scales only the BASIS, not the whole transform (`Transform3D.
    scaled()` would move the origin and drag segments toward the chain root).
- **Bug found and fixed while wiring this** (pre-existing, newly reachable): `_rebuild_chain_preview()` did
  `var members: Array[String] = _chain_group_order.get(root_name, [])` — `Dictionary.get()` returns an
  UNTYPED Array, which throws at runtime when assigned to `Array[String]`. Every enemy chain's part names
  match the Head/Body<N>/Tail regex so they always had an entry and never hit it; VIPER's don't
  ("VIPER head top", "VIPER Tail"), so adding VIPER started spamming the error. Now uses `members.assign()`.
- **Verified end to end** by driving the real editor + a real `arena_weapons` instance: `_chain_id_for()`
  returns `viper` for all 3 parts and `""` for a non-chain weapon; the panel becomes visible; setting
  Segments 12 / Spacing 1.5 / Bend 90° / Taper 3% gave `segs=12 spacing=37.8 turn=1.57 taper=3.0 len()=12`
  with taper `seg0=1.000 seg1=0.970 seg5=0.859`; the cfg row round-tripped; Reset restored
  `segs=5 spacing=25.2 turn=3.00 taper=0.0`.

## Changelog — 2026-08-22 (7th pass) — TP nudge keys remapped to the X/Y/Z panel axes, PgUp/PgDn added for Z

- Requested mapping: Up/Down = +/-Y, Right/Left = +/-X, PgUp/PgDn = +/-Z.
- **Y is now reported UP-POSITIVE** in `_tp_xyz_get()`/`_tp_xyz_set()` (note the added minus). Canvas y grows
  downward, so before this, pressing Up made the displayed Y go DOWN — the opposite of what an arrow key
  should read as. Purely a UI/edit convention: `tp["pos"]` is still stored in canvas space and the actual 3D
  placement is computed straight from `frac` elsewhere (`_refresh_plume3d_preview` / `_glb_refresh_tp_gizmos`
  / arena_weapons.gd), so **nothing about where a plume renders changed** — only the sign shown in the TP POS
  panel and the TP list row.
- **PgUp/PgDn → Z** is new: `tp["z"]` (height above the ground plane) had no key binding at all before,
  spinbox-only. Selected TPs only — Z is a TP-specific field, meaningless for FP/tentacle/vortex/LED points,
  which keep arrow keys only. Shift multiplies by 10, same as the arrow keys.
- **Also fixed while here**: the arrow-key TP branch never called `_refresh_transform_panel()` (so the TP POS
  X/Y/Z spinboxes went stale after a nudge) nor `_save_layout(true)` (so the live weapon didn't follow).
  Both added, matching the new Z path.
- **Step sizes**: arrows move 1 canvas pixel, which is `target_px / eo.size` in panel units (0.55 for a
  44px-target creep in an 80px rect); PgUp/PgDn move 1.0 world unit. Different units on purpose — X/Y nudge
  in screen space where you are clicking, Z has no screen axis to nudge along.
- **Verified** by driving the real editor's `_input()` with each key and reading `_tp_xyz_get()` before/after:
  `Up -> Y +0.55`, `Down -> Y -0.55`, `Right -> X +0.55`, `Left -> X -0.55`, `PgUp -> Z +1.00`,
  `PgDn -> Z -1.00`.
- **Test-harness note** (not a product bug, worth knowing for future probes): the editor auto-closes itself
  whenever it is open while `get_tree().paused` is false, silently resetting `_is_open` and clearing the TP
  selection. A probe that drives it must set `get_tree().paused = true` and run its own node at
  `PROCESS_MODE_ALWAYS`, or every input it sends lands on a closed editor and appears to do nothing.

## Changelog — 2026-08-22 (6th pass) — TP rendered ~176px off the click point: TextureRect clamped its own size, plus the overlay used the wrong camera/scale

- **Symptom**: "click addTP thì điểm add nằm ở đâu ấy, lệch xa so với điểm click chuột" — a regression from
  the 5th pass. Two stacked causes, both measured rather than guessed:
  1. **Wrong camera + wrong scale**: the 5th pass matched the overlay camera to the object preview's 35°
     pitch and scaled the layer by `eo.size.y / obj_cam.size` (the object's bounding-sphere framing). But TP
     positions are stored as `frac` of the object's rect and converted by `local_pos = (frac-0.5)*target_px`
     with `frac.y` becoming world **Z** — a mapping that is top-down BY DEFINITION and is exactly what the
     live game uses (`arena_weapons.gd` builds its rigs with `rig.make_camera()`, top-down). Viewing it
     through a 35° camera foreshortens Z by `sin(35°)` and pulls everything toward centre. Reverted the
     overlay to a top-down camera and scaled the layer by the relation the frac conversion actually assumes:
     the full `target_px` world span maps onto `eo.size`, **per axis** (anisotropic — `frac` divides by
     `eo.size.x`/`eo.size.y` separately, so a non-square EO needs the same split).
  2. **The bigger one — `TextureRect` silently clamped its own size**: `layer.size = 160` read back as
     **512**, because a TextureRect's default `expand_mode` makes the TEXTURE's size its minimum size. The
     rect ended up 3.2× too large, dragging everything drawn inside it that far off. The 3D placement was
     always correct (the particle sat dead centre in its viewport — verified before fixing). Fixed with
     `EXPAND_IGNORE_SIZE` + `STRETCH_SCALE`. This is the same clamp `_place_creep_eo()` already documents for
     creep sprites — worth remembering as a recurring Godot footgun in this codebase.
- **Verified, placement**: plume drawn vs click point across 5 positions (centre, right, up, down-right,
  up-left): errors `0.16, 0.00, 0.00, 0.00, 0.00` px.
- **Verified, rotation still intact** (off-centre TP, object rotated 90° per axis):
  `ZERO (282,247) 17×43` → `X (281,247) 18×18` → `Y (247,213) 72×18` → `Z (246,247) 20×87` — all three axes
  still move the plume.

## Changelog — 2026-08-22 (5th pass) — plume preview rebuilt as a real child scene: Z-rotation now works, orbit tracks the object

- **Symptoms**: "Xoay theo chiều Z thì plume ko xoay. Xoay theo Y hay X thì quỹ đạo xoay của plume ko bám
  chính xác theo object." Three separate root causes, each proven with a runnable probe rather than guessed:
  1. **Z did nothing, by arithmetic**: `make_plume()`'s base direction is `Vector3(0,0,1)` — exactly parallel
     to the Z axis. Rotating a vector about its own axis is the identity, verified directly
     (`rotate 90 about Z -> (0,0,1) CHANGED=false`, while X and Y both changed). Nothing was broken; a pure
     direction vector simply cannot express roll.
  2. **Camera mismatch**: the object preview renders from a `GLB_DEFAULT_PITCH_DEG` (35°) camera, but the
     per-TP plume overlays used `rig.make_camera()` — a STRAIGHT TOP-DOWN camera. The same 3D rotation
     projected through two different cameras cannot look the same on screen, so the plume could never
     visually track the model however correct the rotation maths was.
  3. **No orbit**: each plume was pinned to a fixed canvas point (its click position) with only its direction
     rotated. A genuine child of the object must also ORBIT its centre — which is most of what "bám theo
     object" means, and the entire visible effect of a Z rotation on an off-centre TP.
- **Fix — one overlay that mirrors the object's own 3D scene** (replaces the per-TP overlays): a single
  SubViewport per creep holding a `rot_pivot` (the object's mount rotation) that PARENTS one pivot per TP,
  each at its true 3D `local_pos` carrying only its own raw `dir_rot`, with the particle beneath it. Godot's
  scene graph then composes position AND orientation for free — the same structure the live game already
  uses (arena_weapons.gd parents TP pivots under the weapon carrier) — so no `Basis` product is needed any
  more and `_tp_combined_rot()` was deleted. Camera is now built identically to the object's (same 35° pitch,
  projection and up-vector; only `size` is wider to fit the plumes), and the `TextureRect` is centred on the
  object's own rect at a matching world→pixel scale (`eo.size.y / obj_cam.size`), so what the overlay draws
  lands exactly where the model's 3D space says it should.
- **Verified** by driving the real editor with an OFF-CENTRE TP on VIPER head top and rotating the OBJECT 90°
  about each axis (plume bbox in the overlay viewport):
  `ZERO pos=(254,222) 18×29` → `X pos=(254,211) 18×44` → `Y pos=(203,242) 63×19` → `Z pos=(246,216) 19×52`.
  All three axes now move the plume, **including Z** (it orbits, exactly as a rigidly attached child should,
  even though a Z roll leaves its own spray vector unchanged — see cause 1).

## Changelog — 2026-08-22 (4th pass) — one Add TP was still producing TWO plumes (standalone preview + in-object gizmo)

- **Symptom** (VIPER head top): "bấm addTP 1 lần thì lại xuất hiện 2 TP... 2 TP đều di chuyển nhưng theo các
  quỹ đạo khác nhau". One SAVED TP, two rendered plumes — the 3rd pass added the standalone per-TP preview
  (`_preview_plumes3d`) but left `_glb_refresh_tp_gizmos()` still drawing its own copy for every TP inside
  the object's own SubViewport. They tracked genuinely different transforms, hence the two trajectories:
  the in-object one is positioned by `local_pos` (frac-of-bounding-box, in the model's own 3D space) and
  rotates with `rot_pivot`; the standalone one sits at the flat canvas click point with
  `Basis(object_rot) * Basis(dir_rot)`.
- **Fix**: `_glb_refresh_tp_gizmos()` now skips any TP with `dir_rot` — the standalone preview is the single
  owner of a 3D TP's visual. A glb creep NOT in `WIRED_3D_CREEPS` (e.g. `BC-SL-Spore`) never gets `dir_rot`
  on its TPs, so it still renders here exactly as before; this function remains the only preview those have.
- **Verified** by driving the real `weapon_edit_mode` class with one 3D TP on VIPER head top:
  `standalone_previews=1  in_object_gizmos=0  TOTAL_visuals_for_1_TP=1` (was 2).

## Changelog — 2026-08-22 (3rd pass) — THE root cause: the editor's own TP preview was a `CPUParticles2D` reading `dir_angle`; replaced with a real rotatable 3D plume

- **Root cause, finally** (user's own observation cracked it: "Có 1 TP dạng 2D được add ngay tại điểm tôi
  click"): `creep_edit_mode.gd::_refresh_plume_preview()` spawned a **`CPUParticles2D`** at every TP's click
  position, built from `tp.get("dir_angle")` — a field the Rotate X/Y/Z sliders **never write** (they only
  ever write `dir_rot`). So the thing the user was actually looking at on the edit canvas was frozen by
  construction, no matter how correct everything downstream was. Every prior 2026-08-21 fix (local_coords,
  pivot rewrite, group name, pause/process_mode, redraw-while-paused) was real and necessary but targeted the
  LIVE GAMEPLAY plume and the in-model gizmo — never this separate, purely-editor 2D preview, which is what
  was on screen the whole time. Lesson: when a user reports "X doesn't move", confirm WHICH on-screen object
  is X before touching the pipeline behind it.
- **Fix**: a 3D TP (`dir_rot` present) now gets a real 3D plume preview at its click point instead —
  `_preview_plumes3d` (`tp_id -> {vp, pivot, layer, half}`), one SubViewport + top-down Camera3D +
  `pivot: Node3D` + fixed-direction `CPUParticles3D` per TP, composited via a `TextureRect` centred on the
  click position. Architecture deliberately copies arena_weapons.gd's TEST PLUME, the one rotation approach
  proven to work end-to-end. Viewport is framed to that style's own particle reach (`vel_max × lifetime`,
  clamped 48–220px) so a long/fast plume isn't clipped nor a short one lost in an empty frame. Plume Style
  (Vel/Life/Spr/Sc/colours) feeds it unchanged. A plain 2D TP keeps the original `CPUParticles2D` preview.
- **Sliders → plume**: `_on_glb_rotation_changed()` writes `pivot.rotation` directly, same frame, no save/
  reload/group-lookup in the path. Verified by driving the REAL editor class: plume bbox went `7×20` →
  `22×7` (width/height swapped = 90° turn) after one rotation write.
- **"Bỏ frame crop object đi"**: `_load_glb_topdown_tex()` framed the preview camera to the model's
  silhouette **as seen at rotation zero** — rotate the object and its wider silhouette ran past the frame
  edge, visibly clipping it into a rectangle. Now frames to the model's **bounding sphere** (half the AABB
  diagonal), the one extent invariant under every rotation, so clipping is impossible by construction rather
  than by a bigger fudge margin. Necessarily square (supersedes the earlier `ext.max(target_px)` floor, which
  the sphere already covers). Trade-off, deliberate: slightly more transparent padding around the model and
  `eo._aspect_ratio` becomes 1.0 — the model itself is still rendered at true proportions inside that square,
  nothing is stretched. Verified at 90° yaw: object bbox sits fully inside the 256² frame, touching no edge.
- **"TP là child của object, xoay object thì plume xoay theo như 1 khối"**: the standalone per-TP preview
  viewports aren't real children of the object's own 3D scene, so the composition that parenting gives for
  free in the real game (arena_weapons.gd parents each TP pivot under the carrier holding `_aliwa3d_cal`)
  is done explicitly: `_tp_combined_rot()` = `Basis.from_euler(object_rot) * Basis.from_euler(tp.dir_rot)`
  (a Basis product — euler addition would be wrong for rotations not sharing one axis), re-applied to every
  pivot by `_sync_plume3d_rotations()` whenever either half changes (`_glb_apply_rotation` for the object,
  `_on_glb_rotation_changed` for the TP). Verified: rotating the OBJECT 90°y with the TP's own `dir_rot`
  left at zero moved the plume pivot to `(0, 1.5708, 0)` and swapped its bbox `7×22` → `27×8`.

## Changelog — 2026-08-22 — TP editor: dropped the flat 2D marker for 3D TPs, fixed Aliwa's editor-preview scale mismatch, widened preview camera so off-model TPs aren't clipped

- **User's own diagnosis** ("Có 1 TP dạng 2D được add ngay tại điểm tôi click. và 1 TP dạng 3D rất nhỏ được
  tạo ngay tại tâm của object. và bị object che lấp"): a single saved TP was being shown TWO disconnected
  ways — `grid_overlay.gd`'s flat diamond+arrow+label marker (drawn in raw screen space at the exact click
  point, entirely independent of the object's own bounds) vs. the REAL 3D representation (a particle baked
  into the object's own composited SubViewport texture — see `_glb_refresh_tp_gizmos`/`glb_topdown_rig.gd`),
  which can only ever render somewhere WITHIN that texture's own small frame. Reading both at once looked
  like "2 TPs, one right where I clicked, one tiny and stuck at the object's center."
- **Fix 1**: `grid_overlay.gd::_draw_thrust_points()` now skips the ENTIRE flat marker (not just the direction
  arrow, dropped the same way the previous pass already dropped for 3D TPs) for any TP with `dir_rot` —
  selection stays available via the TP list panel, which never depended on this canvas marker. A plain 2D TP
  (no 3D representation to fall back to) keeps the full marker unchanged.
- **Fix 2, the actual "tiny/clipped" root cause**: `creep_edit_mode.gd::_load_glb_topdown_tex()` sizes its
  preview camera to the MODEL's own silhouette only (`glb_topdown_rig.gd::silhouette_extent()`) — but a TP's
  saved position can land ANYWHERE within `±target_px/2` on each axis (the TP editing math, `_tp_xyz_get`/
  `_glb_refresh_tp_gizmos`, is fraction-of-the-OBJECT'S-bounding-box, not fraction-of-the-model's-silhouette),
  e.g. an exhaust point placed below/behind the ship, off the mesh entirely. Framing the camera to the model
  alone clipped any such TP out of frame or crushed it into a sliver at the edge. Now widens the framing
  extent to `max(model silhouette, target_px²)` so every legally-placeable TP position stays inside the
  visible frustum. Also fixed Aliwa specifically falling through to the WRONG generic `target_px` fallback
  (32.0, when the real gameplay render — `ALIWA3D_DISPLAY_PX`/`BOOM_DRAW` — uses 25.35) — a ~26% scale
  mismatch between what the editor preview showed and where a TP would actually land in real gameplay.
- **Fix 3, "Plume Style áp dụng cho Plume 3D"**: verified, not changed — `_refresh_plume_editor()` gates
  purely on "is a TP selected", never on 2D vs 3D, and `_load_aliwa_plume_3d()`/`make_plume()` already read
  the SAME `weapon_plume_styles.cfg` entry regardless of dir_rot presence (confirmed earlier the same day by
  directly reading back a live particle's `scale_amount_max` after a style edit). The perceived "doesn't
  apply" was very likely the SAME visibility issue as Fix 2 — you can't see a style change on a particle
  that's being clipped out of frame.

## Changelog — 2026-08-21 — Weapon TP editor: "Add TP" writes `dir_rot` immediately for 3D weapons; VIPER/Jaeger/Aliwa TPs cleared for redo

- **Two weapon "types" now exist**: 2D (flat sprite, flat `dir_angle` thrust points, the original `_register_
  plume`/`_make_orbital_plume` path) and **3D** (`.glb` model rendered top-down into a SubViewport, per-weapon
  `_load_*_plume_3d()` runtime function, TPs carrying a full 3-axis `dir_rot` spray direction). Which weapons
  are "3D" is the `WIRED_3D_CREEPS` allowlist in `creep_edit_mode.gd` (shared by `weapon_edit_mode.gd`, which
  subclasses it wholesale — see that file's own header) — currently `"VIPER head top"`, `"VIPER body"`,
  `"VIPER Tail"`, `"Yari-Jeager"`, `"ND-Aliwa-Bmr"`. Only weapons on this list actually get the Rotate X/Y/Z
  "3D VIEW / MOUNT ANGLE" sliders in the editor and a live 3D plume in-game; a weapon can have a `.glb` PREVIEW
  model (nicer editor thumbnail) without being on the list yet (e.g. `BC-SL-Spore`), in which case it still
  renders/plumes through the old 2D path — see `creep_edit_mode.gd`'s own `WIRED_3D_CREEPS` doc comment for
  the full "convincing but non-functional control" rationale.
- **"Add TP" now writes `dir_rot: Vector3.ZERO` immediately** when the active weapon is 3D-wired
  (`creep_edit_mode.gd::_add_thrustpoint_at`), instead of only gaining a `dir_rot` key once the user first
  drags a Rotate X/Y/Z slider. Functionally a no-op (`Vector3.ZERO` already matches the old flat
  `dir_angle = PI/2` fallback direction via `glb_topdown_rig.gd`'s `tp_direction()`) — it just marks every new
  TP on a 3D weapon as an explicit 3D TP from the moment it's placed, visible in the saved cfg.
- **Cleared all existing thrust points** (`[thrustpoints]` in `weapon_layout.cfg`) for the 5 `WIRED_3D_CREEPS`
  weapon parts above — most of them (VIPER ×3, Yari-Jeager) still had leftover flat `dir_angle`-only TPs from
  before their 3D swap, which is what the "Add TP 3D" request above was about. `ND-Aliwa-Bmr` had a mix (one
  TP with `dir_rot`, one without) — also cleared for consistency. Per explicit request, the user is
  re-placing all of these from scratch in the editor now that "Add TP" produces a proper 3D TP immediately.
  `BC-SL-Spore` (not `WIRED_3D_CREEPS`, still 2D-driven) was left untouched. Every `_load_*_plume_3d()`
  function early-returns cleanly on an empty TP array (no plume spawned, no crash) — verified by reading each
  of the 3 functions before clearing.
- **Same-day follow-up** ("AddTP vẫn đang thêm TP dạng 2D... xoay ko có tác dụng"): user reported the Rotate
  X/Y/Z sliders looked non-functional on a freshly-added Aliwa TP. Traced by having the user drag Rot X to max
  and Save, then reading the value straight out of `weapon_layout.cfg`: it landed exactly at `dir_rot:
  Vector3(3.1415927, 0, 0)` (= π = 180°, matching the drag) — **the write path was already correct**; there
  was no data bug. The real gap: the 3 sliders had no numeric readout at all, so there was no way to tell a
  drag had registered short of saving and inspecting the cfg by hand, and the 3D-preview particle's direction
  change is too subtle to notice in the small (256px) editor thumbnail. Added a `"<deg>°"` `Label` next to each
  slider (`_glb_rot_x_lbl`/`_y_lbl`/`_z_lbl`, synced via new `_sync_glb_rot_labels()`) — called from the drag
  path AND every `set_value_no_signal` call site (`_refresh_glb_view_ui`, `_on_glb_reset_rotation`), since
  `set_value_no_signal` deliberately doesn't fire `value_changed` and would otherwise leave the label stale.
- **Bug #1** (found from a screenshot after the label fix — TP1's on-canvas arrow stayed frozen at "90°"
  while the user visibly dragged Rot X/Y/Z): `grid_overlay.gd::_draw_thrust_points()` — the flat 2D arrow
  gizmo drawn directly on the edit canvas for every TP — read the raw `dir_angle` field straight off the TP
  dict. Dragging the Rotate X/Y/Z sliders only ever writes `dir_rot` (never touches `dir_angle`), so the
  moment a TP became 3D, this specific on-canvas arrow silently froze at whatever `dir_angle` it was created
  with. Fixed by routing through `glb_topdown_rig.gd`'s `tp_direction()` (the same authoritative source every
  other consumer already uses) and projecting its X/Z onto the flat canvas (screen X = world X, screen Y =
  world Z, matching that file's own convention) instead of reading `dir_angle` directly — a plain 2D TP (no
  `dir_rot`) still resolves to the exact same vector as before, so this is a strict superset, not a behavior
  change for any non-3D weapon. No extra sync call needed to animate live while dragging:
  `_update_grid_overlay()` already assigns `grid_overlay.thrust_points` the SAME array reference
  `_on_glb_rotation_changed` mutates in place, and `grid_overlay._process()` already calls `queue_redraw()`
  every frame unconditionally.
- **Bug #2, the actual "no visible effect on gameplay" root cause** (user, after bug #1's fix: "Plume vẫn
  chưa xoay theo hướng mũi tên" / "...chưa xoay cùng với object khi tôi xoay object"): every 3D weapon's
  mount-angle calibration (`_aliwa3d_cal`/`_jaeger3d_cal`/`_snake3d_head_cal`/`_body_cal`/`_tail_cal`, via
  `_read_creep_rot()`) AND every plume TP's spray direction (baked into its `CPUParticles3D` once, inside
  `_load_*_plume_3d()`, via `glb_topdown_rig.gd::make_plume`) are each read from `weapon_layout.cfg` exactly
  ONCE, at that weapon's own `_setup_*_3d()` (equip/boot time) — arena_weapons.gd never re-reads the file
  again after that. So editor edits (Save writes the file correctly, confirmed earlier) had **zero live
  effect** on the already-running weapon; a screenshot mid-arena showing the plume not reacting to slider
  drags was accurately reporting the game, not a display glitch. Added `arena_weapons.gd::reload_3d_weapon_
  layout()` (public) — re-reads all 3 calibrations and rebuilds all 3 weapons' plume anchors from the file as
  it stands now, explicitly `queue_free()`-ing each OLD anchor first (`_load_*_plume_3d()` never frees its own
  previous anchor — it's normally only ever called once — so skipping this would leak the old anchor as a
  dangling duplicate plume instead of replacing it). `creep_edit_mode.gd::_save_layout()` now calls it via
  `get_tree().get_first_node_in_group("weapon_system")` (the same lookup every boss already uses) right after
  writing the cfg, but ONLY when editing `weapon_layout.cfg` specifically (`_layout_path()` check) — mirrors
  the pre-existing `ArenaEnemyScript.reload_layout_cfgs()` call the same function already made for enemies,
  just scoped to the 3D-wired weapons instead. Net effect: Save now applies live, no restart needed to test.
- **Bug #3** (same-day follow-up, user still saw no change — turned out they'd rotated the sliders again
  WITHOUT pressing Save since bug #2's fix landed, confirmed by re-reading `weapon_layout.cfg`: the file still
  held the previous drag's value, not the one on screen): bug #2's reload only fired on the **Save button**,
  so "drag slider → nothing visibly happens → have to remember to also click Save" was still a confusing
  extra step, especially since the on-canvas arrow (bug #1) already reacted with no Save needed. Since
  `reload_3d_weapon_layout()` reads the file from DISK, a reload alone isn't enough mid-drag — the file itself
  has to be current first. `_on_glb_rotation_changed()` now calls `_save_layout(true)` (new `silent` param —
  same full write the Save button does, just without the "Saved ..." toast) on every single rotation-slider
  tick, so the real in-game plume now tracks the sliders live, same as the arrow. The Save button still exists
  for the toast/explicit confirmation, but no longer does anything the live drag hasn't already written.
  Tradeoff accepted: this writes the whole (small) weapon_layout.cfg to disk on every mouse-move during a
  drag — fine for a dev-tool cfg file, worth debouncing later only if it visibly stutters.
- **Bug #4, THE actual root cause of both remaining complaints** ("Plume vẫn chưa xoay theo khi xoay object" /
  "Plume đơn lẻ vẫn chưa xoay khi kéo thanh trượt, chỉ có mũi tên vector chỉ hướng xoay" — user set an explicit
  "don't stop until both are fixed" goal here): verified directly rather than guessed — a one-line headless
  probe script (`CPUParticles3D.new().local_coords`) confirmed the engine **defaults `local_coords` to
  `false`** for the 3D node (opposite of its 2D counterpart, `CPUParticles2D`, whose default IS `true` — this
  file's own arena_weapons.gd 2D plumes explicitly set it `false` specifically to OPT INTO the same
  world-space behavior CPUParticles3D already has out of the box). With `local_coords=false`, `direction` is
  an ABSOLUTE WORLD vector — the particle's own PARENT node's rotation is never consulted at all. Every 3D
  plume anchor in this system (VIPER head/body/tail, Jaeger, Aliwa) is a real child of a carrier/anchor that
  gets re-rotated every frame specifically so the plume would track the object — but that whole design was
  silently inert: rotating the anchor (object mount-angle OR — composed into `tp_direction()` — a TP's own
  `dir_rot`) never had anywhere to apply itself, because the particle wasn't reading the parent's transform in
  the first place. This is why bug #1-#3's fixes (arrow direction, live-reload-on-drag) were each real and
  necessary but insufficient on their own — they made sure the CORRECT direction data reached the particle
  node, but the particle was still incapable of visually expressing rotation once built. Fixed with one line,
  `glb_topdown_rig.gd::make_plume()`: `p.local_coords = true`. Affects every consumer of this shared helper
  uniformly (all 5 `WIRED_3D_CREEPS` weapon parts' live plumes, plus the in-editor preview gizmo) — no
  per-caller changes needed.
- **Bug #5, THE actual "still nothing changes in the real game" root cause** (`local_coords` fix in place,
  `.free()` fix in place, user still saw zero live effect — "VẪN CHỈ CÓ VECTOR INDICATOR XOAY"): wrong GROUP
  NAME in `creep_edit_mode.gd::_reload_live_weapon_3d()`. `arena_weapons.gd` (VIPER/Jaeger/Aliwa) joins group
  `"arena_weapons"` (its own `_ready()`) — the reload code looked up `"weapon_system"` instead, a name copied
  from CLAUDE.md's docs for a COMPLETELY DIFFERENT file (`scripts/gameplay/weapon_system.gd`, the SpaceScreen/
  asteroid equipped-item engine). The lookup silently returned null/an unrelated node every time, so
  `reload_3d_weapon_layout()` was never actually invoked — every fix above this one was independently correct
  and individually verified, but none of them could ever reach the live game through this broken call. Fixed
  the group name. Re-verified end to end afterward: instantiated a real `arena_weapons.gd`, changed a TP's
  `dir_rot` on disk, triggered reload via the SAME group lookup the editor now uses, and read back
  `anchor.global_transform.basis * particle.direction` (the actual world-space spray vector) before/after —
  confirmed it changes.
- **Debug tool added**: `arena_weapons.gd`'s `_setup_test_plume_3d()`/`_update_test_plume_3d()` — a standalone
  bright/oversized 3D plume next to the player, rotated directly by held Numpad keys (4/6 yaw, 8/2 pitch, 7/9
  roll, 5 reset) with ZERO dependency on weapon_layout.cfg/TP/Save — built specifically to let the user
  isolate "does rotating a plume's parent actually work" from every other layer (config round-trip, group
  lookup, editor UI) that turned out to have its own bugs. User confirmed live in-game it rotates correctly.
  Explicitly a throwaway — not meant to ship; remove the var block + both functions + their 2 call sites
  (`_ready()`/`_process()`, both gated `if not _companion:`) once the real TP path is trusted again.
- **Visibility follow-up** ("áp dụng code plume này vào weapon edit" — after confirming the mechanism itself
  was correct the whole time): the ACTUAL TP the user was testing (`id=4`, after deleting/recreating TPs a
  few times) had never had its own entry in `weapon_plume_styles.cfg`, so it rendered from bare fallback
  numbers — small, short-lived, low particle count — nearly invisible at real gameplay scale/zoom even though
  it WAS rotating correctly. Bumped both defaults that feed a never-styled TP (`glb_topdown_rig.gd::
  make_plume()`'s own `.get(key, fallback)` values, and `creep_edit_mode.gd::_default_plume_style()` — the
  one that actually wins in practice, since selecting a TP even once auto-populates and saves it): lifetime
  0.30→0.6, spread 12°→4°, `sc_min/max` 0.6/1.5→1.5/2.5, and a new particle-count floor (`amount`,
  `maxi(12, target_px/5.0)` — a small weapon like Aliwa was down to just 5 total particles, which at a
  ~1s lifetime spawns barely faster than 1 every 0.2s, reading as "a sparse trickle of dots" regardless of how
  big/bright each one is). Also directly set `weapon_plume_styles.cfg`'s Aliwa `"tp_4"` to a bold, unmistakable
  style (matching the test plume's own values) for the user's very next test. **Bug found while doing this**:
  my first attempt at that edit landed a SECOND, duplicate `"tp_4"` key inside the same `ND-Aliwa-Bmr` `{...}`
  dict — Godot's dict-literal parser silently keeps the LAST duplicate key, so my edit was shadowed by the
  user's own already-saved `"tp_4"` sitting later in the same block; fixed by editing the real occurrence
  instead of blindly inserting a new one — a reminder to always check for an existing key before writing one
  into hand-edited save data.
- **Live direct-manipulation rotation** ("áp dụng cơ chế xoay của plume test... nhưng thay vì bấm numpad thì
  kéo slider"): after the group-name fix, dragging a Rotate X/Y/Z slider still went through a full
  save-to-disk → `reload_3d_weapon_layout()` → free/rebuild-every-anchor round trip on every tick — correct,
  but heavier and one step removed from the TEST PLUME's instant `Node3D.rotation = ...` feel. Added a second,
  lighter path that runs ALONGSIDE the existing one: `arena_weapons.gd` now tracks every live TP particle in
  `_live_tp_particles` (`"<weapon_name>|<tp_id>"` → `Array[CPUParticles3D]`, populated by each `_load_*_plume_
  3d()` via the new `_register_live_tp_particle()`, cleared at the top of `reload_3d_weapon_layout()` so
  repeated reloads don't pile up dead references) and exposes two public setters — `set_live_tp_direction(
  weapon_name, tp_id, dir_rot)` (writes `CPUParticles3D.direction` on every matching live particle directly)
  and `set_live_mount_cal(weapon_name, cal)` (writes the `_aliwa3d_cal`/`_jaeger3d_cal`/`_snake3d_*_cal` var
  directly — already re-read every frame by each weapon's own `_update_*_3d()`, so no rebuild needed at all
  for this one). `creep_edit_mode.gd::_on_glb_rotation_changed()` now calls the matching setter (via the
  `"arena_weapons"` group) THE SAME FRAME the slider moves, before `_save_layout(true)` — the save still runs,
  now purely so the value survives a restart, no longer what makes the drag visible. Verified with a direct
  before/after read of a live particle's `.direction` on a real `arena_weapons.gd` instance: changes
  same-frame, no reload in between.
- **TP list row 3D display** ("dòng (tọa độ X, tọa độ Y) 90 độ... không còn đúng nữa"): `_make_point_row()`'s
  position label always showed the flat `dir_angle` field, frozen at whatever it was when the TP was created
  and meaningless once a TP has `dir_rot` (edited via the 3D sliders now, never touches `dir_angle`). A TP
  with `dir_rot` now shows its real 3-axis position (`_tp_xyz_get()`, the same X/Y/Z-relative-to-object frame
  the "TP POS X/Y/Z" transform panel already uses) and 3-axis rotation in degrees instead — `"(x,y,z)
  R:rx,ry,rz°"`. A plain 2D TP/FP is unaffected, same `"(x,y) angle°"` as before.
- **Dropped the on-canvas direction arrow for 3D TPs** ("bạn đang xoay nhầm mũi tên chỉ hướng thay vì
  plume... xóa mũi tên đó đi"): now that the real particle rotates live (previous entry), the flat 2D arrow —
  always a lossy projection of the true 3-axis direction — risked reading as "the thing you're rotating"
  instead of the actual plume. `grid_overlay.gd::_draw_thrust_points()` now skips the arrow entirely for any
  TP with `dir_rot`; the diamond marker + "TPn" label still draw (still visible/selectable), just without the
  direction indicator. A plain 2D TP (no `dir_rot`, no real 3D plume to compare against) keeps the arrow.

## Changelog — 2026-08-05 (2nd pass) — Gatling `GATLING_POOL` per-rank value dialed from +50% down to +20%, hybrid resolution

- Same-day follow-up to the +50%/rank redesign below, on request: every local rank now contributes **+20%**
  output damage instead of 50%.
- **Hardened Round / Quick Round**: trivial — pure continuous multipliers, just changed `0.5` → `0.2` in
  `_gat_bullet_base()`/`_gat_fire_bonus()`. Still zero RNG.
- **Multishot / Bouncing / Piercing** (bullet-count-based, twin-barrel base = 2 bullets): 20%×2 = 0.4, not a
  whole number — unlike 50%×2 = 1, which is why the prior pass could stay fully deterministic. Asked the user
  how to handle the fractional remainder; picked **hybrid** (guaranteed integer part + a `_proc()` roll for the
  leftover fraction, landing on the correct +20%/rank *expected* value every rank, with an outright guarantee
  every 5th rank since 0.2×5 = 1.0 exactly):
  - `_gat_multishot_chance()`: per-rank constant `1.0` → **`0.4`** (still resolved once per shot in
    `_fire_gatling`, unchanged call site — that function already had the guaranteed+`_proc()` split built in).
  - `_gat_bounces()` / `_gat_pierce_budget()`: dropped the `n`-based even/odd split entirely (no longer needed
    — that trick existed specifically to keep the old 50% design deterministic) and now roll **independently
    per bullet at spawn time** in `_spawn_gat_bullet()` (same place/pattern as the existing Healing Round
    roll), each returning `floor(0.2×rank) + (1 if _proc(frac) else 0)`. Call sites updated back to no-arg.
- **Side-effect**: since Bouncing's fractional roll now goes through `_proc()`, it gains Stroke of Luck synergy
  for the first time (it was always-guaranteed and RNG-free in the 50% pass, so it never touched `_proc()`
  before this). Piercing already had this synergy pre-50%-redesign, lost it when made deterministic, and now
  regains it here.
- **Advance Ballistic** (global) left untouched at +10%/rank, per the same standing decision as the prior pass.
- `GATLING_POOL`'s `"per"`/`"desc"` strings updated to say "20%" and to describe the chance-based framing for
  the three hybrid perks (dropped "guaranteed" wording, added "20%/rank, guaranteed every 5th rank").

## Changelog — 2026-08-05 — Gatling `GATLING_POOL` perks redesigned: every local rank = +50% output damage, deterministic (no RNG)

- **Requested design goal**: each Gatling perk rank should contribute a uniform +50% output damage, so ranks
  are directly comparable across perks (previously Quick Round's 16%/rank, Multishot's 25%/rank, and
  Bouncing's conditional ricochet were not apples-to-apples — see prior conversation turn for the audit).
- **Quick Round** (`_gat_fire_bonus`): 0.16 → **0.5**/rank. Already unconditional/linear, no other change needed.
- **Multishot** (`_gat_multishot_chance`): 0.25 → **1.0**/rank. Root cause of the old dilution: the twin-barrel
  base is already 2 bullets, so a 0.25/rank chance for ONE extra bullet was only ~12.5%/rank relative to that
  base, not 25%. Fixed by making the per-rank contribution 1.0 (= +50% of the 2-bullet base), which also makes
  it fully deterministic at every local rank — `int(ms)` guaranteed extras, no leftover fraction unless a
  global source (Advance Ballistic) mixes one in.
- **Hardened Round** (`_gat_bullet_base`): flat `+2/rank` additive → **multiplicative** `GAT_DAMAGE × (1 +
  0.5×rank)`. Chosen over keeping it flat because multiplicative strictly dominates flat at every rank for
  `GAT_DAMAGE = 5.0` (0.5×5=2.5 > flat 2 per rank), per an explicit "whichever is bigger" request.
- **Piercing Round**: was a hybrid perk (`+20%/rank _proc pierce chance` + `+10%/rank flat damage`, buffed by
  Arc's Stroke of Luck via `_proc()`). Both replaced by a single deterministic mechanic mirroring Bouncing:
  a bullet gets a **guaranteed pierce budget** (`_gat_pierce_budget(n)`) that lets it keep flying straight
  through for one more hit on the next un-hit enemy in its path. The flat `+10%/rank` damage component was
  dropped entirely (per explicit request) so Piercing's whole contribution is the extra-hit budget — and since
  the roll is gone, Piercing **no longer benefits from Stroke of Luck** (a side-effect, not a bug).
- **Bouncing Round**: mechanic unchanged (still a guaranteed ricochet to the most-perpendicular un-hit enemy
  within `GAT_BOUNCE_RANGE`), but the **budget is now per-bullet-slot** instead of a flat rank-wide value:
  `_gat_bounces(n)` / `_gat_pierce_budget(n)` split `ceil(rank/2)` to even slots and `floor(rank/2)` to odd
  slots — deterministic, no RNG. This is what lets both perks keep scaling past rank 2 even though the
  twin-barrel base is only 2 bullets: rank 1 = 1 of 2 bullets gets 1 extra hit, rank 2 = both get 1, rank 3 =
  one bullet chains 2 extra hits + the other 1, etc. — always exactly `rank` extra hits per shot, i.e. +50%
  output damage per rank, same accounting as Multishot's extra-bullet count.
- **`_gat_bounce_or_pierce`/`_gat_spawn_bounce_clone`** rewritten: both budgets now live on the bullet dict
  (`"bounces"`, `"pierce"`) from spawn time; on a hit, whichever budgets are still >0 fire (both can fire the
  same hit — pierce keeps the original bullet going straight while a clone peels off with the bounce, exactly
  as before, just without the RNG roll deciding whether pierce applies).
- **Advance Ballistic** (global multishot perk, buffs every "shots"-tagged weapon, not just Gatling) was
  explicitly left at its original **+10%/rank**, per request — the +50%/rank scheme applies only to Gatling's
  own local pool.
- `GATLING_POOL`'s `"per"`/`"desc"` display strings (read directly by `arena_levelup_ui.gd` — no separate
  numeric binding to update) updated to match.

## Changelog — 2026-08-02 — Divinity loot no longer instant-kills Elite/Champion Creep, only bosses

- `arena_divinity_visual.gd`'s `_kill_touching_enemies()` already spared bosses (`is_in_group("boss")` →
  `RESIST_DPS`/s instead of an instant `take_damage(99999, ..., true)`) — extended the same carve-out to
  `arena_enemy.gd`'s `_is_elite` (read via `en.get("_is_elite")`, no public getter exists). Since a prior
  pass removed the separate `_is_champion` flag, Elite Creep and Champion Creep (`arena_wave_director_v2.gd`'s
  two `_spawn_tiered_creep` tiers) are indistinguishable at the instance level — both just `_is_elite==true`
  — so this is one shared bucket with boss, not three separately-tuned cases. `BOSS_DPS` (200) renamed to
  `RESIST_DPS` and bumped to **300**/s, per-request, for all three.

## Changelog — 2026-08-02 — Fixed 7 level-up weapon icons falling back to gray; beamer's beam now reuses death_beam's VFX (blue)

- **Gray-icon bug root-caused**: NOT a locked-module problem — `inventory_manager.gd`'s `get_icon()` and
  `ITEM_DEFS["yari"]` (etc.) were already correct. `get_icon()` never returns null (an unregistered id falls
  through to `_make_placeholder()`, a solid-rarity-color swatch — gray for `"common"`), so a wrong `def_id`
  silently renders as a gray box instead of erroring. The actual bug: `arena_weapons.gd`'s `WEAPON_INFO`
  table had 7 stale/typo'd `def_id` values that don't match any `ITEM_DEFS` key — `yari→"moroboshi"`,
  `gauss→"gauss_cannon"`, `defensive_orbitals→"orbitals"`, `dragons_breath→"red_x"`,
  `fat_boy→"rosastro_nuclear"`, `ultrasonicator→"sonic_wave"`, `venomancer→"parasite_cloud"` — fixed to
  match their own `ITEM_DEFS` key (all 7 already existed under the "expected" name). Also fixed a compounding
  fallback-ordering bug in `arena_levelup_ui.gd` (`_option_icon_tex`/`_sprite_or_swatch`/`_board_make_choice`
  — 3 call sites): each called `InventoryManager.get_icon(def_id)` unconditionally whenever `def_id != ""`,
  never reaching the `icon` field override one line down since `get_icon()`'s placeholder return already
  looked like success — now gated on `InventoryManager.ITEM_DEFS.has(def_id)` first. This specifically
  matters for `shooter`/`vampire_host`, which have NO real `ITEM_DEFS` entry by design (their own dedicated
  `icon` art, `res://assets/weaponry/shooter.png` / `res://assets/inventory/Vampire Host.png`) — they'd have
  stayed gray even after the 7 def_id fixes above without this ordering fix. Verified via a real-render
  script: 0 of 33 `WEAPON_INFO` + 6 `FUSION_DEFS` entries now resolve to neither an `ITEM_DEFS` match nor an
  `icon` fallback. (Separately, unrelated: the perpetual boot-log `gatling_gun.png not found` error is a
  DIFFERENT bug in `hud_binder.gd`'s HUD-slot icon loader, `assets/inventory/icon/` folder — that folder has
  `gatling.png` not `gatling_gun.png`, and recovers harmlessly via its own `get_icon()` fallback since
  `gatling_gun`'s own `def_id` was never wrong. Not fixed here — out of scope, no visible gray-icon symptom.)
- **Beamer's beam VFX** (`arena_enemy.gd`) now reuses the player's `death_beam` weapon's own procedural
  shader beam (`lasgun_ani_5.gd`, `arena_weapons.gd`'s `BeamScript`) instead of two flat `draw_line()` calls
  — recolored blue via the class's existing `fx_core_color`/`fx_body_color`/`fx_glow_color`/`packet_color`
  `@export` tint parameters (no shader/texture duplication needed, the color was already a parameter, not
  baked in). New `_setup_laser_beam()` (called from `_ready()` for `behavior=="beamer"`) creates one
  `LaserBeamScript` instance per beamer, `beam_thickness` scaled down to 20 (vs. the player weapon's 120) —
  parented to `get_parent()` (Arena root, world-space, no rotation), NOT to the enemy itself, since
  `set_beam(from, to, active, hit)` takes absolute WORLD coordinates every frame (`_beamer_tick`, computed
  from the existing `_beam_origin`/`_beam_dir` state) and parenting under the moving/rotating enemy would
  double-apply that transform. Freed via `tree_exited` (`_on_beamer_gone`) so it can't outlive its owner on
  any removal path (death, `LIFETIME_MAX` despawn, any cull). `_beam_on`/`_beam_dir`/`_beam_origin` are kept
  — still used for the player-hit distance math, just no longer for drawing.

## Changelog — 2026-07-28 (2nd pass) — Bismuth-reflected Gatling bullet slowed to jetfighter speed

- Clarified two DIFFERENT "gatling bounces" mechanisms on request: the **Bouncing Round** perk
  (`_gat_bounce_target()`) only ever ricochets to another ENEMY (`_enemies()`) — it can never hit the
  player. The thing that DOES hit the player is a separate, unrelated mechanic: a **bismuth** enemy
  (`"anti_magnetic": true`) has a `GAT_REFLECT_FRAC` (50%) chance to bounce an incoming gatling bullet back
  at the player instead of taking the hit (`_reflect_bullet()`), dealing `GAT_REFLECT_DMG` (5) if it connects.
- **Slowed the reflected bullet**: was flying back at whatever speed it hit bismuth with (effectively
  `GAT_SPEED` = 900px/s — very hard to dodge). New `GAT_REFLECT_SPEED` const (280.0, matching a jetfighter's
  own bullet speed — `arena_enemy.gd`'s "shooter"/`KITE_BULLET_SPEED`) replaces the inherited speed in
  `_reflect_bullet()`. **Side effect worth knowing**: the reflected bullet's lifetime (`GAT_LIFETIME` = 1.2s,
  unchanged) now caps its effective travel to ~336px (was ~1080px at the old speed) before it despawns —
  bismuth hit from farther than that won't have its reflect actually reach the player. Not extended since
  only the speed was asked for; flag if the shorter reach should be compensated by also raising the reflected
  bullet's lifetime/range.

## Changelog — 2026-07-28 — per-weapon damage/DPS tracking + RUN OVER stats screen

`arena_weapons.gd._roll_damage(base, kind)` is the ONE chokepoint essentially every weapon's damage
passes through before `take_damage()` (crit roll, all the global/family/mastery multipliers) — so it's
where `_dmg_by_kind: Dictionary` (kind → total damage dealt this run) is tallied, right before the
function returns. This gives near-total coverage without touching the ~50+ individual `take_damage()`
call sites scattered through the file. **Known gap**: a few flat/DoT-style hits that bypass
`_roll_damage()` entirely (e.g. Rift Maker's `per_tick` damage) aren't captured — accepted, not chased.
Player-2 companion damage (a separate `arena_weapons.gd` instance, `_companion = true`) also isn't
included — the RUN OVER screen only reads the MAIN instance via group `"arena_weapons"`.

- **`damage_stats() -> Dictionary`** — public copy of `_dmg_by_kind`, read by `arena.gd._build_run_over_
  stats()`.
- **`weapon_display_name(kind) -> String`** — `WEAPON_INFO`/`FUSION_DEFS`'s `"label"` field, falling back
  to a capitalized raw kind id.
- **`arena.gd._show_run_over()`** (RUN OVER screen) now also shows: creeps killed (`GameManager.
  run_kills`), one row per weapon that dealt damage — **weapons with 0 damage are skipped** — as
  `"<name>: <dmg> dmg (<dps>/s)"` where DPS = that weapon's total damage ÷ `GameManager.run_time` (whole-
  run average, not "time that weapon was actually equipped" — simpler, and avoids needing to track
  acquire/replace timestamps per weapon), total damage summed across all weapons, and "Last hit by:
  <icon> <name>" (see [`enemy.md`](enemy.md) for how that's captured — only regular-enemy contact/bullet/
  explosion damage is tracked, not boss-specific attacks, an explicitly agreed scope cut).

## Changelog — 2026-07-28 — Gatling bullets rendered via MultiMesh (perf fix for high-level lag)

**Root cause** (confirmed by reading the code, not guessed): high-level Gatling lag was NOT enemy
collision — `_tick_bullets()`'s `_enemies_near()` grid lookup was already spatially partitioned. It was
the **draw path**: `_draw_tracer()` did ~10 immediate-mode `draw_circle`/`draw_colored_polygon` calls per
bullet (a 5-step tail + 2 glow polygons + edge/body/head polygons via `_oblong()`, each computing 16-20
trig vertices in GDScript) — at high level, ~170-250+ bullets in flight → **1,700-2,500+ draw calls and
tens of thousands of trig ops every frame**, just for tracers.

**Fix**: `arena_weapons.gd` now renders every bullet in `_bullets` (both `gatling_gun` and the `carnage`
fusion — the only two kinds that land in that array, both previously sharing `_draw_tracer`) through ONE
`MultiMeshInstance2D` (`_gat_mm`), the same GPU-instancing pattern already used by
`arena_xp_orb_manager.gd`/`arena_plume_manager.gd` — collapses the whole tracer draw to a single draw
call regardless of bullet count.

- **`_setup_gat_multimesh()`** (called from `_ready()`): loads `res://assets/weaponry/bullet.png` (user-
  supplied art), builds a `QuadMesh` sized to match the tracer's PREVIOUS on-screen size — height =
  `GAT_TRACER_LEN` (16px), width derived from the source image's own aspect ratio (never stretched, per
  the project's image rules) — and a `MultiMesh` with `instance_count = GAT_MM_MAX` (4000).
- **`_sync_gat_multimesh()`** (called every frame right after `_tick_bullets()`): rewrites every visible
  instance's `Transform2D` (position + rotation from the bullet's velocity) from the current `_bullets`
  array. `visible_instance_count` tracks the live count — cheap to change per frame (unlike
  `instance_count`, which reallocates).
- **Sprite rotation**: the art's default pose is assumed nose-up (-Y); `GAT_SPRITE_ROT_OFFSET := PI/2` is
  added to the velocity angle to point the nose along the bullet's travel direction. **Not verified
  against the actual art** — if bullets visibly fly sideways/backwards in-game, flip the sign of
  `GAT_SPRITE_ROT_OFFSET`.
- **What's preserved**: the Healing Round capstone's small red glow overlay (`_draw()` still loops
  `_bullets` for just that, cheap since it's rare) and the muzzle-flash FX (`GAT_CORE/BODY/EDGE_COL`
  still used there, untouched).
- **What's lost**: the old multi-layer glow/tail visual (`GAT_GLOW_SIZE`/`GAT_GLOW_INTENSITY`/
  `GAT_TAIL_LEN` consts removed, now genuinely unused) — replaced by the flat sprite. Expected tradeoff of
  this optimization, not an oversight.
- **Not touched**: other weapons' bullet-ish effects (Gauss orbs, mortar shells, etc.) — this was scoped
  to exactly what the user asked ("tối ưu đạn gatling"), not a general bullet-rendering overhaul.
- **Known caveat, not fixed**: `_gat_mm` is a child node added in `_ready()`, so it now draws ON TOP of
  everything else `arena_weapons.gd._draw()` renders (previously bullets were drawn mid-sequence, before
  several later effects like orbital/thunder/gravwell/prism). Likely imperceptible for fast-moving tracers
  but flagged in case it reads as a stacking-order regression.

## Combat, Asteroids & Materials

This is the big-picture loop the original idle docs don't cover. It spans `asteroid_layer.gd`, `gun_system.gd`, `weapon_manager.gd`, `material_manager.gd`, and the weapon/material/defense panels.

### Material economy (`MaterialManager`)

Four integer currencies — `metal`, `nonmetal`, `organic`, `liquid` — separate from the fuel/crew/credits idle economy. `add(type, n)` / `spend(type, n)` (clamped at 0). The `material_panel.gd` HUD subscribes to `materials_changed`. Materials are earned **only** from asteroids; they are spent **only** on weapons (`WeaponManager`).

### Asteroids (`scripts/gameplay/asteroid_layer.gd`)

- Two instances added to `SpaceScreen`: a blurred, dimmed **under-layer** (`is_under=true`, z_index 0, custom 3×3 blur `ShaderMaterial`) and the interactive **main layer** (z_index 1, joins group `"asteroid_main"`).
- Asteroids spawn from `assets/asteroid/*.png`, drift down within a ±15° cone, rotate, and respawn on exit. Type is parsed from the **leading non-digit chars** of the filename (`dirt`, `ice`, `jewel`, `metal`, `rare`).
- **Collection** = click the asteroid OR a bullet hits it → `_collect_loot(type)` rolls a per-type random drop table into `MaterialManager.add(...)`. Hitbox min size `MIN_HITBOX = 36`.
- Query API used by the gun: `get_asteroid_centers()`, `get_asteroid_sizes()`, `collect_near(pos, radius)`. **Centers are in SpaceScreen-local space** — the gun adds `SS_OFFSET = (270, 8)` to convert to ObjectsContainer/viewport space.

### `weapon_system.gd` vs `gun_system.gd` — QUAN TRỌNG

The active firing engine is **`weapon_system.gd`** (`scripts/gameplay/weapon_system.gd`), not `gun_system.gd`. They run in parallel:

| | `weapon_system.gd` (live) | `gun_system.gd` (legacy) |
|--|---------------------------|--------------------------|
| Role | Equipped-weapon engine + all combat FX | Ship float/movement + asteroid-vs-ship collision |
| Source of weapons | `InventoryManager` equipped slots, read each frame | (mount auto-fire **retired**) |
| Where added | `main.gd` → child of `SpaceScreen`, group `"weapon_system"` | `main.gd` → `ObjectsContainer`, z_index just above spaceship |
| Looked up by | bosses via `get_tree().get_first_node_in_group("weapon_system")` | not group-queried |

`weapon_system.gd` handles fire modes **repeat / charge / beam / channel / aura**; projectiles/missiles/homing/cone-spread/chain/parasites-with-DoT, orbitals, bat swarm, Laser gun (hitscan, mouse-aimed) + Plasma-Drill (tether) beams, Rift-Maker vortex, environment light overlay, and floating crit damage numbers. Primary weapon = left-click, secondary = right-click. It applies each item's hidden `base_mult` (±20%) and affixes when computing stats. **`gun_system.refresh_layout()` and the F4 save/load cycle remain locked** (see LOCKED MODULES).

**Laser gun** (`fire_type: "hitscan_beam"`, item id `"lasgun"`, display name `"Laser gun"`): beam hướng từ muzzle về phía chuột (`get_local_mouse_position() - muzzle`). Fallback `Vector2.UP` chỉ khi chuột trùng muzzle. Affix `splash_radius` → suffix "of Detonation" (chưa implement splash). **`splash_radius` và các affix `multishot/pierce/ricochet/knockback` chưa được wire vào fire logic** (xem comment `weapon_system.gd:2436`).

### Gun system (`scripts/gameplay/gun_system.gd`) — legacy mount auto-fire

> Historical: the description below documents the retired `WeaponManager`-driven mount auto-fire. `gun_system.gd` still runs for ship movement + asteroid collision, but no longer fires.

- A full-rect `Control` (added to `ObjectsContainer`, z_index 7) that fires every `FIRE_INTERVAL = 0.5s` from each **active `"gun"` weapon object** (`WeaponManager.get_active_objects("gun")`).
- Targets the nearest asteroid that is ≥100px above the gun muzzle; spawns a bullet (`atan2(dir.x, -dir.y)` rotation), an ejecting shell, an impact GIF on hit, and plays the gun-fire GIF (hides the static sprite during the animation). GIFs loaded via `GifLoader` (`Gun.gif`, `Gun-Impact50.gif`) from `assets/sprites/weapons/`.
- All projectiles/animations are pooled in plain arrays and ticked manually in `_process` (same manual-pool pattern as the asteroids and scrolling bg).


### Weapons (`scripts/autoload/weapon_manager.gd`) — canvas-driven catalog

The single most important non-obvious pattern: **weapons are discovered from edit-mode-placed sprites, not declared as a static list.**

- `WEAPON_CATALOG` (const) holds only metadata per id: `desc`, `base_cost` (per material), tier `mult` `[1.0, 2.5, 4.5]`, optional `center: true` (single mid-ship mount) and `requires: "wing"` (gate). `get_tier_cost(id, tier)` = `ceil(base_cost * mult[tier])`.
- `sync_from_canvas(placed)` is called from **`edit_mode.gd` after the layout loads** (`WeaponManager.sync_from_canvas(_placed["weaponry"])`). It scans the `"weaponry"` edit group:
  - finds the `spaceship` sprite to get the ship's horizontal center;
  - parses each filename via `_parse_filename()` for **tier** (`" Mk2"`/`" MkII"` → tier 1, `" Mk3"`/`" MkIII"` → tier 2) and a key;
  - assigns each sprite a **side**: `"C"` for `center` weapons, else `"L"`/`"R"` by whether its center is left/right of the ship;
  - fuzzy-groups keys sharing the first 7 chars (`_find_or_add_group`) plus `KEY_ALIASES` (e.g. `homing_missle`→`homing_missile`) to tolerate filename typos.
- `owned[id] = {L, R}` (or `{C}`); `-1` = not purchased. `_refresh_visibility()` shows **only the sprite for the currently-owned tier** per side (so buying Mk2 hides the Mk1 sprite, reveals the Mk2 one). `purchase()` checks `is_tier_available` (symmetric tiers per side), the `requires` gate, and material cost via `MaterialManager`.
- `weapon_panel.gd` (`assets/weaponry/`) renders the shop in fixed `WEAPON_ORDER`.


## Inventory, Items & Affixes (current item layer)

A Diablo-2-style grid inventory with equip slots and rolled affixes. This is the **live** weapon/gear path; `weapon_system.gd` reads equipped items from here. Two autoloads + four UI files.

### `InventoryManager` (`scripts/autoload/inventory_manager.gd`) — data layer

- **`ITEM_DEFS`** (const): master catalog (weapons + hulls + shield). Each def: `name`, `icon`, `size` (grid cells), `tags`, `rarity`, optional `fire_mode`/`fire_type`, `stats` dict.
- **Item instances** (`_items[uid]`): `{def, where, cell, affixes, base_mult, hull_mult}`. `uid` is an int counter (`_next_uid`); `where` = `"backpack"` or a slot name; `cell` = grid origin. `STARTER_ITEMS` are granted once per save (tracked in `_granted`); `RESET_INVENTORY_ON_LOAD` flag re-grants on load.
- **Backpack**: grid (cols × rows from `BACKPACK_COLS/ROWS`), 46px cells. **10 equip slots**: `primary_weapon`, `secondary_weapon`, `thruster`, `command_bridge`, `hull`, `energy_core`, `radar`, `drone_1`, `drone_2`, `wings`. Slot gating via `SLOT_RULES` (per-slot `any` tags required + `exclude` tags blocked) → `fits_slot(def_id, slot)`.
- Key methods: `add_to_backpack`, `move_item(uid, cell)`, `equip(uid, slot)`, `unequip(slot)`, `can_place(size, cell, ignore_uid)`, `generate_weapon(tier, base_def_id)` / `generate_hull(...)`, `roll_asteroid_drop()` (weighted by def `rarity`). Stat accessors apply rolls: `item_base_mult`, `item_affixes`, `item_display_name`, `item_display_color`, `hull_bonus_hp`, `hull_damage_reduction`.
- **Signals:** `inventory_changed`, `item_added(uid)`, `item_equipped(slot, uid)`, `item_unequipped(slot, uid)`. **Save:** `user://save.cfg` section `[inventory]`.

### `AffixManager` (`scripts/autoload/affix_manager.gd`) — affix roller

- **`AFFIX_DEFS`**: ~40 affixes, each with prefix/suffix names, `unit`, `min`/`max`. Pools: `WEAPON_AFFIX_POOL` (~19) vs `HULL_AFFIX_POOL` (~22). No persistence.
- **`roll_affix(id, tier)`**: rolls inside a tier band of `[min, max]` — tier 1 Low (0–33%), tier 2 Mid (33–66%), tier 3 High (66–100%). Negative affixes use the same math (higher tier = more negative = better).

### Rolling model

- Per weapon/hull instance: **30% prefix + 30% suffix** chance independently → **0, 1, or 2** affixes (distinct ids). Plus a **hidden ±20% `base_mult`** (weapons: on damage) / per-stat `hull_mult` (hulls: HP & damage-reduction each roll their own ±20%).
- **Display color = affix count, not def rarity**: white (0 affixes) vs blue (1–2). `rarity` only drives loot-drop weights. Display name = `[Prefix] Base [Suffix]`.

### UI (`scripts/ui/inventory/`)

- `inventory_ui.gd` — toggle panel (key **I** / ESC), rebuilds children on `inventory_changed`; cross-shaped equip-slot grid (each slot sized to its largest item footprint) + backpack grid; right-click item → `sell_requested` → confirm → `sell_item`.
- `backpack_grid.gd` — drag/drop re-arrange; delegates to `can_place` / `move_item`; green/red hover overlay.
- `equip_slot.gd` — drop target; `_can_drop_data` → `fits_slot`, `_drop_data` → `equip`.
- `item_widget.gd` — one placed item; drag source (`_get_drag_data` carries `{uid, def_id, grab, slot}`) + D2 hover tooltip (name colored by affix count → base stats → affix lines). **LOCKED** (tooltip is critical).

---

## Inventory — Equip Slot Tooltips & Gate Fix

### Slot tooltips

`inventory_ui.gd` set `es.tooltip_text = SLOT_LABELS.get(slot, slot)` ngay sau `es.setup(slot)` → Godot tự hiện tên slot khi hover chuột lên ô trống hoặc ô có item.

### Equip-gate on swap (item_widget.gd)

`_drop_data()` trong `item_widget.gd` (khi drop lên equipped item để swap) giờ kiểm tra `InventoryManager.meets_requirement(def_id)` trước khi gọi `equip()` — giống logic trong `equip_slot.gd`. Không đủ stat → `flash_message` + return (item không bị swap).

## Ship Visual System (`gun_system.gd`)

### Hull Skin Swap

Khi equip/unequip hull, `InventoryManager.inventory_changed` → `_apply_hull_skin()` → swap texture của spaceship EO.

- **`HULL_SKIN_MAP`** — dict-of-dicts: `def_id → {"idle": path, "lean": path, "dash": path}`. Thiếu key `lean`/`dash` → fallback về `SHIP_DEFAULT_LEAN` / `SHIP_DEFAULT_DASH`.
- **Default skins:** `SHIP_DEFAULT_SKIN = "res://assets/screen/Spaceship.png"`, `SHIP_DEFAULT_LEAN = "res://assets/screen/lean.png"`, `SHIP_DEFAULT_DASH = "res://assets/screen/dash.png"`.
- `_hull_skin_path(state: String)` — helper tra cứu path cho state `"idle"/"lean"/"dash"` của hull đang equip.
- **Khi thêm lean/dash cho hull mới:** thêm key `"lean"`/`"dash"` vào entry tương ứng trong `HULL_SKIN_MAP`.

### Ship Asset Folder Structure

```
assets/screen/ship/
  <hull_name>/          ← tên folder = tên ship (vd: adamantium, titanium…)
    <hull_name>.png     ← idle skin
    lean.png            ← lean skin (nếu có, nếu không → dùng default)
    dash.png            ← dash skin (nếu có, nếu không → dùng default)
```

Mapping `def_id` → folder (lưu ý `adamantine_hull` → folder `adamantium`):

| def_id | folder |
|--------|--------|
| `titanium_hull` | `titanium/` |
| `adamantine_hull` | `adamantium/` |
| `aerographene_hull` | `aerographene/` |
| `glass_hull` | `glass/` |
| `neutronium_hull` | `neutronium/` |
| `nanobot_hull` | `nano/` |
| `voidmetal_hull` | `voidmetal/` |
| `pzt_hull` | `pzt/` |
| `memory_foam_hull` | `thorned/` |
| `cursed_hull` | `cursed/` |

### Ship Pose System

Pose được set mỗi frame trong `_handle_ship_movement()`. Texture chỉ load khi pose thực sự thay đổi.

```gdscript
const POSE_IDLE       := 0
const POSE_LEAN_LEFT  := 1   # di chuyển sang trái → lean.png
const POSE_LEAN_RIGHT := 2   # di chuyển sang phải → lean.png + flip_h
const POSE_DASH_LEFT  := 3   # dash sang trái → dash.png
const POSE_DASH_RIGHT := 4   # dash sang phải → dash.png + flip_h
```

- `_set_ship_pose(pose)` — áp texture + `flip_h`, skip nếu pose không đổi.
- Khi `inventory_changed`: `_apply_hull_skin()` reset `_ship_pose = -1` → force reload pose hiện tại với skin mới.
- Intro / `input_locked` → force `POSE_IDLE`.


## Arena Weapons (`scripts/gameplay/arena_weapons.gd`)
### `arena_weapons.gd` — Gatling multi-barrel

`GAT_BARREL_SPACING = 18.0px`. `num_barrels = maxi(1, floori(shots_per_sec / 10.0))`. Barrels placed perpendicular to the forward direction:

| shots/sec | barrels |
|-----------|---------|
| 10–19.9 | 1 |
| 20–29.9 | 2 |
| 30–39.9 | 3 |
| 40+ | 4+ |

### `arena_weapons.gd` — Crit System (2026-06-20)

- `const BASE_CRIT_CHANCE := 0.10` — 10% base crit chance at game start, additive with `GameManager.get_crit_chance()` from upgrade cards. Without this, upgrading "crit damage" (multiplier) had no effect because default chance was 0%.
- `_crit_chance = BASE_CRIT_CHANCE + (GameManager.get_crit_chance() if GameManager.has_method("get_crit_chance") else 0.0)` — refreshed on every upgrade pickup.
- `_roll_damage(base: float) -> Dictionary` returns `{"dmg": float, "is_crit": bool}` (changed from plain `float`).
- `_spawn_crit_number(world_pos: Vector2, amount: float)` — spawns a floating Label in a CanvasLayer (layer 12) at screen-space coords via `get_viewport().get_canvas_transform() * world_pos`. Style: red fill `Color(1.0, 0.15, 0.10)`, white outline (size 7), font `Gameplay.ttf` at 22px, scale ×1.6. Tweens: rise 48px over 0.8s, fade out, then `queue_free()`.
- All three weapons (Gatling, Arc, Lasgun) call `_spawn_crit_number()` when `is_crit == true`.

### `arena_weapons.gd` — Arc lightning (textured, from the 2D-lightning tutorial)

The Arc (chain lightning) **visual** is textured `Line2D` bolts (the 2D-lightning-tutorial technique), NOT
immediate-mode polylines. `_fire_arc`'s damage/chain logic is unchanged; only the rendering. Per chain link,
`_spawn_arc_bolt(a, b, delay)` builds a small `bolts` list via `_make_bolt_line` (each `{ln, mat}`): a **main**
strand + a thin **secondary** companion (`ARC_SECONDARY_FRAC` 0.4, same jagged path nudged `±ARC_STRAND_GAP` perp
via `_offset_points`, + a texture `phase` offset so it crackles out of phase). `_arc_line_points` = a jagged path
(random perp kinks per point, `amp = dist*0.1`). Each bolt is a `Line2D` (width `ARC_BOLT_WIDTH`, `STRETCH`) with
`scripts/gameplay/fx/arc_lightning.gdshader` + a **procedural tileable thunder texture** (`_make_thunder_tex` — a
CONTINUOUS bright jagged centreline that always peaks at 1.0 along its length + a soft glow halo; **h=64 so the
bright band is well-resolved**).
**The CONTINUITY rule (hard-won):** the white core is `pow(t, ARC_CORE_SHARP)` — a SMOOTH continuous function of
the texture brightness, NOT `smoothstep(threshold, …)`. A threshold is on/off, and combined with a sub-pixel-thin
bright band it only lit where the jittering centreline landed on a texel row → the core broke into DASHES. A
`pow` core fades smoothly from the bright centreline → an unbroken line. So: body = `color * t*keep` (soft blue
`ARC_HDR_COL`), core = `core_color * pow(t,core_sharp) * keep` (HDR white-blue `ARC_CORE_COL`), additive, blooms.
`scroll_speed = 0` (static, generated once per shot). `_tick_arcs` animates each bolt's `vanishing_value`
(per-link `delay` → outward sweep) and frees the `Line2D`s at `ARC_LIFE`; `_fire_arc` calls `_clear_arcs()` on a
new burst so shots REPLACE the old arc (no stacking). Each strike point spawns `_spawn_arc_sparks`. `get_lights()`
reads each link's `tip` for dust illumination. Tunables: `ARC_BOLT_WIDTH`, `ARC_THUNDER_UNIT`,
`ARC_SECONDARY_FRAC`/`ARC_STRAND_GAP`, `ARC_CORE_SHARP` (core thinness), `ARC_HDR_COL`/`ARC_CORE_COL`/`ARC_LIGHT`.
RULE: never bake a thin bright feature sub-pixel into a low-res texture, and prefer a smooth `pow` over a
threshold for a continuous core. (History: was briefly widened to a 216px branched/forked beam — reverted to this
clean continuous single-bolt-per-link on request.)

### `arena_weapons.gd` — Z-Sword slash (layered, "VFX Anatomy: Slash")

The Z-Sword **visual** is a sweeping energy-slash CRESCENT, not the old radial line (`_draw_zsword` removed).
`scripts/gameplay/fx/z_slash.gd` (`class_name ZSlash`) is an additive Node2D child of `arena_weapons` (created
in `_ready`, typed `Node2D` and called dynamically — do NOT type by `ZSlash` or a fresh-class-name boot fails).
`_tick_zsword` drives it: each frame `set_sweep(center, reach, _zsword_start, blade_ang)`; on each enemy hit
`add_spark(pos)`; on sweep end `fade_out()`. Preview: `scenes/test_slash.tscn` (F6 → plays a sweep, replays on
Space; draws a glow env + white grid so the bloom and the distortion layer are visible). The whole thing is
**additive HDR** (`CanvasItemMaterial` ADD) so it blooms under the arena WorldEnvironment.

**Reworked to a blue-white CRESCENT BLADE** after a detailed crit (the prior green version read as a uniform
"neon tube"). Palette is **white core → cyan body → blue glow → faint violet** (no green). Layers (`_draw`,
back→front):
- **Width curve** `_w(p)= peak·pow(4p(1-p),0.55)` — the crescent is thin at both ends and thick in the MIDDLE,
  tapering to a SHARP point at the leading tip (not a constant-width tube). `BODY_PEAK 46` (big, per "scale").
- **Blue bloom aura** — a wide soft crescent (`BLOOM_PEAK`, `GLOW_COL`, low alpha), strongest toward the lead.
- **Cyan body** — translucent crescent (`BODY_COL`, `BODY_ALPHA 0.5`) — you see the background through it.
- **Ghost streaks** (`_draw_ghosts`) — `GHOST_COUNT` thin polylines at different radial offsets, parallel to the
  arc, broken into fragments (sine gaps), white-blue, lead-bright = speed lines (not curly rainbow noise).
- **Hard cutting edge** (`_draw_cutting_edge`) — a thin near-overexposed line riding the crescent's OUTER
  boundary (`radius + _w(p)`), `EDGE_COL`→`CORE_COL` toward the lead = the bright sharp blade edge.
- **Lead bloom** (`_draw_lead_bloom`) — concentric blue→violet→cyan→white circles at the leading edge (impact mass).
- **Origin wisp** (`_draw_origin_wisp`) — a faint thin tapered quad + small flash from the ship → keeps it
  attached WITHOUT the old rigid bright tube ("hide the emitter" crit).
- **Shards** (`_emit_shard`/`_draw_shards`) — drawn (not particle nodes) white-blue fragments stretched along
  their velocity, trailed off the leading edge during the sweep (direction cue) + a burst per hit (`add_spark`);
  they outlive the body fade. No `CPUParticles2D` here → no scale_amount footgun.
- **Distortion (layer 4)** — `z_slash_distort.gdshader` on a fullscreen `CanvasLayer` (`DISTORT_LAYER 79`),
  `_update_distort` feeds it the arc band (PIXEL space, aspect-correct) from the world centre/radius/`_lead`/span;
  low `aberration` (0.2) to avoid rainbow. Caveat (like the explosion shockwave): invisible on a flat background
  and the CanvasLayer ripples everything below it.
Tunables: `SPAN`/`BODY_PEAK`/`BLOOM_PEAK`/`GHOST_COUNT`/`EDGE_W`/`SHARD_*`, palette `CORE_/EDGE_/BODY_/GLOW_/
GHOST_/SHARD_/VIOLET_COL`. **Lessons:** `CPUParticles2D.scale_amount` is a texture-size MULTIPLIER (~0.8 on a
64px tex; 24 = a ~1500px blob); **don't redefine `PI`/`TAU` in a shader** (built-in → compile error); and for a
sword slash, build a varying-width CRESCENT (thin→thick→sharp) in blue-white, NOT a uniform tube — a constant
half-width additive band reads as a glowing noodle. The scythe HIT's expanding *veil* is still an unbuilt upgrade
in the `slash-technique` memory note.

### `arena_weapons.gd` — SFX

| Const | File | Trigger |
|-------|------|---------|
| `SFX_ENGINE_HUM` | `sfx/enginehum3.wav` | Always-on engine hum — loops via `finished` signal, stops when `ship_hp <= 0`, restarts on `_on_ship_hp_changed`. `PROCESS_MODE_PAUSABLE` → tự pause khi game paused. |
| `SFX_GAUSS_FIRE` | `sfx/hitimpact.wav` | Gauss cannon fires (once per shot) |
| `SFX_GAUSS_IMPACT` | `sfx/AstroMenace-SFX/weaponfire6.wav` | Gauss orb hits an enemy or ruin |
| `SFX_LASGUN_CHARGE` | `sfx/Scifi/blg_beam_01.wav` | Lasgun charge phase bắt đầu (one-shot, guarded by `_las_charge_started`) |
| `SFX_LASGUN_BEAM` | `sfx/AstroMenace-SFX/weaponfire14.wav` | Lasgun beam firing — restarts nếu WAV kết thúc trước khi beam tắt (guarded by `_las_beam_playing` flag) |

**`arena_elephant.gd` M5 SFX:** `SFX_M1 = preload("res://assets/audio/sfx/blob.wav")` (Shoot Blob move).

**Asset folder note:** `AstroMenace-SFX/` nằm ở `assets/audio/sfx/AstroMenace-SFX/` (không phải `sfx/Scifi/AstroMenace-SFX/`).

### `arena_weapons.gd` — Weapon tuning constants (as of 2026-06-25)

| Const | Value | Notes |
|-------|-------|-------|
| `BOOM_SPIN` | `12.566` rad/s | Aliwa flat self-spin = 120 RPM (4π). *Was 50.265 (480 RPM) from some earlier drift until 2026-08-23; restored to the documented rate on request.* |
| `BOOM_ROLL_RPM` | `45.0` | Aliwa 3D tumble about its travel direction (2026-08-23) |
| `SNAKE_SPACING` | `25.2` px | = `BODY_SEG_PX` → zero gap between body segments |
| `YARI_TURN_RATE` | `120/60 × TAU` rad/s | 120 RPM — shared by both Yari Jaeger and Yari (moroboshi) |
| `MORO turn` | uses `YARI_TURN_RATE` | `_moro_facing` clamped by `angle_difference + clampf` instead of instant snap |

### `arena_weapons.gd` — Gauss orb visuals

- `GAUSS_ORB_DRAW = 38.0` px — kích thước hiển thị trên screen (TextureRect 38×38). Frame nguồn là ~421px nhưng được scale về 38px.
- `GAUSS_TRAIL_WIDTH = 0.75` — hệ số nhân bán kính trail circle (`base_w = GAUSS_RADIUS × GAUSS_TRAIL_WIDTH`). Giảm để trail nhỏ hơn, bớt "vòng sáng" quanh orb.
- **Trail và charge rings dùng gradient layers** — mỗi vị trí trail vẽ 4 circle lồng nhau (outer soft → inner bright) với `antialiased=true`. Charge rings tương tự 4 arc layers. Đây là cách mô phỏng soft/glow edge trong Godot 4 CanvasItem `_draw()` (không có built-in blur).

### `arena_weapons.gd` — Generic Plume Registry (2026-06-25)

Replaces 9 per-weapon load/update functions (~390 lines) with a single generic system (~90 lines).

**API:**
```gdscript
var _plume_registry: Array = []   # [{cfg_key, count, ds, provider, anchors}]

func _register_plume(cfg_key: String, count: int, ds: Vector2, provider: Callable) -> void
func _load_all_plumes() -> void   # call once in _ready() after all registrations
func _update_all_plumes() -> void # call once per frame in _process()
```

**How it works:**
- `_register_plume()` adds a weapon entry with a `provider` Callable that returns `Array[{pos, rot, visible}]`
- `_load_all_plumes()` reads `weapon_layout.cfg` [thrustpoints] and `weapon_plume_styles.cfg` [styles] in ONE pass for all registered weapons. Creates `count` anchor Node2Ds each with CPUParticles2D children at TP frac offsets.
- `_update_all_plumes()` calls each provider, moves anchors to returned world positions + rotations.

**Adding a new weapon plume:** add TPs in `weapon_layout.cfg` + styles in `weapon_plume_styles.cfg`, then one `_register_plume()` call in `_ready()`. No new functions needed.

**Kept separate (too complex for generic pattern):**
- Snake (`_load_snake_plume` / `_update_snake_plumes`) — multi-segment chain physics
- Para cloud (`_load_para_plume_data` / `_make_para_cloud_plume`) — dynamic lifecycle (created/freed per cloud)

**`local_coords = false` in `_make_orbital_plume()`:** All plumes use world-space particles. When a weapon rotates or changes direction, previously emitted particles continue on their old trajectory (inertia) while new particles emit in the new direction — physically correct curving trail. Setting this to `true` makes plumes rigidly rotate with the weapon (wrong).

### `arena_weapons.gd` — Spore (Parasite Cloud) Mechanics (2026-06-25)

**Gas cloud VFX on expire:** When a spore's `age >= PARA_LIFETIME`, instead of disappearing silently it spawns `PARA_GAS_PUFF_N = 7` DynamicFire puffs (1 centre + 6 on ring at `PARA_RADIUS × 0.55`) at its final position. These live for `PARA_GAS_LIFETIME = 4.0s` and render via `_para_gas_fx: DynamicFire` (green→purple, `intensity=0.15`). The circle drawn by `_draw_para_cloud()` has `alpha=0.0` — players see only the gas cloud, not the circle.

**Facing freeze fix:** Cloud dict has `"ang"` key (initialized to launch direction angle). Updated each tick only when `vel.length_squared() > 1.0` — freezes on last valid velocity direction instead of snapping to `angle=0.0` when decelerated. `_draw_para_cloud()` uses `c.get("ang", 0.0)` for sprite rotation.

### `arena_weapons.gd` — Auto-fire logic

**`_has_enemy_on_screen() -> bool`:**
- Trả `true` ngay nếu `GameManager.is_boss_alive()` (boss luôn kích hoạt auto-fire bất kể vị trí)
- Dùng `get_viewport().get_canvas_transform()` convert world pos → screen pos
- Rect kiểm tra = viewport rect được mở rộng 50% mỗi cạnh (`grow_individual(vp_size.x * 0.5, vp_size.y * 0.5, ...)`) — tổng diện tích gấp 4 lần screen

**Behavior khi không có enemy:**

| Weapon | Behavior |
|--------|----------|
| Gatling | Tích `_gat_acc` bình thường, không gọi `_fire_gatling()` → bắn ngay khi enemy xuất hiện |
| Gauss | Charge đến full (`_gauss_charge` vẫn tăng), giữ nguyên, fire ngay khi enemy xuất hiện |
| Arc | Skip `_fire_arc()` — `_arc_cd` vẫn tick |
| Lasgun | Dừng `_fire_lasgun(delta)` → `_las_t` không advance (cycle paused); tắt beam visuals + audio |

