extends CharacterBody2D
## World-space arena enemy — the port of the legacy NormalEnemy roster as ONE data-driven script. The
## wave_director configures each instance from its enemy table (behavior + stats); this script runs the
## behavior each frame, takes damage via the universal take_damage(amount) contract (so arena_weapons hit
## it), deals contact damage to the player via GameManager, and grants XP on death.
##
## Behaviours ported (shmup-directional ones reinterpreted player-relative for the top-down arena):
##   chase, centipede, dash(diver), orbit(dragonfly), jump(octopus), jump_diag(spider), scatter(fly),
##   swarm_dive(bee/bug/swarm), shooter, sentinel, beamer, bomber(bombing-wanderer), missile, bomb,
##   dummy, boss_stub(elephant/chromeleon/metalfly). Uses the real enemy sprites (def "icon") when present,
##   falling back to placeholder shapes.

const GifLoader        := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const ArenaExplosion   := preload("res://scripts/gameplay/arena_explosion.gd")
const DeathFX          := preload("res://scripts/gameplay/arena_death_fx.gd")
# Per-enemy attack SFX (one-shot; played from a lazily-created AudioStreamPlayer on bus "SFX").
const SFX_SPIDER_JUMP  := preload("res://assets/audio/sfx/dash.wav")      # spider (jump_diag) leap
const SFX_OCTOPUS_JUMP := preload("res://assets/audio/sfx/chargeby.wav")  # octopus (jump) leap
const SFX_BEAM         := preload("res://assets/audio/sfx/laserbeam.wav") # beamer beam fire (once, no loop)
const SFX_ZAP          := preload("res://assets/audio/sfx/zap1.wav")      # shooter / sentinel fire

static var simplified_mode: bool = false
const ICON_DRAW_SCALE := 2.6   # drawn sprite width = _radius × this (sprites read a bit bigger than the hit circle)
const ENEMY_LAYER := 2              # physics layer enemies live on (separate from the player on layer 1)
const CORE_FRAC := 0.70             # collision-core radius = _radius × this (enemies can't fully stack)
const SWARM_ZOOM_SPEED := 400.0     # swarm "zoom" mode — fly straight through the player and keep going
const SWARM_ZOOM_CULL  := 1200.0    # ...then silently despawn once this far from the player
const RETURN_DIST := 900.0          # dive group re-aims at the player once it gets this far away (loops back)
const SPIRAL_SHRINK := 75       # px/s the spiral radius tightens toward the player (diver)
const SPIRAL_CENTER_SPEED := 80.0   # px/s the spiral center drifts toward the player — run faster to pull away
const TURN_RATE := 10.0             # how fast a sprite eases to face its movement direction (head = sprite north)
const THROWN_BOMB_SPEED := 460.0    # bomber's thrown bombs travel this fast (straight, aimed at the player)
const THROWN_BOMB_RANGE := 1200.0   # a thrown bomb despawns after travelling this far (projectile, not an enemy)

# ── "Alive" procedural-motion tunables (sprite transform only — no new art) ────
const BOB_AMOUNT     := 0.05    # idle breathing scale pulse (±)
const BOB_FREQ_MIN   := 2.2     # per-enemy breathing speed range (randomized → crowd desyncs)
const BOB_FREQ_MAX   := 3.6
const SQUASH_MAG     := 0.12    # max stretch-along-travel / thin-across when moving fast
const SQUASH_EASE    := 9.0     # how fast squash eases toward its speed-driven target
const SQUASH_REF_SPEED := 220.0 # speed at which squash reaches full magnitude
const HIT_FLASH_COLOR := Color(1.0, 1.0, 1.0)    # normal hit → white
const KILL_FLASH_COLOR := Color(1.0, 0.18, 0.18) # a killing blow → red
const HIT_FLASH_TIME := 0.14    # flash duration on hit (more prominent)
# Flash shader: lerp the sprite's pixels toward flash_color by `flash` (modulate-white can't whiten a texture).
const FLASH_SHADER_CODE := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
void fragment() {
	COLOR *= texture(TEXTURE, UV);
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash * COLOR.a);
}
"""
static var _flash_shader: Shader = null
const HIT_SQUASH     := 0.42    # extra squash pulse on hit (more prominent)
const HIT_SQUASH_DECAY := 8.0
const KNOCKBACK_SPEED := 460.0  # recoil impulse away from the player on hit (px/s, decays) — more prominent
const KNOCKBACK_DECAY := 10.0
const SPAWN_POP_TIME := 0.20    # scale-up-with-overshoot + fade-in on spawn
const DEATH_POP_TIME := 0.15    # stretch + scale-up + fade-out before freeing
const SCALE_VAR      := 0.15    # per-enemy base-size variance (±) so the crowd looks individual

# Fallbacks so the enemy is self-sufficient if configured without a def (e.g. manager.spawn_bomb).
const FALLBACK := {
	"chase": {"behavior": "chase", "hp": 30.0, "speed": 95.0, "size": 16.0, "contact": 6, "xp": 5, "shape": "diamond", "tint": Color(0.95, 0.35, 0.30)},
	"bomb":  {"behavior": "bomb",  "hp": 50.0, "speed": 120.0, "size": 18.0, "contact": 0, "explodes": true, "xp": 0, "shape": "circle", "tint": Color(0.9, 0.5, 0.2), "no_collide": true},
	"thrown_bomb": {"behavior": "thrown_bomb", "hp": 12.0, "speed": THROWN_BOMB_SPEED, "size": 13.0, "contact": 0, "explodes": true, "xp": 0, "shape": "circle", "tint": Color(1.0, 0.55, 0.2), "icon": "res://assets/enemies/bomb.png", "no_collide": true},
}

# ── Fire-point positions (loaded from creep_layout.cfg [firepoints]) ─────────
static var _fp_fracs_cache: Dictionary = {}
var _fp_fracs: Array = []   # Array[{frac:Vector2, dir_angle:float, id:int}]

# ── Thrust-point plume VFX ────────────────────────────────────────────────────
static var _tp_fracs_cache: Dictionary = {}
var _plumes: Array[CPUParticles2D] = []
var _plume_vrot_applied: float = 0.0   # last rotation pushed to plume emitters; skip the re-rotate when unchanged
var _plume_vrot_init: bool = false
var _plume_base: Array = []        # [{vel_min, vel_max, sc_min, sc_max, life}] per plume
var _plume_base_cols: Array = []   # [PackedColorArray] per plume
var _plume_red_cols: Array = []    # pre-built red gradient (dragonfly proximity)
var _plume_in_red: bool = false

var _type: String = "chase"
var behavior: String = "chase"
var hp_max: float = 30.0
var hp: float = 30.0
var armor: float = 0.0
var speed: float = 95.0
var _radius: float = 16.0
var hit_radius: float:
	get: return _radius
var contact_damage: int = 6
var contact_explodes: bool = false
var _ship_contact_cd: float = 0.0   # throttles the ship's own contact damage to this enemy (Orbital pool)
var xp: int = 5
var _color: Color = Color(0.95, 0.35, 0.30)
var shape_kind: String = "diamond"
var _icon: String = ""
var _original_icon: String = ""
var _no_collide: bool = false
var _invincible: bool = false   # test dummy: blocks the beam (group "arena_enemy") but ignores all damage
var _tex: Texture2D = null
var _frames: Array = []
var _delays: Array = []
var _anim_acc: float = 0.0
var _anim_frame: int = 0
var _draw_size: Vector2 = Vector2.ZERO

# ── Tracking eye (optional, def "eye"): a separate sprite that slides within a socket toward the player ──
const EYE_TRACK_SPEED := 9.0        # how fast the eye eases toward its player-tracking target
var _has_eye: bool = false
var _eye_icon: String = ""
var _eye_tex: Texture2D = null
var _eye_socket: Vector2 = Vector2(0.5, 0.5)   # socket center, fraction of draw rect (0..1)
var _eye_range: Vector2 = Vector2.ZERO         # max eye displacement, fraction of draw size
var _eye_size_frac: Vector2 = Vector2.ZERO     # eye sprite size, fraction of draw size
var _eye_off: Vector2 = Vector2.ZERO           # current eye offset (local px from socket center, smoothed)

# ── Tentacles (active undulation; the chain root is rigidly anchored to the body) ──
# The child creeps (parent == this body's creep name, e.g. squid-1 … squid-8) define ONE template:
# an ordered chain of segment sprites with rest angles & gaps. Each [tentaclepoints] entry in
# creep_layout.cfg then spawns an INSTANCE of that template at the point's body-relative position, rotated
# by the point's Dir vector — so the squid can have many tentacles fanning out. If no tentacle points are
# defined, one instance is placed at the template's own native position (backward compatible).
# Each instance: root pinned to the body; the rest placed by forward kinematics = rest angle + traveling
# sine wave (always undulates like a swimming limb) + a lag trailing behind the body's motion.
const TENT_WAVE_FREQ := 5.0     # rad/s — temporal speed of the undulation
const TENT_WAVE_K    := 1.3     # phase shift per segment → the wave travels root → tip (S-curve)
const TENT_WAVE_AMP  := 0.42    # rad — per-joint sway amplitude
const TENT_DRAG_GAIN := 0.55    # how strongly a tentacle trails behind body motion
const TENT_DRAG_REF  := 140.0   # body speed (px/s) at which trailing drag reaches full strength
var _tent_template: Array = []  # root→tip: [{tex:Texture2D, size:Vector2, gap:float, rest_ang:float}]
var _tents:         Array = []  # instances: [{base_off:Vector2, dir:float, phase:float, pts:Array}]
var _tent_init:     bool    = false
var _tent_phase:    float   = 0.0           # advancing wave clock shared by all instances
var _tent_prev_pos: Vector2 = Vector2.ZERO  # body position last frame (for velocity-driven drag)
var _tent_vel:      Vector2 = Vector2.ZERO  # smoothed body velocity
var _tent_front_ang: float  = 0.0           # local angle of the tentacle side (squid aims this at the player)
var _tent_attach:    float  = 0.0           # 0→1 wrap blend: how much the tentacles curl around the ship

# ── Squid behaviour: chase led by the tentacles, then cling to the ship & slow it (no contact damage) ──
const SQUID_ATTACH_RANGE := 28.0   # tentacle reach beyond the body radius at which the squid latches on
const SQUID_WRAP_Z       := 101    # while clinging the squid draws ABOVE the ship (SHIP_Z = 100) so tentacles wrap over it
const SQUID_BASE_Z       := 1      # normal enemy draw layer (restored on detach)
var _squid_attached:   bool    = false
var _squid_attach_off: Vector2 = Vector2.ZERO   # held offset from the player while clinging

var _mgr: Node = null
var _target: Node2D = null
var _flash: float = 0.0
var _dead: bool = false
# behavior state
var _t: float = 0.0
var _phase: int = 0
var _timer: float = 0.0
var _fire_t: float = 0.0
var _aim: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _orbit_r: float = 180.0
var _orbit_ang: float = 0.0
var _spiral_dir: float = 1.0   # spin direction (±1) for the spiral approach
var _scatter_target: Vector2 = Vector2.ZERO
var _init_done: bool = false
var _beam_on: bool = false
var _beam_dir: Vector2 = Vector2.RIGHT
var _beam_origin: Vector2 = Vector2.ZERO   # local-space offset to muzzle (for draw + hit-test)
var _burst_shots: int = 0   # shooter burst: bullets remaining in current burst
var _burst_t: float = 0.0   # shooter burst: countdown to next shot
var _missile_volley: Node = null   # missile: in-flight plasma volley (self-frees when done)
var _sfx: AudioStreamPlayer = null  # lazily-created one-shot SFX player (jump / fire / beam)
var sfx_bus: String = "SFX"          # audio bus for this enemy's sounds (menu reroutes to a "distant" bus)
var _jump_interval: float = 1.0   # jump_diag (spider): randomized per jump (±0.5 s)
# "alive" motion state
var _facing: float = 0.0
var _prev_pos: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0
var _bob_freq: float = 3.0
var _scale_var: float = 1.0
var _squash: float = 0.0
var _hit_squash: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _spawn_t: float = 0.0
var _dying: bool = false
var _death_t: float = 0.0
var _stagger_t: float = 0.0   # while > 0, movement/attacks are frozen (per-weapon hit stagger)
# ── Status effects (burn / freeze) — applied by weapons via apply_burn() / apply_freeze() ──
const BURN_DURATION    := 5.0    # s a burn lasts (refreshed on each new stack)
const BURN_TICK        := 1.0    # s between burn DoT ticks
const BURN_PCT         := 0.001  # current-HP fraction lost per second PER stack (0.1%)
const FREEZE_DURATION  := 3.0    # s a freeze lasts before stacks decay (refreshed on apply)
const FREEZE_SLOW_PER  := 0.15   # movement slow per freeze stack
const FREEZE_MAX       := 0.90   # max slow (normal enemies) → 6 stacks
const FREEZE_MAX_BOSS  := 0.30   # max slow (bosses) → 2 stacks
const STUN_DMG_MULT    := 1.5    # +50% damage taken while stunned
const STUN_IMMUNE      := 0.5    # immunity after a stun (normal enemies)
const STUN_IMMUNE_BOSS := 3.0    # immunity after a stun (bosses)
var _burn_stacks: int = 0
var _burn_t: float = 0.0
var _burn_acc: float = 0.0
var _freeze_stacks: int = 0
var _freeze_t: float = 0.0
var _move_slow: float = 0.0    # current freeze slow (0..cap); scales `speed` each frame
var _base_speed: float = -1.0  # captured configured speed (so freeze slow is non-destructive)
var _stun_t: float = 0.0       # remaining stun time (movement/attacks frozen, +50% damage taken)
var _stun_immune_t: float = 0.0  # immunity window after a stun (can't be re-stunned)
var _stun_immune_mult: float = 1.0   # Dazzling Display capstone shortens immunity (set via set_stun_immune_mult)
var _weaken_t: float = 0.0    # Pacifying Jolt: while > 0, this enemy's damage output is halved
var _vuln_t: float = 0.0      # Orb of Annihilation: while > 0, this enemy takes +20% damage from all sources
var _swarm_mode: String = "chase"   # swarm blob unit: "zoom" (fly through @400) or "chase" (slow @speed)
var _flash_color: Color = HIT_FLASH_COLOR

## Configure from the director's enemy table (or a fallback). Call before add_child.
func configure(type_id: String, mgr: Node, def: Dictionary = {}) -> void:
	_type = type_id
	_mgr = mgr
	var d: Dictionary = def if not def.is_empty() else FALLBACK.get(type_id, FALLBACK["chase"])
	behavior         = String(d.get("behavior", "chase"))
	_swarm_mode      = String(d.get("swarm_mode", "chase"))
	hp_max           = float(d.get("hp", 30.0))
	hp               = hp_max
	armor            = float(d.get("armor", 0.0))
	speed            = float(d.get("speed", 95.0))
	_radius          = float(d.get("size", 16.0)) * 1.05
	contact_damage   = int(d.get("contact", 6))
	contact_explodes = bool(d.get("explodes", false))
	xp               = int(d.get("xp", 5))
	_color           = d.get("tint", Color(0.95, 0.35, 0.30))
	shape_kind       = String(d.get("shape", "diamond"))
	_original_icon   = String(d.get("icon", ""))
	_icon            = _original_icon
	if simplified_mode and _icon.begins_with("res://assets/enemies/"):
		var s_path: String = "res://assets/enemies/simplified/" + _icon.get_file()
		if FileAccess.file_exists(s_path):
			_icon = s_path
	_no_collide      = bool(d.get("no_collide", false))
	_invincible      = bool(d.get("invincible", false))
	var eye_cfg: Dictionary = d.get("eye", {})
	if not eye_cfg.is_empty():
		_has_eye       = true
		_eye_icon      = String(eye_cfg.get("icon", ""))
		_eye_socket    = eye_cfg.get("socket", Vector2(0.5, 0.5))
		_eye_range     = eye_cfg.get("range", Vector2.ZERO)
		_eye_size_frac = eye_cfg.get("size", Vector2.ZERO)

func _ready() -> void:
	add_to_group("arena_enemy")
	add_to_group("normal_enemy")
	if behavior == "boss_stub":
		add_to_group("boss")   # weapons (e.g. the lasgun) treat bosses as beam-blockers
	# Collision core: enemies collide with EACH OTHER (own layer) so they can't overlap, but not with the
	# player (layer 1) — contact stays distance-based. `no_collide` types (projectiles/special) pass freely.
	if _no_collide:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = ENEMY_LAYER
		collision_mask = ENEMY_LAYER
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = _radius * CORE_FRAC
		col.shape = shape
		add_child(col)
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_target = get_tree().get_first_node_in_group("player")
	z_index = 1
	# Per-instance flash material (shared compiled shader) — lerps the sprite toward white/red on hit.
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _flash_shader
	material = mat
	_load_icon()
	_load_tentacle()
	_setup_plumes()
	_setup_fire_points()
	# Per-enemy "alive" variation so the crowd reads as individuals, not synced clones.
	_bob_phase = randf() * TAU
	_bob_freq = randf_range(BOB_FREQ_MIN, BOB_FREQ_MAX)
	_scale_var = randf_range(1.0 - SCALE_VAR, 1.0 + SCALE_VAR)
	_prev_pos = global_position

## Prefer a high-res sprite from assets/enemiesHD/; fall back to the standard assets/enemies/ path.
## Only the texture SOURCE changes — draw size still comes from creep_layout.cfg, so the in-game scale/ratio is unchanged.
static func _resolve_sprite(path: String) -> String:
	const STD := "res://assets/enemies/"
	const HD  := "res://assets/enemiesHD/"
	if path.begins_with(STD):
		var hd := HD + path.substr(STD.length())
		if FileAccess.file_exists(hd) or ResourceLoader.exists(hd):
			return hd
	return path

## Load the sprite (PNG, animated GIF, or sprite-sheet PNG+JSON) and compute draw size.
func _load_icon() -> void:
	if _icon == "":
		return
	var src := _resolve_sprite(_icon)   # HD if available, else the standard path
	if _icon.ends_with(".gif"):
		var g := GifLoader.load_gif(src)
		if g != null and g.has_meta("gif_frames"):
			_frames = g.get_meta("gif_frames")
			_delays = g.get_meta("gif_delays") if g.has_meta("gif_delays") else []
			_tex = _frames[0] as Texture2D if not _frames.is_empty() else g
		else:
			_tex = g
	elif _icon.ends_with(".sheet.png"):
		_load_sheet_frames(src)
	else:
		_tex = load(src) as Texture2D
		if _tex == null and src != _icon:
			_tex = load(_icon) as Texture2D   # HD failed to load (e.g. not imported) → standard sprite
	if _tex != null:
		var ts := _tex.get_size()
		var w := _radius * ICON_DRAW_SCALE
		var h := w * (ts.y / ts.x) if ts.x > 0.0 else w
		_draw_size = Vector2(w, h)
		var cname := _icon.get_file().get_basename().to_lower()
		var raw_name := _icon.get_file().get_basename()   # editor keeps the file's original case (e.g. "Squid-body")
		var eo_cfg := ConfigFile.new()
		if eo_cfg.load("res://creep_layout.cfg") == OK:
			var eo: Dictionary = eo_cfg.get_value("creeps", raw_name, eo_cfg.get_value("creeps", cname, {}))
			var eo_sz: Vector2 = eo.get("size", Vector2.ZERO)
			if eo_sz.x > 0.0 and eo_sz.y > 0.0:
				_draw_size = eo_sz
				# Self-heal a stale saved aspect (e.g. source art rotated after placement):
				# keep the configured width but lock height to the texture true aspect -> never stretches.
				if ts.x > 0.0:
					_draw_size.y = eo_sz.x * (ts.y / ts.x)
	if _has_eye and _eye_icon != "" and _eye_tex == null:
		var eye_src := _resolve_sprite(_eye_icon)
		_eye_tex = load(eye_src) as Texture2D
		if _eye_tex == null and eye_src != _eye_icon:
			_eye_tex = load(_eye_icon) as Texture2D

## Parse <name>.sheet.json alongside the PNG to slice frames into AtlasTexture objects.
## JSON format: { "cols": 1, "w": <px>, "h": <px>, "delays": [<sec>, ...] }
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
				cols   = int(data.get("cols", 1))
				fw     = int(data.get("w", fw))
				fh     = int(data.get("h", fh))
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
		var d: float = float(raw_delays[i]) if i < raw_delays.size() else float(raw_delays[-1])
		_delays.append(d)
	if not _frames.is_empty():
		_tex = _frames[0] as Texture2D

## Swap or revert sprite for simplified mode. Called by arena_hud_buttons after scanning the folder.
## simplified_files: dict of filename → full res:// path for every file found in assets/enemies/simplified/.
func apply_simplified(enabled: bool, simplified_files: Dictionary) -> void:
	if _original_icon == "" or not _original_icon.begins_with("res://assets/enemies/"):
		return
	if enabled:
		var fname: String = _original_icon.get_file()
		if simplified_files.has(fname):
			_reload_icon(simplified_files[fname])
	else:
		_reload_icon(_original_icon)

func _reload_icon(new_path: String) -> void:
	_frames.clear()
	_delays.clear()
	_anim_acc = 0.0
	_anim_frame = 0
	_tex = null
	_draw_size = Vector2.ZERO
	_icon = new_path
	_load_icon()
	queue_redraw()

# ── Thrust-point plume VFX ────────────────────────────────────────────────────
func _setup_plumes() -> void:
	if _icon.is_empty() or _draw_size == Vector2.ZERO:
		return
	var cname := _icon.get_file().get_basename().to_lower()
	if not _tp_fracs_cache.has(cname):
		_tp_fracs_cache[cname] = _load_tp_fracs(cname)
	var fracs: Array = _tp_fracs_cache[cname]
	if fracs.is_empty():
		return
	var all_styles := _load_plume_styles_for(cname)
	for i: int in fracs.size():
		var fd: Dictionary = fracs[i]
		var tp_id: int = int(fd.get("id", i + 1))
		var style: Dictionary = all_styles.get("tp_%d" % tp_id, {})
		var p := _make_plume(fd["frac"] as Vector2, float(fd["dir_angle"]), style)
		add_child(p)
		_plumes.append(p)
	var red := PackedColorArray([
		Color(1.0, 0.20, 0.10, 1.0), Color(0.85, 0.05, 0.02, 1.0),
		Color(0.60, 0.00, 0.00, 0.85), Color(0.40, 0.00, 0.00, 0.00),
	])
	for p2: CPUParticles2D in _plumes:
		_plume_base.append({"vel_min": p2.initial_velocity_min, "vel_max": p2.initial_velocity_max,
			"sc_min": p2.scale_amount_min, "sc_max": p2.scale_amount_max, "life": p2.lifetime})
		_plume_base_cols.append(p2.color_ramp.colors.duplicate())
		_plume_red_cols.append(red)

static func _load_plume_styles_for(cname: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load("res://plume_styles.cfg") != OK:
		return {}
	return cfg.get_value("styles", cname, {})

static func _load_tp_fracs(cname: String) -> Array:
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	var cfg := ConfigFile.new()
	if cfg.load("res://creep_layout.cfg") != OK:
		return []
	var eo: Dictionary = cfg.get_value("creeps", cname, {})
	if eo.is_empty():
		return []
	var eo_pos: Vector2 = eo.get("pos", Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0, 60.0))
	if eo_size.x <= 0.0 or eo_size.y <= 0.0:
		return []
	var tps: Array = cfg.get_value("thrustpoints", cname, [])
	var result: Array = []
	for i: int in tps.size():
		var tp: Dictionary = tps[i]
		var tp_oc: Vector2 = (tp["pos"] as Vector2) + SCREEN_ORIGIN
		var frac := (tp_oc - eo_pos) / eo_size
		result.append({"frac": frac, "dir_angle": float(tp.get("dir_angle", PI * 0.5)), "id": int(tp.get("id", i + 1))})
	return result

func _setup_fire_points() -> void:
	if _icon.is_empty() or _draw_size == Vector2.ZERO:
		return
	var cname := _icon.get_file().get_basename().to_lower()
	if not _fp_fracs_cache.has(cname):
		_fp_fracs_cache[cname] = _load_fp_fracs(cname)
	_fp_fracs = _fp_fracs_cache[cname]

static func _load_fp_fracs(cname: String) -> Array:
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	var cfg := ConfigFile.new()
	if cfg.load("res://creep_layout.cfg") != OK:
		return []
	var eo: Dictionary = cfg.get_value("creeps", cname, {})
	if eo.is_empty():
		return []
	var eo_pos: Vector2  = eo.get("pos",  Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0,  60.0))
	if eo_size.x <= 0.0 or eo_size.y <= 0.0:
		return []
	var fps: Array = cfg.get_value("firepoints", cname, [])
	var result: Array = []
	for i: int in fps.size():
		var fp: Dictionary = fps[i]
		var fp_oc: Vector2 = (fp["pos"] as Vector2) + SCREEN_ORIGIN
		var frac := (fp_oc - eo_pos) / eo_size
		result.append({"frac": frac, "dir_angle": float(fp.get("dir_angle", 0.0)), "id": int(fp.get("id", i + 1))})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return result

## World position of fire-point `idx`. Falls back to global_position if FP not configured.
## Origin of CharacterBody2D is CENTER; frac offset shifted by -0.5 to match.
func _muzzle(idx: int = 0) -> Vector2:
	if idx < _fp_fracs.size() and _draw_size != Vector2.ZERO:
		return global_position + (_fp_fracs[idx]["frac"] as Vector2 - Vector2(0.5, 0.5)) * _draw_size
	return global_position

func _make_plume(frac: Vector2, dir_angle: float, style: Dictionary = {}) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	# Origin of CharacterBody2D is CENTER; _draw_size is the full drawn sprite extent.
	# frac (0,0)=top-left (1,1)=bottom-right → shift by -0.5 to center on origin.
	p.position = (frac - Vector2(0.5, 0.5)) * _draw_size
	p.amount = maxi(1, int(_draw_size.x / 5.0))
	p.lifetime             = float(style.get("lifetime", 0.35))
	p.emitting = true
	p.local_coords = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.z_as_relative = true
	p.z_index = 1
	p.gravity = Vector2.ZERO
	p.direction = Vector2.RIGHT.rotated(dir_angle)
	p.spread               = float(style.get("spread",   12.0))
	p.initial_velocity_min = float(style.get("vel_min",  80.0))
	p.initial_velocity_max = float(style.get("vel_max",  130.0))
	p.scale_amount_min     = float(style.get("sc_min",   1.0))
	p.scale_amount_max     = float(style.get("sc_max",   2.2))
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.05))
	p.scale_amount_curve = taper
	# Store unrotated values so _physics_process can re-apply visual rotation each frame.
	p.set_meta("base_pos", p.position)
	p.set_meta("base_dir", p.direction)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(16, 16) * 0.5
	for iy in 16:
		for ix in 16:
			var d: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / 8.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	p.texture = ImageTexture.create_from_image(img)
	var col_core:  Color = style.get("col_core",  Color(1.0, 0.95, 0.7, 1.0))
	var col_flame: Color = style.get("col_flame", Color(1.0, 0.6,  0.2, 1.0))
	var col_cool:  Color = style.get("col_cool",  Color(0.45, 0.6, 1.0, 0.85))
	var col_fade           := col_cool; col_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	grad.colors  = PackedColorArray([col_core, col_flame, col_cool, col_fade])
	p.color_ramp = grad
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	return p

# ── Dynamic plume modulation ──────────────────────────────────────────────────
func _apply_plume_vel_mult(m: float) -> void:
	for i: int in _plumes.size():
		var b: Dictionary = _plume_base[i]
		_plumes[i].initial_velocity_min = float(b["vel_min"]) * m
		_plumes[i].initial_velocity_max = float(b["vel_max"]) * m

func _apply_plume_full_mult(m: float) -> void:
	for i: int in _plumes.size():
		var p: CPUParticles2D = _plumes[i]
		var b: Dictionary = _plume_base[i]
		p.initial_velocity_min = float(b["vel_min"]) * m
		p.initial_velocity_max = float(b["vel_max"]) * m
		p.scale_amount_min     = float(b["sc_min"])  * m
		p.scale_amount_max     = float(b["sc_max"])  * m
		p.lifetime             = float(b["life"])    * m

func _apply_plume_color(want_red: bool) -> void:
	if want_red == _plume_in_red:
		return
	_plume_in_red = want_red
	var src: Array = _plume_red_cols if want_red else _plume_base_cols
	for i: int in _plumes.size():
		if _plumes[i].color_ramp != null and i < src.size():
			_plumes[i].color_ramp.colors = src[i]

func _update_plumes() -> void:
	if _plume_base.is_empty():
		return
	match behavior:
		"swarm_dive":
			_apply_plume_vel_mult(2.0 if _phase == 1 else 1.0)
		"orbit":
			_apply_plume_color(global_position.distance_to(_player_pos()) < 350.0)
		"jump":
			_apply_plume_full_mult(3.0 if _phase == 1 else 1.0)
		"jump_diag":
			_apply_plume_full_mult(3.0 if _phase == 1 else 1.0)
		"squid":
			_apply_plume_full_mult(2.0 if _phase == 1 else 1.0)   # vel / scale / life ×2 during a leap

# ── Universal damage contract ──────────────────────────────────────────────────
# ── Status effects ─────────────────────────────────────────────────────────────
## Status-duration multiplier from the Lasgun's Capacitor perk (global mech "duration_pct").
func _dur_mult() -> float:
	return 1.0 + (GameManager.mech_bonus("duration_pct") if GameManager.has_method("mech_bonus") else 0.0)

func is_burning() -> bool:
	return _burn_stacks > 0

## Apply burn stack(s): % current-HP DoT per stack for BURN_DURATION (refreshed). No hard stack cap.
func apply_burn(stacks: int = 1) -> void:
	if _dead:
		return
	_burn_stacks += maxi(1, stacks)
	var add: float = GameManager.mech_bonus("burn_dur_add") if GameManager.has_method("mech_bonus") else 0.0
	_burn_t = BURN_DURATION * _dur_mult() + add   # Prolonged Flame / Dragon's Breath burn-duration bonus

## Apply freeze stack(s): each slows FREEZE_SLOW_PER, capped (6 stacks normal / 2 boss), decays after FREEZE_DURATION.
func apply_freeze(stacks: int = 1) -> void:
	if _dead:
		return
	var cap_stacks := 2 if is_in_group("boss") else 6
	_freeze_stacks = mini(_freeze_stacks + maxi(1, stacks), cap_stacks)
	_freeze_t = FREEZE_DURATION * _dur_mult()

## Stun for `duration` s — frozen movement/attacks + +50% damage taken. No-op if already stunned or immune.
func apply_stun(duration: float) -> void:
	if _dead or _stun_t > 0.0 or _stun_immune_t > 0.0:
		return
	_stun_t = duration * _dur_mult()

func is_stunned() -> bool:
	return _stun_t > 0.0

## Dazzling Display capstone: scale this enemy's post-stun immunity (e.g. 0.5 = halved).
func set_stun_immune_mult(m: float) -> void:
	_stun_immune_mult = m

## Pacifying Jolt: halve this enemy's damage output for `duration` s.
func apply_weaken(duration: float) -> void:
	if not _dead:
		_weaken_t = maxf(_weaken_t, duration)

## Multiplier on this enemy's outgoing damage (0.5 while weakened).
func damage_out_mult() -> float:
	return 0.5 if _weaken_t > 0.0 else 1.0

## Orb of Annihilation: this enemy takes +20% damage from all sources for `duration` s (refreshed while in the orb).
func apply_vulnerable(duration: float) -> void:
	if not _dead:
		_vuln_t = maxf(_vuln_t, duration)

## Tick burn DoT + freeze decay; update the movement-slow + a status tint.
func _tick_status(delta: float) -> void:
	if _burn_stacks > 0:
		_burn_t -= delta
		if _burn_t <= 0.0:
			_burn_stacks = 0
			_burn_acc = 0.0
		else:
			_burn_acc += delta
			# Armor Melter (Dragon's Breath evo): heavily-burned enemies (≥10 stacks) take more damage.
			# (Enemies have no real armor stat — modeled as vulnerability; see note.)
			if _burn_stacks >= 10 and GameManager.has_method("mech_bonus") and GameManager.mech_bonus("armor_melt") > 0.0:
				apply_vulnerable(BURN_TICK + 0.2)
			while _burn_acc >= BURN_TICK:
				_burn_acc -= BURN_TICK
				var bmul: float = 1.0 + (GameManager.mech_bonus("burn_dmg") if GameManager.has_method("mech_bonus") else 0.0)
				var dmg := hp * BURN_PCT * float(_burn_stacks) * BURN_TICK * bmul
				if dmg > 0.0:
					take_damage(dmg, 0.0)
					if _dead:
						return
	if _freeze_stacks > 0:
		_freeze_t -= delta
		if _freeze_t <= 0.0:
			_freeze_stacks = 0
	var cap := FREEZE_MAX_BOSS if is_in_group("boss") else FREEZE_MAX
	_move_slow = minf(float(_freeze_stacks) * FREEZE_SLOW_PER, cap)
	# Stun timer → on expiry, grant the post-stun immunity window.
	if _weaken_t > 0.0:
		_weaken_t = maxf(0.0, _weaken_t - delta)
	if _vuln_t > 0.0:
		_vuln_t = maxf(0.0, _vuln_t - delta)
	if _stun_t > 0.0:
		_stun_t -= delta
		if _stun_t <= 0.0:
			_stun_t = 0.0
			var imm := STUN_IMMUNE_BOSS if is_in_group("boss") else STUN_IMMUNE
			# Dazzling Display: a global immunity reduction (0..0.95) on top of any per-enemy mult.
			var reduce: float = GameManager.mech_bonus("stun_immune_reduce") if GameManager.has_method("mech_bonus") else 0.0
			_stun_immune_t = imm * _stun_immune_mult * (1.0 - clampf(reduce, 0.0, 0.95))
	elif _stun_immune_t > 0.0:
		_stun_immune_t = maxf(0.0, _stun_immune_t - delta)
	# Status tint: stun (electric) > freeze (icy) > burn (fiery).
	if _stun_t > 0.0:
		modulate = Color(1.7, 1.7, 0.6)
	elif _freeze_stacks > 0:
		modulate = Color(0.6, 0.8, 1.25)
	elif _burn_stacks > 0:
		modulate = Color(1.3, 0.7, 0.45)
	else:
		modulate = Color.WHITE

func take_damage(amount: float, stagger: float = 0.0, knock: float = 0.0) -> void:
	if _dead:
		return
	if _invincible:
		return   # test dummy — still blocks the beam (it's in "arena_enemy") but never takes damage or dies
	var dr := 0.0
	if GameManager.has_method("armor_damage_reduction"):
		dr = GameManager.armor_damage_reduction(armor)
	if _stun_t > 0.0:
		amount *= STUN_DMG_MULT   # stunned enemies take +50% damage
	if _vuln_t > 0.0:
		amount *= 1.2             # Orb of Annihilation: +20% damage taken
	hp -= amount * (1.0 - dr)
	# Hit reaction: flash (red if this blow kills, else white) + squash pulse + (optional) knockback + stagger.
	_flash_color = KILL_FLASH_COLOR if hp <= 0.0 else HIT_FLASH_COLOR
	_stagger_t = maxf(_stagger_t, stagger)
	_flash = HIT_FLASH_TIME
	_hit_squash = HIT_SQUASH
	# Pushback ONLY when the hitting weapon asks for it (knock > 0). Most weapons no longer push — only the
	# Nuke and Gatling pass knock=1.0.
	if knock > 0.0:
		var away := global_position - _player_pos()
		var momentum: float = GameManager.get_momentum_mult() if GameManager.has_method("get_momentum_mult") else 1.0
		_knockback = (away.normalized() if away.length() > 0.01 else Vector2.UP) * KNOCKBACK_SPEED * knock * momentum
	queue_redraw()
	if hp <= 0.0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	if _squid_attached:
		_squid_detach()   # stop slowing the ship the instant this squid dies
	# Drop a collectible XP orb (the player magnetizes + collects it) instead of granting XP instantly.
	if xp > 0:
		if _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("spawn_xp_orb"):
			_mgr.spawn_xp_orb(global_position, xp)
		elif GameManager.has_method("add_xp"):
			GameManager.add_xp(xp)   # fallback if no manager is wired
	# Explosion VFX + random boom SFX
	_spawn_explosion(maxf(_draw_size.x, _radius * 2.0))
	_play_boom()
	# Start the death pop (a short flourish) instead of freeing immediately; disable collisions meanwhile.
	_dying = true
	_death_t = 0.0
	collision_layer = 0
	collision_mask = 0

func _spawn_explosion(size_px: float) -> void:
	# Baked flipbook blast (scripts/gameplay/arena_death_fx.gd) — a pre-rendered sprite sheet of the composite
	# Explosion, played back ADDITIVE (1 node + 1 draw call). The live composite (~4 particle systems/death)
	# tanked the frame rate when a whole wave died at once; the flipbook looks the same for ~zero cost. It scales
	# itself to the enemy via its own DISPLAY_SCALE, so pass the enemy size straight through.
	var ex: Node2D = DeathFX.new()
	get_parent().add_child(ex)
	ex.call("setup", global_position, size_px)

func _play_boom() -> void:
	var stream := load("res://assets/audio/sfx/boom.wav") as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = sfx_bus
	p.volume_db = linear_to_db(0.7)
	get_parent().add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

## Play a one-shot attack sound (lazily creates the player on first use). Plays once — no loop.
func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	if _sfx == null:
		_sfx = AudioStreamPlayer.new()
		_sfx.bus = sfx_bus
		add_child(_sfx)
	_sfx.stream = stream
	_sfx.play()

func _player_pos() -> Vector2:
	if _target != null and is_instance_valid(_target):
		return _target.global_position
	_target = get_tree().get_first_node_in_group("player")
	return _target.global_position if _target != null else global_position

# ── Squid: orient so the tentacle side faces the player (tentacles lead the approach / wrap on contact). ──
func _face_squid(pp: Vector2, delta: float) -> void:
	var to := pp - global_position
	if to.length() <= 0.5:
		return
	var desired := to.angle() - _tent_front_ang   # rotate body so local front-angle aims at the player
	_facing = lerp_angle(_facing, desired, clampf(TURN_RATE * delta, 0.0, 1.0))

func _squid_attach(pp: Vector2) -> void:
	_squid_attached = true
	_squid_attach_off = global_position - pp
	var max_off := _radius + SQUID_ATTACH_RANGE
	if _squid_attach_off.length() > max_off:
		_squid_attach_off = _squid_attach_off.normalized() * max_off
	z_index = SQUID_WRAP_Z   # draw above the ship so the wrapping tentacles render over the hull
	if not is_in_group("squid_clinging"):
		add_to_group("squid_clinging")   # arena.gd counts this group to slow the ship

func _squid_detach() -> void:
	_squid_attached = false
	z_index = SQUID_BASE_Z   # back below the ship
	_phase = 0; _timer = 0.0   # restart the jump cycle cleanly (wait → leap)
	if is_in_group("squid_clinging"):
		remove_from_group("squid_clinging")

# ── Per-frame ───────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _dying:   # death pop owns the transform; just advance the timer, then free
		_death_t += delta
		queue_redraw()
		if _death_t >= DEATH_POP_TIME:
			queue_free()
		return
	if _dead:
		return
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")
		if _target == null:
			return
	_t += delta
	_spawn_t = minf(_spawn_t + delta, SPAWN_POP_TIME)
	_stagger_t = maxf(0.0, _stagger_t - delta)
	_tick_status(delta)
	if _dead:   # a burn tick may have killed it
		return
	if _base_speed < 0.0:
		_base_speed = speed                      # capture the configured base once
	speed = _base_speed * (1.0 - _move_slow)     # freeze slows all movement (behaviors read `speed`)
	if not _init_done:
		_init_behavior()
		_init_done = true
	if _stagger_t <= 0.0 and _stun_t <= 0.0:   # staggered/stunned → movement & attacks frozen (visuals still play)
		_tick_behavior(delta)
	# Position after intended (pursuit) movement but BEFORE knockback — facing reads from this, so a knockback
	# push only DISPLACES the enemy, it never turns/reorients it.
	var pos_pre_knockback := global_position
	# Knockback recoil (decays).
	if _knockback.length() > 1.0:
		global_position += _knockback * delta
		_knockback = _knockback.lerp(Vector2.ZERO, clampf(KNOCKBACK_DECAY * delta, 0.0, 1.0))
	# Squash/stretch eased from actual speed; hit-squash pulse decays.
	var moved := global_position - _prev_pos
	var spd := moved.length() / maxf(delta, 0.0001)
	var target_squash := SQUASH_MAG * clampf(spd / SQUASH_REF_SPEED, 0.0, 1.0)
	_squash = lerpf(_squash, target_squash, clampf(SQUASH_EASE * delta, 0.0, 1.0))
	_hit_squash = lerpf(_hit_squash, 0.0, clampf(HIT_SQUASH_DECAY * delta, 0.0, 1.0))
	# Face the intended movement direction only — knockback must NOT rotate the enemy (centipede keeps spin).
	var intended := pos_pre_knockback - _prev_pos
	if behavior != "centipede" and behavior != "squid" and intended.length() > 0.5:
		_facing = lerp_angle(_facing, intended.angle() + PI * 0.5, clampf(TURN_RATE * delta, 0.0, 1.0))
	_prev_pos = global_position
	if not _frames.is_empty():
		_anim_acc += delta
		var fd: float = float(_delays[_anim_frame]) if _anim_frame < _delays.size() else 0.1
		if _anim_acc >= fd:
			_anim_acc -= fd
			_anim_frame = (_anim_frame + 1) % _frames.size()
			_tex = _frames[_anim_frame] as Texture2D
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	_check_contact()
	# Sync plume emitters to the visual rotation (draw_set_transform rotates the sprite but not node children).
	_update_plumes()
	if not _plumes.is_empty():
		var vrot := _spin if behavior == "centipede" else _facing
		# Only re-rotate the emitters when the rotation actually moved (skips the per-frame .rotated() churn
		# for the hundreds of near-static swarm enemies that dominate the node count).
		if not _plume_vrot_init or absf(angle_difference(vrot, _plume_vrot_applied)) > 0.01:
			_plume_vrot_init = true
			_plume_vrot_applied = vrot
			for p: CPUParticles2D in _plumes:
				if is_instance_valid(p):
					p.position  = (p.get_meta("base_pos") as Vector2).rotated(vrot)
					p.direction = (p.get_meta("base_dir") as Vector2).rotated(vrot)
	if _has_eye:
		_update_eye(delta)
	if not _tent_template.is_empty():
		_update_tentacle(delta)
	queue_redraw()   # bob/squash/facing animate continuously

## Slide the tracking eye toward the player within its socket. _eye_off is in local (pre-rotation) px,
## relative to the socket center, smoothed so the gaze eases rather than snaps.
func _update_eye(delta: float) -> void:
	if _draw_size == Vector2.ZERO:
		return
	var rot := _spin if behavior == "centipede" else _facing
	var to_world := _player_pos() - global_position
	var target := Vector2.ZERO
	if to_world.length() > 1.0:
		var dir_local := to_world.normalized().rotated(-rot)   # gaze direction in the sprite's local frame
		target = Vector2(dir_local.x * _eye_range.x * _draw_size.x, dir_local.y * _eye_range.y * _draw_size.y)
	_eye_off = _eye_off.lerp(target, clampf(EYE_TRACK_SPEED * delta, 0.0, 1.0))

# ── Tentacles: build the segment template + one instance per [tentaclepoints] entry. ──
func _load_tentacle() -> void:
	_tent_template.clear()
	_tents.clear()
	_tent_init = false
	if _icon.is_empty() or _draw_size == Vector2.ZERO:
		return
	var cfg := ConfigFile.new()
	if cfg.load("res://creep_layout.cfg") != OK or not cfg.has_section("creeps"):
		return
	var body_name := _icon.get_file().get_basename()
	var keys := cfg.get_section_keys("creeps")
	# Resolve the body's actual creep key (case-insensitive — editor keys keep the file's case).
	var body_key := ""
	for k: String in keys:
		if k.to_lower() == body_name.to_lower():
			body_key = k
			break
	if body_key == "":
		return
	var body_eo: Dictionary = cfg.get_value("creeps", body_key, {})
	var body_pos: Vector2  = body_eo.get("pos",  Vector2(480.0, 380.0))
	var body_size: Vector2 = body_eo.get("size", Vector2(60.0, 60.0))
	if body_size.x <= 0.0:
		return
	var body_center := body_pos + body_size * 0.5
	# Config-space → in-game scale, so the tentacle tracks whatever size the body is drawn at.
	var s := _draw_size.x / body_size.x
	# Collect children parented to the body, ordered by name (squid-1, squid-2, … = root → tip).
	var child_keys: Array = []
	for k: String in keys:
		var eo: Dictionary = cfg.get_value("creeps", k, {})
		if String(eo.get("parent", "")).to_lower() == body_key.to_lower():
			child_keys.append(k)
	if child_keys.is_empty():
		return
	child_keys.sort()
	# ── Template: per-segment rest angle (body-local 0° frame) + gap, relative to the anchor (seg 0). ──
	var anchor_center := Vector2.ZERO
	var prev_center := Vector2.ZERO
	for i: int in child_keys.size():
		var eo: Dictionary = cfg.get_value("creeps", child_keys[i], {})
		var seg_path := String(eo.get("path", ""))
		var seg_src := _resolve_sprite(seg_path)   # HD segment if available
		var tex := load(seg_src) as Texture2D
		if tex == null and seg_src != seg_path:
			tex = load(seg_path) as Texture2D       # HD failed → standard segment
		if tex == null:
			continue
		var pos: Vector2 = eo.get("pos",  body_pos)
		var sz: Vector2  = eo.get("size", Vector2(10.0, 10.0))
		var center := pos + sz * 0.5
		var gap := 0.0
		var rest_ang := 0.0
		if _tent_template.is_empty():
			anchor_center = center   # seg 0 is the anchor
		else:
			var d := center - prev_center
			gap = maxf(d.length() * s, 0.5)
			rest_ang = d.angle()    # joint direction in the body-local frame (template's 0°)
		_tent_template.append({"tex": tex, "size": sz * s, "gap": gap, "rest_ang": rest_ang})
		prev_center = center
	if _tent_template.is_empty():
		return
	# ── Instances: one per tentacle point; fall back to the template's native placement if none. ──
	var tps: Array = cfg.get_value("tentaclepoints", body_key, [])
	const SS_ORIGIN := Vector2(15.0, 8.0)
	if not tps.is_empty():
		for ti: int in tps.size():
			var tn: Dictionary = tps[ti]
			var tn_oc: Vector2 = (tn.get("pos", Vector2.ZERO) as Vector2) + SS_ORIGIN
			_tents.append({
				"base_off": (tn_oc - body_center) * s,
				"dir":      float(tn.get("dir_angle", 0.0)),
				"phase":    randf() * TAU,
				"wrap":     1.0 if ti % 2 == 0 else -1.0,   # alternate curl direction → tentacles grasp from both sides
				"pts":      [],
			})
	else:
		_tents.append({
			"base_off": (anchor_center - body_center) * s,   # native single tentacle at the placed anchor
			"dir":      0.0,
			"phase":    randf() * TAU,
			"wrap":     1.0,
			"pts":      [],
		})
	# Local angle of the tentacle side (centroid of the instance anchors) — the squid aims this at the player.
	var sum := Vector2.ZERO
	for inst: Dictionary in _tents:
		sum += inst["base_off"] as Vector2
	if not _tents.is_empty():
		sum /= float(_tents.size())
	_tent_front_ang = sum.angle() if sum.length() > 0.5 else 0.0

# ── Tentacles: forward kinematics per instance. Root pinned; joint = rest angle + traveling wave + drag. ──
func _update_tentacle(delta: float) -> void:
	if _tent_template.is_empty() or _tents.is_empty():
		return
	var n := _tent_template.size()
	var rot := _facing
	if not _tent_init:
		_tent_prev_pos = global_position
		_tent_vel = Vector2.ZERO
		_tent_phase = 0.0
		_tent_init = true
	_tent_phase += delta
	# Smoothed body velocity drives the trailing drag (computed here — _prev_pos was already updated upstream).
	var vel := (global_position - _tent_prev_pos) / maxf(delta, 0.0001)
	_tent_prev_pos = global_position
	_tent_vel = _tent_vel.lerp(vel, clampf(8.0 * delta, 0.0, 1.0))
	var speed := _tent_vel.length()
	var drag_strength := TENT_DRAG_GAIN * clampf(speed / TENT_DRAG_REF, 0.0, 1.0)
	var trail_ang := (-_tent_vel).angle() if speed > 1.0 else 0.0
	# Wrap blend: when the squid is clinging, the tentacles curl around the ship instead of trailing.
	var wrapping := behavior == "squid" and _squid_attached
	_tent_attach = lerpf(_tent_attach, 1.0 if wrapping else 0.0, clampf(4.0 * delta, 0.0, 1.0))
	var ship := _player_pos() if _tent_attach > 0.001 else Vector2.ZERO
	for inst: Dictionary in _tents:
		var pts: Array = inst["pts"]
		if pts.size() != n:
			pts.resize(n)
			inst["pts"] = pts
		var base_rot: float = rot + float(inst["dir"])   # whole chain rotates by the point's Dir
		var inst_phase: float = float(inst["phase"])
		var wrap_sign: float = float(inst.get("wrap", 1.0))
		# Root segment — rigidly anchored at the point's body-relative position (rotates with facing).
		pts[0] = global_position + (inst["base_off"] as Vector2).rotated(rot)
		for k in range(1, n):
			var base_a: float = float(_tent_template[k]["rest_ang"]) + base_rot
			var taper := 0.3 + 0.7 * float(k) / float(n - 1)   # root stiff, tip floppy
			var wave := TENT_WAVE_AMP * taper * sin(_tent_phase * TENT_WAVE_FREQ + inst_phase - float(k) * TENT_WAVE_K)
			var drag := angle_difference(base_a, trail_ang) * drag_strength * taper if speed > 1.0 else 0.0
			var a := base_a + (wave + drag) * (1.0 - 0.7 * _tent_attach)
			if _tent_attach > 0.001:
				# Curl around the ship: head tangentially around it (perpendicular to the radius), biased
				# slightly inward so the tentacle hugs the hull rather than orbiting at a fixed distance.
				var r := ship - (pts[k - 1] as Vector2)
				var wrap_a := r.angle() + wrap_sign * (PI * 0.5 - 0.35)
				a = lerp_angle(a, wrap_a, _tent_attach * taper)
			pts[k] = (pts[k - 1] as Vector2) + Vector2(cos(a), sin(a)) * float(_tent_template[k]["gap"])

# ── Tentacles: draw every instance, tip → root, so the root paints last (just under the body). ──
func _draw_tentacle(alpha: float) -> void:
	var n := _tent_template.size()
	if n == 0:
		return
	for inst: Dictionary in _tents:
		var pts: Array = inst["pts"]
		if pts.size() < n:
			continue
		for idx in range(n - 1, -1, -1):
			var seg: Dictionary = _tent_template[idx]
			var tex: Texture2D = seg["tex"]
			var sz: Vector2 = seg["size"]
			var p: Vector2 = pts[idx]
			# Tangent along the tentacle, root → tip (sprite's +x axis points outward toward the tip).
			var ang: float
			if n == 1:
				ang = (p - global_position).angle()
			elif idx == 0:
				ang = ((pts[1] as Vector2) - p).angle()
			elif idx == n - 1:
				ang = (p - (pts[idx - 1] as Vector2)).angle()
			else:
				ang = ((pts[idx + 1] as Vector2) - (pts[idx - 1] as Vector2)).angle()
			draw_set_transform(p - global_position, ang, Vector2.ONE)
			draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _init_behavior() -> void:
	var to := _player_pos() - global_position
	_aim = to.normalized() if to.length() > 0.01 else Vector2.UP
	match behavior:
		"orbit", "spiral":
			_orbit_r = global_position.distance_to(_player_pos())
			_orbit_ang = (global_position - _player_pos()).angle()
			_spiral_dir = 1.0   # always clockwise (Y-down screen → increasing angle = clockwise)
			_scatter_target = _player_pos()   # spiral: orbit center anchor; drifts toward player each frame
		"scatter", "bomber":
			_scatter_target = _player_pos() + _rand_offset(_view().length() * 0.35)
		"jump_diag":
			_jump_interval = randf_range(0.5, 1.5)

func _tick_behavior(delta: float) -> void:
	var pp := _player_pos()
	var to := pp - global_position
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector2.UP
	match behavior:
		"chase", "boss_stub":
			velocity = dir * speed
			move_and_slide()
		"swarm":   # blob unit: ZOOM straight through the player @400 (then despawn), or CHASE slowly @speed
			if _swarm_mode == "zoom":
				velocity = _aim * SWARM_ZOOM_SPEED
				move_and_slide()
				if dist > SWARM_ZOOM_CULL:
					queue_free()   # flew off the far side — vanish (no XP/explosion; it wasn't killed)
			else:
				velocity = dir * speed
				move_and_slide()
		"centipede":
			_spin += TAU / 3.0 * delta
			velocity = dir * speed
			move_and_slide()
			queue_redraw()
		"dash":   # dive along the captured aim; once it flies off-view, re-aim and dive back
			if dist > RETURN_DIST:
				_aim = dir
			velocity = _aim * speed
			move_and_slide()
		"spiral":   # diver — spiral in; center drifts (not snaps) toward player → player can pull away
			if _phase == 0:
				_scatter_target = _scatter_target.move_toward(pp, SPIRAL_CENTER_SPEED * delta)
				var ang_speed := (speed / maxf(40.0, _orbit_r)) * _spiral_dir
				_orbit_ang += ang_speed * delta
				_orbit_r = maxf(8.0, _orbit_r - SPIRAL_SHRINK * delta)
				global_position = _scatter_target + Vector2(cos(_orbit_ang), sin(_orbit_ang)) * _orbit_r
				if _orbit_r <= 8.0:
					_phase = 1
					_aim = dir   # aim-once at the moment of committing to the dash
			else:   # dash: fly straight at the captured aim; re-aim only if it overshoots far off-screen
				if dist > RETURN_DIST:
					_aim = dir
				velocity = _aim * speed
				move_and_slide()
		"orbit":  # dragonfly — orbit + tighten, then dive (loops back when it overshoots off-view)
			if _phase == 0:
				_orbit_ang += (speed / maxf(20.0, _orbit_r)) * delta
				_orbit_r = maxf(28.0, _orbit_r - 28.0 * delta)
				global_position = pp + Vector2(cos(_orbit_ang), sin(_orbit_ang)) * _orbit_r
				if _orbit_r <= 32.0:
					_phase = 1
					_aim = dir
			else:
				if dist > RETURN_DIST:
					_aim = dir
				velocity = _aim * (speed * 1.7)
				move_and_slide()
		"jump":   # octopus — wait, then leap toward the player, repeat
			_jump_tick(delta, dir, false)
		"jump_diag":   # spider — leap along the nearest 45° diagonal
			_jump_tick(delta, dir, true)
		"scatter":   # fly — wander to random points around the player
			if global_position.distance_to(_scatter_target) < 24.0 or _t - _timer > 1.0:
				_scatter_target = pp + _rand_offset(_view().length() * 0.35)
				_timer = _t
			velocity = (_scatter_target - global_position).normalized() * speed
			move_and_slide()
		"swarm_dive":   # bee/bug/swarm — drift toward the player, pause, then dive through
			if _phase == 0:
				if _t < 1.2:
					velocity = dir * speed * 0.6
					move_and_slide()
				else:
					_phase = 1
					_aim = dir
			else:
				if dist > RETURN_DIST:
					_aim = dir
				velocity = _aim * speed * 1.6
				move_and_slide()
		"shooter":   # burst of 1 shot per FP (up to 4), 0.2s between shots, 1s between bursts
			_standoff(dist, dir, 340.0)
			var sh_total := maxi(1, _fp_fracs.size())
			if _burst_shots == 0 and _fire_ready(1.0):
				_burst_shots = sh_total
				_burst_t = 0.0
				_play_sfx(SFX_ZAP)
			if _burst_shots > 0:
				_burst_t -= delta
				if _burst_t <= 0.0:
					var fp_idx := sh_total - _burst_shots
					_mgr.spawn_bullet(_muzzle(fp_idx), dir * 280.0, 5)
					_burst_shots -= 1
					if _burst_shots > 0:
						_burst_t = 0.2
		"sentinel":   # hold, fire a fan TOWARD the player from FP 0
			_standoff(dist, dir, 420.0)
			if _fire_ready(2.0):
				_play_sfx(SFX_ZAP)
				var muzzle := _muzzle(0)
				var base := dir.angle()
				for k in 5:
					var a := base + deg_to_rad(lerpf(-24.0, 24.0, float(k) / 4.0))
					_mgr.spawn_bullet(muzzle, Vector2(cos(a), sin(a)) * 260.0, 5)
		"beamer":
			_standoff(dist, dir, 380.0)
			_beamer_tick(delta, dir)
		"bomber":   # bombing-wanderer — roam near the player, drop bombs from FP 0
			if global_position.distance_to(_scatter_target) < 30.0 or _t - _timer > 1.5:
				_scatter_target = pp + _rand_offset(260.0)
				_timer = _t
			velocity = (_scatter_target - global_position).normalized() * speed
			move_and_slide()
			if _fire_ready(3.0) and _mgr != null and _mgr.has_method("throw_bomb"):
				_mgr.throw_bomb(_muzzle(0))
		"missile":   # launcher — fan BEHIND launcher → hover → boomerang at player
			_standoff(dist, dir, 460.0)
			if _fire_ready(2.5) and (_missile_volley == null or not is_instance_valid(_missile_volley)):
				var ml_total := maxi(1, _fp_fracs.size())
				var muzzles: Array = []
				for k in ml_total:
					muzzles.append(_muzzle(k))
				var vol := _MissileVolley.new()
				if _mgr != null and is_instance_valid(_mgr):
					_mgr.add_child(vol)
				else:
					get_parent().add_child(vol)
				vol.global_position = Vector2.ZERO
				vol.launch(muzzles, -dir, self)
				_missile_volley = vol
		"bomb":   # falls toward the player; explodes on contact/death
			velocity = dir * speed
			move_and_slide()
		"thrown_bomb":   # fast straight projectile aimed at the player; explodes on contact, fizzles at range
			velocity = _aim * speed
			move_and_slide()
			_orbit_r += speed * delta
			if _orbit_r >= THROWN_BOMB_RANGE:
				_die()
		"dummy":
			pass

## Octopus/spider shared leap engine.
func _jump_tick(delta: float, dir: Vector2, diagonal: bool) -> void:
	var interval := _jump_interval if diagonal else 1.0
	if _phase == 0:   # wait, then aim
		_timer += delta
		if _timer >= interval:
			_timer = 0.0
			_phase = 1
			_play_sfx(SFX_SPIDER_JUMP if diagonal else SFX_OCTOPUS_JUMP)
			if diagonal:
				_jump_interval = randf_range(0.5, 1.5)   # randomize next wait
			var d := dir
			if diagonal:
				var a := (roundf(dir.angle() / (PI * 0.5) - 0.5) + 0.5) * (PI * 0.5)
				d = Vector2(cos(a), sin(a))
			_aim = d
			_orbit_r = 0.0   # reuse as jump-distance accumulator
	else:   # leap
		var step := speed * 2.2 * delta
		global_position += _aim * step
		_orbit_r += step
		if _orbit_r >= 200.0:
			_phase = 0

## Move to a standoff ring around the player (used by ranged enemies).
func _standoff(dist: float, dir: Vector2, want: float) -> void:
	if dist > want + 40.0:
		velocity = dir * speed
	elif dist < want - 40.0:
		velocity = -dir * speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

func _fire_ready(interval: float) -> bool:
	if _t - _fire_t >= interval:
		_fire_t = _t
		return true
	return false

func _beamer_tick(delta: float, dir: Vector2) -> void:
	# IDLE 0.6 → CHARGE 1.0 → FIRE 3.0 → COOLDOWN 1.5, beam aimed at the player when it starts.
	_timer += delta
	match _phase:
		0:
			_beam_on = false
			if _timer >= 0.6:
				_phase = 1
				_timer = 0.0
		1:
			if _timer >= 1.0:
				_phase = 2
				_timer = 0.0
				_beam_dir = dir
				_beam_origin = _muzzle(0) - global_position   # local offset to FP
				_beam_on = true
				_play_sfx(SFX_BEAM)
		2:
			if _timer >= 3.0:
				_phase = 3
				_timer = 0.0
				_beam_on = false
			else:
				var beam_world := global_position + _beam_origin
				var pp := _player_pos()
				var proj := (pp - beam_world).dot(_beam_dir)
				if proj > 0.0:
					var closest := beam_world + _beam_dir * proj
					if closest.distance_to(pp) <= 30.0 and fmod(_timer, 0.5) < delta:
						GameManager.ship_take_damage(int(round(5.0 * damage_out_mult())))
		3:
			if _timer >= 1.5:
				_phase = 0
				_timer = 0.0
	queue_redraw()

func _view() -> Vector2:
	if _mgr != null and _mgr.has_method("screen_size"):
		return _mgr.screen_size()
	return Vector2(1440, 780)

func _rand_offset(r: float) -> Vector2:
	var a := randf() * TAU
	return Vector2(cos(a), sin(a)) * randf_range(r * 0.4, r)

func _exit_tree() -> void:
	if _missile_volley != null and is_instance_valid(_missile_volley):
		_missile_volley.queue_free()
	_missile_volley = null

# ── Contact ─────────────────────────────────────────────────────────────────────
func _check_contact() -> void:
	if _ship_contact_cd > 0.0:
		_ship_contact_cd -= get_physics_process_delta_time()
	var ship_cd: float = GameManager.ship_contact_damage() if GameManager.has_method("ship_contact_damage") else 0.0
	if contact_damage <= 0 and not contact_explodes and ship_cd <= 0.0:
		return
	if global_position.distance_to(_player_pos()) <= 16.0 + _radius:
		if contact_damage > 0:
			GameManager.ship_take_damage(int(round(contact_damage * damage_out_mult())))
		if ship_cd > 0.0 and _ship_contact_cd <= 0.0:
			take_damage(ship_cd, 0.0)        # ship hits back (Orbital pool: ship contact damage × Contact Mastery)
			_ship_contact_cd = 0.5           # at most every 0.5s per enemy
		if contact_explodes:
			_on_contact_death()

func _on_contact_death() -> void:
	if (behavior == "bomb" or behavior == "thrown_bomb") and _mgr != null and _mgr.has_method("explode"):
		_mgr.explode(global_position, 100.0, 20, self)
	_die()

# ── Draw: composes idle bob + squash/stretch + facing + spawn/death pop + flash, around the sprite/shape;
# the HP bar and beam are drawn AFTER resetting the transform so they stay level & unscaled. ────────────
func _draw() -> void:
	# Uniform scale: per-enemy base variance × idle bob × spawn/death pop.
	var bob := 1.0 + sin(_t * _bob_freq + _bob_phase) * BOB_AMOUNT
	var alpha := 1.0
	var pop := 1.0
	if _dying:
		var df := clampf(_death_t / DEATH_POP_TIME, 0.0, 1.0)
		pop = 1.0 + 0.6 * df          # scale up
		alpha = 1.0 - df              # fade out
		bob = 1.0                     # death owns scale; freeze breathing
	elif _spawn_t < SPAWN_POP_TIME:
		var sf := clampf(_spawn_t / SPAWN_POP_TIME, 0.0, 1.0)
		pop = _ease_out_back(sf)      # 0 → 1 with slight overshoot
		alpha = sf                    # fade in
	var uniform := _scale_var * bob * pop
	# Squash/stretch along the head axis (local Y); thin across (local X). Frozen during death.
	var sq := 0.0 if _dying else (_squash + _hit_squash)
	var scale_vec := Vector2(uniform * (1.0 - sq * 0.5), uniform * (1.0 + sq))
	var rot := _spin if behavior == "centipede" else _facing

	# Drive the flash shader (whitens/reddens the actual sprite pixels — modulate alone can't).
	var flash_s := clampf(_flash / HIT_FLASH_TIME, 0.0, 1.0)
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("flash", flash_s)
		mat.set_shader_parameter("flash_color", _flash_color)
	# Tentacles first (world-space chains) so they sit behind the body sprite; root paints last → just under body.
	if not _tent_template.is_empty():
		_draw_tentacle(alpha)
	draw_set_transform(Vector2.ZERO, rot, scale_vec)
	if _tex != null:
		draw_texture_rect(_tex, Rect2(-_draw_size * 0.5, _draw_size), false, Color(1, 1, 1, alpha))
		# Tracking eye: drawn in the same rotated/scaled frame so it sits in the socket and slides toward the player.
		if _has_eye and _eye_tex != null:
			var socket := (_eye_socket - Vector2(0.5, 0.5)) * _draw_size
			var eye_sz := _eye_size_frac * _draw_size
			var eye_center := socket + _eye_off
			draw_texture_rect(_eye_tex, Rect2(eye_center - eye_sz * 0.5, eye_sz), false, Color(1, 1, 1, alpha))
	else:
		var col := _color
		col.a *= alpha
		_draw_shape(_radius, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)   # back to level/unscaled for beam + HP bar

	if _beam_on:
		var bstart := _beam_origin   # local offset from enemy center to muzzle
		var bend := bstart + _beam_dir * 2000.0
		draw_line(bstart, bend, Color(1.0, 0.3, 0.3, 0.85), 8.0)
		draw_line(bstart, bend, Color(1.0, 1.0, 1.0, 0.9), 3.0)
	if hp < hp_max and not _dying:
		var ratio := clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
		var w := _radius * 2.0
		draw_rect(Rect2(-_radius, -_radius - 8.0, w, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-_radius, -_radius - 8.0, w * ratio, 3.0), Color(0.4, 0.95, 0.4))

## Ease-out-back: 0→1 with a slight overshoot past 1 before settling (spawn pop).
func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var f := x - 1.0
	return 1.0 + c3 * f * f * f + c1 * f * f

func _draw_shape(r: float, col: Color) -> void:
	var pts: PackedVector2Array
	match shape_kind:
		"triangle":
			pts = PackedVector2Array([Vector2(0, -r), Vector2(-r * 0.87, r * 0.6), Vector2(r * 0.87, r * 0.6)])
		"square":
			draw_rect(Rect2(Vector2(-r, -r) * 0.8, Vector2(r, r) * 1.6), col)
			return
		"circle":
			draw_circle(Vector2.ZERO, r, col)
			return
		_:   # diamond
			pts = PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
	draw_colored_polygon(pts, col)   # rotation/scale applied by the caller's draw_set_transform

# ── Missile launcher plasma volley ────────────────────────────────────────────
## Owns N plasma darts through the boomerang arc: fan-out BEHIND the launcher →
## decelerate to hover (telegraph) → stagger-return at player with homing acceleration.
## Parented to the arena enemy manager at world origin so draw coords = world coords.
class _MissileVolley extends Node2D:
	const ML_FAN_ANGLE     := 80.0
	const ML_OUT_SPEED     := 750.0
	const ML_DRAG          := 0.06
	const ML_HOVER_END     := 1.0
	const ML_STAGGER       := 0.5
	const ML_RETURN_START  := 40.0
	const ML_RETURN_ACCEL  := 900.0
	const ML_ACCEL_RAMP    := 9.0
	const ML_RETURN_MAX    := 800.0
	const ML_TURN_EARLY    := 10.0
	const ML_TURN_LATE     := 3.0
	const ML_TURN_SWITCH_T := 0.5
	const ML_LINE_DMG      := 8
	const ML_HIT_R         := 6.0
	const ML_LIFETIME      := 6.0
	const ML_TRAIL_LEN     := 40
	const ML_GLOW_INTENSITY := 1.0
	const ML_COL_HEAD      := Color(0.55, 0.85, 1.0)
	const ML_COL_TAIL      := Color(0.62, 0.30, 1.0)
	const ML_CORE_SIZE     := 9.0
	const ML_CORE_BRIGHT   := 1.0
	const ML_BLOOM_SIZE    := 32.0
	const ML_BLOOM_ALPHA   := 0.5
	const ML_TAIL_MIN      := 28.0
	const ML_TAIL_MAX      := 180.0
	const ML_FULL_SPEED    := 700.0
	const ML_TAIL_SAMPLES  := 30
	const ML_TAIL_W_HEAD   := 24.0
	const ML_TAIL_W_TAIL   := 2.0
	const ML_SPINE_FRAC    := 0.32
	const ML_SPINE_ALPHA   := 0.7
	const ML_HAZE_ALPHA    := 0.30
	const ML_HAZE_WISP     := 5.0
	const ML_FLARE_ON      := true
	const ML_FLARE_SCALE   := 1.0
	const ML_FLARE_LONG    := 80.0
	const ML_FLARE_SHORT   := 30.0
	const ML_FLARE_THIN    := 6.0
	const ML_FLARE_ALPHA   := 0.5
	const ML_DUST_ON       := true
	const ML_DUST_GAP      := 11.0
	const ML_DUST_TTL      := 0.7
	const ML_DUST_SIZE     := 5.0
	const ML_DUST_SPREAD   := 6.0
	const ML_GLITTER_SPEED := 20.0

	var _lines: Array = []
	var _dust:  Array = []
	var _clock: float = 0.0
	var _soft: Texture2D = null
	var _launcher: Node = null   # excluded from dart–enemy collision checks (self-hit guard)

	func launch(muzzles: Array, away: Vector2, launcher: Node = null) -> void:
		_launcher = launcher
		z_index = 4
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		_soft = _make_soft_tex()
		var base_ang := away.angle()
		var count: int = maxi(1, muzzles.size())
		for i in count:
			var frac: float = 0.0 if count <= 1 else float(i) / float(count - 1)
			var ang := base_ang + deg_to_rad(ML_FAN_ANGLE) * (frac - 0.5)
			var dir := Vector2(cos(ang), sin(ang))
			var dart_pos: Vector2 = muzzles[i] if i < muzzles.size() else Vector2.ZERO
			_lines.append({
				"pos": dart_pos, "vel": dir * ML_OUT_SPEED,
				"t": 0.0, "life": 0.0,
				"return_at": ML_HOVER_END + float(i) * ML_STAGGER,
				"returning": false, "speed": 0.0, "seek_t": 0.0,
				"trail": [dart_pos] as Array,
				"dust_acc": 0.0, "phase": randf() * TAU,
			})

	func _process(delta: float) -> void:
		_clock += delta
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			queue_redraw()
			return
		var ship_c: Vector2 = player.global_position
		var ship_r: float   = 16.0
		var i := _lines.size() - 1
		while i >= 0:
			var ln: Dictionary = _lines[i]
			ln["t"]    = float(ln["t"])    + delta
			ln["life"] = float(ln["life"]) + delta
			var prev: Vector2 = ln["pos"]
			if not bool(ln["returning"]):
				_tick_out(ln, delta)
				if float(ln["t"]) >= float(ln["return_at"]):
					_begin_return(ln, ship_c)
			else:
				_tick_return(ln, delta, ship_c)
			var trail: Array = ln["trail"]
			trail.push_front(ln["pos"])
			if trail.size() > ML_TRAIL_LEN:
				trail.resize(ML_TRAIL_LEN)
			_shed_dust(ln, prev)
			var p: Vector2 = ln["pos"]
			var removed := false
			if p.distance_to(ship_c) <= ship_r + ML_HIT_R:
				GameManager.ship_take_damage(ML_LINE_DMG)
				_lines.remove_at(i)
				removed = true
			if not removed:
				for en: Node in get_tree().get_nodes_in_group("arena_enemy"):
					if not is_instance_valid(en) or en == _launcher:
						continue
					var en2 := en as Node2D
					var er: float = en.get("_radius") if en.get("_radius") != null else 16.0
					if p.distance_to(en2.global_position) <= er + ML_HIT_R:
						if en.has_method("take_damage"):
							en.call("take_damage", float(ML_LINE_DMG), 0.0)
						_lines.remove_at(i)
						removed = true
						break
			if not removed and float(ln["life"]) >= ML_LIFETIME:
				_lines.remove_at(i)
			i -= 1
		_tick_dust(delta)
		queue_redraw()
		if _lines.is_empty() and _dust.is_empty():
			queue_free()

	func _tick_out(ln: Dictionary, delta: float) -> void:
		ln["vel"] = (ln["vel"] as Vector2) * pow(ML_DRAG, delta)
		ln["pos"] = (ln["pos"] as Vector2) + (ln["vel"] as Vector2) * delta

	func _begin_return(ln: Dictionary, ship_c: Vector2) -> void:
		# Point TOWARD the player from the start — vel starts near-zero after drag,
		# so preserving current direction would keep the dart flying away forever.
		var toward := (ship_c - (ln["pos"] as Vector2)).normalized()
		if toward.length() < 0.01:
			toward = Vector2.DOWN
		ln["returning"] = true
		ln["speed"]     = ML_RETURN_START
		ln["seek_t"]    = 0.0
		ln["vel"]       = toward * ML_RETURN_START

	func _tick_return(ln: Dictionary, delta: float, ship_c: Vector2) -> void:
		ln["seek_t"] = float(ln["seek_t"]) + delta
		var accel := ML_RETURN_ACCEL * (1.0 + ML_ACCEL_RAMP * float(ln["seek_t"]))
		ln["speed"]  = minf(ML_RETURN_MAX, float(ln["speed"]) + accel * delta)
		var spd: float = ln["speed"]
		var cur: Vector2 = ln["vel"]
		var desired := (ship_c - (ln["pos"] as Vector2)).normalized() * spd
		var turn: float = ML_TURN_EARLY if float(ln["seek_t"]) < ML_TURN_SWITCH_T else ML_TURN_LATE
		var steer := cur.lerp(desired, clampf(turn * delta, 0.0, 1.0))
		if steer.length() > 0.01:
			ln["vel"] = steer.normalized() * spd
		ln["pos"] = (ln["pos"] as Vector2) + (ln["vel"] as Vector2) * delta

	func _shed_dust(ln: Dictionary, prev: Vector2) -> void:
		if not ML_DUST_ON:
			return
		var p: Vector2 = ln["pos"]
		var seg := p - prev
		var moved := seg.length()
		if moved < 0.01:
			return
		var acc := float(ln["dust_acc"]) + moved
		var d := seg / moved
		var perp := Vector2(-d.y, d.x)
		while acc >= ML_DUST_GAP:
			acc -= ML_DUST_GAP
			var along := prev + d * (moved - acc)
			_dust.append({
				"pos":   along + perp * randf_range(-ML_DUST_SPREAD, ML_DUST_SPREAD),
				"life":  0.0,
				"ttl":   ML_DUST_TTL * randf_range(0.7, 1.2),
				"size":  ML_DUST_SIZE * randf_range(0.6, 1.2),
				"hue":   randf(),
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

	func _draw() -> void:
		_draw_dust()
		for ln: Dictionary in _lines:
			_draw_comet(ln["pos"], _dart_dir(ln["vel"], ln["trail"]),
				(ln["vel"] as Vector2).length(), float(ln["phase"]), ln["trail"])

	func _dart_dir(v: Vector2, trail: Array) -> Vector2:
		if v.length() > 1.0:
			return v.normalized()
		if trail.size() >= 2:
			var diff: Vector2 = (trail[0] as Vector2) - (trail[1] as Vector2)
			if diff.length() > 0.01:
				return diff.normalized()
		return Vector2.UP

	func _tail_samples(trail: Array, tail_len: float, n: int) -> Array:
		var out: Array = []
		if trail.is_empty() or tail_len <= 0.0 or n < 2:
			return out
		var step := tail_len / float(n - 1)
		out.append(trail[0])
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

	func _draw_comet(p: Vector2, d: Vector2, speed: float, phase: float, trail: Array) -> void:
		var tail_len := lerpf(ML_TAIL_MIN, ML_TAIL_MAX, clampf(speed / ML_FULL_SPEED, 0.0, 1.0))
		var pts := _tail_samples(trail, tail_len, ML_TAIL_SAMPLES)
		var perp := Vector2(-d.y, d.x)
		for k in range(pts.size() - 1, -1, -1):
			var f := float(k) / float(ML_TAIL_SAMPLES - 1)
			var fade := 1.0 - f
			var col := ML_COL_HEAD.lerp(ML_COL_TAIL, f)
			var body_w := lerpf(ML_TAIL_W_HEAD, ML_TAIL_W_TAIL, f)
			var bp: Vector2 = pts[k]
			var wob := sin(f * 9.0 + phase + _clock * 2.0) * ML_HAZE_WISP * f
			_blob(bp + perp * wob, Vector2(body_w * 2.0, body_w * 2.0), 0.0, _ca(col, ML_HAZE_ALPHA * fade))
			var sc := col.lerp(Color(1.0, 1.0, 1.0, 1.0), fade * 0.6)
			_blob(bp, Vector2(body_w * ML_SPINE_FRAC * 2.0, body_w * ML_SPINE_FRAC * 2.0), 0.0, _ca(sc, ML_SPINE_ALPHA * fade))
		_blob(p, Vector2(ML_BLOOM_SIZE * 2.0, ML_BLOOM_SIZE * 2.0), 0.0, _ca(ML_COL_HEAD, ML_BLOOM_ALPHA * 0.5))
		_blob(p, Vector2(ML_BLOOM_SIZE * 1.1, ML_BLOOM_SIZE * 1.1), 0.0, _ca(Color(0.8, 0.93, 1.0), ML_BLOOM_ALPHA))
		_blob(p, Vector2(ML_CORE_SIZE * 2.0,  ML_CORE_SIZE * 2.0),  0.0, _ca(Color(1.0, 1.0, 1.0), ML_CORE_BRIGHT))
		if ML_FLARE_ON:
			var ang := d.angle()
			var tw := 0.6 + 0.4 * sin(_clock * ML_GLITTER_SPEED + phase)
			var fcol := _ca(Color(0.85, 0.95, 1.0), ML_FLARE_ALPHA * tw)
			_blob(p, Vector2(ML_FLARE_LONG * ML_FLARE_SCALE,        ML_FLARE_THIN * ML_FLARE_SCALE),        ang,              fcol)
			_blob(p, Vector2(ML_FLARE_SHORT * ML_FLARE_SCALE, ML_FLARE_THIN * 0.8 * ML_FLARE_SCALE), ang + PI * 0.5, fcol)

	func _draw_dust() -> void:
		for m: Dictionary in _dust:
			var fade := 1.0 - clampf(float(m["life"]) / maxf(0.01, float(m["ttl"])), 0.0, 1.0)
			var tw   := 0.25 + 0.75 * (0.5 + 0.5 * sin(_clock * ML_GLITTER_SPEED + float(m["phase"])))
			var col  := ML_COL_HEAD.lerp(Color(1.0, 1.0, 1.0, 1.0), float(m["hue"]))
			var a    := fade * tw
			var sz: float = float(m["size"])
			_blob(m["pos"], Vector2(sz * 2.2, sz * 2.2), 0.0, Color(col.r, col.g, col.b, 0.22 * a))
			_blob(m["pos"], Vector2(sz * 0.9,  sz * 0.9),  0.0, Color(1.0, 1.0, 1.0,     0.80 * a))

	func _ca(c: Color, a: float) -> Color:
		return Color(c.r, c.g, c.b, clampf(a * ML_GLOW_INTENSITY, 0.0, 1.0))

	func _blob(pos: Vector2, sizev: Vector2, rot: float, col: Color) -> void:
		if _soft == null:
			return
		draw_set_transform(pos, rot, Vector2.ONE)
		draw_texture_rect(_soft, Rect2(-sizev * 0.5, sizev), false, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _make_soft_tex() -> Texture2D:
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var c := float(s - 1) * 0.5
		for y in s:
			for x in s:
				var dx := (float(x) - c) / c
				var dy := (float(y) - c) / c
				var a := pow(clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0), 2.4)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		return ImageTexture.create_from_image(img)
