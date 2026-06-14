extends Control

# =============================================================================
# Boss Manager
# -----------------------------------------------------------------------------
# Single coordinator for every boss. Owns the per-boss modules as children, is
# the ONLY node in the "boss_fight" group, and the ONLY listener of
# GameManager.boss_killed / boss_hp_changed — routing each to the ACTIVE boss.
# This removes the old 3-way signal cross-talk and the ambiguous group lookups
# (the elephant-button bug), and is where Metalfly finally gets wired in.
#
# Each boss keeps its own engine / move logic / victory screen in its module:
#   boss_elephant.gd, boss_chromeleon.gd, boss_metalfly.gd
# Modules expose: setup(oc), spawn_boss(), kill_boss(), get_boss_hit_rect(),
# notify_boss_killed(), and optionally notify_hp_changed(hp), flash_boss_hit(),
# consume_projectile_near(c, r), get_move_name().
# =============================================================================

const BossElephantScript   := preload("res://scripts/gameplay/boss_elephant.gd")
const BossChromeleonScript := preload("res://scripts/gameplay/boss_chromeleon.gd")
const BossMetalflyScript   := preload("res://scripts/gameplay/boss_metalfly.gd")
const BossNautilusScript   := preload("res://scripts/gameplay/boss_nautilus.gd")
const BossDeathFXScript    := preload("res://scripts/gameplay/boss_death_fx.gd")

const OC_BOUNDS     := Rect2(15.0, 8.0, 955.0, 764.0)   # play-area rect (viewport)
const OC_TOP        := 8.0    # play-area top edge (objects-container-local y)
const OC_CENTER_X   := 492.0  # play-area horizontal centre (15 + 955/2)
const BOSS_INTRO_T  := 1.0    # boss/ship fly-in duration (seconds)
const INTRO_EDGE_CM := 2.0    # boss stops this far from the top edge (player likewise from the bottom)

const WARNING_DELAY   := 5.0    # seconds of warning flash before boss spawns
const WANDER_DURATION := 5.0    # seconds boss wanders before attacking
const WANDER_CENTER   := Vector2(492.0, 158.0)  # OC coords — screen (477,150) + SS_OFFSET (15,8)
const WANDER_RADIUS   := 50.0   # max px from center per step
const WANDER_STEP_T   := 1.2    # seconds per wander step

var _objects_container: Control = null
var _modules: Dictionary = {}     # id: String -> boss module (Control)
var _active: Node = null          # currently-spawned boss (persists across stage transitions)
var _spawning: bool = false       # true during warning delay — blocks duplicate spawn calls

func setup(oc: Control) -> void:
	_objects_container = oc
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# z_index 0 (not 200): each module child still sets its own z_index = 200, so the
	# module's effective z stays the same as when it was a direct child of the container
	# (manager is just a transparent owner — it draws nothing itself).
	z_index = 0
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("boss_fight")

	_modules["elephant"]   = _make_module(BossElephantScript)
	_modules["chromeleon"] = _make_module(BossChromeleonScript)
	_modules["metalfly"]   = _make_module(BossMetalflyScript)
	_modules["nautilus"]   = _make_module(BossNautilusScript)

	# Single listener for both boss signals; routed only to the active boss below.
	GameManager.boss_killed.connect(_on_boss_killed)
	GameManager.boss_hp_changed.connect(_on_hp_changed)

func _make_module(script: Script) -> Node:
	var m: Node = script.new()
	add_child(m)
	m.setup(_objects_container)
	return m

# ── Signal hub — only the active boss responds (no more cross-talk) ──────────
func _on_boss_killed() -> void:
	if _active != null and is_instance_valid(_active) and _active.has_method("notify_boss_killed"):
		_active.notify_boss_killed()
	# XP (Phase 2): award once on the REAL end of a fight, never on a 2-phase boss's phase change.
	# is_phase_transition() is true only mid-fight, so this fires exactly once per boss defeated.
	if not is_phase_transition():
		GameManager.add_xp(GameManager.XP_PER_BOSS)

func _on_hp_changed(hp: int) -> void:
	if _active != null and is_instance_valid(_active) and _active.has_method("notify_hp_changed"):
		_active.notify_hp_changed(hp)

## True only when the active boss's CURRENT boss_killed is a phase transition (e.g. a 2-phase boss's
## first phase dying), not a real end of the fight. Listeners that reset between fights (asteroids,
## boss music) check this so they DON'T reset between phases. Defaults to false → real end.
func is_phase_transition() -> bool:
	if _active != null and is_instance_valid(_active) and _active.has_method("is_phase_transition"):
		return _active.is_phase_transition()
	return false

# ── Public API (boss_panel, main, weapon_system, boss_hp_bar) ────────────────
func spawn_boss(id: String = "elephant") -> void:
	if GameManager.boss_max_hp > 0 or _spawning:
		return   # a boss is already alive or warning is playing — ignore
	var m: Node = _modules.get(id)
	if m == null or not is_instance_valid(m) or not m.has_method("spawn_boss"):
		return
	_spawning = true
	if m.has_method("setup_arena"):
		m.setup_arena()                    # swap bg/overlay immediately when warning starts
	GameManager.boss_incoming.emit()   # triggers warning overlay immediately

	await get_tree().create_timer(WARNING_DELAY).timeout

	if not _spawning:
		return   # kill_boss() was called during the warning delay — abort

	_active = m
	m.spawn_boss()   # boss appears, sets HP, changes BG — does NOT start attacking
	_start_intro()

# 1-second entrance: boss floats down from the top, ship floats up from the bottom.
# After intro completes, transitions directly into the wander phase.
func _start_intro() -> void:
	GameManager.boss_intro_active = true
	var eo: EditableObjectNode = null
	if _active != null and _active.has_method("get_intro_eo"):
		eo = _active.get_intro_eo()
	var tw := create_tween()
	if eo != null and is_instance_valid(eo):
		var target := Vector2(OC_CENTER_X - eo.size.x * 0.5, OC_TOP + _cm_px(INTRO_EDGE_CM))
		eo.position = Vector2(target.x, OC_TOP - eo.size.y - 40.0)
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(eo, "position", target, BOSS_INTRO_T)
	else:
		tw.tween_interval(BOSS_INTRO_T)
	tw.tween_callback(_start_wander)

# Boss drifts slowly around WANDER_CENTER for WANDER_DURATION seconds before attacking.
func _start_wander() -> void:
	var eo: EditableObjectNode = null
	if _active != null and _active.has_method("get_intro_eo"):
		eo = _active.get_intro_eo()

	var tw := create_tween()
	var steps := int(WANDER_DURATION / WANDER_STEP_T)
	for i: int in steps:
		var angle := randf() * TAU
		var dist  := randf_range(10.0, WANDER_RADIUS)
		var wp    := WANDER_CENTER + Vector2(cos(angle), sin(angle)) * dist
		if eo != null and is_instance_valid(eo):
			# Offset so boss center lands on wp, not its top-left corner
			var dest := wp - eo.size * 0.5
			tw.tween_property(eo, "position", dest, WANDER_STEP_T) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			tw.tween_interval(WANDER_STEP_T)

	tw.tween_callback(_end_wander)

func _end_wander() -> void:
	GameManager.boss_intro_active = false
	_spawning = false
	if _active != null and is_instance_valid(_active) and _active.has_method("start_fight"):
		_active.start_fight()

func _cm_px(cm: float) -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	return cm / 2.54 * float(dpi)

func kill_boss() -> void:
	GameManager.boss_intro_active = false   # safety: never leave input disabled
	_spawning = false                       # cancel any in-progress warning/wander
	if _active != null and is_instance_valid(_active) and _active.has_method("kill_boss"):
		_active.kill_boss()

func get_boss_hit_rect() -> Rect2:
	if _active != null and is_instance_valid(_active) and _active.has_method("get_boss_hit_rect"):
		return _active.get_boss_hit_rect()
	return Rect2()

func flash_boss_hit() -> void:
	if _active != null and is_instance_valid(_active) and _active.has_method("flash_boss_hit"):
		_active.flash_boss_hit()

func consume_projectile_near(center: Vector2, radius: float) -> Dictionary:
	if _active != null and is_instance_valid(_active) and _active.has_method("consume_projectile_near"):
		return _active.consume_projectile_near(center, radius)
	return {"hit": false, "pos": Vector2.ZERO}

func get_move_name() -> String:
	if _active != null and is_instance_valid(_active) and _active.has_method("get_move_name"):
		return _active.get_move_name()
	return ""

# Shared death cutscene: each boss calls this with its visible body node(s) right
# before its victory screen, and awaits the returned signal. FX defined once in
# boss_death_fx.gd; the manager owns the arena rect + the shake target.
func play_death_cutscene(body_nodes: Array, is_final: bool = true) -> Signal:
	var fx := BossDeathFXScript.new()
	_objects_container.add_child(fx)
	fx.finished.connect(fx.queue_free)
	fx.play(body_nodes, OC_BOUNDS, _objects_container, is_final)
	return fx.finished
