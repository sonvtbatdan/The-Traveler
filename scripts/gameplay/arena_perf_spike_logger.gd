extends Node
## TEMP DIAGNOSTIC — NOT part of the game, safe to delete.
##
## Watches frame delta every _process(); when a frame spikes well above the recent rolling average (or
## is just absolutely slow), prints one line to the Godot console with a full snapshot: enemy/loot/ruin
## counts, deaths since the last frame, live node count, physics-2D collision pairs/active bodies, and
## render draw calls. Purpose: pin down a "sudden, not-gradual-with-creep-count" lag spike reported during
## a Level_1_Minh playtest — the log line tells us what was actually happening in the spiking frame instead
## of guessing.
##
## To remove once the cause is found: delete this file and its one `add_child(PerfSpikeLoggerScript.new())`
## line in arena.gd's _ready().

const ArenaEnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const ArenaWeaponsScript := preload("res://scripts/gameplay/arena_weapons.gd")

const SPIKE_ABS_THRESHOLD := 0.05   # a frame taking >= 50ms (<20 FPS) on its own is always logged
const SPIKE_REL_MULT      := 2.5    # ...or this frame is >= 2.5x the recent rolling average
const ROLLING_WINDOW      := 60     # frames averaged for the baseline
const LOG_COOLDOWN        := 0.5    # don't spam the console — at most one log per this many seconds

var _hist: Array[float] = []
var _cooldown_t: float = 0.0
var _last_phys_frame: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_phys_frame = Engine.get_physics_frames()
	print("[perf-spike-logger] armed — watching for frame spikes (abs >= %dms or >= %.1fx rolling avg)" % [int(SPIKE_ABS_THRESHOLD * 1000.0), SPIKE_REL_MULT])

func _process(delta: float) -> void:
	_cooldown_t = maxf(0.0, _cooldown_t - delta)
	var avg := delta
	if not _hist.is_empty():
		var sum := 0.0
		for d: float in _hist:
			sum += d
		avg = sum / _hist.size()
	var is_spike := delta >= SPIKE_ABS_THRESHOLD and (_hist.is_empty() or delta >= avg * SPIKE_REL_MULT)
	_hist.append(delta)
	if _hist.size() > ROLLING_WINDOW:
		_hist.pop_front()
	# Always consume every counter so it doesn't leak into an unrelated later spike.
	var deaths := ArenaEnemyScript.consume_death_count()
	var near_candidates := ArenaWeaponsScript.consume_near_query_candidates()
	var near_calls := ArenaWeaponsScript.consume_near_query_calls()
	# How many physics ticks actually ran DURING this rendered frame. Godot runs extra catch-up physics
	# steps (up to `physics/common/max_physics_steps_per_frame`, default 8) when a frame falls behind its
	# fixed physics timestep — if this spikes to several during a lag frame, the enemy per-tick script cost
	# is being multiplied several times over within that single visual frame (a feedback spiral: falling
	# behind makes the next frame cost more, which falls further behind).
	var phys_now := Engine.get_physics_frames()
	var phys_steps := phys_now - _last_phys_frame
	_last_phys_frame = phys_now
	if is_spike and _cooldown_t <= 0.0:
		_cooldown_t = LOG_COOLDOWN
		_log_snapshot(delta, avg, deaths, phys_steps, near_candidates, near_calls)

func _log_snapshot(delta: float, avg: float, deaths: int, phys_steps: int, near_candidates: int, near_calls: int) -> void:
	var tree := get_tree()
	var total_enemies := tree.get_node_count_in_group("arena_enemy")
	# Dogpile check: how many enemies are currently within ~200px of the player (a proxy for "the whole
	# horde has converged into a ball around the ship" — this is an O(N) scan, but it only runs on already-
	# rare, cooldown-gated spike frames, so it doesn't add sustained per-frame cost of its own).
	var dogpile := _count_near_player(200.0)
	print("[perf-spike] frame=%.1fms avg=%.1fms fps=%d | phys_steps_this_frame=%d proc_ms=%.1f physproc_ms=%.1f | enemies=%d within200=%d loot=%d ruins=%d orbs_mgr=%s | deaths_this_frame=%d | near_query calls=%d candidates=%d avg/call=%.0f | nodes=%d | phys2d_pairs=%d phys2d_active=%d | draw_calls=%d objs_in_frame=%d" % [
		delta * 1000.0,
		avg * 1000.0,
		int(Engine.get_frames_per_second()),
		phys_steps,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		total_enemies,
		dogpile,
		tree.get_node_count_in_group("arena_loot"),
		tree.get_node_count_in_group("arena_ruin"),
		_xp_orb_count(),
		deaths,
		near_calls,
		near_candidates,
		(float(near_candidates) / float(near_calls)) if near_calls > 0 else 0.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
	])

## How many "arena_enemy" group members (legacy Node-based OR batched proxy — both expose
## global_position) are within `radius` of the player right now.
func _count_near_player(radius: float) -> int:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return -1
	var p: Vector2 = player.global_position
	var r2 := radius * radius
	var n := 0
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if is_instance_valid(e) and (e as Node2D).global_position.distance_squared_to(p) <= r2:
			n += 1
	return n

## xp orbs live inside the single MultiMesh manager (group "arena_xp_orb_mgr") as a live count in its
## private `_n` var, not one node each — read it directly rather than adding a public accessor just for
## this temp diagnostic.
func _xp_orb_count() -> String:
	var mgr := get_tree().get_first_node_in_group("arena_xp_orb_mgr")
	if mgr != null and mgr.get("_n") != null:
		return str(mgr.get("_n"))
	return "?"
