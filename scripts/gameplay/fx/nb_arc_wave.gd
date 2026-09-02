extends Node2D
## Nautilus Move 3 — an energy shock-wave shaped as a 60° ARC, fired out of FP3 toward the player. It grows
## outward at a fixed speed, damages the ship ONCE when the front sweeps over it, and shoves every creep the
## front passes through outward so they visibly ride the wave.
##
## World-space (parented to the arena root, absolute coords) like every other boss VFX here, so the boss
## moving/turning after the shot doesn't drag the wave along with it.
##
## NOTE: no class_name — preload + .new(), matching this folder's convention.

const RING_W        := 26.0     # thickness of the bright front, px
const BAND_W        := 74.0     # thickness of the whole gradient body, px
const ARC_STEPS     := 40       # polygon resolution across the arc
const COL_CORE      := Color(0.62, 0.92, 1.0, 0.95)
const COL_MID       := Color(0.20, 0.62, 1.0, 0.55)
const COL_FADE      := Color(0.10, 0.35, 0.95, 0.0)
const PUSH_SPEED    := 520.0    # px/s outward impulse handed to each creep the front passes
const HIT_PAD       := 22.0     # ship counts as hit within this much of the front
const FADE_FRAC     := 0.72     # past this fraction of max range the wave starts dissolving

var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT   # arc centre direction
var _half: float = deg_to_rad(30.0) # half the arc's opening angle
var _speed: float = 300.0
var _max_r: float = 900.0
var _dmg: int = 15
var _r: float = 0.0
var _hit_player: bool = false
var _pushed: Dictionary = {}       # instance_id → true, so each creep is shoved exactly once
var _source: Node = null

func begin(origin: Vector2, dir: Vector2, arc_deg: float, speed: float, max_r: float, dmg: int, source: Node = null) -> void:
	_origin = origin
	_dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	_half = deg_to_rad(maxf(5.0, arc_deg) * 0.5)
	_speed = maxf(20.0, speed)
	_max_r = maxf(60.0, max_r)
	_dmg = dmg
	_source = source
	z_index = 4
	set_process(true)

func _process(delta: float) -> void:
	_r += _speed * delta
	if _r >= _max_r:
		queue_free()
		return
	_sweep()
	queue_redraw()

## Everything the FRONT of the wave is currently crossing: the ship (damage, once) and creeps (outward shove,
## once each). Both use the same test — inside the arc's angular wedge AND within RING_W of the front radius.
func _sweep() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if not _hit_player:
		var pl := tree.get_first_node_in_group("player")
		if pl != null and is_instance_valid(pl):
			var pp: Vector2 = (pl as Node2D).global_position
			if _in_wedge(pp) and absf(_origin.distance_to(pp) - _r) <= RING_W * 0.5 + HIT_PAD:
				_hit_player = true
				if _source != null and is_instance_valid(_source) and _source.has_method("_report_hit_player"):
					_source.call("_report_hit_player")
				GameManager.ship_take_damage(_dmg)
	# Creeps: one outward impulse each, written straight into `_knockback` (the same field a Gatling/Nuke hit
	# uses), so the existing decay in arena_enemy._process carries them along and eases them back out.
	for e in tree.get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(e) or e == _source:
			continue
		var id := (e as Node).get_instance_id()
		if _pushed.has(id):
			continue
		var ep: Vector2 = (e as Node2D).global_position
		if not _in_wedge(ep):
			continue
		if absf(_origin.distance_to(ep) - _r) > RING_W * 0.5 + 18.0:
			continue
		_pushed[id] = true
		var away := ep - _origin
		var push := (away.normalized() if away.length() > 0.01 else _dir) * PUSH_SPEED
		e.set("_knockback", push)

func _in_wedge(p: Vector2) -> bool:
	var v := p - _origin
	if v.length_squared() < 1.0:
		return true
	return absf(wrapf(v.angle() - _dir.angle(), -PI, PI)) <= _half

func _draw() -> void:
	if _r <= 2.0:
		return
	# Dissolve over the last stretch instead of popping out of existence at max range.
	var life := 1.0
	if _r > _max_r * FADE_FRAC:
		life = 1.0 - (_r - _max_r * FADE_FRAC) / maxf(1.0, _max_r * (1.0 - FADE_FRAC))
	var a0 := _dir.angle() - _half
	var a1 := _dir.angle() + _half
	# Body: an annulus band trailing BEHIND the front, faded from the bright front back to nothing.
	_arc_band(a0, a1, maxf(0.0, _r - BAND_W), _r - RING_W * 0.5, COL_FADE, COL_MID, life)
	# Front: the bright crest.
	_arc_band(a0, a1, maxf(0.0, _r - RING_W * 0.5), _r + RING_W * 0.5, COL_CORE, COL_CORE, life)
	# Crisp outer edge line.
	var edge := COL_CORE
	edge.a *= 0.9 * life
	draw_arc(_origin, _r + RING_W * 0.5, a0, a1, ARC_STEPS, edge, 2.5, true)

## One radial gradient band of the annulus, `col_in` at r_in → `col_out` at r_out.
func _arc_band(a0: float, a1: float, r_in: float, r_out: float, col_in: Color, col_out: Color, life: float) -> void:
	if r_out <= r_in:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var ci := col_in
	var co := col_out
	ci.a *= life
	co.a *= life
	# Two rings of vertices (inner then outer, outer reversed) → one closed ribbon polygon.
	for i in ARC_STEPS + 1:
		var t := float(i) / float(ARC_STEPS)
		var ang := lerp_angle(a0, a1, t) if absf(a1 - a0) > PI else lerpf(a0, a1, t)
		pts.append(_origin + Vector2(cos(ang), sin(ang)) * r_in)
		cols.append(ci)
	for i in ARC_STEPS + 1:
		var t := 1.0 - float(i) / float(ARC_STEPS)
		var ang := lerp_angle(a0, a1, t) if absf(a1 - a0) > PI else lerpf(a0, a1, t)
		pts.append(_origin + Vector2(cos(ang), sin(ang)) * r_out)
		cols.append(co)
	draw_polygon(pts, cols)
