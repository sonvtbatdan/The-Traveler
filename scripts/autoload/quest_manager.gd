extends Node
## Quest system — the Electric quest board (Bridge room, see scripts/ui/boards/quest_binder.gd).
##
## 12 quests (eq01..eq12) in 3 tiers, tier-gated. Progress is tracked live during a run (per-enemy-type /
## per-faction kills, survive time, no-hit window, 3 s burst-kill peak, temple breaks, boss kills, rescue)
## plus a persistent per-map lifetime kill tally; every quest's objective is evaluated at run end and newly
## satisfied quests are marked done + their reward applied.
##
## Rewards: coins are applied for real (GameManager.add_money). "+X% … on Electric" bonuses and permanent
## luck / global-XP are RECORDED here (map_mod / luck_bonus / global_xp_pct, persisted) and exposed for the
## arena to read — wiring those numbers into live gameplay is a follow-up.
##
## Persisted in user://save.cfg [quests]: state, lifetime kills, recorded reward effects, tracked set.

signal quest_changed

const SAVE_PATH := "user://save.cfg"

## Enemy type ids that count as "A.I.nimal" for eq02 (arena_wave_director.ENEMY_DEFS group "insects" + the
## loose A.I.nimal ids + their v2 variants).
const AINIMAL_IDS := ["swarm", "swarm_loop", "fly", "dragonfly", "diver", "bug", "bee", "bee_dive",
	"spider", "centipede", "animalhornet", "squid"]

const QUESTS := {
	"eq01": {"name": "First Contact", "tier": 1, "prereq": [],
		"objective": "Finish a run on the Electric map — reach the run-over screen.",
		"reward": "500 coins. Opens the rest of the Electric board.",
		"trivia": "\"Drop into the sector, come back in one piece. That's the whole ask.\"",
		"obj": {"type": "run_end"}, "rw": [{"t": "coins", "n": 500}]},
	"eq02": {"name": "Pest Control", "tier": 1, "prereq": ["eq01"],
		"objective": "Kill 300 A.I.nimal creatures in a single run.",
		"reward": "600 coins. +2% XP gain on Electric.",
		"trivia": "\"The broods breed faster than we can log them. Thin the count.\"",
		"obj": {"type": "faction_run", "faction": "ainimal", "n": 300},
		"rw": [{"t": "coins", "n": 600}, {"t": "mod", "map": "electric", "key": "xp_pct", "n": 2}]},
	"eq03": {"name": "Hold the Line", "tier": 1, "prereq": ["eq01"],
		"objective": "Stay alive until the run clock reaches 10:00 on Electric.",
		"reward": "900 coins.",
		"trivia": "\"Ten minutes. Don't be clever, just don't die.\"",
		"obj": {"type": "survive", "t": 600.0}, "rw": [{"t": "coins", "n": 900}]},
	"eq04": {"name": "Salvage Rights", "tier": 1, "prereq": ["eq01"],
		"objective": "Break a temple landmark on Electric.",
		"reward": "1000 coins.",
		"trivia": "\"There's a temple hull half-buried in the blue-grass. Crack it open.\"",
		"obj": {"type": "temples", "n": 1}, "rw": [{"t": "coins", "n": 1000}]},
	"eq05": {"name": "Swarm Protocol", "tier": 2, "prereq": ["eq01"],
		"objective": "Kill 50 enemies within a 3-second window, once.",
		"reward": "1200 coins. +5% blast / AoE radius on Electric.",
		"trivia": "\"Let them ball up. Then delete the ball.\"",
		"obj": {"type": "burst", "n": 50, "window": 3.0},
		"rw": [{"t": "coins", "n": 1200}, {"t": "mod", "map": "electric", "key": "blast_pct", "n": 5}]},
	"eq06": {"name": "Ground the Sentinels", "tier": 2, "prereq": ["eq01"],
		"objective": "Destroy 5 Sentinel Leaders across any number of Electric runs.",
		"reward": "1200 coins. +10% armour pen vs armoured on Electric.",
		"trivia": "\"The Kingdom's patrol line answers fire with fire. Take the leaders off the board.\"",
		"obj": {"type": "type_lifetime", "id": "sentinelleader", "n": 5},
		"rw": [{"t": "coins", "n": 1200}, {"t": "mod", "map": "electric", "key": "armor_pen", "n": 10}]},
	"eq07": {"name": "Metalfly Down", "tier": 2, "prereq": ["eq01"],
		"objective": "Defeat the Metalfly on Electric.",
		"reward": "1500 coins.",
		"trivia": "\"It sheds a cocoon and comes back angrier. Put it down for good.\"",
		"obj": {"type": "boss", "id": "metalfly"}, "rw": [{"t": "coins", "n": 1500}]},
	"eq08": {"name": "Untouchable", "tier": 2, "prereq": ["eq01"],
		"objective": "Reach 08:00 on Electric without taking a single point of damage.",
		"reward": "2000 coins. +15% i-frame duration on Electric.",
		"trivia": "\"Eight minutes, not a scratch. Prove the drone's worth its mass.\"",
		"obj": {"type": "no_hit", "t": 480.0},
		"rw": [{"t": "coins", "n": 2000}, {"t": "mod", "map": "electric", "key": "iframe_pct", "n": 15}]},
	"eq09": {"name": "Homecoming", "tier": 2, "prereq": ["eq01"],
		"objective": "Rescue the Constructor — break their ruin and survive to run end.",
		"reward": "1500 coins. +5% coin gain on Electric.",
		"trivia": "\"The Constructor's been stranded in that wreck a long time. Bring them in.\"",
		"obj": {"type": "rescue", "id": "constructor"},
		"rw": [{"t": "coins", "n": 1500}, {"t": "mod", "map": "electric", "key": "coin_pct", "n": 5}]},
	"eq10": {"name": "Double Feature", "tier": 3, "prereq": [],
		"objective": "In one Electric run: break both temples AND defeat the Metalfly.",
		"reward": "2000 coins. +1 permanent luck.",
		"trivia": "\"Both temples and the Metalfly. Same sortie. No excuses.\"",
		"obj": {"type": "all", "of": [{"type": "temples", "n": 2}, {"type": "boss", "id": "metalfly"}]},
		"rw": [{"t": "coins", "n": 2000}, {"t": "luck", "n": 1}]},
	"eq11": {"name": "The Long Dark", "tier": 3, "prereq": [],
		"objective": "Survive the full 30:00 and defeat the timeline's final boss.",
		"reward": "5000 coins.",
		"trivia": "\"Ride the whole timeline down and be standing when the last thing dies.\"",
		"obj": {"type": "all", "of": [{"type": "survive", "t": 1800.0}, {"type": "final_boss"}]},
		"rw": [{"t": "coins", "n": 5000}]},
	"eq12": {"name": "Apex Predator", "tier": 3, "prereq": [],
		"objective": "Finish a 30:00 Electric run with 3,000+ kills and zero revives spent.",
		"reward": "3000 coins. +3% XP gain everywhere.",
		"trivia": "\"Full run. Three thousand kills. One life. The record to beat.\"",
		"obj": {"type": "kills_no_revive", "kills": 3000, "t": 1800.0},
		"rw": [{"t": "coins", "n": 3000}, {"t": "xp_global", "n": 3}]},
}
const ORDER := ["eq01", "eq02", "eq03", "eq04", "eq05", "eq06", "eq07", "eq08", "eq09", "eq10", "eq11", "eq12"]

# ── Persistent ────────────────────────────────────────────────────────────────────────────
var _done: Array = []                    # completed quest ids
var _tracked: Array = []                 # quest ids the player is tracking (max 3) — for the in-run HUD later
var lifetime_kills: Dictionary = {}      # {map_id: {enemy_id: count}}
var map_mods: Dictionary = {}            # {map_id: {key: total}}  — recorded "+X% on <map>" reward effects
var luck_bonus: int = 0                  # recorded permanent luck from quests
var global_xp_pct: float = 0.0           # recorded permanent global XP % from quests

# ── Run-scoped (reset in begin_run) ───────────────────────────────────────────────────────
var _run_map: String = ""
var _run_faction_kills: Dictionary = {}  # {faction: count}
var _run_type_kills: Dictionary = {}     # {enemy_id: count}
var _run_temples: int = 0
var _run_bosses: Dictionary = {}         # {boss_id: true}
var _run_final_boss: bool = false
var _run_first_hit_time: float = -1.0    # run-seconds of the first damage taken (-1 = none yet)
var _run_burst_max: int = 0
var _burst_ring: Array = []              # kill timestamps (ms), trimmed to the last 3 s
var _run_revived: bool = false
var _run_active: bool = false

func _ready() -> void:
	load_quests()
	refresh_gates()
	if GameManager.has_signal("player_hit") and not GameManager.player_hit.is_connected(_on_player_hit):
		GameManager.player_hit.connect(_on_player_hit)
	if GameManager.has_signal("rebirth_used") and not GameManager.rebirth_used.is_connected(_on_rebirth_used):
		GameManager.rebirth_used.connect(_on_rebirth_used)

func _on_rebirth_used() -> void:
	_run_revived = true

# ── Query ─────────────────────────────────────────────────────────────────────────────────
func state_of(id: String) -> String:
	if id in _done:
		return "done"
	return String(_gate_state.get(id, "locked"))

func is_done(id: String) -> bool:      return id in _done
func is_available(id: String) -> bool: return state_of(id) == "available"
func is_tracked(id: String) -> bool:   return id in _tracked
func tracked_count() -> int:           return _tracked.size()

func toggle_tracked(id: String) -> bool:
	if id in _tracked:
		_tracked.erase(id)
	elif _tracked.size() >= 3:
		return false   # caller shows "Maximum 3 quest tracking allowed"
	elif is_available(id) or is_done(id):
		_tracked.append(id)
	else:
		return false
	save_quests()
	quest_changed.emit()
	return true

## Recorded "+X% <key> on <map>" total (0 if none). Arena gameplay wiring is a follow-up.
func map_mod(map_id: String, key: String) -> float:
	return float((map_mods.get(map_id, {}) as Dictionary).get(key, 0.0))

# ── Tier gating ───────────────────────────────────────────────────────────────────────────
var _gate_state: Dictionary = {}

func refresh_gates() -> void:
	var t1 := 0
	var t2 := 0
	for id: String in ORDER:
		if id in _done:
			var tier := int(QUESTS[id]["tier"])
			if tier == 1: t1 += 1
			elif tier == 2: t2 += 1
	_gate_state.clear()
	for id: String in ORDER:
		var q: Dictionary = QUESTS[id]
		var ok := true
		for p: String in q["prereq"]:
			if not (p in _done):
				ok = false
		if int(q["tier"]) == 2 and t1 < 2:
			ok = false
		if int(q["tier"]) == 3 and (t2 < 3 or not ("eq09" in _done)):
			ok = false
		_gate_state[id] = "available" if ok else "locked"

# ── Live tracking (called from arena_enemy._die + arena) ──────────────────────────────────
func begin_run(map_id: String) -> void:
	_run_map = map_id
	_run_active = true
	_run_faction_kills.clear()
	_run_type_kills.clear()
	_run_temples = 0
	_run_bosses.clear()
	_run_final_boss = false
	_run_first_hit_time = -1.0
	_run_burst_max = 0
	_burst_ring.clear()
	_run_revived = false

func on_enemy_killed(type_id: String, is_boss: bool, is_final: bool, drop_loot: String) -> void:
	if not _run_active:
		return
	_run_type_kills[type_id] = int(_run_type_kills.get(type_id, 0)) + 1
	if type_id in AINIMAL_IDS:
		_run_faction_kills["ainimal"] = int(_run_faction_kills.get("ainimal", 0)) + 1
	var lm: Dictionary = lifetime_kills.get(_run_map, {})
	lm[type_id] = int(lm.get(type_id, 0)) + 1
	lifetime_kills[_run_map] = lm
	# 3-second burst-kill peak
	var now := Time.get_ticks_msec()
	_burst_ring.append(now)
	while not _burst_ring.is_empty() and now - int(_burst_ring[0]) > 3000:
		_burst_ring.pop_front()
	_run_burst_max = maxi(_run_burst_max, _burst_ring.size())
	if drop_loot == "orb_of_light":
		_run_temples += 1
	if is_boss and "metalfly" in type_id:
		_run_bosses["metalfly"] = true
	if is_final:
		_run_final_boss = true

func _on_player_hit() -> void:
	if _run_active and _run_first_hit_time < 0.0:
		_run_first_hit_time = float(GameManager.run_time)

## Called from arena._show_run_over — evaluate every quest's objective, mark newly done + apply reward.
func end_run(map_id: String, _victory: bool) -> void:
	_run_active = false
	if map_id != "electric":
		return   # this pass ships the Electric board only
	var survived := float(GameManager.run_time)
	var kills := int(GameManager.run_kills)
	var any := false
	# Loop: completing a quest can unlock a higher tier whose objective was ALSO met this run.
	for _pass in 6:
		var progressed := false
		for id: String in ORDER:
			if id in _done or not is_available(id):
				continue
			if _obj_met(QUESTS[id]["obj"], survived, kills):
				_done.append(id)
				_apply_reward(QUESTS[id]["rw"])
				refresh_gates()
				progressed = true
				any = true
		if not progressed:
			break
	if any:
		save_quests()
		quest_changed.emit()

func _obj_met(spec: Dictionary, survived: float, kills: int) -> bool:
	match String(spec.get("type", "")):
		"run_end":
			return true
		"faction_run":
			return int(_run_faction_kills.get(String(spec["faction"]), 0)) >= int(spec["n"])
		"survive":
			return survived >= float(spec["t"])
		"temples":
			return _run_temples >= int(spec["n"])
		"burst":
			return _run_burst_max >= int(spec["n"])
		"type_lifetime":
			return int((lifetime_kills.get("electric", {}) as Dictionary).get(String(spec["id"]), 0)) >= int(spec["n"])
		"boss":
			return bool(_run_bosses.get(String(spec["id"]), false))
		"no_hit":
			return survived >= float(spec["t"]) and (_run_first_hit_time < 0.0 or _run_first_hit_time >= float(spec["t"]))
		"rescue":
			return bool(GameManager.run_rescue_collected) and String(GameManager.run_rescue_char_id) == String(spec["id"])
		"final_boss":
			return _run_final_boss
		"kills_no_revive":
			return survived >= float(spec["t"]) and kills >= int(spec["kills"]) and not _run_revived
		"all":
			for sub: Dictionary in spec["of"]:
				if not _obj_met(sub, survived, kills):
					return false
			return true
	return false

func _apply_reward(rw: Array) -> void:
	for r: Dictionary in rw:
		match String(r.get("t", "")):
			"coins":
				GameManager.add_money(int(r["n"]))
			"mod":
				var m: Dictionary = map_mods.get(String(r["map"]), {})
				m[String(r["key"])] = float(m.get(String(r["key"]), 0.0)) + float(r["n"])
				map_mods[String(r["map"])] = m
			"luck":
				luck_bonus += int(r["n"])
			"xp_global":
				global_xp_pct += float(r["n"])

# ── Persistence (own [quests] section of user://save.cfg) ─────────────────────────────────
func save_quests() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("quests", "done", _done)
	cfg.set_value("quests", "tracked", _tracked)
	cfg.set_value("quests", "lifetime_kills", lifetime_kills)
	cfg.set_value("quests", "map_mods", map_mods)
	cfg.set_value("quests", "luck_bonus", luck_bonus)
	cfg.set_value("quests", "global_xp_pct", global_xp_pct)
	cfg.save(SAVE_PATH)

func load_quests() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_done = cfg.get_value("quests", "done", [])
	_tracked = cfg.get_value("quests", "tracked", [])
	lifetime_kills = cfg.get_value("quests", "lifetime_kills", {})
	map_mods = cfg.get_value("quests", "map_mods", {})
	luck_bonus = int(cfg.get_value("quests", "luck_bonus", 0))
	global_xp_pct = float(cfg.get_value("quests", "global_xp_pct", 0.0))
