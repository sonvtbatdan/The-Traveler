extends Control

const SS_OFFSET  := Vector2(270.0, 8.0)
const OC_BOUNDS  := Rect2(270.0, 8.0, 700.0, 764.0)

const GifLoader := preload("res://scripts/ui/edit_mode/gif_loader.gd")

const BOSS_DAMAGE_MULT := 0.75

# ── Phase 1 & 2 ────────────────────────────────────────────────────────────────
const PHASE1_MAX_HP    := 1000
const PHASE2_MAX_HP    := 5000
const TRANSFORM_ANIM_T := 1.5

# ── M1 — Shard Burst (6s) ────────────────────────────────────────────────────
const M1_DURATION      := 6.0
const M1_DRIFT_SPD     := 40.0
const M1_BURST_INT     := 0.2
const M1_SHARD_COUNT   := 8
const M1_SHARD_SPEED   := 160.0
const M1_SHARD_DMG     := 8
const M1_SHARD_SIZE    := Vector2(10.0, 10.0)

# ── M2 — Blade Sweep (8s) ────────────────────────────────────────────────────
const M2_DURATION      := 8.0
const M2_ROW_INT       := 0.5
const M2_BLADES_PER_ROW := 6
const M2_BLADE_SPEED   := 180.0
const M2_BLADE_DMG     := 14
const M2_BLADE_ROT_SPD := 4.0 * TAU
const M2_BLADE_SIZE    := Vector2(18.0, 18.0)
const M2_LEFT_X_SS     := 100.0
const M2_RIGHT_X_SS    := 550.0

# ── M3 — Sting Beam ─────────────────────────────────────────────────────────
const M3_ENTRY_Y_SS    := 175.0
const M3_MOVE_SPD      := 600.0
const M3_ROT_T         := 1.0
const M3_WARN_T        := 1.0
const M3_FIRE_T        := 1.0
const M3_LASER_W       := 4.0
const M3_LASER_FIRE_MULT := 5.0
const M3_LASER_DMG     := 22
const M3_LASER_WARN_MOD := Color(0.5, 0.8, 0.5, 0.6)
const M3_LASER_FLASH_CYC := 0.08

# ── M4 — Dive Scatter ───────────────────────────────────────────────────────
const M4_DIVE_SPD      := 500.0
const M4_RETREAT_SPD   := 350.0
const M4_SCATTER_COUNT := 12
const M4_SCATTER_SPREAD := PI * 0.6
const M4_SCATTER_SPEED := 220.0
const M4_SCATTER_DMG   := 12

# ── M5 — Needle Storm (5s) ──────────────────────────────────────────────────
const M5_DURATION      := 5.0
const M5_HOVER_Y_SS    := 200.0
const M5_NEEDLE_INT    := 0.3
const M5_NEEDLE_SPEED  := 300.0
const M5_NEEDLE_DMG    := 10
const M5_NEEDLE_SIZE   := Vector2(6.0, 14.0)
const M5_HOVER_LERP    := 3.0

# ── Phase enum ───────────────────────────────────────────────────────────────
enum Phase {
	IDLE,
	ENTERING,
	M1_DRIFT,
	M2_TWEEN, M2_SWEEP,
	M3_ROT, M3_MOVE, M3_WARN, M3_FIRE,
	M4_ENTRY, M4_DIVE, M4_SCATTER, M4_RETREAT,
	M5_HOVER, M5_STORM,
	DONE
}

var _phase     := Phase.IDLE
var _phase_acc := 0.0
var _forced_kill := false

# Phase tracking
var _boss_phase := 1  # 1 = cocoon phase, 2 = metalfly phase
var _cocoon_eo: EditableObjectNode = null
var _transform_anim_acc := 0.0
var _transform_anim_tween: Tween = null

# Damage feedback
var _last_hp := 0
var _flash_tween: Tween = null

# Cocoon movement (Phase 1)
var _cocoon_velocity := Vector2.ZERO
var _cocoon_direction_timer := 0.0
const COCOON_SPEED := 30.0
const COCOON_DIRECTION_CHANGE_INTERVAL := 2.0  # Change direction every 2 seconds

# Scene refs
var _objects_container: Control         = null
var _boss_eo:           EditableObjectNode = null
var _ship_eo:           EditableObjectNode = null
var _ship_alpha_uv:     Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
var _ship_img:          Image = null

# Firepoint
var _fp1_off:  Vector2  = Vector2.ZERO
var _fp1_node: Node2D   = null

# Clip container
var _clip_node: Control = null

# Laser ref (M3)
var _laser_tr:        TextureRect = null
var _laser_flash_acc: float       = 0.0
var _laser_hit_done:  bool        = false
var _laser_w:         float       = M3_LASER_W
var _m3_target_cx_oc: float       = 0.0

# Cached assets
var _shard_frames:  Array = []
var _shard_delays:  Array = []
var _blade_frames:  Array = []
var _blade_delays:  Array = []
var _needle_frames: Array = []
var _needle_delays: Array = []
var _laser_frames:  Array = []

# M1 state
var _m1_acc:        float   = 0.0
var _m1_drift_tgt:  Vector2 = Vector2.ZERO

# M2 state
var _m2_acc:        float = 0.0
var _m2_row_acc:    float = 0.0
var _m2_side:       int   = 0

# M4 state
var _m4_ship_target_y: float = 0.0
var _m4_top_x:         float = 0.0

# M5 state
var _m5_acc:        float = 0.0
var _m5_needle_acc: float = 0.0

# Projectiles
var _projectiles: Array = []

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func setup(oc: Control) -> void:
	_objects_container = oc
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	process_mode = Node.PROCESS_MODE_PAUSABLE

	var clip := Control.new()
	clip.position = OC_BOUNDS.position
	clip.size = OC_BOUNDS.size
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.z_index = 0
	clip.z_as_relative = false
	add_child(clip)
	_clip_node = clip

	_find_eos()
	_load_fp_offsets()
	_load_assets()
	# Boss-killed + boss_hp_changed routing is handled by the Boss Manager (boss_fight.gd),
	# the single listener; it calls notify_boss_killed() / notify_hp_changed() on the active boss.

func _process(delta: float) -> void:
	# Cocoon Phase 1 movement (must be BEFORE early return!)
	if _boss_phase == 1 and _phase == Phase.IDLE:
		_tick_cocoon_movement(delta)

	# Draw hitbox for all phases (must be BEFORE early return!)
	queue_redraw()

	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return

	_tick_projectiles(delta)

	if _phase == Phase.ENTERING:
		return

	match _phase:
		Phase.M1_DRIFT:
			_tick_m1(delta)
		Phase.M2_TWEEN, Phase.M2_SWEEP:
			_tick_m2(delta)
		Phase.M3_ROT:
			_tick_m3_rot(delta)
		Phase.M3_MOVE:
			_tick_m3_move(delta)
		Phase.M3_WARN:
			_tick_m3_warn(delta)
		Phase.M3_FIRE:
			_tick_m3_fire(delta)
		Phase.M4_ENTRY, Phase.M4_DIVE, Phase.M4_SCATTER, Phase.M4_RETREAT:
			_tick_m4(delta)
		Phase.M5_HOVER, Phase.M5_STORM:
			_tick_m5(delta)

# ── Public API ─────────────────────────────────────────────────────────────────

func spawn_boss() -> void:
	if _phase != Phase.IDLE and _phase != Phase.DONE:
		return
	if not is_instance_valid(_cocoon_eo):
		return

	_boss_phase = 1
	_cocoon_direction_timer = 0.0
	_cocoon_velocity = Vector2.ZERO
	GameManager.boss_max_hp = PHASE1_MAX_HP
	GameManager.boss_hp = PHASE1_MAX_HP
	_last_hp = PHASE1_MAX_HP
	GameManager.boss_hp_changed.emit(PHASE1_MAX_HP)
	GameManager.boss_spawned.emit()

	if not GameManager.manual_boost:
		GameManager.set_boost(true)

	# Enable auto-fire for boss fight
	var ws := get_tree().get_first_node_in_group("weapon_system")
	if ws != null and ws.has_method("set_auto_fire"):
		ws.set_auto_fire(true)

	start_fight()

func kill_boss() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return

	_forced_kill = true
	_cleanup_projectiles()
	_free_laser()
	if is_instance_valid(_boss_eo):
		_boss_eo.visible = false
		_boss_eo.rotation = 0.0
		_boss_eo.scale = Vector2.ONE

	_phase = Phase.IDLE
	_phase_acc = 0.0
	GameManager.boss_hp = 0
	GameManager.boss_max_hp = 0
	GameManager.boss_killed.emit()

func _draw() -> void:
	# DEBUG: Draw boss hitbox outline (red)
	if GameManager.boss_max_hp > 0:
		var br := get_boss_hit_rect()
		if br.size != Vector2.ZERO:
			draw_rect(Rect2(br.position - global_position, br.size), Color(1, 0, 0), false, 2.0)

func start_fight() -> void:
	# Show all metalfly-related objects
	for child in _objects_container.get_children():
		var eo := child as EditableObjectNode
		if eo == null:
			continue
		var base := eo.source_path.get_file().get_basename().to_lower()
		if base in ["metalfly", "cocoon", "transform", "arrow", "fly"]:
			eo.visible = false  # Hide all first

	if _boss_phase == 1:
		# Phase 1: show cocoon only
		if is_instance_valid(_cocoon_eo):
			_cocoon_eo.visible = true
			var tr := _cocoon_eo.texture_rect
			if tr != null:
				tr.visible = true
			_cocoon_eo.pivot_offset = _cocoon_eo.size / 2.0
			_cocoon_eo.rotation = 0.0
			_cocoon_eo.scale = Vector2.ONE
	else:
		# Phase 2: show metalfly and accessories
		if is_instance_valid(_boss_eo):
			_boss_eo.visible = true
			var tr := _boss_eo.texture_rect
			if tr != null:
				tr.visible = true
			_boss_eo.pivot_offset = _boss_eo.size / 2.0
			_boss_eo.rotation = 0.0
			_boss_eo.scale = Vector2.ONE
			# Show phase 2 decorations
			for child in _objects_container.get_children():
				var eo := child as EditableObjectNode
				if eo == null:
					continue
				var base := eo.source_path.get_file().get_basename().to_lower()
				match base:
					"arrow", "fly":
						eo.visible = true
						var wtr := eo.texture_rect
						if wtr != null:
							wtr.visible = true

	_begin_random_move()

func get_boss_hit_rect() -> Rect2:
	var target_eo: EditableObjectNode = null
	if _boss_phase == 1:
		target_eo = _cocoon_eo
	else:
		target_eo = _boss_eo

	if not is_instance_valid(target_eo):
		print("[HIT] target invalid phase=%d" % _boss_phase)
		return Rect2()
	if not target_eo.visible:
		print("[HIT] target NOT VISIBLE phase=%d name=%s" % [_boss_phase, target_eo.name])
		return Rect2()

	# Use TextureRect like chromeleon & elephant
	var tr: TextureRect = target_eo.texture_rect
	if tr == null:
		return Rect2(target_eo.global_position, target_eo.size)   # fallback

	var sz := tr.size
	var xf := tr.get_global_transform()
	var p0 := xf * Vector2(0.0, 0.0)
	var p1 := xf * Vector2(sz.x, 0.0)
	var p2 := xf * Vector2(0.0, sz.y)
	var p3 := xf * Vector2(sz.x, sz.y)
	var minp := Vector2(minf(minf(p0.x, p1.x), minf(p2.x, p3.x)),
						minf(minf(p0.y, p1.y), minf(p2.y, p3.y)))
	var maxp := Vector2(maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)),
						maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y)))
	return Rect2(minp, maxp - minp)

func get_move_name() -> String:
	match _phase:
		Phase.M1_DRIFT:
			return "M1: Shard Burst"
		Phase.M2_TWEEN, Phase.M2_SWEEP:
			return "M2: Blade Sweep"
		Phase.M3_ROT, Phase.M3_MOVE, Phase.M3_WARN, Phase.M3_FIRE:
			return "M3: Sting Beam"
		Phase.M4_ENTRY, Phase.M4_DIVE, Phase.M4_SCATTER, Phase.M4_RETREAT:
			return "M4: Dive Scatter"
		Phase.M5_HOVER, Phase.M5_STORM:
			return "M5: Needle Storm"
		_:
			return ""

# ── Move Selection ─────────────────────────────────────────────────────────────

func _begin_random_move() -> void:
	# Phase 1: cocoon doesn't attack, just idle
	if _boss_phase == 1:
		_phase = Phase.IDLE
		return

	# Phase 2: metalfly executes moves
	if is_instance_valid(_boss_eo):
		_boss_eo.rotation = 0.0
	var move_id := randi() % 5
	match move_id:
		0:
			print("[METALFLY] Starting M1: Shard Burst")
			_begin_m1()
		1:
			print("[METALFLY] Starting M2: Blade Sweep")
			_begin_m2()
		2:
			print("[METALFLY] Starting M3: Sting Beam")
			_begin_m3()
		3:
			print("[METALFLY] Starting M4: Dive Scatter")
			_begin_m4()
		4:
			print("[METALFLY] Starting M5: Needle Storm")
			_begin_m5()

# ── Move 1: Shard Burst ────────────────────────────────────────────────────────

func _begin_m1() -> void:
	_phase = Phase.ENTERING
	_phase_acc = 0.0
	var entry_pos := Vector2(OC_BOUNDS.get_center().x - _boss_eo.size.x / 2.0, OC_BOUNDS.position.y + 20)
	var tw := create_tween()
	tw.tween_property(_boss_eo, "position", entry_pos, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(func():
		_phase = Phase.M1_DRIFT
		_phase_acc = 0.0
		_m1_acc = 0.0
		_m1_drift_tgt = _pick_drift_target()
	)

func _tick_m1(delta: float) -> void:
	_phase_acc += delta
	_m1_acc    += delta

	var diff := _m1_drift_tgt - _boss_eo.position
	if diff.length() < M1_DRIFT_SPD * delta + 5.0:
		_m1_drift_tgt = _pick_drift_target()
	else:
		_boss_eo.position += diff.normalized() * M1_DRIFT_SPD * delta
	_clamp_boss()

	while _m1_acc >= M1_BURST_INT:
		_m1_acc -= M1_BURST_INT
		_fire_shard_burst()

	if _phase_acc >= M1_DURATION:
		print("[METALFLY] M1 complete (%.1fs), switching move" % _phase_acc)
		_begin_random_move()

func _fire_shard_burst() -> void:
	var origin := _get_fp1_world()
	print("[METALFLY] M1: Firing %d shards from (%.0f, %.0f)" % [M1_SHARD_COUNT, origin.x, origin.y])
	for i in M1_SHARD_COUNT:
		var angle := float(i) * TAU / float(M1_SHARD_COUNT)
		var dir := Vector2.from_angle(angle)
		_spawn_shard(origin, dir * M1_SHARD_SPEED, M1_SHARD_DMG)

func _pick_drift_target() -> Vector2:
	return Vector2(
		randf_range(OC_BOUNDS.position.x + 40, OC_BOUNDS.end.x - 40 - _boss_eo.size.x),
		randf_range(OC_BOUNDS.position.y + 10, OC_BOUNDS.position.y + 250)
	)

# ── Move 2: Blade Sweep ────────────────────────────────────────────────────────

func _begin_m2() -> void:
	_phase = Phase.M2_TWEEN
	_phase_acc = 0.0
	_m2_acc = 0.0
	_m2_row_acc = 0.0
	_m2_side = 1 - _m2_side
	var target_x_ss := M2_LEFT_X_SS if _m2_side == 0 else M2_RIGHT_X_SS
	var target_pos := Vector2(target_x_ss + SS_OFFSET.x - _boss_eo.size.x / 2.0, OC_BOUNDS.position.y + 30)
	var tw := create_tween()
	tw.tween_property(_boss_eo, "position", target_pos, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(func():
		_phase = Phase.M2_SWEEP
		_phase_acc = 0.0
		_m2_row_acc = 0.0
	)

func _tick_m2(delta: float) -> void:
	_phase_acc  += delta
	_m2_row_acc += delta
	while _m2_row_acc >= M2_ROW_INT:
		_m2_row_acc -= M2_ROW_INT
		_spawn_blade_row()
	if _phase_acc >= M2_DURATION:
		print("[METALFLY] M2 complete (%.1fs), switching move" % _phase_acc)
		_begin_random_move()

func _spawn_blade_row() -> void:
	var y_oc := _boss_eo.global_position.y + _boss_eo.size.y + 4.0
	var spacing := OC_BOUNDS.size.x / float(M2_BLADES_PER_ROW)
	for i in M2_BLADES_PER_ROW:
		var x_oc := OC_BOUNDS.position.x + (float(i) + 0.5) * spacing
		var origin := Vector2(x_oc, y_oc)
		_spawn_blade(origin, Vector2(0.0, M2_BLADE_SPEED), M2_BLADE_DMG)

# ── Move 3: Sting Beam ─────────────────────────────────────────────────────────

func _begin_m3() -> void:
	_phase = Phase.ENTERING
	_phase_acc = 0.0
	var rx := randf_range(OC_BOUNDS.position.x + 50, OC_BOUNDS.end.x - 50 - _boss_eo.size.x)
	var ry := OC_BOUNDS.position.y + M3_ENTRY_Y_SS
	var tw := create_tween()
	tw.tween_property(_boss_eo, "position", Vector2(rx, ry), 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(func():
		_boss_eo.pivot_offset = _boss_eo.size / 2.0
		_phase = Phase.M3_ROT
		_phase_acc = 0.0
		_m3_target_cx_oc = _ship_aim_point_oc().x
	)

func _tick_m3_rot(delta: float) -> void:
	_phase_acc += delta
	var t := minf(_phase_acc / M3_ROT_T, 1.0)
	_boss_eo.rotation = lerp(0.0, PI / 2.0, t)
	if t >= 1.0:
		_boss_eo.rotation = PI / 2.0
		_phase = Phase.M3_MOVE
		_phase_acc = 0.0
		_m3_target_cx_oc = _ship_aim_point_oc().x

func _tick_m3_move(delta: float) -> void:
	var fp_dx := _get_fp1_world().x - _boss_eo.position.x
	var target_oc_x := clampf(_m3_target_cx_oc - fp_dx,
		OC_BOUNDS.position.x, OC_BOUNDS.end.x - _boss_eo.size.x)
	var target_y := clampf(M3_ENTRY_Y_SS + SS_OFFSET.y - _boss_eo.size.y / 2.0,
		OC_BOUNDS.position.y, OC_BOUNDS.end.y - _boss_eo.size.y)
	var target_oc := Vector2(target_oc_x, target_y)
	var diff := target_oc - _boss_eo.position
	var step := M3_MOVE_SPD * delta
	if diff.length() <= maxf(step, 3.0):
		_boss_eo.position = target_oc
		_phase = Phase.M3_WARN
		_phase_acc = 0.0
		_laser_flash_acc = 0.0
		_laser_hit_done = false
		_spawn_laser()
	else:
		_boss_eo.position += diff.normalized() * step

func _tick_m3_warn(delta: float) -> void:
	_phase_acc += delta
	_laser_flash_acc += delta
	_update_laser_pos()
	queue_redraw()
	if is_instance_valid(_laser_tr):
		_laser_tr.visible = fmod(_laser_flash_acc, M3_LASER_FLASH_CYC * 2.0) < M3_LASER_FLASH_CYC
	if _phase_acc >= M3_WARN_T:
		_phase = Phase.M3_FIRE
		_phase_acc = 0.0
		_laser_w = M3_LASER_W * M3_LASER_FIRE_MULT
		if is_instance_valid(_laser_tr):
			_laser_tr.visible = true
			_laser_tr.modulate = Color.WHITE
		queue_redraw()

func _tick_m3_fire(delta: float) -> void:
	_phase_acc += delta
	_update_laser_pos()
	if not _laser_hit_done and is_instance_valid(_ship_eo):
		var fp := _get_fp1_world()
		var laser_rect := Rect2(fp.x - _laser_w / 2.0, fp.y, _laser_w, OC_BOUNDS.end.y - fp.y)
		if laser_rect.intersects(_ship_hit_rect_oc()):
			GameManager.ship_take_damage(int(round(M3_LASER_DMG * BOSS_DAMAGE_MULT)))
			_laser_hit_done = true
	if _phase_acc >= M3_FIRE_T:
		print("[METALFLY] M3 laser complete (%.1fs), switching move" % _phase_acc)
		_free_laser()
		_begin_random_move()

func _spawn_laser() -> void:
	if not is_instance_valid(_boss_eo):
		return

	var fp := _get_fp1_world()
	_laser_tr = TextureRect.new()
	_laser_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_laser_tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var laser_tex := _laser_frames[0] as Texture2D if not _laser_frames.is_empty() else null
	if laser_tex != null:
		_laser_tr.texture = laser_tex
	_laser_tr.position = fp - OC_BOUNDS.position - Vector2(_laser_w / 2.0, 0)
	_laser_tr.size = Vector2(_laser_w, OC_BOUNDS.end.y - fp.y)
	_laser_tr.modulate = M3_LASER_WARN_MOD
	_clip_node.add_child(_laser_tr)

func _update_laser_pos() -> void:
	if not is_instance_valid(_laser_tr) or not is_instance_valid(_boss_eo):
		return
	var fp := _get_fp1_world()
	_laser_tr.position = fp - OC_BOUNDS.position - Vector2(_laser_w / 2.0, 0)
	_laser_tr.size = Vector2(_laser_w, OC_BOUNDS.end.y - fp.y)

func _free_laser() -> void:
	if is_instance_valid(_laser_tr):
		_laser_tr.queue_free()
		_laser_tr = null

# ── Move 4: Dive Scatter ───────────────────────────────────────────────────────

func _begin_m4() -> void:
	_phase = Phase.M4_ENTRY
	_phase_acc = 0.0
	var center_x := OC_BOUNDS.get_center().x - _boss_eo.size.x / 2.0
	var top_y := OC_BOUNDS.position.y - _boss_eo.size.y
	var entry_y := OC_BOUNDS.position.y + 20.0
	_m4_top_x = center_x
	_boss_eo.position = Vector2(center_x, top_y)
	_boss_eo.visible = true
	var tw := create_tween()
	tw.tween_property(_boss_eo, "position", Vector2(center_x, entry_y), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(func():
		_phase = Phase.M4_DIVE
		_phase_acc = 0.0
		_m4_ship_target_y = _ship_aim_point_oc().y - _boss_eo.size.y / 2.0
	)

func _tick_m4(delta: float) -> void:
	match _phase:
		Phase.M4_ENTRY:
			pass
		Phase.M4_DIVE:
			_tick_m4_dive(delta)
		Phase.M4_SCATTER:
			pass
		Phase.M4_RETREAT:
			_tick_m4_retreat(delta)

func _tick_m4_dive(delta: float) -> void:
	var ship_pt := _ship_aim_point_oc()
	var dir := (ship_pt - (_boss_eo.position + _boss_eo.size / 2.0)).normalized()
	_boss_eo.position += dir * M4_DIVE_SPD * delta
	_clamp_boss()

	var boss_center_y := _boss_eo.position.y + _boss_eo.size.y / 2.0
	if boss_center_y >= _m4_ship_target_y:
		_phase = Phase.M4_SCATTER
		_phase_acc = 0.0
		_fire_scatter()
		_phase = Phase.M4_RETREAT
		_phase_acc = 0.0

func _fire_scatter() -> void:
	var origin := _get_fp1_world()
	print("[METALFLY] M4: Scatter burst %d shards from (%.0f, %.0f)" % [M4_SCATTER_COUNT, origin.x, origin.y])
	var base_angle := PI / 2.0
	for i in M4_SCATTER_COUNT:
		var spread := -M4_SCATTER_SPREAD + float(i) * (2.0 * M4_SCATTER_SPREAD / float(M4_SCATTER_COUNT - 1))
		var dir := Vector2.from_angle(base_angle + spread)
		_spawn_shard(origin, dir * M4_SCATTER_SPEED, M4_SCATTER_DMG)

func _tick_m4_retreat(delta: float) -> void:
	var retreat_target := Vector2(_m4_top_x, OC_BOUNDS.position.y - _boss_eo.size.y - 20.0)
	var diff := retreat_target - _boss_eo.position
	if diff.length() <= M4_RETREAT_SPD * delta + 5.0:
		_boss_eo.position = retreat_target
		_boss_eo.visible = false
		_begin_random_move()
	else:
		_boss_eo.position += diff.normalized() * M4_RETREAT_SPD * delta

# ── Move 5: Needle Storm ───────────────────────────────────────────────────────

func _begin_m5() -> void:
	_phase = Phase.M5_HOVER
	_phase_acc = 0.0
	_m5_acc = 0.0
	_m5_needle_acc = 0.0

func _tick_m5(delta: float) -> void:
	match _phase:
		Phase.M5_HOVER:
			_tick_m5_hover(delta)
		Phase.M5_STORM:
			_tick_m5_storm(delta)

func _tick_m5_hover(delta: float) -> void:
	var target_y := M5_HOVER_Y_SS + SS_OFFSET.y - _boss_eo.size.y / 2.0
	var target_x := OC_BOUNDS.get_center().x - _boss_eo.size.x / 2.0
	var target := Vector2(target_x, target_y)
	_boss_eo.position = _boss_eo.position.lerp(target, M5_HOVER_LERP * delta)
	_clamp_boss()
	if _boss_eo.position.distance_to(target) < 8.0:
		_boss_eo.position = target
		_phase = Phase.M5_STORM
		_phase_acc = 0.0
		_m5_acc = 0.0
		_m5_needle_acc = 0.0

func _tick_m5_storm(delta: float) -> void:
	_phase_acc    += delta
	_m5_acc       += delta
	_m5_needle_acc += delta

	while _m5_needle_acc >= M5_NEEDLE_INT:
		_m5_needle_acc -= M5_NEEDLE_INT
		_fire_needle()

	if _phase_acc >= M5_DURATION:
		print("[METALFLY] M5 complete (%.1fs), switching move" % _phase_acc)
		_begin_random_move()

func _fire_needle() -> void:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var origin := _get_fp1_world()
	var ship_pt := _ship_aim_point_oc()
	var dir := (ship_pt - origin).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN

	print("[METALFLY] M5: Needle from (%.0f, %.0f) → (%.0f, %.0f)" % [origin.x, origin.y, ship_pt.x, ship_pt.y])
	var tex := _needle_frames[0] as Texture2D if not _needle_frames.is_empty() else null
	var sz := M5_NEEDLE_SIZE
	var local_pos := origin - OC_BOUNDS.position - sz / 2.0
	var tr := _make_projectile_rect(tex if tex else _make_fallback_needle_tex(), sz, local_pos)
	_projectiles.append({
		"tr": tr, "vel": dir * M5_NEEDLE_SPEED,
		"rot_spd": 0.0, "rot": 0.0, "dmg": M5_NEEDLE_DMG, "type": "needle",
		"frames": _needle_frames, "delays": _needle_delays, "frame": 0, "acc": 0.0,
		"blink_acc": 0.0,
	})

# ── Projectile helpers ─────────────────────────────────────────────────────────

func _spawn_shard(origin_oc: Vector2, vel: Vector2, dmg: int) -> void:
	var tex := _shard_frames[0] as Texture2D if not _shard_frames.is_empty() else _make_fallback_shard_tex()
	var sz := M1_SHARD_SIZE
	var local_pos := origin_oc - OC_BOUNDS.position - sz / 2.0
	var tr := _make_projectile_rect(tex, sz, local_pos)
	_projectiles.append({
		"tr": tr, "vel": vel,
		"rot_spd": 0.0, "rot": 0.0, "dmg": dmg, "type": "shard",
		"frames": _shard_frames, "delays": _shard_delays, "frame": 0, "acc": 0.0,
		"blink_acc": 0.0,
	})

func _spawn_blade(origin_oc: Vector2, vel: Vector2, dmg: int) -> void:
	var tex := _blade_frames[0] as Texture2D if not _blade_frames.is_empty() else _make_fallback_blade_tex()
	var sz := M2_BLADE_SIZE
	var local_pos := origin_oc - OC_BOUNDS.position - sz / 2.0
	var tr := _make_projectile_rect(tex, sz, local_pos)
	_projectiles.append({
		"tr": tr, "vel": vel,
		"rot_spd": M2_BLADE_ROT_SPD, "rot": 0.0, "dmg": dmg, "type": "blade",
		"frames": _blade_frames, "delays": _blade_delays, "frame": 0, "acc": 0.0,
		"blink_acc": 0.0,
	})

func _make_projectile_rect(tex: Texture2D, sz: Vector2, pos: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.position = pos
	tr.size = sz
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.z_index = 1
	tr.pivot_offset = tr.size / 2.0
	_clip_node.add_child(tr)
	return tr

func _tick_projectiles(delta: float) -> void:
	var clip_local := Rect2(Vector2.ZERO, _clip_node.size).grow(60.0)
	var i := 0
	while i < _projectiles.size():
		var p = _projectiles[i]
		var tr: TextureRect = p["tr"]
		var vel: Vector2 = p["vel"]
		var rot_spd: float = p["rot_spd"]
		var dmg: int = p["dmg"]
		var ptype: String = p["type"]
		var frames: Array = p["frames"]
		var delays: Array = p["delays"]

		if not is_instance_valid(tr):
			_projectiles.remove_at(i)
			continue

		tr.position += vel * delta
		if rot_spd != 0.0:
			p["rot"] += rot_spd * delta
			tr.rotation = p["rot"]

		if not frames.is_empty():
			p["acc"] += delta
			var frame_time: float = delays[p["frame"]] if p["frame"] < delays.size() else 0.05
			while p["acc"] >= frame_time and not frames.is_empty():
				p["acc"] -= frame_time
				p["frame"] = (p["frame"] + 1) % frames.size()
				tr.texture = frames[p["frame"]]
				frame_time = delays[p["frame"]] if p["frame"] < delays.size() else 0.05

		if clip_local.has_point(tr.position):
			if is_instance_valid(_ship_eo):
				var ship_hit := _ship_hit_rect_oc()
				if ship_hit.has_point(tr.position):
					print("[METALFLY] %s HIT SHIP for %d dmg" % [ptype, dmg])
					GameManager.ship_take_damage(int(round(dmg * BOSS_DAMAGE_MULT)))
					_flash_ship_red()
					_projectiles.remove_at(i)
					continue
			i += 1
		else:
			_projectiles.remove_at(i)

func _make_fallback_shard_tex() -> Texture2D:
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.7, 0.8, 0.9))
	return ImageTexture.create_from_image(img)

func _make_fallback_blade_tex() -> Texture2D:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.7, 0.8))
	return ImageTexture.create_from_image(img)

func _make_fallback_needle_tex() -> Texture2D:
	var img := Image.create(4, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.9, 1.0))
	return ImageTexture.create_from_image(img)

# ── Setup helpers ──────────────────────────────────────────────────────────────

func _find_eos() -> void:
	for child in _objects_container.get_children():
		var eo := child as EditableObjectNode
		if eo == null:
			continue
		var base := eo.source_path.get_file().get_basename().to_lower()
		match base:
			"spaceship": _ship_eo = eo
			"metalfly":  _boss_eo = eo
			"cocoon": _cocoon_eo = eo
	# Hide metalfly initially (show only cocoon in phase 1)
	if is_instance_valid(_boss_eo):
		_boss_eo.visible = false
	_cache_ship_image()

func _load_fp_offsets() -> void:
	if _boss_eo == null:
		return
	var boss_center := _boss_eo.global_position + _boss_eo.size / 2.0
	var cfg := ConfigFile.new()
	if cfg.load("res://boss_layout.cfg") != OK:
		return
	for fp: Dictionary in cfg.get_value("firepoints", "metalfly", []):
		if int(fp.get("id", 0)) == 1:
			var fp_oc: Vector2 = (fp.get("pos", Vector2.ZERO) as Vector2) + SS_OFFSET
			_fp1_off = fp_oc - boss_center
	if _fp1_off == Vector2.ZERO and _boss_eo != null:
		_fp1_off = Vector2(0.0, _boss_eo.size.y / 2.0)
	_fp1_node = Node2D.new()
	_fp1_node.position = _boss_eo.size / 2.0 + _fp1_off
	_boss_eo.add_child(_fp1_node)

func _get_fp1_world() -> Vector2:
	if _boss_eo == null:
		return Vector2.ZERO
	if _fp1_node != null and is_instance_valid(_fp1_node):
		return _fp1_node.global_position
	return _boss_eo.global_position + _boss_eo.size / 2.0 + _fp1_off.rotated(_boss_eo.rotation)

func _load_assets() -> void:
	var st := GifLoader.load_gif("res://assets/bosses/metalfly/shard.gif")
	if st != null:
		_shard_frames = st.get_meta("gif_frames") if st.has_meta("gif_frames") else [st]
		_shard_delays = st.get_meta("gif_delays") if st.has_meta("gif_delays") else [0.05]

	var bt := GifLoader.load_gif("res://assets/bosses/metalfly/blade.gif")
	if bt != null:
		_blade_frames = bt.get_meta("gif_frames") if bt.has_meta("gif_frames") else [bt]
		_blade_delays = bt.get_meta("gif_delays") if bt.has_meta("gif_delays") else [0.05]

	var nt := GifLoader.load_gif("res://assets/bosses/metalfly/needle.gif")
	if nt != null:
		_needle_frames = nt.get_meta("gif_frames") if nt.has_meta("gif_frames") else [nt]
		_needle_delays = nt.get_meta("gif_delays") if nt.has_meta("gif_delays") else [0.05]

	var lt := GifLoader.load_gif("res://assets/bosses/elephant/laser.gif")
	if lt != null:
		_laser_frames = lt.get_meta("gif_frames") if lt.has_meta("gif_frames") else [lt]

func _cache_ship_image() -> void:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var tex := _ship_eo.texture_rect.texture
	if tex == null:
		return
	_ship_img = tex.get_image()
	if _ship_img == null:
		return
	_compute_tight_uv()

func _compute_tight_uv() -> void:
	if _ship_img == null or _ship_img.is_empty():
		_ship_alpha_uv = Rect2(0.0, 0.0, 1.0, 1.0)
		return
	var w := _ship_img.get_width()
	var h := _ship_img.get_height()
	var left := w
	var right := 0
	var top := h
	var bottom := 0
	for y in range(h):
		for x in range(w):
			var col := _ship_img.get_pixel(x, y)
			if col.a > 0.5:
				left = mini(left, x)
				right = maxi(right, x)
				top = mini(top, y)
				bottom = maxi(bottom, y)
	if left <= right and top <= bottom:
		_ship_alpha_uv = Rect2(float(left) / float(w), float(top) / float(h),
			float(right - left + 1) / float(w), float(bottom - top + 1) / float(h))
	else:
		_ship_alpha_uv = Rect2(0.0, 0.0, 1.0, 1.0)

func _ship_hit_rect_oc() -> Rect2:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return Rect2()
	var pos := _ship_eo.position
	var sz := _ship_eo.size * _ship_alpha_uv.size
	var off := _ship_eo.size * _ship_alpha_uv.position
	return Rect2(pos + off, sz)

func _ship_aim_point_oc() -> Vector2:
	if _ship_eo == null:
		return OC_BOUNDS.get_center()
	return _ship_eo.position + _ship_eo.size / 2.0

func _cleanup_projectiles() -> void:
	for p in _projectiles:
		var tr: TextureRect = p["tr"]
		if is_instance_valid(tr):
			tr.queue_free()
	_projectiles.clear()

func _flash_ship_red() -> void:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	_ship_eo.modulate = Color(1.5, 0.5, 0.5)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(_ship_eo):
		_ship_eo.modulate = Color.WHITE

func _tick_cocoon_movement(delta: float) -> void:
	if not is_instance_valid(_cocoon_eo):
		return

	# Update direction timer
	_cocoon_direction_timer -= delta
	if _cocoon_direction_timer <= 0.0:
		# Pick random direction (8 directions + sometimes stay)
		var angle := randf() * TAU
		_cocoon_velocity = Vector2(cos(angle), sin(angle)) * COCOON_SPEED
		_cocoon_direction_timer = COCOON_DIRECTION_CHANGE_INTERVAL

	# Move cocoon
	_cocoon_eo.position += _cocoon_velocity * delta

	# Clamp to screen bounds
	var bounds := OC_BOUNDS
	_cocoon_eo.position.x = clampf(_cocoon_eo.position.x, bounds.position.x, bounds.end.x - _cocoon_eo.size.x)
	_cocoon_eo.position.y = clampf(_cocoon_eo.position.y, bounds.position.y, bounds.end.y - _cocoon_eo.size.y)

func _clamp_boss() -> void:
	if _boss_eo == null:
		return
	_boss_eo.position.x = clampf(_boss_eo.position.x, OC_BOUNDS.position.x, OC_BOUNDS.end.x - _boss_eo.size.x)
	_boss_eo.position.y = clampf(_boss_eo.position.y, OC_BOUNDS.position.y, OC_BOUNDS.end.y - _boss_eo.size.y)

func notify_boss_killed() -> void:
	if _phase != Phase.IDLE and _phase != Phase.DONE:
		if _boss_phase == 1 and not _forced_kill:
			# Phase 1 → Phase 2 transition
			print("[METALFLY] Phase 1 DEFEATED - triggering Transform animation")
			_phase = Phase.IDLE
			_trigger_phase_transition()
		else:
			# Phase 2 death or forced kill
			var won := not _forced_kill
			print("[METALFLY] Phase 2 DEFEATED - forced=%s, showing victory=%s" % [_forced_kill, won])
			_force_reset()
			if won:
				_show_victory_screen()
	_forced_kill = false

func notify_hp_changed(new_hp: int) -> void:
	if new_hp < _last_hp and _phase != Phase.IDLE and _phase != Phase.DONE:
		_flash_damage()
	_last_hp = new_hp

func _flash_damage() -> void:
	var target_eo: EditableObjectNode = null
	if _boss_phase == 1:
		target_eo = _cocoon_eo
	else:
		target_eo = _boss_eo

	if not is_instance_valid(target_eo):
		return

	if _flash_tween:
		_flash_tween.kill()

	_flash_tween = create_tween()
	_flash_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_flash_tween.tween_property(target_eo, "self_modulate", Color.RED, 0.05)
	_flash_tween.tween_property(target_eo, "self_modulate", Color.WHITE, 0.1)

func _trigger_phase_transition() -> void:
	if not is_instance_valid(_cocoon_eo):
		# Fallback: skip animation, go straight to phase 2
		_begin_phase2()
		return

	# Show Transform animation (cocoon.gif transformation)
	print("[METALFLY] Transform animation (cocoon → metalfly) starting...")
	_cocoon_eo.visible = true
	_transform_anim_acc = 0.0

	# Animate cocoon: scale down then disappear
	var tw := create_tween()
	tw.tween_property(_cocoon_eo, "modulate:a", 0.5, 0.5)
	tw.tween_property(_cocoon_eo, "scale", Vector2(0.8, 0.8), 0.5)
	tw.finished.connect(func():
		print("[METALFLY] Transform animation complete - entering Phase 2")
		_cocoon_eo.visible = false
		_begin_phase2()
	)

func _begin_phase2() -> void:
	_boss_phase = 2
	print("[METALFLY] Phase 2 (METALFLY) starting, HP=%d" % PHASE2_MAX_HP)
	GameManager.boss_max_hp = PHASE2_MAX_HP
	GameManager.boss_hp = PHASE2_MAX_HP
	_last_hp = PHASE2_MAX_HP
	GameManager.boss_hp_changed.emit(PHASE2_MAX_HP)
	start_fight()

func _force_reset() -> void:
	_cleanup_projectiles()
	_free_laser()
	if is_instance_valid(_boss_eo):
		_boss_eo.visible = false
		_boss_eo.rotation = 0.0
		_boss_eo.scale = Vector2.ONE
	_phase = Phase.IDLE
	_phase_acc = 0.0

func _show_victory_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			layer.queue_free()
	)
	layer.add_child(dim)

	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile

	var title := Label.new()
	title.text = "METALFLY DESTROYED"
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font:
		title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	layer.add_child(title)

	var hint := Label.new()
	hint.text = "Click to continue"
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.offset_top = 60.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font:
		hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	layer.add_child(hint)
