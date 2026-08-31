extends Control
## Off-screen pointer to the reward chest: an icon pinned to the screen edge in the chest's direction, with the
## live distance printed to its right. Lives on a CanvasLayer (screen-space). Hides itself when no chest exists.
##
## 2026-08-06, on request ("bỏ dấu mũi tên đi, thay bằng icon chest"): the old procedural chrome arrow is gone —
## the icon is arena_chest.gd's OWN live SubViewport render of the spinning assets/ruin/Chest.glb model
## (icon_texture()), reused as-is rather than drawn as a separate arrow or loaded from a static indicator image
## file ("dùng nó thay cho file ảnh indicator luôn") — the edge icon spins in sync with the in-world chest for
## free, since it's literally the same live texture.
##
## 2026-08-06 follow-up ("offset 20 pixel từ viền màn hình, nếu gặp các bar HUD thì offset từ viền bar — logic
## này ở trên đã làm rồi"): edge margin + HUD-bar-avoidance logic is copied verbatim from
## arena_ruin_pointer.gd (EDGE_MARGIN/HUD_GAP/HUD_AVOID_MACROS/_avoid_hud/_push_clear — see that file's own doc
## comments for the full rationale, especially the get_global_transform_with_canvas() macro-scale gotcha). The
## distance label now sits fixed to the icon's right edge (was: behind the icon, offset backward along the
## pointing direction) with a smaller font, also matching arena_ruin_pointer.gd's own label placement.
##
## 2026-08-19, on request ("tất cả các loại landmark, chest, rescue áp dụng cùng một kích thước model và text
## size — theo rescue landmark hiện tại"): ICON_WIDTH/font size/letter-spacing/label-gap logic all matched
## arena_ruin_pointer.gd's own (post-tuning) values. Same-day follow-up ("giảm chest size xuống còn 70% so với
## hiện tại"): ICON_WIDTH scaled back down to 70% of that shared size — chest is the one type smaller than the
## other two again, just from a bigger shared baseline than before. Also same-day ("Khoảng cách từ viền màn
## hình... tới cụm indicator chỉ là 10 pixel — kiểm tra kĩ"): EDGE_MARGIN/HUD_GAP now measure off the icon's
## REAL rendered content (_content_half, via Image.get_used_rect() on the live SubViewport texture) instead of
## its full padded bounding box — see _measure_content()'s own doc comment, mirrors arena_ruin_pointer.gd's
## identical fix.
##
## 2026-08-28, on request ("khi cac indicator nay nam o ben ria phai man hinh, thi cac chu so chi khoang cach
## bi tran ra khoi vien man hinh, vi the bi cat mat ko nhin thay... luon luon cach vien man hinh (hoac hud)
## 10 px"): every spacing calc measured the ICON's content alone, but the distance label hangs off the icon's
## RIGHT edge - so pinning the icon 10px inside the right screen edge pushed the label entirely off-screen.
## Now the icon + gap + label are treated as one CLUSTER (_cluster_offsets/_cluster_rect) and it is the
## cluster, not the icon, that keeps EDGE_MARGIN from the screen edge and HUD_GAP from the HUD bars: the
## direction ray in _process() uses the cluster's direction-appropriate half-extent, _push_clear() pushes the
## cluster rect, and a final _clamp_cluster() pass (after HUD avoidance, so the screen edge outranks it)
## guarantees the invariant. Same change in arena_ruin_pointer.gd. The label also went yellow-on-black-stroke
## here - see LABEL_COLOR/LABEL_OUTLINE.

const FONT        := preload("res://assets/fonts/mandalore/mandalore.ttf")
# How far the icon's REAL CONTENT edge sits inside the true screen edge when NO HUD bar is in the way — see
# this file's header (2026-08-19) for why this is now measured off content, not the padded icon box.
const EDGE_MARGIN := 10.0
const HUD_GAP      := 10.0    # same real-content-edge gap, kept specifically against HUD bars (_push_clear)
const ICON_WIDTH   := 84.0    # icon draw width AND height (arena_chest.gd's SubViewport render is square).
                               # 2026-08-19: 50 → 120 (matched the other pointer types) → 84 ("giảm chest size
                               # xuống còn 70%" of that 120 — chest reads smaller than landmark/rescue again).
const LABEL_GAP_PX := 8.0     # gap from the icon's REAL visible content edge, not its full bounding box.
                               # 2026-08-28, on request ("chest dang nam qua gan text... dich chest ra ngoai
                               # (ve ben trai) khoang 3 pixel"): 5.0 -> 8.0, i.e. 3px more than
                               # arena_ruin_pointer.gd's own LABEL_GAP_PX, which the user was happy with. The
                               # cluster maths does the rest: at the right screen edge the TEXT stays pinned
                               # EDGE_MARGIN from the edge and the chest icon is what moves 3px left.
const HUD_AVOID_MACROS := ["Weapon", "Aux", "LV"]   # see arena_ruin_pointer.gd's own doc comment
# Distance-label colours (2026-08-28, on request: "text ghi khoang cach chuyen thanh mau vang, stroke den").
# Was a pale blue-white on an 85%-alpha black outline; the outline is now fully opaque so the stroke reads as
# a solid black edge over bright terrain instead of tinting with whatever is behind it.
const LABEL_COLOR   := Color(1.0, 0.84, 0.1)      # yellow
const LABEL_OUTLINE := Color(0.0, 0.0, 0.0, 1.0)  # black stroke

var _chest: Node2D = null
var _player: Node2D = null
var _mgr: Node = null         # enemy_manager — visible_world_rect() for the on-screen check
var _on_screen: bool = false  # chest itself visible in the arena → the whole pointer is suppressed
var _hud_edit: Node = null    # group "hud_edit" — the live playerhud host, for macro_global_rect() lookups
var _icon_tex: Texture2D = null
var _icon_size: Vector2 = Vector2(ICON_WIDTH, ICON_WIDTH)
var _content_half: Vector2 = Vector2(ICON_WIDTH, ICON_WIDTH) * 0.5   # real visible half-extent (w, h) of the icon's content — see _measure_content()
var _content_measured: bool = false   # locks the measurement once a real frame has rendered, see _process()
var _anchor: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _show: bool = false
var _lbl: Label = null

func _ready() -> void:
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl = Label.new()
	# FontVariation wrapping the shared Mandalore FontFile — matches arena_ruin_pointer.gd's own treatment
	# (see that file's _ready() doc comment for why this is a LOCAL +2px on top of MandaloreText.gd's global
	# +4px, not a change to the shared FontFile itself).
	var font_var := FontVariation.new()
	font_var.base_font = FONT
	font_var.spacing_glyph = 2
	_lbl.add_theme_font_override("font", font_var)
	_lbl.add_theme_font_size_override("font_size", 20)   # matches arena_ruin_pointer.gd's own font size
	_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	_lbl.add_theme_color_override("font_outline_color", LABEL_OUTLINE)
	_lbl.add_theme_constant_override("outline_size", 4)
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)

func _process(_delta: float) -> void:
	if _chest == null or not is_instance_valid(_chest):
		_chest = get_tree().get_first_node_in_group("arena_chest")
	if _icon_tex == null and _chest != null and _chest.has_method("icon_texture"):
		_icon_tex = _chest.call("icon_texture")   # null until the chest's model finishes loading — retried each frame
	if _icon_tex != null and not _content_measured:
		_measure_content()
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _hud_edit == null or not is_instance_valid(_hud_edit):
		_hud_edit = get_tree().get_first_node_in_group("hud_edit")
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_show = _chest != null and is_instance_valid(_chest) and _player != null and is_instance_valid(_player)
	# On-screen once the chest sits inside the camera's visible world rect - the player can already see it, so
	# icon AND label are redundant clutter (2026-08-28, on request: "khi object... da xuat hien tren arena thi
	# khong hien icon dan duong nua"). arena_ruin_pointer.gd has always done this; chest never did.
	_on_screen = false
	if _show and _mgr != null and _mgr.has_method("visible_world_rect"):
		_on_screen = (_mgr.call("visible_world_rect") as Rect2).has_point(_chest.global_position)
	_lbl.visible = _show and not _on_screen
	if _show and not _on_screen:
		var vp := get_viewport_rect().size
		var center := vp * 0.5
		var chest_screen := get_viewport().get_canvas_transform() * _chest.global_position
		var d := chest_screen - center
		_dir = d.normalized() if d.length() > 1.0 else Vector2.RIGHT
		# The label's own width is part of the cluster's footprint, so its text/size must be settled BEFORE the
		# anchor is placed - only its final position is applied at the bottom of this block.
		var dist := int(round(_player.global_position.distance_to(_chest.global_position)))
		_lbl.text = MandaloreText.a(str(dist))
		_lbl.reset_size()
		# March out from centre along the chest direction until the WHOLE CLUSTER (icon content + gap + label),
		# not just the icon, is EDGE_MARGIN inside the screen edge. `ext_x` picks the cluster's right half-extent
		# when pointing right (the label side) and its left one when pointing left - that asymmetry is the whole
		# point, see _cluster_offsets().
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
		_lbl.position = Vector2(_anchor.x + _content_half.x + LABEL_GAP_PX, _anchor.y - _lbl.size.y * 0.5)   # gap measured from the REAL content edge, not the padded icon box
	queue_redraw()

## Measures the REAL visible content half-extent (_content_half, w×h in on-screen icon pixels) of the chest
## icon (a live SubViewport render, always square at ICON_WIDTH×ICON_WIDTH) via Image.get_used_rect() on ONE
## snapshot frame, taken the moment the texture first has real rendered content — mirrors arena_ruin_pointer.
## gd's own _measure_content() exactly (see that file's doc comment for the full rationale: a single snapshot
## rather than measuring every frame, since the chest spins continuously and re-measuring every frame would
## make the label visibly jitter as the silhouette's width/height change with rotation). Leaves the current
## fallback in place (and keeps retrying next frame) if the image can't be read yet.
##
## 2026-08-25 bug fix — see arena_ruin_pointer.gd's own _measure_content() for the full write-up: a freshly
## created transparent SubViewport's FIRST rendered frame can read back fully OPAQUE (a one-frame GPU
## clear/composite race), which get_used_rect() then wrongly reports as "the whole canvas is used" instead of
## empty — passing the size>0 check below despite being garbage. Verified live over 40 consecutive frames on
## this exact codepath: frame 1 always misfires (full box), frame 2 onward is correct and stable. This file
## and arena_ruin_pointer.gd share the identical vulnerable pattern (trust the first successful read
## unconditionally); chest usually happened to read fine in practice, which is what made this look like a
## rescue-landmark-only bug rather than the shared race it actually is. Fix: discard the first successful
## read, trust the second.
var _measure_good_reads := 0   # see the fix note above

func _measure_content() -> void:
	var img: Image = _icon_tex.get_image()
	if img == null:
		return
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	_measure_good_reads += 1
	if _measure_good_reads < 2:
		return   # discard the first read — see the 2026-08-25 fix note above
	var tex_w := float(_icon_tex.get_width())
	if tex_w <= 0.0:
		return
	var scale: float = _icon_size.x / tex_w
	_content_half = Vector2(used.size.x, used.size.y) * 0.5 * scale
	_content_measured = true

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
	if not _show or _on_screen or _icon_tex == null:
		return
	draw_texture_rect(_icon_tex, Rect2(_anchor - _icon_size * 0.5, _icon_size), false)
