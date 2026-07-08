# Enemy — Bosses, Arena & Normal Enemies

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on enemy behavior, bosses, waves, arena enemies, ruins, enemy panel.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

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


