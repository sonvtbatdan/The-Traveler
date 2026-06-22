extends Control
## Arena weapon-slot bar. Five rounded-square slots pinned top-left, just below the HP/shield cluster.
## Empty until a weapon is acquired (chest pick or pickup); each filled slot shows the weapon icon plus a
## League-of-Legends-style cooldown pie — a dark translucent wedge over the icon that lifts CLOCKWISE from
## 12 o'clock as the weapon's cooldown/charge progresses. Reads arena_weapons.acquired_weapons() +
## weapon_cooldown_frac(kind) each frame. Pure read-only HUD (no input, no state of its own beyond an icon cache).

const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")

const ORIGIN := Vector2(12.0, 82.0)   # top-left of the first slot — ~8px (~0.2cm) below the HP bar's bottom edge
const SLOT   := 30.8                   # slot side (px) — 30% smaller than the original 44
const GAP    := 5.6                    # gap between slots (px) — 30% smaller than the original 8
const MASK_COL := Color(0.0, 0.0, 0.0, 0.58)   # cooldown wedge tint
const PULSE_SPEED := 11.0               # firing-pulse rate (rad/s)
const PULSE_AMT   := 0.07               # firing-pulse depth (±7% in-place scale)

var _weapons: Node = null
var _icons: Dictionary = {}   # kind → Texture2D (lazy cache)
var _t: float = 0.0           # animation clock for the firing pulse

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)

func _process(delta: float) -> void:
	_t += delta
	if _weapons == null or not is_instance_valid(_weapons):
		_weapons = get_tree().get_first_node_in_group("arena_weapons")
	queue_redraw()

func _icon_for(kind: String) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {})
	var tex := InventoryManager.get_icon(String(info.get("def_id", "")))
	_icons[kind] = tex
	return tex

func _draw() -> void:
	var acquired: Array = []
	if _weapons != null and is_instance_valid(_weapons) and _weapons.has_method("acquired_weapons"):
		acquired = _weapons.call("acquired_weapons")
	for i in ArenaWeapons.MAX_WEAPONS:
		# Base slot box; centre stays put so the firing pulse scales in place.
		var center := ORIGIN + Vector2(float(i) * (SLOT + GAP) + SLOT * 0.5, SLOT * 0.5)
		var rect := Rect2(ORIGIN + Vector2(float(i) * (SLOT + GAP), 0.0), Vector2(SLOT, SLOT))
		if i < acquired.size():
			var kind := String(acquired[i])
			# Slight in-place pulse while this weapon is actively firing.
			if _weapons.has_method("weapon_is_firing") and bool(_weapons.call("weapon_is_firing", kind)):
				var p := 1.0 + sin(_t * PULSE_SPEED) * PULSE_AMT
				var sz := SLOT * p
				rect = Rect2(center - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
			_draw_slot_bg(rect)
			var tex := _icon_for(kind)
			if tex != null:
				draw_texture_rect(tex, rect.grow(-rect.size.x * 0.09), false)
			var frac := 1.0
			if _weapons.has_method("weapon_cooldown_frac"):
				frac = float(_weapons.call("weapon_cooldown_frac", kind))
			if frac < 0.999:
				_draw_cooldown_pie(rect, frac)
		else:
			_draw_slot_bg(rect)
		_draw_slot_border(rect)

## Dim rounded-square backdrop (drawn under the icon).
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
	sb.border_color = Color(0.4, 0.52, 0.8, 0.95)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, rect)

## Dark wedge over the REMAINING cooldown. The revealed (ready) sector sweeps clockwise from 12 o'clock
## as `frac` (0 = just fired → fully masked, 1 = ready → no mask) grows; the wedge is the rest of the disc.
func _draw_cooldown_pie(rect: Rect2, frac: float) -> void:
	var center := rect.get_center()
	var radius := rect.size.x * 0.5
	var top := -PI * 0.5                       # 12 o'clock
	var a0 := top + frac * TAU                  # leading edge of the masked region (revealed ends here)
	var sweep := (1.0 - clampf(frac, 0.0, 1.0)) * TAU
	var steps := maxi(2, int(ceil(sweep / TAU * 48.0)))
	var pts := PackedVector2Array([center])
	for s in steps + 1:
		var a := a0 + sweep * float(s) / float(steps)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, MASK_COL)
