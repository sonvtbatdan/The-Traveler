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
const CreepEditModeScript := preload("res://scripts/ui/boss_edit/creep_edit_mode.gd")
const V1 := preload("res://scripts/gameplay/arena_wave_director.gd")
const WaveHpGen := preload("res://scripts/gameplay/wave_hp_gen.gd")   # shared HP-target wave composer (F7 uses the same one)
const WaveEditorConf := preload("res://scripts/ui/hud/arena_wave_editor.gd")   # map-eligibility consts ONLY (MAP_ENEMY_FOLDERS / SHARED_ENEMY_FOLDERS / FLEET_PREFIX_MAP) so a generated wave fields the same roster F7 would offer. No instance is ever made here; the editor never preloads this file back, so there is no cycle.

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

# ══ Wave cadence — a 2-minute "wave" cycle with a quiet tail: the last WAVE_QUIET_TAIL seconds of every
# WAVE_INTERVAL-second block spawn NOTHING (a breather right before the next wave), whether the source is
# the ambient/cluster/wall loop or the Elite/Champion Creep timers — see _in_wave_quiet_window(), gated in
# _tick_spawn_loop()/_drain_spawn_queue() and _tick_elite_creep()/_tick_champion_creep(). Deliberately does
# NOT gate the F7-authored timeline (_tl_tick) — those spawns are hand-placed at specific times by the level
# designer, not something a generic periodic rule should silently eat.
const WAVE_INTERVAL   := 120.0
const WAVE_QUIET_TAIL := 10.0

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
#     Rank / unlock times / Elite Creep's start delay and must never reset; but row times authored as "5, 10, 15…"
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
#     _tl_tick() fires from the expanded queue instead. The FIRST entry's gap is measured from t=0 (the run's
#     start) exactly like any other entry's gap from its predecessor, so a lone first row authored well past
#     t=0 (e.g. a single row @30s) also spreads across that runway instead of bursting all at once; "Boss"
#     entries and "stream" entries are exempt (a boss is a single dramatic moment, not a name in the entry's
#     own dictionary, and streams already have their own ramp/duration spread — stacking gap-spread on top
#     would double up).
const PATTERNS := ["ring", "arc", "stream", "scatter", "pincer", "wall", "wedge", "portal", "random"]
const RANDOM_FORMATIONS := ["ring", "pincer", "wall", "wedge", "portal"]
const TL_BLOB_SPAWN_R := 90.0    # cluster radius for a "blob" def (e.g. "swarm", blob:50), timeline path only
const GRID_SPREAD_STEP := 5.0    # matches the F7 editor's row grid (GRID_STEP in arena_wave_editor.gd)

# ══ Runtime HP-milestone waves (2026-08-24) ════════════════════════════════════════════════════════
# On request: "Mỗi lần start game, luôn tự gen lại mỗi mốc 30 giây rồi rải đều ra các tick 5 giây."
#
# A wave file's `hp_targets` (the F7 "Total HP" column, persisted since 2026-08-24) is a list of MILESTONES:
# {time, hp}. For each one this director composes a FRESH random creep/fleet mix hitting that HP total —
# every run, so no two runs field the same wave — and spreads it across the 5s grid ticks leading UP to the
# milestone, using the identical spread math the authored timeline gets (_spread_entry).
#
# WHEN each one is composed: a milestone's units are released across the gap BEHIND it (t=90's wave actually
# fires at 65, 70, 75, 80, 85, 90), so its composition has to exist before the first of those ticks — NOT at
# t=90. It is composed the moment the run clock passes the PREVIOUS milestone, i.e. t=90's wave is built at
# t=60. (The user's own estimate was "gen at t=55 for t=90" — right idea; anchoring on the previous milestone
# is the same deadline without a magic number, and it keeps working if the milestone grid isn't 30s.)
#
# An authored entry sitting at a timestamp that HAS a target is dropped — the target is what that row means
# now, and firing both would double the wave. Rows with no target (or a wave file with no `hp_targets` at
# all, i.e. every file authored before this) keep their hand-placed entries exactly as before.
const GEN_SLOTS_PER_WAVE := 10   # same 2×5 slot budget one F7 row has
# "stream" is deliberately absent: a generated wave is ALREADY trickled across the 5s ticks, and a stream
# slot carries duration 0 (see _tl_fire's maxf(0.01, ...)), which would dump its whole count in one frame.
const GEN_PATTERNS := ["ring", "arc", "scatter", "pincer", "wall", "wedge", "portal", "random"]

# ══ Concurrent ranged-creep ceiling ════════════════════════════════════════════════════════════════
# On request: "Có không quá 5 creep bắn projectile xuất hiện đồng thời trên arena." Enforced in _spawn_def()
# — the one funnel every ordinary spawn goes through (continuous loop, timeline, generated waves, catch-up,
# Elite/Champion) — exactly the way MISSILE_MAX_ALIVE already works: the spawn is REFUSED, the item stays in
# _spawn_queue, and _drain_spawn_queue's next pick tries something else. So the field keeps filling at full
# rate with melee creeps and the held-back shooter arrives once one of the five dies.
#
# Fleet Edit formations deploy through their OWN gate instead (_drain_fleet_queue below), because
# _deploy_fleet() builds its units directly rather than through _spawn_def() and a rigid dock formation
# can't be thinned mid-deploy without orphaning its escorts — so a whole formation is admitted or deferred
# as one unit, budgeted by how many ranged members it carries.
#
# 2026-08-24 bug report: "hornet cũng là enemy shoot projectile, vì sao ở giây thứ 55, có tới hơn 70
# animalhornet trên arena?" — exactly that loophole. animalhornet IS classified ranged (behavior "bomber"),
# but elecforest.json's t=60 row is `fleet:A.Hornet.Diamon.5` ×20 — 5 hornets per deployment, 100 in total,
# every one of them arriving through the fleet path that never consulted this ceiling. Spread across the
# 30→60s gap that put ~80 on the field by t=55. Enforcing it on fleets too is what actually makes the rule
# mean anything, since a level's ranged pressure is largely delivered BY formations.
#
# PRECEDENCE (2026-08-25, on request: "luật trần 10 con này là cao nhất override các rule khác"): this
# ceiling outranks every other spawn rule — the ambient rate loop, the low-population catch-up burst, the
# HP-milestone generator, an authored timeline row, and whole Fleet Edit formations all yield to it.
#
# The ONE exemption is a boss, and "boss" here explicitly includes ELITE and CHAMPION creeps: with 10 ranged
# creeps already up, a boss/elite/champion may still spawn. That is the `not is_boss and not def["elite"]`
# guard in _spawn_def() — Elite/Champion are spawned by _spawn_tiered_creep() with def["elite"] = true, so
# both tiers already ride that same exemption.
const SHOOT_MAX_ALIVE := 10   # raised from 5 on request, 2026-08-24

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
var hp_targets: Array = []        # [{time, hp}] sorted — the authored HP milestones (see the const block above)
var _gen_fire_queue: Array = []   # generated milestone waves, already spread, in time order (own queue so the authored one keeps its invariants)
var _gen_next: int = 0            # index into _gen_fire_queue of the next generated entry to fire
var _gen_ms_i: int = 0            # index into hp_targets of the next milestone still to compose
var _gen_unit_pool: Array = []    # [{id, hp, shoot}] eligible creeps for this map, built once in _ready
var _gen_fleet_pool: Array = []   # [{name, hp, shoot}] eligible formations for this map
var _shoot_ids: Dictionary = {}   # enemy id -> true for every ranged type (SHOOT_MAX_ALIVE gate)
var _shoot_alive_n: int = 0       # cached count of live ranged creeps (see _shoot_alive)
var _shoot_alive_frame: int = -1
var _fleet_queue: Array = []      # [{name, angle, rot}] formations waiting on the ranged ceiling (see _drain_fleet_queue)
var _fleet_shoot_n: Dictionary = {}   # fleet name -> ranged units ONE deployment puts on the field
var _tl_start_t: float = 0.0  # _run_t at the moment set_timeline() was last called — elapsed() is relative to this
var _tl_next: int = 0         # index into _tl_fire_queue of the next entry to fire
var _tl_streams: Array = []   # active "stream" entries: {type, left, dur, elapsed, r0, ramp, credit, is_boss, ...}
var _tl_seen_types: Dictionary = {}   # set of "safe" (non-boss/elite/blob) type ids the timeline has fired SO FAR — read by _reinforce_type()

# ── Final-boss encounter: a timeline whose LAST entry is a solo is_boss spawn gets special handling —
# instead of firing at its authored time regardless of the field, it's pulled OUT of the normal fire queue
# and held until every earlier entry has fired, its own authored time has passed, AND the field is
# completely clear (alive == 0) — a deliberate "clear everything, then the boss shows up" finale. Once
# waiting begins, reinforcement (catch-up burst + Elite/Champion Creep) is locked off for the rest of the
# timeline so the field can actually reach zero instead of being perpetually topped back up.
var _final_boss_entry: Dictionary = {}
var _final_boss_pending: bool = false
var _final_boss_node: Node = null
var _reinforcement_locked: bool = false

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

# ── Minimum-population catch-up state ──
var _low_count_timer: float = 0.0
var _catchup_active: bool = false

# ── Opening-surge state ──
var _start_boost_decaying: bool = false
var _start_boost_t: float = 0.0

# XP is proportional to HP, ratio pinned to v1's own "fly" (its very first intro enemy): xp/hp there is
# 100.0/20.0 = 5.0 XP per HP (2026-08-05: every creep XP source, incl. fly's, scaled ×10 again on request —
# was 10.0/20.0 = 0.5; before that, 2026-07-28's units-only pass had it at 1.0/20.0 = 0.05).
# Applied to every test-roster def's BASE hp (pre the automatic ×2 HP/XP tune in arena_enemy.configure() —
# since both sides double equally, the ratio survives the tune unchanged), and reapplied after Elite Creep's
# hp scaling so an Elite Creep's XP scales right along with its HP. Read live from ENEMY_DEFS in _ready() below
# (this initial value is just a placeholder, immediately overwritten), so it self-propagates automatically
# whenever fly's own "xp"/"hp" change — no separate edit needed here for future re-tunes.
var _xp_per_hp: float = 5.0

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
	CreepEditModeScript.apply_chain_overrides(ENEMY_DEFS)   # Creep Edit's CHAIN section — segments/spacing/bend-lock
	# Both derived from the FINAL ENEMY_DEFS (after every override above), and both before
	# _load_remembered_timeline() below — that call composes the first milestone, which needs the pools.
	_shoot_ids = WaveHpGen.shoot_type_ids(ENEMY_DEFS)
	_build_gen_pools()
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
## OWN last-loaded file (Electric's spawn config edits never touch Default's) — _last_wave_cfg_path()'s
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
	var tgt: Variant = (parsed as Dictionary).get("hp_targets", [])
	set_timeline((parsed as Dictionary)["timeline"], tgt if tgt is Array else [])

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
## comment on elapsed() above for why this doesn't touch _run_t/Agony/Elite-Creep state). Also rebuilds the
## gap-spread firing queue (_tl_fire_queue) — see the class-level comment on gap-spread.
func set_timeline(entries: Array, targets: Array = []) -> void:
	timeline = entries.duplicate(true)
	timeline.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	hp_targets = []
	for t in targets:
		var td: Dictionary = t
		var thp := float(td.get("hp", 0.0))
		if thp > 0.0:
			hp_targets.append({"time": float(td.get("time", 0.0)), "hp": thp})
	hp_targets.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	_gen_fire_queue.clear()
	_gen_next = 0
	_gen_ms_i = 0
	_fleet_queue.clear()
	# Authored entries at a milestone timestamp are superseded by that milestone's generated wave (see the
	# GEN_SLOTS_PER_WAVE const block) — everything else plays exactly as before.
	_tl_fire_queue = _spread_gaps(_authored_minus_milestones(timeline))
	_tl_start_t = _run_t
	_tl_next = 0
	_tl_streams.clear()
	_tl_seen_types.clear()
	# See the class-level comment on _final_boss_entry: the LATEST-timed solo is_boss spawn in the whole
	# timeline is pulled out of the normal fire queue and held until the field clears. Found by scanning
	# every entry for the max "time" among is_boss/non-fleet/count<=1 candidates — NOT just checking
	# _tl_fire_queue's last array index, because the authored grid's final row commonly holds SEVERAL
	# entries at the exact same timestamp (e.g. the boss alongside a closing wave of regular creeps), and
	# Array.sort_custom() is not a stable sort: ties can land in any order, so the boss entry isn't
	# guaranteed to end up literally last even though it shares the timeline's latest timestamp.
	_final_boss_entry = {}
	_final_boss_pending = false
	_final_boss_node = null
	_reinforcement_locked = false
	var _fb_idx := -1
	var _fb_time := -INF
	for i in _tl_fire_queue.size():
		var e: Dictionary = _tl_fire_queue[i]
		if not bool(e.get("is_boss", false)):
			continue
		if String(e.get("type", "")).begins_with("fleet:") or int(e.get("count", 1)) > 1:
			continue
		var et := float(e.get("time", 0.0))
		if et > _fb_time:
			_fb_time = et
			_fb_idx = i
	if _fb_idx >= 0:
		_final_boss_entry = _tl_fire_queue[_fb_idx]
		_tl_fire_queue.remove_at(_fb_idx)
	# Milestone 0's own gap runs from t=0, so its ticks start almost immediately — compose it up front rather
	# than waiting for the first _tick_hp_gen() (which would already be a tick or two late).
	_tick_hp_gen()

## Read by F7 so a Save/Load round-trip keeps the milestone targets (the panel rebuilds its rows from this
## director's live state, never from the file — see arena_wave_editor._rebuild_rows).
func get_hp_targets() -> Array:
	return hp_targets

## `timeline` minus every entry whose time matches a milestone that has an HP target — those rows are now
## DEFINED by their target, and the composed wave replaces them. Match is by the 5s grid the F7 rows sit on
## (is_equal_approx on raw floats would miss a 30.0 vs 29.999999 round-trip through JSON).
func _authored_minus_milestones(entries: Array) -> Array:
	if hp_targets.is_empty():
		return entries
	var taken: Dictionary = {}
	for t: Dictionary in hp_targets:
		taken[int(round(float(t["time"])))] = true
	var out: Array = []
	for e: Dictionary in entries:
		if not taken.has(int(round(float(e.get("time", 0.0))))):
			out.append(e)
	return out

## Eligible creeps/formations for a generated wave on the map being played — the same rule F7's own Gen
## candidate pool uses (own map folder + SHARED_ENEMY_FOLDERS for units; FLEET_PREFIX_MAP, else the same
## folder test on member ids, for fleets), read from that file's consts so the two can't diverge. Built once:
## ENEMY_DEFS and fleet_layout.cfg don't change mid-run.
func _build_gen_pools() -> void:
	_gen_unit_pool.clear()
	_gen_fleet_pool.clear()
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	var own_folder := String(WaveEditorConf.MAP_ENEMY_FOLDERS.get(map_id, ""))
	var allowed: Array = ([own_folder] + WaveEditorConf.SHARED_ENEMY_FOLDERS) if own_folder != "" else []
	for id in ENEMY_DEFS.keys():
		var ids := String(id)
		if ENEMY_DEFS_V2.has(ids):
			continue   # the 4 TEST_ROSTER placeholders are re-skins of real types — don't offer both
		var d: Dictionary = ENEMY_DEFS[ids]
		if WaveHpGen.is_auto_excluded(d):
			continue   # one-off bosses + test-only creeps (dummy) — see WaveHpGen.is_auto_excluded()
		if not allowed.is_empty() and not _icon_in_folders(String(d.get("icon", "")), allowed):
			continue
		var hp := float(d.get("hp", 0.0)) * float(maxi(1, int(d.get("blob", 1))))
		if hp > 0.0:
			_gen_unit_pool.append({"id": ids, "hp": hp, "shoot": WaveHpGen.is_shoot_def(d)})
	var fleets := _load_fleets()
	for fl in fleets:
		var nm := String((fl as Dictionary).get("name", ""))
		if nm == "" or not _fleet_belongs(fl, nm, map_id, allowed):
			continue
		var fhp := WaveHpGen.fleet_hp(fleets, nm, ENEMY_DEFS)
		if fhp > 0.0:
			_gen_fleet_pool.append({"name": nm, "hp": fhp,
					"shoot": WaveHpGen.fleet_shoot_count(fleets, nm, ENEMY_DEFS)})

func _icon_in_folders(icon: String, folders: Array) -> bool:
	for p in folders:
		if icon.begins_with(String(p)):
			return true
	return false

func _fleet_belongs(fl: Variant, nm: String, map_id: String, allowed: Array) -> bool:
	if allowed.is_empty():
		return true   # "default"/unmapped map — every fleet is fair game, same as F7
	for pm: Dictionary in WaveEditorConf.FLEET_PREFIX_MAP:
		if nm.begins_with(String(pm["prefix"])):
			return String(pm["map"]) == map_id   # a recognized prefix decides outright
	for s: Dictionary in ((fl as Dictionary).get("slots", []) as Array):
		for en in (s.get("enemies", []) as Array):
			var d: Dictionary = ENEMY_DEFS.get(String(en), {})
			if _icon_in_folders(String(d.get("icon", "")), allowed):
				return true   # legacy, un-prefixed fleet — same folder fallback F7 uses
	return false

## Compose every milestone whose composition deadline has arrived. Milestone i's units are spread across the
## gap behind it, so it is built once the clock passes milestone i-1 (milestone 0 at t=0). Each milestone is
## composed EXACTLY once per run — _gen_ms_i only ever advances.
func _tick_hp_gen() -> void:
	var t := elapsed()
	while _gen_ms_i < hp_targets.size():
		var prev := float(hp_targets[_gen_ms_i - 1]["time"]) if _gen_ms_i > 0 else 0.0
		if t < prev:
			return
		_gen_compose(_gen_ms_i, prev)
		_gen_ms_i += 1

func _gen_compose(i: int, prev_t: float) -> void:
	var ms: Dictionary = hp_targets[i]
	var t := float(ms["time"])
	# shoot_cap_per_type is 0 (unlimited) here on purpose: SHOOT_MAX_ALIVE is a TOTAL, and a per-type ceiling
	# on top of a total of 5 would only ever make the mix more uniform, never safer.
	var slots: Array = WaveHpGen.generate(float(ms["hp"]), _gen_unit_pool, _gen_fleet_pool, GEN_PATTERNS,
			GEN_SLOTS_PER_WAVE, 0, SHOOT_MAX_ALIVE)
	var block: Array = []
	for slot: Dictionary in slots:
		var e := slot.duplicate(true)
		e["time"] = t
		for sub: Dictionary in _spread_entry(e, prev_t, t):
			block.append(sub)
	# Each slot spreads independently, so the block interleaves — sort it before appending. Every entry in it
	# lands in (prev_t, t], i.e. after everything already queued, so the queue as a whole stays time-ordered
	# and _gen_next can keep walking it with a plain index.
	block.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	_gen_fire_queue.append_array(block)

## Expand `sorted` (already time-sorted) into the actual firing queue: every entry stamped at a given time
## has its count divided evenly across each ~GRID_SPREAD_STEP tick spanning the gap back to the previous
## DISTINCT timestamp (all entries of one authored row share that same gap — see the grouping note below).
## Tick spacing = gap / round(gap / GRID_SPREAD_STEP), so the LAST tick always lands exactly on the
## entry's own authored time, even if that time isn't itself grid-aligned. Remainder units go to the
## final ticks so the total spawned always equals the authored count exactly. Skipped (passed through
## unchanged) for: "Boss" entries and "stream" entries. The FIRST entry's own gap is measured from t=0 (the
## run's start, `prev_t`'s own initial value below) exactly like any other entry's gap from ITS predecessor —
## user bug report: a single-entry timeline (e.g. Volcanic's vocalnic.json, one "magma1" row at t=30s) was
## dumping its entire count in one instant burst at t=30 instead of spreading across the 30s runway, because
## this used to special-case "no previous entry" as "never spread" regardless of how large that gap was.
## One entry's count divided across the ~GRID_SPREAD_STEP ticks spanning (prev_t, t]. Shared by
## _spread_gaps() (authored timeline) and _gen_compose() (runtime milestone waves) so both trickle
## identically. Returns [entry] unchanged when the gap is too small to subdivide.
func _spread_entry(entry: Dictionary, prev_t: float, t: float) -> Array:
	var gap := t - prev_t
	if gap <= GRID_SPREAD_STEP:
		var one := entry.duplicate(true)
		one["time"] = t
		return [one]
	var out: Array = []
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
	return out

func _spread_gaps(sorted: Array) -> Array:
	var out: Array = []
	var prev_t := 0.0
	var i := 0
	while i < sorted.size():
		var t := float((sorted[i] as Dictionary).get("time", 0.0))
		# Take the whole GROUP of entries sharing this timestamp before advancing `prev_t`. One authored F7
		# row is several entries (one per Unit slot) all stamped with the SAME "time", and every one of them
		# has to spread across the SAME gap — the one measured back to the previous DISTINCT timestamp.
		# 2026-08-24 bug fix: this used to advance `prev_t = t` after EVERY entry, so only a row's FIRST unit
		# ever saw a non-zero gap; units 2..N measured gap 0, fell through the `gap <= GRID_SPREAD_STEP`
		# early-out and dumped their whole count in one instant burst. With spawnmode2.json's 30s grid (rows
		# of 4-10 entries each) that meant ~99% of every wave arrived as a single 30-second drop instead of
		# trickling every 5s — exactly the reported "creep rơi theo từng tick 30 giây" symptom.
		var j := i
		while j < sorted.size() and is_equal_approx(float((sorted[j] as Dictionary).get("time", 0.0)), t):
			j += 1
		var gap := t - prev_t
		for gi in range(i, j):
			var entry: Dictionary = sorted[gi]
			var pattern := String(entry.get("pattern", "ring"))
			var is_boss := bool(entry.get("is_boss", false))
			if is_boss or pattern == "stream" or gap <= GRID_SPREAD_STEP:
				out.append(entry)
				continue
			out.append_array(_spread_entry(entry, prev_t, t))
		prev_t = t
		i = j
	# Interleaving several entries' sub-ticks leaves `out` out of order (row A's 5s…10s… then row B's 5s…),
	# and _tl_tick() walks this queue strictly sequentially — an out-of-order entry would stall every later
	# one behind it. Re-sort by time; ties may land in any order (sort_custom isn't stable), which the
	# callers already tolerate (see set_timeline()'s final-boss scan).
	out.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
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
	_tick_elite_creep(delta)
	_tick_champion_creep(delta)
	_tick_spawn_loop(delta, alive)
	_tick_hp_gen()
	_tl_tick(delta)
	_drain_fleet_queue()   # retry formations the ranged ceiling held back on an earlier tick
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
	if _reinforcement_locked:
		return   # waiting for (or past) the timeline's final-boss finale — the field must reach zero, never topped back up
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

# ══ Tiered Creeps (Elite / Champion) — two independent escalation tracks, each on its own flat timer,
# promoting the current wave's OWN weakest (lowest-HP) NOT-YET-PROMOTED creep type into a bigger/tougher
# version — see _spawn_tiered_creep()/_weakest_wave_type() below. Champion is the bigger/rarer/later tier
# (3× size, 75× HP, every 60s from 2:30) layered on top of Elite (2× size, 35× HP, every 30s from 1:30);
# each tier tracks its OWN "already promoted" set independently, so Elite and Champion each escalate through
# the wave's roster on their own schedule rather than sharing progress. This is now the ONLY milestone-elite
# mechanic in the game (2026-08-02: replaced v1's 3 fixed, scripted, insect-only elite_fly/bug/bee entries —
# see arena_wave_director.gd's ENEMY_DEFS/DEFAULT_TIMELINE — and, same day, the old single-tier "Champion"
# mechanic that used to live here as a random-archetype, fully knockback-immune, gold-ringed spawn). Both
# tiers are flagged "elite" (cap-bypass — see arena_enemy.gd's _is_elite) and only 50% as resistant to
# knockback (arena_enemy.gd's "knockback_mult", overriding the elite-implies-full-immunity default) and
# "no_downscale" (load the full HD source sprite — at 2-3× a normal creep's footprint, the pre-baked-
# downscale copy, sized for the type's NORMAL on-screen size, would visibly blur once stretched up).
#
# Reward on death DIFFERS per tier (2026-08-06, on request) — ONLY Champion also carries "champion": true
# (arena_enemy.gd's _is_champion), which is what actually branches the reward, "elite" alone stays the
# cap-bypass/knockback-tune flag both share:
#   Elite     → flat 50 coin (arena_enemy.gd's _die(), plain spawn_loot "coin" — no UI, no choice).
#   Champion  → guaranteed-new weapon/aux pick (arena_levelup_ui.gd's grant_champion_reward(), same
#               guaranteed-new-mixed flow the temple's orb_of_light drop uses) — UNLESS every run-slot (5
#               weapons + 5 aux = 10) is already full, in which case a MetaManager unique-fragment is
#               granted directly instead (see grant_champion_reward()'s own doc comment for the full chain).
const ELITE_CREEP_START_DELAY    := 90.0
const ELITE_CREEP_INTERVAL       := 30.0
const ELITE_CREEP_HP_MULT        := 35.0
const ELITE_CREEP_SIZE_MULT      := 2.0
const ELITE_CREEP_KNOCKBACK_MULT := 0.5

const CHAMPION_CREEP_START_DELAY    := 150.0
const CHAMPION_CREEP_INTERVAL       := 60.0
const CHAMPION_CREEP_HP_MULT        := 75.0
const CHAMPION_CREEP_SIZE_MULT      := 3.0
const CHAMPION_CREEP_KNOCKBACK_MULT := 0.5

var _elite_creep_acc: float = 0.0
var _elite_creep_used: Dictionary = {}      # type ids already promoted to an Elite Creep this run — see _weakest_wave_type
var _champion_creep_acc: float = 0.0
var _champion_creep_used: Dictionary = {}   # same idea, tracked separately for the Champion tier

func _tick_elite_creep(delta: float) -> void:
	if _reinforcement_locked:
		return   # waiting for (or past) the timeline's final-boss finale — no more milestone spawns either
	if _run_t < ELITE_CREEP_START_DELAY:
		return
	_elite_creep_acc += delta
	if _elite_creep_acc < ELITE_CREEP_INTERVAL:
		return
	_elite_creep_acc = 0.0
	if _in_wave_quiet_window():
		return   # this beat lands in the quiet tail of a wave interval — skipped outright, not delayed
	_spawn_tiered_creep(_elite_creep_used, ELITE_CREEP_SIZE_MULT, ELITE_CREEP_HP_MULT, ELITE_CREEP_KNOCKBACK_MULT, false)

func _tick_champion_creep(delta: float) -> void:
	if _reinforcement_locked:
		return   # waiting for (or past) the timeline's final-boss finale — no more milestone spawns either
	if _run_t < CHAMPION_CREEP_START_DELAY:
		return
	_champion_creep_acc += delta
	if _champion_creep_acc < CHAMPION_CREEP_INTERVAL:
		return
	_champion_creep_acc = 0.0
	if _in_wave_quiet_window():
		return
	_spawn_tiered_creep(_champion_creep_used, CHAMPION_CREEP_SIZE_MULT, CHAMPION_CREEP_HP_MULT, CHAMPION_CREEP_KNOCKBACK_MULT, true)

## Shared by both tiers — `used` is that tier's own promoted-types set (_elite_creep_used or
## _champion_creep_used), kept independent so Elite and Champion each escalate through the wave's roster on
## their own schedule instead of sharing progress. `is_champion` sets the def's "champion" flag, which is
## the ONLY thing that actually picks which reward arena_enemy.gd's _die() grants — see this file's own
## header comment above _tick_elite_creep for the full Elite-vs-Champion reward split.
func _spawn_tiered_creep(used: Dictionary, size_mult: float, hp_mult: float, knockback_mult: float, is_champion: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var base_type := _weakest_wave_type(used)
	var base_def: Dictionary = ENEMY_DEFS.get(base_type, {})
	if base_def.is_empty():
		return
	used[base_type] = true   # so this tier's NEXT spawn escalates to a different type instead of repeating this one
	var def := base_def.duplicate()
	# draw_w must be computed from the UN-scaled base_def (base_draw_width falls back to def["size"] × a
	# fixed ratio when there's no creep_layout.cfg entry) — compute it BEFORE def["size"] is overwritten below.
	def["draw_w"] = EnemyScript.base_draw_width(base_def) * size_mult
	def["size"] = float(def.get("size", 16.0)) * size_mult
	def["hp"] = float(def.get("hp", 30.0)) * hp_mult
	def["xp"] = float(def["hp"]) * _xp_per_hp   # recompute AFTER the hp scale so XP stays proportional to HP
	def["elite"] = true                    # cap-bypass (arena_enemy.gd _is_elite) — shared by both tiers
	def["champion"] = is_champion          # reward-tier flag (arena_enemy.gd _is_champion) — see header comment
	def["knockback_mult"] = knockback_mult   # override the elite default (full immunity)
	def["no_downscale"] = true             # load the full HD sprite — see const-block comment above
	_spawn_def(base_type, def, _annulus_pos(_player.global_position))

## The current wave's own weakest creep type NOT YET in `used` (that tier's own promoted-types set): lowest
## "hp" (scaled by player level for "lvl": true types, so a per-level base is compared fairly against a flat
## one — see arena_enemy.gd's configure()) among the distinct, non-elite, non-boss types the loaded
## timeline's JSON actually rosters ("type" values — fleet: pseudo-ids excluded, they aren't a real
## ENEMY_DEFS entry; already-elite/boss types excluded — re-eliting an already-elite type or turning a boss
## into a "creep" elite would be nonsensical). No timeline loaded → falls back to the TEST_TYPES roster.
## Once every eligible type has had a turn, `used` resets so the cycle continues (weakest → … → strongest →
## weakest again) rather than that tier quietly going silent for the rest of a long run.
## Distinct enemy type ids authored ANYWHERE in the current timeline (regardless of whether they've fired
## yet), excluding boss/fleet/elite entries — the map-appropriate candidate pool shared by _weakest_wave_type()
## (Elite/Champion Creep promotion) and _timeline_fallback_type() (reinforcement before the timeline has
## fired anything at all) so BOTH systems only ever pick something the CURRENT map's own JSON actually
## authored, never the hardcoded cross-map TEST_ROSTER (user bug report: Volcanic's vocalnic.json only has
## one entry at t=30s, so a low-population catch-up triggering before then used to fall back to "fly" —
## Electric's intro roster — via TEST_TYPES[0]; see _timeline_fallback_type()).
func _timeline_type_pool() -> Array:
	var candidates: Array = []
	var seen := {}
	for entry: Dictionary in timeline:
		var t := String(entry.get("type", ""))
		if t == "" or t.begins_with("fleet:") or seen.has(t):
			continue
		seen[t] = true
		var d: Dictionary = ENEMY_DEFS.get(t, {})
		if d.is_empty() or bool(d.get("elite", false)) or bool(entry.get("is_boss", false)):
			continue
		# boss_stub/gate_waves as before, plus test-only creeps (dummy): an authored `dummy` row still spawns
		# itself, it just never becomes reinforcement fodder or gets promoted to an Elite/Champion.
		if WaveHpGen.is_auto_excluded(d):
			continue
		candidates.append(t)
	return candidates

func _weakest_wave_type(used: Dictionary) -> String:
	var candidates: Array = _timeline_type_pool()
	if candidates.is_empty():
		candidates = TEST_TYPES.duplicate()
	var fresh: Array = candidates.filter(func(t: String) -> bool: return not used.has(t))
	if fresh.is_empty():
		used.clear()
		fresh = candidates
	var best := String(fresh[0])
	var best_hp := INF
	for t: String in fresh:
		var d: Dictionary = ENEMY_DEFS.get(t, {})
		var lvl_mult := float(GameManager.player_level) if bool(d.get("lvl", false)) else 1.0
		var hp: float = float(d.get("hp", 0.0)) * lvl_mult
		if hp < best_hp:
			best_hp = hp
			best = t
	return best

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
# exactly what was authored, no "stray" test-roster enemies mixed in. The catch-up path below IS gated by
# the wave quiet-window (see WAVE_INTERVAL/WAVE_QUIET_TAIL) but NOT by a loaded timeline — a population-floor
# rescue still fires (from the test roster) even with a timeline loaded, so the field can never truly empty
# out; Elite/Champion Creep (_tick_elite_creep/_tick_champion_creep, called separately) are also untouched
# by the timeline check specifically (they have their own quiet-window gate). _spawn_acc deliberately
# doesn't accumulate while skipped (timeline OR quiet window), so returning to a blank timeline / the next
# non-quiet window doesn't unleash a built-up burst.
func _tick_spawn_loop(delta: float, alive: int) -> void:
	if _in_wave_quiet_window():
		return
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
## later/harder wave that hasn't fired yet — "không vượt cấp"), falling back to _timeline_fallback_type() —
## the map's own FULL authored roster, not yet-fired entries included — if nothing has fired yet (a catch-up
## triggering in the gap before the timeline's first entry, e.g. Volcanic's vocalnic.json only starting at
## t=30s). No timeline loaded → unchanged, the default 4-type roster gated by TYPE_UNLOCK_TIME (same pool
## _rand_test_type()'s other callers use, untouched by this).
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
				return _timeline_fallback_type()
			return String(keys[randi() % keys.size()])
		return _timeline_fallback_type()
	return _rand_test_type()

## Reinforcement fallback for when the loaded timeline hasn't fired ANY entry yet — see _reinforce_type()'s
## header (original bug report: "trong map vocalnic... vì sao vẫn thấy flies (vốn là creep của map electric)").
##
## Picks ONLY from types scheduled at the EARLIEST authored time in the timeline (_timeline_earliest_type_pool()),
## NOT the whole map's roster. A first pass at this used the full _timeline_type_pool() (every distinct type
## anywhere in the timeline) — correct by coincidence for Volcanic's single-entry timeline (whole roster == 1
## type), but wrong for a densely-authored map: user bug report — "elecforest.json ở 30 giây đầu chỉ có flies,
## nhưng tôi thấy có rất nhiều các loại khác (beamer, centipede, hornet...)" — elecforest.json's own roster
## spans fly/diver/dragonfly/bee/spider/squid/centipede/swarm/bug/animalhornet/beamer/missile across a full
## 30-minute run; drawing from ALL of it during the opening seconds let a low-population catch-up spawn any
## of those, including types whose own first scripted entry is 15+ minutes away — the exact "vượt cấp"
## (spawning ahead of schedule) _tl_seen_types-based reinforcement was designed to prevent, just re-opened for
## the brief window before the timeline's first entry fires. Restricting to the earliest timestamp's types
## closes that window: elecforest.json's earliest entry is t=30 (type "fly" only), so this now returns "fly",
## matching what the timeline itself schedules first.
func _timeline_fallback_type() -> String:
	var candidates: Array = _timeline_earliest_type_pool()
	if candidates.is_empty():
		candidates = _timeline_type_pool()   # degenerate timeline (nothing found at any single earliest time) — fall back to the whole roster rather than the cross-map TEST_ROSTER
	if candidates.is_empty():
		return TEST_TYPES[0]   # nothing usable authored at all — last-resort fallback (shouldn't happen for a real level)
	return String(candidates[randi() % candidates.size()])

## Distinct enemy type ids scheduled at the EARLIEST "time" value anywhere in the timeline — see
## _timeline_fallback_type()'s header for why this is the correct pool for pre-first-fire reinforcement
## specifically (as opposed to _weakest_wave_type()'s Elite/Champion Creep promotion, which intentionally
## still ranks across the WHOLE authored roster by design). Boss entries at that time are skipped (a boss
## should never be a filler/reinforcement pick). A `fleet:<name>` entry at that time is resolved to its OWN
## member enemy ids (2026-08-18 fix — bug report: authoring the timeline's very first row as ONLY a fleet,
## e.g. Atlantic's t=30 "fleet:AT.Whale.Duo.2" alone, used to make this function find zero non-fleet
## candidates at that timestamp and silently fall through to whatever the NEXT-earliest non-fleet time
## happened to contain — Atlantic's t=60 row, "atlantic_squid" — so the entire pre-t=30 AND t=30-to-60
## window ambient-spawned atlantic_squid almost exclusively, reading as "set 1 fleet at t=30 but see tons
## of atlantic_squid" from the player's side. Resolving the fleet's own roster instead keeps this window
## thematically AND tier-correct: whatever the first authored moment actually introduces, fleet or not).
func _timeline_earliest_type_pool() -> Array:
	var min_t := INF
	for entry: Dictionary in timeline:
		if bool(entry.get("is_boss", false)):
			continue
		min_t = minf(min_t, float(entry.get("time", 0.0)))
	if min_t == INF:
		return []
	var candidates: Array = []
	var seen := {}
	var fleets_cache: Array = []   # lazy-loaded only if an earliest-time entry is actually a fleet
	var fleets_loaded := false
	for entry: Dictionary in timeline:
		if bool(entry.get("is_boss", false)):
			continue
		if not is_equal_approx(float(entry.get("time", 0.0)), min_t):
			continue
		var type_s := String(entry.get("type", ""))
		if type_s == "":
			continue
		if type_s.begins_with("fleet:"):
			if not fleets_loaded:
				fleets_cache = _load_fleets()
				fleets_loaded = true
			var fleet_name := type_s.substr(6)
			var fleet: Dictionary = {}
			for fl in fleets_cache:
				if String((fl as Dictionary).get("name", "")) == fleet_name:
					fleet = fl
					break
			for s: Dictionary in (fleet.get("slots", []) as Array):
				for en in (s.get("enemies", []) as Array):
					var t := String(en)
					if t == "" or seen.has(t):
						continue
					var d: Dictionary = ENEMY_DEFS.get(t, {})
					if d.is_empty() or bool(d.get("elite", false)) or WaveHpGen.is_auto_excluded(d):
						continue
					seen[t] = true
					candidates.append(t)
			continue
		if seen.has(type_s):
			continue
		var d: Dictionary = ENEMY_DEFS.get(type_s, {})
		if d.is_empty() or bool(d.get("elite", false)):
			continue
		# 2026-08-25: this branch checked `elite` but never boss_stub/gate_waves/no_auto, so a boss_stub type
		# authored at the earliest timestamp WITHOUT an is_boss flag (or a test-only creep like dummy) could be
		# drawn as ordinary reinforcement filler. The fleet branch above has the same gap — both now share
		# is_auto_excluded(), matching _timeline_type_pool()'s own filter.
		if WaveHpGen.is_auto_excluded(d):
			continue
		seen[type_s] = true
		candidates.append(type_s)
	return candidates

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

## True during the last WAVE_QUIET_TAIL seconds of every WAVE_INTERVAL-second block of run time — the
## breather right before each "wave" transition (see the WAVE_INTERVAL/WAVE_QUIET_TAIL const comment).
## Deliberately checked only at spawn-DECISION points (_tick_spawn_loop, _tick_elite_creep,
## _tick_champion_creep), not in _drain_spawn_queue() — that queue is shared with the F7 timeline's own
## ring/scatter/wall/stream entries, and gating it here would also stall hand-authored timeline spawns that
## already queued just before the window opened, not just the ambient loop this rule is actually about.
func _in_wave_quiet_window() -> bool:
	return fmod(_run_t, WAVE_INTERVAL) >= (WAVE_INTERVAL - WAVE_QUIET_TAIL)

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
	# Ranged ceiling closed for this frame? Then every shooter still queued is guaranteed to be refused, and a
	# queue holding hundreds of them (a hand-authored shooter flood — the generator never composes more than
	# SHOOT_MAX_ALIVE per wave) would otherwise spend the whole `tries` budget on picks that cannot succeed,
	# starving the melee creeps sitting in the same queue. Skipping those costs one dictionary lookup and
	# deliberately does NOT consume `tries`; `scans` is the separate hard bound that keeps the loop finite.
	var shoot_blocked := _shoot_alive() >= SHOOT_MAX_ALIVE
	var scans := mini(_spawn_queue.size() * 2, 200)
	while budget > 0 and tries > 0 and scans > 0 and not _spawn_queue.is_empty():
		scans -= 1
		var idx := randi() % _spawn_queue.size()
		var it: Dictionary = _spawn_queue[idx]
		if shoot_blocked and _shoot_ids.has(String(it["type"])):
			continue
		tries -= 1
		var node := _spawn(String(it["type"]), it["pos"] as Vector2)
		if node != null:
			_spawn_queue.remove_at(idx)
			budget -= 1
		# else: rejected by a per-type cap (e.g. "missile" at MISSILE_MAX_ALIVE) — leave queued, next pick tries another

## Deploy queued formations, oldest first, for as long as the ranged ceiling has room for the NEXT one.
## Stops at the first formation that doesn't fit rather than skipping past it — a level's fleet order is
## authored, so holding the queue in sequence keeps that intact; the held formation deploys as soon as
## enough of its predecessors' ranged members have died. A fleet carrying no ranged units never waits.
##
## A formation carrying MORE ranged units than the whole ceiling (fleet_layout.cfg has two: AT.Squid.Grid.15
## at 15 and AT.StingrayElite.Row.11 at 11) can never fit as authored. It is NOT waved through — the ceiling
## is absolute — and it is not dropped either: it waits for the full ceiling's worth of room, then deploys
## THINNED, with its ranged escorts capped to what fits (`shoot_budget`). Melee members are unaffected, so
## the formation still reads as itself, just with fewer guns up at once. Safe to thin: escorts are built from
## the `roster` array _deploy_fleet() hands to init_fleet_dock(), so a shorter roster is simply a smaller
## formation — nothing is orphaned (that only happens if a LIVE escort loses its carrier).
func _drain_fleet_queue() -> void:
	var guard := _fleet_queue.size()
	while not _fleet_queue.is_empty() and guard > 0:
		guard -= 1
		var it: Dictionary = _fleet_queue[0]
		var nm := String(it["name"])
		var sh := _fleet_shoot_count(nm)
		var budget := SHOOT_MAX_ALIVE
		if sh > 0:
			var room := SHOOT_MAX_ALIVE - _shoot_alive()
			# Wait for room for the whole formation, or — if it is bigger than the ceiling itself — for the
			# ceiling's full worth. Stops at the first formation that doesn't fit rather than skipping past
			# it, so the authored deployment order survives.
			if room < mini(sh, SHOOT_MAX_ALIVE):
				return
			budget = room
		_fleet_queue.pop_front()
		_deploy_fleet(nm, float(it["angle"]), float(it["rot"]), budget)
		# Keep the per-frame cache exact (several formations can deploy in one frame). A thinned deployment
		# only put `budget` ranged units on the field, not the formation's full `sh`.
		_shoot_alive_n += mini(sh, budget)

## Ranged units one deployment of `fleet_name` puts on the field. Cached: fleet_layout.cfg is read from disk
## by _load_fleets() and neither it nor ENEMY_DEFS changes mid-run.
func _fleet_shoot_count(fleet_name: String) -> int:
	if not _fleet_shoot_n.has(fleet_name):
		_fleet_shoot_n[fleet_name] = WaveHpGen.fleet_shoot_count(_load_fleets(), fleet_name, ENEMY_DEFS)
	return int(_fleet_shoot_n[fleet_name])

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

## Shared instancing path — takes an already-built def directly (Elite Creep spawns a scaled-up variant of
## a real ENEMY_DEFS entry this way; regular spawns just duplicate their def and call straight through).
## Bosses and "elite" defs (Elite Creep) always spawn — the alive-cap only applies to ordinary enemies, same
## rule v1 uses. This is the one authoritative cap check (the continuous loop's own room bookkeeping in
## _tick_spawn_loop is just a pre-filter so it doesn't over-queue; this is the final gate everything —
## continuous loop, timeline, Elite Creep — funnels through).
func _spawn_def(type_id: String, def: Dictionary, pos: Vector2, is_boss: bool = false) -> Node:
	# Unconditional — applies regardless of source (timeline, catch-up, cluster/wall) and ignores the
	# usual boss/elite cap-bypass, since "missile" itself is never boss/elite. See const comment above.
	if type_id == MISSILE_TYPE_ID and _type_alive_count(MISSILE_TYPE_ID) >= MISSILE_MAX_ALIVE:
		return null
	# 2026-08-25, on request ("metalfly là boss, không được spawn ra như creep"): a boss_stub def is a BOSS by
	# definition, so it is promoted here no matter how it was requested — an authored timeline row that forgot
	# `is_boss`, or any other path — instead of being fielded as a regular capped creep with none of a boss's
	# handling. Selection-side exclusion (is_auto_excluded) already keeps boss_stub out of every automatic
	# pool; this is the last line, so "spawned as a creep" is simply not reachable.
	if not is_boss and String(def.get("behavior", "")) == "boss_stub":
		is_boss = true
	var is_shooter := _shoot_ids.has(type_id)
	if not is_boss and not bool(def.get("elite", false)):
		# Ranged ceiling (see SHOOT_MAX_ALIVE). Refusing rather than dropping is the point: the caller leaves
		# the item in _spawn_queue and picks another, so the field still fills — with melee creeps — and this
		# one arrives when a slot frees up.
		if is_shooter and _shoot_alive() >= SHOOT_MAX_ALIVE:
			return null
		if get_tree().get_node_count_in_group("arena_enemy") >= _effective_cap():
			return null
	var e := EnemyScript.new()
	e.configure(type_id, _mgr, def)
	e.position = pos
	get_parent().add_child(e)
	if is_shooter:
		_shoot_alive_n += 1   # _drain_spawn_queue spawns several per frame; without this the cached count
		                      # below would stay stale within the frame and let the ceiling be overshot
	return e

## Public: may a NON-boss/elite creep of `type_id` spawn right now without breaching the ranged ceiling?
## For spawn paths that build an arena_enemy directly instead of going through _spawn_def() — today just
## arena_enemy.gd's _spawn_sibling() (stone→magma death-spawns, alien morphs). No current def death-spawns
## a ranged creep, so this changes nothing today; it exists so the ceiling can't be silently reopened by a
## future def, which is exactly how the "sentinel" hole got in.
func can_spawn_shooter(type_id: String) -> bool:
	return not _shoot_ids.has(type_id) or _shoot_alive() < SHOOT_MAX_ALIVE

## Live count of ranged creeps, rebuilt at most once per process frame (the gate above is consulted on every
## drain attempt, and this walks the whole "arena_enemy" group). Kept exact within a frame by the increment
## in _spawn_def; deaths only ever make it stale on the SAFE side (too high) until the next frame.
func _shoot_alive() -> int:
	var f := Engine.get_process_frames()
	if f != _shoot_alive_frame:
		_shoot_alive_frame = f
		var n := 0
		for e in get_tree().get_nodes_in_group("arena_enemy"):
			if _shoot_ids.has(String(e.get("_type"))):
				n += 1
		_shoot_alive_n = n
	return _shoot_alive_n

# ── Timeline engine ──────────────────────────────────────────────────────────────────────────────
func _tl_tick(delta: float) -> void:
	var t := elapsed()
	while _tl_next < _tl_fire_queue.size() and float(_tl_fire_queue[_tl_next].get("time", 0.0)) <= t:
		_tl_fire(_tl_fire_queue[_tl_next])
		_tl_next += 1
	# Generated milestone waves ride their own queue (see the const block on runtime HP milestones) — same
	# fire path, same clock, just kept separate so the authored queue's ordering/final-boss logic is untouched.
	while _gen_next < _gen_fire_queue.size() and float(_gen_fire_queue[_gen_next].get("time", 0.0)) <= t:
		_tl_fire(_gen_fire_queue[_gen_next])
		_gen_next += 1
	_tl_tick_streams(delta)
	_tick_final_boss(t)

## Final-boss finale: once every earlier entry has fired AND this entry's own authored time has passed,
## lock reinforcement off and wait for the field to hit zero (real players, real kills — no shortcuts)
## before spawning the boss alone. See the class-level comment on _final_boss_entry.
func _tick_final_boss(t: float) -> void:
	if _final_boss_entry.is_empty() or _final_boss_node != null:
		return
	if not _final_boss_pending:
		if _tl_next < _tl_fire_queue.size() or t < float(_final_boss_entry.get("time", 0.0)):
			return   # earlier entries (or streams from them) may still be playing out — not yet
		if _gen_ms_i < hp_targets.size() or _gen_next < _gen_fire_queue.size() or not _fleet_queue.is_empty():
			return   # a generated wave (or a formation held by the ranged ceiling) is still to come
		_final_boss_pending = true
		_reinforcement_locked = true
	if not _tl_streams.is_empty() or get_tree().get_node_count_in_group("arena_enemy") > 0:
		return   # still creeps alive (or a stream still has some left to fire) — keep waiting
	var type_s := String(_final_boss_entry.get("type", ""))
	var angle_deg := float(_final_boss_entry.get("angle", NAN))
	var pattern := String(_final_boss_entry.get("pattern", "ring"))
	if pattern == "random":
		pattern = RANDOM_FORMATIONS[randi() % RANDOM_FORMATIONS.size()]
	elif pattern == "stream" or not (pattern in PATTERNS):
		pattern = "ring"   # a solo boss spawns once, not trickled in — "stream" (or anything unrecognized) has no single-point meaning here
	var positions := _tl_pattern_positions(pattern, 1, angle_deg)
	var pos: Vector2 = positions[0] if not positions.is_empty() \
			else (_player.global_position if _player != null and is_instance_valid(_player) else Vector2.ZERO)
	_final_boss_node = _spawn(type_s, pos, true)
	if _final_boss_node != null:
		_final_boss_pending = false
		# Flag it so arena_enemy.gd's _die() knows to fire GameManager.final_boss_defeated on top of its
		# normal death effects (XP/loot/kill-count all still happen — this is purely additive).
		_final_boss_node.set("_is_final_boss", true)

## Debug (arena_hud_buttons.gd's BOSS FIGHT button / arena_debug_spawn.gd): skip straight to the timeline's
## final-boss finale. Silently despawns every currently-alive creep (no rewards — this is a dev shortcut,
## not a kill) and fast-forwards past every remaining regular wave entry, so _tick_final_boss() spawns the
## boss on its very next tick. Returns false (no-op) if the loaded timeline has no final-boss entry, or it
## already spawned/is already pending.
func debug_jump_to_final_boss() -> bool:
	if _final_boss_entry.is_empty() or _final_boss_node != null:
		return false
	_tl_next = _tl_fire_queue.size()
	_gen_ms_i = hp_targets.size()
	_gen_next = _gen_fire_queue.size()
	_fleet_queue.clear()
	_tl_streams.clear()
	_reinforcement_locked = true
	_final_boss_pending = true
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if is_instance_valid(e) and e.has_method("_despawn_stale"):
			e.call("_despawn_stale")
	return true

func _tl_fire(entry: Dictionary) -> void:
	var type_s := String(entry.get("type", ""))
	var is_boss := bool(entry.get("is_boss", false))
	# `no_auto` creeps (dummy — a test target) never reach the arena from a wave file, even one that names
	# them outright. 2026-08-25 follow-up: the first pass at this rule only filtered the AUTOMATIC selection
	# pools and deliberately let an authored row through, but elecforest.json authors 290 dummies across 6
	# rows, so they kept appearing in play. Blocking it here (rather than in _spawn_def) keeps
	# arena_debug_spawn's Quick Spawn working — that is the intended way to put a dummy on the field.
	if not type_s.begins_with("fleet:") and bool((ENEMY_DEFS.get(type_s, {}) as Dictionary).get("no_auto", false)):
		return
	var angle_deg := float(entry.get("angle", NAN))   # optional fixed spawn heading (deg); NAN = random
	if type_s.begins_with("fleet:"):
		# "n" (count) = how many times the whole formation deploys — same meaning as a Unit slot's count.
		# "angle" = fixed heading the formation spawns from/advances out of (NAN = random, same as Unit).
		# "fleet_rotate" = formation-shape rotation applied around its own centroid before placement.
		# "is_boss" doesn't apply to fleets — every fleet now deploys immediately (bypassing the alive-cap),
		# same as a mothership formation, since the rigid-dock carrier (_deploy_fleet()) needs a live node
		# reference to dock escorts onto right away; it can't wait in the shared drained _spawn_queue.
		# Not registered into _tl_seen_types: catch-up reinforcement spawns ONE type_id via _spawn_def(), it
		# has no concept of deploying a multi-unit formation, so fleets stay a timeline-only feature.
		var fleet_rot := float(entry.get("fleet_rotate", 0.0))
		for i in maxi(1, int(entry.get("count", 1))):
			_fleet_queue.append({"name": type_s.substr(6), "angle": angle_deg, "rot": fleet_rot})
		_drain_fleet_queue()   # deploy whatever fits right now; the rest waits on the ranged ceiling
		return
	var count := maxi(1, int(entry.get("count", 1)))
	var pattern := String(entry.get("pattern", "ring"))
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
## as v1). Every OTHER (generic) formation now deploys the same way: the largest slot becomes the flagship
## "carrier" (spawned immediately, running its own def's normal behavior/steering unmodified — real "creep"
## movement logic), and every other slot rigidly docks onto it via arena_enemy.gd's init_fleet_dock(), so the
## whole squad glides as one rigid block instead of each unit independently chasing the player and scattering
## apart from the authored formation shape. Immediate/cap-bypassing for the same reason mothership is: the
## carrier needs a live node reference to dock the rest onto right away, so it can't wait in _spawn_queue.
## `spawn_angle_deg` (NAN = random, matches _annulus_pos/_tl_pattern_positions convention) fixes which
## direction off the player the whole formation appears from/advances out of. `rotate_deg` spins the
## formation's own shape (each slot's offset from the fleet centroid) around that centroid before placing —
## independent of spawn_angle_deg, so a formation can face any way regardless of which side it enters from.
## `shoot_budget` = how many RANGED units this deployment may put on the field (see _drain_fleet_queue).
## Ranged escorts beyond it are skipped; melee escorts are never affected. Defaults to "no limit" for the
## callers that don't care (mothership path, debug deploy).
func _deploy_fleet(fleet_name: String, spawn_angle_deg: float = NAN, rotate_deg: float = 0.0, shoot_budget: int = 999999) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var fleet: Dictionary = {}
	for fl in _load_fleets():
		if String((fl as Dictionary).get("name", "")) == fleet_name:
			fleet = fl
			break
	if fleet.is_empty():
		return
	var slots_arr: Array = fleet.get("slots", [])
	var mother_slot: Dictionary = {}
	var child_slots: Array = []
	for s: Dictionary in slots_arr:
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
		_deploy_mothership_v2(mother_slot, child_slots, spawn_angle_deg, rotate_deg)
		return
	# Generic formation: the largest (by CANONICAL creep_layout.cfg draw width — Fleet Edit no longer stores
	# its own per-slot size, see fleet_edit_mode.gd's header) non-empty slot becomes the flagship/carrier.
	var carrier_idx := -1
	var carrier_size := -1.0
	for i in slots_arr.size():
		var s: Dictionary = slots_arr[i]
		var rep := ""
		for en in (s.get("enemies", []) as Array):
			if String(en) != "":
				rep = String(en)
				break
		if rep == "":
			continue
		var sz := EnemyScript.base_draw_width(ENEMY_DEFS.get(rep, {}))
		if sz > carrier_size:
			carrier_size = sz
			carrier_idx = i
	if carrier_idx < 0:
		return
	var carrier_slot: Dictionary = slots_arr[carrier_idx]
	var anchor_angle := deg_to_rad(spawn_angle_deg) if not is_nan(spawn_angle_deg) else NAN
	var anchor := _annulus_pos(_player.global_position, anchor_angle)
	var ref := _fleet_centroid(fleet)
	var rot := deg_to_rad(rotate_deg)
	var cpool: Array = []
	for en in (carrier_slot.get("enemies", []) as Array):
		if String(en) != "":
			cpool.append(String(en))
	var carrier_id := String(cpool[randi() % cpool.size()])
	var carrier_def: Dictionary = ENEMY_DEFS.get(carrier_id, {})
	if carrier_def.is_empty():
		return
	var cdef := carrier_def.duplicate()   # no draw_w override — creep_layout.cfg is the sole size source
	if _shoot_ids.has(carrier_id):
		shoot_budget -= 1   # the flagship itself is a ranged unit — it comes out of the same budget
	var carrier := EnemyScript.new()
	carrier.configure(carrier_id, _mgr, cdef)
	var carrier_off: Vector2 = (carrier_slot.get("pos", Vector2.ZERO) as Vector2) - ref
	if not is_zero_approx(rot):
		carrier_off = carrier_off.rotated(rot)
	carrier.global_position = anchor + carrier_off
	get_parent().add_child(carrier)
	var roster: Array = []
	for i in slots_arr.size():
		if i == carrier_idx:
			continue
		var s: Dictionary = slots_arr[i]
		var pool: Array = []
		for en in (s.get("enemies", []) as Array):
			if String(en) != "":
				pool.append(String(en))
		if pool.is_empty():
			continue
		var id := String(pool[randi() % pool.size()])   # random pool → roll one, same as v1
		if _shoot_ids.has(id):
			if shoot_budget <= 0:
				continue   # ranged ceiling reached — this escort is left out of the formation
			shoot_budget -= 1
		var off: Vector2 = (s.get("pos", Vector2.ZERO) as Vector2) - ref
		if not is_zero_approx(rot):
			off = off.rotated(rot)
		roster.append({"id": id, "base_off": off - carrier_off})
	carrier.init_fleet_dock(roster)

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
func _deploy_mothership_v2(mother_slot: Dictionary, child_slots: Array, spawn_angle_deg: float = NAN, rotate_deg: float = 0.0) -> void:
	var mslot: Dictionary = mother_slot["slot"]
	var mpos_screen: Vector2 = mslot.get("pos", Vector2.ZERO)
	var src: Dictionary = ENEMY_DEFS.get(String(mother_slot["id"]), {})
	if src.is_empty():
		return
	var mdef := src.duplicate()   # no draw_w override — creep_layout.cfg is the sole size source
	var mother: Node = EnemyScript.new()
	mother.call("configure", String(mother_slot["id"]), _mgr, mdef)
	var anchor_angle := deg_to_rad(spawn_angle_deg) if not is_nan(spawn_angle_deg) else NAN
	mother.set("global_position", _annulus_pos(_player.global_position, anchor_angle))
	get_parent().add_child(mother)
	var rot := deg_to_rad(rotate_deg)
	var roster: Array = []
	for cs: Dictionary in child_slots:
		var ids: Array = cs["ids"]
		var cid := String(ids[randi() % ids.size()])   # random pool → roll one (as the generic deploy)
		var cslot: Dictionary = cs["slot"]
		var base_off: Vector2 = (cslot.get("pos", Vector2.ZERO) as Vector2) - mpos_screen
		if not is_zero_approx(rot):
			base_off = base_off.rotated(rot)
		roster.append({
			"id": cid,
			"base_off": base_off,
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
## either reaching the player or leaving), "dummy" (a deliberately-placed STATIONARY landmark — e.g. the
## dead-ship wrecks/electric temple boss, both spawned far away on purpose with their own edge-of-screen
## pointer arrow + live distance specifically so the player travels TO them; silently teleporting one next to
## the player would defeat that whole point, and for the temple boss specifically would desync its 2D hit-box
## from the separate live 3D model electric_trees.gd renders at the ORIGINAL spawn position, which this system
## has no way to move in sync), and any `_docked` escort (pinned to its carrier's relative slot every frame by
## _ms_update_dock_positions() — teleporting it independently would fight that pin).
func _tick_despawn_teleport() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var c := _player.global_position
	var r_despawn := _r_max() * R_DESPAWN_MULT
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(e):
			continue
		var beh: String = String(e.get("behavior"))
		if beh == "boss_stub" or beh == "mothership" or beh == "patrol" or beh == "dummy":
			continue
		if bool(e.get("_docked")):
			continue
		var ep: Vector2 = (e as Node2D).global_position
		var off := ep - c
		if off.length() > r_despawn:
			var rel_angle := off.angle() if off.length() > 0.01 else randf() * TAU
			(e as Node2D).global_position = _annulus_pos(c, rel_angle)
