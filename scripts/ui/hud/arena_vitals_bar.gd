extends Control
## Procedural player/boss vitals bar: an OUTER shield layer (blue, fills left→right) framing an INNER main
## HP box (fills left→right), with HP and shield readouts. One widget, two modes — `mode = "player"` pins it
## bottom-center and reads the ship's HP/shield; `mode = "boss"` pins it top-center, reads the boss HP (shield
## 0), and is visible only during a boss fight. Poll-based (reads GameManager each frame) for robustness.

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const BAR_W := 440.0          # bar width (px)
const BAR_H := 46.0           # bar height (px)
const SHIELD_PAD := 7.0       # HP inner box inset from the shield outer frame (the visible shield band)
const BOTTOM_MARGIN := 16.0   # player: gap from the bottom screen edge
const TOP_MARGIN := 12.0      # boss: gap from the top screen edge
const HP_COL    := Color(0.30, 0.85, 0.45, 0.95)
const HP_LOW    := Color(0.90, 0.30, 0.25, 0.95)
const SHIELD_COL := Color(0.35, 0.70, 1.0, 0.95)
const TRACK_COL := Color(0.05, 0.06, 0.09, 0.9)
const BORDER_COL := Color(0.4, 0.55, 0.85, 0.95)

var mode: String = "player"
var _font: FontFile = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) as FontFile

func _process(_delta: float) -> void:
	if mode == "boss":
		visible = GameManager.boss_max_hp > 0 and GameManager.boss_hp > 0
	queue_redraw()

func _origin() -> Vector2:
	var vp := get_viewport_rect().size
	var x := (vp.x - BAR_W) * 0.5
	var y := (vp.y - BAR_H - BOTTOM_MARGIN) if mode == "player" else TOP_MARGIN
	return Vector2(x, y)

func _vitals() -> Dictionary:
	if mode == "boss":
		var bmax := float(maxi(1, GameManager.boss_max_hp))
		return {"hp": float(GameManager.boss_hp), "hp_max": bmax, "sh": 0.0, "sh_max": 0.0}
	var hpmax := float(maxi(1, GameManager.ship_max_hp))
	var shmax: float = GameManager.shield_capacity_total() if GameManager.has_method("shield_capacity_total") else 0.0
	return {"hp": float(GameManager.ship_hp), "hp_max": hpmax, "sh": GameManager.ship_shield, "sh_max": shmax}

func _draw() -> void:
	if mode == "boss" and not visible:
		return
	var v := _vitals()
	var o := _origin()
	var outer := Rect2(o, Vector2(BAR_W, BAR_H))
	# Shield outer layer: dark track + blue L→R fill (shows as a band around the HP box).
	_rounded(outer, TRACK_COL, 8.0)
	var sh_max: float = v["sh_max"]
	if sh_max > 0.0:
		var sf := clampf(float(v["sh"]) / sh_max, 0.0, 1.0)
		_rounded(Rect2(o, Vector2(BAR_W * sf, BAR_H)), SHIELD_COL, 8.0)
	# HP inner main box: dark track + L→R fill.
	var inner := outer.grow(-SHIELD_PAD)
	_rounded(inner, TRACK_COL, 6.0)
	var hf := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
	var hp_col: Color = HP_COL if hf > 0.3 else HP_LOW
	_rounded(Rect2(inner.position, Vector2(inner.size.x * hf, inner.size.y)), hp_col, 6.0)
	# Border around the whole bar.
	_border(outer, BORDER_COL, 8.0)
	# Readouts: HP on the inner box, shield small at the top-right of the outer frame.
	if _font != null:
		var hp_txt := "%d / %d" % [int(round(v["hp"])), int(v["hp_max"])]
		draw_string(_font, Vector2(inner.position.x + 8.0, inner.position.y + inner.size.y * 0.72),
			hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		if sh_max > 0.0:
			var sh_txt := "SH %d / %d" % [int(round(v["sh"])), int(sh_max)]
			draw_string(_font, Vector2(o.x + BAR_W - 110.0, o.y + 13.0),
				sh_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SHIELD_COL)

func _rounded(rect: Rect2, col: Color, r: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r))
	draw_style_box(sb, rect)

func _border(rect: Rect2, col: Color, r: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = col
	sb.set_corner_radius_all(int(r))
	draw_style_box(sb, rect)
