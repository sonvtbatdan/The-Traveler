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
## 2026-08-06 2nd follow-up ("offset giảm còn 10px. Chữ dịch vào gần object 5 pixel, thu nhỏ đi 2 font size"):
## EDGE_MARGIN 20→10, label gap 6→1px, font 14→12 (2 steps down from the original 16 across both requests).
##
## 2026-08-07 ("Text dịch sát lại indicator thêm 5 pixel, cả landmark và chest"): label gap 1 → -4px — the
## label's left edge now sits slightly inside the icon's right edge instead of just touching it. Same -5
## delta applied to arena_ruin_pointer.gd's own label gap (6 → 1px) in the same request.

const FONT        := preload("res://assets/fonts/mandalore/mandalore.ttf")
# How far the icon's OUTER edge sits inside the true screen edge when NO HUD bar is in the way — see
# arena_ruin_pointer.gd's own EDGE_MARGIN doc comment for the "applied to the footprint, not just the center
# point" nuance this also relies on.
const EDGE_MARGIN := 10.0
const HUD_GAP      := 10.0    # smaller gap kept specifically against HUD bars (_push_clear)
const ICON_WIDTH   := 50.0    # icon draw width AND height (arena_chest.gd's SubViewport render is square)
const HUD_AVOID_MACROS := ["Weapon", "Aux", "LV"]   # see arena_ruin_pointer.gd's own doc comment

var _chest: Node2D = null
var _player: Node2D = null
var _hud_edit: Node = null    # group "hud_edit" — the live playerhud host, for macro_global_rect() lookups
var _icon_tex: Texture2D = null
var _icon_size: Vector2 = Vector2(ICON_WIDTH, ICON_WIDTH)
var _anchor: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _show: bool = false
var _lbl: Label = null

func _ready() -> void:
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl = Label.new()
	_lbl.add_theme_font_override("font", FONT)
	_lbl.add_theme_font_size_override("font_size", 12)   # 2026-08-06: 16 → 14 → 12 ("thu nhỏ lại 2 font size" ×2)
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
		# Clamp the icon to the screen edge (inset by EDGE_MARGIN) along the chest direction. Subtracting
		# _icon_size*0.5 keeps the icon's OUTER edge (not just its center point, `_anchor`) at least
		# EDGE_MARGIN from the true screen edge — see arena_ruin_pointer.gd's own doc comment.
		var half := center - Vector2(EDGE_MARGIN, EDGE_MARGIN) - _icon_size * 0.5
		var tx := (half.x / absf(_dir.x)) if absf(_dir.x) > 0.0001 else 1.0e9
		var ty := (half.y / absf(_dir.y)) if absf(_dir.y) > 0.0001 else 1.0e9
		_anchor = center + _dir * minf(tx, ty)
		_anchor = _avoid_hud(_anchor)
		var dist := int(round(_player.global_position.distance_to(_chest.global_position)))
		_lbl.text = MandaloreText.a(str(dist))
		_lbl.reset_size()
		_lbl.position = Vector2(_anchor.x + _icon_size.x * 0.5 - 4.0, _anchor.y - _lbl.size.y * 0.5)   # 2026-08-07: 1 → -4, "dịch sát lại indicator thêm 5 pixel" (same -5 delta applied to arena_ruin_pointer.gd's 6→1)
	queue_redraw()

## Nudges the icon's centre so its footprint (icon_size, ± EDGE_MARGIN) never overlaps the playerhud's
## Weapon/Aux/LV macro regions — verbatim port of arena_ruin_pointer.gd's own _avoid_hud/_push_clear (see that
## file's HUD_AVOID_MACROS doc comment for the full rationale, including the macro-scale gotcha).
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

## Minimum-translation push of an `icon_size`-sized box centered on `pos` fully outside `hud_rect` (grown by
## HUD_GAP on every side) — moves along whichever single axis (X or Y) clears the overlap with the smaller
## shift. Verbatim port of arena_ruin_pointer.gd's own _push_clear.
func _push_clear(pos: Vector2, hud_rect: Rect2) -> Vector2:
	if hud_rect.size.x <= 0.0 or hud_rect.size.y <= 0.0:
		return pos   # region doesn't exist right now (no weapons/aux owned yet, HUD Edit mode open, etc.)
	var blocked := hud_rect.grow(HUD_GAP)
	var icon_rect := Rect2(pos - _icon_size * 0.5, _icon_size)
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
