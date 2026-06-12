extends "res://scripts/gameplay/enemy_base.gd"

## Swarm member — one bead in a follow-the-leader flock (orchestrated by enemy_swarm_flock.gd).
##
## FORMATION is flock-driven: the flock places every member along one shared track each frame via
## set_track_pose() (single-file conga → circle), so they string evenly around the ring.
##
## When the flock launches it from the 6 o'clock point, it captures the player's position AT THAT
## MOMENT and dashes straight at that fixed spot — AIM-ONCE, it does NOT keep tracking the player
## (dodge after it commits and it flies past where you were).
##
## HP 20; explodes on contact with the player only (10 damage).

# ── Tunable constants (Swarm member) ──────────────────────────────────────────
const SW_HP: float = 20.0
const SW_XP: int = 4
const SW_CONTACT_DMG: int = 10
const SW_ZOOM_SPEED: float = 700.0    # dive (dash) speed
const SW_CULL: float = 800.0          # despawn once it strays this far beyond the play area

# DEBUG (temporary): draw a yellow arrow showing the path direction the formation computed at this bead
# (the raw tangent, BEFORE any sprite-facing offset). Flip to false to hide. Compare arrow vs the nose:
#   • arrow points along the line but the nose doesn't → sprite-forward offset is wrong (fix the +90° once)
#   • the arrow ITSELF points randomly → the direction math is wrong
const DEBUG_DIR_ARROWS := false

enum Phase { FOLLOW, ZOOM }
var _phase: int = Phase.FOLLOW
var _heading: float = 0.0
var _dbg_dir: Vector2 = Vector2.ZERO   # world-space path tangent handed in by the formation (debug only)

func _configure() -> void:
	hp_max = SW_HP
	xp_reward = SW_XP
	contact_damage = SW_CONTACT_DMG
	contact_explodes = true
	contact_active = false   # no contact while forming/holding — only once it dives
	body_color = Color(0.3, 0.95, 0.95)   # cyan
	shape_kind = "triangle"

## Flock calls this every frame during formation to place the member along the shared track. `path_dir`
## (optional) is the raw world-space tangent of the path here — kept only to draw the debug arrow.
func set_track_pose(pos: Vector2, facing: float, path_dir: Vector2 = Vector2.ZERO) -> void:
	position = pos - size * 0.5
	rotation = facing
	_dbg_dir = path_dir
	if DEBUG_DIR_ARROWS:
		queue_redraw()   # rotation/position alone don't redraw; force it so the arrow stays current

func is_diving() -> bool:
	return _phase == Phase.ZOOM

## Flock calls this (one-by-one, from the 6 o'clock point) to launch the dive.
func begin_zoom() -> void:
	if _dead or _phase == Phase.ZOOM:
		return
	_phase = Phase.ZOOM
	contact_active = true
	var target: Vector2 = _mgr.ship_center()    # captured ONCE, at the moment of firing
	_heading = (target - center()).angle()      # aim-once; straight dash, no continuous tracking

func _tick(delta: float) -> void:
	if _phase != Phase.ZOOM:
		return   # FOLLOW: the flock owns our position
	position += Vector2.from_angle(_heading) * SW_ZOOM_SPEED * delta
	rotation = _heading + PI * 0.5
	var screen: Vector2 = _mgr.screen_size()
	var c := center()
	if c.x < -SW_CULL or c.x > screen.x + SW_CULL or c.y < -SW_CULL or c.y > screen.y + SW_CULL:
		despawn()

## DEBUG arrow: shows the path direction the FORMATION computed at this bead (_dbg_dir, world-space),
## independent of the sprite's facing. The node is rotated by `rotation`, so convert the world dir to
## local before drawing. Yellow shaft + arrowhead.
func _draw() -> void:
	super()   # the triangle body + HP bar
	if not DEBUG_DIR_ARROWS or _phase == Phase.ZOOM or _dbg_dir.length() < 0.01:
		return
	var c := size * 0.5
	var ln := size.x * 1.2
	var v := (_dbg_dir.normalized() * ln).rotated(-rotation)   # world → local (cancel the node rotation)
	var tip := c + v
	var col := Color(1.0, 0.95, 0.1)
	draw_line(c, tip, col, 2.0)
	var back := -v.normalized() * (ln * 0.3)
	var side := Vector2(-v.y, v.x).normalized() * (ln * 0.16)
	draw_line(tip, tip + back + side, col, 2.0)
	draw_line(tip, tip + back - side, col, 2.0)
