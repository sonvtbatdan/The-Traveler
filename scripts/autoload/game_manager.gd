extends Node

# ---------------------------------------------------------------------------
# Signals (existing — signatures and names locked)
# ---------------------------------------------------------------------------

signal game_loaded
signal boost_changed(active: bool)
signal ship_hp_changed(hp: int)
signal ship_energy_changed(energy: float)
signal ship_shield_changed(shield: float)
signal ship_destroyed
signal money_changed(amount: int)   # green-$ player currency

signal boss_hp_changed(hp: int)
signal boss_spawned
signal boss_killed
signal boss_defeated   # authoritative "boss HP reached zero" (victory) — NOT emitted on player death

var boss_hp:     int = 0
var boss_max_hp: int = 0
var boss_intro_active: bool = false   # true during the 1s boss/ship fly-in; freezes the boss + disables player input
var input_locked:      bool = false   # true during the boss death cutscene; freezes the boss + disables player input

func take_boss_damage(dmg: int) -> void:
	if boss_hp <= 0 or boss_max_hp <= 0:
		return
	boss_hp = maxi(0, boss_hp - dmg)
	boss_hp_changed.emit(boss_hp)
	if boss_hp <= 0:
		boss_max_hp = 0
		boss_killed.emit()      # cleanup (hides boss, clears projectiles)
		boss_defeated.emit()    # victory banner

var manual_boost: bool = false
var money: int = 0   # green-$ currency; new game starts at 0 (Phase 2 will spend/earn it)
var ship_hp: int = 100
const SHIP_MAX_HP: int = 100

# ── Shield (granted by an equipped Shield Generator in the Secondary slot) ─────
const SHIELD_REGEN_DELAY: float = 3.0   # seconds of no damage before regen starts
const SHIELD_REGEN_TIME:  float = 1.5   # seconds to refill 0 → capacity
var ship_shield:       float = 0.0      # current shield points
var _shield_max:       float = 0.0      # capacity of the equipped generator (0 = none equipped)
var _shield_dmg_timer: float = 999.0    # time since last damage; regen once >= SHIELD_REGEN_DELAY

# ── Invincibility frames ──────────────────────────────────────────────────────
const SHIP_IFRAME_TIME: float = 0.3     # invincibility window after a hit
var _iframe_timer: float = 0.0

# ── Energy (dash resource) ────────────────────────────────────────────────────
const SHIP_MAX_ENERGY: float = 100.0
const ENERGY_REGEN:    float = 5.0      # energy per second
var ship_energy: float = 100.0

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)
	save_game()

func set_boost(active: bool) -> void:
	if manual_boost == active:
		return
	manual_boost = active
	boost_changed.emit(active)

func ship_take_damage(dmg: int) -> void:
	if dmg <= 0 or ship_hp <= 0:
		return
	if _iframe_timer > 0.0:
		return   # still invincible from a recent hit
	_iframe_timer = SHIP_IFRAME_TIME
	# Shield absorbs first; leftover spills into HP the same hit.
	var d := float(dmg)
	if ship_shield > 0.0:
		var absorbed := minf(ship_shield, d)
		ship_shield -= absorbed
		d -= absorbed
		ship_shield_changed.emit(ship_shield)
	_shield_dmg_timer = 0.0   # any damage (even fully absorbed) restarts the regen delay
	if d <= 0.0:
		return
	ship_hp = maxi(0, ship_hp - int(ceil(d)))
	ship_hp_changed.emit(ship_hp)
	if ship_hp <= 0:
		ship_destroyed.emit()

## Spend energy for a dash; returns false (no spend) if there isn't enough.
func try_spend_energy(amount: float) -> bool:
	if ship_energy < amount:
		return false
	ship_energy -= amount
	ship_energy_changed.emit(ship_energy)
	return true

## Capacity granted by the Secondary-slot item (0 if it's not a shield item).
func _equipped_shield_capacity() -> float:
	var uid: int = InventoryManager.equipped_uid("secondary_weapon")
	if uid == -1:
		return 0.0
	var item: Dictionary = InventoryManager.get_item(uid)
	var def: Dictionary = InventoryManager.get_def(String(item.get("def", "")))
	return float(def.get("stats", {}).get("shield_points", 0.0))

## Per-frame: keep shield in sync with what's equipped, then regenerate.
func _tick_shield(delta: float) -> void:
	var cap := _equipped_shield_capacity()
	if cap != _shield_max:
		if cap > 0.0 and _shield_max <= 0.0:
			ship_shield = cap            # newly equipped → start at full shield
		_shield_max = cap
		ship_shield = clampf(ship_shield, 0.0, _shield_max)
		ship_shield_changed.emit(ship_shield)
	if _shield_max <= 0.0:
		return
	_shield_dmg_timer += delta
	if _shield_dmg_timer >= SHIELD_REGEN_DELAY and ship_shield < _shield_max:
		ship_shield = minf(_shield_max, ship_shield + (_shield_max / SHIELD_REGEN_TIME) * delta)
		ship_shield_changed.emit(ship_shield)

# ── Hit-stop (crit micro-freeze) ──────────────────────────────────────────────
# Safe, scoped freeze via Engine.time_scale (NOT pausing the SceneTree). Restored on
# a REAL-time deadline (immune to the scaling), so it always resumes and can't get
# stuck; overlapping crits just extend the deadline.
var _hitstop_until_ms: int = 0

func hit_stop(ms: float, scale: float = 0.0) -> void:
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(ms))
	Engine.time_scale = scale

func _process(delta: float) -> void:
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0
	_iframe_timer = maxf(0.0, _iframe_timer - delta)
	if ship_energy < SHIP_MAX_ENERGY:
		ship_energy = minf(SHIP_MAX_ENERGY, ship_energy + ENERGY_REGEN * delta)
		ship_energy_changed.emit(ship_energy)
	_tick_shield(delta)

# ---------------------------------------------------------------------------
# Format and helper stubs to maintain compatibility
# ---------------------------------------------------------------------------

func format_grouped_int(n: int) -> String:
	var sign_str: String = "-" if n < 0 else ""
	var s: String = str(absi(n))
	var result: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return sign_str + result

func format_views(n: int) -> String:
	return format_grouped_int(n)

func format_cash(f: float) -> String:
	return format_grouped_int(int(f))

func on_view_clicked() -> void:
	pass

func reset_stats() -> void:
	ship_hp = SHIP_MAX_HP
	ship_shield = 0.0
	ship_hp_changed.emit(ship_hp)
	ship_shield_changed.emit(ship_shield)
	MaterialManager.reset_all()
	save_game()

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

const SAVE_PATH := "user://save.cfg"

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("player", "ship_hp", ship_hp)
	cfg.set_value("player", "ship_shield", ship_shield)
	cfg.set_value("player", "money", money)
	cfg.save(SAVE_PATH)

func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var loaded_hp: int = cfg.get_value("player", "ship_hp", SHIP_MAX_HP)
	ship_hp = loaded_hp if loaded_hp > 0 else SHIP_MAX_HP   # recover from a dead-saved state
	ship_shield = cfg.get_value("player", "ship_shield", 0.0)
	money = cfg.get_value("player", "money", 0)
	ship_hp_changed.emit(ship_hp)
	ship_shield_changed.emit(ship_shield)
	money_changed.emit(money)
