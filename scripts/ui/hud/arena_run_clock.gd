extends CanvasLayer
## Run timer pinned to the upper-right corner. Counts elapsed real time of the current run, but FREEZES
## whenever the scene tree is paused (level-up card, pause menu, settings) — it runs at PROCESS_MODE_PAUSABLE
## and accumulates delta, so paused frames simply don't tick. A fresh instance is built per run, so it
## always starts at 0. Mirrors perf_overlay.gd's top-right pinning.

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"

var _elapsed: float = 0.0
var _label: Label
var _shown_sec: int = -1

func _ready() -> void:
	layer = 98                                     # above gameplay, below the perf overlay (99) / overlays (100)
	process_mode = Node.PROCESS_MODE_PAUSABLE      # freeze the clock while the game is paused (menu / level-up)
	add_to_group("run_clock")
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -170
	_label.offset_right = -14
	_label.offset_top = 8
	_label.offset_bottom = 44
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := load(FONT_PATH) as FontFile
	if f != null:
		_label.add_theme_font_override("font", f)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	_update_text(0)

func _process(delta: float) -> void:
	_elapsed += delta
	var sec := int(_elapsed)
	if sec != _shown_sec:
		_shown_sec = sec
		_update_text(sec)

func _update_text(total_sec: int) -> void:
	var h := total_sec / 3600
	var m := (total_sec % 3600) / 60
	var s := total_sec % 60
	if h > 0:
		_label.text = "%d:%02d:%02d" % [h, m, s]
	else:
		_label.text = "%02d:%02d" % [m, s]
