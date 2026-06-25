extends Node2D
## Authored-timeline wave spawner for the arena (Vampire Survivors / Halls of Torment style). A hand-authored,
## time-keyed data table fires reusable spawn patterns that place enemies radially around the player, just
## off-screen. Deterministic: the same timeline plays the same every run (only spawn angles are random).
##
## Three layers: (1) ENEMY_DEFS table, (2) spawn-pattern functions, (3) the TIMELINE data block.
## Bosses are stubbed as big high-HP enemies for now (real movesets port later). This is a fresh system —
## it deliberately does NOT use the legacy wave_director/level_recipe/choreography code.

const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")

# ══ TUNABLES ═══════════════════════════════════════════════════════════════════
const SPAWN_RADIUS  := 720.0   # base ring radius — just beyond the visible screen
const SPAWN_VARY    := 120.0   # ± jitter on spawn radius
const COUNT_MULT    := 1.0     # global multiplier on every entry's count
const HP_MULT       := 1.0     # global enemy-HP multiplier (quick difficulty knob)
const SPEED_MULT    := 1.0     # global enemy-speed multiplier
const MAX_ALIVE     := 120     # hard cap on living enemies (bosses still spawn over the cap)
const BLOB_SPAWN_R  := 90.0    # cluster radius for "blob" enemies (e.g. the 50-strong swarm)

# ══ 1. ENEMY DEFINITION TABLE ══════════════════════════════════════════════════
# id → { behavior, hp, speed, size, contact, xp, shape, tint, (explodes), (armor) }
const ENEMY_DEFS := {
	"diver":    {"behavior": "spiral",    "hp": 30.0,  "speed": 150.0, "size": 14.0, "contact": 10, "explodes": true, "xp": 4,  "icon": "res://assets/enemies/kingfisher.png"},
	"centipede":{"behavior": "centipede", "hp": 180.0, "speed": 100.0, "size": 20.0, "contact": 20, "xp": 24, "armor": 1.0, "icon": "res://assets/enemies/animalcentipede.png"},
	"dragonfly":{"behavior": "orbit",     "hp": 90.0,  "speed": 130.0, "size": 16.0, "contact": 10, "explodes": true, "xp": 10, "icon": "res://assets/enemies/animaldragonfly.png"},
	"octopus":  {"behavior": "jump",      "hp": 180.0, "speed": 130.0, "size": 22.0, "contact": 20, "explodes": true, "xp": 24, "icon": "res://assets/enemies/animaloctopus.png"},
	# ── GROUP 1: INSECTS (temporary uniform behavior = slow chase; levels 1→3; XP = HP/10) ──
	"swarm":    {"behavior": "swarm", "group": "insects", "level": 1, "blob": 50, "hp": 10.0,  "speed": 200.0, "size": 12.0, "contact": 1, "explodes": true, "xp": 1,  "icon": "res://assets/enemies/swarm.png"},
	"fly":      {"behavior": "chase", "group": "insects", "level": 1, "hp": 20.0,  "speed": 80.0, "size": 9.0,  "contact": 2, "explodes": true, "xp": 2,  "icon": "res://assets/enemies/animalflies.png"},
	"bug":      {"behavior": "chase", "group": "insects", "level": 2, "hp": 100.0, "speed": 80.0, "size": 11.0, "contact": 3, "explodes": true, "xp": 10, "icon": "res://assets/enemies/animalbug.png", "eye": {"icon": "res://assets/enemies/animalbug_eye.png", "socket": Vector2(0.5265, 0.3551), "range": Vector2(0.0754, 0.0507), "size": Vector2(0.1701, 0.1957)}},
	"bee":      {"behavior": "chase", "group": "insects", "level": 2, "hp": 40.0,  "speed": 80.0, "size": 12.0, "contact": 3, "explodes": true, "xp": 4,  "icon": "res://assets/enemies/animalbee.png"},
	"spider":   {"behavior": "chase", "group": "insects", "level": 3, "hp": 500.0, "speed": 80.0, "size": 16.0, "contact": 8, "explodes": true, "xp": 50, "icon": "res://assets/enemies/animalspider.png"},
	"shooter":  {"behavior": "shooter",   "hp": 50.0,  "speed": 110.0, "size": 16.0, "contact": 0,  "xp": 10, "icon": "res://assets/enemies/jetfighter.png"},
	"sentinel": {"behavior": "sentinel",  "hp": 420.0, "speed": 90.0,  "size": 22.0, "contact": 0,  "xp": 14, "icon": "res://assets/enemies/sentinel.png"},
	"beamer":   {"behavior": "beamer",    "hp": 60.0,  "speed": 90.0,  "size": 18.0, "contact": 0,  "xp": 12, "icon": "res://assets/enemies/beamer.png"},
	"bomber":   {"behavior": "bomber",    "hp": 190.0, "speed": 100.0, "size": 20.0, "contact": 0,  "xp": 24, "icon": "res://assets/enemies/bombing.gif"},
	"missile":  {"behavior": "missile",   "hp": 520.0, "speed": 90.0,  "size": 22.0, "contact": 0,  "xp": 18, "icon": "res://assets/enemies/missilelauncher.png"},
	"dummy":    {"behavior": "dummy",     "hp": 200.0, "speed": 0.0,   "size": 18.0, "contact": 0,  "xp": 0,  "invincible": true, "icon": "res://assets/enemies/dummy.png"},
	# bosses — big high-HP stubs (real movesets later)
	"elephant":  {"behavior": "boss_stub", "hp": 5500.0, "speed": 110.0, "size": 70.0, "contact": 40, "xp": 500, "shape": "circle",   "tint": Color(0.75, 0.70, 0.65), "icon": "res://assets/bosses/elephant/elephant.sheet.png", "boss_script": "res://scripts/gameplay/arena_elephant.gd"},
	"chromeleon":{"behavior": "boss_stub", "hp": 4200.0, "speed": 70.0, "size": 60.0, "contact": 35, "xp": 400, "shape": "diamond",  "tint": Color(0.45, 0.90, 0.65), "icon": "res://assets/bosses/chromeleon/chromeleon.sheet.png"},
	"metalfly":  {"behavior": "boss_stub", "hp": 4800.0, "speed": 65.0, "size": 64.0, "contact": 38, "xp": 450, "shape": "triangle", "tint": Color(0.70, 0.75, 0.85), "icon": "res://assets/bosses/metalfly/metalfly.sheet.png"},
}

# ══ 3. AUTHORED TIMELINE ═══════════════════════════════════════════════════════
# Ordered by time (seconds). Each entry: time, type, count, pattern, [duration], [is_boss].
# pattern ∈ "ring" | "arc" | "stream" | "scatter".  duration (stream) spreads spawns over that window.
const PATTERNS := ["ring", "arc", "stream", "scatter"]
const DEFAULT_TIMELINE := [
	# ── 0:00–1:00 — gentle intro, single types ──
	{"time": 1.0,   "type": "fly",       "count": 6,  "pattern": "ring"},
	{"time": 8.0,   "type": "fly",       "count": 8,  "pattern": "scatter"},
	{"time": 15.0,  "type": "diver",     "count": 5,  "pattern": "arc"},
	{"time": 24.0,  "type": "spider",    "count": 4,  "pattern": "scatter"},
	{"time": 34.0,  "type": "bug",       "count": 16, "pattern": "stream", "duration": 6.0},
	{"time": 46.0,  "type": "dragonfly", "count": 4,  "pattern": "ring"},
	{"time": 55.0,  "type": "shooter",   "count": 3,  "pattern": "arc"},
	# ── 1:00–2:00 — mixed, higher counts ──
	{"time": 66.0,  "type": "bee",       "count": 16, "pattern": "ring"},
	{"time": 78.0,  "type": "octopus",   "count": 3,  "pattern": "scatter"},
	{"time": 86.0,  "type": "diver",     "count": 8,  "pattern": "stream", "duration": 5.0},
	{"time": 98.0,  "type": "sentinel",  "count": 2,  "pattern": "arc"},
	{"time": 108.0, "type": "centipede", "count": 3,  "pattern": "scatter"},
	# ── 2:00 — MID BOSS ──
	{"time": 120.0, "type": "metalfly",  "count": 1,  "pattern": "ring", "is_boss": true},
	{"time": 125.0, "type": "fly",       "count": 14, "pattern": "stream", "duration": 10.0},
	# ── 2:10–3:30 — escalation ──
	{"time": 140.0, "type": "beamer",    "count": 3,  "pattern": "ring"},
	{"time": 150.0, "type": "bug",       "count": 22, "pattern": "ring"},
	{"time": 162.0, "type": "bomber",    "count": 2,  "pattern": "arc"},
	{"time": 172.0, "type": "swarm",     "count": 1,  "pattern": "ring"},   # one 50-strong blob
	{"time": 186.0, "type": "missile",   "count": 2,  "pattern": "scatter"},
	{"time": 196.0, "type": "dragonfly", "count": 8,  "pattern": "ring"},
	{"time": 206.0, "type": "octopus",   "count": 5,  "pattern": "scatter"},
	# ── 3:30 — chromeleon + swarm ──
	{"time": 210.0, "type": "chromeleon","count": 1,  "pattern": "ring", "is_boss": true},
	{"time": 215.0, "type": "bee",       "count": 16, "pattern": "stream", "duration": 12.0},
	{"time": 235.0, "type": "shooter",   "count": 6,  "pattern": "ring"},
	{"time": 250.0, "type": "centipede", "count": 5,  "pattern": "scatter"},
	{"time": 265.0, "type": "sentinel",  "count": 4,  "pattern": "arc"},
	# ── 5:00 — END BOSS + full mix ──
	{"time": 300.0, "type": "elephant",  "count": 1,  "pattern": "ring", "is_boss": true},
	{"time": 305.0, "type": "diver",     "count": 12, "pattern": "stream", "duration": 12.0},
	{"time": 320.0, "type": "missile",   "count": 3,  "pattern": "scatter"},
	{"time": 335.0, "type": "swarm",     "count": 1,  "pattern": "ring"},   # one 50-strong blob
]

# ══ DEBUG ══════════════════════════════════════════════════════════════════════
# Spawn ONLY the Elephant (one, immediately) and nothing else — for iterating on its moveset.
# Set DEBUG_ELEPHANT_ONLY = false to restore the full DEFAULT_TIMELINE.
const DEBUG_ELEPHANT_ONLY := false
const DEBUG_TIMELINE := [
	{"time": 1.0, "type": "elephant", "count": 1, "pattern": "ring", "is_boss": true},
]
# Auto-load NOTHING — no elephant, no enemies at all (empty timeline). Set false to restore spawning.
const DEBUG_NO_ENEMIES := false

# ══ Runtime ════════════════════════════════════════════════════════════════════
var timeline: Array = []    # live, editable copy of DEFAULT_TIMELINE (the F7 editor mutates this)
var _player: Node2D = null
var _mgr: Node = null
var _elapsed: float = 0.0
var _next: int = 0          # index of the next timeline entry to fire
var _streams: Array = []    # active stream entries: {type, left, interval, acc, is_boss}

func _ready() -> void:
	add_to_group("wave_director")
	timeline = [] if DEBUG_NO_ENEMIES else (DEBUG_TIMELINE if DEBUG_ELEPHANT_ONLY else DEFAULT_TIMELINE).duplicate(true)
	_player = get_tree().get_first_node_in_group("player")
	_mgr = get_tree().get_first_node_in_group("enemy_manager")

# ── Editor API (used by the F7 wave editor) ────────────────────────────────────
func enemy_types() -> Array:
	return ENEMY_DEFS.keys()

func get_timeline() -> Array:
	return timeline

## Replace the timeline (sorted by time) and restart the clock from t=0.
func set_timeline(entries: Array) -> void:
	timeline = entries.duplicate(true)
	timeline.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	restart()

func elapsed() -> float:
	return _elapsed

## Reset the playback clock so an edited timeline replays from the start.
func restart() -> void:
	_elapsed = 0.0
	_next = 0
	_streams.clear()
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if is_instance_valid(e):
			e.queue_free()

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	_elapsed += delta
	while _next < timeline.size() and float(timeline[_next]["time"]) <= _elapsed:
		_fire(timeline[_next])
		_next += 1
	_tick_streams(delta)

func _fire(entry: Dictionary) -> void:
	var count := maxi(1, int(round(float(int(entry["count"])) * COUNT_MULT)))
	var pattern := String(entry.get("pattern", "ring"))
	var is_boss := bool(entry.get("is_boss", false))
	if pattern == "stream":
		var dur := float(entry.get("duration", 4.0))
		_streams.append({"type": entry["type"], "left": count, "interval": dur / float(count),
			"acc": 0.0, "is_boss": is_boss})
		return
	for pos: Vector2 in _pattern_positions(pattern, count):
		_spawn(String(entry["type"]), pos, is_boss)

func _tick_streams(delta: float) -> void:
	var i := _streams.size() - 1
	while i >= 0:
		var s: Dictionary = _streams[i]
		s["acc"] = float(s["acc"]) + delta
		while float(s["acc"]) >= float(s["interval"]) and int(s["left"]) > 0:
			s["acc"] = float(s["acc"]) - float(s["interval"])
			_spawn(String(s["type"]), _one_position(), bool(s["is_boss"]))
			s["left"] = int(s["left"]) - 1
		if int(s["left"]) <= 0:
			_streams.remove_at(i)
		i -= 1

# ══ 2. SPAWN PATTERNS (radial around the player, just off-screen) ══════════════
func _spawn_center() -> Vector2:
	return _player.global_position

func _radius() -> float:
	return SPAWN_RADIUS + randf_range(-SPAWN_VARY, SPAWN_VARY)

func _one_position() -> Vector2:
	var a := randf() * TAU
	return _spawn_center() + Vector2(cos(a), sin(a)) * _radius()

func _pattern_positions(pattern: String, count: int) -> Array:
	var out: Array = []
	var c := _spawn_center()
	match pattern:
		"ring":   # evenly spaced full circle
			var off := randf() * TAU
			for k in count:
				var a := off + TAU * float(k) / float(count)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
		"arc":    # partial arc from a random direction
			var start := randf() * TAU
			var span := deg_to_rad(120.0)
			for k in count:
				var a := start + span * (float(k) / float(maxi(1, count - 1)) - 0.5)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
		"scatter":   # random angles + distances
			for k in count:
				out.append(_one_position())
		_:   # fallback = ring
			for k in count:
				var a := TAU * float(k) / float(count)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
	return out

# ══ Spawn ══════════════════════════════════════════════════════════════════════
func _spawn(type_id: String, pos: Vector2, is_boss: bool) -> void:
	# Beacon aux item lifts the alive-cap so more enemies crowd the field (base mult 1.0 = no change).
	var spawn_mult: float = GameManager.upg_spawn_rate_mult if "upg_spawn_rate_mult" in GameManager else 1.0
	var cap := int(round(float(MAX_ALIVE) * spawn_mult))
	if not is_boss and get_tree().get_nodes_in_group("arena_enemy").size() >= cap:
		return
	var src: Dictionary = ENEMY_DEFS.get(type_id, {})
	if src.is_empty():
		return
	var def := src.duplicate()
	def["hp"] = float(def.get("hp", 30.0)) * HP_MULT
	def["speed"] = float(def.get("speed", 95.0)) * SPEED_MULT
	# Blob enemies (e.g. the 50-strong swarm) spawn as a tight cluster that shares ONE behavior mode, so the
	# whole blob travels together (all zoom across, or all chase).
	var blob := int(def.get("blob", 1))
	if blob > 1 and not is_boss:
		var mode := "zoom" if randf() < 0.5 else "chase"
		var room := maxi(0, cap - get_tree().get_nodes_in_group("arena_enemy").size())
		for k in mini(blob, room):
			var d := def.duplicate()
			d["swarm_mode"] = mode
			var u := EnemyScript.new()
			u.configure(type_id, _mgr, d)
			u.position = pos + Vector2(cos(randf() * TAU), sin(randf() * TAU)) * randf_range(0.0, BLOB_SPAWN_R)
			get_parent().add_child(u)
		return
	# Bosses with a dedicated class (e.g. the Elephant moveset) instantiate that instead of the generic enemy.
	var e: Node
	if def.has("boss_script"):
		var bs := load(String(def["boss_script"])) as GDScript
		e = bs.new() if bs != null else EnemyScript.new()
	else:
		e = EnemyScript.new()
	e.configure(type_id, _mgr, def)
	e.position = pos
	get_parent().add_child(e)

## Debug: drop one invincible dummy (blocks the beam, never dies) at a world position. Bypasses MAX_ALIVE.
func spawn_dummy_near(pos: Vector2) -> void:
	_spawn("dummy", pos, true)
