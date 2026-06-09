extends Node

# ---------------------------------------------------------------------------
# Signals (existing — signatures and names locked)
# ---------------------------------------------------------------------------

signal game_loaded
signal boost_changed(active: bool)
signal ship_hp_changed(hp: int)
signal ship_energy_changed(energy: float)
signal ship_ammo_changed(ammo: float)
signal ship_shield_changed(shield: float)
signal ship_destroyed
signal money_changed(amount: int)   # green-$ player currency

signal boss_hp_changed(hp: int)
signal boss_spawned
signal boss_killed
signal boss_defeated   # authoritative "boss HP reached zero" (victory) — NOT emitted on player death

var boss_hp:     int = 0
var boss_max_hp: int = 0
var boss_armor:  float = 0.0   # enemy armor for the active boss (0 = none). A boss can set this in
							   # its spawn_boss(); the acid cloud shreds it toward negative. Reset on death.
var boss_intro_active: bool = false   # true during the 1s boss/ship fly-in; freezes the boss + disables player input
var input_locked:      bool = false   # true during the boss death cutscene; freezes the boss + disables player input

func take_boss_damage(dmg: int) -> void:
	if boss_hp <= 0 or boss_max_hp <= 0:
		return
	# Enemy armor reduces (or, if shredded negative, amplifies) ALL damage the boss takes.
	dmg = int(round(float(dmg) * (1.0 - armor_damage_reduction(boss_armor))))
	if dmg <= 0:
		return
	boss_hp = maxi(0, boss_hp - dmg)
	boss_hp_changed.emit(boss_hp)
	if boss_hp <= 0:
		boss_max_hp = 0
		boss_armor = 0.0        # clear armor so it never carries over to the next fight
		boss_killed.emit()      # cleanup (hides boss, clears projectiles)
		boss_defeated.emit()    # victory banner

## True while a boss fight is underway (used to lock equipment changes mid-battle).
func is_in_battle() -> bool:
	return boss_max_hp > 0 and boss_hp > 0

var manual_boost: bool = false
var money: int = 0   # green-$ currency; new game starts at 0 (Phase 2 will spend/earn it)
var ship_hp: int = 100
# Max HP is now gear-driven: BASE_SHIP_HP + equipped hull's (post-roll) bonus_hp + HP affixes.
# `ship_max_hp` is recomputed by recompute_max_hp() whenever equipment changes.
const BASE_SHIP_HP: int = 100
var ship_max_hp: int = 100

# ── Armor → damage reduction (shared by the player AND enemies) ───────────────
# DR = ARMOR_DR_COEFF * armor / (1 + ARMOR_DR_COEFF * armor). Diminishing returns, never 100%.
# Sanity: 200 armor → 50% DR, 1000 → ~83%. THIS is the knob to reshape the curve.
# NEGATIVE armor → negative DR → damage is AMPLIFIED (enemies only, via acid shred). The negative
# pole is at armor = -1/ARMOR_DR_COEFF (= -200), where the denominator hits 0 — guarded + clamped.
const ARMOR_DR_COEFF: float = 0.005
const ENEMY_ARMOR_DR_MIN: float = -2.0   # most-negative DR → caps amplification at ×3 damage (tunable)

## DR fraction for any armor value. Positive → reduction (capped 0.95); negative → amplification
## (capped at ENEMY_ARMOR_DR_MIN, can't divide-by-zero). Damage multiplier = (1.0 - this).
func armor_damage_reduction(armor: float) -> float:
	var denom := 1.0 + ARMOR_DR_COEFF * armor
	if denom <= 0.0:
		return ENEMY_ARMOR_DR_MIN   # armor at/below the pole (-200) → max amplification
	return clampf(ARMOR_DR_COEFF * armor / denom, ENEMY_ARMOR_DR_MIN, 0.95)

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

# ── Ammo (weapon resource) ────────────────────────────────────────────────────
# Regenerates AMMO_REGEN/s, but ONLY while no weapon is firing — every successful
# ammo spend or weapon fire refreshes a short block timer that pauses the regen.
const SHIP_MAX_AMMO: float = 100.0           # tunable; can be raised/lowered later
const AMMO_REGEN:    float = 5.0             # ammo per second (when not firing)
const AMMO_REGEN_FIRE_BLOCK: float = 0.1     # regen stays paused this long after the last fire/spend
var ship_ammo: float = 100.0
var _ammo_regen_block: float = 0.0

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
	_iframe_timer = effective_iframe()   # post-hit invuln, lengthened by damage_immunity_duration affix
	# Armor (+ damage_reduction affix) reduces ALL incoming damage first, before shield.
	var d := float(dmg) * (1.0 - player_total_dr())
	# Shield absorbs next; leftover spills into HP the same hit.
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

# ── Armor / max HP (gear-driven) ──────────────────────────────────────────────

## Total armor = every equipped item's post-roll base armor (hulls only) PLUS any `armor` affix
## bonuses across ALL equipped slots. Mirrors how weapon damage reads base (×roll) + affixes.
func total_armor() -> int:
	var total := 0
	for slot: String in InventoryManager.EQUIP_SLOTS:
		var uid: int = InventoryManager.equipped_uid(slot)
		if uid == -1:
			continue
		total += InventoryManager.hull_armor(uid)   # post-roll base armor; 0 for non-hull items
		for a: Dictionary in InventoryManager.item_affixes(uid):
			if String(a.get("id", "")) == "armor":
				total += int(round(float(a.get("value", 0.0))))
	return total

## Player damage-reduction fraction from total armor (player armor is ≥0). Uses the shared curve.
func damage_reduction() -> float:
	return armor_damage_reduction(float(total_armor()))

# ── Affix wiring ──────────────────────────────────────────────────────────────
# One helper sums an affix's rolled value across ALL equipped items; the getters below combine the
# base value (consts) with those affixes so gameplay AND the Character Sheet read one source of truth.
const GunSys := preload("res://scripts/gameplay/gun_system.gd")   # movement/dash/scale base consts
var _hp_regen_acc: float = 0.0

## Sum an affix's rolled value across every equipped item (weapons + hulls). Mirrors total_armor().
func sum_affix(id: String) -> float:
	var total := 0.0
	for slot: String in InventoryManager.EQUIP_SLOTS:
		var uid: int = InventoryManager.equipped_uid(slot)
		if uid == -1:
			continue
		for a: Dictionary in InventoryManager.item_affixes(uid):
			if String(a.get("id", "")) == id:
				total += float(a.get("value", 0.0))
	return total

# Movement / dash / model scale (base consts live in gun_system.gd).
func effective_move_speed() -> float:
	return (GunSys.SHIP_MOVE_SPD + sum_affix("faster_run_flat")) * (1.0 + sum_affix("faster_run_percentage") / 100.0)
func effective_dash_cd() -> float:
	return GunSys.DASH_CD * clampf(1.0 - sum_affix("dash_cooldown_reduction") / 100.0, 0.1, 1.0)
func effective_dash_speed() -> float:
	return GunSys.DASH_SPEED * (1.0 + sum_affix("dash_distance") / 100.0)
func effective_dash_range() -> float:
	return effective_dash_speed() * GunSys.DASH_TIME
func model_scale_mult() -> float:
	return clampf(1.0 + (sum_affix("model_size_increase") + sum_affix("model_size_reduce")) / 100.0, 0.4, 2.0)

# Resource regen / shields / defenses.
func energy_regen_rate() -> float:
	return (ENERGY_REGEN + sum_affix("energy_regen_flat")) * (1.0 + sum_affix("energy_regen_percentage") / 100.0)
func hp_regen_rate() -> float:
	var r := sum_affix("hp_regen")
	var uid: int = InventoryManager.equipped_uid("hull")   # + Nanobot-style hull innate hp_regen
	if uid != -1:
		var def: Dictionary = InventoryManager.get_def(String(InventoryManager.get_item(uid).get("def", "")))
		r += float(def.get("stats", {}).get("hp_regen", 0.0))
	return r
func shield_capacity_total() -> float:
	return _equipped_shield_capacity() + sum_affix("shield_flat")
func shield_regen_bonus() -> float:
	return sum_affix("shield_regen")   # flat shield/s added to the refill rate
func shield_delay() -> float:
	return SHIELD_REGEN_DELAY * clampf(1.0 - sum_affix("shield_delay_reduction") / 100.0, 0.1, 1.0)
func player_total_dr() -> float:
	return clampf(damage_reduction() + sum_affix("damage_reduction") / 100.0, 0.0, 0.95)
func effective_iframe() -> float:
	return SHIP_IFRAME_TIME * (1.0 + sum_affix("damage_immunity_duration") / 100.0)

## Recompute gear-driven max HP: (BASE + hull bonus_hp[post-roll] + Σ hp_flat) × (1 + Σ hp_% / 100).
## Keeps current HP, clamping down if the new max is lower (no free heal on equip).
func recompute_max_hp() -> void:
	var flat := 0.0
	var pct := 0.0
	var hull_bonus := 0
	for slot: String in InventoryManager.EQUIP_SLOTS:
		var uid: int = InventoryManager.equipped_uid(slot)
		if uid == -1:
			continue
		hull_bonus += InventoryManager.hull_bonus_hp(uid)   # post-roll; 0 for non-hull items
		for a: Dictionary in InventoryManager.item_affixes(uid):
			match String(a.get("id", "")):
				"hp_flat": flat += float(a.get("value", 0.0))
				"hp_percentage": pct += float(a.get("value", 0.0))
	ship_max_hp = maxi(1, int(round((float(BASE_SHIP_HP) + float(hull_bonus) + flat) * (1.0 + pct / 100.0))))
	ship_hp = mini(ship_hp, ship_max_hp)
	ship_hp_changed.emit(ship_hp)

func _on_equipment_changed(_slot: String, _uid: int) -> void:
	recompute_max_hp()

## Spend energy for a dash; returns false (no spend) if there isn't enough.
func try_spend_energy(amount: float) -> bool:
	if ship_energy < amount:
		return false
	ship_energy -= amount
	ship_energy_changed.emit(ship_energy)
	return true

## Spend ammo; returns false (no spend) if there isn't enough. A successful spend pauses ammo regen.
func try_spend_ammo(amount: float) -> bool:
	if ship_ammo < amount:
		return false
	ship_ammo -= amount
	_ammo_regen_block = AMMO_REGEN_FIRE_BLOCK
	ship_ammo_changed.emit(ship_ammo)
	return true

## Called by weapon_system whenever any weapon actually fires/sustains, to pause ammo regen.
func note_weapon_firing() -> void:
	_ammo_regen_block = AMMO_REGEN_FIRE_BLOCK

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
	var cap := shield_capacity_total()   # generator + shield_flat affix (so a hull can grant a shield)
	if cap != _shield_max:
		if cap > 0.0 and _shield_max <= 0.0:
			ship_shield = cap            # newly equipped → start at full shield
		_shield_max = cap
		ship_shield = clampf(ship_shield, 0.0, _shield_max)
		ship_shield_changed.emit(ship_shield)
	if _shield_max <= 0.0:
		return
	_shield_dmg_timer += delta
	if _shield_dmg_timer >= shield_delay() and ship_shield < _shield_max:
		var rate := (_shield_max / SHIELD_REGEN_TIME) + shield_regen_bonus()   # base + shield_regen affix
		ship_shield = minf(_shield_max, ship_shield + rate * delta)
		ship_shield_changed.emit(ship_shield)

# ── Hit-stop (crit micro-freeze) ──────────────────────────────────────────────
# Safe, scoped freeze via Engine.time_scale (NOT pausing the SceneTree). Restored on
# a REAL-time deadline (immune to the scaling), so it always resumes and can't get
# stuck; overlapping crits just extend the deadline.
var _hitstop_until_ms: int = 0

func hit_stop(ms: float, scale: float = 0.0) -> void:
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(ms))
	Engine.time_scale = scale

func _ready() -> void:
	# InventoryManager autoloads AFTER GameManager, so defer the hookup to the first idle frame.
	call_deferred("_init_equipment_stats")

func _init_equipment_stats() -> void:
	InventoryManager.item_equipped.connect(_on_equipment_changed)
	InventoryManager.item_unequipped.connect(_on_equipment_changed)
	recompute_max_hp()

func _process(delta: float) -> void:
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0
	_iframe_timer = maxf(0.0, _iframe_timer - delta)
	if ship_energy < SHIP_MAX_ENERGY:
		ship_energy = minf(SHIP_MAX_ENERGY, ship_energy + energy_regen_rate() * delta)
		ship_energy_changed.emit(ship_energy)
	# HP regen (hp_regen affix + hull innate) — accumulate fractional HP, heal whole points.
	if ship_hp > 0 and ship_hp < ship_max_hp:
		_hp_regen_acc += hp_regen_rate() * delta
		if _hp_regen_acc >= 1.0:
			var heal := int(_hp_regen_acc)
			_hp_regen_acc -= float(heal)
			ship_hp = mini(ship_max_hp, ship_hp + heal)
			ship_hp_changed.emit(ship_hp)
	# Ammo regen — paused for a moment after any weapon fires/spends (see note_weapon_firing/try_spend_ammo).
	_ammo_regen_block = maxf(0.0, _ammo_regen_block - delta)
	if _ammo_regen_block <= 0.0 and ship_ammo < SHIP_MAX_AMMO:
		ship_ammo = minf(SHIP_MAX_AMMO, ship_ammo + AMMO_REGEN * delta)
		ship_ammo_changed.emit(ship_ammo)
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
	recompute_max_hp()
	ship_hp = ship_max_hp
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
	var loaded_hp: int = cfg.get_value("player", "ship_hp", ship_max_hp)
	ship_hp = loaded_hp if loaded_hp > 0 else ship_max_hp   # recover from a dead-saved state
	ship_shield = cfg.get_value("player", "ship_shield", 0.0)
	money = cfg.get_value("player", "money", 0)
	ship_hp_changed.emit(ship_hp)
	ship_shield_changed.emit(ship_shield)
	money_changed.emit(money)
