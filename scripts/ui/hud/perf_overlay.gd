extends CanvasLayer

## DEV perf readout — ALWAYS ON, pinned to the upper-right corner. Shows FPS, this frame's time, a
## rolling 2s PEAK frame-time (so brief hitches are visible), and the live scene node count (rises as
## bullets accumulate). Turns red when the peak frame-time crosses ~20ms (≈ below 50 FPS). Use it to
## tell a real frame drop apart from a visual jitter at a steady 60.
## (No F8 toggle — F8 is Godot's editor "Stop" shortcut and would close the running game.)

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const HITCH_MS := 20.0   # peak frame-ms above this = a real dip → shown red

var _label: Label
var _peak_ms: float = 0.0
var _win_t: float = 0.0

func _ready() -> void:
	layer = 99
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep measuring even if the tree pauses
	_label = Label.new()
	# Pin to the upper-right corner, right-aligned.
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -320
	_label.offset_right = -10
	_label.offset_top = 8
	_label.offset_bottom = 110
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var f := load(FONT_PATH) as FontFile
	if f != null:
		_label.add_theme_font_override("font", f)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

func _process(delta: float) -> void:
	var ms := delta * 1000.0
	_peak_ms = maxf(_peak_ms, ms)
	_label.text = "FPS %d   frame %.1f ms\npeak(2s) %.1f ms   nodes %d" % [
		Engine.get_frames_per_second(), ms, _peak_ms, get_tree().get_node_count()]
	_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45) if _peak_ms > HITCH_MS else Color(0.7, 1.0, 0.7))
	_win_t += delta
	if _win_t >= 2.0:
		_win_t = 0.0
		_peak_ms = ms   # start a fresh 2s window
