@tool
extends SceneTree
## Builds res://assets/ui/theme.tres — the project-wide "CRT phosphor console" UI theme.
## Palette + font paths are the single source of truth in scripts/ui/ui_palette.gd; this only assembles
## them into control styleboxes. Re-run after changing the palette:
##     godot --headless --script tools/build_ui_theme.gd
##
## Note: run as a --script tool (no autoloads needed). Fonts must be imported first
## (godot --headless --editor --quit) or load() returns null and the theme falls back to the engine font.

const OUT := "res://assets/ui/theme.tres"

# Mirror of UiPalette (can't preload a class_name script reliably in a bare --script SceneTree without the
# global class cache; keep these two in sync — UiPalette is the human source of truth).
const GROUND    := Color("0a0e0b")
const SURFACE   := Color("10160f")
const SURFACE_2 := Color("141c12")
const SURFACE_3 := Color("1b241a")
const INK       := Color("d8e4d3")
const MUTED     := Color("8ba086")
const FAINT     := Color("667a62")
const WIRE      := Color("223019")
const WIRE_2    := Color("2c3a22")
const ACCENT    := Color("45e873")
const ACCENT_INK:= Color("7cf59d")
const ACCENT_DIM:= Color("2b6f43")
const ACCENT_WASH := Color(0.271, 0.910, 0.451, 0.14)
const DANGER    := Color("ff6a5e")

const F_DISPLAY     := "res://assets/fonts/ui/ChakraPetch-SemiBold.ttf"
const F_DISPLAY_MED := "res://assets/fonts/ui/ChakraPetch-Medium.ttf"
const F_BODY        := "res://assets/fonts/ui/IBMPlexSans-VF.ttf"
const F_MONO        := "res://assets/fonts/ui/IBMPlexMono-Regular.ttf"

func _init() -> void:
	var th := Theme.new()

	var f_body := load(F_BODY) as Font
	var f_disp := load(F_DISPLAY) as Font
	var f_disp_med := load(F_DISPLAY_MED) as Font
	var f_mono := load(F_MONO) as Font
	if f_body == null or f_disp == null or f_mono == null:
		push_error("[build_ui_theme] fonts not imported — run `godot --headless --editor --quit` first")
		quit(1)
		return

	th.default_font = f_body
	th.default_font_size = 15

	# ── Label ────────────────────────────────────────────────────────────────
	th.set_color("font_color", "Label", INK)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	th.set_color("font_outline_color", "Label", GROUND)

	# ── RichTextLabel ────────────────────────────────────────────────────────
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0))

	# ── Button family ────────────────────────────────────────────────────────
	for t in ["Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton"]:
		th.set_font("font", t, f_disp_med)
		th.set_font_size("font_size", t, 14)
		th.set_color("font_color", t, INK)
		th.set_color("font_hover_color", t, ACCENT_INK)
		th.set_color("font_pressed_color", t, ACCENT)
		th.set_color("font_focus_color", t, INK)
		th.set_color("font_hover_pressed_color", t, ACCENT)
		th.set_color("font_disabled_color", t, FAINT)
		th.set_color("font_outline_color", t, GROUND)
		th.set_stylebox("normal", t, _btn(SURFACE_2, WIRE_2))
		th.set_stylebox("hover", t, _btn(SURFACE_3, ACCENT))
		th.set_stylebox("pressed", t, _btn(ACCENT_DIM, ACCENT))
		th.set_stylebox("hover_pressed", t, _btn(ACCENT_DIM, ACCENT))
		th.set_stylebox("disabled", t, _btn(SURFACE, WIRE))
		th.set_stylebox("focus", t, _focus())

	# OptionButton dropdown arrow area reads better a touch tighter
	th.set_color("font_color", "OptionButton", INK)

	# ── LineEdit / TextEdit / SpinBox entry ──────────────────────────────────
	for t in ["LineEdit", "TextEdit", "CodeEdit"]:
		th.set_font("font", t, f_mono)
		th.set_font_size("font_size", t, 14)
		th.set_color("font_color", t, INK)
		th.set_color("font_placeholder_color", t, FAINT)
		th.set_color("font_selected_color", t, GROUND)
		th.set_color("caret_color", t, ACCENT)
		th.set_color("selection_color", t, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.30))
		th.set_stylebox("normal", t, _field(SURFACE_2, WIRE_2))
		th.set_stylebox("focus", t, _field(SURFACE_2, ACCENT))
		th.set_stylebox("read_only", t, _field(SURFACE, WIRE))

	# ── Panels ───────────────────────────────────────────────────────────────
	th.set_stylebox("panel", "PanelContainer", _panel(SURFACE, WIRE, 6))
	th.set_stylebox("panel", "Panel", _panel(SURFACE, WIRE, 6))
	th.set_stylebox("panel", "PopupPanel", _panel(SURFACE_2, ACCENT_DIM, 5))

	# ── PopupMenu ────────────────────────────────────────────────────────────
	th.set_font("font", "PopupMenu", f_body)
	th.set_font_size("font_size", "PopupMenu", 14)
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", ACCENT)
	th.set_color("font_accelerator_color", "PopupMenu", MUTED)
	th.set_color("font_disabled_color", "PopupMenu", FAINT)
	th.set_color("font_separator_color", "PopupMenu", MUTED)
	th.set_stylebox("panel", "PopupMenu", _panel(SURFACE_2, ACCENT_DIM, 5))
	th.set_stylebox("hover", "PopupMenu", _flat(ACCENT_WASH, 3))
	th.set_stylebox("separator", "PopupMenu", _line(WIRE_2))
	th.set_stylebox("labeled_separator_left", "PopupMenu", _line(WIRE_2))
	th.set_stylebox("labeled_separator_right", "PopupMenu", _line(WIRE_2))

	# ── Separators ───────────────────────────────────────────────────────────
	th.set_stylebox("separator", "HSeparator", _line(WIRE_2))
	th.set_stylebox("separator", "VSeparator", _line(WIRE_2))
	th.set_constant("separation", "HSeparator", 4)
	th.set_constant("separation", "VSeparator", 4)

	# ── Sliders ──────────────────────────────────────────────────────────────
	for t in ["HSlider", "VSlider"]:
		th.set_stylebox("slider", t, _track(SURFACE_2))
		th.set_stylebox("grabber_area", t, _track(ACCENT))
		th.set_stylebox("grabber_area_highlight", t, _track(ACCENT_INK))

	# ── ProgressBar ──────────────────────────────────────────────────────────
	th.set_stylebox("background", "ProgressBar", _field(SURFACE_2, WIRE_2))
	th.set_stylebox("fill", "ProgressBar", _flat(ACCENT, 3))
	th.set_color("font_color", "ProgressBar", INK)

	# ── ScrollBars ───────────────────────────────────────────────────────────
	for t in ["HScrollBar", "VScrollBar"]:
		th.set_stylebox("scroll", t, _flat(Color(SURFACE_2.r, SURFACE_2.g, SURFACE_2.b, 0.6), 3))
		th.set_stylebox("grabber", t, _flat(WIRE_2, 3))
		th.set_stylebox("grabber_highlight", t, _flat(ACCENT_DIM, 3))
		th.set_stylebox("grabber_pressed", t, _flat(ACCENT, 3))

	# ── TabBar / TabContainer ────────────────────────────────────────────────
	for t in ["TabBar", "TabContainer"]:
		th.set_font("font", t, f_disp_med)
		th.set_font_size("font_size", t, 14)
		th.set_color("font_selected_color", t, ACCENT_INK)
		th.set_color("font_unselected_color", t, MUTED)
		th.set_color("font_hovered_color", t, INK)
		th.set_stylebox("tab_selected", t, _tab(SURFACE, ACCENT))
		th.set_stylebox("tab_hovered", t, _tab(SURFACE_3, WIRE_2))
		th.set_stylebox("tab_unselected", t, _tab(SURFACE_2, WIRE))
	th.set_stylebox("panel", "TabContainer", _panel(SURFACE, WIRE, 6))

	# ── Tree / ItemList ──────────────────────────────────────────────────────
	for t in ["Tree", "ItemList"]:
		th.set_font("font", t, f_body)
		th.set_font_size("font_size", t, 14)
		th.set_color("font_color", t, INK)
		th.set_color("font_selected_color", t, GROUND)
		th.set_stylebox("panel", t, _panel(SURFACE, WIRE, 5))
		th.set_stylebox("selected", t, _flat(ACCENT_WASH, 3))
		th.set_stylebox("selected_focus", t, _flat(ACCENT_WASH, 3))
		th.set_stylebox("hovered", t, _flat(Color(INK.r, INK.g, INK.b, 0.04), 3))
	th.set_color("guide_color", "Tree", WIRE)
	th.set_color("font_selected_color", "Tree", ACCENT)
	th.set_color("font_selected_color", "ItemList", ACCENT)

	# ── Tooltip ──────────────────────────────────────────────────────────────
	th.set_stylebox("panel", "TooltipPanel", _panel(SURFACE_2, ACCENT_DIM, 4))
	th.set_color("font_color", "TooltipLabel", INK)

	var err := ResourceSaver.save(th, OUT)
	if err != OK:
		push_error("[build_ui_theme] save failed: %d" % err)
		quit(1)
		return
	print("[build_ui_theme] wrote ", OUT)
	quit(0)

# ── stylebox helpers ────────────────────────────────────────────────────────
func _flat(col: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	return sb

func _btn(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb

func _field(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb

func _panel(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_content_margin_all(14.0)
	return sb

func _focus() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = ACCENT
	return sb

func _line(col: Color) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = col
	sb.thickness = 1
	return sb

func _track(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(2)
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	return sb

func _tab(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_color = border
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0
	return sb
