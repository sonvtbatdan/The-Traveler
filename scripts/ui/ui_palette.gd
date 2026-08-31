extends RefCounted
class_name UiPalette
## Project UI design system — the "CRT phosphor console" identity applied across every code-built panel.
## Ported from the Electric Quest Board design doc (fonts + palette). Two ways to use it:
##
##   1. The global Theme (res://assets/ui/theme.tres, set as project.godot's gui/theme/custom) styles every
##      bare Control (Button/Panel/OptionButton/SpinBox/LineEdit/Slider/Tree/…) automatically — no code.
##   2. This script's tokens + helpers, for code that draws its own ColorRect / StyleBoxFlat / modulate or
##      needs a Font: `UiPalette.ACCENT`, `UiPalette.display(20)`, `UiPalette.panel_style()`, …
##
## Rebuild the Theme after changing anything here: `godot --headless --script tools/build_ui_theme.gd`.

# ── Palette (dark CRT — near-black with a green bias, phosphor text, one green accent + amber second) ──
const GROUND      := Color("0a0e0b")   # window / deepest ground, behind everything
const SURFACE     := Color("10160f")   # panel body
const SURFACE_2   := Color("141c12")   # inset field / raised row / header strip
const SURFACE_3   := Color("1b241a")   # hover / selected row
const INK         := Color("d8e4d3")   # primary text (phosphor off-white)
const MUTED       := Color("8ba086")   # secondary text
const FAINT       := Color("667a62")   # tertiary text / disabled / placeholder
const WIRE        := Color("223019")   # hairline border
const WIRE_2      := Color("2c3a22")   # stronger border / divider
const ACCENT      := Color("45e873")   # phosphor green — the one accent (matches the scan-line shader)
const ACCENT_INK  := Color("7cf59d")   # lighter green, for green text on the dark ground
const ACCENT_DIM  := Color("2b6f43")   # pressed / de-emphasised green
const ACCENT_WASH := Color(0.271, 0.910, 0.451, 0.14)   # ACCENT @ 14% — tint fills, hovered-row bg
const SELECT_WASH := Color(0.271, 0.910, 0.451, 0.40)   # ACCENT @ 40% — selected row / active toggle fill
const AMBER       := Color("ffb454")   # semantic second: "tracked", caution, highlight
const AMBER_WASH  := Color(1.0, 0.706, 0.329, 0.14)
const DANGER      := Color("ff6a5e")   # semantic: errors, "not enough", destructive
const GOOD        := Color("6ee787")   # semantic: owned / success / affordable

# ── Fonts ────────────────────────────────────────────────────────────────────────────────────────────
const F_DISPLAY      := "res://assets/fonts/ui/ChakraPetch-SemiBold.ttf"   # headings / titles / labels
const F_DISPLAY_BOLD := "res://assets/fonts/ui/ChakraPetch-Bold.ttf"        # big / emphatic headings
const F_DISPLAY_MED  := "res://assets/fonts/ui/ChakraPetch-Medium.ttf"
const F_BODY         := "res://assets/fonts/ui/IBMPlexSans-VF.ttf"          # body / running text (variable)
const F_MONO         := "res://assets/fonts/ui/IBMPlexMono-Regular.ttf"     # data / numbers / ids / code
const F_MONO_MED     := "res://assets/fonts/ui/IBMPlexMono-Medium.ttf"

static var _font_cache: Dictionary = {}

static func _font(path: String) -> Font:
	if not _font_cache.has(path):
		_font_cache[path] = load(path) as Font
	return _font_cache[path]

static func display(_size: int = 0) -> Font:      return _font(F_DISPLAY)
static func display_bold(_size: int = 0) -> Font: return _font(F_DISPLAY_BOLD)
static func body(_size: int = 0) -> Font:         return _font(F_BODY)
static func mono(_size: int = 0) -> Font:         return _font(F_MONO)

## Apply a font + size + colour to a Label/Button in one call (matches the `_font()` helpers scattered
## through the UI code — pass one of the F_* paths or leave `font` null for the theme default).
static func stamp(node: Control, font: String, size: int, col: Color = INK) -> void:
	if node == null:
		return
	if font != "":
		node.add_theme_font_override("font", _font(font))
	if size > 0:
		node.add_theme_font_size_override("font_size", size)
	if node is Label:
		node.add_theme_color_override("font_color", col)
	elif node is Button:
		node.add_theme_color_override("font_color", col)
		node.add_theme_color_override("font_hover_color", col.lerp(ACCENT_INK, 0.6))
		node.add_theme_color_override("font_pressed_color", ACCENT)

# ── StyleBox factories (for code that builds its own PanelContainer / row / field) ────────────────────
static func panel_style(radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = WIRE
	sb.set_content_margin_all(16.0)
	return sb

static func inset_style(radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE_2
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = WIRE_2
	sb.set_content_margin_all(11.0)
	return sb

## A left-accent-bar card (the quest-card / notice look). StyleBoxFlat has ONE border_color, so the accent
## edge is drawn as a thicker left border in that colour and the other three sides get a thin WIRE via a
## faint inner shadow substitute — good enough; use two stacked panels if a true 2-colour frame is needed.
static func card_style(accent: Color = ACCENT, radius: int = 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(radius)
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = accent
	sb.set_content_margin_all(18.0)
	sb.content_margin_left = 20.0
	return sb

static func dim_scrim(alpha: float = 0.72) -> Color:
	return Color(GROUND.r, GROUND.g, GROUND.b, alpha)
