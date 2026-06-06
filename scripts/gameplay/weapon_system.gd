extends Control

## Phase 5 — equipped-weapon behaviour + visual effects.
##
## Lives INSIDE StreamScreen, so its local coordinates match the asteroid layer
## (get_asteroid_centers) and the mouse (get_local_mouse_position).
##
## Reads what's equipped from InventoryManager each frame:
##   Primary slot  → left-click fires toward the cursor.
##       fire_mode "repeat" (Gatling): hold to fire every cooldown_sec.
##       fire_mode "charge" (Gauss):   hold to charge up to cooldown_sec; a bar at
##           the bottom shows charge; release fires once, damage ∝ charge.
##   Secondary slot → fire_mode "aura" (Ionizing Field): while equipped, damages
##       every asteroid within radius_px every tick_interval_sec.
##
## Damage is routed through the "asteroid_main" group (asteroids own their HP).
## Any future enemy type can reuse the same damage_point / damage_area contract.

const BULLET_SPEED := 720.0
const GAUSS_SPEED := 700.0           # heavy lumpy ball — slower so you can see it plough through
const BULLET_HIT_RADIUS := 6.0
const HOMING_TURN := 6.0              # (legacy) how fast old homing bullets bent toward their target
# Homing Missile — cinematic 4-phase launch: eject → curve up → hang & aim → accelerate → strike+explode.
# Phase durations (s):
const MISSILE_EJECT_T := 0.2         # phase 1: pop off the back/underside
const MISSILE_CURVE_T := 0.4         # phase 2: swoop upward (ease-out)
const MISSILE_HANG_T  := 0.6         # phase 3: hover & rotate to lock on (longer = more dramatic)
# Shape of the launch:
const MISSILE_EJECT_DIST := 85.0     # how far it pops out during eject (wider peel-out)
const MISSILE_ARC_WIDTH := 95.0      # how far out to the side the swoop/hang point sits
const MISSILE_ARC_HEIGHT := 72.0     # height of the top-of-arc / hang point above the ship
const MISSILE_FACE_TURN := 14.0      # how fast the nose rotates to match travel / lock target
# Strike (phase 4):
const MISSILE_SEEK_START := 40.0     # speed at the start of the strike (slow creep)
const MISSILE_ACCEL := 900.0         # base acceleration toward the target
const MISSILE_ACCEL_RAMP := 9.0      # acceleration grows ×this per second → slow start, hard whip
const MISSILE_SPEED := 1400.0        # max strike speed
const MISSILE_EXPLODE_DIST := 14.0   # "touched the cursor"
const MISSILE_AOE_RADIUS := 44.0
const MISSILE_MAX_LIFE := 4.0

# ── Lasgun BEAM look (tunable — core stays white, colour lives in the glow) ───
const BEAM_GLOW_COLOR   := Color(1.0, 0.70, 0.40) # beam glow colour — warm/hot (set blue to cool it)
const BEAM_CORE_COLOR   := Color(1.0, 1.0, 1.0)   # pure white core (always)
const BEAM_CORE_FRAC    := 0.10   # core width  = this × beam width (thin & sharp)
const BEAM_INNER_FRAC   := 0.20   # inner glow width (−50%)
const BEAM_HAZE_FRAC    := 0.75   # outer haze width (−50%)
const BEAM_INNER_ALPHA  := 0.50   # inner glow opacity
const BEAM_HAZE_ALPHA   := 0.16   # outer haze opacity (kept low; additive stacks it)
const BEAM_FLICKER      := 0.12   # brightness shimmer amount (0 = steady)
const BEAM_FLICKER_SPEED:= 28.0   # shimmer speed

# ── Stylized-laser layers (each animates at its own rate → feels alive) ────────
# Wobble / distortion (energy turbulence rippling down the beam)
const BEAM_WOBBLE_AMP    := 4.0    # perpendicular ripple amplitude (px); 0 = perfectly straight
const BEAM_WOBBLE_FREQ   := 0.05   # ripples per px along the beam
const BEAM_WOBBLE_SPEED  := 7.0    # how fast the ripple scrolls down the beam
# Scrolling energy pulses (bright dashes running gun→impact)
const BEAM_PULSE_COUNT   := 5
const BEAM_PULSE_SPEED   := 620.0  # px/s
const BEAM_PULSE_LEN     := 46.0   # length of each pulse streak (px)
# Electric / lightning crackle (subtle, fast flicker)
const BEAM_ELEC_INTENSITY:= 0.5    # 0..1 opacity (0 = off)
const BEAM_ELEC_SEGMENTS := 9
const BEAM_ELEC_AMP      := 6.0    # jaggedness (px)
const BEAM_ELEC_SPEED    := 22.0   # re-jag / flicker rate per second
# Stretched particles streaming down the beam
const BEAM_PARTICLE_RATE := 26.0   # spawned per second
const BEAM_PARTICLE_SPEED:= 900.0  # px/s
const BEAM_PARTICLE_LEN  := 18.0   # streak length (px)
const BEAM_PARTICLE_LIFE := 0.6    # seconds
# Bright flash at the muzzle the instant the beam turns on
const BEAM_FIRE_FLASH_SIZE := 42.0 # radius (px)
const BEAM_FIRE_FLASH_TIME := 0.12 # seconds

# ── Lasgun IMPACT — cutting-torch / welding-arc burst (tunable) ───────────────
const FLARE_CORE_COLOR     := Color(1.0, 1.0, 1.0)    # blinding white-hot center
const FLARE_SPARK_COLOR    := Color(1.0, 0.55, 0.15)  # hot-orange sparks / debris
const FLARE_GLOW_COLOR     := Color(1.0, 0.35, 0.10)  # tight hot glow around the hit
const FLARE_CENTER_SIZE    := 4.0    # hard hot center radius (small & sharp)
const FLARE_GLOW_SIZE      := 16.0   # tight glow radius (hot, not a soft halo)
const FLARE_SPARKS         := 12     # spark streaks per frame (count jitters)
const FLARE_SPARK_LEN      := 34.0   # max streak length (randomized per spark)
const FLARE_SPARK_SPREAD   := 1.7    # cone half-angle (rad) around "back toward the gun"
const FLARE_SPARK_WIDTH    := 2.0    # streak thickness
# Flying molten debris flecks (persist + arc + die)
const FLARE_DEBRIS_RATE    := 40.0   # spawned per second
const FLARE_DEBRIS_SPEED   := 260.0  # px/s
const FLARE_DEBRIS_LIFE    := 0.35   # seconds
const FLARE_DEBRIS_GRAVITY := 600.0  # px/s² (arc downward)
const FLARE_DEBRIS_SIZE    := 2.5    # px
# Chunky energy splatter on contact (thick blobs with mass)
const FLARE_CHUNK_RATE     := 28.0   # blobs spawned per second of contact
const FLARE_CHUNK_SIZE     := 9.0    # blob radius (px)
const FLARE_CHUNK_SPEED    := 200.0  # px/s
const FLARE_CHUNK_LIFE     := 0.18   # seconds (short)
const FLARE_CHUNK_LUMPS    := 0.35   # 0 = round, higher = chunkier/irregular

# ── Beam ENVIRONMENT LIGHT — warm additive light that brightens nearby sprites ─
const LIGHT_ENABLED        := true
const LIGHT_COLOR          := Color(1.0, 0.55, 0.20)  # warm light cast on the scene
const LIGHT_ENERGY         := 1.0    # overall brightness (0..~2)
const LIGHT_IMPACT_RADIUS  := 110.0  # radius of the light puddle at the hit
const LIGHT_BEAM_RADIUS    := 40.0   # half-width of the light strip along the beam
const GAUSS_FULL_DIAMETER_CM := 2.0  # full-charge ball ≈ this physical size (approx; tweak freely)

var _gauss_full_diam_px: float = 76.0
var _ship: Control = null

# Per-slot weapon contexts: left-click drives _wp (primary_weapon), right-click
# drives _ws (secondary_weapon). Each holds ALL transient firing state so the two
# slots fire fully independently — trigger/cooldown/charge, beam geometry + beam-FX
# pools, the growing-void zone + its own vortex node, and the bat swarm. Built in
# setup() (which also creates each one's vortex node). See _make_ctx().
var _wp: Dictionary = {}   # primary  (left mouse)
var _ws: Dictionary = {}   # secondary (right mouse)

# Secondary aura state (passive Ionizing Field — independent of the click triggers)
var _aura_acc := 0.0
var _aura_time := 0.0

# Auto-fire toggle (applies to the primary slot only)
var _auto_fire := false

# ── Crit + floating damage numbers ────────────────────────────────────────────
# Crit mechanic: roll crit_chance% per hit; on a crit, multiply damage by
# (1 + crit_damage/100). Both read via get_weapon_stat so affixes raise them.
const BASE_CRIT_CHANCE := 20   # % — TEMP TEST VALUE (every hit crits). SET BACK TO 0.0 when done!
const BASE_CRIT_DAMAGE := 100.0   # % extra damage on a crit (100 = double)
# Floating number look (Phase 1 = normal hits).
const DMG_NUM_COLOR    := Color(0.95, 0.97, 1.0)   # readable white over space
const DMG_NUM_SIZE     := 13       # (−30% from 18)
const DMG_NUM_LIFETIME := 0.7      # seconds before it fades out + frees
const DMG_NUM_RISE     := 36.0     # px it floats upward
const DMG_NUM_MAX      := 50       # cap on live numbers (fast tickers can't flood/lag)
# Crit number / flash (Phase 2).
const CRIT_NUM_SIZE    := 21       # (−30% from 30)
const CRIT_POP_SCALE   := 1.6      # pops to this then settles to 1.0
const CRIT_FLASH_COLOR := Color(1.0, 0.75, 0.25)
const CRIT_FLASH_SIZE  := 46.0
# Crit number LOOK — gold-gradient text + dark outline + starburst (no "CRIT!" word).
const CRIT_GRAD_TOP     := Color("ffd24a")   # gradient top (bright warm yellow)
const CRIT_GRAD_BOTTOM  := Color("f08a1d")   # gradient bottom (orange-gold)
const CRIT_TEXT_OUTLINE := Color("3a1e0a")   # thick dark brown-black outline
const CRIT_OUTLINE_SIZE := 6                  # outline thickness (px)
const CRIT_STAR_CORE    := Color("f5641e")   # starburst core (orange)
const CRIT_STAR_POINTS  := Color("c8341a")   # starburst tips (darker red-orange)
const CRIT_STAR_OUTLINE := Color("3a1e0a")   # starburst dark outline
const CRIT_STAR_SCALE   := 0.85               # star size relative to the number height
const CRIT_TEXT_SHADER := "shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(1.0, 0.82, 0.29, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.94, 0.54, 0.11, 1.0);
uniform float height = 24.0;
varying float v_y;
void vertex() { v_y = VERTEX.y / max(height, 1.0); }
void fragment() { COLOR.rgb = mix(top_color.rgb, bottom_color.rgb, clamp(v_y, 0.0, 1.0)); }
"
const HITSTOP_MS       := 0        # crit micro-freeze (real ms); 0 = OFF (set ~40-60 to re-enable)
const HITSTOP_SCALE    := 0.0      # Engine.time_scale during hit-stop (0 = full freeze)

var _dmg_layer: CanvasLayer = null   # high CanvasLayer for floating numbers (above gameplay)
var _dmg_host: Control = null
var _dmg_numbers: Array = []         # live number nodes, for the DMG_NUM_MAX cap
var _crit_text_shader: Shader = null # gold-gradient fill for crit numbers

# Batch D SHARED pools (source-agnostic — a bullet/parasite is the same whoever fired it)
var _rift_layer: CanvasLayer = null   # high CanvasLayer hosting both slots' vortex nodes
var _orbital_node: Control = null     # draws both slots' orbiting balls + lightning (above the ship)
var _parasites: Array = []  # Parasite Gun darts in flight: {pos, vel, life}
var _dots: Array = []       # attached parasites dealing DoT: {kind:"rock"/"boss", handle, dps, acc, life}
var _block_flashes: Array = []  # bat block-impact pops: {pos, age, max_age}

# Transient FX (all in StreamScreen-local space)
var _bullets: Array = []   # {pos, vel, dmg, big, life}
var _missiles: Array = []  # Homing Missile choreography: {pos, vel, dmg, target, phase, angle, orbit_t, life}
var _impacts: Array = []   # {pos, age, max_age, radius, color}
var _arcs: Array = []      # {a, b, age, max_age}

# Additive draw layer for the beam glow + impact flare (light, not paint)
var _glow: Node2D = null
var _beam_time := 0.0      # shared accumulator for the beam flicker / flare shimmer

# Environment-light overlay (additive, on a CanvasLayer above gameplay so it brightens sprites)
var _light_layer: CanvasLayer = null
var _light: Control = null

## Build a per-slot firing context (its vortex node is assigned in setup()).
func _make_ctx(slot: String, button: int, allow_auto: bool) -> Dictionary:
	return {
		"slot": slot, "button": button, "allow_auto": allow_auto,
		"trigger_down": false, "mouse_was_down": false, "cd": 0.0, "charge": 0.0,
		# beam (Lasgun hitscan_beam / Plasma Drill tether)
		"beam_active": false, "beam_from": Vector2.ZERO, "beam_to": Vector2.ZERO,
		"beam_color": Color(1.0, 0.3, 0.3), "beam_width": 8.0, "beam_hit": false,
		"beam_particles": [], "beam_part_acc": 0.0, "beam_was_active": false,
		"fire_flash_t": 0.0, "flare_debris": [], "flare_debris_acc": 0.0,
		"flare_chunks": [], "flare_chunk_acc": 0.0,
		# channel (Rift Maker void / Swarm Host bats)
		"zone": {"active": false, "pos": Vector2.ZERO, "age": 0.0, "tick_acc": 0.0},
		"rift": null, "bats": [],
		# orbital (Orbitals — always-on passive + held overcharge)
		"orbital": {"active": false, "angle": 0.0, "spin": ORBITAL_NORMAL_SPIN, "powered": false, "hit_cd": []},
	}

# Extra damageable targets registered by fight controllers (e.g. orb sub-bosses).
# Each entry: {get_rect: Callable → Rect2 (stream-local), on_hit: Callable(dmg:float)}
var _extra_targets: Array = []

# Provider for dynamic multi-targets (e.g. shielded bullets). fn() → Array[{rect,on_hit}]
var _multi_hit_provider: Callable = Callable()

var _out_of_energy_t := 0.0   # shows an "OUT OF ENERGY" message for a moment

func add_hit_target(get_rect: Callable, on_hit: Callable) -> void:
	_extra_targets.append({"get_rect": get_rect, "on_hit": on_hit})

func clear_extra_targets() -> void:
	_extra_targets.clear()

func set_multi_hit_provider(fn: Callable) -> void:
	_multi_hit_provider = fn

func clear_multi_hit_provider() -> void:
	_multi_hit_provider = Callable()

func set_auto_fire(enabled: bool) -> void:
	_auto_fire = enabled

func get_auto_fire() -> bool:
	return _auto_fire

func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Input is read by polling in _process (so firing works even when the click lands
	# on a sprite in a higher CanvasLayer, e.g. the boss). Stay transparent to mouse.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	_gauss_full_diam_px = clampf(_cm_to_px(GAUSS_FULL_DIAMETER_CM), 40.0, 120.0)
	add_to_group("weapon_system")

	# Two independent firing slots: left-click = primary, right-click = secondary.
	_wp = _make_ctx("primary_weapon", MOUSE_BUTTON_LEFT, true)
	_ws = _make_ctx("secondary_weapon", MOUSE_BUTTON_RIGHT, false)

	# Additive glow layer for the beam + impact flare (makes it read as light, not paint).
	_glow = Node2D.new()
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = gm
	_glow.z_as_relative = false
	_glow.z_index = z_index   # same depth as the rest of the weapon FX
	add_child(_glow)
	_glow.draw.connect(_draw_beam_fx_all)   # draws BOTH slots' beams additively

	# Environment light: an additive overlay on a CanvasLayer ABOVE gameplay (asteroids=0,
	# ship/boss=10) but below the HUD (50), clipped to the play area, so the beam's light
	# brightens the boss/ship/asteroids/contact. (A single Light2D can't cross CanvasLayers.)
	_light_layer = CanvasLayer.new()
	_light_layer.layer = 11
	add_child(_light_layer)
	_light = Control.new()
	_light.position = Vector2(270.0, 8.0)   # StreamScreen / play-area origin (matches beam coords)
	_light.size = Vector2(700.0, 764.0)
	_light.clip_contents = true
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lm := CanvasItemMaterial.new()
	lm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = lm
	_light_layer.add_child(_light)
	_light.draw.connect(_draw_light_all)   # casts light for BOTH slots' beams

	# Rift Maker vortex: a ColorRect driven by the swirling-portal shader, sized/positioned
	# to the void each frame in _update_rift_visual(). Additive (blend_add in the shader) so
	# it reads as energy. Noise is generated procedurally (seamless) — no asset file.
	var rnoise := FastNoiseLite.new()
	rnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rnoise.frequency = 0.045
	rnoise.fractal_octaves = 4
	var rtex := NoiseTexture2D.new()
	rtex.width = 256
	rtex.height = 256
	rtex.seamless = true
	rtex.noise = rnoise
	var rshader := Shader.new()
	rshader.code = RIFT_VORTEX_SHADER
	# Vortex nodes for the Rift Maker void — ONE PER SLOT (each its own material so the
	# two voids grow independently), on a high CanvasLayer ABOVE gameplay (asteroids=0,
	# ship/boss=10, light=11) so they draw on top. The host Control sits at the
	# StreamScreen origin (270,8) and is clipped to the play area, so the rift's
	# StreamScreen-local coords map straight through. (rshader/rtex are shared.)
	_rift_layer = CanvasLayer.new()
	_rift_layer.layer = 12
	add_child(_rift_layer)
	var rhost := Control.new()
	rhost.position = Vector2(270.0, 8.0)
	rhost.size = Vector2(700.0, 764.0)
	rhost.clip_contents = true
	rhost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rift_layer.add_child(rhost)
	_wp["rift"] = _make_rift_node(rshader, rtex)
	_ws["rift"] = _make_rift_node(rshader, rtex)
	rhost.add_child(_wp["rift"])
	rhost.add_child(_ws["rift"])

	# Orbitals draw layer — a Control at the play-area origin (270,8) on the same high
	# CanvasLayer, so the orbiting balls render ON TOP of the ship/boss. Its local coords
	# match _ship_center() (both relative to 270,8).
	_orbital_node = Control.new()
	_orbital_node.position = Vector2(270.0, 8.0)
	_orbital_node.size = Vector2(700.0, 764.0)
	_orbital_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rift_layer.add_child(_orbital_node)
	_orbital_node.draw.connect(_draw_orbitals_all)

	# Floating damage numbers: their own high CanvasLayer (above gameplay, below HUD),
	# host at the play-area origin so hit positions (StreamScreen-local) map straight in.
	_dmg_layer = CanvasLayer.new()
	_dmg_layer.layer = 13
	add_child(_dmg_layer)
	_dmg_host = Control.new()
	_dmg_host.position = Vector2(270.0, 8.0)
	_dmg_host.size = Vector2(700.0, 764.0)
	_dmg_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_layer.add_child(_dmg_host)
	_crit_text_shader = Shader.new()
	_crit_text_shader.code = CRIT_TEXT_SHADER

## One vortex ColorRect with its own ShaderMaterial (shares the shader + noise texture).
func _make_rift_node(shader: Shader, tex: Texture2D) -> ColorRect:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("portal_texture", tex)
	var cr := ColorRect.new()
	cr.material = mat
	cr.color = Color(1, 1, 1, 1)   # ignored — the shader writes COLOR directly
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.visible = false
	return cr

# ── Input ─────────────────────────────────────────────────────────────────────

func _begin_trigger(ctx: Dictionary) -> void:
	var def := _equipped_def(String(ctx["slot"]))
	if def.is_empty():
		return
	# One-time activation energy cost (Lasgun/Rift Maker): pay the moment you start
	# firing. Not enough → don't fire, and flash "OUT OF ENERGY".
	var act := get_weapon_stat(def, "activation_energy", 0.0)
	if act > 0.0 and (WEAPONS_USE_ENERGY or bool(def.get("uses_energy", false))):
		if not GameManager.try_spend_energy(act):
			_out_of_energy_t = 1.0
			return
	ctx["trigger_down"] = true
	if String(def.get("fire_mode", "")) == "charge":
		ctx["charge"] = 0.0
	# Repeat/other weapons fire from _update_weapon, which respects each slot's
	# cooldown timer — so a click only fires if that slot's cooldown has elapsed.

## Cursor inside the play area (this control fills StreamScreen). Clicks on side
## panels / the inventory button (outside the screen) won't start firing.
func _cursor_in_play() -> bool:
	var m := get_local_mouse_position()
	return m.x >= 0.0 and m.y >= 0.0 and m.x <= size.x and m.y <= size.y

func _release_trigger(ctx: Dictionary) -> void:
	if not bool(ctx["trigger_down"]):
		return
	var def := _equipped_def(String(ctx["slot"]))
	if not def.is_empty() and String(def.get("fire_mode", "")) == "charge" and float(ctx["charge"]) > 0.0:
		_fire_primary_charged(def, float(ctx["charge"]))
	_end_channel(ctx)   # collapse any held void / dismiss the swarm
	ctx["trigger_down"] = false
	ctx["charge"] = 0.0

# ── Frame update ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Each slot fires fully independently: left-click → _wp, right-click → _ws.
	_handle_input(_wp, delta)
	_handle_input(_ws, delta)
	_update_weapon(_wp, delta)
	_update_weapon(_ws, delta)
	_update_secondary(delta)        # passive aura (Ionizing Field in the secondary slot)
	_update_orbital(_wp, delta)     # Orbitals: always-on passive + held overcharge, per slot
	_update_orbital(_ws, delta)
	_update_rift_visual(_wp)        # size/position/intensity each slot's vortex node
	_update_rift_visual(_ws)
	_update_bullets(delta)
	_update_missiles(delta)
	_update_parasites(delta)   # Parasite Gun darts + attached DoTs (tick regardless of trigger)
	_tick_fx(_impacts, delta)
	_tick_fx(_arcs, delta)
	_tick_fx(_block_flashes, delta)
	_beam_time += delta
	_out_of_energy_t = maxf(0.0, _out_of_energy_t - delta)
	_tick_beam_fx(_wp, delta)
	_tick_beam_fx(_ws, delta)
	if _glow != null:
		_glow.queue_redraw()   # additive beam glow + flare (both slots)
	if _light != null:
		_light.queue_redraw()  # environment light overlay (both slots)
	if _orbital_node != null:
		_orbital_node.queue_redraw()   # orbiting balls + lightning (both slots)
	queue_redraw()

## Per-slot trigger polling. cd ticks down in real time so rapid clicking can't beat
## the cooldown. The primary slot also honours the AUTO-DRIVE auto-fire toggle.
func _handle_input(ctx: Dictionary, delta: float) -> void:
	ctx["cd"] = maxf(0.0, float(ctx["cd"]) - delta)
	var auto: bool = bool(ctx["allow_auto"]) and _auto_fire
	var down: bool = Input.is_mouse_button_pressed(int(ctx["button"])) or auto
	if _inventory_open():
		ctx["trigger_down"] = false
		ctx["charge"] = 0.0
	else:
		var can_fire: bool = (down and not bool(ctx["mouse_was_down"])) or (auto and not bool(ctx["trigger_down"]))
		if can_fire and _cursor_in_play() and not _equipped_def(String(ctx["slot"])).is_empty():
			_begin_trigger(ctx)
		elif bool(ctx["trigger_down"]) and not down:
			_release_trigger(ctx)
	ctx["mouse_was_down"] = down

func _update_weapon(ctx: Dictionary, delta: float) -> void:
	if not bool(ctx["trigger_down"]):
		ctx["beam_active"] = false
		_end_channel(ctx)   # released / not firing → collapse void, dismiss swarm
		return
	var def := _equipped_def(String(ctx["slot"]))
	if def.is_empty():
		ctx["trigger_down"] = false
		ctx["beam_active"] = false
		_end_channel(ctx)
		return
	var mode := String(def.get("fire_mode", ""))
	if mode != "beam":
		ctx["beam_active"] = false   # any non-beam weapon clears this slot's beam visual
	if mode != "channel":
		_end_channel(ctx)            # swapped off a channel weapon → clean up its zone/bats
	if mode == "repeat":
		# Fire only when this slot's cooldown has elapsed (covers both click and hold).
		if float(ctx["cd"]) <= 0.0 and _fire_by_type(def):
			ctx["cd"] = maxf(0.02, get_weapon_stat(def, "cooldown_sec", 0.2))
	elif mode == "charge":
		var maxc: float = maxf(0.1, float(_stat(def, "cooldown_sec", 3.0)))
		ctx["charge"] = minf(float(ctx["charge"]) + delta, maxc)
	elif mode == "beam":
		_update_beam(ctx, def, delta)
	elif mode == "channel":
		_update_channel(ctx, def, delta)

func _update_secondary(delta: float) -> void:
	var def := _secondary_def()
	if def.is_empty() or String(def.get("fire_mode", "")) != "aura":
		return
	_aura_time += delta
	var interval: float = maxf(0.05, float(_stat(def, "tick_interval_sec", 0.25)))
	var radius: float = float(_stat(def, "radius_px", 140.0))
	var dmg: float = float(_stat(def, "damage_per_tick", 1.0))
	_aura_acc += delta
	while _aura_acc >= interval:
		_aura_acc -= interval
		_aura_tick(radius, dmg)

func _aura_tick(radius: float, dmg: float) -> void:
	var center := _ship_center()
	var ast := _ast()
	if ast != null and ast.has_method("damage_area"):
		var hits: Array = ast.damage_area(center, radius, dmg)
		for p: Vector2 in hits:
			_arcs.append({"a": center, "b": p, "age": 0.0, "max_age": 0.18})
			_on_damage_dealt(p, dmg, false)   # aura = area DoT → no crit
	# Boss also takes aura damage if within range.
	var boss_rect := _boss_rect_local()
	if boss_rect.has_area() and _circle_hits_rect(center, radius, boss_rect):
		GameManager.take_boss_damage(int(dmg))
		var bf := get_tree().get_first_node_in_group("chromeleon_fight")
		if bf != null and bf.has_method("flash_boss_hit"):
			bf.flash_boss_hit()
		_arcs.append({"a": center, "b": boss_rect.position + boss_rect.size * 0.5, "age": 0.0, "max_age": 0.18})
		_on_damage_dealt(boss_rect.position + boss_rect.size * 0.5, dmg, false)

func _update_bullets(delta: float) -> void:
	var ast := _ast()
	var boss_rect := _boss_rect_local()
	var i: int = _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		# Homing: bend the velocity toward the nearest target, keeping speed constant.
		if b.get("homing", false):
			var tgt := _nearest_target(b["pos"])
			if tgt != Vector2.ZERO:
				var cur: Vector2 = b["vel"]
				var spd := cur.length()
				if spd > 0.01:
					var desired := (tgt - (b["pos"] as Vector2)).normalized() * spd
					var steer := cur.lerp(desired, clampf(HOMING_TURN * delta, 0.0, 1.0))
					if steer.length() > 0.01:
						b["vel"] = steer.normalized() * spd
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) + delta
		var pos: Vector2 = b["pos"]
		var big: bool = b["big"]
		var remove := false
		if big:
			# Piercing: spend damage equal to each rock's HP; leftover keeps flying.
			var r: float = _ball_radius(b)
			if boss_rect.has_area() and _circle_hits_rect(pos, maxf(r, 4.0), boss_rect):
				GameManager.take_boss_damage(int(b["dmg"]))
				var bf := get_tree().get_first_node_in_group("chromeleon_fight")
				if bf != null and bf.has_method("flash_boss_hit"):
					bf.flash_boss_hit()
				_spawn_impact(pos, true)
				_on_damage_dealt(pos, float(b["dmg"]), bool(b.get("is_crit", false)))
				b["dmg"] = 0.0   # boss absorbs the whole ball
			else:
				for et: Dictionary in _extra_targets:
					var er: Rect2 = (et["get_rect"] as Callable).call()
					if er.has_area() and _circle_hits_rect(pos, maxf(r, 4.0), er):
						(et["on_hit"] as Callable).call(float(b["dmg"]))
						_spawn_impact(pos, true)
						_on_damage_dealt(pos, float(b["dmg"]), bool(b.get("is_crit", false)))
						b["dmg"] = 0.0
						break
			if ast != null and ast.has_method("pierce_at") and float(b["dmg"]) > 0.0:
				var absorbed: float = ast.pierce_at(pos, maxf(r, 4.0), float(b["dmg"]))
				if absorbed > 0.0:
					_spawn_impact(pos, true)
					_on_damage_dealt(pos, absorbed, bool(b.get("is_crit", false)))
					b["dmg"] = float(b["dmg"]) - absorbed
			if float(b["dmg"]) <= 0.5:
				remove = true
		else:
			if ast != null and ast.has_method("damage_point") and ast.damage_point(pos, BULLET_HIT_RADIUS, float(b["dmg"])):
				_spawn_impact(pos, false)
				_on_damage_dealt(pos, float(b["dmg"]), bool(b.get("is_crit", false)))
				remove = true
			elif boss_rect.has_area() and boss_rect.has_point(pos):
				GameManager.take_boss_damage(int(b["dmg"]))
				var bf := get_tree().get_first_node_in_group("chromeleon_fight")
				if bf != null and bf.has_method("flash_boss_hit"):
					bf.flash_boss_hit()
				_spawn_impact(pos, false)
				_on_damage_dealt(pos, float(b["dmg"]), bool(b.get("is_crit", false)))
				remove = true
			else:
				for et: Dictionary in _extra_targets:
					var er: Rect2 = (et["get_rect"] as Callable).call()
					if er.has_area() and er.has_point(pos):
						(et["on_hit"] as Callable).call(float(b["dmg"]))
						_spawn_impact(pos, false)
						_on_damage_dealt(pos, float(b["dmg"]), bool(b.get("is_crit", false)))
						remove = true
						break
				if not remove and _multi_hit_provider.is_valid():
					for mh: Dictionary in _multi_hit_provider.call():
						var mr: Rect2 = mh["rect"]
						if mr.has_area() and mr.has_point(pos):
							(mh["on_hit"] as Callable).call(float(b["dmg"]))
							_spawn_impact(pos, false)
							_on_damage_dealt(pos, float(b["dmg"]), bool(b.get("is_crit", false)))
							remove = true
							break
		# Cone pellets: vanish once they've travelled their max range.
		if not remove and b.has("max_dist"):
			b["travel"] = float(b.get("travel", 0.0)) + (b["vel"] as Vector2).length() * delta
			if float(b["travel"]) >= float(b["max_dist"]):
				remove = true
		var off: bool = pos.x < -48.0 or pos.x > size.x + 48.0 or pos.y < -48.0 or pos.y > size.y + 48.0
		if remove or off or float(b["life"]) > 4.0:
			_bullets.remove_at(i)
		i -= 1

func _tick_fx(arr: Array, delta: float) -> void:
	var i: int = arr.size() - 1
	while i >= 0:
		var e: Dictionary = arr[i]
		e["age"] = float(e["age"]) + delta
		if float(e["age"]) >= float(e["max_age"]):
			arr.remove_at(i)
		i -= 1

# ── Firing ────────────────────────────────────────────────────────────────────

func _fire_primary(def: Dictionary) -> void:
	_spawn_bullet(float(get_weapon_stat(def, "damage", 1.0)), false, 0.0, def)

## Data-driven fire dispatch: one shot of the weapon, branched on its fire_type.
## Returns false if the shot couldn't happen (e.g. not enough energy) so the
## caller stops spamming the cooldown loop this frame.
func _fire_by_type(def: Dictionary) -> bool:
	match String(def.get("fire_type", "projectile")):
		"homing":
			if not _spend_weapon_energy(def):
				return false
			_fire_homing(def)
		"cone":
			if not _spend_weapon_energy(def):
				return false
			_fire_cone(def)
		"chain":
			if not _spend_weapon_energy(def):
				return false
			_fire_chain(def)
		"dot_stack":
			if not _spend_weapon_energy(def):
				return false
			_fire_parasites(def)
		_:  # "projectile" and anything not yet implemented → a plain bullet
			_fire_primary(def)
	return true

## Energy consumption is OFF for now (user will re-enable later). Flip this to true
## to make weapons spend their "energy" stat per shot again.
const WEAPONS_USE_ENERGY := false   # global master; individual weapons opt in via def "uses_energy"

## Spend this weapon's energy; true if paid (or free). Per-shot weapons spend the
## full "energy" stat; beam weapons list "energy" as a per-SECOND rate, so they
## spend this tick's share (energy × tick_interval).
func _spend_weapon_energy(def: Dictionary) -> bool:
	if not (WEAPONS_USE_ENERGY or bool(def.get("uses_energy", false))):
		return true
	var cost := get_weapon_stat(def, "energy", 0.0)
	if String(def.get("fire_mode", "")) == "beam":
		cost *= maxf(0.02, get_weapon_stat(def, "tick_interval_sec", 0.15))
	if cost <= 0.0:
		return true
	return GameManager.try_spend_energy(cost)

func _fire_homing(def: Dictionary) -> void:
	# Cinematic launch: eject off the back → swoop up (ease-out) → hang & aim → rocket to cursor → explode.
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var ship_c := _ship_center()
	var nose := _muzzle() - ship_c
	if nose.length() < 0.01:
		nose = Vector2.UP
	nose = nose.normalized()
	var half_ship := maxf(_muzzle().distance_to(ship_c), 24.0)
	var down := -nose                                   # toward the back/underside
	var side := 1.0 if randf() < 0.5 else -1.0          # peel off to one side
	var p0 := ship_c + down * half_ship * 0.5           # spawn at the back/underside
	var eject_dir := (down * 0.5 + Vector2(side, 0.0) * 1.0).normalized()   # out & slightly down
	var p1 := p0 + eject_dir * MISSILE_EJECT_DIST       # eject end
	var p2 := ship_c + Vector2(side * MISSILE_ARC_WIDTH, -MISSILE_ARC_HEIGHT)  # top-of-arc / hang point
	var ctrl := Vector2(p2.x, p1.y)                     # bezier control → swoop out then up
	_missiles.append({
		"pos": p0, "vel": Vector2.ZERO, "dmg": dmg, "target": get_local_mouse_position(),
		"phase": "eject", "pt": 0.0, "speed": 0.0, "seek_t": 0.0, "life": 0.0, "facing": eject_dir.angle(),
		"p0": p0, "p1": p1, "p2": p2, "ctrl": ctrl, "def": def,
	})
	_spawn_impact(p0, false)

func _qbezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u) + b * (2.0 * u * t) + c * (t * t)

func _update_missiles(delta: float) -> void:
	var i: int = _missiles.size() - 1
	while i >= 0:
		var m: Dictionary = _missiles[i]
		m["life"] = float(m["life"]) + delta
		var pos: Vector2 = m["pos"]
		var explode := false
		match String(m["phase"]):
			"eject":  # phase 1 — pop off the back/underside
				m["pt"] = float(m["pt"]) + delta
				var t := clampf(float(m["pt"]) / MISSILE_EJECT_T, 0.0, 1.0)
				var np: Vector2 = (m["p0"] as Vector2).lerp(m["p1"], t)
				m["vel"] = np - pos
				m["pos"] = np
				if float(m["pt"]) >= MISSILE_EJECT_T:
					m["phase"] = "curve"; m["pt"] = 0.0
			"curve":  # phase 2 — swoop upward, ease-out (slows at the top)
				m["pt"] = float(m["pt"]) + delta
				var t := clampf(float(m["pt"]) / MISSILE_CURVE_T, 0.0, 1.0)
				var te := 1.0 - pow(1.0 - t, 2.0)
				var np := _qbezier(m["p1"], m["ctrl"], m["p2"], te)
				m["vel"] = np - pos
				m["pos"] = np
				if float(m["pt"]) >= MISSILE_CURVE_T:
					m["phase"] = "hang"; m["pt"] = 0.0
			"hang":  # phase 3 — nearly stop, rotate to lock onto the cursor
				m["pt"] = float(m["pt"]) + delta
				var drift := -10.0 * clampf(float(m["pt"]) / MISSILE_HANG_T, 0.0, 1.0)
				m["pos"] = (m["p2"] as Vector2) + Vector2(0.0, drift)
				m["vel"] = Vector2.ZERO
				if float(m["pt"]) >= MISSILE_HANG_T:
					m["phase"] = "seek"; m["speed"] = MISSILE_SEEK_START; m["seek_t"] = 0.0
			_:  # phase 4 — accelerate (ease-in) to the cursor, explode on touch.
				# Acceleration grows over time → very slow creep, then a hard whip.
				m["seek_t"] = float(m["seek_t"]) + delta
				var accel := MISSILE_ACCEL * (1.0 + MISSILE_ACCEL_RAMP * float(m["seek_t"]))
				m["speed"] = minf(MISSILE_SPEED, float(m["speed"]) + accel * delta)
				var to_t: Vector2 = (m["target"] as Vector2) - pos
				var step := float(m["speed"]) * delta
				if to_t.length() <= maxf(step, MISSILE_EXPLODE_DIST):
					m["pos"] = m["target"]
					explode = true
				else:
					var dir := to_t.normalized()
					m["vel"] = dir * float(m["speed"])
					m["pos"] = pos + dir * step
		# Rotation: match travel during eject/curve/seek; lock onto the target during hang.
		var desired: float
		if String(m["phase"]) == "hang":
			desired = ((m["target"] as Vector2) - (m["pos"] as Vector2)).angle()
		else:
			var v: Vector2 = m["vel"]
			desired = v.angle() if v.length() > 0.5 else float(m["facing"])
		m["facing"] = lerp_angle(float(m["facing"]), desired, clampf(MISSILE_FACE_TURN * delta, 0.0, 1.0))
		if not explode and float(m["life"]) > MISSILE_MAX_LIFE:
			explode = true
		if explode:
			_missile_explode(m["pos"], float(m["dmg"]), m.get("def", {}))
			_missiles.remove_at(i)
		else:
			_missiles[i] = m
		i -= 1

## AoE blast: damage every target whose center is within MISSILE_AOE_RADIUS.
func _missile_explode(pos: Vector2, dmg: float, def: Dictionary = {}) -> void:
	for t: Dictionary in _collect_targets():
		if (t["center"] as Vector2).distance_to(pos) <= MISSILE_AOE_RADIUS + float(t["radius"]):
			_apply_to(t, dmg, def)
	_spawn_impact(pos, true)   # big flash

func _fire_cone(def: Dictionary) -> void:
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var pellets := int(get_weapon_stat(def, "pellets", 5.0))
	var spread := deg_to_rad(get_weapon_stat(def, "spread_deg", 30.0))
	var rng := get_weapon_stat(def, "range_px", 180.0)
	var muzzle := _muzzle()
	var aim := get_local_mouse_position() - muzzle
	if aim.length() < 0.01:
		aim = Vector2.UP
	var base := aim.angle()
	for i in maxi(1, pellets):
		var t := 0.0 if pellets <= 1 else (float(i) / float(pellets - 1) - 0.5)
		var ang := base + t * spread
		var dir := Vector2(cos(ang), sin(ang))
		var r := _roll_crit(def, dmg)   # each pellet rolls its own crit
		_bullets.append({
			"pos": muzzle, "vel": dir * BULLET_SPEED, "dmg": float(r["dmg"]), "big": false,
			"life": 0.0, "dmg_ref": float(r["dmg"]), "max_dist": rng, "travel": 0.0,
			"is_crit": bool(r["crit"]),
		})
	_spawn_impact(muzzle, false)

## Nearest live target's center in this control's local space (asteroids, then the
## boss, then registered sub-boss targets). Vector2.ZERO if there is nothing.
func _nearest_target(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	var ast := _ast()
	if ast != null and ast.has_method("get_asteroid_centers"):
		for c: Vector2 in ast.get_asteroid_centers():
			var d := from.distance_to(c)
			if d < best_d:
				best_d = d; best = c
	var br := _boss_rect_local()
	if br.has_area():
		var bc := br.position + br.size * 0.5
		var d := from.distance_to(bc)
		if d < best_d:
			best_d = d; best = bc
	for et: Dictionary in _extra_targets:
		var er: Rect2 = (et["get_rect"] as Callable).call()
		if er.has_area():
			var ec := er.position + er.size * 0.5
			var d := from.distance_to(ec)
			if d < best_d:
				best_d = d; best = ec
	return best

# ── Shared targeting (beam / tether / chain) ──────────────────────────────────

## Every live target as {center, radius, kind, on_hit}. kind ∈ rock/boss/extra/multi.
func _collect_targets() -> Array:
	var out: Array = []
	var ast := _ast()
	if ast != null and ast.has_method("get_asteroid_centers"):
		var centers: Array = ast.get_asteroid_centers()
		var sizes: Array = ast.get_asteroid_sizes() if ast.has_method("get_asteroid_sizes") else []
		for i in centers.size():
			var rad := 16.0
			if i < sizes.size():
				rad = maxf((sizes[i] as Vector2).x, (sizes[i] as Vector2).y) * 0.5
			out.append({"center": centers[i], "radius": rad, "kind": "rock", "on_hit": Callable()})
	var br := _boss_rect_local()
	if br.has_area():
		out.append({"center": br.position + br.size * 0.5, "radius": maxf(br.size.x, br.size.y) * 0.5,
			"kind": "boss", "on_hit": Callable()})
	for et: Dictionary in _extra_targets:
		var er: Rect2 = (et["get_rect"] as Callable).call()
		if er.has_area():
			out.append({"center": er.position + er.size * 0.5, "radius": maxf(er.size.x, er.size.y) * 0.5,
				"kind": "extra", "on_hit": et["on_hit"]})
	if _multi_hit_provider.is_valid():
		for mh: Dictionary in _multi_hit_provider.call():
			var mr: Rect2 = mh["rect"]
			if mr.has_area():
				out.append({"center": mr.position + mr.size * 0.5, "radius": maxf(mr.size.x, mr.size.y) * 0.5,
					"kind": "multi", "on_hit": mh["on_hit"]})
	return out

## Apply damage to one target dict (routes by kind). If `def` is given, the hit
## rolls a crit (raising damage) and the floating number reflects it.
func _apply_to(t: Dictionary, dmg: float, def: Dictionary = {}) -> void:
	var final := dmg
	var crit := false
	if not def.is_empty():
		var r := _roll_crit(def, dmg)
		final = r["dmg"]
		crit = r["crit"]
	match String(t.get("kind", "")):
		"rock":
			var ast := _ast()
			if ast != null and ast.has_method("damage_point"):
				ast.damage_point(t["center"], BULLET_HIT_RADIUS, final)
		"boss":
			GameManager.take_boss_damage(int(final))
		_:
			var oh: Callable = t.get("on_hit", Callable())
			if oh.is_valid():
				oh.call(final)
	_on_damage_dealt(t.get("center", Vector2.ZERO), final, crit)

## Nearest target dict to `from` within `max_dist`, skipping any whose center is in
## `exclude`. Returns {} if none.
func _nearest_target_dict(from: Vector2, targets: Array, max_dist: float, exclude: Array = []) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for t: Dictionary in targets:
		var c: Vector2 = t["center"]
		if exclude.has(c):
			continue
		var d := from.distance_to(c)
		if d <= best_d + float(t["radius"]) and d < best_d:
			best_d = d; best = t
	return best

## First target a ray (origin, dir) hits within max_len. Returns {"target": <dict or {}>,
## "along": <distance along the ray to that target's center, or max_len if none>}.
func _beam_first_hit(origin: Vector2, dir: Vector2, max_len: float, width: float) -> Dictionary:
	var best := {}
	var best_along := max_len
	for t: Dictionary in _collect_targets():
		var to_t: Vector2 = (t["center"] as Vector2) - origin
		var along := to_t.dot(dir)
		if along < 0.0 or along > max_len:
			continue
		var perp := (to_t - dir * along).length()
		if perp <= width + float(t["radius"]) and along < best_along:
			best_along = along; best = t
	return {"target": best, "along": best_along}

# ── Beam weapons (hitscan_beam / tether) ──────────────────────────────────────

func _update_beam(ctx: Dictionary, def: Dictionary, delta: float) -> void:
	var ft := String(def.get("fire_type", ""))
	var muzzle := _muzzle()
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var do_tick: bool = float(ctx["cd"]) <= 0.0
	var interval := maxf(0.02, get_weapon_stat(def, "tick_interval_sec", 0.15))
	var width: float = get_weapon_stat(def, "beam_width", 8.0)
	ctx["beam_width"] = width
	# CONTINUOUS energy drain — decoupled from the damage tick so it can't silently
	# skip a subtraction. While the beam is held it drains the "energy" stat as a
	# per-SECOND cost, scaled by delta → a true 20/s regardless of framerate. Regen
	# (GameManager.ENERGY_REGEN = 5/s) keeps running in the background, so net −15/s.
	# Check-then-pay every frame: if we can't afford this frame's slice, the beam
	# cuts out and the trigger releases (must let go + re-press, paying activation).
	if WEAPONS_USE_ENERGY or bool(def.get("uses_energy", false)):
		var drain := get_weapon_stat(def, "energy", 0.0) * delta   # per-second cost × delta
		if drain > 0.0 and not GameManager.try_spend_energy(drain):
			ctx["beam_active"] = false
			ctx["beam_hit"] = false
			ctx["trigger_down"] = false
			return
	if ft == "tether":
		var rng := get_weapon_stat(def, "range_px", 170.0)
		var anchor := _nearest_target_dict(muzzle, _collect_targets(), rng)
		if anchor.is_empty():
			ctx["beam_active"] = false
			return
		ctx["beam_active"] = true
		ctx["beam_color"] = Color(0.4, 1.0, 0.85)
		ctx["beam_from"] = muzzle
		ctx["beam_to"] = anchor["center"]
		ctx["beam_hit"] = true
		if do_tick:   # energy already drained continuously above; tick only deals damage
			_apply_to(anchor, dmg, def)
			ctx["cd"] = interval
	else:  # hitscan_beam
		var max_len := get_weapon_stat(def, "range_px", 760.0)
		var dir := Vector2.UP   # fire straight forward (ship faces up); never tilts toward targets
		var res := _beam_first_hit(muzzle, dir, max_len, width * 0.5)
		var hit: Dictionary = res["target"]
		ctx["beam_active"] = true
		ctx["beam_color"] = BEAM_GLOW_COLOR   # cool-blue glow (core stays white in _draw_beam_fx)
		ctx["beam_from"] = muzzle
		ctx["beam_hit"] = not hit.is_empty()
		if not hit.is_empty():
			# Terminate the (straight) beam at the contact point — the near edge of the
			# first obstacle along the ray — instead of bending to its center.
			var edge := maxf(0.0, float(res["along"]) - float(hit["radius"]))
			ctx["beam_to"] = muzzle + dir * edge
		else:
			ctx["beam_to"] = muzzle + dir * max_len
		if do_tick:   # energy already drained continuously above; tick only deals damage
			if not hit.is_empty():
				_apply_to(hit, dmg, def)
			ctx["cd"] = interval

# ── Chain weapon (Arc) ────────────────────────────────────────────────────────

func _fire_chain(def: Dictionary) -> void:
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var jumps := int(get_weapon_stat(def, "chain_jumps", 4.0))
	var rng := get_weapon_stat(def, "chain_range_px", 200.0)
	var muzzle := _muzzle()
	var targets := _collect_targets()
	# First link: the target nearest the cursor.
	var cursor := get_local_mouse_position()
	var cur := _nearest_target_dict(cursor, targets, INF)
	if cur.is_empty():
		return
	var hit_centers: Array = []
	var prev := muzzle
	for _j in range(maxi(1, jumps)):
		if cur.is_empty():
			break
		var c: Vector2 = cur["center"]
		_apply_to(cur, dmg, def)
		_arcs.append({"a": prev, "b": c, "age": 0.0, "max_age": 0.22})
		hit_centers.append(c)
		_spawn_impact(c, false)
		prev = c
		cur = _nearest_target_dict(c, targets, rng, hit_centers)

func _fire_primary_charged(def: Dictionary, charge: float) -> void:
	var maxc: float = maxf(0.1, float(_stat(def, "cooldown_sec", 1.5)))
	var max_dmg: float = float(_stat(def, "damage", 1.0))
	var dmg: float = max_dmg * clampf(charge / maxc, 0.0, 1.0)
	_spawn_bullet(dmg, true, max_dmg, def)

func _spawn_bullet(dmg: float, big: bool, dmg_ref: float = 0.0, def: Dictionary = {}) -> void:
	var muzzle := _muzzle()
	var dir := (get_local_mouse_position() - muzzle)
	if dir.length() < 0.01:
		dir = Vector2.UP
	dir = dir.normalized()
	var ref := dmg_ref if dmg_ref > 0.0 else dmg
	# Roll crit ONCE at spawn; bake the multiplier into both dmg and the size-reference
	# (so the gauss ball keeps its size + pierce maths) and flag the bullet as a crit.
	var is_crit := false
	if not def.is_empty():
		var r := _roll_crit(def, dmg)
		if bool(r["crit"]):
			var mult := float(r["dmg"]) / maxf(0.0001, dmg)
			dmg = float(r["dmg"])
			ref *= mult
			is_crit = true
	var b: Dictionary = {
		"pos": muzzle,
		"vel": dir * (GAUSS_SPEED if big else BULLET_SPEED),
		"dmg": dmg,
		"big": big,
		"life": 0.0,
		"dmg_ref": ref,   # damage that maps to "full size"
		"is_crit": is_crit,
	}
	if big:
		# Fixed per-ball lumpiness so the metal ball keeps its shape as it shrinks.
		var lumps: Array = []
		for _k in range(12):
			lumps.append(randf_range(0.82, 1.14))
		b["lumps"] = lumps
	_bullets.append(b)
	_spawn_impact(muzzle, big)   # muzzle flash

## Visual + hit radius of a gauss ball: proportional to its remaining damage.
func _ball_radius(b: Dictionary) -> float:
	var frac: float = clampf(float(b["dmg"]) / maxf(1.0, float(b["dmg_ref"])), 0.0, 1.0)
	return _gauss_full_diam_px * 0.5 * frac

func _spawn_impact(pos: Vector2, big: bool) -> void:
	_impacts.append({
		"pos": pos,
		"age": 0.0,
		"max_age": 0.32 if big else 0.20,
		"radius": 30.0 if big else 12.0,
	})

# ── Crit + floating damage numbers ────────────────────────────────────────────
## Roll a crit for this hit. Returns {dmg, crit}. crit_chance/crit_damage read via
## get_weapon_stat → AFFIX HOOK: the crit_chance/crit_damage affixes raise them.
func _roll_crit(def: Dictionary, base: float) -> Dictionary:
	var chance := get_weapon_stat(def, "crit_chance", BASE_CRIT_CHANCE)
	var crit := randf() * 100.0 < chance
	var dmg := base
	if crit:
		dmg = base * (1.0 + get_weapon_stat(def, "crit_damage", BASE_CRIT_DAMAGE) / 100.0)
	return {"dmg": dmg, "crit": crit}

## Single hook fired whenever damage lands: floating number always; on a crit also a
## bigger coloured impact flash + a brief hit-stop.
func _on_damage_dealt(pos: Vector2, amount: float, crit: bool) -> void:
	_spawn_damage_number(pos, amount, crit)
	if crit:
		_spawn_crit_flash(pos)
		if HITSTOP_MS > 0:   # set HITSTOP_MS to 0 to disable the crit micro-freeze entirely
			GameManager.hit_stop(HITSTOP_MS, HITSTOP_SCALE)

## Punchier, coloured impact ring + burst at a crit hit (reuses the _impacts pool).
func _spawn_crit_flash(pos: Vector2) -> void:
	_impacts.append({
		"pos": pos,
		"age": 0.0,
		"max_age": 0.30,
		"radius": CRIT_FLASH_SIZE,
		"color": CRIT_FLASH_COLOR,   # marks it as a crit flash in _draw()
	})

## Floating damage number at a hit position: rises + fades, then frees itself. Normal
## hits are a small white outlined number; crits are a gold-gradient number with a
## thick dark outline and a starburst behind the left (built as one cluster Control).
func _spawn_damage_number(world_pos: Vector2, amount: float, is_crit: bool) -> void:
	if _dmg_host == null:
		return
	while _dmg_numbers.size() >= DMG_NUM_MAX:   # cap → drop oldest so fast tickers can't flood
		var old: Variant = _dmg_numbers.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var node: Control = _make_crit_number(roundi(amount)) if is_crit else _make_normal_number(roundi(amount))
	node.pivot_offset = node.size * 0.5
	node.position = world_pos - node.size * 0.5 + Vector2(randf_range(-6.0, 6.0), -10.0)
	if is_crit:
		node.scale = Vector2.ONE * CRIT_POP_SCALE
	_dmg_host.add_child(node)
	_dmg_numbers.append(node)
	# Rise + fade as one unit; crits also pop their scale back down to 1.0.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "position:y", node.position.y - DMG_NUM_RISE, DMG_NUM_LIFETIME)
	tw.tween_property(node, "modulate:a", 0.0, DMG_NUM_LIFETIME).set_ease(Tween.EASE_IN)
	if is_crit:
		tw.tween_property(node, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void:
		_dmg_numbers.erase(node)
		node.queue_free())

func _dmg_font() -> FontFile:
	return load("res://assets/fonts/Gameplay.ttf") as FontFile

## One number Label with explicit fill/outline (used for both normal numbers and the
## crit cluster's two stacked layers).
func _make_dmg_label(text: String, size: int, fill: Color, outline_col: Color, outline_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := _dmg_font()
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", fill)
	l.add_theme_color_override("font_outline_color", outline_col)
	l.add_theme_constant_override("outline_size", outline_size)
	l.reset_size()
	return l

## Plain white outlined number.
func _make_normal_number(n: int) -> Control:
	return _make_dmg_label(str(n), DMG_NUM_SIZE, DMG_NUM_COLOR, Color(0, 0, 0, 0.9), 5)

## Crit cluster: starburst (back) + dark-outline number + gold-gradient number, as a
## single Control so it floats/pops/fades as one unit.
func _make_crit_number(n: int) -> Control:
	var cont := Control.new()
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Back layer = the number rendered all-dark with a thick outline → the hard outline.
	var back := _make_dmg_label(str(n), CRIT_NUM_SIZE, CRIT_TEXT_OUTLINE, CRIT_TEXT_OUTLINE, CRIT_OUTLINE_SIZE)
	var lblsize := back.size
	cont.custom_minimum_size = lblsize
	cont.size = lblsize
	# Starburst FIRST (drawn behind), anchored to the left of the number.
	var star := Control.new()
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sr := CRIT_NUM_SIZE * CRIT_STAR_SCALE
	star.position = Vector2(-sr * 0.25, lblsize.y * 0.5)
	star.draw.connect(_draw_crit_star.bind(star, sr))
	cont.add_child(star)
	star.queue_redraw()
	cont.add_child(back)
	# Front layer = the gradient fill (no outline), exactly on top → dark rim shows.
	var front := _make_dmg_label(str(n), CRIT_NUM_SIZE, Color.WHITE, Color(0, 0, 0, 0.0), 0)
	var mat := ShaderMaterial.new()
	mat.shader = _crit_text_shader
	mat.set_shader_parameter("top_color", CRIT_GRAD_TOP)
	mat.set_shader_parameter("bottom_color", CRIT_GRAD_BOTTOM)
	mat.set_shader_parameter("height", maxf(1.0, lblsize.y))
	front.material = mat
	cont.add_child(front)
	return cont

## Spiky impact star, centred at the node's local origin (orange core, redder tips).
func _draw_crit_star(node: Control, radius: float) -> void:
	var spikes := 9
	var inner := radius * 0.45
	node.draw_colored_polygon(_star_points(Vector2.ZERO, radius + 2.0, inner + 2.0, spikes), CRIT_STAR_OUTLINE)
	var pts := _star_points(Vector2.ZERO, radius, inner, spikes)
	var cols := PackedColorArray()
	for i in pts.size():
		cols.append(CRIT_STAR_POINTS if i % 2 == 0 else CRIT_STAR_CORE)   # outer tips darker
	node.draw_polygon(pts, cols)

func _star_points(center: Vector2, outer_r: float, inner_r: float, spikes: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := spikes * 2
	for i in n:
		var r := outer_r if i % 2 == 0 else inner_r
		var ang := -PI / 2.0 + TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	return pts

# ── Batch D weapons: growing_zone / dot_stack / minion ────────────────────────
# Rift Maker vortex shader — based on the MIT-licensed "2D Swirling Vortex Portal"
# (godotshaders.com), adapted for a purple galaxy look (dark eye → bright core →
# arms → soft edge), growth-driven intensity, and an additive energy glow. The
# `contrast` knob sharpens the arms (bright peaks, darker gaps). All swirl is
# TIME-driven (no node rotation). Tune via the uniform defaults.
const RIFT_VORTEX_SHADER := "shader_type canvas_item;
render_mode blend_add;

uniform sampler2D portal_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4  arm_color  : source_color = vec4(0.55, 0.20, 0.95, 1.0);
uniform vec4  core_color : source_color = vec4(0.95, 0.75, 1.0, 1.0);
uniform vec4  eye_color  : source_color = vec4(0.04, 0.0, 0.10, 1.0);
uniform float vortex_effect_radius : hint_range(0.05, 0.5, 0.01) = 0.5;
uniform float eye_size : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float twist_strength : hint_range(0.0, 30.0, 0.1) = 9.0;
uniform float arm_count : hint_range(1.0, 12.0, 0.5) = 5.0;
uniform float pulsation_speed : hint_range(0.0, 5.0, 0.01) = 0.7;
uniform float breath_magnitude : hint_range(-0.3, 0.3, 0.005) = 0.05;
uniform float overall_rotation_speed : hint_range(-3.0, 3.0, 0.01) = 0.42;
uniform float texture_scroll_speed : hint_range(-2.0, 2.0, 0.01) = 0.5;
uniform float edge_softness : hint_range(0.01, 0.5, 0.005) = 0.12;
uniform float contrast : hint_range(0.5, 6.0, 0.05) = 2.4;   // higher = sharper arms / darker gaps
uniform float glow : hint_range(0.0, 4.0, 0.01) = 1.7;
uniform float growth : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	float ang = atan(uv.y, uv.x);
	float t = sin(TIME * pulsation_speed);
	// Radius-based twist: arms churn harder near the center, harder as the rift grows.
	float spatial = smoothstep(0.0, vortex_effect_radius, vortex_effect_radius - dist);
	float twist = spatial * twist_strength * (0.5 + 0.5 * growth) * t;
	float a2 = ang + TIME * overall_rotation_speed + twist;
	// Sample seamless noise in polar space → spiral arms scrolling inward.
	vec2 puv  = vec2(a2 * arm_count / 6.2831853, dist - TIME * texture_scroll_speed);
	float n   = texture(portal_texture, fract(puv)).r;
	float n2  = texture(portal_texture, fract(puv * 2.0 + 0.5)).r;
	float raw = clamp(n * 0.7 + n2 * 0.5, 0.0, 1.0);
	float arms = pow(raw, contrast);   // contrast curve: bright peaks, dark gaps
	// Radial colour ramp: dark eye → bright core ring → purple arms.
	float core = smoothstep(eye_size + 0.18, eye_size, dist);
	float eye  = smoothstep(eye_size, 0.0, dist);
	vec3 col = mix(arm_color.rgb, core_color.rgb, core);
	col = mix(col, eye_color.rgb, eye);
	float breath = 1.0 + breath_magnitude * t;
	float bright = arms * (0.35 + 0.65 * growth) * glow * breath;
	bright += core * (0.5 * growth) * glow;   // glowing core even where noise is low
	float edge  = smoothstep(vortex_effect_radius, vortex_effect_radius - edge_softness, dist);
	float alpha = edge * (1.0 - eye * 0.85);   // punch a darker hole at the eye
	COLOR = vec4(col * bright, alpha);
	if (UV.x < 0.0 || UV.x > 1.0 || UV.y < 0.0 || UV.y > 1.0) COLOR.a = 0.0;
}
"

const PARASITE_SPEED      := 520.0
const PARASITE_HIT_RADIUS := 10.0
const BAT_SPEED           := 240.0
const BAT_HIT_RANGE       := 40.0    # how close a bat must be to land an auto-attack
const BAT_BLOCK_RADIUS    := 22.0    # how close a bat must be to pop a boss projectile

# ── Orbitals (orbital) — tunable feel/visual knobs (damage/energy live in the data
# table and route through get_weapon_stat so affixes can modify them later) ──────
const ORBITAL_BALLS             := 3       # number of orbiting balls (evenly spaced)
const ORBITAL_RADIUS            := 98.0    # orbit radius in px (~7cm-diameter circle on screen)
const ORBITAL_NORMAL_SPIN       := 120.0   # passive spin, deg/sec (one loop every 3s)
const ORBITAL_MAX_MULT          := 3.0     # overcharged spin = 300% of normal → 360 deg/sec
const ORBITAL_ACCEL             := 480.0   # spin-up rate (deg/sec per sec) when overcharging
const ORBITAL_DECEL             := 360.0   # spin-down rate (deg/sec per sec) when released
const ORBITAL_BALL_RADIUS       := 9.0     # ball size + collision radius (px)
const ORBITAL_HIT_COOLDOWN      := 0.12    # per-ball seconds before it can hit again (≈1 hit per pass)
const ORBITAL_LIGHTNING_PASSIVE := 0.30    # arc intensity when idle (subtle)
const ORBITAL_LIGHTNING_POWERED := 1.0     # arc intensity at full overcharge

## "channel" fire_mode: hold-to-sustain. Optional continuous energy drain (same as
## beams; OFF unless the weapon sets uses_energy), then dispatch on fire_type.
func _update_channel(ctx: Dictionary, def: Dictionary, delta: float) -> void:
	if WEAPONS_USE_ENERGY or bool(def.get("uses_energy", false)):
		var drain := get_weapon_stat(def, "energy", 0.0) * delta   # per-second cost × delta
		if drain > 0.0 and not GameManager.try_spend_energy(drain):
			_out_of_energy_t = 1.0
			_end_channel(ctx)
			ctx["trigger_down"] = false
			return
	match String(def.get("fire_type", "")):
		"growing_zone":
			_tick_zone(ctx, def, delta)
		"minion":
			_tick_swarm(ctx, def, delta)

## Collapse this slot's Rift Maker void and dismiss its Swarm Host bats. Idempotent.
func _end_channel(ctx: Dictionary) -> void:
	(ctx["zone"] as Dictionary)["active"] = false
	(ctx["bats"] as Array).clear()

## Size/position this slot's swirling-vortex node to its void and feed it the growth
## value. Hidden whenever the rift isn't active (so it vanishes the instant you release).
func _update_rift_visual(ctx: Dictionary) -> void:
	var rift := ctx["rift"] as ColorRect
	if rift == null:
		return
	var z: Dictionary = ctx["zone"]
	if bool(z["active"]):
		var rad: float = float(z.get("radius", 40.0))
		var f: float = float(z.get("intensity", 0.0))
		var zp: Vector2 = z["pos"]
		rift.position = zp - Vector2(rad, rad)
		rift.size = Vector2(rad * 2.0, rad * 2.0)   # diameter ≈ 2× damage-radius
		var mat := rift.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("growth", f)
		rift.visible = true
	else:
		rift.visible = false

# ── Rift Maker (growing_zone) ──────────────────────────────────────────────────
func _tick_zone(ctx: Dictionary, def: Dictionary, delta: float) -> void:
	var z: Dictionary = ctx["zone"]
	if not bool(z["active"]):
		z["active"] = true
		z["pos"] = get_local_mouse_position()   # placed where you press; stays put
		z["age"] = 0.0
		z["tick_acc"] = 0.0
	var ramp: float = maxf(0.1, get_weapon_stat(def, "ramp_sec", 2.5))
	z["age"] = minf(float(z["age"]) + delta, ramp)
	var f: float = float(z["age"]) / ramp
	var radius: float = lerpf(get_weapon_stat(def, "radius_min", 40.0), get_weapon_stat(def, "radius_max", 150.0), f)
	z["radius"] = radius      # cached for the vortex visual (matches the damage radius)
	z["intensity"] = f        # 0→1 growth, drives the shader's intensity
	var dmg_ps: float = lerpf(get_weapon_stat(def, "damage_min", 30.0), get_weapon_stat(def, "damage_max", 300.0), f)
	var interval: float = maxf(0.05, get_weapon_stat(def, "tick_interval_sec", 0.3))
	z["tick_acc"] = float(z["tick_acc"]) + delta
	while float(z["tick_acc"]) >= interval:
		z["tick_acc"] = float(z["tick_acc"]) - interval
		var pos: Vector2 = z["pos"]
		var hit_dmg := dmg_ps * interval
		var ast := _ast()
		if ast != null and ast.has_method("damage_area"):
			var zhits: Array = ast.damage_area(pos, radius, hit_dmg)
			if not zhits.is_empty():
				_on_damage_dealt(pos, hit_dmg, false)   # one number per pulse (area DoT → no crit)
		var br := _boss_rect_local()
		if br.has_area() and _circle_hits_rect(pos, radius, br):
			GameManager.take_boss_damage(int(maxf(1.0, hit_dmg)))
			var bf := get_tree().get_first_node_in_group("chromeleon_fight")
			if bf != null and bf.has_method("flash_boss_hit"):
				bf.flash_boss_hit()
			_on_damage_dealt(br.position + br.size * 0.5, hit_dmg, false)

# ── Parasite Gun (dot_stack) ───────────────────────────────────────────────────
func _fire_parasites(def: Dictionary) -> void:
	var n := maxi(1, int(get_weapon_stat(def, "parasites", 5.0)))
	var dps := get_weapon_stat(def, "dps", 6.0)
	var tick := maxf(0.05, get_weapon_stat(def, "dot_tick_sec", 0.5))
	var muzzle := _muzzle()
	var aim := get_local_mouse_position() - muzzle
	if aim.length() < 0.01:
		aim = Vector2.UP
	var base := aim.angle()
	for i in n:
		var t := 0.0 if n <= 1 else (float(i) / float(n - 1) - 0.5)
		var ang := base + t * deg_to_rad(26.0)
		var dir := Vector2(cos(ang), sin(ang))
		_parasites.append({"pos": muzzle, "vel": dir * PARASITE_SPEED, "life": 0.0, "dps": dps, "tick": tick})
	_spawn_impact(muzzle, false)

## Darts in flight attach on first hit; attached parasites then tick DoT forever
## (until the target dies). Runs every frame, independent of the trigger.
func _update_parasites(delta: float) -> void:
	var ast := _ast()
	var br := _boss_rect_local()
	var i := _parasites.size() - 1
	while i >= 0:
		var p: Dictionary = _parasites[i]
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["life"] = float(p["life"]) + delta
		var pos: Vector2 = p["pos"]
		var attached := false
		if ast != null and ast.has_method("get_asteroid_handle_at"):
			var h: TextureRect = ast.get_asteroid_handle_at(pos, PARASITE_HIT_RADIUS)
			if h != null:
				_dots.append({"kind": "rock", "handle": h, "dps": float(p["dps"]), "tick": float(p["tick"]), "acc": 0.0})
				attached = true
		if not attached and br.has_area() and br.has_point(pos):
			_dots.append({"kind": "boss", "handle": null, "dps": float(p["dps"]), "tick": float(p["tick"]), "acc": 0.0})
			attached = true
		var off: bool = pos.x < -48.0 or pos.x > size.x + 48.0 or pos.y < -48.0 or pos.y > size.y + 48.0
		if attached or off or float(p["life"]) > 4.0:
			if attached:
				_spawn_impact(pos, false)
			_parasites.remove_at(i)
		i -= 1
	# Attached DoTs.
	var di := _dots.size() - 1
	while di >= 0:
		var d: Dictionary = _dots[di]
		var tick: float = maxf(0.05, float(d["tick"]))
		d["acc"] = float(d["acc"]) + delta
		var dead := false
		while float(d["acc"]) >= tick:
			d["acc"] = float(d["acc"]) - tick
			var hit_dmg := float(d["dps"]) * tick
			if String(d["kind"]) == "rock":
				var h: TextureRect = d["handle"]
				if h == null or not is_instance_valid(h):
					dead = true; break
				if ast == null or not ast.has_method("damage_asteroid") or not ast.damage_asteroid(h, hit_dmg):
					dead = true; break   # asteroid destroyed → parasite dies with it
				_on_damage_dealt(h.position + h.size * 0.5, hit_dmg, false)   # DoT → no crit
			else:  # boss
				var br2 := _boss_rect_local()
				if not br2.has_area():
					dead = true; break
				GameManager.take_boss_damage(int(maxf(1.0, hit_dmg)))
				_on_damage_dealt(br2.position + br2.size * 0.5, hit_dmg, false)
		if dead:
			_dots.remove_at(di)
		di -= 1

# ── Swarm Host (minion) ────────────────────────────────────────────────────────
func _tick_swarm(ctx: Dictionary, def: Dictionary, delta: float) -> void:
	var bats: Array = ctx["bats"]
	var want := maxi(0, int(get_weapon_stat(def, "bats", 4.0)))
	var respawn := maxf(0.1, get_weapon_stat(def, "respawn_sec", 3.0))
	var atk_iv := maxf(0.05, get_weapon_stat(def, "attack_interval_sec", 0.4))
	var dmg := get_weapon_stat(def, "damage", 5.0)
	var roam := get_weapon_stat(def, "bat_range_px", 260.0)
	var ship := _ship_center()
	while bats.size() < want:
		bats.append({"pos": ship + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0)),
			"vel": Vector2.ZERO, "alive": true, "respawn_t": 0.0, "atk_acc": 0.0})
	while bats.size() > want:
		bats.remove_at(bats.size() - 1)
	# Boss controllers that can have their projectiles body-blocked.
	var bosses: Array = []
	for g: String in ["boss_fight", "chromeleon_fight"]:
		var node := get_tree().get_first_node_in_group(g)
		if node != null and node.has_method("consume_projectile_near"):
			bosses.append(node)
	var targets := _collect_targets()
	for bi in bats.size():
		var bat: Dictionary = bats[bi]
		if not bool(bat["alive"]):
			bat["respawn_t"] = float(bat["respawn_t"]) - delta
			if float(bat["respawn_t"]) <= 0.0:
				bat["alive"] = true
				bat["pos"] = ship + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
			bats[bi] = bat
			continue
		var tgt := _nearest_target(bat["pos"])
		var aim_pos: Vector2 = tgt if (tgt != Vector2.ZERO and ship.distance_to(tgt) <= roam) else ship
		var to := aim_pos - (bat["pos"] as Vector2)
		var desired := (to.normalized() * BAT_SPEED) if to.length() > 1.0 else Vector2.ZERO
		bat["vel"] = (bat["vel"] as Vector2).lerp(desired, clampf(6.0 * delta, 0.0, 1.0))
		bat["pos"] = (bat["pos"] as Vector2) + (bat["vel"] as Vector2) * delta
		bat["atk_acc"] = float(bat["atk_acc"]) + delta
		if tgt != Vector2.ZERO and (bat["pos"] as Vector2).distance_to(tgt) <= BAT_HIT_RANGE and float(bat["atk_acc"]) >= atk_iv:
			bat["atk_acc"] = 0.0
			var tdict := _nearest_target_dict(bat["pos"], targets, BAT_HIT_RANGE + 24.0)
			if not tdict.is_empty():
				_apply_to(tdict, dmg, def)
		# Body-block: pop the nearest boss projectile; the bat dies on contact.
		for node in bosses:
			var res: Dictionary = node.consume_projectile_near(bat["pos"], BAT_BLOCK_RADIUS)
			if bool(res.get("hit", false)):
				bat["alive"] = false
				bat["respawn_t"] = respawn
				_block_flashes.append({"pos": res.get("pos", bat["pos"]), "age": 0.0, "max_age": 0.25})
				break
		bats[bi] = bat

## Live position of a parasite DoT's target (follows a drifting rock / the boss).
func _dot_pos(d: Dictionary) -> Vector2:
	if String(d["kind"]) == "rock":
		var h: TextureRect = d["handle"]
		if h != null and is_instance_valid(h):
			return h.position + h.size * 0.5
		return Vector2.ZERO
	var br := _boss_rect_local()
	return (br.position + br.size * 0.5) if br.has_area() else Vector2.ZERO

# ── Orbitals (orbital) ─────────────────────────────────────────────────────────
## Always-on while equipped: ORBITAL_BALLS metal balls orbit the ship and damage on
## contact (free, no energy — like the Swarm Host passive). Holding the fire button
## OVERCHARGES them: spin ramps up to ORBITAL_MAX_MULT× and the lightning intensifies,
## draining energy (10 up front via _begin_trigger + this 20/s). Energy is check-paid
## every tick like the Lasgun — can't afford → drop back to the free passive state.
func _update_orbital(ctx: Dictionary, delta: float) -> void:
	var def := _equipped_def(String(ctx["slot"]))
	var orb: Dictionary = ctx["orbital"]
	if def.is_empty() or String(def.get("fire_type", "")) != "orbital":
		orb["active"] = false
		return
	orb["active"] = true
	var hit_cd: Array = orb["hit_cd"]
	while hit_cd.size() < ORBITAL_BALLS:
		hit_cd.append(0.0)
	var powered: bool = bool(ctx["trigger_down"])
	if powered and (WEAPONS_USE_ENERGY or bool(def.get("uses_energy", false))):
		var drain := get_weapon_stat(def, "energy", 20.0) * delta   # per-second cost × delta
		if drain > 0.0 and not GameManager.try_spend_energy(drain):
			ctx["trigger_down"] = false   # can't sustain → drop to the free passive state
			powered = false
	orb["powered"] = powered
	# Smoothly ramp the spin toward its target (normal, or up to max while powered).
	var target_spin: float = ORBITAL_NORMAL_SPIN * (ORBITAL_MAX_MULT if powered else 1.0)
	var rate: float = ORBITAL_ACCEL if powered else ORBITAL_DECEL
	orb["spin"] = move_toward(float(orb["spin"]), target_spin, rate * delta)
	orb["angle"] = fmod(float(orb["angle"]) + float(orb["spin"]) * delta, 360.0)
	# Each ball checks collisions independently, debounced so one pass ≈ one hit — so
	# faster spin → more passes → more hits, WITHOUT changing the per-hit damage.
	var ship := _ship_center()
	var dmg := get_weapon_stat(def, "damage", 18.0)
	var targets := _collect_targets()
	var step := 360.0 / float(ORBITAL_BALLS)
	for k in ORBITAL_BALLS:
		hit_cd[k] = maxf(0.0, float(hit_cd[k]) - delta)
		if float(hit_cd[k]) > 0.0:
			continue
		var ang := deg_to_rad(float(orb["angle"]) + step * float(k))
		var bpos := ship + Vector2(cos(ang), sin(ang)) * ORBITAL_RADIUS
		var best := {}
		var best_d := INF
		for t: Dictionary in targets:
			var d := bpos.distance_to(t["center"])
			if d <= ORBITAL_BALL_RADIUS + float(t["radius"]) and d < best_d:
				best_d = d
				best = t
		if not best.is_empty():
			_apply_to(best, dmg, def)
			hit_cd[k] = ORBITAL_HIT_COOLDOWN

## All orbitals visuals (drawn on _orbital_node, above the ship).
func _draw_orbitals_all() -> void:
	if _orbital_node == null:
		return
	_draw_orbital(_wp)
	_draw_orbital(_ws)

func _draw_orbital(ctx: Dictionary) -> void:
	var orb: Dictionary = ctx["orbital"]
	if not bool(orb.get("active", false)):
		return
	var ship := _ship_center()
	# Lightning intensity tracks the spin ramp (0 at normal → 1 at full overcharge).
	var span := maxf(1.0, ORBITAL_NORMAL_SPIN * (ORBITAL_MAX_MULT - 1.0))
	var frac := clampf((float(orb["spin"]) - ORBITAL_NORMAL_SPIN) / span, 0.0, 1.0)
	var intensity := lerpf(ORBITAL_LIGHTNING_PASSIVE, ORBITAL_LIGHTNING_POWERED, frac)
	var step := 360.0 / float(ORBITAL_BALLS)
	for k in ORBITAL_BALLS:
		var ang := deg_to_rad(float(orb["angle"]) + step * float(k))
		var bpos := ship + Vector2(cos(ang), sin(ang)) * ORBITAL_RADIUS
		_draw_orbital_ball(bpos, intensity)

## One metal ball with electric arcs leaking out (count/size/brightness scale with intensity).
func _draw_orbital_ball(c: Vector2, intensity: float) -> void:
	var r := ORBITAL_BALL_RADIUS
	# Lightning first (under the ball): jagged arcs spraying outward, re-jagged each frame.
	var arcs := 2 + int(round(intensity * 4.0))
	var ecol := Color(0.6, 0.85, 1.0, clampf(0.35 + 0.65 * intensity, 0.0, 1.0))
	var jag := floorf(_beam_time * 22.0)
	for a in arcs:
		var aang := _beam_time * 5.0 + TAU * float(a) / float(arcs) + _pseudo(float(a), jag)
		var dir := Vector2(cos(aang), sin(aang))
		var perp := Vector2(-dir.y, dir.x)
		var length := r * 1.1 + intensity * r * 2.0
		var prev := c + dir * r
		for s in range(1, 4):
			var tt := float(s) / 3.0
			var jit := _pseudo(aang * 10.0 + float(s), jag) * (2.0 + intensity * 5.0)
			var pt := c + dir * (r + length * tt) + perp * jit
			_orbital_node.draw_line(prev, pt, Color(ecol.r, ecol.g, ecol.b, ecol.a * (1.0 - tt * 0.6)), 1.0 + intensity * 1.6)
			prev = pt
	# Metal ball: dark rim → grey body → bright highlight.
	_orbital_node.draw_circle(c, r + 1.0, Color(0.04, 0.05, 0.08))
	_orbital_node.draw_circle(c, r, Color(0.55, 0.58, 0.66))
	_orbital_node.draw_circle(c - Vector2(r * 0.3, r * 0.3), r * 0.36, Color(0.86, 0.9, 0.96))

## All Batch-D visuals (called from _draw()). The Rift Maker void is drawn by its
## own shader node (_rift, updated in _update_rift_visual) — not here.
func _draw_batch_d() -> void:
	# Parasite darts in flight.
	for p: Dictionary in _parasites:
		var pp: Vector2 = p["pos"]
		var tail: Vector2 = pp - (p["vel"] as Vector2).normalized() * 8.0
		draw_line(tail, pp, Color(0.5, 1.0, 0.4, 0.9), 2.0)
		draw_circle(pp, 2.5, Color(0.7, 1.0, 0.5))
	# Attached parasites — pulsing blobs that follow their target.
	var pulse: float = 0.6 + 0.4 * sin(_beam_time * 10.0)
	for d: Dictionary in _dots:
		var dp := _dot_pos(d)
		if dp != Vector2.ZERO:
			draw_circle(dp, 4.0 * pulse, Color(0.4, 0.9, 0.3, 0.85))
			draw_circle(dp, 2.0, Color(0.75, 1.0, 0.5))
	# Swarm bats (both slots).
	_draw_bats(_wp["bats"])
	_draw_bats(_ws["bats"])
	# Bat block-pops.
	for bf2: Dictionary in _block_flashes:
		var t: float = clampf(1.0 - float(bf2["age"]) / float(bf2["max_age"]), 0.0, 1.0)
		_draw_ring(bf2["pos"], 14.0 * (1.0 - t), Color(0.7, 0.9, 1.0, t), 2.0)

## Draw one slot's swarm bats (small winged shapes).
func _draw_bats(bats: Array) -> void:
	for bat: Dictionary in bats:
		if not bool(bat["alive"]):
			continue
		var bp: Vector2 = bat["pos"]
		var fwd: Vector2 = (bat["vel"] as Vector2)
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector2.RIGHT
		var sd := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([bp + sd * 7.0, bp - fwd * 3.0, bp + fwd * 4.0]), Color(0.14, 0.11, 0.18))
		draw_colored_polygon(PackedVector2Array([bp - sd * 7.0, bp - fwd * 3.0, bp + fwd * 4.0]), Color(0.14, 0.11, 0.18))
		draw_circle(bp, 2.0, Color(0.6, 0.1, 0.7))

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Secondary aura ring
	var sdef := _secondary_def()
	if not sdef.is_empty() and String(sdef.get("fire_mode", "")) == "aura":
		var c := _ship_center()
		var r: float = float(_stat(sdef, "radius_px", 140.0))
		var pulse: float = 0.5 + 0.5 * sin(_aura_time * 6.0)
		draw_circle(c, r, Color(0.3, 0.7, 1.0, 0.05 + 0.05 * pulse))
		_draw_ring(c, r, Color(0.5, 0.85, 1.0, 0.45 + 0.35 * pulse), 2.0)

	# (Beam glow + impact flare are drawn additively in _draw_beam_fx on the _glow node.)

	# Batch D weapons (void / parasites / bats)
	_draw_batch_d()

	# Lightning arcs
	for a: Dictionary in _arcs:
		var t: float = clampf(1.0 - float(a["age"]) / float(a["max_age"]), 0.0, 1.0)
		_draw_lightning(a["a"], a["b"], Color(0.75, 0.9, 1.0, t))

	# Bullets
	for b: Dictionary in _bullets:
		if b["big"]:
			_draw_metal_ball(b)
		else:
			var p: Vector2 = b["pos"]
			var col := Color(1.0, 0.95, 0.55)
			var tail: Vector2 = p - (b["vel"] as Vector2).normalized() * 10.0
			draw_line(tail, p, col, 2.5)
			draw_circle(p, 2.5, col)

	# Homing missiles — big orange rounds, oriented to their facing (nose rotates per phase)
	for m: Dictionary in _missiles:
		var mp: Vector2 = m["pos"]
		var f := float(m["facing"])
		var fwd := Vector2(cos(f), sin(f))
		var sd := Vector2(-fwd.y, fwd.x)
		draw_line(mp - fwd * 12.0, mp - fwd * 32.0, Color(1.0, 0.7, 0.2, 0.7), 6.0)   # exhaust streak
		draw_colored_polygon(PackedVector2Array([
			mp + fwd * 16.0, mp - fwd * 11.0 + sd * 6.0, mp - fwd * 11.0 - sd * 6.0,
		]), Color(1.0, 0.5, 0.1))
		draw_circle(mp, 4.0, Color(1.0, 0.9, 0.5))

	# Impacts (expanding fading ring). A crit flash carries a "color" → bigger + a burst.
	for im: Dictionary in _impacts:
		var f: float = float(im["age"]) / float(im["max_age"])
		var a: float = clampf(1.0 - f, 0.0, 1.0)
		var icol: Color = im.get("color", Color(1.0, 0.85, 0.4))
		if im.has("color"):
			draw_circle(im["pos"], float(im["radius"]) * f * 0.7, Color(icol.r, icol.g, icol.b, 0.35 * a))   # burst
			_draw_ring(im["pos"], float(im["radius"]) * f, Color(icol.r, icol.g, icol.b, a), 3.0)
		else:
			_draw_ring(im["pos"], float(im["radius"]) * f, Color(icol.r, icol.g, icol.b, a), 2.0)

	# Asteroid HP bars
	var ast := _ast()
	if ast != null and ast.has_method("get_damaged_asteroids"):
		for d: Dictionary in ast.get_damaged_asteroids():
			var p2: Vector2 = d["pos"]
			var w: float = maxf(float(d["w"]), 16.0)
			var frac: float = d["frac"]
			var bx: float = p2.x - w * 0.5
			var by: float = p2.y - float(d["w"]) * 0.5 - 8.0
			draw_rect(Rect2(bx, by, w, 3.0), Color(0, 0, 0, 0.6), true)
			draw_rect(Rect2(bx, by, w * frac, 3.0),
				Color(0.4, 0.9, 0.4).lerp(Color(0.9, 0.3, 0.3), 1.0 - frac), true)

	# Charge bar (Gauss) — for whichever slot is charging.
	for ctx: Dictionary in [_wp, _ws]:
		if not bool(ctx["trigger_down"]):
			continue
		var cdef := _equipped_def(String(ctx["slot"]))
		if not cdef.is_empty() and String(cdef.get("fire_mode", "")) == "charge":
			_draw_charge_bar(cdef, float(ctx["charge"]))

	# "OUT OF ENERGY" flash (tried to fire with too little energy)
	if _out_of_energy_t > 0.0:
		var fnt := ThemeDB.fallback_font
		var fs := 18
		var msg := "OUT OF ENERGY"
		var tw := fnt.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var mc := _ship_center()
		var at := Vector2(mc.x - tw * 0.5, mc.y - 70.0)
		var al := clampf(_out_of_energy_t, 0.0, 1.0)
		draw_string(fnt, at + Vector2(1, 1), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7 * al))
		draw_string(fnt, at, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.4, 0.3, al))

## Deterministic pseudo-random in -1..1 from two seeds (for the electric jag flicker).
func _pseudo(a: float, b: float) -> float:
	var v := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return (v - floor(v)) * 2.0 - 1.0

## Per-frame beam FX bookkeeping (fire flash + streak particles) for ONE slot.
func _tick_beam_fx(ctx: Dictionary, delta: float) -> void:
	var active: bool = bool(ctx["beam_active"])
	var hit: bool = bool(ctx["beam_hit"])
	var bfrom: Vector2 = ctx["beam_from"]
	var bto: Vector2 = ctx["beam_to"]
	var bwidth: float = float(ctx["beam_width"])
	# Muzzle flash the instant the beam turns on.
	if active and not bool(ctx["beam_was_active"]):
		ctx["fire_flash_t"] = BEAM_FIRE_FLASH_TIME
	ctx["beam_was_active"] = active
	ctx["fire_flash_t"] = maxf(0.0, float(ctx["fire_flash_t"]) - delta)

	# Spawn + advance streak particles streaming gun → impact along the beam.
	var beam_len := bfrom.distance_to(bto)
	var particles: Array = ctx["beam_particles"]
	if active:
		ctx["beam_part_acc"] = float(ctx["beam_part_acc"]) + BEAM_PARTICLE_RATE * delta
		while float(ctx["beam_part_acc"]) >= 1.0:
			ctx["beam_part_acc"] = float(ctx["beam_part_acc"]) - 1.0
			particles.append({
				"along": 0.0,
				"off": randf_range(-bwidth * 0.35, bwidth * 0.35),
				"life": 0.0,
			})
	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["along"] = float(p["along"]) + BEAM_PARTICLE_SPEED * delta
		p["life"] = float(p["life"]) + delta
		if float(p["along"]) > beam_len or float(p["life"]) > BEAM_PARTICLE_LIFE:
			particles.remove_at(i)
		else:
			particles[i] = p
		i -= 1

	# Molten debris flecks sprayed back toward the gun off the contact point.
	var debris: Array = ctx["flare_debris"]
	if active and hit:
		var bdir := bto - bfrom
		bdir = bdir.normalized() if bdir.length() > 0.001 else Vector2.UP
		var back_ang := (-bdir).angle()
		ctx["flare_debris_acc"] = float(ctx["flare_debris_acc"]) + FLARE_DEBRIS_RATE * delta
		while float(ctx["flare_debris_acc"]) >= 1.0:
			ctx["flare_debris_acc"] = float(ctx["flare_debris_acc"]) - 1.0
			var ang := back_ang + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
			var spd := FLARE_DEBRIS_SPEED * randf_range(0.5, 1.0)
			debris.append({
				"pos": bto, "vel": Vector2.from_angle(ang) * spd,
				"life": 0.0, "max_life": FLARE_DEBRIS_LIFE * randf_range(0.6, 1.0),
			})
	var di := debris.size() - 1
	while di >= 0:
		var fb: Dictionary = debris[di]
		fb["life"] = float(fb["life"]) + delta
		if float(fb["life"]) >= float(fb["max_life"]):
			debris.remove_at(di)
			di -= 1
			continue
		var v: Vector2 = fb["vel"]
		v.y += FLARE_DEBRIS_GRAVITY * delta   # arc down like molten flecks
		fb["vel"] = v
		fb["pos"] = (fb["pos"] as Vector2) + v * delta
		debris[di] = fb
		di -= 1

	# Chunky energy splatter — thick blobs with mass, sprayed back+out, short-lived.
	var chunks: Array = ctx["flare_chunks"]
	if active and hit:
		var cdir := bto - bfrom
		cdir = cdir.normalized() if cdir.length() > 0.001 else Vector2.UP
		var cback := (-cdir).angle()
		ctx["flare_chunk_acc"] = float(ctx["flare_chunk_acc"]) + FLARE_CHUNK_RATE * delta
		while float(ctx["flare_chunk_acc"]) >= 1.0:
			ctx["flare_chunk_acc"] = float(ctx["flare_chunk_acc"]) - 1.0
			var cang := cback + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
			var cspd := FLARE_CHUNK_SPEED * randf_range(0.4, 1.0)
			var lumps: Array = []
			for _k in range(8):
				lumps.append(randf_range(1.0 - FLARE_CHUNK_LUMPS, 1.0 + FLARE_CHUNK_LUMPS))
			chunks.append({
				"pos": bto, "vel": Vector2.from_angle(cang) * cspd,
				"life": 0.0, "max_life": FLARE_CHUNK_LIFE * randf_range(0.7, 1.0),
				"size": FLARE_CHUNK_SIZE * randf_range(0.7, 1.2), "lumps": lumps,
			})
	var ci := chunks.size() - 1
	while ci >= 0:
		var cb: Dictionary = chunks[ci]
		cb["life"] = float(cb["life"]) + delta
		if float(cb["life"]) >= float(cb["max_life"]):
			chunks.remove_at(ci)
			ci -= 1
			continue
		var cv: Vector2 = cb["vel"]
		cv.y += FLARE_DEBRIS_GRAVITY * delta
		cb["vel"] = cv
		cb["pos"] = (cb["pos"] as Vector2) + cv * delta
		chunks[ci] = cb
		ci -= 1

## Drawn on the ADDITIVE _glow node (blend = ADD) → reads as light, not paint.
func _draw_beam_fx_all() -> void:
	_draw_beam_fx(_wp)
	_draw_beam_fx(_ws)

func _draw_beam_fx(ctx: Dictionary) -> void:
	if _glow == null:
		return
	_draw_flare_debris(ctx)   # molten flecks (keep flying even after the beam stops)
	if not bool(ctx["beam_active"]):
		return
	var a: Vector2 = ctx["beam_from"]
	var b: Vector2 = ctx["beam_to"]
	var flick := 1.0 + sin(_beam_time * BEAM_FLICKER_SPEED) * BEAM_FLICKER   # subtle shimmer
	var w: float = float(ctx["beam_width"])
	var g: Color = ctx["beam_color"]   # glow colour (blue for the Lasgun, teal for the tether)
	# Outer haze — stacked soft lines → smooth blue falloff, no hard edge
	_glow.draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * 0.4 * flick), w * BEAM_HAZE_FRAC * 1.8)
	_glow.draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * 0.7 * flick), w * BEAM_HAZE_FRAC * 1.25)
	_glow.draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * flick),       w * BEAM_HAZE_FRAC)
	# Inner glow — glow colour blended halfway to white
	var iw := Color((g.r + 1.0) * 0.5, (g.g + 1.0) * 0.5, (g.b + 1.0) * 0.5, BEAM_INNER_ALPHA * flick)
	_glow.draw_line(a, b, iw, maxf(2.0, w * BEAM_INNER_FRAC))

	# Beam axis
	var seg := b - a
	var L := seg.length()
	var dir := (seg / L) if L > 0.001 else Vector2.UP
	var perp := Vector2(-dir.y, dir.x)

	# (1) Energy wobble layer — rippling bright polyline (heat-haze / turbulence)
	if BEAM_WOBBLE_AMP > 0.0 and L > 1.0:
		var wprev := a
		for s in range(1, 17):
			var alo := L * float(s) / 16.0
			var woff := sin(alo * BEAM_WOBBLE_FREQ - _beam_time * BEAM_WOBBLE_SPEED) * BEAM_WOBBLE_AMP
			var wpt := a + dir * alo + perp * woff
			_glow.draw_line(wprev, wpt, Color(g.r, g.g, g.b, 0.30 * flick), maxf(2.0, w * 0.16))
			wprev = wpt

	# (2) Scrolling energy pulses — bright dashes racing gun → impact
	if L > 1.0:
		for k in BEAM_PULSE_COUNT:
			var phase := fmod(_beam_time * BEAM_PULSE_SPEED + float(k) * (L / float(maxi(1, BEAM_PULSE_COUNT))), L)
			var pc := a + dir * phase
			var pt := pc - dir * minf(BEAM_PULSE_LEN, phase)
			_glow.draw_line(pt, pc, Color(1.0, 1.0, 1.0, 0.45 * flick), maxf(2.0, w * 0.22))

	# (3) Electric crackle — jagged polyline, fast flicker (re-jags ELEC_SPEED×/sec)
	if BEAM_ELEC_INTENSITY > 0.0 and L > 1.0:
		var eseed := floorf(_beam_time * BEAM_ELEC_SPEED)
		var ec := Color(0.75, 0.9, 1.0, BEAM_ELEC_INTENSITY * flick)
		var eprev := a
		for s in range(1, BEAM_ELEC_SEGMENTS + 1):
			var alo := L * float(s) / float(BEAM_ELEC_SEGMENTS)
			var eoff := 0.0
			if s < BEAM_ELEC_SEGMENTS:
				eoff = _pseudo(float(s), eseed) * BEAM_ELEC_AMP
			var ept := a + dir * alo + perp * eoff
			_glow.draw_line(eprev, ept, ec, 1.5)
			eprev = ept

	# Core — thin pure white, straight, on top
	_glow.draw_line(a, b, Color(BEAM_CORE_COLOR.r, BEAM_CORE_COLOR.g, BEAM_CORE_COLOR.b, flick), maxf(1.5, w * BEAM_CORE_FRAC))

	# (4) Stretched particles streaming down the beam
	for p: Dictionary in (ctx["beam_particles"] as Array):
		var alo := float(p["along"])
		if alo > L:
			continue
		var ppos := a + dir * alo + perp * float(p["off"])
		var ptail := ppos - dir * BEAM_PARTICLE_LEN
		var pl := clampf(1.0 - float(p["life"]) / BEAM_PARTICLE_LIFE, 0.0, 1.0)
		_glow.draw_line(ptail, ppos, Color(1.0, 1.0, 1.0, 0.55 * pl), 2.0)

	# (5) Fire flash at the muzzle the instant the beam turns on
	var fire_flash_t: float = float(ctx["fire_flash_t"])
	if fire_flash_t > 0.0:
		var ft := fire_flash_t / BEAM_FIRE_FLASH_TIME   # 1 → 0
		var fr := BEAM_FIRE_FLASH_SIZE * (1.0 + (1.0 - ft) * 0.8)
		_glow.draw_circle(a, fr, Color(g.r, g.g, g.b, 0.25 * ft))
		_glow.draw_circle(a, fr * 0.4, Color(1.0, 1.0, 1.0, 0.7 * ft))

	if bool(ctx["beam_hit"]):
		_draw_flare(b, dir, flick)

## Cutting-torch / welding-arc burst at the contact point. `dir` = beam direction
## (sparks spray back toward the gun). Re-randomized every frame → crackles & alive.
func _draw_flare(at: Vector2, dir: Vector2, _flick: float) -> void:
	var back_ang := (-dir).angle()   # toward the gun
	# Tight hot glow (small & hot, not a soft halo)
	var gc := FLARE_GLOW_COLOR
	_glow.draw_circle(at, FLARE_GLOW_SIZE, Color(gc.r, gc.g, gc.b, 0.20))
	_glow.draw_circle(at, FLARE_GLOW_SIZE * 0.55, Color(gc.r, gc.g, gc.b, 0.35))
	# Chaotic spark spray — short streaks in a backward+outward cone, jittered each frame
	var n := maxi(1, FLARE_SPARKS + randi_range(-3, 3))
	var sc := FLARE_SPARK_COLOR
	for _i in n:
		var ang := back_ang + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
		var d := Vector2.from_angle(ang)
		var perp := Vector2(-d.y, d.x)
		var ln := FLARE_SPARK_LEN * randf_range(0.35, 1.0)
		var tip := at + d * ln
		var br := randf_range(0.5, 1.0)   # per-spark brightness jitter
		_glow.draw_polygon(
			PackedVector2Array([at + perp * FLARE_SPARK_WIDTH * 0.5, at - perp * FLARE_SPARK_WIDTH * 0.5, tip]),
			PackedColorArray([
				Color(1.0, 0.85, 0.5, br),     # bright hot base
				Color(1.0, 0.85, 0.5, br),
				Color(sc.r, sc.g, sc.b, 0.0),  # fade to transparent tip
			]))
	# Hard hot center — tiny, blinding, brightness jitters every frame
	_glow.draw_circle(at, FLARE_CENTER_SIZE * randf_range(0.8, 1.2), Color(1.0, 1.0, 1.0, randf_range(0.7, 1.0)))
	_glow.draw_circle(at, FLARE_CENTER_SIZE * 0.45, Color(FLARE_CORE_COLOR.r, FLARE_CORE_COLOR.g, FLARE_CORE_COLOR.b, 1.0))

## Persistent molten flecks + chunky splatter (drawn even after the beam stops).
func _draw_flare_debris(ctx: Dictionary) -> void:
	# Chunky blobs first (under the fine flecks)
	for cb: Dictionary in (ctx["flare_chunks"] as Array):
		var ct := clampf(1.0 - float(cb["life"]) / float(cb["max_life"]), 0.0, 1.0)
		var cp: Vector2 = cb["pos"]
		var r: float = float(cb["size"]) * (0.5 + 0.5 * ct)   # shrink as it dies
		var lumps: Array = cb["lumps"]
		var n: int = lumps.size()
		var pts := PackedVector2Array()
		for k in range(n):
			var ang: float = TAU * float(k) / float(n)
			pts.append(cp + Vector2(cos(ang), sin(ang)) * r * float(lumps[k]))
		_glow.draw_colored_polygon(pts, Color(1.0, 0.6, 0.25, 0.85 * ct))   # molten body
		_glow.draw_circle(cp, r * 0.4, Color(1.0, 0.9, 0.6, 0.9 * ct))       # hot center
	# Fine molten flecks
	for fb: Dictionary in (ctx["flare_debris"] as Array):
		var t := clampf(1.0 - float(fb["life"]) / float(fb["max_life"]), 0.0, 1.0)
		var p: Vector2 = fb["pos"]
		var v: Vector2 = fb["vel"]
		var tail := p - v.normalized() * FLARE_DEBRIS_SIZE * 2.2
		_glow.draw_line(tail, p, Color(1.0, 0.75, 0.35, 0.7 * t), maxf(1.0, FLARE_DEBRIS_SIZE * 0.7))
		_glow.draw_circle(p, FLARE_DEBRIS_SIZE * t, Color(1.0, 0.85, 0.5, t))

## Warm environment light cast by the beam (additive, on the high CanvasLayer overlay).
func _draw_light_all() -> void:
	_draw_light(_wp)
	_draw_light(_ws)

func _draw_light(ctx: Dictionary) -> void:
	if not LIGHT_ENABLED or not bool(ctx["beam_active"]) or _light == null:
		return
	var bfrom: Vector2 = ctx["beam_from"]
	var bto: Vector2 = ctx["beam_to"]
	var lc := LIGHT_COLOR
	var e := LIGHT_ENERGY
	# Soft light strip along the beam (brightens things it passes near)
	_light.draw_line(bfrom, bto, Color(lc.r, lc.g, lc.b, 0.05 * e), LIGHT_BEAM_RADIUS * 2.0)
	_light.draw_line(bfrom, bto, Color(lc.r, lc.g, lc.b, 0.09 * e), LIGHT_BEAM_RADIUS)
	# Impact light puddle — stacked circles (big→small) → soft radial falloff
	if bool(ctx["beam_hit"]):
		var rings := 7
		for i in range(rings):
			var rad := LIGHT_IMPACT_RADIUS * float(i + 1) / float(rings)
			_light.draw_circle(bto, rad, Color(lc.r, lc.g, lc.b, 0.05 * e))
		_light.draw_circle(bto, LIGHT_IMPACT_RADIUS * 0.16, Color(1.0, 0.92, 0.72, 0.22 * e))

func _draw_metal_ball(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var r: float = _ball_radius(b)
	if r < 1.0:
		return
	var lumps: Array = b.get("lumps", [])
	var n: int = lumps.size()
	if n < 3:
		draw_circle(pos, r, Color(0.58, 0.60, 0.65))
		return
	var pts := PackedVector2Array()
	for k in range(n):
		var ang: float = TAU * float(k) / n
		var rr: float = r * float(lumps[k])
		pts.append(pos + Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, Color(0.55, 0.57, 0.62))   # metal body
	var rim := pts
	rim.append(pts[0])
	draw_polyline(rim, Color(0.28, 0.30, 0.35), 2.0)      # dark rim
	draw_circle(pos - Vector2(r * 0.3, r * 0.35), maxf(r * 0.28, 1.0), Color(0.85, 0.88, 0.92, 0.8))  # highlight

func _draw_ring(center: Vector2, radius: float, col: Color, width: float) -> void:
	if radius <= 0.5:
		return
	draw_arc(center, radius, 0.0, TAU, 48, col, width)

func _draw_lightning(a: Vector2, b: Vector2, col: Color) -> void:
	var segs := 5
	var perp := (b - a).normalized().rotated(PI * 0.5)
	var prev := a
	for i in range(1, segs + 1):
		var base := a.lerp(b, float(i) / segs)
		if i < segs:
			base += perp * randf_range(-6.0, 6.0)
		draw_line(prev, base, col, 1.5)
		prev = base

func _draw_charge_bar(def: Dictionary, charge: float) -> void:
	var maxc: float = maxf(0.1, float(_stat(def, "cooldown_sec", 3.0)))
	var frac: float = clampf(charge / maxc, 0.0, 1.0)
	var bw: float = size.x * 0.4
	var bh := 12.0
	var x: float = (size.x - bw) * 0.5
	var y: float = size.y - 30.0
	draw_rect(Rect2(x, y, bw, bh), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(x, y, bw * frac, bh), Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.3, 0.2), frac), true)
	draw_rect(Rect2(x, y, bw, bh), Color(0.7, 0.8, 1.0, 0.85), false, 1.5)

# ── Helpers ───────────────────────────────────────────────────────────────────

## Approximate physical-cm → pixels using the monitor DPI (best-effort; display
## scaling/stretch means it's only roughly cm). Falls back to 96 DPI.
func _cm_to_px(cm: float) -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	return cm / 2.54 * float(dpi)

func _stat(def: Dictionary, key: String, fallback: float) -> float:
	var stats: Dictionary = def.get("stats", {})
	return float(stats.get(key, fallback))

# Stat keys each affix maps onto (an affix only changes the matching keys).
const _AFFIX_DAMAGE_KEYS   := ["damage", "damage_min", "damage_max", "damage_per_tick", "dps"]
const _AFFIX_COOLDOWN_KEYS := ["cooldown_sec", "tick_interval_sec"]   # lower = faster
const _AFFIX_ENERGY_KEYS   := ["energy", "activation_energy"]

## AFFIX HOOK — all firing code reads weapon stats through here. Returns the base
## stat with any rolled affixes on the equipped instance applied. (Affixes ride on
## the def via `def["affixes"]`, attached in _equipped_def from the item instance.)
##
## WIRED affixes: damage_flat & damage_percentage → damage; fire_rate → cooldown/tick
## interval (faster); energy_consumption_percentage → energy cost; crit_chance &
## crit_damage → the crit roll (_roll_crit reads them through here).
## NOT YET WIRED (need new mechanics, not just a stat — left honest as TODO):
##   projectile_speed                  → bullet speed is a shared const, not a stat key
##   armor_penetration                 → no enemy-armor system
##   poison, burn, slow, freeze        → need status-effect system
##   multishot, pierce, ricochet, splash_radius, knockback → need projectile-behaviour changes
##   energy_leech, hp_leech, shield_leech, energy_regen_flat, energy_regen_percentage → need on-hit/regen hooks
func get_weapon_stat(def: Dictionary, key: String, fallback: float) -> float:
	var v := _stat(def, key, fallback)
	# Hidden ±20% base-damage roll (damage keys only) — applied before any affixes.
	var is_dmg: bool = key in _AFFIX_DAMAGE_KEYS
	if is_dmg:
		v *= float(def.get("base_mult", 1.0))
	var affixes: Array = def.get("affixes", [])
	if affixes.is_empty():
		return v
	var dmg_pct := 0.0
	for a: Dictionary in affixes:
		var id := String(a.get("id", ""))
		var val := float(a.get("value", 0.0))
		match id:
			"damage_flat":
				if is_dmg:
					v += val
			"damage_percentage":
				if is_dmg:
					dmg_pct += val
			"fire_rate":
				if key in _AFFIX_COOLDOWN_KEYS:
					v = v / (1.0 + val / 100.0)        # % faster → lower cooldown
			"energy_consumption_percentage":
				if key in _AFFIX_ENERGY_KEYS:
					v = v * (1.0 + val / 100.0)        # val is negative → cheaper
			"crit_chance":
				if key == "crit_chance":
					v += val                           # affix adds to base crit chance
			"crit_damage":
				if key == "crit_damage":
					v += val                           # affix adds to base crit damage
	return v * (1.0 + dmg_pct / 100.0)                 # dmg_pct is 0 for non-damage keys

func _primary_def() -> Dictionary:
	return _equipped_def("primary_weapon")

func _secondary_def() -> Dictionary:
	return _equipped_def("secondary_weapon")

func _equipped_def(slot: String) -> Dictionary:
	var uid: int = InventoryManager.equipped_uid(slot)
	if uid == -1:
		return {}
	var item: Dictionary = InventoryManager.get_item(uid)
	var def: Dictionary = InventoryManager.get_def(String(item.get("def", "")))
	if def.is_empty():
		return {}
	var affixes: Array = item.get("affixes", [])
	var base_mult := float(item.get("base_mult", 1.0))
	if affixes.is_empty() and base_mult == 1.0:
		return def
	# Attach the instance's rolled affixes + base-damage roll WITHOUT mutating the
	# shared ITEM_DEFS entry, so get_weapon_stat() can apply them.
	var d := def.duplicate()
	d["affixes"] = affixes
	d["base_mult"] = base_mult
	return d

func _ast() -> Node:
	return get_tree().get_first_node_in_group("asteroid_main")

## The boss's hit rect in this layer's local space (empty Rect2 if no live boss).
## get_boss_hit_rect() is global; this control sits at StreamScreen's origin.
func _boss_rect_local() -> Rect2:
	if GameManager.boss_max_hp <= 0:
		return Rect2()
	var bf := get_tree().get_first_node_in_group("boss_fight")
	if bf == null or not bf.has_method("get_boss_hit_rect"):
		return Rect2()
	var r: Rect2 = bf.get_boss_hit_rect()
	if not r.has_area():
		return Rect2()
	return Rect2(r.position - global_position, r.size)

func _circle_hits_rect(c: Vector2, radius: float, rect: Rect2) -> bool:
	var nearest := Vector2(
		clampf(c.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(c.y, rect.position.y, rect.position.y + rect.size.y))
	return c.distance_to(nearest) <= radius

func _inventory_open() -> bool:
	var ui := get_tree().get_first_node_in_group("inventory_ui")
	return ui != null and ui.has_method("is_open") and ui.is_open()

func _ship_node() -> Control:
	if is_instance_valid(_ship):
		return _ship
	_ship = get_tree().get_first_node_in_group("ship_body") as Control
	return _ship

func _ship_center() -> Vector2:
	var s := _ship_node()
	if s == null:
		return Vector2(size.x * 0.5, size.y * 0.6)
	# Map through the ship's real transform so scale/pivot (0.5× during boss fights) are baked in.
	# This control sits at StreamScreen's origin, so global → local is a subtraction.
	return (s.get_global_transform() * (s.size * 0.5)) - global_position

func _muzzle() -> Vector2:
	var s := _ship_node()
	if s == null:
		return Vector2(size.x * 0.5, size.y * 0.6)
	# Top-center of the ship, through its real transform (handles the boss-fight 0.5× scale).
	return (s.get_global_transform() * Vector2(s.size.x * 0.5, 0.0)) - global_position
