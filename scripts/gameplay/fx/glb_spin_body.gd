extends Node2D
## Generic world-space 3D body for an arena enemy: one .glb rendered top-down into a SubViewport, shown on a
## Sprite2D centred on this node, spinning about its own vertical axis. No skeleton, no posing — for models
## that are a single static mesh. (A rigged body that has to be POSED every frame is a different job; see
## metalfly_rig.gd, which drives 46 bones by hand.)
##
## Built for the Metalfly boss's Phase 1 cocoon (`assets/map/electric/boss/Cocoon.glb` — 9,204 verts, zero
## bones, zero animations), but nothing here is Metalfly-specific: `setup()` takes any glb path.
##
## Framing comes from glb_topdown_rig.gd, the same shared convention every other live 3D thing in the arena
## uses (VIPER, Yari-Jeager, the Metalfly rig): 1 world unit = 1 px, world X = screen X, world Z = screen Y,
## orthographic camera looking straight down -Y. That is what makes `display_px` mean actual on-screen
## pixels here rather than an arbitrary model-space number.

const GlbRigScript := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd")

## Viewport side = display_px x this. Raised from 1.25 when the second spin axis went in: `center_and_fit`
## sizes the model by its HORIZONTAL (XZ) footprint, so a tumble swings its vertical extent into that plane
## and a body taller than it is wide would clip against the frame at the halfway point of every roll.
const VP_PAD := 1.5

var _rig: RefCounted = null
var _vp: SubViewport = null
var _model: Node3D = null
var _pivot: Node3D = null
var _mount: Node3D = null   # authored mount angle; sits BETWEEN the spin pivot and the model — see setup()
var _sprite: Sprite2D = null
var _tumble: Node3D = null   # second spin axis, nested under the first — see setup()
var _spin_speed := 0.0     # rad/s about the view vertical (reads as an in-plane spin from a top-down camera)
var _tumble_speed := 0.0   # rad/s about the view horizontal (reads as end-over-end tumbling)
var _ready_ok := false

## Loads `glb_path`, fits it to `display_px` on screen and spins it on TWO axes.
##
## The camera looks straight down the view Y axis, so `spin_rpm` (about Y) reads as a flat in-plane spin —
## the body turning like a dial, with the same silhouette throughout. `tumble_rpm` (about the view X axis)
## is what actually rolls the body end over end and shows its other faces. One axis alone looks like a
## rotating picture rather than a rotating object, which is why a lone Y spin reads as "it only turns one
## way". Give the two DIFFERENT rates or they compose into a single fixed axis and the tumble disappears.
##
## `mount_rot` is the angle authored in Creep Edit, in that editor's Z-up space (arena_enemy.gd's
## `_creep_mount_rot`); Vector3.ZERO means "as the model ships". Returns false if the model can't be loaded,
## so the caller can fall back to a flat sprite.
func setup(glb_path: String, display_px: float, spin_rpm: float,
		tumble_rpm: float = 0.0, mount_rot: Vector3 = Vector3.ZERO) -> bool:
	_rig = GlbRigScript.new()
	_model = _rig.load_model(glb_path)
	if _model == null:
		push_warning("glb_spin_body: could not load " + glb_path)
		return false
	_spin_speed = deg_to_rad(spin_rpm * 360.0 / 60.0)
	_tumble_speed = deg_to_rad(tumble_rpm * 360.0 / 60.0)

	var side := int(round(display_px * VP_PAD))
	_vp = SubViewport.new()
	_vp.size = Vector2i(side, side)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_rig.build_lighting(_vp)
	_rig.make_camera(_vp, float(side) * 0.5)

	# The model is centred on its own AABB by center_and_fit, so parenting it to a pivot at the origin makes
	# the spin turn it about its own middle rather than swinging it around a point beside itself.
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	# The mount angle gets its OWN node rather than being written onto the model: center_and_fit bakes the
	# centring and fit scale straight into `_model.transform`, so setting a basis there would throw the
	# scale away. Between the pivot and the model, so the spin still turns the calibrated body.
	# Each spin axis gets its own node, nested. Accumulating two angles onto ONE node's Euler would let them
	# interact (the second axis rides the first, so the tumble would wander); nested nodes keep each axis
	# turning at its own fixed rate in its own parent's frame.
	_tumble = Node3D.new()
	_pivot.add_child(_tumble)
	_mount = Node3D.new()
	_mount.basis = _rig.view_basis(mount_rot)
	_tumble.add_child(_mount)
	_mount.add_child(_model)
	_rig.center_and_fit(_model, display_px)

	_sprite = Sprite2D.new()
	_sprite.texture = _vp.get_texture()
	add_child(_sprite)
	_pivot.rotation.y = randf() * TAU    # so two of these on screen at once aren't in lockstep
	_tumble.rotation.x = randf() * TAU
	_ready_ok = true
	return true

func is_ready() -> bool:
	return _ready_ok

func _process(delta: float) -> void:
	if not _ready_ok:
		return
	_pivot.rotation.y += _spin_speed * delta
	_tumble.rotation.x += _tumble_speed * delta
