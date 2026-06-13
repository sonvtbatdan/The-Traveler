extends "res://scripts/gameplay/enemy_base.gd"

## Missile_launcher — a tanky stationary enemy that descends from the top (like the Sentinel), holds a
## centred position, and fires ONE fan of 4 glowing-blue "plasma line" darts. Each dart whips out fast
## BEHIND the launcher (away from the player), decelerates to a hover (the telegraph), then peels off one
## at a time and boomerangs back at the player on a homing, accelerating arc.
##
## Motion is reused, not reinvented:
##   • fan-out → hover  = the acid glob's fast-then-decelerate (vel *= pow(DRAG, delta))  [weapon_system.gd]
##   • return slow→fast  = the homing missile's acceleration easing (accel grows with seek_t) [weapon_system.gd]
##   • return curving    = the homing missile's turn-rate-limited steering (vel.lerp toward target) [weapon_system.gd]
##   • FX architecture    = the Beamer (FX node parented to the EnemyManager, additive glow) [enemy_beamer.gd]
##
## The darts are drawn as glowing blue energy darts (white-hot core + blue glow head + streaking tail,
## additive blend) by the _PlasmaVolley node below.

# ── Tunables: the enemy ───────────────────────────────────────────────────────
const ML_HP: float = 728.0          # Sentinel's 560 × 1.3 (then ×ENEMY_HP_MULT in _ready → ~1092 effective)
const ML_XP: int = 18
const ML_DESCEND_SPEED: float = 200.0   # px/s entry descent (matches the Sentinel)
const ML_STOP_FRAC: float = 0.30        # parks this far down the screen (a touch higher than the Sentinel,
										#   to give the upward fan-out room above it)
const ML_FIRE_DELAY: float = 0.6        # after parking, wait this long, then fire the single fan
const ML_REFIRE: bool = false           # default: fire ONCE. Flip true to loop on a cooldown.
const ML_REFIRE_COOLDOWN: float = 6.0   # (only used when ML_REFIRE is true)

# ── Tunables: the plasma-line volley (motion) ─────────────────────────────────
# Each dart's arc: whip out fast BEHIND the launcher → decelerate to a hover (telegraph) → after a
# stagger, peel off and boomerang back at the player, slow→fast, curving via turn-rate-limited homing.
const ML_FAN_COUNT: int = 4          # darts per fan
const ML_FAN_ANGLE: float = 80.0     # total fan spread (deg), centred BEHIND the launcher (away from the player)
const ML_OUT_SPEED: float = 750.0    # initial fan-out speed (fast) — reuses the acid glob's launch
const ML_DRAG: float = 0.06          # fraction of velocity kept per SECOND during fan-out → decelerates to a hover
const ML_HOVER_END: float = 1.0      # time from fire until dart 0 begins its return (the telegraph window)
const ML_STAGGER: float = 0.5        # gap between each successive dart starting its return (1→2→3→4)
const ML_RETURN_START: float = 40.0  # return speed at the start (slow creep) — reuses MISSILE_SEEK_START
const ML_RETURN_ACCEL: float = 900.0 # base return acceleration — reuses MISSILE_ACCEL
const ML_ACCEL_RAMP: float = 9.0     # acceleration grows ×this per second → slow start, hard whip (MISSILE_ACCEL_RAMP)
const ML_RETURN_MAX: float = 800.0  # cap on return speed
# Homing turn rate on return, in two stages: a sharp initial lock-on, then a looser turn for the rest of
# the flight (so it commits to its arc and can overshoot a dodging player). HIGHER = sharper / less overshoot.
const ML_TURN_EARLY: float = 10.0    # turn rate for the first ML_TURN_SWITCH_T seconds of the return
const ML_TURN_LATE: float = 3.0      # turn rate after that
const ML_TURN_SWITCH_T: float = 0.5  # when (seconds into the return) the rate drops from EARLY to LATE
const ML_LINE_DMG: int = 8           # damage to the ship on contact
const ML_HIT_R: float = 6.0          # dart hit radius (vs the ship)
const ML_LIFETIME: float = 6.0       # hard cull a dart after this long (safety net)
const ML_TRAIL_LEN: int = 40         # past positions kept per dart (path history the curved tail follows)

# ── Tunables: the plasma-line look (comet/energy dart) ────────────────────────
# A glowing comet dart, built head → tail from soft ADDITIVE layers stamped from one radial sprite, so
# colours blend with no hard edges. The tail follows the dart's ACTUAL (curved) path, so it bends as the
# dart homes. Colour gradient along the dart: white-blue head → violet tail.
const ML_GLOW_INTENSITY: float = 1.0          # global multiplier on EVERY layer's brightness (overall glow)
const ML_COL_HEAD := Color(0.55, 0.85, 1.0)   # near-head colour (cyan / blue-white)
const ML_COL_TAIL := Color(0.62, 0.30, 1.0)   # far-tail colour (purple / magenta)
# Head: a near-pure-white core inside a soft cyan bloom (enlarged — the bright bulb the body flows from).
const ML_CORE_SIZE: float = 9.0      # white-hot core radius (px) — the brightest point at the front tip
const ML_CORE_BRIGHT: float = 1.0    # core alpha (near-overexposed white)
const ML_BLOOM_SIZE: float = 32.0    # cyan bloom radius around the core
const ML_BLOOM_ALPHA: float = 0.5    # bloom brightness
# Tail/trail: follows the curved path and flows CONTINUOUSLY out of the head — widest where it meets the
# head (≈ the bloom, so there's no seam), tapering smoothly to a point at the back; colour white-blue → violet.
const ML_TAIL_MIN: float = 28.0      # tail length (px) when (nearly) static
const ML_TAIL_MAX: float = 180.0     # tail length at full speed
const ML_FULL_SPEED: float = 700.0   # speed (px/s) at which the tail reaches ML_TAIL_MAX
const ML_TAIL_SAMPLES: int = 30      # blobs stamped along the tail (more = smoother)
const ML_TAIL_W_HEAD: float = 24.0   # body half-width where it meets the head (≈ the bloom → seamless)
const ML_TAIL_W_TAIL: float = 2.0    # body half-width at the far tip (tapers to a point)
const ML_SPINE_FRAC: float = 0.32    # crisp bright spine width as a fraction of the body width
const ML_SPINE_ALPHA: float = 0.7    # brightness of the crisp central spine
const ML_HAZE_ALPHA: float = 0.30    # brightness of the soft surrounding purple haze (the body)
const ML_HAZE_WISP: float = 5.0      # how far the haze wobbles off the path (px) — gas-like irregularity
# 4-point lens-flare cross at the head (toggle + scale — prominent on big darts, off/tiny on small ones).
const ML_FLARE_ON: bool = true
const ML_FLARE_SCALE: float = 1.0    # multiplies the spike sizes below
const ML_FLARE_LONG: float = 80.0    # spike length along the direction of travel
const ML_FLARE_SHORT: float = 30.0   # perpendicular spike length
const ML_FLARE_THIN: float = 6.0     # spike thickness
const ML_FLARE_ALPHA: float = 0.5    # spike brightness
# Glistering dust: tiny twinkling motes shed along the flight path.
const ML_DUST: bool = true           # set false to drop the dust trail
const ML_DUST_GAP: float = 11.0      # px of travel between shed motes (so dust is even at any speed)
const ML_DUST_TTL: float = 0.7       # how long a mote lingers (s)
const ML_DUST_SIZE: float = 5.0      # mote glow diameter (px)
const ML_DUST_SPREAD: float = 6.0    # random scatter off the flight path (px)
const ML_GLITTER_SPEED: float = 20.0 # twinkle speed (higher = faster shimmer)

enum Phase { DESCEND, ENGAGE }
var _phase: int = Phase.DESCEND
var _stop_y: float = 0.0
var _engage_t: float = 0.0
var _fired: bool = false
var _volley: Node = null   # most-recent in-flight plasma volley (freed on death; self-frees when spent)

func _configure() -> void:
	hp_max = ML_HP
	xp_reward = ML_XP
	contact_damage = 0          # it launches darts; never rams
	contact_explodes = false
	body_color = Color(0.16, 0.20, 0.34)   # dark blue-grey core; the plasma darts carry the look
	shape_kind = "square"

## Called by EnemyManager.spawn_missile_launcher() after add_child() (size is known by then).
func spawn(mgr: Node) -> void:
	var screen: Vector2 = mgr.screen_size()
	_stop_y = screen.y * ML_STOP_FRAC
	position = Vector2(screen.x * 0.5 - size.x * 0.5, -size.y)   # start just above the top edge, centred
	_phase = Phase.DESCEND

func _tick(delta: float) -> void:
	match _phase:
		Phase.DESCEND:
			position += Vector2(0.0, ML_DESCEND_SPEED * delta)
			if center().y >= _stop_y:
				position = Vector2(position.x, _stop_y - size.y * 0.5)
				_phase = Phase.ENGAGE
				_engage_t = 0.0
		Phase.ENGAGE:
			_engage_t += delta
			if not _fired:
				if _engage_t >= ML_FIRE_DELAY:
					_fire_volley()
					_fired = true
					_engage_t = 0.0
			elif ML_REFIRE and _engage_t >= ML_REFIRE_COOLDOWN:
				_fire_volley()
				_engage_t = 0.0

## Fire one fan of ML_FAN_COUNT plasma lines, fanned out BEHIND the launcher (away from the player). The
## volley is a self-ticking Node2D parented to the EnemyManager (SpaceScreen-local space) — exactly like
## the Beamer parents its beam FX to the manager — so it lives in the same coords as the ship/bullets and
## survives independently while it resolves.
func _fire_volley() -> void:
	if _mgr == null or not is_instance_valid(_mgr):
		return
	var muzzle := center()
	var to_player: Vector2 = _mgr.ship_center() - muzzle
	var away: Vector2 = (-to_player).normalized() if to_player.length() > 0.01 else Vector2.UP
	var volley := _PlasmaVolley.new()
	_mgr.add_child(volley)
	volley.launch(_mgr, muzzle, away)
	_volley = volley

func _exit_tree() -> void:
	super()   # base unregisters the weapon target
	if _volley != null and is_instance_valid(_volley):
		_volley.queue_free()
	_volley = null

# ── The plasma-line volley ────────────────────────────────────────────────────
## Owns the ML_FAN_COUNT darts and ticks them through the 4-phase arc. Parented to the EnemyManager, so
## its local space IS SpaceScreen-local (the node stays at origin; dart positions are absolute). Frees
## itself once every dart has resolved (hit the ship or timed out). Phase 2 draws a simple placeholder
## dart so the motion is visible; Phase 3 replaces _draw() with the glowing blue look.
class _PlasmaVolley extends Node2D:
	var _mgr: Node = null
	var _lines: Array = []   # each: {pos, vel, t, life, return_at, returning, speed, seek_t, trail, dust_acc, phase}
	var _dust: Array = []    # glistering motes: {pos, life, ttl, size, hue, phase}
	var _clock: float = 0.0  # drives the twinkle shimmer
	var _soft: Texture2D = null   # soft radial sprite stamped for every glow layer (edgeless falloff)

	## Build the fan. `muzzle` = launcher centre; `away` = unit direction away from the player (the fan
	## is centred on this and spread across ML_FAN_ANGLE).
	func launch(mgr: Node, muzzle: Vector2, away: Vector2) -> void:
		_mgr = mgr
		z_index = 4   # above enemies/bullets; the additive glow reads as light
		# Additive blend → the core, glow and trail stack as light (same technique as the Beamer's _OrbGlow).
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		_soft = _make_soft_tex()
		var base_ang := away.angle()
		var count: int = ML_FAN_COUNT
		for i in count:
			var frac: float = 0.0 if count <= 1 else float(i) / float(count - 1)
			var ang := base_ang + deg_to_rad(ML_FAN_ANGLE) * (frac - 0.5)
			var dir := Vector2(cos(ang), sin(ang))
			_lines.append({
				"pos": muzzle,
				"vel": dir * ML_OUT_SPEED,          # fast launch outward (fan-out)
				"t": 0.0,                            # time since fire
				"life": 0.0,                         # total lifetime (for the hard cull)
				"return_at": ML_HOVER_END + float(i) * ML_STAGGER,   # staggered return start
				"returning": false,
				"speed": 0.0,
				"seek_t": 0.0,
				"trail": [muzzle] as Array,
				"dust_acc": 0.0,           # px travelled since the last dust mote was shed
				"phase": randf() * TAU,    # twinkle offset so darts don't shimmer in lockstep
			})

	func _process(delta: float) -> void:
		if _mgr == null or not is_instance_valid(_mgr):
			queue_free()
			return
		_clock += delta
		var ship_c: Vector2 = _mgr.ship_center()
		var ship_r: float = _mgr.ship_radius()
		var screen: Vector2 = _mgr.screen_size()
		var i := _lines.size() - 1
		while i >= 0:
			var ln: Dictionary = _lines[i]
			ln["t"] = float(ln["t"]) + delta
			ln["life"] = float(ln["life"]) + delta
			var prev: Vector2 = ln["pos"]
			if not bool(ln["returning"]):
				_tick_out(ln, delta)
				if float(ln["t"]) >= float(ln["return_at"]):
					_begin_return(ln, ship_c)
			else:
				_tick_return(ln, delta, ship_c)
			# trail history (newest first) for the streak tail
			var trail: Array = ln["trail"]
			trail.push_front(ln["pos"])
			if trail.size() > ML_TRAIL_LEN:
				trail.resize(ML_TRAIL_LEN)
			_shed_dust(ln, prev)   # drop glistering motes as it travels
			# resolve: hit the ship, or time out / fly far off-screen
			var p: Vector2 = ln["pos"]
			var off := p.x < -120.0 or p.x > screen.x + 120.0 or p.y < -120.0 or p.y > screen.y + 120.0
			if p.distance_to(ship_c) <= ship_r + ML_HIT_R:
				GameManager.ship_take_damage(ML_LINE_DMG)
				_lines.remove_at(i)
			elif float(ln["life"]) >= ML_LIFETIME or (bool(ln["returning"]) and off):
				_lines.remove_at(i)
			i -= 1
		_tick_dust(delta)
		queue_redraw()
		if _lines.is_empty() and _dust.is_empty():
			queue_free()

	## Shed evenly-spaced dust along the segment the dart just travelled (none while it's truly static).
	func _shed_dust(ln: Dictionary, prev: Vector2) -> void:
		if not ML_DUST:
			return
		var p: Vector2 = ln["pos"]
		var seg := p - prev
		var moved := seg.length()
		if moved < 0.01:
			return
		var acc := float(ln["dust_acc"]) + moved
		var dir := seg / moved
		var perp := Vector2(-dir.y, dir.x)
		while acc >= ML_DUST_GAP:
			acc -= ML_DUST_GAP
			var along := prev + dir * (moved - acc)
			var spot := along + perp * randf_range(-ML_DUST_SPREAD, ML_DUST_SPREAD)
			_dust.append({
				"pos": spot,
				"life": 0.0,
				"ttl": ML_DUST_TTL * randf_range(0.7, 1.2),
				"size": ML_DUST_SIZE * randf_range(0.6, 1.2),
				"hue": randf(),                # 0 = blue, 1 = white-hot
				"phase": randf() * TAU,
			})
		ln["dust_acc"] = acc

	func _tick_dust(delta: float) -> void:
		var i := _dust.size() - 1
		while i >= 0:
			_dust[i]["life"] = float(_dust[i]["life"]) + delta
			if float(_dust[i]["life"]) >= float(_dust[i]["ttl"]):
				_dust.remove_at(i)
			i -= 1

	## Phases A+B — fan-out then hover. Reuses the acid glob's exponential decel (vel *= pow(DRAG, delta)).
	func _tick_out(ln: Dictionary, delta: float) -> void:
		ln["vel"] = (ln["vel"] as Vector2) * pow(ML_DRAG, delta)
		ln["pos"] = (ln["pos"] as Vector2) + (ln["vel"] as Vector2) * delta

	## Switch a hovering dart into its return. It keeps its outward facing (near-zero speed) so the homing
	## has to bend it ~180° back at the player → the boomerang curl.
	func _begin_return(ln: Dictionary, ship_c: Vector2) -> void:
		var v: Vector2 = ln["vel"]
		var dir := v.normalized() if v.length() > 0.01 else ((ln["pos"] as Vector2) - ship_c).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		ln["returning"] = true
		ln["speed"] = ML_RETURN_START
		ln["seek_t"] = 0.0
		ln["vel"] = dir * ML_RETURN_START

	## Phase C — staggered homing return. Reuses the missile's acceleration easing (accel grows with
	## seek_t → slow→fast) AND its turn-rate-limited steering (vel.lerp toward the player, constant speed).
	func _tick_return(ln: Dictionary, delta: float, ship_c: Vector2) -> void:
		ln["seek_t"] = float(ln["seek_t"]) + delta
		var accel := ML_RETURN_ACCEL * (1.0 + ML_ACCEL_RAMP * float(ln["seek_t"]))
		ln["speed"] = minf(ML_RETURN_MAX, float(ln["speed"]) + accel * delta)
		var spd: float = ln["speed"]
		var cur: Vector2 = ln["vel"]
		var desired := (ship_c - (ln["pos"] as Vector2)).normalized() * spd
		# Sharp lock-on for the first ML_TURN_SWITCH_T seconds of the return, then a looser turn for the rest.
		var turn: float = ML_TURN_EARLY if float(ln["seek_t"]) < ML_TURN_SWITCH_T else ML_TURN_LATE
		var steer := cur.lerp(desired, clampf(turn * delta, 0.0, 1.0))
		if steer.length() > 0.01:
			ln["vel"] = steer.normalized() * spd
		ln["pos"] = (ln["pos"] as Vector2) + (ln["vel"] as Vector2) * delta

	# Glistering dust (behind) → comet darts (curved tail + spine-in-haze + glow head + lens-flare cross).
	func _draw() -> void:
		_draw_dust()
		for ln: Dictionary in _lines:
			var p: Vector2 = ln["pos"]
			var d := _dart_dir(ln["vel"], ln["trail"])
			var speed: float = (ln["vel"] as Vector2).length()
			_draw_comet(p, d, speed, float(ln["phase"]), ln["trail"])

	## Travel direction for the head/flare: the velocity when moving, else the last trail step (so a
	## hovering dart still points somewhere sensible), else up.
	func _dart_dir(v: Vector2, trail: Array) -> Vector2:
		if v.length() > 1.0:
			return v.normalized()
		if trail.size() >= 2:
			var diff: Vector2 = (trail[0] as Vector2) - (trail[1] as Vector2)
			if diff.length() > 0.01:
				return diff.normalized()
		return Vector2.UP

	## Even arc-length points along the recorded path (newest-first `trail`), from the head (f=0) back to
	## `tail_len` (f=1). Fewer than `n` points if the history is shorter than `tail_len` (e.g. just fired).
	func _tail_samples(trail: Array, tail_len: float, n: int) -> Array:
		var out: Array = []
		if trail.size() == 0 or tail_len <= 0.0 or n < 2:
			return out
		var step := tail_len / float(n - 1)
		out.append(trail[0])           # f = 0 (the head)
		var next_mark := step
		var traveled := 0.0
		var i := 0
		while i < trail.size() - 1 and out.size() < n:
			var p0: Vector2 = trail[i]
			var p1: Vector2 = trail[i + 1]
			var seglen := p0.distance_to(p1)
			if seglen < 0.0001:
				i += 1
				continue
			while next_mark <= traveled + seglen and out.size() < n:
				out.append(p0.lerp(p1, (next_mark - traveled) / seglen))
				next_mark += step
			traveled += seglen
			i += 1
		return out

	## One comet dart: a curved tail (crisp bright spine inside a wide wispy purple haze, colour blending
	## white-blue → violet) + a tiny white-hot core in a cyan bloom + an optional 4-point lens-flare cross.
	func _draw_comet(p: Vector2, d: Vector2, speed: float, phase: float, trail: Array) -> void:
		var tail_len := lerpf(ML_TAIL_MIN, ML_TAIL_MAX, clampf(speed / ML_FULL_SPEED, 0.0, 1.0))
		var pts := _tail_samples(trail, tail_len, ML_TAIL_SAMPLES)
		var perp := Vector2(-d.y, d.x)
		# Draw tail tail→head so the brighter head layers land on top. Each sample = a wide wispy haze blob
		# (purple, wobbling off the path) wrapping a thin bright spine (whiter near the head).
		for k in range(pts.size() - 1, -1, -1):
			var f := float(k) / float(ML_TAIL_SAMPLES - 1)   # 0 head → 1 tail
			var fade := (1.0 - f)
			var col := ML_COL_HEAD.lerp(ML_COL_TAIL, f)
			# Body half-width: widest at the head (≈ bloom, seamless), tapering to a point at the tail.
			var body_w := lerpf(ML_TAIL_W_HEAD, ML_TAIL_W_TAIL, f)
			var bp: Vector2 = pts[k]
			# wispy haze body — the wide soft shape that flows out of the head (wobbles toward the tail)
			var wob := sin(f * 9.0 + phase + _clock * 2.0) * ML_HAZE_WISP * f
			_blob(bp + perp * wob, Vector2(body_w * 2.0, body_w * 2.0), 0.0, _ca(col, ML_HAZE_ALPHA * fade))
			# crisp spine inside it — a fraction of the body width, bright, whiter toward the head
			var sc := col.lerp(Color(1.0, 1.0, 1.0, 1.0), fade * 0.6)
			var sw := body_w * ML_SPINE_FRAC
			_blob(bp, Vector2(sw * 2.0, sw * 2.0), 0.0, _ca(sc, ML_SPINE_ALPHA * fade))
		# Head: soft cyan bloom → near-pure-white core (the brightest, near-overexposed point at the tip).
		_blob(p, Vector2(ML_BLOOM_SIZE * 2.0, ML_BLOOM_SIZE * 2.0), 0.0, _ca(ML_COL_HEAD, ML_BLOOM_ALPHA * 0.5))
		_blob(p, Vector2(ML_BLOOM_SIZE * 1.1, ML_BLOOM_SIZE * 1.1), 0.0, _ca(Color(0.8, 0.93, 1.0), ML_BLOOM_ALPHA))
		_blob(p, Vector2(ML_CORE_SIZE * 2.0, ML_CORE_SIZE * 2.0), 0.0, _ca(Color(1.0, 1.0, 1.0), ML_CORE_BRIGHT))
		# 4-point lens-flare cross (long spike along travel + short perpendicular), gently twinkling.
		if ML_FLARE_ON:
			var ang := d.angle()
			var tw := 0.6 + 0.4 * sin(_clock * ML_GLITTER_SPEED + phase)
			var fcol := _ca(Color(0.85, 0.95, 1.0), ML_FLARE_ALPHA * tw)
			var s := ML_FLARE_SCALE
			_blob(p, Vector2(ML_FLARE_LONG * s, ML_FLARE_THIN * s), ang, fcol)
			_blob(p, Vector2(ML_FLARE_SHORT * s, ML_FLARE_THIN * 0.8 * s), ang + PI * 0.5, fcol)

	## Apply the global glow-intensity multiplier to a colour's alpha (kept ≤ 1).
	func _ca(c: Color, a: float) -> Color:
		return Color(c.r, c.g, c.b, clampf(a * ML_GLOW_INTENSITY, 0.0, 1.0))

	## Glistering dust: tiny twinkling soft motes that fade as they age (cyan↔white per mote).
	func _draw_dust() -> void:
		for m: Dictionary in _dust:
			var fade := 1.0 - clampf(float(m["life"]) / maxf(0.01, float(m["ttl"])), 0.0, 1.0)
			var tw := 0.25 + 0.75 * (0.5 + 0.5 * sin(_clock * ML_GLITTER_SPEED + float(m["phase"])))
			var col := ML_COL_HEAD.lerp(Color(1.0, 1.0, 1.0, 1.0), float(m["hue"]))
			var a := fade * tw
			var sz: float = float(m["size"])
			_blob(m["pos"], Vector2(sz * 2.2, sz * 2.2), 0.0, Color(col.r, col.g, col.b, 0.22 * a))
			_blob(m["pos"], Vector2(sz * 0.9, sz * 0.9), 0.0, Color(1.0, 1.0, 1.0, 0.8 * a))

	## Stamp the soft radial sprite at `pos`, sized `sizev` (w,h → ellipse/spike), rotated `rot`, tinted.
	func _blob(pos: Vector2, sizev: Vector2, rot: float, col: Color) -> void:
		if _soft == null:
			return
		draw_set_transform(pos, rot, Vector2.ONE)
		draw_texture_rect(_soft, Rect2(-sizev * 0.5, sizev), false, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## Build the soft radial sprite once: white with a smooth alpha falloff to 0 at the rim (edgeless).
	func _make_soft_tex() -> Texture2D:
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var c := float(s - 1) * 0.5
		for y in s:
			for x in s:
				var dx := (float(x) - c) / c
				var dy := (float(y) - c) / c
				var dist := sqrt(dx * dx + dy * dy)
				var a := pow(clampf(1.0 - dist, 0.0, 1.0), 2.4)   # smooth, edgeless falloff
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		return ImageTexture.create_from_image(img)
