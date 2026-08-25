extends Node2D
## Metalfly Move 3 telegraph — the ring the boss gathers its brood inside while it winds up, and the
## concentric pulses of light it throws off the whole time. Raised by `begin()` when the wind-up starts and
## dropped by `release()` the moment the miniatures appear.
##
## Styled to match the Move 2 charge lane deliberately: the two are the same boss saying "something is about
## to come out of me", and they should read as one visual language. Rather than restate that language, every
## colour, the global opacity and both blink rates are taken straight off `metalfly_charge_path.gd` — retype
## them here and the two telegraphs drift apart the first time either is tuned.
##
## Unlike the lane, this is a CHILD of the boss. The lane marks a strip of GROUND the boss is about to leave
## (so it must stay put while the boss flies out of it); the ring marks the boss ITSELF, so it has to follow
## it — the wind-up holds station, but the enemy separation pass still shoves the boss around inside a busy
## field, and a ring left behind would read as a second object.
##
## Everything is drawn as ANNULI (`draw_arc` with a width), not as stacked discs: overlapping translucent
## discs accumulate alpha toward the middle, which turns a radial gradient into a dark blob.

const PathStyle := preload("res://scripts/gameplay/fx/metalfly_charge_path.gd")

const FILL_STEPS   := 16     # annuli making up the body of the disc — the radial gradient's resolution
const RIM_W        := 3.0    # crisp boundary line, same weight as the lane's edge highlight
const RIM_GLOW_W   := 9.0
const RIM_GLOW_A   := 0.22
const GLOW_LAYERS  := 3      # soft bleed OUTSIDE the rim, mirroring the lane's own glow stack
const GLOW_SPREAD  := 0.10   # each layer sits this much further out, as a fraction of the radius
const GLOW_ALPHA   := 0.13
## Segments per circle. 48 left visible corners on the outer rim at the radius Move 3 actually uses; this
## draws ~25 circles a frame, so the extra segments are cheap next to being able to see the polygon.
const ARC_POINTS   := 72
const FADE_IN      := 0.15
const FADE_OUT     := 0.18

# ── The radiating pulses ──────────────────────────────────────────────────────────────────────────────────
# PULSE_COUNT rings share one clock, evenly spread around it by their index, so there is always one leaving
# the middle and one arriving at the rim — a continuous flow rather than a burst every PULSE_PERIOD. Their
# radius comes from that phase, so no ring ever has to be created, tracked or freed.
const PULSE_COUNT  := 4
const PULSE_PERIOD := 0.85   # seconds for one ring to travel centre -> rim
const PULSE_W      := 4.0
const PULSE_ALPHA  := 0.85
const PULSE_FADE_IN  := 0.15   # fraction of the trip spent fading up, so a ring doesn't pop into existence
const PULSE_FADE_OUT := 0.45   # ...and the fraction over which it dissolves before reaching the rim

var _radius := 0.0
var _alpha := 0.0
var _target_alpha := 0.0
var _t := 0.0

## Raise the ring at `radius` px around the boss.
func begin(radius: float) -> void:
	_radius = maxf(radius, 1.0)
	_target_alpha = 1.0
	visible = true

## Fade it out; it hides itself once invisible.
func release() -> void:
	_target_alpha = 0.0

func _process(delta: float) -> void:
	_t += delta
	var rate := (1.0 / FADE_IN) if _target_alpha > _alpha else (1.0 / FADE_OUT)
	_alpha = move_toward(_alpha, _target_alpha, rate * delta)
	if _alpha <= 0.0:
		visible = false
		return
	queue_redraw()

func _draw() -> void:
	if _alpha <= 0.0 or _radius <= 1.0:
		return
	# Same breath x flicker the lane uses while it is still telegraphing — this one never locks, it just
	# ends, so it keeps flickering for its whole life.
	var breath := 1.0 + PathStyle.PULSE_AMOUNT * sin(_t * PathStyle.PULSE_HZ * TAU)
	var flicker := 1.0 + PathStyle.BLINK_AMOUNT * sin(_t * PathStyle.BLINK_HZ * TAU)
	var a := _alpha * breath * flicker * PathStyle.OPACITY

	# Soft bleed outside the rim (widest first, so nothing is drawn over the crisp edge later).
	for i in range(GLOW_LAYERS, 0, -1):
		var gr := _radius * (1.0 + GLOW_SPREAD * float(i))
		draw_arc(Vector2.ZERO, gr, 0.0, TAU, ARC_POINTS,
			_mod(PathStyle.FAR_COLOR, a * GLOW_ALPHA / float(i)), _radius * GLOW_SPREAD)

	# Body: annuli from the middle out, bright at the centre fading to the rim — the lane's near->far ramp
	# turned radial.
	var step := _radius / float(FILL_STEPS)
	for i in FILL_STEPS:
		var f := (float(i) + 0.5) / float(FILL_STEPS)
		var col: Color = PathStyle.NEAR_COLOR.lerp(PathStyle.FAR_COLOR, f)
		draw_arc(Vector2.ZERO, step * (float(i) + 0.5), 0.0, TAU, ARC_POINTS, _mod(col, a), step + 1.0)

	# The radiating pulses.
	for k in PULSE_COUNT:
		var phase := fmod(_t / PULSE_PERIOD + float(k) / float(PULSE_COUNT), 1.0)
		var pa := a * PULSE_ALPHA * _pulse_envelope(phase)
		if pa <= 0.001:
			continue
		draw_arc(Vector2.ZERO, _radius * phase, 0.0, TAU, ARC_POINTS,
			_mod(PathStyle.EDGE_NEAR, pa), PULSE_W)

	# Rim last, on top of everything, so the boundary stays unmistakable.
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, ARC_POINTS, _mod(PathStyle.EDGE_FAR, a * RIM_GLOW_A), RIM_GLOW_W)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, ARC_POINTS, _mod(PathStyle.EDGE_NEAR, a), RIM_W)

## Brightness of a pulse at `phase` (0 = centre, 1 = rim): up over the first stretch, down over the last.
## Without the ramps a ring would appear at full strength on top of the boss and vanish at the rim, both of
## which read as a glitch rather than as light travelling.
func _pulse_envelope(phase: float) -> float:
	if phase < PULSE_FADE_IN:
		return phase / PULSE_FADE_IN
	if phase > 1.0 - PULSE_FADE_OUT:
		return maxf(0.0, (1.0 - phase) / PULSE_FADE_OUT)
	return 1.0

func _mod(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(c.a * a, 0.0, 1.0))
