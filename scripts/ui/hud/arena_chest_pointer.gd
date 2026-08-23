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

const FONT        := preload("res://assets/fonts/mandalore/mandalore.ttf")
# How far the icon's REAL CONTENT edge sits inside the true screen edge when NO HUD bar is in the way — see
# this file's header (2026-08-19) for why this is now measured off content, not the padded icon box.
const EDGE_MARGIN := 10.0
const HUD_GAP      := 10.0    # same real-content-edge gap, kept specifically against HUD bars (_push_clear)
const ICON_WIDTH   := 84.0    # icon draw width AND height (arena_chest.gd's SubViewport render is square).
                               # 2026-08-19: 50 → 120 (matched the other pointer types) → 84 ("giảm chest size
                               # xuống còn 70%" of that 120 — chest reads smaller than landmark/rescue again).
const LABEL_GAP_PX := 5.0     # gap from the icon's REAL visible content edge, not its full bounding box —
                               # matches arena_ruin_pointer.gd's own LABEL_GAP_PX.
const HUD_AVOID_MACROS := ["Weapon", "Aux", "LV"]   # see arena_ruin_pointer.gd's own doc comment

var _chest: Node2D = null
var _player: Node2D = null
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
	_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
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
	_show = _chest != null and is_instance_valid(_chest) and _player != null and is_instance_valid(_player)
	_lbl.visible = _show
	if _show:
		var vp := get_viewport_rect().size
		var center := vp * 0.5
		var chest_screen := get_viewport().get_canvas_transform() * _chest.global_position
		var d := chest_screen - center
		_dir = d.normalized() if d.length() > 1.0 else Vector2.RIGHT
		# Clamp the icon's REAL CONTENT edge (not the padded bounding box) to the screen edge, inset by
		# EDGE_MARGIN, along the chest direction — see this file's header (2026-08-19) and
		# arena_ruin_pointer.gd's matching fix.
		var half := center - Vector2(EDGE_MARGIN, EDGE_MARGIN) - _content_half
		var tx := (half.x / absf(_dir.x)) if absf(_dir.x) > 0.0001 else 1.0e9
		var ty := (half.y / absf(_dir.y)) if absf(_dir.y) > 0.0001 else 1.0e9
		_anchor = center + _dir * minf(tx, ty)
		_anchor = _avoid_hud(_anchor)
		var dist := int(round(_player.global_position.distance_to(_chest.global_position)))
		_lbl.text = MandaloreText.a(str(dist))
		_lbl.reset_size()
		_lbl.position = Vector2(_anchor.x + _content_half.x + LABEL_GAP_PX, _anchor.y - _lbl.size.y * 0.5)   # gap measured from the REAL content edge, not the padded icon box
	queue_redraw()

## Measures the REAL visible content half-extent (_content_half, w×h in on-screen icon pixels) of the chest
## icon (a live SubViewport render, always square at ICON_WIDTH×ICON_WIDTH) via Image.get_used_rect() on ONE
## snapshot frame, taken the moment the texture first has real rendered content — mirrors arena_ruin_pointer.
## gd's own _measure_content() exactly (see that file's doc comment for the full rationale: a single snapshot
## rather than measuring every frame, since the chest spins continuously and re-measuring every frame would
## make the label visibly jitter as the silhouette's width/height change with rotation). Leaves the current
## fallback in place (and keeps retrying next frame) if the image can't be read yet.
func _measure_content() -> void:
	var img: Image = _icon_tex.get_image()
	if img == null:
		return
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	var tex_w := float(_icon_tex.get_width())
	if tex_w <= 0.0:
		return
	var scale: float = _icon_size.x / tex_w
	_content_half = Vector2(used.size.x, used.size.y) * 0.5 * scale
	_content_measured = true

## Nudges the icon's centre so its REAL CONTENT footprint (_content_half, ± EDGE_MARGIN) never overlaps the
## playerhud's Weapon/Aux/LV macro regions — verbatim port of arena_ruin_pointer.gd's own _avoid_hud/
## _push_clear (see that file's HUD_AVOID_MACROS doc comment for the full rationale, including the
## macro-scale gotcha).
func _avoid_hud(pos: Vector2) -> Vector2:
	if _hud_edit == null or not _hud_edit.has_method("get_binder"):
		return pos
	var binder = _hud_edit.call("get_binder")
	if binder == null or not binder.has_method("macro_global_rect"):
		return pos
	for key: String in HUD_AVOID_MACROS:
		var hud_rect: Rect2 = binder.call("macro_global_rect", key)
		pos = _push_clear(pos, hud_rect)
	return pos

## Minimum-translation push of a `_content_half*2`-sized box centered on `pos` fully outside `hud_rect`
## (grown by HUD_GAP on every side) — moves along whichever single axis (X or Y) clears the overlap with the
## smaller shift. Verbatim port of arena_ruin_pointer.gd's own _push_clear.
func _push_clear(pos: Vector2, hud_rect: Rect2) -> Vector2:
	if hud_rect.size.x <= 0.0 or hud_rect.size.y <= 0.0:
		return pos   # region doesn't exist right now (no weapons/aux owned yet, HUD Edit mode open, etc.)
	var blocked := hud_rect.grow(HUD_GAP)
	var icon_rect := Rect2(pos - _content_half, _content_half * 2.0)
	if not icon_rect.intersects(blocked):
		return pos
	var push_left  := icon_rect.end.x - blocked.position.x   # shift this far left to clear blocked's left edge
	var push_right := blocked.end.x - icon_rect.position.x   # shift this far right to clear blocked's right edge
	var push_up    := icon_rect.end.y - blocked.position.y   # shift this far up to clear blocked's top edge
	var push_down  := blocked.end.y - icon_rect.position.y   # shift this far down to clear blocked's bottom edge
	var min_x := minf(push_left, push_right)
	var min_y := minf(push_up, push_down)
	if min_x <= min_y:
		pos.x += -min_x if push_left <= push_right else min_x
	else:
		pos.y += -min_y if push_up <= push_down else min_y
	return pos

func _draw() -> void:
	if not _show or _icon_tex == null:
		return
	draw_texture_rect(_icon_tex, Rect2(_anchor - _icon_size * 0.5, _icon_size), false)
