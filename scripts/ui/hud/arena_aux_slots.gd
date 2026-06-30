extends Control
## Arena auxiliary-item slot bar. A SECOND row of five rounded-square slots directly below the weapon slots
## (arena_weapon_slots.gd). Empty until an aux item is acquired from the level-up screen; each filled slot shows
## the item's placeholder colour swatch (no art yet) plus its level as small pips along the bottom edge.
## Pure read-only HUD: reads arena_aux.owned_aux() / aux_level(id) / def_for(id) each frame.

const ArenaAux := preload("res://scripts/gameplay/arena_aux.gd")

# Same slot size/gap as the weapon row; placed one row lower (weapon ORIGIN.y 82 + SLOT 30.8 + 10 gap).
const SLOT   := 46.0                   # slot side (px) — right-edge vertical column (matches weapon column)
const GAP    := 12.0
const RIGHT_MARGIN := 16.0             # x of the column from the right screen edge

## i-th slot rect: a vertical column pinned to the right edge, vertically centered on screen.
func _slot_rect(i: int) -> Rect2:
	var vp := get_viewport_rect().size
	var n := ArenaAux.MAX_AUX
	var total_h := SLOT * float(n) + GAP * float(n - 1)
	var y0 := (vp.y - total_h) * 0.5
	return Rect2(Vector2(vp.x - RIGHT_MARGIN - SLOT, y0 + float(i) * (SLOT + GAP)), Vector2(SLOT, SLOT))
const PIP_COL    := Color(1.0, 1.0, 1.0, 0.95)
const PIP_OFF    := Color(0.0, 0.0, 0.0, 0.45)

var _aux: Node = null   # arena_aux node (group "arena_aux")
var _icons: Dictionary = {}   # id → Texture2D (lazy cache; null = no art → fall back to the colour swatch)

func _icon_for(id: String, d: Dictionary) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var tex: Texture2D = null
	var path := String(d.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_icons[id] = tex
	return tex

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)

func _process(_delta: float) -> void:
	if _aux == null or not is_instance_valid(_aux):
		_aux = get_tree().get_first_node_in_group("arena_aux")
	queue_redraw()

func _draw() -> void:
	var owned: Array = []
	if _aux != null and is_instance_valid(_aux) and _aux.has_method("owned_aux"):
		owned = _aux.call("owned_aux")
	for i in ArenaAux.MAX_AUX:
		var rect := _slot_rect(i)
		_draw_slot_bg(rect)
		if i < owned.size():
			var id := String(owned[i])
			var d: Dictionary = _aux.call("def_for", id)
			var tex := _icon_for(id, d)
			if tex != null:
				draw_texture_rect(tex, rect.grow(-3.0), false)   # near-full: maximize icon inside the slot
			else:
				var col: Color = d.get("color", Color.GRAY)
				draw_rect(rect.grow(-6.0), col, true)            # colour swatch fallback
			# Level pips along the bottom edge.
			var lvl := int(_aux.call("aux_level", id))
			_draw_level_pips(rect, lvl)
		_draw_slot_border(rect)

## Dim rounded-square backdrop (drawn under the swatch).
func _draw_slot_bg(rect: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.85)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, rect)

## Rounded-square outline (drawn over everything).
func _draw_slot_border(rect: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.45, 0.78, 0.55, 0.95)   # green-tinted to distinguish from the weapon row
	sb.set_corner_radius_all(8)
	draw_style_box(sb, rect)

## Up to MAX_AUX_LEVEL small pips across the bottom; filled = current level.
func _draw_level_pips(rect: Rect2, level: int) -> void:
	var n := ArenaAux.MAX_AUX_LEVEL
	var r := 1.6
	var span := rect.size.x * 0.74
	var step := span / float(n)
	var y := rect.position.y + rect.size.y - 4.0
	var x0 := rect.get_center().x - span * 0.5 + step * 0.5
	for p in n:
		var c := PIP_COL if p < level else PIP_OFF
		draw_circle(Vector2(x0 + step * float(p), y), r, c)
