extends Node2D
## NOTE: was CharacterBody2D. Enemies are now plain Node2D — movement is manual (global_position += velocity·dt
## via _move_step) and enemy-vs-enemy separation is done by the spatial-hash pass in arena_enemy_manager, NOT the
## physics engine. This removes hundreds of CharacterBody2D bodies + move_and_slide solves from the per-frame cost.
## Nothing outside this file depended on the body: weapons find enemies by group + hit_radius distance (never physics).
## World-space arena enemy — the port of the legacy NormalEnemy roster as ONE data-driven script. The
## wave_director configures each instance from its enemy table (behavior + stats); this script runs the
## behavior each frame, takes damage via the universal take_damage(amount) contract (so arena_weapons hit
## it), deals contact damage to the player via GameManager, and grants XP on death.
##
## Behaviours ported (shmup-directional ones reinterpreted player-relative for the top-down arena):
##   chase, centipede, dash(diver), orbit(dragonfly), jump(octopus), jump_diag(spider), scatter(fly),
##   swarm_dive(bee/bug/swarm), shooter, sentinel, beamer, bomber(bombing-wanderer), missile, bomb,
##   dummy, boss_stub(elephant/chromeleon/metalfly). Uses the real enemy sprites (def "icon") when present,
##   falling back to placeholder shapes.

const GifLoader        := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const ArenaExplosion   := preload("res://scripts/gameplay/arena_explosion.gd")
const DeathFX          := preload("res://scripts/gameplay/arena_death_fx.gd")
const EnergyVortex     := preload("res://scripts/gameplay/fx/energy_vortex.gd")
const LedLight         := preload("res://scripts/gameplay/fx/led_light.gd")
const GlbSpinBody      := preload("res://scripts/gameplay/fx/glb_spin_body.gd")         # generic spinning 3D body (Metalfly's phase-1 cocoon)
const GlbRigScript     := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd")       # editor-space -> view-space rotation math (see _creep_mount_rot)
const MetalflyRig      := preload("res://scripts/gameplay/fx/metalfly_rig.gd")          # boss_move "metalfly": live code-posed 3D body
const MetalflyPath     := preload("res://scripts/gameplay/fx/metalfly_charge_path.gd")  # ...and its Move 2 lane telegraph
const MetalflyRing     := preload("res://scripts/gameplay/fx/metalfly_swarm_ring.gd")
const ItemDropScript   := preload("res://scripts/gameplay/arena_item_drop.gd")   # Elite/Champion weapon drop, see _drop_tier_weapon()   # ...and its Move 3 gathering ring
const LaserBeamScript  := preload("res://scripts/gameplay/lasgun_ani_5.gd")   # beamer's beam VFX — same procedural shader beam as the player's death_beam weapon, recolored blue (see _ready()'s "beamer" setup)
# Per-enemy attack SFX (one-shot; played from a lazily-created AudioStreamPlayer on bus "SFX").
const SFX_SPIDER_JUMP  := preload("res://assets/audio/sfx/dash.wav")      # spider (jump_diag) leap
const SFX_OCTOPUS_JUMP := preload("res://assets/audio/sfx/chargeby.wav")  # octopus (jump) leap
const SFX_BEAM         := preload("res://assets/audio/sfx/laserbeam.wav") # beamer beam fire (once, no loop)
const SFX_ZAP          := preload("res://assets/audio/sfx/zap1.wav")      # shooter / sentinel fire

static var simplified_mode: bool = false
# Perf optimization: prefer a pre-baked low-res sprite (tools/downscale_enemies.gd, assets/Enemies
# Downscale/) over the HD source — a light texture at the creep's actual display size instead of the full
# HD art. Re-enabled (2026-07-27) now that tools/downscale_enemies.gd has been re-run at the CURRENT sizes
# (incl. the fly/bug/bee/diver ×3-then-×0.7 resize + fly's new flap_icons pair) — the banding seen earlier
# was a STALE bake (baked for an old, smaller size, then stretched past it), not a problem with baking
# itself. Re-run the tool any time creep/fleet sizes change again; set false here only to bypass entirely.
const USE_DOWNSCALED_SPRITES := true
const ICON_DRAW_SCALE := 2.6   # drawn sprite width = _radius × this (sprites read a bit bigger than the hit circle)
const ENEMY_LAYER := 2              # physics layer enemies live on (separate from the player on layer 1)
## A def's "size" is not the hit radius — it is scaled by this. Named (was an inline 1.05 at the one place
## that reads it) because anything deriving a def "size" BACK from a live `_radius` has to divide it out, and
## silently being 5% off is exactly the kind of thing nobody notices: the Metalfly brood's bodies came out
## 26.2% of the boss instead of the 25% they were specified at.
const SIZE_TO_RADIUS := 1.05
const CORE_FRAC := 0.75             # collision-core radius = _radius × this. Kept modest: the soft player-push already makes the crowd read as a wall, and bigger cores make the physics solver much more expensive in dense packs.

# TEMP DIAGNOSTIC — used by arena_perf_spike_logger.gd to report how many enemies died in a spiking frame.
# Safe to delete alongside that file once the "sudden lag" cause is found.
static var _death_count_since_read: int = 0
static func consume_death_count() -> int:
	var n := _death_count_since_read
	_death_count_since_read = 0
	return n
const SWARM_ZOOM_SPEED := 400.0     # swarm "zoom" mode — fly straight through the player and keep going
const SWARM_ZOOM_CULL  := 1200.0    # ...then silently despawn once this far from the player
const RETURN_DIST := 900.0          # dive group re-aims at the player once it gets this far away (loops back)
# "spiral" (diver) and "vortex_dive" (dragonfly) tighten their orbit radius at a rate scaled by
# _orbit_r0/ORBIT_SPAWN_REF_R — SPIRAL_SHRINK/VORTEX_SHRINK are the rate AT ORBIT_SPAWN_REF_R (v1's
# SPAWN_RADIUS, arena_wave_director.gd — where they were originally tuned/felt right). Without this scaling,
# a fixed px/s rate means time-to-dive is proportional to spawn distance — fine at v1's ~600-840px spawn
# ring, but spawn_mode_2's annulus spawns much farther out (~1000-1900px, see R_PADDING/R_WIDTH in
# arena_wave_director_v2.gd), which was stretching diver's tighten-then-dive to 35-65+ seconds — reads as
# "stuck", not orbiting (2026-07-28 bug report: "32 diver, never seen approaching"). Scaling keeps
# time-to-dive approximately CONSTANT (≈ ORBIT_SPAWN_REF_R / rate) regardless of where the enemy actually
# spawned, so v1's own feel at its own spawn radius is unchanged (rate ≈ SPIRAL_SHRINK/VORTEX_SHRINK there
# by definition). "vortex_dive" steers VELOCITY toward a point on this shrinking-radius ring (rather than
# snapping global_position straight to it, like the old "orbit" behavior did) — a deliberate, guaranteed
# radius decay, NOT a free pursuit-curve steer: an earlier version reused "steer_chaser"'s pure
# dir+tangent-blend math verbatim, which measurably settled into a stable wide orbit (200-400px, oscillating,
# never shrinking) instead of reliably reaching the dive trigger — a known real property of constant-bearing
# pursuit against a near-stationary target at a high tangent ratio, not a rare edge case.
const ORBIT_SPAWN_REF_R := 720.0    # v1's SPAWN_RADIUS (average) — the distance these rates were tuned at
const SPIRAL_SHRINK := 75       # px/s the spiral radius tightens toward the player (diver), AT ORBIT_SPAWN_REF_R
const VORTEX_SHRINK  := 60.0    # px/s the vortex radius tightens toward the player (dragonfly), AT ORBIT_SPAWN_REF_R — faster than the old "orbit" behavior's 28, per "bay nhanh hơn"
const SPIRAL_CENTER_SPEED := 80.0   # px/s the spiral center drifts toward the player — run faster to pull away
const TURN_RATE := 10.0             # how fast a sprite eases to face its movement direction (head = sprite north)
const THROWN_BOMB_SPEED := 460.0    # bomber's thrown bombs travel this fast (straight, aimed at the player)
const THROWN_BOMB_RANGE := 1200.0   # a thrown bomb despawns after travelling this far (projectile, not an enemy)

# ── Swarm loop (boomerang re-dive) — charge the player, fly out to a big radius, bank around, charge again ──
const SWARM_LOOP_DIVE_SPEED  := 400.0   # px/s charge speed toward the player
const SWARM_LOOP_RANGE       := 1320.0  # px it flies out to before turning back (~4x the Aliwa boomerang BOOM_SIZE 330)
const SWARM_LOOP_WAIT        := 5.0     # min seconds spent out past the range before it charges again
const SWARM_LOOP_DRIFT_SPEED := 120.0   # px/s slow outward drift while waiting off-map
const SWARM_LOOP_COAST_SPEED := 300.0   # px/s speed during the graceful banking turn
const SWARM_LOOP_TURN        := 1.6     # rad/s cap on the banking turn (graceful, not an instant snap)
# ── Bee dive-bomber — approach to standoff, hover, then dive with slight homing; loops until killed ──
const BEE_STANDOFF   := 400.0   # px: approach to this distance from the player before the hover
const BEE_PAUSE      := 1.0     # seconds hovering before committing to the dive
const BEE_DIVE_SPEED := 320.0   # px/s dive speed
const BEE_TURN       := 1.2     # rad/s cap on steering the dive toward the player (tracks a bit, not perfectly)

# ── Centipede: a segmented body that crawls toward the player using the Viper weapon's chain logic
# (ported from arena_weapons.gd SNAKE_*). The node IS the head (collision + damage target); the body
# segments TRAIL it at a fixed spacing. Segment pixel sizes scale with the enemy _radius. ──
const CENTI_SEGMENTS_DEFAULT := 10  # 1 head + 8 body + 1 tail — def-overridable, see "centi_segments" below
const CENTI_VIPER_SPEED := 300.0    # arena_weapons.gd SNAKE_SPEED — the Viper's move speed
const CENTI_TURN        := 3.0      # head max turn rad/s (mirrors SNAKE_TURN)
# All 3 sprites are drawn upright (spine vertical: head face / segment connection at TOP, tail stinger at
# bottom), so every segment shares one ACROSS width and rotates by ang+PI/2. Follow-spacing = the body
# segment's along-spine length (height), so body segments sit flush.
const CENTI_WIDTH_MUL   := 1.95     # across width of every segment = _radius × this (75% of ICON_DRAW_SCALE 2.6)
# Default sprite set — the ORIGINAL (electric map) centipede; any def without its own "centi_head_icon"/
# "centi_body_icons"/"centi_tail_icon" falls back to these, so the "centipede" entry itself is untouched.
const CENTI_HEAD_ICON_DEFAULT := "res://assets/map/electric/enemies/centipedehead.png"
const CENTI_BODY_ICON_DEFAULT := "res://assets/map/electric/enemies/centipedebody.png"
const CENTI_TAIL_ICON_DEFAULT := "res://assets/map/electric/enemies/centipedetail.png"
const CENTI_MAX_BEND_DEFAULT := PI * 0.5    # max joint bend (rad) between two consecutive segments — a segment can
									 # swing up to 90° off the previous one's own direction but no further, so
									 # the body can't fold back on itself (e.g. the tail whipping around to
									 # point back at the head) when the head reverses/turns sharply.

# ── Teleport (alien) — blink toward the player every TELE_INTERVAL; gently FLOAT adrift between blinks ──
const TELE_INTERVAL    := 2.0       # seconds between teleports
const TELE_DIST        := 200.0     # px jumped toward the player each teleport
const TELE_FLOAT_RADIUS := 24.0     # drift radius of the slow idle float around the anchor (replaces the old jigger)
const TELE_FLOAT_FREQ  := 0.85      # idle float speed (slow → reads as lazily floating, not jittering)
# ── Patrol (fleet/sentinel) — straight flyby across the screen at `speed`, never re-aims ──
const PATROL_CULL   := 1500.0       # despawn once this far from the player (flew off-screen)
const CHASE_CULL    := 1700.0       # chasers the player has outrun this far are recycled (well beyond the visible area) — frees the alive-cap budget so the director refills the horde on-screen (VS/HoT-style off-screen recycling)
# ── Gauss shooter (pros5) — fires a gauss-style orb at the player ──
const GAUSS_SHOOT_INTERVAL := 3.0   # seconds between gauss orbs
# ── Mothership carrier (prosmotherblank) — docked escort + flee/release/respawn cycle ──
const MS_READY   := 0   # docked squadron, slowly advancing on the player
const MS_TURN    := 1   # turning tail (50 rpm) to face away before fleeing
const MS_FLEE    := 2   # fleeing @120 + releasing escorts, one every MS_RELEASE_INTERVAL
const MS_WAIT    := 3   # fleeing; MS_WAIT_AFTER_RELEASE pause before rebuilding
const MS_RESPAWN := 4   # fleeing; rebuilding the escort, one every MS_RESPAWN_INTERVAL
const MS_READY_HOLD        := 3.0     # READY: seconds to advance before auto-firing the next cycle (timer-driven, NOT damage-driven). After a respawn finishes the carrier waits this long, then releases again.
const MS_TURN_RAD          := 5.235988 # 50 rpm = 300°/s, in rad/s (deg_to_rad(300))
const MS_APPROACH_SPEED    := 60.0    # READY: slow looming advance toward the player
const MS_FLEE_SPEED        := 120.0   # flee speed once turned around
const MS_REGROUP_DIST      := 500.0   # WAIT/RESPAWN: hover at this standoff (on-screen, but mobile not a sitting duck)
const MS_RELEASE_INTERVAL  := 0.5     # seconds between releasing each docked escort (5 → 2.5s)
const MS_WAIT_AFTER_RELEASE := 5.0    # pause after the last release before respawning begins
const MS_RESPAWN_INTERVAL  := 2.5     # seconds per rebuilt escort (5 → 12.5s)
const MS_RESPAWN_ORDER     := ["pros7", "pros8", "pros8", "pros5", "pros6"]   # rebuild sequence
const MS_CYCLE_ENABLED     := false   # 2026-07-28: explicit request — carrier must not flee. false → MS_READY's advance-on-player loop (velocity = dir * MS_APPROACH_SPEED) never times out into MS_TURN/MS_FLEE, so it just keeps closing the distance forever, docked escorts intact. (true = the old full flee/release/respawn cycle on a timer, still here if this ever needs reverting.)
# ── Magma split (large magma → small magma on death) ──
const MAGMA_SPLIT_N      := 3       # small magma flung out when a large magma dies
const MAGMA_SPLIT_SCALE  := 0.5     # small magma size = this × the parent magma size
const MAGMA_SPLIT_FLING  := 300.0   # outward knockback (px/s) given to each small magma so it "bursts" out

# ── "Alive" procedural-motion tunables (sprite transform only — no new art) ────
const BOB_AMOUNT     := 0.05    # idle breathing scale pulse (±)
const BOB_FREQ_MIN   := 2.2     # per-enemy breathing speed range (randomized → crowd desyncs)
const BOB_FREQ_MAX   := 3.6
const SQUASH_MAG     := 0.12    # max stretch-along-travel / thin-across when moving fast
const SQUASH_EASE    := 9.0     # how fast squash eases toward its speed-driven target
const SQUASH_REF_SPEED := 220.0 # speed at which squash reaches full magnitude
const HIT_FLASH_COLOR := Color(1.0, 1.0, 1.0)    # normal hit → white
const KILL_FLASH_COLOR := Color(1.0, 0.18, 0.18) # a killing blow → red
const HIT_FLASH_TIME := 0.20    # flash duration on hit (white sprite flash to register the hit)

# ── Elite/Champion Creep glowing ring (2026-08-25, on request: "với các enemy elite, vẽ vòng tròn vàng phát
# sáng bao quanh nó. Champion thì vòng đỏ") — a milestone spawn (arena_wave_director_v2._spawn_tiered_creep,
# 2-3× normal size already) also needs to read as one AT A GLANCE even buried in a crowded field, not just
# from its size. Champion (_is_champion) supersedes Elite (_is_elite alone) for colour, same branch order the
# death-reward split already uses in _die() — every Champion also carries _is_elite=true for the cap-bypass,
# so checking _is_champion FIRST is required, not optional. Drawn around `_radius` (already the promoted,
# up-scaled hit radius — see configure()'s `_radius = size * SIZE_TO_RADIUS`), so the ring grows with the
# creep's own up-scaled size automatically, no separate size lookup needed.
const TIER_RING_ELITE_COL    := Color(1.0, 0.85, 0.15)   # gold/yellow
const TIER_RING_CHAMPION_COL := Color(1.0, 0.18, 0.15)   # red
const TIER_RING_MARGIN       := 10.0   # px beyond _radius the ring sits at
const TIER_RING_WIDTH        := 3.0    # outline stroke width
const TIER_RING_PULSE_SPEED  := 2.5    # rad/s — matches arena_chest.gd's own beacon-aura pulse cadence
# Flash shader: lerp the sprite's pixels toward flash_color by `flash` (modulate-white can't whiten a texture).
const FLASH_SHADER_CODE := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
void fragment() {
	COLOR *= texture(TEXTURE, UV);
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash * COLOR.a);
}
"""
static var _flash_shader: Shader = null
const KNOCKBACK_SPEED := 460.0  # recoil impulse away from the player on hit (px/s, decays) — more prominent
const KNOCKBACK_DECAY := 10.0
const SPAWN_POP_TIME := 0.20    # scale-up-with-overshoot + fade-in on spawn
const DEATH_POP_TIME := 0.15    # stretch + scale-up + fade-out before freeing
const SCALE_VAR      := 0.15    # per-enemy base-size variance (±) so the crowd looks individual
# Docked (mothership/fleet escort) or fleet-carrier hit reaction: a real _knockback displacement here would
# move global_position, which is exactly what every OTHER docked node re-pins itself to each frame — the
# whole formation would jerk from a single hit. HIT_SHAKE is a small purely-VISUAL offset (applied only in
# _draw()'s transform, decays independently) so the specific hit unit still reads as "hit" without moving
# its actual position or dragging any sibling along.
const HIT_SHAKE_MAG   := 14.0
const HIT_SHAKE_DECAY := 10.0
# Fleet Edit escort follow: each escort chases its carrier-relative slot (+ a small continuous positional
# wander, "độ lệch vận tốc random nhỏ" so the formation looks loosely held rather than bolted) but is VELOCITY
# CAPPED at FLEET_MAX_SPEED_MULT × its own `speed` stat — never faster than that, no matter how far the slot
# just jumped. This matters most when the carrier turns: a wide formation's outer slots sweep through a big
# arc (target = carrier_pos + base_off.rotated(_facing)), and a naive "snap/lerp toward target" would imply a
# speed far beyond what the escort could ever actually fly, reading as a teleport. The same cap governs a
# knocked-out-of-formation escort (real knockback now applies per-unit — see take_damage()'s dock_kind
# "fleet") catching back up to its slot: it visibly "hustles" home at its own capped top speed, never faster.
const FLEET_WANDER_FREQ_MIN := 0.6
const FLEET_WANDER_FREQ_MAX := 1.4
const FLEET_WANDER_AMP      := 4.0
const FLEET_MAX_SPEED_MULT  := 1.3   # hard cap on hold-formation/catch-up speed: 130% of the escort's own `speed`

## Safety-net lifetime cap: a normal enemy still alive after this long (_t, since spawn) is silently freed
## via _despawn_stale() (queue_free, no death FX/kill-count/loot/reward — this isn't a kill) instead of
## piling up forever for whatever reason it never reached/engaged the player. Bosses ("boss_stub" behavior)
## are exempt — multi-minute fights are expected there.
const LIFETIME_MAX := 120.0

## Options for the Creep Info dev panel's Move/Shoot dropdowns (scripts/ui/hud/creep_info_panel.gd reads
## these directly). "" (Move) / "none" (Shoot) = no override, keep the def's original hand-tuned `behavior`.
## A curated, generic subset — NOT a 1:1 port of every one of the ~30 bespoke `behavior` cases (centipede's
## chain, mothership's docking cycle, magma's split-on-death, swarm's boomerang loop, etc. don't decompose
## into an orthogonal move+shoot pair without losing what makes them that specific enemy) — see
## _tick_move_logic()/_tick_shoot_logic() below for exactly what each option does.
const MOVE_LOGICS: Array[String]  = ["chase", "standoff", "orbit", "spiral", "patrol", "teleport", "roam", "stationary"]
const SHOOT_LOGICS: Array[String] = ["none", "burst", "fan", "beam"]
const COMPOSED_STANDOFF_RANGE := 340.0   # move-logic "standoff": preferred hold distance from the player

# ── Global difficulty tuning ───────────────────────────────────────────────────
# Applied at spawn to the def's base values (see setup). HP is doubled for every NON-boss enemy (bosses use
# behavior "boss_stub" and are exempt so boss fights stay tuned); XP value is doubled for all enemies.
const ENEMY_HP_TUNE := 2.0
const ENEMY_XP_TUNE := 2.0
# Chase speed ×tune for non-bosses — closes the gap on the player (320 px/s) so straight-line kiting isn't a
# free escape. e.g. a 95 px/s crawler → 171, a 150 px/s runner → 270 (still under player speed). Bosses exempt.
const ENEMY_SPEED_TUNE := 1.8
# Flank/envelop steering (Halls-of-Torment feel): each chaser adds a small per-enemy PERPENDICULAR bias to its
# seek direction, so the crowd fans into a surrounding arc instead of trailing single-file behind you. The bias
# fades out as the enemy closes (FLANK_FADE_*) so the arc still collapses onto the player for contact.
const FLANK_BIAS_MAX := 0.6     # max |perp/forward| ratio (~31° max approach offset at full bias)
const FLANK_FADE_NEAR := 60.0   # ≤ this distance → no flank (home straight in for the hit)
const FLANK_FADE_FAR  := 320.0  # ≥ this distance → full flank bias
# Soft crowd shove: an overlapping enemy pushes the ship away at up to this px/s (× overlap depth). GameManager
# sums every enemy's push and caps the total (PLAYER_PUSH_MAX) so a dense mob slows you like a current, not a wall.
const ENEMY_PUSH_STRENGTH := 110.0

# ── spawn_mode_2 steering behaviors (arena_wave_director_v2.gd test roster only) ──────────────────
# "steer_chaser" (flies) — vortex/spiral seek: a tangential swirl blended with the straight seek dir, strong
# far from the player and fading to a direct dive up close (funnels in like a vortex instead of beelining).
# Separation is still entirely the manager's spatial-hash pass - never computed here. NOT reused by v1's
# "vortex_dive" (dragonfly, below) despite the similar name/feel - see VORTEX_SHRINK's comment for why a
# free pursuit-curve steer like this one doesn't reliably converge against a near-stationary target.
const VORTEX_TANGENT_RATIO := 1.6   # tangential/radial ratio at full strength (>1 → wide swirling arcs)
const VORTEX_FADE_NEAR := 50.0      # ≤ this distance → no swirl, straight dive in for the hit
const VORTEX_FADE_FAR  := 500.0     # ≥ this distance → full swirl strength
# "vortex_dive" (dragonfly) — once the vortex swirl above closes to VORTEX_DIVE_TRIGGER, commits a straight
# overshoot dash (like a whiffed strike carrying it past the player) for VORTEX_OVERSHOOT_TIME, then curls
# back into the vortex — now re-homing on the player's CURRENT position — instead of the old "orbit"
# behavior's dash, which never returned (just kept re-aiming and dashing forever once committed).
const VORTEX_DIVE_TRIGGER     := 40.0   # px from the player that commits the vortex→overshoot dash
const VORTEX_DIVE_SPEED_MULT  := 1.7    # overshoot dash speed = speed × this (matches the old "orbit" dash mult)
const VORTEX_OVERSHOOT_TIME   := 0.4    # seconds spent in the committed straight dash before curling back into the vortex
# "steer_flanker" — seeks a point AHEAD of the player (player_pos + player_vel * FLANK_PREDICT_T), read
# from the v2 director via group "wave_director" (has_method("player_velocity") guarded).
const FLANK_PREDICT_T := 0.5
# "shooter" (jetfighter) — always closes toward the player (no standoff/flee — explicit request), but ALSO
# coheres toward the shared flock centroid (arena_enemy_manager._tick_jf_flock/jf_flock_center) so multiple
# jetfighters clump into one pack and move together instead of each independently approaching on its own.
# Separation (not literally overlapping) is untouched — the existing spatial-hash push-apart already
# handles that; this only adds the "pull together when far apart" half of flocking, additively blended with
# the player-approach pull (see the "shooter" case in _tick_behavior).
const JF_FLOCK_WEIGHT   := 0.7    # how strongly the cohesion pull competes with the player-approach pull
const JF_FLOCK_HOLD_R   := 70.0   # already "in" the pack within this of the centroid — cohesion pull stops
# "steer_kiter" — 3-zone standoff: approach past R_ATTACK, hold+fire between R_FLEE and R_ATTACK, flee
# below R_FLEE. Fires from global_position (test enemies have no authored firepoints).
const KITE_R_ATTACK      := 340.0
const KITE_R_FLEE        := 160.0
const KITE_FIRE_INTERVAL := 1.2
const KITE_BULLET_SPEED  := 280.0
const KITE_BULLET_DMG    := 5
# "steer_charger" — approach slow → lock aim + telegraph (pulsing flash) → dash in a straight line.
const CHARGE_APPROACH_SPEED := 70.0
const CHARGE_LOCK_RANGE     := 260.0
const CHARGE_TELEGRAPH_T    := 0.6
const CHARGE_PULSE_FREQ     := 18.0
const CHARGE_DASH_SPEED     := 620.0
const CHARGE_DASH_T         := 0.5

# ── Metalfly boss ("boss_move": "metalfly" in the def — see _tick_metalfly) ─────────────────────────────
# TWO PHASES, one node. Phase 1 is a cocoon: a separate 3D body (Cocoon.glb, a static mesh), its OWN small
# HP pool, spinning in place while it chases the player fast. Killing it does NOT kill the boss — the
# `hp <= 0` branch of take_damage() is intercepted (`_metalfly_hatch`), so no XP, no loot, no kill tally,
# no death FX beyond the hatch blast. The winged body and its moveset only exist from Phase 2 on.
#
# The DEF's own hp/speed are Phase 2's (they are the real boss's numbers, and every def-level multiplier —
# player level, Beacon, the director's HP_MULT — is already baked into them by configure()). Phase 1's are
# the flat constants below, captured/restored in configure() + _metalfly_hatch().
const MF_COCOON_GLB      := "res://assets/map/electric/boss/Cocoon.glb"
## Creep Edit layer names for the two bodies — the KEY each one's mount angle is stored under in
## creep_layout.cfg. Defined here, not in the editor, so the contract has exactly one owner: creep_edit_mode.gd
## already preloads this script and reads these, while this script preloads nothing of the editor's (a
## preload the other way would close a cycle). A typo would be silent — the layer would simply never find
## its saved rotation — which is why neither side spells the string twice.
const MF_LAYER_COCOON    := "Metalfly Cocoon"
## The winged body is keyed under the boss's own name, not a "… Wings" suffix, because in Creep Edit it IS
## the group's root row — the boss's palette entry and its Phase 2 body are the same object. Giving it a
## separate name put a second, identical model on the canvas stacked exactly on the root's, which reads as
## one body until you drag it and discover there were two.
const MF_LAYER_WINGS     := "Metalfly"
const MF_COCOON_HP       := 2000.0
const MF_COCOON_SPEED    := 120.0   # px/s — much faster than the winged form's 65: the cocoon just rams
const MF_COCOON_PX       := 150.0   # on-screen size of the cocoon body
const MF_COCOON_RPM      := 26.0    # "xoay tròn" — in-plane spin (about the view vertical)
## Second spin axis, so the cocoon TUMBLES instead of only turning like a dial. Deliberately not a multiple
## or divisor of MF_COCOON_RPM: two related rates compose into one fixed axis and the roll disappears again.
const MF_COCOON_TUMBLE_RPM := 17.0
const MF_HATCH_BLAST_PX  := 260.0   # hatch explosion size — bigger than the boss, it has to read as an event

# The body is a live, code-posed 3D rig (MetalflyRig); these constants are only the FIGHT. The two moves:
#   Move 1 "cruise"  — slow wing beat, chases the player, one projectile off EACH wing tip every second.
#   Move 2 "lunge"   — mouth gapes open, wings buzz, a 150px lane is drawn to the player and held for
#                      MF_WINDUP seconds; then the mouth shuts, the wings STOP, and it flies down the lane.
# The lane is locked the instant the wind-up starts, not re-aimed while it charges — that is what makes the
# move dodgeable, and it matches how "steer_charger" above already telegraphs its own dash.
const MF_CRUISE_T       := 6.0     # seconds of Move 1 before Move 2 comes round
const MF_SHOT_INTERVAL  := 1.0     # Move 1: one volley per second...
const MF_SHOT_SPEED     := 240.0   # ...of 2 shards, one from each wing tip, aimed at the player
const MF_SHOT_DMG       := 12
const MF_WINDUP         := 1.5     # Move 2: mouth open + fast flap + lane drawn, before it commits
const MF_LUNGE_SPEED    := 900.0
## Fixed lane length — NOT the distance to the player. The boss flies the whole 1200 px whatever happens, so
## the lunge always overshoots a player who stands still and always ends somewhere the fight has to
## re-close from. A length derived from the current distance (what this was at first) made a point-blank
## wind-up into a twitch and a long-range one into a screen-crossing charge: same move, two different fights.
const MF_LUNGE_LEN      := 1200.0
const MF_RECOVER_T      := 0.9     # vulnerable beat after the lunge before Move 1 resumes
const MF_TURN_WINDUP    := 6.0     # rad/s the boss swings onto the lane while winding up
const MF_TURN_CHASE     := 5.0     # rad/s it turns to face the player in every non-charging state
# ── Move 3: swarm release ────────────────────────────────────────────────────────────────────────────────
# Fast wing beat, then MF_SWARM_COUNT miniature Metalflies burst out in a ring and chase the player. They
# are the SAME model and the same rig, just built at a fraction of the size (see MetalflyRig.setup's
# `display_px`), and their HP is a fraction of the BOSS's own current maximum rather than a flat number —
# so they scale with everything the boss scales with (player level, Beacon, the director's HP_MULT).
const MF_SWARM_ID       := "metalfly_spawn"
const MF_SWARM_WINDUP   := 1.2
const MF_SWARM_COUNT    := 8
const MF_SWARM_RING     := 110.0   # px from the boss the brood appears at
const MF_SWARM_SCALE    := 0.25    # of the boss's body size
const MF_SWARM_HP_FRAC  := 0.05    # of the boss's hp_max

# Fallbacks so the enemy is self-sufficient if configured without a def (e.g. manager.spawn_bomb).
const FALLBACK := {
	"chase": {"behavior": "chase", "hp": 30.0, "speed": 95.0, "size": 16.0, "contact": 6, "xp": 30.0, "shape": "diamond", "tint": Color(0.95, 0.35, 0.30)},
	"bomb":  {"behavior": "bomb",  "hp": 50.0, "speed": 120.0, "size": 18.0, "contact": 0, "explodes": true, "xp": 0, "shape": "circle", "tint": Color(0.9, 0.5, 0.2), "no_collide": true},
	"thrown_bomb": {"behavior": "thrown_bomb", "hp": 12.0, "speed": THROWN_BOMB_SPEED, "size": 13.0, "contact": 0, "explodes": true, "xp": 0, "shape": "circle", "tint": Color(1.0, 0.55, 0.2), "icon": "res://assets/map/electric/enemies/bomb.png", "no_collide": true},
}

# ── Layout config cache ───────────────────────────────────────────────────────
# creep_layout.cfg is 50+ KB / 500+ entries and was loaded+parsed FRESH FROM DISK on every enemy spawn
# (draw size, firepoints, vortexpoints, tentacles) — a multi-ms stall that fired on every spawn-and-die at
# the ring. Parse each layout config ONCE and share it. The creep/plume editors call reload_layout_cfgs()
# after saving so live edits still apply.
static var _creep_cfg: ConfigFile = null
static var _creep_cfg_tried: bool = false
static var _plume_cfg: ConfigFile = null
static var _plume_cfg_tried: bool = false

static func _creep_layout() -> ConfigFile:
	if not _creep_cfg_tried:
		_creep_cfg_tried = true
		var c := ConfigFile.new()
		_creep_cfg = c if c.load("res://creep_layout.cfg") == OK else null
	return _creep_cfg

## Public: the on-screen sprite WIDTH (px) a NEW enemy spawned from `def` would resolve to at _load_icon()
## time, mirroring that function's exact precedence — def["draw_w"] if already set, else creep_layout.cfg's
## authored width for its icon, else the _radius-proportional default (ICON_DRAW_SCALE) — WITHOUT actually
## loading the texture. For callers that need a faithful multiple of an enemy type's CURRENT visual size
## (e.g. arena_wave_director_v2.gd's Elite Creep spawner setting its own def["draw_w"] to guarantee the
## sprite — not just the hitbox — actually scales up; creep_layout.cfg's fixed authored size would otherwise
## silently override a plain def["size"] bump, per _load_icon()'s own precedence below).
static func base_draw_width(def: Dictionary) -> float:
	var draw_w := float(def.get("draw_w", 0.0))
	if draw_w > 0.0:
		return draw_w
	var icon := String(def.get("icon", ""))
	if icon != "":
		var raw_name := icon.get_file().get_basename()
		var cname := raw_name.to_lower()
		var eo_cfg := _creep_layout()
		if eo_cfg != null:
			var eo: Dictionary = eo_cfg.get_value("creeps", raw_name, eo_cfg.get_value("creeps", cname, {}))
			var eo_sz: Vector2 = eo.get("size", Vector2.ZERO)
			if eo_sz.x > 0.0:
				return eo_sz.x
	return float(def.get("size", 16.0)) * 1.05 * ICON_DRAW_SCALE

static func _plume_styles_cfg() -> ConfigFile:
	if not _plume_cfg_tried:
		_plume_cfg_tried = true
		var c := ConfigFile.new()
		_plume_cfg = c if c.load("res://plume_styles.cfg") == OK else null
	return _plume_cfg

## Drop the cached layout configs (+ derived per-creep caches) so the next spawn re-reads from disk. Called
## by the in-game creep/plume editors after they save, so live edits take effect without a restart.
static func reload_layout_cfgs() -> void:
	_creep_cfg_tried = false
	_creep_cfg = null
	_plume_cfg_tried = false
	_plume_cfg = null
	_fp_fracs_cache.clear()
	_tp_fracs_cache.clear()

# ── Fire-point positions (loaded from creep_layout.cfg [firepoints]) ─────────
static var _fp_fracs_cache: Dictionary = {}
var _fp_fracs: Array = []   # Array[{frac:Vector2, dir_angle:float, id:int}]

# ── Thrust-point plume VFX ────────────────────────────────────────────────────
static var _tp_fracs_cache: Dictionary = {}
var _plumes: Array[CPUParticles2D] = []
var _vortexes: Array = []   # EnergyVortex children (creep_layout.cfg [vortexpoints] + plume_styles.cfg [vortex_styles])
var _leds: Array = []       # LedLight children (creep_layout.cfg [ledpoints] + plume_styles.cfg [led_styles])
var _plume_vrot_applied: float = 0.0   # last rotation pushed to plume emitters; skip the re-rotate when unchanged
var _plume_vrot_init: bool = false
const LOD_MARGIN := 180.0   # grow the camera-visible rect by this before the off-screen LOD test (sprite/plume slack)
const LOD_STAGGER_N := 4   # off-screen enemies only run the full behavior tick + separation 1-in-N ticks
						   # (round-robin by instance_id) — they still move every tick they're on-turn, just less
						   # often while nobody's watching; movement fully resumes at every-tick once on-screen.
const PLUME_LOD_COUNT := 150   # above this many live enemies, stop plume emission (the jets are an indistinct blur
							   # in a melee that dense, so dropping the CPUParticles2D sim is ~free visually)
var _lod_visible: bool = true   # tracks whether this enemy's plumes are currently ON (on-screen AND not overcrowded)
var _plume_base: Array = []        # [{vel_min, vel_max, sc_min, sc_max, life}] per plume
var _plume_base_cols: Array = []   # [PackedColorArray] per plume
var _plume_red_cols: Array = []    # pre-built red gradient (dragonfly proximity)
var _plume_in_red: bool = false
var _plume_body_scale: float = 1.0 # _draw_size.x / creep_layout's authored size — same ratio _setup_vortexes()
									# uses, so Elite/Champion (2x/3x draw_w) get proportionally bigger thrust jets
									# instead of a normal-size flame anchored onto a much bigger body.

var _type: String = "chase"
var behavior: String = "chase"
var hp_max: float = 30.0
var hp: float = 30.0
var armor: float = 0.0
var speed: float = 95.0
var _radius: float = 16.0
var hit_radius: float:
	get: return _radius
var contact_damage: int = 6
var contact_explodes: bool = false
var _ship_contact_cd: float = 0.0   # throttles the ship's own contact damage to this enemy (Orbital pool)
var xp: float = 5.0
var _color: Color = Color(0.95, 0.35, 0.30)
var shape_kind: String = "diamond"
var _icon: String = ""
var _original_icon: String = ""
var _no_collide: bool = false
var _invincible: bool = false   # test dummy: blocks the beam (group "arena_enemy") but ignores all damage
var _tex: Texture2D = null
var _frames: Array = []
var _delays: Array = []
var _anim_acc: float = 0.0
var _anim_frame: int = 0
var _draw_size: Vector2 = Vector2.ZERO

# ── 2-frame wing flap (optional, def "flap_icons": ["file1", "file2"]) — same folder as "icon", which
# stays pointed at the ORIGINAL filename so creep_layout/thrustpoints/plume_styles lookups (keyed by that
# icon's basename) keep working unchanged; only the drawn texture alternates between the flap frames.
const FLAP_FRAME_TIME := 0.07   # seconds per frame (~14fps alternation)
var _flap_icons: Array = []

# ── Tracking eye (optional, def "eye"): a separate sprite that slides within a socket toward the player ──
const EYE_TRACK_SPEED := 9.0        # how fast the eye eases toward its player-tracking target
var _has_eye: bool = false
var _eye_icon: String = ""
var _eye_tex: Texture2D = null
var _eye_socket: Vector2 = Vector2(0.5, 0.5)   # socket center, fraction of draw rect (0..1)
var _eye_range: Vector2 = Vector2.ZERO         # max eye displacement, fraction of draw size
var _eye_size_frac: Vector2 = Vector2.ZERO     # eye sprite size, fraction of draw size
var _eye_off: Vector2 = Vector2.ZERO           # current eye offset (local px from socket center, smoothed)

# ── Tentacles (active undulation; the chain root is rigidly anchored to the body) ──
# The child creeps (parent == this body's creep name, e.g. squid-1 … squid-8) define ONE template:
# an ordered chain of segment sprites with rest angles & gaps. Each [tentaclepoints] entry in
# creep_layout.cfg then spawns an INSTANCE of that template at the point's body-relative position, rotated
# by the point's Dir vector — so the squid can have many tentacles fanning out. If no tentacle points are
# defined, one instance is placed at the template's own native position (backward compatible).
# Each instance: root pinned to the body; the rest placed by forward kinematics = rest angle + traveling
# sine wave (always undulates like a swimming limb) + a lag trailing behind the body's motion.
const TENT_WAVE_FREQ := 5.0     # rad/s — temporal speed of the undulation
const TENT_WAVE_K    := 1.3     # phase shift per segment → the wave travels root → tip (S-curve)
const TENT_WAVE_AMP  := 0.42    # rad — per-joint sway amplitude
const TENT_DRAG_GAIN := 0.55    # how strongly a tentacle trails behind body motion
const TENT_DRAG_REF  := 140.0   # body speed (px/s) at which trailing drag reaches full strength
var _tent_template: Array = []  # root→tip: [{tex:Texture2D, size:Vector2, gap:float, rest_ang:float}]
var _tents:         Array = []  # instances: [{base_off:Vector2, dir:float, phase:float, pts:Array}]
var _tent_init:     bool    = false
var _tent_phase:    float   = 0.0           # advancing wave clock shared by all instances
var _tent_prev_pos: Vector2 = Vector2.ZERO  # body position last frame (for velocity-driven drag)
var _tent_vel:      Vector2 = Vector2.ZERO  # smoothed body velocity
var _tent_front_ang: float  = 0.0           # local angle of the tentacle side (squid aims this at the player)
var _tent_attach:    float  = 0.0           # 0→1 wrap blend: how much the tentacles curl around the ship

# ── Squid behaviour: chase led by the tentacles, then cling to the ship & slow it (no contact damage) ──
const SQUID_ATTACH_RANGE := 28.0   # tentacle reach beyond the body radius at which the squid latches on
const SQUID_WRAP_Z       := 101    # while clinging the squid draws ABOVE the ship (SHIP_Z = 100) so tentacles wrap over it
const SQUID_BASE_Z       := 1      # normal enemy draw layer (restored on detach)
var _squid_attached:   bool    = false
var _squid_attach_off: Vector2 = Vector2.ZERO   # held offset from the player while clinging

var _mgr: Node = null
var _target: Node2D = null
var _flash: float = 0.0
var _flash_mat: ShaderMaterial = null   # attached ONLY while flashing; otherwise material stays null (default pipeline)
var _dead: bool = false
# behavior state
var _t: float = 0.0
var _phase: int = 0
var _timer: float = 0.0
var _fire_t: float = 0.0
var _aim: Vector2 = Vector2.ZERO
var _spin: float = 0.0
# ── Centipede chain (Viper-ported; generalized 2026-08-13 to any "centipede"-behavior def, not just the
# original electric one — see CENTI_HEAD_ICON_DEFAULT/etc. below and _load_centipede()) ──
var _centi_pts: Array = []          # head-first world positions (Vector2), one per segment
var _centi_dir: float = 0.0         # head heading (rad)
var _centi_init: bool = false
var _centi_head_tex: Texture2D = null
var _centi_body_texs: Array[Texture2D] = []   # 1+ textures for the MIDDLE segments, indexed by _centi_tex_for()
var _centi_tail_tex: Texture2D = null
var _centi_width: float = 0.0       # rough across-width, kept only for _check_contact()'s hit radius — see _load_centipede()
# 2026-08-14 — per-part AUTHORED size (creep_layout.cfg's "size" for "<name> head"/"<name> body<N>"/
# "<name> tail", i.e. the exact box the user resizes in Creep Edit), one per texture. Base (untapered) draw
# size at spawn now comes from HERE instead of a shared _centi_width×native-aspect guess, so the arena spawn
# is pixel-identical to Creep Edit's own CHAIN preview — see _centi_seg_size_for()/user request "tôi muốn edit
# như thế nào thì spawn ra sẽ y hệt như thế".
var _centi_head_size: Vector2 = Vector2.ZERO
var _centi_body_sizes: Array[Vector2] = []    # parallel to _centi_body_texs
var _centi_tail_size: Vector2 = Vector2.ZERO
# ── Chain tuning (Creep Edit "CHAIN" section, res://creep_chain_overrides.cfg — see creep_edit_mode.gd) ──
# Per-def overridable copies of the CENTI_* defaults above; read from ENEMY_DEFS in configure(), consumed by
# _load_centipede()/_update_centipede_chain(). Any future multi-node/chain enemy reuses the SAME 4 fields.
var _centi_segments: int = CENTI_SEGMENTS_DEFAULT       # "centi_segments" — number of body nodes (head+body+tail)
var _centi_max_bend: float = CENTI_MAX_BEND_DEFAULT     # "centi_bend_deg" (deg in the def) — joint rotation lock
var _centi_spacing_mult: float = 1.0                    # "centi_spacing_mult" — offset/gap between nodes, 1.0 = touching
var _centi_taper_pct: float = 0.0                       # "centi_taper_pct" (0-100) — per-node progressive shrink toward the tail, see _centi_seg_scale()
# ── Chain sprite paths (2026-08-13) — "centi_head_icon"/"centi_body_icons"(Array)/"centi_tail_icon" in the
# def; default to the original electric centipede's 3 files so the "centipede" entry itself needs no changes.
var _centi_head_icon: String = CENTI_HEAD_ICON_DEFAULT
var _centi_body_icons: Array = [CENTI_BODY_ICON_DEFAULT]
var _centi_tail_icon: String = CENTI_TAIL_ICON_DEFAULT
var _tele_anchor: Vector2 = Vector2.ZERO   # teleport: idle-jigger anchor (last landing spot)
# ── Metalfly boss ("boss_move": "metalfly") — see the MF_* constants and _tick_metalfly() ──
var _boss_move: String = ""            # def "boss_move": a named moveset layered ON TOP of behavior "boss_stub"
var _mf_phase: int = 1                 # 1 = cocoon prologue, 2 = winged boss with the moveset
var _mf_cocoon: Node2D = null          # phase-1 body (GlbSpinBody on Cocoon.glb); freed when it hatches
var _mf_p2_hp: float = 0.0             # the def's own (fully multiplied) hp_max, held back for phase 2
var _mf_p2_speed: float = 0.0          # ...and its speed, likewise
var _mf_rig: Node2D = null             # live 3D body (MetalflyRig); null → the flat sprite still draws
var _mf_path: Node2D = null            # Move 2 lane telegraph (MetalflyChargePath)
var _mf_ring: Node2D = null            # Move 3 gathering ring (MetalflySwarmRing) — a CHILD, unlike the lane
var _mf_state: int = 0                 # 0 cruise, 1 lunge wind-up, 2 lunge, 3 recover, 4 swarm wind-up
var _mf_t: float = 0.0                 # seconds in the current state
var _mf_shot_t: float = 0.0            # Move 1 volley timer
var _mf_dir: Vector2 = Vector2.RIGHT   # Move 2: lane direction — TRACKS the player until the lunge starts
var _mf_travelled: float = 0.0         # Move 2: how far down the lane it has flown
var _mf_use_swarm: bool = false        # which special comes after this cruise — they alternate
# ── A live 3D body on a PLAIN enemy (def "body_rig") — the miniatures Move 3 releases ──
var _body_rig: String = ""             # "" = none; "metalfly" = MetalflyRig, no moveset attached
var _body_px: float = 0.0              # its on-screen footprint diagonal
# ── Per-def special modifiers (enemies.pdf "Move" column) ──
var _sprite_alpha: float = 1.0      # ghost: <1 → permanently see-through
var _evade_chance: float = 0.0      # ghost: chance to dodge a hit entirely once hp ≤ _evade_below × max
var _evade_below:  float = 0.0
var _flee_speed:   float = 0.0      # pirate: flee away from the player at this speed once hp ≤ _flee_below × max
var _flee_below:   float = 0.0
var _flank_bias:   float = 0.0      # per-enemy perpendicular seek bias (envelop/arc steering; 0 for bosses)
var _vortex_sign:  float = 1.0      # "steer_chaser" (flies): per-enemy swirl direction, CW or CCW (set in _init_behavior)
var _death_spawn:  String = ""      # stone: spawn this enemy id at our position on death (stoneN → magmaN)
var _morph_to:     String = ""      # alien5: become this enemy id after _morph_after seconds alive
var _morph_after:  float = 0.0
var _strike_back:  bool = false     # fleet/sentinel: switch patrol→chase the first time it's hit
var _is_elite:     bool = false     # elite (spawn_mode_2's periodic Elite/Champion Creep — arena_wave_director_v2.gd): bypasses the alive-cap; reward on death depends on _is_champion below (see _die())
var _is_champion:  bool = false     # Champion tier only (also carries _is_elite=true for the cap-bypass) — on death, grants a guaranteed-new weapon/aux (or a fragment if every run-slot is full) instead of Elite's flat coin — see _die()
var _is_final_boss: bool = false    # set externally by arena_wave_director_v2.gd's _tick_final_boss() right after spawning a timeline's designated final boss — on death, fires GameManager.final_boss_defeated (see _die())
var _knockback_mult: float = 1.0    # take_damage()'s knockback scale — defaults to 0.0 (full immunity) for any "elite" def unless the def explicitly sets "knockback_mult" itself (e.g. arena_wave_director_v2.gd's Elite Creep: 0.5)
var _no_downscale: bool = false     # _load_icon() loads the full HD sprite, skipping the pre-baked-downscale substitution — for anything drawn much bigger than its normal size (e.g. Elite Creep's 300%), where the downscale bake would visibly blur once stretched up
var _magma_split:  bool = false     # LARGE magma: on death, burst into MAGMA_SPLIT_N small magma (which don't re-split)
var _anti_magnetic: bool = false    # bismuth: reflects 50% of gatling bullets; takes 50% from laser/arc/void
var _gauss_shooter: bool = false    # pros5: fire a gauss orb at the player every GAUSS_SHOOT_INTERVAL
var _gauss_t:      float = 0.0
# ── Mothership carrier state (behavior == "mothership") + docked-escort flag ──
var _docked: bool = false           # rigidly docked in a carrier: no move, no plume, no collision (vortex stays)
var _dock_kind: String = ""         # "mothership" | "fleet" — which carrier system docked this escort (see set_docked() callers); mothership escorts keep the original exact-snap/no-knockback behavior, fleet escorts get real per-unit knockback + a catch-up boost back to their slot (see take_damage() and _fleet_update_dock_positions())
var _force_draw_w: float = 0.0      # >0 → override sprite draw width (world px), set by the carrier deploy
var _ms_state: int = MS_READY
var _ms_timer: float = 0.0
var _ms_release_idx: int = 0
var _ms_respawn_idx: int = 0
var _ms_dock: Array = []            # active docked escorts: [{node, base_off:Vector2, rot:float(rad)}]
var _ms_roster: Array = []          # escort spec for respawn: [{id, base_off, draw_w, rot(deg)}]
var _ms_respawn_bays: Array = []    # roster reordered by MS_RESPAWN_ORDER for the current rebuild
# ── Generic Fleet Edit formation carrier state (any behavior — not just "mothership") ──
var _fleet_dock: Array = []         # active docked fleet escorts: [{node, base_off:Vector2}] — see init_fleet_dock()
var _orbit_r: float = 180.0
var _orbit_r0: float = 180.0   # "orbit"/"spiral" (dragonfly/diver): _orbit_r AT SPAWN — used to scale the
								# tighten rate so time-to-dive stays roughly constant regardless of spawn
								# distance (see ORBIT_SPAWN_REF_R's comment)
var _orbit_ang: float = 0.0
var _spiral_dir: float = 1.0   # spin direction (±1) for the spiral approach
var _scatter_target: Vector2 = Vector2.ZERO
var _init_done: bool = false
var _beam_on: bool = false
var _beam_dir: Vector2 = Vector2.RIGHT
var _beam_origin: Vector2 = Vector2.ZERO   # local-space offset to muzzle (for draw + hit-test)
var _laser_beam: Node2D = null             # beamer's LaserBeamScript instance — world-space child of get_parent(), NOT self (see _ready()'s "beamer" setup for why)
var _burst_shots: int = 0   # shooter burst: bullets remaining in current burst
var _burst_t: float = 0.0   # shooter burst: countdown to next shot
var _missile_volley: Node = null   # missile: in-flight plasma volley (self-frees when done)

# ── Composed Move/Shoot (Creep Info panel overrides) ──────────────────────────────────────────────
# Orthogonal to the classic `behavior` match above: when configure() finds explicit "move"/"shoot" fields
# in the def (written by the Creep Info dev panel, res://creep_info_overrides.cfg), _composed short-circuits
# BOTH _init_behavior() and _tick_behavior() straight to _init_composed()/_tick_move_logic()+
# _tick_shoot_logic() below, running the chosen move-logic and shoot-logic independently every tick — the
# original `behavior` string is never read for these units. Untouched units (no override) have "" for both
# fields → _composed stays false → zero change from before this feature existed.
var _composed:    bool   = false
var _move_logic:  String = ""
var _shoot_logic: String = "none"
var _cm_timer:  float   = 0.0        # move-logic's own interval clock (teleport blink, roam retarget) — kept
									  # separate from `_timer` (used by the classic match) and from the
									  # shoot-logic's own clocks below, since composed mode runs a move-logic
									  # AND a shoot-logic concurrently (the classic system only ever ran one).
var _cm_target: Vector2 = Vector2.ZERO   # move-logic "roam": current wander target
var _cm_orbit_r: float  = 180.0          # move-logic "orbit"/"spiral": current radius
var _cm_orbit_a: float  = 0.0            # move-logic "orbit"/"spiral": current angle
var _cs_burst_shots: int   = 0       # shoot-logic "burst": bullets remaining in the current burst
var _cs_burst_t:     float = 0.0     # shoot-logic "burst": countdown to next shot in the burst
var _sfx: AudioStreamPlayer = null  # lazily-created one-shot SFX player (jump / fire / beam)
var sfx_bus: String = "SFX"          # audio bus for this enemy's sounds (menu reroutes to a "distant" bus)
var menu_confine_fx: bool = false   # true = decorative Main Menu backdrop (see menu_enemy_spawner.gd):
	# fullscreen screen-read FX (warp) must not bleed over the Logo/buttons — see _spawn_warp().
var _jump_interval: float = 1.0   # jump_diag (spider): randomized per jump (±0.5 s)
# "alive" motion state
var _facing: float = 0.0
var _idle_spin: float = 0.0   # rad/s in-place sprite spin for stationary props (dead-ship wrecks); 0 = off
var _drop_loot: String = ""   # loot type dropped on death via _mgr.spawn_loot (e.g. "orb_of_light"); "" = none
var _prev_pos: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0
var _bob_freq: float = 3.0
var _scale_var: float = 1.0
var _squash: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _hit_shake: Vector2 = Vector2.ZERO   # visual-only hit reaction for docked/carrier units — see HIT_SHAKE_MAG
var velocity: Vector2 = Vector2.ZERO   # was CharacterBody2D.velocity; now integrated manually in _move_step
var _separates: bool = false           # participates in the manager's spatial-hash separation (false = no_collide/dying/docked)
var _spawn_t: float = 0.0
var _dying: bool = false
var _death_t: float = 0.0
var _stagger_t: float = 0.0   # while > 0, movement/attacks are frozen (per-weapon hit stagger)
# ── Status effects (burn / freeze) — applied by weapons via apply_burn() / apply_freeze() ──
const BURN_DURATION    := 5.0    # s a burn lasts (refreshed on each new stack)
const BURN_TICK        := 1.0    # s between burn DoT ticks
const BURN_PCT         := 0.001  # current-HP fraction lost per second PER stack (0.1%)
const FREEZE_DURATION  := 3.0    # s a freeze lasts before stacks decay (refreshed on apply)
const FREEZE_SLOW_PER  := 0.15   # movement slow per freeze stack
const FREEZE_MAX       := 0.90   # max slow (normal enemies) → 6 stacks
const FREEZE_MAX_BOSS  := 0.30   # max slow (bosses) → 2 stacks
const STUN_DMG_MULT    := 1.5    # +50% damage taken while stunned
const STUN_IMMUNE      := 0.5    # immunity after a stun (normal enemies)
const STUN_IMMUNE_BOSS := 3.0    # immunity after a stun (bosses)
var _burn_stacks: int = 0
var _burn_t: float = 0.0
var _burn_acc: float = 0.0
var _freeze_stacks: int = 0
var _freeze_t: float = 0.0
var _move_slow: float = 0.0    # current freeze slow (0..cap); scales `speed` each frame
var _base_speed: float = -1.0  # captured configured speed (so freeze slow is non-destructive)
var _stun_t: float = 0.0       # remaining stun time (movement/attacks frozen, +50% damage taken)
var _stun_immune_t: float = 0.0  # immunity window after a stun (can't be re-stunned)
var _stun_immune_mult: float = 1.0   # Dazzling Display capstone shortens immunity (set via set_stun_immune_mult)
var _weaken_t: float = 0.0    # Pacifying Jolt: while > 0, this enemy's damage output is halved
var _vuln_t: float = 0.0      # Orb of Annihilation: while > 0, this enemy takes +20% damage from all sources
var _sed_t: float = 0.0       # Sedative Scent (Chemtrail): while > 0, enemy is slowed + deals less damage
var _sed_dmg: float = 0.0     # sedative outgoing-damage reduction (0..)
var _sed_slow: float = 0.0    # sedative move-speed reduction (0..)
var _armor_reduce: float = 0.0  # Critical Break (Drill Bits): temporary armor stripped off this enemy
var _armor_reduce_t: float = 0.0
var _corrode_reduce: float = 0.0  # Metal Eater (Parasite): armor corroded off, capped, separate from Critical Break
var _corrode_t: float = 0.0
var _wiper_t: float = 0.0     # Windshield Wiper (Z-Sword): brief 99%→0% slow over 0.2s
var _charm_t: float = 0.0     # Siren (Sonic): while > 0 this enemy fights for the player (targets other enemies)
var _aggro_target: Node = null  # who this enemy is chasing/attacking this frame (player, or a charmed enemy, or — if charmed — a foe)
var _bleed_stacks: int = 0   # Drill Bits bleed: 1 dmg/stack/s for 5s, IGNORES armor
var _bleed_t: float = 0.0
var _bleed_acc: float = 0.0
const BLEED_TICK := 1.0
const BLEED_DURATION := 5.0
const BLEED_MAX_BASE := 50
var _swarm_mode: String = "chase"   # swarm blob unit: "zoom" (fly through @400) or "chase" (slow @speed)
var _flash_color: Color = HIT_FLASH_COLOR

## Configure from the director's enemy table (or a fallback). Call before add_child.
func configure(type_id: String, mgr: Node, def: Dictionary = {}) -> void:
	_type = type_id
	_mgr = mgr
	var d: Dictionary = def if not def.is_empty() else FALLBACK.get(type_id, FALLBACK["chase"])
	behavior         = String(d.get("behavior", "chase"))
	_swarm_mode      = String(d.get("swarm_mode", "chase"))
	# Creep Info panel override (res://creep_info_overrides.cfg, merged into ENEMY_DEFS at director _ready())
	# — the def having a "move" or "shoot" KEY AT ALL switches this unit onto the composed system, bypassing
	# `behavior` entirely. Gated on d.has(...), NOT on the resolved value being non-default: an explicit
	# "shoot": "none" override (Creep Info's Shoot dropdown — force this unit to never fire, even if its
	# classic `behavior` normally does) must still count as composed, even though "none" is also literally
	# _shoot_logic's own no-override fallback value.
	_move_logic      = String(d.get("move", ""))
	_shoot_logic     = String(d.get("shoot", "none"))
	_composed        = d.has("move") or d.has("shoot")
	# "lvl": true → HP & XP in the def are PER-PLAYER-LEVEL bases (the table's "15*"); multiply by the
	# player's level snapshotted at spawn. Other stats (speed/size/contact/armor) are flat.
	var lvl_mult: int = GameManager.player_level if bool(d.get("lvl", false)) else 1
	var beacon_hp := (1.0 + GameManager.mech_bonus("enemy_hp_mult")) if GameManager.has_method("mech_bonus") else 1.0   # Beacon
	var tune_hp := 1.0 if behavior == "boss_stub" else ENEMY_HP_TUNE   # ×2 HP for every non-boss enemy
	hp_max           = float(d.get("hp", 30.0)) * float(lvl_mult) * beacon_hp * tune_hp
	hp               = hp_max
	armor            = float(d.get("armor", 0.0))
	var tune_spd := 1.0 if behavior == "boss_stub" else ENEMY_SPEED_TUNE   # non-boss chase speed ×tune
	speed            = float(d.get("speed", 95.0)) * tune_spd
	# Per-enemy flank bias so the crowd envelops instead of trailing (bosses steer straight).
	_flank_bias      = 0.0 if behavior == "boss_stub" else randf_range(-FLANK_BIAS_MAX, FLANK_BIAS_MAX)
	_radius          = float(d.get("size", 16.0)) * SIZE_TO_RADIUS
	contact_damage   = int(d.get("contact", 6))
	contact_explodes = bool(d.get("explodes", false))
	xp               = float(d.get("xp", 5)) * float(lvl_mult) * ENEMY_XP_TUNE   # ×2 XP value (all enemies)
	_color           = d.get("tint", Color(0.95, 0.35, 0.30))
	shape_kind       = String(d.get("shape", "diamond"))
	_original_icon   = String(d.get("icon", ""))
	_icon            = _original_icon
	if simplified_mode and _icon.begins_with("res://assets/enemies/"):
		var s_path: String = "res://assets/enemies/simplified/" + _icon.get_file()
		if FileAccess.file_exists(s_path):
			_icon = s_path
	_no_collide      = bool(d.get("no_collide", false))
	_invincible      = bool(d.get("invincible", false))
	_sprite_alpha    = float(d.get("sprite_alpha", 1.0))
	_evade_chance    = float(d.get("evade_chance", 0.0))
	_evade_below     = float(d.get("evade_below", 0.0))
	_flee_speed      = float(d.get("flee_speed", 0.0))
	_flee_below      = float(d.get("flee_below", 0.0))
	_death_spawn     = String(d.get("death_spawn", ""))
	_drop_loot       = String(d.get("drop_loot", ""))
	_morph_to        = String(d.get("morph_to", ""))
	_morph_after     = float(d.get("morph_after", 0.0))
	_strike_back     = bool(d.get("strike_back", false))
	_is_elite        = bool(d.get("elite", false))
	_is_champion     = bool(d.get("champion", false))
	_knockback_mult  = float(d.get("knockback_mult", 0.0 if _is_elite else 1.0))
	_magma_split     = bool(d.get("magma_split", false))
	_anti_magnetic   = bool(d.get("anti_magnetic", false))
	_gauss_shooter   = bool(d.get("gauss_shooter", false))
	_boss_move       = String(d.get("boss_move", ""))   # named boss moveset (metalfly); "" = plain boss_stub chase
	_body_rig        = String(d.get("body_rig", ""))    # live 3D body on an ordinary enemy — no moveset implied
	_body_px         = float(d.get("body_px", 0.0))
	if _boss_move == "metalfly":
		# Hold the def's hp/speed back for Phase 2 and drop in the cocoon's own, so the boss ARRIVES as the
		# cocoon. Captured here rather than re-read from the def later because these values already carry
		# every multiplier configure() applied above (player level, Beacon, the director's HP_MULT) —
		# re-deriving them at hatch time would silently drop all of that.
		_mf_p2_hp    = hp_max
		_mf_p2_speed = speed
		hp_max = MF_COCOON_HP
		hp     = hp_max
		speed  = MF_COCOON_SPEED
	_idle_spin       = deg_to_rad(float(d.get("idle_spin", 0.0)))   # deg/s in the def -> rad/s stored
	_flap_icons      = d.get("flap_icons", [])   # 2+ filenames (same folder as "icon") to alternate — wing-flap effect
	_no_downscale    = bool(d.get("no_downscale", false))
	_force_draw_w    = float(d.get("draw_w", 0.0))
	# Chain tuning (centipede-type only; harmless no-op for every other behavior) — see the CENTI_* fields' own comment.
	_centi_segments      = int(d.get("centi_segments", CENTI_SEGMENTS_DEFAULT))
	_centi_max_bend      = deg_to_rad(float(d.get("centi_bend_deg", rad_to_deg(CENTI_MAX_BEND_DEFAULT))))
	_centi_spacing_mult  = float(d.get("centi_spacing_mult", 1.0))
	_centi_taper_pct     = clampf(float(d.get("centi_taper_pct", 0.0)), 0.0, 100.0)
	_centi_head_icon     = String(d.get("centi_head_icon", CENTI_HEAD_ICON_DEFAULT))
	var body_icons_raw: Array = d.get("centi_body_icons", [CENTI_BODY_ICON_DEFAULT])
	_centi_body_icons    = body_icons_raw if not body_icons_raw.is_empty() else [CENTI_BODY_ICON_DEFAULT]
	_centi_tail_icon     = String(d.get("centi_tail_icon", CENTI_TAIL_ICON_DEFAULT))
	if _force_draw_w > 0.0:
		_radius = _force_draw_w * 0.42   # hit radius scales with the authored (carrier-honored) draw size
	var eye_cfg: Dictionary = d.get("eye", {})
	if not eye_cfg.is_empty():
		_has_eye       = true
		_eye_icon      = String(eye_cfg.get("icon", ""))
		_eye_socket    = eye_cfg.get("socket", Vector2(0.5, 0.5))
		_eye_range     = eye_cfg.get("range", Vector2.ZERO)
		_eye_size_frac = eye_cfg.get("size", Vector2.ZERO)

func _ready() -> void:
	add_to_group("arena_enemy")
	add_to_group("normal_enemy")
	if behavior == "boss_stub":
		add_to_group("boss")   # weapons (e.g. the lasgun) treat bosses as beam-blockers
	# Separation: enemies push each OTHER apart (so they can't overlap) but never the player (contact stays
	# distance-based). This is now done by arena_enemy_manager's spatial-hash pass, not the physics engine —
	# `_separates` opts this enemy in (a CircleShape core of _radius × CORE_FRAC). `no_collide` types opt out.
	_separates = not _no_collide
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_target = get_tree().get_first_node_in_group("player")
	z_index = 1
	# Per-instance flash material (shared compiled shader) — lerps the sprite toward white/red on hit.
	# IMPORTANT: it is NOT assigned as the node's material by default. Under hdr_2d the custom canvas
	# shader's manual TEXTURE sample renders the sprite darker than the engine-default pipeline, so the
	# sprite would look dimmed at all times. We only attach it WHILE flashing (_physics_process), so the
	# normal state uses the default pipeline (full brightness, matching the Creep Edit preview).
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER_CODE
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = _flash_shader
	_load_icon()
	if _boss_move == "metalfly":
		_setup_metalfly()
	elif _body_rig == "metalfly":
		_setup_body_rig()
	if behavior == "centipede":
		_load_centipede()
	_load_tentacle()
	_setup_plumes()
	_setup_vortexes()
	_setup_leds()
	_setup_fire_points()
	if behavior == "beamer":
		_setup_laser_beam()
	# Per-enemy "alive" variation so the crowd reads as individuals, not synced clones.
	_bob_phase = randf() * TAU
	_bob_freq = randf_range(BOB_FREQ_MIN, BOB_FREQ_MAX)
	_scale_var = randf_range(1.0 - SCALE_VAR, 1.0 + SCALE_VAR)
	_prev_pos = global_position

## Prefer a high-res sprite from assets/enemiesHD/; fall back to the standard assets/enemies/ path.
## Only the texture SOURCE changes — draw size still comes from creep_layout.cfg, so the in-game scale/ratio is unchanged.
## `skip_downscale` bypasses the pre-baked-downscale substitution below, returning the full HD source
## instead — for anything drawn meaningfully bigger than creep_layout.cfg's authored size (e.g. an Elite
## Creep at 300%, see arena_wave_director_v2.gd's _spawn_elite_creep/"no_downscale"), where the downscale
## bake (sized for the type's NORMAL on-screen footprint) would visibly blur once stretched up.
static func _resolve_sprite(path: String, skip_downscale: bool = false) -> String:
	const STD := "res://assets/enemies/"
	const HD  := "res://assets/enemiesHD/"
	const DS  := "res://assets/Enemies Downscale/"
	var p := path
	if p.begins_with(STD):
		var hd := HD + p.substr(STD.length())
		if FileAccess.file_exists(hd) or ResourceLoader.exists(hd):
			p = hd
	# Prefer the pre-baked downscaled sprite (tools/downscale_enemies.gd) — a light texture at the real display
	# size. Missing → fall back to the HD source. Skipped for .gif / .sheet.png (no downscaled copy exists).
	if USE_DOWNSCALED_SPRITES and not skip_downscale:
		var ds := DS + p.get_file()
		if ResourceLoader.exists(ds) or FileAccess.file_exists(ds):
			return ds
	return p

## Load the sprite (PNG, animated GIF, or sprite-sheet PNG+JSON) and compute draw size.
func _load_icon() -> void:
	if _icon == "":
		return
	var src := _resolve_sprite(_icon, _no_downscale)   # HD if available, else the standard path
	if _flap_icons.size() >= 2:
		var dir := _icon.get_base_dir() + "/"
		_frames = []
		_delays = []
		for fname in _flap_icons:
			var t := load(_resolve_sprite(dir + String(fname) + ".png", _no_downscale)) as Texture2D   # downscaled copy if baked, else HD
			if t != null:
				_frames.append(t)
				_delays.append(FLAP_FRAME_TIME)
		if not _frames.is_empty():
			_tex = _frames[0] as Texture2D
	elif _icon.ends_with(".gif"):
		var g := GifLoader.load_gif(src)
		if g != null and g.has_meta("gif_frames"):
			_frames = g.get_meta("gif_frames")
			_delays = g.get_meta("gif_delays") if g.has_meta("gif_delays") else []
			_tex = _frames[0] as Texture2D if not _frames.is_empty() else g
		else:
			_tex = g
	elif _icon.ends_with(".sheet.png"):
		_load_sheet_frames(src)
	else:
		_tex = load(src) as Texture2D
		if _tex == null and src != _icon:
			_tex = load(_icon) as Texture2D   # HD failed to load (e.g. not imported) → standard sprite
	if _tex != null:
		var ts := _tex.get_size()
		var w := _radius * ICON_DRAW_SCALE
		var h := w * (ts.y / ts.x) if ts.x > 0.0 else w
		_draw_size = Vector2(w, h)
		var cname := _icon.get_file().get_basename().to_lower()
		var raw_name := _icon.get_file().get_basename()   # editor keeps the file's original case (e.g. "Squid-body")
		var eo_cfg := _creep_layout()
		if eo_cfg != null:
			var eo: Dictionary = eo_cfg.get_value("creeps", raw_name, eo_cfg.get_value("creeps", cname, {}))
			var eo_sz: Vector2 = eo.get("size", Vector2.ZERO)
			if eo_sz.x > 0.0 and eo_sz.y > 0.0:
				_draw_size = eo_sz
				# Self-heal a stale saved aspect (e.g. source art rotated after placement):
				# keep the configured width but lock height to the texture true aspect -> never stretches.
				if ts.x > 0.0:
					_draw_size.y = eo_sz.x * (ts.y / ts.x)
		# Carrier-honored draw width wins over creep_layout so the squadron matches the Fleet Edit layout.
		if _force_draw_w > 0.0 and ts.x > 0.0:
			_draw_size = Vector2(_force_draw_w, _force_draw_w * (ts.y / ts.x))
	if _has_eye and _eye_icon != "" and _eye_tex == null:
		var eye_src := _resolve_sprite(_eye_icon, _no_downscale)
		_eye_tex = load(eye_src) as Texture2D
		if _eye_tex == null and eye_src != _eye_icon:
			_eye_tex = load(_eye_icon) as Texture2D

## Parse <name>.sheet.json alongside the PNG to slice frames into AtlasTexture objects.
## JSON format: { "cols": 1, "w": <px>, "h": <px>, "delays": [<sec>, ...] }
func _load_sheet_frames(path: String) -> void:
	var json_path := path.replace(".sheet.png", ".sheet.json")
	var atlas := load(path) as Texture2D
	if atlas == null:
		return
	var cols := 1
	var fw := atlas.get_width()
	var fh := atlas.get_height()
	var raw_delays: Array = [0.1]
	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		if file != null:
			var data = JSON.parse_string(file.get_as_text())
			file.close()
			if data is Dictionary:
				cols   = int(data.get("cols", 1))
				fw     = int(data.get("w", fw))
				fh     = int(data.get("h", fh))
				raw_delays = data.get("delays", [0.1])
	var rows := atlas.get_height() / fh if fh > 0 else 1
	var count := rows * cols
	_frames.clear()
	_delays.clear()
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)
		_frames.append(at)
		var d: float = float(raw_delays[i]) if i < raw_delays.size() else float(raw_delays[-1])
		_delays.append(d)
	if not _frames.is_empty():
		_tex = _frames[0] as Texture2D

## Swap or revert sprite for simplified mode. Called by arena_hud_buttons after scanning the folder.
## simplified_files: dict of filename → full res:// path for every file found in assets/enemies/simplified/.
func apply_simplified(enabled: bool, simplified_files: Dictionary) -> void:
	if _original_icon == "" or not _original_icon.begins_with("res://assets/enemies/"):
		return
	if enabled:
		var fname: String = _original_icon.get_file()
		if simplified_files.has(fname):
			_reload_icon(simplified_files[fname])
	else:
		_reload_icon(_original_icon)

func _reload_icon(new_path: String) -> void:
	_frames.clear()
	_delays.clear()
	_anim_acc = 0.0
	_anim_frame = 0
	_tex = null
	_draw_size = Vector2.ZERO
	_icon = new_path
	_load_icon()
	queue_redraw()

# ── Thrust-point plume VFX ────────────────────────────────────────────────────
func _setup_plumes() -> void:
	if _icon.is_empty() or _draw_size == Vector2.ZERO:
		return
	var cname := _icon.get_file().get_basename().to_lower()
	# Same ratio _setup_vortexes() computes: config-authored body size vs. this instance's actual _draw_size
	# (already Elite/Champion-scaled by the time this runs — see _load_icon()'s _force_draw_w override,
	# called before _ready()'s _setup_plumes()). 1.0 for a normal-size creep, ~2.0/~3.0 for Elite/Champion.
	var cfg := _creep_layout()
	if cfg != null:
		var eo: Dictionary = cfg.get_value("creeps", _resolve_cfg_key(cfg, "creeps", cname), {})
		var eo_size: Vector2 = eo.get("size", Vector2.ZERO)
		if eo_size.x > 0.0:
			_plume_body_scale = _draw_size.x / eo_size.x
	if not _tp_fracs_cache.has(cname):
		_tp_fracs_cache[cname] = _load_tp_fracs(cname)
	var fracs: Array = _tp_fracs_cache[cname]
	if fracs.is_empty():
		return
	var all_styles := _load_plume_styles_for(cname)
	for i: int in fracs.size():
		var fd: Dictionary = fracs[i]
		var tp_id: int = int(fd.get("id", i + 1))
		var style: Dictionary = all_styles.get("tp_%d" % tp_id, {})
		var p := _make_plume(fd["frac"] as Vector2, float(fd["dir_angle"]), style)
		add_child(p)
		_plumes.append(p)
	var red := PackedColorArray([
		Color(1.0, 0.20, 0.10, 1.0), Color(0.85, 0.05, 0.02, 1.0),
		Color(0.60, 0.00, 0.00, 0.85), Color(0.40, 0.00, 0.00, 0.00),
	])
	for p2: CPUParticles2D in _plumes:
		_plume_base.append({"vel_min": p2.initial_velocity_min, "vel_max": p2.initial_velocity_max,
			"sc_min": p2.scale_amount_min, "sc_max": p2.scale_amount_max, "life": p2.lifetime})
		_plume_base_cols.append(p2.color_ramp.colors.duplicate())
		_plume_red_cols.append(red)

## The editor saves creep_layout / plume_styles keys with the file's ORIGINAL case (e.g. "Pirate1"),
## but lookups use the lowercased icon basename. Resolve the real key case-insensitively so every sprite
## (incl. capitalized / spaced filenames) finds its TPs, fire-points and plume styles.
static func _resolve_cfg_key(cfg: ConfigFile, section: String, cname: String) -> String:
	if not cfg.has_section(section):
		return cname
	if cfg.has_section_key(section, cname):
		return cname
	for k: String in cfg.get_section_keys(section):
		if k.to_lower() == cname:
			return k
	return cname

static func _load_plume_styles_for(cname: String) -> Dictionary:
	var cfg := _plume_styles_cfg()
	if cfg == null:
		return {}
	return cfg.get_value("styles", _resolve_cfg_key(cfg, "styles", cname), {})

static func _load_tp_fracs(cname: String) -> Array:
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	var cfg := _creep_layout()
	if cfg == null:
		return []
	var key := _resolve_cfg_key(cfg, "creeps", cname)
	var eo: Dictionary = cfg.get_value("creeps", key, {})
	if eo.is_empty():
		return []
	var eo_pos: Vector2 = eo.get("pos", Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0, 60.0))
	if eo_size.x <= 0.0 or eo_size.y <= 0.0:
		return []
	var tps: Array = cfg.get_value("thrustpoints", _resolve_cfg_key(cfg, "thrustpoints", cname), [])
	var result: Array = []
	for i: int in tps.size():
		var tp: Dictionary = tps[i]
		var tp_oc: Vector2 = (tp["pos"] as Vector2) + SCREEN_ORIGIN
		var frac := (tp_oc - eo_pos) / eo_size
		result.append({"frac": frac, "dir_angle": float(tp.get("dir_angle", PI * 0.5)), "id": int(tp.get("id", i + 1))})
	return result

## Spawn EnergyVortex VFX children from creep_layout.cfg [vortexpoints] (styled by plume_styles.cfg
## [vortex_styles]). Anchored at the point's body-relative fraction, scaled to the in-game draw size.
func _setup_vortexes() -> void:
	if _icon.is_empty() or _draw_size == Vector2.ZERO:
		return
	var cname := _icon.get_file().get_basename().to_lower()
	var cfg := _creep_layout()
	if cfg == null:
		return
	var key := _resolve_cfg_key(cfg, "creeps", cname)
	var eo: Dictionary = cfg.get_value("creeps", key, {})
	if eo.is_empty():
		return
	var eo_pos: Vector2  = eo.get("pos",  Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0, 60.0))
	if eo_size.x <= 0.0:
		return
	var vxs: Array = cfg.get_value("vortexpoints", _resolve_cfg_key(cfg, "vortexpoints", cname), [])
	if vxs.is_empty():
		return
	var styles := _load_vortex_styles_for(cname)
	var s := _draw_size.x / eo_size.x   # config-space → in-game scale
	const SS_ORIGIN := Vector2(15.0, 8.0)
	for i: int in vxs.size():
		var vx: Dictionary = vxs[i]
		var vx_id: int = int(vx.get("id", i + 1))
		var vx_oc: Vector2 = (vx["pos"] as Vector2) + SS_ORIGIN
		var frac := (vx_oc - eo_pos) / eo_size
		var node: Node2D = EnergyVortex.new()
		node.position = (frac - Vector2(0.5, 0.5)) * _draw_size   # origin is CENTER → shift by -0.5
		node.scale = Vector2(s, s)
		node.z_index = 1
		# Stash the anchor data so _update_vortex_xform() can re-glue the vortex to the (rotating, breathing)
		# sprite each frame — same approach as the plumes.
		node.set_meta("frac_centered", frac - Vector2(0.5, 0.5))
		node.set_meta("base_scale", s)
		add_child(node)
		node.call("setup", styles.get("vx_%d" % vx_id, {}))
		_vortexes.append(node)

static func _load_vortex_styles_for(cname: String) -> Dictionary:
	var cfg := _plume_styles_cfg()
	if cfg == null:
		return {}
	return cfg.get_value("vortex_styles", _resolve_cfg_key(cfg, "vortex_styles", cname), {})

## Spawn LedLight VFX children from creep_layout.cfg [ledpoints] (styled by plume_styles.cfg [led_styles]) —
## same anchoring approach as _setup_vortexes() (body-relative fraction, scaled to the in-game draw size).
## 2026-08-15: centipede-behavior creeps (multiple independently-moving/bending body segments, not one rigid
## sprite box) route to _setup_leds_centipede() instead — see that function's own comment.
func _setup_leds() -> void:
	if behavior == "centipede":
		_setup_leds_centipede()
		return
	if _icon.is_empty() or _draw_size == Vector2.ZERO:
		return
	var cname := _icon.get_file().get_basename().to_lower()
	var cfg := _creep_layout()
	if cfg == null:
		return
	var key := _resolve_cfg_key(cfg, "creeps", cname)
	var eo: Dictionary = cfg.get_value("creeps", key, {})
	if eo.is_empty():
		return
	var eo_pos: Vector2  = eo.get("pos",  Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0, 60.0))
	if eo_size.x <= 0.0:
		return
	var leds: Array = cfg.get_value("ledpoints", _resolve_cfg_key(cfg, "ledpoints", cname), [])
	if leds.is_empty():
		return
	var styles := _load_led_styles_for(cname)
	var s := _draw_size.x / eo_size.x   # config-space → in-game scale
	const SS_ORIGIN := Vector2(15.0, 8.0)
	for i: int in leds.size():
		var led: Dictionary = leds[i]
		var led_id: int = int(led.get("id", i + 1))
		var led_oc: Vector2 = (led["pos"] as Vector2) + SS_ORIGIN
		var frac := (led_oc - eo_pos) / eo_size
		var node: Node2D = LedLight.new()
		node.position = (frac - Vector2(0.5, 0.5)) * _draw_size   # origin is CENTER → shift by -0.5
		node.scale = Vector2(s, s)
		node.z_index = 1
		# Stash the anchor data so _update_led_xform() can re-glue the LED to the (rotating, breathing)
		# sprite each frame — same approach as the vortexes/plumes.
		node.set_meta("frac_centered", frac - Vector2(0.5, 0.5))
		node.set_meta("base_scale", s)
		var style: Dictionary = styles.get("led_%d" % led_id, {})
		node.set_meta("rotate_deg", float(style.get("rotate_deg", 0.0)))
		add_child(node)
		node.call("setup", style)
		_leds.append(node)

## 2026-08-15 bug fix ("cent di chuyển có bend, LED không dính theo node mà vẫn xếp thành 1 hàng dọc"): the
## regular _setup_leds() above anchors every LED against ONE rigid box (`_icon`'s own creeps entry — for a
## centipede-behavior creep that's just the HEAD's box, since `_icon` is always the head icon). A LED actually
## placed near Body or Tail in Creep Edit got a `frac` computed against the HEAD's tiny box instead, producing
## a huge, fixed local offset that only ever rotated rigidly with the head — never with the body chain's own
## live bend — reading as "stays lined up in one straight column" exactly as reported.
##
## Fix: match each LED to whichever REAL template box (Head / each distinct Body icon / Tail) it's actually
## closest to in creep_layout.cfg, remember that as a chain slot `k` (0=head, tail resolves live to n-1 since
## Segments can change), and glue it every frame to THAT segment's own live `_centi_pts[k]` position + own
## angle (_centi_seg_ang(k), the exact formula _draw_centipede() itself draws with) — see _update_led_xform().
## 2026-08-15, 2nd fix ("tôi đặt nhiều segment body nhưng led chỉ tách thành 2 phần"): the first version only
## matched against the 3 REAL named boxes (Head/Body-template/Tail) — every auto-generated DUPLICATE segment
## (Segments > template count) has no box of its own in creep_layout.cfg, so any LED placed on one collapsed
## onto whichever of the 3 real boxes happened to be nearest, instead of its own segment. Fixed by building a
## full virtual center+size for EVERY slot k=0..n-1 — head, EVERY body slot (real template AND duplicate
## alike, via the exact same _centi_joint_spacing()/_centi_seg_size_for()/_centi_seg_scale() formulas the live
## chain itself walks), and tail — mirroring the same cumulative-distance construction
## _update_centipede_chain()'s own straight-line init uses, just scalar (OC-space Y only; X stays pinned to
## Head's own center, matching the proven fact — see the 24th-pass reply's math — that a centered chain never
## drifts in X regardless of taper/spacing). A LED now finds its own nearest slot among ALL of them, not just
## the 3 named ones, so it correctly lands on the specific duplicate segment it was actually placed near.
func _setup_leds_centipede() -> void:
	var cfg := _creep_layout()
	if cfg == null:
		return
	var cname := _icon.get_file().get_basename().to_lower()
	var leds: Array = cfg.get_value("ledpoints", _resolve_cfg_key(cfg, "ledpoints", cname), [])
	if leds.is_empty():
		return
	var head_eo := _creep_layout_entry(cfg, _centi_head_icon)
	if head_eo.is_empty():
		return
	var head_pos: Vector2 = head_eo.get("pos", Vector2.ZERO)
	var head_size: Vector2 = head_eo.get("size", Vector2(60.0, 60.0))
	var head_center := head_pos + head_size * 0.5
	var n := _centi_segments
	if n < 1:
		return
	var k_centers: Array[Vector2] = [head_center]
	var k_sizes: Array[Vector2] = [head_size]
	var cum := 0.0
	for k in range(1, n - 1):   # every body slot, real template or duplicate alike
		cum += _centi_joint_spacing(k, n)
		k_centers.append(Vector2(head_center.x, head_center.y + cum))
		k_sizes.append(_centi_seg_size_for(k, n) * _centi_seg_scale(k, n))
	var tail_eo := _creep_layout_entry(cfg, _centi_tail_icon)
	if not tail_eo.is_empty():
		var tail_pos: Vector2 = tail_eo.get("pos", Vector2.ZERO)
		var tail_size: Vector2 = tail_eo.get("size", Vector2(60.0, 60.0))
		k_centers.append(tail_pos + tail_size * 0.5)
		k_sizes.append(tail_size)
	else:
		# No real Tail entry at all (unusual) — fall back to extending the body cumulative one more step.
		cum += _centi_joint_spacing(n - 1, n)
		k_centers.append(Vector2(head_center.x, head_center.y + cum))
		k_sizes.append(_centi_tail_size if _centi_tail_size != Vector2.ZERO else head_size)
	var styles := _load_led_styles_for(cname)
	const SS_ORIGIN := Vector2(15.0, 8.0)
	for i: int in leds.size():
		var led: Dictionary = leds[i]
		var led_id: int = int(led.get("id", i + 1))
		var led_oc: Vector2 = (led["pos"] as Vector2) + SS_ORIGIN
		var best_k := 0
		var best_d := INF
		for k in k_centers.size():
			var d := led_oc.distance_squared_to(k_centers[k])
			if d < best_d:
				best_d = d
				best_k = k
		var seg_size: Vector2 = k_sizes[best_k]
		if seg_size.x <= 0.0 or seg_size.y <= 0.0:
			continue
		var frac := (led_oc - k_centers[best_k]) / seg_size
		var node: Node2D = LedLight.new()
		node.z_index = 1
		node.set_meta("centi_k", best_k)
		node.set_meta("frac_centered", frac)
		var style: Dictionary = styles.get("led_%d" % led_id, {})
		node.set_meta("rotate_deg", float(style.get("rotate_deg", 0.0)))
		add_child(node)
		node.call("setup", style)
		_leds.append(node)

static func _load_led_styles_for(cname: String) -> Dictionary:
	var cfg := _plume_styles_cfg()
	if cfg == null:
		return {}
	return cfg.get_value("led_styles", _resolve_cfg_key(cfg, "led_styles", cname), {})

func _setup_fire_points() -> void:
	if _icon.is_empty() or _draw_size == Vector2.ZERO:
		return
	var cname := _icon.get_file().get_basename().to_lower()
	if not _fp_fracs_cache.has(cname):
		_fp_fracs_cache[cname] = _load_fp_fracs(cname)
	_fp_fracs = _fp_fracs_cache[cname]

static func _load_fp_fracs(cname: String) -> Array:
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	var cfg := _creep_layout()
	if cfg == null:
		return []
	var key := _resolve_cfg_key(cfg, "creeps", cname)
	var eo: Dictionary = cfg.get_value("creeps", key, {})
	if eo.is_empty():
		return []
	var eo_pos: Vector2  = eo.get("pos",  Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0,  60.0))
	if eo_size.x <= 0.0 or eo_size.y <= 0.0:
		return []
	var fps: Array = cfg.get_value("firepoints", _resolve_cfg_key(cfg, "firepoints", cname), [])
	var result: Array = []
	for i: int in fps.size():
		var fp: Dictionary = fps[i]
		var fp_oc: Vector2 = (fp["pos"] as Vector2) + SCREEN_ORIGIN
		var frac := (fp_oc - eo_pos) / eo_size
		result.append({"frac": frac, "dir_angle": float(fp.get("dir_angle", 0.0)), "id": int(fp.get("id", i + 1))})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return result

## World position of fire-point `idx`. Falls back to global_position if FP not configured.
## Origin of CharacterBody2D is CENTER; frac offset shifted by -0.5 to match.
func _muzzle(idx: int = 0) -> Vector2:
	if idx < _fp_fracs.size() and _draw_size != Vector2.ZERO:
		return global_position + (_fp_fracs[idx]["frac"] as Vector2 - Vector2(0.5, 0.5)) * _draw_size
	return global_position

func _make_plume(frac: Vector2, dir_angle: float, style: Dictionary = {}) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	# Origin of CharacterBody2D is CENTER; _draw_size is the full drawn sprite extent.
	# frac (0,0)=top-left (1,1)=bottom-right → shift by -0.5 to center on origin.
	p.position = (frac - Vector2(0.5, 0.5)) * _draw_size
	p.amount = maxi(1, int(_draw_size.x / 5.0))
	p.lifetime             = float(style.get("lifetime", 0.35))
	p.emitting = true
	p.local_coords = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.z_as_relative = true
	p.z_index = 1
	p.gravity = Vector2.ZERO
	p.direction = Vector2.RIGHT.rotated(dir_angle)
	p.spread               = float(style.get("spread",   12.0))
	p.initial_velocity_min = float(style.get("vel_min",  80.0))
	p.initial_velocity_max = float(style.get("vel_max",  130.0))
	p.scale_amount_min     = float(style.get("sc_min",   1.0))
	p.scale_amount_max     = float(style.get("sc_max",   2.2))
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.05))
	p.scale_amount_curve = taper
	# Store the sprite-relative anchor (fraction of _draw_size, centered) + base direction so
	# _update_plume_xform() can re-derive position & scale each frame from the live sprite transform.
	p.set_meta("frac_centered", frac - Vector2(0.5, 0.5))
	p.set_meta("base_dir", p.direction)
	p.set_meta("base_pos", p.position)   # un-rotated anchor (px) for the optimized plume re-rotate (R6)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(16, 16) * 0.5
	for iy in 16:
		for ix in 16:
			var d: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / 8.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	p.texture = ImageTexture.create_from_image(img)
	var col_core:  Color = style.get("col_core",  Color(1.0, 0.95, 0.7, 1.0))
	var col_flame: Color = style.get("col_flame", Color(1.0, 0.6,  0.2, 1.0))
	var col_cool:  Color = style.get("col_cool",  Color(0.45, 0.6, 1.0, 0.85))
	var col_fade           := col_cool; col_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	grad.colors  = PackedColorArray([col_core, col_flame, col_cool, col_fade])
	p.color_ramp = grad
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	return p

# ── Dynamic plume modulation ──────────────────────────────────────────────────
func _apply_plume_vel_mult(m: float) -> void:
	for i: int in _plumes.size():
		var b: Dictionary = _plume_base[i]
		_plumes[i].initial_velocity_min = float(b["vel_min"]) * m
		_plumes[i].initial_velocity_max = float(b["vel_max"]) * m

func _apply_plume_full_mult(m: float) -> void:
	for i: int in _plumes.size():
		var p: CPUParticles2D = _plumes[i]
		var b: Dictionary = _plume_base[i]
		p.initial_velocity_min = float(b["vel_min"]) * m
		p.initial_velocity_max = float(b["vel_max"]) * m
		p.scale_amount_min     = float(b["sc_min"])  * m
		p.scale_amount_max     = float(b["sc_max"])  * m
		p.lifetime             = float(b["life"])    * m

func _apply_plume_color(want_red: bool) -> void:
	if want_red == _plume_in_red:
		return
	_plume_in_red = want_red
	var src: Array = _plume_red_cols if want_red else _plume_base_cols
	for i: int in _plumes.size():
		if _plumes[i].color_ramp != null and i < src.size():
			_plumes[i].color_ramp.colors = src[i]

func _update_plumes() -> void:
	if _plume_base.is_empty():
		return
	match behavior:
		"swarm_dive":
			_apply_plume_vel_mult(2.0 if _phase == 1 else 1.0)
		"orbit":
			_apply_plume_color(global_position.distance_to(_player_pos()) < 350.0)
		"jump":
			_apply_plume_full_mult(3.0 if _phase == 1 else 1.0)
		"jump_diag":
			_apply_plume_full_mult(3.0 if _phase == 1 else 1.0)
		"squid":
			_apply_plume_full_mult(2.0 if _phase == 1 else 1.0)   # vel / scale / life ×2 during a leap

## Re-anchor every plume to the sprite each frame using the LIVE sprite transform: its position is the
## fraction-of-sprite anchor scaled by _draw_size × the current squash/stretch (then rotated), and the
## emitter NODE is scaled by `uniform` × `_plume_body_scale` so the particles themselves grow/shrink with
## the enemy's breathing AND its Elite/Champion body size. Result: plumes stay rigidly stuck to the sprite
## at any size — no per-scale re-adjustment needed.
func _update_plume_xform() -> void:
	if _plumes.is_empty():
		return
	var rot := _spin if behavior == "centipede" else _facing
	var vx := _visual_xform()
	var svec: Vector2 = vx["scale"]
	var uni: float = vx["uniform"] * _plume_body_scale
	var node_scale := Vector2(uni, uni)
	for p: CPUParticles2D in _plumes:
		if not is_instance_valid(p):
			continue
		var fc: Vector2 = p.get_meta("frac_centered")
		# Anchor offset in sprite-local px, including squash/stretch, then rotate to face heading.
		var off := Vector2(fc.x * _draw_size.x * svec.x, fc.y * _draw_size.y * svec.y)
		p.position  = off.rotated(rot)
		p.direction = (p.get_meta("base_dir") as Vector2).rotated(rot)
		p.scale     = node_scale   # local_coords plumes → node scale grows the whole jet with the enemy

## Re-anchor every vortex to the sprite each frame using the LIVE sprite transform — identical to the plume
## glue: the anchor offset (fraction-of-sprite × _draw_size × squash) is rotated to the heading, the node is
## scaled by its config-space base × the breathing `uniform`, and the whole swirl is rotated WITH the sprite
## so it tracks the enemy when it turns.
func _update_vortex_xform() -> void:
	if _vortexes.is_empty():
		return
	var rot := _spin if behavior == "centipede" else _facing
	var vx := _visual_xform()
	var svec: Vector2 = vx["scale"]
	var uni: float = vx["uniform"]
	for node: Node2D in _vortexes:
		if not is_instance_valid(node):
			continue
		var fc: Vector2 = node.get_meta("frac_centered")
		var bs: float = node.get_meta("base_scale")
		var off := Vector2(fc.x * _draw_size.x * svec.x, fc.y * _draw_size.y * svec.y)
		node.position = off.rotated(rot)
		node.scale    = Vector2(bs * uni, bs * uni)
		node.rotation = rot   # the swirl orients with the body so it follows the enemy's rotation

## Re-anchor every LED to the sprite each frame — identical glue to _update_vortex_xform().
func _update_led_xform() -> void:
	if _leds.is_empty():
		return
	if behavior == "centipede":
		_update_led_xform_centipede()
		return
	var rot := _facing
	var vx := _visual_xform()
	var svec: Vector2 = vx["scale"]
	var uni: float = vx["uniform"]
	for node: Node2D in _leds:
		if not is_instance_valid(node):
			continue
		var fc: Vector2 = node.get_meta("frac_centered")
		var bs: float = node.get_meta("base_scale")
		var off := Vector2(fc.x * _draw_size.x * svec.x, fc.y * _draw_size.y * svec.y)
		node.position = off.rotated(rot)
		node.scale    = Vector2(bs * uni, bs * uni)
		node.rotation = rot + deg_to_rad(float(node.get_meta("rotate_deg", 0.0)))

## Per-segment LED glue for centipede-behavior creeps (2026-08-15) — each LED rides the LIVE `_centi_pts[k]`
## position + `_centi_seg_ang(k)` angle of whichever real segment it was matched to in
## _setup_leds_centipede(), instead of one rigid whole-body transform. `k=-1` (stored for Tail) resolves to
## the true last index every frame since Segments can change after spawn (shouldn't in practice, but costs
## nothing to stay correct). Taper is honored via _centi_seg_size_for()×_centi_seg_scale() for the offset math,
## so a LED anchored on a tapered-down duplicate slot isn't a concern — it always rides a TEMPLATE's own first-
## use slot (see _setup_leds_centipede()), which is never tapered.
func _update_led_xform_centipede() -> void:
	var n := _centi_pts.size()
	if n == 0:
		return
	for node: Node2D in _leds:
		if not is_instance_valid(node):
			continue
		var k: int = int(node.get_meta("centi_k", 0))
		if k < 0:
			k = n - 1
		k = clampi(k, 0, n - 1)
		var seg_size := _centi_seg_size_for(k, n) * _centi_seg_scale(k, n)
		var ang := _centi_seg_ang(k)
		var fc: Vector2 = node.get_meta("frac_centered")
		var local_off := Vector2(fc.x * seg_size.x, fc.y * seg_size.y).rotated(ang + PI * 0.5)
		node.position = ((_centi_pts[k] as Vector2) - global_position) + local_off
		node.rotation = ang + PI * 0.5 + deg_to_rad(float(node.get_meta("rotate_deg", 0.0)))

# ── Universal damage contract ──────────────────────────────────────────────────
func is_anti_magnetic() -> bool:
	return _anti_magnetic

# ── Status effects ─────────────────────────────────────────────────────────────
## Status-duration multiplier from the Lasgun's Capacitor perk (global mech "duration_pct").
func _dur_mult() -> float:
	return 1.0 + (GameManager.mech_bonus("duration_pct") if GameManager.has_method("mech_bonus") else 0.0)

func is_burning() -> bool:
	return _burn_stacks > 0

## Public death flag (Space Snake's Primordial God counts kills it lands).
func is_dead() -> bool:
	return _dead

## Apply burn stack(s): % current-HP DoT per stack for BURN_DURATION (refreshed). No hard stack cap.
func apply_burn(stacks: int = 1) -> void:
	if _dead:
		return
	_burn_stacks += maxi(1, stacks)
	var add: float = GameManager.mech_bonus("burn_dur_add") if GameManager.has_method("mech_bonus") else 0.0
	_burn_t = BURN_DURATION * _dur_mult() + add   # Prolonged Flame / Dragon's Breath burn-duration bonus

## Apply freeze stack(s): each slows FREEZE_SLOW_PER, capped (6 stacks normal / 2 boss), decays after FREEZE_DURATION.
func apply_freeze(stacks: int = 1) -> void:
	if _dead:
		return
	var cap_stacks := 2 if is_in_group("boss") else 6
	_freeze_stacks = mini(_freeze_stacks + maxi(1, stacks), cap_stacks)
	_freeze_t = FREEZE_DURATION * _dur_mult()

## Stun for `duration` s — frozen movement/attacks + +50% damage taken. No-op if already stunned or immune.
func apply_stun(duration: float) -> void:
	if _dead or _stun_t > 0.0 or _stun_immune_t > 0.0:
		return
	_stun_t = duration * _dur_mult()

func is_stunned() -> bool:
	return _stun_t > 0.0

## Dazzling Display capstone: scale this enemy's post-stun immunity (e.g. 0.5 = halved).
func set_stun_immune_mult(m: float) -> void:
	_stun_immune_mult = m

## Pacifying Jolt: halve this enemy's damage output for `duration` s.
func apply_weaken(duration: float) -> void:
	if not _dead:
		_weaken_t = maxf(_weaken_t, duration)

## Sedative Scent (Chemtrail): slow + outgoing-damage reduction, refreshed each tick the enemy is in the cloud.
func apply_sedative(dmg_red: float, ms_red: float, duration: float = 0.4) -> void:
	if _dead:
		return
	_sed_dmg = dmg_red
	_sed_slow = ms_red
	_sed_t = maxf(_sed_t, duration)

## Effective armor for a hit: (base − temp reductions) × (1 − %pen), then − flat pen, clamped to the floor.
## Floor is 0 normally; −20 under Less Than Nothing; and Parasite's Armor Stripping Mastery / Strip Naked drive
## it further negative via the "armor_floor" mech (magnitude), letting stripped armor amplify damage.
func _hit_armor() -> float:
	if not GameManager.has_method("mech_bonus"):
		return armor
	var a := armor - _armor_reduce - _corrode_reduce
	a = a * (1.0 - GameManager.mech_bonus("armor_pen_pct")) - GameManager.mech_bonus("armor_pen_flat")
	var floor_mag := maxf(20.0 if GameManager.mech_bonus("less_than_nothing") > 0.0 else 0.0, GameManager.mech_bonus("armor_floor"))
	return maxf(-floor_mag, a)

## Total temporary armor stripped off this enemy right now (Critical Break + Metal Eater). For Stolen Fortitude.
func armor_reduction_total() -> float:
	return _armor_reduce + _corrode_reduce

## Critical Break: temporarily strip `amt` armor for `dur` s (accumulates; timer refreshed).
func _reduce_armor(amt: float, dur: float) -> void:
	_armor_reduce += amt
	_armor_reduce_t = maxf(_armor_reduce_t, dur)

## Metal Eater (Parasite): corrode `add` armor per call, capped at `cap` total; refreshes the `dur` timer.
func apply_corrode(add: float, cap: float, dur: float) -> void:
	if _dead:
		return
	_corrode_reduce = minf(_corrode_reduce + add, cap)
	_corrode_t = maxf(_corrode_t, dur)

## Max bleed stacks: base 50 + Bleed Mastery (global) + Hurt evo (+3 per flat armor-pen point).
func _bleed_max() -> int:
	var m := BLEED_MAX_BASE
	if GameManager.has_method("mech_bonus"):
		m += int(GameManager.mech_bonus("bleed_max_add"))
		if GameManager.mech_bonus("hurt") > 0.0:
			m += int(GameManager.mech_bonus("armor_pen_flat") * 3.0)
	return m

## Public max-bleed accessor (Boomerang's Bleed! evolve applies a % of this per hit).
func bleed_max() -> int:
	return _bleed_max()

func apply_bleed(stacks: int = 1) -> void:
	if _dead:
		return
	_bleed_stacks = mini(_bleed_stacks + maxi(1, stacks), _bleed_max())
	var dur_pct: float = GameManager.mech_bonus("bleed_dur_pct") if GameManager.has_method("mech_bonus") else 0.0   # Hemophilia Mastery
	_bleed_t = BLEED_DURATION * (1.0 + dur_pct)

## Cauterize the Wound (Z-Sword): convert a fraction of current bleed stacks into burn stacks.
func cauterize(frac: float) -> void:
	if _bleed_stacks <= 0:
		return
	var moved := int(ceil(float(_bleed_stacks) * frac))
	_bleed_stacks = maxi(0, _bleed_stacks - moved)
	if _bleed_stacks <= 0:
		_bleed_t = 0.0
	apply_burn(moved)

## Windshield Wiper (Z-Sword): a strong, brief slow that decays to 0 over 0.2s.
func apply_wiper() -> void:
	if not _dead:
		_wiper_t = 0.2

## Siren (Sonic): charm this enemy for `dur` s — it fights for the player. Bosses are immune.
func apply_charm(dur: float) -> void:
	if _dead or is_in_group("boss"):
		return
	_charm_t = dur
	if not is_in_group("arena_charmed"):
		add_to_group("arena_charmed")   # tiny group scanned by _resolve_aggro (keeps it O(charmed), not O(all enemies))

func is_charmed() -> bool:
	return _charm_t > 0.0

## Number of distinct active statuses on this enemy — Sensory Overload (Sonic) scales damage by it.
func status_count() -> int:
	var n := 0
	if _burn_stacks > 0: n += 1
	if _freeze_stacks > 0: n += 1
	if _stun_t > 0.0: n += 1
	if _bleed_stacks > 0: n += 1
	if _vuln_t > 0.0: n += 1
	if _weaken_t > 0.0: n += 1
	if _sed_t > 0.0: n += 1
	return n

## Nearest NON-charmed enemy (the charmed one's target / duel partner).
func _nearest_foe() -> Node2D:
	var best: Node2D = null
	var bd := 1.0e20
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if e == self or not is_instance_valid(e):
			continue
		if e.has_method("is_charmed") and e.call("is_charmed"):
			continue
		var d: float = global_position.distance_squared_to((e as Node2D).global_position)
		if d < bd:
			bd = d
			best = e
	return best

## Multiplier on this enemy's outgoing damage (Pacifying Jolt halves; Sedative reduces).
func damage_out_mult() -> float:
	var m := 0.5 if _weaken_t > 0.0 else 1.0
	if _sed_t > 0.0:
		m *= (1.0 - _sed_dmg)
	if GameManager.has_method("mech_bonus") and GameManager.mech_bonus("zone_of_peace") > 0.0:
		m *= 0.8   # Zone of Peace (Ionizing Field evolve)
	if GameManager.has_method("mech_bonus"):
		m *= 1.0 + GameManager.mech_bonus("enemy_dmg_mult")   # Beacon: stronger enemies
	return m

## Orb of Annihilation: this enemy takes +20% damage from all sources for `duration` s (refreshed while in the orb).
func apply_vulnerable(duration: float) -> void:
	if not _dead:
		_vuln_t = maxf(_vuln_t, duration)

## Tick burn DoT + freeze decay; update the movement-slow + a status tint.
func _tick_status(delta: float) -> void:
	if _burn_stacks > 0:
		_burn_t -= delta
		if _burn_t <= 0.0:
			_burn_stacks = 0
			_burn_acc = 0.0
		else:
			_burn_acc += delta
			# Armor Melter (Dragon's Breath evo): heavily-burned enemies (≥10 stacks) take more damage.
			# (Enemies have no real armor stat — modeled as vulnerability; see note.)
			if _burn_stacks >= 10 and GameManager.has_method("mech_bonus") and GameManager.mech_bonus("armor_melt") > 0.0:
				apply_vulnerable(BURN_TICK + 0.2)
			while _burn_acc >= BURN_TICK:
				_burn_acc -= BURN_TICK
				var bmul: float = 1.0 + (GameManager.mech_bonus("burn_dmg") if GameManager.has_method("mech_bonus") else 0.0)
				var dmg := hp * BURN_PCT * float(_burn_stacks) * BURN_TICK * bmul
				if dmg > 0.0:
					take_damage(dmg, 0.0, 0.0, true)   # burn IGNORES armor
					if _dead:
						return
	# Bleed (Drill Bits): 1 dmg/stack/s for 5s, IGNORES armor. Hurt evo scales it by % armor pen.
	if _bleed_stacks > 0:
		_bleed_t -= delta
		if _bleed_t <= 0.0:
			_bleed_stacks = 0
			_bleed_acc = 0.0
		else:
			_bleed_acc += delta
			while _bleed_acc >= BLEED_TICK:
				_bleed_acc -= BLEED_TICK
				var hurt: float = (GameManager.mech_bonus("armor_pen_pct") if (GameManager.has_method("mech_bonus") and GameManager.mech_bonus("hurt") > 0.0) else 0.0)
				var hem: float = GameManager.mech_bonus("bleed_dmg") if GameManager.has_method("mech_bonus") else 0.0   # Hemorrhage Mastery
				take_damage(float(_bleed_stacks) * (1.0 + hurt + hem), 0.0, 0.0, true)
				if _dead:
					return
	if _freeze_stacks > 0:
		_freeze_t -= delta
		if _freeze_t <= 0.0:
			_freeze_stacks = 0
	var cap := FREEZE_MAX_BOSS if is_in_group("boss") else FREEZE_MAX
	_move_slow = minf(float(_freeze_stacks) * FREEZE_SLOW_PER, cap)
	# Stun timer → on expiry, grant the post-stun immunity window.
	if _weaken_t > 0.0:
		_weaken_t = maxf(0.0, _weaken_t - delta)
	if _sed_t > 0.0:
		_sed_t = maxf(0.0, _sed_t - delta)
	if _armor_reduce_t > 0.0:
		_armor_reduce_t = maxf(0.0, _armor_reduce_t - delta)
		if _armor_reduce_t <= 0.0:
			_armor_reduce = 0.0
	if _corrode_t > 0.0:
		_corrode_t = maxf(0.0, _corrode_t - delta)
		if _corrode_t <= 0.0:
			_corrode_reduce = 0.0
	if _wiper_t > 0.0:
		_wiper_t = maxf(0.0, _wiper_t - delta)
	if _charm_t > 0.0:
		_charm_t = maxf(0.0, _charm_t - delta)
		if _charm_t <= 0.0 and is_in_group("arena_charmed"):
			remove_from_group("arena_charmed")   # charm expired → drop out of the scanned group
	if _vuln_t > 0.0:
		_vuln_t = maxf(0.0, _vuln_t - delta)
	if _stun_t > 0.0:
		_stun_t -= delta
		if _stun_t <= 0.0:
			_stun_t = 0.0
			var imm := STUN_IMMUNE_BOSS if is_in_group("boss") else STUN_IMMUNE
			# Dazzling Display: a global immunity reduction (0..0.95) on top of any per-enemy mult.
			var reduce: float = GameManager.mech_bonus("stun_immune_reduce") if GameManager.has_method("mech_bonus") else 0.0
			_stun_immune_t = imm * _stun_immune_mult * (1.0 - clampf(reduce, 0.0, 0.95))
	elif _stun_immune_t > 0.0:
		_stun_immune_t = maxf(0.0, _stun_immune_t - delta)
	# Status tint: charm (pink blink) > stun (electric) > freeze (icy) > burn (fiery).
	if _charm_t > 0.0:
		var blink := 1.4 + 0.5 * sin(_charm_t * 18.0)   # pulsing pink
		modulate = Color(blink, 0.5, blink * 0.8)
	elif _stun_t > 0.0:
		modulate = Color(1.7, 1.7, 0.6)
	elif _freeze_stacks > 0:
		modulate = Color(0.6, 0.8, 1.25)
	elif _burn_stacks > 0:
		modulate = Color(1.3, 0.7, 0.45)
	else:
		modulate = Color.WHITE

## ignore_armor: bleed/burn bypass armor DR. bleeds: kinetic/contact hit → Serrated Heads applies a bleed stack.
## was_crit: a crit hit → Critical Break temporarily strips armor.
func take_damage(amount: float, stagger: float = 0.0, knock: float = 0.0, ignore_armor: bool = false, bleeds: bool = false, was_crit: bool = false, kind: String = "") -> void:
	if _dead:
		return
	if _invincible:
		return   # test dummy — still blocks the beam (it's in "arena_enemy") but never takes damage or dies
	# Ghost evasion: once below the HP threshold, a chance to dodge the hit entirely (brief shimmer, no damage).
	if _evade_chance > 0.0 and hp <= hp_max * _evade_below and randf() < _evade_chance:
		_flash = HIT_FLASH_TIME * 0.5
		_flash_color = HIT_FLASH_COLOR
		queue_redraw()
		return
	# Anemia (Snake evolve): the target takes +1% damage from ALL sources per 10 bleed stacks on it.
	if _bleed_stacks >= 10 and GameManager.has_method("mech_bonus") and GameManager.mech_bonus("anemia_vuln") > 0.0:
		amount *= 1.0 + 0.01 * float(_bleed_stacks / 10)
	# Proximity Mastery (Ionizing Field, GLOBAL): closer-to-the-ship targets take more damage. Distance bands:
	# >400px none, 300-400 → 25%, 150-300 → 75%, <150 → 100% of the per-rank bonus (max at 50px).
	var prox: float = GameManager.mech_bonus("proximity_dmg") if GameManager.has_method("mech_bonus") else 0.0
	if prox > 0.0 and is_instance_valid(_target):
		var pd := global_position.distance_to((_target as Node2D).global_position)
		var f := 0.0
		if pd <= 150.0: f = 1.0
		elif pd <= 300.0: f = 0.75
		elif pd <= 400.0: f = 0.25
		amount *= 1.0 + prox * f
	# Armor damage reduction — RNG's GameManager curve (fallback to the inline formula if unavailable).
	var dr := 0.0
	if GameManager.has_method("armor_damage_reduction"):
		dr = GameManager.armor_damage_reduction(armor)
	else:
		dr = (0.052 * armor) / (1.0 + 0.052 * armor)
	var dealt := amount * (1.0 - dr)
	# Bismuth anti-magnetic: only laser / lightning / vacuum bite, and only for half.
	if _anti_magnetic and (kind == "death_beam" or kind == "arc" or kind == "rift_maker"):
		dealt *= 0.5
	# Status multipliers: stunned enemies take +50%, Orb-of-Annihilation vulnerable +20%.
	if _stun_t > 0.0:
		dealt *= STUN_DMG_MULT
	if _vuln_t > 0.0:
		amount *= 1.2             # Orb of Annihilation: +20% damage taken
	if not ignore_armor and GameManager.has_method("armor_damage_reduction"):
		amount *= 1.0 - GameManager.armor_damage_reduction(_hit_armor())   # armor DR after pen + reductions
	hp -= amount
	# Drill Bits: Serrated Heads (bleed on kinetic/contact hits) + Critical Break (crit strips armor).
	if GameManager.has_method("mech_bonus"):
		if bleeds and GameManager.mech_bonus("serrated") > 0.0:
			apply_bleed(1)
		if was_crit and GameManager.mech_bonus("critbreak") > 0.0:
			_reduce_armor(GameManager.mech_bonus("critbreak") * amount, 5.0)
		# Aim Assistor crit-status perks: a crit applies bleed/burn/freeze/stun per its ranks.
		if was_crit:
			var cb := int(GameManager.mech_bonus("crit_bleed"))
			if cb > 0:
				apply_bleed(cb)
			var bu := int(GameManager.mech_bonus("crit_burn"))
			if bu > 0:
				apply_burn(bu)
			var fz := int(GameManager.mech_bonus("crit_freeze"))
			if fz > 0:
				apply_freeze(fz)
			var sk := GameManager.mech_bonus("crit_shock")
			if sk > 0.0:
				apply_stun(sk)
	# Hit reaction: flash (red if this blow kills, else white) + (optional) knockback + stagger.
	_flash_color = KILL_FLASH_COLOR if hp <= 0.0 else HIT_FLASH_COLOR
	_stagger_t = maxf(_stagger_t, stagger)
	_flash = HIT_FLASH_TIME
	# Pushback ONLY when the hitting weapon asks for it (knock > 0). Most weapons no longer push — only the
	# Nuke and Gatling pass knock=1.0. Elites are immune BY DEFAULT (_knockback_mult defaults to 0.0 whenever
	# "elite" is set — a big, heavy "mini-boss" enemy shouldn't go skating across the screen on every hit);
	# milestone elites and spawn_mode_2 Champions get that default, while arena_wave_director_v2.gd's
	# periodic Elite Creep explicitly overrides it to 0.5 via def["knockback_mult"] — pushed at half a
	# normal enemy's strength instead of full immunity. `no_collide` landmarks (dead-ship wrecks, electric
	# temple boss) are exempt outright — deliberately stationary, and for the temple specifically, knockback
	# would desync its 2D hit-box from the separate live 3D model electric_trees.gd renders at a fixed world
	# position (that model has no way to follow a knockback push).
	if knock > 0.0 and not _no_collide and _knockback_mult > 0.0:
		var away := global_position - _player_pos()
		var dir := away.normalized() if away.length() > 0.01 else Vector2.UP
		# A docked MOTHERSHIP escort, or ANY carrier (fleet or mothership) leading a docked squad: a real
		# _knockback on the carrier would drag every sibling re-pinned to its global_position each frame —
		# shake only. A docked FLEET escort (dock_kind "fleet") is the one exception: it gets a real per-unit
		# knockback below, same as any normal enemy — _fleet_update_dock_positions() eases it back to its
		# slot afterward (with a catch-up speed boost while it's stray), so only THAT unit visibly recoils
		# and the rest of the formation is untouched.
		if (_docked and _dock_kind != "fleet") or not _fleet_dock.is_empty():
			_hit_shake = dir * HIT_SHAKE_MAG
		else:
			var momentum: float = GameManager.get_momentum_mult() if GameManager.has_method("get_momentum_mult") else 1.0
			_knockback = dir * KNOCKBACK_SPEED * knock * momentum * _knockback_mult
	queue_redraw()
	if hp <= 0.0:
		# Metalfly Phase 1: running the cocoon's HP out HATCHES the boss, it doesn't kill it. Intercepted
		# here rather than inside _die() so none of death's consequences (kill tally, XP, loot, chain
		# reaction, boss_defeated) can fire for what is really the first half of one fight.
		if _boss_move == "metalfly" and _mf_phase == 1:
			_metalfly_hatch()
			return
		_die()

## Elite/Champion weapon drop (see _die()). Rolls one weapon from InventoryManager's own loot table — the
## same `roll_boss_weapon()` the mid-run field drops use — and leaves it on the ground as an
## arena_item_drop.gd collectible instead of granting it silently. Champion draws from a higher rarity cap
## (very_rare) than Elite (rare). Parented to the arena (get_parent()) rather than to this enemy, which is
## about to free itself.
func _drop_tier_weapon() -> void:
	if not MetaManager.has_method("roll_boss_weapon"):
		return
	var cap: int = int(MetaManager.RARITY_RANK.get("very_rare", 3)) if _is_champion 			else int(MetaManager.RARITY_RANK.get("rare", 2))
	var def_id := String(MetaManager.roll_boss_weapon(cap))
	if def_id == "":
		return
	var host := get_parent()
	if host == null or not is_instance_valid(host):
		return
	var drop: Node2D = ItemDropScript.new()
	host.add_child(drop)
	drop.call("setup", global_position, def_id)

## LIFETIME_MAX safety net — quietly removes an enemy that's been alive too long (never reached/engaged the
## player, or otherwise got stuck) WITHOUT any of _die()'s effects: no kill count, no XP/loot/reward, no
## death FX/sound. Docked mothership escorts are released first so they don't freeze pinned to a carrier
## that's still alive.
func _despawn_stale() -> void:
	_release_all_docks()
	if _squid_attached:
		_squid_detach()
	queue_free()

## Free every docked escort of a generic Fleet Edit carrier (any behavior — see init_fleet_dock()) so they
## don't freeze pinned to a carrier that's about to die/despawn. Released escorts become normal free-flying
## enemies (own steering resumes via _docked=false), same fallback mothership escorts get when set free.
func _release_fleet_dock() -> void:
	for e: Dictionary in _fleet_dock:
		var dn = e.get("node")
		if dn != null and is_instance_valid(dn):
			dn.call("set_docked", false)
	_fleet_dock.clear()

## Release BOTH dock systems (mothership _ms_dock + generic Fleet _fleet_dock) — call before ANY silent
## self-removal of a live carrier (not just _despawn_stale()/_die()) so its escorts never freeze pinned to a
## carrier that no longer exists. "patrol"-behavior carriers (e.g. Sentinel Fleet's sentinel1-4) never re-aim
## at the player and self-cull via a raw queue_free() once PATROL_CULL away — that call used to bypass both
## _despawn_stale() and _die(), so a Sentinel Fleet formation's escorts were orphaned in place forever the
## moment the carrier flew off and culled itself (the whole formation reads as "never reaches the player").
func _release_all_docks() -> void:
	if behavior == "mothership":
		for e: Dictionary in _ms_dock:
			var dn = e.get("node")
			if dn != null and is_instance_valid(dn):
				dn.call("set_docked", false)
		_ms_dock.clear()
	_release_fleet_dock()

func _die() -> void:
	if _dead:
		return
	_dead = true
	_death_count_since_read += 1   # TEMP DIAGNOSTIC (see arena_perf_spike_logger.gd)
	# Explosivo "Chain Reaction" evolve: 25% chance a slain enemy detonates for 50 kinetic AoE damage.
	if GameManager.has_method("mech_bonus") and GameManager.mech_bonus("chain_reaction") > 0.0 and randf() < 0.25:
		var aw := get_tree().get_first_node_in_group("arena_weapons")
		if aw != null and aw.has_method("chain_reaction_explode"):
			aw.call("chain_reaction_explode", global_position)
	# Carrier destroyed → set its docked escorts free so they don't freeze where they were pinned.
	_release_all_docks()
	if _death_spawn != "":
		_spawn_sibling(_death_spawn, global_position)   # stone → magma fragment that keeps fighting
	if _magma_split:
		_burst_small_magma()   # large magma → MAGMA_SPLIT_N small magma flung outward
	if GameManager.has_method("add_kill"):
		GameManager.add_kill()   # tally for the arena HUD kill counter
	# Milestone Elite/Champion Creep reward on death (2026-08-06, on request — split by tier; see
	# arena_wave_director_v2.gd's header comment above _tick_elite_creep for the full rationale):
	#   Champion (_is_champion) → guaranteed-new weapon/aux pick (or a fragment if every slot's full).
	#   Elite (plain _is_elite)  → flat 50 coin, no UI.
	if _is_champion:
		var ui := get_tree().get_first_node_in_group("levelup_ui")
		if ui != null and is_instance_valid(ui) and ui.has_method("grant_champion_reward"):
			ui.call("grant_champion_reward")
	elif _is_elite:
		if _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("spawn_loot"):
			_mgr.spawn_loot(global_position, "coin")   # spawn_loot's own default value is 50
	# Weapon drop — BOTH tiers, on top of the tier reward above (2026-08-25, on request: "khi bắn chết
	# elite/champion, tôi cần icon weapon drop ra trên màn hình"). A physical collectible, not an instant
	# grant: it lands where the creep died and goes into the BACKPACK when flown over, with a bottom-right
	# "…has been acquired. Press I to view" notice. See arena_item_drop.gd. Champion rolls from a higher
	# rarity cap than Elite, matching how much rarer the tier is.
	if _is_elite:
		_drop_tier_weapon()
	if _is_final_boss and GameManager.has_signal("final_boss_defeated"):
		GameManager.final_boss_defeated.emit()
	if _squid_attached:
		_squid_detach()   # stop slowing the ship the instant this squid dies
	# Custom loot on death (e.g. the dead-ship wrecks' orb of light). Because a wreck is now a real enemy,
	# it already takes every weapon effect + bullet bounce; this is the only bespoke bit it needs.
	if _drop_loot != "" and _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("spawn_loot"):
		_mgr.spawn_loot(global_position, _drop_loot)
	# Drop a collectible XP orb (the player magnetizes + collects it) instead of granting XP instantly.
	if xp > 0:
		# Data Harvester "double orb": a chance (× Stroke of Luck) to drop double XP.
		if GameManager.has_method("mech_bonus") and randf() < (GameManager.mech_bonus("double_xp_chance") + GameManager.mech_bonus("proc_luck")):
			xp *= 2
		if _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("spawn_xp_orb"):
			_mgr.spawn_xp_orb(global_position, xp)
		elif GameManager.has_method("add_xp"):
			GameManager.add_xp(xp)   # fallback if no manager is wired
	# Credit Extractor: chance to drop coin(s), scaled by this enemy's Max HP (≈1 per 900 HP × drop weight);
	# each coin's value is rolled from [1..50], skewed low + scaled by HP. 0 unless Credit Extractor is owned.
	if GameManager.has_method("mech_bonus") and GameManager.upg_coin_drop > 0.0 and _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("spawn_loot"):
		var expected := hp_max / 900.0 * GameManager.upg_coin_drop
		var coins := int(expected) + (1 if randf() < (expected - float(int(expected))) else 0)
		var skew: float = GameManager.mech_bonus("coin_skew")
		for _c in mini(coins, 20):
			_mgr.spawn_loot(global_position, "coin", GameManager.roll_coin_value(hp_max, skew))
	# Field find: small chance this creep kill also drops a weapon/aux token straight into Cargo.
	if MetaManager.has_method("roll_field_drop"):
		MetaManager.roll_field_drop()
	# Explosion VFX + random boom SFX
	_spawn_explosion(maxf(_draw_size.x, _radius * 2.0))
	_play_boom()
	# Start the death pop (a short flourish) instead of freeing immediately; stop separating meanwhile.
	_dying = true
	_death_t = 0.0
	_separates = false

## Spawn another arena enemy by id at `at`, as a sibling (used by stone death-spawn + alien morph).
## Reads ENEMY_DEFS from the live wave_director node (no preload → avoids the wave_director↔enemy cycle).
func _spawn_sibling(id: String, at: Vector2) -> void:
	if id == "":
		return
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd == null:
		return
	var def: Dictionary = (wd.ENEMY_DEFS as Dictionary).get(id, {})
	if def.is_empty():
		return
	# This path builds an arena_enemy DIRECTLY, bypassing the director's _spawn_def() and therefore its
	# ranged ceiling (SHOOT_MAX_ALIVE), which is an absolute rule for non-boss creeps. No def death-spawns a
	# ranged creep today (every stone→magma target is behavior "chase"), so this is a no-op right now — it's
	# here so a future def can't silently reopen the hole the way "sentinel" did.
	if wd.has_method("can_spawn_shooter") and not bool(wd.call("can_spawn_shooter", id)):
		return
	var e: Node = get_script().new()   # a fresh arena_enemy (no preload needed — same script)
	e.call("configure", id, _mgr, def)
	get_parent().add_child(e)
	e.set("global_position", at)

## Large magma death → burst into MAGMA_SPLIT_N small magma. Each small one is a REAL arena_enemy (shootable,
## chases + contact-damages like the parent) at MAGMA_SPLIT_SCALE size, a random magmafrag sprite, and no further
## split. They are flung outward (knockback) in evenly-spread directions so the burst reads as the rock shattering.
func _burst_small_magma() -> void:
	var base_ang := randf() * TAU
	for i in MAGMA_SPLIT_N:
		var ang := base_ang + TAU * float(i) / float(MAGMA_SPLIT_N) + randf_range(-0.25, 0.25)
		var dir := Vector2(cos(ang), sin(ang))
		# Build a magma-like def from THIS magma's (already level-scaled) stats — no "lvl" so it isn't re-scaled.
		var def := {
			"behavior": "chase",
			"hp":       maxf(1.0, hp_max * 0.1),   # magmafrag HP = 10% of the parent magma's HP (was 35%)
			"speed":    speed,
			"size":     (_radius / 1.05) * MAGMA_SPLIT_SCALE,   # configure() multiplies size by 1.05
			"contact":  contact_damage,
			"xp":       xp * 0.25,
			"armor":    armor,
			"icon":     "res://assets/map/volcanic/enemies/magmafrag (%d).png" % randi_range(1, 16),
		}
		var e: Node = get_script().new()
		e.call("configure", "magma_small", _mgr, def)
		get_parent().add_child(e)
		e.set("global_position", global_position + dir * (_radius * 0.4))
		e.set("_knockback", dir * MAGMA_SPLIT_FLING)   # initial outward burst, decays into the chase

## Spawn a teleport space-warp at a world position. expand=true → space pushes outward (arrival);
## expand=false → space pulls inward (departure). Converts the world point to a screen UV for the shader.
func _spawn_warp(world_pos: Vector2, expand: bool) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var sz := vp.get_visible_rect().size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	if not _WarpRect.can_spawn():
		return   # cap concurrent fullscreen screen-read warps — protects the GPU during synchronized alien waves
	var screen := vp.get_canvas_transform() * world_pos
	var center_uv := Vector2(screen.x / sz.x, screen.y / sz.y)
	if menu_confine_fx:
		# Decorative Main Menu backdrop: parent the rect straight into the caller's own canvas
		# layer at the enemy's own z-index (instead of a dedicated fullscreen CanvasLayer), so the
		# screen-read only captures what's already drawn below it (space.png) — Logo/buttons draw
		# on top afterward, undistorted.
		var rect := _WarpRect.new()
		rect.z_index = z_index
		rect.z_as_relative = z_as_relative
		get_parent().add_child(rect)
		rect.setup(center_uv, expand)
	else:
		var fx := _WarpFX.new()
		get_parent().add_child(fx)
		fx.setup(center_uv, expand)

## Fullscreen wrapper around _WarpRect — guarantees the warp renders above every arena element
## regardless of local z-order (real gameplay only; see menu_confine_fx for the decorative case).
class _WarpFX extends CanvasLayer:
	func setup(center_uv: Vector2, expand: bool) -> void:
		layer = 79
		var rect := _WarpRect.new()
		add_child(rect)
		rect.setup(center_uv, expand)

## Teleport space-warp ring — a screen-distortion refraction ring (same technique as the explosion
## shockwave). Signed displacement: outward = expand, inward = contract. Self-frees.
class _WarpRect extends ColorRect:
	const DUR  := 0.32
	const RMAX := 0.16     # ring radius in screen-height units
	const AMP  := 0.06     # peak UV displacement
	const MAX_ACTIVE := 4  # hard cap on concurrent warps — each one is a fullscreen screen-read (backbuffer copy) pass
	static var _active: int = 0
	static var _shared_shader: Shader = null   # compiled ONCE and reused (avoids a per-spawn shader-compile stutter)
	const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);
uniform float radius = 0.0;
uniform float amp = 0.0;          // signed: + push out (expand), - pull in (contract)
uniform float thickness = 0.07;
void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 raw = SCREEN_UV - center;
	vec2 d = raw; d.x *= aspect;
	float dist = length(d);
	vec2 dir = dist > 1e-5 ? normalize(raw) : vec2(0.0);
	float ring = 1.0 - smoothstep(0.0, thickness, abs(dist - radius));
	vec2 disp = dir * ring * amp;
	COLOR = texture(screen_tex, SCREEN_UV - disp);
}
"""
	var _mat: ShaderMaterial = null
	var _t: float = 0.0
	var _expand: bool = true

	static func can_spawn() -> bool:
		return _active < MAX_ACTIVE

	func setup(center_uv: Vector2, expand: bool) -> void:
		_expand = expand
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _shared_shader == null:
			_shared_shader = Shader.new()
			_shared_shader.code = SHADER_CODE
		_mat = ShaderMaterial.new()
		_mat.shader = _shared_shader
		_mat.set_shader_parameter("center", center_uv)
		material = _mat
		_active += 1

	func _exit_tree() -> void:
		_active -= 1

	func _process(delta: float) -> void:
		_t += delta
		var f := clampf(_t / DUR, 0.0, 1.0)
		if f >= 1.0:
			queue_free()
			return
		var pulse := sin(f * PI)   # 0→1→0 envelope
		if _expand:
			_mat.set_shader_parameter("radius", f * RMAX)          # ring grows outward
			_mat.set_shader_parameter("amp", AMP * pulse)
		else:
			_mat.set_shader_parameter("radius", (1.0 - f) * RMAX)  # ring closes inward
			_mat.set_shader_parameter("amp", -AMP * pulse)

## pros5: fire a gauss-style orb straight at the player's current position.
func _fire_gauss_orb() -> void:
	var to := _player_pos() - global_position
	var orb := _GaussOrb.new()
	get_parent().add_child(orb)
	orb.setup(global_position, to.normalized() if to.length() > 0.01 else Vector2.DOWN)

## Gauss orb fired BY an enemy AT the player — reuses the player Gauss orb's plasma flipbook (modulated
## orange instead of blue), flies straight, explodes on player contact OR after MAX_DIST. (Player's gauss
## lives in arena_weapons; this is the enemy-facing counterpart.)
class _GaussOrb extends Node2D:
	const SPEED    := 360.0
	const MAX_DIST := 800.0
	const HIT_R    := 24.0
	const DMG      := 10
	const DRAW     := 40.0
	const FPS      := 24.0
	const COL      := Color(1.0, 0.55, 0.15)   # orange (player's is blue)
	const ORB_DIR  := "res://assets/beam references/Gauss_orb_files_2/"
	static var _frames: Array = []
	var _dir: Vector2 = Vector2.DOWN
	var _start: Vector2 = Vector2.ZERO
	var _fb: float = 0.0
	var _idx: int = 0
	var _spr: Sprite2D = null

	static func _ensure_frames() -> void:
		if not _frames.is_empty():
			return
		for i in 24:
			var img := Image.new()
			if img.load("%sgauss24_%02d.png" % [ORB_DIR, i]) == OK:
				_frames.append(ImageTexture.create_from_image(img))

	func setup(world_pos: Vector2, dir: Vector2) -> void:
		_ensure_frames()
		global_position = world_pos
		_start = world_pos
		_dir = dir
		z_index = 3
		_spr = Sprite2D.new()
		_spr.modulate = COL
		if not _frames.is_empty():
			_spr.texture = _frames[0] as Texture2D
			var w := float((_frames[0] as Texture2D).get_width())
			if w > 0.0:
				_spr.scale = Vector2(DRAW / w, DRAW / w)
		add_child(_spr)

	func _process(delta: float) -> void:
		global_position += _dir * SPEED * delta
		if not _frames.is_empty():
			_fb += delta
			var spf := 1.0 / FPS
			while _fb >= spf:
				_fb -= spf
				_idx = (_idx + 1) % _frames.size()
			if _spr != null:
				_spr.texture = _frames[_idx] as Texture2D
		var pl := get_tree().get_first_node_in_group("player")
		var hit := pl != null and global_position.distance_to((pl as Node2D).global_position) <= HIT_R
		if hit or global_position.distance_to(_start) >= MAX_DIST:
			if hit and GameManager.has_method("ship_take_damage"):
				GameManager.ship_take_damage(DMG)
			var burst := _GaussBurst.new()
			get_parent().add_child(burst)
			burst.setup(global_position)
			queue_free()

## Brief self-animating gauss explosion (reuses the Gauss explosion v1 flipbook, orange-tinted).
class _GaussBurst extends Node2D:
	const DUR  := 0.5
	const DRAW := 90.0
	const COL  := Color(1.0, 0.55, 0.15)
	const DIR  := "res://assets/fx/gauss_explosion/v1/"
	static var _frames: Array = []
	var _t: float = 0.0
	var _spr: Sprite2D = null

	static func _ensure_frames() -> void:
		if not _frames.is_empty():
			return
		for i in 12:
			var img := Image.new()
			if img.load("%s%02d.png" % [DIR, i]) == OK:
				_frames.append(ImageTexture.create_from_image(img))

	func setup(world_pos: Vector2) -> void:
		_ensure_frames()
		global_position = world_pos
		z_index = 4
		_spr = Sprite2D.new()
		_spr.modulate = COL
		if not _frames.is_empty():
			_spr.texture = _frames[0] as Texture2D
			var w := float((_frames[0] as Texture2D).get_width())
			if w > 0.0:
				_spr.scale = Vector2(DRAW / w, DRAW / w)
		add_child(_spr)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= DUR or _frames.is_empty():
			queue_free()
			return
		var idx := clampi(int(_t / DUR * float(_frames.size())), 0, _frames.size() - 1)
		if _spr != null:
			_spr.texture = _frames[idx] as Texture2D

func _spawn_explosion(size_px: float) -> void:
	# Baked flipbook blast (scripts/gameplay/arena_death_fx.gd) — a pre-rendered sprite sheet of the composite
	# Explosion, played back ADDITIVE (1 node + 1 draw call). The live composite (~4 particle systems/death)
	# tanked the frame rate when a whole wave died at once; the flipbook looks the same for ~zero cost. It scales
	# itself to the enemy via its own DISPLAY_SCALE, so pass the enemy size straight through.
	var ex: Node2D = DeathFX.new()
	get_parent().add_child(ex)
	ex.call("setup", global_position, size_px)

func _play_boom() -> void:
	# Route through the manager's pooled+throttled boom (no per-death node churn / boom cacophony at mass death).
	if _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("play_boom"):
		_mgr.play_boom()

## Play a one-shot attack sound (lazily creates the player on first use). Plays once — no loop (every SFX
## resource this calls with has "edit/loop_mode=0" in its .import — checked, none of them loop at the audio
## level). The "sfx lặp lại" the user was hearing wasn't a literal audio loop: it was this getting called
## again and again by an off-screen creep's normal attack cycle (shooter/sentinel/beamer/bomber/missile all
## route through here) — the enemy keeps ticking off-screen (LOD staggers the rate, doesn't stop it), so its
## fire timer keeps firing and keeps re-triggering this, with no visible source to explain the recurring
## sound. Fixed at the source: gated on the SAME camera-visible-rect test _process() already computes for
## the off-screen movement LOD (_run_full_tick/on_screen), so an off-screen creep simply doesn't play
## anything, no matter how many times its behavior calls this. Death booms (_play_boom()) are NOT gated —
## already pooled/throttled manager-side (BOOM_POOL/BOOM_MIN_GAP), and a "something just died" cue reads as
## useful feedback even from just off-screen, unlike a repeating attack sound with no visible source.
func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	if _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("visible_world_rect"):
		if not (_mgr.visible_world_rect() as Rect2).grow(LOD_MARGIN).has_point(global_position):
			return
	if _sfx == null:
		_sfx = AudioStreamPlayer.new()
		_sfx.bus = sfx_bus
		add_child(_sfx)
	_sfx.stream = stream
	_sfx.play()

## Pick this enemy's target by closeness. Charmed → nearest NON-charmed enemy. Normal → nearest of {player,
## charmed enemies} (charmed allies are just more targets; everyone attacks whatever's closest).
func _resolve_aggro() -> Node:
	if _charm_t > 0.0:
		return _nearest_foe()
	var best: Node = _target
	var bd := 1.0e20
	if _target != null and is_instance_valid(_target):
		bd = global_position.distance_squared_to((_target as Node2D).global_position)
	# Only charmed enemies are extra targets. Scanning the (almost always empty) "arena_charmed" group instead
	# of ALL enemies turns this per-frame, per-enemy call from O(N²) into O(N × charmed) — critical at 200-300.
	var charmed := get_tree().get_nodes_in_group("arena_charmed")
	if charmed.is_empty():
		return best
	for e in charmed:
		if e == self or not is_instance_valid(e):
			continue
		var d: float = global_position.distance_squared_to((e as Node2D).global_position)
		if d < bd:
			bd = d
			best = e
	return best

func _player_pos() -> Vector2:
	if _aggro_target != null and is_instance_valid(_aggro_target):
		return (_aggro_target as Node2D).global_position
	if _target != null and is_instance_valid(_target):
		return _target.global_position
	_target = get_tree().get_first_node_in_group("player")
	return _target.global_position if _target != null else global_position

# ── Squid: orient so the tentacle side faces the player (tentacles lead the approach / wrap on contact). ──
func _face_squid(pp: Vector2, delta: float) -> void:
	var to := pp - global_position
	if to.length() <= 0.5:
		return
	var desired := to.angle() - _tent_front_ang   # rotate body so local front-angle aims at the player
	_facing = lerp_angle(_facing, desired, clampf(TURN_RATE * delta, 0.0, 1.0))

func _squid_attach(pp: Vector2) -> void:
	_squid_attached = true
	_squid_attach_off = global_position - pp
	var max_off := _radius + SQUID_ATTACH_RANGE
	if _squid_attach_off.length() > max_off:
		_squid_attach_off = _squid_attach_off.normalized() * max_off
	z_index = SQUID_WRAP_Z   # draw above the ship so the wrapping tentacles render over the hull
	if not is_in_group("squid_clinging"):
		add_to_group("squid_clinging")   # arena.gd counts this group to slow the ship

func _squid_detach() -> void:
	_squid_attached = false
	z_index = SQUID_BASE_Z   # back below the ship
	_phase = 0; _timer = 0.0   # restart the jump cycle cleanly (wait → leap)
	if is_in_group("squid_clinging"):
		remove_from_group("squid_clinging")

# ── Per-frame ───────────────────────────────────────────────────────────────────
# Runs in _process (NOT _physics_process): enemies are bodyless (Phase A) so they don't need the physics clock,
# and being on the fixed 60 Hz tick meant that when the whole swarm's per-frame cost exceeded one tick's budget,
# Godot ran MULTIPLE catch-up physics ticks per rendered frame — re-running every enemy 5-6× and collapsing the
# FPS. In _process the update runs exactly once per frame: slow frames just get slower, they never multiply.
func _process(delta: float) -> void:
	if _dying:   # death pop owns the transform; just advance the timer, then free
		_death_t += delta
		queue_redraw()
		if _death_t >= DEATH_POP_TIME:
			queue_free()
		return
	if _dead:
		return
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")
		if _target == null:
			return
	_aggro_target = _resolve_aggro()   # player / a charmed enemy / (if charmed) a foe — picked by closeness
	# Off-screen LOD, computed early so it can ALSO gate the full behavior tick + separation below (was
	# previously computed only near the end, for visuals only). An enemy outside the camera-visible rect
	# (+ margin) is invisible to the player right now — its movement/separation decision only needs to
	# refresh every LOD_STAGGER_N ticks instead of every tick (#2/#3 perf pass: distance-LOD + stagger).
	# Centipede/squid/mothership are exempt: their chain/tentacle/dock-formation logic needs a stable
	# every-tick cadence to avoid visibly glitching once they DO come on screen.
	var on_screen := true
	if _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("visible_world_rect"):
		on_screen = (_mgr.visible_world_rect() as Rect2).grow(LOD_MARGIN).has_point(global_position)
	# `_boss_move` is exempt for the same reason as the three below: a boss running a scripted move cycle
	# needs a stable cadence, or its wind-up/lunge timings stretch and snap back as it crosses the screen edge.
	var _stagger_exempt := behavior == "centipede" or behavior == "squid" or behavior == "mothership" \
			or _boss_move != ""
	var _run_full_tick := _stagger_exempt or on_screen \
		or (int(Engine.get_physics_frames()) + get_instance_id()) % LOD_STAGGER_N == 0
	_t += delta
	# `no_collide` landmarks (electric temple boss, dead-ship wrecks) are deliberately permanent fixtures, not
	# ordinary mobile creeps that got stuck/never engaged — exempt them, or a landmark boss spawned far away
	# (e.g. the temple, 10,000-15,000px out) can hit this 120s timeout mid-fight from travel+fight time alone,
	# vanishing via _despawn_stale() (a plain queue_free(), never _die()) with no death FX and no loot drop.
	# Elite Creep / Champion Creep (_is_elite — see arena_wave_director_v2.gd's _spawn_tiered_creep) are
	# exempt for the same reason as bosses: a big, deliberately-spawned milestone encounter shouldn't quietly
	# vanish mid-fight just because it took a while to find/kill — it should always end in a real kill (reward)
	# or the player leaving the fight, never a silent timeout.
	if behavior != "boss_stub" and not _no_collide and not _is_elite and _t >= LIFETIME_MAX:
		_despawn_stale()
		return
	# alien5: transform into another enemy (e.g. alien4) after a fixed lifetime — silent swap, no death/XP.
	if _morph_to != "" and _t >= _morph_after:
		_spawn_sibling(_morph_to, global_position)
		_release_all_docks()   # a Fleet Edit carrier (e.g. alien5) must free its escorts here — the morphed
		queue_free()           # sibling doesn't inherit the dock
		return
	_spawn_t = minf(_spawn_t + delta, SPAWN_POP_TIME)
	_stagger_t = maxf(0.0, _stagger_t - delta)
	_tick_status(delta)
	if _dead:   # a burn tick may have killed it
		return
	if _base_speed < 0.0:
		_base_speed = speed                      # capture the configured base once
	var wiper_slow := 0.99 * (_wiper_t / 0.2) if _wiper_t > 0.0 else 0.0   # Windshield Wiper: 99%→0 over 0.2s
	var zop := 0.8 if (GameManager.has_method("mech_bonus") and GameManager.mech_bonus("zone_of_peace") > 0.0) else 1.0   # Zone of Peace
	# Magnet "Reverse Polarity": slow enemies inside the player's pickup range.
	var rpz := 1.0
	if GameManager.has_method("mech_bonus"):
		var rp := GameManager.mech_bonus("reverse_polarity")
		if rp > 0.0 and is_instance_valid(_target) and global_position.distance_to((_target as Node2D).global_position) <= GameManager.get_pickup_radius():
			rpz = maxf(0.0, 1.0 - rp)
	var beacon_spd := (1.0 + GameManager.mech_bonus("enemy_speed_mult")) if GameManager.has_method("mech_bonus") else 1.0   # Beacon
	speed = _base_speed * (1.0 - _move_slow) * (1.0 - (_sed_slow if _sed_t > 0.0 else 0.0)) * (1.0 - wiper_slow) * zop * rpz * beacon_spd
	if not _init_done:
		_init_behavior()
		_init_done = true
	# A boss with a named moveset (`_boss_move`) ignores HIT-STAGGER — stun and docking still freeze it.
	# Measured 2026-08-24 while verifying the Metalfly moveset: under sustained Gatling fire the boss's move
	# clock advanced 0.00s across 700 frames, because each hit re-arms `_stagger_t` faster than it decays
	# (the same stagger-lock the `elif` below already describes). For an ordinary creep that reads as
	# flinching; for a boss it means holding the fire button cancels the entire fight — it would never reach
	# its wind-up, so the moveset would exist but be unreachable.
	var stagger_ok := _stagger_t <= 0.0 or _boss_move != ""
	if stagger_ok and not _docked and _stun_t <= 0.0 and _run_full_tick:   # staggered/docked/stunned/off-turn → movement & attacks frozen (visuals still play)
		_tick_behavior(delta)
		if _gauss_shooter:   # pros5 ranged attack, independent of the chase movement
			_gauss_t += delta
			if _gauss_t >= GAUSS_SHOOT_INTERVAL:
				_gauss_t = 0.0
				_fire_gauss_orb()
	elif not _docked and (_stagger_t > 0.0 or _stun_t > 0.0):
		# _tick_behavior() is frozen by hit-stagger/stun (NOT the LOD off-turn case — that one is expected to
		# catch up) but the lifetime clock _t keeps running. Many behaviors (bomber/scatter/etc.) gate their
		# own periodic re-decisions with `_t - _timer > N`. Without this, a long stagger-lock (sustained
		# Gatling fire keeps re-triggering GAT_STAGGER faster than it decays) lets _t run way ahead of _timer
		# while movement is frozen; the INSTANT the stagger finally clears, the behavior sees a huge backlog
		# and re-rolls its target/heading in one frame — a hard, full-speed direction snap. For a Fleet Edit
		# carrier (e.g. Hornet Row), every docked escort rigidly mirrors the carrier's position/facing each
		# frame, so that one snap reads as the WHOLE formation rotating and jerking at once. Advancing _timer
		# in lockstep while frozen keeps `_t - _timer` from ever building up a backlog, so the re-decision
		# happens on schedule instead of in a single instant catch-up burst.
		_timer += delta
	# Position after intended (pursuit) movement but BEFORE knockback — facing reads from this, so a knockback
	# push only DISPLACES the enemy, it never turns/reorients it.
	var pos_pre_knockback := global_position
	# Knockback recoil (decays). Docked MOTHERSHIP escorts ignore it — the carrier re-pins them exactly each
	# frame with no easing, so a real push would just get silently overwritten anyway. Docked FLEET escorts
	# DO apply their own knockback here (dock_kind "fleet") — _fleet_update_dock_positions() eases them back
	# to their slot afterward instead of snapping, so the recoil actually reads visually.
	if (not _docked or _dock_kind == "fleet") and _knockback.length() > 1.0:
		global_position += _knockback * delta
		_knockback = _knockback.lerp(Vector2.ZERO, clampf(KNOCKBACK_DECAY * delta, 0.0, 1.0))
	if _hit_shake.length() > 0.05:
		_hit_shake = _hit_shake.lerp(Vector2.ZERO, clampf(HIT_SHAKE_DECAY * delta, 0.0, 1.0))
	# Movement squash/stretch disabled — enemies no longer stretch/expand while moving or on hit.
	_squash = 0.0
	# Face the intended movement direction only — knockback must NOT rotate the enemy (centipede keeps spin).
	var intended := pos_pre_knockback - _prev_pos
	# Carrier (mothership) drives its own _facing; docked escorts get it from the carrier each frame.
	if behavior != "centipede" and behavior != "squid" and behavior != "mothership" and not _docked and intended.length() > 0.5:
		_facing = lerp_angle(_facing, intended.angle() + PI * 0.5, clampf(TURN_RATE * delta, 0.0, 1.0))
	_prev_pos = global_position
	if not _fleet_dock.is_empty():   # generic Fleet Edit carrier — re-pin its rigidly-docked escorts each frame
		_fleet_update_dock_positions(delta)
	if _idle_spin != 0.0:
		_facing += _idle_spin * delta   # slow in-place rotation for stationary wrecks (dummy behavior)
	# Point a live 3D body along the final facing. Done HERE, after every contributor to `_facing` has had
	# its say, rather than inside _tick_metalfly — that ran before the block above and covered only the
	# boss, leaving Move 3's brood (a plain "chase" enemy with the same rig) pointing wherever it spawned.
	# The rig wants the travel angle; `_facing` is that plus PI/2 ("sprite north").
	if _mf_rig != null and is_instance_valid(_mf_rig):
		_mf_rig.call("set_heading", _facing - PI * 0.5)
	if not _frames.is_empty():
		_anim_acc += delta
		var fd: float = float(_delays[_anim_frame]) if _anim_frame < _delays.size() else 0.1
		if _anim_acc >= fd:
			_anim_acc -= fd
			_anim_frame = (_anim_frame + 1) % _frames.size()
			_tex = _frames[_anim_frame] as Texture2D
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	# Attach the flash material only while flashing; otherwise leave material null (default = full brightness).
	# Also gated on _sprite_alpha > 0 — a landmark with no visible sprite (temple boss etc, sprite_alpha 0.0,
	# real visual is a separate live 3D model) has nothing texture-based to whiten, but the shader would still
	# apply to every OTHER draw call this node makes (the HP bar, the beam line...), visibly flashing those
	# white/red on every hit even though the "creep" it's flashing has no on-screen body of its own.
	var _want_mat: ShaderMaterial = _flash_mat if (_flash > 0.0 and _sprite_alpha > 0.0) else null
	if material != _want_mat:
		material = _want_mat
	_check_contact()
	# Off-screen visual LOD: an enemy outside the camera-visible rect (+ margin) skips ALL its visual
	# work — no _draw, no plume transform, and its plumes stop emitting (drain to ~0 particles). It keeps
	# moving (physics above — subject to the stagger computed at the top of this function), so it still
	# closes on the player; visuals resume the frame it re-enters view. `on_screen` itself was already
	# computed at the top of this function (reused here, not recomputed) so it can ALSO gate the
	# behavior/separation stagger before any movement happens this tick.
	var crowded := false
	if not _is_elite and _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("enemy_count"):
		# Elite/Champion Creep (_is_elite) are exempt — same "deliberate milestone encounter, must not quietly
		# degrade" reasoning as their LIFETIME_MAX despawn exemption above. They spawn 2-3x sized specifically
		# to stand out, and the fight is BUSIEST (closest to PLUME_LOD_COUNT) exactly when one is likely to be
		# up — without this exemption their thrust jets would silently vanish (`emitting = false` below) the
		# moment the field got crowded, i.e. almost immediately in the situations they're meant to be seen in.
		# User bug report: "elite unit khi được scale lại từ folder HDenemies thì mất thrust point".
		crowded = _mgr.enemy_count() > PLUME_LOD_COUNT   # density LOD: too many enemies → drop plume sim
	# Plumes emit only when on-screen AND the field isn't overcrowded; the sprite still draws while on-screen.
	var plumes_on := on_screen and not crowded
	if plumes_on != _lod_visible:
		_lod_visible = plumes_on
		if not _docked:   # docked escorts manage their own emitting via set_docked — don't fight it
			for p: CPUParticles2D in _plumes:
				if is_instance_valid(p):
					p.emitting = plumes_on
	if on_screen:
		# `_docked` escorts (Fleet Edit / mothership) never have their plumes emit-toggled off by `crowded`
		# above (see the `if not _docked:` guard) — set_docked()/_reenable_plumes() keep them permanently
		# emitting so a formation always reads as "powered on". But this rotation-glue block used to gate on
		# `plumes_on` (on_screen AND not crowded) just like the emit toggle, so once the arena's alive count
		# crossed PLUME_LOD_COUNT, a docked escort's plumes kept firing (never turned off) while their
		# DIRECTION silently froze at whatever it last was — often the raw, un-rotated creep_layout.cfg
		# dir_angle if the escort had never gotten a single on-screen+uncrowded tick since spawning off the
		# annulus. User bug report: bee/diver fleet escorts' thrust always pointing straight down the SCREEN
		# regardless of which way the formation was actually flying — bee/diver's own points are ALL authored
		# near dir_angle=90° (straight "down" in un-rotated body space, see creep_layout.cfg), so a frozen,
		# never-rotated plume is indistinguishable from "always down". Docked escorts must keep rotating in
		# lockstep with the (always-emitting) plume, same as they're exempted from the emit toggle.
		if (plumes_on or _docked) and not _plumes.is_empty():
			# Glue plume emitters to the sprite: same rotation AND scale as the drawn sprite (draw_set_transform
			# rotates/scales the sprite but not child nodes, so we mirror it here).
			_update_plumes()
			var vrot := _spin if behavior == "centipede" else _facing
			# Only re-rotate the emitters when the rotation actually moved (skips the per-frame .rotated() churn
			# for the hundreds of near-static swarm enemies that dominate the node count).
			if not _plume_vrot_init or absf(angle_difference(vrot, _plume_vrot_applied)) > 0.01:
				_plume_vrot_init = true
				_plume_vrot_applied = vrot
				for p: CPUParticles2D in _plumes:
					if is_instance_valid(p):
						p.position  = (p.get_meta("base_pos") as Vector2).rotated(vrot)
						p.direction = (p.get_meta("base_dir") as Vector2).rotated(vrot)
		_update_vortex_xform()   # glue vortexes to the sprite (position + scale + rotation)
		_update_led_xform()     # glue LEDs to the sprite (position + scale + rotation)
	if _has_eye:
		_update_eye(delta)
	if not _tent_template.is_empty():
		_update_tentacle(delta)
	if behavior == "centipede":
		_update_centipede_chain()   # body trails the head's final (post-knockback) position
	if on_screen:
		queue_redraw()   # bob/squash/facing animate continuously (skipped off-screen — last frame persists)

## Slide the tracking eye toward the player within its socket. _eye_off is in local (pre-rotation) px,
## relative to the socket center, smoothed so the gaze eases rather than snaps.
func _update_eye(delta: float) -> void:
	if _draw_size == Vector2.ZERO:
		return
	var rot := _spin if behavior == "centipede" else _facing
	var to_world := _player_pos() - global_position
	var target := Vector2.ZERO
	if to_world.length() > 1.0:
		var dir_local := to_world.normalized().rotated(-rot)   # gaze direction in the sprite's local frame
		target = Vector2(dir_local.x * _eye_range.x * _draw_size.x, dir_local.y * _eye_range.y * _draw_size.y)
	_eye_off = _eye_off.lerp(target, clampf(EYE_TRACK_SPEED * delta, 0.0, 1.0))

# ── Tentacles: build the segment template + one instance per [tentaclepoints] entry. ──
func _load_tentacle() -> void:
	_tent_template.clear()
	_tents.clear()
	_tent_init = false
	# 2026-08-15 bug fix ("cent có 2 tail, 1 node body thừa, không đầu, di chuyển quỹ đạo khác"): this used to
	# run for EVERY enemy and infer tentacle segments purely from creep_layout.cfg's "parent" field matching
	# this enemy's icon basename — but "parent" is ALSO how Creep Edit's CHAIN feature (centipede-behavior
	# Head/Body/Tail) organizes its own Layers panel hierarchy (e.g. "cent body"/"cent tail" both have
	# "parent": "cent head"), a completely different, unrelated use of the same field. Any chain-type creep
	# therefore had its own Body/Tail misread as "tentacle segments" of its Head and got a SECOND, bogus
	# tentacle chain built + drawn every frame (own forward-kinematics wave/drag motion, headless — hence
	# looking like a stray body+tail with no head, drifting on its own trajectory next to the real chain).
	# Tentacles are only ever real for `behavior == "squid"` (see arena_wave_director.gd's "squid" def,
	# icon "Squid-body.png", children "squid-1".."squid-8") — gate on that instead of inferring from "parent".
	if behavior != "squid":
		return
	if _icon.is_empty() or _draw_size == Vector2.ZERO:
		return
	var cfg := _creep_layout()
	if cfg == null or not cfg.has_section("creeps"):
		return
	var body_name := _icon.get_file().get_basename()
	var keys := cfg.get_section_keys("creeps")
	# Resolve the body's actual creep key (case-insensitive — editor keys keep the file's case).
	var body_key := ""
	for k: String in keys:
		if k.to_lower() == body_name.to_lower():
			body_key = k
			break
	if body_key == "":
		return
	var body_eo: Dictionary = cfg.get_value("creeps", body_key, {})
	var body_pos: Vector2  = body_eo.get("pos",  Vector2(480.0, 380.0))
	var body_size: Vector2 = body_eo.get("size", Vector2(60.0, 60.0))
	if body_size.x <= 0.0:
		return
	var body_center := body_pos + body_size * 0.5
	# Config-space → in-game scale, so the tentacle tracks whatever size the body is drawn at.
	var s := _draw_size.x / body_size.x
	# Collect children parented to the body, ordered by name (squid-1, squid-2, … = root → tip).
	var child_keys: Array = []
	for k: String in keys:
		var eo: Dictionary = cfg.get_value("creeps", k, {})
		if String(eo.get("parent", "")).to_lower() == body_key.to_lower():
			child_keys.append(k)
	if child_keys.is_empty():
		return
	child_keys.sort()
	# ── Template: per-segment rest angle (body-local 0° frame) + gap, relative to the anchor (seg 0). ──
	var anchor_center := Vector2.ZERO
	var prev_center := Vector2.ZERO
	for i: int in child_keys.size():
		var eo: Dictionary = cfg.get_value("creeps", child_keys[i], {})
		var seg_path := String(eo.get("path", ""))
		var seg_src := _resolve_sprite(seg_path)   # HD segment if available
		var tex := load(seg_src) as Texture2D
		if tex == null and seg_src != seg_path:
			tex = load(seg_path) as Texture2D       # HD failed → standard segment
		if tex == null:
			continue
		var pos: Vector2 = eo.get("pos",  body_pos)
		var sz: Vector2  = eo.get("size", Vector2(10.0, 10.0))
		var center := pos + sz * 0.5
		var gap := 0.0
		var rest_ang := 0.0
		if _tent_template.is_empty():
			anchor_center = center   # seg 0 is the anchor
		else:
			var d := center - prev_center
			gap = maxf(d.length() * s, 0.5)
			rest_ang = d.angle()    # joint direction in the body-local frame (template's 0°)
		_tent_template.append({"tex": tex, "size": sz * s, "gap": gap, "rest_ang": rest_ang})
		prev_center = center
	if _tent_template.is_empty():
		return
	# ── Instances: one per tentacle point; fall back to the template's native placement if none. ──
	var tps: Array = cfg.get_value("tentaclepoints", body_key, [])
	const SS_ORIGIN := Vector2(15.0, 8.0)
	if not tps.is_empty():
		for ti: int in tps.size():
			var tn: Dictionary = tps[ti]
			var tn_oc: Vector2 = (tn.get("pos", Vector2.ZERO) as Vector2) + SS_ORIGIN
			_tents.append({
				"base_off": (tn_oc - body_center) * s,
				"dir":      float(tn.get("dir_angle", 0.0)),
				"phase":    randf() * TAU,
				"wrap":     1.0 if ti % 2 == 0 else -1.0,   # alternate curl direction → tentacles grasp from both sides
				"pts":      [],
			})
	else:
		_tents.append({
			"base_off": (anchor_center - body_center) * s,   # native single tentacle at the placed anchor
			"dir":      0.0,
			"phase":    randf() * TAU,
			"wrap":     1.0,
			"pts":      [],
		})
	# Local angle of the tentacle side (centroid of the instance anchors) — the squid aims this at the player.
	var sum := Vector2.ZERO
	for inst: Dictionary in _tents:
		sum += inst["base_off"] as Vector2
	if not _tents.is_empty():
		sum /= float(_tents.size())
	_tent_front_ang = sum.angle() if sum.length() > 0.5 else 0.0

# ── Tentacles: forward kinematics per instance. Root pinned; joint = rest angle + traveling wave + drag. ──
func _update_tentacle(delta: float) -> void:
	if _tent_template.is_empty() or _tents.is_empty():
		return
	var n := _tent_template.size()
	var rot := _facing
	if not _tent_init:
		_tent_prev_pos = global_position
		_tent_vel = Vector2.ZERO
		_tent_phase = 0.0
		_tent_init = true
	_tent_phase += delta
	# Smoothed body velocity drives the trailing drag (computed here — _prev_pos was already updated upstream).
	var vel := (global_position - _tent_prev_pos) / maxf(delta, 0.0001)
	_tent_prev_pos = global_position
	_tent_vel = _tent_vel.lerp(vel, clampf(8.0 * delta, 0.0, 1.0))
	var speed := _tent_vel.length()
	var drag_strength := TENT_DRAG_GAIN * clampf(speed / TENT_DRAG_REF, 0.0, 1.0)
	var trail_ang := (-_tent_vel).angle() if speed > 1.0 else 0.0
	# Wrap blend: when the squid is clinging, the tentacles curl around the ship instead of trailing.
	var wrapping := behavior == "squid" and _squid_attached
	_tent_attach = lerpf(_tent_attach, 1.0 if wrapping else 0.0, clampf(4.0 * delta, 0.0, 1.0))
	var ship := _player_pos() if _tent_attach > 0.001 else Vector2.ZERO
	for inst: Dictionary in _tents:
		var pts: Array = inst["pts"]
		if pts.size() != n:
			pts.resize(n)
			inst["pts"] = pts
		var base_rot: float = rot + float(inst["dir"])   # whole chain rotates by the point's Dir
		var inst_phase: float = float(inst["phase"])
		var wrap_sign: float = float(inst.get("wrap", 1.0))
		# Root segment — rigidly anchored at the point's body-relative position (rotates with facing).
		pts[0] = global_position + (inst["base_off"] as Vector2).rotated(rot)
		for k in range(1, n):
			var base_a: float = float(_tent_template[k]["rest_ang"]) + base_rot
			var taper := 0.3 + 0.7 * float(k) / float(n - 1)   # root stiff, tip floppy
			var wave := TENT_WAVE_AMP * taper * sin(_tent_phase * TENT_WAVE_FREQ + inst_phase - float(k) * TENT_WAVE_K)
			var drag := angle_difference(base_a, trail_ang) * drag_strength * taper if speed > 1.0 else 0.0
			var a := base_a + (wave + drag) * (1.0 - 0.7 * _tent_attach)
			if _tent_attach > 0.001:
				# Curl around the ship: head tangentially around it (perpendicular to the radius), biased
				# slightly inward so the tentacle hugs the hull rather than orbiting at a fixed distance.
				var r := ship - (pts[k - 1] as Vector2)
				var wrap_a := r.angle() + wrap_sign * (PI * 0.5 - 0.35)
				a = lerp_angle(a, wrap_a, _tent_attach * taper)
			pts[k] = (pts[k - 1] as Vector2) + Vector2(cos(a), sin(a)) * float(_tent_template[k]["gap"])

# ── Tentacles: draw every instance, tip → root, so the root paints last (just under the body). ──
func _draw_tentacle(alpha: float) -> void:
	var n := _tent_template.size()
	if n == 0:
		return
	for inst: Dictionary in _tents:
		var pts: Array = inst["pts"]
		if pts.size() < n:
			continue
		for idx in range(n - 1, -1, -1):
			var seg: Dictionary = _tent_template[idx]
			var tex: Texture2D = seg["tex"]
			var sz: Vector2 = seg["size"]
			var p: Vector2 = pts[idx]
			# Tangent along the tentacle, root → tip (sprite's +x axis points outward toward the tip).
			var ang: float
			if n == 1:
				ang = (p - global_position).angle()
			elif idx == 0:
				ang = ((pts[1] as Vector2) - p).angle()
			elif idx == n - 1:
				ang = (p - (pts[idx - 1] as Vector2)).angle()
			else:
				ang = ((pts[idx + 1] as Vector2) - (pts[idx - 1] as Vector2)).angle()
			draw_set_transform(p - global_position, ang, Vector2.ONE)
			draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _init_behavior() -> void:
	var to := _player_pos() - global_position
	_aim = to.normalized() if to.length() > 0.01 else Vector2.UP
	if _composed:
		_cm_orbit_r = maxf(20.0, to.length())
		_cm_orbit_a = (-to).angle()
		_cm_target = _player_pos() + _rand_offset(_view().length() * 0.35)
		_tele_anchor = global_position
		return
	match behavior:
		"spiral":
			_orbit_r = global_position.distance_to(_player_pos())
			_orbit_r0 = _orbit_r
			_orbit_ang = (global_position - _player_pos()).angle()
			_spiral_dir = 1.0   # always clockwise (Y-down screen → increasing angle = clockwise)
			_scatter_target = _player_pos()   # spiral: orbit center anchor; drifts toward player each frame
		"vortex_dive":
			_orbit_r = global_position.distance_to(_player_pos())
			_orbit_r0 = _orbit_r
			_orbit_ang = (global_position - _player_pos()).angle()
			_vortex_sign = 1.0 if randf() < 0.5 else -1.0   # per-enemy swirl direction (CW/CCW), picked once so it doesn't flicker
		"steer_chaser":
			_vortex_sign = 1.0 if randf() < 0.5 else -1.0   # per-enemy swirl direction, picked once so it doesn't flicker
		"scatter", "bomber":
			_scatter_target = _player_pos() + _rand_offset(_view().length() * 0.35)
		"jump_diag":
			_jump_interval = randf_range(0.5, 1.5)
		"centipede":
			_centi_dir = _aim.angle()   # head starts pointed at the player
		"teleport":
			_tele_anchor = global_position
			_timer = 0.0
		"patrol":
			_timer = 0.0   # _aim (set above) is the captured straight-line heading; never re-aimed

# Manual movement integrator — replaces CharacterBody2D._move_step(). Behaviors set `velocity` (px/s) then
# call this. Enemy-vs-enemy separation is NOT done here (it's the manager's spatial-hash pass); this is pure motion.
func _move_step() -> void:
	global_position += velocity * get_process_delta_time()

# The manager's separation pass reads this: the enemy's push-apart core radius, or 0 when it shouldn't separate
# (no_collide projectiles, dying, or docked). 0 = skip this enemy entirely in the separation grid.
func separation_radius() -> float:
	return (_radius * CORE_FRAC) if _separates else 0.0

func _tick_behavior(delta: float) -> void:
	var pp := _player_pos()
	var to := pp - global_position
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector2.UP
	if _composed:
		_tick_move_logic(delta, dist, dir, pp)
		_tick_shoot_logic(delta, dist, dir)
		return
	match behavior:
		"chase", "boss_stub":
			# A boss with a named moveset runs that instead of the plain chase below. Layered on top of
			# "boss_stub" rather than being its own `behavior` so it keeps every boss exemption already
			# keyed off that string (HP/speed tuning, the "boss" group, no LIFETIME_MAX despawn, no
			# off-screen recycling in the v2 director).
			if _boss_move == "metalfly":
				_tick_metalfly(delta, dist, dir)
				return
			# Recycle a normal chaser once the player has outrun it far past the screen (bosses never culled).
			if behavior == "chase" and dist > CHASE_CULL:
				_release_all_docks()   # a Fleet Edit carrier (e.g. fly/bee/bug slots) must free its escorts here
				queue_free()
				return
			# Pirate flee: once below the HP threshold, turn tail and run from the player at _flee_speed.
			if _flee_speed > 0.0 and hp <= hp_max * _flee_below:
				velocity = -dir * _flee_speed
			else:
				# Flank/envelop: bias the seek direction sideways (fades to 0 near the player so the arc still
				# closes for contact). +bias enemies wrap one way, −bias the other → the crowd surrounds you.
				var steer := dir
				if _flank_bias != 0.0:
					var fade := clampf((dist - FLANK_FADE_NEAR) / (FLANK_FADE_FAR - FLANK_FADE_NEAR), 0.0, 1.0)
					var perp := Vector2(-dir.y, dir.x)
					steer = (dir + perp * _flank_bias * fade).normalized()
				velocity = steer * speed
			_move_step()
		"steer_chaser":   # spawn_mode_2 (flies) — vortex/spiral seek: swirl fades to a direct dive up close
			var vperp := Vector2(-dir.y, dir.x) * _vortex_sign
			var vfade := clampf((dist - VORTEX_FADE_NEAR) / (VORTEX_FADE_FAR - VORTEX_FADE_NEAR), 0.0, 1.0)
			var vsteer := (dir + vperp * VORTEX_TANGENT_RATIO * vfade).normalized()
			velocity = vsteer * speed
			_move_step()
		"steer_flanker":   # spawn_mode_2 — seeks a point ahead of the player, predicted from the v2 director's tracked velocity
			var target := pp
			var wd := get_tree().get_first_node_in_group("wave_director")
			if wd != null and wd.has_method("player_velocity"):
				var pvel: Vector2 = wd.call("player_velocity")
				target = pp + pvel * FLANK_PREDICT_T
			var fdir := (target - global_position).normalized() if global_position.distance_to(target) > 0.01 else dir
			velocity = fdir * speed
			_move_step()
		"steer_kiter":   # spawn_mode_2 — approach past KITE_R_ATTACK, hold+fire in the band, flee below KITE_R_FLEE
			if dist > KITE_R_ATTACK:
				velocity = dir * speed
			elif dist > KITE_R_FLEE:
				velocity = Vector2.ZERO
				if _fire_ready(KITE_FIRE_INTERVAL) and _mgr != null:
					_play_sfx(SFX_ZAP)
					_mgr.spawn_bullet(global_position, dir * KITE_BULLET_SPEED, KITE_BULLET_DMG, self, "jetfighter")
			else:
				velocity = -dir * speed
			_move_step()
		"steer_charger":   # spawn_mode_2 — approach slow → lock aim + telegraph (pulsing flash) → dash straight
			match _phase:
				0:   # approach
					velocity = dir * CHARGE_APPROACH_SPEED
					_move_step()
					if dist <= CHARGE_LOCK_RANGE:
						_aim = dir
						_timer = 0.0
						_phase = 1
				1:   # telegraph — locked aim, pulsing warning flash
					velocity = Vector2.ZERO
					_flash_color = KILL_FLASH_COLOR
					_flash = 0.5 + 0.5 * sin(_t * CHARGE_PULSE_FREQ)
					_timer += delta
					if _timer >= CHARGE_TELEGRAPH_T:
						_timer = 0.0
						_phase = 2
				2:   # dash — straight line along the locked aim
					velocity = _aim * CHARGE_DASH_SPEED
					_move_step()
					_timer += delta
					if _timer >= CHARGE_DASH_T:
						_timer = 0.0
						_phase = 0
		"mothership":   # carrier: slow advance → on damage, turn tail, flee, release & rebuild the escort
			_tick_mothership(delta)
		"patrol":   # straight flyby across the screen along the captured heading; no tracking
			velocity = _aim * speed
			_move_step()
			if dist > PATROL_CULL:
				_release_all_docks()   # a Fleet Edit carrier riding this behavior (e.g. Sentinel Fleet) must
				queue_free()           # free its escorts here — this bypasses _despawn_stale()/_die()
		"teleport":   # blink TELE_DIST toward the player every TELE_INTERVAL; float adrift between blinks
			_timer += delta
			if _timer >= TELE_INTERVAL:
				_timer = 0.0
				var from := global_position
				global_position += dir * minf(TELE_DIST, dist)
				_tele_anchor = global_position
				_spawn_t = 0.0   # replay the spawn pop at the landing spot
				_spawn_warp(from, false)             # space CONTRACTS where it left
				_spawn_warp(global_position, true)   # space EXPANDS where it arrives
			else:
				# Idle float: a slow elliptical drift around the landing anchor (per-enemy phase desyncs the crowd).
				global_position = _tele_anchor + Vector2(
					sin(_t * TELE_FLOAT_FREQ + _bob_phase),
					cos(_t * TELE_FLOAT_FREQ * 1.3 + _bob_phase)) * TELE_FLOAT_RADIUS
		"swarm":   # blob unit: ZOOM straight through the player @400 (then despawn), or CHASE slowly @speed
			if _swarm_mode == "zoom":
				velocity = _aim * SWARM_ZOOM_SPEED
				_move_step()
				if dist > SWARM_ZOOM_CULL:
					_release_all_docks()   # a Fleet Edit carrier (e.g. "swarm" slot) must free its escorts here
					queue_free()   # flew off the far side — vanish (no XP/explosion; it wasn't killed)
			else:
				velocity = dir * speed
				_move_step()
		"swarm_loop":   # boomerang swarm: charge the player, fly out to a big radius, bank around gracefully, charge again — until killed
			if _phase == 0:   # CHARGE: dive along the captured aim, through the player and out to the range
				if _aim == Vector2.ZERO:
					_aim = dir
				velocity = _aim * SWARM_LOOP_DIVE_SPEED
				_move_step()
				if dist > SWARM_LOOP_RANGE:
					_phase = 1
					_timer = 0.0
			elif _phase == 1:   # HOLD out past the range for >=5s, drifting slowly outward
				_timer += delta
				velocity = _aim * SWARM_LOOP_DRIFT_SPEED
				_move_step()
				if _timer >= SWARM_LOOP_WAIT:
					_phase = 2
			else:   # BANK: graceful capped turn back toward the player, then charge again
				var na := _approach_angle(_aim.angle(), dir.angle(), SWARM_LOOP_TURN * delta)
				_aim = Vector2(cos(na), sin(na))
				velocity = _aim * SWARM_LOOP_COAST_SPEED
				_move_step()
				if _aim.dot(dir) > 0.92:
					_phase = 0   # pointed back at the player → charge again
		"centipede":
			# Head chases the player with a capped turn rate (Viper SNAKE_TURN); the body trails it
			# (see _update_centipede_chain). `speed` is set to 75% of the Viper in ENEMY_DEFS.
			var desired := (pp - global_position).angle()
			_centi_dir = _approach_angle(_centi_dir, desired, CENTI_TURN * delta)
			velocity = Vector2(cos(_centi_dir), sin(_centi_dir)) * speed
			_move_step()
			queue_redraw()
		"dash":   # dive along the captured aim; once it flies off-view, re-aim and dive back
			if dist > RETURN_DIST:
				_aim = dir
			velocity = _aim * speed
			_move_step()
		"spiral":   # diver — spiral in; center drifts (not snaps) toward player → player can pull away
			if _phase == 0:
				_scatter_target = _scatter_target.move_toward(pp, SPIRAL_CENTER_SPEED * delta)
				var ang_speed := (speed / maxf(40.0, _orbit_r)) * _spiral_dir
				_orbit_ang += ang_speed * delta
				var spiral_rate := SPIRAL_SHRINK * (_orbit_r0 / ORBIT_SPAWN_REF_R)
				_orbit_r = maxf(8.0, _orbit_r - spiral_rate * delta)
				global_position = _scatter_target + Vector2(cos(_orbit_ang), sin(_orbit_ang)) * _orbit_r
				if _orbit_r <= 8.0:
					_phase = 1
					_aim = dir   # aim-once at the moment of committing to the dash
			else:   # dash: fly straight at the captured aim; re-aim only if it overshoots far off-screen
				if dist > RETURN_DIST:
					_aim = dir
				velocity = _aim * speed
				_move_step()
		"vortex_dive":   # dragonfly — swirls inward toward the player on a guaranteed-shrinking radius (see
						 # VORTEX_SHRINK's comment for why this is a deterministic decay, not a free pursuit-
						 # curve steer); once the radius reaches VORTEX_DIVE_TRIGGER it commits a straight
						 # overshoot dash, then curls back into the vortex re-homing on the player's CURRENT
						 # position instead of dashing off forever.
			if _phase == 0:
				_orbit_ang += (speed / maxf(20.0, _orbit_r)) * delta * _vortex_sign
				var shrink_rate := VORTEX_SHRINK * (_orbit_r0 / ORBIT_SPAWN_REF_R)
				_orbit_r = maxf(VORTEX_DIVE_TRIGGER, _orbit_r - shrink_rate * delta)
				var target := pp + Vector2(cos(_orbit_ang), sin(_orbit_ang)) * _orbit_r
				var to_target := target - global_position
				velocity = (to_target.normalized() if to_target.length() > 0.01 else dir) * speed
				_move_step()
				if _orbit_r <= VORTEX_DIVE_TRIGGER:
					_phase = 1
					_timer = 0.0
					_aim = dir
			else:
				velocity = _aim * (speed * VORTEX_DIVE_SPEED_MULT)
				_move_step()
				_timer += delta
				if _timer >= VORTEX_OVERSHOOT_TIME:
					# Overshot past the player — curl back into the vortex, spiraling in fresh from wherever
					# the dash actually ended up (not a jarring snap back to the original spawn radius).
					_phase = 0
					_orbit_r = global_position.distance_to(pp)
					_orbit_ang = (global_position - pp).angle()
		"jump":   # octopus — wait, then leap toward the player, repeat
			_jump_tick(delta, dir, false)
		"jump_diag":   # spider — leap along the nearest 45° diagonal
			_jump_tick(delta, dir, true)
		"squid":
			# Leap toward the player (octopus jump rhythm) led by the tentacles; latch on at reach, then cling.
			_face_squid(pp, delta)   # orient so the tentacle side leads (general facing block skips "squid")
			if _squid_attached:
				var tgt := pp + _squid_attach_off
				global_position = global_position.lerp(tgt, clampf(8.0 * delta, 0.0, 1.0))   # ride with the ship
				velocity = Vector2.ZERO
				if dist > (_radius + SQUID_ATTACH_RANGE) * 3.0:
					_squid_detach()   # player got away (e.g. dashed off) — resume the chase
			else:
				_jump_tick(delta, dir, false)   # octopus-style: wait, then leap at the player, repeat
				if global_position.distance_to(pp) <= _radius + SQUID_ATTACH_RANGE:
					_squid_attach(pp)
		"scatter":   # fly — wander to random points around the player
			if global_position.distance_to(_scatter_target) < 24.0 or _t - _timer > 1.0:
				_scatter_target = pp + _rand_offset(_view().length() * 0.35)
				_timer = _t
			velocity = (_scatter_target - global_position).normalized() * speed
			_move_step()
		"swarm_dive":   # bee/bug/swarm — drift toward the player, pause, then dive through
			if _phase == 0:
				if _t < 1.2:
					velocity = dir * speed * 0.6
					_move_step()
				else:
					_phase = 1
					_aim = dir
			else:
				if dist > RETURN_DIST:
					_aim = dir
				velocity = _aim * speed * 1.6
				_move_step()
		"bee_dive":   # dive-bomber: approach to standoff, hover 1s, then dive with slight homing; loops until killed
			if _phase == 0:   # APPROACH at normal speed until within standoff range
				velocity = dir * speed
				_move_step()
				if dist <= BEE_STANDOFF:
					_phase = 1
					_timer = 0.0
			elif _phase == 1:   # PAUSE: hover in place, then commit the dive aim
				velocity = Vector2.ZERO
				_timer += delta
				if _timer >= BEE_PAUSE:
					_aim = dir
					_phase = 2
			else:   # DIVE: fast, steering toward the player with a capped turn (tracks a bit, not perfectly)
				var na := _approach_angle(_aim.angle(), dir.angle(), BEE_TURN * delta)
				_aim = Vector2(cos(na), sin(na))
				velocity = _aim * BEE_DIVE_SPEED
				_move_step()
				if dist > RETURN_DIST:
					_phase = 0   # overshot → loop back and re-approach
		"shooter":   # 1 bullet/sec (was a 4-shot burst, 1 per FP, 0.2s apart — jetfighter has 4 firepoints);
					 # flocks with other jetfighters (see JF_FLOCK_* consts above); always CLOSES the distance
					 # like a normal chase creep — no more holding range / retreating when the player gets close
					 # (explicit request: don't flee).
			var standoff_v := dir * speed
			var flock_v := Vector2.ZERO
			if _mgr != null and _mgr.has_method("jf_flock_valid") and bool(_mgr.call("jf_flock_valid")):
				var fc: Vector2 = _mgr.call("jf_flock_center")
				var to_flock := fc - global_position
				var fdist := to_flock.length()
				if fdist > JF_FLOCK_HOLD_R:
					flock_v = (to_flock / fdist) * speed
			var steer := standoff_v + flock_v * JF_FLOCK_WEIGHT
			if steer.length() > speed:
				steer = steer.normalized() * speed
			velocity = steer
			_move_step()
			var sh_total := 1
			if _burst_shots == 0 and _fire_ready(1.0):
				_burst_shots = sh_total
				_burst_t = 0.0
				_play_sfx(SFX_ZAP)
			if _burst_shots > 0:
				_burst_t -= delta
				if _burst_t <= 0.0:
					var fp_idx := sh_total - _burst_shots
					_mgr.spawn_bullet(_muzzle(fp_idx), dir * 280.0, 5, self, "jetfighter")
					_burst_shots -= 1
					if _burst_shots > 0:
						_burst_t = 0.2
		"sentinel":   # always closes toward the player (no standoff/flee — explicit request); fires a fan TOWARD the player from FP 0 while approaching
			velocity = dir * speed
			_move_step()
			if _fire_ready(2.0):
				_play_sfx(SFX_ZAP)
				var muzzle := _muzzle(0)
				var base := dir.angle()
				for k in 5:
					var a := base + deg_to_rad(lerpf(-24.0, 24.0, float(k) / 4.0))
					_mgr.spawn_bullet(muzzle, Vector2(cos(a), sin(a)) * 260.0, 5, self)
		"beamer":
			_standoff(dist, dir, 380.0)
			_beamer_tick(delta, dir)
		"bomber":   # bombing-wanderer — roam near the player, drop bombs from FP 0
			if global_position.distance_to(_scatter_target) < 30.0 or _t - _timer > 1.5:
				_scatter_target = pp + _rand_offset(260.0)
				_timer = _t
			velocity = (_scatter_target - global_position).normalized() * speed
			_move_step()
			if _fire_ready(3.0) and _mgr != null and _mgr.has_method("throw_bomb"):
				_mgr.throw_bomb(_muzzle(0))
		"missile":   # launcher — fan BEHIND launcher → hover → boomerang at player
			_standoff(dist, dir, 460.0)
			if _fire_ready(2.5) and (_missile_volley == null or not is_instance_valid(_missile_volley)):
				var ml_total := maxi(1, _fp_fracs.size())
				var muzzles: Array = []
				for k in ml_total:
					muzzles.append(_muzzle(k))
				var vol := _MissileVolley.new()
				if _mgr != null and is_instance_valid(_mgr):
					_mgr.add_child(vol)
				else:
					get_parent().add_child(vol)
				vol.global_position = Vector2.ZERO
				vol.launch(muzzles, -dir, self)
				_missile_volley = vol
		"bomb":   # falls toward the player; explodes on contact/death
			velocity = dir * speed
			_move_step()
		"thrown_bomb":   # fast straight projectile aimed at the player; explodes on contact, fizzles at range
			velocity = _aim * speed
			_move_step()
			_orbit_r += speed * delta
			if _orbit_r >= THROWN_BOMB_RANGE:
				_die()
		"dummy":
			pass

# ── Composed Move/Shoot (Creep Info panel overrides) ────────────────────────────────────────────────
## Independent movement — one of MOVE_LOGICS, or "" (shouldn't reach here; _composed requires move or
## shoot non-default, but a shoot-only override leaves move_logic "" — treated as "stationary").
func _tick_move_logic(delta: float, dist: float, dir: Vector2, pp: Vector2) -> void:
	match _move_logic:
		"chase":
			velocity = dir * speed
			_move_step()
		"standoff":
			_standoff(dist, dir, COMPOSED_STANDOFF_RANGE)
		"orbit":   # holds at its spawn radius — circles, doesn't tighten or dive
			_cm_orbit_a += (speed / maxf(20.0, _cm_orbit_r)) * delta
			global_position = pp + Vector2(cos(_cm_orbit_a), sin(_cm_orbit_a)) * _cm_orbit_r
		"spiral":   # tightens inward like the classic diver, but HOLDS at a minimum radius instead of dashing
			_cm_orbit_a += (speed / maxf(20.0, _cm_orbit_r)) * delta
			_cm_orbit_r = maxf(80.0, _cm_orbit_r - 20.0 * delta)
			global_position = pp + Vector2(cos(_cm_orbit_a), sin(_cm_orbit_a)) * _cm_orbit_r
		"patrol":   # straight flyby along the heading captured at spawn (_aim) — never re-aims
			velocity = _aim * speed
			_move_step()
			if dist > PATROL_CULL:
				_release_all_docks()
				queue_free()
		"teleport":   # blink TELE_DIST toward the player every TELE_INTERVAL; idle-float between blinks
			_cm_timer += delta
			if _cm_timer >= TELE_INTERVAL:
				_cm_timer = 0.0
				var from := global_position
				global_position += dir * minf(TELE_DIST, dist)
				_tele_anchor = global_position
				_spawn_t = 0.0
				_spawn_warp(from, false)
				_spawn_warp(global_position, true)
			else:
				global_position = _tele_anchor + Vector2(
					sin(_t * TELE_FLOAT_FREQ + _bob_phase),
					cos(_t * TELE_FLOAT_FREQ * 1.3 + _bob_phase)) * TELE_FLOAT_RADIUS
		"roam":   # wanders to random points near the player, no fixed range
			if global_position.distance_to(_cm_target) < 24.0 or _t - _cm_timer > 1.0:
				_cm_target = pp + _rand_offset(_view().length() * 0.35)
				_cm_timer = _t
			velocity = (_cm_target - global_position).normalized() * speed
			_move_step()
		"stationary", _:   # also the fallback for a shoot-only override (move_logic left "")
			velocity = Vector2.ZERO

## Independent ranged attack — one of SHOOT_LOGICS. "none" = melee/contact-only, same as most classic
## non-shooting behaviors (chase, patrol, ...).
func _tick_shoot_logic(delta: float, dist: float, dir: Vector2) -> void:
	match _shoot_logic:
		"none":
			pass
		"burst":   # 1 shot per fire-point (up to 4), 0.2s apart, 1s between bursts — same math as "shooter"
			var sh_total := maxi(1, _fp_fracs.size())
			if _cs_burst_shots == 0 and _fire_ready(1.0):
				_cs_burst_shots = sh_total
				_cs_burst_t = 0.0
				_play_sfx(SFX_ZAP)
			if _cs_burst_shots > 0:
				_cs_burst_t -= delta
				if _cs_burst_t <= 0.0 and _mgr != null and is_instance_valid(_mgr):
					var fp_idx := sh_total - _cs_burst_shots
					_mgr.spawn_bullet(_muzzle(fp_idx), dir * 280.0, 5, self)
					_cs_burst_shots -= 1
					if _cs_burst_shots > 0:
						_cs_burst_t = 0.2
		"fan":   # a 5-bullet fan toward the player every 2s — same math as "sentinel"
			if _fire_ready(2.0) and _mgr != null and is_instance_valid(_mgr):
				_play_sfx(SFX_ZAP)
				var muzzle := _muzzle(0)
				var base := dir.angle()
				for k in 5:
					var a := base + deg_to_rad(lerpf(-24.0, 24.0, float(k) / 4.0))
					_mgr.spawn_bullet(muzzle, Vector2(cos(a), sin(a)) * 260.0, 5, self)
		"beam":
			# Reuses "beamer"'s own charge-cycle machine (_phase/_timer) — safe here because every move-logic
			# above uses its own dedicated _cm_* vars instead, so nothing else touches _phase/_timer while
			# a move-logic and a shoot-logic are running concurrently (the classic system only ran one).
			_beamer_tick(delta, dir)

# ── Mothership carrier ────────────────────────────────────────────────────────
## State machine: READY (advance) → on 50 dmg → TURN (50 rpm about-face) → FLEE (flee@120, release the 5
## docked escorts 1 per 0.5s) → WAIT (5s) → RESPAWN (rebuild 5 escorts, 1 per 2.5s) → READY. Escorts are
## pinned to the carrier (rotating with it) until released; released ones detach into free-flying chasers.
func _tick_mothership(delta: float) -> void:
	var pp := _player_pos()
	var to := pp - global_position
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector2.UP
	match _ms_state:
		MS_READY:
			_ms_aim_facing(dir, 4.0 * delta)   # face the player while advancing (so the about-face reads later)
			velocity = dir * MS_APPROACH_SPEED
			_move_step()
			# Timer-driven cycle: MS_READY_HOLD seconds after spawning / finishing a respawn, fire the next
			# flee/release/respawn — regardless of whether the carrier has taken any damage.
			if MS_CYCLE_ENABLED:
				_ms_timer += delta
				if _ms_timer >= MS_READY_HOLD:
					_ms_timer = 0.0
					_ms_state = MS_TURN
		MS_TURN:
			velocity = Vector2.ZERO
			if _ms_aim_facing(-dir, MS_TURN_RAD * delta):   # finished turning away from the player
				_ms_state = MS_FLEE
				_ms_timer = 0.0
				_ms_release_idx = 0
		MS_FLEE:   # flee ONLY while launching escorts — then hold so the rebuild stays on-screen
			_ms_aim_facing(-dir, MS_TURN_RAD * delta)
			velocity = -dir * MS_FLEE_SPEED
			_move_step()
			_ms_timer += delta
			while _ms_release_idx < _ms_dock.size() and _ms_timer >= MS_RELEASE_INTERVAL * float(_ms_release_idx + 1):
				_ms_release_child(_ms_release_idx)
				_ms_release_idx += 1
			if _ms_release_idx >= _ms_dock.size():
				_ms_state = MS_WAIT
				_ms_timer = 0.0
		MS_WAIT:   # hover at standoff (on-screen, mobile); rebuild begins MS_WAIT_AFTER_RELEASE s after launch
			_ms_aim_facing(dir, 4.0 * delta)
			_standoff(dist, dir, MS_REGROUP_DIST)
			_ms_timer += delta
			if _ms_timer >= MS_WAIT_AFTER_RELEASE:
				_ms_dock.clear()   # released escorts are free agents now — stop tracking them
				_ms_respawn_bays = _ms_build_respawn_bays()
				_ms_state = MS_RESPAWN
				_ms_timer = 0.0
				_ms_respawn_idx = 0
		MS_RESPAWN:   # hover at standoff; rebuild the escort one ship at a time (visible, not a sitting duck)
			_ms_aim_facing(dir, 4.0 * delta)
			_standoff(dist, dir, MS_REGROUP_DIST)
			_ms_timer += delta
			while _ms_respawn_idx < _ms_respawn_bays.size() and _ms_timer >= MS_RESPAWN_INTERVAL * float(_ms_respawn_idx + 1):
				_ms_respawn_one(_ms_respawn_idx)
				_ms_respawn_idx += 1
			if _ms_respawn_idx >= _ms_respawn_bays.size():
				_ms_state = MS_READY
				_ms_timer = 0.0     # start the MS_READY_HOLD countdown to the next release cycle
	_ms_update_dock_positions()

## Ease _facing toward the heading for `target_dir` (sprite north = travel dir), capped at max_step rad.
## Returns true once aligned within ~3.4°.
func _ms_aim_facing(target_dir: Vector2, max_step: float) -> bool:
	var tgt := target_dir.angle() + PI * 0.5
	_facing = _approach_angle(_facing, tgt, max_step)
	return absf(wrapf(tgt - _facing, -PI, PI)) <= 0.06

## Toggle docked state: docked escorts don't move, emit no plume, ignore collisions (vortex VFX stays on).
func set_docked(on: bool) -> void:
	_docked = on
	for p: CPUParticles2D in _plumes:
		if is_instance_valid(p):
			p.emitting = not on
			p.visible = not on
	if on:
		_separates = false            # docked escort rides the carrier — no separation
	elif not _no_collide:
		_separates = true

## Spawn one escort rigidly docked in this carrier; returns its dock-tracking entry. `keep_plumes` re-enables
## the escort's own thrust jets right after docking — used by generic Fleet formations (init_fleet_dock()),
## which never release/flee, so a permanently "powered down" look (mothership's default) would be wrong;
## mothership escorts keep the default (plumes off while docked, on when released — see set_docked()).
func _spawn_docked_child(id: String, base_off: Vector2, draw_w: float, rot_deg: float, keep_plumes: bool = false, dock_kind: String = "mothership") -> Dictionary:
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd == null:
		return {}
	var def: Dictionary = (wd.ENEMY_DEFS as Dictionary).get(id, {}).duplicate()
	if def.is_empty():
		return {}
	if draw_w > 0.0:
		def["draw_w"] = draw_w
	var c: Node = get_script().new()
	c.call("configure", id, _mgr, def)
	c.set("global_position", global_position + base_off.rotated(_facing))
	get_parent().add_child(c)
	c.set("_facing", _facing + deg_to_rad(rot_deg))
	c.set("_dock_kind", dock_kind)
	c.call("set_docked", true)
	if keep_plumes:
		c.call("_reenable_plumes")
	return {"node": c, "base_off": base_off, "rot": deg_to_rad(rot_deg)}

func _reenable_plumes() -> void:
	for p: CPUParticles2D in _plumes:
		if is_instance_valid(p):
			p.emitting = true
			p.visible = true

## Rigidly dock every OTHER unit of a generic (non-mothership) Fleet Edit formation onto this carrier. The
## carrier keeps running its own normal behavior/steering (whatever its own def authors — "di chuyển theo
## logic của creep"), and each escort is re-pinned to carrier.global_position + its authored offset (rotated
## with the carrier's live facing) every frame via _fleet_update_dock_positions(), so the whole squad glides
## as one rigid block instead of every unit chasing the player independently and scattering apart. Unlike
## mothership escorts, fleet escorts dock for the formation's entire lifetime — no release/flee/respawn cycle.
func init_fleet_dock(roster: Array) -> void:
	_fleet_dock.clear()
	for spec: Dictionary in roster:
		var e := _spawn_docked_child(String(spec["id"]), spec["base_off"] as Vector2, float(spec.get("draw_w", 0.0)), 0.0, true, "fleet")
		if not e.is_empty():
			# Per-escort randomized wander phase/freq (see FLEET_WANDER_* consts) — _fleet_update_dock_positions()
			# uses these so the formation reads as loosely held rather than a perfectly rigid welded frame, while
			# still fundamentally tracking the carrier's slot (speed-capped — see FLEET_MAX_SPEED_MULT).
			e["wander_freq"] = randf_range(FLEET_WANDER_FREQ_MIN, FLEET_WANDER_FREQ_MAX)
			e["wander_phase"] = randf() * TAU
			e["wander_t"] = 0.0
			_fleet_dock.append(e)

## Fleet-formation counterpart of _ms_update_dock_positions(): unlike mothership's exact instant snap, each
## escort CHASES its carrier-relative slot (+ a small continuous per-escort positional wander, own randomized
## freq/phase — "độ lệch vận tốc random nhỏ" so the formation looks naturally held together instead of bolted
## to an invisible rigid frame) but is velocity-capped at FLEET_MAX_SPEED_MULT × its own `speed` stat — it can
## never move faster than ~130% of its natural flight speed to close the gap, no matter how far the slot just
## moved (a sharp carrier turn sweeps a wide formation's outer slots through a big arc). Still fully recovers
## to its authored slot given enough time (the wander is bounded, zero-mean) so the formation shape never
## actually drifts apart — it just can't warp there instantly.
func _fleet_update_dock_positions(delta: float) -> void:
	var i := _fleet_dock.size() - 1
	while i >= 0:
		var e: Dictionary = _fleet_dock[i]
		var n = e.get("node")
		if n == null or not is_instance_valid(n):
			_fleet_dock.remove_at(i)
			i -= 1
			continue
		if n.get("_docked"):   # not bool(...) — n.get() with no default can return null, and bool(null) crashes
			var t: float = float(e.get("wander_t", 0.0)) + delta
			e["wander_t"] = t
			var freq: float = float(e.get("wander_freq", 1.0))
			var phase: float = float(e.get("wander_phase", 0.0))
			var wander := Vector2(cos(t * freq + phase), sin(t * freq * 0.7 + phase)) * FLEET_WANDER_AMP
			var target: Vector2 = global_position + (e["base_off"] as Vector2).rotated(_facing) + wander
			var cur: Vector2 = n.get("global_position")
			var to_target := target - cur
			var max_step: float = float(n.get("speed")) * FLEET_MAX_SPEED_MULT * delta
			if to_target.length() > max_step:
				cur += to_target.normalized() * max_step
			else:
				cur = target
			n.set("global_position", cur)
			n.set("_facing", _facing)
		i -= 1

## Called by the carrier deploy: store the escort roster + dock the initial squadron.
func init_mothership(roster: Array) -> void:
	_ms_roster = roster
	_ms_state = MS_READY
	_ms_timer = 0.0
	_ms_dock.clear()
	for spec: Dictionary in roster:
		var e := _spawn_docked_child(String(spec["id"]), spec["base_off"] as Vector2, float(spec.get("draw_w", 0.0)), float(spec.get("rot", 0.0)))
		if not e.is_empty():
			_ms_dock.append(e)
	print("[MOTHERSHIP] init: roster=", roster.size(), " docked=", _ms_dock.size(), " cycle_enabled=", MS_CYCLE_ENABLED, " mother_draw_w=", _force_draw_w)

## Release docked escort i — it detaches into a free-flying chaser.
func _ms_release_child(i: int) -> void:
	if i < 0 or i >= _ms_dock.size():
		return
	var n = (_ms_dock[i] as Dictionary).get("node")
	if n != null and is_instance_valid(n):
		n.call("set_docked", false)

## Order the roster into the authored respawn sequence (the two pros8 map to the two pros8 bays).
func _ms_build_respawn_bays() -> Array:
	var pool: Array = _ms_roster.duplicate()
	var out: Array = []
	for id: String in MS_RESPAWN_ORDER:
		for j in pool.size():
			if String((pool[j] as Dictionary)["id"]) == id:
				out.append(pool[j])
				pool.remove_at(j)
				break
	return out

func _ms_respawn_one(i: int) -> void:
	if i < 0 or i >= _ms_respawn_bays.size():
		return
	var spec: Dictionary = _ms_respawn_bays[i]
	var e := _spawn_docked_child(String(spec["id"]), spec["base_off"] as Vector2, float(spec.get("draw_w", 0.0)), float(spec.get("rot", 0.0)))
	if not e.is_empty():
		_ms_dock.append(e)

## Pin docked escorts to their carrier-relative slot each frame (the formation rotates with the carrier).
func _ms_update_dock_positions() -> void:
	var i := _ms_dock.size() - 1
	while i >= 0:
		var e: Dictionary = _ms_dock[i]
		var n = e.get("node")
		if n == null or not is_instance_valid(n):
			_ms_dock.remove_at(i)
			i -= 1
			continue
		if n.get("_docked"):   # not bool(...) — n.get() with no default can return null, and bool(null) crashes
			n.set("global_position", global_position + (e["base_off"] as Vector2).rotated(_facing))
			n.set("_facing", _facing + float(e["rot"]))
		i -= 1

## Octopus/spider shared leap engine.
func _jump_tick(delta: float, dir: Vector2, diagonal: bool) -> void:
	var interval := _jump_interval if diagonal else 1.0
	if _phase == 0:   # wait, then aim
		_timer += delta
		if _timer >= interval:
			_timer = 0.0
			_phase = 1
			_play_sfx(SFX_SPIDER_JUMP if diagonal else SFX_OCTOPUS_JUMP)
			if diagonal:
				_jump_interval = randf_range(0.5, 1.5)   # randomize next wait
			var d := dir
			if diagonal:
				var a := (roundf(dir.angle() / (PI * 0.5) - 0.5) + 0.5) * (PI * 0.5)
				d = Vector2(cos(a), sin(a))
			_aim = d
			_orbit_r = 0.0   # reuse as jump-distance accumulator
	else:   # leap
		var step := speed * 2.2 * delta
		global_position += _aim * step
		_orbit_r += step
		if _orbit_r >= 200.0:
			_phase = 0

## Move to a standoff ring around the player (used by ranged enemies).
func _standoff(dist: float, dir: Vector2, want: float) -> void:
	if dist > want + 40.0:
		velocity = dir * speed
	elif dist < want - 40.0:
		velocity = -dir * speed
	else:
		velocity = Vector2.ZERO
	_move_step()

func _fire_ready(interval: float) -> bool:
	if _t - _fire_t >= interval:
		_fire_t = _t
		return true
	return false

const BEAM_RANGE := 2000.0   # beamer's beam draw/hit-test range (effectively "infinite" at arena scale)

func _beamer_tick(delta: float, dir: Vector2) -> void:
	# IDLE 0.6 → CHARGE 1.0 → FIRE 3.0 → COOLDOWN 1.5, beam aimed at the player when it starts.
	_timer += delta
	match _phase:
		0:
			_beam_on = false
			if _timer >= 0.6:
				_phase = 1
				_timer = 0.0
		1:
			if _timer >= 1.0:
				_phase = 2
				_timer = 0.0
				_beam_dir = dir
				_beam_origin = _muzzle(0) - global_position   # local offset to FP
				_beam_on = true
				_play_sfx(SFX_BEAM)
		2:
			if _timer >= 3.0:
				_phase = 3
				_timer = 0.0
				_beam_on = false
				if _laser_beam != null:
					_laser_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
			else:
				var beam_world := global_position + _beam_origin
				var pp := _player_pos()
				var proj := (pp - beam_world).dot(_beam_dir)
				var beam_hit := false
				if proj > 0.0:
					var closest := beam_world + _beam_dir * proj
					beam_hit = closest.distance_to(pp) <= 30.0
					if _charm_t <= 0.0 and beam_hit and fmod(_timer, 0.5) < delta:
						GameManager.ship_take_damage(int(round(5.0 * damage_out_mult())))
				if _laser_beam != null:
					_laser_beam.set_beam(beam_world, beam_world + _beam_dir * BEAM_RANGE, true, beam_hit)
		3:
			if _timer >= 1.5:
				_phase = 0
				_timer = 0.0

## ── Metalfly boss ────────────────────────────────────────────────────────────────────────────────────────
## Builds the live 3D body and the Move 2 lane telegraph.
##
## The body is a child of this enemy (it must follow it). The LANE IS NOT — it goes under `get_parent()`
## (the Arena root, world space, no rotation), exactly like the beamer's own beam does above, and for the
## same reason: the lane marks a fixed strip of ground the boss is about to fly down. Parented to the enemy
## it would translate WITH the boss during the lunge, so the "danger zone" would slide along under it and
## always extend the same distance ahead — i.e. it would stop being a telegraph at the exact moment the
## player needs it to mean something. Freed via tree_exited so it never outlives its owner.
##
## If the rig fails to build (glb missing/unimportable) it is dropped and `_mf_rig` stays null: the moveset
## below still runs, and the enemy falls back to whatever its def's "icon" draws. That is why the def keeps
## `sprite_alpha: 0.0` rather than dropping the icon — the sprite is the fallback body, just invisible while
## the 3D one is up (same arrangement the electric temple boss already uses).
func _setup_metalfly() -> void:
	_mf_path = MetalflyPath.new()
	_mf_path.visible = false
	_mf_path.z_index = 0   # world-space now, so this is absolute: over the ground, under the creeps (z 1)
	var p := get_parent()
	if p != null:
		p.add_child(_mf_path)
		tree_exited.connect(_on_metalfly_gone)
	# Phase 1 only. The winged rig is NOT built here — it is built at hatch time (_metalfly_hatch), so a
	# fight that never gets past the cocoon never pays for a second SubViewport + skeleton. The glb's
	# PackedScene is cached by ResourceLoader after the first boss of the run, and the hatch blast covers
	# the instantiate either way.
	# Added BEFORE either body so that, at equal z_index, tree order draws the ring UNDER the boss rather
	# than across it.
	_mf_ring = MetalflyRing.new()
	_mf_ring.visible = false
	add_child(_mf_ring)
	var cocoon: Node2D = GlbSpinBody.new()
	add_child(cocoon)
	if cocoon.call("setup", MF_COCOON_GLB, MF_COCOON_PX, MF_COCOON_RPM, MF_COCOON_TUMBLE_RPM,
			_creep_mount_rot(MF_LAYER_COCOON)):
		_mf_cocoon = cocoon
	else:
		cocoon.queue_free()
		_sprite_alpha = 1.0   # no 3D body — put the flat sprite back on, or the boss would be invisible

## Phase 1 -> Phase 2. Called INSTEAD of _die() when the cocoon's HP runs out (see take_damage), so none of
## death's consequences fire: no kill tally, no XP, no loot, no boss_defeated. The node lives on; only its
## body, stats and behaviour change.
func _metalfly_hatch() -> void:
	_mf_phase = 2
	_spawn_explosion(MF_HATCH_BLAST_PX)
	_play_boom()
	if _mf_cocoon != null and is_instance_valid(_mf_cocoon):
		_mf_cocoon.queue_free()
	_mf_cocoon = null
	var rig: Node2D = MetalflyRig.new()
	add_child(rig)
	if rig.call("setup", _creep_mount_rot(MF_LAYER_WINGS)):
		_mf_rig = rig
	else:
		rig.queue_free()
		_sprite_alpha = 1.0   # no winged body either — fall back to the def's flat sheet
	# Phase 2's own pool, full. `_base_speed` (not `speed`) is the one to write: _process() recomputes
	# `speed` from it every frame through the slow/Beacon/Zone-of-Peace multiplier chain, so assigning
	# `speed` here would be overwritten on the very next tick.
	hp_max      = _mf_p2_hp
	hp          = hp_max
	_base_speed = _mf_p2_speed
	speed       = _mf_p2_speed
	# Enter the moveset at the top of Move 1, with a fresh clock — the cocoon chase left both dirty.
	_mf_state  = 0
	_mf_t      = 0.0
	_mf_shot_t = 0.0
	_flash     = 0.0

func _on_metalfly_gone() -> void:
	if _mf_path != null and is_instance_valid(_mf_path):
		_mf_path.queue_free()
	_mf_path = null

## Move 1 / Move 2, in that cycle. Called from the "boss_stub" branch of _tick_behavior() instead of the
## plain chase, so everything else about being a boss (HP/speed tune exemptions, the "boss" group, never
## being culled or recycled) is unchanged.
func _tick_metalfly(delta: float, _dist: float, dir: Vector2) -> void:
	_mf_t += delta
	if _mf_phase == 1:
		# Cocoon: no moves and no attacks, it just rams the player. It DOES face them — see _mf_face_player
		# for why that can't be left to the movement-derived facing.
		_mf_face_player(delta, dir)
		velocity = dir * speed
		_move_step()
		return
	match _mf_state:
		0:   # ── Move 1: cruise. Slow beat, close on the player, two shards a second off the wing tips.
			_mf_face_player(delta, dir)
			velocity = dir * speed
			_move_step()
			_mf_shot_t += delta
			if _mf_shot_t >= MF_SHOT_INTERVAL:
				_mf_shot_t -= MF_SHOT_INTERVAL
				_mf_fire_wings()
			if _mf_t >= MF_CRUISE_T:
				# The two specials alternate rather than being rolled, so neither can come up three times
				# running and neither can go missing for a whole fight.
				if _mf_use_swarm:
					_mf_begin_swarm()
				else:
					_mf_begin_windup(dir)
				_mf_use_swarm = not _mf_use_swarm
		1:   # ── Move 2 wind-up: hover, gape, buzz — and TRACK the player with the lane.
			velocity = Vector2.ZERO
			# The lane follows the player for the whole wind-up (2026-08-24, on request). Sidestepping once
			# no longer beats the move: the lane comes with you, and only the instant it locks below does the
			# aim stop mattering. The boss turns onto its own lane, which is where it is about to fly.
			_mf_dir = dir
			_facing = _approach_angle(_facing, _mf_dir.angle() + PI * 0.5, MF_TURN_WINDUP * delta)
			if _mf_path != null and is_instance_valid(_mf_path):
				_mf_path.call("aim", _mf_dir)
			if _mf_t >= MF_WINDUP:
				_mf_state = 2
				_mf_t = 0.0
				_mf_travelled = 0.0
				if _mf_rig != null and is_instance_valid(_mf_rig):
					_mf_rig.call("set_mouth_open", false)   # mouth shuts...
					_mf_rig.call("set_flap", "none")        # ...and the wings stop, per the move's brief
				if _mf_path != null and is_instance_valid(_mf_path):
					_mf_path.call("lock")                   # lane freezes: the aim is final
				_play_sfx(SFX_SPIDER_JUMP)
		2:   # ── Move 2 lunge: straight down the now-locked lane, wings held still, full length.
			velocity = _mf_dir * MF_LUNGE_SPEED
			_move_step()
			_mf_travelled += MF_LUNGE_SPEED * delta
			if _mf_travelled >= MF_LUNGE_LEN:
				_mf_state = 3
				_mf_t = 0.0
				if _mf_path != null and is_instance_valid(_mf_path):
					_mf_path.call("release")
				if _mf_rig != null and is_instance_valid(_mf_rig):
					_mf_rig.call("set_flap", "slow")
		4:   # ── Move 3 wind-up: hover and buzz, then throw the brood.
			velocity = Vector2.ZERO
			_mf_face_player(delta, dir)
			if _mf_t >= MF_SWARM_WINDUP:
				_mf_release_swarm()
				_mf_state = 3
				_mf_t = 0.0
				if _mf_rig != null and is_instance_valid(_mf_rig):
					_mf_rig.call("set_flap", "slow")
		_:   # ── Recover: a short, near-motionless beat where the player gets to punish the last move.
			_mf_face_player(delta, dir)
			velocity = dir * speed * 0.25
			_move_step()
			if _mf_t >= MF_RECOVER_T:
				_mf_state = 0
				_mf_t = 0.0
				_mf_shot_t = 0.0

## Turn to face the player, for every state that isn't the committed lunge.
##
## Set here rather than left to `_process()`'s movement-derived facing, which only re-aims when the enemy
## actually moved more than 0.5 px in the frame. At the boss's cruise speed of 65 px/s that threshold is
## crossed at 60 fps (1.1 px) and MISSED above ~130 fps (0.4 px) — so on a fast machine the boss chased the
## player while pointing wherever it happened to be pointing when the fight started. Facing a target is not
## something that should depend on the frame rate.
func _mf_face_player(delta: float, dir: Vector2) -> void:
	_facing = _approach_angle(_facing, dir.angle() + PI * 0.5, MF_TURN_CHASE * delta)

## Raises the lane and puts the boss into Move 2's wind-up. The lane is a fixed MF_LUNGE_LEN long and starts
## aimed at the player; state 1 re-aims it every frame until it locks.
func _mf_begin_windup(dir: Vector2) -> void:
	_mf_state = 1
	_mf_t = 0.0
	_mf_dir = dir
	if _mf_rig != null and is_instance_valid(_mf_rig):
		_mf_rig.call("set_mouth_open", true)
		_mf_rig.call("set_flap", "fast")
	if _mf_path != null and is_instance_valid(_mf_path):
		# World-space node (see _setup_metalfly) — pin it to where the boss is standing RIGHT NOW. Only the
		# DIRECTION tracks the player during the wind-up; the origin stays put, so the lane keeps marking
		# the ground the boss will actually leave from.
		_mf_path.global_position = global_position
		_mf_path.call("set_beam", dir, MF_LUNGE_LEN)

## Move 3's wind-up: hover, beat hard, and raise the gathering ring. The brood is released at the end of it
## (_mf_release_swarm), which is also where the ring drops.
func _mf_begin_swarm() -> void:
	_mf_state = 4
	_mf_t = 0.0
	if _mf_rig != null and is_instance_valid(_mf_rig):
		_mf_rig.call("set_flap", "fast")
	if _mf_ring != null and is_instance_valid(_mf_ring):
		# Same radius the brood appears at, so the ring reads as the thing they come OUT of rather than as
		# unrelated decoration that happens to be nearby.
		_mf_ring.call("begin", MF_SWARM_RING)

## Move 3: MF_SWARM_COUNT miniature Metalflies in an even ring around the boss, each a real arena_enemy that
## chases and can be shot. Size and HP are taken from THIS boss's own current numbers rather than the def's,
## so the brood scales with whatever the boss was scaled by (player level, Beacon, the director's HP_MULT).
func _mf_release_swarm() -> void:
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd == null:
		return
	var src: Dictionary = (wd.ENEMY_DEFS as Dictionary).get(MF_SWARM_ID, {})
	if src.is_empty():
		push_warning("metalfly: no '%s' def — Move 3 released nothing" % MF_SWARM_ID)
		return
	_play_boom()
	if _mf_ring != null and is_instance_valid(_mf_ring):
		_mf_ring.call("release")   # the ring's whole job was the wind-up — it goes as the brood arrives
	for i in MF_SWARM_COUNT:
		var def := src.duplicate()
		# Written as flat values, and `lvl` cleared: these are already the boss's fully-multiplied numbers,
		# so leaving the def's own scaling on would apply the player-level multiplier a second time.
		#
		# ENEMY_HP_TUNE is divided OUT because configure() will multiply it straight back in: that global x2
		# applies to every enemy whose behavior isn't "boss_stub", and the brood are plain chasers. Without
		# this they hatched at 10% of the boss's HP, not the 5% they are specified at. (Same correction the
		# ruin/temple layers make for the same reason — see their own ENEMY_HP_TUNE consts.)
		def["hp"] = hp_max * MF_SWARM_HP_FRAC / ENEMY_HP_TUNE
		def["lvl"] = false
		# ...and SIZE_TO_RADIUS likewise: `size` is a def field, `_radius` is what it becomes.
		def["size"] = _radius * MF_SWARM_SCALE / SIZE_TO_RADIUS
		def["body_px"] = MetalflyRig.DISPLAY_PX * MF_SWARM_SCALE
		var ang := TAU * float(i) / float(MF_SWARM_COUNT) + _facing
		var e: Node = get_script().new()
		e.call("configure", MF_SWARM_ID, _mgr, def)
		get_parent().add_child(e)
		e.set("global_position", global_position + Vector2(cos(ang), sin(ang)) * MF_SWARM_RING)

## A live 3D body on an ORDINARY enemy — no moveset, no phases, no lane. Only the body: the enemy's own
## `behavior` (chase, for Move 3's brood) drives it exactly as it would with a flat sprite, and `_process()`
## points the model along `_facing`. `sprite_alpha: 0.0` in the def hides the 2D icon, which stays as the
## fallback if the glb ever fails to build — same arrangement the boss itself uses.
func _setup_body_rig() -> void:
	var rig: Node2D = MetalflyRig.new()
	add_child(rig)
	var px := _body_px if _body_px > 0.0 else MetalflyRig.DISPLAY_PX
	if rig.call("setup", _creep_mount_rot(MF_LAYER_WINGS), px):
		_mf_rig = rig
	else:
		rig.queue_free()
		_sprite_alpha = 1.0

## Move 1's volley: one shard from each wing TIP, read off the live posed skeleton so the muzzles ride the
## wing beat. Falls back to the body centre if the 3D rig never built.
func _mf_fire_wings() -> void:
	if _mgr == null or not is_instance_valid(_mgr):
		return
	var muzzles: Array[Vector2] = []
	if _mf_rig != null and is_instance_valid(_mf_rig):
		muzzles = _mf_rig.call("wing_muzzles")
	if muzzles.is_empty():
		muzzles = [global_position]
	_play_sfx(SFX_ZAP)
	var pp := _player_pos()
	for m: Vector2 in muzzles:
		var to := pp - m
		var d := to.normalized() if to.length() > 0.01 else Vector2.DOWN
		_mgr.spawn_bullet(m, d * MF_SHOT_SPEED, MF_SHOT_DMG, self)

## Beamer's beam VFX — an independent LaserBeamScript instance (the SAME procedural shader beam the
## player's death_beam weapon uses, arena_weapons.gd), recolored blue. Parented to get_parent() (this
## enemy's own parent — Arena root, world-space, no rotation) rather than to this enemy itself: set_beam()
## takes absolute WORLD from/to points every frame (see _beamer_tick), and parenting under the enemy (which
## moves, and could rotate) would double-apply that transform on top of the world coordinates already
## passed in. Freed via tree_exited (this enemy's own removal, whichever path — death, LIFETIME_MAX despawn,
## any cull) so it never outlives its owner.
func _setup_laser_beam() -> void:
	_laser_beam = LaserBeamScript.new()
	_laser_beam.beam_thickness = 20.0   # beamer's beam reads much smaller than the player's death_beam (120)
	_laser_beam.fx_core_color = Color(0.85, 0.95, 1.0)
	_laser_beam.fx_body_color = Color(0.15, 0.55, 1.0)
	_laser_beam.fx_glow_color = Color(0.05, 0.25, 0.85)
	_laser_beam.packet_color  = Color(0.85, 0.95, 1.0, 0.9)
	_laser_beam.z_index = 5   # over regular enemies (z 1), under the player ship
	var p := get_parent()
	if p != null:
		p.add_child(_laser_beam)
	tree_exited.connect(_on_beamer_gone)

func _on_beamer_gone() -> void:
	if _laser_beam != null and is_instance_valid(_laser_beam):
		_laser_beam.queue_free()
	_laser_beam = null
	queue_redraw()

func _view() -> Vector2:
	if _mgr != null and _mgr.has_method("screen_size"):
		return _mgr.screen_size()
	return Vector2(1440, 780)

func _rand_offset(r: float) -> Vector2:
	var a := randf() * TAU
	return Vector2(cos(a), sin(a)) * randf_range(r * 0.4, r)

func _exit_tree() -> void:
	if _missile_volley != null and is_instance_valid(_missile_volley):
		_missile_volley.queue_free()
	_missile_volley = null

## RUN OVER's "last hit by" — records this enemy as whoever most recently damaged the player. Called right
## before every GameManager.ship_take_damage() this file triggers (those are ALWAYS player-damage calls;
## the separate enemy-vs-enemy/charm branch below uses en.take_damage() instead, never this).
func _report_hit_player() -> void:
	if GameManager.has_method("record_last_hit"):
		GameManager.record_last_hit(_type.capitalize(), _original_icon)

# ── Contact ─────────────────────────────────────────────────────────────────────
## Contact damages whatever this enemy is aggro'd on: the player (incl. ship-contact-back), or an enemy target
## (a charmed ally for normal enemies, or a foe for charmed enemies). Throttled per-enemy for enemy-vs-enemy.
func _check_contact() -> void:
	if _ship_contact_cd > 0.0:
		_ship_contact_cd -= get_process_delta_time()
	# Ship contact-back damage (Orbital pool) — 0 unless GameManager provides the curve.
	var ship_cd: float = GameManager.ship_contact_damage() if GameManager.has_method("ship_contact_damage") else 0.0
	var t := _aggro_target
	if t == null or not is_instance_valid(t):
		return
	# Centipede: any body segment touching the player bites (GameManager i-frames prevent multi-hits).
	if behavior == "centipede" and not _centi_pts.is_empty():
		var seg_r := 16.0 + _centi_width * 0.5
		var pp := _player_pos()
		for seg: Vector2 in _centi_pts:
			if seg.distance_to(pp) <= seg_r:
				_report_hit_player()
				GameManager.ship_take_damage(contact_damage)
				return
		return
	var pp := _player_pos()
	var pdist := global_position.distance_to(pp)
	var push_range := 16.0 + _radius
	# Soft crowd shove (HoT-style): a solid enemy overlapping the ship pushes it away like a current — deeper
	# overlap shoves harder. GameManager sums + caps every enemy's push so a mob slows you, never trap-walls you.
	if not _no_collide and pdist < push_range:
		var away := pp - global_position
		if away.length_squared() > 0.0001:
			var pen := 1.0 - pdist / maxf(push_range, 0.001)
			GameManager.add_player_push(away.normalized() * ENEMY_PUSH_STRENGTH * pen)
	if pdist <= push_range:
		if contact_damage > 0:
			_report_hit_player()
			GameManager.ship_take_damage(int(round(contact_damage * damage_out_mult())))
		# The player's contact (ramming) damage to the enemy — 0 by default, only > 0 with the contact-damage
		# upgrade. The enemy does NOT die from touching the player; it just takes this (and keeps attacking).
		if ship_cd > 0.0 and _ship_contact_cd <= 0.0:
			var aw := get_tree().get_first_node_in_group("arena_weapons")
			if aw != null and aw.has_method("apply_ship_contact"):
				aw.call("apply_ship_contact", self)   # kinetic + contact-bleed + Blood Thirsty
			else:
				take_damage(ship_cd, 0.0)
			_ship_contact_cd = 0.5
		# Only bombs detonate + die on contact; every other enemy survives the touch.
		if contact_explodes and (behavior == "bomb" or behavior == "thrown_bomb"):
			_on_contact_death()
	else:
		# enemy-vs-enemy (charm): deal contact damage to the target, throttled.
		if contact_damage > 0 and t.has_method("take_damage") and _ship_contact_cd <= 0.0:
			t.take_damage(float(contact_damage) * damage_out_mult())
			_ship_contact_cd = 0.4

func _on_contact_death() -> void:
	if (behavior == "bomb" or behavior == "thrown_bomb") and _mgr != null and _mgr.has_method("explode"):
		_mgr.explode(global_position, 100.0, 20, self)
	_die()

# ── Centipede chain (Viper-ported) ───────────────────────────────────────────────
## Load the 3 HD segment sprites + look up each one's AUTHORED size from creep_layout.cfg (the exact box the
## user resizes in Creep Edit — "<icon-basename>", e.g. "cent head"/"cent body"/"cent tail") so the spawn
## matches the editor pixel-for-pixel. Falls back to the old radius-derived guess only for a sprite that's
## never been placed/sized in Creep Edit yet (no "size" entry on file).
func _load_centipede() -> void:
	_centi_head_tex = load(_centi_head_icon) as Texture2D
	_centi_body_texs.clear()
	for p in _centi_body_icons:
		var t := load(String(p)) as Texture2D
		if t != null:
			_centi_body_texs.append(t)
	_centi_tail_tex = load(_centi_tail_icon) as Texture2D
	if _centi_body_texs.is_empty():
		_centi_body_texs.append(_centi_head_tex)   # defensive — every def is expected to supply at least 1
	_centi_head_size = _authored_seg_size(_centi_head_icon, _centi_head_tex)
	_centi_body_sizes.clear()
	for i in _centi_body_icons.size():
		var tex: Texture2D = _centi_body_texs[i] if i < _centi_body_texs.size() else null
		_centi_body_sizes.append(_authored_seg_size(String(_centi_body_icons[i]), tex))
	if _centi_body_sizes.is_empty():
		_centi_body_sizes.append(_centi_head_size)   # mirrors the _centi_body_texs defensive fallback above
	_centi_tail_size = _authored_seg_size(_centi_tail_icon, _centi_tail_tex)
	_centi_width = _centi_body_sizes[0].x   # rough width, only for _check_contact()'s hit radius now

## The AUTHORED (pos-independent) "size" Creep Edit saved for this sprite in creep_layout.cfg — same lookup
## ArenaEnemyScript.base_draw_width() uses for every other enemy type, generalized to both dimensions here.
## Falls back to the old radius×native-aspect guess if the sprite has never been placed/sized in the editor
## (e.g. a brand new def wired in by hand, not yet opened in Creep Edit).
func _authored_seg_size(icon_path: String, tex: Texture2D) -> Vector2:
	var raw_name := icon_path.get_file().get_basename()
	var cname := raw_name.to_lower()
	var eo_cfg := _creep_layout()
	if eo_cfg != null:
		var eo: Dictionary = eo_cfg.get_value("creeps", raw_name, eo_cfg.get_value("creeps", cname, {}))
		var sz: Vector2 = eo.get("size", Vector2.ZERO)
		if sz.x > 0.0 and sz.y > 0.0:
			return sz
	var w := _radius * CENTI_WIDTH_MUL
	if tex == null:
		return Vector2(w, w)
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	return Vector2(w, w * th / maxf(tw, 1.0))

## The BASE (untapered) authored size for segment index k (0=head, n-1=tail, else a middle "body" slot) —
## mirrors _centi_tex_for()'s own texture selection exactly, one Vector2 per Texture2D.
func _centi_seg_size_for(k: int, n: int) -> Vector2:
	if k == 0:
		return _centi_head_size
	if k == n - 1:
		return _centi_tail_size
	var idx: int = clampi(k - 1, 0, _centi_body_sizes.size() - 1)
	return _centi_body_sizes[idx]

## Which texture segment index k (0=head, n-1=tail, else a middle "body" slot) draws with. Middle slots are
## assigned _centi_body_texs in order (body1, body2, …) and clamp to the LAST one if there are more middle
## slots than provided body textures (e.g. the original centipede's single body sprite reused for all 8).
func _centi_tex_for(k: int, n: int) -> Texture2D:
	if k == 0:
		return _centi_head_tex
	if k == n - 1:
		return _centi_tail_tex
	var idx: int = clampi(k - 1, 0, _centi_body_texs.size() - 1)
	return _centi_body_texs[idx]

## Icon PATH for segment index k — same slot selection as _centi_tex_for(), but the string path (for
## creep_layout.cfg lookups instead of the loaded texture).
func _centi_icon_for(k: int, n: int) -> String:
	if k == 0:
		return _centi_head_icon
	if k == n - 1:
		return _centi_tail_icon
	var idx: int = clampi(k - 1, 0, _centi_body_icons.size() - 1)
	return String(_centi_body_icons[idx])

## The creep_layout.cfg [creeps] entry for `icon_path`'s basename (same case-insensitive lookup
## _authored_seg_size()/base_draw_width() use), or {} if this sprite was never placed in Creep Edit.
## The mount angle authored for a 3D LAYER in Creep Edit, in the editor's own Z-up space — hand it straight
## to glb_topdown_rig.gd's `view_basis()`. Zero when the layer has never been touched, which is what makes
## "no calibration" mean "exactly what shipped", not "some default pose".
##
## `rot_base` ∘ `rot`, not `rot` alone: the editor's "Set 0° here" button banks the dialled-in orientation
## into `rot_base` and zeroes `rot`, so reading one half silently drops the other (same trap arena_weapons.gd's
## `_read_creep_rot` documents). No legacy-axis migration here, unlike that one: creep_layout.cfg holds no
## rotations at all today, so every value it will ever have is written by the current, Z-up editor.
##
## Reads through `_creep_layout()`, whose cache creep_edit_mode.gd invalidates on save — so a rotation
## dialled in the editor reaches the next boss that spawns without a restart.
static var _mount_rot_helper: RefCounted = null
static func _creep_mount_rot(layer_name: String) -> Vector3:
	var cfg := _creep_layout()
	if cfg == null:
		return Vector3.ZERO
	var entry: Dictionary = cfg.get_value("creeps", layer_name, {})
	if entry.is_empty():
		return Vector3.ZERO
	if _mount_rot_helper == null:
		_mount_rot_helper = GlbRigScript.new()
	return _mount_rot_helper.compose_rot(
		entry.get("rot_base", Vector3.ZERO), entry.get("rot", Vector3.ZERO))

func _creep_layout_entry(cfg: ConfigFile, icon_path: String) -> Dictionary:
	var raw_name := icon_path.get_file().get_basename()
	var cname := raw_name.to_lower()
	return cfg.get_value("creeps", raw_name, cfg.get_value("creeps", cname, {}))

## 2026-08-15: X/Y position edits in Creep Edit's Transform panel had NO effect on a real spawn — every
## joint's spacing came purely from size×Spacing-mult (see _centi_joint_spacing() below), so e.g. dragging
## Body up to overlap Head (closing the neck gap) looked "reset" the instant you spawned/reloaded, because
## nothing ever read the saved "pos". Fixes that for every boundary where a saved "pos" is a genuine, free
## user choice: Head↔first-Body-template, Body-template(i)↔Body-template(i+1) for multi-texture sets
## (hammerhead/killerwhale/shark_elite/spermwhale2), and the last-Body-template↔Tail boundary. Returns the
## authored CENTER-TO-CENTER distance between `a_icon` and `b_icon`'s saved boxes, or `fallback` if either
## was never placed in Creep Edit. Chain DUPLICATES (extra segments beyond the template count) deliberately
## do NOT use this — they have no position of their own — see _centi_joint_spacing()'s own comment for why.
func _authored_joint_dist(a_icon: String, b_icon: String, fallback: float) -> float:
	var eo_cfg := _creep_layout()
	if eo_cfg == null:
		return fallback
	var a := _creep_layout_entry(eo_cfg, a_icon)
	var b := _creep_layout_entry(eo_cfg, b_icon)
	var a_sz: Vector2 = a.get("size", Vector2.ZERO)
	var b_sz: Vector2 = b.get("size", Vector2.ZERO)
	if a_sz.y <= 0.0 or b_sz.y <= 0.0 or not a.has("pos") or not b.has("pos"):
		return fallback
	var a_pos: Vector2 = a.get("pos", Vector2.ZERO)
	var b_pos: Vector2 = b.get("pos", Vector2.ZERO)
	var dist := (b_pos.y + b_sz.y * 0.5) - (a_pos.y + a_sz.y * 0.5)
	return dist if dist > 0.0 else fallback

## The center-to-center follow distance for joint k (distance from chain point k-1 to point k) — the single
## source of truth _update_centipede_chain() uses for both its one-time straight-line init and its per-frame
## live follow. Defaults to the existing formula (preceding segment's own size × Spacing-mult × taper), then
## overrides it with the AUTHORED position gap (_authored_joint_dist()) when this boundary sits between two
## real, freely-user-positioned nodes: Head↔first-Body-template, Body-template(i)↔Body-template(i+1), or
## (2026-08-15, reverted creep_edit_mode.gd's old "Tail always auto-follows" behavior — see that file's
## comment) the last-Body-template↔Tail boundary too, now that Tail is independently draggable again just
## like Head/Body. `_centi_icon_for(k-1,n)` resolves to the correct PRECEDING TEMPLATE's icon even when the
## actual runtime slot k-1 is a duplicate/tapered repeat of it, so the authored gap still applies correctly
## regardless of Segments. Chain DUPLICATES (extra segments beyond the template count) still always use the
## formula — they have no position of their own, matching creep_edit_mode.gd's own duplicate placement.
func _centi_joint_spacing(k: int, n: int) -> float:
	var base := _centi_seg_size_for(k - 1, n).y * _centi_spacing_mult * _centi_seg_scale(k - 1, n)
	var template_count := _centi_body_texs.size()
	var prev_is_template: bool = (k - 1 == 0) or (k - 1 <= template_count)
	var cur_is_tail: bool = (k == n - 1)
	var cur_is_template: bool = (not cur_is_tail) and (k <= template_count)
	if prev_is_template and (cur_is_template or cur_is_tail):
		return _authored_joint_dist(_centi_icon_for(k - 1, n), _centi_icon_for(k, n), base)
	return base

## Per-segment draw/spacing shrink toward the tail (Creep Edit CHAIN "Taper %" slider, def:
## "centi_taper_pct", 0-10). 2026-08-14 re-spec — PER-STEP COMPOUNDING, not a fraction of the whole chain:
## each body slot is exactly (1 - taper%) smaller than the ONE RIGHT BEFORE IT in its own texture's run. A
## body slot that's the FIRST occurrence of its own texture (`k <= _centi_body_texs.size()`) is `steps=0` —
## always its own AUTHORED size (see _centi_seg_size_for()), the "template" every later repeat of that same
## texture compounds down from. Head (k=0) and tail (k=n-1) are never scaled. Mirrors creep_edit_mode.gd's
## own `_rebuild_chain_preview()` formula exactly (same `steps = k - idx - 1`) so the arena matches the
## editor's CHAIN preview pixel-for-pixel.
func _centi_seg_scale(k: int, n: int) -> float:
	if _centi_taper_pct <= 0.0 or k <= 0 or k >= n - 1:
		return 1.0
	var template_count := _centi_body_texs.size()
	if k <= template_count:
		return 1.0
	var idx: int = clampi(k - 1, 0, template_count - 1)   # mirrors _centi_tex_for()
	var steps: int = k - idx - 1
	return pow(1.0 - _centi_taper_pct * 0.01, float(steps))

## Max turn toward a target angle, capped per call (ported from arena_weapons._approach_angle).
func _approach_angle(cur: float, target: float, max_step: float) -> float:
	var diff := wrapf(target - cur, -PI, PI)
	return cur + clampf(diff, -max_step, max_step)

## Trail the body behind the head: head = node position; each segment is pulled to a fixed spacing
## behind the one ahead (identical to the Viper's _run_snake follow loop).
func _update_centipede_chain() -> void:
	var n := _centi_segments
	if not _centi_init or _centi_pts.size() != n:
		_centi_pts.clear()
		var back := Vector2(cos(_centi_dir), sin(_centi_dir))
		# Cumulative distance, not a flat sp*k — each joint's own gap is tapered (see _centi_seg_scale()) AND
		# derived from the PRECEDING joint's own authored size (_centi_seg_size_for), so a multi-body set
		# (different-size body1/body2/…) or a shrunk taper doesn't spawn with mismatched gaps. Using the
		# preceding segment's size (not this one's) matches creep_edit_mode.gd's own CHAIN preview spacing
		# formula exactly (`prev_eo.size.y × spacing_mult`) — see _rebuild_chain_preview(). Template↔template
		# boundaries (Head↔Body, Body↔Body) override this with the authored position gap when one was placed
		# in Creep Edit — see _centi_joint_spacing().
		var cum := 0.0
		for k in n:
			if k > 0:
				cum += _centi_joint_spacing(k, n)
			_centi_pts.append(global_position - back * cum)
		_centi_init = true
		return
	_centi_pts[0] = global_position
	for k in range(1, _centi_pts.size()):
		var sp := _centi_joint_spacing(k, n)   # tapered/authored per-joint follow distance — see _centi_joint_spacing()
		var prev: Vector2 = _centi_pts[k - 1]
		var cur: Vector2 = _centi_pts[k]
		var d := prev - cur
		var dlen := d.length()
		if dlen > sp:
			d = d.normalized() * sp
			dlen = sp
			cur = prev - d
		# Cap the bend at this joint to _centi_max_bend (Creep Edit "Bend Lock", def: "centi_bend_deg", default
		# 90°) relative to the PREVIOUS joint's own direction (the segment closer to the head) — without this,
		# the naive "just stay within sp of prev" rule lets a segment swing to ANY angle (including folding back
		# over the segment ahead of it) when the head reverses/turns sharply, reading as the body snapping
		# backward unnaturally.
		# 2026-08-15 bug fix ("bend lock chỉ có tác dụng với body, không có tác dụng với head"): this used to
		# require `k >= 2` (a real k-2 point to derive "the previous joint's own direction" from) — meaning
		# the VERY FIRST joint (k=1, Head→first Body point) had no `prev_dir` to compare against and was
		# silently skipped, letting Body1 swing to any angle relative to where the Head is actually facing.
		# Every other joint (k>=2, which covers Tail too — it's just a normal joint like any other) was
		# already correctly clamped. Fixed by giving k=1 a `prev_dir` of its own: the Head's actual facing
		# direction (`_centi_dir`) plays the same role a real k-2 point would for any later joint.
		if dlen > 0.01:
			var prev_dir: Vector2 = ((_centi_pts[k - 2] as Vector2) - prev) if k >= 2 \
				else Vector2(cos(_centi_dir), sin(_centi_dir))
			if prev_dir.length() > 0.01:
				var diff := wrapf(d.angle() - prev_dir.angle(), -PI, PI)
				if absf(diff) > _centi_max_bend:
					var clamped_ang := prev_dir.angle() + clampf(diff, -_centi_max_bend, _centi_max_bend)
					d = Vector2(cos(clamped_ang), sin(clamped_ang)) * dlen
					cur = prev - d
		_centi_pts[k] = cur

## Nearest point on this enemy's actual hittable body to `from` — for most enemies that's simply
## global_position (a single point), but Centipede's body is drawn along _centi_segments visual points
## while only the head (global_position) has ever been a real collision target: a shot landing on the
## visually-present body/tail wouldn't register at all. Weapons call this instead of reading
## global_position directly so every segment counts as a hittable point. Returns global_position
## unchanged for every other enemy — zero behavior change there.
func nearest_hit_point(from: Vector2) -> Vector2:
	if behavior == "centipede" and not _centi_pts.is_empty():
		var best: Vector2 = _centi_pts[0]
		var best_d := from.distance_squared_to(best)
		for i in range(1, _centi_pts.size()):
			var d := from.distance_squared_to(_centi_pts[i] as Vector2)
			if d < best_d:
				best_d = d
				best = _centi_pts[i]
		return best
	return global_position

## Every world-space point that counts as part of this enemy's hittable body — just [global_position] for
## almost every enemy, but every segment along a Centipede's body. Beam/line weapons that need to test a
## whole swept LINE (not just the single nearest point to one test position) iterate this instead.
func hit_points() -> Array:
	if behavior == "centipede" and not _centi_pts.is_empty():
		return _centi_pts
	return [global_position]

## The facing angle segment k draws at — single source of truth for `_draw_centipede()` AND
## `_update_led_xform()`'s per-segment LED glue (2026-08-15), so a light anchored on a body/tail segment
## rotates with the EXACT same angle the segment's own sprite does, no separate/duplicate formula to drift.
func _centi_seg_ang(k: int) -> float:
	var n := _centi_pts.size()
	if n == 0:
		return _centi_dir
	if k <= 0:
		return _centi_dir
	if k >= n - 1:
		return ((_centi_pts[n - 2] as Vector2) - (_centi_pts[n - 1] as Vector2)).angle()
	return ((_centi_pts[k - 1] as Vector2) - (_centi_pts[k + 1] as Vector2)).angle()

## Draw the chain tail → head (head paints on top), each segment oriented along the body curve.
## Mirrors arena_weapons._draw_snake but in node-local space (pos − global_position) with a flash tint.
func _draw_centipede(alpha: float, flash_s: float) -> void:
	var n := _centi_pts.size()
	if n < 2:
		return
	var col := Color(1.0, 1.0, 1.0, alpha)
	if flash_s > 0.0:
		col = col.lerp(Color(_flash_color.r, _flash_color.g, _flash_color.b, alpha), flash_s)
	for k in range(n - 1, -1, -1):
		var pos: Vector2 = _centi_pts[k]
		var ang: float = _centi_seg_ang(k)
		var seg_scale := _centi_seg_scale(k, n)   # CHAIN "Taper %" — always 1.0 for the head (k=0)
		var seg_size := _centi_seg_size_for(k, n)   # AUTHORED (untapered) size for this slot — see _load_centipede()
		if k == 0:
			# 2026-08-15 ("arena vẫn overlap mạnh hơn creep edit dù đã đồng bộ khoảng cách"): this used to
			# shift the drawn head forward by a magic-number-derived offset (`CENTI_HEAD_OVERLAP`) ON TOP OF
			# the joint-1 distance — a SECOND, separate adjustment Creep Edit's own box layout has no
			# equivalent for (it just draws Head at its authored position, period). That extra shift is what
			# kept making arena look more overlapped than the editor even after `_centi_spacing` itself got
			# synced to the same authored gap in the 29th pass — two sources of truth stacking, not one.
			# Removed: Head now draws directly at its own chain point, exactly like every Body/Tail segment —
			# single source of truth (`_centi_pts[0]` + `_centi_joint_spacing(1,n)`) for the gap, period.
			_draw_centi_seg(pos, ang, _centi_head_tex, seg_size, col, seg_scale)
		elif k == n - 1:
			_draw_centi_seg(pos, ang, _centi_tail_tex, seg_size, col, seg_scale)
		else:
			_draw_centi_seg(pos, ang, _centi_tex_for(k, n), seg_size, col, seg_scale)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## One segment (head/body/tail), drawn at its own AUTHORED `base_size` (× scale_mul, CHAIN "Taper %") — the
## exact box Creep Edit saved for this sprite, so the arena spawn matches the editor's own CHAIN preview.
## local +Y (image bottom) points backward, local −Y (image top = face/connection) points along travel →
## rotation = ang + PI/2.
func _draw_centi_seg(pos: Vector2, ang: float, tex: Texture2D, base_size: Vector2, col: Color, scale_mul: float = 1.0) -> void:
	if tex == null:
		return
	var dw := base_size.x * scale_mul
	var dh := base_size.y * scale_mul
	draw_set_transform(pos - global_position, ang + PI * 0.5, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-dw * 0.5, -dh * 0.5), Vector2(dw, dh)), false, col)

## The live sprite transform: per-enemy base variance × idle bob × spawn/death pop (uniform), plus
## squash/stretch. Returned so BOTH the sprite (_draw) and the plumes (_update_plume_xform) use the exact
## same scale → plumes stay glued to the sprite no matter how the enemy is sized.
func _visual_xform() -> Dictionary:
	var bob := 1.0 + sin(_t * _bob_freq + _bob_phase) * BOB_AMOUNT
	if behavior == "mothership":
		bob = 1.0   # the carrier doesn't breathe — no expand/contract pulse
	var alpha := 1.0
	var pop := 1.0
	if _dying:
		var df := clampf(_death_t / DEATH_POP_TIME, 0.0, 1.0)
		pop = 1.0 + 0.6 * df          # scale up
		alpha = 1.0 - df              # fade out
		bob = 1.0                     # death owns scale; freeze breathing
	elif _spawn_t < SPAWN_POP_TIME:
		var sf := clampf(_spawn_t / SPAWN_POP_TIME, 0.0, 1.0)
		pop = _ease_out_back(sf)      # 0 → 1 with slight overshoot
		alpha = sf                    # fade in
	var uniform := _scale_var * bob * pop
	# Squash/stretch along the head axis (local Y); thin across (local X). Frozen during death.
	var sq := 0.0 if _dying else _squash
	var scale_vec := Vector2(uniform * (1.0 - sq * 0.5), uniform * (1.0 + sq))
	return {"scale": scale_vec, "uniform": uniform, "alpha": alpha * _sprite_alpha}

# ── Draw: composes idle bob + squash/stretch + facing + spawn/death pop + flash, around the sprite/shape;
# the HP bar and beam are drawn AFTER resetting the transform so they stay level & unscaled. ────────────
func _draw() -> void:
	# Shared sprite transform (scale + alpha). _physics_process applies the same scale to the plumes so
	# they stay glued to the sprite at any size — see _update_plume_xform().
	var vx := _visual_xform()
	var scale_vec: Vector2 = vx["scale"]
	var alpha: float = vx["alpha"]
	var rot := _spin if behavior == "centipede" else _facing

	# Drive the flash shader (whitens/reddens the actual sprite pixels — modulate alone can't).
	var flash_s := clampf(_flash / HIT_FLASH_TIME, 0.0, 1.0)
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("flash", flash_s)
		mat.set_shader_parameter("flash_color", _flash_color)
	# Elite/Champion glowing ring — drawn first (under the body/tentacles) so the sprite reads clearly on
	# top while the ring still frames it. See the const-block comment above for the colour/size rationale.
	if _is_elite:
		var ring_col := TIER_RING_CHAMPION_COL if _is_champion else TIER_RING_ELITE_COL
		var pulse := 0.65 + 0.35 * sin(_t * TIER_RING_PULSE_SPEED)
		var ring_r := _radius + TIER_RING_MARGIN
		draw_circle(Vector2.ZERO, ring_r * 1.4, Color(ring_col.r, ring_col.g, ring_col.b, 0.10 * pulse))   # soft outer halo
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 48, Color(ring_col.r, ring_col.g, ring_col.b, 0.55 + 0.35 * pulse), TIER_RING_WIDTH, true)
	# Tentacles first (world-space chains) so they sit behind the body sprite; root paints last → just under body.
	if not _tent_template.is_empty():
		_draw_tentacle(alpha)
	if behavior == "centipede":
		_draw_centipede(alpha, flash_s)   # head/body/tail chain (resets the transform itself)
	else:
		draw_set_transform(_hit_shake, rot, scale_vec)
		if _tex != null:
			draw_texture_rect(_tex, Rect2(-_draw_size * 0.5, _draw_size), false, Color(1, 1, 1, alpha))
			# Tracking eye: drawn in the same rotated/scaled frame so it sits in the socket and slides toward the player.
			if _has_eye and _eye_tex != null:
				var socket := (_eye_socket - Vector2(0.5, 0.5)) * _draw_size
				var eye_sz := _eye_size_frac * _draw_size
				var eye_center := socket + _eye_off
				draw_texture_rect(_eye_tex, Rect2(eye_center - eye_sz * 0.5, eye_sz), false, Color(1, 1, 1, alpha))
		else:
			var col := _color
			col.a *= alpha
			_draw_shape(_radius, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)   # back to level/unscaled for the HP bar
	# _beam_on's own visual is now LaserBeamScript (_laser_beam), a separate world-space node driven from
	# _beamer_tick() — no draw_line() here anymore (see _setup_laser_beam()'s comment for why it isn't a
	# child of this enemy). _beam_on/_beam_dir/_beam_origin are still kept for the hit-test math above.
	if hp < hp_max and not _dying:
		var ratio := clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
		var w := _radius * 2.0
		draw_rect(Rect2(-_radius, -_radius - 8.0, w, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-_radius, -_radius - 8.0, w * ratio, 3.0), Color(0.4, 0.95, 0.4))

## Ease-out-back: 0→1 with a slight overshoot past 1 before settling (spawn pop).
func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var f := x - 1.0
	return 1.0 + c3 * f * f * f + c1 * f * f

func _draw_shape(r: float, col: Color) -> void:
	var pts: PackedVector2Array
	match shape_kind:
		"triangle":
			pts = PackedVector2Array([Vector2(0, -r), Vector2(-r * 0.87, r * 0.6), Vector2(r * 0.87, r * 0.6)])
		"square":
			draw_rect(Rect2(Vector2(-r, -r) * 0.8, Vector2(r, r) * 1.6), col)
			return
		"circle":
			draw_circle(Vector2.ZERO, r, col)
			return
		_:   # diamond
			pts = PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
	draw_colored_polygon(pts, col)   # rotation/scale applied by the caller's draw_set_transform

# ── Missile launcher plasma volley ────────────────────────────────────────────
## Owns N plasma darts through the boomerang arc: fan-out BEHIND the launcher →
## decelerate to hover (telegraph) → stagger-return at player with homing acceleration.
## Parented to the arena enemy manager at world origin so draw coords = world coords.
class _MissileVolley extends Node2D:
	const ML_FAN_ANGLE     := 80.0
	const ML_OUT_SPEED     := 750.0
	const ML_DRAG          := 0.06
	const ML_HOVER_END     := 1.0
	const ML_STAGGER       := 0.5
	const ML_RETURN_START  := 40.0
	const ML_RETURN_ACCEL  := 900.0
	const ML_ACCEL_RAMP    := 9.0
	const ML_RETURN_MAX    := 800.0
	const ML_TURN_EARLY    := 10.0
	const ML_TURN_LATE     := 3.0
	const ML_TURN_SWITCH_T := 0.5
	const ML_LINE_DMG      := 8
	const ML_HIT_R         := 6.0
	const ML_LIFETIME      := 6.0
	const ML_TRAIL_LEN     := 40
	const ML_GLOW_INTENSITY := 1.0
	const ML_COL_HEAD      := Color(0.55, 0.85, 1.0)
	const ML_COL_TAIL      := Color(0.62, 0.30, 1.0)
	const ML_CORE_SIZE     := 9.0
	const ML_CORE_BRIGHT   := 1.0
	const ML_BLOOM_SIZE    := 32.0
	const ML_BLOOM_ALPHA   := 0.5
	const ML_TAIL_MIN      := 28.0
	const ML_TAIL_MAX      := 180.0
	const ML_FULL_SPEED    := 700.0
	const ML_TAIL_SAMPLES  := 30
	const ML_TAIL_W_HEAD   := 24.0
	const ML_TAIL_W_TAIL   := 2.0
	const ML_SPINE_FRAC    := 0.32
	const ML_SPINE_ALPHA   := 0.7
	const ML_HAZE_ALPHA    := 0.30
	const ML_HAZE_WISP     := 5.0
	const ML_FLARE_ON      := true
	const ML_FLARE_SCALE   := 1.0
	const ML_FLARE_LONG    := 80.0
	const ML_FLARE_SHORT   := 30.0
	const ML_FLARE_THIN    := 6.0
	const ML_FLARE_ALPHA   := 0.5
	const ML_DUST_ON       := true
	const ML_DUST_GAP      := 11.0
	const ML_DUST_TTL      := 0.7
	const ML_DUST_SIZE     := 5.0
	const ML_DUST_SPREAD   := 6.0
	const ML_GLITTER_SPEED := 20.0

	var _lines: Array = []
	var _dust:  Array = []
	var _clock: float = 0.0
	var _soft: Texture2D = null
	var _launcher: Node = null   # excluded from dart–enemy collision checks (self-hit guard)

	func launch(muzzles: Array, away: Vector2, launcher: Node = null) -> void:
		_launcher = launcher
		z_index = 4
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		_soft = _make_soft_tex()
		var base_ang := away.angle()
		var count: int = maxi(1, muzzles.size())
		for i in count:
			var frac: float = 0.0 if count <= 1 else float(i) / float(count - 1)
			var ang := base_ang + deg_to_rad(ML_FAN_ANGLE) * (frac - 0.5)
			var dir := Vector2(cos(ang), sin(ang))
			var dart_pos: Vector2 = muzzles[i] if i < muzzles.size() else Vector2.ZERO
			_lines.append({
				"pos": dart_pos, "vel": dir * ML_OUT_SPEED,
				"t": 0.0, "life": 0.0,
				"return_at": ML_HOVER_END + float(i) * ML_STAGGER,
				"returning": false, "speed": 0.0, "seek_t": 0.0,
				"trail": [dart_pos] as Array,
				"dust_acc": 0.0, "phase": randf() * TAU,
			})

	func _process(delta: float) -> void:
		_clock += delta
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			queue_redraw()
			return
		var ship_c: Vector2 = player.global_position
		var ship_r: float   = 16.0
		var i := _lines.size() - 1
		while i >= 0:
			var ln: Dictionary = _lines[i]
			ln["t"]    = float(ln["t"])    + delta
			ln["life"] = float(ln["life"]) + delta
			var prev: Vector2 = ln["pos"]
			if not bool(ln["returning"]):
				_tick_out(ln, delta)
				if float(ln["t"]) >= float(ln["return_at"]):
					_begin_return(ln, ship_c)
			else:
				_tick_return(ln, delta, ship_c)
			var trail: Array = ln["trail"]
			trail.push_front(ln["pos"])
			if trail.size() > ML_TRAIL_LEN:
				trail.resize(ML_TRAIL_LEN)
			_shed_dust(ln, prev)
			var p: Vector2 = ln["pos"]
			var removed := false
			if p.distance_to(ship_c) <= ship_r + ML_HIT_R:
				if _launcher != null and is_instance_valid(_launcher) and GameManager.has_method("record_last_hit"):
					GameManager.record_last_hit(String(_launcher.get("_type")).capitalize(), String(_launcher.get("_original_icon")))
				GameManager.ship_take_damage(ML_LINE_DMG)
				_lines.remove_at(i)
				removed = true
			if not removed:
				for en: Node in get_tree().get_nodes_in_group("arena_enemy"):
					if not is_instance_valid(en) or en == _launcher:
						continue
					var en2 := en as Node2D
					var er: float = en.get("_radius") if en.get("_radius") != null else 16.0
					if p.distance_to(en2.global_position) <= er + ML_HIT_R:
						if en.has_method("take_damage"):
							en.call("take_damage", float(ML_LINE_DMG), 0.0)
						_lines.remove_at(i)
						removed = true
						break
			if not removed and float(ln["life"]) >= ML_LIFETIME:
				_lines.remove_at(i)
			i -= 1
		_tick_dust(delta)
		queue_redraw()
		if _lines.is_empty() and _dust.is_empty():
			queue_free()

	func _tick_out(ln: Dictionary, delta: float) -> void:
		ln["vel"] = (ln["vel"] as Vector2) * pow(ML_DRAG, delta)
		ln["pos"] = (ln["pos"] as Vector2) + (ln["vel"] as Vector2) * delta

	func _begin_return(ln: Dictionary, ship_c: Vector2) -> void:
		# Point TOWARD the player from the start — vel starts near-zero after drag,
		# so preserving current direction would keep the dart flying away forever.
		var toward := (ship_c - (ln["pos"] as Vector2)).normalized()
		if toward.length() < 0.01:
			toward = Vector2.DOWN
		ln["returning"] = true
		ln["speed"]     = ML_RETURN_START
		ln["seek_t"]    = 0.0
		ln["vel"]       = toward * ML_RETURN_START

	func _tick_return(ln: Dictionary, delta: float, ship_c: Vector2) -> void:
		ln["seek_t"] = float(ln["seek_t"]) + delta
		var accel := ML_RETURN_ACCEL * (1.0 + ML_ACCEL_RAMP * float(ln["seek_t"]))
		ln["speed"]  = minf(ML_RETURN_MAX, float(ln["speed"]) + accel * delta)
		var spd: float = ln["speed"]
		var cur: Vector2 = ln["vel"]
		var desired := (ship_c - (ln["pos"] as Vector2)).normalized() * spd
		var turn: float = ML_TURN_EARLY if float(ln["seek_t"]) < ML_TURN_SWITCH_T else ML_TURN_LATE
		var steer := cur.lerp(desired, clampf(turn * delta, 0.0, 1.0))
		if steer.length() > 0.01:
			ln["vel"] = steer.normalized() * spd
		ln["pos"] = (ln["pos"] as Vector2) + (ln["vel"] as Vector2) * delta

	func _shed_dust(ln: Dictionary, prev: Vector2) -> void:
		if not ML_DUST_ON:
			return
		var p: Vector2 = ln["pos"]
		var seg := p - prev
		var moved := seg.length()
		if moved < 0.01:
			return
		var acc := float(ln["dust_acc"]) + moved
		var d := seg / moved
		var perp := Vector2(-d.y, d.x)
		while acc >= ML_DUST_GAP:
			acc -= ML_DUST_GAP
			var along := prev + d * (moved - acc)
			_dust.append({
				"pos":   along + perp * randf_range(-ML_DUST_SPREAD, ML_DUST_SPREAD),
				"life":  0.0,
				"ttl":   ML_DUST_TTL * randf_range(0.7, 1.2),
				"size":  ML_DUST_SIZE * randf_range(0.6, 1.2),
				"hue":   randf(),
				"phase": randf() * TAU,
			})
		ln["dust_acc"] = acc

	func _tick_dust(delta: float) -> void:
		var i := _dust.size() - 1
		while i >= 0:
			_dust[i]["life"] = float(_dust[i]["life"]) + delta
			if float(_dust[i]["life"]) >= float(_dust[i]["ttl"]):
				_dust.remove_at(i)
			i -= 1

	func _draw() -> void:
		_draw_dust()
		for ln: Dictionary in _lines:
			_draw_comet(ln["pos"], _dart_dir(ln["vel"], ln["trail"]),
				(ln["vel"] as Vector2).length(), float(ln["phase"]), ln["trail"])

	func _dart_dir(v: Vector2, trail: Array) -> Vector2:
		if v.length() > 1.0:
			return v.normalized()
		if trail.size() >= 2:
			var diff: Vector2 = (trail[0] as Vector2) - (trail[1] as Vector2)
			if diff.length() > 0.01:
				return diff.normalized()
		return Vector2.UP

	func _tail_samples(trail: Array, tail_len: float, n: int) -> Array:
		var out: Array = []
		if trail.is_empty() or tail_len <= 0.0 or n < 2:
			return out
		var step := tail_len / float(n - 1)
		out.append(trail[0])
		var next_mark := step
		var traveled := 0.0
		var i := 0
		while i < trail.size() - 1 and out.size() < n:
			var p0: Vector2 = trail[i]
			var p1: Vector2 = trail[i + 1]
			var seglen := p0.distance_to(p1)
			if seglen < 0.0001:
				i += 1
				continue
			while next_mark <= traveled + seglen and out.size() < n:
				out.append(p0.lerp(p1, (next_mark - traveled) / seglen))
				next_mark += step
			traveled += seglen
			i += 1
		return out

	func _draw_comet(p: Vector2, d: Vector2, speed: float, phase: float, trail: Array) -> void:
		var tail_len := lerpf(ML_TAIL_MIN, ML_TAIL_MAX, clampf(speed / ML_FULL_SPEED, 0.0, 1.0))
		var pts := _tail_samples(trail, tail_len, ML_TAIL_SAMPLES)
		var perp := Vector2(-d.y, d.x)
		for k in range(pts.size() - 1, -1, -1):
			var f := float(k) / float(ML_TAIL_SAMPLES - 1)
			var fade := 1.0 - f
			var col := ML_COL_HEAD.lerp(ML_COL_TAIL, f)
			var body_w := lerpf(ML_TAIL_W_HEAD, ML_TAIL_W_TAIL, f)
			var bp: Vector2 = pts[k]
			var wob := sin(f * 9.0 + phase + _clock * 2.0) * ML_HAZE_WISP * f
			_blob(bp + perp * wob, Vector2(body_w * 2.0, body_w * 2.0), 0.0, _ca(col, ML_HAZE_ALPHA * fade))
			var sc := col.lerp(Color(1.0, 1.0, 1.0, 1.0), fade * 0.6)
			_blob(bp, Vector2(body_w * ML_SPINE_FRAC * 2.0, body_w * ML_SPINE_FRAC * 2.0), 0.0, _ca(sc, ML_SPINE_ALPHA * fade))
		_blob(p, Vector2(ML_BLOOM_SIZE * 2.0, ML_BLOOM_SIZE * 2.0), 0.0, _ca(ML_COL_HEAD, ML_BLOOM_ALPHA * 0.5))
		_blob(p, Vector2(ML_BLOOM_SIZE * 1.1, ML_BLOOM_SIZE * 1.1), 0.0, _ca(Color(0.8, 0.93, 1.0), ML_BLOOM_ALPHA))
		_blob(p, Vector2(ML_CORE_SIZE * 2.0,  ML_CORE_SIZE * 2.0),  0.0, _ca(Color(1.0, 1.0, 1.0), ML_CORE_BRIGHT))
		if ML_FLARE_ON:
			var ang := d.angle()
			var tw := 0.6 + 0.4 * sin(_clock * ML_GLITTER_SPEED + phase)
			var fcol := _ca(Color(0.85, 0.95, 1.0), ML_FLARE_ALPHA * tw)
			_blob(p, Vector2(ML_FLARE_LONG * ML_FLARE_SCALE,        ML_FLARE_THIN * ML_FLARE_SCALE),        ang,              fcol)
			_blob(p, Vector2(ML_FLARE_SHORT * ML_FLARE_SCALE, ML_FLARE_THIN * 0.8 * ML_FLARE_SCALE), ang + PI * 0.5, fcol)

	func _draw_dust() -> void:
		for m: Dictionary in _dust:
			var fade := 1.0 - clampf(float(m["life"]) / maxf(0.01, float(m["ttl"])), 0.0, 1.0)
			var tw   := 0.25 + 0.75 * (0.5 + 0.5 * sin(_clock * ML_GLITTER_SPEED + float(m["phase"])))
			var col  := ML_COL_HEAD.lerp(Color(1.0, 1.0, 1.0, 1.0), float(m["hue"]))
			var a    := fade * tw
			var sz: float = float(m["size"])
			_blob(m["pos"], Vector2(sz * 2.2, sz * 2.2), 0.0, Color(col.r, col.g, col.b, 0.22 * a))
			_blob(m["pos"], Vector2(sz * 0.9,  sz * 0.9),  0.0, Color(1.0, 1.0, 1.0,     0.80 * a))

	func _ca(c: Color, a: float) -> Color:
		return Color(c.r, c.g, c.b, clampf(a * ML_GLOW_INTENSITY, 0.0, 1.0))

	func _blob(pos: Vector2, sizev: Vector2, rot: float, col: Color) -> void:
		if _soft == null:
			return
		draw_set_transform(pos, rot, Vector2.ONE)
		draw_texture_rect(_soft, Rect2(-sizev * 0.5, sizev), false, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _make_soft_tex() -> Texture2D:
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var c := float(s - 1) * 0.5
		for y in s:
			for x in s:
				var dx := (float(x) - c) / c
				var dy := (float(y) - c) / c
				var a := pow(clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0), 2.4)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		return ImageTexture.create_from_image(img)
