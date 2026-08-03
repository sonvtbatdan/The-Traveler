extends Control
## Off-screen pointer to ONE giant dead-ship wreck: the wreck's own icon pinned to the screen edge in its
## direction, with the live distance printed level with it, snug against its right edge — both hidden once
## the wreck itself is visible on screen (the player has already located it, so the pointer is just clutter
## at that point). Unlike arena_chest_pointer.gd (which finds its single target by group), this holds a direct reference to a
## specific wreck so several can coexist — arena_ruin_layer.gd spawns one per wreck. When its wreck is
## destroyed, the pointer frees itself (and its parent CanvasLayer). Modeled on arena_chest_pointer.gd.

const FONT        := preload("res://assets/fonts/Gameplay.ttf")
const EDGE_MARGIN := 74.0     # how far inside the screen edge the icon sits
const ICON_WIDTH   := 50.0    # icon draw width (px) — height follows the source texture's aspect ratio

var _target: Node2D = null
var _player: Node2D = null
var _mgr: Node = null         # enemy_manager — visible_world_rect() for the on-screen check
var _anchor: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _show: bool = false
var _on_screen: bool = false
var _lbl: Label = null
var _icon_tex: Texture2D = null
var _icon_size: Vector2 = Vector2.ZERO

## Point this arrow at a specific wreck node.
func setup(target: Node2D) -> void:
	_target = target

func _ready() -> void:
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_lbl = Label.new()
	_lbl.add_theme_font_override("font", FONT)
	_lbl.add_theme_font_size_override("font_size", 12)
	_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_lbl.add_theme_constant_override("outline_size", 4)
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)

## Reuse the wreck's own already-loaded ship texture (arena_ruin.gd sets `_tex` in its own _load_tex(),
## called synchronously from setup() before this pointer exists) so the marker matches the actual wreck
## instead of a separate generic icon. Scaled to ICON_WIDTH, aspect ratio preserved (never stretched).
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

func _process(delta: float) -> void:
	# Wreck destroyed → its job is done; remove the pointer (and its dedicated CanvasLayer).
	if _target == null or not is_instance_valid(_target):
		var p := get_parent()
		if p is CanvasLayer:
			p.queue_free()
		else:
			queue_free()
		return
	if _icon_tex == null:
		_load_icon()
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_show = _player != null and is_instance_valid(_player)
	if _show:
		var vp := get_viewport_rect().size
		var center := vp * 0.5
		var target_screen := get_viewport().get_canvas_transform() * _target.global_position
		var d := target_screen - center
		_dir = d.normalized() if d.length() > 1.0 else Vector2.RIGHT
		# Clamp the icon to the screen edge (inset by EDGE_MARGIN) along the wreck's direction.
		var half := center - Vector2(EDGE_MARGIN, EDGE_MARGIN)
		var tx := (half.x / absf(_dir.x)) if absf(_dir.x) > 0.0001 else 1.0e9
		var ty := (half.y / absf(_dir.y)) if absf(_dir.y) > 0.0001 else 1.0e9
		_anchor = center + _dir * minf(tx, ty)
		# On-screen once the wreck itself sits inside the camera's visible world rect - the player can already
		# see it directly, so both the icon (_draw) and the distance label are redundant clutter at that point.
		_on_screen = false
		if _mgr != null and _mgr.has_method("visible_world_rect"):
			_on_screen = (_mgr.call("visible_world_rect") as Rect2).has_point(_target.global_position)
		_lbl.visible = not _on_screen
		if not _on_screen:
			var dist := int(round(_player.global_position.distance_to(_target.global_position)))
			_lbl.text = str(dist)
			_lbl.reset_size()
			_lbl.position = Vector2(_anchor.x + _icon_size.x * 0.5 + 6.0, _anchor.y - _lbl.size.y * 0.5)
	else:
		_lbl.visible = false
	queue_redraw()

func _draw() -> void:
	if not _show or _icon_tex == null or _on_screen:
		return
	draw_texture_rect(_icon_tex, Rect2(_anchor - _icon_size * 0.5, _icon_size), false)
