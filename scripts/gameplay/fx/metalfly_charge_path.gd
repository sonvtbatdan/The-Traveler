extends Node2D
## Metalfly Move 2 telegraph — the lane the boss is about to lunge down, drawn from the boss to the point it
## will end up at. A flat band `WIDTH` px across, bright red at the boss end fading to a dark red at the far
## end, with both long edges picked out by a highlight line so the lane's boundary is unmistakable (the
## player has to be able to tell, at a glance, whether they are standing inside it).
##
## Drawn in this node's own local space with the band running along +X, then rotated by `rotation` — so the
## gradient is a straight-line lerp along the lane no matter which way the boss is aiming. `draw_polygon()`
## interpolates the four corner colours across the two triangles it builds, which is the whole gradient; no
## shader, no gradient texture.
##
## Lives in world space under the Arena root (see arena_enemy.gd's `_setup_metalfly` for why it is not a
## child of the boss). While the boss is still winding up the lane TRACKS the player — `aim()` is called
## every frame, so a player who walks sideways drags the lane with them and has to actually break away
## rather than sidestep once. `lock()` freezes it the instant the boss commits, and the boss then flies down
## whatever it was pointing at at that moment.

const WIDTH        := 150.0    # full width of the lane, px
## Everything the lane draws is multiplied by this. The lane covers a big slice of the screen and the player
## has to be able to READ the field through it — at full strength it reads as a wall rather than a warning.
const OPACITY      := 0.8
const NEAR_COLOR   := Color(1.00, 0.24, 0.18, 0.60)   # bright red, at the boss
const FAR_COLOR    := Color(0.42, 0.03, 0.03, 0.34)   # dark red, at the far end
const EDGE_NEAR    := Color(1.00, 0.55, 0.42, 0.95)   # highlight along both long edges — near end
const EDGE_FAR     := Color(0.75, 0.10, 0.08, 0.55)   # ...and far end
const EDGE_W       := 3.0
const EDGE_GLOW_W  := 9.0     # soft wide pass under the crisp edge line
const EDGE_GLOW_A  := 0.22
const CAP_W        := 2.0     # thin line closing the far end of the lane
const FADE_IN      := 0.18    # seconds
const FADE_OUT     := 0.22
## ── Glow ── three progressively wider, fainter copies of the lane drawn UNDER it, so the light appears to
## bleed out past the edges instead of stopping at them. Additive would blow out to white over the bright
## near end; plain stacked alpha keeps the red.
const GLOW_LAYERS  := 3
const GLOW_SPREAD  := 0.30    # each layer is this much wider than the last, as a fraction of WIDTH
const GLOW_ALPHA   := 0.13    # alpha of the innermost glow layer; the outer ones fall off from it
## ── Blink ── two rates multiplied together: a slow breath plus a fast flicker. One rate alone reads as a
## mechanical pulse; the pair reads as something charging up.
const PULSE_HZ     := 3.2
const PULSE_AMOUNT := 0.22
const BLINK_HZ     := 9.0
const BLINK_AMOUNT := 0.16
## Once the boss commits, the lane stops breathing and snaps to a steady, BRIGHTER state — the change from
## "flickering" to "solid" is itself the tell that the dodge window has closed.
const LOCKED_BOOST := 1.25

var _length := 0.0
var _alpha := 0.0
var _target_alpha := 0.0
var _t := 0.0
var _locked := false   # true once the boss has committed and is flying down it — pulse stops

## Raises the lane: `dir` is a unit direction in world space, `length` how far down it the boss will go.
func set_beam(dir: Vector2, length: float) -> void:
	_length = maxf(length, 1.0)
	rotation = dir.angle()
	_target_alpha = 1.0
	_locked = false
	visible = true

## Re-aims a lane that is already up, without touching its fade or its locked state. Called every frame of
## the wind-up so the lane follows the player; `set_beam` would do the aiming too but would also re-arm the
## fade-in and clear `lock()`, so the two are deliberately separate calls.
func aim(dir: Vector2) -> void:
	if not _locked:
		rotation = dir.angle()

## Stop the wind-up pulse — the boss has committed and is now travelling down the lane.
func lock() -> void:
	_locked = true

## Fade the lane out; it hides itself once invisible.
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
	if _alpha <= 0.0 or _length <= 1.0:
		return
	# Breathing + flickering while the aim is still being telegraphed; both frozen and the whole lane
	# brightened once the boss commits, so the moment it goes steady is itself the "here it comes" tell.
	var pulse := LOCKED_BOOST
	if not _locked:
		var breath := 1.0 + PULSE_AMOUNT * sin(_t * PULSE_HZ * TAU)
		var flicker := 1.0 + BLINK_AMOUNT * sin(_t * BLINK_HZ * TAU)
		pulse = breath * flicker
	var a := _alpha * pulse * OPACITY
	var h := WIDTH * 0.5
	var near_a := Vector2(0.0, -h)
	var near_b := Vector2(0.0,  h)
	var far_a  := Vector2(_length, -h)
	var far_b  := Vector2(_length,  h)

	# Glow first (widest → narrowest), so the body of the lane lands on top of its own bleed.
	for i in range(GLOW_LAYERS, 0, -1):
		var gh := h * (1.0 + GLOW_SPREAD * float(i))
		var ga := a * GLOW_ALPHA / float(i)
		draw_polygon(
			PackedVector2Array([Vector2(0.0, -gh), Vector2(_length, -gh), Vector2(_length, gh), Vector2(0.0, gh)]),
			PackedColorArray([_mod(NEAR_COLOR, ga), _mod(FAR_COLOR, ga), _mod(FAR_COLOR, ga), _mod(NEAR_COLOR, ga)]))

	# Body of the lane: one quad, four corner colours -> a straight gradient down its length.
	draw_polygon(
		PackedVector2Array([near_a, far_a, far_b, near_b]),
		PackedColorArray([_mod(NEAR_COLOR, a), _mod(FAR_COLOR, a), _mod(FAR_COLOR, a), _mod(NEAR_COLOR, a)]))

	# Both long edges: a soft wide pass, then a crisp line on top. Each is drawn as its own gradient so the
	# boundary stays readable at the bright end without glaring at the dark one.
	for edge: Array in [[near_a, far_a], [near_b, far_b]]:
		_grad_line(edge[0], edge[1], EDGE_GLOW_W, a * EDGE_GLOW_A)
		_grad_line(edge[0], edge[1], EDGE_W, a)
	# Close the far end so the lane reads as a bounded strip rather than one running off forever.
	draw_line(far_a, far_b, _mod(EDGE_FAR, a), CAP_W)

## A straight line drawn as N short segments so it can carry the same near->far colour ramp the body has
## (draw_line takes one flat colour; draw_polyline's per-point colours apply to the JOINTS, not the run).
func _grad_line(from: Vector2, to: Vector2, width: float, alpha_mult: float) -> void:
	const STEPS := 12
	for i in STEPS:
		var t0 := float(i) / float(STEPS)
		var t1 := float(i + 1) / float(STEPS)
		var col := EDGE_NEAR.lerp(EDGE_FAR, (t0 + t1) * 0.5)
		draw_line(from.lerp(to, t0), from.lerp(to, t1), _mod(col, alpha_mult), width)

func _mod(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(c.a * a, 0.0, 1.0))
