extends Control

# =============================================================================
# Boss Death Cutscene FX  (shared by every boss via boss_fight.gd)
# -----------------------------------------------------------------------------
# A ~3.5s Mega-Man-X-style death sequence, procedural (no art assets yet):
#   1. Freeze + blink white/red + fire/smoke bursts
#   2. White beams radiate out, bursts intensify
#   3. Full-screen white-out + screen shake; boss disappears
#   4. Hold white, restore the shake, clean up → emit `finished`
# play(body_nodes, arena_rect, shake_node) runs the timeline; `finished` fires at
# the end so the caller can then show its victory screen.
# =============================================================================

signal finished

const DEATH_FREEZE_BLINK_T := 1.0   # phase 1: blink + first bursts
const DEATH_BEAMS_T        := 3.0   # phase 2: flashing light shafts (the main show)
const DEATH_WHITEOUT_T     := 0.7   # phase 3: white fills + shake
const DEATH_HOLD_T         := 0.3   # phase 4: hold full white, boss gone
const TOTAL_T := DEATH_FREEZE_BLINK_T + DEATH_BEAMS_T + DEATH_WHITEOUT_T + DEATH_HOLD_T   # = 5.0s

const BLINK_HZ        := 12.0
const BURST_RATE_MIN  := 4.0     # bursts/sec at the start
const BURST_RATE_MAX  := 22.0    # bursts/sec at peak (end of phase 2)
const SHAKE_MAX       := 14.0    # max jitter px

# Phase-2 light shafts: only a few visible at once, flashing at random angles. Each shaft is
# a triangle with its POINT at the centre (the source) widening out to the edge of the arena.
const MAX_BEAMS       := 4       # at most this many active at any moment (3-4 visible)
# Flash duration: a shaft is held for randf_range(MIN,MAX) × a time-based multiplier. The
# multiplier starts high (slow flashes) and falls at a CONSTANT rate per second — so over the
# long 3s beam phase it keeps speeding up and the final flashes are the fastest of all.
const BEAM_LIFE_MIN      := 0.10  # base flash duration range, seconds (the ×1.0 point)
const BEAM_LIFE_MAX      := 0.18
const BEAM_LIFE_START_X  := 2.0   # first flashes last this many × the base duration
const BEAM_RAMP_PER_SEC  := 0.77  # multiplier drops this much each second (constant ramp speed)
const BEAM_LIFE_MIN_X    := 0.35  # floor: fastest the flashes ever get
const BEAM_REACH      := 1.04    # extend a touch past the arena edge so the wide end clears it
const BEAM_WIDE_W_MIN := 26.0    # width at the OUTER (wide) end, randomized per spawn
const BEAM_WIDE_W_MAX := 60.0
const BEAM_COL_CORE   := Color(1.7, 1.45, 0.75, 1.0)  # bright (HDR) yellow at the centre source
const BEAM_COL_OUTER  := Color(1.4, 0.6, 0.08, 0.0)   # strong orange fading to transparent at the edge

var _body_nodes: Array = []
var _arena: Rect2 = Rect2()
var _shake_node: Node = null
var _shake_origin: Vector2 = Vector2.ZERO

var _t: float = 0.0
var _active: bool = false
var _burst_acc: float = 0.0
var _bursts: Array = []          # tracked burst nodes (freed on cleanup)
var _beams: Array = []           # [{poly, age, life}] active light shafts (freed on cleanup)
var _shared_beam_mat: CanvasItemMaterial = null   # additive blend, shared by all beams
var _white: ColorRect = null
var _body_hidden: bool = false
var _is_final: bool = true   # FINAL: hide body at the end. TRANSITION: restore it (boss lives on).
var _visual_offsets: Dictionary = {}   # body node -> texture_rect-local centre of its opaque pixels

func play(body_nodes: Array, arena_rect: Rect2, shake_node: Node, is_final: bool = true) -> void:
	_body_nodes = body_nodes.duplicate()
	_arena = arena_rect
	_shake_node = shake_node
	_is_final = is_final
	_measure_visual_offsets()   # find each body's true (opaque) centre, once
	if _shake_node != null and "position" in _shake_node:
		_shake_origin = _shake_node.position
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4000   # FX above the boss/projectiles
	z_as_relative = false
	# Full-screen white overlay (starts transparent; oversized so the shake never reveals an edge).
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0.0)
	_white.position = _arena.position - Vector2(60, 60)
	_white.size = _arena.size + Vector2(120, 120)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.z_index = 4001
	_white.z_as_relative = false
	add_child(_white)
	_t = 0.0
	_active = true

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta

	var p1 := DEATH_FREEZE_BLINK_T
	var p2 := p1 + DEATH_BEAMS_T
	var p3 := p2 + DEATH_WHITEOUT_T

	# Blink the body white↔red during phases 1-2.
	if _t < p2 and not _body_hidden:
		var s: float = 0.5 + 0.5 * sin(_t * BLINK_HZ * TAU)
		var col := Color(3.0, 0.3, 0.3).lerp(Color(3.0, 3.0, 3.0), s)
		for n in _body_nodes:
			if is_instance_valid(n):
				n.modulate = col

	# Bursts: rate ramps up across phases 1-2.
	if _t < p2:
		var ramp: float = clampf(_t / p2, 0.0, 1.0)
		var rate: float = lerpf(BURST_RATE_MIN, BURST_RATE_MAX, ramp)
		_burst_acc += delta * rate
		while _burst_acc >= 1.0:
			_burst_acc -= 1.0
			_spawn_burst(_random_body_point())

	# Phase 2: flickering triangular light shafts — only ~3-4 at once, each popping in
	# at a random angle for a fraction of a second, then replaced.
	if _t >= p1 and _t < p2:
		_tick_beams(delta, _t - p1)   # pass absolute seconds into phase 2 (drives the constant ramp)
	elif not _beams.is_empty():
		_clear_beams()   # phase 2 over → kill any lingering shaft

	# Phase 3: white-out + shake; hide the body under the flash.
	if _t >= p2 and _t < p3:
		var wp: float = clampf((_t - p2) / DEATH_WHITEOUT_T, 0.0, 1.0)
		_white.color.a = wp
		if _shake_node != null and "position" in _shake_node:
			var amp: float = SHAKE_MAX * wp
			_shake_node.position = _shake_origin + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		if wp >= 0.5 and not _body_hidden and _is_final:
			_hide_body()   # FINAL only — TRANSITION keeps the boss alive for Phase 2

	# Phase 4: hold full white, stop the shake, finish.
	if _t >= p3:
		_white.color.a = 1.0
		if _shake_node != null and "position" in _shake_node:
			_shake_node.position = _shake_origin
		if _t >= TOTAL_T:
			_finish()

# ── Phase-2 light shafts ──────────────────────────────────────────────────────
# `elapsed` = seconds into phase 2. Count ramps 2→MAX_BEAMS across the phase; flash duration
# shortens at a constant rate (see _spawn_beam), so the last flashes are the quickest.
func _tick_beams(delta: float, elapsed: float) -> void:
	# Age + cull expired shafts.
	var i := _beams.size() - 1
	while i >= 0:
		var b: Dictionary = _beams[i]
		b["age"] = float(b["age"]) + delta
		if float(b["age"]) >= float(b["life"]):
			if is_instance_valid(b["poly"]):
				(b["poly"] as Node).queue_free()
			_beams.remove_at(i)
		i -= 1
	# Keep ~target shafts alive; expired ones are instantly replaced at new random angles.
	var prog: float = clampf(elapsed / DEATH_BEAMS_T, 0.0, 1.0)
	var target: int = int(round(lerpf(2.0, float(MAX_BEAMS), prog)))
	while _beams.size() < target:
		_spawn_beam(randf() * TAU, elapsed)

# Spawn one triangular light shaft at `angle` radiating from the body centre.
# TODO: swap the Polygon2D for an animated sprite (same _spawn_beam entry point).
func _spawn_beam(angle: float, elapsed: float = 0.0) -> void:
	if _shared_beam_mat == null:
		_shared_beam_mat = CanvasItemMaterial.new()
		_shared_beam_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # overlapping shafts glow
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)
	var c := _body_center()
	var length := _edge_distance(c, dir) * BEAM_REACH   # reach the edge of the map
	var hw := randf_range(BEAM_WIDE_W_MIN, BEAM_WIDE_W_MAX) * 0.5   # half of the OUTER (wide) end
	var poly := Polygon2D.new()
	poly.position = c - global_position
	# Point at the centre (source), widening to the far end at the map edge.
	poly.polygon = PackedVector2Array([Vector2.ZERO, dir * length + perp * hw, dir * length - perp * hw])
	poly.vertex_colors = PackedColorArray([BEAM_COL_CORE, BEAM_COL_OUTER, BEAM_COL_OUTER])
	poly.material = _shared_beam_mat
	add_child(poly)
	# Constant-rate ramp: multiplier starts at BEAM_LIFE_START_X and drops BEAM_RAMP_PER_SEC/sec
	# (clamped at BEAM_LIFE_MIN_X), so the longer the phase runs the faster the flashes get.
	var mult: float = clampf(BEAM_LIFE_START_X - BEAM_RAMP_PER_SEC * elapsed, BEAM_LIFE_MIN_X, BEAM_LIFE_START_X)
	var life := randf_range(BEAM_LIFE_MIN, BEAM_LIFE_MAX) * mult
	_beams.append({"poly": poly, "age": 0.0, "life": life})

# Distance from `c` to the arena boundary along (normalized) `dir` — used as the shaft length.
func _edge_distance(c: Vector2, dir: Vector2) -> float:
	var t := INF
	if dir.x > 0.0001:    t = minf(t, (_arena.end.x - c.x) / dir.x)
	elif dir.x < -0.0001: t = minf(t, (_arena.position.x - c.x) / dir.x)
	if dir.y > 0.0001:    t = minf(t, (_arena.end.y - c.y) / dir.y)
	elif dir.y < -0.0001: t = minf(t, (_arena.position.y - c.y) / dir.y)
	if t == INF or t <= 0.0:
		return _arena.size.length()   # degenerate fallback
	return t

func _clear_beams() -> void:
	for b in _beams:
		if is_instance_valid(b["poly"]):
			(b["poly"] as Node).queue_free()
	_beams.clear()

# ── FX helpers ───────────────────────────────────────────────────────────────
# Spawn one fire/smoke puff at `pos` (global). Procedural for now.
# TODO: swap the visual for an animated sprite — pass a Texture2D and play it here.
func _spawn_burst(pos: Vector2) -> void:
	var b := _Burst.new()
	b.position = pos - global_position
	b.z_index = 4000
	b.z_as_relative = false
	add_child(b)
	_bursts.append(b)

# Measure, once, where each body node's opaque pixels actually sit inside its texture_rect.
# The result is a texture_rect-LOCAL point (so it survives the boss moving/rotating later).
# Sprites that fill their rect → centre = size*0.5 (identical to the old behaviour).
func _measure_visual_offsets() -> void:
	_visual_offsets.clear()
	for n in _body_nodes:
		if not (n is Control) or not ("texture_rect" in n):
			continue
		var tr: TextureRect = n.texture_rect
		if tr == null:
			continue
		var local := tr.size * 0.5   # fallback: geometric centre of the rect
		var tex: Texture2D = tr.texture
		if tex != null:
			var img := tex.get_image()
			if img != null:
				var used := img.get_used_rect()
				var isz := Vector2(img.get_size())
				if used.size.x > 0 and used.size.y > 0 and isz.x > 0.0 and isz.y > 0.0:
					var used_c := Vector2(used.position) + Vector2(used.size) * 0.5
					local = used_c * (tr.size / isz)   # image space → texture_rect-local (handles stretch)
		_visual_offsets[n] = local

func _random_body_point() -> Vector2:
	# A random point around one of the body nodes' visible centres (global space).
	for _try in 3:
		var n = _body_nodes[randi() % _body_nodes.size()] if not _body_nodes.is_empty() else null
		if is_instance_valid(n):
			var c := _node_center(n)
			var spread := _node_spread(n)
			return c + Vector2(randf_range(-spread.x, spread.x), randf_range(-spread.y, spread.y))
	return _body_center()

# Half-extent to scatter bursts over: opaque size if measured, else the rect size.
func _node_spread(n: Node) -> Vector2:
	if n is Control and "texture_rect" in n and (n as Control).texture_rect != null:
		var tr: TextureRect = (n as Control).texture_rect
		if _visual_offsets.has(n):
			# Roughly the opaque half-size around the centre (kept inside the rect).
			return Vector2(minf(_visual_offsets[n].x, tr.size.x - _visual_offsets[n].x),
						   minf(_visual_offsets[n].y, tr.size.y - _visual_offsets[n].y))
		return tr.size * 0.5
	if n is Control:
		return (n as Control).size * 0.5
	return Vector2(8, 8)

# True (visible) centre of one body node, in global space, using the live transform.
func _node_center(n: Node) -> Vector2:
	if n is Control and "texture_rect" in n and (n as Control).texture_rect != null and _visual_offsets.has(n):
		var tr: TextureRect = (n as Control).texture_rect
		return tr.get_global_transform() * _visual_offsets[n]
	if n is Control:
		return (n as Control).global_position + (n as Control).size * 0.5
	return _arena.get_center()

func _body_center() -> Vector2:
	var sum := Vector2.ZERO
	var cnt := 0
	for n in _body_nodes:
		if is_instance_valid(n):
			sum += _node_center(n)
			cnt += 1
	if cnt == 0:
		return _arena.get_center()
	return sum / float(cnt)

func _hide_body() -> void:
	_body_hidden = true
	for n in _body_nodes:
		if is_instance_valid(n):
			n.modulate = Color.WHITE
			n.visible = false

# TRANSITION end: undo the blink tint and leave the body visible (it lives on into Phase 2).
func _restore_body() -> void:
	for n in _body_nodes:
		if is_instance_valid(n):
			n.modulate = Color.WHITE
			n.visible = true

func _finish() -> void:
	_active = false
	if not _is_final:
		_restore_body()   # TRANSITION: clear the blink tint + keep the boss visible
	_clear_beams()
	for b in _bursts:
		if is_instance_valid(b):
			b.queue_free()
	_bursts.clear()
	if is_instance_valid(_white):
		_white.queue_free()
	finished.emit()

# ── Inner burst node (procedural fire flash + smoke puff) ─────────────────────
class _Burst extends Control:
	var _life := 0.0
	var _dur := 0.45
	var _smoke_off := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_smoke_off = Vector2(0, -28.0)

	func _process(delta: float) -> void:
		_life += delta
		queue_redraw()
		if _life >= _dur:
			queue_free()

	func _draw() -> void:
		var t: float = clampf(_life / _dur, 0.0, 1.0)
		# Fire flash: bright orange/yellow circle scaling up then fading.
		var fr: float = lerpf(4.0, 22.0, t)
		var fa: float = (1.0 - t)
		draw_circle(Vector2.ZERO, fr, Color(1.0, 0.75, 0.2, fa * 0.9))
		draw_circle(Vector2.ZERO, fr * 0.55, Color(1.0, 1.0, 0.7, fa))
		# Smoke puff: grey circle rising + fading.
		var sr: float = lerpf(6.0, 20.0, t)
		draw_circle(_smoke_off * t, sr, Color(0.5, 0.5, 0.5, (1.0 - t) * 0.5))
