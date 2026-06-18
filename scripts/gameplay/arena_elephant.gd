extends Node2D
## Arena Elephant boss — world-space, player-tethered, spawned by the wave director. Takes damage through the
## universal take_damage(amount, stagger) contract (every arena weapon + crit hits it) and drives
## GameManager.boss_hp for an HP bar; on death drops XP, pops an explosion, emits boss_defeated.
##
## Ported from boss_elephant.gd's 5-move engine but rebuilt for the 360° arena (no SpaceScreen/OC_BOUNDS),
## with attacks aimed at the player:
##   M1 spike rain   — spin + radial spiral spike bursts, slowly chasing the player
##   M2 fire breath  — zoom to the player, then breathe a locked jet that coils into a 360° fire ring
##   M3 laser         — face the player, telegraph (aim LOCKS), then fire a wide beam at the locked aim
##   M4 bomb strafe   — orbit-strafe the player, dropping bombs that rain inward toward you
##   M5 chasing bombs — chase the player while firing fast, barely-homing bombs

const GifLoader      := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const ArenaExplosion := preload("res://scripts/gameplay/arena_explosion.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
# DEBUG: force the boss to a single move (0 = off / full random moveset, 1..5 = always that move).
# Spawn-only-him is handled in arena_wave_director.gd (DEBUG_ELEPHANT_ONLY). Set back to 0 to restore.
const DEBUG_FORCE_MOVE         := 0       # 0 = off; 4 = M4 (bomb strafe) only
const NO_BACKTOBACK_FIREBREATH := true    # never pick M2 twice in a row (ignored when forcing a move)
const ICON_DRAW_SCALE := 2.4
const TETHER_NEAR     := 430.0   # boss drifts toward the player whenever it's farther than this
const BOSS_DAMAGE_MULT := 0.75   # global scale on all of the boss's attack damage
const CONTACT_HIT_PAD := 16.0    # player radius for hit checks
const HIT_FLASH_TIME  := 0.14
const HIT_FLASH_COLOR  := Color(1.0, 1.0, 1.0)
const KILL_FLASH_COLOR := Color(1.0, 0.18, 0.18)
const HP_BAR_W := 120.0
const HP_BAR_H := 8.0
const PROJ_CULL_DIST := 2400.0   # cull projectiles farther than this from the player

# M1 — spin + spike rain (now slowly chases the player)
const M1_DUR          := 6.0
const M1_CHASE_SPD    := 45.0    # slow chase toward the player during the spike rain
const M1_ROT_SPEED    := 40.0 * TAU / 60.0
const M1_SPIKE_INT    := 0.2
const M1_SPIKES_PER_INT := 4
const M1_SPIRAL_STEP  := 0.35
const SPIKE_SPEED     := 150.0
const SPIKE_SPIN_RADIUS := 40.0
const SPIKE_DMG       := 10
const SPIKE_LIFE      := 4.0
const SPIKE_SIZE      := 9.0
const SPIKE_COLOR     := Color(1.0, 0.55, 0.2)
# M2 — vortex wander
const M2_DUR          := 8.0
const M2_MOVE_SPD     := 95.0
const M2_VORTEX_INT   := 0.43
const VORTEX_SPEED    := 150.0
const VORTEX_ROT      := 60.0 * TAU / 60.0
const VORTEX_DMG      := 15
const VORTEX_LIFE     := 5.0
const VORTEX_SIZE     := 16.0
const VORTEX_COLOR    := Color(0.4, 0.8, 1.0)
# M2 (NEW) — zoom to the player, then fire a stream of fire-vortex projectiles that push out along the
# locked aim and curve around into a ring. (Old M2_DUR/M2_MOVE_SPD/M2_VORTEX_INT consts unused.)
const M2_ZOOM_SPD      := 900.0  # dash speed toward the player
const M2_ARRIVE_DIST   := 140.0  # close enough → start breathing
const M2_ZOOM_MAX_T    := 2.0    # safety: charge after this long even if not yet arrived
const M2_CHARGE_T      := 0.8    # charge-up + danger-sign telegraph before the fire erupts
const FIRE_RING_RADIUS := 475.0  # straight jet distance = radius of the ring around the elephant (2.5× bigger)
const FIRE_BEAM_DUR    := 5.0    # the breathed jet emits this long → then the next attack can start
const RING_FORM_TIME   := 5.0    # the two coils complete the full circle in this total time
const RING_HOLD_TIME   := 15.0   # the completed ring lingers this long after closing, then fades
const FIRE_THICKNESS   := 16.0   # half-width of the fire hazard (px)
const FIRE_DMG         := 18     # fire damage per tick (ship iframes gate the cadence)
const COIL_SPEED       := 700.0  # px/s each fire-vortex projectile travels along the jet→ring path
const COIL_INT         := 0.05   # seconds between projectiles in the coil stream (density)
const FIRE_COLOR_OUT   := Color(1.0, 0.32, 0.06)
const FIRE_COLOR_MID   := Color(1.0, 0.6, 0.15)
const FIRE_COLOR_CORE  := Color(1.0, 0.95, 0.6)
# M3 — laser
const M3_ROT_T        := 0.5
const M3_WARN_T       := 1.0
const M3_FIRE_T       := 2.5          # firing window — long enough for the chasing sweep to read
const M3_TURN_SPEED   := TAU / 16.0   # laser turn rate while firing (full circle in 16s = 22.5°/s)
const M3_MAX_TURN     := PI / 2.0     # the beam only sweeps up to 90° from where it locked
const LASER_LEN       := 1700.0
const LASER_WARN_W    := 8.0
const LASER_FIRE_W    := 90.0
const LASER_DMG       := 30
# M4 — bomb stream (stationary; turns its aim toward the player and fires a continuous stream)
const M4_DUR          := 7.0
const M4_TURN_SPEED   := 1.8     # rad/s the aim turns toward the player (it "tries" to track you)
const M4_STREAM_INT   := 0.09    # seconds between bombs in the stream (continuous fire)
const DROP_SPEED      := 360.0
const DROP_DMG        := 20
const DROP_LIFE       := 5.0
const DROP_SIZE       := 12.0
const DROP_COLOR      := Color(1.0, 0.45, 0.2)
# M5 — chasing bombs (fast, barely-homing; the elephant also chases the player)
const M5_DUR          := 6.0    # the whole attack lasts 6s
const M5_MOVE_SPD     := 200.0  # elephant chases the player during the attack
const M5_BLOB_INT     := 0.55
const BLOB_SPEED      := 600.0  # faster bombs
const BLOB_HOMING     := 0.5    # much less turnability
const BLOB_DMG        := 20
const BLOB_LIFE       := 1.5    # bombs last half as long again
const BLOB_SIZE       := 13.0
const BLOB_COLOR      := Color(0.6, 1.0, 0.45)
# Legacy projectile art (from the main-game elephant boss), loaded via GifLoader like the legacy.
const BLOB_GIF          := "res://assets/bosses/elephant/blob.gif"       # chasing bomb (M5)
const VORTEX_GIF        := "res://assets/bosses/elephant/firevortex.gif" # fire vortex → M1 spike projectiles
const PROJ_SPRITE_SCALE := 3.5   # sprite draw size = projectile hit-radius × this

# ── Stats (from configure) ─────────────────────────────────────────────────────
var hp_max: float = 8000.0
var hp: float = 8000.0
var armor: float = 0.0
var speed: float = 120.0
var _radius: float = 70.0
var contact_damage: int = 40
var xp: int = 500
var _icon: String = ""

# ── Runtime ─────────────────────────────────────────────────────────────────────
var _mgr: Node = null
var _player: Node2D = null
var _dead: bool = false
var _flash: float = 0.0
var _flash_color: Color = HIT_FLASH_COLOR
var _spin: float = 0.0
var _projectiles: Array = []   # {pos, vel, life, type, dmg, hit, rot, rot_spd}
# move state
var _move: int = 1
var _move_t: float = 0.0
var _spike_acc := 0.0
var _spiral := 0.0
var _vortex_acc := 0.0
var _drop_acc := 0.0
var _blob_acc := 0.0
var _wander_off := Vector2.ZERO   # M2/M5 wander target offset from the player
var _m4_aim := Vector2.RIGHT   # M4 stream aim direction (turns toward the player)
var _laser_aim := Vector2.RIGHT
var _laser_aim0 := Vector2.RIGHT   # aim captured when firing starts; the 90° sweep is measured from here
var _m3_fired := false             # latches on the first fire frame to capture _laser_aim0
# M2 fire-breath state
var _m2_phase: int = 0          # 0 = zoom, 1 = charge (danger sign), 2 = breathing
var _charge_t: float = 0.0      # charge-up timer (phase 1)
var _charge_aim := Vector2.RIGHT  # telegraph direction during charge (locks at fire)
var _fire_t: float = 0.0        # time since the current breath began
var _fire_center := Vector2.ZERO  # locked origin of the coil stream
var _fire_aim := Vector2.RIGHT    # locked aim of the coil stream
var _coil_acc: float = 0.0        # coil-stream spawn accumulator
var _last_move: int = 0         # for the no-back-to-back-firebreath rule
# sprite
var _frames: Array = []
var _delays: Array = []
var _anim_acc: float = 0.0
var _anim_frame: int = 0
var _tex: Texture2D = null
var _draw_size: Vector2 = Vector2.ZERO
# legacy projectile sprite frames (chasing bomb + fire vortex)
var _blob_frames: Array = []
var _blob_delays: Array = []
var _vortex_frames: Array = []
var _vortex_delays: Array = []
var _proj_t: float = 0.0

func configure(_type_id: String, mgr: Node, def: Dictionary = {}) -> void:
	_mgr = mgr
	hp_max = float(def.get("hp", 8000.0))
	hp = hp_max
	armor = float(def.get("armor", 0.0))
	speed = float(def.get("speed", 120.0))
	_radius = float(def.get("size", 70.0))
	contact_damage = int(def.get("contact", 40))
	xp = int(def.get("xp", 500))
	_icon = String(def.get("icon", ""))

func _ready() -> void:
	add_to_group("arena_enemy")
	add_to_group("boss")
	z_index = 2
	_player = get_tree().get_first_node_in_group("player")
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_load_sprite()
	var bd := _load_gif_anim(BLOB_GIF)
	_blob_frames = bd["frames"]; _blob_delays = bd["delays"]
	var vd := _load_gif_anim(VORTEX_GIF)
	_vortex_frames = vd["frames"]; _vortex_delays = vd["delays"]
	GameManager.boss_max_hp = int(hp_max)
	GameManager.boss_hp = int(hp)
	if GameManager.has_signal("boss_hp_changed"):
		GameManager.boss_hp_changed.emit(int(hp))
	_begin_random_move()

# ── Sprite loading (sheet/gif, like arena_enemy) ───────────────────────────────
func _load_sprite() -> void:
	if _icon == "":
		return
	if _icon.ends_with(".sheet.png"):
		_load_sheet_frames(_icon)
	elif _icon.ends_with(".gif"):
		var g := GifLoader.load_gif(_icon)
		if g != null and g.has_meta("gif_frames"):
			_frames = g.get_meta("gif_frames")
			_delays = g.get_meta("gif_delays") if g.has_meta("gif_delays") else []
			_tex = _frames[0] as Texture2D if not _frames.is_empty() else g
		else:
			_tex = g
	else:
		_tex = load(_icon) as Texture2D
	if _tex != null:
		var ts := _tex.get_size()
		var w := _radius * ICON_DRAW_SCALE
		var h := w * (ts.y / maxf(1.0, ts.x))
		_draw_size = Vector2(w, h)

func _load_sheet_frames(path: String) -> void:
	var json_path := path.replace(".sheet.png", ".sheet.json")
	var atlas := load(path) as Texture2D
	if atlas == null:
		return
	var cols := 1
	var fw := atlas.get_width()
	var fh := atlas.get_height()
	var raw_delays: Array = [0.1]
	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		if file != null:
			var data = JSON.parse_string(file.get_as_text())
			file.close()
			if data is Dictionary:
				cols = int(data.get("cols", 1))
				fw = int(data.get("w", fw))
				fh = int(data.get("h", fh))
				raw_delays = data.get("delays", [0.1])
	var rows := atlas.get_height() / fh if fh > 0 else 1
	var count := rows * cols
	_frames.clear()
	_delays.clear()
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)
		_frames.append(at)
		var dl: float = float(raw_delays[i]) if i < raw_delays.size() else float(raw_delays[-1])
		_delays.append(dl)
	if not _frames.is_empty():
		_tex = _frames[0] as Texture2D

## Generic sheet loader → {frames, delays} (does not touch the boss _frames/_delays members).
func _load_sheet(path: String) -> Dictionary:
	var atlas := load(path) as Texture2D
	if atlas == null:
		return {"frames": [], "delays": []}
	var json_path := path.replace(".sheet.png", ".sheet.json")
	var cols := 1
	var fw := atlas.get_width()
	var fh := atlas.get_height()
	var raw_delays: Array = [0.1]
	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		if file != null:
			var data = JSON.parse_string(file.get_as_text())
			file.close()
			if data is Dictionary:
				cols = int(data.get("cols", 1))
				fw = int(data.get("w", fw))
				fh = int(data.get("h", fh))
				raw_delays = data.get("delays", [0.1])
	var rows := atlas.get_height() / fh if fh > 0 else 1
	var count := rows * cols
	var frames: Array = []
	var delays: Array = []
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)
		frames.append(at)
		delays.append(float(raw_delays[i]) if i < raw_delays.size() else float(raw_delays[-1]))
	return {"frames": frames, "delays": delays}

## Load an animated GIF → {frames, delays} via GifLoader (the proven legacy path; avoids atlas issues).
func _load_gif_anim(path: String) -> Dictionary:
	var g = GifLoader.load_gif(path)
	if g == null:
		return {"frames": [], "delays": []}
	if g.has_meta("gif_frames"):
		var fr: Array = g.get_meta("gif_frames")
		var dl: Array = g.get_meta("gif_delays") if g.has_meta("gif_delays") else []
		while dl.size() < fr.size():
			dl.append(0.1)
		return {"frames": fr, "delays": dl}
	return {"frames": [g], "delays": [0.1]}

func _player_pos() -> Vector2:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return global_position

func _process(delta: float) -> void:
	if _dead:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not _frames.is_empty():
		_anim_acc += delta
		var fd: float = float(_delays[_anim_frame]) if _anim_frame < _delays.size() else 0.1
		if _anim_acc >= fd:
			_anim_acc -= fd
			_anim_frame = (_anim_frame + 1) % _frames.size()
			_tex = _frames[_anim_frame] as Texture2D
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	_move_t += delta
	match _move:
		1: _tick_m1(delta)
		2: _tick_m2(delta)
		3: _tick_m3(delta)
		4: _tick_m4(delta)
		5: _tick_m5(delta)
	_proj_t += delta
	_tick_projectiles(delta)
	_check_contact()
	queue_redraw()

# ── Move sequencer ──────────────────────────────────────────────────────────────
func _begin_random_move() -> void:
	if DEBUG_FORCE_MOVE > 0:
		_move = DEBUG_FORCE_MOVE
	else:
		var choices := [1, 2, 3, 4, 5]
		if NO_BACKTOBACK_FIREBREATH and _last_move == 2:
			choices.erase(2)   # never two fire-breaths in a row
		_move = int(choices[randi() % choices.size()])
	_last_move = _move
	_move_t = 0.0
	_spike_acc = 0.0
	_vortex_acc = 0.0
	_drop_acc = 0.0
	_blob_acc = 0.0
	_m2_phase = 0
	_charge_t = 0.0
	_fire_t = 0.0
	_m3_fired = false
	match _move:
		4:
			var to4 := _player_pos() - global_position
			_m4_aim = to4.normalized() if to4.length() > 0.01 else Vector2.RIGHT

func _new_wander_target() -> void:
	_wander_off = Vector2.from_angle(randf() * TAU) * randf_range(250.0, 400.0)

func _tether(delta: float) -> void:
	var to := _player_pos() - global_position
	if to.length() > TETHER_NEAR:
		global_position += to.normalized() * speed * delta

# ── M1: spin + spiral spike rain ───────────────────────────────────────────────
func _tick_m1(delta: float) -> void:
	# Slowly chase the player while spinning + raining spikes.
	var to := _player_pos() - global_position
	if to.length() > 1.0:
		global_position += to.normalized() * M1_CHASE_SPD * delta
	_spin += M1_ROT_SPEED * delta
	_spike_acc += delta
	while _spike_acc >= M1_SPIKE_INT:
		_spike_acc -= M1_SPIKE_INT
		for i in M1_SPIKES_PER_INT:
			var ang := _spin + _spiral + float(i) * (TAU / float(M1_SPIKES_PER_INT))
			var radial := Vector2.from_angle(ang)
			var tangential := Vector2.from_angle(ang + PI * 0.5)
			_add_proj(radial * SPIKE_SPEED + tangential * (M1_ROT_SPEED * SPIKE_SPIN_RADIUS),
				"spike", SPIKE_DMG, SPIKE_SIZE, VORTEX_ROT)
		_spiral += M1_SPIRAL_STEP
	if _move_t >= M1_DUR:
		_begin_random_move()

# ── M2: zoom to the player → breathe a fire jet that coils into a ring around the elephant ──
func _tick_m2(delta: float) -> void:
	if _m2_phase == 0:
		# ── Zoom to the player ──
		global_position = global_position.move_toward(_player_pos(), M2_ZOOM_SPD * delta)
		var d := global_position.distance_to(_player_pos())
		if d <= M2_ARRIVE_DIST or _move_t >= M2_ZOOM_MAX_T:
			_m2_phase = 1
			_charge_t = 0.0
	elif _m2_phase == 1:
		# ── Charge up + danger sign (aim tracks the player; it LOCKS only when the fire erupts) ──
		_charge_t += delta
		var to := _player_pos() - global_position
		if to.length() > 0.01:
			_charge_aim = to.normalized()
		if _charge_t >= M2_CHARGE_T:
			_start_fire_breath()   # lock aim at the player's CURRENT position + spawn the coiling ring
			_m2_phase = 2
			_fire_t = 0.0
	else:
		# ── Breathe fire: spawn the fire-vortex coil stream along the locked origin/aim ──
		_fire_t += delta
		if _fire_t < FIRE_BEAM_DUR:
			_coil_acc += delta
			while _coil_acc >= COIL_INT:
				_coil_acc -= COIL_INT
				_spawn_coil()
		if _fire_t >= FIRE_BEAM_DUR:
			_begin_random_move()   # stream done → next attack (projectiles finish on their own)

# ── M2 fire breath: lock origin + aim; the coil stream is spawned here / followed in _tick_projectiles ──
func _start_fire_breath() -> void:
	var aim := _player_pos() - global_position
	_fire_aim = aim.normalized() if aim.length() > 0.01 else Vector2.RIGHT
	_fire_center = global_position
	_coil_acc = 0.0

func _spawn_coil() -> void:
	# Split into two: one winds each way around the circle so together they close the ring.
	_add_coil(1.0)
	_add_coil(-1.0)

func _add_coil(dir: float) -> void:
	_projectiles.append({
		"pos": _fire_center, "vel": Vector2.ZERO, "life": 0.0, "type": "firevortex_coil",
		"dmg": FIRE_DMG, "hit": FIRE_THICKNESS, "rot": 0.0, "rot_spd": VORTEX_ROT,
		"center": _fire_center, "aim": _fire_aim, "radius": FIRE_RING_RADIUS, "d": 0.0, "dir": dir,
	})

## Parametric path for a coil projectile: straight jet out to `radius`, then around the circle (dir = ±1).
func _coil_path(center: Vector2, aim: Vector2, radius: float, d: float, dir: float) -> Vector2:
	if d <= radius:
		return center + aim * d
	var a := aim.angle() + dir * (d - radius) / maxf(1.0, radius)
	return center + Vector2.from_angle(a) * radius

# ── M3: face the player → telegraph (aim LOCKS) → fire a wide beam ─────────────
func _tick_m3(delta: float) -> void:
	if _move_t < M3_ROT_T:
		# Rotate toward the player + drift into range; aim tracks the player this whole phase.
		var to := _player_pos() - global_position
		if to.length() > 700.0:
			global_position += to.normalized() * speed * delta
		_laser_aim = to.normalized() if to.length() > 0.01 else _laser_aim
	elif _move_t < M3_ROT_T + M3_WARN_T:
		pass   # warning: aim is LOCKED at the rot→warn value (dodgeable)
	elif _move_t < M3_ROT_T + M3_WARN_T + M3_FIRE_T:
		# Firing: the beam slowly turns to chase the player (90°/s) but only up to 90° from the lock.
		if not _m3_fired:
			_laser_aim0 = _laser_aim
			_m3_fired = true
		var desired := (_player_pos() - global_position).angle()
		var cur := _laser_aim.angle()
		var step := clampf(angle_difference(cur, desired), -M3_TURN_SPEED * delta, M3_TURN_SPEED * delta)
		var swept := clampf(angle_difference(_laser_aim0.angle(), cur + step), -M3_MAX_TURN, M3_MAX_TURN)
		_laser_aim = Vector2.from_angle(_laser_aim0.angle() + swept)
		# continuous beam damage along the (now rotating) aim (iframe-gated).
		var rel := _player_pos() - global_position
		var along := rel.dot(_laser_aim)
		var perp := (rel - _laser_aim * along).length()
		if along >= 0.0 and along <= LASER_LEN and perp <= LASER_FIRE_W * 0.5 + CONTACT_HIT_PAD:
			if GameManager.has_method("ship_take_damage"):
				GameManager.ship_take_damage(int(round(LASER_DMG * BOSS_DAMAGE_MULT)))
	else:
		_begin_random_move()

func _m3_phase() -> int:   # 0 none, 1 rot, 2 warn, 3 fire (for drawing)
	if _move != 3:
		return 0
	if _move_t < M3_ROT_T:
		return 1
	if _move_t < M3_ROT_T + M3_WARN_T:
		return 2
	if _move_t < M3_ROT_T + M3_WARN_T + M3_FIRE_T:
		return 3
	return 0

# ── M4: orbit-strafe the player, dropping bombs that rain inward ───────────────
func _tick_m4(delta: float) -> void:
	# Stationary: turn the aim toward the player, then fire a continuous stream of bombs along it.
	var desired := (_player_pos() - global_position).angle()
	var step := clampf(angle_difference(_m4_aim.angle(), desired), -M4_TURN_SPEED * delta, M4_TURN_SPEED * delta)
	_m4_aim = Vector2.from_angle(_m4_aim.angle() + step)
	_drop_acc += delta
	while _drop_acc >= M4_STREAM_INT:
		_drop_acc -= M4_STREAM_INT
		_add_proj(_m4_aim * DROP_SPEED, "drop", DROP_DMG, DROP_SIZE, VORTEX_ROT)
	if _move_t >= M4_DUR:
		_begin_random_move()

# ── M5: wander near the player + homing blobs ──────────────────────────────────
func _tick_m5(delta: float) -> void:
	# Chase the player directly while firing fast, barely-homing bombs.
	var to := _player_pos() - global_position
	if to.length() > 1.0:
		global_position += to.normalized() * M5_MOVE_SPD * delta
	_blob_acc += delta
	while _blob_acc >= M5_BLOB_INT:
		_blob_acc -= M5_BLOB_INT
		var dir := (_player_pos() - global_position).normalized()
		_add_proj(dir * BLOB_SPEED, "blob", BLOB_DMG, BLOB_SIZE, 0.0)
	if _move_t >= M5_DUR:
		_begin_random_move()

# ── Projectiles ─────────────────────────────────────────────────────────────────
func _add_proj(vel: Vector2, type: String, dmg: int, hit: float, rot_spd: float) -> void:
	_projectiles.append({"pos": global_position, "vel": vel, "life": 0.0, "type": type,
		"dmg": dmg, "hit": hit, "rot": 0.0, "rot_spd": rot_spd})

func _proj_life(type: String) -> float:
	match type:
		"spike":  return SPIKE_LIFE
		"vortex": return VORTEX_LIFE
		"drop":   return DROP_LIFE
		"blob":   return BLOB_LIFE
		"firevortex_coil": return 30.0   # despawn is distance-based (one full loop), not life
	return 4.0

func _tick_projectiles(delta: float) -> void:
	var pp := _player_pos()
	var i := _projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = _projectiles[i]
		var typ := String(p["type"])
		if typ == "firevortex_coil":   # follow the jet→ring path by arc-length
			p["d"] = float(p["d"]) + COIL_SPEED * delta
			p["pos"] = _coil_path(p["center"], p["aim"], float(p["radius"]), float(p["d"]), float(p["dir"]))
		else:
			if typ == "blob":   # homing
				var desired := (pp - (p["pos"] as Vector2)).normalized() * BLOB_SPEED
				p["vel"] = (p["vel"] as Vector2).lerp(desired, clampf(BLOB_HOMING * delta, 0.0, 1.0))
			p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["life"] = float(p["life"]) + delta
		p["rot"] = float(p["rot"]) + float(p["rot_spd"]) * delta
		var pos: Vector2 = p["pos"]
		var dp := pos.distance_to(pp)
		if dp <= float(p["hit"]) + CONTACT_HIT_PAD:
			if GameManager.has_method("ship_take_damage"):
				GameManager.ship_take_damage(int(round(float(p["dmg"]) * BOSS_DAMAGE_MULT)))
			_projectiles.remove_at(i)
		elif float(p["life"]) >= _proj_life(typ) or dp >= PROJ_CULL_DIST \
				or (typ == "firevortex_coil" and float(p["d"]) >= float(p["radius"]) * (1.0 + PI)):
			_projectiles.remove_at(i)
		i -= 1

func _check_contact() -> void:
	if contact_damage <= 0:
		return
	if global_position.distance_to(_player_pos()) <= _radius + CONTACT_HIT_PAD:
		if GameManager.has_method("ship_take_damage"):
			GameManager.ship_take_damage(contact_damage)   # ship iframes prevent per-frame spam

# ── Damage / death ───────────────────────────────────────────────────────────────
func take_damage(amount: float, stagger: float = 0.0) -> void:
	if _dead:
		return
	var dr := 0.0
	if GameManager.has_method("armor_damage_reduction"):
		dr = GameManager.armor_damage_reduction(armor)
	hp -= amount * (1.0 - dr)
	_flash_color = KILL_FLASH_COLOR if hp <= 0.0 else HIT_FLASH_COLOR
	_flash = HIT_FLASH_TIME
	GameManager.boss_hp = int(maxf(0.0, hp))
	if GameManager.has_signal("boss_hp_changed"):
		GameManager.boss_hp_changed.emit(GameManager.boss_hp)
	queue_redraw()
	if hp <= 0.0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	if xp > 0 and _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("spawn_xp_orb"):
		_mgr.spawn_xp_orb(global_position, xp)
	var ex: Node2D = ArenaExplosion.new()
	if get_parent() != null:
		get_parent().add_child(ex)
		ex.global_position = global_position
		ex.call("setup", global_position, maxf(_draw_size.x, _radius * 2.0) * 1.6)
	if GameManager.has_signal("boss_defeated"):
		GameManager.boss_defeated.emit()
	queue_free()

# ── Draw ────────────────────────────────────────────────────────────────────────
func _draw() -> void:
	# Laser telegraph / beam (under the body so the body stays readable).
	var ph := _m3_phase()
	if ph == 2 or ph == 3:
		var end := _laser_aim * LASER_LEN
		if ph == 2:   # dull warning
			draw_line(Vector2.ZERO, end, Color(0.55, 0.6, 0.7, 0.5), LASER_WARN_W)
			draw_line(Vector2.ZERO, end, Color(0.8, 0.85, 1.0, 0.4), LASER_WARN_W * 0.4)
		else:         # bright fire (rainbow-ish flicker)
			var hue := fposmod(_move_t * 1.5, 1.0)
			var col := Color.from_hsv(hue, 0.5, 1.0)
			draw_line(Vector2.ZERO, end, Color(col.r, col.g, col.b, 0.30), LASER_FIRE_W)
			draw_line(Vector2.ZERO, end, Color(col.r, col.g, col.b, 0.6), LASER_FIRE_W * 0.5)
			draw_line(Vector2.ZERO, end, Color(1, 1, 1, 0.9), LASER_FIRE_W * 0.16)
	# Body (spins around the centre = node origin).
	if _tex != null and _draw_size != Vector2.ZERO:
		var rect := Rect2(-_draw_size * 0.5, _draw_size)
		draw_set_transform(Vector2.ZERO, _spin, Vector2.ONE)
		draw_texture_rect(_tex, rect, false)
		if _flash > 0.0:
			draw_texture_rect(_tex, rect, false, Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash / HIT_FLASH_TIME))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, _radius, Color(0.7, 0.68, 0.62))
	# Projectiles (stored in world space → local = world - origin).
	for p: Dictionary in _projectiles:
		_draw_proj((p["pos"] as Vector2) - global_position, String(p["type"]), float(p["hit"]), float(p["rot"]))
	# M2 fire is now a stream of "firevortex_coil" projectiles (see _spawn_coil/_coil_path); only the
	# charge telegraph is drawn here.
	if _move == 2 and _m2_phase == 1:
		_draw_charge()
	# Boss HP bar.
	var top := -_draw_size.y * 0.5 - 22.0 if _draw_size != Vector2.ZERO else -_radius - 22.0
	var frac := clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
	var bx := -HP_BAR_W * 0.5
	draw_rect(Rect2(bx, top, HP_BAR_W, HP_BAR_H), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bx, top, HP_BAR_W * frac, HP_BAR_H), Color(1.0, 0.3, 0.25))
	draw_rect(Rect2(bx, top, HP_BAR_W, HP_BAR_H), Color(1, 1, 1, 0.5), false, 1.0)

func _draw_proj(lp: Vector2, type: String, hit: float, rot: float) -> void:
	match type:
		"vortex":
			if _draw_sprite_proj(lp, _vortex_frames, _vortex_delays, hit, rot):
				return
			# fallback: spinning swirl ring
			draw_circle(lp, VORTEX_SIZE * 1.6, Color(VORTEX_COLOR.r, VORTEX_COLOR.g, VORTEX_COLOR.b, 0.15))
			for k in 3:
				var a0 := rot + float(k) * TAU / 3.0
				draw_arc(lp, VORTEX_SIZE, a0, a0 + 1.6, 10, Color(VORTEX_COLOR.r, VORTEX_COLOR.g, VORTEX_COLOR.b, 0.9), 3.0)
			draw_circle(lp, VORTEX_SIZE * 0.35, Color(1, 1, 1, 0.85))
		"drop":
			if _draw_sprite_proj(lp, _vortex_frames, _vortex_delays, hit, rot):
				return
			draw_circle(lp, DROP_SIZE * 1.7, Color(DROP_COLOR.r, DROP_COLOR.g, DROP_COLOR.b, 0.18))
			draw_circle(lp, DROP_SIZE, DROP_COLOR)
			draw_circle(lp, DROP_SIZE * 0.45, Color(1, 1, 0.8, 0.95))
		"firevortex_coil":
			if _draw_sprite_proj(lp, _vortex_frames, _vortex_delays, hit, rot):
				return
			draw_circle(lp, hit * 1.6, Color(FIRE_COLOR_OUT.r, FIRE_COLOR_OUT.g, FIRE_COLOR_OUT.b, 0.3))
			draw_circle(lp, hit, FIRE_COLOR_MID)
			draw_circle(lp, hit * 0.4, FIRE_COLOR_CORE)
		"blob":
			if _draw_sprite_proj(lp, _blob_frames, _blob_delays, hit, rot):
				return
			var pulse := 0.85 + 0.15 * sin(rot * 6.0)
			draw_circle(lp, BLOB_SIZE * 1.7 * pulse, Color(BLOB_COLOR.r, BLOB_COLOR.g, BLOB_COLOR.b, 0.18))
			draw_circle(lp, BLOB_SIZE * pulse, BLOB_COLOR)
			draw_circle(lp, BLOB_SIZE * 0.4, Color(1, 1, 1, 0.85))
		_:   # spike → legacy fire-vortex sprite (spins via VORTEX_ROT)
			if _draw_sprite_proj(lp, _vortex_frames, _vortex_delays, hit, rot):
				return
			draw_circle(lp, SPIKE_SIZE * 1.6, Color(SPIKE_COLOR.r, SPIKE_COLOR.g, SPIKE_COLOR.b, 0.25))
			draw_circle(lp, SPIKE_SIZE, SPIKE_COLOR)
			draw_circle(lp, SPIKE_SIZE * 0.4, Color(1, 1, 1, 0.9))

## Draw an animated legacy sprite for a projectile (returns false if no frames → caller draws a circle).
func _draw_sprite_proj(lp: Vector2, frames: Array, delays: Array, hit: float, rot: float) -> bool:
	if frames.is_empty():
		return false
	var total := 0.0
	for d: float in delays:
		total += d
	if total <= 0.0:
		total = 0.1
	var ft := fmod(_proj_t, total)
	var idx := 0
	var acc := 0.0
	for i in frames.size():
		acc += float(delays[i])
		if ft < acc:
			idx = i
			break
	var tex: Texture2D = frames[idx]
	if tex == null:
		return false
	var ts := tex.get_size()
	var w := hit * PROJ_SPRITE_SCALE
	var h := w * (ts.y / maxf(1.0, ts.x))
	draw_set_transform(lp, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-w * 0.5, -h * 0.5, w, h), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true

func _draw_charge() -> void:
	# 0.8s charge-up telegraph: a pulsing danger ring at the incoming fire radius, a directional
	# warning toward the tracked aim, a building charge core, and a flashing danger sign overhead.
	var p := clampf(_charge_t / M2_CHARGE_T, 0.0, 1.0)
	var blink := 0.5 + 0.5 * sin(_charge_t * 42.0)
	# Telegraph ring where the fire will coil.
	draw_arc(Vector2.ZERO, FIRE_RING_RADIUS, 0.0, TAU, 96, Color(1.0, 0.15, 0.08, 0.2 + 0.3 * blink), 3.0)
	# Directional warning toward the (still-tracking) aim.
	draw_line(Vector2.ZERO, _charge_aim * FIRE_RING_RADIUS, Color(1.0, 0.3, 0.08, 0.25 + 0.4 * blink), 3.0 + 7.0 * p)
	# Charge core building at the mouth.
	var cr := lerpf(6.0, 30.0, p)
	draw_circle(Vector2.ZERO, cr * 1.7, Color(1.0, 0.4, 0.1, 0.22 * (0.6 + 0.4 * blink)))
	draw_circle(Vector2.ZERO, cr, Color(1.0, 0.7, 0.2, 0.55))
	draw_circle(Vector2.ZERO, cr * 0.5, Color(1.0, 1.0, 0.85, 0.85 * (0.6 + 0.4 * blink)))
	# Danger sign (flashing warning triangle with "!") above the boss.
	var top := (-_draw_size.y * 0.5 - 52.0) if _draw_size != Vector2.ZERO else (-_radius - 52.0)
	var sc := Vector2(0.0, top)
	var s := 20.0
	var dcol := Color(1.0, 0.85, 0.1, 0.45 + 0.55 * blink)
	var t0 := sc + Vector2(0.0, -s)
	var t1 := sc + Vector2(s * 0.92, s * 0.72)
	var t2 := sc + Vector2(-s * 0.92, s * 0.72)
	draw_colored_polygon(PackedVector2Array([t0, t1, t2]), Color(0.55, 0.0, 0.0, 0.4 + 0.5 * blink))
	draw_polyline(PackedVector2Array([t0, t1, t2, t0]), dcol, 2.5)
	draw_line(sc + Vector2(0.0, -s * 0.35), sc + Vector2(0.0, s * 0.18), dcol, 3.0)
	draw_circle(sc + Vector2(0.0, s * 0.42), 2.2, dcol)
