extends RefCounted
## Shared "compose a wave that hits a target total HP" generator — static only, no scene-tree or UI
## dependency, so the SAME code runs in both places that need it:
##   • F7's "Generate Base on HP" button (`arena_wave_editor.gd`, authoring-time, one row at a time), and
##   • the runtime milestone generator (`arena_wave_director_v2.gd`), which re-rolls every authored HP
##     milestone fresh at the start of each run and trickles it out across the 5s grid.
## Extracted 2026-08-24 so the ±HP_TOLERANCE rule and the ranged-creep ceiling can't drift between the two.
##
## Everything here is pure: callers resolve their own pools (which enemy ids / fleets belong to the current
## map, what each one's HP is) and pass them in, because "which creeps are eligible" is the one part that
## genuinely differs — the editor filters by the map tab being authored, the director by the map being played.

## Every behavior in arena_enemy.gd's `_tick_behavior()` that actually spawns a projectile, plus
## "gauss_shooter" (ranged bolted onto a "chase" behavior — pros5) and any explicit Creep Info "shoot"
## override (the composed move/shoot system). Contact-only/melee creeps — the vast majority of the roster —
## are false.
##
## 2026-08-25 bug fix (user report: "playtest đến phút 6:45 có tới 9 animalhornet và 16 sentinel (các
## sentinel này cũng bắn đạn), vậy là vi phạm rule rồi"). This list was hand-written and had drifted from
## the code: an audit of every `case` in `_tick_behavior()` for calls to spawn_bullet / throw_bomb /
## _beamer_tick / the missile volley found SIX firing behaviors, not four. The two missing ones:
##   • "sentinel"    — fires a 5-bullet fan at the player every 2s (arena_enemy.gd's own case comment says
##                     so outright). This is the one that broke the report above: the `sentinel` def sits
##                     inside the Kingdom1/Kingdom2 FLEETS, and because it read as melee, fleet_shoot_count()
##                     returned 0 for those formations, so _drain_fleet_queue's ranged ceiling waved every
##                     Kingdom deployment straight through. NOTE: sentinel1-4/sentinelleader are behavior
##                     "patrol" and genuinely do NOT fire (they only have `strike_back` = turn and chase when
##                     hit) — only the plain "sentinel" id is ranged.
##   • "steer_kiter" — spawn_mode_2's own test_kiter roster entry; fires while kiting.
## Keep this in sync by re-running that audit whenever a behavior gains or loses a projectile.
const SHOOT_BEHAVIORS := ["shooter", "beamer", "bomber", "missile", "sentinel", "steer_kiter"]

const HP_TOLERANCE := 0.10            # the ±band around `target` generate() aims for
const CLOSE_ENOUGH := 0.02            # stop adding slots once the remainder is within this fraction of target
const PER_SLOT_HP_BUDGET := 12000.0   # cheap fry can swarm high, pricey types stay small (per-slot count cap)
const PER_SLOT_MIN := 5
const PER_SLOT_MAX := 500
const FLEET_PICK_CHANCE := 0.35       # odds of drawing from the fleet pool when both pools are available
const FLEET_COPIES_MAX := 20          # sane ceiling on how many copies of one formation a single slot deploys
const PICK_TRIES := 6                 # random candidates drawn per slot before settling (see _pick_index)

static func is_shoot_def(d: Dictionary) -> bool:
	if String(d.get("behavior", "")) in SHOOT_BEHAVIORS:
		return true
	if bool(d.get("gauss_shooter", false)):
		return true
	if d.has("shoot") and String(d.get("shoot", "none")) != "none":
		return true
	return false

## True for a def that must NEVER be picked by an AUTOMATIC spawn path — the F7 "Gen" candidate pool, the
## runtime HP-milestone generator, the low-population reinforcement pool, and Elite/Champion promotion.
## Deliberately does NOT block the deliberate manual paths: an explicitly authored timeline row, Fleet Edit
## membership, and arena_debug_spawn's Quick Spawn all still spawn whatever they name, on purpose.
##
## 2026-08-25, on request: "dummy ko bao giờ được tự động Gen (trong wave editor) và spawn trên arena, vì
## đây là creep test." Data-driven rather than an `id == "dummy"` check hardcoded across five call sites, so
## any future test/target creep just gets the same flag. `invincible` is treated as an implicit opt-out on
## its own: a creep that cannot be killed can never be cleared, so auto-spawning one would wedge the field
## (and the alive-cap) forever — dummy carries both.
static func is_auto_excluded(d: Dictionary) -> bool:
	if d.is_empty():
		return true
	if bool(d.get("no_auto", false)) or bool(d.get("invincible", false)):
		return true
	if String(d.get("behavior", "")) == "boss_stub" or bool(d.get("gate_waves", false)):
		return true
	return false

## { enemy id -> true } for every ranged type in `defs`. Built once by a caller that has to classify live
## enemies by id repeatedly (the director's concurrent-shooter gate) rather than re-reading each def.
static func shoot_type_ids(defs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in defs.keys():
		if is_shoot_def(defs[id]):
			out[String(id)] = true
	return out

## The enemy ids one Fleet Edit formation deploys (flattened across its slots). `fleets` is the raw array
## from res://fleet_layout.cfg — both callers already load it for their own reasons.
static func fleet_unit_ids(fleets: Array, fleet_name: String) -> Array:
	for fl in fleets:
		var f: Dictionary = fl
		if String(f.get("name", "")) != fleet_name:
			continue
		var ids: Array = []
		for s: Dictionary in (f.get("slots", []) as Array):
			for en in (s.get("enemies", []) as Array):
				var id := String(en)
				if id != "":
					ids.append(id)
		return ids
	return []

## MUST match arena_enemy.gd's own const — the ×2 HP every non-"boss_stub" enemy gets in configure().
const ENEMY_HP_TUNE := 2.0

## One creep's HP **as it appears on the live field** — `hp` × any `blob` count × ENEMY_HP_TUNE. This is
## exactly what a spawned creep's `hp_max` is and what the perf overlay's "Total HP" readout sums, so a
## milestone `hp_targets` value composed against this = the number you actually see in that window.
## (2026-09-01, user report: F7 said 5000 for the first 30s but the live readout showed 11.4k — the ×2
## tune wasn't folded in, and low-count catch-up was flooding the field on top; catch-up is now off
## whenever hp_targets is set — see arena_wave_director_v2._tick_low_count_watch.)
## Does NOT count `death_spawn` / `magma_split` — those become their OWN live creeps when they spawn and are
## summed then; they just mean a stone/magma window ramps ABOVE its target as the player fights through it.
## Still no "lvl"/Beacon (player-state, unknowable at authoring time — and `lvl` is off the Volcanic roster).
## `with_blob` — false inside a fleet (rigid dock spawns one creep per slot, ignoring the type's own blob).
static func effective_hp(id: String, defs: Dictionary, with_blob: bool = true) -> float:
	var d: Dictionary = defs.get(id, {})
	if d.is_empty():
		return 0.0
	var hp := float(d.get("hp", 0.0)) * ENEMY_HP_TUNE
	if with_blob:
		hp *= float(maxi(1, int(d.get("blob", 1))))
	return hp

## Combined live-field HP of one whole formation — see effective_hp(). No `blob` expansion (fleet slots
## spawn one creep each). Still no player-state multipliers.
static func fleet_hp(fleets: Array, fleet_name: String, defs: Dictionary) -> float:
	var total := 0.0
	for id: String in fleet_unit_ids(fleets, fleet_name):
		total += effective_hp(id, defs, false)
	return total

## How many ranged units ONE deployment of this formation puts on the field — so a caller enforcing a
## shooter ceiling can budget for fleets, which deploy rigidly and cannot be thinned afterwards.
static func fleet_shoot_count(fleets: Array, fleet_name: String, defs: Dictionary) -> int:
	var n := 0
	for id: String in fleet_unit_ids(fleets, fleet_name):
		if is_shoot_def(defs.get(id, {})):
			n += 1
	return n

## Compose a wave whose combined HP lands within HP_TOLERANCE of `target`, as an Array of at most
## `slot_max` slot dictionaries: {type, count, pattern, is_boss, duration}. "type" is either an enemy id or
## "fleet:<name>". Returns [] for target <= 0 or empty pools.
##
## `unit_pool`  — [{id: String, hp: float, shoot: bool}]   (hp already folds in a "blob" def's own multiplier)
## `fleet_pool` — [{name: String, hp: float, shoot: int}]  (shoot = ranged units per single deployment)
## `patterns`   — spawn formations to pick from at random
## `shoot_cap_per_type` — max ranged units of ONE id in this wave (<= 0 = unlimited)
## `shoot_cap_total`    — max ranged units of ALL ids combined in this wave (<= 0 = unlimited)
##
## Two ceilings rather than one because the callers want different things: the F7 button keeps its original
## per-id ceiling (10 shooters AND 10 beamers in one wave is a deliberate authoring option), while the
## director enforces a hard TOTAL matching its own concurrent-shooter gate, so it never queues up more
## ranged creeps than the field will ever admit at once.
static func generate(target: float, unit_pool: Array, fleet_pool: Array, patterns: Array,
		slot_max: int, shoot_cap_per_type: int, shoot_cap_total: int) -> Array:
	var out: Array = []
	if target <= 0.0 or (unit_pool.is_empty() and fleet_pool.is_empty()) or patterns.is_empty():
		return out

	var achieved := 0.0
	var shoot_used: Dictionary = {}   # id -> ranged units of that id already placed (per-type ceiling)
	var shoot_total := 0              # ranged units of ANY id already placed (total ceiling)
	var iterations := 0
	# Phase 1 — greedy fill: each pick is sized to roughly absorb whatever is left of the target, until the
	# slots run out or the remainder is small enough for Phase 2 to close exactly. The retry budget stops an
	# all-maxed-out-shoot-type pool spinning forever without ever consuming a slot (see the `continue`s).
	while out.size() < slot_max and iterations < slot_max * 4:
		iterations += 1
		var remaining := target - achieved
		if remaining <= target * CLOSE_ENOUGH:
			break
		# How much HP this slot should ideally carry if the rest are to divide the remainder evenly. Used to
		# steer the draw below — see _pick_index.
		var need := remaining / float(maxi(1, slot_max - out.size()))
		var use_fleet := not fleet_pool.is_empty() and (unit_pool.is_empty() or randf() < FLEET_PICK_CHANCE)
		if use_fleet:
			var f: Dictionary = fleet_pool[_pick_index(fleet_pool, remaining, need, float(FLEET_COPIES_MAX))]
			var fhp := float(f["hp"])
			if fhp <= 0.0:
				continue
			var n := clampi(int(round(remaining / fhp)), 1, FLEET_COPIES_MAX)
			var f_shoot := int(f.get("shoot", 0))
			if f_shoot > 0 and shoot_cap_total > 0:
				# A formation deploys rigidly (arena_wave_director_v2._deploy_fleet builds its units
				# directly, bypassing the per-spawn gate), so its ranged units must be budgeted HERE —
				# there is no later chance to hold one back without orphaning the rest of the dock.
				var room: int = (shoot_cap_total - shoot_total) / f_shoot
				if room <= 0:
					continue   # no room for even one copy — retry with a different pick, don't burn a slot
				n = mini(n, room)
			shoot_total += n * f_shoot
			achieved += fhp * float(n)
			out.append({"type": "fleet:" + String(f["name"]), "count": n, "pattern": "ring",
					"is_boss": false, "duration": 0.0})
		else:
			var u: Dictionary = unit_pool[_pick_index(unit_pool, remaining, need, 0.0)]
			var uhp := float(u["hp"])
			if uhp <= 0.0:
				continue
			var uid := String(u["id"])
			var u_shoot := bool(u.get("shoot", false))
			var cap := clampi(int(round(PER_SLOT_HP_BUDGET / uhp)), PER_SLOT_MIN, PER_SLOT_MAX)
			if u_shoot:
				# A swarm of ranged attackers is a far bigger threat than the same HP total in melee
				# creeps, so ranged types get a hard unit ceiling on top of the HP-derived one.
				if shoot_cap_per_type > 0:
					cap = mini(cap, shoot_cap_per_type - int(shoot_used.get(uid, 0)))
				if shoot_cap_total > 0:
					cap = mini(cap, shoot_cap_total - shoot_total)
				if cap <= 0:
					continue   # this type (or the whole wave) is already at its ranged ceiling
			var count := clampi(int(round(remaining / uhp)), 1, cap)
			if u_shoot:
				shoot_used[uid] = int(shoot_used.get(uid, 0)) + count
				shoot_total += count
			achieved += uhp * float(count)
			out.append({"type": uid, "count": count, "pattern": String(patterns[randi() % patterns.size()]),
					"is_boss": false, "duration": 0.0})

	# Phase 2 — fine-tune: re-solve the LAST slot's count so the total lands as close to `target` as that
	# slot's own ceilings allow, instead of keeping whatever Phase 1's rounding happened to produce.
	if not out.is_empty():
		var last: Dictionary = out[out.size() - 1]
		var lt := String(last["type"])
		var lcount := int(last["count"])
		var lhp := 0.0
		var l_shoot_each := 0
		if lt.begins_with("fleet:"):
			for f2: Dictionary in fleet_pool:
				if "fleet:" + String(f2["name"]) == lt:
					lhp = float(f2["hp"])
					l_shoot_each = int(f2.get("shoot", 0))
					break
		else:
			for u2: Dictionary in unit_pool:
				if String(u2["id"]) == lt:
					lhp = float(u2["hp"])
					l_shoot_each = 1 if bool(u2.get("shoot", false)) else 0
					break
		if lhp > 0.0:
			var others := achieved - lhp * float(lcount)
			var new_count: int = maxi(1, int(round((target - others) / lhp)))
			if lt.begins_with("fleet:"):
				new_count = mini(new_count, FLEET_COPIES_MAX)
			if l_shoot_each > 0:
				# Re-derive the ceiling with THIS slot's own contribution taken back out first (shoot_used /
				# shoot_total still include the Phase-1 count we are about to replace).
				var placed_here := lcount * l_shoot_each
				var room := 1000000
				if shoot_cap_per_type > 0 and not lt.begins_with("fleet:"):
					room = mini(room, shoot_cap_per_type - (int(shoot_used.get(lt, 0)) - placed_here))
				if shoot_cap_total > 0:
					room = mini(room, shoot_cap_total - (shoot_total - placed_here))
				new_count = clampi(new_count, 1, maxi(1, room / l_shoot_each))
			last["count"] = new_count
	return out

## Draw a pool entry for one slot. A plain uniform pick (what this was until 2026-08-24) leaves the result
## at the mercy of the draw: a run of cheap 20-HP fry cannot reach a 300k target inside `slot_max` slots
## capped at PER_SLOT_MAX each, and a single formation far pricier than the remainder overshoots it wildly.
## Measured over 400 random targets against a realistic roster, that missed the ±HP_TOLERANCE band on ~8% of
## waves, by as much as 71% (and 285% on a fleet-only pool).
##
## So: draw up to PICK_TRIES candidates at random and keep the FIRST one that both (a) fits — one unit of it
## doesn't already blow past what's left — and (b) can carry its share of the remainder at its own per-slot
## ceiling. Taking the first acceptable draw rather than the "best" one keeps the composition varied; the
## two fallbacks below only decide what happens when no candidate qualifies at all.
##   `bulk_cap` > 0 → a fixed max count (fleets: FLEET_COPIES_MAX); 0 → derive it per entry like generate()
##   does for units (PER_SLOT_HP_BUDGET / hp, clamped).
static func _pick_index(pool: Array, remaining: float, need: float, bulk_cap: float) -> int:
	var smallest := -1     # cheapest single unit seen — least overshoot when everything is too pricey
	var smallest_hp := INF
	var biggest := -1      # most HP one slot of it could deliver — best reach when everything is too cheap
	var biggest_deliver := -1.0
	for i in PICK_TRIES:
		var idx := randi() % pool.size()
		var hp := float((pool[idx] as Dictionary)["hp"])
		if hp <= 0.0:
			continue
		var cap := bulk_cap
		if cap <= 0.0:
			cap = float(clampi(int(round(PER_SLOT_HP_BUDGET / hp)), PER_SLOT_MIN, PER_SLOT_MAX))
		var deliver := hp * cap
		if hp <= remaining and deliver >= need:
			return idx
		if hp < smallest_hp:
			smallest_hp = hp
			smallest = idx
		if deliver > biggest_deliver:
			biggest_deliver = deliver
			biggest = idx
	if smallest_hp > remaining and smallest >= 0:
		return smallest      # every candidate overshoots — take the one that overshoots least
	return biggest if biggest >= 0 else (randi() % pool.size())

## Combined RAW HP of a composed wave — the same number `generate()` was aiming at, so a caller can report
## how close it actually landed.
static func wave_hp(slots: Array, unit_pool: Array, fleet_pool: Array) -> float:
	var total := 0.0
	for s: Dictionary in slots:
		var ty := String(s.get("type", ""))
		var n := float(maxi(1, int(s.get("count", 1))))
		if ty.begins_with("fleet:"):
			for f: Dictionary in fleet_pool:
				if "fleet:" + String(f["name"]) == ty:
					total += float(f["hp"]) * n
					break
		else:
			for u: Dictionary in unit_pool:
				if String(u["id"]) == ty:
					total += float(u["hp"]) * n
					break
	return total
