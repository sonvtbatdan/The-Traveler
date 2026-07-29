extends SceneTree
## One-shot DEV TOOL: boots the REAL scenes/arena.tscn (full ship/weapons/HUD/dev-mode/enemy-waves) under a
## given MetaManager.selected_map_id, so "does map X actually integrate cleanly" can be checked without
## going through Hub → Launch by hand. Pass the map id as the script's cmdline arg (after `--`), e.g.:
##   godot --path . --script tools/screenshot_arena_map.gd -- rubicon
## Defaults to "rubicon" if no arg given. Output: user://arena_map_<id>.png

const SETTLE_FRAMES := 120   # full arena has a LOT more to spin up than the isolated terrain preview

var _f := 0
var _map_id := "rubicon"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_map_id = args[0]
	# Autoload globals (MetaManager, etc.) aren't resolvable as static identifiers from a --script
	# SceneTree — look the node up dynamically instead.
	var meta := get_root().get_node_or_null("MetaManager")
	if meta != null:
		meta.set("selected_map_id", _map_id)
	else:
		push_warning("screenshot_arena_map: MetaManager autoload not found — map_id won't be set")
	var packed := load("res://scenes/arena.tscn") as PackedScene
	get_root().add_child(packed.instantiate())
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	if _f == SETTLE_FRAMES:
		var path := "user://arena_map_%s.png" % _map_id
		var img := get_root().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var err := img.save_png(path)
		if err == OK:
			print("screenshot_arena_map: saved ", path, "  ->  ", ProjectSettings.globalize_path(path))
		else:
			push_warning("screenshot_arena_map: save failed (%d)" % err)
	if _f >= SETTLE_FRAMES + 3:
		quit(0)
