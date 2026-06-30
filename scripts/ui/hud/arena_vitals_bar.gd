extends Control
## Procedural player/boss vitals bar. The WHOLE box IS the bar (no container-with-inner-bar): a blue SHIELD
## layer fills the full box left→right, and a green HP layer fills the interior left→right — so the blue reads
## as the outer shield frame around the green HP. `mode = "player"` pins it bottom-center and reads the ship;
## `mode = "boss"` reads the boss (no shield), pins top-center, is GONE when no boss, and DROPS DOWN on spawn.

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const BAR_H := 50.0           # bar height (px)
const BAR_W_FRAC := 0.5       # bar width as a fraction of the viewport (matches the bezel footprint)
const BAR_W_MIN := 480.0
const BAR_W_MAX := 900.0
const SHIELD_PAD := 9.0       # HP interior inset → the blue band that shows is the shield "outer layer"
const BOTTOM_MARGIN := 14.0   # player: gap from the bottom screen edge
const TOP_MARGIN := 12.0      # boss: resting gap from the top screen edge (after the drop-down)
const DROP_TIME := 0.7        # boss bar drop-down duration (s)
const HP_COL    := Color(0.30, 0.85, 0.45, 0.97)
const HP_LOW    := Color(0.90, 0.30, 0.25, 0.97)
const SHIELD_COL := Color(0.30, 0.62, 1.0, 0.97)
const TRACK_COL := Color(0.05, 0.06, 0.09, 0.92)
const EDGE_COL  := Color(0.40, 0.55, 0.85, 0.9)

var mode: String = "player"
var _font: FontFile = null
var _boss_anim: float = 0.0   # boss drop-down progress 0 (hidden above) → 1 (fully dropped)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) as FontFile

func _process(delta: float) -> void:
	if mode == "boss":
		var active := GameManager.boss_max_hp > 0 and GameManager.boss_hp > 0
		if active:
			visible = true
			_boss_anim = minf(1.0, _boss_anim + delta / DROP_TIME)
		else:
			visible = false           # completely gone when there is no boss
			_boss_anim = 0.0
	queue_redraw()

func _bar_size() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(clampf(vp.x * BAR_W_FRAC, BAR_W_MIN, BAR_W_MAX), BAR_H)

func _origin() -> Vector2:
	var vp := get_viewport_rect().size
	var sz := _bar_size()
	var x := (vp.x - sz.x) * 0.5
	if mode == "player":
		return Vector2(x, vp.y - sz.y - BOTTOM_MARGIN)
	# Boss: slide from above the top edge down to TOP_MARGIN (eased).
	var t := smoothstep(0.0, 1.0, _boss_anim)
	var y := lerpf(-sz.y - 8.0, TOP_MARGIN, t)
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
	var sz := _bar_size()
	var box := Rect2(o, sz)
	# Dark track for the whole box (the bar's empty state).
	_rounded(box, TRACK_COL, 9.0)
	# SHIELD: blue, fills the whole box left→right by shield fraction (the "outer layer").
	var sh_max: float = v["sh_max"]
	var has_shield := sh_max > 0.0
	if has_shield:
		var sf := clampf(float(v["sh"]) / sh_max, 0.0, 1.0)
		if sf > 0.0:
			_rounded(Rect2(o, Vector2(sz.x * sf, sz.y)), SHIELD_COL, 9.0)
	# HP: green, fills left→right. Inset (leaving the blue shield frame) when a shield exists; full box otherwise.
	var inner := box.grow(-SHIELD_PAD) if has_shield else box
	var hf := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
	var hp_col: Color = HP_COL if hf > 0.3 else HP_LOW
	if hf > 0.0:
		_rounded(Rect2(inner.position, Vector2(inner.size.x * hf, inner.size.y)), hp_col, 6.0)
	# Thin edge so the bar reads on the busy battlefield (not a separate container — just the bar's rim).
	_edge(box, 9.0)
	# Readouts.
	if _font != null:
		var hp_txt := "%d / %d" % [int(round(v["hp"])), int(v["hp_max"])]
		draw_string(_font, Vector2(inner.position.x + 10.0, o.y + sz.y * 0.66),
			hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		if has_shield:
			var sh_txt := "SH %d / %d" % [int(round(v["sh"])), int(sh_max)]
			draw_string(_font, Vector2(o.x + sz.x - 120.0, o.y + sz.y * 0.66),
				sh_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.9, 1.0))

func _rounded(rect: Rect2, col: Color, r: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r))
	draw_style_box(sb, rect)

func _edge(rect: Rect2, r: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = EDGE_COL
	sb.set_corner_radius_all(int(r))
	draw_style_box(sb, rect)
