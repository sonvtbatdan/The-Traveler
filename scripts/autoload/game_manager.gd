extends Node

# ---------------------------------------------------------------------------
# Signals (existing — signatures and names locked)
# ---------------------------------------------------------------------------

signal game_loaded
signal player_hit                  # fired whenever a hit actually lands (after iframe/shield checks)
signal boost_changed(active: bool)
signal ship_hp_changed(hp: int)
signal ship_energy_changed(energy: float)
signal ship_ammo_changed(ammo: float)
signal ship_shield_changed(shield: float)
signal ship_destroyed
signal mitigation_burst   # Exoskeleton Reactive evo: fired each time 500 mitigated damage accumulates
signal rebirth_used       # a revive charge was just spent (Backup Image is consumed on this)
signal money_changed(amount: int)   # green-$ player currency
signal kills_changed(kills: int)    # enemies killed this run (arena HUD counter)

# ── Character level / XP (Phases 1 & 2) ──────────────────────────────────────
signal xp_changed(xp: int, xp_to_next: int)   # current XP toward the next level + the threshold
signal level_changed(level: int)              # fired whenever the level number changes (load + level-ups)
signal leveled_up(new_level: int)             # fired once per individual level gained (for UI/effects)
signal player_stats_changed                   # arena-run upgrade stats changed (HUD/weapons may refresh)

signal boss_hp_changed(hp: int)
signal boss_incoming   # fires immediately when spawn is requested, before the warning delay
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

# ── Character level / XP — ALL pacing knobs live here (Phases 1 & 2) ──────────
# Diablo-2/Borderlands feel: quick early levels, a progressively longer late grind.
# Tune these freely by feel; everything else derives from them.
const BASE_XP: float = 100.0      # XP for level 1→2; the whole curve scales off this
const GROWTH:  float = 1.12       # each level costs GROWTH× the previous (early fast, late grind)
const MAX_LEVEL: int = 50         # level cap; XP stops accruing once reached
# Early-level XP-requirement discount (levels 1-6 cheaper; 7+ unchanged). Applied in xp_to_next().
const LEVEL_XP_MULT := {1: 0.39, 2: 0.52, 3: 0.65, 4: 0.91, 5: 1.04, 6: 0.90}   # levels 1–5 = old ×1.3 (+30% req)
const XP_PER_ASTEROID: float = 0.05       # flat XP per asteroid destroyed (1/20 of old 1; XP is face-value now)
const XP_ASTEROID_SIZE_DIV: float = 12.0  # + (width / this) / 20 → bigger rocks worth more
const XP_PER_BOSS: float = 25.0           # one lump on a boss's FINAL defeat (1/20 of old 500)
# NOTE: the old global XP_GAIN_SCALE (1/20) multiplier was removed — every XP source now carries its real,
# face-value amount (see ENEMY_DEFS in arena_wave_director.gd). add_xp still uses a fractional accumulator so
# sub-1 enemies (e.g. swarm at 0.2 XP) accumulate across kills instead of rounding to 0.

var player_level: int = 1   # starts at 1
var player_xp:    int = 0    # current XP toward the NEXT level (resets to 0 on each level-up)
var _xp_frac_acc: float = 0.0   # sub-1 XP carried between add_xp calls so fractional enemy XP isn't lost to rounding

# ── Debounced save (Vampire-Survivors-style XP smoothness) ─────────────────────
# add_xp used to call save_game() on EVERY pickup → a full ConfigFile load+save disk round-trip per XP orb.
# During a mass suck-in (magnet pulse / big pile) that was hundreds of synchronous disk writes in one frame,
# freezing the game. Now XP gains only mark the save DIRTY; the file is flushed on level-up (a milestone),
# every SAVE_FLUSH_INTERVAL seconds while dirty, and on quit — never per pickup.
const SAVE_FLUSH_INTERVAL := 5.0
var _save_dirty: bool = false
var _save_flush_acc: float = 0.0

## XP required to advance FROM `level` to the next: round(BASE_XP * GROWTH^(level-1)).
## Accelerating, so each level is a bigger step than the last.
func xp_to_next(level: int) -> int:
	var lvl_mult: float = LEVEL_XP_MULT.get(level, 1.0)   # early-level discount (Level_1 pacing)
	return maxi(1, int(round(BASE_XP * pow(GROWTH, float(level - 1)) * lvl_mult * (1.0 - upg_xp_req_reduction))))   # Data Harvester -req%

## XP a destroyed asteroid is worth, scaled by its visible width (px). Small rocks ~1, big ~5.
func xp_for_asteroid(width: float) -> float:
	return XP_PER_ASTEROID + (width / XP_ASTEROID_SIZE_DIV) / 20.0

## THE single entry point for gaining XP. Handles multiple level-ups from one big gain (e.g. a
## boss), caps at MAX_LEVEL, emits signals for UI/effects, and saves.
func add_xp(amount: float) -> void:
	if amount > 0.0:
		_pickup_buff_t = 5.0   # Magnet: collecting anything refreshes the 5s on-pickup buffs
	if amount <= 0.0 or player_level >= MAX_LEVEL:
		return
	# Data Harvester aux item scales XP gain. XP is face-value now (the old global 1/20 was removed and baked into
	# the per-enemy values). Accumulate as a float and only spend whole points, carrying the fractional remainder
	# so sub-1 enemies (e.g. swarm at 0.2 XP) still count over many kills instead of rounding to 0.
	_xp_frac_acc += amount * upg_xp_gain_mult
	var gain := int(_xp_frac_acc)
	_xp_frac_acc -= float(gain)
	if gain <= 0:
		return
	player_xp += gain
	var leveled := false
	while player_level < MAX_LEVEL and player_xp >= xp_to_next(player_level):
		player_xp -= xp_to_next(player_level)
		player_level += 1
		unspent_points += POINTS_PER_LEVEL   # each level grants points to spend on attributes
		leveled = true
		leveled_up.emit(player_level)
	if player_level >= MAX_LEVEL:
		player_xp = 0   # at cap there is no "next" bar to fill
	if leveled:
		level_changed.emit(player_level)
	xp_changed.emit(player_xp, xp_to_next(player_level))
	# Debounced save: level-ups flush immediately (milestone); plain XP gains just mark dirty so a mass
	# suck-in doesn't trigger a disk write per orb (see SAVE_FLUSH_INTERVAL / _process flush).
	if leveled:
		save_game()
	else:
		_save_dirty = true

# ── Character attributes (Phase 3) — ALL pacing knobs live here ───────────────
# Four attributes the player levels into. Each level grants POINTS_PER_LEVEL points (see add_xp).
# Tune every coefficient by feel; gameplay reads them only through the getters further down.
signal attributes_changed

const POINTS_PER_LEVEL: int = 5   # attribute points granted per level-up

# Marksmanship — weapon damage. +1% to ALL weapons per point; kinetic weapons get +1% MORE.
const MARKS_DMG_PER_PT: float = 0.01
const MARKS_KINETIC_BONUS_PER_PT: float = 0.01
# Engineering — ammo economy + energy-weapon damage.
const ENG_AMMO_PER_PT: float = 1.0
const ENG_AMMO_REGEN_PER_PT: float = 0.2
const ENG_ENERGY_DMG_PER_PT: float = 0.01
# Biotech — survivability + bio-weapon damage.
const BIO_HP_PER_PT: float = 1.0
const BIO_HP_REGEN_PER_PT: float = 0.2
const BIO_BIODMG_PER_PT: float = 0.01
# Maneuverability — energy pool + mobility + drone damage.
const MAN_ENERGY_PER_PT: float = 1.0
const MAN_ENERGY_REGEN_PER_PT: float = 0.2
const MAN_FLYSPEED_PER_PT: float = 0.01
const MAN_DRONE_DMG_PER_PT: float = 0.02   # NOTE: no drone-firing system yet — hook for the future

# Default minimum-attribute requirement to EQUIP an item, keyed by the item's rarity (tunable).
# common gear is freely equippable; rarer gear demands you spec into its attribute.
const REQ_BY_RARITY: Dictionary = {
	"common": 0, "uncommon": 4, "rare": 8, "very_rare": 14, "unique": 20, "legendary": 28,
}

const ATTRIBUTE_NAMES: Array[String] = ["marksmanship", "engineering", "biotech", "maneuverability"]

var attributes: Dictionary = {
	"marksmanship": 0, "engineering": 0, "biotech": 0, "maneuverability": 0,
}
var unspent_points: int = 0

## Current value of one attribute (0 for an unknown name).
func attr(attr_name: String) -> int:
	return int(attributes.get(attr_name, 0))

## Spend one unspent point into `attr_name`. Returns false if none left / bad name.
func spend_point(attr_name: String) -> bool:
	if unspent_points <= 0 or not attributes.has(attr_name):
		return false
	attributes[attr_name] = int(attributes[attr_name]) + 1
	unspent_points -= 1
	recompute_max_hp()   # Biotech changes max HP
	attributes_changed.emit()
	save_game()
	return true

## Refund every spent point back into the unspent pool (full respec — handy for balancing).
func reset_points() -> void:
	for n: String in ATTRIBUTE_NAMES:
		unspent_points += int(attributes[n])
		attributes[n] = 0
	recompute_max_hp()
	attributes_changed.emit()
	save_game()

## Total points the player has earned across all levels so far.
func total_points_earned() -> int:
	return (player_level - 1) * POINTS_PER_LEVEL

# ── Attribute-derived multipliers used by the weapon system ───────────────────

## Damage multiplier for a weapon def: universal Marksmanship bonus + a class-specific bonus.
## Weapon class is read from InventoryManager.weapon_class(def) and is unset for now, so only the
## universal Marksmanship term is active until weapons are classified.
func weapon_damage_mult(def: Dictionary) -> float:
	var m := 1.0 + MARKS_DMG_PER_PT * float(attr("marksmanship"))
	match InventoryManager.weapon_class(def):
		"kinetic":    m += MARKS_KINETIC_BONUS_PER_PT * float(attr("marksmanship"))
		"energy":     m += ENG_ENERGY_DMG_PER_PT * float(attr("engineering"))
		"biochemical": m += BIO_BIODMG_PER_PT * float(attr("biotech"))
	return m

## Drone-damage multiplier (Maneuverability). Hook only — no drone weapon fires yet.
func drone_damage_mult() -> float:
	return 1.0 + MAN_DRONE_DMG_PER_PT * float(attr("maneuverability"))

# ── Attribute-derived resource pools (Engineering / Maneuverability) ──────────
func max_ammo() -> float:
	return SHIP_MAX_AMMO + ENG_AMMO_PER_PT * float(attr("engineering"))
func ammo_regen_rate() -> float:
	return AMMO_REGEN + ENG_AMMO_REGEN_PER_PT * float(attr("engineering"))
func max_energy() -> float:
	return SHIP_MAX_ENERGY + MAN_ENERGY_PER_PT * float(attr("maneuverability"))

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

# ── Shield (base capacity always present; generators/affixes add on top) ─────
const BASE_SHIELD_MAX:    float = 50.0  # default shield capacity (always present, even with no generator)
const SHIELD_REGEN_DELAY: float = 20.0  # seconds of no damage before shield regen starts
const SHIELD_REGEN_RATE:  float = 1.0   # shield points regenerated per second (flat)
var ship_shield:       float = 0.0      # current shield points
var _shield_max:       float = 0.0      # capacity of the equipped generator (0 = none equipped)
var _shield_dmg_timer: float = 999.0    # time since last damage; regen once >= SHIELD_REGEN_DELAY
# Force Field aux item (arena): adds shield capacity + its own slow regen (after FORCE_SHIELD_DELAY of no damage).
const FORCE_SHIELD_DELAY := 10.0        # s of no damage before the Force Field starts regenerating
var upg_force_shield_max:   float = 0.0 # extra shield capacity from the Force Field aux (folds into the shield)
var upg_force_shield_regen: float = 0.0 # Force Field regen (shield/sec) once the delay has elapsed
# ── Force Field aux POOL + evolves ──
var upg_shield_mastery:     float = 0.0  # Shield Mastery: +% total shield capacity
var upg_force_shield_delay_red: float = 0.0 # seconds shaved off the Force Field regen delay
var upg_shield_disabled:    bool  = false # Energy to the Guns! evo: no shield at all
var upg_impervious:         bool  = false # Impervious evo: -20% damage while shield is up
var upg_void_shield:        bool  = false # Void Shield evo: ship contact damage = 10% of current shield
var upg_panic_rank:         int   = 0     # Panic Button: 0.5s i-frames/rank when shield breaks (60s CD)
var _panic_cd:              float = 0.0   # Panic Button cooldown timer
# Nanobots (regen aux) — regen modifiers. Mastery boosts HP+shield regen; WtL ×3 HP regen at low HP; the
# "attack!" evolution forces HP regen to 0; over-regen routes wasted HP regen into the shield when HP is full.
var upg_regen_mastery:    float = 0.0   # Regeneration Mastery (× applied to HP + shield regen)
var upg_regen_wtl_mult:   float = 1.0   # Will to Live (×3 HP regen below 30% HP, else 1.0)
var upg_regen_disabled:   bool  = false # Nanobots, attack!: HP regen forced to 0 (converted to automation dmg)
var _overregen_to_shield: bool  = false # over-regen → shield: refill shield with HP regen when HP is full

# ── Invincibility frames ──────────────────────────────────────────────────────
const SHIP_IFRAME_TIME: float = 0.3     # invincibility window after a hit
var _iframe_timer: float = 0.0

# ── Soft crowd push (Halls-of-Torment-style envelopment) ──────────────────────
# Enemies overlapping the ship each add a shove (arena_enemy._check_contact → add_player_push); the arena reads
# and clears the summed vector every physics frame (take_player_push) and adds it to the ship's velocity. Capped
# below the player's base speed so a dense mob slows you like a current — you can still crawl out, never trap-walled.
const PLAYER_PUSH_MAX: float = 260.0    # px/s cap on the summed crowd shove (player base move speed is 320)
var _player_push_accum: Vector2 = Vector2.ZERO

## An enemy contributes a shove on the ship (direction = away from that enemy, magnitude = strength × overlap).
func add_player_push(v: Vector2) -> void:
	_player_push_accum += v

## The arena consumes the accumulated crowd shove for this frame (capped) and resets it.
func take_player_push() -> Vector2:
	var p := _player_push_accum.limit_length(PLAYER_PUSH_MAX)
	_player_push_accum = Vector2.ZERO
	return p

# ── Loot shield immunity (from shield drop in arena) ─────────────────────────
var _shield_immune: bool = false
var _shield_timer: float = 0.0

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

## Credit Extractor: called by arena_loot when a coin is collected → refreshes the 5s on-coin buffs.
func on_coin_pickup() -> void:
	_coin_buff_t = 5.0

func can_afford(amount: int) -> bool:
	return money >= amount

## Spend `amount` coins if affordable. Returns true on success (money debited), false if too poor.
func spend_money(amount: int) -> bool:
	if amount < 0 or money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	save_game()
	return true

func set_boost(active: bool) -> void:
	if manual_boost == active:
		return
	manual_boost = active
	boost_changed.emit(active)

func ship_take_damage(dmg: int) -> void:
	if dmg <= 0 or ship_hp <= 0:
		return
	if _shield_immune:
		return
	if _iframe_timer > 0.0:
		return   # still invincible from a recent hit
	# Fins dodge — a POSITIVE chance, so Stroke of Luck (proc_luck) boosts it like every other positive chance.
	if upg_dodge > 0.0 and randf() < clampf(upg_dodge + mech_bonus("proc_luck"), 0.0, 0.95):
		return   # dodged: no damage, no iframe, Daredevil ramp NOT reset
	_iframe_timer = effective_iframe()   # post-hit invuln (× Fins iframe perk)
	# Daredevil takes MORE damage; the incoming hit is scaled first so mitigation/DR work off the real amount.
	var incoming := float(dmg) * upg_damage_taken_mult
	# % DR (Exoskeleton pre-armor DR + Fortress armor→DR) reduces incoming damage first, before the flat armor.
	var d := incoming * (1.0 - player_total_dr())
	# Flat arena armor (× Harden Mastery) subtracts AFTER the % DR — a separate flat layer.
	d = maxf(0.0, d - effective_base_defense())
	# Impervious evo: -20% damage while the shield is still up.
	if upg_impervious and ship_shield > 0.0:
		d *= 0.8
	# Reactive evo: every 500 damage stopped by DR + flat armor fires a shockwave (the arena listens + spawns it).
	if upg_mitigation_shockwave:
		_mitigation_acc += incoming - d
		while _mitigation_acc >= 500.0:
			_mitigation_acc -= 500.0
			mitigation_burst.emit()
	# Shield absorbs next; leftover spills into HP the same hit.
	if ship_shield > 0.0:
		var absorbed := minf(ship_shield, d)
		ship_shield -= absorbed
		d -= absorbed
		ship_shield_changed.emit(ship_shield)
		# Panic Button: the hit that DROPS the shield to 0 grants 0.5s i-frames/rank (60s cooldown).
		if ship_shield <= 0.0 and upg_panic_rank > 0 and _panic_cd <= 0.0:
			_iframe_timer = maxf(_iframe_timer, 0.5 * float(upg_panic_rank))
			_panic_cd = 60.0
	_shield_dmg_timer = 0.0   # any damage (even fully absorbed) restarts the regen delay
	if d <= 0.0:
		return
	_last_hp_dmg = d    # Barbed Wire reflect reads this in the player_hit handler
	player_hit.emit()   # only fires when actual HP damage goes through
	if upg_daredevil:   # Daredevil ramp resets the moment HP damage lands
		_daredevil_t = 0.0
		_daredevil_bonus = 0.0
	if upg_focus:       # Absolute Focus fire-rate ramp also resets on HP damage
		_focus_t = 0.0
		_focus_bonus = 0.0
	ship_hp = maxi(0, ship_hp - int(ceil(d)))
	ship_hp_changed.emit(ship_hp)
	if ship_hp <= 0:
		# Player died mid-fight: the boss never reached 0 HP, so take_boss_damage's own cleanup
		# never ran. Clear its state here so a fresh run doesn't inherit a stale "boss active"
		# flag (the boss HUD bar polls boss_hp/boss_max_hp directly and would otherwise reappear).
		boss_hp = 0
		boss_max_hp = 0
		boss_armor = 0.0
		boss_intro_active = false
		input_locked = false
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
	total += int(round(_stolen_armor_bonus))   # Parasite Stolen Fortitude (arena, set per-frame; 0 otherwise)
	return total

## Player damage-reduction fraction from total armor (player armor is ≥0). Uses the shared curve.
func damage_reduction() -> float:
	return armor_damage_reduction(float(total_armor()))

# ── Affix wiring ──────────────────────────────────────────────────────────────
# One helper sums an affix's rolled value across ALL equipped items; the getters below combine the
# base value (consts) with those affixes so gameplay AND the Character Sheet read one source of truth.
# Movement / dash base consts (formerly read from the now-removed gun_system.gd).
const SHIP_MOVE_SPD := 200.0   # px/s, base run speed
const DASH_CD       := 1.0     # dash cooldown (s)
const DASH_SPEED    := 840.0   # px/s during the dash lunge
const DASH_TIME     := 0.15    # dash duration (s)
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

# Movement / dash / model scale.
func effective_move_speed() -> float:
	# Maneuverability adds a flat %/pt fly-speed bonus on top of the gear affixes.
	var maneuver := 1.0 + MAN_FLYSPEED_PER_PT * float(attr("maneuverability"))
	var coin := (1.0 + upg_coin_haste) if _coin_buff_t > 0.0 else 1.0   # Credit Extractor on-coin speed boost
	return (SHIP_MOVE_SPD + sum_affix("faster_run_flat")) * (1.0 + sum_affix("faster_run_percentage") / 100.0) * maneuver * coin
func effective_dash_cd() -> float:
	return DASH_CD * clampf(1.0 - sum_affix("dash_cooldown_reduction") / 100.0, 0.1, 1.0)
func effective_dash_speed() -> float:
	return DASH_SPEED * (1.0 + sum_affix("dash_distance") / 100.0)
func effective_dash_range() -> float:
	return effective_dash_speed() * DASH_TIME
func model_scale_mult() -> float:
	return clampf(1.0 + (sum_affix("model_size_increase") + sum_affix("model_size_reduce")) / 100.0, 0.4, 2.0)

# Resource regen / shields / defenses.
func energy_regen_rate() -> float:
	# Maneuverability adds a flat energy/s on top of the gear affixes.
	return (ENERGY_REGEN + sum_affix("energy_regen_flat") + MAN_ENERGY_REGEN_PER_PT * float(attr("maneuverability"))) * (1.0 + sum_affix("energy_regen_percentage") / 100.0)
## HP regen (arena-only): the run store (Nanobots perks/level rewards) × Regeneration Mastery × Will-to-Live,
## or 0 when "Nanobots, attack!" has disabled it. Gear affixes / hull-innate / Biotech no longer contribute.
func hp_regen_rate() -> float:
	var base := 0.0 if upg_regen_disabled else upg_hp_regen
	var pickup := (upg_pickup_heal + (1.0 if upg_refuel else 0.0)) if _pickup_buff_t > 0.0 else 0.0   # Magnet on-pickup heal
	var coin := upg_coin_heal if _coin_buff_t > 0.0 else 0.0   # Credit Extractor on-coin heal
	return (base + _heat_syphon_regen + _chem_heal_regen + pickup + coin) * (1.0 + upg_regen_mastery) * upg_regen_wtl_mult
## Dragon's Breath Heat Syphon: regen from currently-burning enemies (set each frame by arena_weapons).
func set_heat_syphon(v: float) -> void:
	_heat_syphon_regen = v
## Chemtrail Healing Cloud: regen while standing in your own chemtrail (set each frame by arena_weapons).
func set_chem_heal(v: float) -> void:
	_chem_heal_regen = v
func shield_capacity_total() -> float:
	if upg_shield_disabled:
		return 0.0   # Energy to the Guns! — no shield
	return maxf(0.0, (BASE_SHIELD_MAX + _equipped_shield_capacity() + sum_affix("shield_flat") + upg_force_shield_max) * (1.0 + upg_shield_mastery))
func shield_regen_bonus() -> float:
	return sum_affix("shield_regen")   # flat shield/s added to the refill rate
func shield_delay() -> float:
	return SHIELD_REGEN_DELAY * clampf(1.0 - sum_affix("shield_delay_reduction") / 100.0, 0.1, 1.0)
## Flat arena armor AFTER Harden Mastery makes it more effective (the value subtracted post-% DR).
func effective_base_defense() -> float:
	return float(upg_base_defense) * (1.0 + upg_harden_mastery)
## Player % damage reduction (arena-only): Exoskeleton's pre-armor DR + the Fortress evo's armor→DR
## (+1% per 10 armor), capped at upg_dr_cap (Fortress lowers the cap to 0.75). Gear DR no longer contributes.
func player_total_dr() -> float:
	var dr := upg_pre_dr
	if upg_armor_to_dr:
		dr += effective_base_defense() * 0.001   # +1% DR per 10 armor
	return clampf(dr, 0.0, upg_dr_cap)
func effective_iframe() -> float:
	return SHIP_IFRAME_TIME * (1.0 + upg_iframe_mult)   # arena-only: Fins iframe perk

## Recompute gear-driven max HP: (BASE + hull bonus_hp[post-roll] + Σ hp_flat) × (1 + Σ hp_% / 100).
## Keeps current HP, clamping down if the new max is lower (no free heal on equip).
## Max HP (arena-only): the fixed base + the arena run store. Every arena HP source — Reinforcement Plate perks,
## its level rewards, Sacrificial Armor, the Mastery/Overall recompute — flows into upg_max_hp_bonus via
## add_max_hp(). The retired attribute system (Biotech) and gear hulls/HP affixes no longer contribute.
func recompute_max_hp() -> void:
	ship_max_hp = maxi(1, BASE_SHIP_HP + upg_max_hp_bonus)
	ship_hp = mini(ship_hp, ship_max_hp)
	ship_hp_changed.emit(ship_hp)

# ── Hull cross-interactions (Phase 5) ─────────────────────────────────────────────
## The equipped hull's def ({} if none). Cursed/Glass etc. carry stats.kind_bonus, max_hp_pct, luck_mult.
func _equipped_hull_def() -> Dictionary:
	var uid: int = InventoryManager.equipped_uid("hull")
	if uid == -1:
		return {}
	return InventoryManager.get_def(String(InventoryManager.get_item(uid).get("def", "")))

## Damage multiplier the equipped hull grants a weapon, from its kind_bonus matched against the weapon's
## damage_kind tags (e.g. Glass → +Light/+Energy, Cursed → +Fire/+Explosive). 1.0 when no hull / no match.
func hull_kind_mult(kinds: Array) -> float:
	var kb: Dictionary = _equipped_hull_def().get("stats", {}).get("kind_bonus", {})
	if kb.is_empty():
		return 1.0
	var bonus := 0.0
	for k in kinds:
		bonus += float(kb.get(String(k), 0.0))
	return 1.0 + bonus / 100.0

## Luck multiplier from the equipped hull (Cursed → <1 reduces crit + drop chance). 1.0 by default.
func hull_luck_mult() -> float:
	return float(_equipped_hull_def().get("stats", {}).get("luck_mult", 1.0))

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
func try_spend_ammo(_amount: float) -> bool:
	return true   # AMMO SYSTEM TEMPORARILY DISABLED — weapons fire freely. Re-enable by restoring the body below.
	# if ship_ammo < amount:
	# 	return false
	# ship_ammo -= amount
	# _ammo_regen_block = AMMO_REGEN_FIRE_BLOCK
	# ship_ammo_changed.emit(ship_ammo)
	# return true

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
	# Default: inventory generator's delay + (capacity / refill-time) rate. The Force Field aux overrides BOTH to
	# its spec (10s delay, +1 shield/sec per level) when present — in the arena it's the only shield source.
	var delay := shield_delay()
	var rate := SHIELD_REGEN_RATE + shield_regen_bonus()   # flat 1 shield/sec (+ any affix bonus)
	if upg_force_shield_max > 0.0:
		delay = maxf(0.5, FORCE_SHIELD_DELAY - upg_force_shield_delay_red)   # Force Field delay − pool reductions
		rate = upg_force_shield_regen
	rate *= (1.0 + upg_regen_mastery)   # Nanobots: Regeneration Mastery boosts shield regen too
	rate += upg_shield_regen_bonus      # Fusion Reactor evolve (flat shield/sec, always on)
	if _shield_dmg_timer >= delay and ship_shield < _shield_max:
		ship_shield = minf(_shield_max, ship_shield + rate * delta)
		ship_shield_changed.emit(ship_shield)
	# Magnet on-pickup shield regen — ignores the post-hit delay (a burst top-up while the buff is active).
	if _pickup_buff_t > 0.0 and ship_shield < _shield_max:
		var pu := upg_pickup_shield + (1.0 if upg_refuel else 0.0)
		if pu > 0.0:
			ship_shield = minf(_shield_max, ship_shield + pu * delta)
			ship_shield_changed.emit(ship_shield)
	# Credit Extractor on-coin shield regen — same idea.
	if _coin_buff_t > 0.0 and upg_coin_shield > 0.0 and ship_shield < _shield_max:
		ship_shield = minf(_shield_max, ship_shield + upg_coin_shield * delta)
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
	# Debounced save flush: write pending XP at most once per SAVE_FLUSH_INTERVAL (not per pickup).
	if _save_dirty:
		_save_flush_acc += delta
		if _save_flush_acc >= SAVE_FLUSH_INTERVAL:
			save_game()   # clears _save_dirty + resets the accumulator
	_iframe_timer = maxf(0.0, _iframe_timer - delta)
	if _panic_cd > 0.0:
		_panic_cd = maxf(0.0, _panic_cd - delta)   # Panic Button cooldown
	if _fervor_t > 0.0:
		_fervor_t = maxf(0.0, _fervor_t - delta)   # Fervor stacks decay together after 5s
		if _fervor_t <= 0.0:
			_fervor_stacks = 0
	if _pickup_buff_t > 0.0:
		_pickup_buff_t = maxf(0.0, _pickup_buff_t - delta)   # Magnet on-pickup buffs (5s)
	if _coin_buff_t > 0.0:
		_coin_buff_t = maxf(0.0, _coin_buff_t - delta)       # Credit Extractor on-coin buffs (5s)
	# Magnet "pick up everything" pulse: every (10 − rank) min, vacuum all XP orbs to the player.
	if upg_magnet_pulse_rank > 0:
		_magnet_pulse_cd = maxf(0.0, _magnet_pulse_cd - delta)
		if _magnet_pulse_cd <= 0.0:
			_magnet_pulse_cd = float(10 - upg_magnet_pulse_rank) * 60.0
			var mgr := get_tree().get_first_node_in_group("arena_xp_orb_mgr")
			var pl := get_tree().get_first_node_in_group("player")
			if mgr != null and pl != null and mgr.has_method("magnetize_all_within"):
				mgr.call("magnetize_all_within", (pl as Node2D).global_position, 100000.0)
	var energy_cap := max_energy()
	if ship_energy < energy_cap:
		ship_energy = minf(energy_cap, ship_energy + energy_regen_rate() * delta)
		ship_energy_changed.emit(ship_energy)
	# HP regen — accumulate fractional HP, heal whole points. When HP is full, the Nanobots over-regen perk routes
	# the otherwise-wasted regen into the shield (continuously, ignoring the shield's own damage delay).
	if ship_hp > 0 and ship_hp < ship_max_hp:
		_hp_regen_acc += hp_regen_rate() * delta
		if _hp_regen_acc >= 1.0:
			var heal := int(_hp_regen_acc)
			_hp_regen_acc -= float(heal)
			ship_hp = mini(ship_max_hp, ship_hp + heal)
			ship_hp_changed.emit(ship_hp)
	elif ship_hp > 0 and _overregen_to_shield:
		var scap := shield_capacity_total()
		if ship_shield < scap:
			ship_shield = minf(scap, ship_shield + hp_regen_rate() * delta)
			ship_shield_changed.emit(ship_shield)
	# Ammo regen — paused for a moment after any weapon fires/spends (see note_weapon_firing/try_spend_ammo).
	_ammo_regen_block = maxf(0.0, _ammo_regen_block - delta)
	var ammo_cap := max_ammo()
	if _ammo_regen_block <= 0.0 and ship_ammo < ammo_cap:
		ship_ammo = minf(ammo_cap, ship_ammo + ammo_regen_rate() * delta)
		ship_ammo_changed.emit(ship_ammo)
	_tick_shield(delta)
	# Daredevil evo: +1% damage every 3s without taking HP damage, up to +100% (reset in ship_take_damage).
	if upg_daredevil and ship_hp > 0:
		_daredevil_t += delta
		while _daredevil_t >= 3.0:
			_daredevil_t -= 3.0
			_daredevil_bonus = minf(1.0, _daredevil_bonus + 0.01)
	# Absolute Focus evo: +1% fire rate every 5s without taking HP damage, up to +60% (300s) (reset on damage).
	if upg_focus and ship_hp > 0:
		_focus_t += delta
		while _focus_t >= 5.0:
			_focus_t -= 5.0
			_focus_bonus = minf(0.60, _focus_bonus + 0.01)
	if _shield_timer > 0.0:
		_shield_timer -= delta
		if _shield_timer <= 0.0:
			_shield_immune = false

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

## Refresh max HP from current gear/attributes, then top the ship off to full. Used on load so every
## session starts at full health.
func heal_to_full() -> void:
	recompute_max_hp()
	ship_hp = ship_max_hp
	ship_hp_changed.emit(ship_hp)

# ── ARENA RUN STATS (Vampire-Survivors upgrade store) ────────────────────────────
# In-memory per-run modifiers picked from the level-up cards. All default to a no-op, so at base values the
# game plays exactly as before. Folded into the existing HP/regen/DR paths (not a parallel system).
const PICKUP_RADIUS_BASE: float = 117.0   # base XP-orb magnet radius (px) before % upgrades (90 base +30%)
var upg_max_hp_bonus:   int   = 0         # flat +max HP (into recompute_max_hp)
var upg_base_defense:   int   = 0         # flat armor: subtracted after the % DR (× Harden Mastery)
var upg_hp_regen:       float = 0.0       # flat HP/sec (into hp_regen_rate)
var upg_shield_regen_bonus: float = 0.0   # flat shield/sec from the Mortar's Fusion Reactor evolve
var _stolen_armor_bonus:    float = 0.0   # Parasite Stolen Fortitude: bonus armor (set per-frame by arena_weapons)
# Exoskeleton (armor aux) — % DR layers + the three evolutions. All no-ops at base.
var upg_pre_dr:         float = 0.0       # pre-armor-mitigation % damage reduction (Exoskeleton)
var upg_harden_mastery: float = 0.0       # Harden Mastery: flat armor is this much MORE effective (×)
var upg_armor_to_dr:    bool  = false     # Fortress evo: +1% DR per 10 armor (into player_total_dr)
var upg_dr_cap:         float = 0.95      # max combined % DR from all sources (Fortress evo → 0.75)
var upg_mitigation_shockwave: bool = false # Reactive evo: every 500 mitigated dmg → a shockwave (signal)
var upg_ship_size_mult: float = 1.0       # ship drawn + hitbox × this (Juggernaut ×2 nerf; Fins shrinks it)
var _mitigation_acc:    float = 0.0       # running mitigated-damage accumulator for the Reactive shockwave
# Fins (speed aux) — dodge, iframe, speed-mastery, and the three evolutions. All no-ops at base.
var upg_dodge:          float = 0.0       # chance (0..0.95) to fully avoid a hit
var upg_iframe_mult:    float = 0.0       # post-hit invuln duration × (1 + this)
var upg_speed_mastery:  float = 0.0       # fraction of the MS BONUS also added to weapon (projectile/minion) speed
var upg_damage_taken_mult: float = 1.0    # Daredevil evo: >1 = take more damage
var upg_ms_to_firerate: bool  = false     # Momentum evo: 100% of MS bonus also adds to global fire rate
var upg_daredevil:      bool  = false     # Daredevil evo: damage ramps while undamaged
var _daredevil_t:       float = 0.0       # seconds since last damage (Daredevil ramp timer)
var _daredevil_bonus:   float = 0.0       # current Daredevil damage bonus (0..1.0), reset on taking damage
var upg_focus:          bool  = false     # Auto-Loader Absolute Focus evo: fire-rate ramps while undamaged
var _focus_t:           float = 0.0       # seconds since last damage (Absolute Focus timer)
var _focus_bonus:       float = 0.0       # current Absolute Focus fire-rate bonus (0..0.60), reset on damage
var contact_dmg_base:   float = 0.0       # ship contact damage (Orbital pool grants it; base 0). × Contact Mastery
var _heat_syphon_regen: float = 0.0       # Dragon's Breath Heat Syphon: HP/s from currently-burning enemies
var _chem_heal_regen:   float = 0.0       # Chemtrail Healing Cloud: HP/s while standing in your own chemtrail
var upg_fire_rate_mult: float = 1.0       # weapon fire-rate ×
var upg_move_speed_mult: float = 1.0      # move-speed ×
var upg_damage_mult:    float = 1.0       # weapon-damage ×
var upg_momentum_mult:  float = 1.0       # knockback (+ future weapon scaling) ×
var upg_pickup_mult:    float = 1.0       # pickup-radius ×
# ── Magnet aux POOL + evolves ──
var upg_pickup_heal:    float = 0.0       # HP/s regen granted for 5s after a pickup (0.1/rank)
var upg_pickup_shield:  float = 0.0       # shield/s regen granted for 5s after a pickup (0.1/rank)
var upg_pickup_dmg:     float = 0.0       # +damage granted for 5s after a pickup (0.01/rank)
var upg_refuel:         bool  = false     # Next Gen Refueling evo: pickup grants +1 HP/+1 shield regen/+10% dmg
var _pickup_buff_t:     float = 0.0       # >0 → the on-pickup buffs are active (refreshed each pickup)
var upg_magnet_pulse_rank: int = 0        # "pick up everything" pulse: cd = (10 − rank) min
var _magnet_pulse_cd:   float = 0.0       # pulse cooldown timer
# ── Data Harvester aux POOL + evolves ──
var upg_xp_req_reduction: float = 0.0     # -% XP needed per level (in xp_to_next)
var upg_applied_learning: bool  = false   # Applied Learning evo: +0.2% damage per player level
var upg_harvester_off:    bool  = false   # Unlearn evo: Data Harvester's level-up procs disabled
var upg_crit_chance:    float = 0.0       # crit probability 0..1 (0 = no crits → non-destructive at base)
var upg_crit_damage:    float = 1.5       # crit damage multiplier (a crit deals damage × this)
# Aim Assistor "Challenge Accepted" evo: each crit grants a Fervor stack (+5% dmg, 5s, max 5).
var upg_fervor:         bool  = false
var _fervor_stacks:     int   = 0
var _fervor_t:          float = 0.0
# Auxiliary-item run stats (arena_aux.gd). Base values are no-ops; aux items stack onto them per level.
var upg_xp_gain_mult:    float = 1.0      # Data Harvester: XP gained × (applied in add_xp)
var upg_spawn_rate_mult: float = 1.0      # Beacon: enemy spawn cadence/cap × (read by arena_wave_director)
var upg_retaliation:     float = 0.0      # Barbed Wire: flat damage dealt back to nearby enemies when hit
var upg_blood_thirsty:   bool  = false    # Barbed Wire evo: heal 5% of contact damage dealt
var _last_hp_dmg:        float = 0.0       # HP damage from the most recent hit (Barbed Wire reflect reads it)
# Per-weapon-group and per-damage-kind run multipliers — populated by the group-scoped level-up cards
# (Phase 4). Empty = every group/kind at ×1.0 (no-op at base). The shared firing engines read these via
# group_damage_mult() / kind_damage_mult() so a "boost the energy group" card lifts every energy weapon.
var upg_group_dmg: Dictionary = {}        # group name → extra multiplier added to 1.0 (e.g. {"energy": 0.25})
var upg_kind_dmg:  Dictionary = {}        # damage_kind → extra multiplier added to 1.0 (e.g. {"fire": 0.4})
var upg_mech:      Dictionary = {}        # mechanic key → flat bonus (chain_jumps/ricochet/pierce/splash_radius/radius/…)

## Flat run bonus for a firing-mechanic key (chain_jumps, ricochet, ricochet_range, pierce, splash_radius,
## radius). 0 when no card has boosted it. The arena firing engine adds this onto the weapon's base stat.
func mech_bonus(key: String) -> float:
	return float(upg_mech.get(key, 0.0))

func add_group_dmg(group: String, amt: float) -> void:
	upg_group_dmg[group] = float(upg_group_dmg.get(group, 0.0)) + amt
	player_stats_changed.emit()

func add_kind_dmg(kind: String, amt: float) -> void:
	upg_kind_dmg[kind] = float(upg_kind_dmg.get(kind, 0.0)) + amt
	player_stats_changed.emit()

func add_mech(key: String, amt: float) -> void:
	upg_mech[key] = float(upg_mech.get(key, 0.0)) + amt
	player_stats_changed.emit()
# Permanent-passive run state (set by MetaManager.apply_run_start each run; reset_run clears to base).
var rebirth_charges: int = 0              # Phoenix Core: revive-on-death charges available THIS run
var run_coin_mult:   float = 1.0          # Scavenger: multiplies in-run coin pickups (arena_loot reads this)
# ── Credit Extractor aux POOL + evolves ──
var upg_coin_drop:   float = 0.0          # coin-drop weight (0 = no CE; base 1.0 on acquire, ×1.05/magic-find rank)
var upg_coin_heal:   float = 0.0          # HP/s regen for 5s after a COIN pickup (0.1/rank)
var upg_coin_shield: float = 0.0          # shield/s regen for 5s after a coin pickup
var upg_coin_haste:  float = 0.0          # +speed & +fire-rate for 5s after a coin pickup (0.05/rank)
var _coin_buff_t:    float = 0.0          # >0 → the on-coin buffs are active

## Credit Extractor coin value: pick from [1,2,5,10,25,50], heavily skewed to the low end; `hp` (enemy Max HP)
## and `skew` (Higher Yield rank fraction) raise how far right the roll can reach. Returns the coin's value.
func roll_coin_value(hp: float, skew: float) -> int:
	const VALS := [1, 2, 5, 10, 25, 50]
	var reach := clampf(log(maxf(hp, 1.0)) / 11.0 + skew, 0.0, 1.0)   # 0 (tiny foe) → 1 (huge foe / maxed skew)
	var t := randf()
	var idx := int(floor(pow(t, 6.0 - 5.0 * reach) * float(VALS.size())))   # pow>1 crushes toward index 0
	return VALS[clampi(idx, 0, VALS.size() - 1)]
var run_luck:        float = 0.0          # Lucky drone: additive luck this run (drop/fragment/coin chance)
var run_kills:       int   = 0            # enemies killed this run (arena HUD; reset each run)

## Tally one enemy kill for the run (arena HUD counter). Called from arena_enemy._die().
func add_kill() -> void:
	run_kills += 1
	kills_changed.emit(run_kills)

## Grant `n` one-run revive charges (Phoenix Core passive). Consumed by the arena on ship death.
func grant_rebirth(n: int) -> void:
	rebirth_charges = maxi(rebirth_charges, n)

## Try to spend a revive charge: heals to half HP and returns true, or false if none left.
func try_rebirth() -> bool:
	if rebirth_charges <= 0:
		return false
	rebirth_charges -= 1
	ship_hp = maxi(1, int(ship_max_hp / 2))   # revive at 50% HP
	ship_hp_changed.emit(ship_hp)
	_iframe_timer = maxf(_iframe_timer, 3.0)   # Backup Image: 3s of invulnerability on revive
	rebirth_used.emit()                        # Backup Image is consumed
	return true

## Run damage multiplier for a weapon group ("ballistic"/"energy"/…). 1.0 when no card boosts it.
func group_damage_mult(group: String) -> float:
	return 1.0 + float(upg_group_dmg.get(group, 0.0))

## Run damage multiplier across a weapon's damage_kind tags (fire/light/kinetic/…). Stacks additively.
func kind_damage_mult(kinds: Array) -> float:
	var bonus := 0.0
	for k in kinds:
		bonus += float(upg_kind_dmg.get(String(k), 0.0))
	return 1.0 + bonus

func get_move_speed_mult() -> float: return upg_move_speed_mult
func get_damage_mult() -> float:     return upg_damage_mult + _daredevil_bonus + 0.05 * float(_fervor_stacks) + ((upg_pickup_dmg + (0.10 if upg_refuel else 0.0)) if _pickup_buff_t > 0.0 else 0.0) + (0.002 * float(player_level) if upg_applied_learning else 0.0)   # + Applied Learning
## Challenge Accepted: a crit adds a Fervor stack (+5% dmg, refreshed 5s, cap 5). No-op unless the evo is taken.
func add_fervor() -> void:
	if not upg_fervor:
		return
	_fervor_stacks = mini(5, _fervor_stacks + 1)
	_fervor_t = 5.0
func get_fire_rate_mult() -> float:
	# Momentum evo: 100% of the move-speed BONUS is also added; Absolute Focus adds its ramped bonus.
	return upg_fire_rate_mult + (maxf(0.0, upg_move_speed_mult - 1.0) if upg_ms_to_firerate else 0.0) + _focus_bonus + (upg_coin_haste if _coin_buff_t > 0.0 else 0.0)   # + Credit Extractor on-coin haste
func set_focus(on: bool) -> void: upg_focus = on; player_stats_changed.emit()
## Fins Speed Mastery: a fraction of the MS bonus that also speeds up weapons (projectile/minion travel speed).
func weapon_speed_bonus() -> float:
	return maxf(0.0, upg_move_speed_mult - 1.0) * upg_speed_mastery
## Ship contact damage dealt to enemies that touch the hull — base × Contact Mastery (global). 0 at base.
func ship_contact_damage() -> float:
	var base := contact_dmg_base
	if upg_void_shield:
		base += 0.10 * ship_shield   # Void Shield evo: contact damage = 10% of current shield
	return base * (1.0 + mech_bonus("contact_dmg_mult"))
func add_contact_damage(n: float) -> void: contact_dmg_base += n; player_stats_changed.emit()
func get_momentum_mult() -> float:   return upg_momentum_mult
func get_base_defense() -> int:      return upg_base_defense
func get_pickup_radius() -> float:   return PICKUP_RADIUS_BASE * upg_pickup_mult
func get_crit_chance() -> float:     return clampf(upg_crit_chance, 0.0, 1.0)
func get_crit_damage() -> float:     return upg_crit_damage

func add_max_hp(n: int) -> void:
	upg_max_hp_bonus += n
	recompute_max_hp()
	ship_hp = mini(ship_max_hp, ship_hp + n)   # the HP card also heals
	ship_hp_changed.emit(ship_hp)
	player_stats_changed.emit()
func add_base_defense(n: int) -> void:  upg_base_defense += n;        player_stats_changed.emit()
# ── Exoskeleton (armor aux) setters ──
func add_pre_dr(p: float) -> void:        upg_pre_dr += p;             player_stats_changed.emit()
func add_harden_mastery(p: float) -> void: upg_harden_mastery += p;    player_stats_changed.emit()
func set_armor_to_dr(on: bool) -> void:   upg_armor_to_dr = on;        player_stats_changed.emit()
func set_dr_cap(c: float) -> void:        upg_dr_cap = c;             player_stats_changed.emit()
func set_mitigation_shockwave(on: bool) -> void: upg_mitigation_shockwave = on
func mul_ship_size(f: float) -> void:     upg_ship_size_mult *= f;     player_stats_changed.emit()   # Juggernaut ×2 / Fins shrink
# ── Fins (speed aux) setters ──
func add_dodge(p: float) -> void:         upg_dodge = clampf(upg_dodge + p, 0.0, 0.95); player_stats_changed.emit()
func add_iframe_mult(p: float) -> void:   upg_iframe_mult += p;        player_stats_changed.emit()
func add_speed_mastery(p: float) -> void: upg_speed_mastery += p;      player_stats_changed.emit()
func set_damage_taken_mult(m: float) -> void: upg_damage_taken_mult = m; player_stats_changed.emit()
func set_ms_to_firerate(on: bool) -> void: upg_ms_to_firerate = on;    player_stats_changed.emit()
func set_daredevil(on: bool) -> void:     upg_daredevil = on;          player_stats_changed.emit()
func add_fire_rate(p: float) -> void:   upg_fire_rate_mult += p;      player_stats_changed.emit()
func add_move_speed(p: float) -> void:  upg_move_speed_mult += p;     player_stats_changed.emit()
func add_damage(p: float) -> void:      upg_damage_mult += p;         player_stats_changed.emit()
func add_momentum(p: float) -> void:    upg_momentum_mult += p;       player_stats_changed.emit()
func add_hp_regen(f: float) -> void:    upg_hp_regen += f;            player_stats_changed.emit()
func add_shield_regen(f: float) -> void: upg_shield_regen_bonus += f;  player_stats_changed.emit()
func set_stolen_armor(f: float) -> void: _stolen_armor_bonus = maxf(0.0, f)   # per-frame; no signal (hot path)
func add_pickup_radius(p: float) -> void: upg_pickup_mult += p;       player_stats_changed.emit()
func add_crit_chance(p: float) -> void: upg_crit_chance += p;         player_stats_changed.emit()
func add_crit_damage(p: float) -> void: upg_crit_damage += p;         player_stats_changed.emit()
# ── Auxiliary-item setters (additive stacking) ──
func add_xp_gain(p: float) -> void:     upg_xp_gain_mult += p;        player_stats_changed.emit()
func add_spawn_rate(p: float) -> void:  upg_spawn_rate_mult += p;     player_stats_changed.emit()
func add_retaliation(f: float) -> void: upg_retaliation += f;         player_stats_changed.emit()
func add_coin_mult(p: float) -> void:   run_coin_mult += p;           player_stats_changed.emit()
func add_force_shield(max_add: float, regen_add: float) -> void:
	upg_force_shield_max += max_add
	upg_force_shield_regen += regen_add
	player_stats_changed.emit()
# ── Nanobots (regen aux) regen modifiers ──
func add_regen_mastery(amt: float) -> void:   upg_regen_mastery += amt;  player_stats_changed.emit()
func set_regen_wtl_mult(mult: float) -> void:
	if not is_equal_approx(upg_regen_wtl_mult, mult):
		upg_regen_wtl_mult = mult
		player_stats_changed.emit()
func set_overregen_to_shield(on: bool) -> void: _overregen_to_shield = on
func disable_hp_regen() -> void:                upg_regen_disabled = true;  player_stats_changed.emit()
func add_rebirth(n: int) -> void:       rebirth_charges += n;         player_stats_changed.emit()

## Heal the player by `amount` HP, capped at max HP. Safe to call from loot drops.
func heal(amount: int) -> void:
	if ship_hp <= 0:
		return
	ship_hp = mini(ship_max_hp, ship_hp + amount)
	ship_hp_changed.emit(ship_hp)

## Grant full damage immunity for `duration` seconds (from loot shield drop).
func activate_shield(duration: float) -> void:
	_shield_immune = true
	_shield_timer = duration

## Start a fresh arena run: reset level/XP + all upgrade modifiers, restore full HP. Called from arena._ready
## (flag RESET_RUN_ON_START) so each survival run is a clean Vampire-Survivors climb from level 1.
func reset_run() -> void:
	player_level = 1
	player_xp = 0
	_shield_immune = false
	_shield_timer = 0.0
	upg_max_hp_bonus = 0
	upg_base_defense = 0
	upg_pre_dr = 0.0
	upg_harden_mastery = 0.0
	upg_armor_to_dr = false
	upg_dr_cap = 0.95
	upg_mitigation_shockwave = false
	upg_ship_size_mult = 1.0
	_mitigation_acc = 0.0
	upg_dodge = 0.0
	upg_iframe_mult = 0.0
	upg_speed_mastery = 0.0
	upg_damage_taken_mult = 1.0
	upg_ms_to_firerate = false
	upg_daredevil = false
	_daredevil_t = 0.0
	_daredevil_bonus = 0.0
	contact_dmg_base = 0.0
	upg_shield_mastery = 0.0
	upg_force_shield_delay_red = 0.0
	upg_shield_disabled = false
	upg_impervious = false
	upg_void_shield = false
	upg_panic_rank = 0
	_panic_cd = 0.0
	_heat_syphon_regen = 0.0
	_chem_heal_regen = 0.0
	upg_focus = false
	_focus_t = 0.0
	_focus_bonus = 0.0
	upg_hp_regen = 0.0
	upg_shield_regen_bonus = 0.0
	_stolen_armor_bonus = 0.0
	upg_fire_rate_mult = 1.0
	upg_move_speed_mult = 1.0
	upg_damage_mult = 1.0
	upg_momentum_mult = 1.0
	upg_pickup_mult = 1.0
	upg_pickup_heal = 0.0
	upg_pickup_shield = 0.0
	upg_pickup_dmg = 0.0
	upg_refuel = false
	_pickup_buff_t = 0.0
	upg_magnet_pulse_rank = 0
	_magnet_pulse_cd = 0.0
	upg_xp_req_reduction = 0.0
	upg_applied_learning = false
	upg_harvester_off = false
	upg_crit_chance = 0.0
	upg_crit_damage = 1.5
	upg_fervor = false
	_fervor_stacks = 0
	_fervor_t = 0.0
	upg_xp_gain_mult = 1.0
	upg_spawn_rate_mult = 1.0
	upg_retaliation = 0.0
	upg_blood_thirsty = false
	_last_hp_dmg = 0.0
	upg_force_shield_max = 0.0
	upg_force_shield_regen = 0.0
	upg_regen_mastery = 0.0
	upg_regen_wtl_mult = 1.0
	upg_regen_disabled = false
	_overregen_to_shield = false
	upg_group_dmg = {}
	upg_kind_dmg = {}
	upg_mech = {}
	rebirth_charges = 0
	run_coin_mult = 1.0
	upg_coin_drop = 0.0
	upg_coin_heal = 0.0
	upg_coin_shield = 0.0
	upg_coin_haste = 0.0
	_coin_buff_t = 0.0
	run_luck = 0.0
	run_kills = 0
	recompute_max_hp()
	heal_to_full()
	# Shield: init straight to full cap (mirrors heal_to_full for HP), don't rely on _tick_shield's
	# lazy self-heal — the start-of-run weapon chest pauses the tree (arena_weapon_chest_ui.show_chest)
	# on the very first deferred call, before GameManager._process ever runs once, so that lazy path
	# would leave ship_shield stuck at 0 (and the shield VFX invisible) for the whole time the chest is up.
	_shield_max = shield_capacity_total()
	ship_shield = _shield_max
	ship_shield_changed.emit(ship_shield)
	level_changed.emit(player_level)
	xp_changed.emit(player_xp, xp_to_next(player_level))
	kills_changed.emit(run_kills)
	player_stats_changed.emit()

func reset_stats() -> void:
	recompute_max_hp()
	ship_hp = ship_max_hp
	ship_shield = 0.0
	ship_hp_changed.emit(ship_hp)
	ship_shield_changed.emit(ship_shield)
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
	cfg.set_value("player", "level", player_level)
	cfg.set_value("player", "xp", player_xp)
	for n: String in ATTRIBUTE_NAMES:
		cfg.set_value("player", "attr_" + n, int(attributes[n]))
	cfg.set_value("player", "unspent_points", unspent_points)
	cfg.save(SAVE_PATH)
	_save_dirty = false
	_save_flush_acc = 0.0

## Flush a pending debounced save to disk if XP (or anything) marked it dirty. Cheap no-op when clean.
func flush_save() -> void:
	if _save_dirty:
		save_game()

## Autoload receives window-close + tree-exit; flush any pending XP so quitting never loses progress.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		flush_save()

func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var loaded_hp: int = cfg.get_value("player", "ship_hp", ship_max_hp)
	ship_hp = loaded_hp if loaded_hp > 0 else ship_max_hp   # recover from a dead-saved state
	ship_shield = cfg.get_value("player", "ship_shield", 0.0)
	money = cfg.get_value("player", "money", 0)
	player_level = clampi(int(cfg.get_value("player", "level", 1)), 1, MAX_LEVEL)
	player_xp = maxi(0, int(cfg.get_value("player", "xp", 0)))
	# Attributes + unspent points.
	var spent := 0
	for n: String in ATTRIBUTE_NAMES:
		attributes[n] = maxi(0, int(cfg.get_value("player", "attr_" + n, 0)))
		spent += int(attributes[n])
	unspent_points = maxi(0, int(cfg.get_value("player", "unspent_points", 0)))
	# Migration: an already-leveled save from before this system has no points stored — grant the
	# difference so leveling is never silently lost. (No effect once everything is saved properly.)
	var earned := total_points_earned()
	if spent + unspent_points < earned:
		unspent_points += earned - (spent + unspent_points)
	ship_hp_changed.emit(ship_hp)
	ship_shield_changed.emit(ship_shield)
	money_changed.emit(money)
	level_changed.emit(player_level)
	xp_changed.emit(player_xp, xp_to_next(player_level))
	attributes_changed.emit()
	recompute_max_hp()
