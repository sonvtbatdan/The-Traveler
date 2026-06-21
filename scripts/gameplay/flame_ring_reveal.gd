extends Node2D
class_name FlameRingReveal
## Fire-ring reveal controller. A straight jet fires from the origin to a point on a circle; then a head
## flame travels the circle leaving a persistent burning trail (progressive reveal) — the ring grows
## 0%→100% like a pen tip — then holds, then burns out. Composes two FlameRibbon children (jet + ring).
## The ring ribbon is rebuilt each frame from a partial path up to draw_progress, with the tip
## INTERPOLATED (not vertex-snapped) so the head glides. UV is arc-length anchored in FlameRibbon, so the
## already-drawn trail stays stable as new length is added. All tunables grouped at top.

const FlameRibbon := preload("res://scripts/gameplay/flame_ribbon.gd")

# ── TUNABLES ─────────────────────────────────────────────────────────────────────
@export var beam_width         := 90.0
# Jet (straight spoke; always runs origin → ring start so the junction is seamless)
@export var jet_duration       := 0.8     # jet-only phase before the draw begins
@export var jet_persists       := true    # keep the jet drawn through draw/hold as the reference spoke
# Ring geometry (start point = ring_center_offset + dir(ring_start_angle)*ring_radius = jet endpoint)
@export var ring_center_offset := Vector2.ZERO
@export var ring_radius         := 240.0
@export var ring_start_angle    := 0.0    # radians; should equal the aim direction so the jet meets the ring
@export var ring_clockwise      := true
@export var ring_segments       := 96
# Phases
@export var draw_duration      := 1.2
@export var draw_ease          := 1.6     # >1 = ease in/out (smoothstep-like) on draw_progress
@export var hold_duration      := 10.0
@export var burnout_duration   := 1.5
@export var head_parks_or_fades := true   # true = head parks at closure during hold; false = head hidden
@export var auto_loop           := true
# Look (pushed to both ribbons; per-ribbon look knobs live on FlameRibbon)
@export var tint_color         := Color(1, 1, 1, 1)
@export var intensity          := 1.0
@export var contact_damage: int = 0   # >0 = deal this damage when player touches jet or ring

const CONTACT_PAD := 16.0   # player ship hit radius

enum Phase { JET, DRAW, HOLD, BURNOUT, DONE }
var _phase: int = Phase.JET
var _t := 0.0
var _jet: FlameRibbon = null
var _ring: FlameRibbon = null
var _ring_pts := PackedVector2Array()
var _ring_cum := PackedFloat32Array()
var _ring_total := 0.0
var _jet_progress: float = 0.0   # 0→1 during JET phase (progressive reveal)
var _draw_progress: float = 0.0  # 0→1 fraction of ring that has been drawn (used by contact check)
var _player: Node2D = null
var visual_alpha: float = 1.0    # current visual alpha; 1 during JET/DRAW/HOLD, fades 1→0 during BURNOUT

func _ready() -> void:
	_jet = FlameRibbon.new()
	_jet.beam_width = beam_width
	_jet.head_enabled = false
	add_child(_jet)
	_ring = FlameRibbon.new()
	_ring.beam_width   = beam_width
	_ring.head_enabled = false
	add_child(_ring)
	_rebuild_ring_geom()
	_apply_alpha(1.0)
	restart()

## Restart the full jet → draw → hold → burnout cycle from the top.
func restart() -> void:
	_phase = Phase.JET
	_t = 0.0
	_jet_progress = 0.0
	_draw_progress = 0.0
	_apply_alpha(1.0)
	_ring.build_path(PackedVector2Array(), beam_width)
	_draw_jet(0.0)

func _rebuild_ring_geom() -> void:
	_ring_pts = PackedVector2Array()
	var sgn := -1.0 if ring_clockwise else 1.0
	for i in ring_segments + 1:
		var a := ring_start_angle + sgn * TAU * float(i) / float(ring_segments)
		_ring_pts.append(ring_center_offset + Vector2.from_angle(a) * ring_radius)
	_ring_cum = PackedFloat32Array()
	_ring_cum.resize(_ring_pts.size())
	_ring_cum[0] = 0.0
	for i in range(1, _ring_pts.size()):
		_ring_cum[i] = _ring_cum[i - 1] + _ring_pts[i].distance_to(_ring_pts[i - 1])
	_ring_total = _ring_cum[_ring_pts.size() - 1]

func _ring_start_point() -> Vector2:
	return ring_center_offset + Vector2.from_angle(ring_start_angle) * ring_radius

func _draw_jet(p: float = 1.0) -> void:
	if p < 0.001:
		_jet.build_path(PackedVector2Array(), beam_width)
		return
	var end := _ring_start_point()
	_jet.build_path(PackedVector2Array([Vector2.ZERO, end * clampf(p, 0.0, 1.0)]), beam_width)

## Partial ring path up to fraction p (0..1), with an interpolated tip so the head glides smoothly.
func _partial_ring(p: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if _ring_pts.size() < 2:
		return out
	var target := clampf(p, 0.0, 1.0) * _ring_total
	out.append(_ring_pts[0])
	for i in range(1, _ring_pts.size()):
		if _ring_cum[i] <= target:
			out.append(_ring_pts[i])
		else:
			var seg := _ring_cum[i] - _ring_cum[i - 1]
			var f := (target - _ring_cum[i - 1]) / maxf(0.0001, seg)
			out.append(_ring_pts[i - 1].lerp(_ring_pts[i], f))   # interpolated tip
			break
	return out

func _draw_ring(p: float) -> void:
	if p <= 0.001:
		_ring.build_path(PackedVector2Array(), beam_width)
		return
	_ring.build_path(_partial_ring(p), beam_width)

func _ease(p: float) -> float:
	# ease-in-out via pow on a smoothstep base; draw_ease=1 ≈ linear-ish, higher = stronger ease
	var s := smoothstep(0.0, 1.0, p)
	return pow(s, 1.0 / maxf(0.25, draw_ease)) if draw_ease < 1.0 else pow(s, draw_ease)

func _apply_alpha(a: float) -> void:
	visual_alpha = a
	for r: FlameRibbon in [_jet, _ring]:
		if r != null:
			r.tint_color = Color(tint_color.r, tint_color.g, tint_color.b, tint_color.a * a)
			r.intensity = intensity
			r.push_uniforms()

func _process(delta: float) -> void:
	_t += delta
	match _phase:
		Phase.JET:
			_jet_progress = clampf(_t / maxf(0.01, jet_duration), 0.0, 1.0)
			_draw_progress = 0.0
			_draw_jet(_jet_progress)
			if _t >= jet_duration:
				_phase = Phase.DRAW
				_t = 0.0
		Phase.DRAW:
			_draw_progress = _ease(clampf(_t / maxf(0.01, draw_duration), 0.0, 1.0))
			if jet_persists:
				_draw_jet()
			_draw_ring(_draw_progress)
			if _t >= draw_duration:
				_phase = Phase.HOLD
				_t = 0.0
				_draw_ring(1.0)
		Phase.HOLD:
			_draw_progress = 1.0
			if jet_persists:
				_draw_jet()
			_draw_ring(1.0)
			_ring.set_head_visible(head_parks_or_fades)
			if _t >= hold_duration:
				_phase = Phase.BURNOUT
				_t = 0.0
		Phase.BURNOUT:
			_draw_progress = 1.0
			if jet_persists:
				_draw_jet()
			_draw_ring(1.0)
			_ring.set_head_visible(head_parks_or_fades)
			_apply_alpha(1.0 - clampf(_t / maxf(0.01, burnout_duration), 0.0, 1.0))
			if _t >= burnout_duration:
				_phase = Phase.DONE
				_t = 0.0
		Phase.DONE:
			if auto_loop:
				restart()
	if contact_damage > 0 and _phase != Phase.DONE:
		_check_contact_damage()

func _check_contact_damage() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	var pp  := (_player as Node2D).global_position
	var hw  := beam_width * 0.5 + CONTACT_PAD
	# Jet segment (world space: node is top_level so local == world)
	var jet_p := _jet_progress if _phase == Phase.JET \
			else (1.0 if jet_persists and _phase in [Phase.DRAW, Phase.HOLD, Phase.BURNOUT] else 0.0)
	if jet_p > 0.001:
		var j_end := global_position + _ring_start_point() * jet_p
		if _seg_dist(pp, global_position, j_end) <= hw:
			GameManager.ship_take_damage(contact_damage)
			return
	# Ring arc — only the drawn portion (not the full circle)
	if _phase in [Phase.DRAW, Phase.HOLD, Phase.BURNOUT] and _draw_progress > 0.001:
		var rc   := global_position + ring_center_offset
		var dist := pp.distance_to(rc)
		if absf(dist - ring_radius) <= hw:
			# Check that the player's angle falls within the drawn arc
			var player_angle := (pp - rc).angle()
			var draw_sgn := -1.0 if ring_clockwise else 1.0
			var rel := fmod(draw_sgn * (player_angle - ring_start_angle), TAU)
			if rel < 0.0:
				rel += TAU
			if rel <= _draw_progress * TAU:
				GameManager.ship_take_damage(contact_damage)

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab   := b - a
	var len2 := ab.dot(ab)
	if len2 < 0.0001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0))
