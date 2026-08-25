extends Node2D
## Live 3D Metalfly boss body — `assets/map/electric/boss/metalfly.glb` rendered top-down into a SubViewport
## and posed EVERY FRAME FROM CODE. There is no AnimationPlayer here on purpose: the glb ships a rig
## (UniRigArmature, 46 bones) and ZERO animation clips, so every motion below is procedural.
##
## Why procedural rather than baking clips in Blender: the wing beat has to change rate on demand (a slow
## cruise flap during Move 1, a hard 9 Hz buzz while winding up Move 2, then dead-stop wings during the
## lunge). A baked clip would need a cross-fade per rate; one sine driven by `_flap_hz` covers all three and
## the antennae/legs/abdomen ride the same clock at their own phase offsets.
##
## ── Bone map ────────────────────────────────────────────────────────────────────────────────────────────
## UniRig auto-named every bone `Bone_NNN`, so the names carry no anatomy. The map below was derived from
## the bones' REST WORLD POSITIONS (mesh is Y-up, 3.10 x 1.70 x 0.89 units: +X/-X = wings, +Z = head,
## -Z = abdomen, -Y = legs) and then each candidate was measured by how far it actually moves SKINNED
## VERTICES — bone-tip travel lies when a stubby bone drives a big piece of mesh, and vice versa. Peak
## vertex displacement, in model units (the model is 1.70 tall):
##
##   wings    Bone_023/Bone_025  flap ±45°  -> 1.127   (48% of all verts move) — reads at any size
##   forewing Bone_017/Bone_021  flap  30°  -> 0.480   (46%)                   — secondary, lagged
##   antennae Bone_034/Bone_039  sway  12°  -> 0.220   (7%)
##   head     Bone_027           tilt  15°  -> 0.267   (13%)
##   MOUTH    Bone_041/043/045   rot   35°  -> 0.084   (3.7%)  <-- vestigial, see MOUTH note below
##
## MOUTH note: the auto-rig gave the mouth three bones ~0.02 units long, so ROTATING them is invisible at
## the size this boss draws (0.084 units ≈ 4 px at DISPLAY_PX). "Miệng mở rộng" therefore combines four
## things — mandibles PUSHED apart (translation, not rotation), the mouth cluster SCALED up, the lower jaw
## dropped, and the head tilted back — measured together at 0.308 units over 20% of the mesh (~33 px at
## DISPLAY_PX), which does read. Rotation alone was tried first and measured; it does not.
##
## ── Rotating a bone about a MODEL axis ──────────────────────────────────────────────────────────────────
## Godot's bone pose REPLACES the rest transform (it is not additive), and pose rotation is expressed in the
## PARENT's space. A naive `set_bone_pose_rotation(b, Quaternion(axis, ang))` therefore throws the rest pose
## away and bends the bone about a local axis that, on a UniRig skeleton, points in an arbitrary direction —
## on the legs, local X runs ALONG the bone, so a 30° rotation about it moved the chain tip 0.034 units
## (i.e. nothing). `_pose_rot()` below composes onto the rest and converts the axis out of model space, so
## "flap about the body's long axis" is written as exactly that. Verified symmetric: at +45° both wing tips
## sit at y 1.750, x ±0.539; at 0° the pose reproduces the rest pose bit-exact (drift 0.0).
##
## Coordinate convention comes from glb_topdown_rig.gd: 1 world unit = 1 px, world X = screen X,
## world Z = screen Y (down). The model's head is at +Z, i.e. it faces screen-DOWN unrotated, which is why
## `set_heading()` yaws by `PI/2 - angle`.

const GlbRigScript := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd")

const GLB_PATH   := "res://assets/map/electric/boss/metalfly.glb"
const DISPLAY_PX := 180.0   # fitted XZ-footprint diagonal; the wingspan lands at ~173 px of that
const VP_PAD     := 1.7     # viewport side = DISPLAY_PX x this — headroom for wings raised out of the footprint

# ── Bones (see the anatomy table in the file header) ──────────────────────────────────────────────────────
const B_WING_R  := "Bone_023"   # main wing root, right (+X)
const B_WING_L  := "Bone_025"
const B_FORE_R  := "Bone_017"   # forewing / arm, right — trails the main wing
const B_FORE_L  := "Bone_021"
const B_ANT_R   := "Bone_034"   # antenna root, right
const B_ANT_L   := "Bone_039"
const B_LEG_R   := "Bone_009"
const B_LEG_L   := "Bone_013"
const B_MAND_R  := "Bone_043"   # mandible, right
const B_MAND_L  := "Bone_041"
const B_JAW     := "Bone_045"   # lower jaw / proboscis
const B_MOUTH   := "Bone_028"   # the whole mouth cluster (parent of all three above)
const B_HEAD    := "Bone_027"
const B_ABDOMEN := "Bone_005"

# Model-space axes (the mesh is authored Y-up with the head at +Z — see header).
const AX_LONG := Vector3(0.0, 0.0, 1.0)   # body long axis: wings hinge about this
const AX_UP   := Vector3(0.0, 1.0, 0.0)
const AX_SIDE := Vector3(1.0, 0.0, 0.0)

# ── Wing beat ────────────────────────────────────────────────────────────────────────────────────────────
# The stroke is asymmetric on purpose: a real wing beat rises further above the body than it drops below it,
# and the range below is the one that was measured (+45° / -35°) rather than a symmetric guess.
const FLAP_MID_DEG  := 5.0
const FLAP_AMP_DEG  := 40.0
const FLAP_HZ_SLOW  := 2.2    # Move 1 cruise
const FLAP_HZ_FAST  := 9.0    # Move 2 wind-up buzz
const FLAP_HZ_LERP  := 7.0    # how fast the beat rate eases between the two (no visual snap)
const FLAP_SETTLE   := 6.0    # rad/s the wings ease back to rest once the beat stops (Move 2 lunge)
# The forewing pair copies the main beat at a fraction of the amplitude, a beat-fraction behind it. Both
# numbers are what make the two pairs read as ONE insect rather than four independent flaps.
const FORE_AMP_FRAC := 0.45
const FORE_LAG      := 0.22   # in beat cycles

# ── Idle life (runs at every flap rate, including "stopped") ─────────────────────────────────────────────
const ANT_AMP_DEG  := 11.0
const ANT_HZ       := 0.62
const ANT_PHASE_R  := 0.0     # the two antennae are deliberately out of phase — synced ones read as a prop
const ANT_PHASE_L  := 2.1
const LEG_AMP_DEG  := 7.0
const LEG_HZ       := 0.45
const ABDOMEN_AMP_DEG := 4.0  # tiny counter-sway against the wing beat, at half its rate

# ── Mouth gape (Move 2) — every component measured, see the MOUTH note in the header ─────────────────────
const MOUTH_MAND_PUSH  := 0.13   # model units the mandibles translate apart
const MOUTH_CLUSTER_UP := 1.55   # mouth cluster scales 1.0 -> this
const MOUTH_JAW_DEG    := 55.0   # lower jaw drops
const MOUTH_HEAD_DEG   := 22.0   # head tilts back, so the gape faces the player
const MOUTH_OPEN_RATE  := 4.0    # per second, 0 -> 1
const MOUTH_SHUT_RATE  := 9.0    # snaps shut faster than it opens

var _rig: RefCounted = null
var _vp: SubViewport = null
var _model: Node3D = null
var _carrier: Node3D = null      # holds the heading yaw; the model's own transform is just the fit
var _skel: Skeleton3D = null
var _sprite: Sprite2D = null
var _ready_ok := false

var _bone: Dictionary = {}           # bone name -> index (-1 if this rig is missing it)
var _rest_rot: Dictionary = {}       # bone name -> rest Quaternion
var _rest_pos: Dictionary = {}       # bone name -> rest origin (parent space)
var _parent_basis: Dictionary = {}   # bone name -> parent's GLOBAL REST basis, for the model-axis conversion
var _tip: Dictionary = {}            # bone name -> chain-tip bone index (wing root -> wing tip)

var _t := 0.0
var _flap_phase := 0.0           # advanced by _flap_hz, never by raw _t — so a rate change doesn't jump
var _flap_hz := FLAP_HZ_SLOW
var _flap_hz_target := FLAP_HZ_SLOW
var _flapping := true
var _flap_blend := 1.0           # 1 = beating, eases to 0 when the beat stops so the wings settle to rest
var _mouth := 0.0                # 0 shut .. 1 gaping
var _mouth_target := 0.0
var _heading := 0.0              # 2D direction the model faces (radians, 0 = screen right)
var _mount_basis := Basis.IDENTITY   # authored mount angle from Creep Edit; identity = as the model ships

## Builds the SubViewport, loads and fits the model, and caches every bone's rest pose. `mount_rot` is the
## angle authored for this body in Creep Edit, in that editor's Z-up space (arena_enemy.gd's
## `_creep_mount_rot`); Vector3.ZERO means "as the model ships", which is the orientation verified in the
## arena — so an untouched install renders exactly as before this was added. Returns false if the glb is
## missing/unloadable, which is the caller's cue to fall back to its flat sprite.
func setup(mount_rot: Vector3 = Vector3.ZERO, display_px: float = DISPLAY_PX) -> bool:
	_rig = GlbRigScript.new()
	_model = _rig.load_model(GLB_PATH)
	if _model == null:
		push_warning("metalfly_rig: could not load " + GLB_PATH)
		return false

	var side := int(round(display_px * VP_PAD))
	_vp = SubViewport.new()
	_vp.size = Vector2i(side, side)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_rig.build_lighting(_vp)
	_rig.make_camera(_vp, float(side) * 0.5)

	_carrier = Node3D.new()
	_vp.add_child(_carrier)
	_carrier.add_child(_model)
	_rig.center_and_fit(_model, display_px)
	_mount_basis = _rig.view_basis(mount_rot)

	_skel = _find_skeleton(_model)
	if _skel == null:
		push_warning("metalfly_rig: no Skeleton3D in " + GLB_PATH)
		return false
	_cache_bones()

	_sprite = Sprite2D.new()
	_sprite.texture = _vp.get_texture()
	add_child(_sprite)

	_flap_phase = randf() * TAU
	_ready_ok = true
	return true

func is_ready() -> bool:
	return _ready_ok

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c: Node in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null

## Rest pose of every bone this rig drives. Cached once: `_pose_rot`/`_pose_move` need the rest values on
## every frame, and re-reading them from an already-POSED skeleton would compound (the pose overwrites the
## rest, so frame 2 would read frame 1's pose as its "rest" and the model would walk away from itself).
func _cache_bones() -> void:
	for bname: String in [B_WING_R, B_WING_L, B_FORE_R, B_FORE_L, B_ANT_R, B_ANT_L,
			B_LEG_R, B_LEG_L, B_MAND_R, B_MAND_L, B_JAW, B_MOUTH, B_HEAD, B_ABDOMEN]:
		var i := _skel.find_bone(bname)
		_bone[bname] = i
		if i < 0:
			push_warning("metalfly_rig: bone not found: " + bname)
			continue
		_rest_rot[bname] = _skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_rest_pos[bname] = _skel.get_bone_rest(i).origin
		var par := _skel.get_bone_parent(i)
		_parent_basis[bname] = Basis.IDENTITY if par < 0 else _skel.get_bone_global_rest(par).basis
		_tip[bname] = _chain_tip(i)

## Last bone of the chain starting at `b` (wing root -> wing tip). Cached at setup — the skeleton's parent
## table never changes, and this is an O(bones) scan per level.
func _chain_tip(b: int) -> int:
	var cur := b
	while true:
		var kid := -1
		for i in _skel.get_bone_count():
			if _skel.get_bone_parent(i) == cur:
				kid = i
				break
		if kid < 0:
			return cur
		cur = kid
	return cur

# ── Pose primitives ──────────────────────────────────────────────────────────────────────────────────────

## Rotate `bname` by `ang` about MODEL-space `axis`, composed on top of its rest rotation. See the header
## for why neither half of that sentence is optional.
func _pose_rot(bname: String, axis: Vector3, ang: float) -> void:
	var i: int = _bone.get(bname, -1)
	if i < 0:
		return
	var local_axis: Vector3 = ((_parent_basis[bname] as Basis).inverse() * axis).normalized()
	_skel.set_bone_pose_rotation(i, Quaternion(local_axis, ang) * (_rest_rot[bname] as Quaternion))

## Translate `bname` by `dist` along MODEL-space `axis`, from its rest position. The mouth needs this: its
## bones are far too short for rotation to move any mesh (header, MOUTH note).
func _pose_move(bname: String, axis: Vector3, dist: float) -> void:
	var i: int = _bone.get(bname, -1)
	if i < 0:
		return
	var off: Vector3 = (_parent_basis[bname] as Basis).inverse() * (axis.normalized() * dist)
	_skel.set_bone_pose_position(i, (_rest_pos[bname] as Vector3) + off)

func _pose_scale(bname: String, s: float) -> void:
	var i: int = _bone.get(bname, -1)
	if i >= 0:
		_skel.set_bone_pose_scale(i, Vector3.ONE * s)

# ── Public control surface (the boss state machine drives these) ─────────────────────────────────────────

## "slow" = Move 1 cruise, "fast" = Move 2 wind-up, "none" = wings held still (the Move 2 lunge). Stopping
## eases the wings back to rest over ~1/FLAP_SETTLE s rather than freezing them mid-stroke.
func set_flap(mode: String) -> void:
	match mode:
		"fast":
			_flapping = true
			_flap_hz_target = FLAP_HZ_FAST
		"none":
			_flapping = false
		_:
			_flapping = true
			_flap_hz_target = FLAP_HZ_SLOW

func set_mouth_open(open: bool) -> void:
	_mouth_target = 1.0 if open else 0.0

## `angle` is the ordinary 2D direction the boss is travelling/facing (0 = screen right), NOT the enemy's
## `_facing` (which is that + PI/2 — "sprite north"). Callers pass `_facing - PI/2`.
func set_heading(angle: float) -> void:
	_heading = angle

## World positions of the two main wing tips — Move 1 fires one projectile from each. Read from the LIVE
## posed skeleton, so the muzzles rise and fall with the beat instead of sitting at a fixed offset.
func wing_muzzles() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not _ready_ok:
		return out
	for bname: String in [B_WING_R, B_WING_L]:
		var tip: int = _tip.get(bname, -1)
		if tip < 0:
			continue
		# carrier (yaw) * model (centering + fit scale) * bone -> viewport space, where X = screen X and
		# Z = screen Y (glb_topdown_rig.gd's convention). The Sprite2D is centred on this node's origin, so
		# that pair IS the local 2D offset.
		var p: Vector3 = _carrier.transform * (_model.transform * _skel.get_bone_global_pose(tip).origin)
		out.append(global_position + Vector2(p.x, p.z))
	return out

# ── Per-frame pose ───────────────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _ready_ok:
		return
	_t += delta
	# Advance the beat by its CURRENT rate, and ease the rate itself — phase stays continuous across a rate
	# change, so slow -> fast spins up like a real wing instead of teleporting to a new point in the stroke.
	_flap_hz = lerpf(_flap_hz, _flap_hz_target, clampf(FLAP_HZ_LERP * delta, 0.0, 1.0))
	if _flapping:
		_flap_phase += _flap_hz * TAU * delta
		_flap_blend = minf(1.0, _flap_blend + FLAP_SETTLE * delta)
	else:
		_flap_blend = maxf(0.0, _flap_blend - FLAP_SETTLE * delta)
	var rate := MOUTH_OPEN_RATE if _mouth_target > _mouth else MOUTH_SHUT_RATE
	_mouth = move_toward(_mouth, _mouth_target, rate * delta)

	_pose_wings()
	_pose_idle()
	_pose_mouth()
	_skel.force_update_all_bone_transforms()
	# Head at +Z renders toward screen-DOWN (angle +PI/2), so this yaw takes it to `_heading`. The authored
	# mount angle is applied FIRST (innermost): it corrects how the model sits on its own axes, which is a
	# property of the asset, while the yaw is which way the boss happens to be flying this frame. Composed
	# the other way round, dialling a mount angle would swing the whole travel direction instead.
	_carrier.basis = Basis(Vector3.UP, PI * 0.5 - _heading) * _mount_basis

func _pose_wings() -> void:
	var up := deg_to_rad(FLAP_MID_DEG + FLAP_AMP_DEG * sin(_flap_phase)) * _flap_blend
	# Mirrored: rotating about +Z lifts the +X wing and drops the -X one, so the left wing takes -up.
	_pose_rot(B_WING_R, AX_LONG,  up)
	_pose_rot(B_WING_L, AX_LONG, -up)
	var fore := deg_to_rad(FLAP_MID_DEG + FLAP_AMP_DEG * sin(_flap_phase - FORE_LAG * TAU)) \
			* FORE_AMP_FRAC * _flap_blend
	_pose_rot(B_FORE_R, AX_LONG,  fore)
	_pose_rot(B_FORE_L, AX_LONG, -fore)

## Antennae, legs and abdomen. These run off `_t`, NOT the beat clock — they must keep living while the
## wings are held still through the Move 2 lunge, or the boss reads as a dead prop mid-charge.
func _pose_idle() -> void:
	var ar := deg_to_rad(ANT_AMP_DEG * sin(_t * ANT_HZ * TAU + ANT_PHASE_R))
	var al := deg_to_rad(ANT_AMP_DEG * sin(_t * ANT_HZ * TAU + ANT_PHASE_L))
	_pose_rot(B_ANT_R, AX_LONG,  ar)
	_pose_rot(B_ANT_L, AX_LONG, -al)
	var leg := deg_to_rad(LEG_AMP_DEG * sin(_t * LEG_HZ * TAU))
	_pose_rot(B_LEG_R, AX_SIDE,  leg)
	_pose_rot(B_LEG_L, AX_SIDE, -leg)
	# Half the wing rate and out of phase with it — the body rocks against the beat, it doesn't nod with it.
	_pose_rot(B_ABDOMEN, AX_SIDE, deg_to_rad(ABDOMEN_AMP_DEG * sin(_flap_phase * 0.5 + PI)) * _flap_blend)

func _pose_mouth() -> void:
	var m := _mouth
	_pose_move(B_MAND_R, AX_SIDE,  MOUTH_MAND_PUSH * m)
	_pose_move(B_MAND_L, AX_SIDE, -MOUTH_MAND_PUSH * m)
	_pose_scale(B_MOUTH, lerpf(1.0, MOUTH_CLUSTER_UP, m))
	_pose_rot(B_JAW,  AX_SIDE, deg_to_rad(MOUTH_JAW_DEG) * m)
	_pose_rot(B_HEAD, AX_SIDE, deg_to_rad(MOUTH_HEAD_DEG) * m)
