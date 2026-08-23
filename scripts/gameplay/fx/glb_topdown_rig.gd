extends RefCounted
## Shared helper for rendering a .glb model TOP-DOWN (camera looking straight along -Y) into a SubViewport,
## used by two different callers that need the exact same framing convention so a thrust-point placed in one
## context lands on the same real spot in the other:
##   - `arena_weapons.gd` (VIPER 3D swap, 2026-08-20) — the LIVE gameplay render: MultiMesh body segments +
##     head/tail MeshInstance3D, driven every frame from the existing 2D snake-chain positions.
##   - `creep_edit_mode.gd` — a live preview `ViewportTexture` so the creep editor can still show a picture of
##     a `.glb` creep to click thrust-points onto, exactly like it already does for `.png`/`.gif` creeps.
##
## No `class_name` on purpose (matches this repo's existing convention for dynamically-loaded VFX helper
## scripts, e.g. `ZSlashScript`/`BeamScript` in arena_weapons.gd — see `traveler_godot_verify` memory note on
## why a fresh class_name needs an editor-opened class cache before a headless parse-check can resolve it).
## Callers do `preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()` and call instance methods below
## (kept as instance methods, not `static func`, only so a single preloaded instance can be reused/cached by
## the caller if it wants to; none of these methods hold state themselves).
##
## Coordinate convention (shared by every caller): 1 world unit = 1 screen pixel (matches the arena's
## `CAM_ZOOM = (1,1)` — see `arena.gd`), world X = screen X, world Z = screen Y (Y still increasing downward,
## same as 2D). The camera sits above the XZ plane looking straight down -Y with up = -Z so that convention
## holds (see `make_camera` below). Every model is centered on its own AABB and UNIFORMLY scaled so its
## horizontal (XZ) footprint diagonal equals a caller-supplied target pixel size — this is what lets a 25.2px
## body segment and a 44px head/tail line up with the pre-existing `SNAKE_SPACING`/`BODY_SEG_PX`/`HEAD_PX`
## constants in `arena_weapons.gd` without re-tuning them.

## Adds 2 DirectionalLight3D + a WorldEnvironment (ambient) to `vp` — same recipe as `item_3d_icon.gd`'s
## `setup()`, duplicated rather than shared per that file's own stated precedent (each caller keeps its own
## copy of this math).
func build_lighting(vp: SubViewport) -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.3
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	vp.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.48)
	e.ambient_light_energy = 1.2
	env.environment = e
	vp.add_child(env)

## Fixed top-down orthographic camera. `world_half_height` = half the ortho view volume's vertical (world Z)
## diameter — pass whatever world-Z span the caller needs visible (for the live arena layer: half the
## viewport's pixel height, since 1 unit = 1 px; for a small edit-mode preview: half the target model size
## plus margin). `height` just needs to clear the model; it doesn't affect apparent size (orthogonal).
func make_camera(vp: SubViewport, world_half_height: float, height: float = 500.0) -> Camera3D:
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(world_half_height, 0.01) * 2.0
	cam.near = 0.05
	cam.far = height * 2.0
	# up = -Z (not +Z) so increasing world Z renders further DOWN the image — keeps "world Z = screen Y"
	# consistent with 2D's own Y-increases-downward convention (see file header).
	cam.look_at_from_position(Vector3(0.0, height, 0.0), Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
	# Headlamp copying the camera's own look direction — see item_3d_icon.gd's identical fix (dark/deeply
	# concave models otherwise render ~black; the 2 fixed DirectionalLight3D above don't reach every model).
	var headlamp := DirectionalLight3D.new()
	headlamp.rotation = cam.rotation
	headlamp.light_energy = 1.6
	vp.add_child(headlamp)
	return cam

## Loads `glb_path` and returns the instantiated root Node3D, or null on failure.
func load_model(glb_path: String) -> Node3D:
	var packed := load(glb_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D

## Centers `model` on its own AABB (position -= center) and uniformly scales it so its horizontal (X-Z plane)
## footprint DIAGONAL equals `target_diam_px` world units (= px, per this file's 1-unit-=-1px convention).
## Matches this repo's existing `BODY_SEG_PX`/`HEAD_PX` "diameter" sizing convention for the old 2D sprites —
## pass the same constant here so scale doesn't need re-tuning per part.
## Returns the applied uniform scale (useful if a caller also needs to scale a companion node, e.g. a
## BoneAttachment3D-driven plume emitter's own offset).
## IDEMPOTENT (2026-08-23): safe to call again on an already-fitted model, which is what lets a size change
## in Weapon Edit take effect on a live weapon instead of waiting for a re-equip. `model_aabb()` deliberately
## excludes `model`'s own transform, so `center` comes out the same every time -- but the centering used to be
## written as `position -= center`, which ACCUMULATED and walked the model off its own origin a little further
## on each call. Assigning it absolutely is identical on the first call (position starts at zero for every
## caller) and a no-op on later ones. `scale` was already absolute.
func center_and_fit(model: Node3D, target_diam_px: float) -> float:
	var aabb := model_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position = -center
	var footprint_diag: float = maxf(Vector2(aabb.size.x, aabb.size.z).length(), 0.001)
	var s: float = target_diam_px / footprint_diag
	model.scale = Vector3.ONE * s
	return s

## Composes each mesh's transform relative to `root` from LOCAL `.transform` values (not global_transform,
## which requires `is_inside_tree()` — see item_3d_icon.gd's own bugfix note on this exact gotcha). Safe to
## call on a model that hasn't been added to the tree yet.
func model_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	for mi: MeshInstance3D in _meshes(root):
		var box: AABB = _relative_transform(root, mi) * instance_aabb(mi)
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

## One MeshInstance3D's bounds IN ITS OWN LOCAL SPACE, as the thing will actually RENDER.
##
## For an ordinary (rigid) mesh that is just `mi.get_aabb()`. For a SKINNED one it is not, and the gap is
## not small — 2026-08-23 bug ("vũ khí bị clip trong 1 frame vuông nhỏ", Yari-Jeager): a skinned mesh's
## vertices are stored in BIND space and are placed on screen by the bones, `bone_global_rest * bind_pose *
## v`, so `mi.get_aabb()` (which reports the raw bind-space box) describes a shape the renderer never draws.
## Yari-Jeager.glb is the case in point: glTF import gives it an `Armature` scaled 0.01 with bone rests ~100x
## to match, so the bind-space box measures 1.7 units while the drawn character measures ~190. Everything
## downstream of `model_aabb` — `center_and_fit`'s uniform scale above all — was therefore fitting the wrong
## number and rendering the model about 100x too big, i.e. a small central crop of it filling the whole
## frame, in the weapon editor AND in the live arena.
##
## Skinning each vertex by its own bones (rather than, say, unioning the bone rests) is what keeps this
## TIGHT: the union of per-bone boxes would over-cover badly on a 24-bone humanoid and shrink the model
## instead. The REST pose is used deliberately — these rigs fit a model once at setup, and a fit that
## breathed with the current animation frame would make the weapon pulse on screen.
##
## Cached per Mesh resource: this walks every vertex, and the same mesh is re-fitted by several callers
## (each editor preview, the live arena rig) within a session.
static var _skin_aabb_cache: Dictionary = {}
func instance_aabb(mi: MeshInstance3D) -> AABB:
	var mesh: Mesh = mi.mesh
	if mesh == null or mi.skin == null:
		return mi.get_aabb()
	var key := mesh.get_instance_id()
	if _skin_aabb_cache.has(key):
		return _skin_aabb_cache[key] as AABB
	var skel := _skeleton_of(mi)
	if skel == null or skel.get_bone_count() == 0:
		return mi.get_aabb()
	# One matrix per SKIN BIND (not per bone — a skin may reference a subset, in its own order).
	var mats: Array[Transform3D] = []
	for i in mi.skin.get_bind_count():
		var bone: int = mi.skin.get_bind_bone(i)
		if bone < 0:
			var bname: String = mi.skin.get_bind_name(i)
			bone = skel.find_bone(bname) if not bname.is_empty() else -1
		var rest: Transform3D = skel.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
		mats.append(rest * mi.skin.get_bind_pose(i))
	if mats.is_empty():
		return mi.get_aabb()
	var acc := AABB()
	var has := false
	for si in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(si)
		if arrays.size() <= Mesh.ARRAY_WEIGHTS:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.size() < verts.size() or weights.size() < verts.size():
			continue
		var per: int = bones.size() / verts.size()   # 4 (or 8, for an 8-influence mesh)
		for vi in verts.size():
			var v := verts[vi]
			var p := Vector3.ZERO
			var wsum := 0.0
			for k in per:
				var w := weights[vi * per + k]
				if w <= 0.0:
					continue
				var bi := bones[vi * per + k]
				if bi < 0 or bi >= mats.size():
					continue
				p += (mats[bi] * v) * w
				wsum += w
			if wsum <= 0.0:
				p = v   # an unweighted vertex rides the mesh transform itself
			if has:
				acc = acc.expand(p)
			else:
				acc = AABB(p, Vector3.ZERO)
				has = true
	if not has:
		return mi.get_aabb()
	_skin_aabb_cache[key] = acc
	return acc

## The Skeleton3D driving `mi`, found by walking ANCESTORS rather than resolving `mi.skeleton` (a NodePath,
## which needs the model to be inside the tree — everything in this file is safe to call fully detached, and
## `center_and_fit` is called that way by creep_edit_mode.gd's preview builder).
func _skeleton_of(mi: MeshInstance3D) -> Skeleton3D:
	var n: Node = mi.get_parent()
	while n != null:
		if n is Skeleton3D:
			return n as Skeleton3D
		n = n.get_parent()
	return null

func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		xform = n.transform * xform
		n = n.get_parent() as Node3D
	return xform

func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_meshes(c))
	return out

## Lifts the (first) `Mesh` resource out of an instantiated+fitted glb, along with its full transform
## RELATIVE TO `model`'s OWN PARENT — i.e. `model.transform` (the centering + fit-scale `center_and_fit`
## baked into `model` itself) composed with the mesh instance's own local transform relative to `model`
## (usually identity — the VIPER glb files are a single mesh-only node — but this stays correct even if a
## caller's model wraps the mesh under extra nodes). Used by callers that need ONE shared mesh + a fixed base
## transform to combine with a per-instance world placement every frame (MultiMeshInstance3D body segments,
## and the head/tail MeshInstance3D — both do `world_xform * base_xform` per frame instead of touching
## `center_and_fit`'s result again, since re-running it every frame would re-fit against an already-fitted,
## already-off-origin model).
func mesh_and_base_xform(model: Node3D) -> Dictionary:
	var found := _meshes(model)
	if found.is_empty():
		return {"mesh": null, "xform": Transform3D.IDENTITY}
	var mi := found[0] as MeshInstance3D
	var base := model.transform * _relative_transform(model, mi)
	return {"mesh": mi.mesh, "xform": base}

## Projects `model`'s AABB onto the plane spanned by `right`/`up` (a camera's own basis vectors — pass
## `cam.global_transform.basis.x` / `.y`) and returns the resulting silhouette's {x: width, y: height} as
## SEEN from that camera. 2026-08-20 bug fix ("clamp bởi sprite 2D"): creep_edit_mode.gd used to force every
## glb creep's preview into a fixed SQUARE render regardless of the model's real proportions, which fed
## straight into `eo._aspect_ratio` (read from the texture's own w/h) and locked the W/H size spinboxes
## together at the WRONG (square) ratio for every 3D creep — a resize behavior that made sense for a flat 2D
## PNG (never distort those) but was actively wrong for a 3D render, whose true on-screen shape depends on
## the model itself. Callers now size the SubViewport/camera to THIS extent instead of a fixed square, so the
## texture's own aspect — and therefore `eo._aspect_ratio` — reflects the model's real silhouette.
## BUG FIX (2026-08-21 — "phóng lên cực to, crop 1 phần nhỏ"): `model_aabb(model)` returns the AABB in
## `model`'s OWN PRE-transform local space (it treats `model` as the root and deliberately excludes root's
## own transform — see that function's header). If the caller already ran `center_and_fit(model, ...)`
## before this (which bakes fit scale/centering directly INTO `model.position`/`model.scale`), the raw AABB
## from `model_aabb` is measured in the UN-SCALED import space — often wildly different from the fitted
## ~target_px scale — so the old version of this function sized the camera around the WRONG (tiny or huge)
## extent, making the actually-fitted model render far too large/small for its frame. Fix: apply `model.
## transform` to every corner before projecting, so this measures the model as it will ACTUALLY appear
## (post-fit) in whatever space `model`'s parent lives in (safe to call fully detached — same as everything
## else in this file, `model.transform` is a pure local-only read, no tree membership needed).
## `pre` (2026-08-23) is an EXTRA transform applied on top of `model.transform` — pass the model's rotation
## pivot's own transform to measure the silhouette AS ROTATED. Without it a caller fitting a frame to this
## measures the model at rotation zero, and any mount angle that widens the silhouette runs straight past the
## frame edge (the "khung crop" on ND-Aliwa-Bmr). Defaults to identity, so callers that genuinely want the
## un-rotated extent are unchanged.
func silhouette_extent(model: Node3D, right: Vector3, up: Vector3,
		pre: Transform3D = Transform3D.IDENTITY) -> Vector2:
	var aabb := model_aabb(model)
	var r := right.normalized()
	var u := up.normalized()
	var min_u := INF; var max_u := -INF
	var min_v := INF; var max_v := -INF
	for i in 8:
		var corner_local := aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1))
		var corner := pre * (model.transform * corner_local)   # baked fit scale/centering, then `pre`
		var pu := corner.dot(r)
		var pv := corner.dot(u)
		min_u = minf(min_u, pu); max_u = maxf(max_u, pu)
		min_v = minf(min_v, pv); max_v = maxf(max_v, pv)
	return Vector2(maxf(max_u - min_u, 0.001), maxf(max_v - min_v, 0.001))

# ── AUTHORING AXIS SPACE (2026-08-22, "Đặt trục X-Y là 2 mặt phẳng / Trục Z là trục thẳng đứng") ──────────
# Two spaces meet in this file and they are NOT the same, which is why every rotation crosses one of the
# three helpers below rather than being handed straight to a Node3D:
#
#   EDITOR space (what the Rotate X/Y/Z sliders edit and what weapon_layout.cfg stores) is Z-UP, matching
#   3ds Max/Blender and the way the user reasons about the layout: +X = canvas right, +Y = canvas UP,
#   +Z = straight up out of the play plane. Every weapon/part therefore lies in the X-Y plane at Z = 0, and
#   a part's "lift" is a Z value (was called `height` before this pass — see the cfg migration note in
#   creep_edit_mode.gd::_load_layout).
#
#   VIEW space (Godot's own, used by the SubViewport rigs here and in creep_edit_mode.gd/arena_weapons.gd)
#   is Y-UP: +X = canvas right, +Y = up, +Z = canvas DOWN (see this file's header — the camera looks along
#   -Y with up = -Z so that "world Z = screen Y" holds against 2D's y-grows-downward convention).
#
# The two differ by exactly a -90° turn about their shared X axis, which is what `axis_fix()` returns. A
# rotation is carried across with a conjugation (`view_basis`/`editor_rot`), never by permuting the Euler
# components — those are only equal for single-axis rotations.

## Euler order for EDITOR-space angles. Deliberately ZXY, not Godot's default YXZ: ZXY applies Z OUTERMOST,
## so the Rot Z slider is a pure spin about the world vertical no matter how the part is already tilted —
## i.e. exactly the flat "heading" the old 2D `dir_angle` was (2026-08-22, "thiết lập lại cơ chế xoay như
## của plume 2D"). Under YXZ, Z is applied innermost/local, so on a tilted part it would swing the object
## around a tilted axis instead. Every from_euler/get_euler on an EDITOR-space value must pass this.
const EDITOR_EULER_ORDER := EULER_ORDER_ZXY

## EDITOR-space Euler ↔ EDITOR-space Basis, both in EDITOR_EULER_ORDER. Use these instead of bare
## `Basis.from_euler()` / `Basis.get_euler()` on anything stored in the cfg or shown on a slider: the bare
## calls default to Godot's YXZ, which would read the same three numbers as a DIFFERENT orientation.
func rot_basis(rot_editor: Vector3) -> Basis:
	return Basis.from_euler(rot_editor, EDITOR_EULER_ORDER)

func rot_euler(b_editor: Basis) -> Vector3:
	return b_editor.get_euler(EDITOR_EULER_ORDER)

## EDITOR(Z-up) → VIEW(Y-up) basis change. Maps editor +Y (canvas up) to view -Z (canvas up) and editor +Z
## (vertical) to view +Y (vertical), leaving X alone.
func axis_fix() -> Basis:
	return Basis(Vector3.RIGHT, -PI * 0.5)

## An EDITOR-space Euler as a VIEW-space Basis (conjugation: `C · R · C⁻¹`). This is the ONLY correct way to
## hand a stored rotation to a Node3D.
func view_basis(rot_editor: Vector3) -> Basis:
	var c := axis_fix()
	return c * Basis.from_euler(rot_editor, EDITOR_EULER_ORDER) * c.inverse()

## Same, as an Euler ready to assign to `Node3D.rotation` (which is read back in Godot's own YXZ order).
func view_rotation(rot_editor: Vector3) -> Vector3:
	return view_basis(rot_editor).get_euler()

## Inverse of `view_basis` — a VIEW-space Basis back to an EDITOR-space Euler. Used by the one-time
## weapon_layout.cfg migration and anywhere a view-space orientation has to be stored/displayed.
func editor_rot(b_view: Basis) -> Vector3:
	var c := axis_fix()
	return (c.inverse() * b_view * c).get_euler(EDITOR_EULER_ORDER)

## Resolves a TP dict's spray DIRECTION as a full 3D unit vector (2026-08-21, "chỉnh hướng phun bằng 3 thanh
## slider XYZ"). Authoritative source is `tp["dir_rot"]` (Vector3, radians — the 3 Rotate X/Y/Z sliders'
## values when a TP is focused instead of the object, see creep_edit_mode.gd's "3D VIEW / MOUNT ANGLE"
## section) applied to a fixed base direction (0,0,1) via `Basis.from_euler`. Falls back to the OLD flat
## `dir_angle` float (ground-plane only, Y=0) when `dir_rot` was never set — every TP saved before this
## feature, and every 2D (non-glb) creep's TP forever, has no `dir_rot` key, so this keeps behaving exactly
## as before for them. Both callers (arena_weapons.gd's live plume, creep_edit_mode.gd's preview) MUST call
## this instead of re-deriving a direction themselves, or the editor and the real game could show different
## spray directions for the same TP.
func tp_direction(tp: Dictionary) -> Vector3:
	if tp.has("dir_rot"):
		return (view_basis(tp_rot_editor(tp)) * Vector3(0.0, 0.0, 1.0)).normalized()   # base-aware, see tp_rot_editor
	var dir_angle: float = float(tp.get("dir_angle", PI * 0.5))
	return Vector3(cos(dir_angle), 0.0, sin(dir_angle))

## 2026-08-21 ("nghiên cứu sự khác biệt giữa cách xoay plume test (hoạt động tốt) và plume weapon edit
## (hỏng)"): the approach that worked rotates by writing a PARENT Node3D's
## `.rotation` every frame, with its child CPUParticles3D's own `direction` held FIXED at the base
## `Vector3(0,0,1)` — because `local_coords=true` (make_plume() below) means the WHOLE particle system,
## including particles already mid-flight, is continuously re-transformed by whatever the parent's CURRENT
## rotation is, every frame → an edit is visible INSTANTLY and uniformly on every particle. The real TP plume
## used to do the opposite: bake the FINAL rotated vector straight into `CPUParticles3D.direction` itself
## (see `make_plume`'s `direction` param, still used that way by any caller not yet updated to this pivot
## pattern). `direction` is only consulted at EACH PARTICLE'S OWN SPAWN moment — changing it live only affects
## particles born AFTER the change; whatever was already in flight (up to a full `lifetime` old) keeps
## drifting on its stale trajectory. That's the actual mechanism gap: not wrong math (`tp_direction()`'s
## output was always correct — see arena_weapons.gd's own numeric proof), just the WRONG PLACE to apply it
## for something meant to be edited live. `tp_view_rotation()` is the fix — gives callers a PIVOT rotation (Euler,
## same authoritative dir_rot/dir_angle source as `tp_direction()`) to apply to a wrapper Node3D that PARENTS
## the particle, instead of baking into the particle's own `direction`. Callers: parent the particle under a
## pivot Node3D built with `make_plume(Vector3.ZERO, Vector3(0,0,1), style, target_px)` (fixed base direction,
## never touched again), set `pivot.position = local_pos` (moved off the particle, which now sits at its
## pivot's local origin) and `pivot.rotation = tp_view_rotation(tp)` — then a live rotation update only ever needs
## to touch `pivot.rotation`, exactly mirroring the TEST PLUME's own model.
## 2026-08-22 (axis-space pass): renamed from `tp_rotation` and now returns an EDITOR-space (Z-up) angle —
## the same space the sliders edit and the cfg stores. Callers that need to drive a Node3D want
## `tp_view_rotation()` below instead; this one is for storage/display/composition.
## The flat `dir_angle` fallback moved from the Y component to the Z component accordingly: a heading in the
## ground plane is a rotation about the VERTICAL axis, which is Z in editor space (it was Y in view space).
func tp_rot_editor(tp: Dictionary) -> Vector3:
	if tp.has("dir_rot"):
		return compose_rot(tp.get("dir_rot_base", Vector3.ZERO), tp["dir_rot"] as Vector3)
	var dir_angle: float = float(tp.get("dir_angle", PI * 0.5))
	return Vector3(0.0, 0.0, PI * 0.5 - dir_angle)   # verified equal to tp_direction()'s own 2D fallback

## `tp_rot_editor()` carried into VIEW space, ready to assign to a plume pivot's `Node3D.rotation`.
func tp_view_rotation(tp: Dictionary) -> Vector3:
	return view_rotation(tp_rot_editor(tp))

## Composes a BASE rotation with an offset one (2026-08-22, "Reset vị trí hiện tại thành 0,0,0 rotation").
## The editor's "Set 0° here" button banks whatever you have dialled in as `*_base` and zeroes the visible
## slider values, so the orientation on screen is unchanged but every later tweak is a small readable delta
## from it instead of an opaque absolute. Everything that consumes a rotation must go through this, or the
## banked half is silently dropped and the object/plume snaps back. A Basis PRODUCT, never euler addition —
## the latter is only correct when both rotations are about one shared axis.
## 2026-08-22: both operands and the result are EDITOR-space angles, so all three conversions use
## EDITOR_EULER_ORDER — mixing orders here would silently re-interpret a banked base as a different pose.
func compose_rot(base: Vector3, offset: Vector3) -> Vector3:
	if base.is_zero_approx():
		return offset
	return (Basis.from_euler(base, EDITOR_EULER_ORDER)
		* Basis.from_euler(offset, EDITOR_EULER_ORDER)).get_euler(EDITOR_EULER_ORDER)

## Builds one 3D plume particle (2026-08-20, shared by the live gameplay VIPER/Jaeger plume in
## arena_weapons.gd AND creep_edit_mode.gd's own TP preview — moved here, not duplicated, specifically so
## the editor preview stays WYSIWYG with the real in-game look instead of two copies drifting apart; every
## other cross-file framing helper in this file stays duplicated per this file's own header convention,
## this one is the deliberate exception). Same soft radial-falloff texture + additive gradient recipe as the
## 2D `_make_orbital_plume` in arena_weapons.gd, just a billboard QuadMesh on CPUParticles3D instead of a
## CanvasItem. `local_pos` is the FINAL local position within whatever the caller parents this under (frac-
## of-model-box XZ + the TP's own "Z" height) — this function doesn't offset it further. `target_px` only
## scales particle size/amount to roughly match the model's own on-screen scale (same role as `ds` in 2D).
## `direction` (2026-08-21, was a flat `dir_angle: float`) — pass `tp_direction(tp)` above, a full 3D vector,
## so a TP's calibrated 3-axis spray direction actually reaches the particle (a flat float couldn't).
## 2026-08-21 ("áp dụng code plume này vào weapon edit" — after finding the rotation math was correct the
## whole time, but the user's ACTIVE TP had no saved style entry, so it rendered from these fallback numbers
## and was nearly invisible at gameplay scale/zoom): bumped from the original (barely-there) defaults —
## `lifetime` 0.30→0.6, `spread` 12°→4° (a tighter cone reads direction more clearly), `sc_min/max` 0.6/1.5→
## 1.5/2.5 (was scaling an already-tiny `target_px*0.18` quad down further). Still modest, not as extreme as
## a deliberately-huge diagnostic style — this is
## meant to be a REASONABLE default a real weapon could ship with, not a diagnostic beacon. Only affects TPs
## that have NEVER had a style explicitly saved (every existing tuned TP — VIPER/Jaeger/Aliwa's `tp_1` —
## already has its own `col_*`/`lifetime`/`spread`/`vel_*`/`sc_*` keys in weapon_plume_styles.cfg and
## overrides every one of these via `style.get(key, fallback)`, so this change is invisible to them).
func make_plume(local_pos: Vector3, direction: Vector3, style: Dictionary, target_px: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = local_pos
	# 2026-08-21: floor of 12 — `target_px / 5.0` alone gives a SMALL weapon (e.g. Aliwa, target_px≈25) as few
	# as 5 total particles, which at a 0.6-1.0s lifetime means new ones are born only every ~0.1-0.2s — reads
	# as a sparse trickle of 1-2 visible dots rather than a plume, no matter how big/bright each one is scaled.
	p.lifetime = float(style.get("lifetime", 0.6))
	# 2026-08-23: `amount` is a POOL SIZE, not a rate — CPUParticles emits `amount / lifetime` per second, so a
	# long-lived style was quietly thinning out into a dotted line (the 1.2s boomerang trail below would have
	# been 10 particles/sec). Scale the pool with lifetime past the 0.6s baseline to hold the emission RATE
	# constant instead. Styles at or under 0.6s are unchanged; longer ones get denser, which is the behaviour
	# they were always asking for.
	var base_amount := maxi(12, int(target_px / 5.0))
	p.amount = maxi(base_amount, int(ceil(base_amount * p.lifetime / 0.6)))
	p.emitting = true
	p.gravity = Vector3.ZERO
	# 2026-08-21 THE bug behind "plume chưa xoay theo object" / "chưa xoay khi kéo slider": CPUParticles3D's
	# `local_coords` DEFAULTS TO FALSE (verified directly — `CPUParticles3D.new().local_coords == false`,
	# unlike the 2D counterpart, which is why arena_weapons.gd's own 2D plumes explicitly set it false to OPT
	# INTO the same world-space behavior this 3D node already had by default). With it false, `direction` is
	# an ABSOLUTE WORLD vector — completely ignoring whatever rotation the particle's own parent node has
	# (the plume anchor, which every caller rotates every frame to track the object's mount-angle calibration
	# AND, for a TP, the calibrated spray direction relative to the model) — so no amount of rotating the
	# anchor (object rotate sliders) OR rebuilding the particle with a new `direction` (TP rotate sliders)
	# could ever visibly change the spray, since the anchor's rotation was never being consulted at all. Every
	# doc comment in this file and every caller (arena_weapons.gd, creep_edit_mode.gd) already assumed/relied
	# on "rotate the anchor → the plume rotates with it" (genuine scene-graph attachment) — `local_coords =
	# true` is what actually MAKES that true: it tells the particle to interpret `direction` (and simulate
	# velocity) relative to its own node's CURRENT transform instead of raw world space.
	# `trail` (2026-08-23, "Khi boomerang lướt đi, plume này sẽ để lại trail"): world-space particles, which is
	# what actually makes a TRAIL. With local_coords TRUE every live particle is re-transformed by the
	# emitter's CURRENT transform each frame, so the whole plume rides along with the object and can never
	# fall behind it — correct for an exhaust flame pinned to a nozzle, wrong for something meant to hang in
	# space while the weapon flies on. Turning it off freezes each particle into world space at birth, so the
	# object leaves a wake it can outrun. The cost is the one the 2026-08-21 note above cares about: with it
	# off, `direction` is only consulted at each particle's OWN spawn moment, so a live rotate-slider drag
	# re-aims newly born particles rather than everything in flight. For a trail that is not a defect — a wake
	# SHOULD keep the heading it was laid down at — but it is why this is opt-in per style, not the default.
	p.local_coords = not bool(style.get("trail", false))
	p.direction = direction
	p.spread = float(style.get("spread", 4.0))
	p.initial_velocity_min = float(style.get("vel_min", 60.0))
	p.initial_velocity_max = float(style.get("vel_max", 100.0))
	p.scale_amount_min = float(style.get("sc_min", 1.5))
	p.scale_amount_max = float(style.get("sc_max", 2.5))
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.05))
	p.scale_amount_curve = taper
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(16, 16) * 0.5
	for iy in 16:
		for ix in 16:
			var dist: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / 8.0
			var a: float = clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * (target_px * 0.18)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# 2026-08-22 bug fix ("Plume tôi tăng SC lên rất lớn rồi nhưng vẫn không to thêm"): Godot DISCARDS a
	# mesh's scale when billboarding unless this is set — so every particle rendered at the QuadMesh's own
	# base size and `scale_amount_min/max` (i.e. the Plume Style panel's Sc fields) did precisely nothing.
	# Measured before the fix: sc 1 / 4 / 10 all rendered an identical 12x12 px blob; with the curve removed
	# too, still 12x12 — proving the scale never reached the renderer at all rather than being overridden.
	# Affects every make_plume() caller, so this fixes Sc for the live VIPER/Jaeger/Aliwa plumes as well as
	# the editor preview.
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true   # required for color_ramp below to actually tint the texture
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mesh.material = mat
	p.mesh = mesh
	var col_core:  Color = style.get("col_core",  Color(0.7, 0.9, 1.0, 1.0))
	var col_flame: Color = style.get("col_flame", Color(0.4, 0.7, 1.0, 1.0))
	var col_cool:  Color = style.get("col_cool",  Color(0.2, 0.5, 1.0, 0.8))
	var col_fade := col_cool; col_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	grad.colors  = PackedColorArray([col_core, col_flame, col_cool, col_fade])
	p.color_ramp = grad
	return p
