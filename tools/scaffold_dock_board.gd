extends SceneTree
## One-off scaffold: writes the initial res://config/boards/dock.cfg for the new "Dock" board (see
## board_defs.gd entry "dock"). Places every sprite found in assets/hud/dock/ as a full-screen item
## (width = screen width, matching the "Return to Dock" main-menu requirement) except the small
## "launch"/"launch hover" button pair and the oddly-sized "pilot" plaque. The 10 individual room
## renders (bridge/engineer/instructor/mechanic/equipment/constructor/codex/trophy/beacon + their
## matching background/frame overlay) start hidden (visible=false) — only one will show at a time once
## room navigation is wired up later; background+frame+launch+pilot stay visible as the default overview.
## Run once via: "C:\Program Files\Godot\Godot.exe" --headless --script res://tools/scaffold_dock_board.gd
## Safe to re-run (fully regenerates dock.cfg from scratch) but NOT idempotent with hand edits — re-running
## after the board has been authored in-editor will wipe those changes.

const ASSET_DIR := "res://assets/hud/dock/"
const OUT_PATH  := "res://config/boards/dock.cfg"
const SCREEN_W  := 1440.0
const SCREEN_H  := 780.0

# Full-screen room renders: width pinned to SCREEN_W, height keeps native aspect, vertically centered.
const FULLSCREEN_FILES := [
	"background", "frame", "bridge", "engineer", "instructor", "mechanic",
	"equipment", "constructor", "codex", "trophy", "beacon",
]
# Room renders that start hidden (everything except background+frame, which form the visible overview).
const HIDDEN_FILES := [
	"bridge", "engineer", "instructor", "mechanic", "equipment", "constructor", "codex", "trophy", "beacon",
]

var _next_id := 1

func _tex_size(file: String) -> Vector2:
	var tex := load(ASSET_DIR + file + ".png") as Texture2D
	return Vector2(tex.get_width(), tex.get_height())

func _fullscreen_item(file: String) -> Dictionary:
	var native := _tex_size(file)
	var h := SCREEN_W * native.y / native.x
	var ch := {
		"id": _next_id, "type": "item", "file": file,
		"pos": Vector2(0.0, (SCREEN_H - h) * 0.5), "size": Vector2(SCREEN_W, h), "blend": 0,
	}
	if file in HIDDEN_FILES:
		ch["visible"] = false
	_next_id += 1
	return ch

func _button_item(file: String, pos: Vector2, size: Vector2) -> Dictionary:
	var ch := {"id": _next_id, "type": "item", "file": file, "pos": pos, "size": size, "blend": 0}
	_next_id += 1
	return ch

func _initialize() -> void:
	var launch_native := _tex_size("launch")
	var launch_size := Vector2(360.0, 360.0 * launch_native.y / launch_native.x)
	var launch_pos := Vector2((SCREEN_W - launch_size.x) * 0.5, SCREEN_H - launch_size.y - 40.0)

	var pilot_native := _tex_size("pilot")
	var pilot_size := Vector2(280.0, 280.0 * pilot_native.y / pilot_native.x)
	var pilot_pos := Vector2(30.0, 30.0)

	var groups: Array = [
		{"name": "Launch", "collapsed": false, "locked": false, "children": [
			_button_item("launch", launch_pos, launch_size),
			_button_item("launch hover", launch_pos, launch_size),
		]},
		{"name": "Pilot", "collapsed": false, "locked": false, "children": [
			_button_item("pilot", pilot_pos, pilot_size),
		]},
		{"name": "Bridge",      "collapsed": false, "locked": false, "children": [_fullscreen_item("bridge")]},
		{"name": "Engineer",    "collapsed": false, "locked": false, "children": [_fullscreen_item("engineer")]},
		{"name": "Instructor",  "collapsed": false, "locked": false, "children": [_fullscreen_item("instructor")]},
		{"name": "Mechanic",    "collapsed": false, "locked": false, "children": [_fullscreen_item("mechanic")]},
		{"name": "Equipment",   "collapsed": false, "locked": false, "children": [_fullscreen_item("equipment")]},
		{"name": "Constructor", "collapsed": false, "locked": false, "children": [_fullscreen_item("constructor")]},
		{"name": "Codex",       "collapsed": false, "locked": false, "children": [_fullscreen_item("codex")]},
		{"name": "Trophy",      "collapsed": false, "locked": false, "children": [_fullscreen_item("trophy")]},
		{"name": "Beacon",      "collapsed": false, "locked": false, "children": [_fullscreen_item("beacon")]},
		{"name": "Frame",       "collapsed": false, "locked": false, "children": [_fullscreen_item("frame")]},
		{"name": "Background",  "collapsed": false, "locked": false, "children": [_fullscreen_item("background")]},
	]
	# z = Z_TOP(240) descending by 1 per child, in document order — matches hud_edit_mode.gd's _reassign_z().
	var z := 240
	for g: Dictionary in groups:
		for ch: Dictionary in (g["children"] as Array):
			ch["z"] = z
			z -= 1

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "next_id", _next_id)
	cfg.set_value("meta", "board", "dock")
	cfg.set_value("hud", "groups", groups)
	var err := cfg.save(OUT_PATH)
	if err == OK:
		print("[scaffold_dock_board] wrote %s (%d items, next_id=%d)" % [OUT_PATH, _next_id - 1, _next_id])
	else:
		print("[scaffold_dock_board] FAILED to save %s: error %d" % [OUT_PATH, err])
	quit(0 if err == OK else 1)
