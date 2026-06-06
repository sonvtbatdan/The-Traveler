extends Control

const SS_OFFSET  := Vector2(270.0, 8.0)
const OC_BOUNDS  := Rect2(270.0, 8.0, 700.0, 764.0)

const GifLoader := preload("res://scripts/ui/edit_mode/gif_loader.gd")

const BOSS_VISUAL_SCALE := 2.0   # elephant drawn at 2× (scaled around its center pivot)

# ── Move 1 constants ──────────────────────────────────────────────────────────
const M1_START_SS      := Vector2(10.0, 175.0)
const M1_END_SS        := Vector2(650.0, 175.0)
const M1_ENTRY_T       := 1.5
const M1_TRAVEL_T      := 8.0
const M1_ROT_SPEED     := 40.0 * TAU / 60.0
const M1_SPIKE_INT     := 0.2
const M1_SPIKES_PER_INT := 6               # 6 spikes per burst (tripled; spiral 6-arm)
const M1_SPIRAL_STEP   := 0.35            # radians to advance base angle each burst
const SPIKE_SPEED      := 108.0           # radial launch speed (+20%)
const SPIKE_SPIN_RADIUS := 40.0          # effective radius for spin-induced tangential kick (tunable)
const SPIKE_DMG        := 10

# ── Move 2 constants ──────────────────────────────────────────────────────────
const M2_DURATION      := 8.0
const M2_VORTEX_INT    := 0.3                 # 5× faster volleys (5× the vortexes)
const M2_MOVE_SPD      := 80.0
const M2_MAX_Y_SS      := 450.0
const VORTEX_SPEED     := 108.0              # +20%
const VORTEX_ROT_SPEED := 60.0 * TAU / 60.0   # 1 rot/s (×2)
const VORTEX_DMG       := 15

# ── Move 3 constants ──────────────────────────────────────────────────────────
const M3_ROT_T         := 0.5
const M3_MOVE_SPD      := 600.0             # 5× — snaps to aim at the ship's X
const M3_WARN_T        := 1.0               # dull warning flash for 1s
const M3_FIRE_T        := 1.0               # fire 1s
const LASER_W          := 5.0
const LASER_FIRE_MULT  := 5.0               # actual beam = 5× the warning width (visual + hitbox)
const LASER_WARN_MODULATE := Color(0.55, 0.6, 0.7, 0.7)  # dull mask during the warning
const LASER_FLASH_CYC  := 0.08
const LASER_DMG        := 30

# ── Move 4 constants ──────────────────────────────────────────────────────────
const M4_ROT_T          := 0.5
const M4_TRAVEL_SPD     := 600.0            # 5× traversal speed
const M4_DROP_INT       := 0.2             # drop a bomb every 0.2s
const DROP_SPEED        := 720.0           # bombs hang then drop fast (+20%)
const DROP_DMG          := 20
const M4_START_LEFT_SS  := Vector2(10.0, 175.0)
const M4_START_RIGHT_SS := Vector2(690.0, 175.0)

# ── Move 5 constants ──────────────────────────────────────────────────────────
const M5_DURATION   := 5.0
const M5_ROT_T      := 0.5
const M5_BLOB_INT   := 2.0 / 3.0           # half as many blobs (half the fire rate)
const M5_MOVE_SPD   := 80.0
const BLOB_SPEED    := 360.0               # +20%
const BLOB_DMG      := 20

# ── Boss HP ───────────────────────────────────────────────────────────────────
const BOSS_MAX_HP      := 2000

# All boss attack damage is scaled by this (75% of the per-attack values above).
const BOSS_DAMAGE_MULT := 0.75

# ── Phase ─────────────────────────────────────────────────────────────────────
enum Phase { IDLE, M1_ENTRY, M1_TRAVEL, M2, M3_ROT, M3_MOVE, M3_WARN, M3_FIRE, M4_ROT, M4_TRAVEL, M5_ROT, M5_MOVE, DONE }

var _phase     := Phase.IDLE
var _phase_acc := 0.0
var _forced_kill := false   # true when kill_boss() is a forced removal (player death / debug) → no victory banner

# ── Scene refs ────────────────────────────────────────────────────────────────
var _objects_container: Control            = null
var _boss_eo:           EditableObjectNode = null
var _spike_eos:         Array              = []
var _ship_eo:              EditableObjectNode = null
var _ship_hitbox_node:     Control = null   # child of _ship_eo — auto-follows ship transform

# Fire point offsets from boss center (OC space), computed at setup time
var _fp1_off := Vector2.ZERO
var _fp2_off := Vector2.ZERO
var _fp3_off := Vector2.ZERO

# Fire point child nodes (child of boss EO — auto-follow boss translation + rotation)
var _fp1_node: Node2D = null
var _fp2_node: Node2D = null
var _fp3_node: Node2D = null

# ── Clip container for all projectiles/laser ──────────────────────────────────
var _clip_node: Control = null

# ── Cached assets ─────────────────────────────────────────────────────────────
var _vortex_frames: Array = []
var _vortex_delays: Array = []
var _laser_frames:  Array = []
var _ball_anims:    Array = []   # array of {frames, delays} dicts for ball1-4
var _drop_frames:   Array = []   # resized to 20%
var _drop_delays:   Array = []
var _drop_size:     Vector2 = Vector2.ZERO
var _blob_frames:   Array = []
var _blob_delays:   Array = []
var _ship_img:        Image = null   # cached ship texture (fallback collision)
var _ship_hitbox_img: Image = null   # Spaceshiphitbox.png — black pixels define hitbox
var _ship_tight_uv:   Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)  # UV rect of hitbox area
var _ship_alpha_uv:   Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)  # opaque (alpha) bounds of the ship sprite

# ── Move 1 state ──────────────────────────────────────────────────────────────
var _boss_spin  := 0.0
var _spike_acc     := 0.0
var _m1_prog       := 0.0
var _spiral_angle  := 0.0   # base angle for spiral spike pattern

# ── Move 2 state ──────────────────────────────────────────────────────────────
var _m2_target  := Vector2.ZERO
var _vortex_acc := 0.0
var _m2_dir     := 1.0   # horizontal sweep direction (+1 = right, -1 = left)

# ── Move 3 state ──────────────────────────────────────────────────────────────
var _m3_target_cx_oc := 0.0   # player hitbox center X (OC/global space) for the laser
var _laser_tr:         TextureRect = null
var _laser_flash_acc  := 0.0
var _laser_hit_done   := false
var _m3_shots         := 0    # how many laser shots fired this Move-3 cycle (fires 3×)
var _laser_w          := LASER_W   # current beam width: thin warning, 3× wide on actual fire

# ── Move 4 state ──────────────────────────────────────────────────────────────
var _m4_dir            := 1.0
var _m4_drop_acc       := 0.0
var _m4_dropped_first  := false   # row dropped when entering the first third
var _m4_dropped_last   := false   # row dropped when entering the last third

# ── Move 5 state ──────────────────────────────────────────────────────────────
var _m5_acc      := 0.0
var _m5_blob_acc := 0.0
var _m5_target   := Vector2.ZERO

# ── Projectiles ───────────────────────────────────────────────────────────────
var _projectiles: Array = []

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

	# Clip container — all projectiles/laser drawn inside this, clipped to StreamScreen area
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
	_load_assets()
	GameManager.boss_killed.connect(_on_boss_killed_internally)

func _on_boss_killed_internally() -> void:
	if _phase != Phase.IDLE and _phase != Phase.DONE:
		var won := not _forced_kill   # HP-zero defeat vs forced removal (player death / debug)
		_force_reset()
		if won:
			_show_victory_screen()
	_forced_kill = false

func _force_reset() -> void:
	_cleanup_projectiles()
	if _laser_tr != null and is_instance_valid(_laser_tr):
		_laser_tr.queue_free()
		_laser_tr = null
	if _boss_eo != null and is_instance_valid(_boss_eo):
		_boss_eo.visible  = false
		_boss_eo.rotation = 0.0
		_boss_eo.scale    = Vector2.ONE
	_phase     = Phase.IDLE
	_phase_acc = 0.0

# =============================================================================
# Public API
# =============================================================================

func spawn_boss() -> void:
	if _phase != Phase.IDLE and _phase != Phase.DONE:
		return
	if _boss_eo == null or not is_instance_valid(_boss_eo):
		return
	GameManager.boss_max_hp = BOSS_MAX_HP
	GameManager.boss_hp     = BOSS_MAX_HP
	GameManager.boss_hp_changed.emit(BOSS_MAX_HP)
	GameManager.boss_spawned.emit()
	# Auto-activate manual boost so player has control
	if not GameManager.manual_boost:
		GameManager.set_boost(true)
	start_fight()

func kill_boss() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	_forced_kill = true   # forced removal (player death / debug) — suppress the victory banner
	_cleanup_projectiles()
	if _laser_tr != null and is_instance_valid(_laser_tr):
		_laser_tr.queue_free()
		_laser_tr = null
	if _boss_eo != null and is_instance_valid(_boss_eo):
		_boss_eo.visible  = false
		_boss_eo.rotation = 0.0
		_boss_eo.scale    = Vector2.ONE
	_phase     = Phase.IDLE
	_phase_acc = 0.0
	GameManager.boss_hp     = 0
	GameManager.boss_max_hp = 0
	GameManager.boss_killed.emit()

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
	title.text = "DISASTER AVOIDED"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
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

## True axis-aligned bounding box of the (rotated/scaled, center-pivot) boss sprite,
## via its TextureRect's real global transform — same pattern as _ship_hit_rect_oc().
## Using _boss_eo.global_position directly is wrong once rotated (origin ≠ visible top-left).
func get_boss_hit_rect() -> Rect2:
	if _boss_eo == null or not is_instance_valid(_boss_eo) or not _boss_eo.visible:
		return Rect2()
	var tr: TextureRect = _boss_eo.texture_rect
	if tr == null:
		return Rect2(_boss_eo.global_position, _boss_eo.size)   # fallback
	# Rotation-INVARIANT box: stable center + scaled size, ignoring the boss's spin.
	# (The old AABB-of-rotated-corners pulsed in size as the boss rotated during Move 1.)
	var xf := tr.get_global_transform()
	var center := xf * (tr.size * 0.5)        # visible center (position + pivot/scale), spin-independent
	var scaled := tr.size * xf.get_scale()    # size with scale baked in, without rotation
	return Rect2(center - scaled * 0.5, scaled)

## Let an external defender (Swarm Host bats) destroy the nearest in-flight boss
## projectile within `radius` of `center`. Projectiles live in _clip_node-local space,
## which shares the StreamScreen origin (270,8) with weapon_system-local — so the bat's
## own local position can be passed straight in. Returns {"hit":bool, "pos":Vector2}.
func consume_projectile_near(center: Vector2, radius: float) -> Dictionary:
	var best: int = -1
	var best_d: float = INF
	var best_pos := Vector2.ZERO
	for i in range(_projectiles.size()):
		var p: Dictionary = _projectiles[i]
		var tr: TextureRect = p.get("tr")
		if tr == null or not is_instance_valid(tr):
			continue
		var pc: Vector2 = tr.position + tr.size * 0.5
		var pr: float = maxf(tr.size.x, tr.size.y) * 0.5
		var d: float = pc.distance_to(center)
		if d <= radius + pr and d < best_d:
			best_d = d; best = i; best_pos = pc
	if best < 0:
		return {"hit": false, "pos": Vector2.ZERO}
	var bp: Dictionary = _projectiles[best]
	var btr: TextureRect = bp.get("tr")
	if btr != null and is_instance_valid(btr):
		btr.queue_free()
	_projectiles.remove_at(best)
	return {"hit": true, "pos": best_pos}

func start_fight() -> void:
	if _boss_eo == null or not is_instance_valid(_boss_eo):
		return
	_boss_eo.visible      = true
	_boss_eo.pivot_offset = _boss_eo.size / 2.0
	_boss_eo.rotation     = 0.0
	_boss_eo.scale        = Vector2(BOSS_VISUAL_SCALE, BOSS_VISUAL_SCALE)
	_boss_spin = 0.0
	_begin_random_move()

func _begin_random_move() -> void:
	_boss_eo.rotation = 0.0
	_boss_spin = 0.0
	match randi() % 5:
		0: _begin_m1()
		1: _begin_m2_tweened()
		2: _begin_m3_tweened()
		3: _begin_m4()
		4: _begin_m5()

func _begin_m1() -> void:
	_phase     = Phase.M1_ENTRY
	_phase_acc = 0.0
	var entry_pos := M1_START_SS + SS_OFFSET - _boss_eo.size / 2.0
	var tw := create_tween()
	tw.tween_property(_boss_eo, "position", entry_pos, M1_ENTRY_T) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(_on_m1_entry_done)

func _begin_m2_tweened() -> void:
	# Start in a top corner (50/50 left vs right) and sweep toward the far side.
	var go_left := randi() % 2 == 0   # start top-LEFT, sweep right
	var top_y := OC_BOUNDS.position.y
	var corner_x: float = OC_BOUNDS.position.x if go_left else OC_BOUNDS.end.x - _boss_eo.size.x
	_m2_dir = 1.0 if go_left else -1.0
	var target := Vector2(corner_x, top_y)
	_phase     = Phase.M1_ENTRY   # block _process tick during tween
	_phase_acc = 0.0
	var tw := create_tween()
	tw.tween_property(_boss_eo, "position", target, 1.0) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(func() -> void:
		_phase      = Phase.M2
		_phase_acc  = 0.0
		_vortex_acc = 0.0)

func _begin_m3_tweened() -> void:
	var rx := randf_range(OC_BOUNDS.position.x, OC_BOUNDS.end.x - _boss_eo.size.x)
	var ry := randf_range(OC_BOUNDS.position.y, OC_BOUNDS.position.y + M2_MAX_Y_SS - _boss_eo.size.y)
	_phase     = Phase.M1_ENTRY
	_phase_acc = 0.0
	var tw := create_tween()
	tw.tween_property(_boss_eo, "position", Vector2(rx, ry), 1.0) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(func() -> void:
		_boss_eo.pivot_offset = _boss_eo.size / 2.0
		_phase     = Phase.M3_ROT
		_phase_acc = 0.0
		_m3_shots  = 0)

func _on_m1_entry_done() -> void:
	_phase        = Phase.M1_TRAVEL
	_phase_acc    = 0.0
	_m1_prog      = 0.0
	_spike_acc    = 0.0
	_boss_spin    = 0.0
	_spiral_angle = 0.0

# =============================================================================
# Main process
# =============================================================================

func _draw() -> void:
	# ⚠ warning sign next to the boss's gun, shown for the whole Move-3 warning.
	if _phase == Phase.M3_WARN and _boss_eo != null and is_instance_valid(_boss_eo):
		var fp3_local := _get_fp3_world() - global_position   # this Control has no scale/rotation
		_draw_warning_sign(fp3_local + Vector2(28.0, -22.0))

func _draw_warning_sign(c: Vector2) -> void:
	var s := 18.0
	var amber := Color(1.0, 0.78, 0.1)
	var dark  := Color(0.12, 0.09, 0.0)
	var p0 := c + Vector2(0.0, -s)            # top
	var p1 := c + Vector2(s * 0.9, s * 0.7)   # bottom-right
	var p2 := c + Vector2(-s * 0.9, s * 0.7)  # bottom-left
	draw_colored_polygon(PackedVector2Array([p0, p1, p2]), amber)
	draw_polyline(PackedVector2Array([p0, p1, p2, p0]), dark, 2.0)
	# exclamation mark
	draw_line(c + Vector2(0.0, -s * 0.35), c + Vector2(0.0, s * 0.18), dark, 3.0)
	draw_circle(c + Vector2(0.0, s * 0.42), 2.0, dark)

func _process(delta: float) -> void:
	if GameManager.boss_max_hp > 0:
		queue_redraw()   # redraw for the Move-3 warning sign
	# Always hide boss when not in an active fight phase
	if _boss_eo != null and is_instance_valid(_boss_eo):
		if _phase == Phase.IDLE or _phase == Phase.DONE:
			_boss_eo.visible = false

	# Tick projectiles every frame regardless of phase
	_tick_projectiles(delta)

	if _phase == Phase.IDLE or _phase == Phase.DONE or _phase == Phase.M1_ENTRY:
		return
	if _boss_eo == null or not is_instance_valid(_boss_eo):
		return
	_boss_eo.visible = true

	match _phase:
		Phase.M1_TRAVEL: _tick_m1(delta)
		Phase.M2:         _tick_m2(delta)
		Phase.M3_ROT:     _tick_m3_rot(delta)
		Phase.M3_MOVE:    _tick_m3_move(delta)
		Phase.M3_WARN:    _tick_m3_warn(delta)
		Phase.M3_FIRE:    _tick_m3_fire(delta)
		Phase.M4_ROT:     _tick_m4_rot(delta)
		Phase.M4_TRAVEL:  _tick_m4_travel(delta)
		Phase.M5_ROT:     _tick_m5_rot(delta)
		Phase.M5_MOVE:    _tick_m5_move(delta)

	_clamp_boss()

func _clamp_boss() -> void:
	if _boss_eo == null or not is_instance_valid(_boss_eo):
		return
	_boss_eo.position.x = clampf(_boss_eo.position.x,
		OC_BOUNDS.position.x, OC_BOUNDS.end.x - _boss_eo.size.x)
	_boss_eo.position.y = clampf(_boss_eo.position.y,
		OC_BOUNDS.position.y, OC_BOUNDS.end.y - _boss_eo.size.y)

# =============================================================================
# Move 1 — spin + horizontal sweep + spike rain
# =============================================================================

func _tick_m1(delta: float) -> void:
	_phase_acc += delta
	_m1_prog    = minf(_phase_acc / M1_TRAVEL_T, 1.0)

	_boss_spin     += M1_ROT_SPEED * delta
	_boss_eo.rotation = _boss_spin

	var ss_pos := M1_START_SS.lerp(M1_END_SS, _m1_prog)
	_boss_eo.position = ss_pos + SS_OFFSET - _boss_eo.size / 2.0

	_spike_acc += delta
	while _spike_acc >= M1_SPIKE_INT:
		_spike_acc -= M1_SPIKE_INT
		# Spiral burst of ball spikes (visual comes from _ball_anims; _spawn_spike guards itself).
		for i in M1_SPIKES_PER_INT:
			var arm_angle := _boss_spin + _spiral_angle + float(i) * (TAU / M1_SPIKES_PER_INT)
			_spawn_spike(arm_angle)
		_spiral_angle += M1_SPIRAL_STEP

	if _m1_prog >= 1.0:
		_begin_random_move()

# =============================================================================
# Move 2 — random movement + firevortex bursts
# =============================================================================

func _tick_m2(delta: float) -> void:
	_phase_acc += delta

	# Horizontal sweep at the top, bouncing off the side walls.
	_boss_eo.position.x += _m2_dir * M2_MOVE_SPD * delta
	var right_wall := OC_BOUNDS.end.x - _boss_eo.size.x
	var left_wall  := OC_BOUNDS.position.x
	if _boss_eo.position.x >= right_wall:
		_boss_eo.position.x = right_wall
		_m2_dir = -1.0
	elif _boss_eo.position.x <= left_wall:
		_boss_eo.position.x = left_wall
		_m2_dir = 1.0

	# Fire rhythm: 2s firing, 1s pause (3s cycle).
	if fmod(_phase_acc, 3.0) < 2.0:
		_vortex_acc += delta
		if _vortex_acc >= M2_VORTEX_INT:
			_vortex_acc -= M2_VORTEX_INT
			var fp1_pos := _fp1_node.global_position if is_instance_valid(_fp1_node) \
				else _boss_eo.global_position + _boss_eo.size / 2.0 + _fp1_off
			var fp2_pos := _fp2_node.global_position if is_instance_valid(_fp2_node) \
				else _boss_eo.global_position + _boss_eo.size / 2.0 + _fp2_off
			_fire_vortex(fp1_pos)
			_fire_vortex(fp2_pos)
	else:
		_vortex_acc = 0.0

	if _phase_acc >= M2_DURATION:
		_begin_random_move()

func _pick_m2_target() -> Vector2:
	var max_y := OC_BOUNDS.position.y + M2_MAX_Y_SS - _boss_eo.size.y
	return Vector2(
		randf_range(OC_BOUNDS.position.x, OC_BOUNDS.end.x - _boss_eo.size.x),
		randf_range(OC_BOUNDS.position.y, max_y)
	)

# =============================================================================
# Move 3 — rotate 90° CW → move to ship X → laser
# =============================================================================

func _tick_m3_rot(delta: float) -> void:
	_phase_acc += delta
	var t := minf(_phase_acc / M3_ROT_T, 1.0)
	_boss_eo.rotation = lerp(0.0, PI / 2.0, t)
	if t >= 1.0:
		_boss_eo.rotation = PI / 2.0
		_phase     = Phase.M3_MOVE
		_phase_acc = 0.0
		# Capture player hitbox center X at the moment rotation completes (most accurate)
		_m3_target_cx_oc = _ship_aim_point_oc().x

func _tick_m3_move(delta: float) -> void:
	# Position the boss so the BEAM (emitted from fp3) lands on the target, not the
	# boss center. fp3's x-offset from boss.position is constant for the locked rotation.
	var fp_dx := _get_fp3_world().x - _boss_eo.position.x
	var target_oc := Vector2(
		clampf(_m3_target_cx_oc - fp_dx,
			OC_BOUNDS.position.x, OC_BOUNDS.end.x - _boss_eo.size.x),
		clampf(175.0 + SS_OFFSET.y - _boss_eo.size.y / 2.0,
			OC_BOUNDS.position.y, OC_BOUNDS.end.y - _boss_eo.size.y)
	)
	var diff := target_oc - _boss_eo.position
	var step := M3_MOVE_SPD * delta
	if diff.length() <= maxf(step, 3.0):   # arrive within one step → no overshoot/vibration
		_boss_eo.position  = target_oc
		_phase             = Phase.M3_WARN
		_phase_acc         = 0.0
		_laser_flash_acc   = 0.0
		_laser_hit_done    = false
		_spawn_laser()
	else:
		_boss_eo.position += diff.normalized() * step

func _tick_m3_warn(delta: float) -> void:
	_phase_acc       += delta
	_laser_flash_acc += delta
	_update_laser_pos()
	queue_redraw()   # keep the ⚠ warning sign drawn during the warning
	if _laser_tr != null and is_instance_valid(_laser_tr):
		_laser_tr.visible = fmod(_laser_flash_acc, LASER_FLASH_CYC * 2.0) < LASER_FLASH_CYC
	if _phase_acc >= M3_WARN_T:
		_phase     = Phase.M3_FIRE
		_phase_acc = 0.0
		_laser_w   = LASER_W * LASER_FIRE_MULT   # actual fire expands to 5× the warning width
		if _laser_tr != null and is_instance_valid(_laser_tr):
			_laser_tr.visible  = true
			_laser_tr.modulate = Color.WHITE     # bright on the real shot (was dull during warning)
		queue_redraw()   # clear the warning sign now that it's firing

func _tick_m3_fire(delta: float) -> void:
	_phase_acc += delta
	_update_laser_pos()
	if not _laser_hit_done and _ship_eo != null and is_instance_valid(_ship_eo):
		var fp3 := _get_fp3_world()
		var laser_rect := Rect2(fp3.x - _laser_w / 2.0, fp3.y, _laser_w, OC_BOUNDS.end.y - fp3.y)
		var ship_rect  := _ship_hit_rect_oc()   # the ship's opaque region, centered on the visible ship
		if laser_rect.intersects(ship_rect):
			GameManager.ship_take_damage(int(round(LASER_DMG * BOSS_DAMAGE_MULT)))
			_laser_hit_done = true
	if _phase_acc >= M3_FIRE_T:
		if _laser_tr != null and is_instance_valid(_laser_tr):
			_laser_tr.queue_free()
			_laser_tr = null
		_m3_shots += 1
		if _m3_shots < 3:
			# Re-aim at the ship's CURRENT hitbox center, then slide there → warn → fire again.
			_m3_target_cx_oc = _ship_aim_point_oc().x
			_phase     = Phase.M3_MOVE
			_phase_acc = 0.0
		else:
			_begin_random_move()

# =============================================================================
# Move 4 — rotate 90° CW → move horizontally + fire drops
# =============================================================================

func _begin_m4() -> void:
	var go_left := randi() % 2 == 0
	_m4_dir = -1.0 if go_left else 1.0
	var start_ss := M4_START_RIGHT_SS if go_left else M4_START_LEFT_SS
	var entry_pos := start_ss + SS_OFFSET - _boss_eo.size / 2.0
	_phase     = Phase.M1_ENTRY
	_phase_acc = 0.0
	var tw := create_tween()
	tw.tween_property(_boss_eo, "position", entry_pos, 1.0) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(func() -> void:
		_boss_eo.pivot_offset = _boss_eo.size / 2.0
		_phase     = Phase.M4_ROT
		_phase_acc = 0.0)

func _tick_m4_rot(delta: float) -> void:
	_phase_acc += delta
	var t := minf(_phase_acc / M4_ROT_T, 1.0)
	_boss_eo.rotation = lerp(0.0, PI / 2.0, t)
	if t >= 1.0:
		_boss_eo.rotation = PI / 2.0
		_phase     = Phase.M4_TRAVEL
		_phase_acc = 0.0
		_m4_drop_acc = 0.0
		_m4_dropped_first = false
		_m4_dropped_last  = false

func _tick_m4_travel(delta: float) -> void:
	_boss_eo.position.x += _m4_dir * M4_TRAVEL_SPD * delta

	# Drop a full row of 8 bombs when the boss center crosses into the first / last
	# third of the map. Nothing in the middle third.
	var left := OC_BOUNDS.position.x
	var third_w := OC_BOUNDS.size.x / 3.0
	var center_x := _boss_eo.position.x + _boss_eo.size.x / 2.0
	if not _m4_dropped_first and center_x >= left and center_x <= left + third_w:
		_spawn_bomb_row(left, left + third_w)
		_m4_dropped_first = true
	if not _m4_dropped_last and center_x >= left + 2.0 * third_w:
		_spawn_bomb_row(left + 2.0 * third_w, OC_BOUNDS.end.x)
		_m4_dropped_last = true

	var hit_right := _m4_dir > 0 and _boss_eo.position.x >= OC_BOUNDS.end.x - _boss_eo.size.x
	var hit_left  := _m4_dir < 0 and _boss_eo.position.x <= OC_BOUNDS.position.x
	if hit_right or hit_left:
		_begin_random_move()

# Spawn 8 bombs evenly across [x0, x1] (OC space), each sized to the slot width so
# they sit adjacent without overlapping. They hover 0.5s then drop straight down fast.
func _spawn_bomb_row(x0: float, x1: float) -> void:
	if _drop_frames.is_empty():
		return
	var slot := (x1 - x0) / 8.0
	var sz := Vector2(slot, slot)
	var y_oc := _boss_eo.position.y + _boss_eo.size.y / 2.0
	for i in 8:
		var cx := x0 + (float(i) + 0.5) * slot
		var local_pos := Vector2(cx, y_oc) - OC_BOUNDS.position - sz / 2.0
		var tr := _make_projectile_rect(_drop_frames[0], sz, local_pos)
		_projectiles.append({
			"tr": tr, "vel": Vector2.ZERO,
			"rot_spd": 0.0, "rot": 0.0, "dmg": DROP_DMG, "type": "drop",
			"frames": _drop_frames, "delays": _drop_delays, "frame": 0, "acc": 0.0,
			"blink_acc": 0.0,
			"delay": 0.75, "fall_speed": DROP_SPEED,
		})

# =============================================================================
# Move 5 — rotate 90° CW + random wander + fire homing blobs
# =============================================================================

func _begin_m5() -> void:
	_boss_eo.pivot_offset = _boss_eo.size / 2.0
	_phase     = Phase.M5_ROT
	_phase_acc = 0.0

func _tick_m5_rot(delta: float) -> void:
	_phase_acc += delta
	var t := minf(_phase_acc / M5_ROT_T, 1.0)
	_boss_eo.rotation = lerp(0.0, PI / 2.0, t)
	if t >= 1.0:
		_boss_eo.rotation = PI / 2.0
		_phase       = Phase.M5_MOVE
		_phase_acc   = 0.0
		_m5_acc      = 0.0
		_m5_blob_acc = 0.0
		_m5_target   = _pick_m5_target()

func _pick_m5_target() -> Vector2:
	var max_y := OC_BOUNDS.position.y + M2_MAX_Y_SS - _boss_eo.size.y
	return Vector2(
		randf_range(OC_BOUNDS.position.x, OC_BOUNDS.end.x - _boss_eo.size.x),
		randf_range(OC_BOUNDS.position.y, max_y)
	)

func _tick_m5_move(delta: float) -> void:
	_m5_acc      += delta
	_m5_blob_acc += delta

	var diff := _m5_target - _boss_eo.position
	if diff.length() < 5.0:
		_m5_target = _pick_m5_target()
	else:
		_boss_eo.position += diff.normalized() * M5_MOVE_SPD * delta

	while _m5_blob_acc >= M5_BLOB_INT:
		_m5_blob_acc -= M5_BLOB_INT
		_fire_blob()

	if _m5_acc >= M5_DURATION:
		_begin_random_move()

func _fire_blob() -> void:
	if _blob_frames.is_empty():
		return
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var origin := _boss_eo.global_position + _boss_eo.size / 2.0
	var ship_ctr := _ship_aim_point_oc()
	var dir := (ship_ctr - origin)
	if dir == Vector2.ZERO:
		dir = Vector2(0.0, 1.0)
	else:
		dir = dir.normalized()
	var tex := _blob_frames[0] as Texture2D
	var sz  := tex.get_size()
	var local_pos := origin - OC_BOUNDS.position - sz / 2.0
	var tr := _make_projectile_rect(tex, sz, local_pos)
	_projectiles.append({
		"tr": tr, "vel": dir * BLOB_SPEED,
		"rot_spd": 0.0, "rot": 0.0, "dmg": BLOB_DMG, "type": "blob",
		"frames": _blob_frames, "delays": _blob_delays, "frame": 0, "acc": 0.0,
		"blink_acc": 0.0,
	})

# ── Laser helpers ─────────────────────────────────────────────────────────────

func _get_fp3_world() -> Vector2:
	if _boss_eo == null:
		return Vector2.ZERO
	if _fp3_node != null and is_instance_valid(_fp3_node):
		return _fp3_node.global_position   # Godot handles rotation+translation automatically
	return _boss_eo.global_position + _boss_eo.size / 2.0 + _fp3_off.rotated(_boss_eo.rotation)

func _spawn_laser() -> void:
	var fp3 := _get_fp3_world()
	# fp3 is in OC space; clip node is positioned at OC_BOUNDS.position, so we need local coords
	var local_fp3 := fp3 - OC_BOUNDS.position
	var h := OC_BOUNDS.size.y - local_fp3.y
	_laser_w = LASER_W   # warning starts thin; widens to 5× when it actually fires
	_laser_tr = TextureRect.new()
	_laser_tr.modulate     = LASER_WARN_MODULATE   # dull mask during the warning
	_laser_tr.size         = Vector2(_laser_w, maxf(h, 1.0))
	_laser_tr.position     = Vector2(local_fp3.x - _laser_w / 2.0, local_fp3.y)
	_laser_tr.stretch_mode = TextureRect.STRETCH_SCALE
	_laser_tr.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_laser_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_laser_tr.z_as_relative = false
	_laser_tr.z_index      = 160
	if not _laser_frames.is_empty():
		_laser_tr.texture = _laser_frames[0] as Texture2D
	else:
		var img := Image.create(1, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.15, 0.15, 1.0))
		_laser_tr.texture = ImageTexture.create_from_image(img)
	_clip_node.add_child(_laser_tr)

func _update_laser_pos() -> void:
	if _laser_tr == null or not is_instance_valid(_laser_tr):
		return
	var fp3 := _get_fp3_world()
	var local_fp3 := fp3 - OC_BOUNDS.position
	var h := OC_BOUNDS.size.y - local_fp3.y
	_laser_tr.position = Vector2(local_fp3.x - _laser_w / 2.0, local_fp3.y)
	_laser_tr.size     = Vector2(_laser_w, maxf(h, 1.0))

# =============================================================================
# Projectile spawning
# =============================================================================

func _spawn_spike(angle: float = -1.0) -> void:
	if _ball_anims.is_empty():
		return
	var origin  := _boss_eo.global_position + _boss_eo.size / 2.0
	var local_pos := origin - OC_BOUNDS.position
	var dir_angle := angle if angle >= 0.0 else randf() * TAU
	var ball_anim := _ball_anims[randi() % _ball_anims.size()] as Dictionary
	var frames: Array = ball_anim.get("frames", [])
	if frames.is_empty():
		return
	var ball_tex := frames[0] as Texture2D
	var orig_sz := ball_tex.get_size()
	var sz := orig_sz * 0.1
	var resized_frames: Array = []
	for frame in frames:
		resized_frames.append(_resize_tex(frame, sz))
	local_pos -= sz / 2.0
	var tr := _make_projectile_rect(resized_frames[0], sz, local_pos)
	# Radial launch + tangential kick from the boss's spin → fast, curving spray.
	var radial := Vector2.from_angle(dir_angle)
	var tangential := Vector2.from_angle(dir_angle + PI * 0.5)   # flip sign if it curves the wrong way
	var spike_vel := radial * SPIKE_SPEED + tangential * (M1_ROT_SPEED * SPIKE_SPIN_RADIUS)
	_projectiles.append({
		"tr": tr, "vel": spike_vel,
		"rot_spd": 0.0, "rot": 0.0, "dmg": SPIKE_DMG, "type": "ball",
		"frames": resized_frames, "delays": ball_anim.get("delays", []), "frame": 0, "acc": 0.0,
		"blink_acc": 0.0,
	})

func _fire_vortex(origin_oc: Vector2) -> void:
	if _vortex_frames.is_empty():
		return
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var ship_ctr  := _ship_aim_point_oc()
	var dir       := (ship_ctr - origin_oc)
	if dir == Vector2.ZERO:
		dir = Vector2(0.0, 1.0)
	else:
		dir = dir.normalized()
	var tex := _vortex_frames[0] as Texture2D
	var sz  := tex.get_size()
	var local_pos := origin_oc - OC_BOUNDS.position - sz / 2.0
	var tr := _make_projectile_rect(tex, sz, local_pos)
	_projectiles.append({
		"tr": tr, "vel": dir * VORTEX_SPEED,
		"rot_spd": VORTEX_ROT_SPEED, "rot": 0.0, "dmg": VORTEX_DMG, "type": "vortex",
		"frames": _vortex_frames, "delays": _vortex_delays, "frame": 0, "acc": 0.0,
		"blink_acc": 0.0,
	})

func _make_projectile_rect(tex: Texture2D, sz: Vector2, pos: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture        = tex
	tr.size           = sz
	tr.stretch_mode   = TextureRect.STRETCH_SCALE        # scale texture to fill control size
	tr.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	tr.pivot_offset   = sz / 2.0
	tr.position       = pos
	tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.z_as_relative  = false
	tr.z_index        = 150
	_clip_node.add_child(tr)
	return tr

# =============================================================================
# Projectile tick — move, animate, collide, blink
# =============================================================================

func _tick_projectiles(delta: float) -> void:
	# Lazy re-cache ship image if not yet available
	if _ship_img == null:
		_cache_ship_image()
	# Hit box = the ship sprite's opaque region (centered + scaled on the visible ship), in clip-local space.
	var ship_hit_local := Rect2()
	if _ship_eo != null and is_instance_valid(_ship_eo):
		var hit_oc := _ship_hit_rect_oc()
		ship_hit_local = Rect2(hit_oc.position - OC_BOUNDS.position, hit_oc.size)

	# Clip bounds in local space (0,0 to size)
	var clip_local := Rect2(Vector2.ZERO, OC_BOUNDS.size)

	var i := _projectiles.size() - 1
	while i >= 0:
		if i >= _projectiles.size():   # guard: array may have shrunk via re-entrancy
			i -= 1
			continue
		var p  : Dictionary = _projectiles[i]
		var tr : TextureRect = p["tr"]
		if not is_instance_valid(tr):
			_projectiles.remove_at(i)
			i -= 1
			continue

		# Hover delay (bomb rows): hold still, then start falling.
		var hover: float = float(p.get("delay", 0.0))
		if hover > 0.0:
			hover -= delta
			if hover <= 0.0:
				hover = 0.0
				p["vel"] = Vector2(0.0, float(p.get("fall_speed", DROP_SPEED)))
			p["delay"] = hover

		tr.position += (p["vel"] as Vector2) * delta

		# Rotation (vortex spins)
		if float(p["rot_spd"]) != 0.0:
			var r: float = float(p["rot"]) + float(p["rot_spd"]) * delta
			p["rot"]    = r
			tr.rotation = r

		# Animate GIF frames (vortex)
		var frames: Array = p.get("frames", [])
		if not frames.is_empty():
			var fa: float = float(p.get("acc", 0.0)) + delta
			var fi: int   = int(p.get("frame", 0))
			var d: Array  = p.get("delays", [])
			var fd: float = float(d[fi]) if fi < d.size() else 0.05
			if fa >= fd:
				fa -= fd
				fi  = (fi + 1) % frames.size()
				tr.texture = frames[fi] as Texture2D
			p["acc"]   = fa
			p["frame"] = fi

		# Blink effect (spikes only)
		if p.get("type") == "spike":
			var ba: float = float(p.get("blink_acc", 0.0)) + delta
			p["blink_acc"] = ba
			var blink := sin(ba * TAU * 5.0) * 0.5 + 0.5
			tr.modulate = Color(1.0, 0.6 + blink * 0.4, blink * 0.2, 1.0)

		# Collision: overlap with the ship's opaque hit box.
		var proj_rect := Rect2(tr.position, tr.size)
		if ship_hit_local != Rect2() and proj_rect.intersects(ship_hit_local):
			GameManager.ship_take_damage(int(round(float(p["dmg"]) * BOSS_DAMAGE_MULT)))
			_flash_ship_red()
			tr.queue_free()
			_projectiles.remove_at(i)
			i -= 1
			continue

		# Cull when fully outside clip area
		var center := tr.position + tr.size / 2.0
		if not clip_local.grow(60.0).has_point(center):
			tr.queue_free()
			_projectiles.remove_at(i)
		else:
			_projectiles[i] = p

		i -= 1

# =============================================================================
# Helpers
# =============================================================================

func _ship_scaled_rect_oc() -> Rect2:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return Rect2()
	var sc  := _ship_eo.scale.x
	var sz  := _ship_eo.size * sc
	var ctr := _ship_eo.global_position + _ship_eo.size * 0.5
	return Rect2(ctr - sz * 0.5, sz)

## Hitbox = the ship sprite's opaque region, mapped through the TextureRect's REAL global
## transform (which already bakes in the ship's position, center pivot, scale and parents).
## No manual reconstruction — tracks the visible ship exactly at any scale.
func _ship_hit_rect_oc() -> Rect2:
	if _ship_eo == null or not is_instance_valid(_ship_eo) or _ship_eo.texture_rect == null:
		return Rect2()
	var tr: TextureRect = _ship_eo.texture_rect
	var full: Vector2 = tr.size
	var xf := tr.get_global_transform()
	var a := xf * (_ship_alpha_uv.position * full)
	var b := xf * ((_ship_alpha_uv.position + _ship_alpha_uv.size) * full)
	var top_left := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	return Rect2(top_left, (a - b).abs())

## Single source of truth for boss aiming: the player's true hitbox center
## (opaque region via the real transform), in OC/global space. All player-aimed
## attacks (vortex, blob, laser) target this so shots track the visible ship at any scale.
func _ship_aim_point_oc() -> Vector2:
	var hr := _ship_hit_rect_oc()
	if hr.size != Vector2.ZERO:
		return hr.position + hr.size / 2.0
	if _ship_eo != null and is_instance_valid(_ship_eo):
		return _ship_eo.global_position + _ship_eo.size / 2.0   # fallback
	return OC_BOUNDS.get_center()

func _ship_tight_rect_oc() -> Rect2:
	var full := _ship_scaled_rect_oc()
	if full.size == Vector2.ZERO:
		return Rect2()
	return Rect2(full.position + _ship_tight_uv.position * full.size,
				 _ship_tight_uv.size * full.size)

func _cleanup_projectiles() -> void:
	for p in _projectiles:
		var tr = p.get("tr")
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
	_projectiles.clear()

func _pixel_hit(tr: TextureRect, proj_rect: Rect2, ship_rect: Rect2) -> bool:
	# Get projectile image (CPU-resized ImageTexture → get_image() always works)
	var proj_img := tr.texture.get_image() if tr.texture != null else null
	# Need projectile image; also need at least one ship image source
	if proj_img == null:
		return false
	if _ship_hitbox_img == null and _ship_img == null:
		return false
	var overlap := proj_rect.intersection(ship_rect)
	if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
		return false
	# Sample every 2px for performance
	var step := 2
	for yi in range(0, int(overlap.size.y) + 1, step):
		for xi in range(0, int(overlap.size.x) + 1, step):
			var pt := overlap.position + Vector2(xi, yi)
			# Projectile UV → pixel
			var pu := (pt.x - proj_rect.position.x) / proj_rect.size.x
			var pv := (pt.y - proj_rect.position.y) / proj_rect.size.y
			var ppx := clampi(int(pu * proj_img.get_width()),  0, proj_img.get_width()  - 1)
			var ppy := clampi(int(pv * proj_img.get_height()), 0, proj_img.get_height() - 1)
			if proj_img.get_pixel(ppx, ppy).a < 0.15:
				continue
			# Ship UV → check against hitbox image (black pixels) or ship texture (alpha)
			var su := (pt.x - ship_rect.position.x) / ship_rect.size.x
			var sv := (pt.y - ship_rect.position.y) / ship_rect.size.y
			if _ship_hitbox_img != null:
				var spx := clampi(int(su * _ship_hitbox_img.get_width()),  0, _ship_hitbox_img.get_width()  - 1)
				var spy := clampi(int(sv * _ship_hitbox_img.get_height()), 0, _ship_hitbox_img.get_height() - 1)
				var sp := _ship_hitbox_img.get_pixel(spx, spy)
				if sp.a < 0.1 or sp.get_luminance() > 0.15:
					continue   # not a black hitbox pixel
			elif _ship_img != null:
				var spx := clampi(int(su * _ship_img.get_width()),  0, _ship_img.get_width()  - 1)
				var spy := clampi(int(sv * _ship_img.get_height()), 0, _ship_img.get_height() - 1)
				if _ship_img.get_pixel(spx, spy).a < 0.15:
					continue
			return true   # both pixels opaque: real hit
	return false

func _flash_ship_red() -> void:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var tw := create_tween()
	tw.tween_property(_ship_eo, "modulate", Color(2.0, 0.2, 0.2, 1.0), 0.05)
	tw.tween_property(_ship_eo, "modulate", Color.WHITE, 0.3)

func _resize_tex(tex: Texture2D, target_sz: Vector2) -> Texture2D:
	# CPU-side resize (bilinear) → ImageTexture. Pattern: fixed-size bullets pre-cached.
	# Tier-specific sizes (10%, 20%) resized at load; frames cached for reuse on spawn.
	var img := tex.get_image()
	if img == null:
		return tex   # fallback: STRETCH_SCALE in _make_projectile_rect will handle
	var copy := img.duplicate() as Image
	copy.resize(int(target_sz.x), int(target_sz.y), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(copy)

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
		elif base == "elephant":
			_boss_eo = eo
			for sub in eo.get_children():
				var seo := sub as EditableObjectNode
				if seo != null:
					_spike_eos.append(seo)
		elif base == "spaceshiphitbox":
			eo.visible = false
			eo.layer_visible = false   # keep hidden through set_gameplay_mode() refreshes
	# Cache ship image for pixel-perfect collision (update after finding ship EO)
	_cache_ship_image()

func _cache_ship_image() -> void:
	_ship_img      = null
	_ship_tight_uv = Rect2(0.0, 0.0, 1.0, 1.0)
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var tex := _ship_eo.texture_rect.texture if _ship_eo.texture_rect != null else null
	if tex == null:
		return
	_ship_img = tex.get_image()
	if _ship_img != null:
		_ship_tight_uv = _compute_tight_uv_black(_ship_img)
		_ship_alpha_uv = _compute_tight_uv(_ship_img)   # opaque region of the visible ship
		_create_ship_hitbox_node()

func _create_ship_hitbox_node() -> void:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	if _ship_hitbox_node == null:
		_ship_hitbox_node = Control.new()
	var tight := _ship_tight_uv
	var sz := _ship_eo.size
	_ship_hitbox_node.position = Vector2(tight.position.x * sz.x, tight.position.y * sz.y)
	_ship_hitbox_node.size     = Vector2(tight.size.x * sz.x, tight.size.y * sz.y)

func _compute_tight_uv(img: Image) -> Rect2:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w;  var max_x := -1
	var min_y := h;  var max_y := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
	if max_x < 0:
		return Rect2(0.0, 0.0, 1.0, 1.0)   # no opaque pixels → fallback full rect
	return Rect2(
		float(min_x) / w,
		float(min_y) / h,
		float(max_x - min_x + 1) / w,
		float(max_y - min_y + 1) / h
	)

func _load_fp_offsets() -> void:
	if _boss_eo == null:
		return
	var boss_center := _boss_eo.global_position + _boss_eo.size / 2.0
	var cfg := ConfigFile.new()
	if cfg.load("res://boss_layout.cfg") != OK:
		return
	for fp: Dictionary in cfg.get_value("firepoints", "elephant", []):
		var fp_id:  int     = fp.get("id", 0)
		var fp_oc:  Vector2 = (fp.get("pos", Vector2.ZERO) as Vector2) + SS_OFFSET
		var offset := fp_oc - boss_center
		match fp_id:
			1: _fp1_off = offset
			2: _fp2_off = offset
			3: _fp3_off = offset
	if _fp3_off == Vector2.ZERO and _boss_eo != null:
		_fp3_off = Vector2(_boss_eo.size.x / 2.0, 0.0)
	_create_fp_nodes()

func _create_fp_nodes() -> void:
	if _boss_eo == null:
		return
	_fp1_node = _make_fp_node(_fp1_off)
	_fp2_node = _make_fp_node(_fp2_off)
	_fp3_node = _make_fp_node(_fp3_off)

func _make_fp_node(off: Vector2) -> Node2D:
	var n := Node2D.new()
	# In boss EO local space: pivot (size/2) + fp_offset
	n.position = _boss_eo.size / 2.0 + off
	_boss_eo.add_child(n)
	return n

func _load_hitbox_image() -> void:
	var tex := load("res://assets/weaponry/Spaceshiphitbox.png") as Texture2D
	if tex == null:
		return
	_ship_hitbox_img = tex.get_image()
	if _ship_hitbox_img != null:
		_ship_tight_uv = _compute_tight_uv_black(_ship_hitbox_img)

func _compute_tight_uv_black(img: Image) -> Rect2:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w;  var max_x := -1
	var min_y := h;  var max_y := -1
	for y in h:
		for x in w:
			var px := img.get_pixel(x, y)
			if px.a > 0.0 and px.get_luminance() < 0.15:  # black pixel
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
	if max_x < 0:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	return Rect2(
		float(min_x)            / w, float(min_y)            / h,
		float(max_x - min_x + 1) / w, float(max_y - min_y + 1) / h
	)

func _load_assets() -> void:
	_load_hitbox_image()
	var vt := GifLoader.load_gif("res://assets/bosses/elephant/firevortex.gif")
	if vt != null:
		_vortex_frames = vt.get_meta("gif_frames") if vt.has_meta("gif_frames") else [vt]
		_vortex_delays = vt.get_meta("gif_delays") if vt.has_meta("gif_delays") else [0.05]
	var lt := GifLoader.load_gif("res://assets/bosses/elephant/laser.gif")
	if lt != null:
		_laser_frames = lt.get_meta("gif_frames") if lt.has_meta("gif_frames") else [lt]
	for ball_idx in range(1, 5):
		var bt := GifLoader.load_gif("res://assets/bosses/elephant/ball%d.gif" % ball_idx)
		if bt != null:
			var frames = bt.get_meta("gif_frames") if bt.has_meta("gif_frames") else [bt]
			var delays = bt.get_meta("gif_delays") if bt.has_meta("gif_delays") else [0.05]
			_ball_anims.append({
				"frames": frames,
				"delays": delays,
			})
	var dt := GifLoader.load_gif("res://assets/bosses/elephant/drop.gif")
	if dt != null:
		var raw_frames = dt.get_meta("gif_frames") if dt.has_meta("gif_frames") else [dt]
		_drop_delays = dt.get_meta("gif_delays") if dt.has_meta("gif_delays") else [0.05]
		if not raw_frames.is_empty():
			var orig_sz := (raw_frames[0] as Texture2D).get_size()
			_drop_size = orig_sz * 0.2
			for frame in raw_frames:
				_drop_frames.append(_resize_tex(frame, _drop_size))
	var blt := GifLoader.load_gif("res://assets/bosses/elephant/blob.gif")
	if blt != null:
		_blob_frames = blt.get_meta("gif_frames") if blt.has_meta("gif_frames") else [blt]
		_blob_delays = blt.get_meta("gif_delays") if blt.has_meta("gif_delays") else [0.05]
