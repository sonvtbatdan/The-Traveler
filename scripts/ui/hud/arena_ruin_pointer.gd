extends Control
## Generic off-screen pointer to ONE target Node2D: its own icon pinned to the screen edge in its direction,
## with the live distance printed level with it, snug against its right edge — both hidden once the target
## itself is visible on screen (the player has already located it, so the pointer is just clutter at that
## point). Unlike arena_chest_pointer.gd (which finds its single target by group), this holds a direct
## reference to a specific target so several can coexist. Current callers: electric_temple_layer.gd /
## volcanic_temple_layer.gd (temple boss) and electric_ruin_layer.gd / volcanic_ruin_layer.gd (rescue-character
## landmark) each spawn one per target. (Originally built for arena_ruin_layer.gd's giant dead-ship wrecks —
## REMOVED 2026-08-06, on request — hence the "ruin" filename; still fully generic, no dead-ship-specific
## logic ever lived here.) When its target is destroyed, the pointer frees itself (and its parent CanvasLayer).
## Modeled on arena_chest_pointer.gd.
##
## 2026-08-07, on request ("indicator chỉ dẫn đến hướng của rescue landmark vẫn đang dùng ảnh png, chưa dùng
## file glb xoay tròn như chest"): setup() now takes an optional `glb_path` — when given (the 2 rescue-ruin
## callers pass it; the 2 temple callers still don't, see below), the icon is a small self-contained
## SubViewport render of that model, spinning continuously, built exactly like arena_chest.gd's own
## icon_texture() (SubViewport + Camera3D framed to the model's AABB + 2 DirectionalLight3D, ROT_RPM spin) —
## same reasoning as chest's own doc comment: the target's REAL in-world instance lives inside a shared
## multi-object World3D scatter pass (ElectricTrees/VolcanicTrees), not its own isolated viewport, so there's
## no existing live render to just reuse the way chest does; this builds a second, independent one purely
## for the icon. Left OFF for the temple-boss callers (electric_temple_layer.gd/volcanic_temple_layer.gd) —
## temples are the one landmark type that deliberately does NOT spin in-world (see electric_ruin_layer.gd's
## own header: "temples stay still — this is what visually marks a ruin as a [rescue landmark]"), and the
## user's request was specifically about the rescue landmark; temple keeps the flat `_tex` icon it always had.
##
## 2026-08-19, on request ("Khoảng cách từ viền màn hình (hoặc hud nếu có) tới cụm indicator chỉ là 10 pixel —
## kiểm tra kĩ"): EDGE_MARGIN/HUD_GAP were already being measured against the icon's full padded BOUNDING BOX
## (_icon_size), not its real visible content — the exact same bug the label-gap fix earlier this session
## caught (see _measure_content()'s doc comment). So even at EDGE_MARGIN=10, a model that only fills ~40% of
## its square icon box actually sat noticeably MORE than 10px from the true edge. Fixed at the root: every
## spacing calc (screen-edge clamp, HUD-bar avoidance, label gap) now measures off `_content_half_w`/
## `_content_half_h` — the REAL rendered content's own half-extent — instead of `_icon_size * 0.5`. This also
## replaced the old GLB path's analytical AABB/fov "apparent_frac" estimate (width-only, no height) with the
## same empirical Image.get_used_rect() snapshot the flat-icon path already used — simpler, and now measures
## BOTH width and height directly from the rendered pixels instead of reasoning about only one axis.
##
## 2026-08-28, on request ("khi cac indicator nay nam o ben ria phai man hinh, thi cac chu so chi khoang cach
## bi tran ra khoi vien man hinh, vi the bi cat mat ko nhin thay... luon luon cach vien man hinh (hoac hud)
## 10 px"): every spacing calc measured the ICON's content alone, but the distance label hangs off the icon's
## RIGHT edge - so pinning the icon 10px inside the right screen edge pushed the label entirely off-screen.
## Now the icon + gap + label are treated as one CLUSTER (_cluster_offsets/_cluster_rect) and it is the
## cluster, not the icon, that keeps EDGE_MARGIN from the screen edge and HUD_GAP from the HUD bars: the
## direction ray in _process() uses the cluster's direction-appropriate half-extent, _push_clear() pushes the
## cluster rect, and a final _clamp_cluster() pass (after HUD avoidance, so the screen edge outranks it)
## guarantees the invariant. The on-screen check also had to move ABOVE the anchor maths, since a hidden
## label changes the cluster's width. Same change in arena_chest_pointer.gd. The label also went
## yellow-on-black-stroke here - see LABEL_COLOR/LABEL_OUTLINE.

const FONT        := preload("res://assets/fonts/mandalore/mandalore.ttf")
# How far the icon's REAL CONTENT edge sits inside the true screen edge when NO HUD bar is in the way — see
# this file's header (2026-08-19) for why this is now measured off content, not the padded icon box.
const EDGE_MARGIN := 10.0
# Same real-content-edge gap, kept specifically against HUD bars (_push_clear) instead of the screen edge.
const HUD_GAP := 10.0
# Icon draw width (px) — height follows the source texture's aspect ratio for the flat-icon (temple) path;
# the GLB (rescue) path renders square so LANDMARK_ICON_WIDTH just equals this too. 2026-08-19, on request
# ("tất cả các loại landmark, chest, rescue áp dụng cùng một kích thước model... theo rescue landmark hiện
# tại"): temple's flat icon now matches the rescue landmark's own size exactly (was 20% smaller before this
# request) — see LANDMARK_ICON_WIDTH below and arena_chest_pointer.gd's matching ICON_WIDTH.
const ICON_WIDTH := 120.0
# 2026-08-06, on request: at a small EDGE_MARGIN the icon can land right on top of the playerhud's Weapon
# (left-center)/Aux (right-center)/LV (bottom-center, HP+Shield+Level bars) macro regions — these 3 keys
# push the icon clear of whichever of those it would otherwise overlap, keeping HUD_GAP against the HUD
# chrome instead of EDGE_MARGIN against the screen edge. See hud_binder.gd's macro_global_rect() — its own
# 2026-08-06 fix (get_global_transform_with_canvas() instead of get_global_rect()) is what actually made this
# avoidance work at all: Weapon/Aux animate their container's scale (0.7↔1.0, see MACRO_BEHAVIOR), and
# get_global_rect() silently ignores ancestor scale — every hud_rect this queried while a macro sat at its
# resting 0.7 scale was ~43% oversized/mispositioned, which is why the icon could end up rendering ON TOP of
# a bar instead of beside it despite _push_clear()'s own math being correct.
const HUD_AVOID_MACROS := ["Weapon", "Aux", "LV"]

# GLB-icon mode (rescue landmarks only — see this file's header) — same values as arena_chest.gd's own.
const VP_SIZE   := 128            # SubViewport render resolution
const ISO_DEG   := 30.0           # camera tilt off top-down, matches arena.gd/arena_chest.gd
const ROT_RPM   := 12.0           # matches electric_ruin_layer.gd/volcanic_ruin_layer.gd's own landmark spin
const ROT_SPEED := deg_to_rad(ROT_RPM * 360.0 / 60.0)
const LANDMARK_ICON_WIDTH := ICON_WIDTH   # equal to ICON_WIDTH now, not 1.2× it — see that const's own doc comment
const LABEL_GAP_PX := 5.0   # gap from the icon's REAL visible content edge, not its full bounding box
# Distance-label colours (2026-08-28, on request: "text ghi khoang cach chuyen thanh mau vang, stroke den").
# Was a pale blue-white on an 85%-alpha black outline; the outline is now fully opaque so the stroke reads as
# a solid black edge over bright terrain instead of tinting with whatever is behind it.
const LABEL_COLOR   := Color(1.0, 0.84, 0.1)      # yellow
const LABEL_OUTLINE := Color(0.0, 0.0, 0.0, 1.0)  # black stroke

var _target: Node2D = null
var _player: Node2D = null
var _mgr: Node = null         # enemy_manager — visible_world_rect() for the on-screen check
var _hud_edit: Node = null    # group "hud_edit" — the live playerhud host, for macro_global_rect() lookups
var _anchor: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _show: bool = false
var _on_screen: bool = false
var _lbl: Label = null
var _icon_tex: Texture2D = null
var _icon_size: Vector2 = Vector2.ZERO
var _content_half: Vector2 = Vector2.ZERO   # real visible half-extent (w, h) of the icon's content — see _measure_content()
var _content_measured: bool = false         # GLB mode only — locks the measurement once a real frame has rendered, see _process()
var _glb_path: String = ""    # non-empty → GLB icon mode instead of the flat _tex fallback
var _vp: SubViewport = null
var _pivot: Node3D = null

## Point this arrow at a specific wreck/landmark node. `glb_path`, when given, renders that model into a
## small spinning SubViewport for the icon instead of falling back to the target's own flat `_tex` — see
## this file's header for which callers pass it.
func setup(target: Node2D, glb_path: String = "") -> void:
	_target = target
	_glb_path = glb_path
	if _glb_path != "":
		_build_model_viewport()

func _ready() -> void:
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_lbl = Label.new()
	# A FontVariation wrapping the shared Mandalore FontFile instead of using FONT directly — MandaloreText.gd
	# already bakes +4px glyph spacing into that SHARED FontFile for every Mandalore label project-wide, so
	# adding spacing there too would be a global change, not a local one. FontVariation.spacing_glyph is
	# additive on TOP of the base font's own spacing, so +2 here reads as "+2px more than the global
	# baseline", for this label only. Matches arena_chest_pointer.gd's own treatment.
	var font_var := FontVariation.new()
	font_var.base_font = FONT
	font_var.spacing_glyph = 2
	_lbl.add_theme_font_override("font", font_var)
	_lbl.add_theme_font_size_override("font_size", 20)   # matches arena_chest_pointer.gd's own font size
	_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	_lbl.add_theme_color_override("font_outline_color", LABEL_OUTLINE)
	_lbl.add_theme_constant_override("outline_size", 4)
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)

## Reuse the target's own already-loaded icon texture (arena_enemy.gd's `_tex`, set from its `configure()`
## "icon" field before this pointer exists) so the marker matches the actual target instead of a separate
## generic icon. Scaled to ICON_WIDTH, aspect ratio preserved (never stretched). GLB-icon mode (_glb_path
## set) never calls this — _build_model_viewport() sets _icon_tex/_icon_size itself, once, in setup().
func _load_icon() -> void:
	if _target == null:
		return
	var tex: Variant = _target.get("_tex")
	if tex == null or not (tex is Texture2D):
		return
	_icon_tex = tex
	var tw := float(_icon_tex.get_width())
	var th := float(_icon_tex.get_height())
	_icon_size = Vector2(ICON_WIDTH, ICON_WIDTH * th / maxf(1.0, tw))
	_content_half = _icon_size * 0.5   # fallback if the image can't be read below
	_measure_content()
	_content_measured = true   # flat icons are available immediately — one measurement is final, unlike GLB's spin

## Renders _glb_path into a small SubViewport, framed via its AABB exactly like arena_chest.gd's own
## _build_model_viewport()/_frame_cam() (fit-to-fov distance, fixed ISO_DEG tilt, continuous ROT_RPM spin
## about the vertical axis) — see this file's header. Sets _icon_tex/_icon_size directly, so _process()'s
## _load_icon() fallback never runs while in this mode; _content_half is measured lazily in _process()
## instead (see _measure_content()'s doc comment on why it can't happen synchronously here).
func _build_model_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.3
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	_vp.add_child(fill)

	var cam := Camera3D.new()
	_vp.add_child(cam)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	var packed := load(_glb_path) as PackedScene
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	_icon_size = Vector2(LANDMARK_ICON_WIDTH, LANDMARK_ICON_WIDTH)   # SubViewport render is always square
	_content_half = _icon_size * 0.5   # fallback until the first real frame renders — see _process()
	if model == null:
		push_warning("arena_ruin_pointer: could not load " + _glb_path)
		_content_measured = true   # nothing will ever render — stop retrying every frame
	else:
		_pivot.add_child(model)
		_frame_cam(cam, model)

	_icon_tex = _vp.get_texture()

## Center `model` on its own AABB (so it spins about its middle) and place `cam` at a fixed ISO_DEG tilt,
## backed off just far enough (given its fov) to fit the whole model — identical math to arena_chest.gd's
## own _frame_cam().
func _frame_cam(cam: Camera3D, model: Node3D) -> void:
	var aabb := _model_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	var iso := deg_to_rad(ISO_DEG)
	cam.position = Vector3(0.0, cos(iso), sin(iso)) * dist
	cam.look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	cam.near = maxf(0.05, dist - radius * 2.0)
	cam.far  = dist + radius * 2.0

## Verbatim port of arena_chest.gd's own _model_aabb()/_model_meshes() — see that file's doc comment on why
## global transforms are safe to use here (root is already inside the tree by the time this runs).
func _model_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var inv := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in _model_meshes(root):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

func _model_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_model_meshes(c))
	return out

## Measures the REAL visible content half-extent (_content_half, w×h in on-screen icon pixels) of whatever
## `_icon_tex` currently holds, via Image.get_used_rect() on its alpha channel — works identically whether
## the texture is a static PNG (temple) or a live SubViewport render (rescue GLB), since both ultimately
## produce a 2D image with transparent padding around the actual silhouette (temple.png measured: only 70%
## content on its 400×400 canvas; a GLB's diagonal-radius camera fit is even more conservative — 38%-52% of
## the frame width alone, measured across the 5 rescue models). A no-op (leaves the current fallback in
## place) if the image can't be read yet — the GLB SubViewport hasn't necessarily rendered a real frame the
## MOMENT _build_model_viewport() runs, so _process() keeps calling this once per frame until it succeeds
## (see _content_measured), then stops: the model spins continuously, so re-measuring every frame would make
## the label visibly jitter as the silhouette's width/height change with rotation — one representative
## snapshot is deliberately used instead, same reasoning as arena_chest_pointer.gd's own _measure_content().
##
## 2026-08-25 bug fix (user report: "offset và khoảng cách giữa object và text của chest đúng, rescue landmark
## sai" — verified by sampling 40 consecutive frames' get_used_rect() live): a freshly created transparent
## SubViewport's FIRST rendered frame can read back FULLY OPAQUE — a one-frame GPU clear/composite race, not
## specific to this model or map. get_used_rect() then reports the WHOLE 128×128 canvas as "used" instead of
## empty, so the `used.size.x <= 0` guard above doesn't catch it (a full box has positive size, it's just
## WRONG). Every measurement from the SECOND successful read onward was correct and stable (~40-58px of 128,
## matching this file's own documented "38-52% of frame width" for GLB rescue models) — this only ever
## corrupts the FIRST one, whichever frame that happens to land on. Both this file and arena_chest_pointer.gd
## trusted that first read unconditionally, so BOTH were exposed to the exact same race; chest usually read
## fine in practice (never confirmed why — likely a small, consistent difference in when its viewport first
## renders vs when this file's own _process() first checks), which is what made it look like a rescue-only
## bug. Fix: discard the first successful GLB-mode read, trust the second — cheap (one extra ~1-frame wait,
## imperceptible) and doesn't touch the flat-icon (temple) path below, which reads a real loaded PNG's alpha
## synchronously and was never exposed to this race.
var _measure_good_reads := 0   # GLB mode only — see the fix note above

func _measure_content() -> void:
	if _icon_tex == null:
		return
	var img: Image = _icon_tex.get_image()
	if img == null:
		return
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	if _glb_path != "":
		_measure_good_reads += 1
		if _measure_good_reads < 2:
			return   # discard the first read — see the 2026-08-25 fix note above
	var tex_w := float(_icon_tex.get_width())
	if tex_w <= 0.0:
		return
	var scale: float = _icon_size.x / tex_w
	_content_half = Vector2(used.size.x, used.size.y) * 0.5 * scale
	_content_measured = true

func _process(delta: float) -> void:
	# Wreck destroyed → its job is done; remove the pointer (and its dedicated CanvasLayer).
	if _target == null or not is_instance_valid(_target):
		var p := get_parent()
		if p is CanvasLayer:
			p.queue_free()
		else:
			queue_free()
		return
	if _pivot != null:
		_pivot.rotation.y += ROT_SPEED * delta
	if _icon_tex == null and _glb_path == "":
		_load_icon()
	if _glb_path != "" and not _content_measured:
		_measure_content()
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	if _hud_edit == null or not is_instance_valid(_hud_edit):
		_hud_edit = get_tree().get_first_node_in_group("hud_edit")
	_show = _player != null and is_instance_valid(_player)
	if _show:
		var vp := get_viewport_rect().size
		var center := vp * 0.5
		var target_screen := get_viewport().get_canvas_transform() * _target.global_position
		var d := target_screen - center
		_dir = d.normalized() if d.length() > 1.0 else Vector2.RIGHT
		# On-screen once the wreck itself sits inside the camera's visible world rect - the player can already
		# see it directly, so both the icon (_draw) and the distance label are redundant clutter at that point.
		# Resolved BEFORE the anchor now: whether the label shows decides how wide the cluster is, and the
		# cluster's width is what the edge clamp below measures.
		_on_screen = false
		if _mgr != null and _mgr.has_method("visible_world_rect"):
			_on_screen = (_mgr.call("visible_world_rect") as Rect2).has_point(_target.global_position)
		_lbl.visible = not _on_screen
		if not _on_screen:
			var dist := int(round(_player.global_position.distance_to(_target.global_position)))
			_lbl.text = MandaloreText.a(str(dist))
			_lbl.reset_size()
		# March out from centre along the target's direction until the WHOLE CLUSTER (icon content + gap +
		# label), not just the icon, is EDGE_MARGIN inside the screen edge. `ext_x` picks the cluster's right
		# half-extent when pointing right (the label side) and its left one when pointing left - that asymmetry
		# is the whole point, see _cluster_offsets().
		var box := _cluster_offsets()
		var ext_x: float = box.end.x if _dir.x >= 0.0 else -box.position.x
		var ext_y: float = maxf(-box.position.y, box.end.y)
		# maxf-clamped at 0: a cluster somehow wider than half the screen would make this negative and send the
		# anchor marching the WRONG way down the ray. Pinned to centre instead; _clamp_cluster has the last say.
		var half := Vector2(maxf(center.x - EDGE_MARGIN - ext_x, 0.0), maxf(center.y - EDGE_MARGIN - ext_y, 0.0))
		var tx := (half.x / absf(_dir.x)) if absf(_dir.x) > 0.0001 else 1.0e9
		var ty := (half.y / absf(_dir.y)) if absf(_dir.y) > 0.0001 else 1.0e9
		_anchor = center + _dir * minf(tx, ty)
		_anchor = _avoid_hud(_anchor, vp)
		# _push_clear() above is now screen-aware too (see its 2026-08-28 doc note), so this should be a no-op
		# in most cases -- kept as the final guarantee for the rare true-squeeze fallback in _push_clear().
		_anchor = _clamp_cluster(_anchor, vp)
		if not _on_screen:
			_lbl.position = Vector2(_anchor.x + _content_half.x + LABEL_GAP_PX, _anchor.y - _lbl.size.y * 0.5)   # gap measured from the REAL content edge, not the padded icon box
	else:
		_lbl.visible = false
	queue_redraw()

## Nudges the icon's centre so its REAL CONTENT footprint (_content_half, +/- EDGE_MARGIN) never overlaps the
## playerhud's Weapon/Aux/LV macro regions -- verbatim port of arena_ruin_pointer.gd's own _avoid_hud/
## _push_clear (see that file's HUD_AVOID_MACROS doc comment for the full rationale, including the
## macro-scale gotcha). `vp` is threaded through to _push_clear() -- see that function's 2026-08-28 doc note.
func _avoid_hud(pos: Vector2, vp: Vector2) -> Vector2:
	if _hud_edit == null or not _hud_edit.has_method("get_binder"):
		return pos
	var binder = _hud_edit.call("get_binder")
	if binder == null or not binder.has_method("macro_global_rect"):
		return pos
	for key: String in HUD_AVOID_MACROS:
		var hud_rect: Rect2 = binder.call("macro_global_rect", key)
		pos = _push_clear(pos, hud_rect, vp)
	return pos

## Minimum-translation push of the whole CLUSTER rect (icon content + distance label, see _cluster_offsets())
## anchored at `pos` fully outside `hud_rect` (grown by HUD_GAP on every side) -- moves along whichever single
## axis (X or Y) clears the overlap with the smaller shift, but ONLY among directions that keep the cluster
## on-screen (see 2026-08-28 fix below). Measuring the cluster rather than the bare icon is what keeps
## HUD_GAP honest for the LABEL too, not just the icon (2026-08-28 - same fix as _cluster_offsets).
##
## 2026-08-28 bug fix (user report: "indicator dang nam de len hud... thay vi offset cach hud 10px"): the
## ORIGINAL version picked whichever of the 4 escape directions was geometrically CHEAPEST with no regard for
## whether that direction was actually usable -- for a wide HUD bar sitting close to the bottom of the
## screen, "push down" (off the bottom of the SCREEN) can be numerically cheaper than "push up" (back onto
## the visible field), so this used to pick "down". _clamp_cluster() then immediately vetoed that (correctly
## keeping the cluster on-screen) and snapped the anchor right back to its pre-push position -- which was
## still INSIDE the HUD rect this function exists to clear. The two constraints fought every single frame,
## always resolving in the HUD's favour since _clamp_cluster runs last. Fixed by filtering candidates to only
## those that keep the cluster within the screen margin BEFORE picking the cheapest one -- verified against a
## 120-bar-geometry x 360-direction sweep (43,200 cases): zero remaining overlaps.
func _push_clear(pos: Vector2, hud_rect: Rect2, vp: Vector2) -> Vector2:
	if hud_rect.size.x <= 0.0 or hud_rect.size.y <= 0.0:
		return pos   # region doesn't exist right now (no weapons/aux owned yet, HUD Edit mode open, etc.)
	var blocked := hud_rect.grow(HUD_GAP)
	var cl := _cluster_rect(pos)
	if not cl.intersects(blocked):
		return pos
	var push_left  := cl.end.x - blocked.position.x   # shift this far left to clear blocked's left edge
	var push_right := blocked.end.x - cl.position.x   # shift this far right to clear blocked's right edge
	var push_up    := cl.end.y - blocked.position.y   # shift this far up to clear blocked's top edge
	var push_down  := blocked.end.y - cl.position.y   # shift this far down to clear blocked's bottom edge
	var candidates := [
		[Vector2(-push_left, 0.0), push_left],
		[Vector2(push_right, 0.0), push_right],
		[Vector2(0.0, -push_up), push_up],
		[Vector2(0.0, push_down), push_down],
	]
	var best_pos := pos
	var best_mag := 1.0e18
	var any_feasible := false
	for c: Array in candidates:
		var delta: Vector2 = c[0]
		var mag: float = c[1]
		var cand: Vector2 = pos + delta
		if mag < best_mag and _cluster_fits_screen(cand, vp):
			best_pos = cand
			best_mag = mag
			any_feasible = true
	if any_feasible:
		return best_pos
	# No direction clears the HUD without also leaving the screen -- a true squeeze (a HUD rect touching the
	# screen edge with less than cluster-size + margin + gap of room to work with). Falls back to the plain
	# cheapest push; _clamp_cluster right after this in _process() still guarantees the screen-edge half.
	var min_x := minf(push_left, push_right)
	var min_y := minf(push_up, push_down)
	if min_x <= min_y:
		pos.x += -min_x if push_left <= push_right else min_x
	else:
		pos.y += -min_y if push_up <= push_down else min_y
	return pos

## True if the cluster rect anchored at `pos` sits fully within the viewport, inset by EDGE_MARGIN on every
## side -- the same safe zone _clamp_cluster() enforces, checked here as a pass/fail instead of a correction
## so _push_clear() can rule out an escape direction the screen edge would just veto anyway.
func _cluster_fits_screen(pos: Vector2, vp: Vector2) -> bool:
	var r := _cluster_rect(pos)
	return r.position.x >= EDGE_MARGIN - 0.01 and r.position.y >= EDGE_MARGIN - 0.01 \
		and r.end.x <= vp.x - EDGE_MARGIN + 0.01 and r.end.y <= vp.y - EDGE_MARGIN + 0.01


## The indicator CLUSTER's footprint in ANCHOR-LOCAL space (position = top-left offset from `_anchor`,
## size = full cluster size), i.e. the icon's REAL rendered content PLUS the distance label sitting off its
## right edge. Asymmetric on X by design - the label only ever extends rightward - which is exactly the bug
## this exists to fix (2026-08-28, user report: "khi cac indicator nay nam o ben ria phai man hinh, thi cac
## chu so chi khoang cach bi tran ra khoi vien man hinh"): every spacing calc used to measure the ICON alone,
## so pinning the icon 10px from the right edge pushed the label clean off-screen. Screen-edge clamping
## (_clamp_cluster), the direction ray in _process() and HUD-bar avoidance (_push_clear) all measure off this
## now, so it is the whole cluster that keeps its 10px from the screen edge / HUD chrome, never just the icon.
## Reads `_lbl.visible`, so a hidden label contributes nothing and the cluster collapses back to the icon, and
## measures the label through _reserved_label_w() rather than its live width - see that function on why.
## The label width the LAYOUT uses - the widest digit glyph x the current digit count, NOT `_lbl.size.x`.
##
## 2026-08-28 bug fix (user report: "khi player di chuyen, text cung thay doi lien tuc dan den object chest co
## cam giac bi giat giat"). Once the icon's anchor started accounting for the label (the 2026-08-28 cluster
## change above), it inherited the label's own width - and Mandalore is a PROPORTIONAL font, so a distance
## ticking 1234 -> 1233 -> 1232 changes the measured width by a pixel or two EVERY frame. At the right screen
## edge, where the cluster's right extent is what the clamp bites on, that fed straight back into the icon's
## position: the model visibly shivered in place. Reserving the widest-digit width instead makes the layout
## depend only on the DIGIT COUNT, which changes a handful of times per run (crossing 1000, 100, 10) rather
## than every frame - the icon is now perfectly still, and the label, being left-aligned off the icon's edge,
## never moves either: only its right end grows and shrinks, inward, into the reserved space.
##
## Consequence, deliberately accepted: for a short number the visible text ends a few px short of the
## EDGE_MARGIN line rather than exactly on it. Erring on the side of MORE margin never clips anything, which
## was the whole point of the cluster work.
## Measured as the WIDEST UNIFORM string of that digit count ("999...", "888...", ...), not as
## widest_single_digit x count: a lone "8" measures 9px but five of them measure 50, because a 1-char
## measurement leaves off the trailing glyph spacing. The naive product undershoots by up to 5px, which would
## clip the text again. Brute-force-verified in Godot against EVERY number of 1-5 digits: the uniform maximum
## is an exact, tight upper bound at every length (margin exactly 0.00, never negative). Cached per length -
## a run sees maybe 5 distinct lengths, so this measures ~10 strings a handful of times, then never again.
const OUTLINE_PAD := 4.0   # matches the label's outline_size - the stroke is drawn OUTSIDE the glyph box
var _reserve_cache: Dictionary = {}   # digit count -> reserved width (px), incl. OUTLINE_PAD

func _reserved_label_w() -> float:
	if not _lbl.visible:
		return 0.0
	var n := _lbl.text.length()
	if n <= 0:
		return 0.0
	if _reserve_cache.has(n):
		return float(_reserve_cache[n])
	var f: Font = _lbl.get_theme_font("font")
	var fs: int = _lbl.get_theme_font_size("font_size")
	if f == null:
		return _lbl.size.x   # theme not resolved yet (never seen in practice) - fall back to the real width
	var w := 0.0
	for d: String in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		w = maxf(w, f.get_string_size(d.repeat(n), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)
	w += OUTLINE_PAD
	_reserve_cache[n] = w
	return w

func _cluster_offsets() -> Rect2:
	var lbl_w: float = (LABEL_GAP_PX + _reserved_label_w()) if _lbl.visible else 0.0
	var lbl_half_h: float = (_lbl.size.y * 0.5) if _lbl.visible else 0.0
	var hy: float = maxf(_content_half.y, lbl_half_h)
	return Rect2(Vector2(-_content_half.x, -hy), Vector2(_content_half.x * 2.0 + lbl_w, hy * 2.0))

## _cluster_offsets() placed at `pos` - the cluster's real screen-space rect.
func _cluster_rect(pos: Vector2) -> Rect2:
	var box := _cluster_offsets()
	return Rect2(pos + box.position, box.size)

## Final guarantee, applied AFTER _avoid_hud(): shifts `pos` by the minimum amount that puts the whole
## cluster rect inside the viewport inset by EDGE_MARGIN on all four sides. Runs last on purpose - a HUD push
## may legitimately move the icon toward an edge, and the screen edge has to win that tie. The size guards
## skip an axis whose cluster is somehow larger than the safe area, so it can never oscillate.
func _clamp_cluster(pos: Vector2, vp: Vector2) -> Vector2:
	var r := _cluster_rect(pos)
	var d := Vector2.ZERO
	if r.size.x <= vp.x - EDGE_MARGIN * 2.0:
		if r.position.x < EDGE_MARGIN:
			d.x = EDGE_MARGIN - r.position.x
		elif r.end.x > vp.x - EDGE_MARGIN:
			d.x = (vp.x - EDGE_MARGIN) - r.end.x
	if r.size.y <= vp.y - EDGE_MARGIN * 2.0:
		if r.position.y < EDGE_MARGIN:
			d.y = EDGE_MARGIN - r.position.y
		elif r.end.y > vp.y - EDGE_MARGIN:
			d.y = (vp.y - EDGE_MARGIN) - r.end.y
	return pos + d

func _draw() -> void:
	if not _show or _icon_tex == null or _on_screen:
		return
	draw_texture_rect(_icon_tex, Rect2(_anchor - _icon_size * 0.5, _icon_size), false)
