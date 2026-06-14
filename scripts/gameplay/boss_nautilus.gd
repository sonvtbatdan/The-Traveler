extends Control

# =============================================================================
# Boss Nautilus — Full implementation
# Phase 1 (broken): 500 shield absorbs damage, 4 attack moves, broken.gif
# Phase 2 (recovery): heals shield every 3 s, Recover.gif, no attacks
# =============================================================================

const SS_OFFSET := Vector2(15.0, 8.0)
const OC_BOUNDS := Rect2(15.0, 8.0, 955.0, 764.0)

const GifLoader := preload("res://scripts/ui/edit_mode/gif_loader.gd")

# ── Boss stats ─────────────────────────────────────────────────────────────────
const BOSS_MAX_HP     := 2000
const SHIELD_MAX      := 500.0
const SHIELD_PER_STEP := 62.5      # one frame advance per this much shield lost
const RECOVER_INTERVAL := 3.0      # seconds per heal tick in Phase 2

# ── Visual ─────────────────────────────────────────────────────────────────────
const DEFAULT_ROT  := PI / 2.0     # 90° clockwise default orientation
const WANDER_SPEED := 35.0
const WANDER_CHANGE := 3.0
const WANDER_P1_MAX_Y := 508.0     # OC Y cap for Phase 1 wander (SS Y < 500)

# ── Move 1 — Crawling ──────────────────────────────────────────────────────────
const M1_SPEED      := 360.0
const M1_DROP       := 100.0
const M1_END_Y      := 758.0        # OC Y at which crawl ends (SS Y = 750)
const M1_START_OC   := Vector2(15.0, 158.0)    # SS (0, 150)
const M1_RIGHT_X    := 970.0        # OC X right edge (SS X = 955)
const M1_LEFT_X     := 15.0         # OC X left edge  (SS X = 0)
const M1_CONTACT_DMG := 30

# ── Move 2 — Shooting Star ─────────────────────────────────────────────────────
const M2_START_OC      := Vector2(370.0, 158.0)   # SS (100, 150)
const M2_END_OC        := Vector2(870.0, 158.0)   # SS (600, 150)
const M2_DURATION      := 2.0
const M2_BURST_TIMES   := [0.3, 1.0, 1.7]
const STAR_SPEED       := 120.0
const STAR_SPLIT_DIST  := 100.0
const CHILD_STAR_SPEED := 80.0
const STAR_DMG         := 15

# ── Move 3 — Turbulence ────────────────────────────────────────────────────────
const M3_DURATION  := 5.0
const M3_SPEED     := 100.0
const M3_RPM       := 30.0
const M3_FIRE_RATE := 0.1          # seconds between dot bursts
const DOT_SPEED    := 90.0
const DOT_DMG      := 10

# ── Move 4 — Shooting Wave ─────────────────────────────────────────────────────
const M4_SPEED      := 100.0
const M4_FIRE_RATE  := 0.5
const M4_VOLLEYS    := 5
const M4_BULLET_SPD := 180.0
const WAVE_DMG      := 10

# =============================================================================
# Phase enum
# =============================================================================
enum Phase {
	IDLE,
	BROKEN_WANDER,  # Phase 1 intermediate
	M1_SETUP,       # un-rotate tween + move to start  (also reused mid-tween by M3 end)
	M1_CRAWL,
	M2_FLY,
	M3_TURB,
	M4_WAVE,
	RECOVERY,       # Phase 2
	DONE
}

var _phase := Phase.IDLE

# ── Scene refs ─────────────────────────────────────────────────────────────────
var _objects_container: Control = null
var _boss_tr:   TextureRect = null
var _clip_node: Control     = null

# ── Animation ──────────────────────────────────────────────────────────────────
var _broken_frames:     Array[Texture2D] = []
var _broken_delays:     Array[float]     = []
var _broken_frame_idx:  int = 0

var _recover_frames:    Array[Texture2D] = []
var _recover_delays:    Array[float]     = []
var _recover_frame_idx: int = 0
var _recover_ticks:     int = 0
var _recover_timer:   float = 0.0

# ── HP / Shield ────────────────────────────────────────────────────────────────
var _current_hp:   int   = 0
var _shield:      float  = SHIELD_MAX
var _restoring_hp := false

# ── Bars ───────────────────────────────────────────────────────────────────────
var _hp_bar_bg:      ColorRect = null
var _hp_bar_fg:      ColorRect = null
var _hp_bar_lbl:     Label     = null
var _shield_bar_bg:  ColorRect = null
var _shield_bar_fg:  ColorRect = null
var _shield_bar_lbl: Label     = null

# ── Fire points ────────────────────────────────────────────────────────────────
var _fp1_off := Vector2.ZERO
var _fp2_off := Vector2.ZERO
var _fp3_off := Vector2.ZERO
var _fp4_off := Vector2.ZERO
var _fp5_off := Vector2.ZERO
var _fp6_off := Vector2.ZERO
var _fp1_node: Node2D = null
var _fp2_node: Node2D = null
var _fp3_node: Node2D = null
var _fp4_node: Node2D = null
var _fp5_node: Node2D = null
var _fp6_node: Node2D = null

# ── Projectiles ────────────────────────────────────────────────────────────────
var _projectiles:    Array = []
var _star_tex:       ImageTexture = null
var _child_star_tex: ImageTexture = null
var _dot_tex:        ImageTexture = null
var _wave_tex:       ImageTexture = null

# ── Wander shared state ────────────────────────────────────────────────────────
var _wander_vel   := Vector2.ZERO
var _wander_timer := 0.0
var _attack_timer := 0.0           # time until next move in BROKEN_WANDER

# ── M1 ────────────────────────────────────────────────────────────────────────
var _crawl_dir: int  = 1
var _m1_tween: Tween = null

# ── M2 ────────────────────────────────────────────────────────────────────────
var _m2_timer:       float = 0.0
var _m2_burst_fired: Array = []   # [bool, bool, bool]
var _m2_tween: Tween = null

# ── M3 ────────────────────────────────────────────────────────────────────────
var _m3_timer:     float = 0.0
var _m3_fire_acc:  float = 0.0
var _m3_dir_timer: float = 0.0

# ── M4 ────────────────────────────────────────────────────────────────────────
var _m4_fire_acc:  float = 0.0
var _m4_volleys:   int   = 0
var _m4_dir_timer: float = 0.0
var _m4_done:      bool  = false

# ── Flash ─────────────────────────────────────────────────────────────────────
var _flash_tween: Tween = null


# =============================================================================
# Setup
# =============================================================================
func setup(oc: Control) -> void:
	_objects_container = oc
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	process_mode = Node.PROCESS_MODE_PAUSABLE
	visible = false
	_load_assets()


# =============================================================================
# Asset loading
# =============================================================================
func _load_assets() -> void:
	_broken_frames  = _extract_frames("res://assets/bosses/nautilus/broken.gif")
	_broken_delays  = _extract_delays("res://assets/bosses/nautilus/broken.gif")
	_recover_frames = _extract_frames("res://assets/bosses/nautilus/Recover.gif")
	_recover_delays = _extract_delays("res://assets/bosses/nautilus/Recover.gif")
	_star_tex       = _make_star_texture(20, Color.WHITE)
	_child_star_tex = _make_star_texture(12, Color.WHITE)
	_dot_tex        = _make_dot_texture(8, Color(1.0, 0.15, 0.15))
	_wave_tex       = _make_dot_texture(7, Color(0.6, 0.8, 1.0))


func _extract_frames(path: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var tex := GifLoader.load_gif(path)
	if tex == null:
		return out
	if tex.has_meta("gif_frames"):
		for f in tex.get_meta("gif_frames"):
			out.append(f as Texture2D)
	elif tex is Texture2D:
		out.append(tex as Texture2D)
	return out


func _extract_delays(path: String) -> Array[float]:
	var out: Array[float] = []
	var tex := GifLoader.load_gif(path)
	if tex == null:
		return out
	if tex.has_meta("gif_delays"):
		for d in tex.get_meta("gif_delays"):
			out.append(float(d))
	else:
		out.append(0.1)
	return out


static func _make_star_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx    := size / 2.0
	var cy    := size / 2.0
	var r_out := size * 0.5
	var r_in  := size * 0.22
	for y: int in size:
		for x: int in size:
			var dx := x - cx
			var dy := y - cy
			var dist := sqrt(dx * dx + dy * dy)
			if dist > r_out:
				continue
			var ang := atan2(dy, dx)
			var sector := fmod(ang + TAU, TAU) / (TAU / 5.0)
			var t := fmod(sector, 1.0)
			var r_edge: float = lerp(r_out, r_in, absf(t * 2.0 - 1.0))
			if dist <= r_edge:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


static func _make_dot_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := size / 2.0
	var cy := size / 2.0
	var r  := size * 0.5
	for y: int in size:
		for x: int in size:
			var dx := x - cx
			var dy := y - cy
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= r:
				var alpha := 1.0 - (dist / r) * 0.6
				img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(img)


# =============================================================================
# Arena / Spawn
# =============================================================================
func setup_arena() -> void:
	var bg := get_tree().get_first_node_in_group("scrolling_bg")
	if is_instance_valid(bg) and bg.has_method("swap_texture"):
		bg.swap_texture("res://assets/bosses/nautilus/background.png")
	var ov := get_tree().get_first_node_in_group("scrolling_overlay")
	if is_instance_valid(ov) and ov.has_method("swap_texture"):
		ov.swap_texture("res://assets/bosses/nautilus/overlay.png")
		ov.set_speed_mult(2.0)


func spawn_boss() -> void:
	_current_hp = BOSS_MAX_HP
	_shield     = SHIELD_MAX
	GameManager.boss_max_hp = BOSS_MAX_HP
	GameManager.boss_hp     = BOSS_MAX_HP
	GameManager.boss_spawned.emit()

	_broken_frame_idx  = 0
	_recover_frame_idx = 0
	_recover_ticks     = 0
	_recover_timer     = 0.0
	_m4_done           = false
	for p: Dictionary in _projectiles:
		var tr: TextureRect = p.get("tr")
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
	_projectiles.clear()

	_build_clip_node()
	_build_boss_tr()
	_build_bars()
	_load_fp_offsets()
	visible = true


func _build_clip_node() -> void:
	if _clip_node != null and is_instance_valid(_clip_node):
		_clip_node.queue_free()
	_clip_node = Control.new()
	_clip_node.position     = OC_BOUNDS.position
	_clip_node.size         = OC_BOUNDS.size
	_clip_node.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_clip_node.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_clip_node)


func _build_boss_tr() -> void:
	if _boss_tr != null and is_instance_valid(_boss_tr):
		_boss_tr.queue_free()
	_boss_tr = TextureRect.new()
	_boss_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_boss_tr.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_boss_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var first := _broken_frames[0] if not _broken_frames.is_empty() else null
	if first != null:
		_boss_tr.texture = first
		_boss_tr.size    = Vector2(first.get_width(), first.get_height())
	else:
		_boss_tr.size = Vector2(80.0, 80.0)
	_boss_tr.pivot_offset = _boss_tr.size * 0.5
	_boss_tr.position = Vector2(620.0 - _boss_tr.size.x * 0.5, 158.0 - _boss_tr.size.y * 0.5)
	_boss_tr.rotation = DEFAULT_ROT
	add_child(_boss_tr)


# ── Fire points ────────────────────────────────────────────────────────────────
func _load_fp_offsets() -> void:
	if _boss_tr == null:
		return
	var boss_center := _boss_tr.position + _boss_tr.size / 2.0
	var cfg := ConfigFile.new()
	if cfg.load("res://boss_layout.cfg") != OK:
		return
	for fp: Dictionary in cfg.get_value("firepoints", "nautilus_broken", []):
		var fp_oc: Vector2 = (fp.get("pos", Vector2.ZERO) as Vector2) + SS_OFFSET
		var off := fp_oc - boss_center
		match int(fp.get("id", 0)):
			1: _fp1_off = off
			2: _fp2_off = off
			3: _fp3_off = off
			4: _fp4_off = off
			5: _fp5_off = off
			6: _fp6_off = off
	_create_fp_nodes()


func _create_fp_nodes() -> void:
	for nd: Node2D in [_fp1_node, _fp2_node, _fp3_node, _fp4_node, _fp5_node, _fp6_node]:
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	_fp1_node = _make_fp_node(_fp1_off)
	_fp2_node = _make_fp_node(_fp2_off)
	_fp3_node = _make_fp_node(_fp3_off)
	_fp4_node = _make_fp_node(_fp4_off)
	_fp5_node = _make_fp_node(_fp5_off)
	_fp6_node = _make_fp_node(_fp6_off)


func _make_fp_node(off: Vector2) -> Node2D:
	var n := Node2D.new()
	n.position = _boss_tr.size / 2.0 + off
	_boss_tr.add_child(n)
	return n


func _fp_world(n: Node2D) -> Vector2:
	if n == null or not is_instance_valid(n):
		return _boss_tr.global_position + _boss_tr.size / 2.0 if _boss_tr != null else Vector2.ZERO
	return n.global_position


# =============================================================================
# HP / Shield bars
# =============================================================================
func _build_bars() -> void:
	if _hp_bar_bg != null and is_instance_valid(_hp_bar_bg):
		_hp_bar_bg.queue_free()
	if _shield_bar_bg != null and is_instance_valid(_shield_bar_bg):
		_shield_bar_bg.queue_free()

	_shield_bar_bg = ColorRect.new()
	_shield_bar_bg.color = Color(0.05, 0.1, 0.15, 0.8)
	_shield_bar_bg.size  = Vector2(120.0, 10.0)
	add_child(_shield_bar_bg)
	_shield_bar_fg = ColorRect.new()
	_shield_bar_fg.color = Color(0.2, 0.7, 0.9, 0.9)
	_shield_bar_fg.size  = Vector2(120.0, 10.0)
	_shield_bar_bg.add_child(_shield_bar_fg)
	_shield_bar_lbl = Label.new()
	_shield_bar_lbl.add_theme_font_size_override("font_size", 9)
	_shield_bar_lbl.add_theme_color_override("font_color", Color.WHITE)
	_shield_bar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shield_bar_lbl.size = Vector2(120.0, 10.0)
	_shield_bar_bg.add_child(_shield_bar_lbl)

	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	_hp_bar_bg.size  = Vector2(120.0, 10.0)
	add_child(_hp_bar_bg)
	_hp_bar_fg = ColorRect.new()
	_hp_bar_fg.color = Color(0.85, 0.25, 0.25, 0.9)
	_hp_bar_fg.size  = Vector2(120.0, 10.0)
	_hp_bar_bg.add_child(_hp_bar_fg)
	_hp_bar_lbl = Label.new()
	_hp_bar_lbl.add_theme_font_size_override("font_size", 9)
	_hp_bar_lbl.add_theme_color_override("font_color", Color.WHITE)
	_hp_bar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_bar_lbl.size = Vector2(120.0, 10.0)
	_hp_bar_bg.add_child(_hp_bar_lbl)

	_shield_bar_bg.visible = false
	_hp_bar_bg.visible     = false

	_update_bars()


func _update_bars() -> void:
	if _boss_tr == null or not is_instance_valid(_boss_tr):
		return
	var bp  := _boss_tr.position
	var bw  := _boss_tr.size.x
	var bar_x := bp.x + (bw - 120.0) * 0.5

	if _shield_bar_bg != null and is_instance_valid(_shield_bar_bg):
		_shield_bar_bg.position = Vector2(bar_x, bp.y - 28.0)
		var sfrac := clampf(_shield / SHIELD_MAX, 0.0, 1.0)
		(_shield_bar_fg as ColorRect).size = Vector2(120.0 * sfrac, 10.0)
		(_shield_bar_lbl as Label).text = "%.0f / %.0f" % [_shield, SHIELD_MAX]

	if _hp_bar_bg != null and is_instance_valid(_hp_bar_bg):
		_hp_bar_bg.position = Vector2(bar_x, bp.y - 16.0)
		var hfrac := clampf(float(_current_hp) / float(BOSS_MAX_HP), 0.0, 1.0)
		(_hp_bar_fg as ColorRect).size = Vector2(120.0 * hfrac, 10.0)
		(_hp_bar_lbl as Label).text = "%d / %d" % [_current_hp, BOSS_MAX_HP]


# =============================================================================
# Intro hook — null → boss_fight uses tween_interval
# =============================================================================
func get_intro_eo() -> EditableObjectNode:
	return null


# =============================================================================
# Fight start
# =============================================================================
func start_fight() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.BROKEN_WANDER
	_pick_wander_dir()
	_attack_timer = randf_range(2.0, 4.0)


# =============================================================================
# Phase helper
# =============================================================================
func _phase_is_broken() -> bool:
	return _phase in [
		Phase.BROKEN_WANDER, Phase.M1_SETUP, Phase.M1_CRAWL,
		Phase.M2_FLY, Phase.M3_TURB, Phase.M4_WAVE
	]


# =============================================================================
# Per-frame dispatch
# =============================================================================
func _process(delta: float) -> void:
	if not visible or _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	if GameManager.boss_intro_active:
		return

	match _phase:
		Phase.BROKEN_WANDER: _tick_broken_wander(delta)
		Phase.M1_CRAWL:      _tick_m1_crawl(delta)
		Phase.M2_FLY:        _tick_m2(delta)
		Phase.M3_TURB:       _tick_m3(delta)
		Phase.M4_WAVE:       _tick_m4(delta)
		Phase.RECOVERY:      _tick_recovery(delta)

	_tick_projectiles(delta)
	_update_bars()


# =============================================================================
# Phase 1 — Broken wander (intermediate state)
# =============================================================================
func _pick_wander_dir() -> void:
	var angle  := randf() * TAU
	_wander_vel   = Vector2(cos(angle), sin(angle)) * WANDER_SPEED
	_wander_timer = WANDER_CHANGE + randf() * 1.5


func _tick_broken_wander(delta: float) -> void:
	_tick_wander_move(delta, true)
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_pick_attack()


func _tick_wander_move(delta: float, restrict_y: bool) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_dir()
	_apply_vel_move(delta, restrict_y)


func _apply_vel_move(delta: float, restrict_y: bool) -> void:
	if _boss_tr == null or not is_instance_valid(_boss_tr):
		return
	var new_pos := _boss_tr.position + _wander_vel * delta
	var mg   := 20.0
	var mn_x := OC_BOUNDS.position.x + mg
	var mx_x := OC_BOUNDS.position.x + OC_BOUNDS.size.x - _boss_tr.size.x - mg
	var mn_y := OC_BOUNDS.position.y + mg
	var mx_y := OC_BOUNDS.position.y + OC_BOUNDS.size.y - _boss_tr.size.y - mg
	if restrict_y:
		mx_y = minf(mx_y, WANDER_P1_MAX_Y - _boss_tr.size.y)
	new_pos.x = clampf(new_pos.x, mn_x, mx_x)
	new_pos.y = clampf(new_pos.y, mn_y, mx_y)
	if new_pos.x <= mn_x or new_pos.x >= mx_x:
		_wander_vel.x = -_wander_vel.x
	if new_pos.y <= mn_y or new_pos.y >= mx_y:
		_wander_vel.y = -_wander_vel.y
	_boss_tr.position = new_pos


func _pick_attack() -> void:
	match randi() % 4:
		0: _enter_m1()
		1: _enter_m2()
		2: _enter_m3()
		3: _enter_m4()


func _return_to_wander() -> void:
	if _phase == Phase.DONE or _phase == Phase.RECOVERY:
		return
	_phase = Phase.BROKEN_WANDER
	if _boss_tr != null and is_instance_valid(_boss_tr):
		_boss_tr.rotation = DEFAULT_ROT
		_boss_tr.scale    = Vector2.ONE
	_pick_wander_dir()
	_attack_timer = randf_range(2.0, 4.0)
	_sync_broken_texture()


# =============================================================================
# Move 1 — Crawling
# =============================================================================
func _enter_m1() -> void:
	_phase = Phase.M1_SETUP
	if _m1_tween != null and _m1_tween.is_running():
		_m1_tween.kill()
	_m1_tween = create_tween().set_parallel(false)
	_m1_tween.tween_property(_boss_tr, "rotation", 0.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var target_pos := M1_START_OC - _boss_tr.size / 2.0
	_m1_tween.tween_property(_boss_tr, "position", target_pos, 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_m1_tween.tween_callback(_begin_m1_crawl)


func _begin_m1_crawl() -> void:
	if _phase != Phase.M1_SETUP:
		return
	_phase     = Phase.M1_CRAWL
	_crawl_dir = 1
	if _boss_tr != null and is_instance_valid(_boss_tr):
		_boss_tr.scale = Vector2.ONE


func _tick_m1_crawl(delta: float) -> void:
	if _boss_tr == null or not is_instance_valid(_boss_tr):
		return

	# Contact damage
	var boss_rect := get_boss_hit_rect()
	var ship_rect := _ship_hit_rect_oc()
	if boss_rect.has_area() and ship_rect.has_area() and boss_rect.intersects(ship_rect):
		GameManager.ship_take_damage(M1_CONTACT_DMG)
		_flash_ship_red()

	var pos     := _boss_tr.position
	var right_x := M1_RIGHT_X - _boss_tr.size.x
	var left_x  := M1_LEFT_X

	pos.x += float(_crawl_dir) * M1_SPEED * delta

	if _crawl_dir > 0 and pos.x >= right_x:
		pos.x = right_x
		pos.y += M1_DROP
		_crawl_dir = -1
		_boss_tr.scale = Vector2(-1.0, 1.0)
	elif _crawl_dir < 0 and pos.x <= left_x:
		pos.x = left_x
		pos.y += M1_DROP
		_crawl_dir = 1
		_boss_tr.scale = Vector2.ONE

	_boss_tr.position = pos

	if pos.y + _boss_tr.size.y >= M1_END_Y:
		_end_m1()


func _end_m1() -> void:
	_phase = Phase.M1_SETUP
	if _m1_tween != null and _m1_tween.is_running():
		_m1_tween.kill()
	# Tween target: move boss back into wander zone before resuming wander.
	# Without this, _apply_vel_move instantly clamps Y from ~758 to ~428 → jerk.
	var target_y   := WANDER_P1_MAX_Y - _boss_tr.size.y - 20.0
	var target_pos := Vector2(_boss_tr.position.x, target_y)
	var return_t   := clampf(absf(_boss_tr.position.y - target_y) / 300.0, 0.3, 2.0)
	_m1_tween = create_tween()
	_m1_tween.tween_property(_boss_tr, "rotation", DEFAULT_ROT, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_m1_tween.tween_property(_boss_tr, "position", target_pos, return_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_m1_tween.tween_callback(_return_to_wander)


# =============================================================================
# Move 2 — Shooting Star
# =============================================================================
func _enter_m2() -> void:
	_phase = Phase.M2_FLY
	_m2_timer = -1.0          # negative = still approaching start, bursts not active
	_m2_burst_fired = [false, false, false]
	if _m2_tween != null and _m2_tween.is_running():
		_m2_tween.kill()
	var start_pos := Vector2(M2_START_OC.x - _boss_tr.size.x / 2.0,
							 M2_START_OC.y - _boss_tr.size.y / 2.0)
	var end_pos   := Vector2(M2_END_OC.x   - _boss_tr.size.x / 2.0,
							 M2_END_OC.y   - _boss_tr.size.y / 2.0)
	var dist := _boss_tr.position.distance_to(start_pos)
	var approach_t := clampf(dist / 300.0, 0.15, 2.0)
	_m2_tween = create_tween()
	_m2_tween.tween_property(_boss_tr, "position", start_pos, approach_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_m2_tween.tween_callback(func() -> void: _m2_timer = 0.0)
	_m2_tween.tween_property(_boss_tr, "position", end_pos, M2_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_m2_tween.tween_callback(_return_to_wander)


func _tick_m2(delta: float) -> void:
	if _m2_timer < 0.0:
		return   # still moving to start position
	_m2_timer += delta
	for i: int in 3:
		if not _m2_burst_fired[i] and _m2_timer >= (M2_BURST_TIMES[i] as float):
			_m2_burst_fired[i] = true
			_fire_stars()


func _fire_stars() -> void:
	for fp: Node2D in [_fp2_node, _fp4_node]:
		var origin := _fp_world(fp)
		var lpos   := origin - OC_BOUNDS.position - Vector2(10.0, 10.0)
		var tr     := _make_proj_rect(_star_tex, Vector2(20.0, 20.0), lpos)
		_projectiles.append({
			"tr": tr, "vel": Vector2(0.0, STAR_SPEED), "dmg": STAR_DMG,
			"type": "star", "rot_spd": PI, "rot": 0.0,
			"traveled": 0.0, "spawned_children": false,
		})


func _spawn_child_stars(origin_oc: Vector2) -> void:
	for i: int in 5:
		var angle := TAU * float(i) / 5.0
		var vel   := Vector2(cos(angle), sin(angle)) * CHILD_STAR_SPEED
		var lpos  := origin_oc - OC_BOUNDS.position - Vector2(6.0, 6.0)
		var tr    := _make_proj_rect(_child_star_tex, Vector2(12.0, 12.0), lpos)
		_projectiles.append({
			"tr": tr, "vel": vel, "dmg": STAR_DMG,
			"type": "child_star", "rot_spd": PI * 1.5, "rot": 0.0,
			"traveled": 0.0, "spawned_children": true,
		})


# =============================================================================
# Move 3 — Turbulence
# =============================================================================
func _enter_m3() -> void:
	_phase        = Phase.M3_TURB
	_m3_timer     = 0.0
	_m3_fire_acc  = 0.0
	_m3_dir_timer = 0.0


func _tick_m3(delta: float) -> void:
	_m3_timer += delta

	# Random direction
	_m3_dir_timer -= delta
	if _m3_dir_timer <= 0.0:
		var angle      := randf() * TAU
		_wander_vel    = Vector2(cos(angle), sin(angle)) * M3_SPEED
		_m3_dir_timer  = 1.0 + randf() * 0.5

	_apply_vel_move(delta, false)

	# Rotation
	if _boss_tr != null and is_instance_valid(_boss_tr):
		_boss_tr.rotation += TAU * M3_RPM / 60.0 * delta

	# Fire red dots
	_m3_fire_acc += delta
	if _m3_fire_acc >= M3_FIRE_RATE:
		_m3_fire_acc -= M3_FIRE_RATE
		for fp: Node2D in [_fp1_node, _fp5_node]:
			var origin := _fp_world(fp)
			var lpos   := origin - OC_BOUNDS.position - Vector2(4.0, 4.0)
			var angle  := randf() * TAU
			var vel    := Vector2(cos(angle), sin(angle)) * DOT_SPEED
			var tr     := _make_proj_rect(_dot_tex, Vector2(8.0, 8.0), lpos)
			_projectiles.append({
				"tr": tr, "vel": vel, "dmg": DOT_DMG,
				"type": "dot", "rot_spd": PI * 4.0, "rot": 0.0,
				"traveled": 0.0, "spawned_children": true,
			})

	if _m3_timer >= M3_DURATION:
		_end_m3()


func _end_m3() -> void:
	_phase = Phase.M1_SETUP
	var tw := create_tween()
	tw.tween_property(_boss_tr, "rotation", DEFAULT_ROT, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_return_to_wander)


# =============================================================================
# Move 4 — Shooting Wave
# =============================================================================
func _enter_m4() -> void:
	_phase        = Phase.M4_WAVE
	_m4_fire_acc  = 0.0
	_m4_volleys   = 0
	_m4_dir_timer = 0.0
	_m4_done      = false


func _m4_aim_rotation() -> float:
	var ship_rect := _ship_hit_rect_oc()
	if not ship_rect.has_area():
		return _boss_tr.rotation
	var ship_center := ship_rect.get_center()
	var boss_pivot  := _boss_tr.global_position + _boss_tr.pivot_offset
	var gun_axis    := (_fp3_off - _fp6_off).angle()
	return (ship_center - boss_pivot).angle() - gun_axis


func _tick_m4(delta: float) -> void:
	if _m4_done:
		return

	# Random movement
	_m4_dir_timer -= delta
	if _m4_dir_timer <= 0.0:
		var angle      := randf() * TAU
		_wander_vel    = Vector2(cos(angle), sin(angle)) * M4_SPEED
		_m4_dir_timer  = 1.0 + randf() * 0.5

	_apply_vel_move(delta, false)

	# Continuously rotate to aim FP3 at ship (FP6→FP3→ship collinear)
	if _boss_tr != null and is_instance_valid(_boss_tr):
		_boss_tr.rotation = lerp_angle(_boss_tr.rotation, _m4_aim_rotation(), delta * 4.0)

	# Fire wave volleys
	_m4_fire_acc += delta
	if _m4_fire_acc >= M4_FIRE_RATE:
		_m4_fire_acc -= M4_FIRE_RATE
		_fire_wave_volley()
		_m4_volleys += 1
		if _m4_volleys >= M4_VOLLEYS:
			_m4_done = true
			_return_to_wander()


func _fire_wave_volley() -> void:
	var fp3_world := _fp_world(_fp3_node)
	var ship_rect := _ship_hit_rect_oc()
	var fire_angle: float
	if ship_rect.has_area():
		fire_angle = (ship_rect.get_center() - fp3_world).angle()
	else:
		fire_angle = PI / 2.0
	var origin := fp3_world - OC_BOUNDS.position
	for i: int in 8:
		var angle := fire_angle - deg_to_rad(17.5) + deg_to_rad(35.0 / 7.0) * float(i)
		var vel   := Vector2(cos(angle), sin(angle)) * M4_BULLET_SPD
		var lpos  := origin - Vector2(3.5, 3.5)
		var tr    := _make_proj_rect(_wave_tex, Vector2(7.0, 7.0), lpos)
		_projectiles.append({
			"tr": tr, "vel": vel, "dmg": WAVE_DMG,
			"type": "wave", "rot_spd": 0.0, "rot": 0.0,
			"traveled": 0.0, "spawned_children": true,
		})


# =============================================================================
# Recovery — Phase 2
# =============================================================================
func _enter_recovery() -> void:
	_phase             = Phase.RECOVERY
	_shield            = 0.0
	_recover_ticks     = 0
	_recover_timer     = 0.0
	_recover_frame_idx = 0
	_broken_frame_idx  = 0
	if _boss_tr != null and is_instance_valid(_boss_tr):
		_boss_tr.rotation = 0.0
		_boss_tr.scale    = Vector2.ONE
	_pick_wander_dir()
	_sync_recovery_texture()


func _tick_recovery(delta: float) -> void:
	_tick_wander_move(delta, false)
	_recover_timer += delta
	if _recover_timer >= RECOVER_INTERVAL:
		_recover_timer -= RECOVER_INTERVAL
		_shield         = minf(SHIELD_MAX, _shield + SHIELD_PER_STEP)
		_recover_ticks += 1
		_recover_frame_idx = mini(_recover_ticks, _recover_frames.size() - 1)
		_sync_recovery_texture()
		if _shield >= SHIELD_MAX:
			_enter_phase1()


func _enter_phase1() -> void:
	_phase             = Phase.BROKEN_WANDER
	_broken_frame_idx  = 0
	_recover_frame_idx = 0
	_pick_wander_dir()
	_attack_timer = randf_range(2.0, 4.0)
	if _boss_tr != null and is_instance_valid(_boss_tr):
		_boss_tr.rotation = DEFAULT_ROT
	_sync_broken_texture()


# =============================================================================
# Texture sync helpers
# =============================================================================
func _sync_broken_texture() -> void:
	if _boss_tr == null or not is_instance_valid(_boss_tr):
		return
	if not _broken_frames.is_empty():
		_boss_tr.texture = _broken_frames[_broken_frame_idx]


func _sync_recovery_texture() -> void:
	if _boss_tr == null or not is_instance_valid(_boss_tr):
		return
	if not _recover_frames.is_empty():
		_boss_tr.texture = _recover_frames[_recover_frame_idx]


# =============================================================================
# Projectile system
# =============================================================================
func _make_proj_rect(tex: Texture2D, sz: Vector2, pos: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture        = tex
	tr.size           = sz
	tr.stretch_mode   = TextureRect.STRETCH_SCALE
	tr.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	tr.pivot_offset   = sz / 2.0
	tr.position       = pos
	tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.z_as_relative  = false
	tr.z_index        = 150
	_clip_node.add_child(tr)
	return tr


func _tick_projectiles(delta: float) -> void:
	if _clip_node == null or not is_instance_valid(_clip_node):
		return
	var ship_rect := _ship_hit_rect_oc()
	var i := _projectiles.size() - 1
	while i >= 0:
		var p:  Dictionary = _projectiles[i]
		var tr: TextureRect = p["tr"]
		if tr == null or not is_instance_valid(tr):
			_projectiles.remove_at(i)
			i -= 1
			continue

		tr.position += (p["vel"] as Vector2) * delta

		var rs := float(p["rot_spd"])
		if rs != 0.0:
			p["rot"] = float(p["rot"]) + rs * delta
			tr.rotation = float(p["rot"])

		# Star split
		if p["type"] == "star" and not (p["spawned_children"] as bool):
			p["traveled"] = float(p["traveled"]) + (p["vel"] as Vector2).length() * delta
			if float(p["traveled"]) >= STAR_SPLIT_DIST:
				var world_pos := tr.position + OC_BOUNDS.position + tr.size / 2.0
				_spawn_child_stars(world_pos)
				tr.queue_free()
				_projectiles.remove_at(i)
				i -= 1
				continue

		# Hit ship
		if ship_rect.has_area():
			var proj_oc := Rect2(tr.position + OC_BOUNDS.position, tr.size)
			if proj_oc.intersects(ship_rect):
				GameManager.ship_take_damage(int(p["dmg"]))
				_flash_ship_red()
				tr.queue_free()
				_projectiles.remove_at(i)
				i -= 1
				continue

		# Cull off-screen
		var center_oc := tr.position + OC_BOUNDS.position + tr.size / 2.0
		if not OC_BOUNDS.has_point(center_oc):
			tr.queue_free()
			_projectiles.remove_at(i)

		i -= 1


# =============================================================================
# Ship helpers
# =============================================================================
func _ship_hit_rect_oc() -> Rect2:
	var s := get_tree().get_first_node_in_group("ship_body") as Control
	if s == null:
		return Rect2()
	var xf := s.get_global_transform()
	var a  := xf * Vector2.ZERO
	var b  := xf * s.size
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)),
				 Vector2(absf(b.x - a.x), absf(b.y - a.y)))


func _flash_ship_red() -> void:
	var s := get_tree().get_first_node_in_group("ship_body") as Control
	if s == null:
		return
	var tw := create_tween()
	tw.tween_property(s, "modulate", Color(2.0, 0.3, 0.3, 1.0), 0.0)
	tw.tween_property(s, "modulate", Color.WHITE, 0.15)


# =============================================================================
# Hitbox — rotated AABB
# =============================================================================
func get_boss_hit_rect() -> Rect2:
	if _boss_tr == null or not is_instance_valid(_boss_tr) or not visible:
		return Rect2()
	var xf := _boss_tr.get_global_transform()
	var corners := [
		xf * Vector2.ZERO,
		xf * Vector2(_boss_tr.size.x, 0.0),
		xf * Vector2(0.0, _boss_tr.size.y),
		xf * _boss_tr.size,
	]
	var mn: Vector2 = corners[0]
	var mx: Vector2 = corners[0]
	for c: Vector2 in corners:
		mn = mn.min(c)
		mx = mx.max(c)
	return Rect2(mn, mx - mn)


# =============================================================================
# Hit feedback
# =============================================================================
func flash_boss_hit() -> void:
	if _boss_tr == null or not is_instance_valid(_boss_tr):
		return
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_boss_tr.modulate = Color(2.0, 2.0, 2.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_boss_tr, "modulate", Color.WHITE, 0.12)


# =============================================================================
# HP / Shield signal interception
# =============================================================================
func notify_hp_changed(hp: int) -> void:
	if _restoring_hp:
		return
	if _phase_is_broken():
		var dmg := _current_hp - hp
		if dmg > 0:
			_apply_shield_damage(float(dmg))
			_restoring_hp = true
			GameManager.boss_hp = _current_hp
			GameManager.boss_hp_changed.emit(_current_hp)
			_restoring_hp = false
	else:
		_current_hp = hp
		_update_bars()


func _apply_shield_damage(dmg: float) -> void:
	_shield = maxf(0.0, _shield - dmg)
	_broken_frame_idx = mini(
		int((SHIELD_MAX - _shield) / SHIELD_PER_STEP),
		_broken_frames.size() - 1
	)
	_sync_broken_texture()
	if _shield <= 0.0:
		_enter_recovery()


# =============================================================================
# Kill routes
# =============================================================================
func notify_boss_killed() -> void:
	_phase = Phase.DONE
	_do_cleanup()
	GameManager.boss_defeated.emit()


func kill_boss() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	GameManager.boss_hp     = 0
	GameManager.boss_max_hp = 0
	GameManager.boss_killed.emit()
	_do_cleanup()


func _do_cleanup() -> void:
	visible = false
	for p: Dictionary in _projectiles:
		var tr: TextureRect = p.get("tr")
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
	_projectiles.clear()

	if _clip_node != null and is_instance_valid(_clip_node):
		_clip_node.queue_free()
		_clip_node = null
	if _boss_tr != null and is_instance_valid(_boss_tr):
		_boss_tr.queue_free()   # also frees FP node children
		_boss_tr = null
	_fp1_node = null; _fp2_node = null; _fp3_node = null
	_fp4_node = null; _fp5_node = null; _fp6_node = null

	if _hp_bar_bg != null and is_instance_valid(_hp_bar_bg):
		_hp_bar_bg.queue_free()
		_hp_bar_bg = null
	if _shield_bar_bg != null and is_instance_valid(_shield_bar_bg):
		_shield_bar_bg.queue_free()
		_shield_bar_bg = null

	var bg := get_tree().get_first_node_in_group("scrolling_bg")
	if is_instance_valid(bg) and bg.has_method("restore_texture"):
		bg.restore_texture()
	var ov := get_tree().get_first_node_in_group("scrolling_overlay")
	if is_instance_valid(ov) and ov.has_method("restore_texture"):
		ov.set_speed_mult(1.0)
		ov.restore_texture()

	GameManager.boss_max_hp = 0
	GameManager.boss_hp     = 0


# =============================================================================
# Phase transition — Phase 1↔2 is internal shield logic, not boss death
# =============================================================================
func is_phase_transition() -> bool:
	return false
