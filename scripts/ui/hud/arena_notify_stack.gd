extends RefCounted
class_name ArenaNotifyStack
## Stacking notification system for elite/champion item-drop pickups that fall through to the backpack
## (arena_item_drop.gd's "…inventory FULL" / "…has been acquired. Press I to view" lines) — 2026-08-28, on
## request. arena_toast.gd's plain `show()` is a single fixed-position fading Label with no memory of earlier
## calls: two pickups close together used to render directly on top of each other instead of stacking. This
## keeps a small PERSISTENT container (found-or-built once per run, via group "arena_notify_stack" — same
## lazy-singleton pattern the rest of this codebase already uses for enemy_manager/hud_edit/etc.) so every new
## call adds one more row instead of starting from scratch.
##
## Layout: bottom-right, phone-lock-screen style — a rounded, semi-transparent dark card per notification with
## a left accent stripe, smaller font than arena_toast.gd's own 22px (this is meant to be read at a glance
## alongside the fight, not centre-stage). `VBoxContainer.alignment = ALIGNMENT_END` packs rows toward the
## BOTTOM of the container, and each new row is simply APPENDED (added as the last child) — since a
## VBoxContainer lays its children out top-to-bottom in child order, the newest row therefore lands at the
## bottom (the anchor point) and every earlier row is pushed upward to make room, exactly matching the user's
## own description ("dòng thông báo mới sẽ xuất hiện và đẩy dòng thông báo cũ lên trên"). Each row fades
## in/out and frees itself independently — an old row disappearing doesn't reflow anything below it, the
## container's own auto-layout (SHRINK_END) closes the gap for free.

const FONT_PATH := "res://assets/fonts/mandalore/mandalore.ttf"
const FONT_SIZE := 15            # notably smaller than arena_toast.gd's 22px — "giảm font size xuống 3 size"
const LIFETIME  := 3.0           # matches arena_toast.gd's own hold time
const ROW_W     := 340.0
const ROW_H     := 44.0
const ROW_GAP   := 8.0
const MARGIN_RIGHT  := 24.0
const MARGIN_BOTTOM := 96.0      # clears the bottom-centre HP/Shield/Level HUD bar — same margin
                                  # arena_toast.gd's own "bottom_right" corner already used
const CARD_BG      := Color(0.063, 0.086, 0.059, 0.9)   # UiPalette.SURFACE @ ~0.9 alpha
const CARD_ACCENT  := Color(1.0, 0.85, 0.2, 0.9)     # left stripe — same gold as arena_toast.gd's text
const TEXT_COLOR   := Color(0.847, 0.894, 0.827)     # UiPalette.INK
const TEXT_OUTLINE := Color(0.0, 0.0, 0.0, 0.6)

## Public entry point — mirrors arena_toast.gd's own show(host, text) shape so call sites read the same way.
static func show(host: Node, text: String) -> void:
	var stack := _get_or_build_stack(host)
	var row := _build_row(text)
	stack.add_child(row)
	var tw := host.create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.15)
	tw.tween_interval(LIFETIME)
	tw.tween_property(row, "modulate:a", 0.0, 0.35)
	tw.tween_callback(row.queue_free)

## Finds the persistent stack container (group "arena_notify_stack"), or builds it once. Lives for the whole
## run — cheap when empty (one CanvasLayer + one VBoxContainer, no rows), so there's nothing to tear down.
static func _get_or_build_stack(host: Node) -> VBoxContainer:
	var existing := host.get_tree().get_first_node_in_group("arena_notify_stack")
	if existing != null and is_instance_valid(existing):
		return existing as VBoxContainer
	var cl := CanvasLayer.new()
	cl.layer = 60   # same tier as arena_toast.gd's own CanvasLayer
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(cl)
	var box := VBoxContainer.new()
	box.add_to_group("arena_notify_stack")
	box.alignment = BoxContainer.ALIGNMENT_END   # pack toward the bottom — see this file's header
	box.add_theme_constant_override("separation", int(ROW_GAP))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -(ROW_W + MARGIN_RIGHT)
	box.offset_right = -MARGIN_RIGHT
	box.offset_top = -800.0     # generous — the container SHRINKs to its actual content, this just bounds it
	box.offset_bottom = -MARGIN_BOTTOM
	box.size_flags_vertical = Control.SIZE_SHRINK_END
	cl.add_child(box)
	return box

## One notification "card" — a rounded dark panel with a gold accent stripe, matching a phone lock-screen
## notification's silhouette, holding a single (auto-wrapping) label.
static func _build_row(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ROW_W, ROW_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.set_corner_radius_all(0)
	sb.border_color = CARD_ACCENT
	sb.set_border_width_all(0)
	sb.border_width_left = 4   # left accent stripe only
	sb.content_margin_left = 14.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	var font := load(FONT_PATH) as Font
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.add_theme_color_override("font_color", TEXT_COLOR)
	lbl.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.text = MandaloreText.a(text)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel
