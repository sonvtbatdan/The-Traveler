extends Node2D
## spawn_mode_2 — continuous procedural spawn director (survivor-like annulus spawning), parallel to the
## authored-timeline `arena_wave_director.gd`. Toggled by `arena.gd`'s `USE_SPAWN_MODE_2` const. Spawns a
## small 4-type test roster (one per new steering behavior: chaser/flanker/kiter/charger — see
## arena_enemy.gd `_tick_behavior` cases `"steer_chaser"/"steer_flanker"/"steer_kiter"/"steer_charger"`)
## in a ring (annulus) around the camera, at a batched rate up to an alive-cap, and teleports enemies that
## wander far behind the player back into the ring ahead of them. Does NOT touch the authored timeline,
## its ENEMY_DEFS entries, or Level_1_Minh.json.

const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const CreepInfoPanelScript := preload("res://scripts/ui/hud/creep_info_panel.gd")
const V1 := preload("res://scripts/gameplay/arena_wave_director.gd")

# ══ Annulus geometry ═══════════════════════════════════════════════════════════
const R_PADDING      := 150.0   # R_min = half the screen diagonal + this (never spawns in view)
const R_WIDTH         := 300.0  # R_max = R_min + this
const R_DESPAWN_MULT  := 1.5    # R_despawn = R_max * this — beyond it, teleport back into the ring

# ══ Spawn loop ═════════════════════════════════════════════════════════════════
# Tuned to match v1's early-game density (its first minute averages well under 1 enemy/sec alive at a
# time with a low-tens alive-count) rather than v1's late-run cap (500–1200 after 20 min of ramping) —
# this is a flat, unramped director, so its defaults should read as "gentle intro", not "endgame swarm".
const SPAWN_INTERVAL := 0.1     # seconds per spawn-loop tick
const TARGET_RATE    := 2.0     # enemies/sec actually admitted (batch patterns draw down the same budget — see _tick_spawn_loop)
const MAX_ALIVE_V2   := 120     # hard cap on live "arena_enemy" nodes
const SPAWN_BUDGET   := 4       # max enemy nodes instantiated per frame (drains _spawn_queue)
const DESPAWN_INTERVAL := 0.5   # throttle for the despawn/teleport sweep — corrective, not per-frame

# ══ Pattern tunables ═══════════════════════════════════════════════════════════
const CLUSTER_N_MIN   := 10
const CLUSTER_N_MAX   := 50
const CLUSTER_DELTA_R := 70.0   # jitter radius around the cluster anchor
const WALL_N          := 6      # units in a wall/grid-wave line
const WALL_WIDTH      := 660.0  # width of the line-abreast formation
const PATTERN_WEIGHTS := {"ambient": 0.6, "cluster": 0.25, "wall": 0.15}

# ══ Agony Rank — the harder-the-longer-you-survive difficulty knob for spawn_mode_2 ════════════════════
# Rank rises two ways: +1 every AGONY_TIME_INTERVAL survived, and +1 whenever the player clears
# FASTKILL_COUNT enemies within a rolling FASTKILL_WINDOW (edge-triggered — see _tick_fastkill — so a
# sustained massacre doesn't rank up every single frame it stays above threshold). Rank falls by 1 each
# time a death is saved by a revive (`GameManager.rebirth_used` — Phoenix Core's charge; the separate
# Project Phoenix/Player-2 revive in arena_weapons.gd does NOT emit that signal and is not covered here).
# No ceiling — TARGET_RATE's growth is only ever bounded by MAX_ALIVE_V2, so the horde can't runaway.
const AGONY_TIME_INTERVAL := 300.0   # +1 rank every 5 minutes survived (paused time doesn't count — see _process)
const AGONY_RATE_PER_RANK := 0.3     # flat enemies/sec added to the spawn rate per rank
const FASTKILL_WINDOW := 1.0         # seconds — rolling window for the fast-kill check
const FASTKILL_COUNT  := 20          # kills within FASTKILL_WINDOW → +1 rank (once per crossing, not per frame)

# ══ Champion — a stronger, gold-ringed spawn on its own timer, independent of the ambient/cluster/wall
# spawn loop and NOT gated by MAX_ALIVE_V2 (bosses/elites already bypass the cap in v1; same rule here).
const CHAMPION_BASE_TIME     := 150.0  # base time between Champions (2:30), at Agony Rank 0
const CHAMPION_TIME_PER_RANK := 9.0    # each rank shaves this many seconds off the interval
const CHAMPION_TIME_FLOOR    := 30.0   # interval never drops below this regardless of rank
const CHAMPION_HP_MULT    := 50.0   # HP mult still matches v1's milestone elites (elite_fly/bug/bee)
const CHAMPION_SIZE_MULT  := 2.0    # exactly double a normal creep's size (was 3× — v1's elite HP/size multiplier, no longer used for size here)
const CHAMPION_SPEED_MULT := 1.5

# ══ Test roster — one enemy per new steering behavior, stats/sprite/count-weight taken straight from
# v1's own early/low-tier roster (arena_wave_director.ENEMY_DEFS) so spawn_mode_2 fields the SAME kind
# of threat a fresh loadout can actually clear — only "behavior" is overridden to the new steer_* move
# logic. Built in _ready() (duplicating a dict isn't a valid const expression). ────────────────────────
const TEST_ROSTER := {
	"test_chaser":  {"base": "fly",         "behavior": "steer_chaser"},    # v1's very first intro enemy (hp 20, speed 80)
	"test_flanker": {"base": "dragonfly",   "behavior": "steer_flanker"},   # light, fast (hp 30, speed 130)
	"test_kiter":   {"base": "shooter",     "behavior": "steer_kiter", "hp_mult": 1.5},   # "jetfighter" sprite, HP +50%
	"test_charger": {"base": "animalhornet", "hp_mult": 1.3},   # no "behavior" override → back to animalhornet's OWN
	                                                             # default ("bomber": roam near the player, drop bombs)
	                                                             # instead of the steer_charger dash — HP +30%
}
const TEST_TYPES := ["test_chaser", "test_flanker", "test_kiter", "test_charger"]
# Wave order reference — v1's own intro timeline: fly@1s, dragonfly@46s, shooter@55s. animalhornet never
# appears in v1's early game at all, so it's introduced last, a bit after the other three. The run always
# opens on flies alone (test_chaser unlocks at t=0) instead of a uniform-random pick across all 4 from
# the very first spawn.
const TYPE_UNLOCK_TIME := {
	"test_chaser":  0.0,
	"test_flanker": 46.0,
	"test_kiter":   55.0,
	"test_charger": 90.0,
}

# ══ Minimum-population floor — never let the field go empty ════════════════════════════════════════
# If the live count stays below LOW_COUNT_THRESHOLD for LOW_COUNT_GRACE seconds straight, catch-up kicks
# in: an INSTANT CATCHUP_BURST-sized queue push the moment it triggers (still queue+budget-drained on
# instantiation — never an actual same-frame dump — but not waiting on the rate accumulator to ramp up
# either), then the spawn loop keeps running at CATCHUP_RATE up to CATCHUP_TARGET before handing control
# back to the normal Agony-scaled rate against the usual MAX_ALIVE_V2 cap.
const LOW_COUNT_THRESHOLD := 20
const LOW_COUNT_GRACE     := 2.0
const CATCHUP_BURST       := 50    # queued immediately the instant catch-up triggers
const CATCHUP_TARGET      := 100   # catch-up keeps running (past the burst) until alive reaches this, then turns off
const CATCHUP_RATE        := 15.0   # enemies/sec for the climb from CATCHUP_BURST up to CATCHUP_TARGET

# ══ Opening-surge multiplier — the field reads as too sparse for the first stretch at a flat 2/s. Starts
# at 3× (triple) the normal rate from t=0; once the field first passes START_BOOST_TRIGGER alive, decays
# smoothly back down (passing through 2× — double — at the halfway point) to 1× over START_BOOST_DECAY_T,
# then it's just the plain TARGET_RATE/Agony formula. Only scales the NORMAL rate, not the low-population
# catch-up rate above (that one already has its own fixed, higher CATCHUP_RATE). Deliberately its OWN
# constant, not CATCHUP_TARGET — the two used to be the same number by coincidence, but decoupled once
# CATCHUP_TARGET moved to 100 (this should still trigger at the original 50, not wait twice as long).
const START_BOOST_MULT     := 3.0
const START_BOOST_TRIGGER  := 50
const START_BOOST_DECAY_T  := 60.0   # seconds to linearly decay 3× → 1× once triggered

# ══ Timeline engine (F7 Wave Edit support) ═════════════════════════════════════════════════════════
# A SECOND, OPTIONAL spawn channel the F7 editor authors — runs alongside the continuous annulus loop
# above (which keeps going unchanged); this is purely additive. Ported from arena_wave_director.gd's
# proven pattern/stream logic (kept as a straight port rather than sharing code — GDScript has no
# mixins, and v1 is locked/tuned, so it's not touched). Differences from v1, all deliberate:
#   • Radius uses v2's own annulus (_r_min/_r_max), not v1's fixed SPAWN_RADIUS — timeline spawns still
#     honor "never spawn in view" the same way the continuous loop does.
#   • elapsed() is TIMELINE-relative (seconds since the timeline currently loaded was applied), not the
#     overall run clock — set_timeline() stamps _tl_start_t = _run_t. Reason: _run_t also drives Agony
#     Rank / unlock times / Champion timing and must never reset; but row times authored as "5, 10, 15…"
#     should always replay from their own start, whenever in the run you hit Apply, not skip ahead.
#   • Boss entries bypass the alive-cap (via _spawn_def's is_boss); ordinary timeline entries share
#     MAX_ALIVE_V2 with the continuous loop's own spawns (both funnel through the same cap check).
#   • Fleet deployment (type "fleet:<name>") IS ported — see _deploy_fleet()/_deploy_mothership_v2() near
#     _tl_queue_or_spawn(). Unlike v1, "count" on a fleet entry is honored (deploys the whole formation
#     that many times, matching a Unit slot's count — v1 explicitly ignores it).
#   • NOT ported: the Scorpion's gate_waves freeze-the-timeline mechanic, and the background texture
#     prewarm (a pure perf nicety in v1, not needed for correctness).
#   • Gap-spread (editing simplification, v2-only, no v1 equivalent): a filled row that follows a run of
#     blank 5s-grid rows has its count spread evenly across every GRID_SPREAD_STEP tick between the
#     PREVIOUS filled row and itself, instead of dumping the whole count in one instant burst — so
#     authoring just the occasional checkpoint total (row @10s, blanks, row @60s) reads the same as
#     manually filling every row in between. Applied once in set_timeline() (_spread_gaps()), producing
#     _tl_fire_queue — the SPARSE, exactly-as-authored `timeline` (what get_timeline()/Save/Load see, so
#     re-opening F7 still shows your original rows, not a wall of tiny expanded ones) is left untouched;
#     _tl_tick() fires from the expanded queue instead. The first entry in a timeline never spreads
#     (nothing precedes it to spread FROM); "Boss" entries and "stream" entries are exempt (a boss is a
#     single dramatic moment, not a name in the entry's own dictionary and streams already have their
#     own ramp/duration spread — stacking gap-spread on top would double up).
const PATTERNS := ["ring", "arc", "stream", "scatter", "pincer", "wall", "wedge", "portal", "random"]
const RANDOM_FORMATIONS := ["ring", "pincer", "wall", "wedge", "portal"]
const TL_BLOB_SPAWN_R := 90.0    # cluster radius for a "blob" def (e.g. "swarm", blob:50), timeline path only
const GRID_SPREAD_STEP := 5.0    # matches the F7 editor's row grid (GRID_STEP in arena_wave_editor.gd)

# ══ Per-type hard cap — "missile" launchers hold position near the player (behavior "missile", standoff)
# and are NOT covered by _tick_despawn_teleport() (that only recycles "steer_*" behaviors), so multiple
# timeline waves' worth of them pile up on screen indefinitely instead of getting culled/replaced. Capped
# unconditionally at MISSILE_MAX_ALIVE, checked in _spawn_def() (the one funnel every spawn path — timeline
# ring/scatter, catch-up reinforcement, cluster/wall — goes through) and excluded from _reinforce_type()'s
# candidate pool once at cap, so the low-population rescue doesn't try to push it over either.
const MISSILE_TYPE_ID  := "missile"
const MISSILE_MAX_ALIVE := 4

var timeline: Array = []          # live, F7-editable, SPARSE — {time, type, count, pattern, [duration], [is_boss], ...}
var _tl_fire_queue: Array = []    # timeline with gap-spread applied — what _tl_tick() actually fires from
var _tl_start_t: float = 0.0  # _run_t at the moment set_timeline() was last called — elapsed() is relative to this
var _tl_next: int = 0         # index into _tl_fire_queue of the next entry to fire
var _tl_streams: Array = []   # active "stream" entries: {type, left, dur, elapsed, r0, ramp, credit, is_boss, ...}
var _tl_seen_types: Dictionary = {}   # set of "safe" (non-boss/elite/blob) type ids the timeline has fired SO FAR — read by _reinforce_type()

# ══ Runtime ════════════════════════════════════════════════════════════════════
var ENEMY_DEFS_V2: Dictionary = {}   # built in _ready(): TEST_ROSTER resolved against V1.ENEMY_DEFS
var ENEMY_DEFS: Dictionary = {}   # V1.ENEMY_DEFS duplicated + ENEMY_DEFS_V2 merged in (see _ready)
var _player: Node2D = null
var _mgr: Node = null
var _player_vel := Vector2.ZERO
var _last_player_pos := Vector2.ZERO
var _spawn_acc := 0.0
var _despawn_acc := 0.0
var _spawn_queue: Array = []   # {type, pos}, drained SPAWN_BUDGET/frame

# ── Agony Rank state ──
var _agony_rank: int = 0
var _run_t: float = 0.0          # local elapsed clock — only advances while this node processes (i.e. unpaused)
var _agony_time_acc: float = 0.0
var _last_run_kills: int = 0     # last-seen GameManager.run_kills, to diff new kills per frame
var _kill_times: Array = []      # timestamps (_run_t) of recent kills, trimmed to the last FASTKILL_WINDOW
var _fastkill_armed: bool = true # edge-trigger guard: re-arms once the rolling count drops back below threshold
var _champion_acc: float = 0.0

# ── Minimum-population catch-up state ──
var _low_count_timer: float = 0.0
var _catchup_active: bool = false

# ── Opening-surge state ──
var _start_boost_decaying: bool = false
var _start_boost_t: float = 0.0

# XP is proportional to HP, ratio pinned to v1's own "fly" (its very first intro enemy): xp/hp there is
# 10.0/20.0 = 0.5 XP per HP (2026-07-28: every XP source, incl. fly's, scaled ×10 — was 1.0/20.0 = 0.05).
# Applied to every test-roster def's BASE hp (pre the automatic ×2 HP/XP tune in arena_enemy.configure() —
# since both sides double equally, the ratio survives the tune unchanged), and reapplied after Champion's
# hp scaling so a Champion's XP scales right along with its HP. Read live from ENEMY_DEFS in _ready() below
# (this initial value is just a placeholder, immediately overwritten), so it self-propagates automatically
# whenever fly's own "xp"/"hp" change — no separate edit needed here for future re-tunes.
var _xp_per_hp: float = 0.5

func _ready() -> void:
	add_to_group("wave_director")   # so _spawn_sibling / debug-spawn / weapon-palette lookups keep working
	var v1_defs: Dictionary = V1.ENEMY_DEFS
	var fly_def: Dictionary = v1_defs.get("fly", {})
	_xp_per_hp = float(fly_def.get("xp", 10.0)) / maxf(1.0, float(fly_def.get("hp", 20.0)))
	for k in TEST_ROSTER:
		var spec: Dictionary = TEST_ROSTER[k]
		var base_id := String(spec["base"])
		var def: Dictionary = (v1_defs.get(base_id, {}) as Dictionary).duplicate()
		if spec.has("behavior"):
			def["behavior"] = String(spec["behavior"])   # else: keep the base type's OWN behavior (e.g. animalhornet's "bomber")
		def["hp"] = float(def.get("hp", 20.0)) * float(spec.get("hp_mult", 1.0))
		def["xp"] = float(def["hp"]) * _xp_per_hp   # computed AFTER hp_mult so XP stays proportional to the boosted HP
		ENEMY_DEFS_V2[k] = def
	ENEMY_DEFS = v1_defs.duplicate(true)
	for k in ENEMY_DEFS_V2:
		ENEMY_DEFS[k] = ENEMY_DEFS_V2[k]
	CreepInfoPanelScript.apply_overrides(ENEMY_DEFS)   # Creep Info dev panel's saved HP/Move/Shoot overrides
	_player = get_tree().get_first_node_in_group("player")
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	if _player != null:
		_last_player_pos = _player.global_position
	_last_run_kills = GameManager.run_kills
	if GameManager.has_signal("rebirth_used"):
		GameManager.rebirth_used.connect(_on_resurrection_used)
	_load_remembered_timeline()

## Auto-loads whatever wave JSON was last Loaded via F7 (arena_wave_editor.gd._remember_last_wave), so a
## timeline picked in a previous run is still active on the next one without having to reopen F7 and
## Load it again. No-op if nothing was ever remembered, or the remembered file is missing/malformed —
## falls back to the plain continuous annulus loop either way. Per-map: each Map Pack entry remembers its
## OWN last-loaded file (Rubicon's spawn config edits never touch Default's) — _last_wave_cfg_path()'s
## logic MUST match the copy in arena_wave_editor.gd (that's the writer; this is the reader).
func _last_wave_cfg_path() -> String:
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	if map_id != "default" and map_id != "":
		return "res://spawn_mode_2_wave_%s.cfg" % map_id
	return "res://spawn_mode_2_wave.cfg"

func _load_remembered_timeline() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_last_wave_cfg_path()) != OK:
		return
	var fname := String(cfg.get_value("wave", "last_file", ""))
	if fname == "":
		return
	var f := FileAccess.open("res://levels/arena/" + fname, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("timeline"):
		return
	set_timeline((parsed as Dictionary)["timeline"])

func enemy_types() -> Array:
	return ENEMY_DEFS.keys()

## Read by the "steer_flanker" behavior (arena_enemy.gd) to predict the player's future position.
func player_velocity() -> Vector2:
	return _player_vel

func agony_rank() -> int:
	return _agony_rank

# ── Timeline editor API (F7 Wave Edit — arena_wave_editor.gd) ──────────────────────────────────────
func get_timeline() -> Array:
	return timeline

## Replace the timeline and restart its playback from "t=0" relative to right now (see the class-level
## comment on elapsed() above for why this doesn't touch _run_t/Agony/Champion state). Also rebuilds the
## gap-spread firing queue (_tl_fire_queue) — see the class-level comment on gap-spread.
func set_timeline(entries: Array) -> void:
	timeline = entries.duplicate(true)
	timeline.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	_tl_fire_queue = _spread_gaps(timeline)
	_tl_start_t = _run_t
	_tl_next = 0
	_tl_streams.clear()
	_tl_seen_types.clear()

## Expand `sorted` (already time-sorted) into the actual firing queue: a filled entry that follows a gap
## since the previous entry has its count divided evenly across every ~GRID_SPREAD_STEP tick spanning that
## gap (tick spacing = gap / round(gap / GRID_SPREAD_STEP), so the LAST tick always lands exactly on the
## entry's own authored time, even if that time isn't itself grid-aligned). Remainder units go to the
## final ticks so the total spawned always equals the authored count exactly. Skipped (passed through
## unchanged) for: the first entry (nothing precedes it), "Boss" entries, and "stream" entries.
func _spread_gaps(sorted: Array) -> Array:
	var out: Array = []
	var prev_t := 0.0
	var has_prev := false
	for entry: Dictionary in sorted:
		var t := float(entry.get("time", 0.0))
		var pattern := String(entry.get("pattern", "ring"))
		var is_boss := bool(entry.get("is_boss", false))
		var gap := t - prev_t
		if not has_prev or is_boss or pattern == "stream" or gap <= GRID_SPREAD_STEP:
			out.append(entry)
			prev_t = t
			has_prev = true
			continue
		var n_ticks: int = maxi(1, int(round(gap / GRID_SPREAD_STEP)))
		var step := gap / float(n_ticks)
		var total := maxi(1, int(entry.get("count", 1)))
		var base := total / n_ticks
		var rem := total % n_ticks
		for k in n_ticks:
			var n := base + (1 if k >= n_ticks - rem else 0)   # remainder → the LAST ticks (so the tick landing on t always fires)
			if n <= 0:
				continue
			var sub := entry.duplicate(true)
			sub["time"] = prev_t + step * float(k + 1)
			sub["count"] = n
			out.append(sub)
		prev_t = t
		has_prev = true
	return out

## Seconds since the current timeline was applied (NOT the overall run clock — see class comment).
func elapsed() -> float:
	return _run_t - _tl_start_t

## Phoenix Core spent a revive charge to save this death — Agony Rank drops a level (never below 0), which
## directly softens the spawn rate again (see _tick_spawn_loop).
func _on_resurrection_used() -> void:
	_agony_rank = maxi(0, _agony_rank - 1)

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	var pos := _player.global_position
	_player_vel = (pos - _last_player_pos) / delta if delta > 0.0 else Vector2.ZERO
	_last_player_pos = pos
	_run_t += delta
	var alive := get_tree().get_node_count_in_group("arena_enemy")
	_tick_agony_time(delta)
	_tick_agony_fastkill()
	_tick_low_count_watch(delta, alive)
	_tick_start_boost(delta, alive)
	_tick_champion(delta)
	_tick_spawn_loop(delta, alive)
	_tl_tick(delta)
	_drain_spawn_queue()
	_despawn_acc += delta
	if _despawn_acc >= DESPAWN_INTERVAL:
		_despawn_acc = 0.0
		_tick_despawn_teleport()

# ── Agony Rank ──────────────────────────────────────────────────────────────────
func _tick_agony_time(delta: float) -> void:
	_agony_time_acc += delta
	while _agony_time_acc >= AGONY_TIME_INTERVAL:
		_agony_time_acc -= AGONY_TIME_INTERVAL
		_agony_rank += 1

## Rolling FASTKILL_WINDOW-second kill count via GameManager.run_kills (arena-wide kill tally, incremented
## in arena_enemy.gd._die regardless of which director spawned the victim). Edge-triggered: ranks up once
## when the count first reaches FASTKILL_COUNT, then re-arms only after it drops back below.
func _tick_agony_fastkill() -> void:
	var rk: int = GameManager.run_kills
	var new_kills := rk - _last_run_kills
	_last_run_kills = rk
	for i in maxi(0, new_kills):
		_kill_times.append(_run_t)
	while not _kill_times.is_empty() and _run_t - float(_kill_times[0]) > FASTKILL_WINDOW:
		_kill_times.pop_front()
	if _kill_times.size() >= FASTKILL_COUNT:
		if _fastkill_armed:
			_agony_rank += 1
			_fastkill_armed = false
	else:
		_fastkill_armed = true

## Minimum-population floor: alive < LOW_COUNT_THRESHOLD sustained for LOW_COUNT_GRACE seconds triggers
## catch-up — an immediate CATCHUP_BURST-sized queue push (_catchup_burst(), fired once on the rising
## edge only) plus the ongoing rate climb in _tick_spawn_loop; it clears itself once alive reaches
## CATCHUP_TARGET.
func _tick_low_count_watch(delta: float, alive: int) -> void:
	if alive < LOW_COUNT_THRESHOLD:
		_low_count_timer += delta
		if _low_count_timer >= LOW_COUNT_GRACE and not _catchup_active:
			_catchup_active = true
			_catchup_burst()
	else:
		_low_count_timer = 0.0
	if _catchup_active and alive >= CATCHUP_TARGET:
		_catchup_active = false

## Instant reinforcement the moment catch-up triggers: queues CATCHUP_BURST spawns right away (still
## budget-drained on actual instantiation by the existing _drain_spawn_queue(), so no same-frame stall —
## "immediate" means not waiting on the rate accumulator, not literally 50 add_child() calls in one frame).
func _catchup_burst() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var c := _player.global_position
	for i in CATCHUP_BURST:
		_spawn_queue.append({"type": _reinforce_type(), "pos": _annulus_pos(c)})

## Opening-surge: 3× rate from t=0 until the field first passes START_BOOST_TRIGGER alive, then linearly
## decays back to 1× over START_BOOST_DECAY_T (passing through 2× at the halfway point). Read by
## _tick_spawn_loop via _start_boost_mult().
func _tick_start_boost(delta: float, alive: int) -> void:
	if not _start_boost_decaying:
		if alive > START_BOOST_TRIGGER:
			_start_boost_decaying = true
	else:
		_start_boost_t += delta

func _start_boost_mult() -> float:
	if not _start_boost_decaying:
		return START_BOOST_MULT
	var f := clampf(_start_boost_t / START_BOOST_DECAY_T, 0.0, 1.0)
	return lerpf(START_BOOST_MULT, 1.0, f)

func _champion_interval() -> float:
	return maxf(CHAMPION_TIME_FLOOR, CHAMPION_BASE_TIME - CHAMPION_TIME_PER_RANK * float(_agony_rank))

func _tick_champion(delta: float) -> void:
	_champion_acc += delta
	if _champion_acc < _champion_interval():
		return
	_champion_acc = 0.0
	_spawn_champion()

## A Champion is one of the 4 test-roster archetypes (random pick) scaled up with v1's own milestone-elite
## multipliers (CHAMPION_HP/SIZE/SPEED_MULT) and flagged "elite" (bypasses MAX_ALIVE_V2, grants a reward on
## death — same as v1's elite_fly/bug/bee) plus "champion" (arena_enemy.gd draws the gold ring). Spawned
## straight into the annulus like any other enemy, bypassing the normal spawn-loop's room budget (same
## exemption v1 gives bosses/elites).
func _spawn_champion() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var base_type: String = _rand_test_type()   # respects TYPE_UNLOCK_TIME — no charger champion before charger itself has unlocked
	var def: Dictionary = (ENEMY_DEFS_V2.get(base_type, {}) as Dictionary).duplicate()
	if def.is_empty():
		return
	def["hp"] = float(def.get("hp", 30.0)) * CHAMPION_HP_MULT
	def["size"] = float(def.get("size", 16.0)) * CHAMPION_SIZE_MULT
	def["speed"] = float(def.get("speed", 95.0)) * CHAMPION_SPEED_MULT
	def["xp"] = float(def["hp"]) * _xp_per_hp   # recompute AFTER the hp scale so XP stays proportional to HP
	def["elite"] = true      # cap-bypass + grant_reward on death (arena_enemy.gd _is_elite)
	def["champion"] = true   # gold-ring visual only (arena_enemy.gd _is_champion)
	_spawn_def(base_type, def, _annulus_pos(_player.global_position))

# ── Annulus geometry helpers ────────────────────────────────────────────────────
func _r_min() -> float:
	var half_diag := 400.0
	if _mgr != null and _mgr.has_method("screen_size"):
		half_diag = (_mgr.call("screen_size") as Vector2).length() * 0.5
	return half_diag + R_PADDING

func _r_max() -> float:
	return _r_min() + R_WIDTH

## A random point in [R_min, R_max] around `center` (or the player if omitted), at `angle` (random if NAN).
func _annulus_pos(center: Vector2, angle: float = NAN) -> Vector2:
	var a := angle if not is_nan(angle) else randf() * TAU
	var r := randf_range(_r_min(), _r_max())
	return center + Vector2(cos(a), sin(a)) * r

# ── Spawn loop: batch size = min(rate*dt, cap - alive), queued + budget-drained ─────────────────────
# Fractional accumulator (see CLAUDE.md's "sub-integer tick rates" pattern), but the credit spent per
# firing equals the actual unit COUNT of the batch (1 for ambient, up to 50 for cluster, WALL_N for
# wall) — NOT a flat 1.0 — so TARGET_RATE is the true average enemies/sec regardless of which pattern
# gets picked (a flat-1.0 spend would let cluster bursts spawn ~20× faster than the rate implies).
# While a low-count catch-up is active (_tick_low_count_watch), the cap/rate swap to CATCHUP_TARGET/RATE
# so the field refills toward 50 quickly — still gradual (queue+budget-drained, not an instant dump) —
# then control reverts to the normal MAX_ALIVE_V2 cap and Agony-scaled rate once alive reaches 50. The
# normal (non-catch-up) rate additionally carries the opening-surge multiplier (_start_boost_mult) — 3×
# from t=0, decaying back to 1× once the field first passes 50 alive.
# When a custom F7 timeline is loaded (`timeline` non-empty), the NORMAL ambient/cluster/wall path steps
# aside entirely — the timeline becomes the sole source of ordinary spawns, so what's on screen matches
# exactly what was authored, no "stray" test-roster enemies mixed in. The catch-up path below is NOT
# gated by this — a population-floor rescue still fires (from the test roster) even with a timeline
# loaded, so the field can never truly empty out; Champion (_tick_champion, called separately) is also
# untouched. _spawn_acc deliberately doesn't accumulate while skipped, so returning to a blank timeline
# later doesn't unleash a built-up burst.
func _tick_spawn_loop(delta: float, alive: int) -> void:
	if not _catchup_active and not timeline.is_empty():
		return
	var cap := CATCHUP_TARGET if _catchup_active else MAX_ALIVE_V2
	var room := cap - alive
	if room <= 0:
		return
	var rate := CATCHUP_RATE if _catchup_active else ((TARGET_RATE + AGONY_RATE_PER_RANK * float(_agony_rank)) * _start_boost_mult())
	_spawn_acc += rate * delta
	while _spawn_acc >= 1.0 and room > 0:
		var pattern := _pick_pattern()
		match pattern:
			"cluster":
				var n: int = mini(randi_range(CLUSTER_N_MIN, CLUSTER_N_MAX), room)
				_queue_cluster(n)
				_spawn_acc -= float(n)
				room -= n
			"wall":
				var n: int = mini(WALL_N, room)
				_queue_wall(n)
				_spawn_acc -= float(n)
				room -= n
			_:
				_queue_ambient(1)
				_spawn_acc -= 1.0
				room -= 1

func _pick_pattern() -> String:
	var roll := randf()
	var acc := 0.0
	for k in PATTERN_WEIGHTS:
		acc += float(PATTERN_WEIGHTS[k])
		if roll <= acc:
			return String(k)
	return "ambient"

## Random pick restricted to types already "unlocked" at the current run time (TYPE_UNLOCK_TIME) — the
## run always opens on flies alone (test_chaser unlocks at t=0) instead of a uniform pick across all 4
## from the very first spawn.
func _rand_test_type() -> String:
	var pool: Array = []
	for t in TEST_TYPES:
		if _run_t >= float(TYPE_UNLOCK_TIME.get(t, 0.0)):
			pool.append(t)
	if pool.is_empty():
		pool = [TEST_TYPES[0]]
	return String(pool[randi() % pool.size()])

## Type for ambient/cluster/wall queuing. These only ever fire during the low-population catch-up while a
## custom timeline is loaded — the normal path stands aside entirely (see _tick_spawn_loop) — so
## reinforcement picks from _tl_seen_types (what the timeline has ALREADY spawned; never something from a
## later/harder wave that hasn't fired yet — "không vượt cấp"), falling back to the single weakest type
## if nothing has fired yet. No timeline loaded → unchanged, the default 4-type roster gated by
## TYPE_UNLOCK_TIME (same pool Champion still always uses via _rand_test_type(), untouched by this).
func _reinforce_type() -> String:
	if not timeline.is_empty():
		if not _tl_seen_types.is_empty():
			var keys := _tl_seen_types.keys()
			# "missile" piles up (never despawns — see MISSILE_MAX_ALIVE's comment), so once it's at cap,
			# stop offering it as a reinforcement candidate — the hard cap in _spawn_def() would silently
			# drop it anyway, but excluding it here also stops it from crowding out other candidates by
			# "winning" the random pick and then spawning nothing.
			if _type_alive_count(MISSILE_TYPE_ID) >= MISSILE_MAX_ALIVE:
				keys = keys.filter(func(k: Variant) -> bool: return String(k) != MISSILE_TYPE_ID)
			if keys.is_empty():
				return TEST_TYPES[0]
			return String(keys[randi() % keys.size()])
		return TEST_TYPES[0]
	return _rand_test_type()

## Live count of a specific enemy type currently alive (group "arena_enemy"). Used by the "missile" hard
## cap — O(alive), only called at spawn-decision time (never every frame), so cheap even at 500 alive.
func _type_alive_count(type_id: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if String(e.get("_type")) == type_id:
			n += 1
	return n

## Ambient / Circle spawn — uniform random angle+radius on the annulus, one enemy at a time.
func _queue_ambient(n: int) -> void:
	var c := _player.global_position
	for i in n:
		_spawn_queue.append({"type": _reinforce_type(), "pos": _annulus_pos(c)})

## Swarm / Cluster spawn — one anchor on the annulus, N enemies scattered within CLUSTER_DELTA_R of it.
## `n` arrives already sized (randi_range(CLUSTER_N_MIN, CLUSTER_N_MAX), capped to remaining room) — no
## re-clamping here, or a low-room cap could get pushed back above the room it was clamped to.
func _queue_cluster(n: int) -> void:
	var c := _player.global_position
	var anchor := _annulus_pos(c)
	var t := _reinforce_type()   # one type per cluster reads as a deliberate "swarm", not noise
	for i in n:
		var off := anchor + Vector2(cos(randf() * TAU), sin(randf() * TAU)) * randf_range(0.0, CLUSTER_DELTA_R)
		_spawn_queue.append({"type": t, "pos": off})

## Wall / Grid Wave — a straight line abreast, perpendicular to one approach angle, advancing as one front.
func _queue_wall(n: int) -> void:
	var c := _player.global_position
	var a := randf() * TAU
	var wdir := Vector2(cos(a), sin(a))
	var wperp := Vector2(-wdir.y, wdir.x)
	var wcenter := c + wdir * randf_range(_r_min(), _r_max())
	var t := _reinforce_type()
	for k in n:
		var f := (float(k) / float(maxi(1, n - 1))) - 0.5
		_spawn_queue.append({"type": t, "pos": wcenter + wperp * (f * WALL_WIDTH)})

## Drains up to SPAWN_BUDGET spawns/frame, picking a RANDOM pending entry each time — NOT strict FIFO —
## so whichever wave is currently "in front" (e.g. a stream that just dumped its whole count in one frame)
## can't monopolize freed room; every source (timeline ring/scatter/wall/cluster, stream, catch-up) shares
## this one queue. Nothing is ever discarded: a spawn that fails (population at MAX_ALIVE_V2, or the
## "missile" hard cap) just stays queued and is retried on a later frame once room frees up — so a heavily
## oversubscribed wave file (JSON counts summing well past MAX_ALIVE_V2) still eventually spawns every
## authored unit, spread out over however long it takes kills to free room, instead of silently losing
## whatever didn't fit the instant it fired.
func _drain_spawn_queue() -> void:
	if _spawn_queue.is_empty():
		return
	if get_tree().get_node_count_in_group("arena_enemy") >= _effective_cap():
		return   # field is full — leave everything queued as-is, try again next frame
	var budget := SPAWN_BUDGET
	var tries := mini(_spawn_queue.size(), 50)   # bounded so a queue full of at-cap "missile" entries can't stall a frame
	while budget > 0 and tries > 0 and not _spawn_queue.is_empty():
		tries -= 1
		var idx := randi() % _spawn_queue.size()
		var it: Dictionary = _spawn_queue[idx]
		var node := _spawn(String(it["type"]), it["pos"] as Vector2)
		if node != null:
			_spawn_queue.remove_at(idx)
			budget -= 1
		# else: rejected by a per-type cap (e.g. "missile" at MISSILE_MAX_ALIVE) — leave queued, next pick tries another

func _spawn(type_id: String, pos: Vector2, is_boss: bool = false) -> Node:
	var src: Dictionary = ENEMY_DEFS.get(type_id, {})
	if src.is_empty():
		return null
	return _spawn_def(type_id, src.duplicate(), pos, is_boss)

## The cap the spawn loop / per-spawn guard target: MAX_ALIVE_V2 normally, CATCHUP_TARGET while a
## low-population catch-up is running (see _tick_low_count_watch), × the Beacon aux's spawn-rate mult.
func _effective_cap() -> int:
	var spawn_mult: float = GameManager.upg_spawn_rate_mult if "upg_spawn_rate_mult" in GameManager else 1.0
	var base := CATCHUP_TARGET if _catchup_active else MAX_ALIVE_V2
	return int(round(float(base) * spawn_mult))

## Shared instancing path — takes an already-built def directly (Champion spawns a scaled-up variant that
## isn't a registered ENEMY_DEFS entry; regular spawns just duplicate their def and call straight through).
## Bosses and "elite" defs (Champion) always spawn — the alive-cap only applies to ordinary enemies, same
## rule v1 uses. This is the one authoritative cap check (the continuous loop's own room bookkeeping in
## _tick_spawn_loop is just a pre-filter so it doesn't over-queue; this is the final gate everything —
## continuous loop, timeline, Champion — funnels through).
func _spawn_def(type_id: String, def: Dictionary, pos: Vector2, is_boss: bool = false) -> Node:
	# Unconditional — applies regardless of source (timeline, catch-up, cluster/wall) and ignores the
	# usual boss/elite cap-bypass, since "missile" itself is never boss/elite. See const comment above.
	if type_id == MISSILE_TYPE_ID and _type_alive_count(MISSILE_TYPE_ID) >= MISSILE_MAX_ALIVE:
		return null
	if not is_boss and not bool(def.get("elite", false)):
		if get_tree().get_node_count_in_group("arena_enemy") >= _effective_cap():
			return null
	var e := EnemyScript.new()
	e.configure(type_id, _mgr, def)
	e.position = pos
	get_parent().add_child(e)
	return e

# ── Timeline engine ──────────────────────────────────────────────────────────────────────────────
func _tl_tick(delta: float) -> void:
	var t := elapsed()
	while _tl_next < _tl_fire_queue.size() and float(_tl_fire_queue[_tl_next].get("time", 0.0)) <= t:
		_tl_fire(_tl_fire_queue[_tl_next])
		_tl_next += 1
	_tl_tick_streams(delta)

func _tl_fire(entry: Dictionary) -> void:
	var type_s := String(entry.get("type", ""))
	var is_boss := bool(entry.get("is_boss", false))
	if type_s.begins_with("fleet:"):
		# "n" (count) = how many times the whole formation deploys — same meaning as a Unit slot's count.
		# Not registered into _tl_seen_types: catch-up reinforcement spawns ONE type_id via _spawn_def(), it
		# has no concept of deploying a multi-unit formation, so fleets stay a timeline-only feature.
		for i in maxi(1, int(entry.get("count", 1))):
			_deploy_fleet(type_s.substr(6), is_boss)
		return
	var count := maxi(1, int(entry.get("count", 1)))
	var pattern := String(entry.get("pattern", "ring"))
	var angle_deg := float(entry.get("angle", NAN))   # optional fixed spawn heading (deg); NAN = random
	if not is_boss:
		# Track "safe" reinforcement candidates as the timeline actually plays out — never a boss, never
		# an elite-flagged type, never a "blob" type (a rescue shouldn't summon 50 units at once). Read by
		# _reinforce_type() so the low-population catch-up only ever backfills with something the timeline
		# has ALREADY spawned (no jumping ahead to a later/harder wave's roster — "không vượt cấp").
		var td: Dictionary = ENEMY_DEFS.get(type_s, {})
		if not bool(td.get("elite", false)) and int(td.get("blob", 1)) <= 1:
			_tl_seen_types[type_s] = true
	if pattern == "stream":
		var dur := maxf(0.01, float(entry.get("duration", 4.0)))
		var ramp := maxf(0.0, float(entry.get("ramp", 1.0)))   # end/start rate ratio; 1.0 = constant
		var r0 := float(count) / (dur * (1.0 + ramp) * 0.5)     # start rate; ramp integrates to count
		_tl_streams.append({
			"type": type_s, "left": count, "dur": dur, "elapsed": 0.0,
			"r0": r0, "ramp": ramp, "credit": 0.0, "is_boss": is_boss,
			"formation": String(entry.get("formation", "scatter")),
			"burst": maxi(1, int(entry.get("burst", 8))), "angle": angle_deg,
		})
		return
	if pattern == "random":
		pattern = RANDOM_FORMATIONS[randi() % RANDOM_FORMATIONS.size()]
	for pos: Vector2 in _tl_pattern_positions(pattern, count, angle_deg):
		_tl_queue_or_spawn(type_s, pos, is_boss)

func _tl_tick_streams(delta: float) -> void:
	var i := _tl_streams.size() - 1
	while i >= 0:
		var s: Dictionary = _tl_streams[i]
		s["elapsed"] = float(s["elapsed"]) + delta
		var frac: float = clampf(float(s["elapsed"]) / float(s["dur"]), 0.0, 1.0)
		var rate: float = float(s["r0"]) * (1.0 + (float(s["ramp"]) - 1.0) * frac)   # linear ramp r0 -> r0*ramp
		s["credit"] = float(s["credit"]) + rate * delta
		var ang := float(s.get("angle", NAN))
		var form := String(s.get("formation", "scatter"))
		if form != "scatter":   # any non-scatter formation bursts in that shape
			var burst: int = int(s["burst"])
			while float(s["credit"]) >= float(burst) and int(s["left"]) > 0:
				s["credit"] = float(s["credit"]) - float(burst)
				var n: int = mini(burst, int(s["left"]))
				var f := form
				if f == "random":
					f = RANDOM_FORMATIONS[randi() % RANDOM_FORMATIONS.size()]
				for pos: Vector2 in _tl_pattern_positions(f, n, ang):
					# Non-boss: queued (shared, randomized, never-discard drain — see _drain_spawn_queue())
					# instead of an immediate _spawn() call, so a fast-credit stream (e.g. duration≈0) can't
					# dump its whole count in one frame and monopolize whatever room is free right then.
					if bool(s["is_boss"]):
						_spawn(String(s["type"]), pos, true)
					else:
						_spawn_queue.append({"type": s["type"], "pos": pos})
				s["left"] = int(s["left"]) - n
		else:
			while float(s["credit"]) >= 1.0 and int(s["left"]) > 0:
				s["credit"] = float(s["credit"]) - 1.0
				var pos := _tl_one_position(ang)
				if bool(s["is_boss"]):
					_spawn(String(s["type"]), pos, true)
				else:
					_spawn_queue.append({"type": s["type"], "pos": pos})
				s["left"] = int(s["left"]) - 1
		if int(s["left"]) <= 0:
			_tl_streams.remove_at(i)
		i -= 1

func _tl_queue_or_spawn(type_id: String, pos: Vector2, is_boss: bool) -> void:
	if is_boss:
		_spawn(type_id, pos, true)
		var extra := int(GameManager.mech_bonus("extra_bosses")) if GameManager.has_method("mech_bonus") else 0
		for i in extra:
			var a := TAU * float(i + 1) / float(extra + 1)
			_spawn(type_id, pos + Vector2(cos(a), sin(a)) * 160.0, true)
		return
	var src: Dictionary = ENEMY_DEFS.get(type_id, {})
	var blob := int(src.get("blob", 1))
	if blob > 1:
		for k in blob:
			var off := pos + Vector2(cos(randf() * TAU), sin(randf() * TAU)) * randf_range(0.0, TL_BLOB_SPAWN_R)
			_spawn_queue.append({"type": type_id, "pos": off})
		return
	_spawn_queue.append({"type": type_id, "pos": pos})

## Fleets are authored in Fleet Edit (res://fleet_layout.cfg) — same source arena_wave_director.gd's
## _deploy_fleet()/_deploy_mothership() read for v1. v1's own HP_MULT/SPEED_MULT knobs are both 1.0 (no-op),
## so skipped here — v2 already applies its tuning uniformly via arena_enemy.gd's configure(). A
## "mothership"-behavior slot deploys via _deploy_mothership_v2() (immediate, self-contained — the carrier
## manages its own docked escorts through init_mothership() regardless of which director spawned it, same
## as v1). Every other (generic) slot rolls ONE enemy from its own pool and joins the shared _spawn_queue —
## unlike v1's instant _spawn(), this respects MAX_ALIVE_V2 and the fair random drain (_drain_spawn_queue()).
func _deploy_fleet(fleet_name: String, is_boss: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var fleet: Dictionary = {}
	for fl in _load_fleets():
		if String((fl as Dictionary).get("name", "")) == fleet_name:
			fleet = fl
			break
	if fleet.is_empty():
		return
	var mother_slot: Dictionary = {}
	var child_slots: Array = []
	for s: Dictionary in (fleet.get("slots", []) as Array):
		var ids: Array = []
		for en in (s.get("enemies", []) as Array):
			if String(en) != "":
				ids.append(String(en))
		if ids.is_empty():
			continue
		var beh := String((ENEMY_DEFS.get(String(ids[0]), {}) as Dictionary).get("behavior", ""))
		if beh == "mothership" and mother_slot.is_empty():
			mother_slot = {"id": String(ids[0]), "slot": s}
		else:
			child_slots.append({"ids": ids, "slot": s})
	if not mother_slot.is_empty():
		_deploy_mothership_v2(mother_slot, child_slots)
		return
	# Generic formation: enters from a random off-screen annulus point (like every other enemy), keeping
	# each unit's authored relative offset (Fleet Edit px = world px).
	var anchor := _annulus_pos(_player.global_position)
	var ref := _fleet_centroid(fleet)
	for s: Dictionary in (fleet.get("slots", []) as Array):
		var pool: Array = []
		for en in (s.get("enemies", []) as Array):
			if String(en) != "":
				pool.append(String(en))
		if pool.is_empty():
			continue
		var id := String(pool[randi() % pool.size()])   # random pool → roll one, same as v1
		var pos := anchor + ((s.get("pos", Vector2.ZERO) as Vector2) - ref)
		if is_boss:
			_spawn(id, pos, true)
		else:
			_spawn_queue.append({"type": id, "pos": pos})

## Centroid (world px, Fleet Edit's authored px = world px) of a fleet's non-empty slots — the anchor
## reference so the formation's relative shape is preserved when placed at a random off-screen point.
func _fleet_centroid(fleet: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for s: Dictionary in (fleet.get("slots", []) as Array):
		var has := false
		for en in (s.get("enemies", []) as Array):
			if String(en) != "":
				has = true
				break
		if has:
			sum += (s.get("pos", Vector2.ZERO) as Vector2)
			n += 1
	return sum / float(n) if n > 0 else Vector2.ZERO

## Carrier fleet: the mother (a "mothership" unit) plus its rigidly-docked escorts, ported from
## arena_wave_director.gd's _deploy_mothership() — self-contained (arena_enemy.gd's init_mothership() runs
## the whole flee/release/respawn cycle from here on), so it works identically regardless of which director
## spawned it. Deploys immediately, bypassing the population cap — same as v1 (a boss-scale formation).
func _deploy_mothership_v2(mother_slot: Dictionary, child_slots: Array) -> void:
	var mslot: Dictionary = mother_slot["slot"]
	var mpos_screen: Vector2 = mslot.get("pos", Vector2.ZERO)
	var src: Dictionary = ENEMY_DEFS.get(String(mother_slot["id"]), {})
	if src.is_empty():
		return
	var mdef := src.duplicate()
	mdef["draw_w"] = float(mslot.get("size", 60.0))   # render the mother at its authored size (world px)
	var mother: Node = EnemyScript.new()
	mother.call("configure", String(mother_slot["id"]), _mgr, mdef)
	mother.set("global_position", _annulus_pos(_player.global_position))
	get_parent().add_child(mother)
	var roster: Array = []
	for cs: Dictionary in child_slots:
		var ids: Array = cs["ids"]
		var cid := String(ids[randi() % ids.size()])   # random pool → roll one (as the generic deploy)
		var cslot: Dictionary = cs["slot"]
		roster.append({
			"id": cid,
			"base_off": (cslot.get("pos", Vector2.ZERO) as Vector2) - mpos_screen,
			"draw_w": float(cslot.get("size", 50.0)),
			"rot": float(cslot.get("rot", 0.0)),
		})
	mother.call("init_mothership", roster)

## Fleet compositions authored in Fleet Edit — same source the wave editor's own _load_fleets() reads.
func _load_fleets() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load("res://fleet_layout.cfg") != OK:
		return []
	var data = cfg.get_value("fleets", "data", [])
	return data if data is Array else []

func _tl_radius() -> float:
	return randf_range(_r_min(), _r_max())

func _tl_one_position(angle_deg: float = NAN) -> Vector2:
	var a: float
	if is_nan(angle_deg):
		a = randf() * TAU
	else:
		a = deg_to_rad(angle_deg) + randf_range(-0.15, 0.15)   # small jitter around the fixed heading
	return _player.global_position + Vector2(cos(a), sin(a)) * _tl_radius()

## Full v1 pattern set (ring/arc/scatter/pincer/wall/wedge/portal + fallback), radius swapped for v2's
## own annulus (_tl_radius = _r_min…_r_max) so timeline spawns still never appear on-screen.
func _tl_pattern_positions(pattern: String, count: int, angle_deg: float = NAN) -> Array:
	var out: Array = []
	var c := _player.global_position
	match pattern:
		"ring":   # evenly spaced full circle (anchored at angle_deg when given)
			var off: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else randf() * TAU
			for k in count:
				var a := off + TAU * float(k) / float(count)
				out.append(c + Vector2(cos(a), sin(a)) * _tl_radius())
		"arc":    # partial arc from a random (or fixed) direction
			var start: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else randf() * TAU
			var span := deg_to_rad(120.0)
			for k in count:
				var a := start + span * (float(k) / float(maxi(1, count - 1)) - 0.5)
				out.append(c + Vector2(cos(a), sin(a)) * _tl_radius())
		"scatter":   # random angles + distances (jittered around angle_deg when given)
			for k in count:
				out.append(_tl_one_position(angle_deg))
		"pincer":   # two tight clusters on OPPOSITE flanks, both converging on the player
			var pbase: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else randf() * TAU
			var pspan := deg_to_rad(45.0)
			var per := int(ceil(count / 2.0))
			for k in count:
				var flank := 0.0 if (k % 2 == 0) else PI    # alternate the two opposite sides
				var t := (float(k / 2) / float(maxi(1, per - 1))) - 0.5
				out.append(c + Vector2(cos(pbase + flank + pspan * t), sin(pbase + flank + pspan * t)) * _tl_radius())
		"wall":   # a straight line abreast (perpendicular to the approach) that advances as one front
			var wa: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else randf() * TAU
			var wdir := Vector2(cos(wa), sin(wa))
			var wperp := Vector2(-wdir.y, wdir.x)
			var wcenter := c + wdir * _tl_radius()             # one radius call → the line stays straight
			for k in count:
				var t := (float(k) / float(maxi(1, count - 1))) - 0.5
				out.append(wcenter + wperp * (t * WALL_WIDTH))
		"wedge":   # arrowhead pointing AT the player: leader at the tip, ranks fan out behind it
			var ga: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else randf() * TAU
			var gdir := Vector2(cos(ga), sin(ga))
			var gperp := Vector2(-gdir.y, gdir.x)
			var tip := c + gdir * _tl_radius()
			out.append(tip)                                 # k=0 → the tip (leader), closest to the player
			for k in range(1, count):
				var rank := (k + 1) / 2                       # 1,1,2,2,3,3,... (rank grows every 2 units)
				var side := 1.0 if (k % 2 == 1) else -1.0    # alternate wings
				out.append(tip + gdir * (46.0 * float(rank)) + gperp * (40.0 * float(rank) * side))
		"portal":   # a single off-screen "gate": the whole group pours in tightly from ONE point
			var qa: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else randf() * TAU
			var gate := c + Vector2(cos(qa), sin(qa)) * _tl_radius()
			for k in count:
				var ja := randf() * TAU
				out.append(gate + Vector2(cos(ja), sin(ja)) * randf_range(0.0, 70.0))
		_:   # fallback = ring
			for k in count:
				var a := TAU * float(k) / float(count)
				out.append(c + Vector2(cos(a), sin(a)) * _tl_radius())
	return out

# ── Despawn/teleport: recycle enemies that wandered far past R_despawn ──────────────────────────────
## Pulls the enemy back into [R_min, R_max] along its OWN existing angle from the player — i.e. it keeps
## approaching from the same relative side it was already on, just closer — instead of relocating to a
## fresh random (or player-heading-biased) direction, which would read as a completely different enemy
## teleporting in.
##
## 2026-07-28: generalized from "steer_* only" to every non-exempt enemy. Root cause of a reported "creep
## count says 120 but nothing's on screen": NOTHING except steer_* ever got recycled, so any slower-than-
## the-player "chase" enemy (bismuth/ghost/pirate/magma/stone/pros1-8 etc. — most of the roster) that never
## caught up just piled up off-screen forever, invisibly, while the population cap kept admitting more.
## Exempt: "boss_stub" (bosses fight wherever combat brings them, never recycled), "mothership" (always
## approaching on its own since MS_CYCLE_ENABLED was disabled — see the 24th-pass entry — teleporting the
## carrier would also visually snap its whole docked formation), "patrol" (intentionally a one-way flyby
## that self-culls via PATROL_CULL — recycling it would fight that design: it'd immediately head back out
## along the SAME captured heading and re-exceed R_despawn almost right away, jittering in place instead of
## either reaching the player or leaving), and any `_docked` escort (pinned to its carrier's relative slot
## every frame by _ms_update_dock_positions() — teleporting it independently would fight that pin).
func _tick_despawn_teleport() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var c := _player.global_position
	var r_despawn := _r_max() * R_DESPAWN_MULT
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(e):
			continue
		var beh: String = String(e.get("behavior"))
		if beh == "boss_stub" or beh == "mothership" or beh == "patrol":
			continue
		if bool(e.get("_docked")):
			continue
		var ep: Vector2 = (e as Node2D).global_position
		var off := ep - c
		if off.length() > r_despawn:
			var rel_angle := off.angle() if off.length() > 0.01 else randf() * TAU
			(e as Node2D).global_position = _annulus_pos(c, rel_angle)
