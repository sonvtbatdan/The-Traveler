@tool
extends SceneTree
## TEMP: exercise wave_hp_gen.gd in isolation (it references no autoloads, so it loads standalone) —
## checks the ±HP_TOLERANCE landing and the ranged-unit ceilings across many random targets/pools.

const Gen := preload("res://scripts/gameplay/wave_hp_gen.gd")

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	seed(4242)

	# A roster shaped like the real one: mostly cheap melee fry, a few expensive types, a handful of ranged.
	var units: Array = []
	for i in 60:
		units.append({"id": "melee%d" % i, "hp": rng.randf_range(20.0, 900.0), "shoot": false})
	for i in 9:
		units.append({"id": "shoot%d" % i, "hp": rng.randf_range(60.0, 1500.0), "shoot": true})
	var fleets: Array = []
	for i in 20:
		fleets.append({"name": "F%d" % i, "hp": rng.randf_range(300.0, 9000.0),
				"shoot": (i % 4)})   # every 4th fleet is pure melee, the rest carry 1-3 ranged units

	var patterns: Array = ["ring", "arc", "scatter", "pincer", "wall", "wedge", "portal", "random"]

	print("=== TOTAL ceiling = 5 (the director's SHOOT_MAX_ALIVE), per-type unlimited ===")
	_run(units, fleets, patterns, 0, 5, 400)
	print()
	print("=== PER-TYPE ceiling = 10 (F7's SHOOT_TYPE_CAP), no total ===")
	_run(units, fleets, patterns, 10, 0, 400)
	print()
	print("=== fleet-only pool (every fleet carries shooters) with TOTAL ceiling 5 ===")
	_run([], fleets, patterns, 0, 5, 200)
	print()
	print("=== degenerate: ONLY ranged units available, TOTAL ceiling 5 ===")
	var only_shoot: Array = []
	for u: Dictionary in units:
		if bool(u["shoot"]):
			only_shoot.append(u)
	_run(only_shoot, [], patterns, 0, 5, 200)
	quit()

func _run(units: Array, fleets: Array, patterns: Array, per_type: int, total_cap: int, n: int) -> void:
	var worst_pct := 0.0
	var within := 0
	var max_shoot := 0
	var max_per_type := 0
	var cap_violations := 0
	var empty := 0
	var t0 := Time.get_ticks_usec()
	for i in n:
		var target := randf_range(2000.0, 400000.0)
		var slots := Gen.generate(target, units, fleets, patterns, 10, per_type, total_cap)
		if slots.is_empty():
			empty += 1
			continue
		var hp := Gen.wave_hp(slots, units, fleets)
		var pct := absf(hp / target - 1.0)
		worst_pct = maxf(worst_pct, pct)
		if pct <= Gen.HP_TOLERANCE:
			within += 1
		# count ranged units this wave puts on the field
		var shoot_total := 0
		var per_id: Dictionary = {}
		for s: Dictionary in slots:
			var ty := String(s["type"])
			var c := int(s["count"])
			if ty.begins_with("fleet:"):
				for f: Dictionary in fleets:
					if "fleet:" + String(f["name"]) == ty:
						shoot_total += c * int(f["shoot"])
						break
			else:
				for u: Dictionary in units:
					if String(u["id"]) == ty:
						if bool(u["shoot"]):
							shoot_total += c
							per_id[ty] = int(per_id.get(ty, 0)) + c
						break
		max_shoot = maxi(max_shoot, shoot_total)
		for k in per_id.keys():
			max_per_type = maxi(max_per_type, int(per_id[k]))
		if total_cap > 0 and shoot_total > total_cap:
			cap_violations += 1
		if per_type > 0:
			for k in per_id.keys():
				if int(per_id[k]) > per_type:
					cap_violations += 1
					break
	var done := n - empty
	print("  %d/%d waves within +/-%.0f%% of target   worst miss %.1f%%   empty %d   %.2f ms/wave" % [
		within, done, Gen.HP_TOLERANCE * 100.0, worst_pct * 100.0, empty,
		float(Time.get_ticks_usec() - t0) / 1000.0 / float(maxi(1, n))])
	print("  max ranged units in one wave: %d (total cap %s)   max of ONE id: %d (per-type cap %s)   VIOLATIONS: %d" % [
		max_shoot, str(total_cap) if total_cap > 0 else "-", max_per_type,
		str(per_type) if per_type > 0 else "-", cap_violations])
