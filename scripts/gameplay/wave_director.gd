extends Node

## Runtime WAVE DIRECTOR — consumes a level recipe (as a Dictionary) and plays the level:
##   • difficulty ramps from floor → ceiling over `length_waves` waves (ceiling = the peak right
##     before the boss),
##   • each wave spawns up to max_spawns(d) enemies, one every spawn_interval(d) seconds, picked
##     (weighted) from the active types — the lower-difficulty types unlock first, more unlock as `d`
##     climbs,
##   • HYBRID advance: a wave ends when ≤ ADVANCE_THRESHOLD enemies remain (after the wave's budget is
##     fully spawned) OR the wave timer hits WAVE_MAX_TIME,
##   • after the last wave it spawns the recipe's boss.
## The F7 level tool's "Test Play" calls start(recipe). Group "wave_director".
##
## The difficulty→numbers mapping is STATIC so the F7 panel's preview uses the exact same math.

# ── Difficulty → numbers mapping (tunable — the preview reads these too) ──────
const SPAWNS_PER_DIFFICULTY := 1.0 / 3.0   # max spawn-actions per wave ≈ difficulty / 3 (easier)
const SPAWNS_CAP := 30
const INTERVAL_BASE := 4.0           # spawn interval at difficulty 0 (doubled — slower spawning)
const INTERVAL_SLOPE := 0.234        # interval drops this per difficulty point …
const INTERVAL_MIN := 1.0            # … down to this floor
const DIFFICULTY_PER_TYPE := 5.0     # every 5 difficulty unlocks one more type (d<5→1, 5-9→2, 10-14→3 …)
const ADVANCE_THRESHOLD := 0         # wave advances when NO enemies remain (all its enemies dead)…
const WAVE_MAX_TIME := 15.0          # …or after this many seconds (backstop)

# Sentinels count double toward a wave's budget ("weighted twice") — self-limits them at low difficulty.
const SENTINEL_COST := 2

# DANGER pre-boss intermission.
const DANGER_DURATION := 10.0        # seconds of NO spawns + blinking banner before the boss
const DANGER_BLINK_HZ := 4.0         # red↔white blinks per second

## Spawn-actions per wave ≈ difficulty/3, min 1, cap 30. d=1→1, d=6→2, d=12→4, d=30→10.
static func max_spawns(d: float) -> int:
	return clampi(int(round(d * SPAWNS_PER_DIFFICULTY)), 1, SPAWNS_CAP)

static func spawn_interval(d: float) -> float:
	return clampf(INTERVAL_BASE - d * INTERVAL_SLOPE, INTERVAL_MIN, INTERVAL_BASE)

## How many of the pool's types are live this wave: 1 + floor(d/5). d 1-4→1, 5-9→2, 10-14→3 … (capped at pool size).
static func active_types(d: float, pool_size: int) -> int:
	return clampi(1 + int(d / DIFFICULTY_PER_TYPE), 1, maxi(1, pool_size))

const ChoreographyRegistry := preload("res://scripts/gameplay/choreography_registry.gd")

enum State { IDLE, WAVES, DANGER, BOSS, DONE, CHOREO }
var _running: bool = false
var _state: int = State.IDLE
# ── Phase 2 choreography mode (additive — the legacy random-roll state below is untouched) ──
var _mode: String = "random"     # "random" (legacy) | "choreography"
var _waves: Array = []           # ordered choreography names
var _choreo: Node = null         # the active choreography instance (child of this director)
# ── Legacy random-roll state ──
var _pool: Array = []
var _edges: Array = []
var _weights: Dictionary = {}
var _floor: float = 1.0
var _ceiling: float = 10.0
var _length: int = 10
var _boss: String = "none"
var _wave: int = 0
var _wave_timer: float = 0.0
var _spawn_acc: float = 0.0
var _spent: int = 0          # budget points spent this wave (sentinels cost 2, others 1)
var _budget: int = 0
var _diver_done: bool = false   # only ONE diver set (burst of 3) is allowed per wave
var _danger_t: float = 0.0
var _danger_layer: CanvasLayer = null
var _danger_label: Label = null

func _ready() -> void:
	add_to_group("wave_director")

## Start playing a recipe (Dictionary, from LevelRecipe.to_dict()). Clears any current enemies first.
## A recipe with mode=="choreography" plays its `waves` list of choreographies; otherwise (the default)
## it falls back to the legacy difficulty random-roll below — that path is intentionally left intact.
func start(recipe: Dictionary) -> void:
	stop()
	_mode = String(recipe.get("mode", "random"))
	_boss = String(recipe.get("boss", "none"))
	if _mode == "choreography":
		var choreo_mode := String(recipe.get("choreo_mode", "fixed"))
		if choreo_mode == "pool":
			# Roll each wave independently from the allowed pool of choreographies. No two CONSECUTIVE
			# waves may be the same (re-roll on a repeat, unless the pool has only one entry).
			var pool := (recipe.get("choreo_pool", []) as Array)
			var count := int(recipe.get("choreo_wave_count", 6))
			_waves = []
			var last := ""
			for i in count:
				if not pool.is_empty():
					var pick := String(pool[randi() % pool.size()])
					while pick == last and pool.size() > 1:
						pick = String(pool[randi() % pool.size()])
					_waves.append(pick)
					last = pick
		else:
			_waves = (recipe.get("waves", []) as Array).duplicate()
		if _waves.is_empty():
			push_warning("[wave_director] choreography recipe has no waves — nothing to play")
			return
		_wave = 0
		_begin_choreo_wave()
		_state = State.CHOREO
		_running = true
		return
	# ── Legacy random-roll (unchanged) ──
	_pool = (recipe.get("enemy_pool", []) as Array).duplicate()
	_edges = (recipe.get("entry_edges", []) as Array).duplicate()
	_weights = (recipe.get("weights", {}) as Dictionary).duplicate()
	_floor = float(recipe.get("difficulty_floor", 1.0))
	_ceiling = float(recipe.get("difficulty_ceiling", 10.0))
	_length = maxi(1, int(recipe.get("length_waves", 10)))
	_boss = String(recipe.get("boss", "none"))
	if _pool.is_empty():
		push_warning("[wave_director] recipe has an empty enemy pool — nothing to spawn")
		return
	_wave = 0
	_begin_wave()
	_state = State.WAVES
	_running = true

func stop() -> void:
	_running = false
	_state = State.IDLE
	_hide_danger()
	_end_choreo()
	var mgr := get_tree().get_first_node_in_group("enemy_manager")
	if mgr != null and mgr.has_method("clear_enemies"):
		mgr.clear_enemies()

func is_running() -> bool:
	return _running

func _difficulty_for_wave(w: int) -> float:
	if _length <= 1:
		return _ceiling
	return lerpf(_floor, _ceiling, float(w) / float(_length - 1))

func _begin_wave() -> void:
	var d := _difficulty_for_wave(_wave)
	_budget = max_spawns(d)
	_wave_timer = 0.0
	_spawn_acc = spawn_interval(d)   # so the first enemy spawns immediately
	_spent = 0
	_diver_done = false

func _process(delta: float) -> void:
	if not _running:
		return
	match _state:
		State.WAVES:
			_tick_waves(delta)
		State.CHOREO:
			_tick_choreo_waves(delta)
		State.DANGER:
			_tick_danger(delta)

func _tick_waves(delta: float) -> void:
	var d := _difficulty_for_wave(_wave)
	var interval := spawn_interval(d)
	_wave_timer += delta
	_spawn_acc += delta
	if _spent < _budget and _spawn_acc >= interval:
		_spawn_acc = 0.0
		var cost := _spawn_one(d)
		if cost <= 0:
			_spent = _budget   # nothing left this wave that isn't capped → treat budget as spent
		else:
			_spent += cost     # add the spawned type's budget cost
	var living := get_tree().get_nodes_in_group("normal_enemy").size()
	var spawned_all := _spent >= _budget
	if (spawned_all and living <= ADVANCE_THRESHOLD) or _wave_timer >= WAVE_MAX_TIME:
		_wave += 1
		if _wave >= _length:
			_enter_danger()
		else:
			_begin_wave()

## Spawn one weighted type; returns its budget cost (sentinels=2, others=1), or 0 if nothing eligible
## remains (e.g. the only active type is diver and it already fired its one set this wave).
func _spawn_one(d: float) -> int:
	var n_types := active_types(d, _pool.size())
	var active: Array = _pool.slice(0, n_types)
	# Drop types that have hit their per-wave cap (diver = 1 set/wave).
	var avail: Array = []
	for t in active:
		if String(t) == "diver" and _diver_done:
			continue
		avail.append(t)
	if avail.is_empty():
		return 0
	var type := _weighted_pick(avail)
	var mgr := get_tree().get_first_node_in_group("enemy_manager")
	if mgr != null and mgr.has_method("spawn_type"):
		mgr.spawn_type(type, _edges)
	if type == "diver":
		_diver_done = true
	return SENTINEL_COST if type == "sentinels" else 1

func _weighted_pick(types: Array) -> String:
	var total := 0.0
	for t in types:
		total += maxf(0.0, float(_weights.get(t, 1.0)))
	if total <= 0.0:
		return String(types[randi() % types.size()])
	var r := randf() * total
	var cum := 0.0
	for t in types:
		cum += maxf(0.0, float(_weights.get(t, 1.0)))
		if r < cum:
			return String(t)
	return String(types[types.size() - 1])

# ── Phase 2: choreography waves ───────────────────────────────────────────────
# A level is an ordered list of choreographies. Each plays until it reports done OR its own max_time()
# backstop fires (the same hybrid advance idea as the legacy waves). After the last one → DANGER → boss.

func _enemy_manager() -> Node:
	return get_tree().get_first_node_in_group("enemy_manager")

func _begin_choreo_wave() -> void:
	_end_choreo()
	_wave_timer = 0.0
	var nm := String(_waves[_wave])
	_choreo = ChoreographyRegistry.make(nm)
	if _choreo == null:
		push_warning("[wave_director] unknown choreography '%s' — skipping" % nm)
		return
	add_child(_choreo)
	if _choreo.has_method("start"):
		_choreo.start(_enemy_manager())

func _tick_choreo_waves(delta: float) -> void:
	_wave_timer += delta
	if _choreo != null and is_instance_valid(_choreo) and _choreo.has_method("tick"):
		_choreo.tick(delta)
	var backstop: float = 0.0
	if _choreo != null and is_instance_valid(_choreo) and _choreo.has_method("max_time"):
		backstop = float(_choreo.max_time())
	var done: bool = _choreo == null or not is_instance_valid(_choreo) \
		or (_choreo.has_method("is_done") and _choreo.is_done())
	if done or (backstop > 0.0 and _wave_timer >= backstop):
		_end_choreo()
		_wave += 1
		if _wave >= _waves.size():
			_enter_danger()      # reuse the existing DANGER → boss flow
		else:
			_begin_choreo_wave()

func _end_choreo() -> void:
	if _choreo != null and is_instance_valid(_choreo):
		if _choreo.has_method("cleanup"):
			_choreo.cleanup()
		_choreo.queue_free()
	_choreo = null

# ── DANGER intermission (10s, no spawns, blinking banner) → then the boss ─────
func _enter_danger() -> void:
	_state = State.DANGER
	_danger_t = 0.0
	_show_danger()

func _tick_danger(delta: float) -> void:
	_danger_t += delta
	if _danger_label != null:
		# Blink red ↔ white.
		var k := 0.5 + 0.5 * sin(_danger_t * TAU * DANGER_BLINK_HZ)
		_danger_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15).lerp(Color.WHITE, k))
	if _danger_t >= DANGER_DURATION:
		_hide_danger()
		_start_boss()

func _show_danger() -> void:
	_hide_danger()
	_danger_layer = CanvasLayer.new()
	_danger_layer.layer = 95
	add_child(_danger_layer)
	_danger_label = Label.new()
	_danger_label.text = "DANGER"
	_danger_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_danger_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_danger_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if font != null:
		_danger_label.add_theme_font_override("font", font)
	_danger_label.add_theme_font_size_override("font_size", 110)
	_danger_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_danger_label.add_theme_constant_override("outline_size", 10)
	_danger_layer.add_child(_danger_label)

func _hide_danger() -> void:
	if _danger_layer != null and is_instance_valid(_danger_layer):
		_danger_layer.queue_free()
	_danger_layer = null
	_danger_label = null

func _start_boss() -> void:
	if _boss != "none" and _boss != "":
		_state = State.BOSS
		var bf := get_tree().get_first_node_in_group("boss_fight")
		if bf != null and bf.has_method("spawn_boss"):
			bf.spawn_boss(_boss)
	else:
		_state = State.DONE
		_running = false
