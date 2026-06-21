extends Node2D
## Exact port of the Chromeleon boss orb's CHANNEL charge FX (`_ChannelFX` in boss_chromeleon.gd): a set of
## rainbow motes that orbit inward and CONVERGE onto the focus over the charge duration, fading + shrinking
## as they reach it (soft glow + core per mote). Additive blend. The Lasgun plays this at the muzzle as its
## pre-burst charge telegraph. Position it externally each frame (the muzzle moves with the ship).

# ── TUNABLES (ported values) ────────────────────────────────────────────────────
const MOTE_COUNT := 12
const RAD_RANGE  := Vector2(80.0, 150.0)
const SPIN_RANGE := Vector2(2.5, 5.0)
const SIZE_RANGE := Vector2(3.0, 6.0)
const MOTE_SCALE := 1.0
const MOTE_MULT  := 1.0

var _t := 0.0
var _dur := 1.0
var _active := false
var _motes: Array = []   # [{ang, rad, spin, size, hue}]

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	visible = false

## Begin a charge that converges over `dur` seconds (regenerates a fresh mote ring).
func start(dur: float) -> void:
	_dur = maxf(dur, 0.01)
	_t = 0.0
	_active = true
	visible = true
	_motes.clear()
	var n := int(round(float(MOTE_COUNT) * MOTE_MULT))
	for i in n:
		_motes.append({
			"ang":  randf() * TAU,
			"rad":  randf_range(RAD_RANGE.x, RAD_RANGE.y) * MOTE_SCALE,
			"spin": randf_range(SPIN_RANGE.x, SPIN_RANGE.y) * (1.0 if randf() < 0.5 else -1.0),
			"size": randf_range(SIZE_RANGE.x, SIZE_RANGE.y) * MOTE_SCALE,
			"hue":  randf(),
		})
	queue_redraw()

func stop() -> void:
	_active = false
	visible = false

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	if _t >= _dur:
		stop()   # converged + faded → done (the weapon fires now)
		return
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var p: float = clampf(_t / _dur, 0.0, 1.0)
	for m in _motes:
		var ang: float = float(m["ang"]) + float(m["spin"]) * _t
		var rad: float = float(m["rad"]) * (1.0 - p)             # converge inward
		var pos := Vector2(cos(ang), sin(ang)) * rad
		var a: float = 1.0 - p                                   # fade as they reach the focus
		var sz: float = float(m["size"]) * (1.0 - 0.5 * p)
		var col := Color.from_hsv(fposmod(float(m["hue"]) + _t * 0.5, 1.0), 0.85, 1.0)   # rainbow
		# Soft, blending edges: stacked falloff layers (additive) instead of one hard disc.
		draw_circle(pos, sz * 3.4, Color(col.r, col.g, col.b, a * 0.08))
		draw_circle(pos, sz * 2.4, Color(col.r, col.g, col.b, a * 0.14))
		draw_circle(pos, sz * 1.6, Color(col.r, col.g, col.b, a * 0.26))
		draw_circle(pos, sz * 1.0, Color(col.r, col.g, col.b, a * 0.5))
		draw_circle(pos, sz * 0.5, Color(1.0, 1.0, 1.0, a * 0.7))   # bright soft centre
