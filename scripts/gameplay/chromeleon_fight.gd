extends Control

const SS_OFFSET := Vector2(270.0, 8.0)
const OC_BOUNDS := Rect2(270.0, 8.0, 700.0, 764.0)
const GifLoader  := preload("res://scripts/ui/edit_mode/gif_loader.gd")

# Viewport-space limits (screen-local + SS_OFFSET)
const Y_LIMIT       := 458.0   # 450 screen-local + 8
const BALL_SPIN_POS := Vector2(620.0, 158.0)   # (350,150) screen-local

# Final patrol waypoints (viewport space)
const TEAL_WP_A := Vector2(920.0, 158.0)   # (650,150)
const TEAL_WP_B := Vector2(320.0, 158.0)   # (50,150)
const BLUE_WP_A := Vector2(320.0, 108.0)   # (50,100)
const BLUE_WP_B := Vector2(920.0, 108.0)   # (650,100)

# Bullet wave spawn (viewport space)
const WAVE_Y     := 58.0
const WAVE_X_MIN := 280.0
const WAVE_X_MAX := 920.0

const BOSS_MAX_HP := 1500
const ORB_MAX_HP  := 1000

const M1_SPEED     := 120.0
const M1_SHOOT_INT := 0.5
const M1_FP2_DELAY := 0.25
const M1_MIN_DUR   := 6.0
const M1_MAX_DUR   := 10.0

const M2_MOVE_SPD  := 150.0
const M2_MOVE_RPM  := 40.0
const M2_SPIN_RPM  := 80.0
const M2_SPINUP_T  := 3.0
const M2_SHOOT_INT := 0.334

const M3_BODY_SPD  := 25.0
const M3_BODY_RPM  := 20.0
const M3_ORB_SPD   := 90.0
const M3_ORB_SHOOT := 0.25
const M3_SNAP_DUR  := 0.1875
const M3_SNAP_MIN  := 0.5
const M3_SNAP_MAX  := 1.5
const M3_DURATION  := 10.0
const M3_RECALL_T  := 1.2

const M4_MOVE_SPD   := 150.0
const M4_MOVE_RPM   := 40.0
const M4_SPIN_RPM   := 80.0
const M4_SPINUP_T   := 2.0
const M4_CHARGE_SPD := 120.0
const M4_HIT_DMG    := 40
const M4_RETURN_T   := 1.5

const FINAL_HEAD_SPD  := 25.0
const FINAL_HEAD_RPM  := 20.0
const FINAL_ORB_RPM   := 40.0
const FINAL_ORB_SHOOT := 0.25
const PATROL_SPD      := 120.0

const SUB1_DUR     := 8.0
const SUB2_DUR     := 3.0
const SUB2_WAVE_INT := 0.5
const SUB2_BLT_HP  := 10
const SUB2_BLT_CNT := 10
const SUB3_DUR     := 5.0
const SUB3_RAND_INT := 0.25
const SUB3_ORB_INT  := 0.5

const BULLET_SPD     := 280.0
const ORB_BULLET_SPD := 250.0
const WAVE_SPD_MIN   := 100.0
const WAVE_SPD_MAX   := 150.0

enum Phase {
	IDLE,
	M1_CRAWL,
	M2_TRANSFORM, M2_MOVE, M2_SPIN, M2_RETURN,
	M3_ACTIVE, M3_RECALL,
	M4_TRANSFORM, M4_MOVE, M4_SPIN, M4_CHARGE, M4_RETURN_CURVE, M4_RETURN,
	FINAL_ENTRY, FINAL_SUB1, FINAL_SUB2, FINAL_SUB3,
	DONE
}

var _phase        := Phase.IDLE
var _phase_timer  := 0.0

var _objects_container: Control          = null
var _ship_eo:           EditableObjectNode = null
var _chromeleon_eo:     EditableObjectNode = null
var _chromeleonbody_eo: EditableObjectNode = null
var _chromehead_eo:     EditableObjectNode = null
var _chromeball_eo:     EditableObjectNode = null
var _blueorb_eo:        EditableObjectNode = null
var _tealorb_eo:        EditableObjectNode = null
var _ball_orig_local_pos: Vector2 = Vector2.ZERO

var _blueorb_hp:    int  = ORB_MAX_HP
var _tealorb_hp:    int  = ORB_MAX_HP
var _orbs_detached: bool = false
var _ball_detached: bool = false

var _main_fp_nodes: Array[Node2D] = []
var _ball_fp_nodes: Array[Node2D] = []
var _blue_fp_nodes: Array[Node2D] = []
var _teal_fp_nodes: Array[Node2D] = []
var _ball_fp_offset: Vector2 = Vector2.ZERO
var _blue_fp_offset: Vector2 = Vector2.ZERO
var _teal_fp_offset: Vector2 = Vector2.ZERO

var _clip_node: Control = null

var _assets_loaded:   bool  = false
var _bullet_frames:   Array = []
var _bullet_sizes:    Array = []   # Vector2 per chromebullet, matching _bullet_frames
var _bullet_native_sizes: Array = []  # native texture sizes for fallback
var _bullet_resized_frames: Array = []  # resized textures, cached per chromebullet
var _last_cb_idx:     int   = 0    # last random chromebullet index
var _ball_frames:     Array = []
var _ball_delays:     Array = []
var _blue_bullet_tex:  Texture2D = null
var _teal_bullet_tex:  Texture2D = null
var _blue_bullet_resized: Texture2D = null
var _teal_bullet_resized: Texture2D = null
var _blue_bullet_native_size: Vector2 = Vector2.ZERO
var _teal_bullet_native_size: Vector2 = Vector2.ZERO
var _blue_bullet_size: Vector2   = Vector2.ZERO
var _teal_bullet_size: Vector2   = Vector2.ZERO

var _projectiles:      Array = []
var _shielded_bullets: Array = []

# Body animation (chromeball gif forward/backward)
var _anim_tr:       TextureRect = null
var _anim_frames:   Array = []
var _anim_delays:   Array = []
var _anim_idx:      int   = 0
var _anim_acc:      float = 0.0
var _anim_backward: bool  = false
var _anim_hold:     bool  = false
var _anim_done:     bool  = false
var _anim_phase_timer: float = 0.0   # timeout guard for anim-waiting phases
signal anim_finished

# M1 state
var _m1_wp:           Vector2 = Vector2.ZERO
var _m1_shoot_acc:    float   = 0.0
var _m1_fp2_acc:      float   = 0.0
var _m1_fp2_pending:  bool    = false
var _m1_duration:     float   = 8.0

# Ball (M2/M4) state
var _ball_angle:   float = 0.0
var _spin_acc:     float = 0.0
var _m2_shoot_acc: float = 0.0

# M3 state
var _body_wp:   Vector2 = Vector2.ZERO
var _body_rot:  float   = 0.0
var _blue_wp:   Vector2 = Vector2.ZERO
var _teal_wp:   Vector2 = Vector2.ZERO
var _blue_rot:  float   = 0.0
var _teal_rot:  float   = 0.0
var _blue_snap_timer:  float = 0.0
var _teal_snap_timer:  float = 0.0
var _blue_snapping:    bool  = false
var _teal_snapping:    bool  = false
var _blue_shoot_acc:   float = 0.0
var _teal_shoot_acc:   float = 0.0

# M4 state
var _m4_charge_dir: Vector2 = Vector2.ZERO

# Final state
var _head_wp:           Vector2 = Vector2.ZERO
var _head_rot:          float   = 0.0
var _teal_fin_angle:    float   = 0.0
var _blue_fin_angle:    float   = 0.0
var _teal_patrol_tgt:   int     = 0   # 0=WP_A, 1=WP_B
var _blue_patrol_tgt:   int     = 0
var _teal_fin_shoot:    float   = 0.0
var _blue_fin_shoot:    float   = 0.0
var _sub2_wave_acc:     float   = 0.0
var _sub3_rand_b:       float   = 0.0
var _sub3_rand_t:       float   = 0.0
var _sub3_orb_b:        float   = 0.0
var _sub3_orb_t:        float   = 0.0

# =============================================================================
# Setup
# =============================================================================

func setup(oc: Control) -> void:
	_objects_container = oc
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("boss_fight")
	add_to_group("chromeleon_fight")

	var clip := Control.new()
	clip.position      = OC_BOUNDS.position
	clip.size          = OC_BOUNDS.size
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	clip.z_index       = 0
	clip.z_as_relative = false
	add_child(clip)
	_clip_node = clip

	_find_eos()
	_load_fp_offsets()
	_cache_fp_offsets()
	# _load_assets() is deferred to first spawn_boss() to avoid startup lag
	GameManager.boss_killed.connect(_on_boss_killed_ext)

func _on_boss_killed_ext() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	# Already in the final sub-phases — the main body HP hitting 0 is expected here;
	# let the orb fight run its course via _check_orb_win().
	match _phase:
		Phase.FINAL_ENTRY, Phase.FINAL_SUB1, Phase.FINAL_SUB2, Phase.FINAL_SUB3:
			return
	# M1-M4: player naturally depleted the body HP → begin final phase.
	_begin_final()

func _force_reset() -> void:
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	_reattach_orbs()
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_phase = Phase.IDLE
	_phase_timer = 0.0
	_orbs_detached = false
	_ball_detached = false
	var ws := _get_ws()
	if ws != null:
		ws.clear_extra_targets()
		ws.clear_multi_hit_provider()

# =============================================================================
# Public API
# =============================================================================

func spawn_boss() -> void:
	if _chromeleon_eo == null or not is_instance_valid(_chromeleon_eo):
		return
	if _phase != Phase.IDLE and _phase != Phase.DONE:
		return
	if not _assets_loaded:
		_load_assets()
		_assets_loaded = true
	_reload_bullet_sizes()
	GameManager.boss_max_hp = BOSS_MAX_HP
	GameManager.boss_hp     = BOSS_MAX_HP
	GameManager.boss_hp_changed.emit(BOSS_MAX_HP)
	GameManager.boss_spawned.emit()
	if not GameManager.manual_boost:
		GameManager.set_boost(true)
	_start_fight()

func kill_boss() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	_reattach_orbs()
	_reattach_ball()
	_show_only(null)
	_phase = Phase.IDLE
	_phase_timer = 0.0
	var ws := _get_ws()
	if ws != null:
		ws.clear_extra_targets()
		ws.clear_multi_hit_provider()
	GameManager.boss_hp     = 0
	GameManager.boss_max_hp = 0
	GameManager.boss_killed.emit()

func get_boss_hit_rect() -> Rect2:
	# Main phase: body takes damage. Final phase: chromehead takes damage (via direct hits).
	var eo: EditableObjectNode
	match _phase:
		Phase.FINAL_ENTRY, Phase.FINAL_SUB1, Phase.FINAL_SUB2, Phase.FINAL_SUB3:
			# Final phase: return chromehead hitbox for direct bullet hits
			eo = _chromehead_eo
		_:
			# M1-M4: return main body hitbox
			eo = _active_body()

	if eo == null or not is_instance_valid(eo) or not eo.visible:
		return Rect2()
	var tr: TextureRect = eo.texture_rect
	if tr == null:
		return Rect2(eo.global_position, eo.size)
	var sz := tr.size
	var xf := tr.get_global_transform()
	var p0 := xf * Vector2(0.0, 0.0); var p1 := xf * Vector2(sz.x, 0.0)
	var p2 := xf * Vector2(0.0, sz.y); var p3 := xf * Vector2(sz.x, sz.y)
	var mn := Vector2(minf(minf(p0.x,p1.x),minf(p2.x,p3.x)), minf(minf(p0.y,p1.y),minf(p2.y,p3.y)))
	var mx := Vector2(maxf(maxf(p0.x,p1.x),maxf(p2.x,p3.x)), maxf(maxf(p0.y,p1.y),maxf(p2.y,p3.y)))
	return Rect2(mn, mx - mn)

func flash_boss_hit() -> void:
	var eo := _active_body()
	if eo == null or not is_instance_valid(eo):
		return
	var tw := create_tween()
	tw.tween_property(eo, "modulate", Color(2.0, 0.5, 0.5, 1.0), 0.04)
	tw.tween_property(eo, "modulate", Color.WHITE, 0.15)

func _start_fight() -> void:
	_reattach_orbs()
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_blueorb_hp   = ORB_MAX_HP
	_tealorb_hp   = ORB_MAX_HP
	_body_rot     = 0.0
	_head_rot     = 0.0
	_setup_pivots()
	_begin_random_move()

func _setup_pivots() -> void:
	for eo: EditableObjectNode in [_chromeleonbody_eo, _chromehead_eo, _chromeball_eo, _blueorb_eo, _tealorb_eo]:
		if is_instance_valid(eo) and eo.texture_rect != null:
			eo.texture_rect.pivot_offset = eo.texture_rect.size / 2.0

# =============================================================================
# Move dispatch
# =============================================================================

func _begin_random_move() -> void:
	var r := randi() % 4
	if r == 0:
		_begin_m1()
	elif r == 1:
		_begin_m2()
	elif r == 2:
		_begin_m3()
	else:
		_begin_m4()

func _check_hp_or_next() -> void:
	if GameManager.boss_hp <= 0:
		_begin_final()
	else:
		_begin_random_move()

# =============================================================================
# Move 1 — Crawl + Shoot
# =============================================================================

func _begin_m1() -> void:
	_phase = Phase.M1_CRAWL
	_phase_timer  = 0.0
	_m1_shoot_acc = 0.0
	_m1_fp2_acc   = 0.0
	_m1_fp2_pending = false
	_m1_duration  = randf_range(M1_MIN_DUR, M1_MAX_DUR)
	_m1_wp        = _pick_crawl_wp()
	_show_only(_chromeleon_eo)

func _tick_m1(delta: float) -> void:
	_phase_timer  += delta
	_m1_shoot_acc += delta

	if is_instance_valid(_chromeleon_eo):
		var diff := _m1_wp - _chromeleon_eo.position
		if diff.length() < M1_SPEED * delta + 5.0:
			_m1_wp = _pick_crawl_wp()
		else:
			_chromeleon_eo.position += diff.normalized() * M1_SPEED * delta
		_clamp_eo(_chromeleon_eo, Y_LIMIT)

	if _m1_fp2_pending:
		_m1_fp2_acc += delta
		if _m1_fp2_acc >= M1_FP2_DELAY:
			_m1_fp2_pending = false
			_fire_m1_spread(1)

	if _m1_shoot_acc >= M1_SHOOT_INT:
		_m1_shoot_acc = 0.0
		_fire_m1_spread(0)
		_m1_fp2_acc = 0.0
		_m1_fp2_pending = true

	if _phase_timer >= _m1_duration:
		_check_hp_or_next()

func _fire_m1_spread(fp_idx: int) -> void:
	if _main_fp_nodes.size() <= fp_idx:
		return
	var fp := _main_fp_nodes[fp_idx]
	if not is_instance_valid(fp):
		return
	var origin := fp.global_position
	var tex := _random_bullet()
	var bsz  := _random_bullet_sz()
	for a: float in [-30.0, 0.0, 30.0]:
		var dir := Vector2.DOWN.rotated(deg_to_rad(a))
		_spawn_bullet(tex, origin, dir * BULLET_SPD, bsz)

# =============================================================================
# Move 2 — Ball spin + shoot 4 dirs
# =============================================================================

func _begin_m2() -> void:
	_phase = Phase.M2_TRANSFORM
	_phase_timer  = 0.0
	_ball_angle   = 0.0
	_spin_acc     = 0.0
	_m2_shoot_acc = 0.0
	_anim_phase_timer = 0.0
	_detach_ball()
	_show_only(null)
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.gif_paused = true   # pause before visible so no rogue GIF frame shows
		_chromeball_eo.reset_gif()
		_chromeball_eo.texture_rect.pivot_offset = _chromeball_eo.texture_rect.size / 2.0
		_chromeball_eo.visible = true
		if not _ball_frames.is_empty():
			_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, false, true)
			anim_finished.connect(_on_m2_transform_done, CONNECT_ONE_SHOT)
		else:
			_on_m2_transform_done()

func _on_m2_transform_done() -> void:
	if _phase != Phase.M2_TRANSFORM:
		return
	_phase = Phase.M2_MOVE

func _tick_m2_move(delta: float) -> void:
	_phase_timer += delta
	_ball_angle  += M2_MOVE_RPM * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
		var target := BALL_SPIN_POS - _chromeball_eo.size / 2.0
		var diff   := target - _chromeball_eo.position
		if diff.length() < M2_MOVE_SPD * delta + 3.0:
			_chromeball_eo.position = target
			_phase    = Phase.M2_SPIN
			_spin_acc = 0.0

func _tick_m2_spin(delta: float) -> void:
	_phase_timer  += delta
	_spin_acc     += delta
	_m2_shoot_acc += delta
	var t: float   = minf(_spin_acc / M2_SPINUP_T, 1.0)
	var rpm: float = lerpf(M2_MOVE_RPM, M2_SPIN_RPM, t)
	_ball_angle += rpm * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
	if _m2_shoot_acc >= M2_SHOOT_INT:
		_m2_shoot_acc = 0.0
		_fire_ball_4dirs()
	if _spin_acc >= M2_SPINUP_T:
		_begin_m2_return()

func _begin_m2_return() -> void:
	_phase = Phase.M2_RETURN
	_anim_phase_timer = 0.0
	if is_instance_valid(_chromeball_eo) and not _ball_frames.is_empty():
		_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, true, true)
		anim_finished.connect(_on_m2_return_done, CONNECT_ONE_SHOT)
	else:
		_on_m2_return_done()

func _on_m2_return_done() -> void:
	if _phase != Phase.M2_RETURN:
		return
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_check_hp_or_next()

# =============================================================================
# Move 3 — Orb detach
# =============================================================================

func _begin_m3() -> void:
	_phase = Phase.M3_ACTIVE
	_phase_timer = 0.0
	_detach_orbs()
	_show_only(_chromeleonbody_eo)
	_blueorb_eo.visible = true
	_tealorb_eo.visible = true
	_body_wp = _pick_wander_wp(Y_LIMIT)
	_blue_wp = _pick_wander_wp(Y_LIMIT)
	_teal_wp = _pick_wander_wp(Y_LIMIT)
	_blue_snap_timer = randf_range(M3_SNAP_MIN, M3_SNAP_MAX)
	_teal_snap_timer = randf_range(M3_SNAP_MIN, M3_SNAP_MAX)
	_blue_snapping = false
	_teal_snapping = false
	_blue_shoot_acc = 0.0
	_teal_shoot_acc = 0.0

func _tick_m3(delta: float) -> void:
	_phase_timer += delta

	# Chromeleonbody drift
	if is_instance_valid(_chromeleonbody_eo):
		_body_wp = _tick_wander(_chromeleonbody_eo, _body_wp, delta, M3_BODY_SPD, Y_LIMIT)
		_body_rot += M3_BODY_RPM * TAU / 60.0 * delta
		_chromeleonbody_eo.texture_rect.rotation = _body_rot

	# Orb snap rotation + movement + shooting
	_tick_orb_m3(_blueorb_eo, delta, true)
	_tick_orb_m3(_tealorb_eo, delta, false)

	if _phase_timer >= M3_DURATION:
		_begin_m3_recall()

func _tick_orb_m3(eo: EditableObjectNode, delta: float, is_blue: bool) -> void:
	if eo == null or not is_instance_valid(eo):
		return

	# Wander
	if is_blue:
		_blue_wp = _tick_wander(eo, _blue_wp, delta, M3_ORB_SPD, Y_LIMIT)
	else:
		_teal_wp = _tick_wander(eo, _teal_wp, delta, M3_ORB_SPD, Y_LIMIT)

	# Snap rotation
	if is_blue:
		if not _blue_snapping:
			_blue_snap_timer -= delta
			if _blue_snap_timer <= 0.0:
				_blue_snap_timer = randf_range(M3_SNAP_MIN, M3_SNAP_MAX)
				var sign := 1.0 if randi() % 2 == 0 else -1.0
				var target := _blue_rot + sign * PI / 2.0
				_blue_snapping = true
				var tw := create_tween()
				tw.tween_method(func(v: float) -> void: _blue_rot = v, _blue_rot, target, M3_SNAP_DUR)
				tw.tween_callback(func() -> void: _blue_snapping = false)
		eo.texture_rect.rotation = _blue_rot
	else:
		if not _teal_snapping:
			_teal_snap_timer -= delta
			if _teal_snap_timer <= 0.0:
				_teal_snap_timer = randf_range(M3_SNAP_MIN, M3_SNAP_MAX)
				var sign := 1.0 if randi() % 2 == 0 else -1.0
				var target := _teal_rot + sign * PI / 2.0
				_teal_snapping = true
				var tw := create_tween()
				tw.tween_method(func(v: float) -> void: _teal_rot = v, _teal_rot, target, M3_SNAP_DUR)
				tw.tween_callback(func() -> void: _teal_snapping = false)
		eo.texture_rect.rotation = _teal_rot

	# Shoot (absolute directions, FP rotates for spawn origin)
	if is_blue:
		_blue_shoot_acc += delta
		if _blue_shoot_acc >= M3_ORB_SHOOT:
			_blue_shoot_acc = 0.0
			_fire_orb_nsew(eo, _blue_fp_offset, _blue_rot, _blue_bullet_resized if _blue_bullet_resized != null else _blue_bullet_tex,
				[Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT], _blue_bullet_size)
	else:
		_teal_shoot_acc += delta
		if _teal_shoot_acc >= M3_ORB_SHOOT:
			_teal_shoot_acc = 0.0
			_fire_orb_nsew(eo, _teal_fp_offset, _teal_rot, _teal_bullet_resized if _teal_bullet_resized != null else _teal_bullet_tex,
				[Vector2(-1,-1).normalized(), Vector2(1,-1).normalized(),
				 Vector2(-1,1).normalized(), Vector2(1,1).normalized()], _teal_bullet_size)

func _begin_m3_recall() -> void:
	_phase = Phase.M3_RECALL
	_phase_timer = 0.0
	if not (is_instance_valid(_chromeleonbody_eo) and is_instance_valid(_blueorb_eo) and is_instance_valid(_tealorb_eo)):
		_finish_m3_recall()
		return
	var tgt := _chromeleonbody_eo.global_position + _chromeleonbody_eo.size / 2.0
	var oc_gp := _objects_container.global_position
	if _blueorb_eo.get_parent() == _objects_container:
		var tw := create_tween()
		tw.tween_property(_blueorb_eo, "position",
			tgt - oc_gp - _blueorb_eo.size / 2.0, M3_RECALL_T).set_ease(Tween.EASE_IN)
	if _tealorb_eo.get_parent() == _objects_container:
		var tw2 := create_tween()
		tw2.tween_property(_tealorb_eo, "position",
			tgt - oc_gp - _tealorb_eo.size / 2.0, M3_RECALL_T).set_ease(Tween.EASE_IN)

func _tick_m3_recall(delta: float) -> void:
	_phase_timer += delta
	if _phase_timer >= M3_RECALL_T + 0.15:
		_finish_m3_recall()

func _finish_m3_recall() -> void:
	_reattach_orbs()
	_show_only(_chromeleon_eo)
	_check_hp_or_next()

# =============================================================================
# Move 4 — Ball charge at player
# =============================================================================

func _begin_m4() -> void:
	_phase = Phase.M4_TRANSFORM
	_phase_timer = 0.0
	_ball_angle  = 0.0
	_spin_acc    = 0.0
	_anim_phase_timer = 0.0
	_detach_ball()
	_show_only(null)
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.gif_paused = true   # pause before visible so no rogue GIF frame shows
		_chromeball_eo.reset_gif()
		_chromeball_eo.texture_rect.pivot_offset = _chromeball_eo.texture_rect.size / 2.0
		_chromeball_eo.visible = true
		if not _ball_frames.is_empty():
			_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, false, true)
			anim_finished.connect(_on_m4_transform_done, CONNECT_ONE_SHOT)
		else:
			_on_m4_transform_done()

func _on_m4_transform_done() -> void:
	if _phase != Phase.M4_TRANSFORM:
		return
	_phase = Phase.M4_MOVE

func _tick_m4_move(delta: float) -> void:
	_phase_timer += delta
	_ball_angle  += M4_MOVE_RPM * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
		var target := BALL_SPIN_POS - _chromeball_eo.size / 2.0
		var diff   := target - _chromeball_eo.position
		if diff.length() < M4_MOVE_SPD * delta + 3.0:
			_chromeball_eo.position = target
			_phase    = Phase.M4_SPIN
			_spin_acc = 0.0

func _tick_m4_spin(delta: float) -> void:
	_phase_timer += delta
	_spin_acc    += delta
	var t: float   = minf(_spin_acc / M4_SPINUP_T, 1.0)
	var rpm: float = lerpf(M4_MOVE_RPM, M4_SPIN_RPM, t)
	_ball_angle += rpm * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
	if _spin_acc >= M4_SPINUP_T:
		_phase = Phase.M4_CHARGE
		if is_instance_valid(_chromeball_eo):
			var ship_c := _ship_center()
			var ball_c := _chromeball_eo.global_position + _chromeball_eo.size / 2.0
			var d := ship_c - ball_c
			if d.length() < 0.01:
				d = Vector2.DOWN
			_m4_charge_dir = d.normalized()

func _tick_m4_charge(delta: float) -> void:
	_phase_timer += delta
	if not is_instance_valid(_chromeball_eo):
		_begin_m4_return_curve()
		return
	_chromeball_eo.position += _m4_charge_dir * M4_CHARGE_SPD * delta
	_ball_angle += M4_SPIN_RPM * TAU / 60.0 * delta
	_chromeball_eo.texture_rect.rotation = _ball_angle

	if _ship_eo != null and is_instance_valid(_ship_eo):
		var ball_r := Rect2(_chromeball_eo.global_position, _chromeball_eo.size)
		var ship_r := Rect2(_ship_eo.global_position, _ship_eo.size)
		if ball_r.intersects(ship_r):
			GameManager.ship_take_damage(M4_HIT_DMG)
			_flash_ship_red()
			_begin_m4_return_curve()
			return

	var bp := _chromeball_eo.position
	if bp.x < OC_BOUNDS.position.x - 80.0 or bp.x > OC_BOUNDS.end.x + 80.0 or \
	   bp.y < OC_BOUNDS.position.y - 80.0 or bp.y > OC_BOUNDS.end.y + 80.0:
		_begin_m4_return_curve()

func _begin_m4_return_curve() -> void:
	_phase = Phase.M4_RETURN_CURVE
	if not is_instance_valid(_chromeball_eo):
		_phase = Phase.M4_RETURN
		return
	var target := BALL_SPIN_POS - _chromeball_eo.size / 2.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_chromeball_eo, "position", target, M4_RETURN_T)
	tw.tween_callback(func() -> void: _begin_m4_return_anim())

func _tick_m4_return_curve(delta: float) -> void:
	_phase_timer += delta
	_ball_angle += M4_SPIN_RPM * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle

func _begin_m4_return_anim() -> void:
	_phase = Phase.M4_RETURN
	_anim_phase_timer = 0.0
	if is_instance_valid(_chromeball_eo) and not _ball_frames.is_empty():
		_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, true, true)
		anim_finished.connect(_on_m4_return_done, CONNECT_ONE_SHOT)
	else:
		_on_m4_return_done()

func _on_m4_return_done() -> void:
	if _phase != Phase.M4_RETURN:
		return
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_check_hp_or_next()

# =============================================================================
# Final Move — triggered when HP = 0
# =============================================================================

func _begin_final() -> void:
	_phase = Phase.FINAL_ENTRY
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	_blueorb_hp = ORB_MAX_HP
	_tealorb_hp = ORB_MAX_HP
	# Reset the boss HP bar to represent the combined orb HP pool.
	GameManager.boss_max_hp = ORB_MAX_HP * 2
	GameManager.boss_hp     = ORB_MAX_HP * 2
	GameManager.boss_hp_changed.emit(GameManager.boss_hp)

	# Hide current body, show chromehead
	_show_only(null)
	if is_instance_valid(_chromehead_eo):
		_chromehead_eo.visible = true

	_detach_orbs()
	if is_instance_valid(_blueorb_eo):
		_blueorb_eo.visible = true
	if is_instance_valid(_tealorb_eo):
		_tealorb_eo.visible = true

	_register_orb_targets()
	_head_wp = _pick_wander_wp(Y_LIMIT)
	_phase = Phase.FINAL_SUB1
	_phase_timer = 0.0
	_teal_patrol_tgt = 0
	_blue_patrol_tgt = 0
	_teal_fin_shoot = 0.0
	_blue_fin_shoot = 0.0

func _tick_final_sub1(delta: float) -> void:
	_phase_timer += delta
	_tick_head(delta)
	_tick_patrol_teal(delta)
	_tick_patrol_blue(delta)
	_check_orb_win()
	if _phase_timer >= SUB1_DUR:
		_begin_final_sub2()

func _begin_final_sub2() -> void:
	_phase = Phase.FINAL_SUB2
	_phase_timer = 0.0
	_sub2_wave_acc = 0.0
	# Move orbs to side-by-side center (Y=150 screen-local = 158 viewport)
	var cy := 150.0 + SS_OFFSET.y
	var cx := BALL_SPIN_POS.x
	if is_instance_valid(_blueorb_eo) and _blueorb_hp > 0:
		var tw := create_tween()
		tw.tween_property(_blueorb_eo, "position",
			Vector2(cx - _blueorb_eo.size.x - 5.0, cy - _blueorb_eo.size.y / 2.0), 0.5)
	if is_instance_valid(_tealorb_eo) and _tealorb_hp > 0:
		var tw := create_tween()
		tw.tween_property(_tealorb_eo, "position",
			Vector2(cx + 5.0, cy - _tealorb_eo.size.y / 2.0), 0.5)
	# Register shielded bullets provider
	var ws := _get_ws()
	if ws != null:
		ws.set_multi_hit_provider(_get_shielded_targets)

func _tick_final_sub2(delta: float) -> void:
	_phase_timer   += delta
	_sub2_wave_acc += delta
	_tick_head(delta)

	# Orbs stay, rotate, shoot patrol pattern
	_tick_patrol_teal(delta)
	_tick_patrol_blue(delta)

	# Bullet waves
	if _sub2_wave_acc >= SUB2_WAVE_INT:
		_sub2_wave_acc = 0.0
		_spawn_bullet_wave()

	# Update shielded bullet positions
	_tick_shielded_bullets(delta)
	_check_orb_win()
	if _phase_timer >= SUB2_DUR:
		_begin_final_sub3()

func _begin_final_sub3() -> void:
	_phase = Phase.FINAL_SUB3
	_phase_timer = 0.0
	_sub3_rand_b = 0.0; _sub3_rand_t = 0.0
	_sub3_orb_b  = 0.0; _sub3_orb_t  = 0.0
	_cleanup_shielded_bullets()
	var ws := _get_ws()
	if ws != null:
		ws.clear_multi_hit_provider()

func _tick_final_sub3(delta: float) -> void:
	_phase_timer += delta
	_tick_head(delta)
	var head_c := _head_center()
	var ship_c := _ship_center()
	var d := ship_c - head_c
	var dir_to_ship := d.normalized() if d.length() > 0.01 else Vector2.DOWN
	var hide_base := head_c - dir_to_ship * 55.0
	var t := _phase_timer

	if is_instance_valid(_blueorb_eo) and _blueorb_hp > 0:
		_blue_fin_angle += FINAL_ORB_RPM * TAU / 60.0 * delta
		_blueorb_eo.texture_rect.rotation = _blue_fin_angle
		var orb_tgt := hide_base + Vector2(sin(t * 2.1) * 4.0, cos(t * 1.7) * 4.0)
		var orb_c   := _blueorb_eo.position + _blueorb_eo.size / 2.0
		var mv      := orb_tgt - orb_c
		if mv.length() > 1.0:
			_blueorb_eo.position += mv.normalized() * minf(mv.length(), 200.0 * delta)
		_sub3_rand_b += delta
		if _sub3_rand_b >= SUB3_RAND_INT:
			_sub3_rand_b = 0.0
			var orig_b := _blueorb_eo.global_position + _blueorb_eo.size / 2.0
			var bdir_b := (ship_c - orig_b).normalized()
			var rb := _random_bullet()
			_spawn_bullet(rb, orig_b, bdir_b * BULLET_SPD, _random_bullet_sz())
		_sub3_orb_b += delta
		if _sub3_orb_b >= SUB3_ORB_INT:
			_sub3_orb_b = 0.0
			var orig_b2 := _blueorb_eo.global_position + _blueorb_eo.size / 2.0
			var bdir_b2 := (ship_c - orig_b2).normalized()
			_spawn_bullet(_blue_bullet_resized if _blue_bullet_resized != null else _blue_bullet_tex, orig_b2, bdir_b2 * ORB_BULLET_SPD, _blue_bullet_size)

	if is_instance_valid(_tealorb_eo) and _tealorb_hp > 0:
		_teal_fin_angle += FINAL_ORB_RPM * TAU / 60.0 * delta
		_tealorb_eo.texture_rect.rotation = _teal_fin_angle
		var orb_tgt := hide_base + Vector2(sin(t * 1.9 + 1.0) * 4.0, cos(t * 2.3) * 4.0)
		var orb_c   := _tealorb_eo.position + _tealorb_eo.size / 2.0
		var mv      := orb_tgt - orb_c
		if mv.length() > 1.0:
			_tealorb_eo.position += mv.normalized() * minf(mv.length(), 200.0 * delta)
		_sub3_rand_t += delta
		if _sub3_rand_t >= SUB3_RAND_INT:
			_sub3_rand_t = 0.0
			var orig_t := _tealorb_eo.global_position + _tealorb_eo.size / 2.0
			var bdir_t := (ship_c - orig_t).normalized()
			var rt := _random_bullet()
			_spawn_bullet(rt, orig_t, bdir_t * BULLET_SPD, _random_bullet_sz())
		_sub3_orb_t += delta
		if _sub3_orb_t >= SUB3_ORB_INT:
			_sub3_orb_t = 0.0
			var orig_t2 := _tealorb_eo.global_position + _tealorb_eo.size / 2.0
			var bdir_t2 := (ship_c - orig_t2).normalized()
			_spawn_bullet(_teal_bullet_resized if _teal_bullet_resized != null else _teal_bullet_tex, orig_t2, bdir_t2 * ORB_BULLET_SPD, _teal_bullet_size)

	_check_orb_win()
	if _phase_timer >= SUB3_DUR:
		_begin_final_sub1_loop()

func _begin_final_sub1_loop() -> void:
	_phase = Phase.FINAL_SUB1
	_phase_timer = 0.0

func _tick_head(delta: float) -> void:
	if not is_instance_valid(_chromehead_eo):
		return
	_head_wp = _tick_wander(_chromehead_eo, _head_wp, delta, FINAL_HEAD_SPD, Y_LIMIT)
	_head_rot += FINAL_HEAD_RPM * TAU / 60.0 * delta
	_chromehead_eo.texture_rect.rotation = _head_rot

func _tick_patrol_teal(delta: float) -> void:
	if not is_instance_valid(_tealorb_eo) or _tealorb_hp <= 0:
		return
	_teal_fin_angle += FINAL_ORB_RPM * TAU / 60.0 * delta
	_tealorb_eo.texture_rect.rotation = _teal_fin_angle
	var waypoints: Array[Vector2] = [TEAL_WP_A, TEAL_WP_B]
	var wp: Vector2 = waypoints[_teal_patrol_tgt] - _tealorb_eo.size / 2.0
	var diff: Vector2 = wp - _tealorb_eo.position
	if diff.length() < PATROL_SPD * delta + 5.0:
		_tealorb_eo.position = wp
		_teal_patrol_tgt = 1 - _teal_patrol_tgt
	else:
		_tealorb_eo.position += diff.normalized() * PATROL_SPD * delta
	_teal_fin_shoot += delta
	if _teal_fin_shoot >= FINAL_ORB_SHOOT:
		_teal_fin_shoot = 0.0
		_fire_orb_rotated(_tealorb_eo, _teal_fp_offset, _teal_fin_angle, _teal_bullet_resized if _teal_bullet_resized != null else _teal_bullet_tex, _teal_bullet_size)

func _tick_patrol_blue(delta: float) -> void:
	if not is_instance_valid(_blueorb_eo) or _blueorb_hp <= 0:
		return
	_blue_fin_angle += FINAL_ORB_RPM * TAU / 60.0 * delta
	_blueorb_eo.texture_rect.rotation = _blue_fin_angle
	var waypoints: Array[Vector2] = [BLUE_WP_A, BLUE_WP_B]
	var wp: Vector2 = waypoints[_blue_patrol_tgt] - _blueorb_eo.size / 2.0
	var diff: Vector2 = wp - _blueorb_eo.position
	if diff.length() < PATROL_SPD * delta + 5.0:
		_blueorb_eo.position = wp
		_blue_patrol_tgt = 1 - _blue_patrol_tgt
	else:
		_blueorb_eo.position += diff.normalized() * PATROL_SPD * delta
	_blue_fin_shoot += delta
	if _blue_fin_shoot >= FINAL_ORB_SHOOT:
		_blue_fin_shoot = 0.0
		_fire_orb_rotated(_blueorb_eo, _blue_fp_offset, _blue_fin_angle, _blue_bullet_resized if _blue_bullet_resized != null else _blue_bullet_tex, _blue_bullet_size)

# =============================================================================
# Orb HP + win condition
# =============================================================================

func _register_orb_targets() -> void:
	var ws := _get_ws()
	if ws == null:
		return
	ws.add_hit_target(
		func() -> Rect2: return _orb_rect_stream(_blueorb_eo, ws),
		func(dmg: float) -> void: _on_blueorb_hit(dmg)
	)
	ws.add_hit_target(
		func() -> Rect2: return _orb_rect_stream(_tealorb_eo, ws),
		func(dmg: float) -> void: _on_tealorb_hit(dmg)
	)

func _orb_rect_stream(eo: EditableObjectNode, ws: Node) -> Rect2:
	if eo == null or not is_instance_valid(eo) or not eo.visible:
		return Rect2()
	return Rect2(eo.global_position - (ws as Control).global_position, eo.size)

func _on_blueorb_hit(dmg: float) -> void:
	if _blueorb_hp <= 0:
		return
	_blueorb_hp = maxi(0, _blueorb_hp - int(dmg))
	var total := _blueorb_hp + _tealorb_hp
	GameManager.boss_hp = total
	GameManager.boss_hp_changed.emit(total)
	if _blueorb_hp <= 0 and is_instance_valid(_blueorb_eo):
		_blueorb_eo.visible = false

func _on_tealorb_hit(dmg: float) -> void:
	if _tealorb_hp <= 0:
		return
	_tealorb_hp = maxi(0, _tealorb_hp - int(dmg))
	var total := _blueorb_hp + _tealorb_hp
	GameManager.boss_hp = total
	GameManager.boss_hp_changed.emit(total)
	if _tealorb_hp <= 0 and is_instance_valid(_tealorb_eo):
		_tealorb_eo.visible = false

func _check_orb_win() -> void:
	if _blueorb_hp <= 0 and _tealorb_hp <= 0:
		_end_fight_win()

func get_move_name() -> String:
	match _phase:
		Phase.M1_CRAWL:
			return "Move 1: Crawl"
		Phase.M2_TRANSFORM, Phase.M2_MOVE, Phase.M2_SPIN, Phase.M2_RETURN:
			return "Move 2: Ball Spin"
		Phase.M3_ACTIVE, Phase.M3_RECALL:
			return "Move 3: Orb Detach"
		Phase.M4_TRANSFORM, Phase.M4_MOVE, Phase.M4_SPIN, Phase.M4_CHARGE, Phase.M4_RETURN_CURVE, Phase.M4_RETURN:
			return "Move 4: Ball Charge"
		Phase.FINAL_ENTRY, Phase.FINAL_SUB1:
			return "FINAL — Sub 1"
		Phase.FINAL_SUB2:
			return "FINAL — Sub 2"
		Phase.FINAL_SUB3:
			return "FINAL — Sub 3"
	return ""

func _end_fight_win() -> void:
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	var ws := _get_ws()
	if ws != null:
		ws.clear_extra_targets()
		ws.clear_multi_hit_provider()
	if is_instance_valid(_chromehead_eo):
		_chromehead_eo.visible = false
	_phase = Phase.DONE
	_phase_timer = 0.0
	GameManager.boss_hp     = 0
	GameManager.boss_max_hp = 0
	# Delay boss_killed so HUD stays visible and asteroids don't spawn yet
	await get_tree().create_timer(0.1).timeout
	GameManager.boss_killed.emit()
	_show_victory_screen()

# =============================================================================
# Shielded bullets (Final Sub 2)
# =============================================================================

func _spawn_bullet_wave() -> void:
	if _bullet_frames.is_empty():
		return
	print(">>> WAVE SPAWN at Y=%f, spawning %d bullets" % [WAVE_Y, SUB2_BLT_CNT])
	for i in SUB2_BLT_CNT:
		var x_vp := WAVE_X_MIN + i * (WAVE_X_MAX - WAVE_X_MIN) / float(SUB2_BLT_CNT - 1)
		var tex  := _random_bullet()
		var sz   := _random_bullet_sz()
		var tr   := TextureRect.new()
		tr.texture        = tex
		tr.size           = sz
		tr.stretch_mode   = TextureRect.STRETCH_SCALE
		tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.z_as_relative  = false
		tr.z_index        = 150
		var lpos := Vector2(x_vp - OC_BOUNDS.position.x, WAVE_Y - OC_BOUNDS.position.y) - sz / 2.0
		tr.position = lpos
		_clip_node.add_child(tr)
		_shielded_bullets.append({
			"tr":  tr,
			"pos": Vector2(x_vp, WAVE_Y),
			"vel": Vector2(0.0, randf_range(WAVE_SPD_MIN, WAVE_SPD_MAX)),
			"hp":  SUB2_BLT_HP,
			"sz":  sz
		})

func _tick_shielded_bullets(delta: float) -> void:
	var i := _shielded_bullets.size() - 1
	while i >= 0:
		var sb: Dictionary = _shielded_bullets[i]
		sb["pos"] = (sb["pos"] as Vector2) + (sb["vel"] as Vector2) * delta
		var tr: TextureRect = sb["tr"]
		if is_instance_valid(tr):
			var p: Vector2 = sb["pos"]
			tr.position = Vector2(p.x - OC_BOUNDS.position.x, p.y - OC_BOUNDS.position.y) - tr.size / 2.0
		var py: float = float((sb["pos"] as Vector2).y)
		if py > OC_BOUNDS.end.y + 20.0:
			if is_instance_valid(tr):
				tr.queue_free()
			_shielded_bullets.remove_at(i)
		i -= 1

func _get_shielded_targets() -> Array:
	var ws := _get_ws()
	if ws == null:
		return []
	var ws_gp: Vector2 = (ws as Control).global_position
	var result: Array = []
	for sb: Dictionary in _shielded_bullets:
		var pos: Vector2 = sb["pos"]
		var sz: Vector2  = sb.get("sz", Vector2.ZERO) as Vector2
		var sbref := sb
		result.append({
			"rect":   Rect2(pos - ws_gp - sz / 2.0, sz),
			"on_hit": func(dmg: float) -> void: _on_shielded_hit(sbref, dmg)
		})
	return result

func _on_shielded_hit(sb: Dictionary, dmg: float) -> void:
	if not _shielded_bullets.has(sb):
		return
	sb["hp"] = int(sb["hp"]) - int(dmg)
	if int(sb["hp"]) <= 0:
		var tr: TextureRect = sb["tr"]
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
		_shielded_bullets.erase(sb)

func _cleanup_shielded_bullets() -> void:
	var ws := _get_ws()
	if ws != null:
		ws.clear_multi_hit_provider()
	for sb: Dictionary in _shielded_bullets:
		var tr: TextureRect = sb["tr"]
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
	_shielded_bullets.clear()

# =============================================================================
# Victory screen
# =============================================================================

func _show_victory_screen() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 500
	get_tree().root.add_child(cl)

	var vp_sz := get_viewport().get_visible_rect().size
	var bg    := ColorRect.new()
	bg.color  = Color(0.0, 0.0, 0.0, 0.75)
	bg.size   = vp_sz
	cl.add_child(bg)

	var cx := vp_sz.x / 2.0
	var cy := vp_sz.y / 2.0

	var font_path := "res://assets/fonts/Gameplay.ttf"
	var font: FontFile = null
	if ResourceLoader.exists(font_path):
		font = load(font_path) as FontFile

	var title := Label.new()
	title.text = "CHROMELEON DEFEATED"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.9))
	title.size = Vector2(640.0, 60.0)
	title.position = Vector2(cx - 320.0, cy - 90.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		title.add_theme_font_override("font", font)
	bg.add_child(title)

	var btn := Button.new()
	btn.text = "Continue to Universe"
	btn.size = Vector2(240.0, 44.0)
	btn.position = Vector2(cx - 120.0, cy + 10.0)
	if font != null:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 12)
	var cl_ref := cl
	btn.pressed.connect(func() -> void: cl_ref.queue_free())
	bg.add_child(btn)

# =============================================================================
# Process
# =============================================================================

func _process(delta: float) -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	_tick_body_anim(delta)
	_tick_projectiles(delta)

	match _phase:
		Phase.M1_CRAWL:        _tick_m1(delta)
		Phase.M2_TRANSFORM:
			_anim_phase_timer += delta
			if _anim_phase_timer >= 15.0:
				_on_m2_transform_done()
		Phase.M2_MOVE:         _tick_m2_move(delta)
		Phase.M2_SPIN:         _tick_m2_spin(delta)
		Phase.M2_RETURN:
			_anim_phase_timer += delta
			if _anim_phase_timer >= 15.0:
				_on_m2_return_done()
		Phase.M3_ACTIVE:       _tick_m3(delta)
		Phase.M3_RECALL:       _tick_m3_recall(delta)
		Phase.M4_TRANSFORM:
			_anim_phase_timer += delta
			if _anim_phase_timer >= 15.0:
				_on_m4_transform_done()
		Phase.M4_MOVE:         _tick_m4_move(delta)
		Phase.M4_SPIN:         _tick_m4_spin(delta)
		Phase.M4_CHARGE:       _tick_m4_charge(delta)
		Phase.M4_RETURN_CURVE: _tick_m4_return_curve(delta)
		Phase.M4_RETURN:
			_anim_phase_timer += delta
			if _anim_phase_timer >= 15.0:
				_on_m4_return_done()
		Phase.FINAL_SUB1:      _tick_final_sub1(delta)
		Phase.FINAL_SUB2:      _tick_final_sub2(delta)
		Phase.FINAL_SUB3:      _tick_final_sub3(delta)

# =============================================================================
# Body animation system
# =============================================================================

func _play_anim(tr: TextureRect, frames: Array, delays: Array, backward: bool, hold: bool) -> void:
	_anim_tr       = tr
	_anim_frames   = frames
	_anim_delays   = delays
	_anim_backward = backward
	_anim_hold     = hold
	_anim_idx      = frames.size() - 1 if backward else 0
	_anim_acc      = 0.0
	_anim_done     = false
	if not frames.is_empty():
		tr.texture = frames[_anim_idx] as Texture2D

func _tick_body_anim(delta: float) -> void:
	if _anim_tr == null or _anim_done or _anim_frames.is_empty():
		return
	_anim_acc += delta
	var d: float = float(_anim_delays[_anim_idx]) if _anim_idx < _anim_delays.size() else 0.05
	if _anim_acc < d:
		return
	_anim_acc -= d
	if _anim_backward:
		_anim_idx -= 1
	else:
		_anim_idx += 1
	if _anim_idx < 0 or _anim_idx >= _anim_frames.size():
		if _anim_hold:
			_anim_idx = clamp(_anim_idx, 0, _anim_frames.size() - 1)
			_anim_done = true
			anim_finished.emit()
		else:
			_anim_idx = (_anim_idx + _anim_frames.size()) % _anim_frames.size()
	if not _anim_done and is_instance_valid(_anim_tr):
		_anim_tr.texture = _anim_frames[_anim_idx] as Texture2D

# =============================================================================
# Shoot helpers
# =============================================================================

func _fire_ball_4dirs() -> void:
	if not is_instance_valid(_chromeball_eo):
		return
	var center := _chromeball_eo.global_position + _chromeball_eo.size / 2.0
	var base_dir: Vector2
	var origin: Vector2
	if _ball_fp_offset.length() > 1.5:
		origin   = center + _ball_fp_offset.rotated(_ball_angle)
		base_dir = _ball_fp_offset.normalized().rotated(_ball_angle)
	else:
		origin   = center
		base_dir = Vector2.UP.rotated(_ball_angle)
	var tex := _random_bullet()
	var bsz := _random_bullet_sz()
	for i in 4:
		var dir := base_dir.rotated(float(i) * PI / 2.0)
		_spawn_bullet(tex, origin, dir * BULLET_SPD, bsz)

func _fire_orb_nsew(eo: EditableObjectNode, fp_off: Vector2, rot: float, tex: Texture2D, dirs: Array, sz: Vector2) -> void:
	if tex == null or eo == null or not is_instance_valid(eo):
		return
	var center := eo.global_position + eo.size / 2.0
	var origin: Vector2
	if fp_off.length() > 1.5:
		origin = center + fp_off.rotated(rot)
	else:
		origin = center
	for d in dirs:
		_spawn_bullet(tex, origin, (d as Vector2) * ORB_BULLET_SPD, sz)

func _fire_orb_rotated(eo: EditableObjectNode, fp_off: Vector2, angle: float, tex: Texture2D, sz: Vector2) -> void:
	if tex == null or eo == null or not is_instance_valid(eo):
		return
	var center := eo.global_position + eo.size / 2.0
	var base_dir: Vector2
	var origin: Vector2
	if fp_off.length() > 1.5:
		origin   = center + fp_off.rotated(angle)
		base_dir = fp_off.normalized().rotated(angle)
	else:
		origin   = center
		base_dir = Vector2.UP.rotated(angle)
	for i in 4:
		var dir := base_dir.rotated(float(i) * PI / 2.0)
		_spawn_bullet(tex, origin, dir * ORB_BULLET_SPD, sz)

func _random_bullet() -> Texture2D:
	if _bullet_frames.is_empty():
		return null
	_last_cb_idx = randi() % _bullet_frames.size()
	# Return resized frame if available, fallback to raw frame
	if _last_cb_idx < _bullet_resized_frames.size():
		return _bullet_resized_frames[_last_cb_idx] as Texture2D
	return _bullet_frames[_last_cb_idx] as Texture2D

func _random_bullet_sz() -> Vector2:
	if _bullet_sizes.size() <= _last_cb_idx:
		return Vector2.ZERO
	var sz := _bullet_sizes[_last_cb_idx] as Vector2
	return sz if sz != Vector2.ZERO else Vector2(1.0, 1.0)

# =============================================================================
# Projectile system
# =============================================================================

func _spawn_bullet(tex: Texture2D, origin_vp: Vector2, vel: Vector2, sz: Vector2) -> void:
	if tex == null:
		return
	var lpos := origin_vp - OC_BOUNDS.position - sz / 2.0
	var tr      := TextureRect.new()
	tr.texture        = tex
	tr.size           = sz
	tr.stretch_mode   = TextureRect.STRETCH_KEEP  # texture is pre-resized CPU-side
	tr.pivot_offset   = sz / 2.0
	tr.position       = lpos
	tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.z_as_relative  = false
	tr.z_index        = 150
	_clip_node.add_child(tr)
	_projectiles.append({"tr": tr, "vel": vel, "dmg": 12})

func _tick_projectiles(delta: float) -> void:
	var ship_rect := Rect2()
	if _ship_eo != null and is_instance_valid(_ship_eo):
		var hit_vp := Rect2(_ship_eo.global_position, _ship_eo.size)
		ship_rect = Rect2(hit_vp.position - OC_BOUNDS.position, hit_vp.size)
	var clip_rect := Rect2(Vector2.ZERO, OC_BOUNDS.size)
	var i := _projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = _projectiles[i]
		var tr: TextureRect = p["tr"]
		if not is_instance_valid(tr):
			_projectiles.remove_at(i); i -= 1; continue
		tr.position += (p["vel"] as Vector2) * delta
		var prc := Rect2(tr.position, tr.size)
		if ship_rect != Rect2() and prc.intersects(ship_rect):
			GameManager.ship_take_damage(int(p["dmg"]))
			_flash_ship_red()
			tr.queue_free()
			_projectiles.remove_at(i); i -= 1; continue
		var ctr := tr.position + tr.size / 2.0
		if not clip_rect.grow(60.0).has_point(ctr):
			tr.queue_free()
			_projectiles.remove_at(i)
		i -= 1

func _cleanup_projectiles() -> void:
	for p in _projectiles:
		var tr = p.get("tr")
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
	_projectiles.clear()

func _resize_tex(tex: Texture2D, target_sz: Vector2) -> Texture2D:
	if tex == null or target_sz == Vector2.ZERO:
		return tex
	var img := tex.get_image()
	if img == null:
		return tex
	var copy := img.duplicate() as Image
	copy.resize(int(target_sz.x), int(target_sz.y), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(copy)

# =============================================================================
# EO helpers
# =============================================================================

func _detach_orbs() -> void:
	if _orbs_detached:
		return
	if _blueorb_eo == null or _tealorb_eo == null:
		return
	_orbs_detached = true
	var oc_gp := _objects_container.global_position
	if is_instance_valid(_blueorb_eo) and _blueorb_eo.get_parent() != _objects_container:
		var gp := _blueorb_eo.global_position
		_blueorb_eo.get_parent().remove_child(_blueorb_eo)
		_objects_container.add_child(_blueorb_eo)
		_blueorb_eo.position = gp - oc_gp
	if is_instance_valid(_tealorb_eo) and _tealorb_eo.get_parent() != _objects_container:
		var gp := _tealorb_eo.global_position
		_tealorb_eo.get_parent().remove_child(_tealorb_eo)
		_objects_container.add_child(_tealorb_eo)
		_tealorb_eo.position = gp - oc_gp
		_clamp_eo(_tealorb_eo, OC_BOUNDS.end.y)

func _reattach_orbs() -> void:
	if not _orbs_detached:
		return
	_orbs_detached = false
	var base := _chromeleon_eo if is_instance_valid(_chromeleon_eo) else _chromeleonbody_eo
	if base == null:
		return
	if is_instance_valid(_blueorb_eo) and _blueorb_eo.get_parent() == _objects_container:
		_objects_container.remove_child(_blueorb_eo)
		base.add_child(_blueorb_eo)
		_blueorb_eo.position = Vector2(-20.0, 0.0)
		_blueorb_eo.visible  = true
	if is_instance_valid(_tealorb_eo) and _tealorb_eo.get_parent() == _objects_container:
		_objects_container.remove_child(_tealorb_eo)
		base.add_child(_tealorb_eo)
		_tealorb_eo.position = Vector2(20.0, 0.0)
		_tealorb_eo.visible  = true

func _detach_ball() -> void:
	if _ball_detached or not is_instance_valid(_chromeball_eo):
		return
	_ball_detached = true
	if _chromeball_eo.get_parent() == _objects_container:
		return
	var oc_gp := _objects_container.global_position
	var gp    := _chromeleon_eo.global_position + _chromeleon_eo.size / 2.0 - _chromeball_eo.size / 2.0
	var parent := _chromeball_eo.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(_chromeball_eo)
	_objects_container.add_child(_chromeball_eo)
	_chromeball_eo.position = gp - oc_gp

func _reattach_ball() -> void:
	if not _ball_detached or not is_instance_valid(_chromeball_eo):
		return
	_ball_detached = false
	if _chromeball_eo.get_parent() != _objects_container:
		return
	var ball_center_vp := _chromeball_eo.position + _objects_container.global_position + _chromeball_eo.size / 2.0
	_objects_container.remove_child(_chromeball_eo)
	if is_instance_valid(_chromeleon_eo):
		_chromeleon_eo.add_child(_chromeball_eo)
		_chromeball_eo.position = _ball_orig_local_pos
		# Position chromeleon so its center is at ball's last center
		_chromeleon_eo.position = ball_center_vp - _chromeleon_eo.size / 2.0
		_clamp_eo(_chromeleon_eo, OC_BOUNDS.end.y)
	_chromeball_eo.texture_rect.rotation = 0.0
	_chromeball_eo.visible = true
	_chromeball_eo.gif_paused = false   # restore EO's own GIF loop
	_chromeball_eo.reset_gif()

func _show_only(target: EditableObjectNode) -> void:
	for eo in [_chromeleon_eo, _chromeleonbody_eo, _chromehead_eo, _chromeball_eo, _blueorb_eo, _tealorb_eo]:
		if is_instance_valid(eo):
			eo.visible = (eo == target)

func _active_body() -> EditableObjectNode:
	if is_instance_valid(_chromehead_eo) and _chromehead_eo.visible:
		return _chromehead_eo
	if is_instance_valid(_chromeleonbody_eo) and _chromeleonbody_eo.visible:
		return _chromeleonbody_eo
	if is_instance_valid(_chromeball_eo) and _chromeball_eo.visible:
		return _chromeball_eo
	if is_instance_valid(_chromeleon_eo) and _chromeleon_eo.visible:
		return _chromeleon_eo
	return null

func _tick_wander(eo: EditableObjectNode, wp: Vector2, delta: float, spd: float, y_max: float) -> Vector2:
	if not is_instance_valid(eo):
		return wp
	var diff := wp - eo.position
	if diff.length() < spd * delta + 5.0:
		eo.position = wp
		return _pick_wander_wp(y_max)
	eo.position += diff.normalized() * spd * delta
	_clamp_eo(eo, y_max)
	return wp

func _clamp_eo(eo: EditableObjectNode, y_max: float) -> void:
	if not is_instance_valid(eo):
		return
	eo.position.x = clampf(eo.position.x, OC_BOUNDS.position.x, OC_BOUNDS.end.x - eo.size.x)
	eo.position.y = clampf(eo.position.y, OC_BOUNDS.position.y, y_max - eo.size.y)

func _pick_wander_wp(y_max: float) -> Vector2:
	return Vector2(
		randf_range(OC_BOUNDS.position.x + 40.0, OC_BOUNDS.end.x - 80.0),
		randf_range(OC_BOUNDS.position.y + 30.0, y_max - 40.0)
	)

func _pick_crawl_wp() -> Vector2:
	return _pick_wander_wp(Y_LIMIT)

func _ship_center() -> Vector2:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return OC_BOUNDS.get_center()
	return _ship_eo.global_position + _ship_eo.size / 2.0

func _head_center() -> Vector2:
	if not is_instance_valid(_chromehead_eo):
		return OC_BOUNDS.get_center()
	return _chromehead_eo.global_position + _chromehead_eo.size / 2.0

func _flash_ship_red() -> void:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var tw := create_tween()
	tw.tween_property(_ship_eo, "modulate", Color(2.0, 0.2, 0.2, 1.0), 0.05)
	tw.tween_property(_ship_eo, "modulate", Color.WHITE, 0.3)

func _get_ws() -> Node:
	return get_tree().get_first_node_in_group("weapon_system")

# =============================================================================
# EO discovery
# =============================================================================

func _find_eos() -> void:
	if _objects_container == null:
		return
	for child in _objects_container.get_children():
		var eo := child as EditableObjectNode
		if eo == null:
			continue
		var base := eo.source_path.get_file().get_basename().to_lower()
		if base == "spaceship":
			_ship_eo = eo
		elif base == "chromeleon":
			_chromeleon_eo = eo
			_find_chromeleon_children(eo)
		elif base == "spaceshiphitbox":
			eo.visible = false

func _find_chromeleon_children(base_eo: EditableObjectNode) -> void:
	for child in base_eo.get_children():
		var seo := child as EditableObjectNode
		if seo == null:
			continue
		var bname := seo.source_path.get_file().get_basename().to_lower()
		match bname:
			"blueorb":
				_blueorb_eo = seo
			"tealorb":
				_tealorb_eo = seo
			"chromeball":
				_chromeball_eo = seo
				_ball_orig_local_pos = seo.position
			"chromeleonbody":
				_chromeleonbody_eo = seo
			"chromehead":
				_chromehead_eo = seo

# =============================================================================
# Firepoint loading
# =============================================================================

func _load_fp_offsets() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://boss_layout.cfg") != OK:
		return
	if is_instance_valid(_chromeleon_eo):
		_main_fp_nodes = _build_fp_nodes(_chromeleon_eo, cfg.get_value("firepoints", "chromeleon", []))
	if is_instance_valid(_chromeball_eo):
		_ball_fp_nodes = _build_fp_nodes(_chromeball_eo, cfg.get_value("firepoints", "chromeleon_chromeball", []))
	if is_instance_valid(_blueorb_eo):
		_blue_fp_nodes = _build_fp_nodes(_blueorb_eo, cfg.get_value("firepoints", "chromeleon_blueorb", []))
	if is_instance_valid(_tealorb_eo):
		_teal_fp_nodes = _build_fp_nodes(_tealorb_eo, cfg.get_value("firepoints", "chromeleon_tealorb", []))

func _build_fp_nodes(parent_eo: EditableObjectNode, fp_data: Array) -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	if fp_data.is_empty():
		return nodes
	var boss_center := parent_eo.global_position + parent_eo.size / 2.0
	for fp: Dictionary in fp_data:
		var fp_oc: Vector2 = (fp.get("pos", Vector2.ZERO) as Vector2) + SS_OFFSET
		var offset := fp_oc - boss_center
		var n := Node2D.new()
		n.position = parent_eo.size / 2.0 + offset
		parent_eo.add_child(n)
		nodes.append(n)
	return nodes

func _cache_fp_offsets() -> void:
	if is_instance_valid(_chromeball_eo) and not _ball_fp_nodes.is_empty():
		var fp := _ball_fp_nodes[0]
		if is_instance_valid(fp):
			_ball_fp_offset = fp.position - _chromeball_eo.size / 2.0
	if is_instance_valid(_blueorb_eo) and not _blue_fp_nodes.is_empty():
		var fp := _blue_fp_nodes[0]
		if is_instance_valid(fp):
			_blue_fp_offset = fp.position - _blueorb_eo.size / 2.0
	if is_instance_valid(_tealorb_eo) and not _teal_fp_nodes.is_empty():
		var fp := _teal_fp_nodes[0]
		if is_instance_valid(fp):
			_teal_fp_offset = fp.position - _tealorb_eo.size / 2.0

# =============================================================================
# Asset loading
# =============================================================================

func _load_assets() -> void:
	# chromebullet1-12
	for i in range(1, 13):
		var bn   := "chromebullet%d" % i
		var path := "res://assets/bosses/chromeleon/%s.gif" % bn
		var tex := GifLoader.load_gif(path)
		if tex == null:
			tex = load(path) as Texture2D
		if tex == null:
			continue
		var frame: Texture2D = tex
		if tex.has_meta("gif_frames"):
			var frames: Array = tex.get_meta("gif_frames")
			if not frames.is_empty():
				frame = frames[0] as Texture2D
		_bullet_frames.append(frame)
		var native_sz := frame.get_size() if frame != null else Vector2.ZERO
		_bullet_native_sizes.append(native_sz)
		_bullet_sizes.append(native_sz)  # will be overwritten by _reload_bullet_sizes() if F5 defines size

	# chromeball animation
	var ball_tex := GifLoader.load_gif("res://assets/bosses/chromeleon/chromeball.gif")
	if ball_tex != null:
		if ball_tex.has_meta("gif_frames"):
			_ball_frames = ball_tex.get_meta("gif_frames")
		if ball_tex.has_meta("gif_delays"):
			_ball_delays = ball_tex.get_meta("gif_delays")

	# bluebullet
	var bt := GifLoader.load_gif("res://assets/bosses/chromeleon/bluebullet.gif")
	if bt == null:
		bt = load("res://assets/bosses/chromeleon/bluebullet.gif") as Texture2D
	if bt != null:
		var bframes: Array = bt.get_meta("gif_frames") if bt.has_meta("gif_frames") else []
		if not bframes.is_empty():
			_blue_bullet_tex = bframes[0] as Texture2D
		else:
			_blue_bullet_tex = bt
		_blue_bullet_native_size = _blue_bullet_tex.get_size() if _blue_bullet_tex != null else Vector2.ZERO
		_blue_bullet_size = _blue_bullet_native_size

	# tealbullet
	var tt := GifLoader.load_gif("res://assets/bosses/chromeleon/tealbullet.gif")
	if tt == null:
		tt = load("res://assets/bosses/chromeleon/tealbullet.gif") as Texture2D
	if tt != null:
		var tframes: Array = tt.get_meta("gif_frames") if tt.has_meta("gif_frames") else []
		if not tframes.is_empty():
			_teal_bullet_tex = tframes[0] as Texture2D
		else:
			_teal_bullet_tex = tt
		_teal_bullet_native_size = _teal_bullet_tex.get_size() if _teal_bullet_tex != null else Vector2.ZERO
		_teal_bullet_size = _teal_bullet_native_size

func _reload_bullet_sizes() -> void:
	# Always re-read bullet sizes from boss_layout.cfg so F5 edits take effect
	var sz_map: Dictionary = {}
	var cfg2 := ConfigFile.new()
	if cfg2.load("res://boss_layout.cfg") == OK:
		var entries: Array = cfg2.get_value("bosses", "chromeleon", [])
		for entry: Dictionary in entries:
			var bn: String = (entry.get("path", "") as String).get_file().get_basename().to_lower()
			var sz: Vector2 = entry.get("size", Vector2.ZERO) as Vector2
			if sz != Vector2.ZERO:
				sz_map[bn] = sz

	# Update chromebullet sizes (fallback to native size if not in F5)
	for i in _bullet_frames.size():
		var bn := "chromebullet%d" % (i + 1)
		var native_fallback: Vector2 = _bullet_native_sizes[i] if i < _bullet_native_sizes.size() else Vector2.ZERO
		if i < _bullet_sizes.size():
			_bullet_sizes[i] = sz_map.get(bn, native_fallback) as Vector2

	# Update orb bullet sizes (fallback to native size if not in F5)
	_blue_bullet_size = sz_map.get("bluebullet", _blue_bullet_native_size) as Vector2
	_teal_bullet_size = sz_map.get("tealbullet", _teal_bullet_native_size) as Vector2

	# Pre-cache resized bullet frames
	_resize_all_bullets()

func _resize_all_bullets() -> void:
	# Resize chromebullets
	_bullet_resized_frames.clear()
	for i in _bullet_frames.size():
		var frame: Texture2D = _bullet_frames[i]
		var sz: Vector2 = _bullet_sizes[i] if i < _bullet_sizes.size() else Vector2.ZERO
		var resized := _resize_tex(frame, sz) if sz != Vector2.ZERO else frame
		_bullet_resized_frames.append(resized)

	# Resize blue/teal bullets
	_blue_bullet_resized = _resize_tex(_blue_bullet_tex, _blue_bullet_size) if _blue_bullet_size != Vector2.ZERO else _blue_bullet_tex
	_teal_bullet_resized = _resize_tex(_teal_bullet_tex, _teal_bullet_size) if _teal_bullet_size != Vector2.ZERO else _teal_bullet_tex
