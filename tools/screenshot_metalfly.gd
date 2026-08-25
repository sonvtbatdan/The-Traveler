extends SceneTree
## DEV TOOL (2026-08-24) — boots the arena, spawns the Metalfly boss under live player fire and drives it
## through BOTH phases, screenshotting on every state change and asserting what actually happened.
## Verifies scripts/gameplay/fx/{metalfly_rig,glb_spin_body}.gd + _tick_metalfly/_metalfly_hatch.
##
## Run NON-headless (it renders):  godot --path . --script tools/screenshot_metalfly.gd
##
## Three things are arranged before the fight, and each is a property of THIS HARNESS, not of the boss:
##   - The field is cleared and the timeline stopped, so the boss is the only enemy. With other creeps alive
##     the player levels up, and the level-up board pauses the tree until a card is picked — it re-pauses
##     faster than this tool can dismiss it, which froze two earlier runs outright. (God Mode was tried for
##     this first and is worse: it bundles a x10000 damage multiplier that dropped the arena to 0.4 fps.)
##   - Knockback off. The player's guns knock the boss back faster than it chases, which walked it
##     off-screen and out of the fight.
##   - The player pinned and healed each frame. It drifts on its own, and it cannot dodge a lunge it is
##     pinned in front of; its death would end the run and pause the tree.
## Hit-stagger is deliberately NOT arranged away — the boss is under continuous Gatling fire throughout,
## which is what proves the stagger-lock fix in arena_enemy.gd's _process holds.
##
## The Phase 1 -> 2 hatch is FORCED with one big take_damage() call once real weapon fire has been shown to
## damage the cocoon (see `_cocoon_dmg_seen`). Chewing 2000 HP at the player's real ~110 dps would add ~18s
## of wall clock to every run for nothing: the point is that the hatch works, not that a Gatling can grind.

const SPAWN_DIST := 460.0   # far enough for the cocoon chase to show, close enough to stay ON CAMERA
                            # (at 700 the boss sits just off the top of the frame and every screenshot missed it)

var _f := 0
var _boss: Node2D = null
var _pin: Vector2 = Vector2.ZERO
var _wing_span: Array[float] = []
var _states: Array[int] = []
var _phases: Array[int] = []
var _shots_seen := 0
var _cocoon_spin: Array[float] = []
var _cocoon_tumble: Array[float] = []
# Move 2 lane-tracking probe
var _aim_at_entry := 0.0     # lane rotation the frame the wind-up started
var _aim_after_move := 0.0   # ...and after the player was shoved sideways mid-wind-up
var _aim_locked := 0.0       # lane rotation the frame it locked
var _aim_after_lock := 0.0   # ...and after ANOTHER shove, once locked
var _windup_seen := false
var _lunge_from: Vector2 = Vector2.ZERO
var _lunge_dist := -1.0
var _lunge_odo := 0.0
var _swarm_seen := false
var _swarm_forced := false
var _ring_up_frames := 0
var _ring_after := ""
var _face_err := 0.0
var _face_err_vs_aim := 0.0
var _face_note := ""
var _swarm_report := ""
var _cocoon_hp0 := 0.0
var _cocoon_dmg_seen := false
var _hatched_at := -1
var _last_state := -1
var _shot_n := 0

func _initialize() -> void:
	var packed := load("res://scenes/arena.tscn") as PackedScene
	get_root().add_child(packed.instantiate())
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	if _f == 60:
		_setup_fight()
		return
	if _boss == null:
		return
	if not is_instance_valid(_boss):
		print("BOSS GONE at frame ", _f)
		quit(1)
		return
	_hold_player()
	_sample()

	var phase := int(_boss.get("_mf_phase"))
	if phase == 1:
		if _boss.get("hp") < _cocoon_hp0:
			_cocoon_dmg_seen = true
		if _f == 240:
			_save("user://mf_p1_cocoon.png")
		# Force the hatch, but only once real weapon fire has been shown to bite (see the header).
		if _f >= 300 and _cocoon_dmg_seen:
			print("forcing hatch at f=%d — cocoon took %.0f real weapon damage first"
				% [_f, _cocoon_hp0 - float(_boss.get("hp"))])
			_boss.call("take_damage", 99999.0)
			_hatched_at = _f
			_report_hatch()
		return

	# Phase 2 — one screenshot per state change, so the shots land on the beat instead of a guessed frame.
	var st := int(_boss.get("_mf_state"))
	var lane := _boss.get("_mf_path") as Node2D
	# ── Move 2 probe: does the lane track the player before the lock, and stop after it? ──
	if st == 1 and not _windup_seen:
		_windup_seen = true
		_aim_at_entry = lane.rotation
		_pin += Vector2(320.0, 0.0)            # shove the player sideways mid-wind-up
	elif st == 1 and _aim_after_move == 0.0 and _boss.get("_mf_t") > 0.4:
		_aim_after_move = lane.rotation
	if st == 2 and _aim_locked == 0.0:
		_aim_locked = lane.rotation
		_lunge_from = _boss.global_position
		_pin += Vector2(-460.0, 0.0)           # shove again — a locked lane must ignore this
	elif st == 2 and _boss.get("_mf_t") > 0.3 and _aim_after_lock == 0.0:
		_aim_after_lock = lane.rotation
	if st == 2:
		# The boss's OWN odometer, sampled every frame — net displacement lies here, because the enemy
		# separation pass shoves the boss sideways all the way down the lane whenever the field is busy.
		_lunge_odo = float(_boss.get("_mf_travelled"))
	if st != 2 and _last_state == 2 and _lunge_dist < 0.0:
		_lunge_dist = _lunge_from.distance_to(_boss.global_position)
	# Move 3 is the SECOND special in the alternation, ~10 s of fight after the first. Waiting that long is
	# what kept killing the run (something still opens a modal and pauses the tree around f=2500 even with
	# XP gain off), and waiting proves nothing the alternation flag doesn't already say. So: as soon as the
	# lunge cycle is done, flip the boss onto the swarm branch and expire its cruise timer. Everything from
	# _mf_begin_swarm onward — the wind-up, the release, the brood's own stats — is the real code path.
	if st == 0 and _last_state == 3 and not _swarm_forced:
		_swarm_forced = true
		_boss.set("_mf_use_swarm", true)
		_boss.set("_mf_t", 99.0)
		print("  forcing Move 3 at f=%d (see the note in _on_post_draw)" % _f)
	# Something still pauses the tree mid-run; unpause so the fight carries on regardless of what it was.
	if get_root().get_tree().paused:
		get_root().get_tree().paused = false
	# ── Move 3 probe ──
	# The gathering ring must be up for the whole wind-up and gone once the brood is out.
	if st == 4:
		var r := _boss.get("_mf_ring") as Node2D
		if r != null and r.visible:
			_ring_up_frames += 1
	if st == 3 and _last_state == 4 and not _swarm_seen:
		_swarm_seen = true
		_probe_swarm()
	if _f % 250 == 0:
		var w := (_pin - _boss.global_position).angle() + PI * 0.5
		print("    f=%d state=%d mf_t=%.2f face_err=%.1f dist=%.0f alive=%d paused=%s"
			% [_f, st, _boss.get("_mf_t"),
			   rad_to_deg(angle_difference(float(_boss.get("_facing")), w)),
			   _boss.global_position.distance_to(_pin),
			   get_node_count_in_group("arena_enemy"), str(get_root().get_tree().paused)])
	if st != _last_state:
		_last_state = st
		_shot_n += 1
		_save("user://mf_p2_%d_state%d.png" % [_shot_n, st])
		print("  -> state %d at f=%d  mouth=%.2f  flap_hz=%.1f  lane=%s  hp=%.0f/%.0f"
			% [st, _f, _rig_f("_mouth"), _rig_f("_flap_hz"),
			   str((_boss.get("_mf_path") as Node2D).visible), _boss.get("hp"), _boss.get("hp_max")])
	# The hatch shot is taken on the same frame the hatch fires, so the cocoon (queue_free'd, not freed yet)
	# is still on it. This one is 40 frames later: the winged body, alone.
	if _hatched_at > 0 and _f == _hatched_at + 40:
		_save("user://mf_p2_hatched.png")
	# Dev -> Creep panel, Boss tab: the new tab and its live 3D Metalfly cell.
	if _hatched_at > 0 and _f == _hatched_at + 80:
		_show_boss_tab()
	if _hatched_at > 0 and _f == _hatched_at + 140:
		_save("user://mf_boss_tab.png")
	if _hatched_at > 0 and _f > _hatched_at + 3400:
		_report()
		quit(0)

## Open the Quick Spawn panel on its Boss tab so the screenshot below catches it.
func _show_boss_tab() -> void:
	var dbg: Node = get_first_node_in_group("arena_debug_spawn")
	if dbg == null:
		print("debug spawn node not found — Boss tab not shown")
		return
	# The panel is built lazily on first open, so go through the real toggle rather than poking `_creep_panel`
	# (which is null until then).
	dbg.call("set_dev_ui_visible", true)
	dbg.call("toggle_creep_panel")
	var panel := dbg.get("_creep_panel") as Panel
	if panel == null:
		print("creep panel not built")
		return
	panel.visible = true
	dbg.call("_select_creep_tab", "boss")
	print("Boss tab open — tabs: ", (dbg.get("_creep_tab_btns") as Dictionary).keys(),
		"  active: ", dbg.get("_creep_tab"))

func _setup_fight() -> void:
	var wd: Node = get_first_node_in_group("wave_director")
	wd.set("_spawning_stopped", true)
	wd.set("_tl_streams", [])
	for e: Node in get_nodes_in_group("arena_enemy"):
		e.queue_free()
	var pl := get_first_node_in_group("player") as Node2D
	_pin = pl.global_position
	_boss = wd.call("_spawn", "metalfly", _pin + Vector2(0.0, -SPAWN_DIST), true) as Node2D
	if _boss == null:
		print("spawn FAILED")
		quit(1)
		return
	_boss.set("_knockback_mult", 0.0)
	_cocoon_hp0 = float(_boss.get("hp"))
	print("── PHASE 1 (cocoon) ──")
	print("  phase=", _boss.get("_mf_phase"), "  hp=", _cocoon_hp0, "/", _boss.get("hp_max"),
		"  speed=", _boss.get("speed"))
	print("  cocoon body built: ", _boss.get("_mf_cocoon") != null,
		"   winged rig built yet: ", _boss.get("_mf_rig") != null, " (must be false — built at hatch)")

func _report_hatch() -> void:
	print("── PHASE 2 (winged) ──")
	print("  phase=", _boss.get("_mf_phase"), "  hp=", _boss.get("hp"), "/", _boss.get("hp_max"))
	print("  cocoon freed: ", _boss.get("_mf_cocoon") == null, "   winged rig built: ", _boss.get("_mf_rig") != null)
	print("  boss still alive (not _dead): ", not bool(_boss.get("_dead")))
	var rig: Node = _boss.get("_mf_rig")
	if rig != null:
		print("  bones: ", (rig.get("_skel") as Skeleton3D).get_bone_count(), "   unresolved: ", _missing_bones(rig))
	_save("user://mf_p2_hatch.png")

func _hold_player() -> void:
	var pl := get_first_node_in_group("player") as Node2D
	if pl != null:
		pl.global_position = _pin
	var gm := get_root().get_node_or_null("GameManager")
	if gm != null:
		gm.set("ship_hp", int(gm.get("ship_max_hp")))

func _sample() -> void:
	_states.append(int(_boss.get("_mf_state")))
	_phases.append(int(_boss.get("_mf_phase")))
	var coc: Node = _boss.get("_mf_cocoon")
	if coc != null:
		_cocoon_spin.append(float((coc.get("_pivot") as Node3D).rotation.y))
		_cocoon_tumble.append(float((coc.get("_tumble") as Node3D).rotation.x))
	var r: Node = _boss.get("_mf_rig")
	if r != null:
		var m: Array = r.call("wing_muzzles")
		if m.size() == 2:
			_wing_span.append((m[0] as Vector2).distance_to(m[1] as Vector2))
	var mgr: Node = get_first_node_in_group("enemy_manager")
	if mgr != null:
		_shots_seen = maxi(_shots_seen, (mgr.get("_bullets") as Array).size())
	# How far off the player is the boss pointing, in every state that is supposed to be facing them?
	# ("sprite north" is the travel angle + PI/2, hence the offset.)
	var st2 := int(_boss.get("_mf_state"))
	# Only in SETTLED cruise (>1s in). The peak over every frame is a useless 180 deg: the lunge ends with
	# the boss having flown straight PAST the player, so it starts the next state facing the wrong way by
	# definition and needs ~0.6s at MF_TURN_CHASE to swing round. What matters is whether it converges.
	# Upper bound as well as lower: the forced-Move-3 hack above parks `_mf_t` at 99 for one frame, and that
	# frame lands right after a lunge with the boss still facing backwards. Sampling it reported a 180 deg
	# "failure" that was purely this tool's own doing — the real trace is 0.0 deg throughout.
	var mf_t := float(_boss.get("_mf_t"))
	# ...and skip frames where the boss is sitting ON the player (the pinned target cannot back away, so it
	# closes to dist 0 and stays). "Which way is the player" has no answer at zero separation: the enemy code
	# falls back to Vector2.UP and this probe takes .angle() of a zero vector, so the two disagree by an
	# arbitrary amount. Every 180 deg reading this tool produced came from that one degenerate frame.
	var sep := _boss.global_position.distance_to(_pin)
	if int(_boss.get("_mf_phase")) == 2 and st2 == 0 and mf_t > 1.0 and mf_t < 6.0 and sep > 20.0:
		var want := (_pin - _boss.global_position).angle() + PI * 0.5
		var e := absf(rad_to_deg(angle_difference(float(_boss.get("_facing")), want)))
		if e > _face_err:
			_face_err = e
			# What is it actually pointing at? The boss aims at `_player_pos()`, which is its AGGRO target —
			# not necessarily the player. Recording both separates "the facing logic is broken" from "it is
			# correctly facing something that isn't the player".
			var aim_pos: Vector2 = _boss.call("_player_pos")
			var want2 := (aim_pos - _boss.global_position).angle() + PI * 0.5
			_face_err_vs_aim = absf(rad_to_deg(angle_difference(float(_boss.get("_facing")), want2)))
			var ag: Node = _boss.get("_aggro_target")
			_face_note = "f=%d  mf_t=%.2f  dist=%.0f  aggro=%s  aim_pos=%s  player=%s  boss=%s" % [
				_f, mf_t, _boss.global_position.distance_to(_pin),
				(ag.name if ag != null else "<none>"), str(aim_pos.round()), str(_pin.round()),
				str(_boss.global_position.round())]

## Snapshot the brood the instant Move 3 releases it.
func _probe_swarm() -> void:
	var minis: Array[Node] = []
	for e: Node in get_nodes_in_group("arena_enemy"):
		if e != _boss and String(e.get("_body_rig")) == "metalfly":
			minis.append(e)
	var line := "count=%d" % minis.size()
	if not minis.is_empty():
		var m := minis[0]
		var hp_pct := 100.0 * float(m.get("hp")) / maxf(float(_boss.get("hp_max")), 1.0)
		var sz_pct := 100.0 * float(m.get("_radius")) / maxf(float(_boss.get("_radius")), 0.001)
		line += "  hp=%.0f = %.1f%% of boss (spec 5%%)  radius=%.1f = %.1f%% of boss (spec 25%%)  rig=%s" % [
			float(m.get("hp")), hp_pct, float(m.get("_radius")), sz_pct, str(m.get("_mf_rig") != null)]
		if absf(hp_pct - 5.0) > 0.2:
			line += "   <-- HP OFF SPEC"
		if absf(sz_pct - 25.0) > 0.5:
			line += "   <-- SIZE OFF SPEC"
	_swarm_report = line
	print("  swarm released: ", line)
	# Sampled on the release frame itself: release() starts a fade, so `visible` is still true here and the
	# meaningful check is that the fade is running (target 0), with the final state confirmed in _report().
	var r2 := _boss.get("_mf_ring") as Node2D
	if r2 != null:
		print("  ring at release: visible=%s target_alpha=%.1f" % [str(r2.visible), float(r2.get("_target_alpha"))])
	if minis.size() != 8:
		print("  FAIL: expected 8 minis")
	_save("user://mf_p2_swarm.png")

func _rig_f(prop: String) -> float:
	var rig: Node = _boss.get("_mf_rig")
	return float(rig.get(prop)) if rig != null else -1.0

func _missing_bones(rig: Node) -> Array:
	var out: Array = []
	var tbl: Dictionary = rig.get("_bone")
	for k: String in tbl:
		if int(tbl[k]) < 0:
			out.append(k)
	return out

func _report() -> void:
	var mn := INF
	var mx := -INF
	for v: float in _wing_span:
		mn = minf(mn, v)
		mx = maxf(mx, v)
	var sp_mn := INF
	var sp_mx := -INF
	for v: float in _cocoon_spin:
		sp_mn = minf(sp_mn, v)
		sp_mx = maxf(sp_mx, v)
	print("── verification ──")
	print("phase sequence: ", _compress(_phases))
	print("state sequence (0 cruise, 1 wind-up, 2 lunge, 3 recover): ", _compress(_states))
	var tm_mn := INF
	var tm_mx := -INF
	for v: float in _cocoon_tumble:
		tm_mn = minf(tm_mn, v)
		tm_mx = maxf(tm_mx, v)
	print("cocoon SPIN travelled  : %.2f rad over %d sampled frames (a static body prints 0.00)"
		% [sp_mx - sp_mn, _cocoon_spin.size()])
	print("cocoon TUMBLE travelled: %.2f rad  (second axis — 0.00 means it only turns like a dial)"
		% [tm_mx - tm_mn])
	print("Move 2 lane: entry %.1f deg -> after player moved %.1f deg  (tracking: %s)"
		% [rad_to_deg(_aim_at_entry), rad_to_deg(_aim_after_move),
		   str(absf(_aim_after_move - _aim_at_entry) > 0.05)])
	print("Move 2 lane: locked %.1f deg -> after another move %.1f deg  (locked: %s)"
		% [rad_to_deg(_aim_locked), rad_to_deg(_aim_after_lock),
		   str(absf(_aim_after_lock - _aim_locked) < 0.001)])
	print("Move 2 lunge: odometer %.0f px, net displacement %.0f px  (MF_LUNGE_LEN = 1200; the two differ by"
		% [_lunge_odo, _lunge_dist])
	print("              however far the separation pass shoved it off the lane)")
	print("Move 3 brood: ", _swarm_report if _swarm_report != "" else "NEVER FIRED")
	var r3 := _boss.get("_mf_ring") as Node2D
	print("Move 3 ring: up for %d frames of the wind-up; now visible=%s  (must be false — it is released"
		% [_ring_up_frames, str(r3.visible if r3 != null else false)])
	print("             the moment the brood appears)")
	print("worst facing error in settled cruise: %.1f deg  (it LERPS toward the player, so a couple of" % _face_err)
	print("              degrees is turn-rate lag; tens of degrees would mean it is not tracking at all)")
	print("   at that worst frame, error vs what it was ACTUALLY aiming at: %.1f deg" % _face_err_vs_aim)
	print("   ", _face_note)
	print("wing-tip span across phase 2: min=%.1f px  max=%.1f px  (a static rig prints min == max)" % [mn, mx])
	print("peak simultaneous enemy projectiles: ", _shots_seen)

func _compress(a: Array) -> Array:
	var out: Array = []
	for v in a:
		if out.is_empty() or out[out.size() - 1] != v:
			out.append(v)
	return out

func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	print("screenshot: ", path, " err=", img.save_png(path))
