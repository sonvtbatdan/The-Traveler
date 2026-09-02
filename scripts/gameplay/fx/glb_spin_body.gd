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
## Cap on the SubViewport RENDER resolution (px). A big body (the Volcanic boss authors ~800 px in Creep
## Edit) would otherwise allocate an ~1200² UPDATE_ALWAYS viewport re-rendering a 27 MB model every frame.
## Past this the render stays fixed-res and the Sprite2D is scaled up to the requested on-screen size —
## a top-down model that never gets bigger than ~half the screen doesn't need more texel detail than this.
const RENDER_CAP := 560

var _rig: RefCounted = null
var _vp: SubViewport = null
var _model: Node3D = null
var _pivot: Node3D = null
var _mount: Node3D = null   # authored mount angle; sits BETWEEN the spin pivot and the model — see setup()
var _sprite: Sprite2D = null
var _tumble: Node3D = null   # second spin axis, nested under the first — see setup()
var _spin_speed := 0.0     # rad/s about the view vertical (reads as an in-plane spin from a top-down camera)
var _tumble_speed := 0.0   # rad/s about the view horizontal (reads as end-over-end tumbling)
var _base_scale := Vector2.ONE   # Sprite2D scale at rest (>1 when the render was resolution-capped, see RENDER_CAP)
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
## `light_scale` (2026-09-02): multiplies every light + the ambient the shared rig adds. 1.0 = the rig's
## default (right for VIPER/Jaeger's dark-metal glbs). A model whose baked albedo already carries its own
## lighting — the Nautilus shell — blows out under the full rig, so it passes ~0.55.
func setup(glb_path: String, display_px: float, spin_rpm: float,
		tumble_rpm: float = 0.0, mount_rot: Vector3 = Vector3.ZERO, light_scale: float = 1.0) -> bool:
	_rig = GlbRigScript.new()
	_model = _rig.load_model(glb_path)
	if _model == null:
		push_warning("glb_spin_body: could not load " + glb_path)
		return false
	_spin_speed = deg_to_rad(spin_rpm * 360.0 / 60.0)
	_tumble_speed = deg_to_rad(tumble_rpm * 360.0 / 60.0)

	var side := int(round(display_px * VP_PAD))
	var render_side := mini(side, RENDER_CAP)   # allocate at most RENDER_CAP²; scale the Sprite2D to cover `side`
	_vp = SubViewport.new()
	_vp.size = Vector2i(render_side, render_side)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_rig.build_lighting(_vp)
	# Camera half-height stays the FULL `side` — the model keeps its `display_px` world size in a `side`-wide
	# view, just sampled into fewer texels. The Sprite2D scale below restores the on-screen size.
	_rig.make_camera(_vp, float(side) * 0.5)
	# Dim AFTER make_camera — it adds a headlamp of its own that build_lighting's pass wouldn't have seen.
	if not is_equal_approx(light_scale, 1.0):
		for c: Node in _vp.get_children():
			if c is Light3D:
				(c as Light3D).light_energy *= light_scale
			elif c is WorldEnvironment and (c as WorldEnvironment).environment != null:
				(c as WorldEnvironment).environment.ambient_light_energy *= light_scale

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
	if render_side < side:
		_base_scale = Vector2.ONE * (float(side) / float(render_side))   # capped render → scale up to `side`
		_sprite.scale = _base_scale
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)
	# Random start phase only for an axis that actually SPINS — so two cocoons on screen aren't in lockstep.
	# A non-spinning body (spin_rpm/tumble_rpm 0 — e.g. the Volcanic boss, which holds the exact orientation
	# authored in Creep Edit) must NOT be randomised, or it renders at a different pose than the editor shows.
	if not is_zero_approx(spin_rpm):
		_pivot.rotation.y = randf() * TAU
	if not is_zero_approx(tumble_rpm):
		_tumble.rotation.x = randf() * TAU
	_ready_ok = true
	return true

func is_ready() -> bool:
	return _ready_ok

## Re-aim the mount (the calibrated body orientation between the spin pivot and the model). `rot_editor` is
## in the same Z-up authoring space `setup()`'s `mount_rot` takes — used by the Volcanic boss to pitch the
## model on demand (Move 4). No-op until the model has loaded.
func set_mount_rot(rot_editor: Vector3) -> void:
	if _mount != null and _rig != null:
		_mount.basis = _rig.view_basis(rot_editor)

## Turn the body flat in the screen plane (about the view-vertical) to `yaw_rad`, independent of the mount
## angle and the idle spin. The Volcanic boss drives this from its heading so it turns to face the player
## while chasing. `_process` still ADDS the idle spin on top (0 for a non-spinner, so this just holds).
func set_yaw(yaw_rad: float) -> void:
	if _pivot != null:
		_pivot.rotation.y = yaw_rad

func get_yaw() -> float:
	return _pivot.rotation.y if _pivot != null else 0.0

## The LIVE mount basis (authored angle, plus whatever a move has pitched it to this frame). Callers that
## have to place an authored point ON the model — arena_enemy's `_glb_point_offset`, which turns a Creep
## Edit fire/thrust point into a canvas offset — need this exact transform, not the rest pose, or the point
## drifts off the body the moment a move re-aims it.
func get_mount_basis() -> Basis:
	return _mount.basis if _mount != null else Basis.IDENTITY

## The Sprite2D showing the SubViewport render — so a caller can tint / scale the whole body (Move 3's
## "descend to the terrain" darken + shrink).
func body_sprite() -> Sprite2D:
	return _sprite

## Sprite2D scale at rest — the baseline any temporary scale tween (Move 3's shrink) should multiply,
## since a resolution-capped render already carries a >1 scale here.
func base_scale() -> Vector2:
	return _base_scale

func _process(delta: float) -> void:
	if not _ready_ok:
		return
	_pivot.rotation.y += _spin_speed * delta
	_tumble.rotation.x += _tumble_speed * delta
