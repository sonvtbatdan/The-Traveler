extends SceneTree
## One-shot DEV TOOL (not shipped/imported into gameplay): boots scenes/rubicon.tscn standalone (no hub,
## no main menu — --script bypasses the project's configured main scene entirely, only autoloads run),
## lets it settle, nudges the player right for a bit to prove ground/grass/tree scroll + camera-follow, and
## captures the real rendered window frame via Godot's own viewport texture — NOT an OS-level screenshot,
## so it can never grab an unrelated window. Saves 2 PNGs then quits.
##
## Run non-headless (needs a real render, like the bake tools):
##   godot --path . --script tools/screenshot_rubicon.gd
## Output: user://rubicon_shot_1_initial.png, user://rubicon_shot_2_moved.png

const SETTLE_FRAMES := 90     # let ground/grass/tree scatter populate before the first shot
const MOVE_FRAMES := 90       # hold "move right" this many frames before the second shot

var _scene: Node
var _f := 0
var _phase := 0   # 0=settling, 1=shot1 taken/moving, 2=shot2 taken → quit

func _initialize() -> void:
	var packed := load("res://scenes/rubicon.tscn") as PackedScene
	_scene = packed.instantiate()
	get_root().add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	if _phase == 0 and _f >= SETTLE_FRAMES:
		_save("user://rubicon_shot_1_initial.png")
		Input.action_press("move_right")
		_phase = 1
		_f = 0
		return
	if _phase == 1 and _f >= MOVE_FRAMES:
		Input.action_release("move_right")
		_save("user://rubicon_shot_2_moved.png")
		_phase = 2
		_f = 0
		return
	if _phase == 2 and _f >= 3:
		quit(0)

func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(path)
	if err == OK:
		print("screenshot_rubicon: saved ", path, "  ->  ", ProjectSettings.globalize_path(path))
	else:
		push_warning("screenshot_rubicon: save failed (%d) for %s" % [err, path])
