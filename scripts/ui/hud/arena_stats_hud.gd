extends Control
## Arena run HUD: an XP bar across the bottom of the screen (fills toward the next level-up) plus a
## top-right kill + coin counter. Reads GameManager run state and re-pins itself on viewport resize.
## Hosted in the arena "UI" CanvasLayer (screen space) — see arena._build_ui().

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"

# ── XP bar geometry ──
const XP_H            := 24.0    # bar height
const XP_BOTTOM_MARGIN := 6.0    # hug the bottom screen edge (the vitals bar sits above it)
const XP_W_FRAC       := 0.5     # bar width — matches the vitals bar so they stack as one column
const XP_W_MIN        := 480.0
const XP_W_MAX        := 900.0
const XP_PAD          := 10.0    # text inset from the bar's left/right edges

# ── Top-right counters geometry ──
const TR_TOP          := 118.0   # start below the perf overlay (which occupies y 8–110)
const TR_RIGHT_MARGIN := 12.0
const TR_BLOCK_W      := 130.0   # icon + number block width
const TR_ICON         := 26.0
const TR_ROW_H        := 30.0
const TR_ROW_GAP      := 6.0
const TR_ICON_GAP     := 8.0

var _font: FontFile = null

# XP bar nodes
var _xp_bg:    ColorRect = null
var _xp_fill:  ColorRect = null
var _xp_label: Label     = null   # left: "xp / require"
var _lv_label: Label     = null   # right: "Level N"

# Top-right counter nodes
var _kill_icon:  ColorRect = null
var _kill_label: Label     = null
var _coin_icon:  ColorRect = null
var _coin_label: Label     = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) as FontFile
	_build()
	get_viewport().size_changed.connect(_relayout)
	# Connect live updates.
	GameManager.xp_changed.connect(_on_xp_changed)
	GameManager.level_changed.connect(_on_level_changed)
	GameManager.money_changed.connect(_on_money_changed)
	GameManager.kills_changed.connect(_on_kills_changed)
	# Prime with current values.
	_on_level_changed(GameManager.player_level)
	_on_money_changed(GameManager.money)
	_on_kills_changed(GameManager.run_kills if "run_kills" in GameManager else 0)
	call_deferred("_relayout")   # viewport size is reliable after the first frame

func _build() -> void:
	# ── XP bar ──
	_xp_bg = ColorRect.new()
	_xp_bg.color = Color(0.05, 0.06, 0.09, 0.85)
	_xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_bg)

	_xp_fill = ColorRect.new()
	_xp_fill.color = Color(0.30, 0.85, 0.45, 0.95)   # green progress
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_fill)

	_xp_label = _make_label(Color("#EAF7E8"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_xp_label)

	_lv_label = _make_label(Color("#FBF662"), HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_lv_label)

	# ── Top-right counters ──
	_kill_icon = _make_icon(Color(0.85, 0.25, 0.25, 0.9))   # placeholder square — swap for a kill icon later
	add_child(_kill_icon)
	_kill_label = _make_label(Color("#FFE7E7"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_kill_label)

	_coin_icon = _make_icon(Color(0.95, 0.80, 0.20, 0.95))  # placeholder square — swap for a coin icon later
	add_child(_coin_icon)
	_coin_label = _make_label(Color("#FFF4C2"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_coin_label)

func _make_label(color: Color, halign: int) -> Label:
	var lbl := Label.new()
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _make_icon(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = Vector2(TR_ICON, TR_ICON)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Position everything from the current viewport size (called on resize + once deferred at start).
func _relayout() -> void:
	var vp := get_viewport_rect().size

	# XP bar — centered horizontally, pinned near the bottom edge.
	var bar_w := clampf(vp.x * XP_W_FRAC, XP_W_MIN, XP_W_MAX)
	var bar_x := (vp.x - bar_w) * 0.5
	var bar_y := vp.y - XP_H - XP_BOTTOM_MARGIN
	_xp_bg.position = Vector2(bar_x, bar_y)
	_xp_bg.size = Vector2(bar_w, XP_H)
	_xp_fill.position = Vector2(bar_x, bar_y)   # width set by _refresh_xp_fill()
	_xp_label.position = Vector2(bar_x + XP_PAD, bar_y)
	_xp_label.size = Vector2(bar_w - XP_PAD * 2.0, XP_H)
	_lv_label.position = Vector2(bar_x + XP_PAD, bar_y)
	_lv_label.size = Vector2(bar_w - XP_PAD * 2.0, XP_H)
	_refresh_xp_fill()

	# Top-right counters — two stacked rows under the perf overlay.
	var block_x := vp.x - TR_RIGHT_MARGIN - TR_BLOCK_W
	var label_x := block_x + TR_ICON + TR_ICON_GAP
	var label_w := TR_BLOCK_W - TR_ICON - TR_ICON_GAP
	var icon_y_off := (TR_ROW_H - TR_ICON) * 0.5

	var row0_y := TR_TOP
	_kill_icon.position = Vector2(block_x, row0_y + icon_y_off)
	_kill_label.position = Vector2(label_x, row0_y)
	_kill_label.size = Vector2(label_w, TR_ROW_H)

	var row1_y := TR_TOP + TR_ROW_H + TR_ROW_GAP
	_coin_icon.position = Vector2(block_x, row1_y + icon_y_off)
	_coin_label.position = Vector2(label_x, row1_y)
	_coin_label.size = Vector2(label_w, TR_ROW_H)

# ── Live updates ──
func _on_xp_changed(xp: int, xp_to_next: int) -> void:
	_xp_label.text = "%d / %d" % [xp, xp_to_next]
	_refresh_xp_fill()

func _on_level_changed(level: int) -> void:
	_lv_label.text = "Level %d" % level
	# Refresh the bar text/fill against the new threshold even if xp_changed fires separately.
	_on_xp_changed(GameManager.player_xp, GameManager.xp_to_next(level))

func _on_money_changed(amount: int) -> void:
	_coin_label.text = str(amount)

func _on_kills_changed(kills: int) -> void:
	_kill_label.text = str(kills)

## Scale the green fill to the current XP fraction (uses the bg's current width).
func _refresh_xp_fill() -> void:
	if _xp_bg == null or _xp_fill == null:
		return
	var to_next := GameManager.xp_to_next(GameManager.player_level)
	var frac := 0.0
	if to_next > 0:
		frac = clampf(float(GameManager.player_xp) / float(to_next), 0.0, 1.0)
	_xp_fill.size = Vector2(_xp_bg.size.x * frac, XP_H)
