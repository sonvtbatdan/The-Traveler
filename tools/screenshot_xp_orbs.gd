extends SceneTree
## One-shot DEV TOOL (not shipped/imported into gameplay): boots scenes/arena.tscn standalone (no hub/main
## menu — --script bypasses the project's configured main scene, only autoloads run), waits for the xp orb
## manager (group "arena_xp_orb_mgr") to exist, spawns one orb of each tier (green/yellow/orange/red/purple)
## in a row near the player so the real artwork + animated glow/sparkle border (arena_xp_orb_manager.gd) can
## be visually verified, lets the shimmer animate for a bit, then captures the real rendered window frame.
##
## Run non-headless (needs a real render):
##   godot --path . --script tools/screenshot_xp_orbs.gd
## Output: user://xp_orb_shot.png

const SETTLE_FRAMES := 20    # let arena _ready()/deferred setup finish before spawning orbs
const ANIM_FRAMES := 60      # let the glow shimmer/sparkle animate before the shot

# Values picked to land solidly inside each tier (see arena_xp_orb_manager.gd's TIER_*_MAX thresholds).
const TIER_VALUES := [10.0, 40.0, 80.0, 150.0, 400.0]   # green, yellow, orange, red, purple

var _scene: Node
var _f := 0
var _spawned := false
var _mgr: Node = null

func _initialize() -> void:
	var packed := load("res://scenes/arena.tscn") as PackedScene
	_scene = packed.instantiate()
	get_root().add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	if not _spawned:
		if _f < SETTLE_FRAMES:
			return
		_mgr = get_root().get_tree().get_first_node_in_group("arena_xp_orb_mgr")
		var player := get_root().get_tree().get_first_node_in_group("player")
		if _mgr == null or player == null:
			return   # not built yet — keep waiting
		var origin: Vector2 = (player as Node2D).global_position + Vector2(-200.0, -120.0)
		for i in TIER_VALUES.size():
			_mgr.call("spawn", origin + Vector2(float(i) * 90.0, 0.0), TIER_VALUES[i])
		_spawned = true
		_f = 0
		return
	if _f >= ANIM_FRAMES:
		_save("user://xp_orb_shot.png")
		quit(0)

func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(path)
	if err == OK:
		print("screenshot_xp_orbs: saved ", path, "  ->  ", ProjectSettings.globalize_path(path))
	else:
		push_warning("screenshot_xp_orbs: save failed (%d) for %s" % [err, path])
