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

const OC_TOP        := 8.0    # play-area top edge (objects-container-local y)
const OC_CENTER_X   := 620.0  # play-area horizontal centre (270 + 700/2)
const BOSS_INTRO_T  := 1.0    # boss/ship fly-in duration (seconds)
const INTRO_EDGE_CM := 2.0    # boss stops this far from the top edge (player likewise from the bottom)

var _objects_container: Control = null
var _modules: Dictionary = {}     # id: String -> boss module (Control)
var _active: Node = null          # currently-spawned boss (persists across stage transitions)

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

func _on_hp_changed(hp: int) -> void:
	if _active != null and is_instance_valid(_active) and _active.has_method("notify_hp_changed"):
		_active.notify_hp_changed(hp)

# ── Public API (boss_panel, main, weapon_system, boss_hp_bar) ────────────────
func spawn_boss(id: String = "elephant") -> void:
	if GameManager.boss_max_hp > 0:
		return   # a boss is already alive — ignore
	var m: Node = _modules.get(id)
	if m == null or not is_instance_valid(m) or not m.has_method("spawn_boss"):
		return
	_active = m
	m.spawn_boss()
	_start_intro()

# 1-second entrance: boss floats down from the top, ship floats up from the bottom
# (gun_system, via the flag), all player input disabled. The flag is set the same frame
# as spawn, so each module's _process freezes before it can tick a move.
func _start_intro() -> void:
	GameManager.boss_intro_active = true
	var eo: EditableObjectNode = null
	if _active.has_method("get_intro_eo"):
		eo = _active.get_intro_eo()
	var tw := create_tween()
	if eo != null and is_instance_valid(eo):
		# Land centred, top of the boss ~INTRO_EDGE_CM below the top edge.
		var target := Vector2(OC_CENTER_X - eo.size.x * 0.5, OC_TOP + _cm_px(INTRO_EDGE_CM))
		eo.position = Vector2(target.x, OC_TOP - eo.size.y - 40.0)   # start just above the top edge
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(eo, "position", target, BOSS_INTRO_T)
	else:
		tw.tween_interval(BOSS_INTRO_T)
	tw.tween_callback(func() -> void: GameManager.boss_intro_active = false)

func _cm_px(cm: float) -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	return cm / 2.54 * float(dpi)

func kill_boss() -> void:
	GameManager.boss_intro_active = false   # safety: never leave input disabled
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
