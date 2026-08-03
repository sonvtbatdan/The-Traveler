extends Node2D
## Divinity buff, added as a child of the player when the divinity loot drop is collected.
## Self-contained (unlike the shield loot, this node IS the whole effect, not just a cosmetic overlay):
##   - Grows the ship +20% for the duration (drives GameManager.upg_ship_size_mult directly; arena.gd's
##     own _process already re-applies that multiplier to the sprite + collision radius every frame).
##   - Overlays the divinity sprite ON TOP of the ship (z_index = ship's SHIP_Z + 1, screen blend), rotating
##     with the ship for free since it's parented to it. Flickers, then slows down and fades out over the
##     final WARN_T seconds, disappearing exactly as the buff ends.
##   - Instantly kills any touching enemy every frame EXCEPT boss / Elite Creep / Champion Creep
##     (arena_enemy.gd's `_is_elite` — both tiers, see arena_wave_director_v2.gd's _spawn_tiered_creep;
##     there's no flag distinguishing Elite from Champion at the instance level, so both are one bucket
##     here) — those instead take RESIST_DPS per second (normal armor/mitigation applies, same as any
##     other damage source), so a well-timed divinity can't casually delete a boss or a beefed-up creep.
##   - Grants full damage immunity for the whole DURATION via GameManager.activate_shield() — while the
##     ship is glowing/growing it can't lose HP or shield to enemy contact (or anything else).
##   - In the final WARN_T seconds the ship shrinks back to its pre-buff size too.

const DURATION       := 10.0   # must match the divinity case in arena_loot.gd
const GROW_MULT      := 1.2    # +20% ship size while active
const GROW_IN_T      := 0.25   # seconds to pop up to full size on pickup
const WARN_T         := 2.5    # final seconds: shrink back + flicker slows to a stop
const SHIP_RADIUS    := 16.0   # matches arena.gd's PLAYER_RADIUS / arena_enemy.gd's ship-contact constant
const SHIP_Z         := 100    # must match arena.gd's SHIP_Z — the overlay draws at SHIP_Z + 1, just above the ship sprite
const SPRITE_WIDTH   := 70.0   # overlay sprite's on-ship width (unscaled by the grow animation)
const RESIST_DPS     := 300.0   # dmg/s dealt to boss/Elite Creep/Champion Creep instead of an instant kill
const BLINK_FREQ_MAX := 5.0    # Hz, fast flicker while at full power

var _t: float = 0.0
var _base_mult: float = 1.0
var _base_scale: float = 1.0
var _blink_phase: float = 0.0
var _player: Node2D = null
var _sprite: Sprite2D = null

func _ready() -> void:
	_player = get_parent() as Node2D
	_base_mult = GameManager.upg_ship_size_mult
	if GameManager.has_method("activate_shield"):
		GameManager.activate_shield(DURATION)   # full immunity for as long as the ship is glowing
	var tex := load("res://assets/screen/divinity.png") as Texture2D
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.z_index = SHIP_Z + 1   # draws just above the ship sprite (which sits at SHIP_Z)
		# Screen blend needs the backdrop, so it goes through hud_blend.gdshader (mode 0 = Screen) —
		# CanvasItemMaterial only exposes Mix/Add/Sub/Mul/PremultAlpha, no Screen.
		var sm := ShaderMaterial.new()
		sm.shader = load("res://assets/shaders/hud_blend.gdshader")
		sm.set_shader_parameter("mode", 0)   # Screen
		_sprite.material = sm
		_base_scale = SPRITE_WIDTH / maxf(1.0, float(tex.get_width()))
		# Set the real scale/alpha NOW, not just in _process(): the Sprite2D would otherwise sit at its
		# default scale (1.0 = full native texture size, e.g. hundreds of px) for however many frames pass
		# before _process() first runs — a single huge unscaled frame flashing on screen. Harmless-looking
		# on the old flat 2D ship art, but glaring once the SubViewport-rendered 3D ship made that frame
		# actually get composited.
		_sprite.scale = Vector2(_base_scale, _base_scale)
		_sprite.modulate.a = _glow_alpha()
		add_child(_sprite)
		# Rotation/position are inherited for free: this node (and the sprite) is a direct child of the
		# ship, so it turns and moves with it without any extra code.

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	GameManager.upg_ship_size_mult = _base_mult * _grow_factor()
	_blink_phase += TAU * _blink_freq() * delta
	_kill_touching_enemies(delta)
	if _sprite != null:
		var s := _base_scale * _grow_factor()
		_sprite.scale = Vector2(s, s)
		_sprite.modulate.a = _glow_alpha()

func _exit_tree() -> void:
	GameManager.upg_ship_size_mult = _base_mult   # always restore, however this node leaves the tree

func _grow_factor() -> float:
	if _t < GROW_IN_T:
		return lerpf(1.0, GROW_MULT, _t / GROW_IN_T)
	var warn_start := DURATION - WARN_T
	if _t >= warn_start:
		return lerpf(GROW_MULT, 1.0, clampf((_t - warn_start) / WARN_T, 0.0, 1.0))
	return GROW_MULT

## Blink frequency ramps down to 0 across the warn window (slows the flicker to a stop).
func _blink_freq() -> float:
	var warn_start := DURATION - WARN_T
	if _t < warn_start:
		return BLINK_FREQ_MAX
	return lerpf(BLINK_FREQ_MAX, 0.0, clampf((_t - warn_start) / WARN_T, 0.0, 1.0))

## Overlay sprite alpha: the sin flicker, dimmed by the same warn-window fade so it ends dark
## rather than freezing mid-bright when the frequency hits 0.
func _glow_alpha() -> float:
	var warn_start := DURATION - WARN_T
	var envelope := 1.0
	if _t >= warn_start:
		envelope = 1.0 - clampf((_t - warn_start) / WARN_T, 0.0, 1.0)
	return (0.7 + 0.3 * (0.5 + 0.5 * sin(_blink_phase))) * envelope   # brighter floor — reads clearly, not washed-out/faint

func _kill_touching_enemies(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var ship_r := SHIP_RADIUS * GameManager.upg_ship_size_mult
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en) or not en.has_method("take_damage"):
			continue
		if en.has_method("is_charmed") and en.call("is_charmed"):
			continue
		var en2 := en as Node2D
		var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
		if _player.global_position.distance_to(en2.global_position) > ship_r + enr:
			continue
		if en.is_in_group("boss") or bool(en.get("_is_elite")):
			en.take_damage(RESIST_DPS * delta)   # continuous DPS, normal armor mitigation applies
		else:
			en.take_damage(99999.0, 0.0, 0.0, true)   # instant kill, ignores armor
