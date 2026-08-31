extends Node2D
## World-space enemy services for the arena — the port of the legacy EnemyManager's API, but in world
## coordinates (no SpaceScreen). Enemies find it via group "enemy_manager" and call the SAME methods they
## did before: ship_center / ship_radius / screen_size / spawn_bullet / explode / spawn_bomb / take_lane_x /
## take_wanderer_y_offset. It owns the enemy-bullet pool + explosion FX and routes damage through GameManager.

const ArenaEnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const LootScript       := preload("res://scripts/gameplay/arena_loot.gd")
const SFX_HIT          := preload("res://assets/audio/sfx/hit.wav")
const SFX_BOOM         := preload("res://assets/audio/sfx/boom.wav")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const BULLET_RADIUS    := 5.0
const BULLET_MAX_LIFE  := 6.0
const BULLET_MAX_DIST  := 2200.0
const BULLET_COLOR     := Color(1.0, 0.45, 0.35)

# "Jet Fighter" bullets (arena_enemy.gd's "shooter" behavior + spawn_mode_2's "steer_kiter", both the
# jetfighter.png sprite) — spawn_bullet(..., kind="jetfighter") tags them so they get their own shorter max
# range and a dedicated MultiMesh sprite (_jf_mm) instead of the generic circle+tail immediate-mode draw
# every other enemy bullet still uses (see _draw()). Kept a separate MultiMesh from arena_weapons.gd's
# Gatling one (different texture/owner script entirely) — same technique, ported.
const JF_BULLET_TEX      := "res://assets/weaponry/jetfighterbullet.png"
const JF_BULLET_LEN      := 22.0    # target on-screen height; width follows the source aspect ratio (112×280)
const JF_BULLET_MAX_DIST := 2000.0
const JF_MM_MAX          := 200     # generous headroom — shooter bursts are ≤4 bullets at a time, never Gatling-scale

const HIT_FLASH_DUR := 0.12
const HIT_FLASH_SHADER := """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 screen = texture(screen_texture, SCREEN_UV);
	vec3 red = vec3(0.85, 0.0, 0.0);
	vec3 blended = 1.0 - (1.0 - red) * (1.0 - screen.rgb);
	COLOR.rgb = mix(screen.rgb, blended, intensity);
	COLOR.a = 1.0;
}
"""

var _player: Node2D = null
var _bullets: Array = []      # {pos, vel, dmg, life, start, owner, kind}
var _jf_mm: MultiMeshInstance2D = null   # renders every "jetfighter"-kind bullet — see _setup_jf_multimesh/_sync_jf_multimesh
var _explosions: Array = []   # {pos, age, max_age, radius}
var _lane_i: int = 0
var _wanderer_i: int = 0

# ── Jetfighter ("shooter" type_id) flock centroid ──────────────────────────────
# A shared, periodically-recomputed centroid of every live jetfighter's position — read by arena_enemy.gd's
# "shooter" case to bias its movement toward the group (cohesion), so they clump into one pack and move
# together instead of each independently orbiting the player on its own. Computed HERE (once, O(alive), on
# a timer) rather than per-jetfighter every frame, which would be O(alive) PER jetfighter — same "compute
# once, let everyone read it" pattern as _vis_rect/_enemy_count above. Separation (not stacking on top of
# each other) is untouched — the existing spatial-hash push-apart already handles that; this only adds the
# "pull together when far apart" half of flocking.
const JF_FLOCK_RECALC_EVERY := 0.4   # seconds between recomputes — the pack doesn't need frame-perfect tracking
var _jf_flock_center: Vector2 = Vector2.ZERO
var _jf_flock_valid: bool = false
var _jf_flock_acc: float = 0.0

# ── The ONE sun — single shared light direction for the 3D objects' own lighting ─────────────────────────
# (2026-08-28, user report: "Ánh sáng đang cast qua object 3D này có phải ánh sáng trong Light Edit ko? Nếu
# là 2 nguồn sáng độc lập thì bạn đang làm sai, tôi cần 1 mặt trời thôi" — the player ship's and VIPER's own
# key lights used to be a hand-picked constant, completely disconnected from the map's REAL, player-
# configurable sun: each terrain's Light Edit panel (electric/volcanic/atlantic/arctic/mechanic_light_edit.gd)
# already drives a real light direction into that map's own ground shader (canopy_light_dir / ground_light_dir
# — identical Vector3(cos(angle)*xy_mag, sin(angle)*xy_mag, height) formula in every one of the 5 *_ground.gd
# files, just renamed canopy_*/ground_* per map). That WAS the second, independent light source the report
# correctly called out.
#
# Fix: every *_ground.gd caches that same computed Vector3 and exposes it back via a public sun_dir() — see
# that function's own doc comment in e.g. electric_ground.gd. THIS function polls whichever one of the 5
# map-ground groups is actually alive right now (only one ever is, per run) and caches ITS sun_dir() here, so
# arena.gd's ship key light and arena_weapons.gd's VIPER key light both orient off the exact same Vector3 —
# genuinely one sun, not two coincidentally similar ones. Falls back to SUN_DEFAULT (matching the ground
# shader's own uniform default) on a map with no ground node at all (Default/Space).
#
# 2026-08-28, later same day, on request ("bỏ chế độ đổ bóng đi, cả 2D và 3D, xóa hẳn code. Vẫn giữ lại cái
# ánh sáng chiếu lên object 3D"): the earlier drop-shadow feature this system ALSO used to feed (arena_enemy.
# gd's creep blob shadow, arena.gd's ship shadow sprite, arena_weapons.gd's VIPER shadow layer, and this
# file's own sun_offset_2d() helper) has been removed outright, code and all — sun_dir() below is untouched
# and still the single source both 3D key lights read.
const SUN_RECALC_EVERY := 1.0   # seconds — a "sun" a player is actively dragging a Light Edit slider on is
                                 # the only thing that ever changes this; no light needs frame-perfect tracking
const SUN_GROUND_GROUPS := ["electric_ground", "volcanic_ground", "atlantic_ground", "arctic_ground", "mechanic_ground"]
const SUN_DEFAULT := Vector3(0.6, 0.6, 0.6)   # matches every *_ground.gdshader's own uniform default
var _sun_dir: Vector3 = SUN_DEFAULT
var _sun_acc: float = 0.0

func _tick_sun(delta: float) -> void:
	_sun_acc += delta
	if _sun_acc < SUN_RECALC_EVERY:
		return
	_sun_acc = 0.0
	for grp: String in SUN_GROUND_GROUPS:
		var ground := get_tree().get_first_node_in_group(grp)
		if ground != null and is_instance_valid(ground) and ground.has_method("sun_dir"):
			_sun_dir = ground.call("sun_dir")
			return
	_sun_dir = SUN_DEFAULT   # no map ground this run (Default/Space) — fixed, still-consistent fallback

## Public: the arena's one live sun direction, Vector3(x, y, height) — same convention as the ground shaders'
## own light_dir (screen-space XY toward the light, Z = how overhead: 0 grazing, 1 straight down). Read by
## arena.gd's/arena_weapons.gd's key-light rotation (_update_ship_lighting()/_update_snake3d_lighting()).
func sun_dir() -> Vector3:
	return _sun_dir

# ── Ambient Pack/Fleet regrouping — organically-spawned same-species creeps drift together mid-run ────────
# (2026-08-28, on request: "khi các creep cùng chủng loại xuất hiện trên màn hình, chúng sẽ có xu hướng form
# lại thành các pack (bầy đàn đi chung hỗn độn) hoặc các fleet (form theo dạng fleet)... tùy thuộc số lượng
# các enemy đang có sẵn trên map"). Generalizes the jetfighter flock above from one hardcoded `_type` to
# every plain "chase"-behavior creep, and adds a second, stronger tier on top of it:
#   • FLEET — a same-species cluster of PACK_FLEET_MIN_SIZE..PACK_FLEET_MAX_SIZE mutually-close, still-
#     independent creeps is rigidly assembled into a real Fleet Edit-style formation: the member nearest the
#     player becomes the flagship carrier and keeps running its own normal "chase" steering completely
#     unmodified (real creep movement, not a scripted path); every other member is docked onto it via
#     arena_enemy.gd's add_existing_fleet_escort() — the SAME rigid-dock / speed-capped-catch-up machinery an
#     authored Fleet Edit formation gets from init_fleet_dock() (arena_wave_director_v2.gd's _deploy_fleet()),
#     just fed a shape synthesized on the spot (_fleet_wedge_offsets()) instead of one hand-placed in the
#     Fleet Edit UI — no fleet_layout.cfg entry exists (or reasonably could — see that function's own doc
#     comment) for an ad-hoc same-species cluster of an arbitrary size that only exists because of how a run
#     happened to unfold. Docking each escort at its DESIRED slot (not its current position) is what makes
#     the assembly read as flying INTO formation — _fleet_update_dock_positions()'s existing speed-capped
#     chase closes the gap over a couple of seconds instead of snapping.
#   • PACK — every eligible "chase" creep NOT (yet) claimed by a fleet this pass gets a soft cohesion pull
#     toward its own species' shared centroid — exactly the jetfighter flock's mechanic, just keyed per
#     `_type` instead of one hardcoded id (see pack_center()/pack_valid(), read from arena_enemy.gd's "chase"
#     case via PACK_WEIGHT/PACK_HOLD_R). This is the "hỗn độn" loose-crowd half of the request: no minimum
#     size, no formation shape — creeps just visibly drift toward each other's general vicinity.
# Both tiers re-run every PACK_FLEET_INTERVAL: as more of a species spawns in, yesterday's loose pack members
# graduate into today's fleet; when a fleet's carrier dies its escorts release (arena_enemy.gd's existing
# _die() → _release_all_docks(), unconditional for every enemy, already covers this) and fall straight back
# into the pack pool on the very next pass — no extra bookkeeping needed here for that.
#
# Scope is deliberately narrow (2026-08-28, per explicit choice over the broader "every steering behavior"
# option): ONLY behavior == "chase" is eligible, on both sides. Excluded: elite/champion/final-boss (their own
# milestone-encounter reward flow, see arena_enemy.gd's _is_elite/_is_champion), boss_stub (shares the "chase"
# match case for its non-metalfly fallback move but is checked separately), centipede (already has its own
# chain-body formation), mothership/fleet-docked escorts and existing carriers (already mid-formation), and
# every specialized steering behavior (steer_chaser/steer_flanker/steer_kiter/bomber/beamer/etc.) — those
# already have their own bespoke movement feel that an added cohesion/dock bias would fight against.
const PACK_FLEET_INTERVAL  := 2.5     # seconds between regroup passes — clustering costs more than the flat
                                       # flock centroid above, so this deliberately runs slower than JF_FLOCK_RECALC_EVERY
const PACK_FLEET_MIN_SIZE  := 4       # minimum same-species cluster that graduates into a fleet
const PACK_FLEET_MAX_SIZE  := 9       # largest procedural fleet this forms in one pass (request: "4,5,6,7,8,9... con")
const PACK_FLEET_CLUSTER_R := 260.0   # same-species creeps within this of a cluster's seed count as "close
                                       # enough" to fleet together
var _pack_fleet_acc: float = 0.0
var _pack_centers: Dictionary = {}    # type_id -> Vector2 — this pass's shared cohesion target per species
var _pack_valid: Dictionary = {}      # type_id -> bool

var _hit_player: AudioStreamPlayer = null
var _hit_flash_rect: ColorRect = null
var _hit_flash_mat: ShaderMaterial = null
var _hit_flash_t: float = 0.0

# Pooled, throttled death booms — replaces a per-death AudioStreamPlayer.new() (node churn + dozens of
# overlapping booms when a whole wave dies at once). Round-robin a few players; collapse near-simultaneous
# booms via a min-gap so mass death is one punchy boom, not 50.
const BOOM_POOL    := 6
const BOOM_MIN_GAP := 0.045
var _boom_pool: Array[AudioStreamPlayer] = []
var _boom_i: int = 0
var _boom_last: float = -1.0
var _now: float = 0.0

# Camera-visible world rect, refreshed once per frame. Enemies read it for off-screen LOD: an enemy outside
# this (grown by a margin) skips its _draw and pauses its plume emission — the dominant saving at 500 enemies.
var _vis_rect: Rect2 = Rect2(-1.0e9, -1.0e9, 2.0e9, 2.0e9)
var _enemy_count: int = 0   # live "arena_enemy" count, refreshed once per frame (plume density LOD)

# ── Enemy-vs-enemy separation (replaces per-enemy CharacterBody2D + move_and_slide) ─────────────
# Spatial-hash push-apart: bucket separating enemies into a grid, and push each pair that overlaps within its
# 3×3 cells. It's the ENTIRE non-stacking mechanism now. Cost control (a converging swarm clumps → many enemies
# per cell → the neighbour scan degrades badly, so all three matter):
#   • THROTTLE — runs every SEP_EVERY physics frames (it's corrective; 30 Hz is visually identical to 60).
#   • PAIRS-ONCE — each unordered pair is handled once (j>i) and the push applied to BOTH, halving the scan.
#   • REUSED BUFFERS — the arrays + grid are members, cleared and refilled, never reallocated per pass.
const SEP_CELL     := 48.0   # grid cell size (px) — ~one enemy diameter, so overlaps stay within the 3×3 neighbourhood
const SEP_STRENGTH := 0.5    # fraction of each overlap corrected per pass; split across the pair, so ~full resolution
const SEP_MAX_PUSH := 40.0   # px/pass cap per enemy so deep overlaps (a whole cluster spawning on one point) ease apart instead of exploding
const SEP_EVERY    := 2      # run separation every N physics frames (throttle: 60/2 = 30 Hz)
const SEP_MAX_NEIGHBORS := 8 # hard cap on pushes computed per enemy per pass — bounds cost to O(N) even when
                             # hundreds pile into one cell (the O(K²)-per-cell blowup that tanked FPS in a clump).
							 # An enemy still gets shoved out by its nearest few neighbours; that's enough to spread.
const SEP_VIS_MARGIN := 220.0 # only separate enemies within the visible rect + this margin — off-screen overlaps
							  # cause no overdraw and are invisible, so separating them is pure wasted CPU.
var _sep_tick: int = 0
# Reused across passes (never reallocated): parallel per-enemy snapshot + the grid.
var _sep_nodes: Array = []
var _sep_pos:   PackedVector2Array = PackedVector2Array()
var _sep_rad:   PackedFloat32Array = PackedFloat32Array()
var _sep_push:  PackedVector2Array = PackedVector2Array()
var _sep_grid:  Dictionary = {}

func _ready() -> void:
	add_to_group("enemy_manager")
	# ALWAYS, not the default INHERIT — SPECIFICALLY so _tick_sun() (see below) keeps tracking the map's live
	# Light Edit sun even while Dev Mode pauses the tree (arena_hud_buttons.gd's set_dev_mode() does
	# `get_tree().paused = true`, and Light Edit is a Dev Mode-only panel — a slider drag would otherwise
	# visibly do nothing to the ship's/VIPER's key lights until the tester closed the panel, 2026-08-28 bug
	# report: "sao tôi chỉnh light height và các slider khác, bóng đổ lên terrain của player vẫn ko thay đổi
	# nhỉ" — filed against the drop-shadow feature that report's fix fed, since removed outright). _process()
	# below immediately early-returns into everything ELSE this manager does (bullets, separation, pack/fleet,
	# explosions) once paused, so real gameplay simulation stays exactly as frozen as before this change —
	# only the cosmetic sun cache keeps refreshing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100   # run the separation pass AFTER every enemy has moved this physics frame
	z_index = -1   # bullets/explosions just under the player/enemies
	_player = get_tree().get_first_node_in_group("player")
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = SFX_HIT
	_hit_player.bus = "SFX"
	add_child(_hit_player)
	var sh := Shader.new()
	sh.code = HIT_FLASH_SHADER
	_hit_flash_mat = ShaderMaterial.new()
	_hit_flash_mat.shader = sh
	_hit_flash_mat.set_shader_parameter("intensity", 0.0)
	var cl := CanvasLayer.new()
	cl.layer = 95
	_hit_flash_rect = ColorRect.new()
	_hit_flash_rect.color = Color.WHITE
	_hit_flash_rect.material = _hit_flash_mat
	_hit_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash_rect.hide()
	cl.add_child(_hit_flash_rect)
	add_child(cl)
	for i in BOOM_POOL:
		var bp := AudioStreamPlayer.new()
		bp.stream = SFX_BOOM
		bp.bus = "SFX"
		bp.volume_db = linear_to_db(0.7)
		add_child(bp)
		_boom_pool.append(bp)
	GameManager.player_hit.connect(_play_hit)
	_setup_jf_multimesh()

## Death boom for a dying enemy — pooled + throttled (see _boom_pool). Call instead of spawning a player.
func play_boom() -> void:
	if _boom_pool.is_empty():
		return
	if _now - _boom_last < BOOM_MIN_GAP:
		return   # collapse a burst of simultaneous deaths into a single boom
	_boom_last = _now
	var p := _boom_pool[_boom_i]
	_boom_i = (_boom_i + 1) % _boom_pool.size()
	p.pitch_scale = randf_range(0.92, 1.08)   # slight variation so reused booms don't sound mechanical
	p.play()

## Refresh the camera-visible world rect (once per frame). Enemies read it via visible_world_rect().
func _update_vis_rect() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_2d()
	if cam == null or cam.zoom.x <= 0.0 or cam.zoom.y <= 0.0:
		return
	var size := vp.get_visible_rect().size / cam.zoom
	_vis_rect = Rect2(cam.get_screen_center_position() - size * 0.5, size)

## Camera-visible world rect, cached per frame (LOD culling for enemies).
func visible_world_rect() -> Rect2:
	return _vis_rect

## Live enemy count, cached once per frame — read by enemies for the plume density LOD (avoids an O(N) query
## per enemy, which would be O(N²)).
func enemy_count() -> int:
	return _enemy_count

## Spatial-hash push-apart. Snapshots separating enemies into reused buffers, buckets them into the grid, then
## handles each overlapping PAIR once (j>i, push applied to both) and moves them apart. This is what stops the
## swarm from stacking now that there is no physics body.
func _tick_separation() -> void:
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	if enemies.size() < 2:
		return
	# Snapshot into reused buffers (clear keeps capacity — no per-pass allocation). Skip non-separating nodes
	# (radius 0 = no_collide/dying/docked) and bosses (share the group but have no separation_radius()).
	_sep_nodes.clear()
	_sep_pos.clear()
	_sep_rad.clear()
	var vis := _vis_rect.grow(SEP_VIS_MARGIN)   # separate only what's on (or near) screen — see SEP_VIS_MARGIN
	for e in enemies:
		if not is_instance_valid(e) or not e.has_method("separation_radius"):
			continue
		var r: float = e.separation_radius()
		if r <= 0.0:
			continue
		var epos: Vector2 = (e as Node2D).global_position
		if not vis.has_point(epos):
			continue
		_sep_nodes.append(e)
		_sep_pos.append(epos)
		_sep_rad.append(r)
	var m := _sep_nodes.size()
	if m < 2:
		return
	# Bucket into the grid (reused dict).
	_sep_grid.clear()
	var inv := 1.0 / SEP_CELL
	for i in m:
		var p := _sep_pos[i]
		var key := Vector2i(int(floor(p.x * inv)), int(floor(p.y * inv)))
		if _sep_grid.has(key):
			(_sep_grid[key] as Array).append(i)
		else:
			_sep_grid[key] = [i]
	_sep_push.resize(m)
	for i in m:
		_sep_push[i] = Vector2.ZERO
	# Each unordered overlapping pair once (j>i): compute the push and apply to BOTH ends (halves the scan).
	for i in m:
		var pi := _sep_pos[i]
		var ri := _sep_rad[i]
		var cx := int(floor(pi.x * inv))
		var cy := int(floor(pi.y * inv))
		var pushed := 0
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var cell: Variant = _sep_grid.get(Vector2i(cx + ox, cy + oy))
				if cell == null:
					continue
				for j: int in (cell as Array):
					if j <= i:
						continue
					var d := pi - _sep_pos[j]
					var dist := d.length()
					var min_d := ri + _sep_rad[j]
					if dist < min_d and dist > 0.001:
						var f := d * ((min_d - dist) * SEP_STRENGTH / dist)
						_sep_push[i] += f
						_sep_push[j] -= f
						pushed += 1
						if pushed >= SEP_MAX_NEIGHBORS:
							break
				if pushed >= SEP_MAX_NEIGHBORS:
					break
			if pushed >= SEP_MAX_NEIGHBORS:
				break
	# Apply (capped) after the full pair pass so the reads stayed a clean snapshot.
	for i in m:
		var pv := _sep_push[i]
		var l := pv.length()
		if l > SEP_MAX_PUSH:
			pv = pv * (SEP_MAX_PUSH / l)
		if pv != Vector2.ZERO:
			(_sep_nodes[i] as Node2D).global_position += pv

func _process(delta: float) -> void:
	# Runs ALWAYS now (see _ready()) so the sun cache survives Dev Mode's pause — but everything below this
	# point is real gameplay simulation, which must stay exactly as frozen as it was before that change.
	_tick_sun(delta)
	if get_tree().paused:
		return
	_now += delta
	_update_vis_rect()
	_enemy_count = get_tree().get_node_count_in_group("arena_enemy")   # cached for the plume density LOD
	# Enemy-vs-enemy separation — now in _process (enemies moved off the physics clock, so this follows them).
	# process_priority=100 makes this run after every enemy's _process; throttled to every SEP_EVERY frames.
	_sep_tick += 1
	if _sep_tick % SEP_EVERY == 0:
		_tick_separation()
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_tick_bullets(delta)
	_sync_jf_multimesh()
	_tick_jf_flock(delta)
	_tick_pack_fleet(delta)
	_tick_explosions(delta)
	queue_redraw()
	if _hit_flash_rect != null:
		if _hit_flash_t > 0.0:
			_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
			var vp := get_viewport()
			if vp != null:
				_hit_flash_rect.size = vp.get_visible_rect().size
			_hit_flash_mat.set_shader_parameter("intensity", (_hit_flash_t / HIT_FLASH_DUR) * 0.35)
			_hit_flash_rect.show()
		else:
			_hit_flash_rect.hide()

## Recomputes _jf_flock_center from every live "shooter"-type (jetfighter) enemy's position, throttled to
## JF_FLOCK_RECALC_EVERY. O(alive) — cheap at the 500-enemy scale and only runs a few times/sec, not every frame.
func _tick_jf_flock(delta: float) -> void:
	_jf_flock_acc += delta
	if _jf_flock_acc < JF_FLOCK_RECALC_EVERY:
		return
	_jf_flock_acc = 0.0
	var sum := Vector2.ZERO
	var n := 0
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if is_instance_valid(e) and String(e.get("_type")) == "shooter":
			sum += (e as Node2D).global_position
			n += 1
	_jf_flock_valid = n > 0
	if _jf_flock_valid:
		_jf_flock_center = sum / float(n)

## Read by arena_enemy.gd's "shooter" case for cohesion — check jf_flock_valid() first (false if no
## jetfighter is alive yet, e.g. the very first one spawned has nothing to flock toward).
func jf_flock_center() -> Vector2:
	return _jf_flock_center

func jf_flock_valid() -> bool:
	return _jf_flock_valid

## Regroup pass — see this section's header (above the consts/vars) for the full pack/fleet design. Buckets
## every FLEET/PACK-eligible creep by species (`_type`), tries to graduate each species' own cluster(s) into
## a rigid fleet via _form_fleets(), and turns whatever's left into that species' pack cohesion centroid.
## O(alive) to bucket + O(k²) per species for clustering (k = that species' own live count, not the whole
## field — see _form_fleets' doc comment) — throttled to PACK_FLEET_INTERVAL, so this is a few-times-a-second
## cost at most, not a per-frame one.
func _tick_pack_fleet(delta: float) -> void:
	_pack_fleet_acc += delta
	if _pack_fleet_acc < PACK_FLEET_INTERVAL:
		return
	_pack_fleet_acc = 0.0
	var by_type: Dictionary = {}   # type_id -> Array[Node2D], every eligible live member of that species
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(e):
			continue
		if String(e.get("behavior")) != "chase":
			continue   # scope: plain "chase" only — see this section's header
		if bool(e.get("_is_elite")) or bool(e.get("_is_champion")) or bool(e.get("_is_final_boss")):
			continue   # milestone encounters keep their own reward flow, untouched by this
		if bool(e.get("_docked")):
			continue   # already someone else's escort (mothership, an authored fleet, or an earlier pack/fleet pass)
		var dock: Array = e.get("_fleet_dock")
		if dock != null and not dock.is_empty():
			continue   # already a carrier of its own squad — don't fold it into ANOTHER formation
		var tid := String(e.get("_type"))
		if tid == "":
			continue
		if not by_type.has(tid):
			by_type[tid] = []
		(by_type[tid] as Array).append(e)
	_pack_centers.clear()
	_pack_valid.clear()
	for tid: String in by_type:
		var leftover: Array = _form_fleets(by_type[tid])
		if leftover.size() > 0:
			var sum := Vector2.ZERO
			for e in leftover:
				sum += (e as Node2D).global_position
			_pack_centers[tid] = sum / float(leftover.size())
			_pack_valid[tid] = true

## Clusters `members` (already filtered to one species' fleet-eligible population) into as many
## PACK_FLEET_MIN_SIZE..PACK_FLEET_MAX_SIZE fleets as fit, forming each one immediately via _form_one_fleet(),
## and returns whatever's left un-clustered — that becomes this species' pack pool for the pass (see
## _tick_pack_fleet). SINGLE-LINKAGE / chain clustering, not "everyone within CLUSTER_R of one seed": a
## cluster grows by admitting any still-unclaimed node within CLUSTER_R of ANY member already in it, not just
## the original seed. That distinction matters — an evenly-spaced LINE of 5 same-species creeps 100px apart
## (each neighbour-to-neighbour link well inside CLUSTER_R=260, but the two ends 400px apart, outside it)
## previously failed to cluster at all under seed-only distance, because every non-seed member was checked
## against the FIRST node alone; chain-linking lets it grow through each intermediate member instead, which
## is exactly the shape a same-species stream converging on the player from one direction tends to form.
## One pass, O(k²) worst case, but k is a SINGLE species' own live population (this game's per-type counts run
## tens, not thousands) since the by-species bucketing in _tick_pack_fleet already keeps different creep types
## from ever being compared against each other here.
func _form_fleets(members: Array) -> Array:
	var unclaimed: Array = members.duplicate()
	var leftover: Array = []
	while not unclaimed.is_empty():
		var cluster: Array = [unclaimed[0]]
		unclaimed.remove_at(0)
		var grew := true
		while grew and cluster.size() < PACK_FLEET_MAX_SIZE:
			grew = false
			var i := 0
			while i < unclaimed.size():
				var cand: Node2D = unclaimed[i]
				var joins := false
				for m in cluster:
					if (m as Node2D).global_position.distance_to(cand.global_position) <= PACK_FLEET_CLUSTER_R:
						joins = true
						break
				if joins:
					cluster.append(cand)
					unclaimed.remove_at(i)
					grew = true
					if cluster.size() >= PACK_FLEET_MAX_SIZE:
						break   # full — whatever's still unclaimed waits for the NEXT cluster/pass instead
				else:
					i += 1
		if cluster.size() >= PACK_FLEET_MIN_SIZE:
			_form_one_fleet(cluster)
		else:
			leftover.append_array(cluster)
	return leftover

## Assembles ONE cluster (already known: same species, PACK_FLEET_MIN_SIZE..MAX_SIZE members, all mutually
## close) into a rigid fleet. The member nearest the player becomes the flagship carrier — kept running its
## own normal "chase" steering unmodified, real creep movement rather than a scripted path — and every other
## member is greedily matched to whichever procedural wedge slot (_fleet_wedge_offsets()) it's currently
## closest to (minimizes total travel, so no member gets assigned a slot clear across the formation from
## where it's standing), then docked at that DESIRED slot via arena_enemy.gd's add_existing_fleet_escort() —
## see that function's own doc comment on why a desired slot, not the escort's current position, is what
## makes the assembly read as "flying into formation" rather than snapping there.
func _form_one_fleet(group: Array) -> void:
	var carrier: Node2D = group[0]
	if _player != null and is_instance_valid(_player):
		var best_d: float = carrier.global_position.distance_squared_to(_player.global_position)
		for n in group:
			var d: float = (n as Node2D).global_position.distance_squared_to(_player.global_position)
			if d < best_d:
				best_d = d
				carrier = n
	if not carrier.has_method("add_existing_fleet_escort"):
		return   # not an arena_enemy after all (shouldn't happen — every member came from group "arena_enemy")
	var escorts: Array = group.duplicate()
	escorts.erase(carrier)
	var spacing: float = maxf(24.0, float(carrier.get("_radius")) * 1.6)   # bigger species get more elbow room
	var facing: float = float(carrier.get("_facing"))
	var slots: Array = _fleet_wedge_offsets(escorts.size(), spacing)
	for esc in escorts:
		var epos: Vector2 = (esc as Node2D).global_position
		var best_i := 0
		var best_dist := 1.0e18
		for i in slots.size():
			var world_slot: Vector2 = carrier.global_position + (slots[i] as Vector2).rotated(facing)
			var d: float = epos.distance_squared_to(world_slot)
			if d < best_dist:
				best_dist = d
				best_i = i
		var chosen: Vector2 = slots[best_i]
		slots.remove_at(best_i)
		carrier.call("add_existing_fleet_escort", esc, chosen)

## Procedural trailing-wedge shape (à la geese / fighter squadron) for `n` escorts around a carrier at local
## origin, in the SAME carrier-local pre-`_facing`-rotation frame arena_enemy.gd's `base_off` convention
## already uses everywhere else (init_fleet_dock/_fleet_update_dock_positions): local UP (−Y) is straight
## ahead of the carrier's own travel and local RIGHT/LEFT (±X) is lateral spread — derived from how
## arena_enemy.gd computes `_facing` itself (movement angle + 90°, the standard "sprite drawn facing up"
## correction), NOT an arbitrary choice; see add_existing_fleet_escort()'s call site above for where this
## gets rotated into world space. Two escorts per row, alternating sides, each row one step further back
## and out than the last — deliberately simple/symmetric rather than reusing an authored fleet_layout.cfg
## shape: those are hand-placed per SPECIFIC species at FIXED sizes (5/9/10/12/16/20...), none of which cover
## an arbitrary ad-hoc cluster of 3-8 escorts (PACK_FLEET_MIN_SIZE=4 minus the carrier .. PACK_FLEET_MAX_SIZE
## =9 minus the carrier) for a species that may never have had a fleet authored for it at all.
func _fleet_wedge_offsets(n: int, spacing: float) -> Array:
	var out: Array = []
	for i in n:
		var row := i / 2 + 1
		var side := -1.0 if i % 2 == 0 else 1.0
		out.append(Vector2(side * row * spacing, row * spacing * 0.85))   # +Y = behind (see doc comment)
	return out

## Read by arena_enemy.gd's "chase" case for cohesion — check pack_valid(type_id) first (false if this
## species has no leftover pack pool this pass, e.g. everyone of that type is already in a fleet, or the
## single one alive has nothing to flock toward).
func pack_center(type_id: String) -> Vector2:
	return _pack_centers.get(type_id, Vector2.ZERO)

func pack_valid(type_id: String) -> bool:
	return bool(_pack_valid.get(type_id, false))

# ── Legacy API (now world-space) ───────────────────────────────────────────────
func ship_center() -> Vector2:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return global_position

func ship_radius() -> float:
	return 16.0   # matches arena.PLAYER_RADIUS

## The visible view size in world units (viewport / camera zoom). Used as the off-screen spawn extent.
func screen_size() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom if cam != null else Vector2.ONE
	return Vector2(vp.x / maxf(0.01, z.x), vp.y / maxf(0.01, z.y))

## Round-robin lane x across the current view width, in world coords (around the player).
func take_lane_x() -> float:
	var lanes := [0.1, 0.3, 0.5, 0.7, 0.9]
	var f: float = lanes[_lane_i % lanes.size()]
	_lane_i += 1
	var vs := screen_size()
	return ship_center().x - vs.x * 0.5 + vs.x * f

func take_wanderer_y_offset() -> float:
	var rows := [-50.0, 0.0, 50.0]
	var o: float = rows[_wanderer_i % rows.size()]
	_wanderer_i += 1
	return o

# ── Enemy bullets ───────────────────────────────────────────────────────────────
func spawn_bullet(pos: Vector2, vel: Vector2, dmg: int, owner: Node = null, kind: String = "") -> void:
	var oid := owner.get_instance_id() if owner != null else 0
	if GameManager.has_method("mech_bonus") and GameManager.mech_bonus("zone_of_peace") > 0.0:
		vel *= 0.8   # Zone of Peace (Ionizing Field evolve): -20% enemy projectile speed
	_bullets.append({"pos": pos, "vel": vel, "dmg": dmg, "life": 0.0, "start": pos, "owner": oid, "kind": kind})

## Destroy every live enemy projectile (Sonic's Deafening Silence evolution).
func clear_bullets() -> void:
	_bullets.clear()

## Deflect every enemy bullet within `radius` of `center` to fly outward at ≥ `force` px/s. Used by the
## Bulwark thruster + Guardian drone to shove incoming fire away. Returns how many bullets were pushed.
func push_bullets_away(center: Vector2, radius: float, force: float) -> int:
	var n := 0
	for b: Dictionary in _bullets:
		var p: Vector2 = b["pos"]
		var d := p.distance_to(center)
		if d <= radius:
			var away := (p - center).normalized() if d > 0.01 else Vector2.UP
			b["vel"] = away * maxf((b["vel"] as Vector2).length(), force)
			n += 1
	return n

## Offset from `center` to the nearest enemy bullet within `radius` (Vector2.ZERO if none). The Smart
## thruster reads this to nudge the ship off incoming fire.
func nearest_bullet_offset(center: Vector2, radius: float) -> Vector2:
	var best := Vector2.ZERO
	var best_d := radius
	for b: Dictionary in _bullets:
		var off: Vector2 = (b["pos"] as Vector2) - center
		var d := off.length()
		if d < best_d:
			best_d = d
			best = off
	return best

func _tick_bullets(delta: float) -> void:
	var sc := ship_center()
	var sr := ship_radius()
	# Impenetrable evo: orbiting balls destroy enemy projectiles they touch.
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	var blocks: Array = aw.call("orbital_block_positions") if (aw != null and aw.has_method("orbital_block_positions")) else []
	# Event Horizon (2026-08-07, on request): any enemy bullet caught inside the field's radius — its own
	# shooter's, or one that just flew in from outside — gets redirected straight toward the centre every
	# frame (same speed, new direction), same "no escape" treatment the field gives the enemies themselves.
	# It still can't hit its OWN shooter (_bullet_hits_enemy excludes the owner, unchanged) but very
	# routinely ends up hitting some OTHER enemy also being dragged toward that same point.
	var eventh: Dictionary = aw.call("event_horizon_field") if (aw != null and aw.has_method("event_horizon_field")) else {"active": false}
	var eventh_on: bool = bool(eventh.get("active", false))
	var eventh_pos: Vector2 = eventh.get("pos", Vector2.ZERO)
	var eventh_r: float = float(eventh.get("radius", 0.0))
	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		if eventh_on and (b["pos"] as Vector2).distance_to(eventh_pos) <= eventh_r:
			var to_center := eventh_pos - (b["pos"] as Vector2)
			if to_center.length() > 1.0:
				b["vel"] = to_center.normalized() * (b["vel"] as Vector2).length()
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) + delta
		var p: Vector2 = b["pos"]
		var blocked := false
		for blk: Dictionary in blocks:
			if p.distance_to(blk["pos"]) <= float(blk["r"]) + BULLET_RADIUS:
				blocked = true
				break
		if blocked:
			_bullets.remove_at(i)
		elif p.distance_to(sc) <= sr + BULLET_RADIUS:
			_report_bullet_owner(int(b.get("owner", 0)))
			GameManager.ship_take_damage(int(b["dmg"]))
			_bullets.remove_at(i)
		elif _bullet_hits_enemy(p, int(b.get("owner", 0)), int(b["dmg"])):
			_bullets.remove_at(i)   # bullets also damage enemies (charmed shooters fire on the swarm; friendly fire)
		else:
			var max_dist := JF_BULLET_MAX_DIST if String(b.get("kind", "")) == "jetfighter" else BULLET_MAX_DIST
			if float(b["life"]) >= BULLET_MAX_LIFE or p.distance_to(b["start"]) >= max_dist:
				_bullets.remove_at(i)
		i -= 1

## RUN OVER's "last hit by" — resolves a bullet's owner instance id (arena_enemy.gd's group "arena_enemy")
## back to the enemy node and records it. No-op if the owner is gone/invalid (already died, etc.).
func _report_bullet_owner(owner_id: int) -> void:
	if owner_id == 0 or not GameManager.has_method("record_last_hit"):
		return
	var owner := instance_from_id(owner_id)
	if owner != null and is_instance_valid(owner):
		GameManager.record_last_hit(String(owner.get("_type")).capitalize(), String(owner.get("_original_icon")))

## World position to test a hit against for `en` — nearest_hit_point() when the enemy exposes one (currently
## only Centipede, whose long segmented body is drawn well past its single collidable global_position — see
## arena_enemy.gd's own doc comment on nearest_hit_point()), else just en.global_position unchanged.
## 2026-08-06, bug fix: this manager's own AoE/bullet hit-tests (_bullet_hits_enemy/explode/retaliation below)
## used to read global_position directly, same class of bug arena_weapons.gd's _hit_pos() was already built
## to avoid for its own hit-tests — Centipede's body/tail segments (9 of its 10 CENTI_SEGMENTS) silently
## couldn't be hit through THESE particular paths, only its head, which reads as "unkillable" since most of
## what's on screen is the un-hittable body.
func _enemy_hit_pos(en: Node, test_pos: Vector2) -> Vector2:
	if en.has_method("nearest_hit_point"):
		return en.call("nearest_hit_point", test_pos)
	return (en as Node2D).global_position

## A bullet at `p` damages the first enemy it touches (excluding its owner). Returns true if it hit one.
func _bullet_hits_enemy(p: Vector2, owner_id: int, dmg: int) -> bool:
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en) or en.get_instance_id() == owner_id:
			continue
		var er: float = float(en.get("_radius")) if en.get("_radius") != null else 16.0
		if p.distance_to(_enemy_hit_pos(en, p)) <= er + BULLET_RADIUS:
			if en.has_method("take_damage"):
				en.take_damage(float(dmg))
			return true
	return false

# ── Explosions (cross-faction blast) ────────────────────────────────────────────
func explode(blast_center: Vector2, blast_radius: float, dmg: int, source: Node = null) -> void:
	# Player
	if ship_center().distance_to(blast_center) <= blast_radius + ship_radius():
		if source != null and is_instance_valid(source) and GameManager.has_method("record_last_hit"):
			GameManager.record_last_hit(String(source.get("_type")).capitalize(), String(source.get("_original_icon")))
		GameManager.ship_take_damage(dmg)
	# All enemies (skip the source so a bomb doesn't re-hit itself in a chain)
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if en == source or not is_instance_valid(en):
			continue
		if _enemy_hit_pos(en, blast_center).distance_to(blast_center) <= blast_radius and en.has_method("take_damage"):
			en.take_damage(float(dmg))
	# Ruin ships/boxes also take blast damage
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if ruin == source or not is_instance_valid(ruin):
			continue
		if (ruin as Node2D).global_position.distance_to(blast_center) <= blast_radius and ruin.has_method("take_damage"):
			ruin.take_damage(float(dmg))
	_explosions.append({"pos": blast_center, "age": 0.0, "max_age": 0.4, "radius": blast_radius})

func _tick_explosions(delta: float) -> void:
	var i := _explosions.size() - 1
	while i >= 0:
		var e: Dictionary = _explosions[i]
		e["age"] = float(e["age"]) + delta
		if float(e["age"]) >= float(e["max_age"]):
			_explosions.remove_at(i)
		i -= 1

## Drop a collectible XP orb at a world position. Delegates to the single MultiMesh orb manager (no
## per-orb node) — keeps the same signature so arena_enemy / arena_elephant callers are unchanged.
func spawn_xp_orb(pos: Vector2, value: float) -> void:
	var mgr := get_tree().get_first_node_in_group("arena_xp_orb_mgr")
	if mgr != null:
		mgr.spawn(pos, value)

## Drop a loot item (coin / diamond / heart / magnetic / shield) at a world position.
func spawn_loot(pos: Vector2, type: String, value: int = 50) -> void:
	var l := LootScript.new()
	get_parent().add_child(l)
	l.setup(pos, type, value)

## Drop a bomb enemy at a world position (falls toward the player, explodes on contact/death).
func spawn_bomb(pos: Vector2) -> void:
	var b := ArenaEnemyScript.new()
	b.configure("bomb", self)
	b.position = pos
	get_parent().add_child(b)

## Throw a FAST bomb from `pos` aimed straight at the player (it auto-aims on init, explodes on contact).
func throw_bomb(pos: Vector2) -> void:
	var b := ArenaEnemyScript.new()
	b.configure("thrown_bomb", self)
	b.position = pos
	get_parent().add_child(b)

## Spawn a small flock of bee enemies near the player — used by the F12 debug palette to test plume VFX.
func spawn_bee() -> void:
	const BEE_DEF := {"behavior": "swarm_dive", "hp": 20.0, "speed": 150.0, "size": 12.0,
		"contact": 8, "explodes": true, "xp": 20.0, "icon": "res://assets/map/electric/enemies/animalbee.png"}
	var pp := ship_center()
	for i in 6:
		var e := ArenaEnemyScript.new()
		e.configure("bee", self, BEE_DEF)
		var a := TAU * float(i) / 6.0
		e.position = pp + Vector2(cos(a), sin(a)) * 500.0
		get_parent().add_child(e)

const RETALIATION_RADIUS := 220.0   # Barbed Wire aux: enemies within this of the player take the return hit

func _play_hit() -> void:
	if _hit_player != null:
		_hit_player.stop()
		_hit_player.play()
	_hit_flash_t = HIT_FLASH_DUR
	# Barbed Wire: flat retaliation + the reflect perk (100%/rank of the damage taken) as a kinetic AoE blast.
	var retal: float = GameManager.upg_retaliation if "upg_retaliation" in GameManager else 0.0
	var reflect: float = GameManager._last_hp_dmg * GameManager.mech_bonus("reflect_taken") if GameManager.has_method("mech_bonus") else 0.0
	var total := retal + reflect
	if total > 0.0:
		var center := ship_center()
		var aoe: float = GameManager.mech_bonus("aoe_pct") if GameManager.has_method("mech_bonus") else 0.0
		var radius := maxf(RETALIATION_RADIUS, 200.0 * (1.0 + aoe))
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en):
				continue
			if _enemy_hit_pos(en, center).distance_to(center) <= radius and en.has_method("take_damage"):
				en.take_damage(total)

# ── Draw bullets + explosion rings (world space) ───────────────────────────────
func _draw() -> void:
	for b: Dictionary in _bullets:
		if String(b.get("kind", "")) == "jetfighter":
			continue   # rendered via _jf_mm (MultiMesh) instead — see _sync_jf_multimesh()
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"]
		var dir := v.normalized() if v.length() > 0.01 else Vector2.UP
		var tail := p - dir * 9.0
		draw_line(tail, p, Color(BULLET_COLOR.r, BULLET_COLOR.g, BULLET_COLOR.b, 0.5), 3.0)
		draw_circle(p, BULLET_RADIUS, BULLET_COLOR)
		draw_circle(p, BULLET_RADIUS * 0.5, Color(1, 1, 1, 0.9))
	for e: Dictionary in _explosions:
		var t := clampf(float(e["age"]) / maxf(0.01, float(e["max_age"])), 0.0, 1.0)
		var r := float(e["radius"]) * (0.4 + 0.6 * t)
		draw_arc(e["pos"], r, 0.0, TAU, 32, Color(1.0, 0.55, 0.2, 1.0 - t), 3.0)
		draw_circle(e["pos"], r * 0.5, Color(1.0, 0.7, 0.3, (1.0 - t) * 0.4))

## MultiMeshInstance2D for every "jetfighter"-kind bullet (arena_enemy.gd's "shooter" behavior + spawn_mode_2's
## "steer_kiter") — same technique as arena_weapons.gd's Gatling tracer (_setup_gat_multimesh), ported here
## since these bullets live in a different array/script. Sprite scaled to JF_BULLET_LEN height, width from
## the source aspect ratio (never stretched, per the project's image rules).
func _setup_jf_multimesh() -> void:
	var tex := load(JF_BULLET_TEX) as Texture2D
	if tex == null:
		return
	_jf_mm = MultiMeshInstance2D.new()
	_jf_mm.texture = tex
	_jf_mm.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	var quad := QuadMesh.new()
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var disp_h := JF_BULLET_LEN
	var disp_w := disp_h * tw / maxf(1.0, th)
	quad.size = Vector2(disp_w, disp_h)
	mm.mesh = quad
	mm.instance_count = JF_MM_MAX
	mm.visible_instance_count = 0
	_jf_mm.multimesh = mm
	add_child(_jf_mm)

## Rewrites every visible instance transform from the "jetfighter"-kind subset of _bullets — called once per
## frame right after _tick_bullets() moves/removes them. Sprite's default pose assumed nose-up (-Y); flip
## JF_SPRITE_ROT_OFFSET's sign if the art's nose turns out to face the other way (untested assumption, same
## caveat as arena_weapons.gd's GAT_SPRITE_ROT_OFFSET).
const JF_SPRITE_ROT_OFFSET := PI * 0.5
func _sync_jf_multimesh() -> void:
	if _jf_mm == null:
		return
	var i := 0
	for b: Dictionary in _bullets:
		if i >= JF_MM_MAX:
			break
		if String(b.get("kind", "")) != "jetfighter":
			continue
		var vel: Vector2 = b.get("vel", Vector2.ZERO)
		var ang := (vel.angle() + JF_SPRITE_ROT_OFFSET) if vel.length_squared() > 0.01 else 0.0
		_jf_mm.multimesh.set_instance_transform_2d(i, Transform2D(ang, b["pos"] as Vector2))
		i += 1
	_jf_mm.multimesh.visible_instance_count = i
