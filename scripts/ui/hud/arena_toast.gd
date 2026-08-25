extends RefCounted
class_name ArenaToast
## Shared in-arena pop-up toast (2026-08-06, on request) — fades in/out top-center of the gameplay view.
## Two current callers:
##   - electric_ruin_layer.gd / volcanic_ruin_layer.gd: "<name> has been taken on your ship" the instant a
##     rescue-character landmark is destroyed, independent of how the run eventually ends (that separate
##     outcome shows on the RUN OVER/BOSS ELIMINATED screen, see arena.gd's _show_run_over).
##   - arena_levelup_ui.gd: "<weapon name> Blueprint Acquired" the instant a brand-new weapon is picked from
##     a level-up/reward choice screen (_apply()'s "weapon"+"new" branch).
## Distinct from hub_screen.gd's own _show_notice (top-right, Dock-only) since this fires mid-combat and
## shouldn't compete with HUD chrome that also lives near the top edge.
##
## `show()` is a static entry point (no instance state to keep) — `host` just needs to be a live Node so it
## can own the temporary CanvasLayer/Tween it creates.

const FONT_BODY := "res://assets/fonts/mandalore/mandalore.ttf"
const LIFETIME := 3.0

## `corner` picks where the toast sits. "top" (default) is the original top-centre placement every existing
## caller uses; "bottom_right" (2026-08-25, on request for the elite/champion weapon drop pickup) tucks it
## into the lower-right, clear of the top-centre chrome and of the bottom-centre HP/Shield/Level bars.
static func show(host: Node, text: String, corner: String = "top") -> void:
	var cl := CanvasLayer.new()
	cl.layer = 60   # above gameplay + the edge-of-screen ruin pointer (55), below settings/overlays
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(cl)

	var lbl := Label.new()
	var font := load(FONT_BODY) as Font
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.text = MandaloreText.a(text)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if corner == "bottom_right":
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lbl.offset_left = -640.0
		lbl.offset_right = -24.0
		lbl.offset_top = -96.0
		lbl.offset_bottom = -56.0
	else:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
		lbl.offset_left = -280.0
		lbl.offset_right = 280.0
		lbl.offset_top = 60.0
		lbl.offset_bottom = 100.0
	lbl.modulate.a = 0.0
	cl.add_child(lbl)

	var tw := host.create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.2)
	tw.tween_interval(LIFETIME)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(cl.queue_free)
